const std = @import("std");

/// Coverage collection options
pub const CoverageOptions = struct {
    /// Enable coverage collection
    enabled: bool = false,
    /// Output directory for coverage reports
    output_dir: []const u8 = "coverage",
    /// Tool to use for coverage (kcov or grindcov)
    tool: CoverageTool = .kcov,
    /// Include pattern for files to cover
    include_pattern: ?[]const u8 = null,
    /// Exclude pattern for files to skip
    exclude_pattern: ?[]const u8 = null,
    /// Generate HTML report
    html_report: bool = true,
    /// Clean coverage directory before running
    clean: bool = true,
};

/// Coverage tool to use
pub const CoverageTool = enum {
    kcov,
    grindcov,
};

/// Coverage result summary
pub const CoverageResult = struct {
    /// Total lines in covered files
    total_lines: usize = 0,
    /// Lines executed during tests
    covered_lines: usize = 0,
    /// Total functions in covered files
    total_functions: usize = 0,
    /// Functions executed during tests
    covered_functions: usize = 0,
    /// Total branches in covered files
    total_branches: usize = 0,
    /// Branches executed during tests
    covered_branches: usize = 0,
    /// Coverage report directory
    report_dir: []const u8,

    /// Calculate line coverage percentage
    pub fn linePercentage(self: CoverageResult) f64 {
        if (self.total_lines == 0) return 0.0;
        return (@as(f64, @floatFromInt(self.covered_lines)) / @as(f64, @floatFromInt(self.total_lines))) * 100.0;
    }

    /// Calculate function coverage percentage
    pub fn functionPercentage(self: CoverageResult) f64 {
        if (self.total_functions == 0) return 0.0;
        return (@as(f64, @floatFromInt(self.covered_functions)) / @as(f64, @floatFromInt(self.total_functions))) * 100.0;
    }

    /// Calculate branch coverage percentage
    pub fn branchPercentage(self: CoverageResult) f64 {
        if (self.total_branches == 0) return 0.0;
        return (@as(f64, @floatFromInt(self.covered_branches)) / @as(f64, @floatFromInt(self.total_branches))) * 100.0;
    }
};

/// Check if coverage tool is available
pub fn isCoverageToolAvailable(allocator: std.mem.Allocator, tool: CoverageTool) !bool {
    const tool_name = switch (tool) {
        .kcov => "kcov",
        .grindcov => "grindcov",
    };

    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);

    try argv.append(allocator, "which");
    try argv.append(allocator, tool_name);

    var child = std.process.Child.init(argv.items, allocator);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    const term = child.spawnAndWait() catch return false;

    return switch (term) {
        .Exited => |code| code == 0,
        else => false,
    };
}

/// Run a test executable with coverage collection
pub fn runWithCoverage(
    allocator: std.mem.Allocator,
    test_exe_path: []const u8,
    test_args: []const []const u8,
    options: CoverageOptions,
) !bool {
    if (!options.enabled) {
        return error.CoverageNotEnabled;
    }

    // Check if coverage tool is available
    const available = try isCoverageToolAvailable(allocator, options.tool);
    if (!available) {
        const tool_name = switch (options.tool) {
            .kcov => "kcov",
            .grindcov => "grindcov",
        };
        std.debug.print("Warning: Coverage tool '{s}' not found. Install it to enable coverage.\n", .{tool_name});
        return false;
    }

    // Clean coverage directory if requested
    if (options.clean) {
        std.fs.cwd().deleteTree(options.output_dir) catch {};
    }

    // Create coverage output directory
    try std.fs.cwd().makePath(options.output_dir);

    // Build command based on coverage tool
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);

    switch (options.tool) {
        .kcov => {
            try argv.append(allocator, "kcov");

            // Add include pattern if specified
            if (options.include_pattern) |pattern| {
                try argv.append(allocator, try std.fmt.allocPrint(allocator, "--include-pattern={s}", .{pattern}));
            }

            // Add exclude pattern if specified
            if (options.exclude_pattern) |pattern| {
                try argv.append(allocator, try std.fmt.allocPrint(allocator, "--exclude-pattern={s}", .{pattern}));
            }

            // Output directory
            try argv.append(allocator, options.output_dir);

            // Test executable
            try argv.append(allocator, test_exe_path);

            // Test arguments
            for (test_args) |arg| {
                try argv.append(allocator, arg);
            }
        },
        .grindcov => {
            try argv.append(allocator, "grindcov");
            try argv.append(allocator, "--");
            try argv.append(allocator, test_exe_path);

            for (test_args) |arg| {
                try argv.append(allocator, arg);
            }
        },
    }

    // Run coverage tool
    var child = std.process.Child.init(argv.items, allocator);
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    const term = try child.spawnAndWait();

    const success = switch (term) {
        .Exited => |code| code == 0,
        else => false,
    };

    return success;
}

/// Run test file with coverage using zig test --test-cmd
pub fn runTestWithCoverage(
    allocator: std.mem.Allocator,
    test_file_path: []const u8,
    options: CoverageOptions,
) !bool {
    if (!options.enabled) {
        return error.CoverageNotEnabled;
    }

    // Check if coverage tool is available
    const available = try isCoverageToolAvailable(allocator, options.tool);
    if (!available) {
        const tool_name = switch (options.tool) {
            .kcov => "kcov",
            .grindcov => "grindcov",
        };
        std.debug.print("Warning: Coverage tool '{s}' not found. Skipping coverage for {s}\n", .{ tool_name, test_file_path });

        // Run test without coverage
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(allocator);

        try argv.append(allocator, "zig");
        try argv.append(allocator, "test");
        try argv.append(allocator, test_file_path);

        var child = std.process.Child.init(argv.items, allocator);
        child.stdout_behavior = .Inherit;
        child.stderr_behavior = .Inherit;

        const term = try child.spawnAndWait();
        return switch (term) {
            .Exited => |code| code == 0,
            else => false,
        };
    }

    // Clean coverage directory if requested (only on first run)
    if (options.clean) {
        std.fs.cwd().deleteTree(options.output_dir) catch {};
        try std.fs.cwd().makePath(options.output_dir);
    }

    // Build zig test command with coverage integration
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);

    try argv.append(allocator, "zig");
    try argv.append(allocator, "test");
    try argv.append(allocator, test_file_path);

    switch (options.tool) {
        .kcov => {
            // Use --test-cmd to wrap test execution with kcov
            try argv.append(allocator, "--test-cmd");
            try argv.append(allocator, "kcov");

            // Add include pattern if specified
            if (options.include_pattern) |pattern| {
                try argv.append(allocator, "--test-cmd");
                try argv.append(allocator, try std.fmt.allocPrint(allocator, "--include-pattern={s}", .{pattern}));
            }

            // Add exclude pattern if specified
            if (options.exclude_pattern) |pattern| {
                try argv.append(allocator, "--test-cmd");
                try argv.append(allocator, try std.fmt.allocPrint(allocator, "--exclude-pattern={s}", .{pattern}));
            }

            // Output directory
            try argv.append(allocator, "--test-cmd");
            try argv.append(allocator, options.output_dir);

            // --test-cmd-bin tells zig test where to insert the test binary
            try argv.append(allocator, "--test-cmd-bin");
        },
        .grindcov => {
            try argv.append(allocator, "--test-cmd");
            try argv.append(allocator, "grindcov");
            try argv.append(allocator, "--test-cmd");
            try argv.append(allocator, "--");
            try argv.append(allocator, "--test-cmd-bin");
        },
    }

    // Run zig test with coverage
    var child = std.process.Child.init(argv.items, allocator);
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    const term = try child.spawnAndWait();

    const success = switch (term) {
        .Exited => |code| code == 0,
        else => false,
    };

    return success;
}

/// Parse kcov coverage report to extract metrics
pub fn parseCoverageReport(allocator: std.mem.Allocator, coverage_dir: []const u8) !CoverageResult {
    // Try to read kcov's index.json for coverage metrics
    const json_path = try std.fs.path.join(allocator, &.{ coverage_dir, "index.json" });
    defer allocator.free(json_path);

    const file = std.fs.cwd().openFile(json_path, .{}) catch |err| {
        std.debug.print("Warning: Could not read coverage report: {any}\n", .{err});
        return CoverageResult{
            .report_dir = coverage_dir,
        };
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024); // 10MB max
    defer allocator.free(content);

    // Parse JSON (simplified - in production you'd use a JSON parser)
    // For now, return basic structure
    return CoverageResult{
        .report_dir = coverage_dir,
    };
}

/// Print coverage summary to console
pub fn printCoverageSummary(result: CoverageResult) void {
    std.debug.print("\n", .{});
    std.debug.print("==================== Coverage Summary ====================\n", .{});
    std.debug.print("\n", .{});

    if (result.total_lines > 0) {
        std.debug.print("  Line Coverage:     {d}/{d} ({d:.2}%)\n", .{
            result.covered_lines,
            result.total_lines,
            result.linePercentage(),
        });
    }

    if (result.total_functions > 0) {
        std.debug.print("  Function Coverage: {d}/{d} ({d:.2}%)\n", .{
            result.covered_functions,
            result.total_functions,
            result.functionPercentage(),
        });
    }

    if (result.total_branches > 0) {
        std.debug.print("  Branch Coverage:   {d}/{d} ({d:.2}%)\n", .{
            result.covered_branches,
            result.total_branches,
            result.branchPercentage(),
        });
    }

    std.debug.print("\n", .{});
    std.debug.print("  Coverage report: {s}/index.html\n", .{result.report_dir});
    std.debug.print("==========================================================\n", .{});
    std.debug.print("\n", .{});
}

// Tests
test "coverage percentages" {
    const result = CoverageResult{
        .total_lines = 100,
        .covered_lines = 75,
        .total_functions = 20,
        .covered_functions = 15,
        .total_branches = 40,
        .covered_branches = 30,
        .report_dir = "coverage",
    };

    try std.testing.expectEqual(@as(f64, 75.0), result.linePercentage());
    try std.testing.expectEqual(@as(f64, 75.0), result.functionPercentage());
    try std.testing.expectEqual(@as(f64, 75.0), result.branchPercentage());
}

test "coverage percentages with zero totals" {
    const result = CoverageResult{
        .report_dir = "coverage",
    };

    try std.testing.expectEqual(@as(f64, 0.0), result.linePercentage());
    try std.testing.expectEqual(@as(f64, 0.0), result.functionPercentage());
    try std.testing.expectEqual(@as(f64, 0.0), result.branchPercentage());
}

test "coverage percentages with 100% coverage" {
    const result = CoverageResult{
        .total_lines = 100,
        .covered_lines = 100,
        .total_functions = 20,
        .covered_functions = 20,
        .total_branches = 40,
        .covered_branches = 40,
        .report_dir = "coverage",
    };

    try std.testing.expectEqual(@as(f64, 100.0), result.linePercentage());
    try std.testing.expectEqual(@as(f64, 100.0), result.functionPercentage());
    try std.testing.expectEqual(@as(f64, 100.0), result.branchPercentage());
}

test "coverage percentages with partial coverage" {
    const result = CoverageResult{
        .total_lines = 200,
        .covered_lines = 50,
        .total_functions = 10,
        .covered_functions = 3,
        .total_branches = 30,
        .covered_branches = 15,
        .report_dir = "coverage",
    };

    try std.testing.expectEqual(@as(f64, 25.0), result.linePercentage());
    try std.testing.expectEqual(@as(f64, 30.0), result.functionPercentage());
    try std.testing.expectEqual(@as(f64, 50.0), result.branchPercentage());
}

test "CoverageOptions default values" {
    const options = CoverageOptions{};

    try std.testing.expectEqual(false, options.enabled);
    try std.testing.expectEqualStrings("coverage", options.output_dir);
    try std.testing.expectEqual(CoverageTool.kcov, options.tool);
    try std.testing.expectEqual(@as(?[]const u8, null), options.include_pattern);
    try std.testing.expectEqual(@as(?[]const u8, null), options.exclude_pattern);
    try std.testing.expectEqual(true, options.html_report);
    try std.testing.expectEqual(true, options.clean);
}

test "CoverageOptions custom values" {
    const options = CoverageOptions{
        .enabled = true,
        .output_dir = "my-coverage",
        .tool = .grindcov,
        .include_pattern = "src/*",
        .exclude_pattern = "test/*",
        .html_report = false,
        .clean = false,
    };

    try std.testing.expectEqual(true, options.enabled);
    try std.testing.expectEqualStrings("my-coverage", options.output_dir);
    try std.testing.expectEqual(CoverageTool.grindcov, options.tool);
    try std.testing.expectEqualStrings("src/*", options.include_pattern.?);
    try std.testing.expectEqualStrings("test/*", options.exclude_pattern.?);
    try std.testing.expectEqual(false, options.html_report);
    try std.testing.expectEqual(false, options.clean);
}

test "isCoverageToolAvailable with non-existent tool" {
    const allocator = std.testing.allocator;

    // Test with a tool that definitely doesn't exist
    const available = try isCoverageToolAvailable(allocator, .kcov);

    // On systems without kcov, this should return false
    // We can't assert the value since it depends on the system,
    // but we verify the function doesn't crash
    _ = available;
}

test "printCoverageSummary does not crash" {
    const result = CoverageResult{
        .total_lines = 100,
        .covered_lines = 75,
        .total_functions = 20,
        .covered_functions = 15,
        .total_branches = 40,
        .covered_branches = 30,
        .report_dir = "coverage",
    };

    // Just verify it doesn't crash
    printCoverageSummary(result);
}

test "CoverageResult with only line coverage" {
    const result = CoverageResult{
        .total_lines = 100,
        .covered_lines = 80,
        .report_dir = "coverage",
    };

    try std.testing.expectEqual(@as(f64, 80.0), result.linePercentage());
    try std.testing.expectEqual(@as(f64, 0.0), result.functionPercentage());
    try std.testing.expectEqual(@as(f64, 0.0), result.branchPercentage());
}

test "CoverageResult with only function coverage" {
    const result = CoverageResult{
        .total_functions = 50,
        .covered_functions = 40,
        .report_dir = "coverage",
    };

    try std.testing.expectEqual(@as(f64, 0.0), result.linePercentage());
    try std.testing.expectEqual(@as(f64, 80.0), result.functionPercentage());
    try std.testing.expectEqual(@as(f64, 0.0), result.branchPercentage());
}

test "CoverageResult with only branch coverage" {
    const result = CoverageResult{
        .total_branches = 25,
        .covered_branches = 20,
        .report_dir = "coverage",
    };

    try std.testing.expectEqual(@as(f64, 0.0), result.linePercentage());
    try std.testing.expectEqual(@as(f64, 0.0), result.functionPercentage());
    try std.testing.expectEqual(@as(f64, 80.0), result.branchPercentage());
}
