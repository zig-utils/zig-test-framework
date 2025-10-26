const std = @import("std");
const suite = @import("suite.zig");

/// ANSI color codes
pub const Colors = struct {
    pub const reset = "\x1b[0m";
    pub const bold = "\x1b[1m";
    pub const dim = "\x1b[2m";
    pub const red = "\x1b[31m";
    pub const green = "\x1b[32m";
    pub const yellow = "\x1b[33m";
    pub const blue = "\x1b[34m";
    pub const magenta = "\x1b[35m";
    pub const cyan = "\x1b[36m";
    pub const white = "\x1b[37m";
    pub const gray = "\x1b[90m";
};

/// Reporter interface
pub const Reporter = struct {
    vtable: *const VTable,
    allocator: std.mem.Allocator,
    use_colors: bool = true,

    const Self = @This();

    pub const VTable = struct {
        onRunStart: *const fn (self: *Reporter, total_tests: usize) anyerror!void,
        onRunEnd: *const fn (self: *Reporter, results: *TestResults) anyerror!void,
        onSuiteStart: *const fn (self: *Reporter, suite_name: []const u8) anyerror!void,
        onSuiteEnd: *const fn (self: *Reporter, suite_name: []const u8) anyerror!void,
        onTestStart: *const fn (self: *Reporter, test_name: []const u8) anyerror!void,
        onTestEnd: *const fn (self: *Reporter, test_case: *const suite.TestCase) anyerror!void,
    };

    pub fn onRunStart(self: *Self, total_tests: usize) !void {
        try self.vtable.onRunStart(self, total_tests);
    }

    pub fn onRunEnd(self: *Self, results: *TestResults) !void {
        try self.vtable.onRunEnd(self, results);
    }

    pub fn onSuiteStart(self: *Self, suite_name: []const u8) !void {
        try self.vtable.onSuiteStart(self, suite_name);
    }

    pub fn onSuiteEnd(self: *Self, suite_name: []const u8) !void {
        try self.vtable.onSuiteEnd(self, suite_name);
    }

    pub fn onTestStart(self: *Self, test_name: []const u8) !void {
        try self.vtable.onTestStart(self, test_name);
    }

    pub fn onTestEnd(self: *Self, test_case: *const suite.TestCase) !void {
        try self.vtable.onTestEnd(self, test_case);
    }
};

/// Test results summary
pub const TestResults = struct {
    total: usize = 0,
    passed: usize = 0,
    failed: usize = 0,
    skipped: usize = 0,
    total_time_ns: u64 = 0,
    failed_tests: std.ArrayList(suite.TestCase),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TestResults {
        return TestResults{
            .failed_tests = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TestResults) void {
        self.failed_tests.deinit(self.allocator);
    }

    pub fn addTest(self: *TestResults, test_case: *const suite.TestCase) !void {
        self.total += 1;
        self.total_time_ns += test_case.execution_time_ns;

        switch (test_case.status) {
            .passed => self.passed += 1,
            .failed => {
                self.failed += 1;
                try self.failed_tests.append(self.allocator, test_case.*);
            },
            .skipped => self.skipped += 1,
            else => {},
        }
    }
};

/// Default/Spec reporter
pub const SpecReporter = struct {
    reporter: Reporter,
    indent_level: usize = 0,
    writer: std.io.Writer,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, writer: std.io.Writer) Self {
        return Self{
            .reporter = Reporter{
                .vtable = &vtable,
                .allocator = allocator,
            },
            .writer = writer,
        };
    }

    const vtable = Reporter.VTable{
        .onRunStart = onRunStart,
        .onRunEnd = onRunEnd,
        .onSuiteStart = onSuiteStart,
        .onSuiteEnd = onSuiteEnd,
        .onTestStart = onTestStart,
        .onTestEnd = onTestEnd,
    };

    fn self(reporter: *Reporter) *Self {
        return @fieldParentPtr("reporter", reporter);
    }

    fn onRunStart(reporter: *Reporter, total_tests: usize) !void {
        const s = self(reporter);
        try s.writer.print("\n", .{});
        if (reporter.use_colors) {
            try s.writer.print("{s}Running {d} test(s)...{s}\n\n", .{ Colors.bold, total_tests, Colors.reset });
        } else {
            try s.writer.print("Running {d} test(s)...\n\n", .{total_tests});
        }
    }

    fn onRunEnd(reporter: *Reporter, results: *TestResults) !void {
        const s = self(reporter);
        try s.writer.print("\n", .{});

        // Print failed tests details
        if (results.failed > 0) {
            if (reporter.use_colors) {
                try s.writer.print("{s}Failed Tests:{s}\n\n", .{ Colors.bold ++ Colors.red, Colors.reset });
            } else {
                try s.writer.print("Failed Tests:\n\n", .{});
            }

            for (results.failed_tests.items) |test_case| {
                if (reporter.use_colors) {
                    try s.writer.print("  {s}✗{s} {s}\n", .{ Colors.red, Colors.reset, test_case.name });
                } else {
                    try s.writer.print("  ✗ {s}\n", .{test_case.name});
                }
                if (test_case.error_message) |msg| {
                    try s.writer.print("    {s}\n", .{msg});
                }
            }
            try s.writer.print("\n", .{});
        }

        // Print summary
        const total_time_ms = @as(f64, @floatFromInt(results.total_time_ns)) / 1_000_000.0;

        if (reporter.use_colors) {
            try s.writer.print("{s}Test Summary:{s}\n", .{ Colors.bold, Colors.reset });
            try s.writer.print("  Total:   {d}\n", .{results.total});
            try s.writer.print("  {s}Passed:  {d}{s}\n", .{ Colors.green, results.passed, Colors.reset });
            if (results.failed > 0) {
                try s.writer.print("  {s}Failed:  {d}{s}\n", .{ Colors.red, results.failed, Colors.reset });
            }
            if (results.skipped > 0) {
                try s.writer.print("  {s}Skipped: {d}{s}\n", .{ Colors.yellow, results.skipped, Colors.reset });
            }
            try s.writer.print("  Time:    {d:.2}ms\n", .{total_time_ms});
        } else {
            try s.writer.print("Test Summary:\n", .{});
            try s.writer.print("  Total:   {d}\n", .{results.total});
            try s.writer.print("  Passed:  {d}\n", .{results.passed});
            if (results.failed > 0) {
                try s.writer.print("  Failed:  {d}\n", .{results.failed});
            }
            if (results.skipped > 0) {
                try s.writer.print("  Skipped: {d}\n", .{results.skipped});
            }
            try s.writer.print("  Time:    {d:.2}ms\n", .{total_time_ms});
        }
    }

    fn onSuiteStart(reporter: *Reporter, suite_name: []const u8) !void {
        const s = self(reporter);

        // Print indent
        var i: usize = 0;
        while (i < s.indent_level) : (i += 1) {
            try s.writer.print("  ", .{});
        }

        if (reporter.use_colors) {
            try s.writer.print("{s}{s}{s}\n", .{ Colors.bold, suite_name, Colors.reset });
        } else {
            try s.writer.print("{s}\n", .{suite_name});
        }
        s.indent_level += 1;
    }

    fn onSuiteEnd(reporter: *Reporter, suite_name: []const u8) !void {
        _ = suite_name;
        const s = self(reporter);
        if (s.indent_level > 0) {
            s.indent_level -= 1;
        }
    }

    fn onTestStart(reporter: *Reporter, test_name: []const u8) !void {
        _ = reporter;
        _ = test_name;
    }

    fn onTestEnd(reporter: *Reporter, test_case: *const suite.TestCase) !void {
        const s = self(reporter);

        // Print indent
        var i: usize = 0;
        while (i < s.indent_level) : (i += 1) {
            try s.writer.print("  ", .{});
        }

        const time_ms = @as(f64, @floatFromInt(test_case.execution_time_ns)) / 1_000_000.0;

        switch (test_case.status) {
            .passed => {
                if (reporter.use_colors) {
                    try s.writer.print("{s}✓{s} {s} {s}({d:.2}ms){s}\n", .{
                        Colors.green,
                        Colors.reset,
                        test_case.name,
                        Colors.gray,
                        time_ms,
                        Colors.reset,
                    });
                } else {
                    try s.writer.print("✓ {s} ({d:.2}ms)\n", .{ test_case.name, time_ms });
                }
            },
            .failed => {
                if (reporter.use_colors) {
                    try s.writer.print("{s}✗{s} {s} {s}({d:.2}ms){s}\n", .{
                        Colors.red,
                        Colors.reset,
                        test_case.name,
                        Colors.gray,
                        time_ms,
                        Colors.reset,
                    });
                } else {
                    try s.writer.print("✗ {s} ({d:.2}ms)\n", .{ test_case.name, time_ms });
                }
            },
            .skipped => {
                if (reporter.use_colors) {
                    try s.writer.print("{s}⊘{s} {s} {s}(skipped){s}\n", .{
                        Colors.yellow,
                        Colors.reset,
                        test_case.name,
                        Colors.gray,
                        Colors.reset,
                    });
                } else {
                    try s.writer.print("⊘ {s} (skipped)\n", .{test_case.name});
                }
            },
            else => {},
        }
    }
};

/// Dot reporter (minimal output)
pub const DotReporter = struct {
    reporter: Reporter,
    writer: std.io.Writer,
    tests_per_line: usize = 80,
    current_line_count: usize = 0,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, writer: std.io.Writer) Self {
        return Self{
            .reporter = Reporter{
                .vtable = &vtable,
                .allocator = allocator,
            },
            .writer = writer,
        };
    }

    const vtable = Reporter.VTable{
        .onRunStart = onRunStart,
        .onRunEnd = onRunEnd,
        .onSuiteStart = onSuiteStart,
        .onSuiteEnd = onSuiteEnd,
        .onTestStart = onTestStart,
        .onTestEnd = onTestEnd,
    };

    fn self(reporter: *Reporter) *Self {
        return @fieldParentPtr("reporter", reporter);
    }

    fn onRunStart(reporter: *Reporter, total_tests: usize) !void {
        const s = self(reporter);
        try s.writer.print("\nRunning {d} tests:\n", .{total_tests});
    }

    fn onRunEnd(reporter: *Reporter, results: *TestResults) !void {
        const s = self(reporter);
        try s.writer.print("\n\n", .{});

        const total_time_ms = @as(f64, @floatFromInt(results.total_time_ns)) / 1_000_000.0;

        if (reporter.use_colors) {
            try s.writer.print("{s}Passed: {d}{s}, ", .{ Colors.green, results.passed, Colors.reset });
            try s.writer.print("{s}Failed: {d}{s}, ", .{ Colors.red, results.failed, Colors.reset });
            try s.writer.print("Total: {d} ({d:.2}ms)\n", .{ results.total, total_time_ms });
        } else {
            try s.writer.print("Passed: {d}, Failed: {d}, Total: {d} ({d:.2}ms)\n", .{
                results.passed,
                results.failed,
                results.total,
                total_time_ms,
            });
        }
    }

    fn onSuiteStart(reporter: *Reporter, suite_name: []const u8) !void {
        _ = reporter;
        _ = suite_name;
    }

    fn onSuiteEnd(reporter: *Reporter, suite_name: []const u8) !void {
        _ = reporter;
        _ = suite_name;
    }

    fn onTestStart(reporter: *Reporter, test_name: []const u8) !void {
        _ = reporter;
        _ = test_name;
    }

    fn onTestEnd(reporter: *Reporter, test_case: *const suite.TestCase) !void {
        const s = self(reporter);

        switch (test_case.status) {
            .passed => {
                if (reporter.use_colors) {
                    try s.writer.print("{s}.{s}", .{ Colors.green, Colors.reset });
                } else {
                    try s.writer.print(".", .{});
                }
            },
            .failed => {
                if (reporter.use_colors) {
                    try s.writer.print("{s}F{s}", .{ Colors.red, Colors.reset });
                } else {
                    try s.writer.print("F", .{});
                }
            },
            .skipped => {
                if (reporter.use_colors) {
                    try s.writer.print("{s}S{s}", .{ Colors.yellow, Colors.reset });
                } else {
                    try s.writer.print("S", .{});
                }
            },
            else => {},
        }

        s.current_line_count += 1;
        if (s.current_line_count >= s.tests_per_line) {
            try s.writer.print("\n", .{});
            s.current_line_count = 0;
        }
    }
};

/// JSON reporter
pub const JsonReporter = struct {
    reporter: Reporter,
    writer: std.io.Writer,
    suites: std.ArrayList([]const u8),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, writer: std.io.Writer) Self {
        return Self{
            .reporter = Reporter{
                .vtable = &vtable,
                .allocator = allocator,
            },
            .writer = writer,
            .suites = .empty,
        };
    }

    pub fn deinit(s: *Self) void {
        s.suites.deinit(s.reporter.allocator);
    }

    const vtable = Reporter.VTable{
        .onRunStart = onRunStart,
        .onRunEnd = onRunEnd,
        .onSuiteStart = onSuiteStart,
        .onSuiteEnd = onSuiteEnd,
        .onTestStart = onTestStart,
        .onTestEnd = onTestEnd,
    };

    fn self(reporter: *Reporter) *Self {
        return @fieldParentPtr("reporter", reporter);
    }

    fn onRunStart(reporter: *Reporter, total_tests: usize) !void {
        const s = self(reporter);
        try s.writer.print("{{\"totalTests\":{d},\"tests\":[\n", .{total_tests});
    }

    fn onRunEnd(reporter: *Reporter, results: *TestResults) !void {
        const s = self(reporter);
        const total_time_ms = @as(f64, @floatFromInt(results.total_time_ns)) / 1_000_000.0;

        try s.writer.print("],\"summary\":{{\"total\":{d},\"passed\":{d},\"failed\":{d},\"skipped\":{d},\"time\":{d:.2}}}}}\n", .{
            results.total,
            results.passed,
            results.failed,
            results.skipped,
            total_time_ms,
        });
    }

    fn onSuiteStart(reporter: *Reporter, suite_name: []const u8) !void {
        const s = self(reporter);
        try s.suites.append(reporter.allocator, suite_name);
    }

    fn onSuiteEnd(reporter: *Reporter, suite_name: []const u8) !void {
        _ = suite_name;
        const s = self(reporter);
        if (s.suites.items.len > 0) {
            _ = s.suites.pop();
        }
    }

    fn onTestStart(reporter: *Reporter, test_name: []const u8) !void {
        _ = reporter;
        _ = test_name;
    }

    fn onTestEnd(reporter: *Reporter, test_case: *const suite.TestCase) !void {
        const s = self(reporter);
        const time_ms = @as(f64, @floatFromInt(test_case.execution_time_ns)) / 1_000_000.0;

        const status_str = switch (test_case.status) {
            .passed => "passed",
            .failed => "failed",
            .skipped => "skipped",
            else => "unknown",
        };

        // Note: In a real implementation, you'd want to properly escape JSON strings
        try s.writer.print("  {{\"name\":\"{s}\",\"status\":\"{s}\",\"time\":{d:.2}", .{
            test_case.name,
            status_str,
            time_ms,
        });

        if (test_case.error_message) |msg| {
            try s.writer.print(",\"error\":\"{s}\"", .{msg});
        }

        try s.writer.print("}},\n", .{});
    }
};
