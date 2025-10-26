const std = @import("std");

// Core modules
pub const assertions = @import("assertions.zig");
pub const suite = @import("suite.zig");
pub const test_runner = @import("test_runner.zig");
pub const reporter = @import("reporter.zig");
pub const matchers = @import("matchers.zig");
pub const mock = @import("mock.zig");
pub const cli = @import("cli.zig");

// Re-export commonly used types and functions
pub const expect = assertions.expect;
pub const Expectation = assertions.Expectation;
pub const StringExpectation = assertions.StringExpectation;
pub const SliceExpectation = assertions.SliceExpectation;
pub const AssertionError = assertions.AssertionError;

// Suite management
pub const describe = suite.describe;
pub const it = suite.it;
pub const test_ = suite.test_;
pub const beforeEach = suite.beforeEach;
pub const afterEach = suite.afterEach;
pub const beforeAll = suite.beforeAll;
pub const afterAll = suite.afterAll;
pub const describeSkip = suite.describeSkip;
pub const describeOnly = suite.describeOnly;
pub const itSkip = suite.itSkip;
pub const itOnly = suite.itOnly;

pub const TestSuite = suite.TestSuite;
pub const TestCase = suite.TestCase;
pub const TestStatus = suite.TestStatus;
pub const TestRegistry = suite.TestRegistry;
pub const TestFn = suite.TestFn;
pub const HookFn = suite.HookFn;

// Test runner
pub const TestRunner = test_runner.TestRunner;
pub const RunnerOptions = test_runner.RunnerOptions;
pub const ReporterType = test_runner.ReporterType;
pub const runTests = test_runner.runTests;
pub const runTestsWithOptions = test_runner.runTestsWithOptions;

// Reporters
pub const Reporter = reporter.Reporter;
pub const TestResults = reporter.TestResults;
pub const SpecReporter = reporter.SpecReporter;
pub const DotReporter = reporter.DotReporter;
pub const JsonReporter = reporter.JsonReporter;
pub const Colors = reporter.Colors;

// Matchers
pub const Matchers = matchers.Matchers;
pub const StructMatcher = matchers.StructMatcher;
pub const ArrayMatcher = matchers.ArrayMatcher;
pub const expectStruct = matchers.expectStruct;
pub const expectArray = matchers.expectArray;
pub const toBeCloseTo = matchers.Matchers.toBeCloseTo;
pub const toBeNaN = matchers.Matchers.toBeNaN;
pub const toBeInfinite = matchers.Matchers.toBeInfinite;

// Mocking
pub const Mock = mock.Mock;
pub const Spy = mock.Spy;
pub const createMock = mock.createMock;
pub const createSpy = mock.createSpy;
pub const CallRecord = mock.CallRecord;

// CLI
pub const CLI = cli.CLI;
pub const CLIOptions = cli.CLIOptions;

// Utility to get the test registry
pub fn getRegistry(allocator: std.mem.Allocator) *TestRegistry {
    return suite.getRegistry(allocator);
}

// Utility to clean up the test registry
pub fn cleanupRegistry() void {
    suite.cleanupRegistry();
}

test "import all modules" {
    std.testing.refAllDecls(@This());
}
