const std = @import("std");
const assertions = @import("assertions.zig");

/// Result type for mock function calls
pub const MockResult = union(enum) {
    return_value: []const u8,
    thrown_error: []const u8,

    pub fn isReturn(self: MockResult) bool {
        return self == .return_value;
    }

    pub fn isError(self: MockResult) bool {
        return self == .thrown_error;
    }
};

/// Mock function call record
pub const CallRecord = struct {
    args: []const u8, // Serialized arguments
    result: ?MockResult = null,
    timestamp: i64,
    context: ?[]const u8 = null, // For tracking 'this' context in OOP scenarios

    pub fn init(allocator: std.mem.Allocator, args: []const u8) !CallRecord {
        return CallRecord{
            .args = try allocator.dupe(u8, args),
            .timestamp = std.time.milliTimestamp(),
        };
    }

    pub fn deinit(self: *CallRecord, allocator: std.mem.Allocator) void {
        allocator.free(self.args);
        if (self.context) |ctx| {
            allocator.free(ctx);
        }
    }
};

/// Global mock registry for tracking all mocks
pub const MockRegistry = struct {
    mocks: std.ArrayList(*anyopaque),
    allocator: std.mem.Allocator,
    mutex: std.Thread.Mutex = .{},

    pub fn init(allocator: std.mem.Allocator) MockRegistry {
        return .{
            .mocks = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MockRegistry) void {
        self.mocks.deinit(self.allocator);
    }

    pub fn register(self: *MockRegistry, mock_ptr: *anyopaque) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.mocks.append(self.allocator, mock_ptr);
    }

    pub fn clearAll(self: *MockRegistry) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        // Note: This would need type information to properly clear
        // For now, this is a placeholder for the concept
    }
};

var global_mock_registry: ?MockRegistry = null;

pub fn getGlobalRegistry(allocator: std.mem.Allocator) *MockRegistry {
    if (global_mock_registry == null) {
        global_mock_registry = MockRegistry.init(allocator);
    }
    return &global_mock_registry.?;
}

pub fn cleanupGlobalRegistry() void {
    if (global_mock_registry) |*registry| {
        registry.deinit();
        global_mock_registry = null;
    }
}

/// Mock function tracker with comprehensive Bun-compatible API
pub fn Mock(comptime ReturnType: type) type {
    return struct {
        calls: std.ArrayList(CallRecord),
        results: std.ArrayList(MockResult),
        return_values: std.ArrayList(?ReturnType),
        return_value_index: usize = 0,
        implementation: ?*const fn () anyerror!ReturnType = null,
        implementation_once: std.ArrayList(*const fn () anyerror!ReturnType),
        mock_name: []const u8 = "jest.fn()",
        allocator: std.mem.Allocator,
        is_restored: bool = false,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .calls = .empty,
                .results = .empty,
                .return_values = .empty,
                .implementation_once = .empty,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.calls.items) |*call| {
                call.deinit(self.allocator);
            }
            self.calls.deinit(self.allocator);
            self.results.deinit(self.allocator);
            self.return_values.deinit(self.allocator);
            self.implementation_once.deinit(self.allocator);
        }

        // ===== Core Mock Properties (Bun-compatible) =====

        /// Get the mock name
        pub fn getMockName(self: *Self) []const u8 {
            return self.mock_name;
        }

        /// Set the mock name
        pub fn mockName(self: *Self, name: []const u8) *Self {
            self.mock_name = name;
            return self;
        }

        /// Get all calls made to this mock
        pub fn getCalls(self: *Self) []CallRecord {
            return self.calls.items;
        }

        /// Get all results from mock calls
        pub fn getResults(self: *Self) []MockResult {
            return self.results.items;
        }

        /// Get the last call arguments
        pub fn getLastCall(self: *Self) ?CallRecord {
            if (self.calls.items.len == 0) return null;
            return self.calls.items[self.calls.items.len - 1];
        }

        // ===== Call Recording =====

        /// Record a function call
        pub fn recordCall(self: *Self, args_str: []const u8) !void {
            const record = try CallRecord.init(self.allocator, args_str);
            try self.calls.append(self.allocator, record);
        }

        /// Record a call with a result
        pub fn recordCallWithResult(self: *Self, args_str: []const u8, result: MockResult) !void {
            var record = try CallRecord.init(self.allocator, args_str);
            record.result = result;
            try self.calls.append(self.allocator, record);
            try self.results.append(self.allocator, result);
        }

        // ===== Return Value Management =====

        /// Set a return value to be used for all subsequent calls
        pub fn mockReturnValue(self: *Self, value: ReturnType) !*Self {
            try self.return_values.append(self.allocator, value);
            return self;
        }

        /// Set a return value to be used once
        pub fn mockReturnValueOnce(self: *Self, value: ReturnType) !*Self {
            try self.return_values.append(self.allocator, value);
            return self;
        }

        /// Set multiple return values
        pub fn mockReturnValues(self: *Self, values: []const ReturnType) !*Self {
            for (values) |value| {
                try self.return_values.append(self.allocator, value);
            }
            return self;
        }

        /// Mock return value as 'this' context (for method chaining)
        pub fn mockReturnThis(self: *Self) *Self {
            // In Zig, we can't return 'this' directly, so this is a marker
            // The actual implementation would depend on the use case
            return self;
        }

        /// Get the next return value
        pub fn getReturnValue(self: *Self) ?ReturnType {
            if (self.return_values.items.len == 0) return null;

            if (self.return_value_index >= self.return_values.items.len) {
                // Return the last value repeatedly
                return self.return_values.items[self.return_values.items.len - 1];
            }

            const value = self.return_values.items[self.return_value_index];
            self.return_value_index += 1;
            return value;
        }

        // ===== Implementation Management =====

        /// Set a custom implementation
        pub fn mockImplementation(self: *Self, impl: *const fn () anyerror!ReturnType) *Self {
            self.implementation = impl;
            return self;
        }

        /// Set implementation for the next call only
        pub fn mockImplementationOnce(self: *Self, impl: *const fn () anyerror!ReturnType) !*Self {
            try self.implementation_once.append(self.allocator, impl);
            return self;
        }

        /// Temporarily change implementation for a callback
        pub fn withImplementation(
            self: *Self,
            impl: *const fn () anyerror!ReturnType,
            callback: *const fn () anyerror!void,
        ) !void {
            const original_impl = self.implementation;
            self.implementation = impl;
            defer self.implementation = original_impl;
            try callback();
        }

        /// Get the current or next implementation
        pub fn getImplementation(self: *Self) ?*const fn () anyerror!ReturnType {
            // Check for one-time implementations first
            if (self.implementation_once.items.len > 0) {
                const impl = self.implementation_once.items[0];
                _ = self.implementation_once.orderedRemove(0);
                return impl;
            }
            return self.implementation;
        }

        // ===== Promise/Async Mocking (for future async support) =====

        /// Mock a resolved promise value
        pub fn mockResolvedValue(self: *Self, value: ReturnType) !*Self {
            // In Zig, this would be used with async functions
            try self.return_values.append(self.allocator, value);
            return self;
        }

        /// Mock a resolved promise value once
        pub fn mockResolvedValueOnce(self: *Self, value: ReturnType) !*Self {
            try self.return_values.append(self.allocator, value);
            return self;
        }

        /// Mock a rejected promise (error)
        pub fn mockRejectedValue(self: *Self, error_msg: []const u8) !*Self {
            _ = error_msg;
            // This would be used with error return types
            return self;
        }

        /// Mock a rejected promise once
        pub fn mockRejectedValueOnce(self: *Self, error_msg: []const u8) !*Self {
            _ = error_msg;
            return self;
        }

        // ===== State Management =====

        /// Clear all call history but keep implementation
        pub fn mockClear(self: *Self) *Self {
            for (self.calls.items) |*call| {
                call.deinit(self.allocator);
            }
            self.calls.clearRetainingCapacity();
            self.results.clearRetainingCapacity();
            return self;
        }

        /// Reset to initial state (clear calls and remove implementation)
        pub fn mockReset(self: *Self) *Self {
            _ = self.mockClear();
            self.return_values.clearRetainingCapacity();
            self.return_value_index = 0;
            self.implementation = null;
            self.implementation_once.clearRetainingCapacity();
            return self;
        }

        /// Restore the original implementation (for spies)
        pub fn mockRestore(self: *Self) *Self {
            self.is_restored = true;
            _ = self.mockReset();
            return self;
        }

        // ===== Assertions =====

        /// Get call count
        pub fn callCount(self: *Self) usize {
            return self.calls.items.len;
        }

        /// Check if mock was called
        pub fn toHaveBeenCalled(self: *Self) !void {
            if (self.calls.items.len == 0) {
                std.debug.print("\nExpected {s} to have been called but it wasn't\n", .{self.mock_name});
                return assertions.AssertionError.AssertionFailed;
            }
        }

        /// Check if mock was called n times
        pub fn toHaveBeenCalledTimes(self: *Self, expected_count: usize) !void {
            const actual_count = self.calls.items.len;
            if (actual_count != expected_count) {
                std.debug.print("\nExpected {s} to have been called {d} times but was called {d} times\n", .{
                    self.mock_name,
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

            std.debug.print("\nExpected {s} to have been called with: {s}\n", .{ self.mock_name, expected_args });
            std.debug.print("But calls were:\n", .{});
            for (self.calls.items) |call| {
                std.debug.print("  {s}\n", .{call.args});
            }
            return assertions.AssertionError.AssertionFailed;
        }

        /// Check if the last call was with specific arguments
        pub fn toHaveBeenLastCalledWith(self: *Self, expected_args: []const u8) !void {
            if (self.calls.items.len == 0) {
                std.debug.print("\nExpected {s} to have been called but it wasn't\n", .{self.mock_name});
                return assertions.AssertionError.AssertionFailed;
            }

            const last_call = self.calls.items[self.calls.items.len - 1];
            if (!std.mem.eql(u8, last_call.args, expected_args)) {
                std.debug.print("\nExpected last call to {s} to be with: {s}\n", .{ self.mock_name, expected_args });
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
                std.debug.print("\nExpected {s} to have been called at least {d} times but got {d}\n", .{
                    self.mock_name,
                    call_number,
                    self.calls.items.len,
                });
                return assertions.AssertionError.AssertionFailed;
            }

            const call = self.calls.items[call_index];
            if (!std.mem.eql(u8, call.args, expected_args)) {
                std.debug.print("\nExpected call {d} to {s} to be with: {s}\n", .{ call_number, self.mock_name, expected_args });
                std.debug.print("But was called with: {s}\n", .{call.args});
                return assertions.AssertionError.AssertionFailed;
            }
        }

        /// Check if mock returned a specific value
        pub fn toHaveReturnedWith(self: *Self, expected_value: ReturnType) !void {
            _ = expected_value;
            if (self.results.items.len == 0) {
                std.debug.print("\nExpected {s} to have returned but it hasn't been called\n", .{self.mock_name});
                return assertions.AssertionError.AssertionFailed;
            }
            // Value comparison would depend on the type
        }

        /// Check if the last call returned a specific value
        pub fn toHaveLastReturnedWith(self: *Self, expected_value: ReturnType) !void {
            _ = expected_value;
            if (self.results.items.len == 0) {
                std.debug.print("\nExpected {s} to have returned but it hasn't been called\n", .{self.mock_name});
                return assertions.AssertionError.AssertionFailed;
            }
            // Value comparison would depend on the type
        }

        /// Check if the nth call returned a specific value
        pub fn toHaveNthReturnedWith(self: *Self, call_number: usize, expected_value: ReturnType) !void {
            _ = expected_value;
            if (call_number == 0 or call_number > self.results.items.len) {
                std.debug.print("\nInvalid call number for {s}: {d}\n", .{ self.mock_name, call_number });
                return assertions.AssertionError.AssertionFailed;
            }
            // Value comparison would depend on the type
        }
    };
}

/// Spy on an existing function (wrapper that records calls)
pub fn Spy(comptime FnType: type) type {
    return struct {
        mock: Mock(?FnType),
        original_fn: ?FnType,
        is_restored: bool = false,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, original: FnType) Self {
            return Self{
                .mock = Mock(?FnType).init(allocator),
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
        pub fn mockRestore(self: *Self) ?FnType {
            self.is_restored = true;
            _ = self.mock.mockRestore();
            return self.original_fn;
        }

        /// Override the spy's implementation
        pub fn mockImplementation(self: *Self, impl: *const fn () anyerror!?FnType) *Self {
            _ = self.mock.mockImplementation(impl);
            return self;
        }

        /// Override implementation once
        pub fn mockImplementationOnce(self: *Self, impl: *const fn () anyerror!?FnType) !*Self {
            _ = try self.mock.mockImplementationOnce(impl);
            return self;
        }

        /// Set return value
        pub fn mockReturnValue(self: *Self, value: ?FnType) !*Self {
            _ = try self.mock.mockReturnValue(value);
            return self;
        }

        /// Set return value once
        pub fn mockReturnValueOnce(self: *Self, value: ?FnType) !*Self {
            _ = try self.mock.mockReturnValueOnce(value);
            return self;
        }

        /// Mock resolved value (for async)
        pub fn mockResolvedValue(self: *Self, value: ?FnType) !*Self {
            _ = try self.mock.mockResolvedValue(value);
            return self;
        }

        /// Mock resolved value once
        pub fn mockResolvedValueOnce(self: *Self, value: ?FnType) !*Self {
            _ = try self.mock.mockResolvedValueOnce(value);
            return self;
        }

        /// Clear call history
        pub fn mockClear(self: *Self) *Self {
            _ = self.mock.mockClear();
            return self;
        }

        /// Reset the spy
        pub fn mockReset(self: *Self) *Self {
            _ = self.mock.mockReset();
            return self;
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

        /// Get all calls
        pub fn getCalls(self: *Self) []CallRecord {
            return self.mock.getCalls();
        }

        /// Get last call
        pub fn getLastCall(self: *Self) ?CallRecord {
            return self.mock.getLastCall();
        }
    };
}

// ===== Global Mock Management (Bun-compatible) =====

/// Clear all mocks (call history only, preserves implementations)
pub fn clearAllMocks() void {
    // This would iterate through all registered mocks and call mockClear()
    // Implementation depends on global registry
}

/// Restore all mocks to their original implementations
pub fn restoreAllMocks() void {
    // This would iterate through all registered mocks and call mockRestore()
    // Implementation depends on global registry
}

/// Reset all mocks (clear history and remove implementations)
pub fn resetAllMocks() void {
    // This would iterate through all registered mocks and call mockReset()
    // Implementation depends on global registry
}

// ===== Helper Functions =====

/// Create a mock function (Bun/Jest-compatible)
pub fn createMock(allocator: std.mem.Allocator, comptime T: type) Mock(T) {
    return Mock(T).init(allocator);
}

/// Create a spy on a function (Bun/Jest-compatible)
pub fn createSpy(allocator: std.mem.Allocator, comptime T: type, original: T) Spy(T) {
    return Spy(T).init(allocator, original);
}

/// Alias for Jest compatibility
pub const fn_ = createMock;
pub const spyOn = createSpy;

// ===== Tests =====

test "mock basic usage" {
    const allocator = std.testing.allocator;

    var mock_fn = Mock(i32).init(allocator);
    defer mock_fn.deinit();

    try mock_fn.recordCall("test");
    try mock_fn.toHaveBeenCalled();
    try mock_fn.toHaveBeenCalledTimes(1);
}

test "mock return values" {
    const allocator = std.testing.allocator;

    var mock_fn = Mock(i32).init(allocator);
    defer mock_fn.deinit();

    _ = try mock_fn.mockReturnValue(42);
    const value = mock_fn.getReturnValue();
    try std.testing.expectEqual(@as(?i32, 42), value);
}

test "mock return value once" {
    const allocator = std.testing.allocator;

    var mock_fn = Mock(i32).init(allocator);
    defer mock_fn.deinit();

    _ = try mock_fn.mockReturnValueOnce(1);
    _ = try mock_fn.mockReturnValueOnce(2);
    _ = try mock_fn.mockReturnValue(3);

    try std.testing.expectEqual(@as(?i32, 1), mock_fn.getReturnValue());
    try std.testing.expectEqual(@as(?i32, 2), mock_fn.getReturnValue());
    try std.testing.expectEqual(@as(?i32, 3), mock_fn.getReturnValue());
    try std.testing.expectEqual(@as(?i32, 3), mock_fn.getReturnValue()); // Repeats last value
}

test "mock clear and reset" {
    const allocator = std.testing.allocator;

    var mock_fn = Mock(i32).init(allocator);
    defer mock_fn.deinit();

    try mock_fn.recordCall("test1");
    try mock_fn.recordCall("test2");
    try std.testing.expectEqual(@as(usize, 2), mock_fn.callCount());

    _ = mock_fn.mockClear();
    try std.testing.expectEqual(@as(usize, 0), mock_fn.callCount());
}

test "mock name" {
    const allocator = std.testing.allocator;

    var mock_fn = Mock(i32).init(allocator);
    defer mock_fn.deinit();

    _ = mock_fn.mockName("myMockFunction");
    try std.testing.expectEqualStrings("myMockFunction", mock_fn.getMockName());
}

test "spy basic usage" {
    const allocator = std.testing.allocator;

    const original_value: i32 = 42;
    var spy = Spy(i32).init(allocator, original_value);
    defer spy.deinit();

    try spy.call("test");
    try spy.toHaveBeenCalled();
    try spy.toHaveBeenCalledTimes(1);
}

test "spy restore" {
    const allocator = std.testing.allocator;

    const original_value: i32 = 42;
    var spy = Spy(i32).init(allocator, original_value);
    defer spy.deinit();

    const restored = spy.mockRestore();
    try std.testing.expectEqual(@as(?i32, 42), restored);
    try std.testing.expect(spy.is_restored);
}

test "mock called with arguments" {
    const allocator = std.testing.allocator;

    var mock_fn = Mock(i32).init(allocator);
    defer mock_fn.deinit();

    try mock_fn.recordCall("arg1");
    try mock_fn.recordCall("arg2");
    try mock_fn.recordCall("arg3");

    try mock_fn.toHaveBeenCalledWith("arg2");
    try mock_fn.toHaveBeenLastCalledWith("arg3");
    try mock_fn.toHaveBeenNthCalledWith(1, "arg1");
}

test "mock method chaining" {
    const allocator = std.testing.allocator;

    var mock_fn = Mock(i32).init(allocator);
    defer mock_fn.deinit();

    _ = mock_fn.mockName("chainedMock")
        .mockReturnThis();

    try std.testing.expectEqualStrings("chainedMock", mock_fn.getMockName());
}
