const std = @import("std");
const discovery = @import("discovery.zig");
const coverage = @import("coverage.zig");
const ui_server = @import("ui_server.zig");

/// Options for running discovered tests
pub const LoaderOptions = struct {
    /// Whether to bail on first failure
    bail: bool = false,
    /// Filter to apply to test names
    filter: ?[]const u8 = null,
    /// Whether to show verbose output
    verbose: bool = false,
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

    std.debug.print("Found {} test file(s):\n", .{discovered.files.items.len});
    for (discovered.files.items) |file| {
        std.debug.print("  - {s}\n", .{file.relative_path});
    }
    std.debug.print("\n", .{});

    // Notify UI of run start
    if (options.ui_server) |server| {
        var buffer: [256]u8 = undefined;
        const json = try std.fmt.bufPrint(&buffer, "{{\"total\":{d}}}", .{discovered.files.items.len});
        try server.broadcast("run_start", json);
    }

    var total_passed: usize = 0;
    var total_failed: usize = 0;
    var files_run: usize = 0;

    // Clean coverage directory once before all tests if coverage is enabled
    if (options.coverage_options) |cov_opts| {
        if (cov_opts.enabled and cov_opts.clean) {
            std.fs.cwd().deleteTree(cov_opts.output_dir) catch {};
            try std.fs.cwd().makePath(cov_opts.output_dir);
        }
    }

    for (discovered.files.items) |file| {
        // Run each test file using zig test command
        std.debug.print("Running {s}...\n", .{file.relative_path});

        // Notify UI of test file start
        if (options.ui_server) |server| {
            var buffer: [512]u8 = undefined;
            const json = try std.fmt.bufPrint(&buffer, "{{\"name\":\"{s}\"}}", .{file.name});
            try server.broadcast("suite_start", json);
            try server.broadcast("test_start", json);
        }

        const start_time = std.time.nanoTimestamp();
        const result = try runTestFile(allocator, file.path, options);
        const end_time = std.time.nanoTimestamp();
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
        if (cov_opts.enabled) {
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
    std.debug.print("  Files run: {}\n", .{files_run});
    std.debug.print("  Passed: {}\n", .{total_passed});
    std.debug.print("  Failed: {}\n", .{total_failed});

    return total_failed == 0;
}

/// Run a single test file using `zig test`
fn runTestFile(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    options: LoaderOptions,
) !bool {
    // If coverage is enabled, use coverage.runTestWithCoverage
    if (options.coverage_options) |cov_opts| {
        if (cov_opts.enabled) {
            // Disable clean for individual test runs since we cleaned once at the start
            var modified_opts = cov_opts;
            modified_opts.clean = false;
            return coverage.runTestWithCoverage(allocator, file_path, modified_opts) catch |err| {
                std.debug.print("Warning: Coverage failed for {s}: {any}\n", .{ file_path, err });
                // Fall back to running without coverage
                return runTestFileWithoutCoverage(allocator, file_path);
            };
        }
    }

    return runTestFileWithoutCoverage(allocator, file_path);
}

/// Run a single test file without coverage
fn runTestFileWithoutCoverage(
    allocator: std.mem.Allocator,
    file_path: []const u8,
) !bool {
    // Build zig test command
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);

    try argv.append(allocator, "zig");
    try argv.append(allocator, "test");
    try argv.append(allocator, file_path);

    // Create child process
    var child = std.process.Child.init(argv.items, allocator);
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    // Run the test
    const term = try child.spawnAndWait();

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
    try std.testing.expectEqual(@as(?coverage.CoverageOptions, null), options.coverage_options);
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
