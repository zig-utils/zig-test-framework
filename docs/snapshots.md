# Snapshot Testing

Snapshot testing is a powerful technique for testing complex outputs by capturing and storing expected values. When tests run, outputs are compared against stored snapshots. If they differ, the test fails and shows a diff.

## Table of Contents

- [Basic Usage](#basic-usage)
- [API Reference](#api-reference)
- [Snapshot Formats](#snapshot-formats)
- [Named Snapshots](#named-snapshots)
- [Updating Snapshots](#updating-snapshots)
- [Interactive Mode](#interactive-mode)
- [Snapshot Management](#snapshot-management)
- [Best Practices](#best-practices)
- [Examples](#examples)

## Basic Usage

### Creating a Simple Snapshot

```zig
const std = @import("std");
const ztf = @import("zig-test-framework");

test "snapshot example" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try ztf.describe(allocator, "Snapshot Tests", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should match snapshot", testSnapshot);
        }

        fn testSnapshot(alloc: std.mem.Allocator) !void {
            // Create a snapshot with update mode
            var snap = ztf.createSnapshot(alloc, "my_test", .{ .update = true });
            try snap.matchString("Hello, World!");

            // Subsequent runs verify against the snapshot
            var snap2 = ztf.createSnapshot(alloc, "my_test", .{});
            try snap2.matchString("Hello, World!");
        }
    }.testSuite);

    const registry = ztf.getRegistry(allocator);
    _ = try ztf.runTests(allocator, registry);
    ztf.cleanupRegistry();
}
```

### Snapshotting Structs

```zig
fn testStructSnapshot(alloc: std.mem.Allocator) !void {
    const User = struct {
        name: []const u8,
        age: u32,
        active: bool,
    };

    const user = User{
        .name = "Alice",
        .age = 30,
        .active = true,
    };

    var snap = ztf.createSnapshot(alloc, "user_struct", .{
        .update = true,
        .format = .pretty_text,
    });
    try snap.match(user);
}
```

## API Reference

### Creating Snapshots

```zig
pub fn createSnapshot(
    allocator: std.mem.Allocator,
    test_name: []const u8,
    options: SnapshotOptions,
) Snapshot
```

Creates a new snapshot instance for the given test.

**Parameters:**
- `allocator`: Memory allocator for snapshot operations
- `test_name`: Unique name identifying this snapshot
- `options`: Configuration options (see SnapshotOptions below)

### SnapshotOptions

```zig
pub const SnapshotOptions = struct {
    /// Directory where snapshots are stored (default: ".snapshots")
    snapshot_dir: []const u8 = ".snapshots",

    /// Update snapshots instead of verifying (default: false)
    update: bool = false,

    /// Interactively prompt for updates (default: false)
    interactive: bool = false,

    /// Format for snapshot serialization (default: .pretty_text)
    format: SnapshotFormat = .pretty_text,

    /// Pretty print the snapshot output (default: true)
    pretty_print: bool = true,

    /// File extension for snapshot files (default: ".snap")
    file_extension: []const u8 = ".snap",
};
```

### SnapshotFormat

```zig
pub const SnapshotFormat = enum {
    /// Human-readable text format with indentation
    pretty_text,

    /// Compact text format without extra whitespace
    compact_text,

    /// JSON format (great for structured data)
    json,

    /// Raw format (no transformation)
    raw,
};
```

### Snapshot Methods

#### matchString

```zig
pub fn matchString(self: *Snapshot, value: []const u8) !void
```

Matches a string value against the snapshot.

**Example:**
```zig
var snap = ztf.createSnapshot(alloc, "string_test", .{ .update = true });
try snap.matchString("Expected output");
```

#### matchStringNamed

```zig
pub fn matchStringNamed(
    self: *Snapshot,
    name: []const u8,
    value: []const u8,
) !void
```

Matches a named string snapshot, allowing multiple snapshots per test.

**Example:**
```zig
var snap = ztf.createSnapshot(alloc, "config_test", .{ .update = true });
try snap.matchStringNamed("dev", "dev configuration");
try snap.matchStringNamed("prod", "prod configuration");
```

#### match

```zig
pub fn match(self: *Snapshot, value: anytype) !void
```

Matches any value against the snapshot (structs, primitives, etc.).

**Example:**
```zig
const data = .{ .count = 42, .enabled = true };
var snap = ztf.createSnapshot(alloc, "data_test", .{ .update = true });
try snap.match(data);
```

#### matchNamed

```zig
pub fn matchNamed(
    self: *Snapshot,
    name: []const u8,
    value: anytype,
) !void
```

Matches a named value snapshot.

**Example:**
```zig
var snap = ztf.createSnapshot(alloc, "states_test", .{ .update = true });
try snap.matchNamed("initial", initial_state);
try snap.matchNamed("after_update", updated_state);
```

#### matchInline

```zig
pub fn matchInline(
    self: *Snapshot,
    file_path: []const u8,
    line_number: usize,
    value: anytype,
) !void
```

Matches an inline snapshot (stored in source code rather than external file).

## Snapshot Formats

### Pretty Text Format

Human-readable format with indentation and formatting.

```zig
var snap = ztf.createSnapshot(alloc, "pretty_test", .{
    .update = true,
    .format = .pretty_text,
    .pretty_print = true,
});
```

**Output:**
```
struct {
  name: Alice
  age: 30
  active: true
}
```

### JSON Format

Standard JSON format, great for structured data.

```zig
var snap = ztf.createSnapshot(alloc, "json_test", .{
    .update = true,
    .format = .json,
    .pretty_print = true,
});
```

**Output:**
```json
{
  "name": "Alice",
  "age": 30,
  "active": true
}
```

### Compact Text Format

Minimized format without extra whitespace.

```zig
var snap = ztf.createSnapshot(alloc, "compact_test", .{
    .update = true,
    .format = .compact_text,
});
```

**Output:**
```
struct{name:Alice,age:30,active:true}
```

### Raw Format

No transformation applied - stores value as-is.

```zig
var snap = ztf.createSnapshot(alloc, "raw_test", .{
    .update = true,
    .format = .raw,
});
```

## Named Snapshots

Named snapshots allow multiple snapshots within a single test.

```zig
fn testMultipleSnapshots(alloc: std.mem.Allocator) !void {
    var snap = ztf.createSnapshot(alloc, "app_states", .{ .update = true });

    // Snapshot different states
    try snap.matchStringNamed("initial", "App starting");
    try snap.matchStringNamed("loading", "Loading data...");
    try snap.matchStringNamed("ready", "App ready");

    // Each creates a separate snapshot file:
    // .snapshots/app_states_initial.snap
    // .snapshots/app_states_loading.snap
    // .snapshots/app_states_ready.snap
}
```

## Updating Snapshots

### Manual Update Mode

Set `update: true` in options:

```zig
var snap = ztf.createSnapshot(alloc, "test", .{ .update = true });
try snap.matchString("New expected value");
```

### Update All Snapshots

Run tests with update flag (if your test runner supports it):

```bash
zig build test-snapshots -- --update-snapshots
```

### Detecting Changes

When a snapshot doesn't match, you'll see a diff:

```
Snapshot mismatch for 'user_test':

=== Snapshot Diff ===
Line 1:
  - Expected: Alice
  + Received: Bob
Line 2:
  - Expected: 30
  + Received: 25
=====================

Run with --update-snapshots to update.
```

## Interactive Mode

Interactive mode prompts you to accept or reject snapshot changes:

```zig
var snap = ztf.createSnapshot(alloc, "test", .{
    .interactive = true,
});
try snap.matchString("New value");
```

When a mismatch occurs, you'll be prompted:

```
Snapshot 'test' has changed:
Expected: Old value
Received: New value
Interactive mode: Updating snapshot automatically.
```

## Snapshot Management

### Snapshot Cleanup Utility

The framework provides `SnapshotCleanup` to manage snapshot files:

```zig
fn cleanupSnapshots(alloc: std.mem.Allocator) !void {
    var cleanup = ztf.SnapshotCleanup.init(alloc, ".snapshots");
    defer cleanup.deinit();

    // List all snapshot files
    var snapshots = try cleanup.listSnapshots();
    defer {
        for (snapshots.items) |item| {
            alloc.free(item);
        }
        snapshots.deinit(alloc);
    }

    std.debug.print("Found {} snapshots\n", .{snapshots.items.len});

    // Mark snapshots as used
    try cleanup.markUsed("my_test.snap");

    // Remove unused snapshots
    try cleanup.removeUnused();
}
```

### Snapshot File Location

By default, snapshots are stored in `.snapshots/` directory:

```
.snapshots/
  ├── simple_string.snap
  ├── user_struct.snap
  ├── config_test_dev.snap
  ├── config_test_prod.snap
  └── complex_user.snap
```

You can customize the directory:

```zig
var snap = ztf.createSnapshot(alloc, "test", .{
    .snapshot_dir = "tests/__snapshots__",
});
```

## Best Practices

### 1. Use Descriptive Test Names

```zig
// Good: Descriptive name
var snap = ztf.createSnapshot(alloc, "user_registration_success", .{});

// Bad: Generic name
var snap = ztf.createSnapshot(alloc, "test1", .{});
```

### 2. Commit Snapshots to Version Control

Snapshot files should be committed alongside your tests:

```bash
git add .snapshots/
git commit -m "Add snapshot tests"
```

### 3. Review Snapshot Changes

When snapshots change, review the diff carefully:

```bash
git diff .snapshots/
```

### 4. Use Appropriate Formats

- **pretty_text**: For readability in reviews
- **json**: For structured data that may be processed
- **compact_text**: For minimal storage
- **raw**: For exact binary or special format data

### 5. Avoid Dynamic Values

Don't snapshot values that change between runs:

```zig
// Bad: Timestamps and IDs change
const user = User{
    .id = generateId(),           // Changes every run
    .created_at = std.time.timestamp(),  // Changes every run
    .name = "Alice",
};

// Good: Use stable values or property matchers
const user = User{
    .id = 1001,
    .created_at = 1234567890,
    .name = "Alice",
};
```

### 6. Keep Snapshots Focused

Each snapshot should test one specific aspect:

```zig
// Good: Separate snapshots for different concerns
var user_snap = ztf.createSnapshot(alloc, "user_data", .{});
try user_snap.match(user);

var config_snap = ztf.createSnapshot(alloc, "config_data", .{});
try config_snap.match(config);

// Bad: Single massive snapshot
var snap = ztf.createSnapshot(alloc, "everything", .{});
try snap.match(.{ .user = user, .config = config, .logs = logs });
```

### 7. Use Named Snapshots for Related Data

```zig
var snap = ztf.createSnapshot(alloc, "api_responses", .{ .update = true });

try snap.matchNamed("success", success_response);
try snap.matchNamed("error", error_response);
try snap.matchNamed("not_found", not_found_response);
```

## Examples

### Example 1: Testing API Responses

```zig
fn testApiResponse(alloc: std.mem.Allocator) !void {
    const Response = struct {
        status: u16,
        message: []const u8,
        data: ?[]const u8,
    };

    const response = Response{
        .status = 200,
        .message = "Success",
        .data = "User created",
    };

    var snap = ztf.createSnapshot(alloc, "api_create_user", .{
        .update = true,
        .format = .json,
    });
    try snap.match(response);
}
```

### Example 2: Testing Complex Nested Structures

```zig
fn testComplexObject(alloc: std.mem.Allocator) !void {
    const Address = struct {
        street: []const u8,
        city: []const u8,
        zip: []const u8,
    };

    const Preferences = struct {
        theme: []const u8,
        notifications: bool,
    };

    const User = struct {
        id: u32,
        username: []const u8,
        address: Address,
        preferences: Preferences,
    };

    const user = User{
        .id = 1001,
        .username = "johndoe",
        .address = .{
            .street = "123 Main St",
            .city = "Springfield",
            .zip = "12345",
        },
        .preferences = .{
            .theme = "dark",
            .notifications = true,
        },
    };

    var snap = ztf.createSnapshot(alloc, "complex_user", .{
        .update = true,
        .format = .json,
        .pretty_print = true,
    });
    try snap.match(user);
}
```

### Example 3: Testing Different Data Types

```zig
fn testVariousTypes(alloc: std.mem.Allocator) !void {
    // Integer
    const int_val: i32 = 42;
    var int_snap = ztf.createSnapshot(alloc, "integer_value", .{ .update = true });
    try int_snap.match(int_val);

    // Float
    const float_val: f64 = 3.14159;
    var float_snap = ztf.createSnapshot(alloc, "float_value", .{ .update = true });
    try float_snap.match(float_val);

    // Boolean
    const bool_val: bool = true;
    var bool_snap = ztf.createSnapshot(alloc, "bool_value", .{ .update = true });
    try bool_snap.match(bool_val);

    // String
    const str_val = "Hello, Snapshots!";
    var str_snap = ztf.createSnapshot(alloc, "string_value", .{ .update = true });
    try str_snap.matchString(str_val);
}
```

### Example 4: Testing State Transitions

```zig
fn testStateTransitions(alloc: std.mem.Allocator) !void {
    const State = enum { idle, loading, success, error };

    var snap = ztf.createSnapshot(alloc, "app_states", .{ .update = true });

    // Snapshot each state transition
    try snap.matchNamed("initial", State.idle);
    try snap.matchNamed("fetching", State.loading);
    try snap.matchNamed("completed", State.success);
}
```

### Example 5: Snapshot Mismatch Detection

```zig
fn testMismatchDetection(alloc: std.mem.Allocator) !void {
    // Create original snapshot
    var snap1 = ztf.createSnapshot(alloc, "mismatch_test", .{ .update = true });
    try snap1.matchString("Original value");

    // Try to match with different value (this should fail)
    var snap2 = ztf.createSnapshot(alloc, "mismatch_test", .{});
    const result = snap2.matchString("Different value");

    // Verify it errors with SnapshotMismatch
    if (result) {
        return error.TestFailed;
    } else |err| {
        try ztf.expect(alloc, err == error.SnapshotMismatch).toBe(true);
    }
}
```

## Troubleshooting

### Snapshot File Not Found

**Problem:** `error.FileNotFound` when trying to verify snapshot

**Solution:** Run test with `update: true` first to create the snapshot:

```zig
var snap = ztf.createSnapshot(alloc, "test", .{ .update = true });
try snap.matchString("value");
```

### Snapshot Always Failing

**Problem:** Snapshot comparison always fails even though values look identical

**Possible causes:**
1. Hidden whitespace differences
2. Different serialization format
3. Dynamic values (timestamps, random IDs)

**Solutions:**
- Check the diff output carefully
- Use consistent formats (`.format = .json`)
- Replace dynamic values with stable ones

### Memory Leaks

**Problem:** Tests leak memory when using snapshots

**Solution:** Ensure proper cleanup:

```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer {
    const leaked = gpa.deinit();
    if (leaked == .leak) @panic("Memory leak detected!");
}
```

### Too Many Snapshot Files

**Problem:** `.snapshots/` directory is cluttered with unused files

**Solution:** Use `SnapshotCleanup` to remove unused snapshots:

```zig
var cleanup = ztf.SnapshotCleanup.init(alloc, ".snapshots");
defer cleanup.deinit();
try cleanup.removeUnused();
```

## Comparison with Bun/Jest/Vitest

The Zig Test Framework snapshot API is inspired by and compatible with Jest/Vitest patterns:

| Feature | Bun/Jest/Vitest | Zig Test Framework |
|---------|-----------------|-------------------|
| Basic snapshots | `expect(value).toMatchSnapshot()` | `snap.match(value)` |
| Named snapshots | `expect(value).toMatchSnapshot('name')` | `snap.matchNamed('name', value)` |
| Inline snapshots | `expect(value).toMatchInlineSnapshot()` | `snap.matchInline(file, line, value)` |
| Update snapshots | `--updateSnapshots` flag | `update: true` option |
| Snapshot formats | Automatic | Configurable (JSON, text, compact, raw) |
| File location | `__snapshots__/` | `.snapshots/` (configurable) |

## Conclusion

Snapshot testing is a powerful tool for testing complex outputs, UI components, API responses, and more. The Zig Test Framework provides a comprehensive snapshot testing system with:

- Multiple serialization formats
- Named and inline snapshots
- Interactive update mode
- Diff visualization
- Snapshot cleanup utilities
- Bun/Jest/Vitest-inspired API

Use snapshots to catch unexpected changes and ensure your outputs remain consistent across refactoring and updates.
