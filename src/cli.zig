const std = @import("std");
const test_runner = @import("test_runner.zig");

pub const CLIOptions = struct {
    help: bool = false,
    version: bool = false,
    bail: bool = false,
    filter: ?[]const u8 = null,
    reporter: test_runner.ReporterType = .spec,
    verbose: bool = false,
    quiet: bool = false,
    no_color: bool = false,
};

pub const CLIError = error{
    InvalidArgument,
    MissingValue,
};

pub const CLI = struct {
    allocator: std.mem.Allocator,
    options: CLIOptions,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .options = CLIOptions{},
        };
    }

    /// Parse command-line arguments
    pub fn parse(self: *Self, args: []const []const u8) !void {
        var i: usize = 1; // Skip program name
        while (i < args.len) : (i += 1) {
            const arg = args[i];

            if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
                self.options.help = true;
            } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
                self.options.version = true;
            } else if (std.mem.eql(u8, arg, "--bail") or std.mem.eql(u8, arg, "-b")) {
                self.options.bail = true;
            } else if (std.mem.eql(u8, arg, "--verbose")) {
                self.options.verbose = true;
            } else if (std.mem.eql(u8, arg, "--quiet") or std.mem.eql(u8, arg, "-q")) {
                self.options.quiet = true;
            } else if (std.mem.eql(u8, arg, "--no-color")) {
                self.options.no_color = true;
            } else if (std.mem.eql(u8, arg, "--reporter")) {
                if (i + 1 >= args.len) {
                    std.debug.print("Error: --reporter requires a value\n", .{});
                    return CLIError.MissingValue;
                }
                i += 1;
                const reporter_name = args[i];

                if (std.mem.eql(u8, reporter_name, "spec")) {
                    self.options.reporter = .spec;
                } else if (std.mem.eql(u8, reporter_name, "dot")) {
                    self.options.reporter = .dot;
                } else if (std.mem.eql(u8, reporter_name, "json")) {
                    self.options.reporter = .json;
                } else {
                    std.debug.print("Error: Unknown reporter '{s}'. Available: spec, dot, json\n", .{reporter_name});
                    return CLIError.InvalidArgument;
                }
            } else if (std.mem.eql(u8, arg, "--filter")) {
                if (i + 1 >= args.len) {
                    std.debug.print("Error: --filter requires a value\n", .{});
                    return CLIError.MissingValue;
                }
                i += 1;
                self.options.filter = args[i];
            } else if (std.mem.startsWith(u8, arg, "--")) {
                std.debug.print("Error: Unknown option '{s}'\n", .{arg});
                return CLIError.InvalidArgument;
            }
        }
    }

    /// Print help message
    pub fn printHelp(self: Self) void {
        _ = self;
        const help_text =
            \\Zig Test Framework - A modern testing framework for Zig
            \\
            \\USAGE:
            \\    zig-test [OPTIONS]
            \\
            \\OPTIONS:
            \\    -h, --help              Show this help message
            \\    -v, --version           Show version information
            \\    -b, --bail              Stop test execution on first failure
            \\    --filter <pattern>      Run only tests matching pattern
            \\    --reporter <name>       Set reporter type (spec, dot, json)
            \\    --verbose               Enable verbose output
            \\    -q, --quiet             Minimal output
            \\    --no-color              Disable colored output
            \\
            \\REPORTERS:
            \\    spec                    Default hierarchical reporter with colors
            \\    dot                     Minimal dot-based reporter
            \\    json                    Machine-readable JSON output
            \\
            \\EXAMPLES:
            \\    zig-test                           Run all tests
            \\    zig-test --filter "user"           Run tests matching "user"
            \\    zig-test --reporter json           Output results as JSON
            \\    zig-test --bail                    Stop on first failure
            \\    zig-test --no-color                Disable colored output
            \\
        ;

        std.debug.print("{s}\n", .{help_text});
    }

    /// Print version information
    pub fn printVersion(self: Self) void {
        _ = self;
        std.debug.print("Zig Test Framework v0.1.0\n", .{});
    }

    /// Convert CLI options to RunnerOptions
    pub fn toRunnerOptions(self: Self) test_runner.RunnerOptions {
        return test_runner.RunnerOptions{
            .bail = self.options.bail,
            .filter = self.options.filter,
            .reporter_type = self.options.reporter,
            .use_colors = !self.options.no_color,
        };
    }
};

test "CLI parse help" {
    var cli = CLI.init(std.testing.allocator);
    const args = [_][]const u8{ "zig-test", "--help" };
    try cli.parse(&args);
    try std.testing.expect(cli.options.help);
}

test "CLI parse version" {
    var cli = CLI.init(std.testing.allocator);
    const args = [_][]const u8{ "zig-test", "-v" };
    try cli.parse(&args);
    try std.testing.expect(cli.options.version);
}

test "CLI parse bail" {
    var cli = CLI.init(std.testing.allocator);
    const args = [_][]const u8{ "zig-test", "--bail" };
    try cli.parse(&args);
    try std.testing.expect(cli.options.bail);
}

test "CLI parse reporter" {
    var cli = CLI.init(std.testing.allocator);
    const args = [_][]const u8{ "zig-test", "--reporter", "json" };
    try cli.parse(&args);
    try std.testing.expectEqual(test_runner.ReporterType.json, cli.options.reporter);
}

test "CLI parse filter" {
    var cli = CLI.init(std.testing.allocator);
    const args = [_][]const u8{ "zig-test", "--filter", "user" };
    try cli.parse(&args);
    try std.testing.expect(cli.options.filter != null);
    try std.testing.expectEqualStrings("user", cli.options.filter.?);
}
