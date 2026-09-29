/// Compatibility layer for Zig 0.16 API changes.
/// Provides wrappers for APIs that changed between Zig versions.
const std = @import("std");
const builtin = @import("builtin");

// ============================================================
// Time utilities (std.time.milliTimestamp removed in 0.16)
// ============================================================

/// Get clock_gettime result as seconds and nanoseconds.
fn getRealtimeClock() struct { sec: i64, nsec: i64 } {
    if (comptime builtin.os.tag == .linux or builtin.os.tag == .macos or
        builtin.os.tag == .ios or builtin.os.tag == .tvos or
        builtin.os.tag == .watchos or builtin.os.tag == .visionos or
        builtin.os.tag == .freebsd or builtin.os.tag == .netbsd or
        builtin.os.tag == .openbsd or builtin.os.tag == .dragonfly)
    {
        var ts: std.c.timespec = .{ .sec = 0, .nsec = 0 };
        const rc = std.c.clock_gettime(std.c.CLOCK.REALTIME, &ts);
        if (rc == 0) {
            return .{ .sec = ts.sec, .nsec = ts.nsec };
        }
    }
    return .{ .sec = 0, .nsec = 0 };
}

/// Get current wall-clock time in nanoseconds since Unix epoch.
/// Replaces std.time.nanoTimestamp() which was removed in Zig 0.16.
pub fn nanoTimestamp() i128 {
    if (comptime builtin.os.tag == .windows) {
        const intervals: i128 = @intCast(std.os.windows.ntdll.RtlGetSystemTimePrecise());
        const epoch_ns: i128 = std.time.epoch.windows * std.time.ns_per_s;
        return intervals * 100 + epoch_ns;
    } else {
        const clock = getRealtimeClock();
        return @as(i128, clock.sec) * 1_000_000_000 + @as(i128, clock.nsec);
    }
}

/// Get current wall-clock time in milliseconds since Unix epoch.
/// Replaces std.time.milliTimestamp() which was removed in Zig 0.16.
pub fn milliTimestamp() i64 {
    return @intCast(@divFloor(nanoTimestamp(), std.time.ns_per_ms));
}

// ============================================================
// Sleep utility (std.Thread.sleep removed in 0.16)
// ============================================================

/// Sleep for the given number of nanoseconds.
/// Replaces std.Thread.sleep() which was removed in Zig 0.16.
pub fn sleep(ns: u64) void {
    if (comptime builtin.os.tag == .windows) {
        var interval: std.os.windows.LARGE_INTEGER = -@as(i64, @intCast(@max(ns / 100, 1)));
        _ = std.os.windows.ntdll.NtDelayExecution(.FALSE, &interval);
        return;
    }

    const s: isize = @intCast(ns / std.time.ns_per_s);
    const remaining_ns: isize = @intCast(ns % std.time.ns_per_s);
    var ts: std.c.timespec = .{ .sec = s, .nsec = remaining_ns };
    while (true) {
        const rc = std.c.nanosleep(&ts, &ts);
        if (rc == 0) break;
        // On EINTR, retry with remaining time
        continue;
    }
}

// ============================================================
// Mutex (std.Thread.Mutex removed in 0.16-dev.2736+)
// Uses simple spinlock via atomics since std.Io.Mutex needs Io.
// ============================================================

/// Simple spinlock mutex for use without Io.
/// Replaces std.Thread.Mutex which was removed in Zig 0.16.
pub const Mutex = struct {
    state: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

    pub fn lock(self: *Mutex) void {
        while (self.state.cmpxchgWeak(0, 1, .acquire, .monotonic) != null) {
            // Spin
            std.atomic.spinLoopHint();
        }
    }

    pub fn unlock(self: *Mutex) void {
        self.state.store(0, .release);
    }

    pub fn tryLock(self: *Mutex) bool {
        return self.state.cmpxchgStrong(0, 1, .acquire, .monotonic) == null;
    }
};

// ============================================================
// File I/O helpers (std.fs.cwd() removed, needs std.Io now)
// ============================================================

fn initIo(allocator: std.mem.Allocator) std.Io.Threaded {
    return .init(allocator, .{ .environ = currentEnviron() });
}

fn currentEnviron() std.process.Environ {
    return if (comptime builtin.os.tag == .windows)
        .{ .block = .global }
    else
        .{ .block = .{ .slice = std.mem.span(std.c.environ) } };
}

/// Read entire file contents using portable Zig I/O.
/// Replaces std.fs.cwd().openFile() + file.readToEndAlloc().
pub fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    var threaded = initIo(allocator);
    defer threaded.deinit();
    return std.Io.Dir.cwd().readFileAlloc(threaded.io(), path, allocator, .unlimited);
}

/// Write content to a file using portable Zig I/O.
/// Replaces std.fs.cwd().createFile() + file.writeAll().
pub fn writeFile(allocator: std.mem.Allocator, path: []const u8, content: []const u8) !void {
    var threaded = initIo(allocator);
    defer threaded.deinit();
    try std.Io.Dir.cwd().writeFile(threaded.io(), .{ .sub_path = path, .data = content });
}

/// Delete a file using portable Zig I/O.
/// Replaces std.fs.cwd().deleteFile().
pub fn deleteFile(allocator: std.mem.Allocator, path: []const u8) !void {
    var threaded = initIo(allocator);
    defer threaded.deinit();
    try std.Io.Dir.cwd().deleteFile(threaded.io(), path);
}

/// Delete an empty directory using portable Zig I/O.
/// Replaces std.fs.cwd().deleteDir().
pub fn deleteDir(allocator: std.mem.Allocator, path: []const u8) !void {
    var threaded = initIo(allocator);
    defer threaded.deinit();
    try std.Io.Dir.cwd().deleteDir(threaded.io(), path);
}

/// Create directories recursively using portable Zig I/O.
/// Replaces std.fs.cwd().makePath().
pub fn makePath(allocator: std.mem.Allocator, path: []const u8) !void {
    var threaded = initIo(allocator);
    defer threaded.deinit();
    try std.Io.Dir.cwd().createDirPath(threaded.io(), path);
}

// ============================================================
// Directory iteration (std.fs.openDirAbsolute removed in 0.16)
// ============================================================

/// Entry from directory iteration
pub const DirEntry = struct {
    name: []const u8,
    kind: enum { file, directory, sym_link, other },
};

/// A simple directory iterator using portable Zig I/O.
/// Replaces std.fs.openDirAbsolute() + dir.iterate() which was removed in Zig 0.16.
pub const DirIterator = struct {
    threaded: *std.Io.Threaded,
    dir: std.Io.Dir,
    iterator: std.Io.Dir.Iterator,

    pub fn open(dir_path: []const u8) !DirIterator {
        const threaded = try std.heap.page_allocator.create(std.Io.Threaded);
        errdefer std.heap.page_allocator.destroy(threaded);
        threaded.* = initIo(std.heap.page_allocator);
        errdefer threaded.deinit();

        const dir = try std.Io.Dir.cwd().openDir(threaded.io(), dir_path, .{ .iterate = true });
        return .{
            .threaded = threaded,
            .dir = dir,
            .iterator = dir.iterateAssumeFirstIteration(),
        };
    }

    pub fn next(self: *DirIterator) !?DirEntry {
        const entry = try self.iterator.next(self.threaded.io()) orelse return null;
        return .{
            .name = entry.name,
            .kind = switch (entry.kind) {
                .directory => .directory,
                .file => .file,
                .sym_link => .sym_link,
                else => .other,
            },
        };
    }

    pub fn close(self: *DirIterator) void {
        self.dir.close(self.threaded.io());
        self.threaded.deinit();
        std.heap.page_allocator.destroy(self.threaded);
    }
};

// ============================================================
// Child process spawning (std.process.Child.init removed in 0.16)
// ============================================================

/// Spawn behavior for stdout/stderr
pub const StdBehavior = enum {
    Inherit,
    Ignore,
    Pipe,
};

/// Result of spawning and waiting for a child process
pub const SpawnResult = union(enum) {
    Exited: u8,
    Signal: u32,
    Unknown: u32,
};

/// Spawn a child process and wait for it to complete.
/// Uses Zig's portable process API, including PATH lookup and Windows process
/// creation, while preserving the compatibility result used by callers.
pub fn spawnAndWait(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    stdout_behavior: StdBehavior,
    stderr_behavior: StdBehavior,
) !SpawnResult {
    if (argv.len == 0) return error.InvalidArgument;

    var threaded = initIo(allocator);
    defer threaded.deinit();
    const io = threaded.io();

    var child = try std.process.spawn(io, .{
        .argv = argv,
        .stdout = stdBehavior(stdout_behavior),
        .stderr = stdBehavior(stderr_behavior),
        .create_no_window = false,
    });
    const term = try child.wait(io);
    return switch (term) {
        .exited => |code| .{ .Exited = code },
        .signal => |signal| .{ .Signal = @backingInt(signal) },
        .stopped => |signal| .{ .Signal = @backingInt(signal) },
        .unknown => |status| .{ .Unknown = status },
    };
}

fn stdBehavior(behavior: StdBehavior) std.process.SpawnOptions.StdIo {
    return switch (behavior) {
        .Inherit, .Pipe => .inherit,
        .Ignore => .ignore,
    };
}

// ============================================================
// ArrayList writer replacement
// ============================================================

/// Format into an ArrayList(u8) using the allocator.
/// Replaces buffer.writer(allocator) pattern.
/// Returns the formatted string as an owned slice.
pub fn formatAlloc(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) ![]const u8 {
    return std.fmt.allocPrint(allocator, fmt, args);
}

// ============================================================
// ArrayList writer adapter
// ============================================================

/// A writer that appends to an ArrayList(u8), capturing the allocator.
/// Replaces the removed ArrayList.writer(allocator) API in Zig 0.16.
pub const ArrayListWriter = struct {
    list: *std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn init(list: *std.ArrayList(u8), allocator: std.mem.Allocator) ArrayListWriter {
        return .{ .list = list, .allocator = allocator };
    }

    pub fn writeAll(self: *ArrayListWriter, bytes: []const u8) !void {
        try self.list.appendSlice(self.allocator, bytes);
    }

    pub fn print(self: *ArrayListWriter, comptime fmt: []const u8, args: anytype) !void {
        try self.list.print(self.allocator, fmt, args);
    }

    pub fn writeByte(self: *ArrayListWriter, byte: u8) !void {
        try self.list.append(self.allocator, byte);
    }

    pub fn writeByteNTimes(self: *ArrayListWriter, byte: u8, n: usize) !void {
        for (0..n) |_| {
            try self.list.append(self.allocator, byte);
        }
    }
};

test "portable file helpers preserve nested paths" {
    const allocator = std.testing.allocator;
    const nonce = nanoTimestamp();
    const dir_path = try std.fmt.allocPrint(allocator, ".zig-cache/compat-{d}", .{nonce});
    defer allocator.free(dir_path);
    const file_path = try std.fs.path.join(allocator, &.{ dir_path, "roundtrip.txt" });
    defer allocator.free(file_path);

    try makePath(allocator, dir_path);
    defer deleteDir(allocator, dir_path) catch {};
    defer deleteFile(allocator, file_path) catch {};

    try writeFile(allocator, file_path, "portable");
    const contents = try readFileAlloc(allocator, file_path);
    defer allocator.free(contents);
    try std.testing.expectEqualStrings("portable", contents);
}

test "portable process helper preserves exit codes" {
    const argv: []const []const u8 = if (comptime builtin.os.tag == .windows)
        &.{ "cmd.exe", "/C", "exit", "7" }
    else
        &.{ "sh", "-c", "exit 7" };

    const result = try spawnAndWait(std.testing.allocator, argv, .Ignore, .Ignore);
    switch (result) {
        .Exited => |code| try std.testing.expectEqual(@as(u8, 7), code),
        else => return error.UnexpectedTermination,
    }
}
