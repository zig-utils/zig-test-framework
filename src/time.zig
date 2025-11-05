const std = @import("std");

/// Time mocking state
pub const TimeMock = struct {
    /// Whether fake timers are currently enabled
    is_fake: bool = false,

    /// The mocked timestamp (milliseconds since epoch)
    mocked_timestamp: ?i64 = null,

    /// Original timezone (to restore later)
    original_timezone: ?[]const u8 = null,

    allocator: std.mem.Allocator,

    const Self = @This();

    /// Initialize the time mock
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .is_fake = false,
            .mocked_timestamp = null,
            .original_timezone = null,
            .allocator = allocator,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        if (self.original_timezone) |tz| {
            self.allocator.free(tz);
        }
    }

    /// Enable fake timers (Jest compatibility)
    pub fn useFakeTimers(self: *Self) *Self {
        self.is_fake = true;
        return self;
    }

    /// Disable fake timers and restore real time (Jest compatibility)
    pub fn useRealTimers(self: *Self) *Self {
        self.is_fake = false;
        self.mocked_timestamp = null;
        return self;
    }

    /// Set the system time to a specific timestamp
    pub fn setSystemTime(self: *Self, timestamp: ?i64) *Self {
        if (timestamp) |ts| {
            self.mocked_timestamp = ts;
            self.is_fake = true;
        } else {
            // Reset to real time
            self.mocked_timestamp = null;
            self.is_fake = false;
        }
        return self;
    }

    /// Get current time (mocked or real)
    pub fn now(self: *Self) i64 {
        if (self.is_fake) {
            return self.mocked_timestamp orelse std.time.milliTimestamp();
        }
        return std.time.milliTimestamp();
    }

    /// Advance mocked time by milliseconds
    pub fn advanceTimersByTime(self: *Self, ms: i64) *Self {
        if (self.is_fake) {
            const current = self.mocked_timestamp orelse std.time.milliTimestamp();
            self.mocked_timestamp = current + ms;
        }
        return self;
    }

    /// Clear all timers (Jest compatibility - currently a no-op)
    pub fn clearAllTimers(self: *Self) *Self {
        // Timer mocking not yet implemented
        return self;
    }

    /// Run all timers (Jest compatibility - currently a no-op)
    pub fn runAllTimers(self: *Self) *Self {
        // Timer mocking not yet implemented
        return self;
    }

    /// Run pending timers (Jest compatibility - currently a no-op)
    pub fn runOnlyPendingTimers(self: *Self) *Self {
        // Timer mocking not yet implemented
        return self;
    }
};

/// Global time mock instance
var global_time_mock: ?TimeMock = null;
var time_mock_mutex = std.Thread.Mutex{};

/// Get or create the global time mock
pub fn getTimeMock(allocator: std.mem.Allocator) *TimeMock {
    time_mock_mutex.lock();
    defer time_mock_mutex.unlock();

    if (global_time_mock == null) {
        global_time_mock = TimeMock.init(allocator);
    }

    return &global_time_mock.?;
}

/// Clean up the global time mock
pub fn cleanupTimeMock() void {
    time_mock_mutex.lock();
    defer time_mock_mutex.unlock();

    if (global_time_mock) |*mock| {
        mock.deinit();
        global_time_mock = null;
    }
}

/// Set the system time globally (Bun-compatible API)
pub fn setSystemTime(allocator: std.mem.Allocator, timestamp: ?i64) void {
    const mock = getTimeMock(allocator);
    _ = mock.setSystemTime(timestamp);
}

/// Enable fake timers globally (Jest-compatible API)
pub fn useFakeTimers(allocator: std.mem.Allocator) void {
    const mock = getTimeMock(allocator);
    _ = mock.useFakeTimers();
}

/// Disable fake timers globally (Jest-compatible API)
pub fn useRealTimers(allocator: std.mem.Allocator) void {
    const mock = getTimeMock(allocator);
    _ = mock.useRealTimers();
}

/// Get current mocked or real time (Jest-compatible API)
pub fn now(allocator: std.mem.Allocator) i64 {
    const mock = getTimeMock(allocator);
    return mock.now();
}

/// Advance time by milliseconds (Jest-compatible API)
pub fn advanceTimersByTime(allocator: std.mem.Allocator, ms: i64) void {
    const mock = getTimeMock(allocator);
    _ = mock.advanceTimersByTime(ms);
}

/// Jest-compatible namespace for time functions
pub const jest = struct {
    /// Set the system time (Jest compatibility)
    pub fn setSystemTime(allocator: std.mem.Allocator, timestamp: i64) void {
        const mock = getTimeMock(allocator);
        _ = mock.setSystemTime(timestamp);
    }

    /// Enable fake timers (Jest compatibility)
    pub fn useFakeTimers(allocator: std.mem.Allocator) void {
        const mock = getTimeMock(allocator);
        _ = mock.useFakeTimers();
    }

    /// Disable fake timers (Jest compatibility)
    pub fn useRealTimers(allocator: std.mem.Allocator) void {
        const mock = getTimeMock(allocator);
        _ = mock.useRealTimers();
    }

    /// Get current mocked time (Jest compatibility)
    pub fn now(allocator: std.mem.Allocator) i64 {
        const mock = getTimeMock(allocator);
        return mock.now();
    }

    /// Advance time by milliseconds (Jest compatibility)
    pub fn advanceTimersByTime(allocator: std.mem.Allocator, ms: i64) void {
        const mock = getTimeMock(allocator);
        _ = mock.advanceTimersByTime(ms);
    }

    /// Clear all timers (Jest compatibility - no-op for now)
    pub fn clearAllTimers(allocator: std.mem.Allocator) void {
        const mock = getTimeMock(allocator);
        _ = mock.clearAllTimers();
    }

    /// Run all timers (Jest compatibility - no-op for now)
    pub fn runAllTimers(allocator: std.mem.Allocator) void {
        const mock = getTimeMock(allocator);
        _ = mock.runAllTimers();
    }

    /// Run pending timers (Jest compatibility - no-op for now)
    pub fn runOnlyPendingTimers(allocator: std.mem.Allocator) void {
        const mock = getTimeMock(allocator);
        _ = mock.runOnlyPendingTimers();
    }
};

/// Date helper functions for tests
pub const DateHelper = struct {
    allocator: std.mem.Allocator,

    /// Create a timestamp from year, month, day
    pub fn fromDate(year: u16, month: u8, day: u8) i64 {
        // Simple timestamp calculation (approximate)
        // This is a simplified version - for production use proper date library
        const days_since_epoch = @as(i64, year - 1970) * 365 +
                                 @as(i64, month - 1) * 30 +
                                 @as(i64, day);
        return days_since_epoch * 24 * 60 * 60 * 1000;
    }

    /// Create a timestamp from ISO 8601 string (simplified)
    pub fn fromISO(iso_string: []const u8) !i64 {
        // Simplified ISO 8601 parser
        // Expected format: "2020-01-01T00:00:00.000Z"
        if (iso_string.len < 10) return error.InvalidISOString;

        // Parse year
        const year = try std.fmt.parseInt(u16, iso_string[0..4], 10);
        const month = try std.fmt.parseInt(u8, iso_string[5..7], 10);
        const day = try std.fmt.parseInt(u8, iso_string[8..10], 10);

        var hours: u8 = 0;
        var minutes: u8 = 0;
        var seconds: u8 = 0;
        var millis: u16 = 0;

        // Parse time if present
        if (iso_string.len > 11 and iso_string[10] == 'T') {
            if (iso_string.len >= 16) {
                hours = try std.fmt.parseInt(u8, iso_string[11..13], 10);
                minutes = try std.fmt.parseInt(u8, iso_string[14..16], 10);
            }
            if (iso_string.len >= 19 and iso_string[16] == ':') {
                seconds = try std.fmt.parseInt(u8, iso_string[17..19], 10);
            }
            if (iso_string.len >= 23 and iso_string[19] == '.') {
                millis = try std.fmt.parseInt(u16, iso_string[20..23], 10);
            }
        }

        // Calculate days since epoch (1970-01-01)
        var days: i64 = 0;

        // Add years
        var y: u16 = 1970;
        while (y < year) : (y += 1) {
            days += if (isLeapYear(y)) 366 else 365;
        }

        // Add months
        const days_in_month = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
        var m: u8 = 1;
        while (m < month) : (m += 1) {
            days += days_in_month[m - 1];
            // Add leap day for February if needed
            if (m == 2 and isLeapYear(year)) {
                days += 1;
            }
        }

        // Add days
        days += day - 1;

        // Convert to milliseconds
        const total_millis = days * 24 * 60 * 60 * 1000 +
                           @as(i64, hours) * 60 * 60 * 1000 +
                           @as(i64, minutes) * 60 * 1000 +
                           @as(i64, seconds) * 1000 +
                           @as(i64, millis);

        return total_millis;
    }

    /// Check if a year is a leap year
    fn isLeapYear(year: u16) bool {
        if (year % 4 != 0) return false;
        if (year % 100 != 0) return true;
        return year % 400 == 0;
    }

    /// Get the current year from a timestamp
    pub fn getYear(timestamp: i64) u16 {
        const days = @divFloor(timestamp, 24 * 60 * 60 * 1000);
        var year: u16 = 1970;
        var remaining_days = days;

        while (remaining_days >= 365) {
            const year_days: i64 = if (isLeapYear(year)) 366 else 365;
            if (remaining_days < year_days) break;
            remaining_days -= year_days;
            year += 1;
        }

        return year;
    }

    /// Get the current timestamp (respects mocked time)
    pub fn now(self: DateHelper) i64 {
        const mock = getTimeMock(self.allocator);
        return mock.now();
    }
};

/// Create a date helper
pub fn createDateHelper(allocator: std.mem.Allocator) DateHelper {
    return .{ .allocator = allocator };
}

test "TimeMock basic functionality" {
    const allocator = std.testing.allocator;

    var mock = TimeMock.init(allocator);
    defer mock.deinit();

    // Initially using real time
    try std.testing.expect(!mock.is_fake);
    try std.testing.expect(mock.mocked_timestamp == null);

    // Enable fake timers
    _ = mock.useFakeTimers();
    try std.testing.expect(mock.is_fake);

    // Set a specific time
    const test_time: i64 = 1577836800000; // 2020-01-01T00:00:00.000Z
    _ = mock.setSystemTime(test_time);
    try std.testing.expectEqual(test_time, mock.now());

    // Advance time
    _ = mock.advanceTimersByTime(1000);
    try std.testing.expectEqual(test_time + 1000, mock.now());

    // Reset to real time
    _ = mock.useRealTimers();
    try std.testing.expect(!mock.is_fake);
    try std.testing.expect(mock.mocked_timestamp == null);
}

test "DateHelper ISO string parsing" {
    const timestamp = try DateHelper.fromISO("2020-01-01T00:00:00.000Z");

    // Verify it's close to the expected timestamp
    // 2020-01-01T00:00:00.000Z = 1577836800000
    const expected: i64 = 1577836800000;
    const diff = if (timestamp > expected) timestamp - expected else expected - timestamp;
    try std.testing.expect(diff < 86400000); // Within 1 day
}

test "DateHelper year calculation" {
    const timestamp: i64 = 1577836800000; // 2020-01-01T00:00:00.000Z
    const year = DateHelper.getYear(timestamp);
    try std.testing.expectEqual(@as(u16, 2020), year);
}
