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

test "CLI flags override configuration defaults" {
    var cli = ztf.CLI.init(std.testing.allocator);
    var config = ztf.TestConfig{};
    config.test_options.test_dir = "configured-tests";
    config.test_options.filter = "configured-filter";
    config.test_options.recursive = false;
    config.reporter.verbose = true;

    try cli.applyConfig(config);
    try cli.parse(&.{ "zig-test", "--test-dir", "cli-tests", "--filter", "cli-filter" });

    try std.testing.expectEqualStrings("cli-tests", cli.options.test_dir.?);
    try std.testing.expectEqualStrings("cli-filter", cli.options.filter.?);
    try std.testing.expect(cli.options.no_recursive);
    try std.testing.expect(cli.options.verbose);
}
