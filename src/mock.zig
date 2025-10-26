const std = @import("std");
const assertions = @import("assertions.zig");

/// Mock function call record
pub const CallRecord = struct {
    args: []const u8, // Serialized arguments
    return_value: ?[]const u8 = null,
    timestamp: i64,

    pub fn init(allocator: std.mem.Allocator, args: []const u8) !CallRecord {
        return CallRecord{
            .args = try allocator.dupe(u8, args),
            .timestamp = std.time.milliTimestamp(),
        };
    }

    pub fn deinit(self: *CallRecord, allocator: std.mem.Allocator) void {
        allocator.free(self.args);
        if (self.return_value) |rv| {
            allocator.free(rv);
        }
    }
};

/// Mock function tracker
pub fn Mock(comptime FnType: type) type {
    return struct {
        calls: std.ArrayList(CallRecord),
        return_values: std.ArrayList(?FnType),
        return_value_index: usize = 0,
        implementation: ?FnType = null,
        allocator: std.mem.Allocator,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .calls = .empty,
                .return_values = .empty,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.calls.items) |*call| {
                call.deinit(self.allocator);
            }
            self.calls.deinit(self.allocator);
            self.return_values.deinit(self.allocator);
        }

        /// Record a function call
        pub fn recordCall(self: *Self, args_str: []const u8) !void {
            const record = try CallRecord.init(self.allocator, args_str);
            try self.calls.append(self.allocator, record);
        }

        /// Set a return value to be used for the next call
        pub fn mockReturnValue(self: *Self, value: FnType) !void {
            try self.return_values.append(self.allocator, value);
        }

        /// Set a return value to be used once
        pub fn mockReturnValueOnce(self: *Self, value: FnType) !void {
            try self.mockReturnValue(value);
        }

        /// Set multiple return values
        pub fn mockReturnValues(self: *Self, values: []const FnType) !void {
            for (values) |value| {
                try self.return_values.append(self.allocator, value);
            }
        }

        /// Set a custom implementation
        pub fn mockImplementation(self: *Self, impl: FnType) void {
            self.implementation = impl;
        }

        /// Get the next return value
        pub fn getReturnValue(self: *Self) ?FnType {
            if (self.return_values.items.len == 0) return null;

            if (self.return_value_index >= self.return_values.items.len) {
                // Return the last value repeatedly
                return self.return_values.items[self.return_values.items.len - 1];
            }

            const value = self.return_values.items[self.return_value_index];
            self.return_value_index += 1;
            return value;
        }

        /// Clear all call history
        pub fn mockClear(self: *Self) void {
            for (self.calls.items) |*call| {
                call.deinit(self.allocator);
            }
            self.calls.clearRetainingCapacity();
        }

        /// Reset to initial state
        pub fn mockReset(self: *Self) void {
            self.mockClear();
            self.return_values.clearRetainingCapacity();
            self.return_value_index = 0;
            self.implementation = null;
        }

        /// Get call count
        pub fn callCount(self: *Self) usize {
            return self.calls.items.len;
        }

        /// Check if mock was called
        pub fn toHaveBeenCalled(self: *Self) !void {
            if (self.calls.items.len == 0) {
                std.debug.print("\nExpected mock to have been called but it wasn't\n", .{});
                return assertions.AssertionError.AssertionFailed;
            }
        }

        /// Check if mock was called n times
        pub fn toHaveBeenCalledTimes(self: *Self, expected_count: usize) !void {
            const actual_count = self.calls.items.len;
            if (actual_count != expected_count) {
                std.debug.print("\nExpected mock to have been called {d} times but was called {d} times\n", .{
                    expected_count,
                    actual_count,
                });
                return assertions.AssertionError.AssertionFailed;
            }
        }

        /// Check if mock was called with specific arguments
        pub fn toHaveBeenCalledWith(self: *Self, expected_args: []const u8) !void {
            for (self.calls.items) |call| {
                if (std.mem.eql(u8, call.args, expected_args)) {
                    return;
                }
            }

            std.debug.print("\nExpected mock to have been called with: {s}\n", .{expected_args});
            std.debug.print("But calls were:\n", .{});
            for (self.calls.items) |call| {
                std.debug.print("  {s}\n", .{call.args});
            }
            return assertions.AssertionError.AssertionFailed;
        }

        /// Check if the last call was with specific arguments
        pub fn toHaveBeenLastCalledWith(self: *Self, expected_args: []const u8) !void {
            if (self.calls.items.len == 0) {
                std.debug.print("\nExpected mock to have been called but it wasn't\n", .{});
                return assertions.AssertionError.AssertionFailed;
            }

            const last_call = self.calls.items[self.calls.items.len - 1];
            if (!std.mem.eql(u8, last_call.args, expected_args)) {
                std.debug.print("\nExpected last call to be with: {s}\n", .{expected_args});
                std.debug.print("But was called with: {s}\n", .{last_call.args});
                return assertions.AssertionError.AssertionFailed;
            }
        }

        /// Check if the nth call was with specific arguments (1-indexed)
        pub fn toHaveBeenNthCalledWith(self: *Self, call_number: usize, expected_args: []const u8) !void {
            if (call_number == 0) {
                std.debug.print("\nCall number must be >= 1\n", .{});
                return assertions.AssertionError.AssertionFailed;
            }

            const call_index = call_number - 1;
            if (call_index >= self.calls.items.len) {
                std.debug.print("\nExpected at least {d} calls but got {d}\n", .{
                    call_number,
                    self.calls.items.len,
                });
                return assertions.AssertionError.AssertionFailed;
            }

            const call = self.calls.items[call_index];
            if (!std.mem.eql(u8, call.args, expected_args)) {
                std.debug.print("\nExpected call {d} to be with: {s}\n", .{ call_number, expected_args });
                std.debug.print("But was called with: {s}\n", .{call.args});
                return assertions.AssertionError.AssertionFailed;
            }
        }
    };
}

/// Spy on an existing function (wrapper that records calls)
pub fn Spy(comptime FnType: type) type {
    return struct {
        mock: Mock(FnType),
        original_fn: FnType,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, original: FnType) Self {
            return Self{
                .mock = Mock(FnType).init(allocator),
                .original_fn = original,
            };
        }

        pub fn deinit(self: *Self) void {
            self.mock.deinit();
        }

        /// Record a call and call the original function
        pub fn call(self: *Self, args_str: []const u8) !void {
            try self.mock.recordCall(args_str);
        }

        /// Get call count
        pub fn callCount(self: *Self) usize {
            return self.mock.callCount();
        }

        /// Restore the original function
        pub fn mockRestore(self: *Self) FnType {
            return self.original_fn;
        }

        // Delegate assertion methods to the underlying mock
        pub fn toHaveBeenCalled(self: *Self) !void {
            try self.mock.toHaveBeenCalled();
        }

        pub fn toHaveBeenCalledTimes(self: *Self, expected_count: usize) !void {
            try self.mock.toHaveBeenCalledTimes(expected_count);
        }

        pub fn toHaveBeenCalledWith(self: *Self, expected_args: []const u8) !void {
            try self.mock.toHaveBeenCalledWith(expected_args);
        }

        pub fn toHaveBeenLastCalledWith(self: *Self, expected_args: []const u8) !void {
            try self.mock.toHaveBeenLastCalledWith(expected_args);
        }

        pub fn toHaveBeenNthCalledWith(self: *Self, call_number: usize, expected_args: []const u8) !void {
            try self.mock.toHaveBeenNthCalledWith(call_number, expected_args);
        }
    };
}

/// Simple mock function helpers
pub fn createMock(allocator: std.mem.Allocator, comptime T: type) Mock(T) {
    return Mock(T).init(allocator);
}

pub fn createSpy(allocator: std.mem.Allocator, comptime T: type, original: T) Spy(T) {
    return Spy(T).init(allocator, original);
}

test "mock basic usage" {
    const allocator = std.testing.allocator;

    var mock = Mock(i32).init(allocator);
    defer mock.deinit();

    try mock.recordCall("test");
    try mock.toHaveBeenCalled();
    try mock.toHaveBeenCalledTimes(1);
}

test "mock return values" {
    const allocator = std.testing.allocator;

    var mock = Mock(i32).init(allocator);
    defer mock.deinit();

    try mock.mockReturnValue(42);
    const value = mock.getReturnValue();
    try std.testing.expectEqual(@as(?i32, 42), value);
}

test "mock clear and reset" {
    const allocator = std.testing.allocator;

    var mock = Mock(i32).init(allocator);
    defer mock.deinit();

    try mock.recordCall("test1");
    try mock.recordCall("test2");
    try std.testing.expectEqual(@as(usize, 2), mock.callCount());

    mock.mockClear();
    try std.testing.expectEqual(@as(usize, 0), mock.callCount());
}
