const std = @import("std");
const ztf = @import("zig-test-framework");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test 1: Basic Mock Function Usage
    try ztf.describe(allocator, "Basic Mock Functions", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should track function calls", testBasicCallTracking);
            try ztf.it(alloc, "should work with toHaveBeenCalled", testToHaveBeenCalled);
            try ztf.it(alloc, "should work with toHaveBeenCalledTimes", testCallTimes);
        }

        fn testBasicCallTracking(alloc: std.mem.Allocator) !void {
            var mock_fn = ztf.createMock(alloc, i32);
            defer mock_fn.deinit();

            try mock_fn.recordCall("first_call");
            try mock_fn.recordCall("second_call");

            const calls = mock_fn.getCalls();
            try ztf.expect(alloc, calls.len).toBe(@as(usize, 2));
        }

        fn testToHaveBeenCalled(alloc: std.mem.Allocator) !void {
            var mock_fn = ztf.createMock(alloc, i32);
            defer mock_fn.deinit();

            try mock_fn.recordCall("test");
            try mock_fn.toHaveBeenCalled();
        }

        fn testCallTimes(alloc: std.mem.Allocator) !void {
            var mock_fn = ztf.createMock(alloc, i32);
            defer mock_fn.deinit();

            try mock_fn.recordCall("call1");
            try mock_fn.recordCall("call2");
            try mock_fn.recordCall("call3");

            try mock_fn.toHaveBeenCalledTimes(3);
        }
    }.testSuite);

    // Test 2: Mock Return Values
    try ztf.describe(allocator, "Mock Return Values", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should return mocked values", testReturnValue);
            try ztf.it(alloc, "should return once values then repeat", testReturnOnce);
            try ztf.it(alloc, "should support multiple return values", testMultipleReturns);
        }

        fn testReturnValue(alloc: std.mem.Allocator) !void {
            var mock_fn = ztf.createMock(alloc, i32);
            defer mock_fn.deinit();

            _ = try mock_fn.mockReturnValue(42);

            const val1 = mock_fn.getReturnValue();
            const val2 = mock_fn.getReturnValue();

            try ztf.expect(alloc, val1).toBe(@as(?i32, 42));
            try ztf.expect(alloc, val2).toBe(@as(?i32, 42));
        }

        fn testReturnOnce(alloc: std.mem.Allocator) !void {
            var mock_fn = ztf.createMock(alloc, i32);
            defer mock_fn.deinit();

            _ = try mock_fn.mockReturnValueOnce(10);
            _ = try mock_fn.mockReturnValueOnce(20);
            _ = try mock_fn.mockReturnValue(30);

            try ztf.expect(alloc, mock_fn.getReturnValue()).toBe(@as(?i32, 10));
            try ztf.expect(alloc, mock_fn.getReturnValue()).toBe(@as(?i32, 20));
            try ztf.expect(alloc, mock_fn.getReturnValue()).toBe(@as(?i32, 30));
            try ztf.expect(alloc, mock_fn.getReturnValue()).toBe(@as(?i32, 30)); // Repeats
        }

        fn testMultipleReturns(alloc: std.mem.Allocator) !void {
            var mock_fn = ztf.createMock(alloc, i32);
            defer mock_fn.deinit();

            const values = [_]i32{ 1, 2, 3 };
            _ = try mock_fn.mockReturnValues(&values);

            try ztf.expect(alloc, mock_fn.getReturnValue()).toBe(@as(?i32, 1));
            try ztf.expect(alloc, mock_fn.getReturnValue()).toBe(@as(?i32, 2));
            try ztf.expect(alloc, mock_fn.getReturnValue()).toBe(@as(?i32, 3));
        }
    }.testSuite);

    // Test 3: Mock Names
    try ztf.describe(allocator, "Mock Names", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should have default name", testDefaultName);
            try ztf.it(alloc, "should allow custom names", testCustomName);
        }

        fn testDefaultName(alloc: std.mem.Allocator) !void {
            var mock_fn = ztf.createMock(alloc, i32);
            defer mock_fn.deinit();

            try ztf.expect(alloc, std.mem.eql(u8, mock_fn.getMockName(), "jest.fn()")).toBe(true);
        }

        fn testCustomName(alloc: std.mem.Allocator) !void {
            var mock_fn = ztf.createMock(alloc, i32);
            defer mock_fn.deinit();

            _ = mock_fn.mockName("myCustomMock");
            try ztf.expect(alloc, std.mem.eql(u8, mock_fn.getMockName(), "myCustomMock")).toBe(true);
        }
    }.testSuite);

    // Test 4: Call Arguments Tracking
    try ztf.describe(allocator, "Call Arguments", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should track call arguments", testCallArguments);
            try ztf.it(alloc, "should verify last call", testLastCall);
            try ztf.it(alloc, "should verify nth call", testNthCall);
        }

        fn testCallArguments(alloc: std.mem.Allocator) !void {
            var mock_fn = ztf.createMock(alloc, i32);
            defer mock_fn.deinit();

            try mock_fn.recordCall("arg1");
            try mock_fn.recordCall("arg2");

            try mock_fn.toHaveBeenCalledWith("arg1");
            try mock_fn.toHaveBeenCalledWith("arg2");
        }

        fn testLastCall(alloc: std.mem.Allocator) !void {
            var mock_fn = ztf.createMock(alloc, i32);
            defer mock_fn.deinit();

            try mock_fn.recordCall("first");
            try mock_fn.recordCall("second");
            try mock_fn.recordCall("last");

            try mock_fn.toHaveBeenLastCalledWith("last");
        }

        fn testNthCall(alloc: std.mem.Allocator) !void {
            var mock_fn = ztf.createMock(alloc, i32);
            defer mock_fn.deinit();

            try mock_fn.recordCall("call1");
            try mock_fn.recordCall("call2");
            try mock_fn.recordCall("call3");

            try mock_fn.toHaveBeenNthCalledWith(1, "call1");
            try mock_fn.toHaveBeenNthCalledWith(2, "call2");
            try mock_fn.toHaveBeenNthCalledWith(3, "call3");
        }
    }.testSuite);

    // Test 5: Mock State Management
    try ztf.describe(allocator, "Mock State Management", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should clear call history", testMockClear);
            try ztf.it(alloc, "should reset mock completely", testMockReset);
        }

        fn testMockClear(alloc: std.mem.Allocator) !void {
            var mock_fn = ztf.createMock(alloc, i32);
            defer mock_fn.deinit();

            try mock_fn.recordCall("call1");
            try mock_fn.recordCall("call2");
            try ztf.expect(alloc, mock_fn.callCount()).toBe(@as(usize, 2));

            _ = mock_fn.mockClear();
            try ztf.expect(alloc, mock_fn.callCount()).toBe(@as(usize, 0));
        }

        fn testMockReset(alloc: std.mem.Allocator) !void {
            var mock_fn = ztf.createMock(alloc, i32);
            defer mock_fn.deinit();

            try mock_fn.recordCall("call");
            _ = try mock_fn.mockReturnValue(42);

            _ = mock_fn.mockReset();

            try ztf.expect(alloc, mock_fn.callCount()).toBe(@as(usize, 0));
            try ztf.expect(alloc, mock_fn.getReturnValue()).toBe(@as(?i32, null));
        }
    }.testSuite);

    // Test 6: Method Chaining
    try ztf.describe(allocator, "Method Chaining", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should support method chaining", testChaining);
        }

        fn testChaining(alloc: std.mem.Allocator) !void {
            var mock_fn = ztf.createMock(alloc, i32);
            defer mock_fn.deinit();

            _ = mock_fn.mockName("chainedMock")
                .mockReturnThis();

            try ztf.expect(alloc, std.mem.eql(u8, mock_fn.getMockName(), "chainedMock")).toBe(true);
        }
    }.testSuite);

    // Test 7: Spy Functionality
    try ztf.describe(allocator, "Spy Functions", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should create spy with original function", testSpyCreation);
            try ztf.it(alloc, "should track spy calls", testSpyCalls);
            try ztf.it(alloc, "should restore original function", testSpyRestore);
        }

        fn testSpyCreation(alloc: std.mem.Allocator) !void {
            const original: i32 = 42;
            var spy = ztf.createSpy(alloc, i32, original);
            defer spy.deinit();

            try ztf.expect(alloc, spy.original_fn).toBe(@as(?i32, 42));
        }

        fn testSpyCalls(alloc: std.mem.Allocator) !void {
            const original: i32 = 100;
            var spy = ztf.createSpy(alloc, i32, original);
            defer spy.deinit();

            try spy.call("test_call");
            try spy.toHaveBeenCalled();
            try spy.toHaveBeenCalledTimes(1);
        }

        fn testSpyRestore(alloc: std.mem.Allocator) !void {
            const original: i32 = 99;
            var spy = ztf.createSpy(alloc, i32, original);
            defer spy.deinit();

            const restored = spy.mockRestore();
            try ztf.expect(alloc, restored).toBe(@as(?i32, 99));
            try ztf.expect(alloc, spy.is_restored).toBe(true);
        }
    }.testSuite);

    // Test 8: Spy with Mocked Implementation
    try ztf.describe(allocator, "Spy with Mock Overrides", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should override spy return value", testSpyReturnValue);
            try ztf.it(alloc, "should clear spy calls", testSpyClear);
        }

        fn testSpyReturnValue(alloc: std.mem.Allocator) !void {
            const original: i32 = 1;
            var spy = ztf.createSpy(alloc, i32, original);
            defer spy.deinit();

            _ = try spy.mockReturnValue(50);
            const value = spy.mock.getReturnValue();

            try ztf.expect(alloc, value).toBe(@as(?i32, 50));
        }

        fn testSpyClear(alloc: std.mem.Allocator) !void {
            const original: i32 = 1;
            var spy = ztf.createSpy(alloc, i32, original);
            defer spy.deinit();

            try spy.call("call1");
            try spy.call("call2");
            try ztf.expect(alloc, spy.callCount()).toBe(@as(usize, 2));

            _ = spy.mockClear();
            try ztf.expect(alloc, spy.callCount()).toBe(@as(usize, 0));
        }
    }.testSuite);

    // Test 9: Async Mock Support
    try ztf.describe(allocator, "Async Mocks", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should mock resolved values", testResolvedValue);
            try ztf.it(alloc, "should mock resolved value once", testResolvedValueOnce);
        }

        fn testResolvedValue(alloc: std.mem.Allocator) !void {
            var mock_fn = ztf.createMock(alloc, i32);
            defer mock_fn.deinit();

            _ = try mock_fn.mockResolvedValue(123);
            const value = mock_fn.getReturnValue();

            try ztf.expect(alloc, value).toBe(@as(?i32, 123));
        }

        fn testResolvedValueOnce(alloc: std.mem.Allocator) !void {
            var mock_fn = ztf.createMock(alloc, i32);
            defer mock_fn.deinit();

            _ = try mock_fn.mockResolvedValueOnce(10);
            _ = try mock_fn.mockResolvedValue(20);

            try ztf.expect(alloc, mock_fn.getReturnValue()).toBe(@as(?i32, 10));
            try ztf.expect(alloc, mock_fn.getReturnValue()).toBe(@as(?i32, 20));
        }
    }.testSuite);

    // Test 10: Complex Usage Pattern
    try ztf.describe(allocator, "Complex Mock Patterns", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should handle service mock pattern", testServiceMock);
        }

        fn testServiceMock(alloc: std.mem.Allocator) !void {
            // Simulate a user service with mocked methods
            var getUserMock = ztf.createMock(alloc, []const u8);
            defer getUserMock.deinit();

            var createUserMock = ztf.createMock(alloc, []const u8);
            defer createUserMock.deinit();

            // Set up mock behavior
            _ = getUserMock.mockName("getUser");
            _ = try getUserMock.mockReturnValue("mock_user_data");

            _ = createUserMock.mockName("createUser");
            _ = try createUserMock.mockReturnValue("new_user_created");

            // Simulate service calls
            try getUserMock.recordCall("user_id_123");
            try createUserMock.recordCall("new_user_data");

            // Verify the mocks were called correctly
            try getUserMock.toHaveBeenCalledWith("user_id_123");
            try createUserMock.toHaveBeenCalledWith("new_user_data");

            // Verify return values
            try ztf.expect(alloc, getUserMock.getReturnValue()).toBe(@as(?[]const u8, "mock_user_data"));
            try ztf.expect(alloc, createUserMock.getReturnValue()).toBe(@as(?[]const u8, "new_user_created"));
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

    if (!success) {
        std.debug.print("\nSome mock tests failed!\n", .{});
        std.process.exit(1);
    }

    std.debug.print("\n✓ All comprehensive mock tests passed!\n", .{});
}
