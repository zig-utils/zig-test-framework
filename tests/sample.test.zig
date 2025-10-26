const std = @import("std");

test "simple addition" {
    const result = 2 + 2;
    try std.testing.expectEqual(@as(i32, 4), result);
}

test "simple subtraction" {
    const result = 10 - 5;
    try std.testing.expectEqual(@as(i32, 5), result);
}

test "string equality" {
    const str1 = "hello";
    const str2 = "hello";
    try std.testing.expectEqualStrings(str1, str2);
}
