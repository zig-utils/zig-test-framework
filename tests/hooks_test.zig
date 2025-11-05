const std = @import("std");
const ztf = @import("zig-test-framework");

// Global state to track hook execution
var hook_execution_log: std.ArrayList([]const u8) = undefined;
var allocator_global: std.mem.Allocator = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    allocator_global = allocator;
    hook_execution_log = .empty;
    defer hook_execution_log.deinit(allocator);

    // Test 1: Basic beforeEach and afterEach
    try ztf.describe(allocator, "beforeEach and afterEach hooks", struct {
        var setup_count: i32 = 0;
        var teardown_count: i32 = 0;

        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.beforeEach(alloc, beforeHook);
            try ztf.afterEach(alloc, afterHook);

            try ztf.it(alloc, "should run beforeEach before test 1", test1);
            try ztf.it(alloc, "should run beforeEach before test 2", test2);
            try ztf.it(alloc, "should run beforeEach before test 3", test3);
        }

        fn beforeHook(alloc: std.mem.Allocator) !void {
            _ = alloc;
            setup_count += 1;
        }

        fn afterHook(alloc: std.mem.Allocator) !void {
            _ = alloc;
            teardown_count += 1;
        }

        fn test1(alloc: std.mem.Allocator) !void {
            try ztf.expect(alloc, setup_count).toBe(1);
            try ztf.expect(alloc, teardown_count).toBe(0);
        }

        fn test2(alloc: std.mem.Allocator) !void {
            try ztf.expect(alloc, setup_count).toBe(2);
            try ztf.expect(alloc, teardown_count).toBe(1);
        }

        fn test3(alloc: std.mem.Allocator) !void {
            try ztf.expect(alloc, setup_count).toBe(3);
            try ztf.expect(alloc, teardown_count).toBe(2);
        }
    }.testSuite);

    // Test 2: Basic beforeAll and afterAll
    try ztf.describe(allocator, "beforeAll and afterAll hooks", struct {
        var initialized: bool = false;
        var test_count: i32 = 0;
        var cleanup_called: bool = false;

        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.beforeAll(alloc, setupAll);
            try ztf.afterAll(alloc, teardownAll);

            try ztf.it(alloc, "should have initialized before all tests", test1);
            try ztf.it(alloc, "should still be initialized", test2);
            try ztf.it(alloc, "cleanup should not have run yet", test3);
        }

        fn setupAll(alloc: std.mem.Allocator) !void {
            _ = alloc;
            initialized = true;
        }

        fn teardownAll(alloc: std.mem.Allocator) !void {
            _ = alloc;
            cleanup_called = true;
        }

        fn test1(alloc: std.mem.Allocator) !void {
            try ztf.expect(alloc, initialized).toBe(true);
            test_count += 1;
        }

        fn test2(alloc: std.mem.Allocator) !void {
            try ztf.expect(alloc, initialized).toBe(true);
            try ztf.expect(alloc, test_count).toBe(1);
            test_count += 1;
        }

        fn test3(alloc: std.mem.Allocator) !void {
            try ztf.expect(alloc, initialized).toBe(true);
            try ztf.expect(alloc, test_count).toBe(2);
            try ztf.expect(alloc, cleanup_called).toBe(false);
        }
    }.testSuite);

    // Test 3: Nested hooks
    try ztf.describe(allocator, "Nested describe blocks with hooks", struct {
        var outer_before_count: i32 = 0;
        var inner_before_count: i32 = 0;
        var outer_after_count: i32 = 0;
        var inner_after_count: i32 = 0;

        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.beforeEach(alloc, outerBefore);
            try ztf.afterEach(alloc, outerAfter);

            try ztf.it(alloc, "outer test runs outer hooks", outerTest);

            try ztf.describe(alloc, "Inner describe", struct {
                fn innerSuite(inner_alloc: std.mem.Allocator) !void {
                    try ztf.beforeEach(inner_alloc, innerBefore);
                    try ztf.afterEach(inner_alloc, innerAfter);

                    try ztf.it(inner_alloc, "inner test runs both hooks", innerTest);
                }

                fn innerBefore(inner_alloc: std.mem.Allocator) !void {
                    _ = inner_alloc;
                    inner_before_count += 1;
                }

                fn innerAfter(inner_alloc: std.mem.Allocator) !void {
                    _ = inner_alloc;
                    inner_after_count += 1;
                }

                fn innerTest(inner_alloc: std.mem.Allocator) !void {
                    // Outer beforeEach runs first, then inner beforeEach
                    try ztf.expect(inner_alloc, outer_before_count).toBe(2); // 1 from outer test + 1 from this test
                    try ztf.expect(inner_alloc, inner_before_count).toBe(1);
                    // After hooks haven't run yet
                    try ztf.expect(inner_alloc, inner_after_count).toBe(0);
                }
            }.innerSuite);
        }

        fn outerBefore(alloc: std.mem.Allocator) !void {
            _ = alloc;
            outer_before_count += 1;
        }

        fn outerAfter(alloc: std.mem.Allocator) !void {
            _ = alloc;
            outer_after_count += 1;
        }

        fn outerTest(alloc: std.mem.Allocator) !void {
            try ztf.expect(alloc, outer_before_count).toBe(1);
            try ztf.expect(alloc, inner_before_count).toBe(0);
        }
    }.testSuite);

    // Test 4: Multiple hooks of same type
    try ztf.describe(allocator, "Multiple hooks of same type", struct {
        var call_order: [10]i32 = undefined;
        var call_index: usize = 0;

        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.beforeEach(alloc, before1);
            try ztf.beforeEach(alloc, before2);
            try ztf.beforeEach(alloc, before3);

            try ztf.afterEach(alloc, after1);
            try ztf.afterEach(alloc, after2);

            try ztf.it(alloc, "should run all beforeEach hooks in order", testOrder);
        }

        fn before1(alloc: std.mem.Allocator) !void {
            _ = alloc;
            call_order[call_index] = 1;
            call_index += 1;
        }

        fn before2(alloc: std.mem.Allocator) !void {
            _ = alloc;
            call_order[call_index] = 2;
            call_index += 1;
        }

        fn before3(alloc: std.mem.Allocator) !void {
            _ = alloc;
            call_order[call_index] = 3;
            call_index += 1;
        }

        fn after1(alloc: std.mem.Allocator) !void {
            _ = alloc;
            call_order[call_index] = 4;
            call_index += 1;
        }

        fn after2(alloc: std.mem.Allocator) !void {
            _ = alloc;
            call_order[call_index] = 5;
            call_index += 1;
        }

        fn testOrder(alloc: std.mem.Allocator) !void {
            // Before hooks should have run in order: 1, 2, 3
            try ztf.expect(alloc, call_order[0]).toBe(1);
            try ztf.expect(alloc, call_order[1]).toBe(2);
            try ztf.expect(alloc, call_order[2]).toBe(3);
        }
    }.testSuite);

    // Test 5: Hook error handling
    try ztf.describe(allocator, "Hook error handling", struct {
        var test_ran: bool = false;

        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.beforeEach(alloc, failingBefore);
            try ztf.it(alloc, "this test should be skipped due to beforeEach failure", testThatShouldntRun);
        }

        fn failingBefore(alloc: std.mem.Allocator) !void {
            _ = alloc;
            return error.BeforeEachFailed;
        }

        fn testThatShouldntRun(alloc: std.mem.Allocator) !void {
            _ = alloc;
            test_ran = true;
        }
    }.testSuite);

    // Test 6: Async setup/teardown pattern
    try ztf.describe(allocator, "Async-style setup and teardown", struct {
        var resource_allocated: bool = false;
        var resource_freed: bool = false;

        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.beforeAll(alloc, allocateResource);
            try ztf.afterAll(alloc, freeResource);

            try ztf.beforeEach(alloc, resetState);
            try ztf.afterEach(alloc, cleanupState);

            try ztf.it(alloc, "should have allocated resource", test1);
            try ztf.it(alloc, "should still have allocated resource", test2);
        }

        fn allocateResource(alloc: std.mem.Allocator) !void {
            _ = alloc;
            resource_allocated = true;
        }

        fn freeResource(alloc: std.mem.Allocator) !void {
            _ = alloc;
            resource_freed = true;
        }

        fn resetState(alloc: std.mem.Allocator) !void {
            _ = alloc;
            // Reset per-test state
        }

        fn cleanupState(alloc: std.mem.Allocator) !void {
            _ = alloc;
            // Cleanup per-test state
        }

        fn test1(alloc: std.mem.Allocator) !void {
            try ztf.expect(alloc, resource_allocated).toBe(true);
            try ztf.expect(alloc, resource_freed).toBe(false);
        }

        fn test2(alloc: std.mem.Allocator) !void {
            try ztf.expect(alloc, resource_allocated).toBe(true);
            try ztf.expect(alloc, resource_freed).toBe(false);
        }
    }.testSuite);

    // Test 7: Real-world database simulation
    try ztf.describe(allocator, "Database connection simulation", struct {
        const Connection = struct {
            id: u32,
            active: bool,
        };

        var db_initialized: bool = false;
        var connection_pool: [5]?Connection = undefined;
        var next_connection_id: u32 = 0;
        var current_connection: ?*Connection = null;

        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.beforeAll(alloc, initializeDatabase);
            try ztf.afterAll(alloc, shutdownDatabase);

            try ztf.beforeEach(alloc, getConnection);
            try ztf.afterEach(alloc, releaseConnection);

            try ztf.it(alloc, "should execute query with active connection", testQuery);
            try ztf.it(alloc, "should execute another query", testQuery2);
        }

        fn initializeDatabase(alloc: std.mem.Allocator) !void {
            _ = alloc;
            db_initialized = true;
            for (&connection_pool) |*conn| {
                conn.* = null;
            }
        }

        fn shutdownDatabase(alloc: std.mem.Allocator) !void {
            _ = alloc;
            db_initialized = false;
        }

        fn getConnection(alloc: std.mem.Allocator) !void {
            _ = alloc;
            const conn = Connection{
                .id = next_connection_id,
                .active = true,
            };
            next_connection_id += 1;
            connection_pool[0] = conn;
            current_connection = &connection_pool[0].?;
        }

        fn releaseConnection(alloc: std.mem.Allocator) !void {
            _ = alloc;
            if (current_connection) |conn| {
                conn.active = false;
            }
            current_connection = null;
        }

        fn testQuery(alloc: std.mem.Allocator) !void {
            try ztf.expect(alloc, db_initialized).toBe(true);
            try ztf.expect(alloc, current_connection != null).toBe(true);
            if (current_connection) |conn| {
                try ztf.expect(alloc, conn.active).toBe(true);
            }
        }

        fn testQuery2(alloc: std.mem.Allocator) !void {
            try ztf.expect(alloc, db_initialized).toBe(true);
            try ztf.expect(alloc, current_connection != null).toBe(true);
        }
    }.testSuite);

    // Test 8: File I/O simulation
    try ztf.describe(allocator, "File operations with hooks", struct {
        var temp_file_created: bool = false;
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
            temp_file_created = true;
        }

        fn cleanupTempDirectory(alloc: std.mem.Allocator) !void {
            _ = alloc;
            temp_file_created = false;
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
            try ztf.expect(alloc, temp_file_created).toBe(true);
        }

        fn testRead(alloc: std.mem.Allocator) !void {
            try ztf.expect(alloc, file_handle != null).toBe(true);
            try ztf.expect(alloc, temp_file_created).toBe(true);
        }
    }.testSuite);

    // Test 9: Triple nested describes with hooks
    try ztf.describe(allocator, "Level 1", struct {
        var level1_setup: i32 = 0;

        fn testSuite(alloc: std.mem.Allocator) !void {
            try ztf.beforeAll(alloc, setupLevel1);
            try ztf.beforeEach(alloc, beforeLevel1);

            try ztf.it(alloc, "level 1 test", testLevel1);

            try ztf.describe(alloc, "Level 2", struct {
                var level2_setup: i32 = 0;

                fn level2Suite(alloc2: std.mem.Allocator) !void {
                    try ztf.beforeAll(alloc2, setupLevel2);
                    try ztf.beforeEach(alloc2, beforeLevel2);

                    try ztf.it(alloc2, "level 2 test", testLevel2);

                    try ztf.describe(alloc2, "Level 3", struct {
                        fn level3Suite(alloc3: std.mem.Allocator) !void {
                            try ztf.beforeEach(alloc3, beforeLevel3);

                            try ztf.it(alloc3, "level 3 test", testLevel3);
                        }

                        fn beforeLevel3(alloc3: std.mem.Allocator) !void {
                            _ = alloc3;
                        }

                        fn testLevel3(alloc3: std.mem.Allocator) !void {
                            // All three beforeEach hooks should have run
                            try ztf.expect(alloc3, level1_setup).toBeGreaterThan(0);
                            try ztf.expect(alloc3, level2_setup).toBeGreaterThan(0);
                        }
                    }.level3Suite);
                }

                fn setupLevel2(alloc2: std.mem.Allocator) !void {
                    _ = alloc2;
                    level2_setup = 1;
                }

                fn beforeLevel2(alloc2: std.mem.Allocator) !void {
                    _ = alloc2;
                    level2_setup += 1;
                }

                fn testLevel2(alloc2: std.mem.Allocator) !void {
                    try ztf.expect(alloc2, level1_setup).toBeGreaterThan(0);
                    try ztf.expect(alloc2, level2_setup).toBeGreaterThan(0);
                }
            }.level2Suite);
        }

        fn setupLevel1(alloc: std.mem.Allocator) !void {
            _ = alloc;
            level1_setup = 1;
        }

        fn beforeLevel1(alloc: std.mem.Allocator) !void {
            _ = alloc;
            level1_setup += 1;
        }

        fn testLevel1(alloc: std.mem.Allocator) !void {
            try ztf.expect(alloc, level1_setup).toBeGreaterThan(0);
        }
    }.testSuite);

    // Run all tests
    std.debug.print("Starting hooks tests...\n", .{});
    const registry = ztf.getRegistry(allocator);
    std.debug.print("Registry has {d} suites\n", .{registry.root_suites.items.len});

    const success = try ztf.runTestsWithOptions(allocator, registry, .{
        .reporter_type = .spec,
        .use_colors = false,
    });

    // Clean up
    ztf.cleanupRegistry();

    std.debug.print("Test result: success={}\n", .{success});

    if (!success) {
        std.debug.print("\nSome hook tests failed!\n", .{});
        std.process.exit(1);
    }

    std.debug.print("\n✓ All lifecycle hook tests passed!\n", .{});
}
