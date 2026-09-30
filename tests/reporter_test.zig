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

test "reporter json output uses versioned event envelopes" {
    var buffer: [4096]u8 = undefined;
    const writer: std.Io.Writer = .fixed(&buffer);
    var reporter = ztf.JsonReporter.init(std.testing.allocator, writer);
    defer reporter.deinit();
    var results = ztf.TestResults.init(std.testing.allocator);
    defer results.deinit();
    results.total = 1;
    results.passed = 1;
    results.random_seed = 4242;
    reporter.reporter.random_seed = 4242;
    var test_case = ztf.TestCase.init("passes \"quoted\"\nname", passingTest);
    test_case.status = .passed;

    try reporter.reporter.onRunStart(1);
    try reporter.reporter.onSuiteStart("suite\tone");
    try reporter.reporter.onTestStart(test_case.name);
    try reporter.reporter.onTestEnd(&test_case);
    try reporter.reporter.onSuiteEnd("suite\tone");
    try reporter.reporter.onRunEnd(&results);

    const output = buffer[0..reporter.writer.end];
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, output, .{});
    defer parsed.deinit();
    const events = parsed.value.array.items;
    try std.testing.expectEqual(@as(usize, 6), events.len);
    try std.testing.expectEqual(@as(i64, ztf.protocol_version), events[0].object.get("protocol_version").?.integer);
    try std.testing.expectEqualStrings("run_start", events[0].object.get("type").?.string);
    try std.testing.expectEqual(@as(i64, 4242), events[0].object.get("data").?.object.get("random_seed").?.integer);
    try std.testing.expectEqualStrings("test_start", events[2].object.get("type").?.string);
    const test_data = events[3].object.get("data").?.object;
    try std.testing.expectEqualStrings(test_case.name, test_data.get("name").?.string);
    try std.testing.expectEqualStrings("suite\tone", test_data.get("suite").?.string);
    try std.testing.expectEqualStrings("run_end", events[5].object.get("type").?.string);
    try std.testing.expectEqual(@as(i64, 1), events[5].object.get("data").?.object.get("passed").?.integer);
    try std.testing.expectEqual(@as(i64, 4242), events[5].object.get("data").?.object.get("random_seed").?.integer);
}

test "reporter json output includes flaky attempt history" {
    const allocator = std.testing.allocator;
    var buffer: [4096]u8 = undefined;
    const writer: std.Io.Writer = .fixed(&buffer);
    var reporter = ztf.JsonReporter.init(allocator, writer);
    defer reporter.deinit();
    var results = ztf.TestResults.init(allocator);
    defer results.deinit();
    results.total = 1;
    results.flaky = 1;
    var test_case = ztf.TestCase.init("eventually passes", passingTest);
    defer test_case.attempts.deinit(allocator);
    test_case.status = .flaky;
    try test_case.attempts.append(allocator, .{
        .number = 1,
        .repetition = 1,
        .status = .failed,
        .duration_ns = 10,
    });
    try test_case.attempts.append(allocator, .{
        .number = 2,
        .repetition = 1,
        .status = .passed,
        .duration_ns = 5,
    });

    try reporter.reporter.onRunStart(1);
    try reporter.reporter.onSuiteStart("suite");
    try reporter.reporter.onTestEnd(&test_case);
    try reporter.reporter.onSuiteEnd("suite");
    try reporter.reporter.onRunEnd(&results);

    const output = buffer[0..reporter.writer.end];
    try std.testing.expect(std.mem.indexOf(u8, output, "\"status\":\"flaky\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"type\":\"retry\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"duration_ns\":10") != null);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, output, .{});
    defer parsed.deinit();
    const events = parsed.value.array.items;
    try std.testing.expectEqualStrings("retry", events[2].object.get("type").?.string);
    try std.testing.expectEqualStrings("retry", events[3].object.get("type").?.string);
    try std.testing.expectEqualStrings("test_end", events[4].object.get("type").?.string);
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

test "JUnit reporter records the random seed as a suite property" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const output_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/results.xml", .{tmp.sub_path});
    defer allocator.free(output_path);

    var reporter = ztf.JUnitReporter.init(allocator, output_path);
    defer reporter.deinit();
    reporter.reporter.random_seed = 73;
    var results = ztf.TestResults.init(allocator);
    defer results.deinit();
    results.total = 1;
    results.passed = 1;
    results.random_seed = 73;
    var test_case = ztf.TestCase.init("passes", passingTest);
    test_case.status = .passed;

    try reporter.reporter.onRunStart(1);
    try reporter.reporter.onSuiteStart("suite");
    try reporter.reporter.onTestEnd(&test_case);
    try reporter.reporter.onSuiteEnd("suite");
    try reporter.reporter.onRunEnd(&results);

    const output = try ztf.compat.readFileAlloc(allocator, output_path);
    defer allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "<property name=\"random_seed\" value=\"73\"/>") != null);
}
