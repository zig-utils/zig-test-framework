const std = @import("std");
const discovery = @import("discovery.zig");
const reporter = @import("reporter.zig");
const suite = @import("suite.zig");

pub const PlanOrigin = enum {
    registered,
    discovered,
};

pub const RegisteredTest = struct {
    test_suite: *suite.TestSuite,
    test_case: *suite.TestCase,
};

pub const PlanItem = union(PlanOrigin) {
    registered: RegisteredTest,
    discovered: *const discovery.TestFile,

    pub fn identity(self: PlanItem) []const u8 {
        return switch (self) {
            .registered => |item| item.test_case.name,
            .discovered => |file| file.relative_path,
        };
    }
};

/// Executor-neutral plan produced by registration or file discovery.
pub const TestPlan = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(PlanItem) = .empty,

    pub fn init(allocator: std.mem.Allocator) TestPlan {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *TestPlan) void {
        self.items.deinit(self.allocator);
    }

    pub fn fromRegistry(
        allocator: std.mem.Allocator,
        registry: *suite.TestRegistry,
    ) !TestPlan {
        var plan = TestPlan.init(allocator);
        errdefer plan.deinit();
        for (registry.root_suites.items) |test_suite| {
            try plan.appendSuite(test_suite);
        }
        return plan;
    }

    pub fn fromDiscovery(
        allocator: std.mem.Allocator,
        discovered: *const discovery.DiscoveryResult,
    ) !TestPlan {
        var plan = TestPlan.init(allocator);
        errdefer plan.deinit();
        for (discovered.files.items) |*file| {
            try plan.appendDiscovered(file);
        }
        return plan;
    }

    pub fn appendDiscovered(self: *TestPlan, file: *const discovery.TestFile) !void {
        try self.items.append(self.allocator, .{ .discovered = file });
    }

    fn appendSuite(self: *TestPlan, test_suite: *suite.TestSuite) !void {
        for (test_suite.tests.items) |*test_case| {
            try self.items.append(self.allocator, .{ .registered = .{
                .test_suite = test_suite,
                .test_case = test_case,
            } });
        }
        for (test_suite.suites.items) |nested| {
            try self.appendSuite(nested);
        }
    }
};

/// Shared execution policy. Executors apply it at their natural granularity:
/// registered test names or filters forwarded to an external Zig test process.
pub const ExecutionPolicy = struct {
    bail: bool = false,
    filter: ?[]const u8 = null,
    timeout_ms: ?u64 = null,

    pub fn matches(self: ExecutionPolicy, name: []const u8) bool {
        const filter = self.filter orelse return true;
        return std.mem.indexOf(u8, name, filter) != null;
    }

    pub fn shouldStop(self: ExecutionPolicy, results: *const reporter.TestResults) bool {
        return self.bail and results.failed > 0;
    }

    pub fn timedOut(self: ExecutionPolicy, execution_time_ns: u64) bool {
        const timeout_ms = self.timeout_ms orelse return false;
        return execution_time_ns > timeout_ms * std.time.ns_per_ms;
    }
};

pub const LifecycleEvent = union(enum) {
    run_started: usize,
    run_finished: *reporter.TestResults,
    suite_started: []const u8,
    suite_finished: []const u8,
    test_started: []const u8,
    test_finished: *const suite.TestCase,
};

/// Routes the typed lifecycle shared by every executor into existing reporter
/// callbacks. Additional consumers can be added without changing executors.
pub const EventStream = struct {
    rep: *reporter.Reporter,

    pub fn emit(self: EventStream, event: LifecycleEvent) !void {
        switch (event) {
            .run_started => |total| try self.rep.onRunStart(total),
            .run_finished => |results| try self.rep.onRunEnd(results),
            .suite_started => |name| try self.rep.onSuiteStart(name),
            .suite_finished => |name| try self.rep.onSuiteEnd(name),
            .test_started => |name| try self.rep.onTestStart(name),
            .test_finished => |test_case| try self.rep.onTestEnd(test_case),
        }
    }
};

fn passingTest(_: std.mem.Allocator) !void {}

test "registered and discovered inputs produce one plan model" {
    const allocator = std.testing.allocator;

    var registry = suite.TestRegistry.init(allocator);
    defer registry.deinit();
    const test_suite = try suite.TestSuite.init(allocator, "unit");
    try test_suite.addTest(suite.TestCase.init("passes", passingTest));
    try registry.registerSuite(test_suite);

    var registered = try TestPlan.fromRegistry(allocator, &registry);
    defer registered.deinit();
    try std.testing.expectEqual(@as(usize, 1), registered.items.items.len);
    try std.testing.expectEqualStrings("passes", registered.items.items[0].identity());

    var discovered = discovery.DiscoveryResult.init(allocator);
    defer discovered.deinit();
    try discovered.addFile("tests/sample.test.zig", "sample.test.zig", "sample.test.zig");

    var external = try TestPlan.fromDiscovery(allocator, &discovered);
    defer external.deinit();
    try std.testing.expectEqual(@as(usize, 1), external.items.items.len);
    try std.testing.expectEqualStrings("sample.test.zig", external.items.items[0].identity());
}

test "execution policy shares matching and bail semantics" {
    const policy = ExecutionPolicy{ .bail = true, .filter = "selected", .timeout_ms = 500 };
    try std.testing.expect(policy.matches("selected test"));
    try std.testing.expect(!policy.matches("other test"));
    try std.testing.expectEqual(@as(?u64, 500), policy.timeout_ms);
    try std.testing.expect(!policy.timedOut(499 * std.time.ns_per_ms));
    try std.testing.expect(policy.timedOut(501 * std.time.ns_per_ms));

    var results = reporter.TestResults.init(std.testing.allocator);
    defer results.deinit();
    try std.testing.expect(!policy.shouldStop(&results));
    results.failed = 1;
    try std.testing.expect(policy.shouldStop(&results));
}
