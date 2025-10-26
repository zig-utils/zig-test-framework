const std = @import("std");

/// Test file discovery options
pub const DiscoveryOptions = struct {
    /// Root directory to start searching from
    root_path: []const u8 = ".",
    /// Pattern to match test files (default: "*.test.zig")
    pattern: []const u8 = "*.test.zig",
    /// Whether to search recursively
    recursive: bool = true,
    /// Directories to exclude from search
    exclude_dirs: []const []const u8 = &.{ "zig-cache", "zig-out", ".git", "node_modules" },
};

/// Discovered test file
pub const TestFile = struct {
    /// Full path to the test file
    path: []const u8,
    /// Relative path from root
    relative_path: []const u8,
    /// File name only
    name: []const u8,

    pub fn deinit(self: *TestFile, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        allocator.free(self.relative_path);
        allocator.free(self.name);
    }
};

/// Test file discovery result
pub const DiscoveryResult = struct {
    files: std.ArrayList(TestFile),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DiscoveryResult {
        return DiscoveryResult{
            .files = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DiscoveryResult) void {
        for (self.files.items) |*file| {
            file.deinit(self.allocator);
        }
        self.files.deinit(self.allocator);
    }

    pub fn addFile(self: *DiscoveryResult, path: []const u8, relative_path: []const u8, name: []const u8) !void {
        const file = TestFile{
            .path = try self.allocator.dupe(u8, path),
            .relative_path = try self.allocator.dupe(u8, relative_path),
            .name = try self.allocator.dupe(u8, name),
        };
        try self.files.append(self.allocator, file);
    }
};

/// Discover test files in a directory
pub fn discoverTests(allocator: std.mem.Allocator, options: DiscoveryOptions) !DiscoveryResult {
    var result = DiscoveryResult.init(allocator);
    errdefer result.deinit();

    // Get absolute path of root
    const root_path = try std.fs.cwd().realpathAlloc(allocator, options.root_path);
    defer allocator.free(root_path);

    try scanDirectory(allocator, &result, root_path, root_path, options);

    return result;
}

/// Recursively scan a directory for test files
fn scanDirectory(
    allocator: std.mem.Allocator,
    result: *DiscoveryResult,
    root_path: []const u8,
    current_path: []const u8,
    options: DiscoveryOptions,
) !void {
    var dir = std.fs.openDirAbsolute(current_path, .{ .iterate = true }) catch |err| {
        // Skip directories we can't open (permission issues, etc.)
        std.debug.print("Warning: Cannot open directory {s}: {any}\n", .{ current_path, err });
        return;
    };
    defer dir.close();

    var iterator = dir.iterate();

    while (try iterator.next()) |entry| {
        // Build full path
        const full_path = try std.fs.path.join(allocator, &.{ current_path, entry.name });
        defer allocator.free(full_path);

        switch (entry.kind) {
            .directory => {
                if (!options.recursive) continue;

                // Check if directory should be excluded
                var should_exclude = false;
                for (options.exclude_dirs) |exclude_dir| {
                    if (std.mem.eql(u8, entry.name, exclude_dir)) {
                        should_exclude = true;
                        break;
                    }
                }

                if (!should_exclude) {
                    try scanDirectory(allocator, result, root_path, full_path, options);
                }
            },
            .file => {
                // Check if file matches the pattern
                if (matchesPattern(entry.name, options.pattern)) {
                    // Calculate relative path from root
                    const relative_path = if (std.mem.startsWith(u8, full_path, root_path))
                        full_path[root_path.len..]
                    else
                        full_path;

                    // Skip leading slash in relative path
                    const clean_relative = if (relative_path.len > 0 and relative_path[0] == '/')
                        relative_path[1..]
                    else
                        relative_path;

                    try result.addFile(full_path, clean_relative, entry.name);
                }
            },
            else => {
                // Skip other types (symlinks, etc.)
            },
        }
    }
}

/// Check if a filename matches the pattern
fn matchesPattern(filename: []const u8, pattern: []const u8) bool {
    // Simple pattern matching - check if filename ends with pattern
    // For "*.test.zig", we check if filename ends with ".test.zig"
    if (std.mem.startsWith(u8, pattern, "*")) {
        const suffix = pattern[1..];
        return std.mem.endsWith(u8, filename, suffix);
    }

    // Exact match
    return std.mem.eql(u8, filename, pattern);
}

// Tests
test "matchesPattern with *.test.zig" {
    try std.testing.expect(matchesPattern("foo.test.zig", "*.test.zig"));
    try std.testing.expect(matchesPattern("bar.test.zig", "*.test.zig"));
    try std.testing.expect(!matchesPattern("foo.zig", "*.test.zig"));
    try std.testing.expect(!matchesPattern("test.zig", "*.test.zig"));
}

test "matchesPattern with exact match" {
    try std.testing.expect(matchesPattern("test.zig", "test.zig"));
    try std.testing.expect(!matchesPattern("other.zig", "test.zig"));
}
