const std = @import("std");
const lib = @import("lib.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse CLI arguments
    var cli_parser = lib.CLI.init(allocator);
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    try cli_parser.parse(args);

    // Handle special flags
    if (cli_parser.options.help) {
        cli_parser.printHelp();
        return;
    }

    if (cli_parser.options.version) {
        cli_parser.printVersion();
        return;
    }

    // Get the test registry
    var registry = lib.getRegistry(allocator);
    defer registry.deinit();

    // Create test runner with CLI options
    const runner_options = cli_parser.toRunnerOptions();
    var runner = lib.TestRunner.init(allocator, registry, runner_options);
    defer runner.deinit();

    // Run tests
    const all_passed = runner.run() catch |err| {
        switch (err) {
            lib.test_runner.RunnerError.NoTestsFound => {
                std.debug.print("\nNo tests found!\n", .{});
                std.debug.print("Make sure to:\n", .{});
                std.debug.print("  1. Register tests using describe() and it()\n", .{});
                std.debug.print("  2. Import and call your test setup code\n", .{});
                std.process.exit(1);
            },
            else => return err,
        }
    };

    // Exit with appropriate code
    if (all_passed) {
        std.process.exit(0);
    } else {
        std.process.exit(1);
    }
}
