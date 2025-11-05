const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create the main library module
    const lib_module = b.addModule("zig-test-framework", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
    });

    // Create the test runner executable
    const exe = b.addExecutable(.{
        .name = "zig-test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the test framework");
    run_step.dependOn(&run_cmd.step);

    // Unit tests for the framework itself
    const lib_unit_tests = b.addTest(.{
        .root_module = lib_module,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    // Test runner tests
    const test_runner_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/test_runner_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_test_runner_tests = b.addRunArtifact(test_runner_tests);

    // Assertions tests
    const assertions_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/assertions_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_assertions_tests = b.addRunArtifact(assertions_tests);

    // Suite tests
    const suite_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/suite_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_suite_tests = b.addRunArtifact(suite_tests);

    // Matchers tests
    const matchers_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/matchers_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_matchers_tests = b.addRunArtifact(matchers_tests);

    // Hooks tests (executable, not unit test)
    const hooks_tests = b.addExecutable(.{
        .name = "hooks_test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/hooks_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig-test-framework", .module = lib_module },
            },
        }),
    });
    b.installArtifact(hooks_tests);
    const run_hooks_tests = b.addRunArtifact(hooks_tests);
    const hooks_step = b.step("test-hooks", "Run lifecycle hooks tests");
    hooks_step.dependOn(&run_hooks_tests.step);

    // Reporter tests
    const reporter_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/reporter_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_reporter_tests = b.addRunArtifact(reporter_tests);

    // CLI tests
    const cli_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/cli_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_cli_tests = b.addRunArtifact(cli_tests);

    // Filter tests
    const filter_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/filter_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_filter_tests = b.addRunArtifact(filter_tests);

    // Mock tests
    const mock_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/mock_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_mock_tests = b.addRunArtifact(mock_tests);

    // Comprehensive mock tests (executable)
    const comprehensive_mock_tests = b.addExecutable(.{
        .name = "comprehensive_mock_test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/comprehensive_mock_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig-test-framework", .module = lib_module },
            },
        }),
    });
    b.installArtifact(comprehensive_mock_tests);
    const run_comprehensive_mock_tests = b.addRunArtifact(comprehensive_mock_tests);
    const comprehensive_mock_step = b.step("test-mocks", "Run comprehensive mock tests");
    comprehensive_mock_step.dependOn(&run_comprehensive_mock_tests.step);

    // Snapshot usage tests (executable)
    const snapshot_usage_tests = b.addExecutable(.{
        .name = "snapshot_usage_test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/snapshot_usage_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig-test-framework", .module = lib_module },
            },
        }),
    });
    b.installArtifact(snapshot_usage_tests);
    const run_snapshot_usage_tests = b.addRunArtifact(snapshot_usage_tests);
    const snapshot_usage_step = b.step("test-snapshots", "Run snapshot usage tests");
    snapshot_usage_step.dependOn(&run_snapshot_usage_tests.step);

    // Time mocking tests (executable)
    const time_tests = b.addExecutable(.{
        .name = "time_test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/time_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig-test-framework", .module = lib_module },
            },
        }),
    });
    b.installArtifact(time_tests);
    const run_time_tests = b.addRunArtifact(time_tests);
    const time_step = b.step("test-time", "Run time mocking tests");
    time_step.dependOn(&run_time_tests.step);

    // Create test step that runs all tests
    const test_step = b.step("test", "Run all unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_test_runner_tests.step);
    test_step.dependOn(&run_assertions_tests.step);
    test_step.dependOn(&run_suite_tests.step);
    test_step.dependOn(&run_matchers_tests.step);
    // Note: hooks_test is an executable, run with 'zig build test-hooks'
    test_step.dependOn(&run_reporter_tests.step);
    test_step.dependOn(&run_cli_tests.step);
    test_step.dependOn(&run_filter_tests.step);
    test_step.dependOn(&run_mock_tests.step);

    // Examples
    const basic_example = b.addExecutable(.{
        .name = "basic_example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/basic_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig-test-framework", .module = lib_module },
            },
        }),
    });

    const advanced_example = b.addExecutable(.{
        .name = "advanced_example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/advanced_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zig-test-framework", .module = lib_module },
            },
        }),
    });

    const run_basic_example = b.addRunArtifact(basic_example);
    const run_advanced_example = b.addRunArtifact(advanced_example);

    const examples_step = b.step("examples", "Run all examples");
    examples_step.dependOn(&run_basic_example.step);
    examples_step.dependOn(&run_advanced_example.step);
}
