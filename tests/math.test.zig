const std = @import("std");

test "multiplication" {
    const result = 3 * 4;
    try std.testing.expectEqual(@as(i32, 12), result);
}

test "division" {
    const result = 20 / 4;
    try std.testing.expectEqual(@as(i32, 5), result);
}

test "modulo" {
    const result = 10 % 3;
    try std.testing.expectEqual(@as(i32, 1), result);
}
