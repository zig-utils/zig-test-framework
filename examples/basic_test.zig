const std = @import("std");
const ztf = @import("zig-test-framework");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Example 1: Basic describe/it structure
    try ztf.describe(allocator, "Math operations", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should add two numbers correctly", testAddition);
            try ztf.it(alloc, "should subtract two numbers correctly", testSubtraction);
            try ztf.it(alloc, "should multiply two numbers correctly", testMultiplication);
            try ztf.it(alloc, "should divide two numbers correctly", testDivision);
        }

        fn testAddition(alloc: std.mem.Allocator) !void {
            const result: i32 = 2 + 2;
            try ztf.expect(alloc, result).toBe(@as(i32, 4));
        }

        fn testSubtraction(alloc: std.mem.Allocator) !void {
            const result: i32 = 10 - 5;
            try ztf.expect(alloc, result).toBe(@as(i32, 5));
        }

        fn testMultiplication(alloc: std.mem.Allocator) !void {
            const result: i32 = 3 * 4;
            try ztf.expect(alloc, result).toBe(@as(i32, 12));
        }

        fn testDivision(alloc: std.mem.Allocator) !void {
            const result: i32 = 20 / 4;
            try ztf.expect(alloc, result).toBe(@as(i32, 5));
        }
    }.testSuite);

    // Example 2: String assertions
    try ztf.describe(allocator, "String operations", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should compare strings", testStringEquality);
            try ztf.it(alloc, "should check if string contains substring", testStringContains);
            try ztf.it(alloc, "should check string length", testStringLength);
        }

        fn testStringEquality(alloc: std.mem.Allocator) !void {
            const message = "Hello, World!";
            try ztf.expect(alloc, message).toBe("Hello, World!");
        }

        fn testStringContains(alloc: std.mem.Allocator) !void {
            const message = "The quick brown fox";
            try ztf.expect(alloc, message).toContain("quick");
            try ztf.expect(alloc, message).toStartWith("The");
            try ztf.expect(alloc, message).toEndWith("fox");
        }

        fn testStringLength(alloc: std.mem.Allocator) !void {
            const message = "Hello";
            try ztf.expect(alloc, message).toHaveLength(5);
        }
    }.testSuite);

    // Example 3: Comparison assertions
    try ztf.describe(allocator, "Comparisons", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should compare numbers", testComparisons);
        }

        fn testComparisons(alloc: std.mem.Allocator) !void {
            try ztf.expect(alloc, @as(i32, 10)).toBeGreaterThan(@as(i32, 5));
            try ztf.expect(alloc, @as(i32, 10)).toBeGreaterThanOrEqual(@as(i32, 10));
            try ztf.expect(alloc, @as(i32, 5)).toBeLessThan(@as(i32, 10));
            try ztf.expect(alloc, @as(i32, 5)).toBeLessThanOrEqual(@as(i32, 5));
        }
    }.testSuite);

    // Example 4: Boolean assertions
    try ztf.describe(allocator, "Boolean tests", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should handle booleans", testBooleans);
        }

        fn testBooleans(alloc: std.mem.Allocator) !void {
            try ztf.expect(alloc, true).toBeTruthy();
            try ztf.expect(alloc, false).toBeFalsy();
            try ztf.expect(alloc, true).not().toBeFalsy();
        }
    }.testSuite);

    // Example 5: Optional (nullable) values
    try ztf.describe(allocator, "Optional values", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should handle null values", testNull);
            try ztf.it(alloc, "should handle defined values", testDefined);
        }

        fn testNull(alloc: std.mem.Allocator) !void {
            const value: ?i32 = null;
            try ztf.expect(alloc, value).toBeNull();
        }

        fn testDefined(alloc: std.mem.Allocator) !void {
            const value: ?i32 = 42;
            try ztf.expect(alloc, value).toBeDefined();
            try ztf.expect(alloc, value).not().toBeNull();
        }
    }.testSuite);

    // Example 6: Negation with .not()
    try ztf.describe(allocator, "Negation tests", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should support .not() modifier", testNegation);
        }

        fn testNegation(alloc: std.mem.Allocator) !void {
            try ztf.expect(alloc, @as(i32, 5)).not().toBe(@as(i32, 10));
            try ztf.expect(alloc, "hello").not().toBe("world");
            try ztf.expect(alloc, true).not().toBe(false);
        }
    }.testSuite);

    // Run all tests
    const registry = ztf.getRegistry(allocator);
    const success = try ztf.runTests(allocator, registry);

    // Clean up the registry
    ztf.cleanupRegistry();

    if (!success) {
        std.process.exit(1);
    }
}
