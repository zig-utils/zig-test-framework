const std = @import("std");
const suite = @import("suite.zig");
const compat = @import("compat.zig");

pub const ReporterType = enum {
    spec,
    dot,
    json,
    tap,
    junit,
};

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
    flaky: usize = 0,
    failed: usize = 0,
    skipped: usize = 0,
    total_time_ns: u64 = 0,
    failed_tests: std.ArrayList(suite.TestCase),
    flaky_tests: std.ArrayList(suite.TestCase),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TestResults {
        return TestResults{
            .failed_tests = .empty,
            .flaky_tests = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TestResults) void {
        self.failed_tests.deinit(self.allocator);
        self.flaky_tests.deinit(self.allocator);
    }

    pub fn addTest(self: *TestResults, test_case: *const suite.TestCase) !void {
        self.total += 1;
        self.total_time_ns += test_case.execution_time_ns;

        switch (test_case.status) {
            .passed => self.passed += 1,
            .flaky => {
                self.flaky += 1;
                try self.flaky_tests.append(self.allocator, test_case.*);
            },
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
    writer: std.Io.Writer,
    writer_ref: ?*std.Io.Writer = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, writer: std.Io.Writer) Self {
        return Self{
            .reporter = Reporter{
                .vtable = &vtable,
                .allocator = allocator,
            },
            .writer = writer,
        };
    }

    pub fn initRef(allocator: std.mem.Allocator, writer: *std.Io.Writer) Self {
        var result = init(allocator, writer.*);
        result.writer_ref = writer;
        return result;
    }

    fn output(instance: *Self) *std.Io.Writer {
        return instance.writer_ref orelse &instance.writer;
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
        try s.output().print("\n", .{});
        if (reporter.use_colors) {
            try s.output().print("{s}Running {d} test(s)...{s}\n\n", .{ Colors.bold, total_tests, Colors.reset });
        } else {
            try s.output().print("Running {d} test(s)...\n\n", .{total_tests});
        }
    }

    fn onRunEnd(reporter: *Reporter, results: *TestResults) !void {
        const s = self(reporter);
        try s.output().print("\n", .{});

        // Print failed tests details
        if (results.failed > 0) {
            if (reporter.use_colors) {
                try s.output().print("{s}Failed Tests:{s}\n\n", .{ Colors.bold ++ Colors.red, Colors.reset });
            } else {
                try s.output().print("Failed Tests:\n\n", .{});
            }

            for (results.failed_tests.items) |test_case| {
                if (reporter.use_colors) {
                    try s.output().print("  {s}✗{s} {s}\n", .{ Colors.red, Colors.reset, test_case.name });
                } else {
                    try s.output().print("  ✗ {s}\n", .{test_case.name});
                }
                if (test_case.error_message) |msg| {
                    try s.output().print("    {s}\n", .{msg});
                }
            }
            try s.output().print("\n", .{});
        }

        // Print summary
        const total_time_ms = @as(f64, @floatFromInt(results.total_time_ns)) / 1_000_000.0;

        if (reporter.use_colors) {
            try s.output().print("{s}Test Summary:{s}\n", .{ Colors.bold, Colors.reset });
            try s.output().print("  Total:   {d}\n", .{results.total});
            try s.output().print("  {s}Passed:  {d}{s}\n", .{ Colors.green, results.passed, Colors.reset });
            if (results.flaky > 0) {
                try s.output().print("  {s}Flaky:   {d}{s}\n", .{ Colors.yellow, results.flaky, Colors.reset });
            }
            if (results.failed > 0) {
                try s.output().print("  {s}Failed:  {d}{s}\n", .{ Colors.red, results.failed, Colors.reset });
            }
            if (results.skipped > 0) {
                try s.output().print("  {s}Skipped: {d}{s}\n", .{ Colors.yellow, results.skipped, Colors.reset });
            }
            try s.output().print("  Time:    {d:.2}ms\n", .{total_time_ms});
        } else {
            try s.output().print("Test Summary:\n", .{});
            try s.output().print("  Total:   {d}\n", .{results.total});
            try s.output().print("  Passed:  {d}\n", .{results.passed});
            if (results.flaky > 0) {
                try s.output().print("  Flaky:   {d}\n", .{results.flaky});
            }
            if (results.failed > 0) {
                try s.output().print("  Failed:  {d}\n", .{results.failed});
            }
            if (results.skipped > 0) {
                try s.output().print("  Skipped: {d}\n", .{results.skipped});
            }
            try s.output().print("  Time:    {d:.2}ms\n", .{total_time_ms});
        }
    }

    fn onSuiteStart(reporter: *Reporter, suite_name: []const u8) !void {
        const s = self(reporter);

        // Print indent
        var i: usize = 0;
        while (i < s.indent_level) : (i += 1) {
            try s.output().print("  ", .{});
        }

        if (reporter.use_colors) {
            try s.output().print("{s}{s}{s}\n", .{ Colors.bold, suite_name, Colors.reset });
        } else {
            try s.output().print("{s}\n", .{suite_name});
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
            try s.output().print("  ", .{});
        }

        const time_ms = @as(f64, @floatFromInt(test_case.execution_time_ns)) / 1_000_000.0;

        switch (test_case.status) {
            .passed => {
                if (reporter.use_colors) {
                    try s.output().print("{s}✓{s} {s} {s}({d:.2}ms){s}\n", .{
                        Colors.green,
                        Colors.reset,
                        test_case.name,
                        Colors.gray,
                        time_ms,
                        Colors.reset,
                    });
                } else {
                    try s.output().print("✓ {s} ({d:.2}ms)\n", .{ test_case.name, time_ms });
                }
            },
            .flaky => {
                if (reporter.use_colors) {
                    try s.output().print("{s}~{s} {s} {s}({d} attempts, {d:.2}ms){s}\n", .{
                        Colors.yellow,
                        Colors.reset,
                        test_case.name,
                        Colors.gray,
                        test_case.attempts.items.len,
                        time_ms,
                        Colors.reset,
                    });
                } else {
                    try s.output().print("~ {s} (flaky after {d} attempts, {d:.2}ms)\n", .{
                        test_case.name,
                        test_case.attempts.items.len,
                        time_ms,
                    });
                }
            },
            .failed => {
                if (reporter.use_colors) {
                    try s.output().print("{s}✗{s} {s} {s}({d:.2}ms){s}\n", .{
                        Colors.red,
                        Colors.reset,
                        test_case.name,
                        Colors.gray,
                        time_ms,
                        Colors.reset,
                    });
                } else {
                    try s.output().print("✗ {s} ({d:.2}ms)\n", .{ test_case.name, time_ms });
                }
            },
            .skipped => {
                if (reporter.use_colors) {
                    try s.output().print("{s}⊘{s} {s} {s}(skipped){s}\n", .{
                        Colors.yellow,
                        Colors.reset,
                        test_case.name,
                        Colors.gray,
                        Colors.reset,
                    });
                } else {
                    try s.output().print("⊘ {s} (skipped)\n", .{test_case.name});
                }
            },
            else => {},
        }
    }
};

/// Dot reporter (minimal output)
pub const DotReporter = struct {
    reporter: Reporter,
    writer: std.Io.Writer,
    writer_ref: ?*std.Io.Writer = null,
    tests_per_line: usize = 80,
    current_line_count: usize = 0,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, writer: std.Io.Writer) Self {
        return Self{
            .reporter = Reporter{
                .vtable = &vtable,
                .allocator = allocator,
            },
            .writer = writer,
        };
    }

    pub fn initRef(allocator: std.mem.Allocator, writer: *std.Io.Writer) Self {
        var result = init(allocator, writer.*);
        result.writer_ref = writer;
        return result;
    }

    fn output(instance: *Self) *std.Io.Writer {
        return instance.writer_ref orelse &instance.writer;
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
        try s.output().print("\nRunning {d} tests:\n", .{total_tests});
    }

    fn onRunEnd(reporter: *Reporter, results: *TestResults) !void {
        const s = self(reporter);
        try s.output().print("\n\n", .{});

        const total_time_ms = @as(f64, @floatFromInt(results.total_time_ns)) / 1_000_000.0;

        if (reporter.use_colors) {
            try s.output().print("{s}Passed: {d}{s}, ", .{ Colors.green, results.passed, Colors.reset });
            try s.output().print("{s}Flaky: {d}{s}, ", .{ Colors.yellow, results.flaky, Colors.reset });
            try s.output().print("{s}Failed: {d}{s}, ", .{ Colors.red, results.failed, Colors.reset });
            try s.output().print("Total: {d} ({d:.2}ms)\n", .{ results.total, total_time_ms });
        } else {
            try s.output().print("Passed: {d}, Flaky: {d}, Failed: {d}, Total: {d} ({d:.2}ms)\n", .{
                results.passed,
                results.flaky,
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
                    try s.output().print("{s}.{s}", .{ Colors.green, Colors.reset });
                } else {
                    try s.output().print(".", .{});
                }
            },
            .flaky => {
                if (reporter.use_colors) {
                    try s.output().print("{s}~{s}", .{ Colors.yellow, Colors.reset });
                } else {
                    try s.output().print("~", .{});
                }
            },
            .failed => {
                if (reporter.use_colors) {
                    try s.output().print("{s}F{s}", .{ Colors.red, Colors.reset });
                } else {
                    try s.output().print("F", .{});
                }
            },
            .skipped => {
                if (reporter.use_colors) {
                    try s.output().print("{s}S{s}", .{ Colors.yellow, Colors.reset });
                } else {
                    try s.output().print("S", .{});
                }
            },
            else => {},
        }

        s.current_line_count += 1;
        if (s.current_line_count >= s.tests_per_line) {
            try s.output().print("\n", .{});
            s.current_line_count = 0;
        }
    }
};

/// JSON reporter
pub const JsonReporter = struct {
    reporter: Reporter,
    writer: std.Io.Writer,
    writer_ref: ?*std.Io.Writer = null,
    suites: std.ArrayList([]const u8),
    emitted_tests: bool = false,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, writer: std.Io.Writer) Self {
        return Self{
            .reporter = Reporter{
                .vtable = &vtable,
                .allocator = allocator,
            },
            .writer = writer,
            .suites = .empty,
        };
    }

    pub fn initRef(allocator: std.mem.Allocator, writer: *std.Io.Writer) Self {
        var result = init(allocator, writer.*);
        result.writer_ref = writer;
        return result;
    }

    fn output(instance: *Self) *std.Io.Writer {
        return instance.writer_ref orelse &instance.writer;
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
        try s.output().print("{{\"totalTests\":{d},\"tests\":[\n", .{total_tests});
    }

    fn onRunEnd(reporter: *Reporter, results: *TestResults) !void {
        const s = self(reporter);
        const total_time_ms = @as(f64, @floatFromInt(results.total_time_ns)) / 1_000_000.0;

        try s.output().print("\n],\"summary\":{{\"total\":{d},\"passed\":{d},\"flaky\":{d},\"failed\":{d},\"skipped\":{d},\"time\":{d:.2}}}}}\n", .{
            results.total,
            results.passed,
            results.flaky,
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
            .flaky => "flaky",
            .failed => "failed",
            .skipped => "skipped",
            else => "unknown",
        };

        if (s.emitted_tests) try s.output().print(",\n", .{});
        s.emitted_tests = true;

        // Note: In a real implementation, you'd want to properly escape JSON strings
        try s.output().print("  {{\"name\":\"{s}\",\"status\":\"{s}\",\"time\":{d:.2}", .{
            test_case.name,
            status_str,
            time_ms,
        });

        if (test_case.error_message) |msg| {
            try s.output().print(",\"error\":\"{s}\"", .{msg});
        }

        try s.output().print(",\"attempts\":[", .{});
        for (test_case.attempts.items, 0..) |attempt, index| {
            if (index > 0) try s.output().print(",", .{});
            const attempt_status = switch (attempt.status) {
                .passed => "passed",
                .flaky => "flaky",
                .failed => "failed",
                .skipped => "skipped",
                else => "unknown",
            };
            try s.output().print(
                "{{\"number\":{d},\"repetition\":{d},\"status\":\"{s}\",\"durationNs\":{d}",
                .{ attempt.number, attempt.repetition, attempt_status, attempt.duration_ns },
            );
            if (attempt.error_message) |message| {
                try s.output().print(",\"error\":\"{s}\"", .{message});
            }
            try s.output().print("}}", .{});
        }
        try s.output().print("]}}", .{});
    }
};

/// TAP (Test Anything Protocol) reporter
pub const TAPReporter = struct {
    reporter: Reporter,
    writer: std.Io.Writer,
    writer_ref: ?*std.Io.Writer = null,
    test_count: usize = 0,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, writer: std.Io.Writer) Self {
        return .{
            .reporter = .{
                .vtable = &.{
                    .onRunStart = onRunStart,
                    .onRunEnd = onRunEnd,
                    .onSuiteStart = onSuiteStart,
                    .onSuiteEnd = onSuiteEnd,
                    .onTestStart = onTestStart,
                    .onTestEnd = onTestEnd,
                },
                .allocator = allocator,
                .use_colors = false,
            },
            .writer = writer,
        };
    }

    pub fn initRef(allocator: std.mem.Allocator, writer: *std.Io.Writer) Self {
        var result = init(allocator, writer.*);
        result.writer_ref = writer;
        return result;
    }

    fn output(instance: *Self) *std.Io.Writer {
        return instance.writer_ref orelse &instance.writer;
    }

    fn onRunStart(reporter: *Reporter, total: usize) !void {
        const self: *Self = @fieldParentPtr("reporter", reporter);
        try self.output().print("TAP version 14\n1..{d}\n", .{total});
    }

    fn onRunEnd(reporter: *Reporter, results: *TestResults) !void {
        _ = reporter;
        _ = results;
    }

    fn onSuiteStart(reporter: *Reporter, suite_name: []const u8) !void {
        const self: *Self = @fieldParentPtr("reporter", reporter);
        try self.output().print("# Subtest: {s}\n", .{suite_name});
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
        const self: *Self = @fieldParentPtr("reporter", reporter);
        self.test_count += 1;

        const status = switch (test_case.status) {
            .passed => "ok",
            .flaky => "ok",
            .failed => "not ok",
            .skipped => "ok",
            else => "not ok",
        };

        try self.output().print("{s} {d} - {s}", .{ status, self.test_count, test_case.name });

        if (test_case.status == .flaky) {
            try self.output().print(" # FLAKY attempts={d}\n", .{test_case.attempts.items.len});
        } else if (test_case.status == .skipped) {
            try self.output().print(" # SKIP\n", .{});
        } else if (test_case.status == .failed and test_case.error_message != null) {
            try self.output().print("\n  ---\n  message: {s}\n  ...\n", .{test_case.error_message.?});
        } else {
            try self.output().print("\n", .{});
        }
    }
};

/// JUnit XML reporter
pub const JUnitReporter = struct {
    reporter: Reporter,
    allocator: std.mem.Allocator,
    output_file: []const u8,
    suites: std.ArrayList(TestSuiteResult),
    current_suite: ?*TestSuiteResult = null,

    const Self = @This();

    const TestSuiteResult = struct {
        name: []const u8,
        tests: std.ArrayList(TestCaseResult),
        timestamp: i64,

        pub fn deinit(self: *TestSuiteResult, allocator: std.mem.Allocator) void {
            for (self.tests.items) |*test_case| {
                allocator.free(test_case.name);
                if (test_case.error_message) |msg| {
                    allocator.free(msg);
                }
                for (test_case.attempts) |attempt| {
                    if (attempt.error_message) |msg| allocator.free(msg);
                }
                allocator.free(test_case.attempts);
            }
            self.tests.deinit(allocator);
            allocator.free(self.name);
        }
    };

    const TestCaseResult = struct {
        name: []const u8,
        time: f64,
        status: suite.TestStatus,
        error_message: ?[]const u8,
        attempts: []AttemptResult,
    };

    const AttemptResult = struct {
        number: usize,
        repetition: usize,
        status: suite.TestStatus,
        duration_ns: u64,
        error_message: ?[]const u8,
    };

    pub fn init(allocator: std.mem.Allocator, output_file: []const u8) Self {
        return .{
            .reporter = .{
                .vtable = &.{
                    .onRunStart = onRunStart,
                    .onRunEnd = onRunEnd,
                    .onSuiteStart = onSuiteStart,
                    .onSuiteEnd = onSuiteEnd,
                    .onTestStart = onTestStart,
                    .onTestEnd = onTestEnd,
                },
                .allocator = allocator,
                .use_colors = false,
            },
            .allocator = allocator,
            .output_file = output_file,
            .suites = .empty,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.suites.items) |*suite_result| {
            suite_result.deinit(self.allocator);
        }
        self.suites.deinit(self.allocator);
    }

    fn onRunStart(reporter: *Reporter, total: usize) !void {
        _ = reporter;
        _ = total;
    }

    fn onRunEnd(reporter: *Reporter, results: *TestResults) !void {
        const self: *Self = @fieldParentPtr("reporter", reporter);
        try self.writeXML(results);
    }

    fn onSuiteStart(reporter: *Reporter, suite_name: []const u8) !void {
        const self: *Self = @fieldParentPtr("reporter", reporter);

        const suite_result = try self.allocator.create(TestSuiteResult);
        suite_result.* = .{
            .name = try self.allocator.dupe(u8, suite_name),
            .tests = .empty,
            .timestamp = compat.milliTimestamp(),
        };

        try self.suites.append(self.allocator, suite_result.*);
        self.current_suite = &self.suites.items[self.suites.items.len - 1];
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
        const self: *Self = @fieldParentPtr("reporter", reporter);

        if (self.current_suite) |test_suite| {
            const time_seconds = @as(f64, @floatFromInt(test_case.execution_time_ns)) / 1_000_000_000.0;

            const error_msg = if (test_case.error_message) |msg|
                try self.allocator.dupe(u8, msg)
            else
                null;

            const attempts = try self.allocator.alloc(AttemptResult, test_case.attempts.items.len);
            errdefer self.allocator.free(attempts);
            for (test_case.attempts.items, 0..) |attempt, index| {
                attempts[index] = .{
                    .number = attempt.number,
                    .repetition = attempt.repetition,
                    .status = attempt.status,
                    .duration_ns = attempt.duration_ns,
                    .error_message = if (attempt.error_message) |message|
                        try self.allocator.dupe(u8, message)
                    else
                        null,
                };
            }

            const test_result = TestCaseResult{
                .name = try self.allocator.dupe(u8, test_case.name),
                .time = time_seconds,
                .status = test_case.status,
                .error_message = error_msg,
                .attempts = attempts,
            };

            try test_suite.tests.append(self.allocator, test_result);
        }
    }

    fn writeXML(self: *Self, results: *TestResults) !void {
        var buffer = std.ArrayList(u8).empty;
        defer buffer.deinit(self.allocator);

        try buffer.appendSlice(self.allocator, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
        try buffer.print(self.allocator, "<testsuites tests=\"{d}\" failures=\"{d}\" skipped=\"{d}\" flaky=\"{d}\">\n", .{
            results.total,
            results.failed,
            results.skipped,
            results.flaky,
        });

        for (self.suites.items) |suite_result| {
            var suite_failures: usize = 0;
            var suite_skipped: usize = 0;
            var suite_time: f64 = 0.0;

            for (suite_result.tests.items) |test_result| {
                if (test_result.status == .failed) suite_failures += 1;
                if (test_result.status == .skipped) suite_skipped += 1;
                suite_time += test_result.time;
            }

            try buffer.print(self.allocator, "  <testsuite name=\"{s}\" tests=\"{d}\" failures=\"{d}\" skipped=\"{d}\" time=\"{d:.6}\">\n", .{
                suite_result.name,
                suite_result.tests.items.len,
                suite_failures,
                suite_skipped,
                suite_time,
            });

            for (suite_result.tests.items) |test_result| {
                try buffer.print(self.allocator, "    <testcase name=\"{s}\" time=\"{d:.6}\"", .{
                    test_result.name,
                    test_result.time,
                });

                if (test_result.status == .failed) {
                    try buffer.appendSlice(self.allocator, ">\n");
                    try buffer.print(self.allocator, "      <failure message=\"{s}\"/>\n", .{
                        test_result.error_message orelse "Test failed",
                    });
                    try writeAttemptHistory(&buffer, self.allocator, test_result.attempts);
                    try buffer.appendSlice(self.allocator, "    </testcase>\n");
                } else if (test_result.status == .skipped) {
                    try buffer.appendSlice(self.allocator, ">\n");
                    try buffer.appendSlice(self.allocator, "      <skipped/>\n");
                    try buffer.appendSlice(self.allocator, "    </testcase>\n");
                } else if (test_result.attempts.len > 1) {
                    try buffer.appendSlice(self.allocator, ">\n");
                    try writeAttemptHistory(&buffer, self.allocator, test_result.attempts);
                    try buffer.appendSlice(self.allocator, "    </testcase>\n");
                } else {
                    try buffer.appendSlice(self.allocator, "/>\n");
                }
            }

            try buffer.appendSlice(self.allocator, "  </testsuite>\n");
        }

        try buffer.appendSlice(self.allocator, "</testsuites>\n");

        try compat.writeFile(self.allocator, self.output_file, buffer.items);
    }

    fn writeAttemptHistory(
        buffer: *std.ArrayList(u8),
        allocator: std.mem.Allocator,
        attempts: []const AttemptResult,
    ) !void {
        try buffer.appendSlice(allocator, "      <system-out>");
        for (attempts, 0..) |attempt, index| {
            if (index > 0) try buffer.appendSlice(allocator, "&#10;");
            try buffer.print(
                allocator,
                "attempt={d} repetition={d} status={s} duration_ns={d}",
                .{ attempt.number, attempt.repetition, @tagName(attempt.status), attempt.duration_ns },
            );
        }
        try buffer.appendSlice(allocator, "</system-out>\n");
    }
};

/// Owns every built-in reporter and selects one through a shared interface.
/// Keeping construction here lets every executor expose identical reporters.
pub const ReporterSet = struct {
    kind: ReporterType,
    spec: SpecReporter,
    dot: DotReporter,
    json: JsonReporter,
    tap: TAPReporter,
    junit: JUnitReporter,

    pub fn init(
        allocator: std.mem.Allocator,
        writer: std.Io.Writer,
        kind: ReporterType,
        junit_output: []const u8,
        use_colors: bool,
    ) ReporterSet {
        var reporters = ReporterSet{
            .kind = kind,
            .spec = SpecReporter.init(allocator, writer),
            .dot = DotReporter.init(allocator, writer),
            .json = JsonReporter.init(allocator, writer),
            .tap = TAPReporter.init(allocator, writer),
            .junit = JUnitReporter.init(allocator, junit_output),
        };
        reporters.selected().use_colors = use_colors;
        return reporters;
    }

    pub fn initRef(
        allocator: std.mem.Allocator,
        writer: *std.Io.Writer,
        kind: ReporterType,
        junit_output: []const u8,
        use_colors: bool,
    ) ReporterSet {
        var reporters = ReporterSet{
            .kind = kind,
            .spec = SpecReporter.initRef(allocator, writer),
            .dot = DotReporter.initRef(allocator, writer),
            .json = JsonReporter.initRef(allocator, writer),
            .tap = TAPReporter.initRef(allocator, writer),
            .junit = JUnitReporter.init(allocator, junit_output),
        };
        reporters.selected().use_colors = use_colors;
        return reporters;
    }

    pub fn deinit(self: *ReporterSet) void {
        self.json.deinit();
        self.junit.deinit();
    }

    pub fn selected(self: *ReporterSet) *Reporter {
        return switch (self.kind) {
            .spec => &self.spec.reporter,
            .dot => &self.dot.reporter,
            .json => &self.json.reporter,
            .tap => &self.tap.reporter,
            .junit => &self.junit.reporter,
        };
    }

    pub fn flush(self: *ReporterSet) !void {
        switch (self.kind) {
            .spec => try self.spec.output().flush(),
            .dot => try self.dot.output().flush(),
            .json => try self.json.output().flush(),
            .tap => try self.tap.output().flush(),
            .junit => {},
        }
    }
};

// Tests
test "Colors constants exist" {
    // Just verify the constants are defined
    _ = Colors.reset;
    _ = Colors.bold;
    _ = Colors.dim;
    _ = Colors.red;
    _ = Colors.green;
    _ = Colors.yellow;
    _ = Colors.blue;
    _ = Colors.magenta;
    _ = Colors.cyan;
    _ = Colors.white;
    _ = Colors.gray;
}

test "TestResults creation" {
    const allocator = std.testing.allocator;

    var results = TestResults.init(allocator);
    defer results.deinit();

    try std.testing.expectEqual(@as(usize, 0), results.total);
    try std.testing.expectEqual(@as(usize, 0), results.passed);
    try std.testing.expectEqual(@as(usize, 0), results.failed);
    try std.testing.expectEqual(@as(usize, 0), results.skipped);
}
