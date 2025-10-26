const std = @import("std");
const discovery = @import("discovery.zig");
const test_loader = @import("test_loader.zig");

/// Watch mode options
pub const WatchOptions = struct {
    /// Directory to watch
    watch_dir: []const u8 = ".",
    /// Test file pattern
    pattern: []const u8 = "*.test.zig",
    /// Whether to watch recursively
    recursive: bool = true,
    /// Debounce delay in milliseconds
    debounce_ms: u64 = 300,
    /// Clear screen between runs
    clear_screen: bool = true,
    /// Verbose output
    verbose: bool = false,
};

/// File watcher for test files
pub const TestWatcher = struct {
    allocator: std.mem.Allocator,
    options: WatchOptions,
    running: *std.atomic.Value(bool),
    last_run_time: std.atomic.Value(i64) = std.atomic.Value(i64).init(0),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, options: WatchOptions, running: *std.atomic.Value(bool)) Self {
        return .{
            .allocator = allocator,
            .options = options,
            .running = running,
        };
    }

    /// Start watching for file changes
    pub fn watch(self: *Self, loader_options: test_loader.LoaderOptions) !void {
        if (self.options.verbose) {
            std.debug.print("Watching for changes in '{s}' (pattern: {s})...\n", .{ self.options.watch_dir, self.options.pattern });
            std.debug.print("Press Ctrl+C to stop.\n\n", .{});
        }

        // Run tests initially
        try self.runTests(loader_options);

        // Watch for file changes
        while (self.running.load(.monotonic)) {
            std.Thread.sleep(self.options.debounce_ms * std.time.ns_per_ms);

            if (try self.checkForChanges()) {
                const current_time = std.time.milliTimestamp();
                const last_run = self.last_run_time.load(.monotonic);

                // Debounce: only run if enough time has passed
                if (current_time - last_run >= self.options.debounce_ms) {
                    if (self.options.clear_screen) {
                        self.clearScreen();
                    }

                    std.debug.print("Change detected, re-running tests...\n\n", .{});

                    try self.runTests(loader_options);

                    self.last_run_time.store(current_time, .monotonic);
                }
            }
        }
    }

    /// Check if any test files have changed
    fn checkForChanges(self: *Self) !bool {
        // Simple implementation: check modification times
        // In a production system, you'd use std.fs.Watch or platform-specific APIs
        var dir = try std.fs.cwd().openDir(self.options.watch_dir, .{ .iterate = true });
        defer dir.close();

        var walker = try dir.walk(self.allocator);
        defer walker.deinit();

        const current_time = std.time.milliTimestamp();
        const check_window_ms = self.options.debounce_ms * 2;

        while (try walker.next()) |entry| {
            if (entry.kind != .file) continue;

            // Check if file matches pattern
            if (!self.matchesPattern(entry.basename, self.options.pattern)) continue;

            // Get file stats
            const stat = try entry.dir.statFile(entry.basename);
            const mtime_ms = @divTrunc(stat.mtime, 1_000_000); // Convert to milliseconds

            // Check if file was modified recently
            if (current_time - mtime_ms < check_window_ms) {
                if (self.options.verbose) {
                    std.debug.print("Detected change in: {s}\n", .{entry.path});
                }
                return true;
            }
        }

        return false;
    }

    /// Run tests with discovery
    fn runTests(self: *Self, loader_options: test_loader.LoaderOptions) !void {
        const discovery_options = discovery.DiscoveryOptions{
            .root_path = self.options.watch_dir,
            .pattern = self.options.pattern,
            .recursive = self.options.recursive,
        };

        var discovered = try discovery.discoverTests(self.allocator, discovery_options);
        defer discovered.deinit();

        const passed = try test_loader.runDiscoveredTests(self.allocator, &discovered, loader_options);

        if (passed) {
            std.debug.print("\n✓ All tests passed! Watching for changes...\n", .{});
        } else {
            std.debug.print("\n✗ Some tests failed. Fix them and save to re-run.\n", .{});
        }
    }

    /// Check if filename matches pattern
    fn matchesPattern(self: *Self, filename: []const u8, pattern: []const u8) bool {
        _ = self;

        // Simple wildcard matching
        if (std.mem.indexOf(u8, pattern, "*")) |star_pos| {
            const prefix = pattern[0..star_pos];
            const suffix = pattern[star_pos + 1 ..];

            if (prefix.len > 0 and !std.mem.startsWith(u8, filename, prefix)) {
                return false;
            }

            if (suffix.len > 0 and !std.mem.endsWith(u8, filename, suffix)) {
                return false;
            }

            return true;
        } else {
            return std.mem.eql(u8, filename, pattern);
        }
    }

    /// Clear terminal screen
    fn clearScreen(self: *Self) void {
        _ = self;
        // ANSI escape code to clear screen
        std.debug.print("\x1b[2J\x1b[H", .{});
    }
};

/// Simple file watcher using polling
/// Note: In production, use std.fs.Watch or platform-specific APIs (inotify, kqueue, etc.)
pub const FileWatcher = struct {
    allocator: std.mem.Allocator,
    watch_paths: std.ArrayList([]const u8),
    file_times: std.StringHashMap(i64),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .watch_paths = std.ArrayList([]const u8).empty,
            .file_times = std.StringHashMap(i64).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.watch_paths.items) |path| {
            self.allocator.free(path);
        }
        self.watch_paths.deinit(self.allocator);
        self.file_times.deinit();
    }

    /// Add a path to watch
    pub fn addPath(self: *Self, path: []const u8) !void {
        const path_copy = try self.allocator.dupe(u8, path);
        try self.watch_paths.append(self.allocator, path_copy);

        // Initialize modification time
        const stat = std.fs.cwd().statFile(path) catch |err| {
            if (err == error.FileNotFound) {
                try self.file_times.put(path_copy, 0);
                return;
            }
            return err;
        };

        const mtime_ms = @divTrunc(stat.mtime, 1_000_000);
        try self.file_times.put(path_copy, mtime_ms);
    }

    /// Check if any watched files have changed
    pub fn hasChanges(self: *Self) !bool {
        for (self.watch_paths.items) |path| {
            const stat = std.fs.cwd().statFile(path) catch |err| {
                if (err == error.FileNotFound) continue;
                return err;
            };

            const mtime_ms = @divTrunc(stat.mtime, 1_000_000);
            const last_mtime = self.file_times.get(path) orelse 0;

            if (mtime_ms > last_mtime) {
                try self.file_times.put(path, mtime_ms);
                return true;
            }
        }

        return false;
    }
};

// Tests
test "WatchOptions default values" {
    const options = WatchOptions{};

    try std.testing.expectEqualStrings(".", options.watch_dir);
    try std.testing.expectEqualStrings("*.test.zig", options.pattern);
    try std.testing.expectEqual(true, options.recursive);
    try std.testing.expectEqual(@as(u64, 300), options.debounce_ms);
    try std.testing.expectEqual(true, options.clear_screen);
}

test "FileWatcher initialization" {
    const allocator = std.testing.allocator;

    var watcher = FileWatcher.init(allocator);
    defer watcher.deinit();

    try std.testing.expectEqual(@as(usize, 0), watcher.watch_paths.items.len);
}
