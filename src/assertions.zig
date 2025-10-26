const std = @import("std");

/// Custom error for assertion failures
pub const AssertionError = error{
    AssertionFailed,
};

/// Expectation struct that holds the actual value and provides assertion methods
pub fn Expectation(comptime T: type) type {
    return struct {
        actual: T,
        allocator: std.mem.Allocator,
        negated: bool = false,
        custom_message: ?[]const u8 = null,

        const Self = @This();

        /// Create a negated expectation
        pub fn not(self: Self) Self {
            return Self{
                .actual = self.actual,
                .allocator = self.allocator,
                .negated = !self.negated,
                .custom_message = self.custom_message,
            };
        }

        /// Set a custom error message
        pub fn withMessage(self: Self, message: []const u8) Self {
            return Self{
                .actual = self.actual,
                .allocator = self.allocator,
                .negated = self.negated,
                .custom_message = message,
            };
        }

        /// Assert strict equality (===)
        pub fn toBe(self: Self, expected: T) !void {
            const equal = std.meta.eql(self.actual, expected);
            if (self.negated) {
                if (equal) {
                    if (self.custom_message) |msg| {
                        std.debug.print("\nAssertion Failed: {s}\n", .{msg});
                    } else {
                        std.debug.print("\nExpected not to be equal\n", .{});
                        std.debug.print("  Received: {any}\n", .{self.actual});
                    }
                    return AssertionError.AssertionFailed;
                }
            } else {
                if (!equal) {
                    if (self.custom_message) |msg| {
                        std.debug.print("\nAssertion Failed: {s}\n", .{msg});
                    } else {
                        std.debug.print("\nExpected values to be equal\n", .{});
                        std.debug.print("  Expected: {any}\n", .{expected});
                        std.debug.print("  Received: {any}\n", .{self.actual});
                    }
                    return AssertionError.AssertionFailed;
                }
            }
        }

        /// Assert deep equality
        pub fn toEqual(self: Self, expected: T) !void {
            // For now, toEqual is the same as toBe in Zig
            // In more complex scenarios, this could handle deep struct comparison
            try self.toBe(expected);
        }

        /// Assert value is true (for bools)
        pub fn toBeTruthy(self: Self) !void {
            if (T != bool) {
                @compileError("toBeTruthy can only be used with boolean values");
            }
            if (self.negated) {
                if (self.actual) {
                    std.debug.print("\nExpected value to be falsy but got true\n", .{});
                    return AssertionError.AssertionFailed;
                }
            } else {
                if (!self.actual) {
                    std.debug.print("\nExpected value to be truthy but got false\n", .{});
                    return AssertionError.AssertionFailed;
                }
            }
        }

        /// Assert value is false (for bools)
        pub fn toBeFalsy(self: Self) !void {
            if (T != bool) {
                @compileError("toBeFalsy can only be used with boolean values");
            }
            if (self.negated) {
                if (!self.actual) {
                    std.debug.print("\nExpected value to be truthy but got false\n", .{});
                    return AssertionError.AssertionFailed;
                }
            } else {
                if (self.actual) {
                    std.debug.print("\nExpected value to be falsy but got true\n", .{});
                    return AssertionError.AssertionFailed;
                }
            }
        }

        /// Assert value is null (for optionals)
        pub fn toBeNull(self: Self) !void {
            const type_info = @typeInfo(T);
            if (type_info != .optional) {
                @compileError("toBeNull can only be used with optional types");
            }
            const is_null = self.actual == null;
            if (self.negated) {
                if (is_null) {
                    std.debug.print("\nExpected value not to be null\n", .{});
                    return AssertionError.AssertionFailed;
                }
            } else {
                if (!is_null) {
                    std.debug.print("\nExpected value to be null\n", .{});
                    std.debug.print("  Received: {any}\n", .{self.actual});
                    return AssertionError.AssertionFailed;
                }
            }
        }

        /// Assert value is not null (for optionals)
        pub fn toBeDefined(self: Self) !void {
            const type_info = @typeInfo(T);
            if (type_info != .optional) {
                // Non-optional types are always defined
                if (self.negated) {
                    std.debug.print("\nExpected value to be null but it's a non-optional type\n", .{});
                    return AssertionError.AssertionFailed;
                }
                return;
            }
            const is_null = self.actual == null;
            if (self.negated) {
                if (!is_null) {
                    std.debug.print("\nExpected value to be undefined/null\n", .{});
                    return AssertionError.AssertionFailed;
                }
            } else {
                if (is_null) {
                    std.debug.print("\nExpected value to be defined (not null)\n", .{});
                    return AssertionError.AssertionFailed;
                }
            }
        }

        /// Assert greater than
        pub fn toBeGreaterThan(self: Self, expected: T) !void {
            const type_info = @typeInfo(T);
            const is_numeric = switch (type_info) {
                .int, .float, .comptime_int, .comptime_float => true,
                else => false,
            };
            if (!is_numeric) {
                @compileError("toBeGreaterThan can only be used with numeric types");
            }

            const is_greater = self.actual > expected;
            if (self.negated) {
                if (is_greater) {
                    std.debug.print("\nExpected {any} not to be greater than {any}\n", .{ self.actual, expected });
                    return AssertionError.AssertionFailed;
                }
            } else {
                if (!is_greater) {
                    std.debug.print("\nExpected {any} to be greater than {any}\n", .{ self.actual, expected });
                    return AssertionError.AssertionFailed;
                }
            }
        }

        /// Assert greater than or equal
        pub fn toBeGreaterThanOrEqual(self: Self, expected: T) !void {
            const type_info = @typeInfo(T);
            const is_numeric = switch (type_info) {
                .int, .float, .comptime_int, .comptime_float => true,
                else => false,
            };
            if (!is_numeric) {
                @compileError("toBeGreaterThanOrEqual can only be used with numeric types");
            }

            const is_gte = self.actual >= expected;
            if (self.negated) {
                if (is_gte) {
                    std.debug.print("\nExpected {any} not to be >= {any}\n", .{ self.actual, expected });
                    return AssertionError.AssertionFailed;
                }
            } else {
                if (!is_gte) {
                    std.debug.print("\nExpected {any} to be >= {any}\n", .{ self.actual, expected });
                    return AssertionError.AssertionFailed;
                }
            }
        }

        /// Assert less than
        pub fn toBeLessThan(self: Self, expected: T) !void {
            const type_info = @typeInfo(T);
            const is_numeric = switch (type_info) {
                .int, .float, .comptime_int, .comptime_float => true,
                else => false,
            };
            if (!is_numeric) {
                @compileError("toBeLessThan can only be used with numeric types");
            }

            const is_less = self.actual < expected;
            if (self.negated) {
                if (is_less) {
                    std.debug.print("\nExpected {any} not to be less than {any}\n", .{ self.actual, expected });
                    return AssertionError.AssertionFailed;
                }
            } else {
                if (!is_less) {
                    std.debug.print("\nExpected {any} to be less than {any}\n", .{ self.actual, expected });
                    return AssertionError.AssertionFailed;
                }
            }
        }

        /// Assert less than or equal
        pub fn toBeLessThanOrEqual(self: Self, expected: T) !void {
            const type_info = @typeInfo(T);
            const is_numeric = switch (type_info) {
                .int, .float, .comptime_int, .comptime_float => true,
                else => false,
            };
            if (!is_numeric) {
                @compileError("toBeLessThanOrEqual can only be used with numeric types");
            }

            const is_lte = self.actual <= expected;
            if (self.negated) {
                if (is_lte) {
                    std.debug.print("\nExpected {any} not to be <= {any}\n", .{ self.actual, expected });
                    return AssertionError.AssertionFailed;
                }
            } else {
                if (!is_lte) {
                    std.debug.print("\nExpected {any} to be <= {any}\n", .{ self.actual, expected });
                    return AssertionError.AssertionFailed;
                }
            }
        }

        /// Assert that a function throws an error
        /// Usage: try expect(allocator, myFunction).toThrow()
        pub fn toThrow(self: Self) !void {
            // This function expects T to be a function that returns an error union
            // Call the function and check if it returns an error
            const result = if (@typeInfo(T) == .@"fn") blk: {
                // For function types, we need to call them
                break :blk self.actual();
            } else blk: {
                // For error unions, just use the value
                break :blk self.actual;
            };

            if (self.negated) {
                // Should NOT throw
                if (result) |_| {
                    // No error thrown - this is what we want for .not()
                    return;
                } else |_| {
                    std.debug.print("\nExpected function not to throw an error, but it did\n", .{});
                    return AssertionError.AssertionFailed;
                }
            } else {
                // Should throw
                if (result) |_| {
                    std.debug.print("\nExpected function to throw an error, but it succeeded\n", .{});
                    return AssertionError.AssertionFailed;
                } else |_| {
                    // Error was thrown - this is what we want
                    return;
                }
            }
        }

        /// Assert that a function throws a specific error
        /// Usage: try expect(allocator, myFunction).toThrowError(error.MyError)
        pub fn toThrowError(self: Self, expected_error: anyerror) !void {
            const result = if (@typeInfo(T) == .@"fn") blk: {
                break :blk self.actual();
            } else blk: {
                break :blk self.actual;
            };

            if (self.negated) {
                // Should NOT throw this specific error
                if (result) |_| {
                    return; // No error, good
                } else |err| {
                    if (err == expected_error) {
                        std.debug.print("\nExpected function not to throw error.{s}, but it did\n", .{@errorName(expected_error)});
                        return AssertionError.AssertionFailed;
                    }
                    return; // Different error, that's fine
                }
            } else {
                // Should throw this specific error
                if (result) |_| {
                    std.debug.print("\nExpected function to throw error.{s}, but it succeeded\n", .{@errorName(expected_error)});
                    return AssertionError.AssertionFailed;
                } else |err| {
                    if (err != expected_error) {
                        std.debug.print("\nExpected function to throw error.{s}, but it threw error.{s}\n", .{ @errorName(expected_error), @errorName(err) });
                        return AssertionError.AssertionFailed;
                    }
                    return; // Correct error thrown
                }
            }
        }
    };
}

/// String-specific expectation methods
pub const StringExpectation = struct {
    actual: []const u8,
    allocator: std.mem.Allocator,
    negated: bool = false,
    custom_message: ?[]const u8 = null,

    const Self = @This();

    pub fn not(self: Self) Self {
        return Self{
            .actual = self.actual,
            .allocator = self.allocator,
            .negated = !self.negated,
            .custom_message = self.custom_message,
        };
    }

    pub fn withMessage(self: Self, message: []const u8) Self {
        return Self{
            .actual = self.actual,
            .allocator = self.allocator,
            .negated = self.negated,
            .custom_message = message,
        };
    }

    pub fn toBe(self: Self, expected: []const u8) !void {
        const equal = std.mem.eql(u8, self.actual, expected);
        if (self.negated) {
            if (equal) {
                if (self.custom_message) |msg| {
                    std.debug.print("\nAssertion Failed: {s}\n", .{msg});
                } else {
                    std.debug.print("\nExpected strings not to be equal\n", .{});
                    std.debug.print("  Received: \"{s}\"\n", .{self.actual});
                }
                return AssertionError.AssertionFailed;
            }
        } else {
            if (!equal) {
                if (self.custom_message) |msg| {
                    std.debug.print("\nAssertion Failed: {s}\n", .{msg});
                } else {
                    std.debug.print("\nExpected strings to be equal\n", .{});
                    std.debug.print("  Expected: \"{s}\"\n", .{expected});
                    std.debug.print("  Received: \"{s}\"\n", .{self.actual});
                }
                return AssertionError.AssertionFailed;
            }
        }
    }

    pub fn toEqual(self: Self, expected: []const u8) !void {
        try self.toBe(expected);
    }

    pub fn toContain(self: Self, substring: []const u8) !void {
        const contains = std.mem.indexOf(u8, self.actual, substring) != null;
        if (self.negated) {
            if (contains) {
                std.debug.print("\nExpected \"{s}\" not to contain \"{s}\"\n", .{ self.actual, substring });
                return AssertionError.AssertionFailed;
            }
        } else {
            if (!contains) {
                std.debug.print("\nExpected \"{s}\" to contain \"{s}\"\n", .{ self.actual, substring });
                return AssertionError.AssertionFailed;
            }
        }
    }

    pub fn toStartWith(self: Self, prefix: []const u8) !void {
        const starts_with = std.mem.startsWith(u8, self.actual, prefix);
        if (self.negated) {
            if (starts_with) {
                std.debug.print("\nExpected \"{s}\" not to start with \"{s}\"\n", .{ self.actual, prefix });
                return AssertionError.AssertionFailed;
            }
        } else {
            if (!starts_with) {
                std.debug.print("\nExpected \"{s}\" to start with \"{s}\"\n", .{ self.actual, prefix });
                return AssertionError.AssertionFailed;
            }
        }
    }

    pub fn toEndWith(self: Self, suffix: []const u8) !void {
        const ends_with = std.mem.endsWith(u8, self.actual, suffix);
        if (self.negated) {
            if (ends_with) {
                std.debug.print("\nExpected \"{s}\" not to end with \"{s}\"\n", .{ self.actual, suffix });
                return AssertionError.AssertionFailed;
            }
        } else {
            if (!ends_with) {
                std.debug.print("\nExpected \"{s}\" to end with \"{s}\"\n", .{ self.actual, suffix });
                return AssertionError.AssertionFailed;
            }
        }
    }

    pub fn toHaveLength(self: Self, expected_length: usize) !void {
        const actual_length = self.actual.len;
        if (self.negated) {
            if (actual_length == expected_length) {
                std.debug.print("\nExpected string not to have length {d} but it does\n", .{expected_length});
                return AssertionError.AssertionFailed;
            }
        } else {
            if (actual_length != expected_length) {
                std.debug.print("\nExpected string to have length {d} but got {d}\n", .{ expected_length, actual_length });
                std.debug.print("  String: \"{s}\"\n", .{self.actual});
                return AssertionError.AssertionFailed;
            }
        }
    }

    pub fn toBeEmpty(self: Self) !void {
        const is_empty = self.actual.len == 0;
        if (self.negated) {
            if (is_empty) {
                std.debug.print("\nExpected string not to be empty\n", .{});
                return AssertionError.AssertionFailed;
            }
        } else {
            if (!is_empty) {
                std.debug.print("\nExpected string to be empty but got \"{s}\"\n", .{self.actual});
                return AssertionError.AssertionFailed;
            }
        }
    }
};

/// Slice expectation methods
pub fn SliceExpectation(comptime T: type) type {
    return struct {
        actual: []const T,
        allocator: std.mem.Allocator,
        negated: bool = false,
        custom_message: ?[]const u8 = null,

        const Self = @This();

        pub fn not(self: Self) Self {
            return Self{
                .actual = self.actual,
                .allocator = self.allocator,
                .negated = !self.negated,
                .custom_message = self.custom_message,
            };
        }

        pub fn toHaveLength(self: Self, expected_length: usize) !void {
            const actual_length = self.actual.len;
            if (self.negated) {
                if (actual_length == expected_length) {
                    std.debug.print("\nExpected slice not to have length {d} but it does\n", .{expected_length});
                    return AssertionError.AssertionFailed;
                }
            } else {
                if (actual_length != expected_length) {
                    std.debug.print("\nExpected slice to have length {d} but got {d}\n", .{ expected_length, actual_length });
                    return AssertionError.AssertionFailed;
                }
            }
        }

        pub fn toContain(self: Self, item: T) !void {
            var contains = false;
            for (self.actual) |element| {
                if (std.meta.eql(element, item)) {
                    contains = true;
                    break;
                }
            }
            if (self.negated) {
                if (contains) {
                    std.debug.print("\nExpected slice not to contain {any}\n", .{item});
                    return AssertionError.AssertionFailed;
                }
            } else {
                if (!contains) {
                    std.debug.print("\nExpected slice to contain {any}\n", .{item});
                    return AssertionError.AssertionFailed;
                }
            }
        }

        pub fn toBeEmpty(self: Self) !void {
            const is_empty = self.actual.len == 0;
            if (self.negated) {
                if (is_empty) {
                    std.debug.print("\nExpected slice not to be empty\n", .{});
                    return AssertionError.AssertionFailed;
                }
            } else {
                if (!is_empty) {
                    std.debug.print("\nExpected slice to be empty but got length {d}\n", .{self.actual.len});
                    return AssertionError.AssertionFailed;
                }
            }
        }
    };
}

/// Create an expectation for a value
pub fn expect(allocator: std.mem.Allocator, actual: anytype) blk: {
    const T = @TypeOf(actual);
    if (T == []const u8) break :blk StringExpectation;

    const type_info = @typeInfo(T);
    if (type_info == .pointer) {
        const ptr_info = type_info.pointer;
        // String slice
        if (ptr_info.size == .slice and ptr_info.child == u8) break :blk StringExpectation;
        // String literal (pointer to array of u8)
        const child_info = @typeInfo(ptr_info.child);
        if (child_info == .array and child_info.array.child == u8) break :blk StringExpectation;
        // Other u8 pointer
        if (ptr_info.child == u8) break :blk StringExpectation;
        // General slice
        if (ptr_info.size == .slice) break :blk SliceExpectation(ptr_info.child);
    }
    break :blk Expectation(T);
} {
    if (@TypeOf(actual) == []const u8) {
        return StringExpectation{
            .actual = actual,
            .allocator = allocator,
        };
    }

    const type_info = @typeInfo(@TypeOf(actual));
    if (type_info == .pointer) {
        const ptr_info = type_info.pointer;
        // Check for u8 slices/pointers (strings)
        if (ptr_info.child == u8) {
            return StringExpectation{
                .actual = actual,
                .allocator = allocator,
            };
        }
        // Check for array of u8 (string literals like "hello")
        const child_info = @typeInfo(ptr_info.child);
        if (child_info == .array and child_info.array.child == u8) {
            return StringExpectation{
                .actual = actual,
                .allocator = allocator,
            };
        }
        if (ptr_info.size == .slice) {
            return SliceExpectation(ptr_info.child){
                .actual = actual,
                .allocator = allocator,
            };
        }
    }

    return Expectation(@TypeOf(actual)){
        .actual = actual,
        .allocator = allocator,
    };
}

test "expect basic equality" {
    const allocator = std.testing.allocator;
    try expect(allocator, 5).toBe(5);
    try expect(allocator, true).toBe(true);
}

test "expect with not modifier" {
    const allocator = std.testing.allocator;
    try expect(allocator, 5).not().toBe(3);
    try expect(allocator, false).not().toBe(true);
}

test "expect string operations" {
    const allocator = std.testing.allocator;
    try expect(allocator, "hello").toBe("hello");
    try expect(allocator, "hello world").toContain("world");
    try expect(allocator, "hello").toStartWith("hel");
    try expect(allocator, "hello").toEndWith("lo");
    try expect(allocator, "hello").toHaveLength(5);
}

test "expect comparisons" {
    const allocator = std.testing.allocator;
    try expect(allocator, 10).toBeGreaterThan(5);
    try expect(allocator, 10).toBeGreaterThanOrEqual(10);
    try expect(allocator, 5).toBeLessThan(10);
    try expect(allocator, 5).toBeLessThanOrEqual(5);
}

test "expect error assertions" {
    const allocator = std.testing.allocator;

    // Test function that throws an error
    const ThrowsError = struct {
        fn call() !void {
            return error.TestError;
        }
    };

    // Test function that succeeds
    const Succeeds = struct {
        fn call() !void {
            return;
        }
    };

    // Should throw any error
    try expect(allocator, ThrowsError.call).toThrow();

    // Should not throw
    try expect(allocator, Succeeds.call).not().toThrow();

    // Should throw specific error
    try expect(allocator, ThrowsError.call).toThrowError(error.TestError);

    // Should not throw specific error (throws different error)
    const ThrowsDifferent = struct {
        fn call() !void {
            return error.DifferentError;
        }
    };
    try expect(allocator, ThrowsDifferent.call).not().toThrowError(error.TestError);
}
