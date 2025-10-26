const std = @import("std");

// These are simple tests to verify coverage tool integration works
// The framework will run these with kcov/grindcov when --coverage is enabled

test "coverage test: basic math" {
    const a: i32 = 2 + 2;
    try std.testing.expectEqual(@as(i32, 4), a);

    const b: i32 = 10 - 5;
    try std.testing.expectEqual(@as(i32, 5), b);

    const c: i32 = 3 * 4;
    try std.testing.expectEqual(@as(i32, 12), c);
}

test "coverage test: conditionals" {
    const value = 42;

    if (value > 0) {
        try std.testing.expect(true);
    } else {
        try std.testing.expect(false);
    }

    if (value < 0) {
        try std.testing.expect(false);
    } else {
        try std.testing.expect(true);
    }
}

test "coverage test: loops" {
    var sum: i32 = 0;
    var i: i32 = 0;
    while (i < 10) : (i += 1) {
        sum += i;
    }
    try std.testing.expectEqual(@as(i32, 45), sum);
}

test "coverage test: functions" {
    const result = addNumbers(5, 10);
    try std.testing.expectEqual(@as(i32, 15), result);

    const result2 = multiplyNumbers(3, 7);
    try std.testing.expectEqual(@as(i32, 21), result2);
}

fn addNumbers(a: i32, b: i32) i32 {
    return a + b;
}

fn multiplyNumbers(a: i32, b: i32) i32 {
    return a * b;
}

test "coverage test: error handling" {
    const result = divideNumbers(10, 2) catch unreachable;
    try std.testing.expectEqual(@as(i32, 5), result);

    const err_result = divideNumbers(10, 0);
    try std.testing.expectError(error.DivisionByZero, err_result);
}

fn divideNumbers(a: i32, b: i32) !i32 {
    if (b == 0) {
        return error.DivisionByZero;
    }
    return @divTrunc(a, b);
}
