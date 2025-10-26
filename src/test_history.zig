const std = @import("std");
const reporter_mod = @import("reporter.zig");
const suite = @import("suite.zig");

/// Test history entry
pub const HistoryEntry = struct {
    timestamp: i64,
    total: usize,
    passed: usize,
    failed: usize,
    skipped: usize,
    duration_ns: u64,
    tests: std.ArrayList(TestRecord),

    pub fn deinit(self: *HistoryEntry, allocator: std.mem.Allocator) void {
        for (self.tests.items) |*test_record| {
            test_record.deinit(allocator);
        }
        self.tests.deinit(allocator);
    }
};

/// Individual test record
pub const TestRecord = struct {
    name: []const u8,
    suite_name: []const u8,
    status: []const u8,
    execution_time_ns: u64,
    error_message: ?[]const u8,

    pub fn deinit(self: *TestRecord, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.suite_name);
        allocator.free(self.status);
        if (self.error_message) |msg| {
            allocator.free(msg);
        }
    }
};

/// Test history manager
pub const TestHistory = struct {
    allocator: std.mem.Allocator,
    history_dir: []const u8,
    current_entry: ?HistoryEntry = null,
    start_time: i64 = 0,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, history_dir: []const u8) Self {
        return .{
            .allocator = allocator,
            .history_dir = history_dir,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.current_entry) |*entry| {
            entry.deinit(self.allocator);
        }
    }

    /// Start recording a new test run
    pub fn startRun(self: *Self, total: usize) !void {
        self.start_time = std.time.milliTimestamp();

        self.current_entry = HistoryEntry{
            .timestamp = self.start_time,
            .total = total,
            .passed = 0,
            .failed = 0,
            .skipped = 0,
            .duration_ns = 0,
            .tests = std.ArrayList(TestRecord).empty,
        };
    }

    /// Record a test result
    pub fn recordTest(
        self: *Self,
        name: []const u8,
        suite_name: []const u8,
        status: suite.TestStatus,
        execution_time_ns: u64,
        error_message: ?[]const u8,
    ) !void {
        if (self.current_entry == null) return error.NoActiveRun;

        const name_copy = try self.allocator.dupe(u8, name);
        const suite_name_copy = try self.allocator.dupe(u8, suite_name);
        const status_str = @tagName(status);
        const status_copy = try self.allocator.dupe(u8, status_str);
        const error_msg_copy = if (error_message) |msg| try self.allocator.dupe(u8, msg) else null;

        const record = TestRecord{
            .name = name_copy,
            .suite_name = suite_name_copy,
            .status = status_copy,
            .execution_time_ns = execution_time_ns,
            .error_message = error_msg_copy,
        };

        try self.current_entry.?.tests.append(self.allocator, record);
    }

    /// Finish the test run and save to file
    pub fn finishRun(self: *Self, results: *reporter_mod.TestResults) !void {
        if (self.current_entry == null) return error.NoActiveRun;

        const end_time = std.time.milliTimestamp();
        self.current_entry.?.duration_ns = @intCast((end_time - self.start_time) * std.time.ns_per_ms);
        self.current_entry.?.passed = results.passed;
        self.current_entry.?.failed = results.failed;
        self.current_entry.?.skipped = results.skipped;

        try self.saveToFile();
    }

    /// Save current entry to a JSON file
    fn saveToFile(self: *Self) !void {
        if (self.current_entry == null) return;

        // Ensure history directory exists
        std.fs.cwd().makePath(self.history_dir) catch {};

        // Generate filename based on timestamp
        var filename_buf: [256]u8 = undefined;
        const filename = try std.fmt.bufPrint(&filename_buf, "{s}/test-run-{d}.json", .{ self.history_dir, self.current_entry.?.timestamp });

        // Create file
        const file = try std.fs.cwd().createFile(filename, .{});
        defer file.close();

        // Write JSON
        var buffer = std.ArrayList(u8).empty;
        defer buffer.deinit(self.allocator);

        const writer = buffer.writer(self.allocator);

        try writer.writeAll("{\n");
        try writer.print("  \"timestamp\": {d},\n", .{self.current_entry.?.timestamp});
        try writer.print("  \"total\": {d},\n", .{self.current_entry.?.total});
        try writer.print("  \"passed\": {d},\n", .{self.current_entry.?.passed});
        try writer.print("  \"failed\": {d},\n", .{self.current_entry.?.failed});
        try writer.print("  \"skipped\": {d},\n", .{self.current_entry.?.skipped});
        try writer.print("  \"duration_ns\": {d},\n", .{self.current_entry.?.duration_ns});
        try writer.writeAll("  \"tests\": [\n");

        for (self.current_entry.?.tests.items, 0..) |test_record, i| {
            try writer.writeAll("    {\n");
            try writer.print("      \"name\": \"{s}\",\n", .{test_record.name});
            try writer.print("      \"suite_name\": \"{s}\",\n", .{test_record.suite_name});
            try writer.print("      \"status\": \"{s}\",\n", .{test_record.status});
            try writer.print("      \"execution_time_ns\": {d}", .{test_record.execution_time_ns});

            if (test_record.error_message) |msg| {
                try writer.writeAll(",\n");
                try writer.print("      \"error_message\": \"{s}\"\n", .{msg});
            } else {
                try writer.writeAll("\n");
            }

            if (i < self.current_entry.?.tests.items.len - 1) {
                try writer.writeAll("    },\n");
            } else {
                try writer.writeAll("    }\n");
            }
        }

        try writer.writeAll("  ]\n");
        try writer.writeAll("}\n");

        try file.writeAll(buffer.items);
    }

    /// Get list of all history files
    pub fn listHistory(self: *Self) !std.ArrayList([]const u8) {
        var list = std.ArrayList([]const u8).empty;

        var dir = std.fs.cwd().openDir(self.history_dir, .{ .iterate = true }) catch |err| {
            if (err == error.FileNotFound) {
                return list;
            }
            return err;
        };
        defer dir.close();

        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".json")) {
                const name_copy = try self.allocator.dupe(u8, entry.name);
                try list.append(self.allocator, name_copy);
            }
        }

        return list;
    }

    /// Load a specific history entry
    pub fn loadHistory(self: *Self, filename: []const u8) !HistoryEntry {
        var path_buf: [512]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ self.history_dir, filename });

        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024); // 10MB max
        defer self.allocator.free(content);

        // For now, just return a simple entry
        // Full JSON parsing would require std.json.parseFromSlice
        return HistoryEntry{
            .timestamp = 0,
            .total = 0,
            .passed = 0,
            .failed = 0,
            .skipped = 0,
            .duration_ns = 0,
            .tests = std.ArrayList(TestRecord).empty,
        };
    }

    /// Clean old history files (keep last N)
    pub fn cleanOldHistory(self: *Self, keep_count: usize) !void {
        var history_files = try self.listHistory();
        defer {
            for (history_files.items) |name| {
                self.allocator.free(name);
            }
            history_files.deinit(self.allocator);
        }

        if (history_files.items.len <= keep_count) return;

        // Sort by name (which includes timestamp)
        std.mem.sort([]const u8, history_files.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a, b);
            }
        }.lessThan);

        // Delete oldest files
        const to_delete = history_files.items.len - keep_count;
        for (history_files.items[0..to_delete]) |filename| {
            var path_buf: [512]u8 = undefined;
            const path = try std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ self.history_dir, filename });
            std.fs.cwd().deleteFile(path) catch {};
        }
    }
};

// Tests
test "TestHistory initialization" {
    const allocator = std.testing.allocator;

    var history = TestHistory.init(allocator, ".test-history");
    defer history.deinit();

    try std.testing.expectEqual(@as(?HistoryEntry, null), history.current_entry);
}

test "TestHistory start and record" {
    const allocator = std.testing.allocator;

    var history = TestHistory.init(allocator, ".test-history");
    defer history.deinit();

    try history.startRun(5);
    try std.testing.expect(history.current_entry != null);
    try std.testing.expectEqual(@as(usize, 5), history.current_entry.?.total);

    try history.recordTest("test1", "suite1", .passed, 1000000, null);
    try std.testing.expectEqual(@as(usize, 1), history.current_entry.?.tests.items.len);
}
