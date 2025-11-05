# Lifecycle Hooks

> Learn how to use beforeAll, beforeEach, afterEach, and afterAll lifecycle hooks in Zig Test Framework

The Zig Test Framework supports comprehensive lifecycle hooks that allow you to perform setup and teardown operations at various points during test execution. These hooks are inspired by popular testing frameworks like Bun, Vitest, and Jest.

## Available Hooks

| Hook         | Description                 |
| ------------ | --------------------------- |
| `beforeAll`  | Runs once before all tests in a describe block |
| `beforeEach` | Runs before each test       |
| `afterEach`  | Runs after each test        |
| `afterAll`   | Runs once after all tests in a describe block  |

## Per-Test Setup and Teardown

Perform per-test setup and teardown logic with `beforeEach` and `afterEach`.

```zig
const std = @import("std");
const ztf = @import("zig-test-framework");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try ztf.describe(allocator, "User Service", struct {
        var user_data: ?[]const u8 = null;

        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.beforeEach(alloc, setupTest);
            try ztf.afterEach(alloc, cleanupTest);

            try ztf.it(alloc, "should create a user", testCreateUser);
            try ztf.it(alloc, "should update a user", testUpdateUser);
        }

        fn setupTest(alloc: std.mem.Allocator) !void {
            _ = alloc;
            std.debug.print("Setting up test...\n", .{});
            user_data = "test_user";
        }

        fn cleanupTest(alloc: std.mem.Allocator) !void {
            _ = alloc;
            std.debug.print("Cleaning up test...\n", .{});
            user_data = null;
        }

        fn testCreateUser(alloc: std.mem.Allocator) !void {
            try ztf.expect(alloc, user_data != null).toBe(true);
        }

        fn testUpdateUser(alloc: std.mem.Allocator) !void {
            try ztf.expect(alloc, user_data != null).toBe(true);
        }
    }.testSuite);

    // Run all tests
    const registry = ztf.getRegistry(allocator);
    _ = try ztf.runTests(allocator, registry);
    ztf.cleanupRegistry();
}
```

## Per-Suite Setup and Teardown

Perform per-suite setup and teardown logic with `beforeAll` and `afterAll`. The scope is determined by where the hook is defined.

### Scoped to a Describe Block

To scope the hooks to a particular describe block:

```zig
try ztf.describe(allocator, "Database tests", struct {
    var db_connection: ?*Database = null;

    fn testSuite(alloc: std.mem.Allocator) !void {
        try ztf.beforeAll(alloc, setupDatabase);
        try ztf.afterAll(alloc, teardownDatabase);

        try ztf.it(alloc, "should query data", testQuery);
        try ztf.it(alloc, "should insert data", testInsert);
    }

    fn setupDatabase(alloc: std.mem.Allocator) !void {
        _ = alloc;
        std.debug.print("Setting up database connection...\n", .{});
        // db_connection = try Database.connect();
    }

    fn teardownDatabase(alloc: std.mem.Allocator) !void {
        _ = alloc;
        std.debug.print("Tearing down database connection...\n", .{});
        // if (db_connection) |db| db.close();
        db_connection = null;
    }

    fn testQuery(alloc: std.mem.Allocator) !void {
        try ztf.expect(alloc, db_connection != null).toBe(true);
    }

    fn testInsert(alloc: std.mem.Allocator) !void {
        try ztf.expect(alloc, db_connection != null).toBe(true);
    }
}.testSuite);
```

## Nested Hooks

Hooks can be nested and will run in the appropriate order:
- `beforeEach` hooks run from outer to inner (parent before child)
- `afterEach` hooks run from inner to outer (child before parent)
- `beforeAll` hooks run once per suite before any tests
- `afterAll` hooks run once per suite after all tests

```zig
try ztf.describe(allocator, "Outer suite", struct {
    var outer_setup_count: i32 = 0;

    fn testSuite(alloc: std.mem.Allocator) !void {
        try ztf.beforeAll(alloc, outerBeforeAll);
        try ztf.beforeEach(alloc, outerBeforeEach);
        try ztf.afterEach(alloc, outerAfterEach);
        try ztf.afterAll(alloc, outerAfterAll);

        try ztf.it(alloc, "outer test", outerTest);

        try ztf.describe(alloc, "Inner suite", struct {
            var inner_setup_count: i32 = 0;

            fn innerSuite(inner_alloc: std.mem.Allocator) !void {
                try ztf.beforeAll(inner_alloc, innerBeforeAll);
                try ztf.beforeEach(inner_alloc, innerBeforeEach);
                try ztf.afterEach(inner_alloc, innerAfterEach);
                try ztf.afterAll(inner_alloc, innerAfterAll);

                try ztf.it(inner_alloc, "inner test", innerTest);
            }

            fn innerBeforeAll(inner_alloc: std.mem.Allocator) !void {
                _ = inner_alloc;
                std.debug.print("Inner beforeAll\n", .{});
            }

            fn innerBeforeEach(inner_alloc: std.mem.Allocator) !void {
                _ = inner_alloc;
                inner_setup_count += 1;
                std.debug.print("Inner beforeEach\n", .{});
            }

            fn innerAfterEach(inner_alloc: std.mem.Allocator) !void {
                _ = inner_alloc;
                std.debug.print("Inner afterEach\n", .{});
            }

            fn innerAfterAll(inner_alloc: std.mem.Allocator) !void {
                _ = inner_alloc;
                std.debug.print("Inner afterAll\n", .{});
            }

            fn innerTest(inner_alloc: std.mem.Allocator) !void {
                // Both outer and inner beforeEach hooks have run
                try ztf.expect(inner_alloc, outer_setup_count).toBeGreaterThan(0);
                try ztf.expect(inner_alloc, inner_setup_count).toBeGreaterThan(0);
            }
        }.innerSuite);
    }

    fn outerBeforeAll(alloc: std.mem.Allocator) !void {
        _ = alloc;
        std.debug.print("Outer beforeAll\n", .{});
    }

    fn outerBeforeEach(alloc: std.mem.Allocator) !void {
        _ = alloc;
        outer_setup_count += 1;
        std.debug.print("Outer beforeEach\n", .{});
    }

    fn outerAfterEach(alloc: std.mem.Allocator) !void {
        _ = alloc;
        std.debug.print("Outer afterEach\n", .{});
    }

    fn outerAfterAll(alloc: std.mem.Allocator) !void {
        _ = alloc;
        std.debug.print("Outer afterAll\n", .{});
    }

    fn outerTest(alloc: std.mem.Allocator) !void {
        try ztf.expect(alloc, outer_setup_count).toBeGreaterThan(0);
    }
}.testSuite);
```

**Output order:**
```
Outer beforeAll
Outer beforeEach
outer test
Outer afterEach
Inner beforeAll
Outer beforeEach
Inner beforeEach
inner test
Inner afterEach
Outer afterEach
Inner afterAll
Outer afterAll
```

## Practical Examples

### Database Setup

```zig
try ztf.describe(allocator, "Database operations", struct {
    const Connection = struct {
        id: u32,
        active: bool,
    };

    var db_initialized: bool = false;
    var connection: ?Connection = null;

    fn testSuite(alloc: std.mem.Allocator) !void {
        try ztf.beforeAll(alloc, initializeDatabase);
        try ztf.afterAll(alloc, shutdownDatabase);
        try ztf.beforeEach(alloc, getConnection);
        try ztf.afterEach(alloc, releaseConnection);

        try ztf.it(alloc, "should execute query", testQuery);
        try ztf.it(alloc, "should insert record", testInsert);
    }

    fn initializeDatabase(alloc: std.mem.Allocator) !void {
        _ = alloc;
        std.debug.print("Initializing database...\n", .{});
        db_initialized = true;
    }

    fn shutdownDatabase(alloc: std.mem.Allocator) !void {
        _ = alloc;
        std.debug.print("Shutting down database...\n", .{});
        db_initialized = false;
    }

    fn getConnection(alloc: std.mem.Allocator) !void {
        _ = alloc;
        connection = Connection{ .id = 1, .active = true };
    }

    fn releaseConnection(alloc: std.mem.Allocator) !void {
        _ = alloc;
        if (connection) |*conn| {
            conn.active = false;
        }
        connection = null;
    }

    fn testQuery(alloc: std.mem.Allocator) !void {
        try ztf.expect(alloc, db_initialized).toBe(true);
        try ztf.expect(alloc, connection != null).toBe(true);
    }

    fn testInsert(alloc: std.mem.Allocator) !void {
        try ztf.expect(alloc, db_initialized).toBe(true);
        try ztf.expect(alloc, connection != null).toBe(true);
    }
}.testSuite);
```

### File I/O Setup

```zig
try ztf.describe(allocator, "File operations", struct {
    var temp_dir_created: bool = false;
    var file_handle: ?[]const u8 = null;

    fn testSuite(alloc: std.mem.Allocator) !void {
        try ztf.beforeAll(alloc, createTempDirectory);
        try ztf.afterAll(alloc, cleanupTempDirectory);
        try ztf.beforeEach(alloc, openFile);
        try ztf.afterEach(alloc, closeFile);

        try ztf.it(alloc, "should write to file", testWrite);
        try ztf.it(alloc, "should read from file", testRead);
    }

    fn createTempDirectory(alloc: std.mem.Allocator) !void {
        _ = alloc;
        std.debug.print("Creating temp directory...\n", .{});
        temp_dir_created = true;
    }

    fn cleanupTempDirectory(alloc: std.mem.Allocator) !void {
        _ = alloc;
        std.debug.print("Cleaning up temp directory...\n", .{});
        temp_dir_created = false;
    }

    fn openFile(alloc: std.mem.Allocator) !void {
        _ = alloc;
        file_handle = "mock_file_handle";
    }

    fn closeFile(alloc: std.mem.Allocator) !void {
        _ = alloc;
        file_handle = null;
    }

    fn testWrite(alloc: std.mem.Allocator) !void {
        try ztf.expect(alloc, file_handle != null).toBe(true);
        try ztf.expect(alloc, temp_dir_created).toBe(true);
    }

    fn testRead(alloc: std.mem.Allocator) !void {
        try ztf.expect(alloc, file_handle != null).toBe(true);
        try ztf.expect(alloc, temp_dir_created).toBe(true);
    }
}.testSuite);
```

### Mock Setup

```zig
try ztf.describe(allocator, "API Client with mocks", struct {
    var api_mock: ?ztf.Mock([]const u8) = null;

    fn testSuite(alloc: std.mem.Allocator) !void {
        try ztf.beforeEach(alloc, setupMocks);
        try ztf.afterEach(alloc, resetMocks);

        try ztf.it(alloc, "should call API endpoint", testApiCall);
    }

    fn setupMocks(alloc: std.mem.Allocator) !void {
        api_mock = ztf.createMock(alloc, []const u8);
        try api_mock.?.mockReturnValue("mock_response");
    }

    fn resetMocks(alloc: std.mem.Allocator) !void {
        _ = alloc;
        if (api_mock) |*mock| {
            mock.deinit();
        }
        api_mock = null;
    }

    fn testApiCall(alloc: std.mem.Allocator) !void {
        _ = alloc;
        // Test using the mock
        if (api_mock) |*mock| {
            const response = mock.getReturnValue();
            try ztf.expect(alloc, response).toBe(@as(?[]const u8, "mock_response"));
        }
    }
}.testSuite);
```

## Error Handling

If a lifecycle hook throws an error, it affects test execution:

### beforeAll Errors

If `beforeAll` throws an error, all tests in that suite will be skipped:

```zig
try ztf.describe(allocator, "Tests with failing beforeAll", struct {
    fn testSuite(alloc: std.mem.Allocator) !void {
        try ztf.beforeAll(alloc, failingSetup);
        try ztf.it(alloc, "this test will be skipped", test1);
    }

    fn failingSetup(alloc: std.mem.Allocator) !void {
        _ = alloc;
        return error.SetupFailed;
    }

    fn test1(alloc: std.mem.Allocator) !void {
        _ = alloc;
        // This won't run
    }
}.testSuite);
```

### beforeEach Errors

If `beforeEach` throws an error, the current test will fail and skip to `afterEach`:

```zig
try ztf.describe(allocator, "Tests with failing beforeEach", struct {
    fn testSuite(alloc: std.mem.Allocator) !void {
        try ztf.beforeEach(alloc, failingBefore);
        try ztf.afterEach(alloc, cleanupAfter);
        try ztf.it(alloc, "this test will fail", test1);
    }

    fn failingBefore(alloc: std.mem.Allocator) !void {
        _ = alloc;
        return error.BeforeEachFailed;
    }

    fn cleanupAfter(alloc: std.mem.Allocator) !void {
        _ = alloc;
        // This will still run even though beforeEach failed
    }

    fn test1(alloc: std.mem.Allocator) !void {
        _ = alloc;
        // This won't run
    }
}.testSuite);
```

### afterEach and afterAll Errors

Errors in `afterEach` and `afterAll` are logged but don't affect test results:

```zig
try ztf.describe(allocator, "Tests with failing afterEach", struct {
    fn testSuite(alloc: std.mem.Allocator) !void {
        try ztf.afterEach(alloc, failingAfter);
        try ztf.it(alloc, "test will pass", test1);
    }

    fn failingAfter(alloc: std.mem.Allocator) !void {
        _ = alloc;
        return error.CleanupFailed; // Error is logged but test still passes
    }

    fn test1(alloc: std.mem.Allocator) !void {
        try ztf.expect(alloc, true).toBe(true);
    }
}.testSuite);
```

## Best Practices

### Keep Hooks Simple

```zig
// Good: Simple, focused setup
fn beforeEach(alloc: std.mem.Allocator) !void {
    _ = alloc;
    clearLocalStorage();
    resetCounters();
}

// Avoid: Complex logic in hooks makes tests hard to debug
fn beforeEachComplex(alloc: std.mem.Allocator) !void {
    const data = try fetchComplexData(alloc);
    try processData(data);
    try setupMultipleServices(data);
    // Too much complexity!
}
```

### Use Appropriate Scope

```zig
// Good: Suite-level setup for expensive resources
fn beforeAll(alloc: std.mem.Allocator) !void {
    _ = alloc;
    try startTestServer(); // Expensive operation, do once
}

// Good: Test-level setup for test-specific state
fn beforeEach(alloc: std.mem.Allocator) !void {
    _ = alloc;
    user = createTestUser(); // Fresh state for each test
}
```

### Clean Up Resources

Always clean up resources in `afterEach` and `afterAll`:

```zig
fn testSuite(alloc: std.mem.Allocator) !void {
    try ztf.afterEach(alloc, cleanupTest);
    try ztf.afterAll(alloc, cleanupSuite);

    // tests...
}

fn cleanupTest(alloc: std.mem.Allocator) !void {
    _ = alloc;
    // Clean up after each test
    clearTemporaryData();
}

fn cleanupSuite(alloc: std.mem.Allocator) !void {
    _ = alloc;
    // Clean up expensive resources
    try closeDatabase();
    try stopServer();
}
```

### Handle Errors Gracefully

```zig
fn setupDatabase(alloc: std.mem.Allocator) !void {
    _ = alloc;
    database.connect() catch |err| {
        std.debug.print("Database setup failed: {any}\n", .{err});
        return err; // Re-throw to fail the suite
    };
}
```

## Multiple Hooks of Same Type

You can register multiple hooks of the same type, and they will run in the order they were registered:

```zig
try ztf.describe(allocator, "Multiple hooks", struct {
    fn testSuite(alloc: std.mem.Allocator) !void {
        try ztf.beforeEach(alloc, setup1);
        try ztf.beforeEach(alloc, setup2);
        try ztf.beforeEach(alloc, setup3);

        try ztf.afterEach(alloc, cleanup1);
        try ztf.afterEach(alloc, cleanup2);

        try ztf.it(alloc, "test", testFunc);
    }

    fn setup1(alloc: std.mem.Allocator) !void {
        _ = alloc;
        std.debug.print("Setup 1\n", .{});
    }

    fn setup2(alloc: std.mem.Allocator) !void {
        _ = alloc;
        std.debug.print("Setup 2\n", .{});
    }

    fn setup3(alloc: std.mem.Allocator) !void {
        _ = alloc;
        std.debug.print("Setup 3\n", .{});
    }

    fn cleanup1(alloc: std.mem.Allocator) !void {
        _ = alloc;
        std.debug.print("Cleanup 1\n", .{});
    }

    fn cleanup2(alloc: std.mem.Allocator) !void {
        _ = alloc;
        std.debug.print("Cleanup 2\n", .{});
    }

    fn testFunc(alloc: std.mem.Allocator) !void {
        try ztf.expect(alloc, true).toBe(true);
    }
}.testSuite);
```

**Output:**
```
Setup 1
Setup 2
Setup 3
test
Cleanup 1
Cleanup 2
```

## API Reference

### beforeAll

Registers a function to run once before all tests in the current describe block.

**Signature:**
```zig
pub fn beforeAll(allocator: std.mem.Allocator, hook: HookFn) !void
```

**Parameters:**
- `allocator`: Memory allocator
- `hook`: Function to run before all tests

**Hook Function Type:**
```zig
pub const HookFn = *const fn (allocator: std.mem.Allocator) anyerror!void;
```

### afterAll

Registers a function to run once after all tests in the current describe block.

**Signature:**
```zig
pub fn afterAll(allocator: std.mem.Allocator, hook: HookFn) !void
```

### beforeEach

Registers a function to run before each test in the current describe block (and nested blocks).

**Signature:**
```zig
pub fn beforeEach(allocator: std.mem.Allocator, hook: HookFn) !void
```

### afterEach

Registers a function to run after each test in the current describe block (and nested blocks).

**Signature:**
```zig
pub fn afterEach(allocator: std.mem.Allocator, hook: HookFn) !void
```

## Summary

Lifecycle hooks in Zig Test Framework provide powerful capabilities for:
- Setting up and tearing down test fixtures
- Managing shared resources across tests
- Organizing test code with proper setup/cleanup separation
- Handling nested test contexts with inherited hooks

The hooks follow the same patterns as Bun/Vitest/Jest, making them familiar to developers coming from JavaScript/TypeScript ecosystems while maintaining Zig's explicit error handling and memory management principles.
