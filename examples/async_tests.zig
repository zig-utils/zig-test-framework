const std = @import("std");
const zig_test = @import("zig-test");

/// Example: Basic async test
pub fn example_basic_async_test() !void {
    const allocator = std.heap.page_allocator;

    // Create async test executor
    var executor = zig_test.AsyncTestExecutor.init(allocator, .{
        .default_timeout_ms = 5000,
        .concurrent = false,
        .verbose = true,
    });
    defer executor.deinit();

    // Define an async test function
    const asyncTest1 = struct {
        fn run(alloc: std.mem.Allocator) !void {
            _ = alloc;
            // Simulate async work
            std.Thread.sleep(100 * std.time.ns_per_ms);
            std.debug.print("Async test 1 completed\n", .{});
        }
    }.run;

    // Register the test
    try executor.registerTest("async_test_1", asyncTest1);

    // Execute all tests
    const results = try executor.executeAll();
    defer allocator.free(results);

    // Print results
    for (results) |result| {
        std.debug.print("Test '{s}': {s}\n", .{ result.name, @tagName(result.status) });
    }

    // Get statistics
    const stats = zig_test.AsyncTestExecutor.getStats(results);
    std.debug.print("{}\n", .{stats});
}

/// Example: Async test with timeout
pub fn example_async_timeout() !void {
    const allocator = std.heap.page_allocator;

    var executor = zig_test.AsyncTestExecutor.init(allocator, .{
        .default_timeout_ms = 100, // Short timeout
        .verbose = true,
    });
    defer executor.deinit();

    // Test that will timeout
    const slowTest = struct {
        fn run(alloc: std.mem.Allocator) !void {
            _ = alloc;
            std.Thread.sleep(500 * std.time.ns_per_ms); // Takes too long
        }
    }.run;

    try executor.registerTest("slow_test", slowTest);

    const results = try executor.executeAll();
    defer allocator.free(results);

    for (results) |*result| {
        std.debug.print("Test '{s}': {s}\n", .{ result.name, @tagName(result.status) });
        if (result.error_msg) |msg| {
            std.debug.print("  Error: {s}\n", .{msg});
        }
        result.deinit();
    }
}

/// Example: Concurrent async tests
pub fn example_concurrent_async() !void {
    const allocator = std.heap.page_allocator;

    var executor = zig_test.AsyncTestExecutor.init(allocator, .{
        .concurrent = true,
        .max_concurrent = 3,
        .verbose = true,
    });
    defer executor.deinit();

    // Create multiple async tests
    const asyncTest = struct {
        fn run(alloc: std.mem.Allocator) !void {
            _ = alloc;
            std.Thread.sleep(50 * std.time.ns_per_ms);
        }
    }.run;

    try executor.registerTest("concurrent_1", asyncTest);
    try executor.registerTest("concurrent_2", asyncTest);
    try executor.registerTest("concurrent_3", asyncTest);
    try executor.registerTest("concurrent_4", asyncTest);
    try executor.registerTest("concurrent_5", asyncTest);

    const start = std.time.nanoTimestamp();
    const results = try executor.executeAll();
    defer allocator.free(results);
    const duration = std.time.nanoTimestamp() - start;

    std.debug.print("Total duration: {d:.2}ms\n", .{
        @as(f64, @floatFromInt(duration)) / 1_000_000.0,
    });

    const stats = zig_test.AsyncTestExecutor.getStats(results);
    std.debug.print("{}\n", .{stats});
}

/// Example: Async tests with hooks
pub fn example_async_hooks() !void {
    const allocator = std.heap.page_allocator;

    var hooks = zig_test.AsyncHooksManager.init(allocator);

    // Setup hooks
    const beforeHook = struct {
        fn run(alloc: std.mem.Allocator) !void {
            _ = alloc;
            std.debug.print("Before hook executed\n", .{});
            std.Thread.sleep(10 * std.time.ns_per_ms);
        }
    }.run;

    const afterHook = struct {
        fn run(alloc: std.mem.Allocator) !void {
            _ = alloc;
            std.debug.print("After hook executed\n", .{});
            std.Thread.sleep(10 * std.time.ns_per_ms);
        }
    }.run;

    hooks.before_each = beforeHook;
    hooks.after_each = afterHook;

    // Run hooks
    try hooks.runBeforeEach();
    std.debug.print("Running test...\n", .{});
    try hooks.runAfterEach();
}

/// Example: Using itAsync in suite
pub fn example_suite_async() !void {
    const allocator = std.heap.page_allocator;

    // Register async tests using the suite API
    const asyncTest1 = struct {
        fn run(alloc: std.mem.Allocator) !void {
            _ = alloc;
            std.Thread.sleep(50 * std.time.ns_per_ms);
            std.debug.print("Suite async test 1 passed\n", .{});
        }
    }.run;

    const asyncTest2 = struct {
        fn run(alloc: std.mem.Allocator) !void {
            _ = alloc;
            std.Thread.sleep(50 * std.time.ns_per_ms);
            std.debug.print("Suite async test 2 passed\n", .{});
        }
    }.run;

    // Register async tests
    try zig_test.itAsync(allocator, "async suite test 1", asyncTest1);
    try zig_test.itAsync(allocator, "async suite test 2", asyncTest2);

    // With custom timeout
    try zig_test.itAsyncTimeout(allocator, "async with timeout", asyncTest1, 1000);

    std.debug.print("Async tests registered successfully\n", .{});
}

/// Example: Mixed sync and async tests
pub fn example_mixed_tests() !void {
    const allocator = std.heap.page_allocator;

    const syncTest = struct {
        fn run(alloc: std.mem.Allocator) !void {
            _ = alloc;
            std.debug.print("Sync test executed\n", .{});
        }
    }.run;

    const asyncTest = struct {
        fn run(alloc: std.mem.Allocator) !void {
            _ = alloc;
            std.Thread.sleep(50 * std.time.ns_per_ms);
            std.debug.print("Async test executed\n", .{});
        }
    }.run;

    // Register both types
    try zig_test.it(allocator, "sync test", syncTest);
    try zig_test.itAsync(allocator, "async test", asyncTest);

    std.debug.print("Mixed sync/async tests registered\n", .{});
}

/// Example: Error handling in async tests
pub fn example_async_errors() !void {
    const allocator = std.heap.page_allocator;

    var executor = zig_test.AsyncTestExecutor.init(allocator, .{
        .verbose = true,
    });
    defer executor.deinit();

    // Test that passes
    const passingTest = struct {
        fn run(alloc: std.mem.Allocator) !void {
            _ = alloc;
            std.Thread.sleep(10 * std.time.ns_per_ms);
        }
    }.run;

    // Test that fails
    const failingTest = struct {
        fn run(alloc: std.mem.Allocator) !void {
            _ = alloc;
            std.Thread.sleep(10 * std.time.ns_per_ms);
            return error.AsyncTestFailed;
        }
    }.run;

    try executor.registerTest("passing_test", passingTest);
    try executor.registerTest("failing_test", failingTest);

    const results = try executor.executeAll();
    defer allocator.free(results);

    for (results) |*result| {
        std.debug.print("Test '{s}': {s}\n", .{ result.name, @tagName(result.status) });
        if (result.error_msg) |msg| {
            std.debug.print("  Error: {s}\n", .{msg});
        }
        result.deinit();
    }

    const stats = zig_test.AsyncTestExecutor.getStats(results);
    std.debug.print("{}\n", .{stats});
}

pub fn main() !void {
    std.debug.print("\n=== Basic Async Test ===\n", .{});
    try example_basic_async_test();

    std.debug.print("\n=== Async Timeout ===\n", .{});
    try example_async_timeout();

    std.debug.print("\n=== Concurrent Async Tests ===\n", .{});
    try example_concurrent_async();

    std.debug.print("\n=== Async Hooks ===\n", .{});
    try example_async_hooks();

    std.debug.print("\n=== Suite Async Tests ===\n", .{});
    try example_suite_async();

    std.debug.print("\n=== Mixed Sync/Async Tests ===\n", .{});
    try example_mixed_tests();

    std.debug.print("\n=== Async Error Handling ===\n", .{});
    try example_async_errors();

    std.debug.print("\n✅ All async test examples completed!\n", .{});
}
