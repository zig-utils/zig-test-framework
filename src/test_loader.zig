const std = @import("std");
const discovery = @import("discovery.zig");
const sharding = @import("sharding.zig");
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

    const selected_files = try selectedFileCount(discovered, options.shard);
    if (options.shard) |shard| {
        std.debug.print(
            "Shard {}/{}: selected {} of {} test file(s).\n",
            .{ shard.index, shard.count, selected_files, discovered.files.items.len },
        );
    }

    std.debug.print("Found {} test file(s):\n", .{selected_files});
    for (discovered.files.items) |file| {
        if (!try fileSelected(file.relative_path, options.shard)) continue;
        std.debug.print("  - {s}\n", .{file.relative_path});
    }
    std.debug.print("\n", .{});

    // Notify UI of run start
    if (options.ui_server) |server| {
        var buffer: [256]u8 = undefined;
        const json = try std.fmt.bufPrint(&buffer, "{{\"total\":{d}}}", .{selected_files});
        try server.broadcast("run_start", json);
    }

    var total_passed: usize = 0;
    var total_failed: usize = 0;
    var files_run: usize = 0;

    // Clean coverage directory once before all tests if coverage is enabled
    if (options.coverage_options) |cov_opts| {
        if (cov_opts.enabled and cov_opts.clean) {
            // TODO: deleteTree needs Io in Zig 0.16
            compat.makePath(allocator, cov_opts.output_dir) catch {};
        }
    }

    for (discovered.files.items) |file| {
        if (!try fileSelected(file.relative_path, options.shard)) continue;

        // Run each test file using zig test command
        std.debug.print("Running {s}...\n", .{file.relative_path});

        // Notify UI of test file start
        if (options.ui_server) |server| {
            var buffer: [512]u8 = undefined;
            const json = try std.fmt.bufPrint(&buffer, "{{\"name\":\"{s}\"}}", .{file.name});
            try server.broadcast("suite_start", json);
            try server.broadcast("test_start", json);
        }

        const start_time = compat.nanoTimestamp();
        const result = try runTestFile(allocator, file.path, options);
        const end_time = compat.nanoTimestamp();
        const execution_time_ns: u64 = @intCast(end_time - start_time);

        files_run += 1;

        // Notify UI of test file end
        if (options.ui_server) |server| {
            var buffer: [512]u8 = undefined;
            const status = if (result) "passed" else "failed";
            const json = try std.fmt.bufPrint(&buffer, "{{\"name\":\"{s}\",\"status\":\"{s}\",\"execution_time_ns\":{d},\"error_message\":\"\"}}", .{ file.name, status, execution_time_ns });
            try server.broadcast("test_end", json);
            try server.broadcast("suite_end", try std.fmt.bufPrint(&buffer, "{{\"name\":\"{s}\"}}", .{file.name}));
        }

        if (result) {
            total_passed += 1;
            if (options.verbose) {
                std.debug.print("  ✓ {s} passed\n", .{file.name});
            }
        } else {
            total_failed += 1;
            std.debug.print("  ✗ {s} failed\n", .{file.name});

            if (options.bail) {
                std.debug.print("\nStopping on first failure (--bail)\n", .{});
                break;
            }
        }
    }

    // Print coverage summary if enabled
    if (options.coverage_options) |cov_opts| {
        if (cov_opts.enabled and files_run > 0) {
            std.debug.print("\n", .{});
            const cov_result = coverage.parseCoverageReport(allocator, cov_opts.output_dir) catch |err| {
                std.debug.print("Warning: Could not parse coverage report: {any}\n", .{err});
                return total_failed == 0;
            };

            coverage.printCoverageSummary(cov_result);
        }
    }

    // Notify UI of run end
    if (options.ui_server) |server| {
        var buffer: [512]u8 = undefined;
        const json = try std.fmt.bufPrint(&buffer, "{{\"total\":{d},\"passed\":{d},\"failed\":{d},\"skipped\":0}}", .{ files_run, total_passed, total_failed });
        try server.broadcast("run_end", json);
    }

    std.debug.print("\n", .{});
    std.debug.print("Test Summary:\n", .{});
    if (options.shard) |shard| {
        std.debug.print("  Shard: {}/{}\n", .{ shard.index, shard.count });
        std.debug.print("  Selected: {} of {} files\n", .{ selected_files, discovered.files.items.len });
    }
    std.debug.print("  Files run: {}\n", .{files_run});
    std.debug.print("  Passed: {}\n", .{total_passed});
    std.debug.print("  Failed: {}\n", .{total_failed});

    return total_failed == 0;
}

fn fileSelected(relative_path: []const u8, shard: ?sharding.ShardOptions) !bool {
    return if (shard) |selection| selection.includes(relative_path) else true;
}

fn selectedFileCount(
    discovered: *const discovery.DiscoveryResult,
    shard: ?sharding.ShardOptions,
) !usize {
    var count: usize = 0;
    for (discovered.files.items) |file| {
        if (try fileSelected(file.relative_path, shard)) count += 1;
    }
    return count;
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
        total_selected += try selectedFileCount(
            &discovered,
            .{ .index = index, .count = 3 },
        );
    }

    try std.testing.expectEqual(discovered.files.items.len, total_selected);
}
