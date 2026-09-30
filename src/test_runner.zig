const std = @import("std");
const suite = @import("suite.zig");
const reporter_mod = @import("reporter.zig");
const pipeline = @import("pipeline.zig");
const parallel = @import("parallel.zig");
const compat = @import("compat.zig");
const random_order = @import("random_order.zig");

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
    /// Additional attempts after a failed execution.
    retries: usize = 0,
    /// Number of times every selected test is required to pass.
    repeat: usize = 1,
    /// Treat tests that pass after a retry as an unsuccessful run.
    fail_on_flaky: bool = false,
    /// Shuffle suites and tests. A generated seed is printed for replay.
    shuffle: bool = false,
    /// Reproduce a shuffled run. Supplying a seed implicitly enables shuffle.
    seed: ?u64 = null,
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
        const random_seed = random_order.resolveSeed(self.options.shuffle, self.options.seed);
        current_reporter.random_seed = random_seed;
        self.results.random_seed = random_seed;
        const events = pipeline.EventStream{ .rep = current_reporter };

        var plan = try pipeline.TestPlan.fromRegistry(self.allocator, self.registry);
        defer plan.deinit();
        const total_tests = plan.items.items.len;
        if (total_tests == 0) {
            return RunnerError.NoTestsFound;
        }

        // Run tests in parallel or sequential based on options
        if (self.options.parallel and self.options.retries == 0 and self.options.repeat == 1) {
            const parallel_opts = parallel.ParallelOptions{
                .enabled = true,
                .n_jobs = self.options.n_jobs,
                .filter = self.options.filter,
                .timeout_ms = self.options.timeout_ms,
                .random_seed = random_seed,
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
            return all_passed and self.results.failed == 0 and
                (!self.options.fail_on_flaky or self.results.flaky == 0);
        }

        // Sequential execution (original behavior)
        var shuffler: random_order.Shuffler = undefined;
        const shuffler_ptr: ?*random_order.Shuffler = if (random_seed) |seed| blk: {
            shuffler = .init(seed);
            break :blk &shuffler;
        } else null;
        var root_suites: std.ArrayList(*suite.TestSuite) = .empty;
        defer root_suites.deinit(self.allocator);
        try root_suites.appendSlice(self.allocator, self.registry.root_suites.items);
        if (shuffler_ptr) |randomizer| randomizer.shuffle(*suite.TestSuite, root_suites.items);

        try events.emit(.{ .run_started = total_tests });
        for (root_suites.items) |test_suite| {
            try self.runSuite(test_suite, events, shuffler_ptr);
            if (self.policy().shouldStop(&self.results)) {
                break;
            }
        }

        // Notify reporter of run end
        try events.emit(.{ .run_finished = &self.results });

        // Flush output
        try reporters.flush();

        return self.results.failed == 0 and
            (!self.options.fail_on_flaky or self.results.flaky == 0);
    }

    fn addSuiteResults(self: *Self, test_suite: *suite.TestSuite) !void {
        for (test_suite.tests.items) |*test_case| try self.results.addTest(test_case);
        for (test_suite.suites.items) |nested| try self.addSuiteResults(nested);
    }

    /// Run a single test suite
    fn runSuite(
        self: *Self,
        test_suite: *suite.TestSuite,
        events: pipeline.EventStream,
        shuffler: ?*random_order.Shuffler,
    ) !void {
        // Skip if marked as skip or if has_only and this isn't marked as only
        if (test_suite.shouldSkip()) {
            try self.skipAllTests(test_suite, events, shuffler);
            return;
        }

        if (self.registry.has_only and !test_suite.hasOnly()) {
            try self.skipAllTests(test_suite, events, shuffler);
            return;
        }

        // Notify reporter
        try events.emit(.{ .suite_started = test_suite.name });

        // Run beforeAll hooks
        test_suite.runBeforeAllHooks(self.allocator) catch |err| {
            std.debug.print("beforeAll hook failed: {any}\n", .{err});
            try self.skipAllTests(test_suite, events, shuffler);
            try events.emit(.{ .suite_finished = test_suite.name });
            return;
        };

        // Run tests in this suite
        var tests: std.ArrayList(*suite.TestCase) = .empty;
        defer tests.deinit(self.allocator);
        for (test_suite.tests.items) |*test_case| try tests.append(self.allocator, test_case);
        if (shuffler) |randomizer| randomizer.shuffle(*suite.TestCase, tests.items);
        for (tests.items) |test_case| {
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
        var nested_suites: std.ArrayList(*suite.TestSuite) = .empty;
        defer nested_suites.deinit(self.allocator);
        try nested_suites.appendSlice(self.allocator, test_suite.suites.items);
        if (shuffler) |randomizer| randomizer.shuffle(*suite.TestSuite, nested_suites.items);
        for (nested_suites.items) |nested_suite| {
            try self.runSuite(nested_suite, events, shuffler);
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

        for (test_case.attempts.items) |attempt| {
            if (attempt.error_message) |message| self.allocator.free(message);
        }
        test_case.attempts.clearRetainingCapacity();
        test_case.execution_time_ns = 0;
        test_case.error_message = null;

        const retries = test_case.retry_count orelse self.options.retries;
        const repeat_count = @max(self.options.repeat, 1);
        var attempt_number: usize = 0;
        var had_failure = false;
        var final_failure = false;

        repetitions: for (1..repeat_count + 1) |repetition| {
            for (1..retries + 2) |attempt_in_repetition| {
                attempt_number += 1;
                const passed = try self.runSingleAttempt(test_case, test_suite, repetition, attempt_number);
                if (passed) break;

                had_failure = true;
                if (attempt_in_repetition == retries + 1) {
                    final_failure = true;
                    break :repetitions;
                }
            }
        }

        if (!final_failure) {
            test_case.status = if (had_failure) .flaky else .passed;
            test_case.error_message = null;
        }

        try self.results.addTest(test_case);
        try events.emit(.{ .test_finished = test_case });
    }

    fn runSingleAttempt(
        self: *Self,
        test_case: *suite.TestCase,
        test_suite: *suite.TestSuite,
        repetition: usize,
        attempt_number: usize,
    ) !bool {
        test_case.status = .running;
        test_case.error_message = null;
        const start_time = compat.nanoTimestamp();

        var before_hooks = try test_suite.getAllBeforeEachHooks(self.allocator);
        defer before_hooks.deinit(self.allocator);

        var before_failed = false;
        for (before_hooks.items) |hook| {
            hook(self.allocator) catch |err| {
                test_case.status = .failed;
                test_case.error_message = try std.fmt.allocPrint(
                    self.allocator,
                    "beforeEach hook failed: {any}",
                    .{err},
                );
                before_failed = true;
                break;
            };
        }

        if (!before_failed) {
            test_case.test_fn(self.allocator) catch |err| {
                test_case.status = .failed;
                test_case.error_message = try std.fmt.allocPrint(self.allocator, "{any}", .{err});
            };
            if (test_case.status == .running) test_case.status = .passed;
        }

        var after_hooks = try test_suite.getAllAfterEachHooks(self.allocator);
        defer after_hooks.deinit(self.allocator);
        for (after_hooks.items) |hook| {
            hook(self.allocator) catch |err| {
                std.debug.print("afterEach hook failed: {any}\n", .{err});
            };
        }

        const duration_ns: u64 = @intCast(compat.nanoTimestamp() - start_time);
        if (test_case.status == .passed and self.policy().timedOut(duration_ns)) {
            test_case.status = .failed;
            test_case.error_message = try std.fmt.allocPrint(
                self.allocator,
                "Test exceeded timeout of {d}ms",
                .{self.options.timeout_ms.?},
            );
        }
        test_case.execution_time_ns += duration_ns;
        try test_case.attempts.append(self.allocator, .{
            .number = attempt_number,
            .repetition = repetition,
            .status = test_case.status,
            .duration_ns = duration_ns,
            .error_message = test_case.error_message,
        });
        return test_case.status == .passed;
    }

    /// Skip all tests in a suite
    fn skipAllTests(
        self: *Self,
        test_suite: *suite.TestSuite,
        events: pipeline.EventStream,
        shuffler: ?*random_order.Shuffler,
    ) !void {
        var tests: std.ArrayList(*suite.TestCase) = .empty;
        defer tests.deinit(self.allocator);
        for (test_suite.tests.items) |*test_case| try tests.append(self.allocator, test_case);
        if (shuffler) |randomizer| randomizer.shuffle(*suite.TestCase, tests.items);
        for (tests.items) |test_case| {
            test_case.status = .skipped;
            try self.results.addTest(test_case);
            try events.emit(.{ .test_finished = test_case });
        }

        var nested_suites: std.ArrayList(*suite.TestSuite) = .empty;
        defer nested_suites.deinit(self.allocator);
        try nested_suites.appendSlice(self.allocator, test_suite.suites.items);
        if (shuffler) |randomizer| randomizer.shuffle(*suite.TestSuite, nested_suites.items);
        for (nested_suites.items) |nested_suite| {
            try self.skipAllTests(nested_suite, events, shuffler);
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
    try std.testing.expectEqual(@as(usize, 0), options.retries);
    try std.testing.expectEqual(@as(usize, 1), options.repeat);
    try std.testing.expect(!options.fail_on_flaky);
    try std.testing.expect(!options.shuffle);
    try std.testing.expect(options.seed == null);
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

var flaky_fixture_runs: usize = 0;
var failing_fixture_runs: usize = 0;
var skipped_by_bail_runs: usize = 0;
var repeated_fixture_runs: usize = 0;
var timeout_fixture_runs: usize = 0;
var randomized_log: [6]u8 = undefined;
var randomized_log_len: usize = 0;

fn recordRandomized(id: u8) void {
    randomized_log[randomized_log_len] = id;
    randomized_log_len += 1;
}

fn randomizedOne(_: std.mem.Allocator) !void {
    recordRandomized(1);
}

fn randomizedTwo(_: std.mem.Allocator) !void {
    recordRandomized(2);
}

fn randomizedThree(_: std.mem.Allocator) !void {
    recordRandomized(3);
}

fn randomizedFour(_: std.mem.Allocator) !void {
    recordRandomized(4);
}

fn randomizedFive(_: std.mem.Allocator) !void {
    recordRandomized(5);
}

fn randomizedSix(_: std.mem.Allocator) !void {
    recordRandomized(6);
}

fn flakyFixture(_: std.mem.Allocator) !void {
    flaky_fixture_runs += 1;
    if (flaky_fixture_runs == 1) return error.TransientFailure;
}

fn failingFixture(_: std.mem.Allocator) !void {
    failing_fixture_runs += 1;
    return error.DeterministicFailure;
}

fn skippedByBailFixture(_: std.mem.Allocator) !void {
    skipped_by_bail_runs += 1;
}

test "sequential order is reproducible with a fixed seed" {
    const allocator = std.testing.allocator;
    var registry = suite.TestRegistry.init(allocator);
    defer registry.deinit();
    const test_suite = try suite.TestSuite.init(allocator, "randomized");
    try test_suite.addTest(suite.TestCase.init("one", randomizedOne));
    try test_suite.addTest(suite.TestCase.init("two", randomizedTwo));
    try test_suite.addTest(suite.TestCase.init("three", randomizedThree));
    try test_suite.addTest(suite.TestCase.init("four", randomizedFour));
    try test_suite.addTest(suite.TestCase.init("five", randomizedFive));
    try test_suite.addTest(suite.TestCase.init("six", randomizedSix));
    try registry.registerSuite(test_suite);

    var first_output: [4096]u8 = undefined;
    var first_writer: std.Io.Writer = .fixed(&first_output);
    randomized_log_len = 0;
    var first_runner = TestRunner.init(allocator, &registry, .{
        .seed = 112358,
        .use_colors = false,
        .reporter_writer = &first_writer,
    });
    defer first_runner.deinit();
    try std.testing.expect(try first_runner.run());
    const first_order = randomized_log;

    var second_output: [4096]u8 = undefined;
    var second_writer: std.Io.Writer = .fixed(&second_output);
    randomized_log_len = 0;
    var second_runner = TestRunner.init(allocator, &registry, .{
        .seed = 112358,
        .use_colors = false,
        .reporter_writer = &second_writer,
    });
    defer second_runner.deinit();
    try std.testing.expect(try second_runner.run());

    try std.testing.expectEqual(@as(usize, randomized_log.len), randomized_log_len);
    try std.testing.expectEqualSlices(u8, &first_order, &randomized_log);
    try std.testing.expectEqual(@as(?u64, 112358), first_runner.results.random_seed);
    try std.testing.expectEqual(@as(?u64, 112358), second_runner.results.random_seed);
}

fn repeatedFixture(_: std.mem.Allocator) !void {
    repeated_fixture_runs += 1;
}

fn timeoutFixture(_: std.mem.Allocator) !void {
    timeout_fixture_runs += 1;
    compat.sleep(std.time.ns_per_ms);
}

test "retries record deterministic flaky attempt history" {
    flaky_fixture_runs = 0;
    const allocator = std.testing.allocator;
    var registry = suite.TestRegistry.init(allocator);
    defer registry.deinit();
    const test_suite = try suite.TestSuite.init(allocator, "retry suite");
    try test_suite.addTest(suite.TestCase.init("flaky fixture", flakyFixture).withRetries(1));
    try registry.registerSuite(test_suite);

    var output: [4096]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&output);
    var runner = TestRunner.init(allocator, &registry, .{
        .reporter_writer = &writer,
        .use_colors = false,
    });
    defer runner.deinit();

    try std.testing.expect(try runner.run());
    const test_case = &test_suite.tests.items[0];
    try std.testing.expectEqual(suite.TestStatus.flaky, test_case.status);
    try std.testing.expectEqual(@as(usize, 2), test_case.attempts.items.len);
    try std.testing.expectEqual(suite.TestStatus.failed, test_case.attempts.items[0].status);
    try std.testing.expectEqual(suite.TestStatus.passed, test_case.attempts.items[1].status);
    try std.testing.expectEqual(@as(usize, 1), runner.results.flaky);

    var strict_runner = TestRunner.init(allocator, &registry, .{
        .retries = 1,
        .fail_on_flaky = true,
        .reporter_writer = &writer,
        .use_colors = false,
    });
    defer strict_runner.deinit();
    flaky_fixture_runs = 0;
    try std.testing.expect(!try strict_runner.run());
}

test "repeat mode runs every required passing repetition" {
    repeated_fixture_runs = 0;
    const allocator = std.testing.allocator;
    var registry = suite.TestRegistry.init(allocator);
    defer registry.deinit();
    const test_suite = try suite.TestSuite.init(allocator, "repeat suite");
    try test_suite.addTest(suite.TestCase.init("repeated fixture", repeatedFixture));
    try registry.registerSuite(test_suite);

    var output: [4096]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&output);
    var runner = TestRunner.init(allocator, &registry, .{
        .repeat = 3,
        .reporter_writer = &writer,
        .use_colors = false,
    });
    defer runner.deinit();

    try std.testing.expect(try runner.run());
    try std.testing.expectEqual(@as(usize, 3), repeated_fixture_runs);
    try std.testing.expectEqual(@as(usize, 3), test_suite.tests.items[0].attempts.items.len);
}

test "bail waits until retries are exhausted" {
    failing_fixture_runs = 0;
    skipped_by_bail_runs = 0;
    const allocator = std.testing.allocator;
    var registry = suite.TestRegistry.init(allocator);
    defer registry.deinit();
    const test_suite = try suite.TestSuite.init(allocator, "bail suite");
    try test_suite.addTest(suite.TestCase.init("always fails", failingFixture));
    try test_suite.addTest(suite.TestCase.init("must be skipped", skippedByBailFixture));
    try registry.registerSuite(test_suite);

    var output: [4096]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&output);
    var runner = TestRunner.init(allocator, &registry, .{
        .bail = true,
        .retries = 2,
        .reporter_writer = &writer,
        .use_colors = false,
    });
    defer runner.deinit();

    try std.testing.expect(!try runner.run());
    try std.testing.expectEqual(@as(usize, 3), failing_fixture_runs);
    try std.testing.expectEqual(@as(usize, 0), skipped_by_bail_runs);
    try std.testing.expectEqual(@as(usize, 3), test_suite.tests.items[0].attempts.items.len);
}

test "timeouts are evaluated for every retry attempt" {
    timeout_fixture_runs = 0;
    const allocator = std.testing.allocator;
    var registry = suite.TestRegistry.init(allocator);
    defer registry.deinit();
    const test_suite = try suite.TestSuite.init(allocator, "timeout suite");
    try test_suite.addTest(suite.TestCase.init("times out", timeoutFixture));
    try registry.registerSuite(test_suite);

    var output: [4096]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&output);
    var runner = TestRunner.init(allocator, &registry, .{
        .timeout_ms = 0,
        .retries = 1,
        .reporter_writer = &writer,
        .use_colors = false,
    });
    defer runner.deinit();

    try std.testing.expect(!try runner.run());
    try std.testing.expectEqual(@as(usize, 2), timeout_fixture_runs);
    try std.testing.expectEqual(@as(usize, 2), test_suite.tests.items[0].attempts.items.len);
    try std.testing.expectEqual(suite.TestStatus.failed, test_suite.tests.items[0].status);
}
