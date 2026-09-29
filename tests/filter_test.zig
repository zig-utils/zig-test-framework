const std = @import("std");
const ztf = @import("zig_test_framework");

test "discovery forwards test-name filters to zig test" {
    const allocator = std.testing.allocator;
    var discovered = ztf.DiscoveryResult.init(allocator);
    defer discovered.deinit();

    try discovered.addFile(
        "tests/fixtures/filter_fixture.zig",
        "fixtures/filter_fixture.zig",
        "filter_fixture.zig",
    );

    const passed = try ztf.runDiscoveredTests(allocator, &discovered, .{
        .filter = "selected test passes",
        .use_colors = false,
    });

    try std.testing.expect(passed);
}
