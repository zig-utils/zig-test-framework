const std = @import("std");

/// Async/Await Support for Zig Test Framework
///
/// NOTE: Zig's async/await is still experimental and subject to change.
/// This module provides basic utilities for async testing until Zig's
/// async stabilizes. For now, we provide thread-based async simulation.

/// Async test function signature
pub const AsyncTestFn = *const fn (allocator: std.mem.Allocator) anyerror!void;

/// Future-like type for async operations
pub fn Future(comptime T: type) type {
    return struct {
        result: ?Result = null,
        completed: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        mutex: std.Thread.Mutex = .{},

        const Self = @This();
        const Result = union(enum) {
            value: T,
            err: anyerror,
        };

        pub fn init() Self {
            return .{};
        }

        /// Wait for the future to complete and get the result
        pub fn await_value(self: *Self) !T {
            while (!self.completed.load(.monotonic)) {
                std.Thread.sleep(1 * std.time.ns_per_ms);
            }

            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.result) |result| {
                return switch (result) {
                    .value => |v| v,
                    .err => |e| e,
                };
            }

            return error.FutureNotCompleted;
        }

        /// Complete the future with a value
        pub fn resolve(self: *Self, value: T) void {
            self.mutex.lock();
            self.result = .{ .value = value };
            self.mutex.unlock();
            self.completed.store(true, .monotonic);
        }

        /// Complete the future with an error
        pub fn reject(self: *Self, err: anyerror) void {
            self.mutex.lock();
            self.result = .{ .err = err };
            self.mutex.unlock();
            self.completed.store(true, .monotonic);
        }

        /// Check if the future is completed
        pub fn isCompleted(self: *Self) bool {
            return self.completed.load(.monotonic);
        }
    };
}

/// Promise type for creating async operations
pub fn Promise(comptime T: type) type {
    return struct {
        future: Future(T),

        const Self = @This();

        pub fn init() Self {
            return .{
                .future = Future(T).init(),
            };
        }

        pub fn resolve(self: *Self, value: T) void {
            self.future.resolve(value);
        }

        pub fn reject(self: *Self, err: anyerror) void {
            self.future.reject(err);
        }

        pub fn getFuture(self: *Self) *Future(T) {
            return &self.future;
        }
    };
}

/// Run an async test function
pub fn runAsync(allocator: std.mem.Allocator, func: AsyncTestFn) !void {
    const Context = struct {
        allocator: std.mem.Allocator,
        func: AsyncTestFn,
        result: ?anyerror = null,
        completed: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

        fn run(ctx: *@This()) void {
            if (ctx.func(ctx.allocator)) |_| {
                ctx.result = null;
            } else |err| {
                ctx.result = err;
            }
            ctx.completed.store(true, .monotonic);
        }
    };

    var context = Context{
        .allocator = allocator,
        .func = func,
    };

    const thread = try std.Thread.spawn(.{}, Context.run, .{&context});
    thread.detach();

    // Wait for completion
    while (!context.completed.load(.monotonic)) {
        std.Thread.sleep(1 * std.time.ns_per_ms);
    }

    if (context.result) |err| {
        return err;
    }
}

/// Async executor for running multiple async operations concurrently
pub const AsyncExecutor = struct {
    allocator: std.mem.Allocator,
    threads: std.ArrayList(std.Thread),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .threads = std.ArrayList(std.Thread).empty,
        };
    }

    pub fn deinit(self: *Self) void {
        self.threads.deinit(self.allocator);
    }

    /// Spawn an async task
    pub fn spawn(self: *Self, comptime func: anytype, args: anytype) !void {
        const thread = try std.Thread.spawn(.{}, func, args);
        try self.threads.append(self.allocator, thread);
    }

    /// Wait for all spawned tasks to complete
    pub fn waitAll(self: *Self) void {
        for (self.threads.items) |thread| {
            thread.join();
        }
        self.threads.clearRetainingCapacity();
    }
};

/// Delay for async operations
pub fn delay(ms: u64) void {
    std.Thread.sleep(ms * std.time.ns_per_ms);
}

/// Run multiple futures concurrently and wait for all to complete
pub fn all(comptime T: type, allocator: std.mem.Allocator, futures: [](*Future(T))) ![]T {
    var results = try allocator.alloc(T, futures.len);

    for (futures, 0..) |future, i| {
        results[i] = try future.await_value();
    }

    return results;
}

/// Run multiple futures concurrently and return the first completed
pub fn race(comptime T: type, futures: [](*Future(T))) !T {
    while (true) {
        for (futures) |future| {
            if (future.isCompleted()) {
                return try future.await_value();
            }
        }
        std.Thread.sleep(1 * std.time.ns_per_ms);
    }
}

/// Timeout wrapper for async operations
pub fn timeout(comptime T: type, future: *Future(T), timeout_ms: u64) !T {
    const start = std.time.milliTimestamp();

    while (!future.isCompleted()) {
        const elapsed = std.time.milliTimestamp() - start;
        if (elapsed >= timeout_ms) {
            return error.Timeout;
        }
        std.Thread.sleep(1 * std.time.ns_per_ms);
    }

    return try future.await_value();
}

// Tests
test "Future resolve and await" {
    var future = Future(i32).init();

    // Resolve in background thread
    const ResolveContext = struct {
        future: *Future(i32),

        fn run(ctx: @This()) void {
            delay(10); // Simulate async work
            ctx.future.resolve(42);
        }
    };

    const thread = try std.Thread.spawn(.{}, ResolveContext.run, .{ResolveContext{ .future = &future }});
    thread.detach();

    const result = try future.await_value();
    try std.testing.expectEqual(@as(i32, 42), result);
}

test "Future reject with error" {
    var future = Future(i32).init();

    // Reject in background thread
    const RejectContext = struct {
        future: *Future(i32),

        fn run(ctx: @This()) void {
            delay(10);
            ctx.future.reject(error.TestError);
        }
    };

    const thread = try std.Thread.spawn(.{}, RejectContext.run, .{RejectContext{ .future = &future }});
    thread.detach();

    const result = future.await_value();
    try std.testing.expectError(error.TestError, result);
}

test "Promise pattern" {
    var promise = Promise([]const u8).init();
    var future = promise.getFuture();

    // Resolve promise in background
    const PromiseContext = struct {
        promise: *Promise([]const u8),

        fn run(ctx: @This()) void {
            delay(10);
            ctx.promise.resolve("Hello, Async!");
        }
    };

    const thread = try std.Thread.spawn(.{}, PromiseContext.run, .{PromiseContext{ .promise = &promise }});
    thread.detach();

    const result = try future.await_value();
    try std.testing.expectEqualStrings("Hello, Async!", result);
}

test "AsyncExecutor spawn and wait" {
    const allocator = std.testing.allocator;

    var executor = AsyncExecutor.init(allocator);
    defer executor.deinit();

    const TaskContext = struct {
        fn task1() void {
            delay(10);
        }

        fn task2() void {
            delay(10);
        }
    };

    try executor.spawn(TaskContext.task1, .{});
    try executor.spawn(TaskContext.task2, .{});

    executor.waitAll();

    // If we get here, all tasks completed
    try std.testing.expect(true);
}

test "timeout with Future" {
    var future = Future(i32).init();

    // Never resolve the future
    const result = timeout(i32, &future, 50);
    try std.testing.expectError(error.Timeout, result);
}
