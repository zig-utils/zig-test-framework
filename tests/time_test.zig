const std = @import("std");
const ztf = @import("zig-test-framework");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test 1: Basic Time Mocking
    try ztf.describe(allocator, "Basic Time Mocking", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should set and get mocked time", testSetSystemTime);
            try ztf.it(alloc, "should reset to real time", testResetTime);
            try ztf.it(alloc, "should use fake timers", testUseFakeTimers);
        }

        fn testSetSystemTime(alloc: std.mem.Allocator) !void {
            // Set to Jan 1, 2020
            const test_time: i64 = 1577836800000; // 2020-01-01T00:00:00.000Z
            ztf.setSystemTime(alloc, test_time);

            const current = ztf.time.now(alloc);
            try ztf.expect(alloc, current).toBe(test_time);

            // Clean up
            ztf.setSystemTime(alloc, null);
        }

        fn testResetTime(alloc: std.mem.Allocator) !void {
            // Set mocked time
            const test_time: i64 = 1577836800000;
            ztf.setSystemTime(alloc, test_time);
            try ztf.expect(alloc, ztf.time.now(alloc)).toBe(test_time);

            // Reset to real time
            ztf.setSystemTime(alloc, null);
            const real_time = ztf.time.now(alloc);

            // Real time should be much greater than 2020
            try ztf.expect(alloc, real_time).toBeGreaterThan(test_time);
        }

        fn testUseFakeTimers(alloc: std.mem.Allocator) !void {
            ztf.useFakeTimers(alloc);
            ztf.setSystemTime(alloc, 1577836800000);

            const before = ztf.time.now(alloc);
            std.Thread.sleep(100 * std.time.ns_per_ms); // Sleep 100ms
            const after = ztf.time.now(alloc);

            // Time shouldn't advance when using fake timers with a set time
            try ztf.expect(alloc, after).toBe(before);

            // Clean up
            ztf.useRealTimers(alloc);
        }
    }.testSuite);

    // Test 2: Jest-Compatible API
    try ztf.describe(allocator, "Jest-Compatible API", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should work with jest.setSystemTime", testJestSetSystemTime);
            try ztf.it(alloc, "should work with jest.useFakeTimers", testJestFakeTimers);
            try ztf.it(alloc, "should get time with jest.now()", testJestNow);
        }

        fn testJestSetSystemTime(alloc: std.mem.Allocator) !void {
            const test_time: i64 = 1577836800000; // 2020-01-01
            ztf.jest.setSystemTime(alloc, test_time);

            try ztf.expect(alloc, ztf.jest.now(alloc)).toBe(test_time);

            // Clean up
            ztf.jest.useRealTimers(alloc);
        }

        fn testJestFakeTimers(alloc: std.mem.Allocator) !void {
            ztf.jest.useFakeTimers(alloc);
            ztf.jest.setSystemTime(alloc, 1577836800000);

            try ztf.expect(alloc, ztf.jest.now(alloc)).toBe(@as(i64, 1577836800000));

            ztf.jest.useRealTimers(alloc);
        }

        fn testJestNow(alloc: std.mem.Allocator) !void {
            const test_time: i64 = 1609459200000; // 2021-01-01
            ztf.jest.setSystemTime(alloc, test_time);

            const now1 = ztf.jest.now(alloc);
            const now2 = ztf.time.now(alloc);

            try ztf.expect(alloc, now1).toBe(test_time);
            try ztf.expect(alloc, now2).toBe(test_time);
            try ztf.expect(alloc, now1).toBe(now2);

            // Clean up
            ztf.jest.useRealTimers(alloc);
        }
    }.testSuite);

    // Test 3: Advancing Time
    try ztf.describe(allocator, "Advancing Time", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should advance time by milliseconds", testAdvanceTime);
            try ztf.it(alloc, "should advance multiple times", testMultipleAdvances);
        }

        fn testAdvanceTime(alloc: std.mem.Allocator) !void {
            const start_time: i64 = 1577836800000;
            ztf.setSystemTime(alloc, start_time);

            const before = ztf.time.now(alloc);
            ztf.advanceTimersByTime(alloc, 5000); // Advance 5 seconds
            const after = ztf.time.now(alloc);

            try ztf.expect(alloc, after).toBe(before + 5000);

            // Clean up
            ztf.setSystemTime(alloc, null);
        }

        fn testMultipleAdvances(alloc: std.mem.Allocator) !void {
            const start_time: i64 = 1577836800000;
            ztf.jest.setSystemTime(alloc, start_time);

            ztf.jest.advanceTimersByTime(alloc, 1000);
            try ztf.expect(alloc, ztf.jest.now(alloc)).toBe(start_time + 1000);

            ztf.jest.advanceTimersByTime(alloc, 2000);
            try ztf.expect(alloc, ztf.jest.now(alloc)).toBe(start_time + 3000);

            ztf.jest.advanceTimersByTime(alloc, 7000);
            try ztf.expect(alloc, ztf.jest.now(alloc)).toBe(start_time + 10000);

            // Clean up
            ztf.jest.useRealTimers(alloc);
        }
    }.testSuite);

    // Test 4: DateHelper Functionality
    try ztf.describe(allocator, "DateHelper", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should parse ISO 8601 strings", testISOParsing);
            try ztf.it(alloc, "should extract year from timestamp", testYearExtraction);
            try ztf.it(alloc, "should respect mocked time", testDateHelperWithMock);
        }

        fn testISOParsing(alloc: std.mem.Allocator) !void {
            // Parse a date string
            const timestamp = try ztf.DateHelper.fromISO("2020-01-01T00:00:00.000Z");

            // Verify we get a reasonable 2020 timestamp
            // 2020-01-01 should be around 1577836800000
            // Allow for calculation variance
            const year = ztf.DateHelper.getYear(timestamp);
            try ztf.expect(alloc, year).toBe(@as(u16, 2020));
        }

        fn testYearExtraction(alloc: std.mem.Allocator) !void {
            const timestamp_2020: i64 = 1577836800000; // 2020-01-01
            const year_2020 = ztf.DateHelper.getYear(timestamp_2020);
            try ztf.expect(alloc, year_2020).toBe(@as(u16, 2020));

            const timestamp_2021: i64 = 1609459200000; // 2021-01-01
            const year_2021 = ztf.DateHelper.getYear(timestamp_2021);
            try ztf.expect(alloc, year_2021).toBe(@as(u16, 2021));

            const timestamp_2025: i64 = 1735689600000; // 2025-01-01
            const year_2025 = ztf.DateHelper.getYear(timestamp_2025);
            try ztf.expect(alloc, year_2025).toBe(@as(u16, 2025));
        }

        fn testDateHelperWithMock(alloc: std.mem.Allocator) !void {
            const helper = ztf.createDateHelper(alloc);

            // Set mocked time
            ztf.setSystemTime(alloc, 1577836800000);

            // DateHelper should respect mocked time
            try ztf.expect(alloc, helper.now()).toBe(@as(i64, 1577836800000));

            // Clean up
            ztf.setSystemTime(alloc, null);
        }
    }.testSuite);

    // Test 5: Multiple Date Scenarios
    try ztf.describe(allocator, "Multiple Date Scenarios", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should handle different years", testDifferentYears);
            try ztf.it(alloc, "should handle year transitions", testYearTransitions);
        }

        fn testDifferentYears(alloc: std.mem.Allocator) !void {
            // Test 2020
            ztf.setSystemTime(alloc, 1577836800000);
            const year_2020 = ztf.DateHelper.getYear(ztf.time.now(alloc));
            try ztf.expect(alloc, year_2020).toBe(@as(u16, 2020));

            // Test 2023
            ztf.setSystemTime(alloc, 1672531200000);
            const year_2023 = ztf.DateHelper.getYear(ztf.time.now(alloc));
            try ztf.expect(alloc, year_2023).toBe(@as(u16, 2023));

            // Test 2025
            ztf.setSystemTime(alloc, 1735689600000);
            const year_2025 = ztf.DateHelper.getYear(ztf.time.now(alloc));
            try ztf.expect(alloc, year_2025).toBe(@as(u16, 2025));

            // Clean up
            ztf.setSystemTime(alloc, null);
        }

        fn testYearTransitions(alloc: std.mem.Allocator) !void {
            // Dec 31, 2019, 23:59:59
            const end_2019: i64 = 1577836799000;
            ztf.setSystemTime(alloc, end_2019);
            try ztf.expect(alloc, ztf.DateHelper.getYear(ztf.time.now(alloc))).toBe(@as(u16, 2019));

            // Advance 1 second to Jan 1, 2020
            ztf.advanceTimersByTime(alloc, 1000);
            try ztf.expect(alloc, ztf.DateHelper.getYear(ztf.time.now(alloc))).toBe(@as(u16, 2020));

            // Clean up
            ztf.setSystemTime(alloc, null);
        }
    }.testSuite);

    // Test 6: Real vs Fake Time
    try ztf.describe(allocator, "Real vs Fake Time", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should distinguish between real and fake time", testRealVsFake);
            try ztf.it(alloc, "should transition between modes", testModeTransitions);
        }

        fn testRealVsFake(alloc: std.mem.Allocator) !void {
            // Switch to fake time
            ztf.useFakeTimers(alloc);
            ztf.setSystemTime(alloc, 1577836800000);
            try ztf.expect(alloc, ztf.time.now(alloc)).toBe(@as(i64, 1577836800000));

            // Back to real time
            ztf.useRealTimers(alloc);
            const real_time2 = ztf.time.now(alloc);
            try ztf.expect(alloc, real_time2).toBeGreaterThan(@as(i64, 1577836800000));
        }

        fn testModeTransitions(alloc: std.mem.Allocator) !void {
            // Fake time
            ztf.useFakeTimers(alloc);
            ztf.setSystemTime(alloc, 1000000000000);
            const t2 = ztf.time.now(alloc);
            try ztf.expect(alloc, t2).toBe(@as(i64, 1000000000000));

            // Real time
            ztf.useRealTimers(alloc);
            const t3 = ztf.time.now(alloc);
            try ztf.expect(alloc, t3).toBeGreaterThan(@as(i64, 1000000000000));
        }
    }.testSuite);

    // Test 7: ISO Date Parsing Edge Cases
    try ztf.describe(allocator, "ISO Date Parsing", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should parse dates with time", testFullISO);
            try ztf.it(alloc, "should parse dates with milliseconds", testISOWithMillis);
        }

        fn testFullISO(alloc: std.mem.Allocator) !void {
            const ts1 = try ztf.DateHelper.fromISO("2020-01-01T00:00:00.000Z");
            const ts2 = try ztf.DateHelper.fromISO("2020-06-15T12:30:45.123Z");

            // Verify year extraction works
            const year1 = ztf.DateHelper.getYear(ts1);
            const year2 = ztf.DateHelper.getYear(ts2);
            try ztf.expect(alloc, year1).toBe(@as(u16, 2020));
            try ztf.expect(alloc, year2).toBe(@as(u16, 2020));

            // ts2 should be later than ts1 (both are 2020, but ts2 is mid-year)
            try ztf.expect(alloc, ts2).toBeGreaterThan(ts1);
        }

        fn testISOWithMillis(alloc: std.mem.Allocator) !void {
            const ts1 = try ztf.DateHelper.fromISO("2021-03-15T10:20:30.000Z");
            const ts2 = try ztf.DateHelper.fromISO("2021-03-15T10:20:30.999Z");

            // Should differ by ~999 milliseconds
            const diff = ts2 - ts1;
            try ztf.expect(alloc, diff).toBe(@as(i64, 999));
        }
    }.testSuite);

    // Test 8: Time Freezing
    try ztf.describe(allocator, "Time Freezing", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should freeze time when using fake timers", testTimeFreezing);
        }

        fn testTimeFreezing(alloc: std.mem.Allocator) !void {
            const frozen_time: i64 = 1577836800000;
            ztf.setSystemTime(alloc, frozen_time);

            const t1 = ztf.time.now(alloc);
            std.Thread.sleep(50 * std.time.ns_per_ms); // Sleep 50ms
            const t2 = ztf.time.now(alloc);
            std.Thread.sleep(50 * std.time.ns_per_ms); // Sleep another 50ms
            const t3 = ztf.time.now(alloc);

            // Time should remain frozen
            try ztf.expect(alloc, t1).toBe(frozen_time);
            try ztf.expect(alloc, t2).toBe(frozen_time);
            try ztf.expect(alloc, t3).toBe(frozen_time);
            try ztf.expect(alloc, t1).toBe(t2);
            try ztf.expect(alloc, t2).toBe(t3);

            // Clean up
            ztf.setSystemTime(alloc, null);
        }
    }.testSuite);

    // Test 9: Time Mocking in beforeAll/afterAll
    try ztf.describe(allocator, "Time Mocking in Hooks", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.beforeAll(alloc, beforeAllHook);
            try ztf.afterAll(alloc, afterAllHook);

            try ztf.it(alloc, "should have mocked time from beforeAll", testWithMockedTime);
        }

        fn beforeAllHook(alloc: std.mem.Allocator) !void {
            ztf.setSystemTime(alloc, 1577836800000); // 2020-01-01
        }

        fn afterAllHook(alloc: std.mem.Allocator) !void {
            ztf.setSystemTime(alloc, null); // Reset
        }

        fn testWithMockedTime(alloc: std.mem.Allocator) !void {
            const year = ztf.DateHelper.getYear(ztf.time.now(alloc));
            try ztf.expect(alloc, year).toBe(@as(u16, 2020));
        }
    }.testSuite);

    // Test 10: Complex Time Scenarios
    try ztf.describe(allocator, "Complex Time Scenarios", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should handle multiple time changes", testMultipleChanges);
            try ztf.it(alloc, "should handle large time jumps", testLargeJumps);
        }

        fn testMultipleChanges(alloc: std.mem.Allocator) !void {
            // Set to 2020
            ztf.setSystemTime(alloc, 1577836800000);
            try ztf.expect(alloc, ztf.DateHelper.getYear(ztf.time.now(alloc))).toBe(@as(u16, 2020));

            // Jump to 2021
            ztf.setSystemTime(alloc, 1609459200000);
            try ztf.expect(alloc, ztf.DateHelper.getYear(ztf.time.now(alloc))).toBe(@as(u16, 2021));

            // Jump to 2023
            ztf.setSystemTime(alloc, 1672531200000);
            try ztf.expect(alloc, ztf.DateHelper.getYear(ztf.time.now(alloc))).toBe(@as(u16, 2023));

            // Reset
            ztf.setSystemTime(alloc, null);
        }

        fn testLargeJumps(alloc: std.mem.Allocator) !void {
            // Start at 2020
            ztf.setSystemTime(alloc, 1577836800000);

            // Jump forward 10 years worth of milliseconds
            const ten_years_ms: i64 = 10 * 365 * 24 * 60 * 60 * 1000;
            ztf.advanceTimersByTime(alloc, ten_years_ms);

            const new_time = ztf.time.now(alloc);
            try ztf.expect(alloc, new_time).toBe(1577836800000 + ten_years_ms);

            // Clean up
            ztf.setSystemTime(alloc, null);
        }
    }.testSuite);

    // Run all tests
    const registry = ztf.getRegistry(allocator);
    const success = try ztf.runTestsWithOptions(allocator, registry, .{
        .reporter_type = .spec,
        .use_colors = false,
    });

    // Clean up
    ztf.cleanupRegistry();
    ztf.cleanupTimeMock();

    if (!success) {
        std.debug.print("\nSome time tests failed!\n", .{});
        std.process.exit(1);
    }

    std.debug.print("\n✓ All time manipulation tests passed!\n", .{});
}
