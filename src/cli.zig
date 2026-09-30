const std = @import("std");
const build_options = @import("build_options");
const config_mod = @import("config.zig");
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
    test_dir: ?[]const u8 = ".",
    pattern: []const u8 = "*.test.zig",
    no_recursive: bool = false,
    shard_index: ?usize = null,
    shard_count: ?usize = null,
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
    // Snapshot testing options
    update_snapshots: bool = false,
    snapshot_dir: []const u8 = ".snapshots",
    // Watch mode options
    watch: bool = false,
    watch_debounce: u64 = 300,
    // Memory profiling options
    profile_memory: bool = false,
    memory_threshold: usize = 0,
    fail_on_leak: bool = false,
    // Configuration file
    config: ?[]const u8 = null,
    // JUnit reporter options
    junit_output: ?[]const u8 = null,
    // Timeout options
    timeout: ?u64 = null, // Global timeout in milliseconds
    // Retry and repetition options
    retries: usize = 0,
    repeat: usize = 1,
    fail_on_flaky: bool = false,
};

pub const version = build_options.version;

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

    /// Apply configuration defaults before parsing command-line arguments.
    /// A subsequent `parse` call gives explicitly supplied CLI flags priority.
    pub fn applyConfig(self: *Self, config: config_mod.TestConfig) !void {
        self.options.test_dir = config.test_options.test_dir;
        self.options.pattern = config.test_options.pattern;
        self.options.no_recursive = !config.test_options.recursive;
        self.options.filter = config.test_options.filter;
        self.options.timeout = config.test_options.timeout;
        self.options.retries = config.test_options.retries;
        self.options.repeat = config.test_options.repeat;
        self.options.fail_on_flaky = config.test_options.fail_on_flaky;
        self.options.shard_index = config.sharding.index;
        self.options.shard_count = config.sharding.count;
        self.options.parallel = config.parallel.enabled;
        self.options.jobs = config.parallel.jobs;
        self.options.reporter = try reporterFromName(config.reporter.reporter);
        self.options.junit_output = config.reporter.junit_output;
        self.options.verbose = config.reporter.verbose;
        self.options.update_snapshots = config.snapshot.update;
        self.options.snapshot_dir = config.snapshot.snapshot_dir;
        self.options.watch = config.watch.enabled;
        self.options.watch_debounce = config.watch.debounce_ms;
        self.options.profile_memory = config.memory.enabled;
        self.options.memory_threshold = config.memory.report_threshold;
        self.options.fail_on_leak = config.memory.fail_on_leak;
        self.options.ui = config.ui.enabled;
        self.options.ui_port = config.ui.port;
        self.options.coverage = config.coverage.enabled;
        self.options.coverage_dir = config.coverage.output_dir;
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
            } else if (std.mem.eql(u8, arg, "--retry") or std.mem.eql(u8, arg, "--retries")) {
                if (i + 1 >= args.len) {
                    std.debug.print("Error: {s} requires a value\n", .{arg});
                    return CLIError.MissingValue;
                }
                i += 1;
                self.options.retries = std.fmt.parseInt(usize, args[i], 10) catch {
                    std.debug.print("Error: {s} must be a valid number\n", .{arg});
                    return CLIError.InvalidArgument;
                };
            } else if (std.mem.eql(u8, arg, "--repeat")) {
                if (i + 1 >= args.len) {
                    std.debug.print("Error: --repeat requires a value\n", .{});
                    return CLIError.MissingValue;
                }
                i += 1;
                self.options.repeat = std.fmt.parseInt(usize, args[i], 10) catch {
                    std.debug.print("Error: --repeat must be a valid positive number\n", .{});
                    return CLIError.InvalidArgument;
                };
                if (self.options.repeat == 0) {
                    std.debug.print("Error: --repeat must be greater than zero\n", .{});
                    return CLIError.InvalidArgument;
                }
            } else if (std.mem.eql(u8, arg, "--fail-on-flaky")) {
                self.options.fail_on_flaky = true;
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

                self.options.reporter = reporterFromName(reporter_name) catch {
                    std.debug.print("Error: Unknown reporter '{s}'. Available: spec, dot, json, tap, junit\n", .{reporter_name});
                    return CLIError.InvalidArgument;
                };
            } else if (std.mem.eql(u8, arg, "--filter") or std.mem.eql(u8, arg, "--grep")) {
                if (i + 1 >= args.len) {
                    std.debug.print("Error: --filter/--grep requires a value\n", .{});
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
            } else if (std.mem.eql(u8, arg, "--shard-index")) {
                if (i + 1 >= args.len) {
                    std.debug.print("Error: --shard-index requires a value\n", .{});
                    return CLIError.MissingValue;
                }
                i += 1;
                self.options.shard_index = std.fmt.parseInt(usize, args[i], 10) catch {
                    std.debug.print("Error: --shard-index must be a valid number\n", .{});
                    return CLIError.InvalidArgument;
                };
            } else if (std.mem.eql(u8, arg, "--shard-count")) {
                if (i + 1 >= args.len) {
                    std.debug.print("Error: --shard-count requires a value\n", .{});
                    return CLIError.MissingValue;
                }
                i += 1;
                self.options.shard_count = std.fmt.parseInt(usize, args[i], 10) catch {
                    std.debug.print("Error: --shard-count must be a valid number\n", .{});
                    return CLIError.InvalidArgument;
                };
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
                if (!std.mem.eql(u8, self.options.coverage_tool, "kcov") and
                    !std.mem.eql(u8, self.options.coverage_tool, "grindcov"))
                {
                    std.debug.print("Error: --coverage-tool must be 'kcov' or 'grindcov'\n", .{});
                    return CLIError.InvalidArgument;
                }
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
                if (self.options.jobs.? == 0) {
                    std.debug.print("Error: --jobs must be greater than zero\n", .{});
                    return CLIError.InvalidArgument;
                }
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
            } else if (std.mem.eql(u8, arg, "--update-snapshots") or std.mem.eql(u8, arg, "-u")) {
                self.options.update_snapshots = true;
            } else if (std.mem.eql(u8, arg, "--snapshot-dir")) {
                if (i + 1 >= args.len) {
                    std.debug.print("Error: --snapshot-dir requires a value\n", .{});
                    return CLIError.MissingValue;
                }
                i += 1;
                self.options.snapshot_dir = args[i];
            } else if (std.mem.eql(u8, arg, "--watch") or std.mem.eql(u8, arg, "-w")) {
                self.options.watch = true;
            } else if (std.mem.eql(u8, arg, "--watch-debounce")) {
                if (i + 1 >= args.len) {
                    std.debug.print("Error: --watch-debounce requires a value\n", .{});
                    return CLIError.MissingValue;
                }
                i += 1;
                const debounce_str = args[i];
                self.options.watch_debounce = std.fmt.parseInt(u64, debounce_str, 10) catch {
                    std.debug.print("Error: --watch-debounce must be a valid number\n", .{});
                    return CLIError.InvalidArgument;
                };
            } else if (std.mem.eql(u8, arg, "--profile-memory")) {
                self.options.profile_memory = true;
            } else if (std.mem.eql(u8, arg, "--memory-threshold")) {
                if (i + 1 >= args.len) {
                    std.debug.print("Error: --memory-threshold requires a value\n", .{});
                    return CLIError.MissingValue;
                }
                i += 1;
                const threshold_str = args[i];
                self.options.memory_threshold = std.fmt.parseInt(usize, threshold_str, 10) catch {
                    std.debug.print("Error: --memory-threshold must be a valid number\n", .{});
                    return CLIError.InvalidArgument;
                };
            } else if (std.mem.eql(u8, arg, "--fail-on-leak")) {
                self.options.fail_on_leak = true;
            } else if (std.mem.eql(u8, arg, "--config") or std.mem.eql(u8, arg, "-c")) {
                if (i + 1 >= args.len) {
                    std.debug.print("Error: --config requires a value\n", .{});
                    return CLIError.MissingValue;
                }
                i += 1;
                self.options.config = args[i];
            } else if (std.mem.eql(u8, arg, "--junit-output")) {
                if (i + 1 >= args.len) {
                    std.debug.print("Error: --junit-output requires a value\n", .{});
                    return CLIError.MissingValue;
                }
                i += 1;
                self.options.junit_output = args[i];
            } else if (std.mem.eql(u8, arg, "--timeout")) {
                if (i + 1 >= args.len) {
                    std.debug.print("Error: --timeout requires a value\n", .{});
                    return CLIError.MissingValue;
                }
                i += 1;
                const timeout_str = args[i];
                self.options.timeout = std.fmt.parseInt(u64, timeout_str, 10) catch {
                    std.debug.print("Error: --timeout must be a valid number (milliseconds)\n", .{});
                    return CLIError.InvalidArgument;
                };
            } else if (std.mem.startsWith(u8, arg, "--")) {
                std.debug.print("Error: Unknown option '{s}'\n", .{arg});
                return CLIError.InvalidArgument;
            } else {
                // Treat non-flag arguments as test directory path
                self.options.test_dir = arg;
            }
        }

        const has_shard_index = self.options.shard_index != null;
        const has_shard_count = self.options.shard_count != null;
        if (has_shard_index != has_shard_count) {
            std.debug.print("Error: --shard-index and --shard-count must be provided together\n", .{});
            return CLIError.InvalidArgument;
        }
        if (self.options.shard_count) |count| {
            const index = self.options.shard_index.?;
            if (count == 0) {
                std.debug.print("Error: --shard-count must be greater than zero\n", .{});
                return CLIError.InvalidArgument;
            }
            if (index == 0 or index > count) {
                std.debug.print("Error: --shard-index must be between 1 and --shard-count\n", .{});
                return CLIError.InvalidArgument;
            }
        }
    }

    /// Return the first option that discovery mode cannot currently honor.
    /// Discovery must reject these options explicitly instead of silently
    /// behaving differently from programmatic mode.
    pub fn unsupportedDiscoveryOption(self: Self) ?[]const u8 {
        if (!self.options.coverage and !std.mem.eql(u8, self.options.coverage_dir, "coverage")) return "--coverage-dir";
        if (!self.options.coverage and !std.mem.eql(u8, self.options.coverage_tool, "kcov")) return "--coverage-tool";
        if (!self.options.watch and self.options.watch_debounce != 300) return "--watch-debounce";
        if (!self.options.ui and self.options.ui_port != 8080) return "--ui-port";
        if (!self.options.ui and !std.mem.eql(u8, self.options.ui_host, "127.0.0.1")) return "--ui-host";
        if (self.options.quiet) return "--quiet";
        if (self.options.parallel) return "--parallel";
        if (self.options.jobs != null) return "--jobs";
        if (self.options.update_snapshots) return "--update-snapshots";
        if (!std.mem.eql(u8, self.options.snapshot_dir, ".snapshots")) return "--snapshot-dir";
        if (self.options.profile_memory) return "--profile-memory";
        if (self.options.memory_threshold != 0) return "--memory-threshold";
        if (self.options.fail_on_leak) return "--fail-on-leak";
        return null;
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
            \\    --retry <N>             Retry each failed test up to N times
            \\    --repeat <N>            Require N successful runs of each selected test
            \\    --fail-on-flaky         Exit unsuccessfully when a retry recovers a failure
            \\    --filter <pattern>      Run only tests matching pattern
            \\    --grep <pattern>        Same as --filter (alias)
            \\    --reporter <name>       Set reporter type (spec, dot, json, tap, junit)
            \\    --verbose               Enable verbose output
            \\    -q, --quiet             Minimal output
            \\    --no-color              Disable colored output
            \\    --timeout <ms>          Global timeout for all tests in milliseconds
            \\    -c, --config <file>     Load strict JSON configuration
            \\
            \\TEST DISCOVERY:
            \\    --test-dir <dir>        Directory to search for tests (default: .)
            \\    --pattern <pattern>     Test file pattern (default: *.test.zig)
            \\    --no-recursive          Disable recursive directory search
            \\    --shard-index <N>       One-based shard to run
            \\    --shard-count <N>       Total number of shards
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
            \\SNAPSHOT TESTING:
            \\    -u, --update-snapshots  Update snapshot files instead of comparing
            \\    --snapshot-dir <dir>    Snapshot directory (default: .snapshots)
            \\
            \\WATCH MODE:
            \\    -w, --watch             Watch files and re-run tests on changes
            \\    --watch-debounce <ms>   Debounce delay in milliseconds (default: 300)
            \\                              Type r + Enter to force a full rerun
            \\
            \\MEMORY PROFILING:
            \\    --profile-memory        Enable memory profiling for tests
            \\    --memory-threshold <N>  Report threshold in bytes (default: 0)
            \\    --fail-on-leak          Fail tests if memory leaks detected
            \\
            \\REPORTERS:
            \\    spec                    Default hierarchical reporter with colors
            \\    dot                     Minimal dot-based reporter
            \\    json                    Machine-readable JSON output
            \\    tap                     TAP (Test Anything Protocol) format
            \\    junit                   JUnit XML format (use with --junit-output)
            \\
            \\JUNIT OPTIONS:
            \\    --junit-output <file>   Write JUnit XML to file
            \\
            \\EXAMPLES:
            \\    zig-test                              Run all tests
            \\    zig-test --filter "user"              Run tests matching "user"
            \\    zig-test --grep "auth"                Run tests matching "auth"
            \\    zig-test --reporter tap               Output in TAP format
            \\    zig-test --reporter junit --junit-output results.xml
            \\    zig-test -u                           Update all snapshots (short flag)
            \\    zig-test --update-snapshots           Update all snapshots
            \\    zig-test --watch                      Run in watch mode
            \\    zig-test --timeout 10000              Set 10s timeout for all tests
            \\    zig-test --retry 2 --fail-on-flaky    Detect and reject flaky tests
            \\    zig-test --repeat 100 --filter parser Stress-run selected tests
            \\    zig-test --profile-memory --fail-on-leak
            \\    zig-test --parallel --jobs 4          Run with 4 parallel workers
            \\    zig-test --config zig-test.json       Load config from file
            \\    zig-test --ui --parallel --coverage   All features together
            \\
        ;

        std.debug.print("{s}\n", .{help_text});
    }

    /// Print version information
    pub fn printVersion(self: Self) void {
        _ = self;
        std.debug.print("Zig Test Framework v{s}\n", .{version});
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
            .junit_output = self.options.junit_output orelse "test-results.xml",
            .timeout_ms = self.options.timeout,
            .retries = self.options.retries,
            .repeat = self.options.repeat,
            .fail_on_flaky = self.options.fail_on_flaky,
        };
    }
};

fn reporterFromName(name: []const u8) !test_runner.ReporterType {
    if (std.mem.eql(u8, name, "spec")) return .spec;
    if (std.mem.eql(u8, name, "dot")) return .dot;
    if (std.mem.eql(u8, name, "json")) return .json;
    if (std.mem.eql(u8, name, "tap")) return .tap;
    if (std.mem.eql(u8, name, "junit")) return .junit;
    return CLIError.InvalidArgument;
}

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

test "CLI build version is valid semantic version metadata" {
    _ = try std.SemanticVersion.parse(version);
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

test "CLI parse shard options" {
    var cli = CLI.init(std.testing.allocator);
    try cli.parse(&.{ "zig-test", "--shard-count", "5", "--shard-index", "3" });
    try std.testing.expectEqual(@as(?usize, 3), cli.options.shard_index);
    try std.testing.expectEqual(@as(?usize, 5), cli.options.shard_count);
}

test "CLI rejects incomplete and out-of-range shards" {
    var incomplete = CLI.init(std.testing.allocator);
    try std.testing.expectError(
        CLIError.InvalidArgument,
        incomplete.parse(&.{ "zig-test", "--shard-count", "2" }),
    );

    var out_of_range = CLI.init(std.testing.allocator);
    try std.testing.expectError(
        CLIError.InvalidArgument,
        out_of_range.parse(&.{ "zig-test", "--shard-index", "0", "--shard-count", "2" }),
    );
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
        "--test-dir",
        "tests",
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
    try std.testing.expectEqualStrings(".", cli.options.test_dir.?);
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

test "CLI parse grep alias" {
    var cli = CLI.init(std.testing.allocator);
    const args = [_][]const u8{ "zig-test", "--grep", "auth" };
    try cli.parse(&args);
    try std.testing.expect(cli.options.filter != null);
    try std.testing.expectEqualStrings("auth", cli.options.filter.?);
}

test "CLI parse timeout" {
    var cli = CLI.init(std.testing.allocator);
    const args = [_][]const u8{ "zig-test", "--timeout", "5000" };
    try cli.parse(&args);
    try std.testing.expectEqual(@as(?u64, 5000), cli.options.timeout);
}

test "CLI parses retry repeat and flaky exit policy" {
    var cli = CLI.init(std.testing.allocator);
    const args = [_][]const u8{
        "zig-test",
        "--retry",
        "2",
        "--repeat",
        "5",
        "--fail-on-flaky",
    };
    try cli.parse(&args);
    try std.testing.expectEqual(@as(usize, 2), cli.options.retries);
    try std.testing.expectEqual(@as(usize, 5), cli.options.repeat);
    try std.testing.expect(cli.options.fail_on_flaky);

    const runner_options = cli.toRunnerOptions();
    try std.testing.expectEqual(@as(usize, 2), runner_options.retries);
    try std.testing.expectEqual(@as(usize, 5), runner_options.repeat);
    try std.testing.expect(runner_options.fail_on_flaky);
}

test "CLI rejects a zero repeat count" {
    var cli = CLI.init(std.testing.allocator);
    try std.testing.expectError(
        CLIError.InvalidArgument,
        cli.parse(&.{ "zig-test", "--repeat", "0" }),
    );
}

test "CLI rejects invalid coverage tool" {
    var cli = CLI.init(std.testing.allocator);
    const args = [_][]const u8{ "zig-test", "--coverage-tool", "unknown" };
    try std.testing.expectError(CLIError.InvalidArgument, cli.parse(&args));
}

test "CLI rejects zero jobs" {
    var cli = CLI.init(std.testing.allocator);
    const args = [_][]const u8{ "zig-test", "--jobs", "0" };
    try std.testing.expectError(CLIError.InvalidArgument, cli.parse(&args));
}

test "discovery accepts implemented options" {
    var cli = CLI.init(std.testing.allocator);
    const args = [_][]const u8{
        "zig-test",
        "--test-dir",
        "tests",
        "--filter",
        "math",
        "--no-color",
        "--bail",
        "--verbose",
    };
    try cli.parse(&args);
    try std.testing.expectEqual(@as(?[]const u8, null), cli.unsupportedDiscoveryOption());
}

test "discovery accepts reporter selection" {
    var cli = CLI.init(std.testing.allocator);
    const args = [_][]const u8{ "zig-test", "--test-dir", "tests", "--reporter", "json" };
    try cli.parse(&args);
    try std.testing.expectEqual(@as(?[]const u8, null), cli.unsupportedDiscoveryOption());
}

test "discovery accepts the live UI" {
    var cli = CLI.init(std.testing.allocator);
    const args = [_][]const u8{ "zig-test", "--test-dir", "tests", "--ui", "--ui-port", "0" };
    try cli.parse(&args);
    try std.testing.expectEqual(@as(?[]const u8, null), cli.unsupportedDiscoveryOption());
}

test "discovery accepts timeout and reports parallel as unsupported" {
    var cli = CLI.init(std.testing.allocator);

    cli.options.timeout = 1000;
    try std.testing.expectEqual(@as(?[]const u8, null), cli.unsupportedDiscoveryOption());

    cli.options.timeout = null;
    cli.options.parallel = true;
    try std.testing.expectEqualStrings("--parallel", cli.unsupportedDiscoveryOption().?);
}

test "CLI parse update-snapshots short flag" {
    var cli = CLI.init(std.testing.allocator);
    const args = [_][]const u8{ "zig-test", "-u" };
    try cli.parse(&args);
    try std.testing.expect(cli.options.update_snapshots);
}
