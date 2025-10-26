const std = @import("std");
const assertions = @import("assertions.zig");

/// Extended matchers for advanced assertions
pub const Matchers = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{ .allocator = allocator };
    }

    /// Check if a float is close to another value within a precision
    pub fn toBeCloseTo(actual: f64, expected: f64, precision: u32) !void {
        const tolerance = std.math.pow(f64, 10.0, -@as(f64, @floatFromInt(precision)));
        const diff = @abs(actual - expected);

        if (diff > tolerance) {
            std.debug.print("\nExpected {d} to be close to {d} (precision: {d})\n", .{ actual, expected, precision });
            std.debug.print("  Difference: {d}\n", .{diff});
            std.debug.print("  Tolerance:  {d}\n", .{tolerance});
            return assertions.AssertionError.AssertionFailed;
        }
    }

    /// Check if a value is NaN
    pub fn toBeNaN(actual: f64) !void {
        if (!std.math.isNan(actual)) {
            std.debug.print("\nExpected value to be NaN but got {d}\n", .{actual});
            return assertions.AssertionError.AssertionFailed;
        }
    }

    /// Check if a value is infinite
    pub fn toBeInfinite(actual: f64) !void {
        if (!std.math.isInf(actual)) {
            std.debug.print("\nExpected value to be infinite but got {d}\n", .{actual});
            return assertions.AssertionError.AssertionFailed;
        }
    }

    /// Check if a value is positive infinity
    pub fn toBePositiveInfinity(actual: f64) !void {
        if (!std.math.isPositiveInf(actual)) {
            std.debug.print("\nExpected value to be positive infinity but got {d}\n", .{actual});
            return assertions.AssertionError.AssertionFailed;
        }
    }

    /// Check if a value is negative infinity
    pub fn toBeNegativeInfinity(actual: f64) !void {
        if (!std.math.isNegativeInf(actual)) {
            std.debug.print("\nExpected value to be negative infinity but got {d}\n", .{actual});
            return assertions.AssertionError.AssertionFailed;
        }
    }
};

/// Struct matcher for checking properties
pub fn StructMatcher(comptime T: type) type {
    return struct {
        actual: T,
        allocator: std.mem.Allocator,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, actual: T) Self {
            return Self{
                .actual = actual,
                .allocator = allocator,
            };
        }

        /// Check if struct has a specific field with a value
        pub fn toHaveField(self: Self, comptime field_name: []const u8, expected_value: anytype) !void {
            const type_info = @typeInfo(T);
            if (type_info != .@"struct") {
                @compileError("toHaveField can only be used with struct types");
            }

            if (!@hasField(T, field_name)) {
                std.debug.print("\nExpected struct to have field '{s}'\n", .{field_name});
                return assertions.AssertionError.AssertionFailed;
            }

            const actual_value = @field(self.actual, field_name);
            if (!std.meta.eql(actual_value, expected_value)) {
                std.debug.print("\nExpected field '{s}' to equal {any} but got {any}\n", .{
                    field_name,
                    expected_value,
                    actual_value,
                });
                return assertions.AssertionError.AssertionFailed;
            }
        }

        /// Check if struct matches a subset of properties
        pub fn toMatchObject(self: Self, expected: anytype) !void {
            const ExpectedType = @TypeOf(expected);
            const expected_info = @typeInfo(ExpectedType);

            if (expected_info != .Struct) {
                @compileError("toMatchObject expects a struct as the expected value");
            }

            inline for (expected_info.Struct.fields) |field| {
                if (@hasField(T, field.name)) {
                    const actual_value = @field(self.actual, field.name);
                    const expected_value = @field(expected, field.name);

                    if (!std.meta.eql(actual_value, expected_value)) {
                        std.debug.print("\nObject does not match at field '{s}'\n", .{field.name});
                        std.debug.print("  Expected: {any}\n", .{expected_value});
                        std.debug.print("  Received: {any}\n", .{actual_value});
                        return assertions.AssertionError.AssertionFailed;
                    }
                } else {
                    std.debug.print("\nExpected object to have field '{s}' but it doesn't\n", .{field.name});
                    return assertions.AssertionError.AssertionFailed;
                }
            }
        }
    };
}

/// Array matcher for advanced array assertions
pub fn ArrayMatcher(comptime T: type) type {
    return struct {
        actual: []const T,
        allocator: std.mem.Allocator,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator, actual: []const T) Self {
            return Self{
                .actual = actual,
                .allocator = allocator,
            };
        }

        /// Check if array contains an item with deep equality
        pub fn toContainEqual(self: Self, expected_item: T) !void {
            for (self.actual) |item| {
                if (std.meta.eql(item, expected_item)) {
                    return;
                }
            }

            std.debug.print("\nExpected array to contain item {any}\n", .{expected_item});
            std.debug.print("  Array: {any}\n", .{self.actual});
            return assertions.AssertionError.AssertionFailed;
        }

        /// Alias for toContainEqual
        pub const toContain = toContainEqual;

        /// Check if array contains all specified items
        pub fn toContainAll(self: Self, expected_items: []const T) !void {
            for (expected_items) |expected_item| {
                var found = false;
                for (self.actual) |item| {
                    if (std.meta.eql(item, expected_item)) {
                        found = true;
                        break;
                    }
                }

                if (!found) {
                    std.debug.print("\nExpected array to contain item {any}\n", .{expected_item});
                    std.debug.print("  Array: {any}\n", .{self.actual});
                    return assertions.AssertionError.AssertionFailed;
                }
            }
        }

        /// Check if array has exact length
        pub fn toHaveLength(self: Self, expected_length: usize) !void {
            if (self.actual.len != expected_length) {
                std.debug.print("\nExpected array to have length {d} but got {d}\n", .{
                    expected_length,
                    self.actual.len,
                });
                return assertions.AssertionError.AssertionFailed;
            }
        }

        /// Check if array is empty
        pub fn toBeEmpty(self: Self) !void {
            if (self.actual.len != 0) {
                std.debug.print("\nExpected array to be empty but got length {d}\n", .{self.actual.len});
                return assertions.AssertionError.AssertionFailed;
            }
        }

        /// Check if array is sorted
        pub fn toBeSorted(self: Self) !void {
            if (self.actual.len <= 1) return;

            for (self.actual[0 .. self.actual.len - 1], 0..) |item, i| {
                const next_item = self.actual[i + 1];

                // This requires T to have comparison operators
                const type_info = @typeInfo(T);
                const is_comparable = switch (type_info) {
                    .Int, .Float, .ComptimeInt, .ComptimeFloat => true,
                    else => false,
                };

                if (!is_comparable) {
                    @compileError("toBeSorted requires a comparable type");
                }

                if (item > next_item) {
                    std.debug.print("\nExpected array to be sorted but found {any} > {any} at index {d}\n", .{
                        item,
                        next_item,
                        i,
                    });
                    return assertions.AssertionError.AssertionFailed;
                }
            }
        }
    };
}

/// Helper to create struct matcher
pub fn expectStruct(allocator: std.mem.Allocator, actual: anytype) StructMatcher(@TypeOf(actual)) {
    return StructMatcher(@TypeOf(actual)).init(allocator, actual);
}

/// Helper to create array matcher
pub fn expectArray(allocator: std.mem.Allocator, actual: anytype) ArrayMatcher(std.meta.Child(@TypeOf(actual.*))) {
    const ChildType = std.meta.Child(@TypeOf(actual.*));
    const slice: []const ChildType = actual;
    return ArrayMatcher(ChildType).init(allocator, slice);
}

test "toBeCloseTo" {
    const matchers = Matchers.init(std.testing.allocator);
    _ = matchers;
    try Matchers.toBeCloseTo(0.1 + 0.2, 0.3, 10);
    try Matchers.toBeCloseTo(1.0, 1.00001, 4);
}

test "toBeNaN" {
    try Matchers.toBeNaN(std.math.nan(f64));
}

test "array matchers" {
    const allocator = std.testing.allocator;
    const arr = [_]i32{ 1, 2, 3, 4, 5 };
    const matcher = expectArray(allocator, &arr);

    try matcher.toHaveLength(5);
    try matcher.toContainEqual(@as(i32, 3));
    try matcher.toContainAll(&[_]i32{ 1, 3, 5 });
}

test "struct matchers" {
    const allocator = std.testing.allocator;

    const Person = struct {
        name: []const u8,
        age: u32,
        email: []const u8,
    };

    const person = Person{
        .name = "Alice",
        .age = 30,
        .email = "alice@example.com",
    };

    const matcher = expectStruct(allocator, person);
    try matcher.toHaveField("name", "Alice");
    try matcher.toHaveField("age", @as(u32, 30));
}
