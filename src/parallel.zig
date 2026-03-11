const std = @import("std");
const suite = @import("suite.zig");
const reporter = @import("reporter.zig");
const compat = @import("compat.zig");

/// Options for parallel test execution
pub const ParallelOptions = struct {
    /// Number of worker threads (null = auto-detect CPU count)
    n_jobs: ?usize = null,
    /// Whether parallel execution is enabled
    enabled: bool = false,
};

/// Result from running a test in parallel
pub const TestResult = struct {
    test_case: *suite.TestCase,
    suite_name: []const u8,
    success: bool,
    mutex: compat.Mutex = .{},
};

/// Context for parallel test execution
pub const ParallelContext = struct {
    allocator: std.mem.Allocator,
    reporter: *reporter.Reporter,
    results: std.ArrayList(TestResult),
    mutex: compat.Mutex = .{},

    pub fn init(allocator: std.mem.Allocator, rep: *reporter.Reporter) ParallelContext {
        return .{
            .allocator = allocator,
            .reporter = rep,
            .results = .empty,
        };
    }

    pub fn deinit(self: *ParallelContext) void {
        self.results.deinit(self.allocator);
    }
};

/// Task for executing a single test
pub const TestTask = struct {
    context: *ParallelContext,
    test_case: *suite.TestCase,
    suite_name: []const u8,

    pub fn run(self: *TestTask) void {
        // Execute the test
        const success = self.executeTest();

        // Store result in thread-safe manner
        self.context.mutex.lock();
        defer self.context.mutex.unlock();

        self.context.results.append(self.context.allocator, .{
            .test_case = self.test_case,
            .suite_name = self.suite_name,
            .success = success,
        }) catch |err| {
            std.debug.print("Error appending result: {any}\n", .{err});
        };
    }

    fn executeTest(self: *TestTask) bool {
        self.test_case.status = .running;

        // Call the test function
        self.test_case.test_fn(self.context.allocator) catch |err| {
            self.test_case.status = .failed;
            const err_msg = std.fmt.allocPrint(
                self.context.allocator,
                "Test failed: {any}",
                .{err},
            ) catch "Out of memory";
            self.test_case.error_message = err_msg;
            return false;
        };

        self.test_case.status = .passed;
        return true;
    }
};

/// Run tests in parallel using thread pool
pub fn runTestsParallel(
    allocator: std.mem.Allocator,
    test_registry: *suite.TestRegistry,
    rep: *reporter.Reporter,
    options: ParallelOptions,
) !bool {
    if (!options.enabled) {
        return error.ParallelNotEnabled;
    }

    // Create parallel context
    var context = ParallelContext.init(allocator, rep);
    defer context.deinit();

    // Count total tests
    var total_tests: usize = 0;
    for (test_registry.root_suites.items) |test_suite| {
        total_tests += test_suite.tests.items.len;
    }

    try rep.onRunStart(total_tests);

    // Collect tasks and spawn threads
    var threads = std.ArrayList(std.Thread).empty;
    defer threads.deinit(allocator);

    for (test_registry.root_suites.items) |test_suite| {
        try rep.onSuiteStart(test_suite.name);

        for (test_suite.tests.items) |*test_case| {
            if (test_case.skip) {
                test_case.status = .skipped;
                continue;
            }

            // Create task
            const task = try allocator.create(TestTask);
            task.* = .{
                .context = &context,
                .test_case = test_case,
                .suite_name = test_suite.name,
            };

            // Spawn thread for task
            const thread = try std.Thread.spawn(.{}, runTestTask, .{task});
            try threads.append(allocator, thread);
        }
    }

    // Wait for all threads to complete
    for (threads.items) |thread| {
        thread.join();
    }

    // Report results (now that all tests are done)
    var all_passed = true;
    for (test_registry.root_suites.items) |test_suite| {
        for (test_suite.tests.items) |*test_case| {
            try rep.onTestEnd(test_case);
            if (test_case.status == .failed) {
                all_passed = false;
            }
        }
        try rep.onSuiteEnd(test_suite.name);
    }

    // Create results summary
    var results = reporter.TestResults.init(allocator);
    defer results.deinit();

    for (test_registry.root_suites.items) |test_suite| {
        for (test_suite.tests.items) |test_case| {
            results.total += 1;
            switch (test_case.status) {
                .passed => results.passed += 1,
                .failed => results.failed += 1,
                .skipped => results.skipped += 1,
                else => {},
            }
        }
    }

    try rep.onRunEnd(&results);

    return all_passed;
}

fn runTestTask(task: *TestTask) void {
    task.run();
}

// Tests
test "ParallelOptions default values" {
    const options = ParallelOptions{};

    try std.testing.expectEqual(@as(?usize, null), options.n_jobs);
    try std.testing.expectEqual(false, options.enabled);
}

test "ParallelOptions with custom values" {
    const options = ParallelOptions{
        .n_jobs = 4,
        .enabled = true,
    };

    try std.testing.expectEqual(@as(?usize, 4), options.n_jobs);
    try std.testing.expectEqual(true, options.enabled);
}

test "ParallelContext initialization" {
    const allocator = std.testing.allocator;

    var rep = reporter.Reporter{
        .vtable = undefined,
        .allocator = allocator,
    };

    var context = ParallelContext.init(allocator, &rep);
    defer context.deinit();

    try std.testing.expectEqual(@as(usize, 0), context.results.items.len);
}
