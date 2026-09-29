const std = @import("std");
const ztf = @import("zig_test_framework");

test "CLI parses the help flag" {
    var cli = ztf.CLI.init(std.testing.allocator);
    try cli.parse(&.{ "zig-test", "--help" });
    try std.testing.expect(cli.options.help);
}

test "CLI parses a representative discovery invocation" {
    var cli = ztf.CLI.init(std.testing.allocator);
    try cli.parse(&.{ "zig-test", "--test-dir", "specs", "--grep", "database", "--coverage", "--no-color", "--bail" });
    try std.testing.expectEqualStrings("specs", cli.options.test_dir.?);
    try std.testing.expectEqualStrings("database", cli.options.filter.?);
    try std.testing.expect(cli.options.coverage);
    try std.testing.expect(cli.options.no_color);
    try std.testing.expect(cli.options.bail);
}

test "CLI rejects missing and invalid values" {
    var missing = ztf.CLI.init(std.testing.allocator);
    try std.testing.expectError(ztf.cli.CLIError.MissingValue, missing.parse(&.{ "zig-test", "--reporter" }));
    var invalid = ztf.CLI.init(std.testing.allocator);
    try std.testing.expectError(ztf.cli.CLIError.InvalidArgument, invalid.parse(&.{ "zig-test", "--jobs", "0" }));
}
