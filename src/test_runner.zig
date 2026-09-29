const std = @import("std");
const suite = @import("suite.zig");
const reporter_mod = @import("reporter.zig");
const pipeline = @import("pipeline.zig");
const parallel = @import("parallel.zig");
const compat = @import("compat.zig");

pub const RunnerError = error{
    NoTestsFound,
    AllTestsFailed,
};

pub const RunnerOptions = struct {
    bail: bool = false, // Stop on first failure
    filter: ?[]const u8 = null, // Test name filter
    reporter_type: ReporterType = .spec,
    use_colors: bool = true,
    parallel: bool = false, // Enable parallel execution
    n_jobs: ?usize = null, // Number of parallel jobs
    junit_output: []const u8 = "test-results.xml",
    timeout_ms: ?u64 = null,
    /// Optional output supplied by a CLI host. Embedded/test callers default
    /// to stderr so they do not interfere with Zig's stdout test protocol.
    reporter_writer: ?*std.Io.Writer = null,
};

pub const ReporterType = reporter_mod.ReporterType;

pub const TestRunner = struct {
    allocator: std.mem.Allocator,
    registry: *suite.TestRegistry,
    options: RunnerOptions,
    results: reporter_mod.TestResults,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, registry: *suite.TestRegistry, options: RunnerOptions) Self {
        return Self{
            .allocator = allocator,
            .registry = registry,
            .options = options,
            .results = reporter_mod.TestResults.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.results.deinit();
    }

    /// Run all registered tests
    pub fn run(self: *Self) !bool {
        const stderr_file = std.Io.File.stderr();
        var stderr_buffer: [4096]u8 = undefined;
        var threaded_io: std.Io.Threaded = .init(std.mem.Allocator.failing, .{ .environ = .empty });
        defer threaded_io.deinit();
        var stderr_writer = stderr_file.writer(threaded_io.io(), &stderr_buffer);
        const reporter_writer = self.options.reporter_writer orelse &stderr_writer.interface;

        var reporters = reporter_mod.ReporterSet.initRef(
            self.allocator,
            reporter_writer,
            self.options.reporter_type,
            self.options.junit_output,
            self.options.use_colors,
        );
        defer reporters.deinit();
        const current_reporter = reporters.selected();
        const events = pipeline.EventStream{ .rep = current_reporter };

        var plan = try pipeline.TestPlan.fromRegistry(self.allocator, self.registry);
        defer plan.deinit();
        const total_tests = plan.items.items.len;
        if (total_tests == 0) {
            return RunnerError.NoTestsFound;
        }

        // Run tests in parallel or sequential based on options
        if (self.options.parallel) {
            const parallel_opts = parallel.ParallelOptions{
                .enabled = true,
                .n_jobs = self.options.n_jobs,
                .filter = self.options.filter,
                .timeout_ms = self.options.timeout_ms,
            };

            const all_passed = try parallel.runTestsParallel(
                self.allocator,
                self.registry,
                current_reporter,
                parallel_opts,
            );

            for (self.registry.root_suites.items) |test_suite| {
                try self.addSuiteResults(test_suite);
            }

            try reporters.flush();
            return all_passed and self.results.failed == 0;
        }

        // Sequential execution (original behavior)
        try events.emit(.{ .run_started = total_tests });
        for (self.registry.root_suites.items) |test_suite| {
            try self.runSuite(test_suite, events);
            if (self.policy().shouldStop(&self.results)) {
                break;
            }
        }

        // Notify reporter of run end
        try events.emit(.{ .run_finished = &self.results });

        // Flush output
        try reporters.flush();

        return self.results.failed == 0;
    }

    fn addSuiteResults(self: *Self, test_suite: *suite.TestSuite) !void {
        for (test_suite.tests.items) |*test_case| try self.results.addTest(test_case);
        for (test_suite.suites.items) |nested| try self.addSuiteResults(nested);
    }

    /// Run a single test suite
    fn runSuite(self: *Self, test_suite: *suite.TestSuite, events: pipeline.EventStream) !void {
        // Skip if marked as skip or if has_only and this isn't marked as only
        if (test_suite.shouldSkip()) {
            try self.skipAllTests(test_suite, events);
            return;
        }

        if (self.registry.has_only and !test_suite.hasOnly()) {
            try self.skipAllTests(test_suite, events);
            return;
        }

        // Notify reporter
        try events.emit(.{ .suite_started = test_suite.name });

        // Run beforeAll hooks
        test_suite.runBeforeAllHooks(self.allocator) catch |err| {
            std.debug.print("beforeAll hook failed: {any}\n", .{err});
            try self.skipAllTests(test_suite, events);
            try events.emit(.{ .suite_finished = test_suite.name });
            return;
        };

        // Run tests in this suite
        for (test_suite.tests.items) |*test_case| {
            if (test_case.skip or (self.registry.has_only and !test_case.only)) {
                test_case.status = .skipped;
                try events.emit(.{ .test_finished = test_case });
                try self.results.addTest(test_case);
                continue;
            }

            // Check filter
            if (!self.policy().matches(test_case.name)) {
                test_case.status = .skipped;
                try events.emit(.{ .test_finished = test_case });
                try self.results.addTest(test_case);
                continue;
            }

            try self.runTest(test_case, test_suite, events);

            if (self.policy().shouldStop(&self.results)) {
                break;
            }
        }

        // Run nested suites
        for (test_suite.suites.items) |nested_suite| {
            try self.runSuite(nested_suite, events);
            if (self.policy().shouldStop(&self.results)) {
                break;
            }
        }

        // Run afterAll hooks
        test_suite.runAfterAllHooks(self.allocator) catch |err| {
            std.debug.print("afterAll hook failed: {any}\n", .{err});
        };

        try events.emit(.{ .suite_finished = test_suite.name });
    }

    /// Run a single test
    fn runTest(self: *Self, test_case: *suite.TestCase, test_suite: *suite.TestSuite, events: pipeline.EventStream) !void {
        try events.emit(.{ .test_started = test_case.name });

        test_case.status = .running;
        const start_time = compat.nanoTimestamp();

        // Get all beforeEach hooks (including parent hooks)
        var before_hooks = try test_suite.getAllBeforeEachHooks(self.allocator);
        defer before_hooks.deinit(self.allocator);

        // Run beforeEach hooks
        var before_failed = false;
        for (before_hooks.items) |hook| {
            hook(self.allocator) catch |err| {
                test_case.status = .failed;
                const err_msg = try std.fmt.allocPrint(self.allocator, "beforeEach hook failed: {any}", .{err});
                test_case.error_message = err_msg;
                before_failed = true;
                break;
            };
        }

        // Run the actual test if beforeEach succeeded
        if (!before_failed) {
            test_case.test_fn(self.allocator) catch |err| {
                test_case.status = .failed;
                const err_msg = try std.fmt.allocPrint(self.allocator, "{any}", .{err});
                test_case.error_message = err_msg;
            };

            if (test_case.status == .running) {
                test_case.status = .passed;
            }
        }

        // Get all afterEach hooks (including parent hooks)
        var after_hooks = try test_suite.getAllAfterEachHooks(self.allocator);
        defer after_hooks.deinit(self.allocator);

        // Run afterEach hooks (always run, even if test failed)
        for (after_hooks.items) |hook| {
            hook(self.allocator) catch |err| {
                std.debug.print("afterEach hook failed: {any}\n", .{err});
            };
        }

        const end_time = compat.nanoTimestamp();
        test_case.execution_time_ns = @intCast(end_time - start_time);
        if (test_case.status == .passed and self.policy().timedOut(test_case.execution_time_ns)) {
            test_case.status = .failed;
            test_case.error_message = try std.fmt.allocPrint(
                self.allocator,
                "Test exceeded timeout of {d}ms",
                .{self.options.timeout_ms.?},
            );
        }

        try self.results.addTest(test_case);
        try events.emit(.{ .test_finished = test_case });
    }

    /// Skip all tests in a suite
    fn skipAllTests(self: *Self, test_suite: *suite.TestSuite, events: pipeline.EventStream) !void {
        for (test_suite.tests.items) |*test_case| {
            test_case.status = .skipped;
            try self.results.addTest(test_case);
            try events.emit(.{ .test_finished = test_case });
        }

        for (test_suite.suites.items) |nested_suite| {
            try self.skipAllTests(nested_suite, events);
        }
    }

    fn policy(self: *const Self) pipeline.ExecutionPolicy {
        return .{
            .bail = self.options.bail,
            .filter = self.options.filter,
            .timeout_ms = self.options.timeout_ms,
        };
    }
};

/// Helper function to run tests with default options
pub fn runTests(allocator: std.mem.Allocator, registry: *suite.TestRegistry) !bool {
    var runner = TestRunner.init(allocator, registry, .{});
    defer runner.deinit();
    return try runner.run();
}

/// Helper function to run tests with custom options
pub fn runTestsWithOptions(allocator: std.mem.Allocator, registry: *suite.TestRegistry, options: RunnerOptions) !bool {
    var runner = TestRunner.init(allocator, registry, options);
    defer runner.deinit();
    return try runner.run();
}

// Tests
test "ReporterType enum values" {
    const spec = ReporterType.spec;
    const dot = ReporterType.dot;
    const json = ReporterType.json;

    try std.testing.expect(spec == .spec);
    try std.testing.expect(dot == .dot);
    try std.testing.expect(json == .json);
}

test "RunnerOptions default values" {
    const options = RunnerOptions{};

    try std.testing.expectEqual(false, options.bail);
    try std.testing.expectEqual(@as(?[]const u8, null), options.filter);
    try std.testing.expectEqual(ReporterType.spec, options.reporter_type);
    try std.testing.expectEqual(true, options.use_colors);
    try std.testing.expectEqual(@as(?u64, null), options.timeout_ms);
}

test "RunnerOptions custom values" {
    const options = RunnerOptions{
        .bail = true,
        .filter = "test",
        .reporter_type = .json,
        .use_colors = false,
    };

    try std.testing.expectEqual(true, options.bail);
    try std.testing.expectEqualStrings("test", options.filter.?);
    try std.testing.expectEqual(ReporterType.json, options.reporter_type);
    try std.testing.expectEqual(false, options.use_colors);
}
