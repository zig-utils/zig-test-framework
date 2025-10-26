const std = @import("std");

/// Snapshot testing options
pub const SnapshotOptions = struct {
    /// Directory to store snapshots
    snapshot_dir: []const u8 = ".snapshots",
    /// Update snapshots instead of comparing
    update: bool = false,
    /// Pretty print JSON snapshots
    pretty_print: bool = true,
};

/// Snapshot matcher
pub const Snapshot = struct {
    allocator: std.mem.Allocator,
    options: SnapshotOptions,
    test_name: []const u8,

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
        const snapshot_path = try self.getSnapshotPath();
        defer self.allocator.free(snapshot_path);

        if (self.options.update) {
            try self.writeSnapshot(snapshot_path, value);
        } else {
            const expected = try self.readSnapshot(snapshot_path);
            defer self.allocator.free(expected);

            if (!std.mem.eql(u8, value, expected)) {
                std.debug.print("\nSnapshot mismatch for '{s}':\n", .{self.test_name});
                std.debug.print("Expected:\n{s}\n", .{expected});
                std.debug.print("Received:\n{s}\n", .{value});
                std.debug.print("\nRun with --update-snapshots to update.\n", .{});
                return error.SnapshotMismatch;
            }
        }
    }

    /// Match any value against a snapshot (converts to string)
    pub fn match(self: *Self, value: anytype) !void {
        var buffer = std.ArrayList(u8).empty;
        defer buffer.deinit(self.allocator);

        const writer = buffer.writer(self.allocator);
        try self.formatValue(writer, value);

        try self.matchString(buffer.items);
    }

    /// Format a value for snapshotting
    fn formatValue(self: *Self, writer: anytype, value: anytype) !void {
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
            .@"struct" => {
                if (self.options.pretty_print) {
                    try self.formatStructPretty(writer, value);
                } else {
                    try writer.print("{any}", .{value});
                }
            },
            .array => try writer.print("{any}", .{value}),
            else => try writer.print("{any}", .{value}),
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

    /// Get snapshot file path
    fn getSnapshotPath(self: *Self) ![]const u8 {
        // Sanitize test name for filename
        var sanitized = try self.allocator.alloc(u8, self.test_name.len);
        defer self.allocator.free(sanitized);

        for (self.test_name, 0..) |c, i| {
            sanitized[i] = switch (c) {
                ' ' => '_',
                '/', '\\', ':', '*', '?', '"', '<', '>', '|' => '-',
                else => c,
            };
        }

        return std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}.snap",
            .{ self.options.snapshot_dir, sanitized },
        );
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

    // Now test matching (would fail if content different)
    var snap2 = Snapshot.init(allocator, "test_snapshot_string", .{ .update = false });
    try snap2.matchString("Hello, World!");

    // Cleanup
    std.fs.cwd().deleteFile(".snapshots/test_snapshot_string.snap") catch {};
}

test "Snapshot struct formatting" {
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

    var snap = Snapshot.init(allocator, "test_snapshot_struct", .{ .update = true });
    try snap.match(value);

    // Cleanup
    std.fs.cwd().deleteFile(".snapshots/test_snapshot_struct.snap") catch {};
}
