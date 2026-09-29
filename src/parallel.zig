const std = @import("std");
const suite = @import("suite.zig");
const reporter = @import("reporter.zig");
const pipeline = @import("pipeline.zig");
const compat = @import("compat.zig");

/// Options for bounded parallel test execution.
pub const ParallelOptions = struct {
    /// Exact maximum worker count. Null uses the logical CPU count, falling
    /// back to one worker when the platform cannot report it.
    n_jobs: ?usize = null,
    enabled: bool = false,
    filter: ?[]const u8 = null,
    timeout_ms: ?u64 = null,
};

pub const ParallelError = error{
    ParallelNotEnabled,
    InvalidJobCount,
};

pub fn resolveWorkerCount(n_jobs: ?usize) !usize {
    if (n_jobs) |jobs| {
        if (jobs == 0) return ParallelError.InvalidJobCount;
        return jobs;
    }
    return @max(std.Thread.getCpuCount() catch 1, 1);
}

const WorkerContext = struct {
    allocator: std.mem.Allocator,
    test_suite: *suite.TestSuite,
    tests: []const *suite.TestCase,
    next_index: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    error_mutex: compat.Mutex = .{},
    policy: pipeline.ExecutionPolicy,

    fn worker(self: *WorkerContext) void {
        while (true) {
            const index = self.next_index.fetchAdd(1, .monotonic);
            if (index >= self.tests.len) return;
            self.runTest(self.tests[index]);
        }
    }

    fn runTest(self: *WorkerContext, test_case: *suite.TestCase) void {
        test_case.status = .running;
        const start_time = compat.nanoTimestamp();

        var before_hooks = self.test_suite.getAllBeforeEachHooks(self.allocator) catch {
            self.fail(test_case, "could not collect beforeEach hooks", .{});
            self.finishTiming(test_case, start_time);
            return;
        };
        defer before_hooks.deinit(self.allocator);

        var before_failed = false;
        for (before_hooks.items) |hook| {
            hook(self.allocator) catch |err| {
                self.fail(test_case, "beforeEach hook failed: {any}", .{err});
                before_failed = true;
                break;
            };
        }

        if (!before_failed) {
            test_case.test_fn(self.allocator) catch |err| {
                self.fail(test_case, "{any}", .{err});
            };
            if (test_case.status == .running) test_case.status = .passed;
        }

        var after_hooks = self.test_suite.getAllAfterEachHooks(self.allocator) catch {
            self.fail(test_case, "could not collect afterEach hooks", .{});
            self.finishTiming(test_case, start_time);
            return;
        };
        defer after_hooks.deinit(self.allocator);
        for (after_hooks.items) |hook| {
            hook(self.allocator) catch |err| {
                self.fail(test_case, "afterEach hook failed: {any}", .{err});
                break;
            };
        }

        self.finishTiming(test_case, start_time);
    }

    fn fail(self: *WorkerContext, test_case: *suite.TestCase, comptime format: []const u8, args: anytype) void {
        test_case.status = .failed;
        self.error_mutex.lock();
        defer self.error_mutex.unlock();
        test_case.error_message = std.fmt.allocPrint(self.allocator, format, args) catch "Out of memory";
    }

    fn finishTiming(self: *WorkerContext, test_case: *suite.TestCase, start_time: i128) void {
        test_case.execution_time_ns = @intCast(compat.nanoTimestamp() - start_time);
        if (test_case.status == .passed and self.policy.timedOut(test_case.execution_time_ns)) {
            self.fail(
                test_case,
                "Test exceeded timeout of {d}ms",
                .{self.policy.timeout_ms.?},
            );
        }
    }
};

const RunContext = struct {
    allocator: std.mem.Allocator,
    registry: *suite.TestRegistry,
    rep: *reporter.Reporter,
    options: ParallelOptions,
    worker_limit: usize,

    fn runSuite(self: *RunContext, test_suite: *suite.TestSuite) !bool {
        try self.rep.onSuiteStart(test_suite.name);

        if (test_suite.shouldSkip()) {
            try self.reportSkippedSuite(test_suite);
            try self.rep.onSuiteEnd(test_suite.name);
            return true;
        }

        test_suite.runBeforeAllHooks(self.allocator) catch |err| {
            std.debug.print("beforeAll hook failed: {any}\n", .{err});
            try self.reportSkippedSuite(test_suite);
            try self.rep.onSuiteEnd(test_suite.name);
            return true;
        };

        var scheduled: std.ArrayList(*suite.TestCase) = .empty;
        defer scheduled.deinit(self.allocator);

        for (test_suite.tests.items) |*test_case| {
            if (!self.shouldRun(test_suite, test_case)) {
                test_case.status = .skipped;
                continue;
            }
            try self.rep.onTestStart(test_case.name);
            try scheduled.append(self.allocator, test_case);
        }

        try self.runBatch(test_suite, scheduled.items);

        var all_passed = true;
        for (test_suite.tests.items) |*test_case| {
            try self.rep.onTestEnd(test_case);
            if (test_case.status == .failed) all_passed = false;
        }

        for (test_suite.suites.items) |nested_suite| {
            if (!try self.runSuite(nested_suite)) all_passed = false;
        }

        test_suite.runAfterAllHooks(self.allocator) catch |err| {
            std.debug.print("afterAll hook failed: {any}\n", .{err});
            all_passed = false;
        };

        try self.rep.onSuiteEnd(test_suite.name);
        return all_passed;
    }

    fn shouldRun(self: *RunContext, test_suite: *suite.TestSuite, test_case: *suite.TestCase) bool {
        if (test_case.skip) return false;
        if (self.registry.has_only and !test_case.only and !test_suite.hasOnly()) return false;
        if (self.options.filter) |filter| {
            if (std.mem.indexOf(u8, test_case.name, filter) == null) return false;
        }
        return true;
    }

    fn runBatch(self: *RunContext, test_suite: *suite.TestSuite, tests: []const *suite.TestCase) !void {
        if (tests.len == 0) return;

        var worker_context = WorkerContext{
            .allocator = self.allocator,
            .test_suite = test_suite,
            .tests = tests,
            .policy = .{
                .filter = self.options.filter,
                .timeout_ms = self.options.timeout_ms,
            },
        };
        const count = @min(self.worker_limit, tests.len);
        var threads: std.ArrayList(std.Thread) = .empty;
        defer threads.deinit(self.allocator);

        for (0..count) |_| {
            const thread = std.Thread.spawn(.{}, WorkerContext.worker, .{&worker_context}) catch |err| {
                for (threads.items) |started| started.join();
                return err;
            };
            threads.append(self.allocator, thread) catch |err| {
                thread.join();
                for (threads.items) |started| started.join();
                return err;
            };
        }
        for (threads.items) |thread| thread.join();
    }

    fn reportSkippedSuite(self: *RunContext, test_suite: *suite.TestSuite) !void {
        for (test_suite.tests.items) |*test_case| {
            test_case.status = .skipped;
            try self.rep.onTestEnd(test_case);
        }
        for (test_suite.suites.items) |nested| {
            try self.rep.onSuiteStart(nested.name);
            try self.reportSkippedSuite(nested);
            try self.rep.onSuiteEnd(nested.name);
        }
    }
};

/// Run suites in declaration order while executing each suite's direct tests
/// with a bounded worker set. Reporter callbacks are serialized and emitted in
/// declaration order after each batch completes.
pub fn runTestsParallel(
    allocator: std.mem.Allocator,
    test_registry: *suite.TestRegistry,
    rep: *reporter.Reporter,
    options: ParallelOptions,
) !bool {
    if (!options.enabled) return ParallelError.ParallelNotEnabled;
    const worker_limit = try resolveWorkerCount(options.n_jobs);

    const total_tests = test_registry.countAllTests();
    try rep.onRunStart(total_tests);

    var context = RunContext{
        .allocator = allocator,
        .registry = test_registry,
        .rep = rep,
        .options = options,
        .worker_limit = worker_limit,
    };

    var all_passed = true;
    for (test_registry.root_suites.items) |test_suite| {
        if (!try context.runSuite(test_suite)) all_passed = false;
    }

    var results = reporter.TestResults.init(allocator);
    defer results.deinit();
    for (test_registry.root_suites.items) |test_suite| {
        try addSuiteResults(&results, test_suite);
    }
    try rep.onRunEnd(&results);
    return all_passed and results.failed == 0;
}

fn addSuiteResults(results: *reporter.TestResults, test_suite: *suite.TestSuite) !void {
    for (test_suite.tests.items) |*test_case| try results.addTest(test_case);
    for (test_suite.suites.items) |nested| try addSuiteResults(results, nested);
}

test "ParallelOptions defaults to CPU-based workers" {
    const options = ParallelOptions{};
    try std.testing.expect(options.n_jobs == null);
    try std.testing.expect(!options.enabled);
    try std.testing.expectEqual(
        @max(std.Thread.getCpuCount() catch 1, 1),
        try resolveWorkerCount(null),
    );
}

test "configured worker count rejects zero" {
    try std.testing.expectEqual(@as(usize, 2), try resolveWorkerCount(2));
    try std.testing.expectError(ParallelError.InvalidJobCount, resolveWorkerCount(0));
}

var active_tests = std.atomic.Value(usize).init(0);
var peak_tests = std.atomic.Value(usize).init(0);

fn boundedTest(_: std.mem.Allocator) !void {
    const active = active_tests.fetchAdd(1, .monotonic) + 1;
    var peak = peak_tests.load(.monotonic);
    while (active > peak) {
        if (peak_tests.cmpxchgWeak(peak, active, .monotonic, .monotonic)) |observed| {
            peak = observed;
        } else break;
    }
    compat.sleep(20 * std.time.ns_per_ms);
    _ = active_tests.fetchSub(1, .monotonic);
}

fn passingTest(_: std.mem.Allocator) !void {}

fn failingTest(_: std.mem.Allocator) !void {
    return error.ExpectedFailure;
}

var parent_before_each = std.atomic.Value(usize).init(0);
var parent_after_each = std.atomic.Value(usize).init(0);
var child_before_each = std.atomic.Value(usize).init(0);
var child_after_each = std.atomic.Value(usize).init(0);
var parent_before_all = std.atomic.Value(usize).init(0);
var child_before_all = std.atomic.Value(usize).init(0);
var parent_after_all = std.atomic.Value(usize).init(0);
var child_after_all = std.atomic.Value(usize).init(0);

fn parentBeforeEach(_: std.mem.Allocator) !void {
    _ = parent_before_each.fetchAdd(1, .monotonic);
}

fn parentAfterEach(_: std.mem.Allocator) !void {
    _ = parent_after_each.fetchAdd(1, .monotonic);
}

fn childBeforeEach(_: std.mem.Allocator) !void {
    _ = child_before_each.fetchAdd(1, .monotonic);
}

fn childAfterEach(_: std.mem.Allocator) !void {
    _ = child_after_each.fetchAdd(1, .monotonic);
}

fn parentBeforeAll(_: std.mem.Allocator) !void {
    _ = parent_before_all.fetchAdd(1, .monotonic);
}

fn childBeforeAll(_: std.mem.Allocator) !void {
    if (parent_before_all.load(.monotonic) != 1) return error.ParentBeforeAllMissing;
    _ = child_before_all.fetchAdd(1, .monotonic);
}

fn childAfterAll(_: std.mem.Allocator) !void {
    _ = child_after_all.fetchAdd(1, .monotonic);
}

fn parentAfterAll(_: std.mem.Allocator) !void {
    if (child_after_all.load(.monotonic) != 1) return error.ChildAfterAllMissing;
    _ = parent_after_all.fetchAdd(1, .monotonic);
}

const RecordingReporter = struct {
    reporter: reporter.Reporter,
    run_starts: usize = 0,
    run_ends: usize = 0,
    suite_starts: usize = 0,
    suite_ends: usize = 0,
    test_starts: usize = 0,
    ended_count: usize = 0,
    ended_names: [16][]const u8 = undefined,
    total: usize = 0,
    passed: usize = 0,
    failed: usize = 0,
    skipped: usize = 0,

    fn init(allocator: std.mem.Allocator) RecordingReporter {
        return .{
            .reporter = .{
                .vtable = &.{
                    .onRunStart = onRunStart,
                    .onRunEnd = onRunEnd,
                    .onSuiteStart = onSuiteStart,
                    .onSuiteEnd = onSuiteEnd,
                    .onTestStart = onTestStart,
                    .onTestEnd = onTestEnd,
                },
                .allocator = allocator,
            },
        };
    }

    fn self(rep: *reporter.Reporter) *RecordingReporter {
        return @fieldParentPtr("reporter", rep);
    }

    fn onRunStart(rep: *reporter.Reporter, _: usize) !void {
        self(rep).run_starts += 1;
    }

    fn onRunEnd(rep: *reporter.Reporter, results: *reporter.TestResults) !void {
        const recording = self(rep);
        recording.run_ends += 1;
        recording.total = results.total;
        recording.passed = results.passed;
        recording.failed = results.failed;
        recording.skipped = results.skipped;
    }

    fn onSuiteStart(rep: *reporter.Reporter, _: []const u8) !void {
        self(rep).suite_starts += 1;
    }

    fn onSuiteEnd(rep: *reporter.Reporter, _: []const u8) !void {
        self(rep).suite_ends += 1;
    }

    fn onTestStart(rep: *reporter.Reporter, _: []const u8) !void {
        self(rep).test_starts += 1;
    }

    fn onTestEnd(rep: *reporter.Reporter, test_case: *const suite.TestCase) !void {
        const recording = self(rep);
        recording.ended_names[recording.ended_count] = test_case.name;
        recording.ended_count += 1;
    }
};

fn verifyConcurrencyLimit(limit: ?usize) !void {
    const allocator = std.heap.smp_allocator;
    var registry = suite.TestRegistry.init(allocator);
    defer registry.deinit();
    const test_suite = try suite.TestSuite.init(allocator, "bounded");
    for (0..8) |_| try test_suite.addTest(suite.TestCase.init("work", boundedTest));
    try registry.registerSuite(test_suite);

    active_tests.store(0, .monotonic);
    peak_tests.store(0, .monotonic);
    var recording = RecordingReporter.init(allocator);
    try std.testing.expect(try runTestsParallel(allocator, &registry, &recording.reporter, .{
        .enabled = true,
        .n_jobs = limit,
    }));

    const resolved = try resolveWorkerCount(limit);
    try std.testing.expect(peak_tests.load(.monotonic) > 0);
    try std.testing.expect(peak_tests.load(.monotonic) <= @min(resolved, 8));
}

test "parallel executor bounds one worker" {
    try verifyConcurrencyLimit(1);
    try std.testing.expectEqual(@as(usize, 1), peak_tests.load(.monotonic));
}

test "parallel executor bounds two workers" {
    try verifyConcurrencyLimit(2);
    try std.testing.expectEqual(@as(usize, 2), peak_tests.load(.monotonic));
}

test "parallel executor bounds default CPU workers" {
    try verifyConcurrencyLimit(null);
}

test "parallel reporting is serialized, ordered, and complete" {
    const allocator = std.heap.smp_allocator;
    var registry = suite.TestRegistry.init(allocator);
    defer registry.deinit();
    const test_suite = try suite.TestSuite.init(allocator, "ordered");
    try test_suite.addTest(suite.TestCase.init("first", passingTest));
    try test_suite.addTest(suite.TestCase.init("second", failingTest));
    var skipped = suite.TestCase.init("third", passingTest);
    skipped.skip = true;
    try test_suite.addTest(skipped);
    try registry.registerSuite(test_suite);

    var recording = RecordingReporter.init(allocator);
    try std.testing.expect(!try runTestsParallel(allocator, &registry, &recording.reporter, .{
        .enabled = true,
        .n_jobs = 2,
    }));

    try std.testing.expectEqual(@as(usize, 1), recording.run_starts);
    try std.testing.expectEqual(@as(usize, 1), recording.run_ends);
    try std.testing.expectEqual(@as(usize, 1), recording.suite_starts);
    try std.testing.expectEqual(@as(usize, 1), recording.suite_ends);
    try std.testing.expectEqual(@as(usize, 2), recording.test_starts);
    try std.testing.expectEqual(@as(usize, 3), recording.ended_count);
    try std.testing.expectEqualStrings("first", recording.ended_names[0]);
    try std.testing.expectEqualStrings("second", recording.ended_names[1]);
    try std.testing.expectEqualStrings("third", recording.ended_names[2]);
    try std.testing.expectEqual(@as(usize, 3), recording.total);
    try std.testing.expectEqual(@as(usize, 1), recording.passed);
    try std.testing.expectEqual(@as(usize, 1), recording.failed);
    try std.testing.expectEqual(@as(usize, 1), recording.skipped);
}

test "parallel executor preserves nested hook lifecycles" {
    const counters = [_]*std.atomic.Value(usize){
        &parent_before_each,
        &parent_after_each,
        &child_before_each,
        &child_after_each,
        &parent_before_all,
        &child_before_all,
        &parent_after_all,
        &child_after_all,
    };
    for (counters) |counter| counter.store(0, .monotonic);

    const allocator = std.heap.smp_allocator;
    var registry = suite.TestRegistry.init(allocator);
    defer registry.deinit();
    const parent = try suite.TestSuite.init(allocator, "parent");
    const child = try suite.TestSuite.init(allocator, "child");
    try parent.addBeforeAll(parentBeforeAll);
    try parent.addAfterAll(parentAfterAll);
    try parent.addBeforeEach(parentBeforeEach);
    try parent.addAfterEach(parentAfterEach);
    try parent.addTest(suite.TestCase.init("parent test", passingTest));
    try child.addBeforeAll(childBeforeAll);
    try child.addAfterAll(childAfterAll);
    try child.addBeforeEach(childBeforeEach);
    try child.addAfterEach(childAfterEach);
    try child.addTest(suite.TestCase.init("child one", passingTest));
    try child.addTest(suite.TestCase.init("child two", passingTest));
    try parent.addSuite(child);
    try registry.registerSuite(parent);

    var recording = RecordingReporter.init(allocator);
    try std.testing.expect(try runTestsParallel(allocator, &registry, &recording.reporter, .{
        .enabled = true,
        .n_jobs = 2,
    }));

    try std.testing.expectEqual(@as(usize, 3), parent_before_each.load(.monotonic));
    try std.testing.expectEqual(@as(usize, 3), parent_after_each.load(.monotonic));
    try std.testing.expectEqual(@as(usize, 2), child_before_each.load(.monotonic));
    try std.testing.expectEqual(@as(usize, 2), child_after_each.load(.monotonic));
    try std.testing.expectEqual(@as(usize, 1), parent_before_all.load(.monotonic));
    try std.testing.expectEqual(@as(usize, 1), child_before_all.load(.monotonic));
    try std.testing.expectEqual(@as(usize, 1), parent_after_all.load(.monotonic));
    try std.testing.expectEqual(@as(usize, 1), child_after_all.load(.monotonic));
    try std.testing.expectEqual(@as(usize, 2), recording.suite_starts);
    try std.testing.expectEqual(@as(usize, 2), recording.suite_ends);
    try std.testing.expectEqual(@as(usize, 3), recording.total);
    try std.testing.expectEqual(@as(usize, 3), recording.passed);
}
