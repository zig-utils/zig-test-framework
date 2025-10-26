const std = @import("std");
const lib = @import("lib.zig");

// Global signal handler state
var shutdown_requested = std.atomic.Value(bool).init(false);

/// Signal handler for SIGINT and SIGTERM
fn handleSignal(sig: c_int) callconv(.c) void {
    _ = sig;
    shutdown_requested.store(true, .monotonic);
    std.debug.print("\n\nShutdown requested... cleaning up\n", .{});
}

/// Install signal handlers
fn installSignalHandlers() !void {
    const posix = std.posix;

    // Install SIGINT handler (Ctrl+C)
    const sigint_action = posix.Sigaction{
        .handler = .{ .handler = handleSignal },
        .mask = posix.sigemptyset(),
        .flags = 0,
    };
    posix.sigaction(posix.SIG.INT, &sigint_action, null);

    // Install SIGTERM handler
    const sigterm_action = posix.Sigaction{
        .handler = .{ .handler = handleSignal },
        .mask = posix.sigemptyset(),
        .flags = 0,
    };
    posix.sigaction(posix.SIG.TERM, &sigterm_action, null);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Install signal handlers
    installSignalHandlers() catch |err| {
        std.debug.print("Warning: Could not install signal handlers: {}\n", .{err});
    };

    // Parse CLI arguments
    var cli_parser = lib.CLI.init(allocator);
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

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

    // Check if we should use test discovery or programmatic tests
    const use_discovery = cli_parser.options.test_dir != null;

    // Start UI server if requested
    var ui_server: ?lib.UIServer = null;
    var ui_thread: ?std.Thread = null;
    var server_running = std.atomic.Value(bool).init(false);

    defer {
        if (shutdown_requested.load(.monotonic)) {
            std.debug.print("Cleanup complete.\n", .{});
        }
        if (ui_server) |*server| {
            server_running.store(false, .monotonic);
            server.deinit();
        }
        if (ui_thread) |thread| {
            thread.detach();
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

        std.debug.print("UI Server started at http://{s}:{d}\n", .{ ui_options.host, ui_options.port });
        std.debug.print("Open this URL in your browser to view test results.\n\n", .{});

        // Start server in background thread
        const ServerContext = struct {
            server: *lib.UIServer,
            running: *std.atomic.Value(bool),
            verbose: bool,

            fn run(ctx: @This()) void {
                ctx.running.store(true, .monotonic);
                while (ctx.running.load(.monotonic)) {
                    ctx.server.acceptClient() catch |err| {
                        if (ctx.verbose) {
                            std.debug.print("UI Server error: {any}\n", .{err});
                        }
                        // Small delay to avoid tight loop on errors
                        std.Thread.sleep(100 * std.time.ns_per_ms);
                    };
                }
            }
        };

        const server_ctx = ServerContext{
            .server = &ui_server.?,
            .running = &server_running,
            .verbose = cli_parser.options.verbose,
        };
        ui_thread = try std.Thread.spawn(.{}, ServerContext.run, .{server_ctx});

        // Give server time to start
        std.Thread.sleep(100 * std.time.ns_per_ms);
    }

    var all_passed: bool = undefined;

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
            .pattern = cli_parser.options.pattern,
            .recursive = !cli_parser.options.no_recursive,
            .debounce_ms = cli_parser.options.watch_debounce,
            .clear_screen = true,
            .verbose = cli_parser.options.verbose,
        };

        var watch_running = std.atomic.Value(bool).init(true);
        var watcher = lib.TestWatcher.init(allocator, watch_options, &watch_running);

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

        std.debug.print("Discovering tests in '{s}' with pattern '*{s}'...\n\n", .{ discovery_options.root_path, discovery_options.pattern });

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
            .coverage_options = cov_opts,
            .ui_server = if (ui_server) |*server| server else null,
        };

        all_passed = try lib.runDiscoveredTests(allocator, &discovered, loader_options);
    } else {
        // Use programmatic test registration mode (existing behavior)
        const registry = lib.getRegistry(allocator);
        defer lib.cleanupRegistry();

        // Create test runner with CLI options
        const runner_options = cli_parser.toRunnerOptions();
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
    if (all_passed) {
        std.process.exit(0);
    } else {
        std.process.exit(1);
    }
}
