const std = @import("std");

/// Major version of the public JSON event protocol.
pub const version: u16 = 1;

pub const Status = enum { pending, running, passed, flaky, failed, skipped };
pub const HookKind = enum { before_all, before_each, after_each, after_all };
pub const OutputStream = enum { stdout, stderr };

pub const RunStart = struct {
    total: usize,
    random_seed: ?u64 = null,
};
pub const RunEnd = struct {
    total: usize,
    passed: usize,
    flaky: usize,
    failed: usize,
    skipped: usize,
    duration_ns: u64 = 0,
    random_seed: ?u64 = null,
};
pub const Suite = struct { name: []const u8 };
pub const TestStart = struct { name: []const u8, suite: ?[]const u8 = null };
pub const TestEnd = struct {
    name: []const u8,
    suite: ?[]const u8 = null,
    status: Status,
    duration_ns: u64,
    error_message: ?[]const u8 = null,
};
pub const Hook = struct {
    kind: HookKind,
    suite: ?[]const u8 = null,
    test_name: ?[]const u8 = null,
    status: Status,
    duration_ns: u64 = 0,
    error_message: ?[]const u8 = null,
};
pub const Output = struct {
    stream: OutputStream,
    text: []const u8,
    test_name: ?[]const u8 = null,
};
pub const Retry = struct {
    name: []const u8,
    attempt: usize,
    repetition: usize,
    status: Status,
    duration_ns: u64,
    error_message: ?[]const u8 = null,
};
pub const Coverage = struct {
    line_percent: ?f64 = null,
    function_percent: ?f64 = null,
    branch_percent: ?f64 = null,
    report_path: ?[]const u8 = null,
};

/// Every serialized value is an envelope with the same version/type/data
/// shape. Unknown fields and event types are intentionally safe to ignore.
pub const Event = union(enum) {
    run_start: RunStart,
    run_end: RunEnd,
    suite_start: Suite,
    suite_end: Suite,
    test_start: TestStart,
    test_end: TestEnd,
    hook: Hook,
    output: Output,
    retry: Retry,
    coverage: Coverage,

    pub fn eventName(self: Event) []const u8 {
        return @tagName(std.meta.activeTag(self));
    }

    pub fn jsonStringify(self: Event, json: anytype) !void {
        try json.beginObject();
        try json.objectField("protocol_version");
        try json.write(version);
        try json.objectField("type");
        try json.write(self.eventName());
        try json.objectField("data");
        switch (self) {
            inline else => |payload| try json.write(payload),
        }
        try json.endObject();
    }
};

pub fn status(value: anytype) Status {
    return std.meta.stringToEnum(Status, @tagName(value)) orelse unreachable;
}

pub fn encodeAlloc(allocator: std.mem.Allocator, event: Event) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, event, .{});
}

test "every event type follows the versioned envelope contract" {
    const events = [_]Event{
        .{ .run_start = .{ .total = 2 } },
        .{ .run_end = .{ .total = 2, .passed = 1, .flaky = 0, .failed = 1, .skipped = 0 } },
        .{ .suite_start = .{ .name = "suite \"one\"" } },
        .{ .suite_end = .{ .name = "suite \"one\"" } },
        .{ .test_start = .{ .name = "line\nbreak", .suite = "suite" } },
        .{ .test_end = .{ .name = "line\nbreak", .status = .failed, .duration_ns = 42, .error_message = "bad \"value\"" } },
        .{ .hook = .{ .kind = .before_each, .test_name = "case", .status = .passed } },
        .{ .output = .{ .stream = .stderr, .text = "hello\nworld", .test_name = "case" } },
        .{ .retry = .{ .name = "case", .attempt = 2, .repetition = 1, .status = .passed, .duration_ns = 10 } },
        .{ .coverage = .{ .line_percent = 90.5, .report_path = "coverage/index.html" } },
    };

    inline for (events) |event| {
        const encoded = try encodeAlloc(std.testing.allocator, event);
        defer std.testing.allocator.free(encoded);
        var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, encoded, .{});
        defer parsed.deinit();
        const object = parsed.value.object;
        try std.testing.expectEqual(@as(i64, version), object.get("protocol_version").?.integer);
        try std.testing.expectEqualStrings(event.eventName(), object.get("type").?.string);
        try std.testing.expect(object.get("data") != null);
    }
}

test "event payload strings use standard JSON escaping" {
    const encoded = try encodeAlloc(std.testing.allocator, .{ .test_end = .{
        .name = "case\tname",
        .status = .failed,
        .duration_ns = 1,
        .error_message = "line one\n\"quoted\" and \\escaped",
    } });
    defer std.testing.allocator.free(encoded);

    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, encoded, .{});
    defer parsed.deinit();
    const data = parsed.value.object.get("data").?.object;
    try std.testing.expectEqualStrings("case\tname", data.get("name").?.string);
    try std.testing.expectEqualStrings("line one\n\"quoted\" and \\escaped", data.get("error_message").?.string);
}
