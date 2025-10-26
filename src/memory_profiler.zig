const std = @import("std");
const suite = @import("suite.zig");

/// Memory profiling options
pub const ProfileOptions = struct {
    /// Enable memory profiling
    enabled: bool = false,
    /// Detect memory leaks
    detect_leaks: bool = true,
    /// Track peak memory usage
    track_peak: bool = true,
    /// Report threshold in bytes (only report if usage exceeds this)
    report_threshold: usize = 0,
    /// Fail tests on memory leaks
    fail_on_leak: bool = false,
};

/// Memory statistics for a single test
pub const MemoryStats = struct {
    /// Total bytes allocated
    total_allocated: usize = 0,
    /// Total bytes freed
    total_freed: usize = 0,
    /// Peak memory usage
    peak_usage: usize = 0,
    /// Current memory usage
    current_usage: usize = 0,
    /// Number of allocations
    allocation_count: usize = 0,
    /// Number of frees
    free_count: usize = 0,
    /// Memory leaked (allocated - freed)
    leaked: usize = 0,

    pub fn hasLeak(self: MemoryStats) bool {
        return self.leaked > 0;
    }

    pub fn format(
        self: MemoryStats,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("Memory Stats:\n", .{});
        try writer.print("  Allocated: {d} bytes ({d} allocations)\n", .{ self.total_allocated, self.allocation_count });
        try writer.print("  Freed: {d} bytes ({d} frees)\n", .{ self.total_freed, self.free_count });
        try writer.print("  Peak: {d} bytes\n", .{self.peak_usage});
        try writer.print("  Leaked: {d} bytes\n", .{self.leaked});

        if (self.hasLeak()) {
            try writer.print("  ⚠️  MEMORY LEAK DETECTED!\n", .{});
        }
    }
};

/// Profiling allocator that tracks memory usage
pub const ProfilingAllocator = struct {
    parent_allocator: std.mem.Allocator,
    stats: *MemoryStats,

    const Self = @This();

    pub fn init(parent_allocator: std.mem.Allocator, stats: *MemoryStats) Self {
        return .{
            .parent_allocator = parent_allocator,
            .stats = stats,
        };
    }

    pub fn allocator(self: *Self) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
                .remap = remap,
            },
        };
    }

    fn remap(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = new_len;
        _ = ret_addr;
        return null; // We don't support remap, let the allocator fall back
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));

        const result = self.parent_allocator.rawAlloc(len, ptr_align, ret_addr);

        if (result) |_| {
            self.stats.total_allocated += len;
            self.stats.current_usage += len;
            self.stats.allocation_count += 1;

            if (self.stats.current_usage > self.stats.peak_usage) {
                self.stats.peak_usage = self.stats.current_usage;
            }
        }

        return result;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *Self = @ptrCast(@alignCast(ctx));

        const result = self.parent_allocator.rawResize(buf, buf_align, new_len, ret_addr);

        if (result) {
            const old_len = buf.len;
            if (new_len > old_len) {
                const diff = new_len - old_len;
                self.stats.total_allocated += diff;
                self.stats.current_usage += diff;

                if (self.stats.current_usage > self.stats.peak_usage) {
                    self.stats.peak_usage = self.stats.current_usage;
                }
            } else {
                const diff = old_len - new_len;
                self.stats.total_freed += diff;
                self.stats.current_usage -= diff;
            }
        }

        return result;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        const self: *Self = @ptrCast(@alignCast(ctx));

        self.parent_allocator.rawFree(buf, buf_align, ret_addr);

        self.stats.total_freed += buf.len;
        self.stats.current_usage -= buf.len;
        self.stats.free_count += 1;
    }
};

/// Memory profiler for tests
pub const MemoryProfiler = struct {
    allocator: std.mem.Allocator,
    options: ProfileOptions,
    test_stats: std.StringHashMap(MemoryStats),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, options: ProfileOptions) Self {
        return .{
            .allocator = allocator,
            .options = options,
            .test_stats = std.StringHashMap(MemoryStats).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.test_stats.deinit();
    }

    /// Create a profiling allocator for a test
    pub fn createTestAllocator(self: *Self, test_name: []const u8) !ProfilingAllocator {
        const stats = try self.allocator.create(MemoryStats);
        stats.* = .{};

        try self.test_stats.put(test_name, stats.*);

        return ProfilingAllocator.init(self.allocator, stats);
    }

    /// Get statistics for a test
    pub fn getStats(self: *Self, test_name: []const u8) ?MemoryStats {
        return self.test_stats.get(test_name);
    }

    /// Update final stats for a test
    pub fn finalizeTest(self: *Self, test_name: []const u8, stats: MemoryStats) !void {
        var final_stats = stats;
        final_stats.leaked = final_stats.total_allocated - final_stats.total_freed;

        try self.test_stats.put(test_name, final_stats);
    }

    /// Print memory report
    pub fn printReport(self: *Self) !void {
        std.debug.print("\n==================== Memory Profile Report ====================\n\n", .{});

        var total_allocated: usize = 0;
        var total_leaked: usize = 0;
        var tests_with_leaks: usize = 0;

        var iterator = self.test_stats.iterator();
        while (iterator.next()) |entry| {
            const test_name = entry.key_ptr.*;
            const stats = entry.value_ptr.*;

            total_allocated += stats.total_allocated;
            if (stats.hasLeak()) {
                total_leaked += stats.leaked;
                tests_with_leaks += 1;
            }

            // Only print if above threshold
            if (stats.total_allocated >= self.options.report_threshold) {
                std.debug.print("Test: {s}\n", .{test_name});
                std.debug.print("{}\n\n", .{stats});
            }
        }

        std.debug.print("Summary:\n", .{});
        std.debug.print("  Total Allocated: {d} bytes\n", .{total_allocated});
        std.debug.print("  Total Leaked: {d} bytes\n", .{total_leaked});
        std.debug.print("  Tests with Leaks: {d}/{d}\n", .{ tests_with_leaks, self.test_stats.count() });

        if (tests_with_leaks > 0) {
            std.debug.print("\n⚠️  WARNING: Memory leaks detected in {d} test(s)!\n", .{tests_with_leaks});
        } else {
            std.debug.print("\n✓ No memory leaks detected!\n", .{});
        }

        std.debug.print("\n================================================================\n", .{});
    }

    /// Check if any tests have memory leaks
    pub fn hasLeaks(self: *Self) bool {
        var iterator = self.test_stats.iterator();
        while (iterator.next()) |entry| {
            if (entry.value_ptr.hasLeak()) {
                return true;
            }
        }
        return false;
    }
};

/// Format bytes in human-readable format
pub fn formatBytes(bytes: usize) []const u8 {
    if (bytes < 1024) {
        return std.fmt.allocPrint(std.heap.page_allocator, "{d} B", .{bytes}) catch "? B";
    } else if (bytes < 1024 * 1024) {
        return std.fmt.allocPrint(std.heap.page_allocator, "{d:.2} KB", .{@as(f64, @floatFromInt(bytes)) / 1024.0}) catch "? KB";
    } else if (bytes < 1024 * 1024 * 1024) {
        return std.fmt.allocPrint(std.heap.page_allocator, "{d:.2} MB", .{@as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0)}) catch "? MB";
    } else {
        return std.fmt.allocPrint(std.heap.page_allocator, "{d:.2} GB", .{@as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0 * 1024.0)}) catch "? GB";
    }
}

// Tests
test "MemoryStats default values" {
    const stats = MemoryStats{};

    try std.testing.expectEqual(@as(usize, 0), stats.total_allocated);
    try std.testing.expectEqual(@as(usize, 0), stats.total_freed);
    try std.testing.expectEqual(@as(usize, 0), stats.leaked);
    try std.testing.expectEqual(false, stats.hasLeak());
}

test "ProfilingAllocator tracks allocations" {
    const allocator = std.testing.allocator;

    var stats = MemoryStats{};
    var profiling_alloc = ProfilingAllocator.init(allocator, &stats);
    const tracked_allocator = profiling_alloc.allocator();

    // Allocate some memory
    const data = try tracked_allocator.alloc(u8, 100);
    defer tracked_allocator.free(data);

    try std.testing.expectEqual(@as(usize, 100), stats.total_allocated);
    try std.testing.expectEqual(@as(usize, 1), stats.allocation_count);
    try std.testing.expectEqual(@as(usize, 100), stats.peak_usage);
}

test "MemoryProfiler initialization" {
    const allocator = std.testing.allocator;

    var profiler = MemoryProfiler.init(allocator, .{});
    defer profiler.deinit();

    try std.testing.expectEqual(@as(usize, 0), profiler.test_stats.count());
}
