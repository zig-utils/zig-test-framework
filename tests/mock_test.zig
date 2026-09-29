const std = @import("std");
const ztf = @import("zig_test_framework");

test "mock records calls and exposes the latest invocation" {
    var mock = ztf.createMock(std.testing.allocator, i32);
    defer mock.deinit();
    try mock.recordCall("first");
    try mock.recordCall("second");
    try std.testing.expectEqual(@as(usize, 2), mock.callCount());
    try std.testing.expectEqualStrings("second", mock.getLastCall().?.args);
    try mock.toHaveBeenCalledWith("first");
}

test "mock returns configured values in order" {
    var mock = ztf.createMock(std.testing.allocator, i32);
    defer mock.deinit();
    _ = try mock.mockReturnValueOnce(10);
    _ = try mock.mockReturnValue(20);
    try std.testing.expectEqual(@as(?i32, 10), mock.getReturnValue());
    try std.testing.expectEqual(@as(?i32, 20), mock.getReturnValue());
    try std.testing.expectEqual(@as(?i32, 20), mock.getReturnValue());
}

test "mock clear preserves return values while reset removes them" {
    var mock = ztf.createMock(std.testing.allocator, i32);
    defer mock.deinit();
    try mock.recordCall("call");
    _ = try mock.mockReturnValue(7);
    _ = mock.mockClear();
    try std.testing.expectEqual(@as(usize, 0), mock.callCount());
    try std.testing.expectEqual(@as(?i32, 7), mock.getReturnValue());
    _ = mock.mockReset();
    try std.testing.expectEqual(@as(?i32, null), mock.getReturnValue());
}
