const std = @import("std");
const ztf = @import("zig_test_framework");

test "assertions report equality failures and support negation" {
    const allocator = std.testing.allocator;
    try ztf.expect(allocator, @as(i32, 42)).toBe(42);
    try ztf.expect(allocator, @as(i32, 42)).not().toBe(7);
    try std.testing.expectError(ztf.AssertionError.AssertionFailed, ztf.expect(allocator, @as(i32, 42)).toBe(7));
}

test "assertions cover comparisons and optionals" {
    const allocator = std.testing.allocator;
    try ztf.expect(allocator, @as(i32, 10)).toBeGreaterThan(5);
    try ztf.expect(allocator, @as(i32, 5)).toBeLessThan(10);
    try ztf.expect(allocator, @as(?i32, null)).toBeNull();
    try ztf.expect(allocator, @as(?i32, 3)).toBeDefined();
}

test "assertions cover strings and error unions" {
    const allocator = std.testing.allocator;
    const Failing = struct {
        fn call() !void {
            return error.ExpectedFailure;
        }
    };
    try ztf.expect(allocator, "zig test framework").toContain("test");
    try ztf.expect(allocator, "zig test framework").toStartWith("zig");
    try ztf.expect(allocator, "zig test framework").toEndWith("framework");
    try ztf.expect(allocator, Failing.call).toThrowError(error.ExpectedFailure);
}
