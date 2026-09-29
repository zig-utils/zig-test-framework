const std = @import("std");
const ztf = @import("zig_test_framework");

fn passingTest(_: std.mem.Allocator) !void {}

test "reporter spec output" {
    var buffer: [2048]u8 = undefined;
    const writer: std.Io.Writer = .fixed(&buffer);
    var reporter = ztf.SpecReporter.init(std.testing.allocator, writer);
    reporter.reporter.use_colors = false;
    var results = ztf.TestResults.init(std.testing.allocator);
    defer results.deinit();
    results.total = 1;
    results.passed = 1;
    var test_case = ztf.TestCase.init("passes", passingTest);
    test_case.status = .passed;

    try reporter.reporter.onRunStart(1);
    try reporter.reporter.onSuiteStart("suite");
    try reporter.reporter.onTestEnd(&test_case);
    try reporter.reporter.onSuiteEnd("suite");
    try reporter.reporter.onRunEnd(&results);

    const output = buffer[0..reporter.writer.end];
    try std.testing.expect(std.mem.indexOf(u8, output, "Running 1 test(s)") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Passed:  1") != null);
}

test "reporter dot output" {
    var buffer: [1024]u8 = undefined;
    const writer: std.Io.Writer = .fixed(&buffer);
    var reporter = ztf.DotReporter.init(std.testing.allocator, writer);
    reporter.reporter.use_colors = false;
    var results = ztf.TestResults.init(std.testing.allocator);
    defer results.deinit();
    results.total = 1;
    results.passed = 1;
    var test_case = ztf.TestCase.init("passes", passingTest);
    test_case.status = .passed;

    try reporter.reporter.onRunStart(1);
    try reporter.reporter.onTestEnd(&test_case);
    try reporter.reporter.onRunEnd(&results);

    const output = buffer[0..reporter.writer.end];
    try std.testing.expect(std.mem.indexOf(u8, output, ".") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Passed: 1") != null);
}

test "reporter json output" {
    var buffer: [2048]u8 = undefined;
    const writer: std.Io.Writer = .fixed(&buffer);
    var reporter = ztf.JsonReporter.init(std.testing.allocator, writer);
    defer reporter.deinit();
    var results = ztf.TestResults.init(std.testing.allocator);
    defer results.deinit();
    results.total = 1;
    results.passed = 1;
    var test_case = ztf.TestCase.init("passes", passingTest);
    test_case.status = .passed;

    try reporter.reporter.onRunStart(1);
    try reporter.reporter.onSuiteStart("suite");
    try reporter.reporter.onTestEnd(&test_case);
    try reporter.reporter.onSuiteEnd("suite");
    try reporter.reporter.onRunEnd(&results);

    const output = buffer[0..reporter.writer.end];
    try std.testing.expect(std.mem.indexOf(u8, output, "\"name\":\"passes\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"passed\":1") != null);
}

test "reporter set selects the same built-ins for every executor" {
    var buffer: [1024]u8 = undefined;
    const writer: std.Io.Writer = .fixed(&buffer);
    var reporters = ztf.ReporterSet.init(
        std.testing.allocator,
        writer,
        .tap,
        "test-results.xml",
        false,
    );
    defer reporters.deinit();

    try std.testing.expect(reporters.selected() == &reporters.tap.reporter);
    try std.testing.expect(!reporters.selected().use_colors);
}
