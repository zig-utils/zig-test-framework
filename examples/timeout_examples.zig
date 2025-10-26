const std = @import("std");
const zig_test = @import("zig-test");

/// Example 1: Basic per-test timeout
pub fn example_per_test_timeout() !void {
    const allocator = std.heap.page_allocator;

    const fastTest = struct {
        fn run(alloc: std.mem.Allocator) !void {
            _ = alloc;
            std.Thread.sleep(50 * std.time.ns_per_ms);
            std.debug.print("Fast test completed\n", .{});
        }
    }.run;

    // Register test with 1 second timeout
    try zig_test.itTimeout(allocator, "fast test", fastTest, 1000);

    std.debug.print("Test registered with 1000ms timeout\n", .{});
}

/// Example 2: Suite timeout
pub fn example_suite_timeout() !void {
    const allocator = std.heap.page_allocator;

    const test1 = struct {
        fn run(alloc: std.mem.Allocator) !void {
            _ = alloc;
            std.Thread.sleep(100 * std.time.ns_per_ms);
        }
    }.run;

    const test2 = struct {
        fn run(alloc: std.mem.Allocator) !void {
            _ = alloc;
            std.Thread.sleep(100 * std.time.ns_per_ms);
        }
    }.run;

    // Create suite with 500ms timeout for all tests
    const SuiteFn = struct {
        fn suite(alloc: std.mem.Allocator) !void {
            try zig_test.it(alloc, "test 1", test1);
            try zig_test.it(alloc, "test 2", test2);
        }
    };

    try zig_test.describeTimeout(allocator, "Timed Suite", 500, SuiteFn.suite);

    std.debug.print("Suite registered with 500ms timeout\n", .{});
}

/// Example 3: Timeout context usage
pub fn example_timeout_context() !void {
    const allocator = std.heap.page_allocator;

    var context = zig_test.TimeoutContext.init(allocator, 1000);
    context.start();

    std.debug.print("Timeout context started with 1000ms timeout\n", .{});

    // Simulate some work
    std.Thread.sleep(200 * std.time.ns_per_ms);

    if (!context.isTimedOut()) {
        std.debug.print("Still within timeout, elapsed: {d}ms, remaining: {d}ms\n", .{
            context.getElapsedMs(),
            context.getRemainingMs(),
        });
    }

    // Complete the context
    context.complete();

    var result = try context.getResult();
    defer result.deinit();

    std.debug.print("Result: {}\n", .{result});
}

/// Example 4: Timeout extension
pub fn example_timeout_extension() !void {
    const allocator = std.heap.page_allocator;

    var context = zig_test.TimeoutContext.init(allocator, 500);
    context.start();

    std.debug.print("Started with 500ms timeout\n", .{});

    // Simulate work
    std.Thread.sleep(400 * std.time.ns_per_ms);

    // Need more time!
    try context.extend(500);
    std.debug.print("Extended timeout by 500ms (total: 1000ms)\n", .{});

    // Continue work
    std.Thread.sleep(300 * std.time.ns_per_ms);

    if (!context.isTimedOut()) {
        std.debug.print("Completed within extended timeout\n", .{});
    }

    context.complete();

    var result = try context.getResult();
    defer result.deinit();

    std.debug.print("Final result: {}\n", .{result});
}

/// Example 5: Global timeout configuration
pub fn example_global_timeout() !void {
    const allocator = std.heap.page_allocator;

    const global_config = zig_test.GlobalTimeoutConfig{
        .default_timeout_ms = 2000,
        .enabled = true,
        .grace_period_ms = 500,
        .allow_extension = true,
        .max_extension_ms = 5000,
    };

    var enforcer = zig_test.TimeoutEnforcer.init(allocator, global_config);
    defer enforcer.deinit();

    std.debug.print("Global timeout config:\n", .{});
    std.debug.print("  Default: {d}ms\n", .{global_config.default_timeout_ms});
    std.debug.print("  Grace period: {d}ms\n", .{global_config.grace_period_ms});
    std.debug.print("  Allow extension: {}\n", .{global_config.allow_extension});
    std.debug.print("  Max extension: {d}ms\n", .{global_config.max_extension_ms});

    // Get effective timeout (test, suite, then global)
    const timeout1 = enforcer.getEffectiveTimeout(3000, 0);
    const timeout2 = enforcer.getEffectiveTimeout(0, 2500);
    const timeout3 = enforcer.getEffectiveTimeout(0, 0);

    std.debug.print("Effective timeouts:\n", .{});
    std.debug.print("  With test timeout (3000ms): {d}ms\n", .{timeout1});
    std.debug.print("  With suite timeout (2500ms): {d}ms\n", .{timeout2});
    std.debug.print("  With global timeout: {d}ms\n", .{timeout3});
}

/// Example 6: Timeout monitoring
pub fn example_timeout_monitoring() !void {
    const allocator = std.heap.page_allocator;

    const global_config = zig_test.GlobalTimeoutConfig{
        .default_timeout_ms = 1000,
        .enabled = true,
    };

    var enforcer = zig_test.TimeoutEnforcer.init(allocator, global_config);
    defer enforcer.deinit();

    // Start monitoring
    try enforcer.startMonitoring();
    std.debug.print("Timeout monitoring started\n", .{});

    // Create and register a timeout context
    var context = zig_test.TimeoutContext.init(allocator, 500);
    context.start();
    try enforcer.registerContext(&context);

    std.debug.print("Registered context with 500ms timeout\n", .{});

    // Simulate work
    std.Thread.sleep(600 * std.time.ns_per_ms);

    // Check if timed out
    if (context.isTimedOut()) {
        std.debug.print("Context timed out as expected\n", .{});
    }

    // Unregister and stop
    enforcer.unregisterContext(&context);
    enforcer.stop();

    std.debug.print("Monitoring stopped\n", .{});
}

/// Example 7: Suite timeout tracker
pub fn example_suite_tracker() !void {
    const allocator = std.heap.page_allocator;

    var tracker = zig_test.SuiteTimeoutTracker.init(allocator, "My Test Suite", 1000);

    std.debug.print("Suite: {s}\n", .{tracker.suite_name});
    std.debug.print("Timeout: {d}ms\n", .{tracker.timeout_ms});

    // Run some tests
    tracker.incrementTest();
    std.Thread.sleep(200 * std.time.ns_per_ms);
    tracker.incrementCompleted();

    tracker.incrementTest();
    std.Thread.sleep(200 * std.time.ns_per_ms);
    tracker.incrementCompleted();

    std.debug.print("Tests run: {d}/{d}\n", .{ tracker.completed_count, tracker.test_count });
    std.debug.print("Elapsed: {d}ms\n", .{tracker.getElapsedMs()});
    std.debug.print("Remaining: {d}ms\n", .{tracker.getRemainingMs()});

    if (!tracker.isTimedOut()) {
        std.debug.print("Suite completed within timeout\n", .{});
    }
}

/// Example 8: Timeout error handling
pub fn example_timeout_errors() !void {
    const allocator = std.heap.page_allocator;

    var context = zig_test.TimeoutContext.init(allocator, 500);
    context.allow_extension = false; // Disable extension
    context.start();

    // Try to extend (should fail)
    if (context.extend(100)) |_| {
        std.debug.print("Extended (unexpected)\n", .{});
    } else |err| {
        std.debug.print("Extension failed as expected: {s}\n", .{@errorName(err)});
    }

    // Try to exceed max extension
    var context2 = zig_test.TimeoutContext.init(allocator, 500);
    context2.max_extension_ms = 1000;
    context2.start();

    if (context2.extend(1500)) |_| {
        std.debug.print("Extended (unexpected)\n", .{});
    } else |err| {
        std.debug.print("Extension limit exceeded: {s}\n", .{@errorName(err)});
    }
}

/// Example 9: Combined async and timeout
pub fn example_async_with_timeout() !void {
    const allocator = std.heap.page_allocator;

    const asyncTest = struct {
        fn run(alloc: std.mem.Allocator) !void {
            _ = alloc;
            std.Thread.sleep(100 * std.time.ns_per_ms);
            std.debug.print("Async test completed\n", .{});
        }
    }.run;

    // Register async test with custom timeout
    try zig_test.itAsyncTimeout(allocator, "timed async test", asyncTest, 2000);

    std.debug.print("Async test registered with 2000ms timeout\n", .{});
}

/// Example 10: Timeout result formatting
pub fn example_timeout_result() !void {
    const allocator = std.heap.page_allocator;

    var context = zig_test.TimeoutContext.init(allocator, 1000);
    context.start();

    std.Thread.sleep(150 * std.time.ns_per_ms);

    // Extend timeout
    try context.extend(500);

    std.Thread.sleep(100 * std.time.ns_per_ms);

    context.complete();

    var result = try context.getResult();
    defer result.deinit();

    std.debug.print("{}\n", .{result});

    // Can also access individual fields
    std.debug.print("Status: {s}\n", .{@tagName(result.status)});
    std.debug.print("Elapsed: {d}ms\n", .{result.elapsed_ms});
    std.debug.print("Timeout: {d}ms\n", .{result.timeout_ms});
    std.debug.print("Extended: {d}ms\n", .{result.extended_ms});
}

pub fn main() !void {
    std.debug.print("\n=== Example 1: Per-Test Timeout ===\n", .{});
    try example_per_test_timeout();

    std.debug.print("\n=== Example 2: Suite Timeout ===\n", .{});
    try example_suite_timeout();

    std.debug.print("\n=== Example 3: Timeout Context ===\n", .{});
    try example_timeout_context();

    std.debug.print("\n=== Example 4: Timeout Extension ===\n", .{});
    try example_timeout_extension();

    std.debug.print("\n=== Example 5: Global Timeout Configuration ===\n", .{});
    try example_global_timeout();

    std.debug.print("\n=== Example 6: Timeout Monitoring ===\n", .{});
    try example_timeout_monitoring();

    std.debug.print("\n=== Example 7: Suite Timeout Tracker ===\n", .{});
    try example_suite_tracker();

    std.debug.print("\n=== Example 8: Timeout Error Handling ===\n", .{});
    try example_timeout_errors();

    std.debug.print("\n=== Example 9: Async with Timeout ===\n", .{});
    try example_async_with_timeout();

    std.debug.print("\n=== Example 10: Timeout Result Formatting ===\n", .{});
    try example_timeout_result();

    std.debug.print("\n✅ All timeout examples completed!\n", .{});
}
