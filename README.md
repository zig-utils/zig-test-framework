# Zig Test Framework

A modern, feature-rich testing framework for Zig inspired by Jest, Vitest, and Bun's test runner.

## Features

- **Familiar API** - Describe/it syntax similar to Jest and Vitest
- **Rich Assertions** - Comprehensive assertion library with `.expect()` and matchers
- **Error Assertions** - `toThrow()` and `toThrowError()` for testing error handling
- **Test Hooks** - beforeEach, afterEach, beforeAll, afterAll support
- **Multiple Reporters** - Spec, Dot, and JSON reporters built-in
- **Mocking & Spying** - Function mocking and call tracking
- **Advanced Matchers** - Floating-point comparison, array/struct matchers, and more
- **CLI Support** - Full command-line interface with filtering and options
- **Nested Suites** - Support for nested describe blocks
- **Test Filtering** - Skip tests with `.skip()` or focus with `.only()`
- **Colorized Output** - Beautiful, readable test output with colors

## Installation

### As a Dependency

Add to your `build.zig.zon`:

```zig
.{
    .name = "my-project",
    .version = "0.1.0",
    .dependencies = .{
        .@"zig-test-framework" = .{
            .url = "https://github.com/zig-utils/zig-test-framework/archive/refs/tags/v0.1.0.tar.gz",
            // Replace with actual hash after publishing
        },
    },
}
```

### Quick Start

1. Clone this repository
2. Run `zig build` to build the framework
3. Run `zig build test` to run the framework's self-tests
4. Run `zig build examples` to run the example tests

## Usage

### Basic Test Example

```zig
const std = @import("std");
const ztf = @import("zig-test-framework");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Define a test suite
    try ztf.describe(allocator, "Math operations", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should add two numbers", testAddition);
            try ztf.it(alloc, "should subtract two numbers", testSubtraction);
        }

        fn testAddition(alloc: std.mem.Allocator) !void {
            const result = 2 + 2;
            try ztf.expect(alloc, result).toBe(4);
        }

        fn testSubtraction(alloc: std.mem.Allocator) !void {
            const result = 10 - 5;
            try ztf.expect(alloc, result).toBe(5);
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
```

### Assertions

```zig
// Basic equality
try expect(alloc, 5).toBe(5);
try expect(alloc, true).toBeTruthy();
try expect(alloc, false).toBeFalsy();

// Negation
try expect(alloc, 5).not().toBe(10);

// Comparisons
try expect(alloc, 10).toBeGreaterThan(5);
try expect(alloc, 10).toBeGreaterThanOrEqual(10);
try expect(alloc, 5).toBeLessThan(10);
try expect(alloc, 5).toBeLessThanOrEqual(5);

// Strings
try expect(alloc, "hello").toBe("hello");
try expect(alloc, "hello world").toContain("world");
try expect(alloc, "hello").toStartWith("hel");
try expect(alloc, "hello").toEndWith("lo");
try expect(alloc, "hello").toHaveLength(5);

// Optionals
const value: ?i32 = null;
try expect(alloc, value).toBeNull();

const defined: ?i32 = 42;
try expect(alloc, defined).toBeDefined();

// Arrays/Slices
const numbers = [_]i32{1, 2, 3, 4, 5};
const matcher = expectArray(alloc, &numbers);
try matcher.toHaveLength(5);
try matcher.toContain(3);
try matcher.toContainAll(&[_]i32{1, 3, 5});

// Error assertions
const FailingFn = struct {
    fn call() !void {
        return error.TestError;
    }
};
try expect(alloc, FailingFn.call).toThrow();
try expect(alloc, FailingFn.call).toThrowError(error.TestError);
```

### Advanced Matchers

```zig
// Floating-point comparison
try ztf.toBeCloseTo(0.1 + 0.2, 0.3, 10);

// NaN and Infinity
try ztf.toBeNaN(std.math.nan(f64));
try ztf.toBeInfinite(std.math.inf(f64));

// Struct matching
const User = struct {
    name: []const u8,
    age: u32,
};

const user = User{ .name = "Alice", .age = 30 };
const matcher = ztf.expectStruct(alloc, user);
try matcher.toHaveField("name", "Alice");
try matcher.toHaveField("age", @as(u32, 30));
```

### Test Hooks

```zig
try ztf.describe(allocator, "Database tests", struct {
    var db_connection: ?*Database = null;

    fn testSuite(alloc: std.mem.Allocator) !void {
        // Runs once before all tests
        try ztf.beforeAll(alloc, setupDatabase);

        // Runs before each test
        try ztf.beforeEach(alloc, openConnection);

        // Runs after each test
        try ztf.afterEach(alloc, closeConnection);

        // Runs once after all tests
        try ztf.afterAll(alloc, teardownDatabase);

        try ztf.it(alloc, "should query data", testQuery);
        try ztf.it(alloc, "should insert data", testInsert);
    }

    fn setupDatabase(alloc: std.mem.Allocator) !void {
        // Initialize database
    }

    fn teardownDatabase(alloc: std.mem.Allocator) !void {
        // Cleanup database
    }

    fn openConnection(alloc: std.mem.Allocator) !void {
        // Open DB connection
    }

    fn closeConnection(alloc: std.mem.Allocator) !void {
        // Close DB connection
    }

    fn testQuery(alloc: std.mem.Allocator) !void {
        // Test implementation
    }

    fn testInsert(alloc: std.mem.Allocator) !void {
        // Test implementation
    }
}.testSuite);
```

### Memory Management

**Important**: Always call `cleanupRegistry()` after running tests to prevent memory leaks:

```zig
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Define your test suites...
    try ztf.describe(allocator, "My tests", ...);

    // Run tests
    const registry = ztf.getRegistry(allocator);
    const success = try ztf.runTests(allocator, registry);

    // Clean up - IMPORTANT!
    ztf.cleanupRegistry();

    if (!success) {
        std.process.exit(1);
    }
}
```

The `cleanupRegistry()` function frees all test suites, test cases, and associated resources. Without it, you'll see memory leaks when using `GeneralPurposeAllocator` in debug mode.

### Nested Describe Blocks

```zig
try ztf.describe(allocator, "User Service", struct {
    fn testSuite(alloc: std.mem.Allocator) !void {
        try ztf.describe(alloc, "Authentication", struct {
            fn nestedSuite(nested_alloc: std.mem.Allocator) !void {
                try ztf.it(nested_alloc, "should login with valid credentials", testValidLogin);
                try ztf.it(nested_alloc, "should reject invalid credentials", testInvalidLogin);
            }

            fn testValidLogin(nested_alloc: std.mem.Allocator) !void {
                // Test implementation
            }

            fn testInvalidLogin(nested_alloc: std.mem.Allocator) !void {
                // Test implementation
            }
        }.nestedSuite);
    }
}.testSuite);
```

### Mocking and Spying

```zig
// Create a mock
var mock_fn = ztf.createMock(alloc, i32);
defer mock_fn.deinit();

// Record calls
try mock_fn.recordCall("arg1");
try mock_fn.recordCall("arg2");

// Assert on calls
try mock_fn.toHaveBeenCalled();
try mock_fn.toHaveBeenCalledTimes(2);
try mock_fn.toHaveBeenCalledWith("arg1");
try mock_fn.toHaveBeenLastCalledWith("arg2");

// Mock return values
try mock_fn.mockReturnValue(42);
const value = mock_fn.getReturnValue();
```

### Test Filtering

```zig
// Skip a test
try ztf.itSkip(alloc, "should skip this test", testSkipped);

// Skip an entire suite
try ztf.describeSkip(allocator, "Skipped suite", struct {
    // All tests in this suite will be skipped
}.testSuite);

// Run only specific tests
try ztf.itOnly(alloc, "should run only this test", testOnly);

// Run only specific suites
try ztf.describeOnly(allocator, "Only this suite", struct {
    // Only tests in this suite will run
}.testSuite);
```

## CLI Usage

```bash
# Run all tests
zig-test

# Show help
zig-test --help

# Use different reporter
zig-test --reporter dot
zig-test --reporter json

# Filter tests by name
zig-test --filter "user"

# Stop on first failure
zig-test --bail

# Disable colors
zig-test --no-color
```

### CLI Options

| Option | Alias | Description |
|--------|-------|-------------|
| `--help` | `-h` | Show help message |
| `--version` | `-v` | Show version information |
| `--bail` | `-b` | Stop on first failure |
| `--filter <pattern>` | | Run only tests matching pattern |
| `--reporter <name>` | | Set reporter (spec, dot, json) |
| `--verbose` | | Enable verbose output |
| `--quiet` | `-q` | Minimal output |
| `--no-color` | | Disable colored output |

## Reporters

### Spec Reporter (Default)

Beautiful hierarchical output with colors:

```
Running 12 test(s)...

Math operations
  ✓ should add two numbers (0.05ms)
  ✓ should subtract two numbers (0.03ms)
  ✓ should multiply two numbers (0.04ms)

String operations
  ✓ should compare strings (0.02ms)
  ✓ should check substring (0.03ms)

Test Summary:
  Total:   12
  Passed:  12
  Time:    1.23ms
```

### Dot Reporter

Minimal output for CI environments:

```
Running 12 tests:
............

Passed: 12, Failed: 0, Total: 12 (1.23ms)
```

### JSON Reporter

Machine-readable output for tooling:

```json
{
  "totalTests": 12,
  "tests": [
    {
      "name": "should add two numbers",
      "status": "passed",
      "time": 0.05
    }
  ],
  "summary": {
    "total": 12,
    "passed": 12,
    "failed": 0,
    "skipped": 0,
    "time": 1.23
  }
}
```

## API Reference

See [docs/api.md](docs/api.md) for complete API documentation.

## Examples

Check out the `examples/` directory for more examples:

- `examples/basic_test.zig` - Basic assertions and test structure
- `examples/advanced_test.zig` - Hooks, matchers, mocking, and advanced features

## Building from Source

```bash
# Clone the repository
git clone https://github.com/zig-utils/zig-test-framework.git
cd zig-test-framework

# Build the framework
zig build

# Run self-tests
zig build test

# Run examples
zig build examples
```

## Requirements

- Zig 0.13.0 or later

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Roadmap

- [ ] Snapshot testing
- [ ] Async/await test support
- [ ] Test timeout handling
- [ ] Code coverage reporting
- [ ] Watch mode for file changes
- [ ] Parameterized tests (it.each)
- [ ] Property-based testing
- [ ] IDE integration
- [ ] Performance benchmarking

## Acknowledgments

Inspired by:
- [Jest](https://jestjs.io/) - JavaScript testing framework
- [Vitest](https://vitest.dev/) - Vite-native testing framework
- [Bun Test](https://bun.sh/docs/cli/test) - Bun's built-in test runner

## Support

- GitHub Issues: https://github.com/zig-utils/zig-test-framework/issues
- Documentation: https://github.com/zig-utils/zig-test-framework/tree/main/docs

---

Made with ❤️ for the Zig community
