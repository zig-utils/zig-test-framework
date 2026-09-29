const std = @import("std");
const manifest_source = @embedFile("build.zig.zon");
const package_version = manifestVersion(manifest_source);

fn manifestVersion(source: []const u8) []const u8 {
    const marker = ".version = \"";
    const marker_start = std.mem.indexOf(u8, source, marker) orelse
        @compileError("build.zig.zon must declare .version");
    const start = marker_start + marker.len;
    const end_offset = std.mem.indexOfScalar(u8, source[start..], '"') orelse
        @compileError("build.zig.zon contains an unterminated .version");
    return source[start .. start + end_offset];
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "version", package_version);

    // Create the main library module
    const lib_module = b.addModule("zig_test_framework", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .link_libc = true,
    });
    lib_module.addOptions("build_options", build_options);

    // Create the test runner executable
    const exe = b.addExecutable(.{
        .name = "zig-test",
        .version = std.SemanticVersion.parse(package_version) catch
            @panic("build.zig.zon contains an invalid semantic version"),
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "zig_test_framework", .module = lib_module },
            },
        }),
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    run_cmd.addPassthruArgs();

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
            .link_libc = true,
            .imports = &.{
                .{ .name = "zig_test_framework", .module = lib_module },
            },
        }),
    });
    const run_test_runner_tests = b.addRunArtifact(test_runner_tests);

    // Assertions tests
    const assertions_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/assertions_test.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "zig_test_framework", .module = lib_module },
            },
        }),
    });
    const run_assertions_tests = b.addRunArtifact(assertions_tests);

    // Suite tests
    const suite_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/suite_test.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "zig_test_framework", .module = lib_module },
            },
        }),
    });
    const run_suite_tests = b.addRunArtifact(suite_tests);

    // Matchers tests
    const matchers_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/matchers_test.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "zig_test_framework", .module = lib_module },
            },
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
            .link_libc = true,
            .imports = &.{
                .{ .name = "zig_test_framework", .module = lib_module },
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
            .link_libc = true,
            .imports = &.{
                .{ .name = "zig_test_framework", .module = lib_module },
            },
        }),
    });
    const run_reporter_tests = b.addRunArtifact(reporter_tests);

    // CLI tests
    const cli_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/cli_test.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "zig_test_framework", .module = lib_module },
            },
        }),
    });
    const run_cli_tests = b.addRunArtifact(cli_tests);

    // Filter tests
    const filter_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/filter_test.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "zig_test_framework", .module = lib_module },
            },
        }),
    });
    const run_filter_tests = b.addRunArtifact(filter_tests);

    // Mock tests
    const mock_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/mock_test.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "zig_test_framework", .module = lib_module },
            },
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
            .link_libc = true,
            .imports = &.{
                .{ .name = "zig_test_framework", .module = lib_module },
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
            .link_libc = true,
            .imports = &.{
                .{ .name = "zig_test_framework", .module = lib_module },
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
            .link_libc = true,
            .imports = &.{
                .{ .name = "zig_test_framework", .module = lib_module },
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
    test_step.dependOn(&run_hooks_tests.step);
    test_step.dependOn(&run_reporter_tests.step);
    test_step.dependOn(&run_cli_tests.step);
    test_step.dependOn(&run_filter_tests.step);
    test_step.dependOn(&run_mock_tests.step);
    test_step.dependOn(&run_comprehensive_mock_tests.step);
    test_step.dependOn(&run_snapshot_usage_tests.step);
    test_step.dependOn(&run_time_tests.step);

    // Exercise configuration through the real CLI. The second invocation
    // proves that an explicit CLI filter overrides the configured filter.
    const run_config_fixture = b.addRunArtifact(exe);
    run_config_fixture.addArgs(&.{ "--config", "tests/fixtures/zig-test.json" });
    test_step.dependOn(&run_config_fixture.step);

    const run_config_override = b.addRunArtifact(exe);
    run_config_override.addArgs(&.{ "--config", "tests/fixtures/zig-test.json", "--filter", "unselected test fails" });
    run_config_override.expectExitCode(1);
    test_step.dependOn(&run_config_override.step);

    const run_invalid_config = b.addRunArtifact(exe);
    run_invalid_config.addArgs(&.{ "--config", "tests/fixtures/invalid-zig-test.json" });
    run_invalid_config.expectExitCode(2);
    test_step.dependOn(&run_invalid_config.step);

    // Exercise both sides of a file-level shard split. One shard runs the
    // fixture and the other is intentionally empty; both are valid CI jobs.
    const run_shard_one = b.addRunArtifact(exe);
    run_shard_one.addArgs(&.{ "--test-dir", "tests", "--pattern", "sample.test.zig", "--shard-index", "1", "--shard-count", "2", "--no-color" });
    test_step.dependOn(&run_shard_one.step);

    const run_shard_two = b.addRunArtifact(exe);
    run_shard_two.addArgs(&.{ "--test-dir", "tests", "--pattern", "sample.test.zig", "--shard-index", "2", "--shard-count", "2", "--no-color" });
    test_step.dependOn(&run_shard_two.step);

    const run_discovery_tap = b.addRunArtifact(exe);
    run_discovery_tap.addArgs(&.{ "--test-dir", "tests", "--pattern", "sample.test.zig", "--reporter", "tap", "--no-color" });
    run_discovery_tap.expectStdOutEqual(
        "TAP version 14\n1..1\n# Subtest: sample.test.zig\nok 1 - sample.test.zig\n",
    );
    test_step.dependOn(&run_discovery_tap.step);

    const run_version = b.addRunArtifact(exe);
    run_version.addArg("--version");
    run_version.expectStdErrEqual(b.fmt("Zig Test Framework v{s}\n", .{package_version}));
    test_step.dependOn(&run_version.step);

    // Examples
    const basic_example = b.addExecutable(.{
        .name = "basic_example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/basic_test.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "zig_test_framework", .module = lib_module },
            },
        }),
    });

    const advanced_example = b.addExecutable(.{
        .name = "advanced_example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/advanced_test.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "zig_test_framework", .module = lib_module },
            },
        }),
    });

    const run_basic_example = b.addRunArtifact(basic_example);
    const run_advanced_example = b.addRunArtifact(advanced_example);

    // These showcase intentionally slow, interactive, or failure-oriented
    // scenarios, so keep them compile-only while still checking every example.
    const async_examples = b.addExecutable(.{
        .name = "async_examples",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/async_tests.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "zig_test", .module = lib_module },
            },
        }),
    });

    const snapshot_examples = b.addExecutable(.{
        .name = "snapshot_examples",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/snapshot_examples.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "zig_test", .module = lib_module },
            },
        }),
    });

    const progress_examples = b.addExecutable(.{
        .name = "progress_examples",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/progress_examples.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "zig_test", .module = lib_module },
            },
        }),
    });

    const timeout_examples = b.addExecutable(.{
        .name = "timeout_examples",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/timeout_examples.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{
                .{ .name = "zig_test", .module = lib_module },
            },
        }),
    });

    const examples_step = b.step("examples", "Run core examples and compile all examples");
    examples_step.dependOn(&run_basic_example.step);
    examples_step.dependOn(&run_advanced_example.step);
    examples_step.dependOn(&async_examples.step);
    examples_step.dependOn(&snapshot_examples.step);
    examples_step.dependOn(&progress_examples.step);
    examples_step.dependOn(&timeout_examples.step);
}
