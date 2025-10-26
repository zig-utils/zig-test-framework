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
    // Test discovery options
    test_dir: ?[]const u8 = null,
    pattern: []const u8 = "*.test.zig",
    no_recursive: bool = false,
    // Coverage options
    coverage: bool = false,
    coverage_dir: []const u8 = "coverage",
    coverage_tool: []const u8 = "kcov",
    // Parallel execution options
    parallel: bool = false,
    jobs: ?usize = null,
    // UI server options
    ui: bool = false,
    ui_port: u16 = 8080,
    ui_host: []const u8 = "127.0.0.1",
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
            } else if (std.mem.eql(u8, arg, "--test-dir")) {
                if (i + 1 >= args.len) {
                    std.debug.print("Error: --test-dir requires a value\n", .{});
                    return CLIError.MissingValue;
                }
                i += 1;
                self.options.test_dir = args[i];
            } else if (std.mem.eql(u8, arg, "--pattern")) {
                if (i + 1 >= args.len) {
                    std.debug.print("Error: --pattern requires a value\n", .{});
                    return CLIError.MissingValue;
                }
                i += 1;
                self.options.pattern = args[i];
            } else if (std.mem.eql(u8, arg, "--no-recursive")) {
                self.options.no_recursive = true;
            } else if (std.mem.eql(u8, arg, "--coverage")) {
                self.options.coverage = true;
            } else if (std.mem.eql(u8, arg, "--coverage-dir")) {
                if (i + 1 >= args.len) {
                    std.debug.print("Error: --coverage-dir requires a value\n", .{});
                    return CLIError.MissingValue;
                }
                i += 1;
                self.options.coverage_dir = args[i];
            } else if (std.mem.eql(u8, arg, "--coverage-tool")) {
                if (i + 1 >= args.len) {
                    std.debug.print("Error: --coverage-tool requires a value\n", .{});
                    return CLIError.MissingValue;
                }
                i += 1;
                self.options.coverage_tool = args[i];
            } else if (std.mem.eql(u8, arg, "--parallel") or std.mem.eql(u8, arg, "-p")) {
                self.options.parallel = true;
            } else if (std.mem.eql(u8, arg, "--jobs") or std.mem.eql(u8, arg, "-j")) {
                if (i + 1 >= args.len) {
                    std.debug.print("Error: --jobs requires a value\n", .{});
                    return CLIError.MissingValue;
                }
                i += 1;
                const jobs_str = args[i];
                self.options.jobs = std.fmt.parseInt(usize, jobs_str, 10) catch {
                    std.debug.print("Error: --jobs must be a valid number\n", .{});
                    return CLIError.InvalidArgument;
                };
            } else if (std.mem.eql(u8, arg, "--ui")) {
                self.options.ui = true;
            } else if (std.mem.eql(u8, arg, "--ui-port")) {
                if (i + 1 >= args.len) {
                    std.debug.print("Error: --ui-port requires a value\n", .{});
                    return CLIError.MissingValue;
                }
                i += 1;
                const port_str = args[i];
                self.options.ui_port = std.fmt.parseInt(u16, port_str, 10) catch {
                    std.debug.print("Error: --ui-port must be a valid port number (1-65535)\n", .{});
                    return CLIError.InvalidArgument;
                };
            } else if (std.mem.eql(u8, arg, "--ui-host")) {
                if (i + 1 >= args.len) {
                    std.debug.print("Error: --ui-host requires a value\n", .{});
                    return CLIError.MissingValue;
                }
                i += 1;
                self.options.ui_host = args[i];
            } else if (std.mem.startsWith(u8, arg, "--")) {
                std.debug.print("Error: Unknown option '{s}'\n", .{arg});
                return CLIError.InvalidArgument;
            } else {
                // Treat non-flag arguments as test directory path
                self.options.test_dir = arg;
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
            \\    zig-test [OPTIONS] [TEST_DIR]
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
            \\TEST DISCOVERY:
            \\    --test-dir <dir>        Directory to search for tests (default: .)
            \\    --pattern <pattern>     Test file pattern (default: *.test.zig)
            \\    --no-recursive          Disable recursive directory search
            \\
            \\COVERAGE:
            \\    --coverage              Enable code coverage collection
            \\    --coverage-dir <dir>    Coverage output directory (default: coverage)
            \\    --coverage-tool <tool>  Coverage tool to use (default: kcov)
            \\
            \\PARALLEL EXECUTION:
            \\    -p, --parallel          Enable parallel test execution
            \\    -j, --jobs <N>          Number of parallel jobs (default: CPU count)
            \\
            \\WEB UI:
            \\    --ui                    Enable web-based test UI
            \\    --ui-port <port>        UI server port (default: 8080)
            \\    --ui-host <host>        UI server host (default: 127.0.0.1)
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
            .parallel = self.options.parallel,
            .n_jobs = self.options.jobs,
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

test "CLI parse coverage flag" {
    var cli = CLI.init(std.testing.allocator);
    const args = [_][]const u8{ "zig-test", "--coverage" };
    try cli.parse(&args);
    try std.testing.expect(cli.options.coverage);
}

test "CLI parse coverage-dir" {
    var cli = CLI.init(std.testing.allocator);
    const args = [_][]const u8{ "zig-test", "--coverage-dir", "my-coverage" };
    try cli.parse(&args);
    try std.testing.expectEqualStrings("my-coverage", cli.options.coverage_dir);
}

test "CLI parse coverage-tool" {
    var cli = CLI.init(std.testing.allocator);
    const args = [_][]const u8{ "zig-test", "--coverage-tool", "grindcov" };
    try cli.parse(&args);
    try std.testing.expectEqualStrings("grindcov", cli.options.coverage_tool);
}

test "CLI parse all coverage options" {
    var cli = CLI.init(std.testing.allocator);
    const args = [_][]const u8{ "zig-test", "--coverage", "--coverage-dir", "cov", "--coverage-tool", "kcov" };
    try cli.parse(&args);
    try std.testing.expect(cli.options.coverage);
    try std.testing.expectEqualStrings("cov", cli.options.coverage_dir);
    try std.testing.expectEqualStrings("kcov", cli.options.coverage_tool);
}

test "CLI parse test-dir option" {
    var cli = CLI.init(std.testing.allocator);
    const args = [_][]const u8{ "zig-test", "--test-dir", "tests" };
    try cli.parse(&args);
    try std.testing.expect(cli.options.test_dir != null);
    try std.testing.expectEqualStrings("tests", cli.options.test_dir.?);
}

test "CLI parse pattern option" {
    var cli = CLI.init(std.testing.allocator);
    const args = [_][]const u8{ "zig-test", "--pattern", "*.spec.zig" };
    try cli.parse(&args);
    try std.testing.expectEqualStrings("*.spec.zig", cli.options.pattern);
}

test "CLI parse no-recursive option" {
    var cli = CLI.init(std.testing.allocator);
    const args = [_][]const u8{ "zig-test", "--no-recursive" };
    try cli.parse(&args);
    try std.testing.expect(cli.options.no_recursive);
}

test "CLI parse multiple options" {
    var cli = CLI.init(std.testing.allocator);
    const args = [_][]const u8{
        "zig-test",
        "--test-dir", "tests",
        "--coverage",
        "--bail",
        "--verbose",
    };
    try cli.parse(&args);
    try std.testing.expect(cli.options.test_dir != null);
    try std.testing.expectEqualStrings("tests", cli.options.test_dir.?);
    try std.testing.expect(cli.options.coverage);
    try std.testing.expect(cli.options.bail);
    try std.testing.expect(cli.options.verbose);
}

test "CLI default values" {
    var cli = CLI.init(std.testing.allocator);
    const args = [_][]const u8{"zig-test"};
    try cli.parse(&args);

    try std.testing.expect(!cli.options.help);
    try std.testing.expect(!cli.options.version);
    try std.testing.expect(!cli.options.bail);
    try std.testing.expect(!cli.options.coverage);
    try std.testing.expectEqualStrings("coverage", cli.options.coverage_dir);
    try std.testing.expectEqualStrings("kcov", cli.options.coverage_tool);
    try std.testing.expectEqualStrings("*.test.zig", cli.options.pattern);
    try std.testing.expect(!cli.options.ui);
    try std.testing.expectEqual(@as(u16, 8080), cli.options.ui_port);
    try std.testing.expectEqualStrings("127.0.0.1", cli.options.ui_host);
}

test "CLI parse ui flag" {
    var cli = CLI.init(std.testing.allocator);
    const args = [_][]const u8{ "zig-test", "--ui" };
    try cli.parse(&args);
    try std.testing.expect(cli.options.ui);
}

test "CLI parse ui-port" {
    var cli = CLI.init(std.testing.allocator);
    const args = [_][]const u8{ "zig-test", "--ui-port", "3000" };
    try cli.parse(&args);
    try std.testing.expectEqual(@as(u16, 3000), cli.options.ui_port);
}

test "CLI parse ui-host" {
    var cli = CLI.init(std.testing.allocator);
    const args = [_][]const u8{ "zig-test", "--ui-host", "0.0.0.0" };
    try cli.parse(&args);
    try std.testing.expectEqualStrings("0.0.0.0", cli.options.ui_host);
}

test "CLI parse all ui options" {
    var cli = CLI.init(std.testing.allocator);
    const args = [_][]const u8{ "zig-test", "--ui", "--ui-port", "9000", "--ui-host", "localhost" };
    try cli.parse(&args);
    try std.testing.expect(cli.options.ui);
    try std.testing.expectEqual(@as(u16, 9000), cli.options.ui_port);
    try std.testing.expectEqualStrings("localhost", cli.options.ui_host);
}

test "CLI parse parallel flag" {
    var cli = CLI.init(std.testing.allocator);
    const args = [_][]const u8{ "zig-test", "--parallel" };
    try cli.parse(&args);
    try std.testing.expect(cli.options.parallel);
}

test "CLI parse jobs" {
    var cli = CLI.init(std.testing.allocator);
    const args = [_][]const u8{ "zig-test", "--jobs", "4" };
    try cli.parse(&args);
    try std.testing.expectEqual(@as(?usize, 4), cli.options.jobs);
}
