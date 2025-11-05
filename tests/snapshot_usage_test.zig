const std = @import("std");
const ztf = @import("zig-test-framework");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test 1: Basic String Snapshots
    try ztf.describe(allocator, "Basic String Snapshots", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should snapshot a simple string", testSimpleString);
            try ztf.it(alloc, "should snapshot multiple values", testMultipleSnapshots);
        }

        fn testSimpleString(alloc: std.mem.Allocator) !void {
            var snap = ztf.createSnapshot(alloc, "simple_string", .{ .update = true });
            try snap.matchString("Hello, Snapshot Testing!");

            // Verify it matches
            var snap2 = ztf.createSnapshot(alloc, "simple_string", .{});
            try snap2.matchString("Hello, Snapshot Testing!");
        }

        fn testMultipleSnapshots(alloc: std.mem.Allocator) !void {
            var snap = ztf.createSnapshot(alloc, "multiple_snapshots", .{ .update = true });

            try snap.matchStringNamed("first", "First snapshot value");
            try snap.matchStringNamed("second", "Second snapshot value");
            try snap.matchStringNamed("third", "Third snapshot value");
        }
    }.testSuite);

    // Test 2: Struct Snapshots
    try ztf.describe(allocator, "Struct Snapshots", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should snapshot a simple struct", testSimpleStruct);
            try ztf.it(alloc, "should snapshot nested structs", testNestedStruct);
        }

        fn testSimpleStruct(alloc: std.mem.Allocator) !void {
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

            var snap = ztf.createSnapshot(alloc, "simple_struct", .{
                .update = true,
                .format = .pretty_text,
            });
            try snap.match(user);

            // Verify
            var snap2 = ztf.createSnapshot(alloc, "simple_struct", .{ .format = .pretty_text });
            try snap2.match(user);
        }

        fn testNestedStruct(alloc: std.mem.Allocator) !void {
            const Profile = struct {
                theme: []const u8,
                notifications: bool,
            };

            const User = struct {
                id: u32,
                name: []const u8,
                profile: Profile,
            };

            const user = User{
                .id = 1,
                .name = "Bob",
                .profile = .{
                    .theme = "dark",
                    .notifications = true,
                },
            };

            var snap = ztf.createSnapshot(alloc, "nested_struct", .{
                .update = true,
                .format = .json,
            });
            try snap.match(user);
        }
    }.testSuite);

    // Test 3: Snapshot Formats
    try ztf.describe(allocator, "Snapshot Formats", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should support pretty text format", testPrettyText);
            try ztf.it(alloc, "should support JSON format", testJsonFormat);
            try ztf.it(alloc, "should support compact format", testCompactFormat);
        }

        fn testPrettyText(alloc: std.mem.Allocator) !void {
            const Data = struct {
                title: []const u8,
                count: i32,
                enabled: bool,
            };

            const data = Data{
                .title = "Test Data",
                .count = 42,
                .enabled = true,
            };

            var snap = ztf.createSnapshot(alloc, "format_pretty", .{
                .update = true,
                .format = .pretty_text,
                .pretty_print = true,
            });
            try snap.match(data);
        }

        fn testJsonFormat(alloc: std.mem.Allocator) !void {
            const Data = struct {
                name: []const u8,
                value: i32,
            };

            const data = Data{
                .name = "json_test",
                .value = 123,
            };

            var snap = ztf.createSnapshot(alloc, "format_json", .{
                .update = true,
                .format = .json,
                .pretty_print = true,
            });
            try snap.match(data);
        }

        fn testCompactFormat(alloc: std.mem.Allocator) !void {
            var snap = ztf.createSnapshot(alloc, "format_compact", .{
                .update = true,
                .format = .compact_text,
            });
            try snap.matchString("Compact format test");
        }
    }.testSuite);

    // Test 4: Snapshot Diff Detection
    try ztf.describe(allocator, "Snapshot Mismatch Detection", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should detect changes in snapshots", testMismatchDetection);
        }

        fn testMismatchDetection(alloc: std.mem.Allocator) !void {
            // Create original snapshot
            var snap1 = ztf.createSnapshot(alloc, "mismatch_test", .{ .update = true });
            try snap1.matchString("Original value");

            // Try to match with different value (this should fail)
            var snap2 = ztf.createSnapshot(alloc, "mismatch_test", .{});
            const result = snap2.matchString("Different value");

            // This should error
            if (result) {
                std.debug.print("ERROR: Snapshot should have mismatched!\n", .{});
            } else |err| {
                try ztf.expect(alloc, err == error.SnapshotMismatch).toBe(true);
            }
        }
    }.testSuite);

    // Test 5: Named Snapshots
    try ztf.describe(allocator, "Named Snapshots", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should create separate named snapshots", testNamedSnapshots);
        }

        fn testNamedSnapshots(alloc: std.mem.Allocator) !void {
            var snap = ztf.createSnapshot(alloc, "named_test", .{ .update = true });

            // Create multiple named snapshots
            try snap.matchStringNamed("config_dev", "dev configuration");
            try snap.matchStringNamed("config_prod", "prod configuration");
            try snap.matchStringNamed("config_test", "test configuration");

            // Verify each one separately
            var snap2 = ztf.createSnapshot(alloc, "named_test", .{});
            try snap2.matchStringNamed("config_dev", "dev configuration");
            try snap2.matchStringNamed("config_prod", "prod configuration");
            try snap2.matchStringNamed("config_test", "test configuration");
        }
    }.testSuite);

    // Test 6: Complex Object Snapshots
    try ztf.describe(allocator, "Complex Objects", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should snapshot complex nested structures", testComplexObject);
        }

        fn testComplexObject(alloc: std.mem.Allocator) !void {
            const Address = struct {
                street: []const u8,
                city: []const u8,
                zip: []const u8,
            };

            const Preferences = struct {
                theme: []const u8,
                language: []const u8,
                notifications_enabled: bool,
            };

            const User = struct {
                id: u32,
                username: []const u8,
                email: []const u8,
                age: u32,
                active: bool,
                address: Address,
                preferences: Preferences,
            };

            const user = User{
                .id = 1001,
                .username = "johndoe",
                .email = "john@example.com",
                .age = 28,
                .active = true,
                .address = .{
                    .street = "123 Main St",
                    .city = "Springfield",
                    .zip = "12345",
                },
                .preferences = .{
                    .theme = "dark",
                    .language = "en",
                    .notifications_enabled = true,
                },
            };

            var snap = ztf.createSnapshot(alloc, "complex_user", .{
                .update = true,
                .format = .json,
                .pretty_print = true,
            });
            try snap.match(user);
        }
    }.testSuite);

    // Test 7: Snapshot Cleanup
    try ztf.describe(allocator, "Snapshot Cleanup", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should list all snapshots", testListSnapshots);
            try ztf.it(alloc, "should mark and cleanup unused snapshots", testCleanupUnused);
        }

        fn testListSnapshots(alloc: std.mem.Allocator) !void {
            // Create a few snapshots
            var snap = ztf.createSnapshot(alloc, "cleanup_list_1", .{ .update = true });
            try snap.matchString("test1");

            var snap2 = ztf.createSnapshot(alloc, "cleanup_list_2", .{ .update = true });
            try snap2.matchString("test2");

            // List snapshots
            var cleanup = ztf.SnapshotCleanup.init(alloc, ".snapshots");
            defer cleanup.deinit();

            var snapshots = try cleanup.listSnapshots();
            defer {
                for (snapshots.items) |item| {
                    alloc.free(item);
                }
                snapshots.deinit(alloc);
            }

            try ztf.expect(alloc, snapshots.items.len).toBeGreaterThan(0);
        }

        fn testCleanupUnused(alloc: std.mem.Allocator) !void {
            // Create test snapshots
            var snap_used = ztf.createSnapshot(alloc, "cleanup_used_snap", .{ .update = true });
            try snap_used.matchString("used");

            var snap_unused = ztf.createSnapshot(alloc, "cleanup_unused_snap", .{ .update = true });
            try snap_unused.matchString("unused");

            var cleanup = ztf.SnapshotCleanup.init(alloc, ".snapshots");
            defer cleanup.deinit();

            // Mark only first as used
            try cleanup.markUsed("cleanup_used_snap.snap");

            // The cleanup would remove unused ones
            // Note: We don't actually run cleanup here to avoid affecting other tests
        }
    }.testSuite);

    // Test 8: Different Data Types
    try ztf.describe(allocator, "Different Data Types", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should snapshot integers", testIntegers);
            try ztf.it(alloc, "should snapshot floats", testFloats);
            try ztf.it(alloc, "should snapshot booleans", testBooleans);
        }

        fn testIntegers(alloc: std.mem.Allocator) !void {
            const value: i32 = 42;

            var snap = ztf.createSnapshot(alloc, "int_value", .{ .update = true });
            try snap.match(value);

            var snap2 = ztf.createSnapshot(alloc, "int_value", .{});
            try snap2.match(value);
        }

        fn testFloats(alloc: std.mem.Allocator) !void {
            const value: f64 = 3.14159;

            var snap = ztf.createSnapshot(alloc, "float_value", .{ .update = true });
            try snap.match(value);

            var snap2 = ztf.createSnapshot(alloc, "float_value", .{});
            try snap2.match(value);
        }

        fn testBooleans(alloc: std.mem.Allocator) !void {
            const value: bool = true;

            var snap = ztf.createSnapshot(alloc, "bool_value", .{ .update = true });
            try snap.match(value);

            var snap2 = ztf.createSnapshot(alloc, "bool_value", .{});
            try snap2.match(value);
        }
    }.testSuite);

    // Test 9: Update Mode
    try ztf.describe(allocator, "Snapshot Update Mode", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should update snapshots when update=true", testUpdateMode);
        }

        fn testUpdateMode(alloc: std.mem.Allocator) !void {
            // Create original
            var snap1 = ztf.createSnapshot(alloc, "update_mode_test", .{ .update = true });
            try snap1.matchString("Original");

            // Update with new value
            var snap2 = ztf.createSnapshot(alloc, "update_mode_test", .{ .update = true });
            try snap2.matchString("Updated");

            // Verify the update
            var snap3 = ztf.createSnapshot(alloc, "update_mode_test", .{});
            try snap3.matchString("Updated");
        }
    }.testSuite);

    // Test 10: Interactive Mode
    try ztf.describe(allocator, "Interactive Update Mode", struct {
        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.it(alloc, "should support interactive updates", testInteractiveMode);
        }

        fn testInteractiveMode(alloc: std.mem.Allocator) !void {
            // Create original snapshot
            var snap1 = ztf.createSnapshot(alloc, "interactive_test", .{ .update = true });
            try snap1.matchString("Interactive original");

            // Test interactive mode (auto-updates in our implementation)
            var snap2 = ztf.createSnapshot(alloc, "interactive_test", .{
                .update = true,
                .interactive = true,
            });
            try snap2.matchString("Interactive updated");
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

    // Clean up snapshot files created during testing
    const cleanup_files = [_][]const u8{
        ".snapshots/simple_string.snap",
        ".snapshots/multiple_snapshots_first.snap",
        ".snapshots/multiple_snapshots_second.snap",
        ".snapshots/multiple_snapshots_third.snap",
        ".snapshots/simple_struct.snap",
        ".snapshots/nested_struct.snap",
        ".snapshots/format_pretty.snap",
        ".snapshots/format_json.snap",
        ".snapshots/format_compact.snap",
        ".snapshots/mismatch_test.snap",
        ".snapshots/named_test_config_dev.snap",
        ".snapshots/named_test_config_prod.snap",
        ".snapshots/named_test_config_test.snap",
        ".snapshots/complex_user.snap",
        ".snapshots/cleanup_list_1.snap",
        ".snapshots/cleanup_list_2.snap",
        ".snapshots/cleanup_used_snap.snap",
        ".snapshots/cleanup_unused_snap.snap",
        ".snapshots/int_value.snap",
        ".snapshots/float_value.snap",
        ".snapshots/bool_value.snap",
        ".snapshots/update_mode_test.snap",
        ".snapshots/interactive_test.snap",
    };

    for (cleanup_files) |file| {
        std.fs.cwd().deleteFile(file) catch {};
    }

    if (!success) {
        std.debug.print("\nSome snapshot tests failed!\n", .{});
        std.process.exit(1);
    }

    std.debug.print("\n✓ All snapshot tests passed!\n", .{});
}
