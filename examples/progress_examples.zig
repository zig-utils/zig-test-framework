const std = @import("std");
const zig_test = @import("zig-test");

/// Example 1: Basic Spinner
pub fn example_basic_spinner() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("\n=== Example 1: Basic Spinner ===\n", .{});

    var spinner = try zig_test.Spinner.init(allocator, "Loading data...", .dots);
    defer spinner.deinit();

    try spinner.start();
    std.Thread.sleep(2000 * std.time.ns_per_ms);
    spinner.succeed("Data loaded successfully");
}

/// Example 2: Different Spinner Styles
pub fn example_spinner_styles() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("\n=== Example 2: Spinner Styles ===\n", .{});

    const styles = [_]zig_test.SpinnerStyle{
        .dots,
        .line,
        .arc,
        .circle,
        .square,
        .arrow,
        .bounce,
    };

    inline for (styles) |style| {
        const style_name = @tagName(style);
        const message = try std.fmt.allocPrint(allocator, "Testing {s} spinner...", .{style_name});
        defer allocator.free(message);

        var spinner = try zig_test.Spinner.init(allocator, message, style);
        defer spinner.deinit();

        try spinner.start();
        std.Thread.sleep(1000 * std.time.ns_per_ms);
        spinner.succeed(try std.fmt.allocPrint(allocator, "{s} style complete", .{style_name}));
        allocator.free(try std.fmt.allocPrint(allocator, "{s} style complete", .{style_name}));
    }
}

/// Example 3: Spinner with different outcomes
pub fn example_spinner_outcomes() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("\n=== Example 3: Spinner Outcomes ===\n", .{});

    // Success
    var spinner1 = try zig_test.Spinner.init(allocator, "Operation 1...", .dots);
    defer spinner1.deinit();
    try spinner1.start();
    std.Thread.sleep(500 * std.time.ns_per_ms);
    spinner1.succeed("Operation 1 succeeded");

    // Failure
    var spinner2 = try zig_test.Spinner.init(allocator, "Operation 2...", .dots);
    defer spinner2.deinit();
    try spinner2.start();
    std.Thread.sleep(500 * std.time.ns_per_ms);
    spinner2.fail("Operation 2 failed");

    // Warning
    var spinner3 = try zig_test.Spinner.init(allocator, "Operation 3...", .dots);
    defer spinner3.deinit();
    try spinner3.start();
    std.Thread.sleep(500 * std.time.ns_per_ms);
    spinner3.warn("Operation 3 has warnings");

    // Info
    var spinner4 = try zig_test.Spinner.init(allocator, "Operation 4...", .dots);
    defer spinner4.deinit();
    try spinner4.start();
    std.Thread.sleep(500 * std.time.ns_per_ms);
    spinner4.info("Operation 4 information");
}

/// Example 4: Basic Progress Bar
pub fn example_basic_progress_bar() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("\n=== Example 4: Basic Progress Bar ===\n", .{});

    var bar = try zig_test.ProgressBar.init(allocator, 100, .{
        .message = "Processing",
        .width = 40,
    });
    defer bar.deinit();

    var i: usize = 0;
    while (i <= 100) : (i += 5) {
        bar.update(i);
        std.Thread.sleep(100 * std.time.ns_per_ms);
    }
    bar.finish();
}

/// Example 5: Progress Bar Styles
pub fn example_progress_bar_styles() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("\n=== Example 5: Progress Bar Styles ===\n", .{});

    const styles = [_]zig_test.ProgressBarStyle{
        .classic,
        .blocks,
        .arrows,
        .dots,
    };

    inline for (styles) |style| {
        const style_name = @tagName(style);
        const message = try std.fmt.allocPrint(allocator, "{s} style", .{style_name});
        defer allocator.free(message);

        var bar = try zig_test.ProgressBar.init(allocator, 50, .{
            .message = message,
            .style = style,
            .width = 30,
        });
        defer bar.deinit();

        var i: usize = 0;
        while (i <= 50) : (i += 5) {
            bar.update(i);
            std.Thread.sleep(50 * std.time.ns_per_ms);
        }
        bar.finish();
    }
}

/// Example 6: Progress Bar with Custom Options
pub fn example_progress_bar_options() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("\n=== Example 6: Progress Bar Options ===\n", .{});

    // Without percentage
    var bar1 = try zig_test.ProgressBar.init(allocator, 50, .{
        .message = "No percentage",
        .show_percentage = false,
    });
    defer bar1.deinit();

    var i: usize = 0;
    while (i <= 50) : (i += 10) {
        bar1.update(i);
        std.Thread.sleep(100 * std.time.ns_per_ms);
    }
    bar1.finish();

    // Without count
    var bar2 = try zig_test.ProgressBar.init(allocator, 50, .{
        .message = "No count",
        .show_count = false,
    });
    defer bar2.deinit();

    i = 0;
    while (i <= 50) : (i += 10) {
        bar2.update(i);
        std.Thread.sleep(100 * std.time.ns_per_ms);
    }
    bar2.finish();

    // Minimal
    var bar3 = try zig_test.ProgressBar.init(allocator, 50, .{
        .message = "Minimal",
        .show_percentage = false,
        .show_count = false,
    });
    defer bar3.deinit();

    i = 0;
    while (i <= 50) : (i += 10) {
        bar3.update(i);
        std.Thread.sleep(100 * std.time.ns_per_ms);
    }
    bar3.finish();
}

/// Example 7: Test Progress Tracker
pub fn example_test_progress() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("\n=== Example 7: Test Progress Tracker ===\n", .{});

    var progress = try zig_test.TestProgress.init(allocator, 10, .{
        .use_spinner = true,
        .use_progress_bar = true,
    });
    defer progress.deinit();

    // Simulate running 10 tests
    const test_names = [_][]const u8{
        "test_addition",
        "test_subtraction",
        "test_multiplication",
        "test_division",
        "test_modulo",
        "test_power",
        "test_square_root",
        "test_absolute",
        "test_min",
        "test_max",
    };

    for (test_names, 0..) |name, i| {
        try progress.startTest(name);
        std.Thread.sleep(200 * std.time.ns_per_ms);

        // Simulate different outcomes
        const passed = i != 3; // Fail the 4th test
        const skipped = i == 5; // Skip the 6th test
        progress.completeTest(passed, skipped);
    }

    progress.printSummary();
}

/// Example 8: Test Progress without Visual Indicators
pub fn example_test_progress_minimal() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("\n=== Example 8: Minimal Test Progress ===\n", .{});

    var progress = try zig_test.TestProgress.init(allocator, 5, .{
        .use_spinner = false,
        .use_progress_bar = false,
    });
    defer progress.deinit();

    var i: usize = 0;
    while (i < 5) : (i += 1) {
        const name = try std.fmt.allocPrint(allocator, "test_{d}", .{i});
        defer allocator.free(name);

        try progress.startTest(name);
        std.Thread.sleep(100 * std.time.ns_per_ms);
        progress.completeTest(true, false);
    }

    progress.printSummary();
}

/// Example 9: Multi-Spinner for Parallel Operations
pub fn example_multi_spinner() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("\n=== Example 9: Multi-Spinner ===\n", .{});

    var multi = zig_test.MultiSpinner.init(allocator);
    defer multi.deinit();

    // Add multiple spinners
    try multi.add("task1", "Processing task 1...");
    try multi.add("task2", "Processing task 2...");
    try multi.add("task3", "Processing task 3...");

    std.Thread.sleep(1000 * std.time.ns_per_ms);

    // Complete tasks at different times
    multi.succeed("task1", "Task 1 complete");
    std.Thread.sleep(500 * std.time.ns_per_ms);

    multi.fail("task2", "Task 2 failed");
    std.Thread.sleep(500 * std.time.ns_per_ms);

    multi.succeed("task3", "Task 3 complete");
}

/// Example 10: Progress Bar with Increment
pub fn example_progress_increment() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("\n=== Example 10: Progress Bar Increment ===\n", .{});

    var bar = try zig_test.ProgressBar.init(allocator, 20, .{
        .message = "Incremental progress",
    });
    defer bar.deinit();

    var i: usize = 0;
    while (i < 20) : (i += 1) {
        bar.increment();
        std.Thread.sleep(100 * std.time.ns_per_ms);
    }
    bar.finish();
}

/// Example 11: Long Running Operation with Spinner Update
pub fn example_spinner_update() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("\n=== Example 11: Spinner with Updates ===\n", .{});

    var spinner = try zig_test.Spinner.init(allocator, "Step 1: Initializing...", .dots);
    defer spinner.deinit();

    try spinner.start();
    std.Thread.sleep(1000 * std.time.ns_per_ms);

    try spinner.updateMessage("Step 2: Processing data...");
    std.Thread.sleep(1000 * std.time.ns_per_ms);

    try spinner.updateMessage("Step 3: Finalizing...");
    std.Thread.sleep(1000 * std.time.ns_per_ms);

    spinner.succeed("All steps completed");
}

/// Example 12: Combined Progress Indicators
pub fn example_combined_progress() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("\n=== Example 12: Combined Indicators ===\n", .{});

    // Use spinner for overall operation
    var spinner = try zig_test.Spinner.init(allocator, "Starting batch process...", .dots);
    defer spinner.deinit();
    try spinner.start();
    std.Thread.sleep(500 * std.time.ns_per_ms);
    spinner.stop();

    // Use progress bar for sub-tasks
    var bar = try zig_test.ProgressBar.init(allocator, 100, .{
        .message = "Batch processing",
    });
    defer bar.deinit();

    var i: usize = 0;
    while (i <= 100) : (i += 10) {
        bar.update(i);
        std.Thread.sleep(200 * std.time.ns_per_ms);
    }
    bar.finish();

    // Final success
    var final_spinner = try zig_test.Spinner.init(allocator, "Completing...", .dots);
    defer final_spinner.deinit();
    try final_spinner.start();
    std.Thread.sleep(500 * std.time.ns_per_ms);
    final_spinner.succeed("Batch process completed successfully");
}

pub fn main() !void {
    try example_basic_spinner();
    try example_spinner_styles();
    try example_spinner_outcomes();
    try example_basic_progress_bar();
    try example_progress_bar_styles();
    try example_progress_bar_options();
    try example_test_progress();
    try example_test_progress_minimal();
    try example_multi_spinner();
    try example_progress_increment();
    try example_spinner_update();
    try example_combined_progress();

    std.debug.print("\n=== All Progress Examples Complete! ===\n", .{});
}
