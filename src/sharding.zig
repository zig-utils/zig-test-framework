const std = @import("std");

pub const ShardError = error{
    InvalidShardCount,
    InvalidShardIndex,
};

/// A one-based shard selection suitable for CI matrix values.
pub const ShardOptions = struct {
    index: usize,
    count: usize,

    pub fn validate(self: ShardOptions) ShardError!void {
        if (self.count == 0) return ShardError.InvalidShardCount;
        if (self.index == 0 or self.index > self.count) return ShardError.InvalidShardIndex;
    }

    pub fn includes(self: ShardOptions, identity: []const u8) ShardError!bool {
        try self.validate();
        return (try shardIndex(identity, self.count)) + 1 == self.index;
    }
};

/// Assign a normalized test identity to a zero-based shard using FNV-1a 64.
/// Path separators are normalized so the same relative path maps identically
/// on Unix and Windows. The algorithm and seed are intentionally fixed.
pub fn shardIndex(identity: []const u8, shard_count: usize) ShardError!usize {
    if (shard_count == 0) return ShardError.InvalidShardCount;

    var hash: u64 = 14_695_981_039_346_656_037;
    for (identity) |byte| {
        const normalized = if (byte == '\\') @as(u8, '/') else byte;
        hash ^= normalized;
        hash *%= 1_099_511_628_211;
    }

    const count: u64 = @intCast(shard_count);
    return @intCast(hash % count);
}

test "fixed identities have stable shard assignments" {
    try std.testing.expectEqual(@as(usize, 1), try shardIndex("tests/api.test.zig", 4));
    try std.testing.expectEqual(@as(usize, 1), try shardIndex("tests/db.test.zig", 4));
    try std.testing.expectEqual(@as(usize, 2), try shardIndex("tests/unit/math.test.zig", 4));
}

test "path separators do not change shard assignment" {
    try std.testing.expectEqual(
        try shardIndex("tests/unit/math.test.zig", 7),
        try shardIndex("tests\\unit\\math.test.zig", 7),
    );
}

test "every identity belongs to exactly one shard" {
    const identities = [_][]const u8{
        "tests/api.test.zig",
        "tests/db.test.zig",
        "tests/unit/math.test.zig",
        "tests/unit/string.test.zig",
    };

    for (identities) |identity| {
        var matches: usize = 0;
        for (1..5) |index| {
            if (try (ShardOptions{ .index = index, .count = 4 }).includes(identity)) {
                matches += 1;
            }
        }
        try std.testing.expectEqual(@as(usize, 1), matches);
    }
}

test "invalid shard options are rejected" {
    try std.testing.expectError(
        ShardError.InvalidShardCount,
        (ShardOptions{ .index = 1, .count = 0 }).validate(),
    );
    try std.testing.expectError(ShardError.InvalidShardCount, shardIndex("test.zig", 0));
    try std.testing.expectError(
        ShardError.InvalidShardIndex,
        (ShardOptions{ .index = 0, .count = 2 }).validate(),
    );
    try std.testing.expectError(
        ShardError.InvalidShardIndex,
        (ShardOptions{ .index = 3, .count = 2 }).validate(),
    );
}
