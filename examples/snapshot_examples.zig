const std = @import("std");
const zig_test = @import("zig-test");

/// Example 1: Basic String Snapshot
pub fn example_basic_string_snapshot() !void {
    const allocator = std.heap.page_allocator;

    var snap = zig_test.Snapshot.init(allocator, "basic_string", .{
        .update = true, // Set to false to compare against existing snapshot
    });

    try snap.matchString("Hello, Snapshot!");

    std.debug.print("Example 1: Basic string snapshot created\n", .{});
}

/// Example 2: Struct Snapshot with Pretty Format
pub fn example_struct_snapshot() !void {
    const allocator = std.heap.page_allocator;

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

    var snap = zig_test.Snapshot.init(allocator, "user_struct", .{
        .update = true,
        .format = .pretty_text,
    });

    try snap.match(user);

    std.debug.print("Example 2: Struct snapshot created\n", .{});
}

/// Example 3: JSON Format Snapshot
pub fn example_json_snapshot() !void {
    const allocator = std.heap.page_allocator;

    const Config = struct {
        host: []const u8,
        port: u32,
        secure: bool,
    };

    const config = Config{
        .host = "localhost",
        .port = 8080,
        .secure = false,
    };

    var snap = zig_test.Snapshot.init(allocator, "config_json", .{
        .update = true,
        .format = .json,
        .pretty_print = true,
    });

    try snap.match(config);

    std.debug.print("Example 3: JSON format snapshot created\n", .{});
}

/// Example 4: Multiple Named Snapshots
pub fn example_named_snapshots() !void {
    const allocator = std.heap.page_allocator;

    var snap = zig_test.Snapshot.init(allocator, "api_responses", .{
        .update = true,
    });

    // Create multiple snapshots for different scenarios
    try snap.matchStringNamed("success", "{ \"status\": \"ok\", \"data\": [] }");
    try snap.matchStringNamed("error", "{ \"status\": \"error\", \"message\": \"Not found\" }");
    try snap.matchStringNamed("empty", "{ \"status\": \"ok\", \"data\": null }");

    std.debug.print("Example 4: Named snapshots created\n", .{});
}

/// Example 5: Snapshot Comparison (Mismatch Detection)
pub fn example_snapshot_comparison() !void {
    const allocator = std.heap.page_allocator;

    // First, create a snapshot
    var snap1 = zig_test.Snapshot.init(allocator, "comparison_test", .{
        .update = true,
    });
    try snap1.matchString("Original value");

    std.debug.print("Example 5: Created snapshot with 'Original value'\n", .{});

    // Try to compare with different value (this will fail)
    var snap2 = zig_test.Snapshot.init(allocator, "comparison_test", .{
        .update = false,
    });

    // This will fail and show diff
    const result = snap2.matchString("Modified value");
    if (result) {
        std.debug.print("Match succeeded (unexpected)\n", .{});
    } else |err| {
        std.debug.print("Match failed as expected: {s}\n", .{@errorName(err)});
    }
}

/// Example 6: Compact Format Snapshot
pub fn example_compact_snapshot() !void {
    const allocator = std.heap.page_allocator;

    const Data = struct {
        x: i32,
        y: i32,
    };

    const data = Data{ .x = 10, .y = 20 };

    var snap = zig_test.Snapshot.init(allocator, "compact_data", .{
        .update = true,
        .format = .compact_text,
    });

    try snap.match(data);

    std.debug.print("Example 6: Compact format snapshot created\n", .{});
}

/// Example 7: Interactive Snapshot Update
pub fn example_interactive_update() !void {
    const allocator = std.heap.page_allocator;

    var snap = zig_test.Snapshot.init(allocator, "interactive_test", .{
        .update = true,
        .interactive = true, // Interactive mode (auto-updates in current implementation)
    });

    try snap.matchString("This will be created/updated interactively");

    std.debug.print("Example 7: Interactive snapshot updated\n", .{});
}

/// Example 8: Snapshot Diff Generation
pub fn example_diff_generation() !void {
    const allocator = std.heap.page_allocator;

    var diff = zig_test.SnapshotDiff.init(allocator);
    defer diff.deinit();

    // Add some differences
    try diff.addDiff(1, "line 1 original", "line 1 modified");
    try diff.addDiff(3, "line 3 original", "line 3 modified");
    try diff.addDiff(5, "line 5 exists", "");

    std.debug.print("Example 8: Diff generated:\n", .{});
    diff.print();
}

/// Example 9: Snapshot Cleanup
pub fn example_snapshot_cleanup() !void {
    const allocator = std.heap.page_allocator;

    // Create a cleanup manager
    var cleanup = zig_test.SnapshotCleanup.init(allocator, ".snapshots");
    defer cleanup.deinit();

    // List all snapshots
    var snapshots = try cleanup.listSnapshots();
    defer {
        for (snapshots.items) |item| {
            allocator.free(item);
        }
        snapshots.deinit(allocator);
    }

    std.debug.print("Example 9: Found {d} snapshot files\n", .{snapshots.items.len});

    // Mark some as used
    if (snapshots.items.len > 0) {
        try cleanup.markUsed(snapshots.items[0]);
        std.debug.print("Marked {s} as used\n", .{snapshots.items[0]});
    }

    // Note: In real usage, you'd call cleanup.cleanupUnused() here
    // but we skip it to preserve examples
    std.debug.print("Cleanup setup complete (skipping actual cleanup)\n", .{});
}

/// Example 10: Raw Format Snapshot
pub fn example_raw_snapshot() !void {
    const allocator = std.heap.page_allocator;

    var snap = zig_test.Snapshot.init(allocator, "raw_data", .{
        .update = true,
        .format = .raw,
    });

    const data = "Raw format: no formatting applied";
    try snap.matchString(data);

    std.debug.print("Example 10: Raw format snapshot created\n", .{});
}

/// Example 11: Custom Snapshot Directory
pub fn example_custom_directory() !void {
    const allocator = std.heap.page_allocator;

    var snap = zig_test.Snapshot.init(allocator, "custom_dir_test", .{
        .update = true,
        .snapshot_dir = ".custom_snapshots",
    });

    try snap.matchString("Snapshot in custom directory");

    std.debug.print("Example 11: Snapshot created in custom directory\n", .{});

    // Cleanup
    std.fs.cwd().deleteFile(".custom_snapshots/custom_dir_test.snap") catch {};
    std.fs.cwd().deleteDir(".custom_snapshots") catch {};
}

/// Example 12: Custom File Extension
pub fn example_custom_extension() !void {
    const allocator = std.heap.page_allocator;

    var snap = zig_test.Snapshot.init(allocator, "custom_ext_test", .{
        .update = true,
        .file_extension = ".snapshot",
    });

    try snap.matchString("Snapshot with custom extension");

    std.debug.print("Example 12: Snapshot with custom extension created\n", .{});

    // Cleanup
    std.fs.cwd().deleteFile(".snapshots/custom_ext_test.snapshot") catch {};
}

/// Example 13: Multiple Formats Comparison
pub fn example_multiple_formats() !void {
    const allocator = std.heap.page_allocator;

    const TestData = struct {
        name: []const u8,
        value: u32,
    };

    const data = TestData{
        .name = "test",
        .value = 42,
    };

    // Pretty text format
    var snap_pretty = zig_test.Snapshot.init(allocator, "format_pretty", .{
        .update = true,
        .format = .pretty_text,
    });
    try snap_pretty.match(data);

    // JSON format
    var snap_json = zig_test.Snapshot.init(allocator, "format_json", .{
        .update = true,
        .format = .json,
    });
    try snap_json.match(data);

    // Compact format
    var snap_compact = zig_test.Snapshot.init(allocator, "format_compact", .{
        .update = true,
        .format = .compact_text,
    });
    try snap_compact.match(data);

    std.debug.print("Example 13: Created snapshots in all formats\n", .{});
}

pub fn main() !void {
    std.debug.print("\n=== Snapshot Testing Examples ===\n\n", .{});

    std.debug.print("Running Example 1: Basic String Snapshot\n", .{});
    try example_basic_string_snapshot();

    std.debug.print("\nRunning Example 2: Struct Snapshot\n", .{});
    try example_struct_snapshot();

    std.debug.print("\nRunning Example 3: JSON Format\n", .{});
    try example_json_snapshot();

    std.debug.print("\nRunning Example 4: Named Snapshots\n", .{});
    try example_named_snapshots();

    std.debug.print("\nRunning Example 5: Snapshot Comparison\n", .{});
    try example_snapshot_comparison();

    std.debug.print("\nRunning Example 6: Compact Format\n", .{});
    try example_compact_snapshot();

    std.debug.print("\nRunning Example 7: Interactive Update\n", .{});
    try example_interactive_update();

    std.debug.print("\nRunning Example 8: Diff Generation\n", .{});
    try example_diff_generation();

    std.debug.print("\nRunning Example 9: Snapshot Cleanup\n", .{});
    try example_snapshot_cleanup();

    std.debug.print("\nRunning Example 10: Raw Format\n", .{});
    try example_raw_snapshot();

    std.debug.print("\nRunning Example 11: Custom Directory\n", .{});
    try example_custom_directory();

    std.debug.print("\nRunning Example 12: Custom Extension\n", .{});
    try example_custom_extension();

    std.debug.print("\nRunning Example 13: Multiple Formats\n", .{});
    try example_multiple_formats();

    std.debug.print("\n=== All Snapshot Examples Completed! ===\n", .{});
}
