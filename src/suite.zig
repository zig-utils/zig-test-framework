const std = @import("std");

pub const TestError = error{
    TestFailed,
    TestSkipped,
    SetupFailed,
    TeardownFailed,
};

/// Test function type
pub const TestFn = *const fn (allocator: std.mem.Allocator) anyerror!void;

/// Hook function type
pub const HookFn = *const fn (allocator: std.mem.Allocator) anyerror!void;

/// Test status
pub const TestStatus = enum {
    pending,
    running,
    passed,
    failed,
    skipped,
};

/// Individual test case
pub const TestCase = struct {
    name: []const u8,
    test_fn: TestFn,
    status: TestStatus = .pending,
    error_message: ?[]const u8 = null,
    execution_time_ns: u64 = 0,
    skip: bool = false,
    only: bool = false,
    file: []const u8 = "",
    line: u32 = 0,

    pub fn init(name: []const u8, test_fn: TestFn) TestCase {
        return TestCase{
            .name = name,
            .test_fn = test_fn,
        };
    }
};

/// Test suite (describe block)
pub const TestSuite = struct {
    name: []const u8,
    tests: std.ArrayList(TestCase),
    suites: std.ArrayList(*TestSuite),
    before_each_hooks: std.ArrayList(HookFn),
    after_each_hooks: std.ArrayList(HookFn),
    before_all_hooks: std.ArrayList(HookFn),
    after_all_hooks: std.ArrayList(HookFn),
    allocator: std.mem.Allocator,
    skip: bool = false,
    only: bool = false,
    parent: ?*TestSuite = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, name: []const u8) !*Self {
        const suite = try allocator.create(Self);
        suite.* = Self{
            .name = name,
            .tests = .empty,
            .suites = .empty,
            .before_each_hooks = .empty,
            .after_each_hooks = .empty,
            .before_all_hooks = .empty,
            .after_all_hooks = .empty,
            .allocator = allocator,
        };
        return suite;
    }

    pub fn deinit(self: *Self) void {
        for (self.suites.items) |suite| {
            suite.deinit();
        }
        self.tests.deinit(self.allocator);
        self.suites.deinit(self.allocator);
        self.before_each_hooks.deinit(self.allocator);
        self.after_each_hooks.deinit(self.allocator);
        self.before_all_hooks.deinit(self.allocator);
        self.after_all_hooks.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    /// Add a test to this suite
    pub fn addTest(self: *Self, test_case: TestCase) !void {
        try self.tests.append(self.allocator, test_case);
    }

    /// Add a nested suite
    pub fn addSuite(self: *Self, suite: *TestSuite) !void {
        suite.parent = self;
        try self.suites.append(self.allocator, suite);
    }

    /// Add a beforeEach hook
    pub fn addBeforeEach(self: *Self, hook: HookFn) !void {
        try self.before_each_hooks.append(self.allocator, hook);
    }

    /// Add an afterEach hook
    pub fn addAfterEach(self: *Self, hook: HookFn) !void {
        try self.after_each_hooks.append(self.allocator, hook);
    }

    /// Add a beforeAll hook
    pub fn addBeforeAll(self: *Self, hook: HookFn) !void {
        try self.before_all_hooks.append(self.allocator, hook);
    }

    /// Add an afterAll hook
    pub fn addAfterAll(self: *Self, hook: HookFn) !void {
        try self.after_all_hooks.append(self.allocator, hook);
    }

    /// Get all beforeEach hooks including parent hooks
    pub fn getAllBeforeEachHooks(self: *Self, allocator: std.mem.Allocator) !std.ArrayList(HookFn) {
        var hooks: std.ArrayList(HookFn) = .empty;

        // Collect parent hooks first (they run before child hooks)
        if (self.parent) |parent| {
            var parent_hooks = try parent.getAllBeforeEachHooks(allocator);
            defer parent_hooks.deinit(allocator);
            try hooks.appendSlice(allocator, parent_hooks.items);
        }

        // Add this suite's hooks
        try hooks.appendSlice(allocator, self.before_each_hooks.items);

        return hooks;
    }

    /// Get all afterEach hooks including parent hooks
    pub fn getAllAfterEachHooks(self: *Self, allocator: std.mem.Allocator) !std.ArrayList(HookFn) {
        var hooks: std.ArrayList(HookFn) = .empty;

        // Add this suite's hooks first
        try hooks.appendSlice(allocator, self.after_each_hooks.items);

        // Collect parent hooks last (they run after child hooks)
        if (self.parent) |parent| {
            var parent_hooks = try parent.getAllAfterEachHooks(allocator);
            defer parent_hooks.deinit(allocator);
            try hooks.appendSlice(allocator, parent_hooks.items);
        }

        return hooks;
    }

    /// Run all beforeAll hooks
    pub fn runBeforeAllHooks(self: *Self, allocator: std.mem.Allocator) !void {
        for (self.before_all_hooks.items) |hook| {
            try hook(allocator);
        }
    }

    /// Run all afterAll hooks
    pub fn runAfterAllHooks(self: *Self, allocator: std.mem.Allocator) !void {
        for (self.after_all_hooks.items) |hook| {
            try hook(allocator);
        }
    }

    /// Check if this suite should be skipped
    pub fn shouldSkip(self: *Self) bool {
        if (self.skip) return true;
        if (self.parent) |parent| {
            return parent.shouldSkip();
        }
        return false;
    }

    /// Check if only this suite (or a parent) is marked as only
    pub fn hasOnly(self: *Self) bool {
        if (self.only) return true;
        if (self.parent) |parent| {
            return parent.hasOnly();
        }
        return false;
    }

    /// Count total tests in this suite and nested suites
    pub fn countTests(self: *Self) usize {
        var count: usize = self.tests.items.len;
        for (self.suites.items) |suite| {
            count += suite.countTests();
        }
        return count;
    }
};

/// Global test registry
pub const TestRegistry = struct {
    root_suites: std.ArrayList(*TestSuite),
    current_suite: ?*TestSuite = null,
    allocator: std.mem.Allocator,
    has_only: bool = false,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .root_suites = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.root_suites.items) |suite| {
            suite.deinit();
        }
        self.root_suites.deinit(self.allocator);
    }

    /// Register a new suite
    pub fn registerSuite(self: *Self, suite: *TestSuite) !void {
        if (self.current_suite) |current| {
            try current.addSuite(suite);
        } else {
            try self.root_suites.append(self.allocator, suite);
        }
        if (suite.only) {
            self.has_only = true;
        }
    }

    /// Register a test in the current suite
    pub fn registerTest(self: *Self, test_case: TestCase) !void {
        if (self.current_suite) |current| {
            try current.addTest(test_case);
        } else {
            // If no current suite, create a default one
            const default_suite = try TestSuite.init(self.allocator, "default");
            try default_suite.addTest(test_case);
            try self.root_suites.append(self.allocator, default_suite);
        }
        if (test_case.only) {
            self.has_only = true;
        }
    }

    /// Count total tests across all suites
    pub fn countAllTests(self: *Self) usize {
        var count: usize = 0;
        for (self.root_suites.items) |suite| {
            count += suite.countTests();
        }
        return count;
    }
};

/// Global test registry instance
var global_registry: ?TestRegistry = null;

/// Get the global test registry
pub fn getRegistry(allocator: std.mem.Allocator) *TestRegistry {
    if (global_registry == null) {
        global_registry = TestRegistry.init(allocator);
    }
    return &global_registry.?;
}

/// Clean up the global test registry
pub fn cleanupRegistry() void {
    if (global_registry) |*registry| {
        registry.deinit();
        global_registry = null;
    }
}

/// Helper to create a test suite (describe)
pub fn describe(allocator: std.mem.Allocator, name: []const u8, func: anytype) !void {
    const registry = getRegistry(allocator);
    const suite = try TestSuite.init(allocator, name);

    const previous_suite = registry.current_suite;
    registry.current_suite = suite;

    // Execute the describe block
    try func(allocator);

    registry.current_suite = previous_suite;
    try registry.registerSuite(suite);
}

/// Helper to create a test case (it/test)
pub fn it(allocator: std.mem.Allocator, name: []const u8, test_fn: TestFn) !void {
    const registry = getRegistry(allocator);
    const test_case = TestCase.init(name, test_fn);
    try registry.registerTest(test_case);
}

/// Alias for it
pub const test_ = it;

/// Skip a describe block
pub fn describeSkip(allocator: std.mem.Allocator, name: []const u8, func: anytype) !void {
    const registry = getRegistry(allocator);
    const suite = try TestSuite.init(allocator, name);
    suite.skip = true;

    const previous_suite = registry.current_suite;
    registry.current_suite = suite;

    try func(allocator);

    registry.current_suite = previous_suite;
    try registry.registerSuite(suite);
}

/// Only run this describe block
pub fn describeOnly(allocator: std.mem.Allocator, name: []const u8, func: anytype) !void {
    const registry = getRegistry(allocator);
    const suite = try TestSuite.init(allocator, name);
    suite.only = true;

    const previous_suite = registry.current_suite;
    registry.current_suite = suite;

    try func(allocator);

    registry.current_suite = previous_suite;
    try registry.registerSuite(suite);
}

/// Skip a test
pub fn itSkip(allocator: std.mem.Allocator, name: []const u8, test_fn: TestFn) !void {
    const registry = getRegistry(allocator);
    var test_case = TestCase.init(name, test_fn);
    test_case.skip = true;
    try registry.registerTest(test_case);
}

/// Only run this test
pub fn itOnly(allocator: std.mem.Allocator, name: []const u8, test_fn: TestFn) !void {
    const registry = getRegistry(allocator);
    var test_case = TestCase.init(name, test_fn);
    test_case.only = true;
    try registry.registerTest(test_case);
}

/// Add beforeEach hook
pub fn beforeEach(allocator: std.mem.Allocator, hook: HookFn) !void {
    const registry = getRegistry(allocator);
    if (registry.current_suite) |suite| {
        try suite.addBeforeEach(hook);
    }
}

/// Add afterEach hook
pub fn afterEach(allocator: std.mem.Allocator, hook: HookFn) !void {
    const registry = getRegistry(allocator);
    if (registry.current_suite) |suite| {
        try suite.addAfterEach(hook);
    }
}

/// Add beforeAll hook
pub fn beforeAll(allocator: std.mem.Allocator, hook: HookFn) !void {
    const registry = getRegistry(allocator);
    if (registry.current_suite) |suite| {
        try suite.addBeforeAll(hook);
    }
}

/// Add afterAll hook
pub fn afterAll(allocator: std.mem.Allocator, hook: HookFn) !void {
    const registry = getRegistry(allocator);
    if (registry.current_suite) |suite| {
        try suite.addAfterAll(hook);
    }
}

// Tests
test "TestStatus enum values" {
    const pending_status = TestStatus.pending;
    const running_status = TestStatus.running;
    const passed_status = TestStatus.passed;
    const failed_status = TestStatus.failed;
    const skipped_status = TestStatus.skipped;

    try std.testing.expect(pending_status == .pending);
    try std.testing.expect(running_status == .running);
    try std.testing.expect(passed_status == .passed);
    try std.testing.expect(failed_status == .failed);
    try std.testing.expect(skipped_status == .skipped);
}

test "TestCase creation" {
    const allocator = std.testing.allocator;

    const name_duped = try allocator.dupe(u8, "test case");
    defer allocator.free(name_duped);

    const test_case = TestCase{
        .name = name_duped,
        .test_fn = undefined,
        .status = .pending,
        .skip = false,
        .only = false,
        .error_message = null,
    };

    try std.testing.expectEqualStrings("test case", test_case.name);
    try std.testing.expect(test_case.status == .pending);
    try std.testing.expect(!test_case.skip);
    try std.testing.expect(!test_case.only);
}

test "TestSuite creation and cleanup" {
    const allocator = std.testing.allocator;

    var suite = try TestSuite.init(allocator, "Test Suite");
    defer suite.deinit();

    try std.testing.expectEqualStrings("Test Suite", suite.name);
    try std.testing.expect(!suite.skip);
    try std.testing.expect(!suite.only);
    try std.testing.expectEqual(@as(usize, 0), suite.tests.items.len);
    try std.testing.expectEqual(@as(usize, 0), suite.suites.items.len);
}

test "TestRegistry cleanup" {
    // Verify cleanup doesn't crash
    cleanupRegistry();
}
