const std = @import("std");

/// Spinner style
pub const SpinnerStyle = enum {
    dots,
    line,
    arc,
    circle,
    square,
    arrow,
    bounce,

    pub fn frames(self: SpinnerStyle) []const []const u8 {
        return switch (self) {
            .dots => &[_][]const u8{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
            .line => &[_][]const u8{ "-", "\\", "|", "/" },
            .arc => &[_][]const u8{ "◜", "◠", "◝", "◞", "◡", "◟" },
            .circle => &[_][]const u8{ "◐", "◓", "◑", "◒" },
            .square => &[_][]const u8{ "◰", "◳", "◲", "◱" },
            .arrow => &[_][]const u8{ "←", "↖", "↑", "↗", "→", "↘", "↓", "↙" },
            .bounce => &[_][]const u8{ "⠁", "⠂", "⠄", "⠂" },
        };
    }
};

/// Progress bar style
pub const ProgressBarStyle = enum {
    classic,
    blocks,
    arrows,
    dots,

    pub fn chars(self: ProgressBarStyle) struct { filled: []const u8, empty: []const u8 } {
        return switch (self) {
            .classic => .{ .filled = "█", .empty = "░" },
            .blocks => .{ .filled = "■", .empty = "□" },
            .arrows => .{ .filled = "▶", .empty = "▷" },
            .dots => .{ .filled = "●", .empty = "○" },
        };
    }
};

/// Spinner for showing ongoing operations
pub const Spinner = struct {
    allocator: std.mem.Allocator,
    style: SpinnerStyle,
    message: []const u8,
    frame_index: usize,
    running: std.atomic.Value(bool),
    thread: ?std.Thread,
    mutex: std.Thread.Mutex,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, message: []const u8, style: SpinnerStyle) !Self {
        return .{
            .allocator = allocator,
            .style = style,
            .message = try allocator.dupe(u8, message),
            .frame_index = 0,
            .running = std.atomic.Value(bool).init(false),
            .thread = null,
            .mutex = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.stop();
        self.allocator.free(self.message);
    }

    /// Start the spinner in a background thread
    pub fn start(self: *Self) !void {
        if (self.running.load(.monotonic)) return;

        self.running.store(true, .monotonic);
        self.thread = try std.Thread.spawn(.{}, Self.spinLoop, .{self});
    }

    /// Stop the spinner
    pub fn stop(self: *Self) void {
        if (!self.running.load(.monotonic)) return;

        self.running.store(false, .monotonic);
        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }

        // Clear the spinner line
        std.debug.print("\r\x1b[K", .{});
    }

    /// Update the spinner message
    pub fn updateMessage(self: *Self, new_message: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.allocator.free(self.message);
        self.message = try self.allocator.dupe(u8, new_message);
    }

    /// Spinner animation loop
    fn spinLoop(self: *Self) void {
        const frames = self.style.frames();

        while (self.running.load(.monotonic)) {
            self.mutex.lock();
            const frame = frames[self.frame_index % frames.len];
            std.debug.print("\r{s} {s}", .{ frame, self.message });
            self.frame_index += 1;
            self.mutex.unlock();

            std.Thread.sleep(80 * std.time.ns_per_ms);
        }
    }

    /// Show success message and stop
    pub fn succeed(self: *Self, message: []const u8) void {
        self.stop();
        std.debug.print("\r✓ {s}\n", .{message});
    }

    /// Show failure message and stop
    pub fn fail(self: *Self, message: []const u8) void {
        self.stop();
        std.debug.print("\r✗ {s}\n", .{message});
    }

    /// Show warning message and stop
    pub fn warn(self: *Self, message: []const u8) void {
        self.stop();
        std.debug.print("\r⚠ {s}\n", .{message});
    }

    /// Show info message and stop
    pub fn info(self: *Self, message: []const u8) void {
        self.stop();
        std.debug.print("\rℹ {s}\n", .{message});
    }
};

/// Progress bar for showing completion percentage
pub const ProgressBar = struct {
    allocator: std.mem.Allocator,
    style: ProgressBarStyle,
    total: usize,
    current: usize,
    width: usize,
    message: []const u8,
    show_percentage: bool,
    show_count: bool,
    mutex: std.Thread.Mutex,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, total: usize, options: struct {
        width: usize = 40,
        style: ProgressBarStyle = .classic,
        message: []const u8 = "Progress",
        show_percentage: bool = true,
        show_count: bool = true,
    }) !Self {
        return .{
            .allocator = allocator,
            .style = options.style,
            .total = total,
            .current = 0,
            .width = options.width,
            .message = try allocator.dupe(u8, options.message),
            .show_percentage = options.show_percentage,
            .show_count = options.show_count,
            .mutex = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.message);
    }

    /// Update progress
    pub fn update(self: *Self, current: usize) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.current = @min(current, self.total);
        self.render();
    }

    /// Increment progress by 1
    pub fn increment(self: *Self) void {
        self.update(self.current + 1);
    }

    /// Set progress to completion
    pub fn finish(self: *Self) void {
        self.update(self.total);
        std.debug.print("\n", .{});
    }

    /// Render the progress bar
    fn render(self: *Self) void {
        const percentage = if (self.total > 0)
            @as(f64, @floatFromInt(self.current)) / @as(f64, @floatFromInt(self.total)) * 100.0
        else
            0.0;

        const filled_width = if (self.total > 0)
            @as(usize, @intFromFloat(@as(f64, @floatFromInt(self.width)) * @as(f64, @floatFromInt(self.current)) / @as(f64, @floatFromInt(self.total))))
        else
            0;

        const chars = self.style.chars();

        // Build progress bar
        std.debug.print("\r{s} [", .{self.message});

        var i: usize = 0;
        while (i < self.width) : (i += 1) {
            if (i < filled_width) {
                std.debug.print("{s}", .{chars.filled});
            } else {
                std.debug.print("{s}", .{chars.empty});
            }
        }

        std.debug.print("]", .{});

        if (self.show_percentage) {
            std.debug.print(" {d:.1}%", .{percentage});
        }

        if (self.show_count) {
            std.debug.print(" ({d}/{d})", .{ self.current, self.total });
        }
    }
};

/// Real-time test progress tracker
pub const TestProgress = struct {
    allocator: std.mem.Allocator,
    total_tests: usize,
    completed: std.atomic.Value(usize),
    passed: std.atomic.Value(usize),
    failed: std.atomic.Value(usize),
    skipped: std.atomic.Value(usize),
    running_test: ?[]const u8,
    start_time: i64,
    spinner: ?Spinner,
    progress_bar: ?ProgressBar,
    use_spinner: bool,
    use_progress_bar: bool,
    mutex: std.Thread.Mutex,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, total_tests: usize, options: struct {
        use_spinner: bool = true,
        use_progress_bar: bool = true,
    }) !Self {
        var self = Self{
            .allocator = allocator,
            .total_tests = total_tests,
            .completed = std.atomic.Value(usize).init(0),
            .passed = std.atomic.Value(usize).init(0),
            .failed = std.atomic.Value(usize).init(0),
            .skipped = std.atomic.Value(usize).init(0),
            .running_test = null,
            .start_time = std.time.milliTimestamp(),
            .spinner = null,
            .progress_bar = null,
            .use_spinner = options.use_spinner,
            .use_progress_bar = options.use_progress_bar,
            .mutex = .{},
        };

        if (options.use_progress_bar) {
            self.progress_bar = try ProgressBar.init(allocator, total_tests, .{
                .message = "Running tests",
                .width = 30,
            });
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        if (self.spinner) |*spinner| {
            spinner.deinit();
        }
        if (self.progress_bar) |*bar| {
            bar.deinit();
        }
        if (self.running_test) |test_name| {
            self.allocator.free(test_name);
        }
    }

    /// Start a test
    pub fn startTest(self: *Self, test_name: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Update running test
        if (self.running_test) |old_name| {
            self.allocator.free(old_name);
        }
        self.running_test = try self.allocator.dupe(u8, test_name);

        // Start spinner if enabled
        if (self.use_spinner and self.spinner == null) {
            var spinner = try Spinner.init(self.allocator, test_name, .dots);
            try spinner.start();
            self.spinner = spinner;
        } else if (self.spinner) |*spinner| {
            try spinner.updateMessage(test_name);
        }
    }

    /// Complete a test
    pub fn completeTest(self: *Self, passed: bool, skipped: bool) void {
        const completed = self.completed.fetchAdd(1, .monotonic) + 1;

        if (skipped) {
            _ = self.skipped.fetchAdd(1, .monotonic);
        } else if (passed) {
            _ = self.passed.fetchAdd(1, .monotonic);
        } else {
            _ = self.failed.fetchAdd(1, .monotonic);
        }

        // Stop spinner
        if (self.spinner) |*spinner| {
            if (skipped) {
                spinner.warn(self.running_test orelse "Test skipped");
            } else if (passed) {
                spinner.succeed(self.running_test orelse "Test passed");
            } else {
                spinner.fail(self.running_test orelse "Test failed");
            }
            spinner.deinit();
            self.spinner = null;
        }

        // Update progress bar
        if (self.progress_bar) |*bar| {
            bar.update(completed);
        }
    }

    /// Get elapsed time in milliseconds
    pub fn getElapsedMs(self: *Self) i64 {
        return std.time.milliTimestamp() - self.start_time;
    }

    /// Print summary
    pub fn printSummary(self: *Self) void {
        if (self.progress_bar) |*bar| {
            bar.finish();
        }

        const elapsed_ms = self.getElapsedMs();
        const elapsed_sec = @as(f64, @floatFromInt(elapsed_ms)) / 1000.0;

        std.debug.print("\n", .{});
        std.debug.print("Tests:    {d} total, {d} passed, {d} failed, {d} skipped\n", .{
            self.total_tests,
            self.passed.load(.monotonic),
            self.failed.load(.monotonic),
            self.skipped.load(.monotonic),
        });
        std.debug.print("Duration: {d:.2}s\n", .{elapsed_sec});
    }
};

/// Multi-spinner for parallel operations
pub const MultiSpinner = struct {
    allocator: std.mem.Allocator,
    spinners: std.ArrayList(struct { name: []const u8, spinner: Spinner }),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .spinners = std.ArrayList(struct { name: []const u8, spinner: Spinner }).empty,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.spinners.items) |*item| {
            item.spinner.deinit();
            self.allocator.free(item.name);
        }
        self.spinners.deinit(self.allocator);
    }

    /// Add a spinner
    pub fn add(self: *Self, name: []const u8, message: []const u8) !void {
        const name_copy = try self.allocator.dupe(u8, name);
        var spinner = try Spinner.init(self.allocator, message, .dots);
        try spinner.start();

        try self.spinners.append(self.allocator, .{
            .name = name_copy,
            .spinner = spinner,
        });
    }

    /// Update a spinner
    pub fn update(self: *Self, name: []const u8, message: []const u8) !void {
        for (self.spinners.items) |*item| {
            if (std.mem.eql(u8, item.name, name)) {
                try item.spinner.updateMessage(message);
                return;
            }
        }
    }

    /// Complete a spinner with success
    pub fn succeed(self: *Self, name: []const u8, message: []const u8) void {
        for (self.spinners.items) |*item| {
            if (std.mem.eql(u8, item.name, name)) {
                item.spinner.succeed(message);
                return;
            }
        }
    }

    /// Complete a spinner with failure
    pub fn fail(self: *Self, name: []const u8, message: []const u8) void {
        for (self.spinners.items) |*item| {
            if (std.mem.eql(u8, item.name, name)) {
                item.spinner.fail(message);
                return;
            }
        }
    }
};

// Tests
test "Spinner creation and basic operations" {
    const allocator = std.testing.allocator;

    var spinner = try Spinner.init(allocator, "Loading...", .dots);
    defer spinner.deinit();

    try std.testing.expect(!spinner.running.load(.monotonic));
}

test "ProgressBar creation and updates" {
    const allocator = std.testing.allocator;

    var bar = try ProgressBar.init(allocator, 100, .{});
    defer bar.deinit();

    try std.testing.expectEqual(@as(usize, 0), bar.current);
    try std.testing.expectEqual(@as(usize, 100), bar.total);

    bar.update(50);
    try std.testing.expectEqual(@as(usize, 50), bar.current);

    bar.increment();
    try std.testing.expectEqual(@as(usize, 51), bar.current);
}

test "TestProgress tracking" {
    const allocator = std.testing.allocator;

    var progress = try TestProgress.init(allocator, 10, .{
        .use_spinner = false,
        .use_progress_bar = false,
    });
    defer progress.deinit();

    try std.testing.expectEqual(@as(usize, 10), progress.total_tests);
    try std.testing.expectEqual(@as(usize, 0), progress.completed.load(.monotonic));

    try progress.startTest("test 1");
    progress.completeTest(true, false);

    try std.testing.expectEqual(@as(usize, 1), progress.completed.load(.monotonic));
    try std.testing.expectEqual(@as(usize, 1), progress.passed.load(.monotonic));
}

test "SpinnerStyle frames" {
    const dots_frames = SpinnerStyle.dots.frames();
    try std.testing.expect(dots_frames.len > 0);

    const line_frames = SpinnerStyle.line.frames();
    try std.testing.expectEqual(@as(usize, 4), line_frames.len);
}

test "ProgressBarStyle chars" {
    const classic = ProgressBarStyle.classic.chars();
    try std.testing.expect(classic.filled.len > 0);
    try std.testing.expect(classic.empty.len > 0);
}
