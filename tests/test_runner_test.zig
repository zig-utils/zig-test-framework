const std = @import("std");
const ztf = @import("zig_test_framework");

fn passingTest(_: std.mem.Allocator) !void {}

test "test runner initialization" {
    var registry = ztf.TestRegistry.init(std.testing.allocator);
    defer registry.deinit();
    var runner = ztf.TestRunner.init(std.testing.allocator, &registry, .{});
    defer runner.deinit();
    try std.testing.expectEqual(@as(usize, 0), runner.results.total);
    try std.testing.expectEqual(ztf.ReporterType.spec, runner.options.reporter_type);
}

test "test runner executes matching tests and skips filtered tests" {
    const allocator = std.testing.allocator;
    var registry = ztf.TestRegistry.init(allocator);
    defer registry.deinit();
    const suite = try ztf.TestSuite.init(allocator, "runner suite");
    try suite.addTest(ztf.TestCase.init("selected", passingTest));
    try suite.addTest(ztf.TestCase.init("ignored", passingTest));
    try registry.registerSuite(suite);

    var runner = ztf.TestRunner.init(allocator, &registry, .{ .filter = "selected", .use_colors = false });
    defer runner.deinit();
    try std.testing.expect(try runner.run());
    try std.testing.expectEqual(@as(usize, 2), runner.results.total);
    try std.testing.expectEqual(@as(usize, 1), runner.results.passed);
    try std.testing.expectEqual(@as(usize, 1), runner.results.skipped);
}
