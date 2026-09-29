const std = @import("std");
const ztf = @import("zig_test_framework");

test "numeric matchers accept special and approximate values" {
    try ztf.toBeCloseTo(0.1 + 0.2, 0.3, 10);
    try ztf.toBeNaN(std.math.nan(f64));
    try ztf.toBeInfinite(std.math.inf(f64));
    try std.testing.expectError(ztf.AssertionError.AssertionFailed, ztf.toBeCloseTo(1.0, 2.0, 4));
}

test "array matchers inspect contents and length" {
    const values = [_]i32{ 1, 2, 3, 5, 8 };
    const matcher = ztf.expectArray(std.testing.allocator, &values);
    try matcher.toHaveLength(5);
    try matcher.toContain(5);
    try matcher.toContainAll(&.{ 1, 3, 8 });
    try std.testing.expectError(ztf.AssertionError.AssertionFailed, matcher.toContain(13));
}

test "struct matchers inspect named fields" {
    const User = struct { name: []const u8, active: bool };
    const matcher = ztf.expectStruct(std.testing.allocator, User{ .name = "Ada", .active = true });
    try matcher.toHaveField("name", "Ada");
    try matcher.toHaveField("active", true);
    try std.testing.expectError(ztf.AssertionError.AssertionFailed, matcher.toHaveField("name", "Grace"));
}
