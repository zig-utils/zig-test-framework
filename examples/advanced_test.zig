const std = @import("std");
const ztf = @import("zig-test-framework");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Example 1: Using hooks (beforeEach, afterEach, beforeAll, afterAll)
    try ztf.describe(allocator, "Database operations", struct {
        var connection_count: i32 = 0;
        var query_count: i32 = 0;

        fn testSuite(alloc: std.mem.Allocator) !void {
            // Runs once before all tests in this suite
            try ztf.beforeAll(alloc, setupDatabase);

            // Runs before each test
            try ztf.beforeEach(alloc, openConnection);

            // Runs after each test
            try ztf.afterEach(alloc, closeConnection);

            // Runs once after all tests in this suite
            try ztf.afterAll(alloc, teardownDatabase);

            try ztf.it(alloc, "should query data", testQuery);
            try ztf.it(alloc, "should insert data", testInsert);
            try ztf.it(alloc, "should update data", testUpdate);
        }

        fn setupDatabase(alloc: std.mem.Allocator) !void {
            _ = alloc;
            std.debug.print("  [Setup] Initializing database...\n", .{});
        }

        fn teardownDatabase(alloc: std.mem.Allocator) !void {
            _ = alloc;
            std.debug.print("  [Teardown] Cleaning up database...\n", .{});
        }

        fn openConnection(alloc: std.mem.Allocator) !void {
            _ = alloc;
            connection_count += 1;
        }

        fn closeConnection(alloc: std.mem.Allocator) !void {
            _ = alloc;
            connection_count -= 1;
        }

        fn testQuery(alloc: std.mem.Allocator) !void {
            query_count += 1;
            try ztf.expect(alloc, connection_count).toBe(1);
        }

        fn testInsert(alloc: std.mem.Allocator) !void {
            query_count += 1;
            try ztf.expect(alloc, connection_count).toBe(1);
        }

        fn testUpdate(alloc: std.mem.Allocator) !void {
            query_count += 1;
            try ztf.expect(alloc, connection_count).toBe(1);
        }
    }.testSuite);

    // Example 2: Nested describe blocks
    try ztf.describe(allocator, "User Service", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.describe(alloc, "User creation", struct {
                fn nestedSuite(nested_alloc: std.mem.Allocator) !void {
                    try ztf.it(nested_alloc, "should create a user with valid data", testValidUser);
                    try ztf.it(nested_alloc, "should reject invalid email", testInvalidEmail);
                }

                fn testValidUser(nested_alloc: std.mem.Allocator) !void {
                    const email = "user@example.com";
                    try ztf.expect(nested_alloc, email).toContain("@");
                }

                fn testInvalidEmail(nested_alloc: std.mem.Allocator) !void {
                    const email = "invalid-email";
                    try ztf.expect(nested_alloc, email).not().toContain("@");
                }
            }.nestedSuite);

            try ztf.describe(alloc, "User authentication", struct {
                fn nestedSuite(nested_alloc: std.mem.Allocator) !void {
                    try ztf.it(nested_alloc, "should authenticate with correct password", testValidAuth);
                    try ztf.it(nested_alloc, "should reject wrong password", testInvalidAuth);
                }

                fn testValidAuth(nested_alloc: std.mem.Allocator) !void {
                    const password = "correct_password";
                    const hash = "correct_password"; // Simplified
                    try ztf.expect(nested_alloc, password).toBe(hash);
                }

                fn testInvalidAuth(nested_alloc: std.mem.Allocator) !void {
                    const password = "wrong_password";
                    const hash = "correct_password";
                    try ztf.expect(nested_alloc, password).not().toBe(hash);
                }
            }.nestedSuite);
        }
    }.testSuite);

    // Example 3: Advanced matchers
    try ztf.describe(allocator, "Advanced matchers", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should use toBeCloseTo for floats", testFloatComparison);
            try ztf.it(alloc, "should check NaN values", testNaN);
            try ztf.it(alloc, "should work with arrays", testArrays);
            try ztf.it(alloc, "should work with structs", testStructs);
        }

        fn testFloatComparison(alloc: std.mem.Allocator) !void {
            _ = alloc;
            const result = 0.1 + 0.2;
            try ztf.toBeCloseTo(result, 0.3, 10);
        }

        fn testNaN(alloc: std.mem.Allocator) !void {
            _ = alloc;
            const nan_value = std.math.nan(f64);
            try ztf.toBeNaN(nan_value);
        }

        fn testArrays(alloc: std.mem.Allocator) !void {
            const numbers = [_]i32{ 1, 2, 3, 4, 5 };
            const matcher = ztf.expectArray(alloc, &numbers);

            try matcher.toHaveLength(5);
            try matcher.toContainEqual(3);
            try matcher.toContainAll(&[_]i32{ 1, 3, 5 });
        }

        fn testStructs(alloc: std.mem.Allocator) !void {
            const User = struct {
                name: []const u8,
                age: u32,
            };

            const user = User{
                .name = "Alice",
                .age = 30,
            };

            const matcher = ztf.expectStruct(alloc, user);
            try matcher.toHaveField("name", "Alice");
            try matcher.toHaveField("age", @as(u32, 30));
        }
    }.testSuite);

    // Example 4: Mocking
    try ztf.describe(allocator, "Mocking and Spies", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should track function calls", testMockCalls);
            try ztf.it(alloc, "should mock return values", testMockReturnValues);
        }

        fn testMockCalls(alloc: std.mem.Allocator) !void {
            var mock_fn = ztf.createMock(alloc, i32);
            defer mock_fn.deinit();

            try mock_fn.recordCall("arg1");
            try mock_fn.recordCall("arg2");
            try mock_fn.recordCall("arg3");

            try mock_fn.toHaveBeenCalled();
            try mock_fn.toHaveBeenCalledTimes(3);
            try mock_fn.toHaveBeenCalledWith("arg2");
            try mock_fn.toHaveBeenLastCalledWith("arg3");
        }

        fn testMockReturnValues(alloc: std.mem.Allocator) !void {
            var mock_fn = ztf.createMock(alloc, i32);
            defer mock_fn.deinit();

            try mock_fn.mockReturnValue(42);
            const value = mock_fn.getReturnValue();

            try ztf.expect(alloc, value).toBe(@as(?i32, 42));
        }
    }.testSuite);

    // Example 5: Test filtering with .skip() and .only()
    try ztf.describe(allocator, "Test filtering", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should run this test", testNormal);
            try ztf.itSkip(alloc, "should skip this test", testSkipped);
            // Uncomment to run only specific test:
            // try ztf.itOnly(alloc, "should run only this test", testOnly);
        }

        fn testNormal(alloc: std.mem.Allocator) !void {
            try ztf.expect(alloc, true).toBeTruthy();
        }

        fn testSkipped(alloc: std.mem.Allocator) !void {
            // This test will be skipped
            try ztf.expect(alloc, false).toBeTruthy();
        }

        fn testOnly(alloc: std.mem.Allocator) !void {
            try ztf.expect(alloc, true).toBeTruthy();
        }
    }.testSuite);

    // Example 6: Slice operations
    try ztf.describe(allocator, "Slice operations", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should work with slices", testSlices);
        }

        fn testSlices(alloc: std.mem.Allocator) !void {
            const items = [_]i32{ 10, 20, 30, 40, 50 };
            const slice_matcher = ztf.expectArray(alloc, items[1..4]);

            try slice_matcher.toHaveLength(3);
            try slice_matcher.toContain(20);
            try slice_matcher.toContain(30);
        }
    }.testSuite);

    // Example 7: Error assertions
    try ztf.describe(allocator, "Error handling", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should handle errors correctly", testErrorAssertions);
        }

        fn testErrorAssertions(alloc: std.mem.Allocator) !void {
            // Note: Error assertions work best with error unions directly
            // For now, we'll demonstrate with a simple example

            // This would throw an error
            const will_fail: anyerror!void = error.SomethingWentWrong;

            // Check that it's an error
            const is_error = if (will_fail) |_| false else |_| true;
            try ztf.expect(alloc, is_error).toBe(true);

            // This would succeed
            const will_succeed: anyerror!void = {};
            const is_ok = if (will_succeed) |_| true else |_| false;
            try ztf.expect(alloc, is_ok).toBe(true);

            // Note: Full toThrow() support requires function pointers
            // which have some limitations in current implementation.
            // This is a known limitation and can be enhanced in future versions.
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
