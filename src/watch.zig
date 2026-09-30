const std = @import("std");
const discovery = @import("discovery.zig");
const test_loader = @import("test_loader.zig");
const compat = @import("compat.zig");

/// Watch mode options.
pub const WatchOptions = struct {
    /// Directory containing discoverable tests.
    watch_dir: []const u8 = ".",
    /// Project root scanned for Zig source changes.
    project_root: []const u8 = ".",
    /// Test file pattern.
    pattern: []const u8 = "*.test.zig",
    /// Whether test discovery is recursive.
    recursive: bool = true,
    /// Debounce delay in milliseconds.
    debounce_ms: u64 = 300,
    /// Clear screen between runs.
    clear_screen: bool = true,
    /// Verbose output.
    verbose: bool = false,
    /// Listen for `r` followed by Enter to request a full rerun.
    interactive_commands: bool = false,
};

pub const ChangeKind = enum { added, modified, deleted };

pub const FileChange = struct {
    path: []const u8,
    kind: ChangeKind,
};

const ChangeSet = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(FileChange) = .empty,

    fn deinit(self: *ChangeSet) void {
        for (self.items.items) |change| self.allocator.free(change.path);
        self.items.deinit(self.allocator);
    }

    fn append(self: *ChangeSet, path: []const u8, kind: ChangeKind) !void {
        const path_copy = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(path_copy);
        try self.items.append(self.allocator, .{
            .path = path_copy,
            .kind = kind,
        });
    }
};

const FileStamp = struct {
    modified_ns: i96,
    size: u64,

    fn eql(a: FileStamp, b: FileStamp) bool {
        return a.modified_ns == b.modified_ns and a.size == b.size;
    }
};

const Snapshot = struct {
    allocator: std.mem.Allocator,
    files: std.StringHashMap(FileStamp),

    fn init(allocator: std.mem.Allocator) Snapshot {
        return .{ .allocator = allocator, .files = .init(allocator) };
    }

    fn deinit(self: *Snapshot) void {
        var keys = self.files.keyIterator();
        while (keys.next()) |path| self.allocator.free(path.*);
        self.files.deinit();
    }

    fn put(self: *Snapshot, path: []u8, stamp: FileStamp) !void {
        const entry = try self.files.getOrPut(path);
        if (entry.found_existing) {
            self.allocator.free(path);
        } else {
            entry.key_ptr.* = path;
        }
        entry.value_ptr.* = stamp;
    }

    fn changesSince(self: *const Snapshot, previous: *const Snapshot, allocator: std.mem.Allocator) !ChangeSet {
        var changes = ChangeSet{ .allocator = allocator };
        errdefer changes.deinit();

        var current = self.files.iterator();
        while (current.next()) |entry| {
            if (previous.files.get(entry.key_ptr.*)) |old_stamp| {
                if (!entry.value_ptr.eql(old_stamp)) try changes.append(entry.key_ptr.*, .modified);
            } else {
                try changes.append(entry.key_ptr.*, .added);
            }
        }

        var old = previous.files.iterator();
        while (old.next()) |entry| {
            if (!self.files.contains(entry.key_ptr.*)) try changes.append(entry.key_ptr.*, .deleted);
        }
        return changes;
    }
};

const SelectionReason = enum { changed_test, affected_source };

const SelectedTest = struct {
    index: usize,
    reason: SelectionReason,
    cause: []const u8,
};

const FullRunReason = enum {
    initial,
    manual,
    test_topology_changed,
    dependency_information_unavailable,
};

const Selection = struct {
    allocator: std.mem.Allocator,
    full_run: ?FullRunReason = null,
    tests: std.ArrayList(SelectedTest) = .empty,

    fn deinit(self: *Selection) void {
        self.tests.deinit(self.allocator);
    }

    fn select(self: *Selection, index: usize, reason: SelectionReason, cause: []const u8) !void {
        for (self.tests.items) |existing| {
            if (existing.index == index) return;
        }
        try self.tests.append(self.allocator, .{ .index = index, .reason = reason, .cause = cause });
    }
};

const DependencyInfo = struct {
    allocator: std.mem.Allocator,
    paths: std.StringHashMap(void),
    complete: bool = true,

    fn init(allocator: std.mem.Allocator) DependencyInfo {
        return .{ .allocator = allocator, .paths = .init(allocator) };
    }

    fn deinit(self: *DependencyInfo) void {
        var keys = self.paths.keyIterator();
        while (keys.next()) |path| self.allocator.free(path.*);
        self.paths.deinit();
    }

    fn add(self: *DependencyInfo, path: []u8) !bool {
        const entry = try self.paths.getOrPut(path);
        if (entry.found_existing) {
            self.allocator.free(path);
            return false;
        }
        entry.key_ptr.* = path;
        entry.value_ptr.* = {};
        return true;
    }
};

var manual_rerun_requested = std.atomic.Value(bool).init(false);
var command_listener_started = std.atomic.Value(bool).init(false);

/// Polling watcher that selects only tests affected by a change when it can do
/// so safely.
pub const TestWatcher = struct {
    allocator: std.mem.Allocator,
    options: WatchOptions,
    running: *std.atomic.Value(bool),
    last_run_time: std.atomic.Value(i64) = .init(0),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, options: WatchOptions, running: *std.atomic.Value(bool)) Self {
        return .{ .allocator = allocator, .options = options, .running = running };
    }

    /// Ask a running watcher to execute every discovered test at its next poll.
    pub fn requestFullRerun(_: *Self) void {
        manual_rerun_requested.store(true, .release);
    }

    /// Run tests initially, then poll source and test files for changes.
    pub fn watch(self: *Self, loader_options: test_loader.LoaderOptions) !void {
        if (self.options.verbose) {
            std.debug.print("Watching project '{s}' for tests in '{s}' (pattern: {s})...\n", .{
                self.options.project_root,
                self.options.watch_dir,
                self.options.pattern,
            });
        }
        if (self.options.interactive_commands) {
            std.debug.print("Press Ctrl+C to stop; type 'r' and press Enter for a full rerun.\n\n", .{});
        } else if (self.options.verbose) {
            std.debug.print("Press Ctrl+C to stop.\n\n", .{});
        }

        manual_rerun_requested.store(false, .release);
        if (self.options.interactive_commands) startCommandListener();

        var snapshot = try captureSnapshot(self.allocator, self.options.project_root);
        defer snapshot.deinit();
        try self.runFull(loader_options, .initial);
        self.last_run_time.store(compat.milliTimestamp(), .release);

        while (self.running.load(.acquire)) {
            compat.sleep(self.options.debounce_ms * std.time.ns_per_ms);

            var current = try captureSnapshot(self.allocator, self.options.project_root);
            var changes = try current.changesSince(&snapshot, self.allocator);
            snapshot.deinit();
            snapshot = current;
            defer changes.deinit();

            const manual = manual_rerun_requested.swap(false, .acq_rel);
            if (changes.items.items.len == 0 and !manual) continue;

            if (self.options.clear_screen) self.clearScreen();
            if (manual) {
                try self.runFull(loader_options, .manual);
            } else {
                try self.runAffected(loader_options, changes.items.items);
            }
            self.last_run_time.store(compat.milliTimestamp(), .release);
        }
    }

    fn runFull(self: *Self, loader_options: test_loader.LoaderOptions, reason: FullRunReason) !void {
        printFullRunReason(reason);
        var discovered = try self.discover();
        defer discovered.deinit();
        printOutcome(try test_loader.runDiscoveredTests(self.allocator, &discovered, loader_options));
    }

    fn runAffected(self: *Self, loader_options: test_loader.LoaderOptions, changes: []const FileChange) !void {
        var discovered = try self.discover();
        defer discovered.deinit();
        var selection = try planAffected(self.allocator, self.options, &discovered, changes);
        defer selection.deinit();

        if (selection.full_run) |reason| {
            printChanges(changes);
            printFullRunReason(reason);
            printOutcome(try test_loader.runDiscoveredTests(self.allocator, &discovered, loader_options));
            return;
        }

        var selected = discovery.DiscoveryResult.init(self.allocator);
        defer selected.deinit();
        std.debug.print("Watch selection:\n", .{});
        for (selection.tests.items) |item| {
            const file = discovered.files.items[item.index];
            try selected.addFile(file.path, file.relative_path, file.name);
            std.debug.print("  - {s} ({s}: {s})\n", .{
                file.relative_path,
                switch (item.reason) {
                    .changed_test => "changed test file",
                    .affected_source => "imports changed source",
                },
                item.cause,
            });
        }
        std.debug.print("\n", .{});
        printOutcome(try test_loader.runDiscoveredTests(self.allocator, &selected, loader_options));
    }

    fn discover(self: *Self) !discovery.DiscoveryResult {
        return discovery.discoverTests(self.allocator, .{
            .root_path = self.options.watch_dir,
            .pattern = self.options.pattern,
            .recursive = self.options.recursive,
        });
    }

    fn clearScreen(_: *Self) void {
        std.debug.print("\x1b[2J\x1b[H", .{});
    }
};

fn printOutcome(passed: bool) void {
    if (passed) {
        std.debug.print("\n✓ Selected tests passed. Watching for changes...\n", .{});
    } else {
        std.debug.print("\n✗ Selected tests failed. Fix them and save to re-run.\n", .{});
    }
}

fn printChanges(changes: []const FileChange) void {
    std.debug.print("Detected changes:\n", .{});
    for (changes) |change| std.debug.print("  - {s}: {s}\n", .{ @tagName(change.kind), change.path });
}

fn printFullRunReason(reason: FullRunReason) void {
    const message = switch (reason) {
        .initial => "initial watch run",
        .manual => "manual full-rerun command",
        .test_topology_changed => "a test was deleted or renamed",
        .dependency_information_unavailable => "dependency information was incomplete or no affected test was found",
    };
    std.debug.print("Watch selection: full suite ({s})\n\n", .{message});
}

fn startCommandListener() void {
    if (command_listener_started.cmpxchgStrong(false, true, .acq_rel, .acquire) != null) return;
    const thread = std.Thread.spawn(.{}, commandLoop, .{}) catch {
        command_listener_started.store(false, .release);
        return;
    };
    thread.detach();
}

fn commandLoop() void {
    var threaded: std.Io.Threaded = .init(std.heap.page_allocator, .{ .environ = .empty });
    defer threaded.deinit();
    var buffer: [256]u8 = undefined;
    var reader = std.Io.File.stdin().reader(threaded.io(), &buffer);
    while (true) {
        const raw = (reader.interface.takeDelimiter('\n') catch return) orelse return;
        const command = std.mem.trim(u8, raw, " \t\r");
        if (std.ascii.eqlIgnoreCase(command, "r") or std.ascii.eqlIgnoreCase(command, "run all")) {
            manual_rerun_requested.store(true, .release);
        }
    }
}

fn captureSnapshot(allocator: std.mem.Allocator, root: []const u8) !Snapshot {
    var snapshot = Snapshot.init(allocator);
    errdefer snapshot.deinit();
    var threaded: std.Io.Threaded = .init(allocator, .{ .environ = .empty });
    defer threaded.deinit();
    try scanSnapshot(allocator, &snapshot, threaded.io(), root);
    return snapshot;
}

fn scanSnapshot(allocator: std.mem.Allocator, snapshot: *Snapshot, io: std.Io, current_path: []const u8) !void {
    var dir = compat.DirIterator.open(current_path) catch return;
    defer dir.close();

    while (try dir.next()) |entry| {
        if (entry.kind == .directory and shouldSkipDirectory(entry.name)) continue;
        const joined = try std.fs.path.join(allocator, &.{ current_path, entry.name });
        defer allocator.free(joined);

        switch (entry.kind) {
            .directory => try scanSnapshot(allocator, snapshot, io, joined),
            .file => {
                if (!std.mem.endsWith(u8, entry.name, ".zig")) continue;
                const normalized = try std.fs.path.resolveAlloc(allocator, &.{joined});
                errdefer allocator.free(normalized);
                const stat = std.Io.Dir.cwd().statFile(io, normalized, .{}) catch {
                    allocator.free(normalized);
                    continue;
                };
                try snapshot.put(normalized, .{ .modified_ns = stat.mtime.nanoseconds, .size = stat.size });
            },
            else => {},
        }
    }
}

fn shouldSkipDirectory(name: []const u8) bool {
    const excluded = [_][]const u8{ ".git", ".zig-cache", "zig-cache", "zig-out", "node_modules", ".codex" };
    for (excluded) |candidate| {
        if (std.mem.eql(u8, name, candidate)) return true;
    }
    return false;
}

fn planAffected(
    allocator: std.mem.Allocator,
    options: WatchOptions,
    discovered: *const discovery.DiscoveryResult,
    changes: []const FileChange,
) !Selection {
    var selection = Selection{ .allocator = allocator };
    errdefer selection.deinit();
    var sources: std.ArrayList([]const u8) = .empty;
    defer sources.deinit(allocator);

    for (changes) |change| {
        if (isTestPath(change.path, options.pattern)) {
            if (change.kind == .deleted) {
                selection.full_run = .test_topology_changed;
                return selection;
            }
            if (findTest(discovered, change.path, allocator)) |index| {
                try selection.select(index, .changed_test, change.path);
            } else {
                selection.full_run = .test_topology_changed;
                return selection;
            }
        } else {
            try sources.append(allocator, change.path);
        }
    }

    if (sources.items.len == 0) return selection;
    const mapped = try allocator.alloc(bool, sources.items.len);
    defer allocator.free(mapped);
    @memset(mapped, false);

    for (discovered.files.items, 0..) |file, index| {
        var dependencies = try resolveDependencies(allocator, file.path);
        defer dependencies.deinit();
        if (!dependencies.complete) {
            selection.full_run = .dependency_information_unavailable;
            return selection;
        }
        for (sources.items, 0..) |source, source_index| {
            if (dependencies.paths.contains(source)) {
                mapped[source_index] = true;
                try selection.select(index, .affected_source, source);
            }
        }
    }

    for (mapped) |was_mapped| {
        if (!was_mapped) {
            selection.full_run = .dependency_information_unavailable;
            return selection;
        }
    }
    return selection;
}

fn findTest(discovered: *const discovery.DiscoveryResult, changed_path: []const u8, allocator: std.mem.Allocator) ?usize {
    for (discovered.files.items, 0..) |file, index| {
        const normalized = std.fs.path.resolveAlloc(allocator, &.{file.path}) catch continue;
        defer allocator.free(normalized);
        if (std.mem.eql(u8, normalized, changed_path)) return index;
    }
    return null;
}

fn isTestPath(path: []const u8, pattern: []const u8) bool {
    const name = std.fs.path.basename(path);
    if (std.mem.indexOfScalar(u8, pattern, '*')) |star| {
        const prefix = pattern[0..star];
        const suffix = pattern[star + 1 ..];
        return std.mem.startsWith(u8, name, prefix) and std.mem.endsWith(u8, name, suffix);
    }
    return std.mem.eql(u8, name, pattern);
}

fn resolveDependencies(allocator: std.mem.Allocator, test_path: []const u8) !DependencyInfo {
    var info = DependencyInfo.init(allocator);
    errdefer info.deinit();
    const normalized = try std.fs.path.resolveAlloc(allocator, &.{test_path});
    defer allocator.free(normalized);
    try scanImports(&info, normalized);
    if (info.paths.fetchRemove(normalized)) |removed| allocator.free(removed.key);
    return info;
}

fn scanImports(info: *DependencyInfo, importer_path: []const u8) !void {
    const content = compat.readFileAlloc(info.allocator, importer_path) catch {
        info.complete = false;
        return;
    };
    defer info.allocator.free(content);

    const marker = "@import(\"";
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, content, cursor, marker)) |start| {
        const value_start = start + marker.len;
        const value_end = std.mem.indexOfScalarPos(u8, content, value_start, '"') orelse {
            info.complete = false;
            return;
        };
        const import_name = content[value_start..value_end];
        cursor = value_end + 1;

        if (std.mem.eql(u8, import_name, "std") or
            std.mem.eql(u8, import_name, "builtin") or
            std.mem.eql(u8, import_name, "root")) continue;

        if (!std.mem.endsWith(u8, import_name, ".zig") or
            std.mem.indexOfScalar(u8, import_name, '\\') != null)
        {
            info.complete = false;
            continue;
        }

        const parent = std.fs.path.dirname(importer_path) orelse ".";
        const dependency = try std.fs.path.resolveAlloc(info.allocator, &.{ parent, import_name });
        if (try info.add(dependency)) try scanImports(info, dependency);
    }
}

/// Simple watcher for explicitly registered paths.
pub const FileWatcher = struct {
    allocator: std.mem.Allocator,
    watch_paths: std.ArrayList([]const u8),
    file_stamps: std.StringHashMap(?FileStamp),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator, .watch_paths = .empty, .file_stamps = .init(allocator) };
    }

    pub fn deinit(self: *Self) void {
        for (self.watch_paths.items) |path| self.allocator.free(path);
        self.watch_paths.deinit(self.allocator);
        self.file_stamps.deinit();
    }

    pub fn addPath(self: *Self, path: []const u8) !void {
        const path_copy = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(path_copy);
        try self.watch_paths.append(self.allocator, path_copy);
        errdefer _ = self.watch_paths.pop();
        var threaded: std.Io.Threaded = .init(self.allocator, .{ .environ = .empty });
        defer threaded.deinit();
        const initial: ?FileStamp = if (std.Io.Dir.cwd().statFile(threaded.io(), path_copy, .{})) |stat|
            .{ .modified_ns = stat.mtime.nanoseconds, .size = stat.size }
        else |_|
            null;
        try self.file_stamps.put(path_copy, initial);
    }

    pub fn hasChanges(self: *Self) !bool {
        var threaded: std.Io.Threaded = .init(self.allocator, .{ .environ = .empty });
        defer threaded.deinit();
        var changed = false;
        for (self.watch_paths.items) |path| {
            const current: ?FileStamp = if (std.Io.Dir.cwd().statFile(threaded.io(), path, .{})) |stat|
                .{ .modified_ns = stat.mtime.nanoseconds, .size = stat.size }
            else |_|
                null;
            const previous = self.file_stamps.get(path) orelse null;
            if (!std.meta.eql(current, previous)) changed = true;
            try self.file_stamps.put(path, current);
        }
        return changed;
    }
};

test "WatchOptions default values" {
    const options = WatchOptions{};
    try std.testing.expectEqualStrings(".", options.watch_dir);
    try std.testing.expectEqualStrings(".", options.project_root);
    try std.testing.expectEqualStrings("*.test.zig", options.pattern);
    try std.testing.expect(options.recursive);
    try std.testing.expectEqual(@as(u64, 300), options.debounce_ms);
    try std.testing.expect(options.clear_screen);
    try std.testing.expect(!options.interactive_commands);
}

test "test pattern classification handles wildcard and exact patterns" {
    try std.testing.expect(isTestPath("tests/math.test.zig", "*.test.zig"));
    try std.testing.expect(!isTestPath("src/math.zig", "*.test.zig"));
    try std.testing.expect(isTestPath("tests/specific.zig", "specific.zig"));
}

test "snapshot diff reports additions modifications and deletions" {
    const allocator = std.testing.allocator;
    var old = Snapshot.init(allocator);
    defer old.deinit();
    try old.put(try allocator.dupe(u8, "deleted.zig"), .{ .modified_ns = 1, .size = 1 });
    try old.put(try allocator.dupe(u8, "modified.zig"), .{ .modified_ns = 1, .size = 1 });
    var current = Snapshot.init(allocator);
    defer current.deinit();
    try current.put(try allocator.dupe(u8, "added.zig"), .{ .modified_ns = 1, .size = 1 });
    try current.put(try allocator.dupe(u8, "modified.zig"), .{ .modified_ns = 2, .size = 1 });

    var changes = try current.changesSince(&old, allocator);
    defer changes.deinit();
    try std.testing.expectEqual(@as(usize, 3), changes.items.items.len);
}

test "affected selection handles direct tests dependencies and safe fallbacks" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    defer allocator.free(root);
    const tests_dir = try std.fs.path.join(allocator, &.{ root, "tests" });
    defer allocator.free(tests_dir);
    const src_dir = try std.fs.path.join(allocator, &.{ root, "src" });
    defer allocator.free(src_dir);
    try compat.makePath(allocator, tests_dir);
    try compat.makePath(allocator, src_dir);

    const helper_path = try std.fs.path.join(allocator, &.{ src_dir, "helper.zig" });
    defer allocator.free(helper_path);
    const math_path = try std.fs.path.join(allocator, &.{ src_dir, "math.zig" });
    defer allocator.free(math_path);
    const test_path = try std.fs.path.join(allocator, &.{ tests_dir, "math.test.zig" });
    defer allocator.free(test_path);
    try compat.writeFile(allocator, helper_path, "pub const value = 1;\n");
    try compat.writeFile(allocator, math_path, "pub const helper = @import(\"helper.zig\");\n");
    try compat.writeFile(allocator, test_path, "const math = @import(\"../src/math.zig\");\ntest \"math\" { _ = math; }\n");

    var discovered = discovery.DiscoveryResult.init(allocator);
    defer discovered.deinit();
    try discovered.addFile(test_path, "math.test.zig", "math.test.zig");
    const normalized_test = try std.fs.path.resolveAlloc(allocator, &.{test_path});
    defer allocator.free(normalized_test);
    const normalized_helper = try std.fs.path.resolveAlloc(allocator, &.{helper_path});
    defer allocator.free(normalized_helper);
    const options = WatchOptions{ .watch_dir = tests_dir, .project_root = root };

    var direct = try planAffected(allocator, options, &discovered, &.{.{
        .path = normalized_test,
        .kind = .modified,
    }});
    defer direct.deinit();
    try std.testing.expect(direct.full_run == null);
    try std.testing.expectEqual(@as(usize, 1), direct.tests.items.len);
    try std.testing.expectEqual(SelectionReason.changed_test, direct.tests.items[0].reason);

    var added = try planAffected(allocator, options, &discovered, &.{.{
        .path = normalized_test,
        .kind = .added,
    }});
    defer added.deinit();
    try std.testing.expect(added.full_run == null);
    try std.testing.expectEqual(@as(usize, 1), added.tests.items.len);

    var dependency = try planAffected(allocator, options, &discovered, &.{.{
        .path = normalized_helper,
        .kind = .modified,
    }});
    defer dependency.deinit();
    try std.testing.expect(dependency.full_run == null);
    try std.testing.expectEqual(@as(usize, 1), dependency.tests.items.len);
    try std.testing.expectEqual(SelectionReason.affected_source, dependency.tests.items[0].reason);

    var deleted = try planAffected(allocator, options, &discovered, &.{.{
        .path = normalized_test,
        .kind = .deleted,
    }});
    defer deleted.deinit();
    try std.testing.expectEqual(FullRunReason.test_topology_changed, deleted.full_run.?);

    const opaque_path = try std.fs.path.join(allocator, &.{ tests_dir, "opaque.test.zig" });
    defer allocator.free(opaque_path);
    try compat.writeFile(allocator, opaque_path, "const app = @import(\"app\");\ntest \"opaque\" { _ = app; }\n");
    try discovered.addFile(opaque_path, "opaque.test.zig", "opaque.test.zig");
    var fallback = try planAffected(allocator, options, &discovered, &.{.{
        .path = normalized_helper,
        .kind = .modified,
    }});
    defer fallback.deinit();
    try std.testing.expectEqual(FullRunReason.dependency_information_unavailable, fallback.full_run.?);
}

test "FileWatcher initialization" {
    var watcher = FileWatcher.init(std.testing.allocator);
    defer watcher.deinit();
    try std.testing.expectEqual(@as(usize, 0), watcher.watch_paths.items.len);
}
