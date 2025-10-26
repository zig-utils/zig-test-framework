const std = @import("std");
const suite = @import("suite.zig");
const reporter_mod = @import("reporter.zig");
const parallel = @import("parallel.zig");

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
};

pub const ReporterType = enum {
    spec,
    dot,
    json,
};

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
        const stdout_file = std.fs.File.stdout();
        var stdout_buffer: [4096]u8 = undefined;
        var stdout_writer = stdout_file.writer(&stdout_buffer);

        // Create reporter
        var spec_reporter = reporter_mod.SpecReporter.init(self.allocator, stdout_writer.interface);
        var dot_reporter = reporter_mod.DotReporter.init(self.allocator, stdout_writer.interface);
        var json_reporter = reporter_mod.JsonReporter.init(self.allocator, stdout_writer.interface);
        defer json_reporter.deinit();

        var current_reporter: *reporter_mod.Reporter = switch (self.options.reporter_type) {
            .spec => &spec_reporter.reporter,
            .dot => &dot_reporter.reporter,
            .json => &json_reporter.reporter,
        };

        current_reporter.use_colors = self.options.use_colors;

        const total_tests = self.registry.countAllTests();
        if (total_tests == 0) {
            return RunnerError.NoTestsFound;
        }

        // Notify reporter of run start
        try current_reporter.onRunStart(total_tests);

        // Run tests in parallel or sequential based on options
        if (self.options.parallel) {
            const parallel_opts = parallel.ParallelOptions{
                .enabled = true,
                .n_jobs = self.options.n_jobs,
            };

            _ = parallel.runTestsParallel(
                self.allocator,
                self.registry,
                current_reporter,
                parallel_opts,
            ) catch |err| {
                std.debug.print("Parallel execution failed: {any}, falling back to sequential\n", .{err});
                // Fall back to sequential execution
                for (self.registry.root_suites.items) |test_suite| {
                    try self.runSuite(test_suite, current_reporter);
                    if (self.options.bail and self.results.failed > 0) {
                        break;
                    }
                }
                return false;
            };

            // Update results from parallel execution
            self.results.total = 0;
            self.results.passed = 0;
            self.results.failed = 0;
            self.results.skipped = 0;

            for (self.registry.root_suites.items) |test_suite| {
                for (test_suite.tests.items) |test_case| {
                    self.results.total += 1;
                    switch (test_case.status) {
                        .passed => self.results.passed += 1,
                        .failed => self.results.failed += 1,
                        .skipped => self.results.skipped += 1,
                        else => {},
                    }
                }
            }
        } else {
            // Sequential execution (original behavior)
            for (self.registry.root_suites.items) |test_suite| {
                try self.runSuite(test_suite, current_reporter);
                if (self.options.bail and self.results.failed > 0) {
                    break;
                }
            }
        }

        // Notify reporter of run end
        try current_reporter.onRunEnd(&self.results);

        // Flush output
        try stdout_writer.interface.flush();

        return self.results.failed == 0;
    }

    /// Run a single test suite
    fn runSuite(self: *Self, test_suite: *suite.TestSuite, rep: *reporter_mod.Reporter) !void {
        // Skip if marked as skip or if has_only and this isn't marked as only
        if (test_suite.shouldSkip()) {
            try self.skipAllTests(test_suite);
            return;
        }

        if (self.registry.has_only and !test_suite.hasOnly()) {
            try self.skipAllTests(test_suite);
            return;
        }

        // Notify reporter
        try rep.onSuiteStart(test_suite.name);

        // Run beforeAll hooks
        test_suite.runBeforeAllHooks(self.allocator) catch |err| {
            std.debug.print("beforeAll hook failed: {any}\n", .{err});
            try self.skipAllTests(test_suite);
            try rep.onSuiteEnd(test_suite.name);
            return;
        };

        // Run tests in this suite
        for (test_suite.tests.items) |*test_case| {
            if (test_case.skip or (self.registry.has_only and !test_case.only)) {
                test_case.status = .skipped;
                try rep.onTestEnd(test_case);
                try self.results.addTest(test_case);
                continue;
            }

            // Check filter
            if (self.options.filter) |filter| {
                if (std.mem.indexOf(u8, test_case.name, filter) == null) {
                    test_case.status = .skipped;
                    try rep.onTestEnd(test_case);
                    try self.results.addTest(test_case);
                    continue;
                }
            }

            try self.runTest(test_case, test_suite, rep);

            if (self.options.bail and test_case.status == .failed) {
                break;
            }
        }

        // Run nested suites
        for (test_suite.suites.items) |nested_suite| {
            try self.runSuite(nested_suite, rep);
            if (self.options.bail and self.results.failed > 0) {
                break;
            }
        }

        // Run afterAll hooks
        test_suite.runAfterAllHooks(self.allocator) catch |err| {
            std.debug.print("afterAll hook failed: {any}\n", .{err});
        };

        try rep.onSuiteEnd(test_suite.name);
    }

    /// Run a single test
    fn runTest(self: *Self, test_case: *suite.TestCase, test_suite: *suite.TestSuite, rep: *reporter_mod.Reporter) !void {
        try rep.onTestStart(test_case.name);

        test_case.status = .running;
        const start_time = std.time.nanoTimestamp();

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

        const end_time = std.time.nanoTimestamp();
        test_case.execution_time_ns = @intCast(end_time - start_time);

        try self.results.addTest(test_case);
        try rep.onTestEnd(test_case);
    }

    /// Skip all tests in a suite
    fn skipAllTests(self: *Self, test_suite: *suite.TestSuite) !void {
        for (test_suite.tests.items) |*test_case| {
            test_case.status = .skipped;
            try self.results.addTest(test_case);
        }

        for (test_suite.suites.items) |nested_suite| {
            try self.skipAllTests(nested_suite);
        }
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
