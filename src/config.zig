const std = @import("std");
const compat = @import("compat.zig");

/// JSON is the only configuration format currently supported by the CLI.
pub const ConfigFormat = enum { json };

/// Configuration values mirror options that the current execution paths can
/// actually honor. Defaults intentionally match `CLIOptions`.
pub const TestConfig = struct {
    test_options: TestOptions = .{},
    sharding: ShardingOptions = .{},
    parallel: ParallelOptions = .{},
    reporter: ReporterOptions = .{},
    snapshot: SnapshotOptions = .{},
    watch: WatchOptions = .{},
    memory: MemoryOptions = .{},
    ui: UIOptions = .{},
    coverage: CoverageOptions = .{},
};

pub const ShardingOptions = struct {
    index: ?usize = null,
    count: ?usize = null,
};

pub const TestOptions = struct {
    pattern: []const u8 = "*.test.zig",
    test_dir: []const u8 = ".",
    recursive: bool = true,
    filter: ?[]const u8 = null,
    timeout: ?u64 = null,
    retries: usize = 0,
    repeat: usize = 1,
    fail_on_flaky: bool = false,
};

pub const ParallelOptions = struct {
    enabled: bool = false,
    jobs: ?usize = null,
};

pub const ReporterOptions = struct {
    reporter: []const u8 = "spec",
    junit_output: ?[]const u8 = null,
    verbose: bool = false,
};

pub const SnapshotOptions = struct {
    snapshot_dir: []const u8 = ".snapshots",
    update: bool = false,
};

pub const WatchOptions = struct {
    enabled: bool = false,
    debounce_ms: u64 = 300,
};

pub const MemoryOptions = struct {
    enabled: bool = false,
    report_threshold: usize = 0,
    fail_on_leak: bool = false,
};

pub const UIOptions = struct {
    enabled: bool = false,
    port: u16 = 8080,
};

pub const CoverageOptions = struct {
    enabled: bool = false,
    output_dir: []const u8 = "coverage",
};

const FileConfig = struct {
    @"test": TestOptions = .{},
    sharding: ShardingOptions = .{},
    parallel: ParallelOptions = .{},
    reporter: ReporterOptions = .{},
    snapshot: SnapshotOptions = .{},
    watch: WatchOptions = .{},
    memory: MemoryOptions = .{},
    ui: UIOptions = .{},
    coverage: CoverageOptions = .{},
};

pub const ConfigError = error{
    UnsupportedFormat,
    InvalidReporter,
    InvalidJobs,
    InvalidPort,
    InvalidTimeout,
    InvalidRepeat,
    InvalidDebounce,
    InvalidShard,
};

/// Owns strings parsed from configuration files until `deinit` is called.
pub const ConfigLoader = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .arena = .init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.arena.deinit();
    }

    /// Load a strict JSON configuration. Unknown keys, duplicate keys, and
    /// values of the wrong type are rejected by the standard JSON parser.
    pub fn loadFromFile(self: *Self, path: []const u8) !TestConfig {
        if (!std.mem.endsWith(u8, path, ".json")) return ConfigError.UnsupportedFormat;

        const content = try compat.readFileAlloc(self.allocator, path);
        defer self.allocator.free(content);

        const file_config = try std.json.parseFromSliceLeaky(
            FileConfig,
            self.arena.allocator(),
            content,
            .{ .allocate = .alloc_always },
        );
        const config = TestConfig{
            .test_options = file_config.@"test",
            .sharding = file_config.sharding,
            .parallel = file_config.parallel,
            .reporter = file_config.reporter,
            .snapshot = file_config.snapshot,
            .watch = file_config.watch,
            .memory = file_config.memory,
            .ui = file_config.ui,
            .coverage = file_config.coverage,
        };
        try validate(config);
        return config;
    }

    /// Try conventional JSON configuration locations.
    pub fn autoLoad(self: *Self, config_name: []const u8) !?TestConfig {
        const search_paths = [_][]const u8{
            "zig-test.json",
            ".zig-test.json",
            "config/zig-test.json",
            ".config/zig-test.json",
        };

        if (!std.mem.eql(u8, config_name, "zig-test")) {
            const path = try std.fmt.allocPrint(self.allocator, "{s}.json", .{config_name});
            defer self.allocator.free(path);
            return self.loadFromFile(path) catch |err| switch (err) {
                error.FileNotFound => null,
                else => return err,
            };
        }

        for (search_paths) |path| {
            const config = self.loadFromFile(path) catch |err| switch (err) {
                error.FileNotFound => continue,
                else => return err,
            };
            return config;
        }
        return null;
    }
};

fn validate(config: TestConfig) !void {
    const reporter = config.reporter.reporter;
    if (!std.mem.eql(u8, reporter, "spec") and
        !std.mem.eql(u8, reporter, "dot") and
        !std.mem.eql(u8, reporter, "json") and
        !std.mem.eql(u8, reporter, "tap") and
        !std.mem.eql(u8, reporter, "junit"))
    {
        return ConfigError.InvalidReporter;
    }
    if (config.parallel.jobs) |jobs| {
        if (jobs == 0) return ConfigError.InvalidJobs;
    }
    if (config.ui.port == 0) return ConfigError.InvalidPort;
    if (config.test_options.timeout) |timeout| {
        if (timeout == 0) return ConfigError.InvalidTimeout;
    }
    if (config.test_options.repeat == 0) return ConfigError.InvalidRepeat;
    if (config.watch.debounce_ms == 0) return ConfigError.InvalidDebounce;
    const has_shard_index = config.sharding.index != null;
    const has_shard_count = config.sharding.count != null;
    if (has_shard_index != has_shard_count) return ConfigError.InvalidShard;
    if (config.sharding.count) |count| {
        const index = config.sharding.index.?;
        if (count == 0 or index == 0 or index > count) return ConfigError.InvalidShard;
    }
}

test "TestConfig defaults match CLI discovery defaults" {
    const config = TestConfig{};
    try std.testing.expectEqualStrings("*.test.zig", config.test_options.pattern);
    try std.testing.expectEqualStrings(".", config.test_options.test_dir);
    try std.testing.expect(config.test_options.recursive);
    try std.testing.expect(config.test_options.timeout == null);
    try std.testing.expectEqual(@as(usize, 0), config.test_options.retries);
    try std.testing.expectEqual(@as(usize, 1), config.test_options.repeat);
    try std.testing.expect(!config.test_options.fail_on_flaky);
    try std.testing.expect(config.sharding.index == null);
    try std.testing.expect(config.sharding.count == null);
    try std.testing.expect(!config.parallel.enabled);
    try std.testing.expectEqualStrings("spec", config.reporter.reporter);
}

test "ConfigLoader rejects unsupported formats" {
    var loader = ConfigLoader.init(std.testing.allocator);
    defer loader.deinit();
    try std.testing.expectError(ConfigError.UnsupportedFormat, loader.loadFromFile("zig-test.toml"));
}

test "configuration validation rejects invalid runtime values" {
    var invalid = TestConfig{};
    invalid.reporter.reporter = "pretty";
    try std.testing.expectError(ConfigError.InvalidReporter, validate(invalid));
    invalid.reporter.reporter = "spec";
    invalid.parallel.jobs = 0;
    try std.testing.expectError(ConfigError.InvalidJobs, validate(invalid));
    invalid.parallel.jobs = null;
    invalid.test_options.repeat = 0;
    try std.testing.expectError(ConfigError.InvalidRepeat, validate(invalid));
    invalid.test_options.repeat = 1;
    invalid.sharding.index = 2;
    try std.testing.expectError(ConfigError.InvalidShard, validate(invalid));
    invalid.sharding.count = 1;
    try std.testing.expectError(ConfigError.InvalidShard, validate(invalid));
}

test "ConfigLoader loads supported JSON and rejects unknown keys" {
    var loader = ConfigLoader.init(std.testing.allocator);
    defer loader.deinit();

    const config = try loader.loadFromFile("tests/fixtures/zig-test.json");
    try std.testing.expectEqualStrings("tests/fixtures", config.test_options.test_dir);
    try std.testing.expectEqualStrings("selected test passes", config.test_options.filter.?);
    try std.testing.expect(!config.test_options.recursive);
    try std.testing.expectEqual(@as(usize, 1), config.test_options.retries);
    try std.testing.expectEqual(@as(usize, 2), config.test_options.repeat);
    try std.testing.expect(!config.test_options.fail_on_flaky);
    try std.testing.expectEqual(@as(?usize, 1), config.sharding.index);
    try std.testing.expectEqual(@as(?usize, 1), config.sharding.count);

    try std.testing.expectError(
        error.UnknownField,
        loader.loadFromFile("tests/fixtures/invalid-zig-test.json"),
    );
}
