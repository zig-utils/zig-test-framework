const std = @import("std");
const discovery = @import("discovery.zig");
const sharding = @import("sharding.zig");
const pipeline = @import("pipeline.zig");
const reporter = @import("reporter.zig");
const suite = @import("suite.zig");
const coverage = @import("coverage.zig");
const ui_server = @import("ui_server.zig");
const compat = @import("compat.zig");

/// Options for running discovered tests
pub const LoaderOptions = struct {
    /// Whether to bail on first failure
    bail: bool = false,
    /// Filter to apply to test names
    filter: ?[]const u8 = null,
    /// Whether to show verbose output
    verbose: bool = false,
    /// Whether child Zig test processes may emit colors
    use_colors: bool = true,
    /// Optional one-based file shard to execute
    shard: ?sharding.ShardOptions = null,
    /// Reporter shared with programmatic execution
    reporter_type: reporter.ReporterType = .spec,
    /// Output path used by the JUnit reporter
    junit_output: []const u8 = "test-results.xml",
    /// Global per-file timeout checked by the shared execution policy
    timeout_ms: ?u64 = null,
    /// Optional output supplied by a CLI host. Embedded/test callers default
    /// to stderr so they do not interfere with Zig's stdout test protocol.
    reporter_writer: ?*std.Io.Writer = null,
    /// Coverage options
    coverage_options: ?coverage.CoverageOptions = null,
    /// UI server for real-time updates
    ui_server: ?*ui_server.UIServer = null,
};

/// Run all discovered test files
pub fn runDiscoveredTests(
    allocator: std.mem.Allocator,
    discovered: *discovery.DiscoveryResult,
    options: LoaderOptions,
) !bool {
    if (discovered.files.items.len == 0) {
        std.debug.print("No test files found.\n", .{});
        return false;
    }

    var plan = try discoveryPlan(allocator, discovered, options.shard);
    defer plan.deinit();
    const selected_files = plan.items.items.len;
    if (options.shard) |shard| {
        std.debug.print(
            "Shard {}/{}: selected {} of {} test file(s).\n",
            .{ shard.index, shard.count, selected_files, discovered.files.items.len },
        );
    }

    std.debug.print("Found {} test file(s):\n", .{selected_files});
    for (plan.items.items) |item| {
        const file = item.discovered;
        std.debug.print("  - {s}\n", .{file.relative_path});
    }
    std.debug.print("\n", .{});

    const stderr_file = std.Io.File.stderr();
    var stderr_buffer: [4096]u8 = undefined;
    var threaded_io: std.Io.Threaded = .init(std.mem.Allocator.failing, .{ .environ = .empty });
    defer threaded_io.deinit();
    var stderr_writer = stderr_file.writer(threaded_io.io(), &stderr_buffer);
    const reporter_writer = options.reporter_writer orelse &stderr_writer.interface;
    var reporters = reporter.ReporterSet.initRef(
        allocator,
        reporter_writer,
        options.reporter_type,
        options.junit_output,
        options.use_colors,
    );
    defer reporters.deinit();
    const events = pipeline.EventStream{ .rep = reporters.selected() };
    const policy = pipeline.ExecutionPolicy{
        .bail = options.bail,
        .filter = options.filter,
        .timeout_ms = options.timeout_ms,
    };
    var results = reporter.TestResults.init(allocator);
    defer results.deinit();

    try events.emit(.{ .run_started = selected_files });

    // Notify UI of run start
    if (options.ui_server) |server| {
        var buffer: [256]u8 = undefined;
        const json = try std.fmt.bufPrint(&buffer, "{{\"total\":{d}}}", .{selected_files});
        try server.broadcast("run_start", json);
    }

    var files_run: usize = 0;

    // Clean coverage directory once before all tests if coverage is enabled
    if (options.coverage_options) |cov_opts| {
        if (cov_opts.enabled and cov_opts.clean) {
            // TODO: deleteTree needs Io in Zig 0.16
            compat.makePath(allocator, cov_opts.output_dir) catch {};
        }
    }

    for (plan.items.items) |item| {
        const file = item.discovered;
        // Run each test file using zig test command
        std.debug.print("Running {s}...\n", .{file.relative_path});
        try events.emit(.{ .suite_started = file.relative_path });
        try events.emit(.{ .test_started = file.name });

        // Notify UI of test file start
        if (options.ui_server) |server| {
            var buffer: [512]u8 = undefined;
            const json = try std.fmt.bufPrint(&buffer, "{{\"name\":\"{s}\"}}", .{file.name});
            try server.broadcast("suite_start", json);
            try server.broadcast("test_start", json);
        }

        const start_time = compat.nanoTimestamp();
        var result = try runTestFile(allocator, file.path, options);
        const end_time = compat.nanoTimestamp();
        const execution_time_ns: u64 = @intCast(end_time - start_time);
        const timed_out = policy.timedOut(execution_time_ns);
        if (timed_out) result = false;

        files_run += 1;
        var test_case = suite.TestCase.init(file.name, externalTestNoop);
        test_case.file = file.relative_path;
        test_case.execution_time_ns = execution_time_ns;
        test_case.status = if (result) .passed else .failed;
        if (timed_out) {
            test_case.error_message = "External test file exceeded the configured timeout";
        } else if (!result) {
            test_case.error_message = "External zig test process failed";
        }
        try results.addTest(&test_case);
        try events.emit(.{ .test_finished = &test_case });
        try events.emit(.{ .suite_finished = file.relative_path });

        // Notify UI of test file end
        if (options.ui_server) |server| {
            var buffer: [512]u8 = undefined;
            const status = if (result) "passed" else "failed";
            const json = try std.fmt.bufPrint(&buffer, "{{\"name\":\"{s}\",\"status\":\"{s}\",\"execution_time_ns\":{d},\"error_message\":\"\"}}", .{ file.name, status, execution_time_ns });
            try server.broadcast("test_end", json);
            try server.broadcast("suite_end", try std.fmt.bufPrint(&buffer, "{{\"name\":\"{s}\"}}", .{file.name}));
        }

        if (result) {
            if (options.verbose) std.debug.print("  ✓ {s} passed\n", .{file.name});
        } else {
            std.debug.print("  ✗ {s} failed\n", .{file.name});
            if (policy.shouldStop(&results)) {
                std.debug.print("\nStopping on first failure (--bail)\n", .{});
                break;
            }
        }
    }

    // Print coverage summary if enabled
    if (options.coverage_options) |cov_opts| {
        if (cov_opts.enabled and files_run > 0) {
            std.debug.print("\n", .{});
            const cov_result: ?coverage.CoverageResult = coverage.parseCoverageReport(allocator, cov_opts.output_dir) catch |err| result: {
                std.debug.print("Warning: Could not parse coverage report: {any}\n", .{err});
                break :result null;
            };
            if (cov_result) |summary| coverage.printCoverageSummary(summary);
        }
    }

    // Notify UI of run end
    if (options.ui_server) |server| {
        var buffer: [512]u8 = undefined;
        const json = try std.fmt.bufPrint(&buffer, "{{\"total\":{d},\"passed\":{d},\"failed\":{d},\"skipped\":{d}}}", .{ results.total, results.passed, results.failed, results.skipped });
        try server.broadcast("run_end", json);
    }

    if (options.shard) |shard| {
        std.debug.print("\nShard Summary:\n", .{});
        std.debug.print("  Shard: {}/{}\n", .{ shard.index, shard.count });
        std.debug.print("  Selected: {} of {} files\n", .{ selected_files, discovered.files.items.len });
    }
    try events.emit(.{ .run_finished = &results });
    try reporters.flush();

    return results.failed == 0;
}

fn externalTestNoop(_: std.mem.Allocator) !void {}

fn fileSelected(relative_path: []const u8, shard: ?sharding.ShardOptions) !bool {
    return if (shard) |selection| selection.includes(relative_path) else true;
}

fn discoveryPlan(
    allocator: std.mem.Allocator,
    discovered: *discovery.DiscoveryResult,
    shard: ?sharding.ShardOptions,
) !pipeline.TestPlan {
    var plan = pipeline.TestPlan.init(allocator);
    errdefer plan.deinit();
    for (discovered.files.items) |*file| {
        if (try fileSelected(file.relative_path, shard)) try plan.appendDiscovered(file);
    }
    return plan;
}

/// Run a single test file using `zig test`
fn runTestFile(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    options: LoaderOptions,
) !bool {
    var test_args: std.ArrayList([]const u8) = .empty;
    defer test_args.deinit(allocator);

    try appendTestArgs(allocator, &test_args, options);

    // If coverage is enabled, use coverage.runTestWithCoverage
    if (options.coverage_options) |cov_opts| {
        if (cov_opts.enabled) {
            // Disable clean for individual test runs since we cleaned once at the start
            var modified_opts = cov_opts;
            modified_opts.clean = false;
            return coverage.runTestWithCoverageArgs(allocator, file_path, test_args.items, modified_opts) catch |err| {
                std.debug.print("Warning: Coverage failed for {s}: {any}\n", .{ file_path, err });
                // Fall back to running without coverage
                return runTestFileWithoutCoverage(allocator, file_path, test_args.items);
            };
        }
    }

    return runTestFileWithoutCoverage(allocator, file_path, test_args.items);
}

fn appendTestArgs(
    allocator: std.mem.Allocator,
    args: *std.ArrayList([]const u8),
    options: LoaderOptions,
) !void {
    if (options.filter) |filter| {
        try args.append(allocator, "--test-filter");
        try args.append(allocator, filter);
    }
    if (!options.use_colors) {
        try args.append(allocator, "--color");
        try args.append(allocator, "off");
    }
}

/// Run a single test file without coverage
fn runTestFileWithoutCoverage(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    test_args: []const []const u8,
) !bool {
    // Build zig test command
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);

    try argv.append(allocator, "zig");
    try argv.append(allocator, "test");
    try argv.append(allocator, file_path);
    try argv.appendSlice(allocator, test_args);

    // Run the test
    const term = try compat.spawnAndWait(allocator, argv.items, .Inherit, .Inherit);

    switch (term) {
        .Exited => |code| {
            return code == 0;
        },
        else => {
            return false;
        },
    }
}

test "LoaderOptions default values" {
    const options = LoaderOptions{};

    try std.testing.expectEqual(false, options.bail);
    try std.testing.expectEqual(@as(?[]const u8, null), options.filter);
    try std.testing.expectEqual(false, options.verbose);
    try std.testing.expectEqual(true, options.use_colors);
    try std.testing.expectEqual(@as(?sharding.ShardOptions, null), options.shard);
    try std.testing.expectEqual(reporter.ReporterType.spec, options.reporter_type);
    try std.testing.expectEqualStrings("test-results.xml", options.junit_output);
    try std.testing.expectEqual(@as(?u64, null), options.timeout_ms);
    try std.testing.expectEqual(@as(?*std.Io.Writer, null), options.reporter_writer);
    try std.testing.expectEqual(@as(?coverage.CoverageOptions, null), options.coverage_options);
}

test "test command options forward filter and color" {
    const allocator = std.testing.allocator;
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(allocator);

    try appendTestArgs(allocator, &args, .{
        .filter = "selected test",
        .use_colors = false,
    });

    try std.testing.expectEqual(@as(usize, 4), args.items.len);
    try std.testing.expectEqualStrings("--test-filter", args.items[0]);
    try std.testing.expectEqualStrings("selected test", args.items[1]);
    try std.testing.expectEqualStrings("--color", args.items[2]);
    try std.testing.expectEqualStrings("off", args.items[3]);
}

test "LoaderOptions with custom values" {
    const cov_opts = coverage.CoverageOptions{
        .enabled = true,
        .output_dir = "cov",
    };

    const options = LoaderOptions{
        .bail = true,
        .filter = "mytest",
        .verbose = true,
        .coverage_options = cov_opts,
    };

    try std.testing.expectEqual(true, options.bail);
    try std.testing.expectEqualStrings("mytest", options.filter.?);
    try std.testing.expectEqual(true, options.verbose);
    try std.testing.expect(options.coverage_options != null);
    try std.testing.expectEqual(true, options.coverage_options.?.enabled);
}

test "LoaderOptions with coverage disabled" {
    const options = LoaderOptions{
        .bail = false,
        .verbose = true,
        .coverage_options = null,
    };

    try std.testing.expectEqual(@as(?coverage.CoverageOptions, null), options.coverage_options);
}

test "file sharding partitions discovered files exactly once" {
    const allocator = std.testing.allocator;
    var discovered = discovery.DiscoveryResult.init(allocator);
    defer discovered.deinit();

    try discovered.addFile("tests/api.test.zig", "api.test.zig", "api.test.zig");
    try discovered.addFile("tests/db.test.zig", "db.test.zig", "db.test.zig");
    try discovered.addFile("tests/math.test.zig", "math.test.zig", "math.test.zig");
    try discovered.addFile("tests/string.test.zig", "string.test.zig", "string.test.zig");

    var total_selected: usize = 0;
    for (1..4) |index| {
        var plan = try discoveryPlan(allocator, &discovered, .{ .index = index, .count = 3 });
        defer plan.deinit();
        total_selected += plan.items.items.len;
    }

    try std.testing.expectEqual(discovered.files.items.len, total_selected);
}
