const std = @import("std");
const compat = @import("compat.zig");

/// Return the seed that should control this run. Supplying a seed enables
/// shuffling even when `shuffle` is false; otherwise random order is opt-in.
pub fn resolveSeed(shuffle: bool, configured: ?u64) ?u64 {
    if (configured) |seed| return seed;
    if (!shuffle) return null;
    return @truncate(@as(u128, @bitCast(compat.nanoTimestamp())));
}

pub const Shuffler = struct {
    prng: std.Random.DefaultPrng,

    pub fn init(seed: u64) Shuffler {
        return .{ .prng = std.Random.DefaultPrng.init(seed) };
    }

    pub fn shuffle(self: *Shuffler, comptime T: type, items: []T) void {
        self.prng.random().shuffleWithIndex(T, items, u64);
    }
};

test "random order is opt-in and an explicit seed enables it" {
    try std.testing.expect(resolveSeed(false, null) == null);
    try std.testing.expect(resolveSeed(true, null) != null);
    try std.testing.expectEqual(@as(?u64, 0), resolveSeed(false, 0));
    try std.testing.expectEqual(@as(?u64, 42), resolveSeed(true, 42));
}

test "the same seed produces the same order" {
    var first = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    var second = first;
    var first_shuffler = Shuffler.init(123456789);
    var second_shuffler = Shuffler.init(123456789);

    first_shuffler.shuffle(u8, &first);
    second_shuffler.shuffle(u8, &second);

    try std.testing.expectEqualSlices(u8, &first, &second);
    try std.testing.expect(!std.mem.eql(u8, &first, &[_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 }));
}
