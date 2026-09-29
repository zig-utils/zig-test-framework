const std = @import("std");
const ztf = @import("zig_test_framework");

fn passingTest(_: std.mem.Allocator) !void {}
fn hookOne(_: std.mem.Allocator) !void {}
fn hookTwo(_: std.mem.Allocator) !void {}

test "suite owns tests and nested suites" {
    const allocator = std.testing.allocator;
    const parent = try ztf.TestSuite.init(allocator, "parent");
    defer parent.deinit();
    const child = try ztf.TestSuite.init(allocator, "child");
    try parent.addTest(ztf.TestCase.init("one", passingTest));
    try child.addTest(ztf.TestCase.init("two", passingTest));
    try parent.addSuite(child);
    try std.testing.expectEqual(@as(usize, 2), parent.countTests());
    try std.testing.expectEqual(parent, child.parent.?);
}

test "nested hooks preserve before and after ordering" {
    const allocator = std.testing.allocator;
    const parent = try ztf.TestSuite.init(allocator, "parent");
    defer parent.deinit();
    const child = try ztf.TestSuite.init(allocator, "child");
    try parent.addSuite(child);
    try parent.addBeforeEach(hookOne);
    try child.addBeforeEach(hookTwo);
    try parent.addAfterEach(hookOne);
    try child.addAfterEach(hookTwo);

    var before = try child.getAllBeforeEachHooks(allocator);
    defer before.deinit(allocator);
    var after = try child.getAllAfterEachHooks(allocator);
    defer after.deinit(allocator);
    try std.testing.expectEqual(hookOne, before.items[0]);
    try std.testing.expectEqual(hookTwo, before.items[1]);
    try std.testing.expectEqual(hookTwo, after.items[0]);
    try std.testing.expectEqual(hookOne, after.items[1]);
}

test "suite skip and only state inherits from parents" {
    const allocator = std.testing.allocator;
    const parent = try ztf.TestSuite.init(allocator, "parent");
    defer parent.deinit();
    const child = try ztf.TestSuite.init(allocator, "child");
    try parent.addSuite(child);
    parent.skip = true;
    parent.only = true;
    try std.testing.expect(child.shouldSkip());
    try std.testing.expect(child.hasOnly());
}
