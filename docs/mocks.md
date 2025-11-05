# Mocks

> Learn how to create and use mock functions, spies, and module mocks in Zig Test Framework

Mocking is essential for testing by allowing you to replace dependencies with controlled implementations. The Zig Test Framework provides comprehensive mocking capabilities including function mocks and spies, inspired by Bun, Jest, and Vitest.

## Basic Function Mocks

Create mocks with the `createMock` function.

```zig
const std = @import("std");
const ztf = @import("zig-test-framework");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var random_mock = ztf.createMock(allocator, i32);
    defer random_mock.deinit();

    try ztf.describe(allocator, "random function", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should track calls", testMock);
        }

        fn testMock(alloc: std.mem.Allocator) !void {
            var mock_fn = ztf.createMock(alloc, i32);
            defer mock_fn.deinit();

            _ = try mock_fn.mockReturnValue(42);
            try mock_fn.recordCall("test");

            const val = mock_fn.getReturnValue();
            try ztf.expect(alloc, val).toBe(@as(?i32, 42));
            try mock_fn.toHaveBeenCalled();
            try mock_fn.toHaveBeenCalledTimes(1);
        }
    }.testSuite);

    // Run tests
    const registry = ztf.getRegistry(allocator);
    _ = try ztf.runTests(allocator, registry);
    ztf.cleanupRegistry();
}
```

## Mock Function Properties

The result of `createMock()` is a `Mock(T)` struct that's been decorated with properties and methods for tracking calls and controlling behavior.

```zig
var mock_fn = ztf.createMock(allocator, i32);
defer mock_fn.deinit();

try mock_fn.recordCall("arg1");
try mock_fn.recordCall("arg2");

// Access call history
const calls = mock_fn.getCalls();
// calls[0].args == "arg1"
// calls[1].args == "arg2"

// Access results
const results = mock_fn.getResults();
```

### Available Properties and Methods

The following properties and methods are implemented on mock functions:

| Property/Method                           | Description                                    |
| ----------------------------------------- | ---------------------------------------------- |
| `mockFn.getMockName()`                    | Returns the mock name                          |
| `mockFn.getCalls()`                       | Array of call records for each invocation      |
| `mockFn.getResults()`                     | Array of results for each invocation           |
| `mockFn.getLastCall()`                    | Arguments of the most recent call              |
| `mockFn.mockClear()`                      | Clears call history                            |
| `mockFn.mockReset()`                      | Clears call history and removes implementation |
| `mockFn.mockRestore()`                    | Restores original implementation               |
| `mockFn.mockImplementation(fn)`           | Sets a new implementation                      |
| `mockFn.mockImplementationOnce(fn)`       | Sets implementation for next call only         |
| `mockFn.mockName(name)`                   | Sets the mock name                             |
| `mockFn.mockReturnThis()`                 | Returns self (for method chaining)             |
| `mockFn.mockReturnValue(value)`           | Sets a return value                            |
| `mockFn.mockReturnValueOnce(value)`       | Sets return value for next call only           |
| `mockFn.mockResolvedValue(value)`         | Sets a resolved value (async support)          |
| `mockFn.mockResolvedValueOnce(value)`     | Sets resolved value for next call only         |
| `mockFn.mockRejectedValue(error)`         | Sets a rejected error (async support)          |
| `mockFn.mockRejectedValueOnce(error)`     | Sets rejected error for next call only         |
| `mockFn.withImplementation(fn, callback)` | Temporarily changes implementation             |

### Practical Examples

#### Basic Mock Usage

```zig
try ztf.describe(allocator, "mock function behavior", struct {
    fn testSuite(alloc: std.mem.Allocator) !void {
        try ztf.it(alloc, "should track calls and return values", testBasic);
    }

    fn testBasic(alloc: std.mem.Allocator) !void {
        var mock_fn = ztf.createMock(alloc, i32);
        defer mock_fn.deinit();

        // Set return values
        _ = try mock_fn.mockReturnValueOnce(10);
        _ = try mock_fn.mockReturnValueOnce(20);

        // Call the mock
        try mock_fn.recordCall("5");
        const result1 = mock_fn.getReturnValue();

        try mock_fn.recordCall("10");
        const result2 = mock_fn.getReturnValue();

        // Verify calls
        try mock_fn.toHaveBeenCalledTimes(2);
        try mock_fn.toHaveBeenCalledWith("5");
        try mock_fn.toHaveBeenLastCalledWith("10");

        // Check results
        try ztf.expect(alloc, result1).toBe(@as(?i32, 10));
        try ztf.expect(alloc, result2).toBe(@as(?i32, 20));
    }
}.testSuite);
```

#### Dynamic Mock Return Values

```zig
try ztf.describe(allocator, "dynamic mock return values", struct {
    fn testSuite(alloc: std.mem.Allocator) !void {
        try ztf.it(alloc, "should return different values", testDynamic);
    }

    fn testDynamic(alloc: std.mem.Allocator) !void {
        var mock_fn = ztf.createMock(alloc, []const u8);
        defer mock_fn.deinit();

        // Set different return values
        _ = try mock_fn.mockReturnValueOnce("first");
        _ = try mock_fn.mockReturnValueOnce("second");
        _ = try mock_fn.mockReturnValue("default");

        try ztf.expect(alloc, mock_fn.getReturnValue()).toBe(@as(?[]const u8, "first"));
        try ztf.expect(alloc, mock_fn.getReturnValue()).toBe(@as(?[]const u8, "second"));
        try ztf.expect(alloc, mock_fn.getReturnValue()).toBe(@as(?[]const u8, "default"));
        try ztf.expect(alloc, mock_fn.getReturnValue()).toBe(@as(?[]const u8, "default")); // Repeats
    }
}.testSuite);
```

## Spies with spyOn()

Track calls to a function without replacing it entirely. Use `createSpy()` to create a spy; these spies can be passed to `.toHaveBeenCalled()` and `.toHaveBeenCalledTimes()`.

```zig
const User = struct {
    name: []const u8,

    pub fn greet(self: *const User) []const u8 {
        return self.name;
    }
};

try ztf.describe(allocator, "spy on methods", struct {
    fn testSuite(alloc: std.mem.Allocator) !void {
        try ztf.it(alloc, "should spy on function calls", testSpy);
    }

    fn testSpy(alloc: std.mem.Allocator) !void {
        const user = User{ .name = "Alice" };
        const original_fn = user.greet();

        var spy = ztf.createSpy(alloc, []const u8, original_fn);
        defer spy.deinit();

        try spy.call("test");

        try spy.toHaveBeenCalledTimes(1);
        try ztf.expect(alloc, spy.callCount()).toBe(@as(usize, 1));
    }
}.testSuite);
```

### Advanced Spy Usage

```zig
const UserService = struct {
    pub fn getUser(id: []const u8) []const u8 {
        return id;
    }

    pub fn createUser(data: []const u8) []const u8 {
        return data;
    }
};

try ztf.describe(allocator, "user service with spies", struct {
    fn testSuite(alloc: std.mem.Allocator) !void {
        try ztf.it(alloc, "should spy on service methods", testServiceSpy);
    }

    fn testServiceSpy(alloc: std.mem.Allocator) !void {
        // Create spies for service methods
        var getUserSpy = ztf.createSpy(alloc, []const u8, "original_user");
        defer getUserSpy.deinit();

        var createUserSpy = ztf.createSpy(alloc, []const u8, "original_create");
        defer createUserSpy.deinit();

        // Use the service (simulated)
        try getUserSpy.call("123");
        try createUserSpy.call("new_user_data");

        // Verify calls
        try getUserSpy.toHaveBeenCalledWith("123");
        try createUserSpy.toHaveBeenCalledWith("new_user_data");
    }
}.testSuite);
```

### Spy with Mock Implementation

```zig
try ztf.describe(allocator, "spy with mock implementation", struct {
    fn testSuite(alloc: std.mem.Allocator) !void {
        try ztf.it(alloc, "should override spy behavior", testSpyOverride);
    }

    fn testSpyOverride(alloc: std.mem.Allocator) !void {
        var spy = ztf.createSpy(alloc, i32, 42);
        defer spy.deinit();

        // Override the return value
        _ = try spy.mockReturnValue(100);

        const result = spy.mock.getReturnValue();
        try ztf.expect(alloc, result).toBe(@as(?i32, 100));
    }
}.testSuite);
```

## Global Mock Functions

### Clear All Mocks

Reset all mock function state (calls, results, etc.) without restoring their original implementation:

```zig
var mock1 = ztf.createMock(allocator, i32);
defer mock1.deinit();

var mock2 = ztf.createMock(allocator, i32);
defer mock2.deinit();

try mock1.recordCall("call1");
try mock2.recordCall("call2");

try ztf.expect(allocator, mock1.callCount()).toBe(@as(usize, 1));
try ztf.expect(allocator, mock2.callCount()).toBe(@as(usize, 1));

// Note: clearAllMocks() and restoreAllMocks() are available for global management
// but require manual tracking of mocks in Zig due to type system constraints

_ = mock1.mockClear();
_ = mock2.mockClear();

try ztf.expect(allocator, mock1.callCount()).toBe(@as(usize, 0));
try ztf.expect(allocator, mock2.callCount()).toBe(@as(usize, 0));
```

## Assertions with Mocks

The Zig Test Framework provides several assertion methods for mocks:

### toHaveBeenCalled

Verify that a mock was called at least once.

```zig
var mock_fn = ztf.createMock(allocator, i32);
defer mock_fn.deinit();

try mock_fn.recordCall("test");
try mock_fn.toHaveBeenCalled();
```

### toHaveBeenCalledTimes

Verify that a mock was called a specific number of times.

```zig
var mock_fn = ztf.createMock(allocator, i32);
defer mock_fn.deinit();

try mock_fn.recordCall("call1");
try mock_fn.recordCall("call2");
try mock_fn.recordCall("call3");

try mock_fn.toHaveBeenCalledTimes(3);
```

### toHaveBeenCalledWith

Verify that a mock was called with specific arguments.

```zig
var mock_fn = ztf.createMock(allocator, i32);
defer mock_fn.deinit();

try mock_fn.recordCall("expected_arg");
try mock_fn.toHaveBeenCalledWith("expected_arg");
```

### toHaveBeenLastCalledWith

Verify the arguments of the most recent call.

```zig
var mock_fn = ztf.createMock(allocator, i32);
defer mock_fn.deinit();

try mock_fn.recordCall("first");
try mock_fn.recordCall("second");
try mock_fn.recordCall("last");

try mock_fn.toHaveBeenLastCalledWith("last");
```

### toHaveBeenNthCalledWith

Verify the arguments of a specific call (1-indexed).

```zig
var mock_fn = ztf.createMock(allocator, i32);
defer mock_fn.deinit();

try mock_fn.recordCall("call1");
try mock_fn.recordCall("call2");
try mock_fn.recordCall("call3");

try mock_fn.toHaveBeenNthCalledWith(1, "call1");
try mock_fn.toHaveBeenNthCalledWith(2, "call2");
try mock_fn.toHaveBeenNthCalledWith(3, "call3");
```

## Practical Patterns

### Service Mock Pattern

```zig
const UserApi = struct {
    fetchUser: ztf.Mock([]const u8),
    createUser: ztf.Mock([]const u8),
    updateUser: ztf.Mock([]const u8),

    pub fn init(alloc: std.mem.Allocator) UserApi {
        return .{
            .fetchUser = ztf.createMock(alloc, []const u8),
            .createUser = ztf.createMock(alloc, []const u8),
            .updateUser = ztf.createMock(alloc, []const u8),
        };
    }

    pub fn deinit(self: *UserApi) void {
        self.fetchUser.deinit();
        self.createUser.deinit();
        self.updateUser.deinit();
    }
};

try ztf.describe(allocator, "user service with mocked API", struct {
    fn testSuite(alloc: std.mem.Allocator) !void {
        try ztf.it(alloc, "should call API methods", testUserService);
    }

    fn testUserService(alloc: std.mem.Allocator) !void {
        var api = UserApi.init(alloc);
        defer api.deinit();

        // Set up mock behavior
        _ = api.fetchUser.mockName("fetchUser");
        _ = try api.fetchUser.mockReturnValue("user_data");

        _ = api.createUser.mockName("createUser");
        _ = try api.createUser.mockReturnValue("new_user_id");

        // Simulate service calls
        try api.fetchUser.recordCall("user_123");
        try api.createUser.recordCall("new_user");

        // Verify
        try api.fetchUser.toHaveBeenCalledWith("user_123");
        try api.createUser.toHaveBeenCalledWith("new_user");
    }
}.testSuite);
```

### Factory Functions

```zig
fn createMockUser(alloc: std.mem.Allocator, id: []const u8) !ztf.Mock([]const u8) {
    var mock_user = ztf.createMock(alloc, []const u8);
    _ = try mock_user.mockReturnValue(id);
    _ = mock_user.mockName("User");
    return mock_user;
}

try ztf.describe(allocator, "user factory", struct {
    fn testSuite(alloc: std.mem.Allocator) !void {
        try ztf.it(alloc, "should create mock users", testFactory);
    }

    fn testFactory(alloc: std.mem.Allocator) !void {
        var user1 = try createMockUser(alloc, "user_1");
        defer user1.deinit();

        var user2 = try createMockUser(alloc, "user_2");
        defer user2.deinit();

        try ztf.expect(alloc, user1.getReturnValue()).toBe(@as(?[]const u8, "user_1"));
        try ztf.expect(alloc, user2.getReturnValue()).toBe(@as(?[]const u8, "user_2"));
    }
}.testSuite);
```

## Mock Cleanup Patterns

It's important to clean up mocks properly to avoid memory leaks:

```zig
try ztf.describe(allocator, "test suite with cleanup", struct {
    var api_mock: ?ztf.Mock([]const u8) = null;

    fn testSuite(alloc: std.mem.Allocator) !void {
        try ztf.beforeEach(alloc, setupMocks);
        try ztf.afterEach(alloc, cleanupMocks);

        try ztf.it(alloc, "test 1", test1);
        try ztf.it(alloc, "test 2", test2);
    }

    fn setupMocks(alloc: std.mem.Allocator) !void {
        api_mock = ztf.createMock(alloc, []const u8);
        _ = try api_mock.?.mockReturnValue("mock_response");
    }

    fn cleanupMocks(alloc: std.mem.Allocator) !void {
        _ = alloc;
        if (api_mock) |*mock| {
            mock.deinit();
            api_mock = null;
        }
    }

    fn test1(alloc: std.mem.Allocator) !void {
        if (api_mock) |*mock| {
            try ztf.expect(alloc, mock.getReturnValue()).toBe(@as(?[]const u8, "mock_response"));
        }
    }

    fn test2(alloc: std.mem.Allocator) !void {
        if (api_mock) |*mock| {
            _ = mock.mockClear();
            try ztf.expect(alloc, mock.callCount()).toBe(@as(usize, 0));
        }
    }
}.testSuite);
```

## Best Practices

### Keep Mocks Simple

```zig
// Good: Simple, focused mock
var mockUserApi = ztf.createMock(allocator, []const u8);
defer mockUserApi.deinit();
_ = try mockUserApi.mockReturnValue("user_data");

// Avoid: Overly complex mock setup
// Complex logic should be in the code under test, not the mock
```

### Use Type-Safe Mocks

```zig
const UserId = []const u8;
const UserData = []const u8;

var getUserMock = ztf.createMock(allocator, UserData);
defer getUserMock.deinit();
_ = try getUserMock.mockReturnValue("mock_user");
```

### Test Mock Behavior

```zig
try ztf.describe(allocator, "service with mocks", struct {
    fn testSuite(alloc: std.mem.Allocator) !void {
        try ztf.it(alloc, "should call API correctly", testApiCalls);
    }

    fn testApiCalls(alloc: std.mem.Allocator) !void {
        var apiMock = ztf.createMock(alloc, []const u8);
        defer apiMock.deinit();

        _ = try apiMock.mockReturnValue("response");
        try apiMock.recordCall("request_data");

        // Verify the mock was called correctly
        try apiMock.toHaveBeenCalledWith("request_data");
        try apiMock.toHaveBeenCalledTimes(1);
    }
}.testSuite);
```

### Clean Up Resources

Always use `defer` to ensure mocks are cleaned up:

```zig
var mock_fn = ztf.createMock(allocator, i32);
defer mock_fn.deinit(); // Always clean up!

// Use the mock...
```

## API Reference

### Mock(T)

Creates a mock function that returns values of type `T`.

**Signature:**
```zig
pub fn Mock(comptime ReturnType: type) type
```

**Methods:**
- `init(allocator)` - Create a new mock
- `deinit()` - Clean up the mock
- `mockName(name)` - Set the mock name
- `getMockName()` - Get the mock name
- `recordCall(args)` - Record a function call
- `mockReturnValue(value)` - Set a return value
- `mockReturnValueOnce(value)` - Set a one-time return value
- `getReturnValue()` - Get the next return value
- `mockClear()` - Clear call history
- `mockReset()` - Reset the mock completely
- `mockRestore()` - Mark as restored
- `toHaveBeenCalled()` - Assert mock was called
- `toHaveBeenCalledTimes(n)` - Assert call count
- `toHaveBeenCalledWith(args)` - Assert called with args
- `toHaveBeenLastCalledWith(args)` - Assert last call args
- `toHaveBeenNthCalledWith(n, args)` - Assert nth call args

### Spy(T)

Creates a spy that wraps an original function while tracking calls.

**Signature:**
```zig
pub fn Spy(comptime FnType: type) type
```

**Methods:**
- `init(allocator, original)` - Create a spy
- `deinit()` - Clean up the spy
- `call(args)` - Record a call
- `mockRestore()` - Restore original function
- `mockReturnValue(value)` - Override return value
- All assertion methods from Mock(T)

### Helper Functions

```zig
// Create a mock
pub fn createMock(allocator: std.mem.Allocator, comptime T: type) Mock(T)

// Create a spy
pub fn createSpy(allocator: std.mem.Allocator, comptime T: type, original: T) Spy(T)

// Aliases
pub const fn_ = createMock;
pub const spyOn = createSpy;
```

## Summary

The Zig Test Framework provides comprehensive mocking capabilities:
- **Function Mocks** - Track calls and control return values
- **Spies** - Wrap existing functions while tracking calls
- **Rich Assertions** - Verify call counts, arguments, and return values
- **Method Chaining** - Fluent API for mock configuration
- **Memory Safe** - Proper cleanup with Zig's allocator system

The mocking API follows patterns from Bun/Jest/Vitest, making it familiar to developers coming from JavaScript/TypeScript ecosystems while maintaining Zig's explicitness and safety guarantees.
