const std = @import("std");

/// Configuration file format
pub const ConfigFormat = enum {
    json,
    toml, // Future support
};

/// Test framework configuration
pub const TestConfig = struct {
    // Test discovery options
    test_options: TestOptions = .{},

    /// Parallel execution options
    parallel: ParallelOptions = .{},

    /// Reporter options
    reporter: ReporterOptions = .{},

    /// Snapshot testing options
    snapshot: SnapshotOptions = .{},

    /// Watch mode options
    watch: WatchOptions = .{},

    /// Memory profiling options
    memory: MemoryOptions = .{},

    /// UI server options
    ui: UIOptions = .{},

    /// Coverage options
    coverage: CoverageOptions = .{},
};

pub const TestOptions = struct {
    /// Test file pattern
    pattern: []const u8 = "*.test.zig",
    /// Test directory
    test_dir: []const u8 = "src",
    /// Recursive search
    recursive: bool = true,
    /// Filter tests by name
    filter: ?[]const u8 = null,
    /// Timeout per test in milliseconds
    timeout: u64 = 5000,
};

pub const ParallelOptions = struct {
    /// Enable parallel execution
    enabled: bool = false,
    /// Number of worker threads (0 = auto-detect)
    jobs: usize = 0,
};

pub const ReporterOptions = struct {
    /// Reporter type: spec, dot, json, tap, junit
    reporter: []const u8 = "spec",
    /// JUnit XML output file
    junit_output: ?[]const u8 = null,
    /// Verbose output
    verbose: bool = false,
};

pub const SnapshotOptions = struct {
    /// Snapshot directory
    snapshot_dir: []const u8 = ".snapshots",
    /// Update snapshots
    update: bool = false,
    /// Pretty print snapshots
    pretty_print: bool = true,
};

pub const WatchOptions = struct {
    /// Enable watch mode
    enabled: bool = false,
    /// Directory to watch
    watch_dir: []const u8 = ".",
    /// Debounce delay in milliseconds
    debounce_ms: u64 = 300,
    /// Clear screen between runs
    clear_screen: bool = true,
};

pub const MemoryOptions = struct {
    /// Enable memory profiling
    enabled: bool = false,
    /// Detect memory leaks
    detect_leaks: bool = true,
    /// Track peak memory usage
    track_peak: bool = true,
    /// Report threshold in bytes
    report_threshold: usize = 0,
    /// Fail tests on memory leaks
    fail_on_leak: bool = false,
};

pub const UIOptions = struct {
    /// Enable UI server
    enabled: bool = false,
    /// Port for UI server
    port: u16 = 8080,
    /// Open browser automatically
    open_browser: bool = true,
};

pub const CoverageOptions = struct {
    /// Enable coverage tracking
    enabled: bool = false,
    /// Coverage output directory
    output_dir: []const u8 = "coverage",
    /// Minimum coverage threshold
    threshold: f64 = 0.0,
};

/// Configuration loader
pub const ConfigLoader = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    /// Load configuration from file
    pub fn loadFromFile(self: *Self, path: []const u8) !TestConfig {
        // Detect format from extension
        const format = if (std.mem.endsWith(u8, path, ".json"))
            ConfigFormat.json
        else if (std.mem.endsWith(u8, path, ".toml"))
            ConfigFormat.toml
        else
            return error.UnsupportedFormat;

        switch (format) {
            .json => return try self.loadFromJson(path),
            .toml => return error.TomlNotImplementedYet,
        }
    }

    /// Load configuration from JSON file
    fn loadFromJson(self: *Self, path: []const u8) !TestConfig {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024);
        defer self.allocator.free(content);

        var parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, content, .{});
        defer parsed.deinit();

        return try self.parseConfig(parsed.value);
    }

    /// Parse configuration from JSON value
    fn parseConfig(self: *Self, value: std.json.Value) !TestConfig {
        _ = self;

        var config = TestConfig{};

        if (value != .object) return config;

        const root = value.object;

        // Parse test options
        if (root.get("test")) |test_value| {
            if (test_value == .object) {
                const test_obj = test_value.object;
                if (test_obj.get("pattern")) |v| {
                    if (v == .string) config.test_options.pattern = v.string;
                }
                if (test_obj.get("test_dir")) |v| {
                    if (v == .string) config.test_options.test_dir = v.string;
                }
                if (test_obj.get("recursive")) |v| {
                    if (v == .bool) config.test_options.recursive = v.bool;
                }
                if (test_obj.get("timeout")) |v| {
                    if (v == .integer) config.test_options.timeout = @intCast(v.integer);
                }
            }
        }

        // Parse parallel options
        if (root.get("parallel")) |parallel_value| {
            if (parallel_value == .object) {
                const parallel_obj = parallel_value.object;
                if (parallel_obj.get("enabled")) |v| {
                    if (v == .bool) config.parallel.enabled = v.bool;
                }
                if (parallel_obj.get("jobs")) |v| {
                    if (v == .integer) config.parallel.jobs = @intCast(v.integer);
                }
            }
        }

        // Parse reporter options
        if (root.get("reporter")) |reporter_value| {
            if (reporter_value == .object) {
                const reporter_obj = reporter_value.object;
                if (reporter_obj.get("reporter")) |v| {
                    if (v == .string) config.reporter.reporter = v.string;
                }
                if (reporter_obj.get("junit_output")) |v| {
                    if (v == .string) config.reporter.junit_output = v.string;
                }
                if (reporter_obj.get("verbose")) |v| {
                    if (v == .bool) config.reporter.verbose = v.bool;
                }
            }
        }

        // Parse snapshot options
        if (root.get("snapshot")) |snapshot_value| {
            if (snapshot_value == .object) {
                const snapshot_obj = snapshot_value.object;
                if (snapshot_obj.get("snapshot_dir")) |v| {
                    if (v == .string) config.snapshot.snapshot_dir = v.string;
                }
                if (snapshot_obj.get("update")) |v| {
                    if (v == .bool) config.snapshot.update = v.bool;
                }
                if (snapshot_obj.get("pretty_print")) |v| {
                    if (v == .bool) config.snapshot.pretty_print = v.bool;
                }
            }
        }

        // Parse watch options
        if (root.get("watch")) |watch_value| {
            if (watch_value == .object) {
                const watch_obj = watch_value.object;
                if (watch_obj.get("enabled")) |v| {
                    if (v == .bool) config.watch.enabled = v.bool;
                }
                if (watch_obj.get("watch_dir")) |v| {
                    if (v == .string) config.watch.watch_dir = v.string;
                }
                if (watch_obj.get("debounce_ms")) |v| {
                    if (v == .integer) config.watch.debounce_ms = @intCast(v.integer);
                }
                if (watch_obj.get("clear_screen")) |v| {
                    if (v == .bool) config.watch.clear_screen = v.bool;
                }
            }
        }

        // Parse memory options
        if (root.get("memory")) |memory_value| {
            if (memory_value == .object) {
                const memory_obj = memory_value.object;
                if (memory_obj.get("enabled")) |v| {
                    if (v == .bool) config.memory.enabled = v.bool;
                }
                if (memory_obj.get("detect_leaks")) |v| {
                    if (v == .bool) config.memory.detect_leaks = v.bool;
                }
                if (memory_obj.get("track_peak")) |v| {
                    if (v == .bool) config.memory.track_peak = v.bool;
                }
                if (memory_obj.get("report_threshold")) |v| {
                    if (v == .integer) config.memory.report_threshold = @intCast(v.integer);
                }
                if (memory_obj.get("fail_on_leak")) |v| {
                    if (v == .bool) config.memory.fail_on_leak = v.bool;
                }
            }
        }

        // Parse UI options
        if (root.get("ui")) |ui_value| {
            if (ui_value == .object) {
                const ui_obj = ui_value.object;
                if (ui_obj.get("enabled")) |v| {
                    if (v == .bool) config.ui.enabled = v.bool;
                }
                if (ui_obj.get("port")) |v| {
                    if (v == .integer) config.ui.port = @intCast(v.integer);
                }
                if (ui_obj.get("open_browser")) |v| {
                    if (v == .bool) config.ui.open_browser = v.bool;
                }
            }
        }

        // Parse coverage options
        if (root.get("coverage")) |coverage_value| {
            if (coverage_value == .object) {
                const coverage_obj = coverage_value.object;
                if (coverage_obj.get("enabled")) |v| {
                    if (v == .bool) config.coverage.enabled = v.bool;
                }
                if (coverage_obj.get("output_dir")) |v| {
                    if (v == .string) config.coverage.output_dir = v.string;
                }
                if (coverage_obj.get("threshold")) |v| {
                    if (v == .float) config.coverage.threshold = v.float;
                }
            }
        }

        return config;
    }

    /// Try to find and load configuration file
    pub fn autoLoad(self: *Self, config_name: []const u8) !?TestConfig {
        const search_paths = [_][]const u8{
            "zig-test.json",
            ".zig-test.json",
            "config/zig-test.json",
            ".config/zig-test.json",
        };

        for (search_paths) |path| {
            const full_path = if (std.mem.eql(u8, config_name, "zig-test"))
                path
            else
                try std.fmt.allocPrint(self.allocator, "{s}.json", .{config_name});

            defer if (!std.mem.eql(u8, config_name, "zig-test")) self.allocator.free(full_path);

            const config = self.loadFromFile(full_path) catch |err| {
                if (err == error.FileNotFound) continue;
                return err;
            };

            return config;
        }

        return null;
    }
};

// Tests
test "TestConfig default values" {
    const config = TestConfig{};

    try std.testing.expectEqualStrings("*.test.zig", config.test_options.pattern);
    try std.testing.expectEqualStrings("src", config.test_options.test_dir);
    try std.testing.expectEqual(true, config.test_options.recursive);
    try std.testing.expectEqual(false, config.parallel.enabled);
    try std.testing.expectEqualStrings("spec", config.reporter.reporter);
}

test "ConfigLoader initialization" {
    const allocator = std.testing.allocator;

    const loader = ConfigLoader.init(allocator);
    try std.testing.expect(loader.allocator.ptr == allocator.ptr);
}

test "ConfigLoader parse empty JSON" {
    const allocator = std.testing.allocator;

    var loader = ConfigLoader.init(allocator);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, "{}", .{});
    defer parsed.deinit();

    const config = try loader.parseConfig(parsed.value);

    // Should return defaults
    try std.testing.expectEqualStrings("spec", config.reporter.reporter);
    try std.testing.expectEqual(false, config.parallel.enabled);
}
