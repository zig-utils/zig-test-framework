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
        const ft = std.os.windows.GetSystemTimeAsFileTime();
        const EPOCH_DIFF: i128 = 11644473600 * 1_000_000_000;
        const intervals: i128 = @as(i128, @as(u64, ft.dwHighDateTime) << 32 | @as(u64, ft.dwLowDateTime));
        return intervals * 100 - EPOCH_DIFF;
    } else {
        const clock = getRealtimeClock();
        return @as(i128, clock.sec) * 1_000_000_000 + @as(i128, clock.nsec);
    }
}

/// Get current wall-clock time in milliseconds since Unix epoch.
/// Replaces std.time.milliTimestamp() which was removed in Zig 0.16.
pub fn milliTimestamp() i64 {
    if (comptime builtin.os.tag == .windows) {
        const ft = std.os.windows.GetSystemTimeAsFileTime();
        const EPOCH_DIFF: i64 = 11644473600000;
        const intervals: i64 = @bitCast(@as(u64, ft.dwHighDateTime) << 32 | @as(u64, ft.dwLowDateTime));
        return @divFloor(intervals, 10000) - EPOCH_DIFF;
    } else {
        const clock = getRealtimeClock();
        return @as(i64, clock.sec) * 1000 + @divFloor(@as(i64, clock.nsec), 1_000_000);
    }
}

// ============================================================
// Sleep utility (std.Thread.sleep removed in 0.16)
// ============================================================

/// Sleep for the given number of nanoseconds.
/// Replaces std.Thread.sleep() which was removed in Zig 0.16.
pub fn sleep(ns: u64) void {
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
// File descriptor close wrapper
// ============================================================

/// Close a file descriptor using libc.
/// Replaces std.posix.close() which was removed in Zig 0.16.
fn closeFd(fd: std.posix.fd_t) void {
    _ = std.c.close(fd);
}

// ============================================================
// File I/O helpers (std.fs.cwd() removed, needs std.Io now)
// ============================================================

/// Read entire file contents using POSIX APIs.
/// Replaces std.fs.cwd().openFile() + file.readToEndAlloc().
pub fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);

    const fd = std.posix.openatZ(std.posix.AT.FDCWD, path_z, .{}, 0) catch |err| {
        if (err == error.FileNotFound) return error.FileNotFound;
        return err;
    };
    defer closeFd(fd);

    // Read file in chunks
    var result = std.ArrayList(u8).empty;
    errdefer result.deinit(allocator);

    var buf: [4096]u8 = undefined;
    while (true) {
        const n = std.posix.read(fd, &buf) catch |err| return err;
        if (n == 0) break;
        try result.appendSlice(allocator, buf[0..n]);
    }

    return result.toOwnedSlice(allocator);
}

/// Write content to a file using POSIX APIs.
/// Replaces std.fs.cwd().createFile() + file.writeAll().
pub fn writeFile(allocator: std.mem.Allocator, path: []const u8, content: []const u8) !void {
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);

    const fd = std.posix.openatZ(std.posix.AT.FDCWD, path_z, .{
        .ACCMODE = .WRONLY,
        .CREAT = true,
        .TRUNC = true,
    }, 0o644) catch |err| return err;
    defer closeFd(fd);

    var remaining = content;
    while (remaining.len > 0) {
        const rc = std.c.write(fd, remaining.ptr, remaining.len);
        if (rc < 0) return error.Unexpected;
        const written: usize = @intCast(rc);
        remaining = remaining[written..];
    }
}

/// Delete a file using POSIX APIs.
/// Replaces std.fs.cwd().deleteFile().
pub fn deleteFile(allocator: std.mem.Allocator, path: []const u8) !void {
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);
    const rc = std.c.unlink(path_z);
    if (rc != 0) {
        switch (std.c.errno(rc)) {
            .NOENT => return error.FileNotFound,
            else => return error.Unexpected,
        }
    }
}

/// Create directories recursively using POSIX APIs.
/// Replaces std.fs.cwd().makePath().
pub fn makePath(allocator: std.mem.Allocator, path: []const u8) !void {
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);

    const rc = std.c.mkdir(path_z, 0o755);
    if (rc == 0) return;

    switch (std.c.errno(rc)) {
        .EXIST => return, // Already exists
        .NOENT => {
            // Parent doesn't exist, find and create it
            if (std.mem.lastIndexOfScalar(u8, path, '/')) |sep| {
                if (sep > 0) {
                    try makePath(allocator, path[0..sep]);
                    // Retry creating the directory
                    const retry_z = try allocator.dupeZ(u8, path);
                    defer allocator.free(retry_z);
                    const rc2 = std.c.mkdir(retry_z, 0o755);
                    if (rc2 != 0 and std.c.errno(rc2) != .EXIST) {
                        return error.Unexpected;
                    }
                }
            }
        },
        else => return error.Unexpected,
    }
}

// ============================================================
// Directory iteration (std.fs.openDirAbsolute removed in 0.16)
// ============================================================

/// Entry from directory iteration
pub const DirEntry = struct {
    name: []const u8,
    kind: enum { file, directory, sym_link, other },
};

/// A simple directory iterator using POSIX APIs.
/// Replaces std.fs.openDirAbsolute() + dir.iterate() which was removed in Zig 0.16.
pub const DirIterator = struct {
    dir: *std.c.DIR,
    path_buf: [1024]u8,

    pub fn open(dir_path: []const u8) !DirIterator {
        var path_buf: [1024:0]u8 = @splat(0);
        if (dir_path.len >= path_buf.len) return error.NameTooLong;
        @memcpy(path_buf[0..dir_path.len], dir_path);

        const dir = std.c.opendir(&path_buf);
        if (dir == null) return error.FileNotFound;
        return .{
            .dir = dir.?,
            .path_buf = undefined,
        };
    }

    pub fn next(self: *DirIterator) !?DirEntry {
        while (true) {
            const entry_opt = std.c.readdir(self.dir);
            if (entry_opt == null) return null;
            const entry = entry_opt.?;

            // Get name as slice
            const name_ptr: [*]const u8 = @ptrCast(&entry.name);
            const name_len = if (@hasField(@TypeOf(entry.*), "namlen"))
                entry.namlen
            else
                std.mem.indexOfScalar(u8, name_ptr[0..256], 0) orelse 256;
            const name = name_ptr[0..name_len];

            // Skip . and ..
            if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;

            return .{
                .name = name,
                .kind = switch (entry.type) {
                    std.c.DT.DIR => .directory,
                    std.c.DT.REG => .file,
                    std.c.DT.LNK => .sym_link,
                    else => .other,
                },
            };
        }
    }

    pub fn close(self: *DirIterator) void {
        _ = std.c.closedir(self.dir);
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
/// Replaces std.process.Child.init() + spawnAndWait() which was removed in Zig 0.16.
pub fn spawnAndWait(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    stdout_behavior: StdBehavior,
    stderr_behavior: StdBehavior,
) !SpawnResult {
    if (argv.len == 0) return error.InvalidArgument;

    // Convert argv to null-terminated C strings
    const c_argv = try allocator.alloc(?[*:0]const u8, argv.len + 1);
    defer allocator.free(c_argv);

    for (argv, 0..) |arg, i| {
        const z = try allocator.dupeZ(u8, arg);
        c_argv[i] = z.ptr;
    }
    c_argv[argv.len] = null;

    // Fork
    const pid = std.c.fork();
    if (pid < 0) return error.ForkFailed;

    if (pid == 0) {
        // Child process
        // Handle stdout
        switch (stdout_behavior) {
            .Ignore => {
                const dev_null: [*:0]const u8 = "/dev/null";
                const null_fd = std.posix.openatZ(std.posix.AT.FDCWD, dev_null, .{ .ACCMODE = .WRONLY }, 0) catch std.process.exit(127);
                if (std.c.dup2(null_fd, 1) < 0) std.process.exit(127);
                closeFd(null_fd);
            },
            else => {},
        }

        // Handle stderr
        switch (stderr_behavior) {
            .Ignore => {
                const dev_null: [*:0]const u8 = "/dev/null";
                const null_fd = std.posix.openatZ(std.posix.AT.FDCWD, dev_null, .{ .ACCMODE = .WRONLY }, 0) catch std.process.exit(127);
                if (std.c.dup2(null_fd, 2) < 0) std.process.exit(127);
                closeFd(null_fd);
            },
            else => {},
        }

        // Exec - use execve with PATH lookup and current environment
        const envp: [*:null]const ?[*:0]const u8 = @ptrCast(std.c.environ);

        // Try direct execution first
        _ = std.c.execve(c_argv[0].?, @ptrCast(c_argv.ptr), envp);

        // If direct exec failed, try PATH lookup
        const cmd = std.mem.sliceTo(c_argv[0].?, 0);
        if (std.mem.indexOfScalar(u8, cmd, '/') == null) {
            // Search PATH
            var path_search: ?[*:0]const u8 = null;
            var env_idx: usize = 0;
            while (std.c.environ[env_idx]) |env_entry| : (env_idx += 1) {
                const entry = std.mem.sliceTo(env_entry, 0);
                if (std.mem.startsWith(u8, entry, "PATH=")) {
                    path_search = @ptrCast(env_entry + 5);
                    break;
                }
            }

            if (path_search) |path_val| {
                const path_str = std.mem.sliceTo(path_val, 0);
                var path_iter = std.mem.splitScalar(u8, path_str, ':');
                while (path_iter.next()) |dir| {
                    var full_path: [1024:0]u8 = @splat(0);
                    if (dir.len + 1 + cmd.len < full_path.len) {
                        @memcpy(full_path[0..dir.len], dir);
                        full_path[dir.len] = '/';
                        @memcpy(full_path[dir.len + 1 ..][0..cmd.len], cmd);
                        _ = std.c.execve(&full_path, @ptrCast(c_argv.ptr), envp);
                    }
                }
            }
        }
        std.process.exit(127);
    }

    // Parent process - free the duped strings
    for (argv, 0..) |_, i| {
        const z: [*:0]const u8 = c_argv[i].?;
        const len = std.mem.len(z);
        allocator.free(z[0 .. len + 1]);
    }

    // Wait for child
    var status: c_int = 0;
    const wait_result = std.c.waitpid(pid, &status, 0);
    if (wait_result < 0) return error.WaitFailed;

    const ustatus: u32 = @bitCast(status);

    // Check if exited normally (WIFEXITED)
    if (ustatus & 0x7f == 0) {
        // WEXITSTATUS
        const exit_code: u8 = @intCast((ustatus >> 8) & 0xff);
        return .{ .Exited = exit_code };
    }

    // Signal
    const sig = ustatus & 0x7f;
    return .{ .Signal = sig };
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

// ============================================================
// Signal handler type
// ============================================================

/// The signal type used in signal handlers.
/// In Zig 0.16, this changed from c_int to std.posix.SIG enum.
pub const SignalType = std.posix.SIG;
