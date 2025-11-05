# Dates and Times

Learn how to manipulate time and dates in your Zig tests using `setSystemTime` and Jest-compatible functions.

The Zig Test Framework lets you control what time it is in your tests, making it easy to test time-dependent logic deterministically.

## Table of Contents

- [Basic Time Mocking](#basic-time-mocking)
- [API Reference](#api-reference)
- [Jest Compatibility](#jest-compatibility)
- [Advancing Time](#advancing-time)
- [Date Helpers](#date-helpers)
- [Best Practices](#best-practices)
- [Examples](#examples)

## Basic Time Mocking

### setSystemTime

To change the system time, use `setSystemTime`:

```zig
const std = @import("std");
const ztf = @import("zig-test-framework");

test "time mocking example" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try ztf.describe(allocator, "Time Tests", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.beforeAll(alloc, setupTime);
            try ztf.it(alloc, "it is 2020", testYear);
            try ztf.afterAll(alloc, cleanupTime);
        }

        fn setupTime(alloc: std.mem.Allocator) !void {
            // Set to Jan 1, 2020
            ztf.setSystemTime(alloc, 1577836800000);
        }

        fn testYear(alloc: std.mem.Allocator) !void {
            const year = ztf.DateHelper.getYear(ztf.time.now(alloc));
            try ztf.expect(alloc, year).toBe(@as(u16, 2020));
        }

        fn cleanupTime(alloc: std.mem.Allocator) !void {
            ztf.setSystemTime(alloc, null);
        }
    }.testSuite);

    const registry = ztf.getRegistry(allocator);
    _ = try ztf.runTests(allocator, registry);
    ztf.cleanupRegistry();
    ztf.cleanupTimeMock();
}
```

## API Reference

### Time Mocking Functions

#### setSystemTime

```zig
pub fn setSystemTime(allocator: std.mem.Allocator, timestamp: ?i64) void
```

Sets the system time to a specific timestamp (milliseconds since Unix epoch).

**Parameters:**
- `allocator`: Memory allocator
- `timestamp`: Unix timestamp in milliseconds, or `null` to reset to real time

**Example:**
```zig
// Set to Jan 1, 2020, 00:00:00 UTC
ztf.setSystemTime(alloc, 1577836800000);

// Reset to real time
ztf.setSystemTime(alloc, null);
```

#### useFakeTimers

```zig
pub fn useFakeTimers(allocator: std.mem.Allocator) void
```

Enable fake timers mode. Time will not advance unless explicitly set or advanced.

**Example:**
```zig
ztf.useFakeTimers(alloc);
ztf.setSystemTime(alloc, 1577836800000);
// Time is now frozen at Jan 1, 2020
```

#### useRealTimers

```zig
pub fn useRealTimers(allocator: std.mem.Allocator) void
```

Disable fake timers and return to real system time.

**Example:**
```zig
ztf.useRealTimers(alloc);
// Time advances normally again
```

#### advanceTimersByTime

```zig
pub fn advanceTimersByTime(allocator: std.mem.Allocator, ms: i64) void
```

Advance mocked time by a specified number of milliseconds.

**Parameters:**
- `allocator`: Memory allocator
- `ms`: Milliseconds to advance

**Example:**
```zig
ztf.setSystemTime(alloc, 1577836800000);
ztf.advanceTimersByTime(alloc, 60000); // Advance 1 minute
// Time is now Jan 1, 2020, 00:01:00
```

#### now

```zig
pub fn now(allocator: std.mem.Allocator) i64
```

Get the current time (mocked or real) as a Unix timestamp in milliseconds.

**Example:**
```zig
const current_time = ztf.time.now(alloc);
```

### cleanupTimeMock

```zig
pub fn cleanupTimeMock() void
```

Clean up time mocking resources. Call this after your tests complete.

**Example:**
```zig
defer ztf.cleanupTimeMock();
```

## Jest Compatibility

The framework provides Jest-compatible APIs for easier migration from JavaScript tests:

### jest.setSystemTime

```zig
test "jest compatible" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try ztf.describe(allocator, "Jest API", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "works like jest", testJest);
        }

        fn testJest(alloc: std.mem.Allocator) !void {
            ztf.jest.useFakeTimers(alloc);
            ztf.jest.setSystemTime(alloc, 1577836800000);

            const year = ztf.DateHelper.getYear(ztf.jest.now(alloc));
            try ztf.expect(alloc, year).toBe(@as(u16, 2020));

            ztf.jest.useRealTimers(alloc);
        }
    }.testSuite);

    const registry = ztf.getRegistry(allocator);
    _ = try ztf.runTests(allocator, registry);
    ztf.cleanupRegistry();
}
```

### Jest API Methods

All Jest-compatible methods are available under the `ztf.jest` namespace:

- `jest.setSystemTime(allocator, timestamp)`
- `jest.useFakeTimers(allocator)`
- `jest.useRealTimers(allocator)`
- `jest.now(allocator)` - Get current mocked time
- `jest.advanceTimersByTime(allocator, ms)`
- `jest.clearAllTimers(allocator)` - No-op (timers not yet implemented)
- `jest.runAllTimers(allocator)` - No-op (timers not yet implemented)
- `jest.runOnlyPendingTimers(allocator)` - No-op (timers not yet implemented)

> **Note:** Timer mocking (setTimeout, setInterval) is not yet implemented, but these functions are provided for API compatibility.

## Advancing Time

### Manual Time Advancement

```zig
fn testTimeAdvancement(alloc: std.mem.Allocator) !void {
    // Start at a specific time
    ztf.setSystemTime(alloc, 1577836800000); // Jan 1, 2020, 00:00:00

    // Advance 5 seconds
    ztf.advanceTimersByTime(alloc, 5000);
    const time1 = ztf.time.now(alloc);
    try ztf.expect(alloc, time1).toBe(@as(i64, 1577836805000));

    // Advance 1 minute
    ztf.advanceTimersByTime(alloc, 60000);
    const time2 = ztf.time.now(alloc);
    try ztf.expect(alloc, time2).toBe(@as(i64, 1577836865000));

    // Reset
    ztf.setSystemTime(alloc, null);
}
```

### Time Freezing

When you set a specific time, it remains frozen until you explicitly advance it:

```zig
fn testFrozenTime(alloc: std.mem.Allocator) !void {
    ztf.setSystemTime(alloc, 1577836800000);

    const t1 = ztf.time.now(alloc);
    std.Thread.sleep(100 * std.time.ns_per_ms); // Sleep 100ms
    const t2 = ztf.time.now(alloc);

    // Time hasn't advanced despite real time passing
    try ztf.expect(alloc, t1).toBe(t2);

    ztf.setSystemTime(alloc, null);
}
```

## Date Helpers

### DateHelper API

The `DateHelper` provides utilities for working with dates:

```zig
const helper = ztf.createDateHelper(allocator);
```

#### fromISO

Parse an ISO 8601 date string:

```zig
pub fn fromISO(iso_string: []const u8) !i64
```

**Example:**
```zig
const timestamp = try ztf.DateHelper.fromISO("2020-01-01T00:00:00.000Z");
// Returns: 1577836800000 (approximately)
```

**Supported formats:**
- `"2020-01-01T00:00:00.000Z"` - Full ISO 8601 with milliseconds
- `"2020-01-01T12:30:45.123Z"` - Any time of day
- `"2020-06-15T10:20:30.000Z"` - Any date

#### getYear

Extract the year from a timestamp:

```zig
pub fn getYear(timestamp: i64) u16
```

**Example:**
```zig
const timestamp: i64 = 1577836800000; // 2020-01-01
const year = ztf.DateHelper.getYear(timestamp);
// Returns: 2020
```

#### now

Get current time (respects mocked time):

```zig
pub fn now(self: DateHelper) i64
```

**Example:**
```zig
const helper = ztf.createDateHelper(alloc);
ztf.setSystemTime(alloc, 1577836800000);
const current = helper.now();
// Returns: 1577836800000
```

## Best Practices

### 1. Always Clean Up

Always reset time mocking after tests:

```zig
// Good: Use afterAll to clean up
try ztf.afterAll(alloc, cleanupTime);

fn cleanupTime(alloc: std.mem.Allocator) !void {
    ztf.setSystemTime(alloc, null);
}

// Also good: Clean up at the end
defer ztf.cleanupTimeMock();
```

### 2. Use beforeAll for Setup

Set up time mocking in `beforeAll` hooks:

```zig
try ztf.beforeAll(alloc, setupTime);

fn setupTime(alloc: std.mem.Allocator) !void {
    ztf.setSystemTime(alloc, 1577836800000);
}
```

### 3. Test Time-Dependent Logic

```zig
// Good: Test expiration logic
fn testTokenExpiration(alloc: std.mem.Allocator) !void {
    // Set to token creation time
    ztf.setSystemTime(alloc, 1577836800000);
    const token = createToken(alloc);

    // Advance 1 hour
    ztf.advanceTimersByTime(alloc, 3600000);
    try ztf.expect(alloc, isTokenExpired(token)).toBe(true);

    ztf.setSystemTime(alloc, null);
}
```

### 4. Avoid Real Time Dependencies

```zig
// Bad: Depends on real system time
const now = std.time.milliTimestamp();

// Good: Use framework's time
const now = ztf.time.now(alloc);
```

### 5. Use Meaningful Timestamps

```zig
// Good: Use constants with clear meaning
const JAN_1_2020: i64 = 1577836800000;
const JAN_1_2021: i64 = 1609459200000;

ztf.setSystemTime(alloc, JAN_1_2020);
```

### 6. Test Year Transitions

```zig
fn testYearBoundary(alloc: std.mem.Allocator) !void {
    // Dec 31, 2019, 23:59:59
    ztf.setSystemTime(alloc, 1577836799000);
    const year_before = ztf.DateHelper.getYear(ztf.time.now(alloc));
    try ztf.expect(alloc, year_before).toBe(@as(u16, 2019));

    // Advance 1 second to Jan 1, 2020
    ztf.advanceTimersByTime(alloc, 1000);
    const year_after = ztf.DateHelper.getYear(ztf.time.now(alloc));
    try ztf.expect(alloc, year_after).toBe(@as(u16, 2020));

    ztf.setSystemTime(alloc, null);
}
```

## Examples

### Example 1: Testing Time-Based Features

```zig
fn testSessionTimeout(alloc: std.mem.Allocator) !void {
    const Session = struct {
        created_at: i64,
        timeout_ms: i64 = 3600000, // 1 hour

        pub fn isExpired(self: @This(), current_time: i64) bool {
            return (current_time - self.created_at) > self.timeout_ms;
        }
    };

    // Create session at Jan 1, 2020, 00:00:00
    ztf.setSystemTime(alloc, 1577836800000);
    const session = Session{ .created_at = ztf.time.now(alloc) };

    // Check it's not expired yet
    try ztf.expect(alloc, session.isExpired(ztf.time.now(alloc))).toBe(false);

    // Advance 30 minutes
    ztf.advanceTimersByTime(alloc, 1800000);
    try ztf.expect(alloc, session.isExpired(ztf.time.now(alloc))).toBe(false);

    // Advance another 31 minutes (total 61 minutes)
    ztf.advanceTimersByTime(alloc, 1860000);
    try ztf.expect(alloc, session.isExpired(ztf.time.now(alloc))).toBe(true);

    ztf.setSystemTime(alloc, null);
}
```

### Example 2: Testing Date Calculations

```zig
fn testAgeCalculation(alloc: std.mem.Allocator) !void {
    const Person = struct {
        birth_year: u16,

        pub fn getAge(self: @This(), current_timestamp: i64) u16 {
            const current_year = ztf.DateHelper.getYear(current_timestamp);
            return current_year - self.birth_year;
        }
    };

    const person = Person{ .birth_year = 1990 };

    // Test in 2020
    ztf.setSystemTime(alloc, 1577836800000); // Jan 1, 2020
    try ztf.expect(alloc, person.getAge(ztf.time.now(alloc))).toBe(@as(u16, 30));

    // Test in 2025
    ztf.setSystemTime(alloc, 1735689600000); // Jan 1, 2025
    try ztf.expect(alloc, person.getAge(ztf.time.now(alloc))).toBe(@as(u16, 35));

    ztf.setSystemTime(alloc, null);
}
```

### Example 3: Testing Cache Expiration

```zig
fn testCacheExpiration(alloc: std.mem.Allocator) !void {
    const Cache = struct {
        value: []const u8,
        cached_at: i64,
        ttl_ms: i64 = 300000, // 5 minutes

        pub fn isValid(self: @This(), current_time: i64) bool {
            return (current_time - self.cached_at) < self.ttl_ms;
        }
    };

    ztf.setSystemTime(alloc, 1577836800000);
    const cache = Cache{
        .value = "cached_data",
        .cached_at = ztf.time.now(alloc),
    };

    // Fresh cache
    try ztf.expect(alloc, cache.isValid(ztf.time.now(alloc))).toBe(true);

    // Advance 4 minutes
    ztf.advanceTimersByTime(alloc, 240000);
    try ztf.expect(alloc, cache.isValid(ztf.time.now(alloc))).toBe(true);

    // Advance 2 more minutes (total 6 minutes)
    ztf.advanceTimersByTime(alloc, 120000);
    try ztf.expect(alloc, cache.isValid(ztf.time.now(alloc))).toBe(false);

    ztf.setSystemTime(alloc, null);
}
```

### Example 4: Testing Scheduling Logic

```zig
fn testDailySchedule(alloc: std.mem.Allocator) !void {
    const Schedule = struct {
        last_run: i64,
        interval_ms: i64 = 86400000, // 24 hours

        pub fn shouldRun(self: @This(), current_time: i64) bool {
            return (current_time - self.last_run) >= self.interval_ms;
        }
    };

    // Start at Jan 1, 2020, 00:00:00
    ztf.setSystemTime(alloc, 1577836800000);
    var schedule = Schedule{ .last_run = ztf.time.now(alloc) };

    // Should not run after 12 hours
    ztf.advanceTimersByTime(alloc, 43200000);
    try ztf.expect(alloc, schedule.shouldRun(ztf.time.now(alloc))).toBe(false);

    // Should run after 24 hours
    ztf.advanceTimersByTime(alloc, 43200000); // Total 24 hours
    try ztf.expect(alloc, schedule.shouldRun(ztf.time.now(alloc))).toBe(true);

    // Update last run
    schedule.last_run = ztf.time.now(alloc);

    // Should not run immediately after
    try ztf.expect(alloc, schedule.shouldRun(ztf.time.now(alloc))).toBe(false);

    ztf.setSystemTime(alloc, null);
}
```

### Example 5: Testing Multiple Time Zones (Conceptual)

```zig
fn testMultipleTimeScenarios(alloc: std.mem.Allocator) !void {
    // Scenario 1: Morning in 2020
    ztf.setSystemTime(alloc, 1577836800000); // Jan 1, 2020, 00:00:00
    var year = ztf.DateHelper.getYear(ztf.time.now(alloc));
    try ztf.expect(alloc, year).toBe(@as(u16, 2020));

    // Scenario 2: Afternoon in 2021
    ztf.setSystemTime(alloc, 1609459200000); // Jan 1, 2021, 00:00:00
    year = ztf.DateHelper.getYear(ztf.time.now(alloc));
    try ztf.expect(alloc, year).toBe(@as(u16, 2021));

    // Scenario 3: Evening in 2023
    ztf.setSystemTime(alloc, 1672531200000); // Jan 1, 2023, 00:00:00
    year = ztf.DateHelper.getYear(ztf.time.now(alloc));
    try ztf.expect(alloc, year).toBe(@as(u16, 2023));

    ztf.setSystemTime(alloc, null);
}
```

### Example 6: Testing with Jest API

```zig
fn testWithJestAPI(alloc: std.mem.Allocator) !void {
    // Use Jest-compatible API
    ztf.jest.useFakeTimers(alloc);
    ztf.jest.setSystemTime(alloc, 1577836800000);

    const year = ztf.DateHelper.getYear(ztf.jest.now(alloc));
    try ztf.expect(alloc, year).toBe(@as(u16, 2020));

    // Advance time
    ztf.jest.advanceTimersByTime(alloc, 86400000); // 1 day
    const new_time = ztf.jest.now(alloc);
    try ztf.expect(alloc, new_time).toBe(@as(i64, 1577923200000));

    // Reset
    ztf.jest.useRealTimers(alloc);
}
```

## Comparison with Bun/Jest

The Zig Test Framework time API is inspired by Bun and Jest:

| Feature | Bun/Jest | Zig Test Framework |
|---------|----------|-------------------|
| Set time | `setSystemTime(date)` | `setSystemTime(alloc, timestamp)` |
| Fake timers | `jest.useFakeTimers()` | `useFakeTimers(alloc)` or `jest.useFakeTimers(alloc)` |
| Real timers | `jest.useRealTimers()` | `useRealTimers(alloc)` or `jest.useRealTimers(alloc)` |
| Get time | `jest.now()` | `time.now(alloc)` or `jest.now(alloc)` |
| Advance time | `jest.advanceTimersByTime(ms)` | `advanceTimersByTime(alloc, ms)` or `jest.advanceTimersByTime(alloc, ms)` |
| Parse dates | `new Date("2020-01-01")` | `DateHelper.fromISO("2020-01-01T00:00:00.000Z")` |
| Get year | `date.getFullYear()` | `DateHelper.getYear(timestamp)` |

## Limitations

### Timers Not Yet Implemented

The framework does not currently mock timers (setTimeout, setInterval). The following functions are no-ops:

- `jest.clearAllTimers()`
- `jest.runAllTimers()`
- `jest.runOnlyPendingTimers()`

These functions are provided for API compatibility but will be fully implemented in a future release.

### Timezone Support

Unlike Bun/Jest, explicit timezone support is not yet implemented. All timestamps are treated as UTC milliseconds since Unix epoch.

## Troubleshooting

### Time Not Freezing

**Problem:** Time advances even with fake timers enabled

**Solution:** Make sure to call `setSystemTime()` with a specific timestamp after enabling fake timers:

```zig
ztf.useFakeTimers(alloc);
ztf.setSystemTime(alloc, 1577836800000); // Now time is frozen
```

### Time Not Resetting Between Tests

**Problem:** Time from previous test affects current test

**Solution:** Always clean up in `afterEach` or `afterAll`:

```zig
try ztf.afterEach(alloc, resetTime);

fn resetTime(alloc: std.mem.Allocator) !void {
    ztf.setSystemTime(alloc, null);
}
```

### Year Calculation Off

**Problem:** `DateHelper.getYear()` returns wrong year

**Solution:** The `DateHelper.getYear()` function uses a simplified calculation. For production code, use a proper date library. The helper is designed for testing purposes only.

### Memory Leaks

**Problem:** Memory leaks when using time mocking

**Solution:** Call `cleanupTimeMock()` at the end of your test suite:

```zig
defer ztf.cleanupTimeMock();
```

## Conclusion

The Zig Test Framework provides comprehensive time mocking capabilities for testing time-dependent logic:

- **Simple API**: `setSystemTime()`, `useFakeTimers()`, `useRealTimers()`
- **Jest Compatible**: Full `jest.*` namespace for familiar API
- **Time Advancement**: `advanceTimersByTime()` for testing over time
- **Date Helpers**: Parse ISO dates and extract year information
- **Flexible**: Works with hooks, nested describes, and all test patterns

Use time mocking to make your tests deterministic, fast, and reliable!
