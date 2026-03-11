const std = @import("std");
const reporter_mod = @import("reporter.zig");
const suite = @import("suite.zig");
const test_history = @import("test_history.zig");
const compat = @import("compat.zig");

/// Options for the UI server
pub const UIServerOptions = struct {
    /// Port to listen on
    port: u16 = 8080,
    /// Host to bind to
    host: []const u8 = "127.0.0.1",
    /// Enable verbose logging
    verbose: bool = false,
};

/// UI Server for web-based test visualization
/// Note: std.net was removed in Zig 0.16. Server functionality is stubbed out
/// until the new Io-based networking API stabilizes.
pub const UIServer = struct {
    allocator: std.mem.Allocator,
    options: UIServerOptions,
    mutex: compat.Mutex = .{},
    history: ?*test_history.TestHistory = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, options: UIServerOptions) Self {
        return .{
            .allocator = allocator,
            .options = options,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    /// Start the UI server (stubbed - std.net removed in Zig 0.16)
    pub fn start(self: *Self) !void {
        if (self.options.verbose) {
            std.debug.print("UI Server: networking stubbed out (std.net removed in Zig 0.16)\n", .{});
        }
    }

    /// Accept a client connection (stubbed)
    pub fn acceptClient(self: *Self) !void {
        _ = self;
        // Stubbed: no networking available
        compat.sleep(100 * std.time.ns_per_ms);
    }

    /// Broadcast an event to all connected clients (stubbed)
    pub fn broadcast(self: *Self, event: []const u8, data: []const u8) !void {
        _ = self;
        _ = event;
        _ = data;
    }
};

/// UI Reporter - sends test events to the UI server
pub const UIReporter = struct {
    reporter: reporter_mod.Reporter,
    server: *UIServer,
    buffer: std.ArrayList(u8),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, server: *UIServer) Self {
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
            .server = server,
            .buffer = .empty,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.reporter.allocator);
    }

    fn onRunStart(reporter: *reporter_mod.Reporter, total: usize) !void {
        const self: *Self = @fieldParentPtr("reporter", reporter);

        self.buffer.clearRetainingCapacity();
        try self.buffer.print(reporter.allocator, "{{\"total\":{d}}}", .{total});

        try self.server.broadcast("run_start", self.buffer.items);
    }

    fn onRunEnd(reporter: *reporter_mod.Reporter, results: *reporter_mod.TestResults) !void {
        const self: *Self = @fieldParentPtr("reporter", reporter);

        self.buffer.clearRetainingCapacity();
        try self.buffer.print(reporter.allocator, "{{\"total\":{d},\"passed\":{d},\"failed\":{d},\"skipped\":{d}}}", .{
            results.total,
            results.passed,
            results.failed,
            results.skipped,
        });

        try self.server.broadcast("run_end", self.buffer.items);
    }

    fn onSuiteStart(reporter: *reporter_mod.Reporter, suite_name: []const u8) !void {
        const self: *Self = @fieldParentPtr("reporter", reporter);

        self.buffer.clearRetainingCapacity();
        try self.buffer.print(reporter.allocator, "{{\"name\":\"{s}\"}}", .{suite_name});

        try self.server.broadcast("suite_start", self.buffer.items);
    }

    fn onSuiteEnd(reporter: *reporter_mod.Reporter, suite_name: []const u8) !void {
        const self: *Self = @fieldParentPtr("reporter", reporter);

        self.buffer.clearRetainingCapacity();
        try self.buffer.print(reporter.allocator, "{{\"name\":\"{s}\"}}", .{suite_name});

        try self.server.broadcast("suite_end", self.buffer.items);
    }

    fn onTestStart(reporter: *reporter_mod.Reporter, test_name: []const u8) !void {
        const self: *Self = @fieldParentPtr("reporter", reporter);

        self.buffer.clearRetainingCapacity();
        try self.buffer.print(reporter.allocator, "{{\"name\":\"{s}\"}}", .{test_name});

        try self.server.broadcast("test_start", self.buffer.items);
    }

    fn onTestEnd(reporter: *reporter_mod.Reporter, test_case: *const suite.TestCase) !void {
        const self: *Self = @fieldParentPtr("reporter", reporter);

        self.buffer.clearRetainingCapacity();

        const error_msg = test_case.error_message orelse "";
        try self.buffer.print(reporter.allocator, "{{\"name\":\"{s}\",\"status\":\"{s}\",\"execution_time_ns\":{d},\"error_message\":\"{s}\"}}", .{
            test_case.name,
            @tagName(test_case.status),
            test_case.execution_time_ns,
            error_msg,
        });

        try self.server.broadcast("test_end", self.buffer.items);
    }
};

/// Multi-Reporter - broadcasts events to multiple reporters
pub const MultiReporter = struct {
    reporter: reporter_mod.Reporter,
    reporters: []*reporter_mod.Reporter,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, reporters: []*reporter_mod.Reporter) Self {
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
            .reporters = reporters,
            .allocator = allocator,
        };
    }

    fn onRunStart(reporter: *reporter_mod.Reporter, total: usize) !void {
        const self: *Self = @fieldParentPtr("reporter", reporter);
        for (self.reporters) |rep| {
            try rep.onRunStart(total);
        }
    }

    fn onRunEnd(reporter: *reporter_mod.Reporter, results: *reporter_mod.TestResults) !void {
        const self: *Self = @fieldParentPtr("reporter", reporter);
        for (self.reporters) |rep| {
            try rep.onRunEnd(results);
        }
    }

    fn onSuiteStart(reporter: *reporter_mod.Reporter, suite_name: []const u8) !void {
        const self: *Self = @fieldParentPtr("reporter", reporter);
        for (self.reporters) |rep| {
            try rep.onSuiteStart(suite_name);
        }
    }

    fn onSuiteEnd(reporter: *reporter_mod.Reporter, suite_name: []const u8) !void {
        const self: *Self = @fieldParentPtr("reporter", reporter);
        for (self.reporters) |rep| {
            try rep.onSuiteEnd(suite_name);
        }
    }

    fn onTestStart(reporter: *reporter_mod.Reporter, test_name: []const u8) !void {
        const self: *Self = @fieldParentPtr("reporter", reporter);
        for (self.reporters) |rep| {
            try rep.onTestStart(test_name);
        }
    }

    fn onTestEnd(reporter: *reporter_mod.Reporter, test_case: *const suite.TestCase) !void {
        const self: *Self = @fieldParentPtr("reporter", reporter);
        for (self.reporters) |rep| {
            try rep.onTestEnd(test_case);
        }
    }
};

// Tests
test "UIServerOptions default values" {
    const options = UIServerOptions{};

    try std.testing.expectEqual(@as(u16, 8080), options.port);
    try std.testing.expectEqualStrings("127.0.0.1", options.host);
    try std.testing.expectEqual(false, options.verbose);
}

test "UIServer initialization" {
    const allocator = std.testing.allocator;

    var server = UIServer.init(allocator, .{});
    defer server.deinit();
}

test "UIReporter initialization" {
    const allocator = std.testing.allocator;

    var server = UIServer.init(allocator, .{});
    defer server.deinit();

    var ui_reporter = UIReporter.init(allocator, &server);
    defer ui_reporter.deinit();

    try std.testing.expectEqual(false, ui_reporter.reporter.use_colors);
    try std.testing.expectEqual(@as(usize, 0), ui_reporter.buffer.items.len);
}
