const std = @import("std");
const builtin = @import("builtin");
const lib = @import("zig_test_framework");

// Global signal handler state. Watch mode shares this flag so Ctrl+C can
// unwind through normal cleanup instead of bypassing the UI server shutdown.
var keep_running = std.atomic.Value(bool).init(true);

/// Install signal handlers
fn installSignalHandlers() !void {
    // Windows console control events retain their native default behavior:
    // Ctrl-C and console close terminate the CLI. POSIX platforms install
    // cooperative handlers so long-running watch/UI modes can clean up.
    if (comptime builtin.os.tag == .windows) return;

    const Handler = struct {
        fn handle(sig: std.posix.SIG) callconv(.c) void {
            _ = sig;
            keep_running.store(false, .monotonic);
            std.debug.print("\n\nShutdown requested... cleaning up\n", .{});
        }
    };
    const posix = std.posix;

    // Install SIGINT handler (Ctrl+C)
    const sigint_action = posix.Sigaction{
        .handler = .{ .handler = Handler.handle },
        .mask = posix.sigemptyset(),
        .flags = 0,
    };
    posix.sigaction(posix.SIG.INT, &sigint_action, null);

    // Install SIGTERM handler
    const sigterm_action = posix.Sigaction{
        .handler = .{ .handler = Handler.handle },
        .mask = posix.sigemptyset(),
        .flags = 0,
    };
    posix.sigaction(posix.SIG.TERM, &sigterm_action, null);
}

pub fn main(init: std.process.Init.Minimal) !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Install signal handlers
    installSignalHandlers() catch |err| {
        std.debug.print("Warning: Could not install signal handlers: {}\n", .{err});
    };

    // Parse CLI arguments
    var cli_parser = lib.CLI.init(allocator);

    // Collect args from iterator
    var args_list = std.ArrayList([]const u8).empty;
    defer {
        for (args_list.items) |arg| allocator.free(arg);
        args_list.deinit(allocator);
    }
    var args_iter = try std.process.Args.Iterator.initAllocator(init.args, allocator);
    defer args_iter.deinit();
    while (args_iter.next()) |arg| {
        try args_list.append(allocator, try allocator.dupe(u8, arg));
    }
    const args = args_list.items;

    try cli_parser.parse(args);

    // Handle special flags
    if (cli_parser.options.help) {
        cli_parser.printHelp();
        return;
    }

    if (cli_parser.options.version) {
        cli_parser.printVersion();
        return;
    }

    // Configuration establishes defaults; parsing the arguments again makes
    // every explicitly supplied CLI flag take precedence.
    var config_loader = lib.ConfigLoader.init(allocator);
    defer config_loader.deinit();
    if (cli_parser.options.config) |config_path| {
        const config = config_loader.loadFromFile(config_path) catch |err| {
            std.debug.print("Error: invalid configuration '{s}': {s}\n", .{ config_path, @errorName(err) });
            std.process.exit(2);
        };
        cli_parser = lib.CLI.init(allocator);
        try cli_parser.applyConfig(config);
        try cli_parser.parse(args);
    }

    // Check if we should use test discovery or programmatic tests
    const use_discovery = cli_parser.options.test_dir != null;

    if (use_discovery) {
        if (cli_parser.unsupportedDiscoveryOption()) |option| {
            std.debug.print(
                "Error: {s} cannot be honored in test discovery mode\n",
                .{option},
            );
            std.process.exit(2);
        }
    }

    // Start UI server if requested
    var ui_server: ?lib.UIServer = null;

    defer {
        if (!keep_running.load(.monotonic)) {
            std.debug.print("Cleanup complete.\n", .{});
        }
        if (ui_server) |*server| {
            server.deinit();
        }
    }

    if (cli_parser.options.ui) {
        const ui_options = lib.UIServerOptions{
            .port = cli_parser.options.ui_port,
            .host = cli_parser.options.ui_host,
            .verbose = cli_parser.options.verbose,
        };

        ui_server = lib.UIServer.init(allocator, ui_options);
        try ui_server.?.start();

        std.debug.print("UI Server started at http://{s}:{d}\n", .{ ui_options.host, ui_server.?.port() });
        std.debug.print("Open this URL in your browser to view test results.\n\n", .{});
    }

    var all_passed: bool = undefined;
    const stdout_file = std.Io.File.stdout();
    var stdout_buffer: [4096]u8 = undefined;
    var reporter_io: std.Io.Threaded = .init(std.mem.Allocator.failing, .{ .environ = .empty });
    defer reporter_io.deinit();
    var stdout_writer = stdout_file.writer(reporter_io.io(), &stdout_buffer);
    const shard_options: ?lib.ShardOptions = if (cli_parser.options.shard_index) |index|
        .{ .index = index, .count = cli_parser.options.shard_count.? }
    else
        null;

    // Check if watch mode is enabled
    if (cli_parser.options.watch) {
        // Watch mode
        if (!use_discovery) {
            std.debug.print("Error: Watch mode requires --test-dir to be specified\n", .{});
            std.process.exit(1);
        }

        const test_dir = cli_parser.options.test_dir orelse ".";

        const watch_options = lib.WatchOptions{
            .watch_dir = test_dir,
            .project_root = ".",
            .pattern = cli_parser.options.pattern,
            .recursive = !cli_parser.options.no_recursive,
            .debounce_ms = cli_parser.options.watch_debounce,
            .clear_screen = true,
            .verbose = cli_parser.options.verbose,
            .interactive_commands = true,
        };

        var watcher = lib.TestWatcher.init(allocator, watch_options, &keep_running);

        // Create coverage options if coverage is enabled
        const cov_opts = if (cli_parser.options.coverage) lib.CoverageOptions{
            .enabled = true,
            .output_dir = cli_parser.options.coverage_dir,
            .tool = if (std.mem.eql(u8, cli_parser.options.coverage_tool, "grindcov"))
                .grindcov
            else
                .kcov,
            .html_report = true,
            .clean = true,
        } else null;

        const loader_options = lib.LoaderOptions{
            .bail = cli_parser.options.bail,
            .filter = cli_parser.options.filter,
            .verbose = cli_parser.options.verbose,
            .use_colors = !cli_parser.options.no_color,
            .shard = shard_options,
            .reporter_type = cli_parser.options.reporter,
            .junit_output = cli_parser.options.junit_output orelse "test-results.xml",
            .timeout_ms = cli_parser.options.timeout,
            .retries = cli_parser.options.retries,
            .repeat = cli_parser.options.repeat,
            .fail_on_flaky = cli_parser.options.fail_on_flaky,
            .shuffle = cli_parser.options.shuffle,
            .seed = cli_parser.options.seed,
            .reporter_writer = &stdout_writer.interface,
            .coverage_options = cov_opts,
            .ui_server = if (ui_server) |*server| server else null,
        };

        // Start watching (this will run tests initially and on changes)
        try watcher.watch(loader_options);

        all_passed = true;
    } else if (use_discovery) {
        // Regular discovery mode (non-watch)
        const discovery_options = lib.DiscoveryOptions{
            .root_path = cli_parser.options.test_dir orelse ".",
            .pattern = cli_parser.options.pattern,
            .recursive = !cli_parser.options.no_recursive,
        };

        std.debug.print("Discovering tests in '{s}' with pattern '{s}'...\n\n", .{ discovery_options.root_path, discovery_options.pattern });

        var discovered = try lib.discoverTests(allocator, discovery_options);
        defer discovered.deinit();

        // Create coverage options if coverage is enabled
        const cov_opts = if (cli_parser.options.coverage) lib.CoverageOptions{
            .enabled = true,
            .output_dir = cli_parser.options.coverage_dir,
            .tool = if (std.mem.eql(u8, cli_parser.options.coverage_tool, "grindcov"))
                .grindcov
            else
                .kcov,
            .html_report = true,
            .clean = true,
        } else null;

        const loader_options = lib.LoaderOptions{
            .bail = cli_parser.options.bail,
            .filter = cli_parser.options.filter,
            .verbose = cli_parser.options.verbose,
            .use_colors = !cli_parser.options.no_color,
            .shard = shard_options,
            .reporter_type = cli_parser.options.reporter,
            .junit_output = cli_parser.options.junit_output orelse "test-results.xml",
            .timeout_ms = cli_parser.options.timeout,
            .retries = cli_parser.options.retries,
            .repeat = cli_parser.options.repeat,
            .fail_on_flaky = cli_parser.options.fail_on_flaky,
            .shuffle = cli_parser.options.shuffle,
            .seed = cli_parser.options.seed,
            .reporter_writer = &stdout_writer.interface,
            .coverage_options = cov_opts,
            .ui_server = if (ui_server) |*server| server else null,
        };

        all_passed = try lib.runDiscoveredTests(allocator, &discovered, loader_options);
    } else {
        // Use programmatic test registration mode (existing behavior)
        const registry = lib.getRegistry(allocator);
        defer lib.cleanupRegistry();

        // Create test runner with CLI options
        var runner_options = cli_parser.toRunnerOptions();
        runner_options.reporter_writer = &stdout_writer.interface;
        var runner = lib.TestRunner.init(allocator, registry, runner_options);
        defer runner.deinit();

        // Run tests
        all_passed = runner.run() catch |err| {
            switch (err) {
                lib.test_runner.RunnerError.NoTestsFound => {
                    std.debug.print("\nNo tests found!\n", .{});
                    std.debug.print("Make sure to:\n", .{});
                    std.debug.print("  1. Register tests using describe() and it(), OR\n", .{});
                    std.debug.print("  2. Use --test-dir to discover *.test.zig files\n", .{});
                    std.process.exit(1);
                },
                else => return err,
            }
        };
    }

    // Exit with appropriate code
    if (all_passed) return;

    // `std.process.exit` does not run defers, so explicitly stop the server
    // before returning the unsuccessful process status.
    if (ui_server) |*server| server.deinit();
    ui_server = null;
    std.process.exit(1);
}
