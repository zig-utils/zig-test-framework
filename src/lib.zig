const std = @import("std");

// Core modules
pub const assertions = @import("assertions.zig");
pub const suite = @import("suite.zig");
pub const test_runner = @import("test_runner.zig");
pub const reporter = @import("reporter.zig");
pub const matchers = @import("matchers.zig");
pub const mock = @import("mock.zig");
pub const cli = @import("cli.zig");
pub const discovery = @import("discovery.zig");
pub const test_loader = @import("test_loader.zig");
pub const coverage = @import("coverage.zig");
pub const parallel = @import("parallel.zig");
pub const ui_server = @import("ui_server.zig");
pub const test_history = @import("test_history.zig");
pub const snapshot = @import("snapshot.zig");
pub const watch = @import("watch.zig");
pub const memory_profiler = @import("memory_profiler.zig");
pub const config = @import("config.zig");
pub const async_support = @import("async_support.zig");
pub const async_test = @import("async_test.zig");
pub const timeout = @import("timeout.zig");

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

// Async test management
pub const itAsync = suite.itAsync;
pub const itAsyncTimeout = suite.itAsyncTimeout;
pub const itAsyncSkip = suite.itAsyncSkip;
pub const itAsyncOnly = suite.itAsyncOnly;

// Timeout management
pub const itTimeout = suite.itTimeout;
pub const describeTimeout = suite.describeTimeout;

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
pub const TAPReporter = reporter.TAPReporter;
pub const JUnitReporter = reporter.JUnitReporter;
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

// Test Discovery
pub const DiscoveryOptions = discovery.DiscoveryOptions;
pub const DiscoveryResult = discovery.DiscoveryResult;
pub const TestFile = discovery.TestFile;
pub const discoverTests = discovery.discoverTests;

// Test Loader
pub const LoaderOptions = test_loader.LoaderOptions;
pub const runDiscoveredTests = test_loader.runDiscoveredTests;

// Coverage
pub const CoverageOptions = coverage.CoverageOptions;
pub const CoverageResult = coverage.CoverageResult;
pub const CoverageTool = coverage.CoverageTool;
pub const runWithCoverage = coverage.runWithCoverage;
pub const runTestWithCoverage = coverage.runTestWithCoverage;
pub const parseCoverageReport = coverage.parseCoverageReport;
pub const printCoverageSummary = coverage.printCoverageSummary;
pub const isCoverageToolAvailable = coverage.isCoverageToolAvailable;

// Parallel Execution
pub const ParallelOptions = parallel.ParallelOptions;
pub const runTestsParallel = parallel.runTestsParallel;

// UI Server
pub const UIServer = ui_server.UIServer;
pub const UIServerOptions = ui_server.UIServerOptions;
pub const UIReporter = ui_server.UIReporter;
pub const MultiReporter = ui_server.MultiReporter;

// Test History
pub const TestHistory = test_history.TestHistory;
pub const HistoryEntry = test_history.HistoryEntry;
pub const TestRecord = test_history.TestRecord;

// Snapshot Testing
pub const Snapshot = snapshot.Snapshot;
pub const SnapshotOptions = snapshot.SnapshotOptions;
pub const SnapshotFormat = snapshot.SnapshotFormat;
pub const SnapshotDiff = snapshot.SnapshotDiff;
pub const DiffEntry = snapshot.DiffEntry;
pub const InlineSnapshot = snapshot.InlineSnapshot;
pub const SnapshotCleanup = snapshot.SnapshotCleanup;
pub const createSnapshot = snapshot.snapshot;

// Watch Mode
pub const TestWatcher = watch.TestWatcher;
pub const WatchOptions = watch.WatchOptions;
pub const FileWatcher = watch.FileWatcher;

// Memory Profiling
pub const MemoryProfiler = memory_profiler.MemoryProfiler;
pub const MemoryStats = memory_profiler.MemoryStats;
pub const ProfilingAllocator = memory_profiler.ProfilingAllocator;
pub const ProfileOptions = memory_profiler.ProfileOptions;

// Configuration
pub const TestConfig = config.TestConfig;
pub const ConfigLoader = config.ConfigLoader;
pub const ConfigFormat = config.ConfigFormat;

// Async Support
pub const Future = async_support.Future;
pub const Promise = async_support.Promise;
pub const AsyncExecutor = async_support.AsyncExecutor;
pub const runAsync = async_support.runAsync;
pub const asyncDelay = async_support.delay;

// Async Test Support
pub const AsyncTestExecutor = async_test.AsyncTestExecutor;
pub const AsyncTestContext = async_test.AsyncTestContext;
pub const AsyncTestResult = async_test.AsyncTestResult;
pub const AsyncHooksManager = async_test.AsyncHooksManager;
pub const AsyncOptions = async_test.AsyncOptions;
pub const AsyncStatus = async_test.AsyncStatus;
pub const AsyncStats = async_test.AsyncStats;

// Timeout Support
pub const TimeoutContext = timeout.TimeoutContext;
pub const TimeoutEnforcer = timeout.TimeoutEnforcer;
pub const TimeoutConfig = timeout.TimeoutConfig;
pub const GlobalTimeoutConfig = timeout.GlobalTimeoutConfig;
pub const TimeoutStatus = timeout.TimeoutStatus;
pub const TimeoutResult = timeout.TimeoutResult;
pub const SuiteTimeoutTracker = timeout.SuiteTimeoutTracker;

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
