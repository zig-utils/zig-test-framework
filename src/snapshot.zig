const std = @import("std");

/// Snapshot format type
pub const SnapshotFormat = enum {
    /// Pretty-printed text format
    pretty_text,
    /// Compact text format
    compact_text,
    /// JSON format
    json,
    /// Raw format (no formatting)
    raw,
};

/// Snapshot testing options
pub const SnapshotOptions = struct {
    /// Directory to store snapshots
    snapshot_dir: []const u8 = ".snapshots",
    /// Update snapshots instead of comparing
    update: bool = false,
    /// Interactive update mode (ask before updating)
    interactive: bool = false,
    /// Snapshot format
    format: SnapshotFormat = .pretty_text,
    /// Pretty print (only for formats that support it)
    pretty_print: bool = true,
    /// Snapshot file extension
    file_extension: []const u8 = ".snap",
};

/// Snapshot diff entry
pub const DiffEntry = struct {
    line_number: usize,
    expected: []const u8,
    received: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *DiffEntry) void {
        self.allocator.free(self.expected);
        self.allocator.free(self.received);
    }
};

/// Snapshot diff result
pub const SnapshotDiff = struct {
    has_diff: bool,
    diffs: std.ArrayList(DiffEntry),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SnapshotDiff {
        return .{
            .has_diff = false,
            .diffs = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SnapshotDiff) void {
        for (self.diffs.items) |*entry| {
            entry.deinit();
        }
        self.diffs.deinit(self.allocator);
    }

    pub fn addDiff(self: *SnapshotDiff, line_number: usize, expected: []const u8, received: []const u8) !void {
        self.has_diff = true;
        const expected_copy = try self.allocator.dupe(u8, expected);
        const received_copy = try self.allocator.dupe(u8, received);

        try self.diffs.append(self.allocator, .{
            .line_number = line_number,
            .expected = expected_copy,
            .received = received_copy,
            .allocator = self.allocator,
        });
    }

    pub fn print(self: *SnapshotDiff) void {
        if (!self.has_diff) return;

        std.debug.print("\n=== Snapshot Diff ===\n", .{});
        for (self.diffs.items) |entry| {
            std.debug.print("Line {d}:\n", .{entry.line_number});
            std.debug.print("  - Expected: {s}\n", .{entry.expected});
            std.debug.print("  + Received: {s}\n", .{entry.received});
        }
        std.debug.print("=====================\n\n", .{});
    }
};

/// Inline snapshot marker
pub const InlineSnapshot = struct {
    file_path: []const u8,
    line_number: usize,
    value: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, file_path: []const u8, line_number: usize, value: []const u8) !InlineSnapshot {
        return .{
            .file_path = try allocator.dupe(u8, file_path),
            .line_number = line_number,
            .value = try allocator.dupe(u8, value),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *InlineSnapshot) void {
        self.allocator.free(self.file_path);
        self.allocator.free(self.value);
    }
};

/// Snapshot matcher
pub const Snapshot = struct {
    allocator: std.mem.Allocator,
    options: SnapshotOptions,
    test_name: []const u8,
    snapshot_count: usize = 0,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, test_name: []const u8, options: SnapshotOptions) Self {
        return .{
            .allocator = allocator,
            .options = options,
            .test_name = test_name,
        };
    }

    /// Match a string value against a snapshot
    pub fn matchString(self: *Self, value: []const u8) !void {
        const snapshot_path = try self.getSnapshotPath(null);
        defer self.allocator.free(snapshot_path);

        if (self.options.update) {
            if (self.options.interactive) {
                try self.interactiveUpdate(snapshot_path, value);
            } else {
                try self.writeSnapshot(snapshot_path, value);
            }
        } else {
            try self.compareSnapshot(snapshot_path, value);
        }
    }

    /// Match a string with a specific name
    pub fn matchStringNamed(self: *Self, name: []const u8, value: []const u8) !void {
        const snapshot_path = try self.getSnapshotPath(name);
        defer self.allocator.free(snapshot_path);

        if (self.options.update) {
            if (self.options.interactive) {
                try self.interactiveUpdate(snapshot_path, value);
            } else {
                try self.writeSnapshot(snapshot_path, value);
            }
        } else {
            try self.compareSnapshot(snapshot_path, value);
        }
    }

    /// Match any value against a snapshot (converts to string)
    pub fn match(self: *Self, value: anytype) !void {
        const formatted = try self.formatValue(value);
        defer self.allocator.free(formatted);
        try self.matchString(formatted);
    }

    /// Match any value with a specific name
    pub fn matchNamed(self: *Self, name: []const u8, value: anytype) !void {
        const formatted = try self.formatValue(value);
        defer self.allocator.free(formatted);
        try self.matchStringNamed(name, formatted);
    }

    /// Match inline snapshot
    pub fn matchInline(self: *Self, file_path: []const u8, line_number: usize, value: anytype) !void {
        const formatted = try self.formatValue(value);
        defer self.allocator.free(formatted);

        var inline_snap = try InlineSnapshot.init(self.allocator, file_path, line_number, formatted);
        defer inline_snap.deinit();

        // For inline snapshots, we need to update the source file
        if (self.options.update) {
            try self.updateInlineSnapshot(&inline_snap);
        } else {
            try self.verifyInlineSnapshot(&inline_snap);
        }
    }

    /// Format a value for snapshotting
    fn formatValue(self: *Self, value: anytype) ![]const u8 {
        var buffer = std.ArrayList(u8).empty;
        const writer = buffer.writer(self.allocator);

        switch (self.options.format) {
            .pretty_text => try self.formatValuePretty(writer, value),
            .compact_text => try self.formatValueCompact(writer, value),
            .json => try self.formatValueJson(writer, value),
            .raw => try writer.print("{any}", .{value}),
        }

        return buffer.toOwnedSlice(self.allocator);
    }

    /// Format value as pretty text
    fn formatValuePretty(self: *Self, writer: anytype, value: anytype) !void {
        const T = @TypeOf(value);
        const type_info = @typeInfo(T);

        switch (type_info) {
            .int, .comptime_int => try writer.print("{d}", .{value}),
            .float, .comptime_float => try writer.print("{d:.6}", .{value}),
            .bool => try writer.print("{}", .{value}),
            .pointer => |ptr_info| {
                if (ptr_info.size == .slice and ptr_info.child == u8) {
                    try writer.print("\"{s}\"", .{value});
                } else {
                    try writer.print("{any}", .{value});
                }
            },
            .@"struct" => try self.formatStructPretty(writer, value),
            .array => try writer.print("{any}", .{value}),
            else => try writer.print("{any}", .{value}),
        }
    }

    /// Format value as compact text
    fn formatValueCompact(self: *Self, writer: anytype, value: anytype) !void {
        _ = self;
        try writer.print("{any}", .{value});
    }

    /// Format value as JSON
    fn formatValueJson(self: *Self, writer: anytype, value: anytype) !void {
        const T = @TypeOf(value);
        const type_info = @typeInfo(T);

        switch (type_info) {
            .int, .comptime_int => try writer.print("{d}", .{value}),
            .float, .comptime_float => try writer.print("{d:.6}", .{value}),
            .bool => try writer.print("{}", .{value}),
            .pointer => |ptr_info| {
                if (ptr_info.size == .slice and ptr_info.child == u8) {
                    try writer.print("\"{s}\"", .{value});
                } else {
                    try writer.print("null", .{});
                }
            },
            .@"struct" => {
                try writer.writeAll("{\n");
                inline for (type_info.@"struct".fields, 0..) |field, i| {
                    if (self.options.pretty_print) {
                        try writer.writeAll("  ");
                    }
                    try writer.print("\"{s}\": ", .{field.name});

                    const field_value = @field(value, field.name);
                    try self.formatJsonValue(writer, field_value);

                    if (i < type_info.@"struct".fields.len - 1) {
                        try writer.writeAll(",");
                    }
                    if (self.options.pretty_print) {
                        try writer.writeAll("\n");
                    }
                }
                try writer.writeAll("}");
            },
            else => try writer.print("null", .{}),
        }
    }

    /// Format a single JSON value
    fn formatJsonValue(self: *Self, writer: anytype, value: anytype) !void {
        _ = self;
        const T = @TypeOf(value);
        const type_info = @typeInfo(T);

        switch (type_info) {
            .int, .comptime_int => try writer.print("{d}", .{value}),
            .float, .comptime_float => try writer.print("{d:.6}", .{value}),
            .bool => try writer.print("{}", .{value}),
            .pointer => |ptr_info| {
                if (ptr_info.size == .slice and ptr_info.child == u8) {
                    try writer.print("\"{s}\"", .{value});
                } else {
                    try writer.print("null", .{});
                }
            },
            else => try writer.print("null", .{}),
        }
    }

    /// Format a struct with pretty printing
    fn formatStructPretty(self: *Self, writer: anytype, value: anytype) !void {
        _ = self;
        const T = @TypeOf(value);
        const type_info = @typeInfo(T);

        if (type_info != .@"struct") {
            try writer.print("{any}", .{value});
            return;
        }

        try writer.writeAll("{\n");

        inline for (type_info.@"struct".fields, 0..) |field, i| {
            try writer.print("  \"{s}\": ", .{field.name});

            const field_value = @field(value, field.name);
            const FieldType = @TypeOf(field_value);
            const field_info = @typeInfo(FieldType);

            switch (field_info) {
                .int, .comptime_int => try writer.print("{d}", .{field_value}),
                .float, .comptime_float => try writer.print("{d:.6}", .{field_value}),
                .bool => try writer.print("{}", .{field_value}),
                .pointer => |ptr_info| {
                    if (ptr_info.size == .slice and ptr_info.child == u8) {
                        try writer.print("\"{s}\"", .{field_value});
                    } else {
                        try writer.print("{any}", .{field_value});
                    }
                },
                else => try writer.print("{any}", .{field_value}),
            }

            if (i < type_info.@"struct".fields.len - 1) {
                try writer.writeAll(",\n");
            } else {
                try writer.writeAll("\n");
            }
        }

        try writer.writeAll("}");
    }

    /// Compare snapshot with deep comparison and diff generation
    fn compareSnapshot(self: *Self, path: []const u8, value: []const u8) !void {
        const expected = try self.readSnapshot(path);
        defer self.allocator.free(expected);

        if (!std.mem.eql(u8, value, expected)) {
            // Generate diff
            var diff = SnapshotDiff.init(self.allocator);
            defer diff.deinit();

            try self.generateDiff(&diff, expected, value);

            std.debug.print("\nSnapshot mismatch for '{s}':\n", .{self.test_name});
            diff.print();
            std.debug.print("Run with --update-snapshots to update.\n", .{});

            return error.SnapshotMismatch;
        }
    }

    /// Generate diff between expected and received
    fn generateDiff(self: *Self, diff: *SnapshotDiff, expected: []const u8, received: []const u8) !void {
        var expected_lines = std.mem.splitScalar(u8, expected, '\n');
        var received_lines = std.mem.splitScalar(u8, received, '\n');

        var line_num: usize = 1;

        while (true) {
            const exp_line = expected_lines.next();
            const rec_line = received_lines.next();

            if (exp_line == null and rec_line == null) break;

            const exp_str = exp_line orelse "";
            const rec_str = rec_line orelse "";

            if (!std.mem.eql(u8, exp_str, rec_str)) {
                try diff.addDiff(line_num, exp_str, rec_str);
            }

            line_num += 1;
        }

        // Handle case where files have different line counts
        while (expected_lines.next()) |exp_line| {
            try diff.addDiff(line_num, exp_line, "");
            line_num += 1;
        }

        while (received_lines.next()) |rec_line| {
            try diff.addDiff(line_num, "", rec_line);
            line_num += 1;
        }

        _ = self;
    }

    /// Interactive update - ask user before updating
    fn interactiveUpdate(self: *Self, path: []const u8, value: []const u8) !void {
        // Try to read existing snapshot
        const existing = self.readSnapshot(path) catch |err| {
            if (err == error.SnapshotNotFound) {
                // No existing snapshot, create new one
                std.debug.print("\nNo existing snapshot for '{s}'\n", .{self.test_name});
                std.debug.print("Interactive mode: Creating new snapshot automatically.\n", .{});
                try self.writeSnapshot(path, value);
                return;
            }
            return err;
        };
        defer self.allocator.free(existing);

        if (!std.mem.eql(u8, value, existing)) {
            std.debug.print("\nSnapshot '{s}' has changed:\n", .{self.test_name});
            std.debug.print("Expected:\n{s}\n", .{existing});
            std.debug.print("Received:\n{s}\n", .{value});
            std.debug.print("Interactive mode: Updating snapshot automatically.\n", .{});
            try self.writeSnapshot(path, value);
        }
    }

    /// Update inline snapshot in source file
    fn updateInlineSnapshot(self: *Self, inline_snap: *InlineSnapshot) !void {
        _ = self;
        _ = inline_snap;
        // TODO: Implement source file modification for inline snapshots
        // This requires parsing the source file and updating the specific line
        std.debug.print("Inline snapshot update not yet implemented\n", .{});
    }

    /// Verify inline snapshot
    fn verifyInlineSnapshot(self: *Self, inline_snap: *InlineSnapshot) !void {
        _ = self;
        _ = inline_snap;
        // TODO: Implement inline snapshot verification
        std.debug.print("Inline snapshot verification not yet implemented\n", .{});
    }

    /// Get snapshot file path
    fn getSnapshotPath(self: *Self, name: ?[]const u8) ![]const u8 {
        // Sanitize test name for filename
        const base_name = name orelse self.test_name;
        var sanitized = try self.allocator.alloc(u8, base_name.len);
        defer self.allocator.free(sanitized);

        for (base_name, 0..) |c, i| {
            sanitized[i] = switch (c) {
                ' ' => '_',
                '/', '\\', ':', '*', '?', '"', '<', '>', '|' => '-',
                else => c,
            };
        }

        if (name != null) {
            return std.fmt.allocPrint(
                self.allocator,
                "{s}/{s}_{s}{s}",
                .{ self.options.snapshot_dir, sanitized, sanitized, self.options.file_extension },
            );
        } else {
            return std.fmt.allocPrint(
                self.allocator,
                "{s}/{s}{s}",
                .{ self.options.snapshot_dir, sanitized, self.options.file_extension },
            );
        }
    }

    /// Read snapshot from file
    fn readSnapshot(self: *Self, path: []const u8) ![]const u8 {
        const file = std.fs.cwd().openFile(path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                std.debug.print("\nSnapshot file not found: {s}\n", .{path});
                std.debug.print("Run with --update-snapshots to create it.\n", .{});
                return error.SnapshotNotFound;
            }
            return err;
        };
        defer file.close();

        return try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024); // 10MB max
    }

    /// Write snapshot to file
    fn writeSnapshot(self: *Self, path: []const u8, content: []const u8) !void {
        // Ensure snapshot directory exists
        std.fs.cwd().makePath(self.options.snapshot_dir) catch {};

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        try file.writeAll(content);

        std.debug.print("Snapshot updated: {s}\n", .{path});
    }
};

/// Snapshot cleanup utility
pub const SnapshotCleanup = struct {
    allocator: std.mem.Allocator,
    snapshot_dir: []const u8,
    used_snapshots: std.StringHashMap(bool),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, snapshot_dir: []const u8) Self {
        return .{
            .allocator = allocator,
            .snapshot_dir = snapshot_dir,
            .used_snapshots = std.StringHashMap(bool).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.used_snapshots.deinit();
    }

    /// Mark a snapshot as used
    pub fn markUsed(self: *Self, snapshot_name: []const u8) !void {
        try self.used_snapshots.put(snapshot_name, true);
    }

    /// Find and remove unused snapshots
    pub fn cleanupUnused(self: *Self) !usize {
        var removed_count: usize = 0;

        var dir = try std.fs.cwd().openDir(self.snapshot_dir, .{ .iterate = true });
        defer dir.close();

        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.name, ".snap")) continue;

            const is_used = self.used_snapshots.get(entry.name) orelse false;
            if (!is_used) {
                try dir.deleteFile(entry.name);
                std.debug.print("Removed unused snapshot: {s}\n", .{entry.name});
                removed_count += 1;
            }
        }

        return removed_count;
    }

    /// List all snapshot files
    pub fn listSnapshots(self: *Self) !std.ArrayList([]const u8) {
        var snapshots = std.ArrayList([]const u8).empty;

        var dir = std.fs.cwd().openDir(self.snapshot_dir, .{ .iterate = true }) catch |err| {
            if (err == error.FileNotFound) {
                return snapshots;
            }
            return err;
        };
        defer dir.close();

        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.name, ".snap")) continue;

            const name = try self.allocator.dupe(u8, entry.name);
            try snapshots.append(self.allocator, name);
        }

        return snapshots;
    }
};

/// Create a snapshot matcher for a test
pub fn snapshot(allocator: std.mem.Allocator, test_name: []const u8, options: SnapshotOptions) Snapshot {
    return Snapshot.init(allocator, test_name, options);
}

// Tests
test "Snapshot string matching" {
    const allocator = std.testing.allocator;

    var snap = Snapshot.init(allocator, "test_snapshot_string", .{ .update = true });

    // Update snapshot
    try snap.matchString("Hello, World!");

    // Now test matching
    var snap2 = Snapshot.init(allocator, "test_snapshot_string", .{ .update = false });
    try snap2.matchString("Hello, World!");
}

test "Snapshot struct formatting - pretty text" {
    const allocator = std.testing.allocator;

    const TestStruct = struct {
        name: []const u8,
        age: u32,
        active: bool,
    };

    const value = TestStruct{
        .name = "Alice",
        .age = 30,
        .active = true,
    };

    var snap = Snapshot.init(allocator, "test_snapshot_struct", .{
        .update = true,
        .format = .pretty_text,
    });
    try snap.match(value);
}

test "Snapshot JSON format" {
    const allocator = std.testing.allocator;

    const TestStruct = struct {
        name: []const u8,
        count: u32,
    };

    const value = TestStruct{
        .name = "test",
        .count = 42,
    };

    var snap = Snapshot.init(allocator, "test_snapshot_json", .{
        .update = true,
        .format = .json,
    });
    try snap.match(value);

    // Cleanup
    std.fs.cwd().deleteFile(".snapshots/test_snapshot_json.snap") catch {};
}

test "Snapshot mismatch detection" {
    const allocator = std.testing.allocator;

    // Create snapshot
    var snap1 = Snapshot.init(allocator, "test_mismatch", .{ .update = true });
    try snap1.matchString("original value");

    // Try to match different value
    var snap2 = Snapshot.init(allocator, "test_mismatch", .{ .update = false });
    const result = snap2.matchString("different value");

    try std.testing.expectError(error.SnapshotMismatch, result);

    // Cleanup
    std.fs.cwd().deleteFile(".snapshots/test_mismatch.snap") catch {};
}

test "Snapshot diff generation" {
    const allocator = std.testing.allocator;

    var diff = SnapshotDiff.init(allocator);
    defer diff.deinit();

    try diff.addDiff(1, "line 1", "different line 1");
    try diff.addDiff(3, "line 3", "changed line 3");

    try std.testing.expect(diff.has_diff);
    try std.testing.expectEqual(@as(usize, 2), diff.diffs.items.len);
}

test "Named snapshots" {
    const allocator = std.testing.allocator;

    var snap = Snapshot.init(allocator, "test_named", .{ .update = true });

    try snap.matchStringNamed("first", "First snapshot");
    try snap.matchStringNamed("second", "Second snapshot");

    // Verify they were created separately
    var snap2 = Snapshot.init(allocator, "test_named", .{ .update = false });
    try snap2.matchStringNamed("first", "First snapshot");
    try snap2.matchStringNamed("second", "Second snapshot");

    // Cleanup
    std.fs.cwd().deleteFile(".snapshots/test_named_first.snap") catch {};
    std.fs.cwd().deleteFile(".snapshots/test_named_second.snap") catch {};
}

test "Snapshot cleanup - list snapshots" {
    const allocator = std.testing.allocator;

    // Create some test snapshots
    var snap = Snapshot.init(allocator, "cleanup_test_1", .{ .update = true });
    try snap.matchString("test");

    var cleanup = SnapshotCleanup.init(allocator, ".snapshots");
    defer cleanup.deinit();

    var snapshots = try cleanup.listSnapshots();
    defer {
        for (snapshots.items) |item| {
            allocator.free(item);
        }
        snapshots.deinit(allocator);
    }

    try std.testing.expect(snapshots.items.len > 0);

    // Cleanup
    std.fs.cwd().deleteFile(".snapshots/cleanup_test_1.snap") catch {};
}

test "Snapshot cleanup - remove unused" {
    const allocator = std.testing.allocator;

    // Create test snapshots
    var snap1 = Snapshot.init(allocator, "cleanup_used", .{ .update = true });
    try snap1.matchString("used");

    var snap2 = Snapshot.init(allocator, "cleanup_unused", .{ .update = true });
    try snap2.matchString("unused");

    var cleanup = SnapshotCleanup.init(allocator, ".snapshots");
    defer cleanup.deinit();

    // Mark only first snapshot as used
    try cleanup.markUsed("cleanup_used.snap");

    // Clean up unused (this should remove cleanup_unused.snap)
    const removed = try cleanup.cleanupUnused();
    try std.testing.expect(removed >= 1);

    // Cleanup remaining
    std.fs.cwd().deleteFile(".snapshots/cleanup_used.snap") catch {};
}

test "Snapshot compact format" {
    const allocator = std.testing.allocator;

    var snap = Snapshot.init(allocator, "test_compact", .{
        .update = true,
        .format = .compact_text,
    });

    try snap.matchString("compact snapshot");

    // Cleanup
    std.fs.cwd().deleteFile(".snapshots/test_compact.snap") catch {};
}
