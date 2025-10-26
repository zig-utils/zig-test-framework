const std = @import("std");
const suite = @import("suite.zig");

/// Global timeout configuration
pub const GlobalTimeoutConfig = struct {
    /// Default timeout for all tests (milliseconds)
    default_timeout_ms: u64 = 5000,
    /// Enable global timeout enforcement
    enabled: bool = true,
    /// Grace period after timeout before force termination (milliseconds)
    grace_period_ms: u64 = 1000,
    /// Allow tests to extend their timeout
    allow_extension: bool = true,
    /// Maximum timeout extension allowed (milliseconds)
    max_extension_ms: u64 = 30000,
};

/// Timeout configuration
pub const TimeoutConfig = struct {
    /// Test timeout in milliseconds (0 = no timeout)
    timeout_ms: u64 = 0,
    /// Suite timeout in milliseconds (0 = no timeout)
    suite_timeout_ms: u64 = 0,
    /// Use global timeout if no specific timeout set
    use_global: bool = true,
};

/// Timeout status
pub const TimeoutStatus = enum {
    not_started,
    running,
    completed_in_time,
    timed_out,
    extended,
    grace_period,
};

/// Timeout result
pub const TimeoutResult = struct {
    status: TimeoutStatus,
    elapsed_ms: u64,
    timeout_ms: u64,
    extended_ms: u64 = 0,
    message: ?[]const u8 = null,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *TimeoutResult) void {
        if (self.message) |msg| {
            self.allocator.free(msg);
        }
    }

    pub fn format(
        self: TimeoutResult,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("Timeout Result:\n", .{});
        try writer.print("  Status: {s}\n", .{@tagName(self.status)});
        try writer.print("  Elapsed: {d}ms\n", .{self.elapsed_ms});
        try writer.print("  Timeout: {d}ms\n", .{self.timeout_ms});
        if (self.extended_ms > 0) {
            try writer.print("  Extended: {d}ms\n", .{self.extended_ms});
        }
        if (self.message) |msg| {
            try writer.print("  Message: {s}\n", .{msg});
        }
    }
};

/// Timeout context for tracking test execution time
pub const TimeoutContext = struct {
    allocator: std.mem.Allocator,
    timeout_ms: u64,
    start_time: i64,
    extension_ms: u64 = 0,
    status: std.atomic.Value(u32) = std.atomic.Value(u32).init(0), // 0=not_started, 1=running, 2=completed, 3=timed_out, 4=extended, 5=grace_period
    completed: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    allow_extension: bool = true,
    max_extension_ms: u64 = 30000,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, timeout_ms: u64) Self {
        return .{
            .allocator = allocator,
            .timeout_ms = timeout_ms,
            .start_time = std.time.milliTimestamp(),
        };
    }

    /// Start the timeout timer
    pub fn start(self: *Self) void {
        self.start_time = std.time.milliTimestamp();
        self.status.store(1, .monotonic); // running
    }

    /// Check if timeout has been exceeded
    pub fn isTimedOut(self: *Self) bool {
        if (self.completed.load(.monotonic)) {
            return false;
        }

        const elapsed = self.getElapsedMs();
        const total_timeout = self.timeout_ms + self.extension_ms;

        return elapsed >= total_timeout;
    }

    /// Get elapsed time in milliseconds
    pub fn getElapsedMs(self: *Self) u64 {
        const now = std.time.milliTimestamp();
        return @intCast(now - self.start_time);
    }

    /// Get remaining time in milliseconds
    pub fn getRemainingMs(self: *Self) u64 {
        const elapsed = self.getElapsedMs();
        const total_timeout = self.timeout_ms + self.extension_ms;

        if (elapsed >= total_timeout) {
            return 0;
        }

        return total_timeout - elapsed;
    }

    /// Extend the timeout by specified milliseconds
    pub fn extend(self: *Self, additional_ms: u64) !void {
        if (!self.allow_extension) {
            return error.ExtensionNotAllowed;
        }

        const new_extension = self.extension_ms + additional_ms;
        if (new_extension > self.max_extension_ms) {
            return error.ExtensionLimitExceeded;
        }

        self.extension_ms = new_extension;
        self.status.store(4, .monotonic); // extended
    }

    /// Mark as completed
    pub fn complete(self: *Self) void {
        self.completed.store(true, .monotonic);
        self.status.store(2, .monotonic); // completed_in_time
    }

    /// Mark as timed out
    pub fn markTimedOut(self: *Self) void {
        self.status.store(3, .monotonic); // timed_out
    }

    fn statusToEnum(status_int: u32) TimeoutStatus {
        return switch (status_int) {
            0 => .not_started,
            1 => .running,
            2 => .completed_in_time,
            3 => .timed_out,
            4 => .extended,
            5 => .grace_period,
            else => .not_started,
        };
    }

    /// Get the timeout result
    pub fn getResult(self: *Self) !TimeoutResult {
        const elapsed = self.getElapsedMs();
        const status_int = self.status.load(.monotonic);
        const status_value = statusToEnum(status_int);

        var message: ?[]const u8 = null;
        if (status_value == .timed_out) {
            message = try std.fmt.allocPrint(
                self.allocator,
                "Test exceeded timeout of {d}ms (elapsed: {d}ms)",
                .{ self.timeout_ms + self.extension_ms, elapsed },
            );
        } else if (status_value == .extended) {
            message = try std.fmt.allocPrint(
                self.allocator,
                "Timeout extended by {d}ms",
                .{self.extension_ms},
            );
        }

        return TimeoutResult{
            .status = status_value,
            .elapsed_ms = elapsed,
            .timeout_ms = self.timeout_ms,
            .extended_ms = self.extension_ms,
            .message = message,
            .allocator = self.allocator,
        };
    }
};

/// Timeout enforcer - monitors and enforces test timeouts
pub const TimeoutEnforcer = struct {
    allocator: std.mem.Allocator,
    global_config: GlobalTimeoutConfig,
    active_contexts: std.ArrayList(*TimeoutContext),
    monitor_thread: ?std.Thread = null,
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    mutex: std.Thread.Mutex = .{},

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, global_config: GlobalTimeoutConfig) Self {
        return .{
            .allocator = allocator,
            .global_config = global_config,
            .active_contexts = std.ArrayList(*TimeoutContext).empty,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stop();
        self.active_contexts.deinit(self.allocator);
    }

    /// Start monitoring timeouts
    pub fn startMonitoring(self: *Self) !void {
        if (self.running.load(.monotonic)) {
            return;
        }

        self.running.store(true, .monotonic);
        self.monitor_thread = try std.Thread.spawn(.{}, Self.monitorLoop, .{self});
    }

    /// Stop monitoring
    pub fn stop(self: *Self) void {
        if (!self.running.load(.monotonic)) {
            return;
        }

        self.running.store(false, .monotonic);
        if (self.monitor_thread) |thread| {
            thread.join();
            self.monitor_thread = null;
        }
    }

    /// Register a timeout context for monitoring
    pub fn registerContext(self: *Self, context: *TimeoutContext) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.active_contexts.append(self.allocator, context);
    }

    /// Unregister a timeout context
    pub fn unregisterContext(self: *Self, context: *TimeoutContext) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var i: usize = 0;
        while (i < self.active_contexts.items.len) {
            if (self.active_contexts.items[i] == context) {
                _ = self.active_contexts.swapRemove(i);
                return;
            }
            i += 1;
        }
    }

    /// Monitor loop that runs in a separate thread
    fn monitorLoop(self: *Self) void {
        while (self.running.load(.monotonic)) {
            std.Thread.sleep(100 * std.time.ns_per_ms); // Check every 100ms

            self.mutex.lock();
            var i: usize = 0;
            while (i < self.active_contexts.items.len) {
                const context = self.active_contexts.items[i];

                if (context.completed.load(.monotonic)) {
                    // Remove completed contexts
                    _ = self.active_contexts.swapRemove(i);
                    continue;
                }

                if (context.isTimedOut()) {
                    context.markTimedOut();
                    // Don't remove yet, let the test handler clean up
                }

                i += 1;
            }
            self.mutex.unlock();
        }
    }

    /// Get the effective timeout for a test
    pub fn getEffectiveTimeout(self: *Self, test_timeout_ms: u64, suite_timeout_ms: u64) u64 {
        // Priority: test timeout > suite timeout > global timeout
        if (test_timeout_ms > 0) {
            return test_timeout_ms;
        }

        if (suite_timeout_ms > 0) {
            return suite_timeout_ms;
        }

        if (self.global_config.enabled) {
            return self.global_config.default_timeout_ms;
        }

        return 0; // No timeout
    }
};

/// Suite timeout tracker
pub const SuiteTimeoutTracker = struct {
    allocator: std.mem.Allocator,
    suite_name: []const u8,
    timeout_ms: u64,
    start_time: i64,
    test_count: usize = 0,
    completed_count: usize = 0,
    timed_out: bool = false,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, suite_name: []const u8, timeout_ms: u64) Self {
        return .{
            .allocator = allocator,
            .suite_name = suite_name,
            .timeout_ms = timeout_ms,
            .start_time = std.time.milliTimestamp(),
        };
    }

    pub fn isTimedOut(self: *Self) bool {
        if (self.timed_out) {
            return true;
        }

        if (self.timeout_ms == 0) {
            return false;
        }

        const elapsed = self.getElapsedMs();
        self.timed_out = elapsed >= self.timeout_ms;
        return self.timed_out;
    }

    pub fn getElapsedMs(self: *Self) u64 {
        const now = std.time.milliTimestamp();
        return @intCast(now - self.start_time);
    }

    pub fn incrementTest(self: *Self) void {
        self.test_count += 1;
    }

    pub fn incrementCompleted(self: *Self) void {
        self.completed_count += 1;
    }

    pub fn getRemainingMs(self: *Self) u64 {
        if (self.timeout_ms == 0) {
            return 0;
        }

        const elapsed = self.getElapsedMs();
        if (elapsed >= self.timeout_ms) {
            return 0;
        }

        return self.timeout_ms - elapsed;
    }
};

// Tests
test "TimeoutContext basic timeout" {
    const allocator = std.testing.allocator;

    var context = TimeoutContext.init(allocator, 100);
    context.start();

    // Should not be timed out immediately
    try std.testing.expect(!context.isTimedOut());

    // Wait for timeout
    std.Thread.sleep(150 * std.time.ns_per_ms);

    // Should be timed out now
    try std.testing.expect(context.isTimedOut());
}

test "TimeoutContext extension" {
    const allocator = std.testing.allocator;

    var context = TimeoutContext.init(allocator, 100);
    context.start();

    // Extend timeout
    try context.extend(100);

    std.Thread.sleep(120 * std.time.ns_per_ms);

    // Should not be timed out (extended to 200ms total)
    try std.testing.expect(!context.isTimedOut());

    std.Thread.sleep(100 * std.time.ns_per_ms);

    // Should be timed out now
    try std.testing.expect(context.isTimedOut());
}

test "TimeoutContext completion before timeout" {
    const allocator = std.testing.allocator;

    var context = TimeoutContext.init(allocator, 1000);
    context.start();

    std.Thread.sleep(50 * std.time.ns_per_ms);

    context.complete();

    // Should not be timed out when completed
    try std.testing.expect(!context.isTimedOut());

    var result = try context.getResult();
    defer result.deinit();

    try std.testing.expectEqual(TimeoutStatus.completed_in_time, result.status);
    try std.testing.expect(result.elapsed_ms < 1000);
}

test "TimeoutContext get result" {
    const allocator = std.testing.allocator;

    var context = TimeoutContext.init(allocator, 100);
    context.start();

    std.Thread.sleep(150 * std.time.ns_per_ms);
    context.markTimedOut();

    var result = try context.getResult();
    defer result.deinit();

    try std.testing.expectEqual(TimeoutStatus.timed_out, result.status);
    try std.testing.expect(result.elapsed_ms >= 100);
}

test "TimeoutEnforcer effective timeout priority" {
    const allocator = std.testing.allocator;

    var enforcer = TimeoutEnforcer.init(allocator, .{
        .default_timeout_ms = 5000,
        .enabled = true,
    });
    defer enforcer.deinit();

    // Test timeout takes priority
    const timeout1 = enforcer.getEffectiveTimeout(1000, 2000);
    try std.testing.expectEqual(@as(u64, 1000), timeout1);

    // Suite timeout takes priority over global
    const timeout2 = enforcer.getEffectiveTimeout(0, 2000);
    try std.testing.expectEqual(@as(u64, 2000), timeout2);

    // Global timeout when no specific timeout
    const timeout3 = enforcer.getEffectiveTimeout(0, 0);
    try std.testing.expectEqual(@as(u64, 5000), timeout3);
}

test "SuiteTimeoutTracker basic functionality" {
    const allocator = std.testing.allocator;

    var tracker = SuiteTimeoutTracker.init(allocator, "test suite", 200);

    try std.testing.expect(!tracker.isTimedOut());

    tracker.incrementTest();
    tracker.incrementCompleted();

    std.Thread.sleep(250 * std.time.ns_per_ms);

    try std.testing.expect(tracker.isTimedOut());
}

test "SuiteTimeoutTracker remaining time" {
    const allocator = std.testing.allocator;

    var tracker = SuiteTimeoutTracker.init(allocator, "test suite", 1000);

    const remaining1 = tracker.getRemainingMs();
    try std.testing.expect(remaining1 > 900 and remaining1 <= 1000);

    std.Thread.sleep(100 * std.time.ns_per_ms);

    const remaining2 = tracker.getRemainingMs();
    try std.testing.expect(remaining2 < remaining1);
}
