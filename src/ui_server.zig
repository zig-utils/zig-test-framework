const std = @import("std");
const reporter_mod = @import("reporter.zig");
const suite = @import("suite.zig");
const test_history = @import("test_history.zig");

/// Options for the UI server
pub const UIServerOptions = struct {
    /// Port to listen on
    port: u16 = 8080,
    /// Host to bind to
    host: []const u8 = "127.0.0.1",
    /// Enable verbose logging
    verbose: bool = false,
};

/// UI Server for web-based test visualization
pub const UIServer = struct {
    allocator: std.mem.Allocator,
    options: UIServerOptions,
    server: ?std.net.Server = null,
    clients: std.ArrayList(*Client),
    mutex: std.Thread.Mutex = .{},
    history: ?*test_history.TestHistory = null,

    const Self = @This();

    /// Client connection for SSE
    pub const Client = struct {
        stream: std.net.Stream,
        allocator: std.mem.Allocator,
        active: bool = true,

        pub fn deinit(self: *Client) void {
            self.stream.close();
            self.active = false;
        }

        pub fn sendEvent(self: *Client, event: []const u8, data: []const u8) !void {
            if (!self.active) return;

            var buffer: [4096]u8 = undefined;
            const message = try std.fmt.bufPrint(&buffer, "event: {s}\ndata: {s}\n\n", .{ event, data });

            self.stream.writeAll(message) catch |err| {
                self.active = false;
                return err;
            };
        }
    };

    pub fn init(allocator: std.mem.Allocator, options: UIServerOptions) Self {
        return .{
            .allocator = allocator,
            .options = options,
            .clients = .empty,
        };
    }

    pub fn deinit(self: *Self) void {
        // Close all client connections
        for (self.clients.items) |client| {
            client.deinit();
            self.allocator.destroy(client);
        }
        self.clients.deinit(self.allocator);

        if (self.server) |*srv| {
            srv.deinit();
        }
    }

    /// Start the UI server
    pub fn start(self: *Self) !void {
        const address = try std.net.Address.parseIp(self.options.host, self.options.port);
        self.server = try address.listen(.{
            .reuse_address = true,
        });

        if (self.options.verbose) {
            std.debug.print("UI Server listening on http://{s}:{d}\n", .{ self.options.host, self.options.port });
        }
    }

    /// Accept a client connection (blocking)
    pub fn acceptClient(self: *Self) !void {
        if (self.server == null) return error.ServerNotStarted;

        const connection = try self.server.?.accept();
        try self.handleConnection(connection);
    }

    /// Handle an incoming connection
    fn handleConnection(self: *Self, connection: std.net.Server.Connection) !void {
        defer connection.stream.close();

        var buffer: [8192]u8 = undefined;
        const bytes_read = try connection.stream.read(&buffer);

        if (bytes_read == 0) return;

        const request = buffer[0..bytes_read];

        // Parse request line
        const request_line_end = std.mem.indexOf(u8, request, "\r\n") orelse return error.InvalidRequest;
        const request_line = request[0..request_line_end];

        // Extract method and path
        var parts = std.mem.splitSequence(u8, request_line, " ");
        const method = parts.next() orelse return error.InvalidRequest;
        const path = parts.next() orelse return error.InvalidRequest;

        if (self.options.verbose) {
            std.debug.print("{s} {s}\n", .{ method, path });
        }

        // Route the request
        if (std.mem.eql(u8, path, "/")) {
            try self.serveIndex(connection.stream);
        } else if (std.mem.eql(u8, path, "/events")) {
            try self.serveSSE(connection.stream);
        } else if (std.mem.eql(u8, path, "/api/tests")) {
            try self.serveTestsAPI(connection.stream);
        } else if (std.mem.eql(u8, path, "/api/history")) {
            try self.serveHistoryAPI(connection.stream);
        } else {
            try self.serve404(connection.stream);
        }
    }

    /// Serve the main index.html page
    fn serveIndex(self: *Self, stream: std.net.Stream) !void {
        _ = self;
        const html = @embedFile("ui/index.html");

        var response_buffer: [2048]u8 = undefined;
        const response = try std.fmt.bufPrint(&response_buffer,
            "HTTP/1.1 200 OK\r\n" ++
            "Content-Type: text/html; charset=utf-8\r\n" ++
            "Content-Length: {d}\r\n" ++
            "Connection: close\r\n" ++
            "\r\n" ++
            "{s}",
            .{ html.len, html },
        );

        try stream.writeAll(response);
    }

    /// Serve Server-Sent Events endpoint
    fn serveSSE(self: *Self, stream: std.net.Stream) !void {
        const response =
            "HTTP/1.1 200 OK\r\n" ++
            "Content-Type: text/event-stream\r\n" ++
            "Cache-Control: no-cache\r\n" ++
            "Connection: keep-alive\r\n" ++
            "\r\n";

        try stream.writeAll(response);

        // Create a new client and add to list
        const client = try self.allocator.create(Client);
        client.* = .{
            .stream = stream,
            .allocator = self.allocator,
            .active = true,
        };

        self.mutex.lock();
        try self.clients.append(self.allocator, client);
        self.mutex.unlock();

        // Send initial connection message
        try client.sendEvent("connected", "{}");
    }

    /// Serve tests API endpoint
    fn serveTestsAPI(self: *Self, stream: std.net.Stream) !void {
        _ = self;
        const json_response = "{\"status\": \"ok\", \"message\": \"Tests API\"}";

        var response_buffer: [1024]u8 = undefined;
        const response = try std.fmt.bufPrint(&response_buffer,
            "HTTP/1.1 200 OK\r\n" ++
            "Content-Type: application/json\r\n" ++
            "Content-Length: {d}\r\n" ++
            "Connection: close\r\n" ++
            "\r\n" ++
            "{s}",
            .{ json_response.len, json_response },
        );

        try stream.writeAll(response);
    }

    /// Serve history API endpoint
    fn serveHistoryAPI(self: *Self, stream: std.net.Stream) !void {
        if (self.history) |history| {
            var files = try history.listHistory();
            defer {
                for (files.items) |name| {
                    self.allocator.free(name);
                }
                files.deinit(self.allocator);
            }

            // Build JSON response
            var buffer = std.ArrayList(u8).empty;
            defer buffer.deinit(self.allocator);

            const writer = buffer.writer(self.allocator);
            try writer.writeAll("{\"files\":[");

            for (files.items, 0..) |filename, i| {
                try writer.print("\"{s}\"", .{filename});
                if (i < files.items.len - 1) {
                    try writer.writeAll(",");
                }
            }

            try writer.writeAll("]}");

            var response_buffer: [2048]u8 = undefined;
            const response = try std.fmt.bufPrint(&response_buffer,
                "HTTP/1.1 200 OK\r\n" ++
                "Content-Type: application/json\r\n" ++
                "Content-Length: {d}\r\n" ++
                "Connection: close\r\n" ++
                "\r\n" ++
                "{s}",
                .{ buffer.items.len, buffer.items },
            );

            try stream.writeAll(response);
        } else {
            const json_response = "{\"files\":[]}";

            var response_buffer: [512]u8 = undefined;
            const response = try std.fmt.bufPrint(&response_buffer,
                "HTTP/1.1 200 OK\r\n" ++
                "Content-Type: application/json\r\n" ++
                "Content-Length: {d}\r\n" ++
                "Connection: close\r\n" ++
                "\r\n" ++
                "{s}",
                .{ json_response.len, json_response },
            );

            try stream.writeAll(response);
        }
    }

    /// Serve 404 Not Found
    fn serve404(self: *Self, stream: std.net.Stream) !void {
        _ = self;
        const html = "<html><body><h1>404 Not Found</h1></body></html>";

        var response_buffer: [512]u8 = undefined;
        const response = try std.fmt.bufPrint(&response_buffer,
            "HTTP/1.1 404 Not Found\r\n" ++
            "Content-Type: text/html\r\n" ++
            "Content-Length: {d}\r\n" ++
            "Connection: close\r\n" ++
            "\r\n" ++
            "{s}",
            .{ html.len, html },
        );

        try stream.writeAll(response);
    }

    /// Broadcast an event to all connected clients
    pub fn broadcast(self: *Self, event: []const u8, data: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var i: usize = 0;
        while (i < self.clients.items.len) {
            const client = self.clients.items[i];
            client.sendEvent(event, data) catch {
                // Client disconnected, remove from list
                client.deinit();
                self.allocator.destroy(client);
                _ = self.clients.swapRemove(i);
                continue;
            };
            i += 1;
        }
    }
};

/// UI Reporter - sends test events to the UI server
pub const UIReporter = struct {
    reporter: reporter_mod.Reporter,
    server: *UIServer,
    buffer: std.ArrayList(u8),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, server: *UIServer) Self {
        return .{
            .reporter = .{
                .vtable = &.{
                    .onRunStart = onRunStart,
                    .onRunEnd = onRunEnd,
                    .onSuiteStart = onSuiteStart,
                    .onSuiteEnd = onSuiteEnd,
                    .onTestStart = onTestStart,
                    .onTestEnd = onTestEnd,
                },
                .allocator = allocator,
                .use_colors = false,
            },
            .server = server,
            .buffer = .empty,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.reporter.allocator);
    }

    fn onRunStart(reporter: *reporter_mod.Reporter, total: usize) !void {
        const self: *Self = @fieldParentPtr("reporter", reporter);

        self.buffer.clearRetainingCapacity();
        const writer = self.buffer.writer(reporter.allocator);
        try writer.print("{{\"total\":{d}}}", .{total});

        try self.server.broadcast("run_start", self.buffer.items);
    }

    fn onRunEnd(reporter: *reporter_mod.Reporter, results: *reporter_mod.TestResults) !void {
        const self: *Self = @fieldParentPtr("reporter", reporter);

        self.buffer.clearRetainingCapacity();
        const writer = self.buffer.writer(reporter.allocator);
        try writer.print("{{\"total\":{d},\"passed\":{d},\"failed\":{d},\"skipped\":{d}}}", .{
            results.total,
            results.passed,
            results.failed,
            results.skipped,
        });

        try self.server.broadcast("run_end", self.buffer.items);
    }

    fn onSuiteStart(reporter: *reporter_mod.Reporter, suite_name: []const u8) !void {
        const self: *Self = @fieldParentPtr("reporter", reporter);

        self.buffer.clearRetainingCapacity();
        const writer = self.buffer.writer(reporter.allocator);
        try writer.print("{{\"name\":\"{s}\"}}", .{suite_name});

        try self.server.broadcast("suite_start", self.buffer.items);
    }

    fn onSuiteEnd(reporter: *reporter_mod.Reporter, suite_name: []const u8) !void {
        const self: *Self = @fieldParentPtr("reporter", reporter);

        self.buffer.clearRetainingCapacity();
        const writer = self.buffer.writer(reporter.allocator);
        try writer.print("{{\"name\":\"{s}\"}}", .{suite_name});

        try self.server.broadcast("suite_end", self.buffer.items);
    }

    fn onTestStart(reporter: *reporter_mod.Reporter, test_name: []const u8) !void {
        const self: *Self = @fieldParentPtr("reporter", reporter);

        self.buffer.clearRetainingCapacity();
        const writer = self.buffer.writer(reporter.allocator);
        try writer.print("{{\"name\":\"{s}\"}}", .{test_name});

        try self.server.broadcast("test_start", self.buffer.items);
    }

    fn onTestEnd(reporter: *reporter_mod.Reporter, test_case: *const suite.TestCase) !void {
        const self: *Self = @fieldParentPtr("reporter", reporter);

        self.buffer.clearRetainingCapacity();
        const writer = self.buffer.writer(reporter.allocator);

        const error_msg = test_case.error_message orelse "";
        try writer.print("{{\"name\":\"{s}\",\"status\":\"{s}\",\"execution_time_ns\":{d},\"error_message\":\"{s}\"}}", .{
            test_case.name,
            @tagName(test_case.status),
            test_case.execution_time_ns,
            error_msg,
        });

        try self.server.broadcast("test_end", self.buffer.items);
    }
};

/// Multi-Reporter - broadcasts events to multiple reporters
pub const MultiReporter = struct {
    reporter: reporter_mod.Reporter,
    reporters: []* reporter_mod.Reporter,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, reporters: []*reporter_mod.Reporter) Self {
        return .{
            .reporter = .{
                .vtable = &.{
                    .onRunStart = onRunStart,
                    .onRunEnd = onRunEnd,
                    .onSuiteStart = onSuiteStart,
                    .onSuiteEnd = onSuiteEnd,
                    .onTestStart = onTestStart,
                    .onTestEnd = onTestEnd,
                },
                .allocator = allocator,
                .use_colors = false,
            },
            .reporters = reporters,
            .allocator = allocator,
        };
    }

    fn onRunStart(reporter: *reporter_mod.Reporter, total: usize) !void {
        const self: *Self = @fieldParentPtr("reporter", reporter);
        for (self.reporters) |rep| {
            try rep.onRunStart(total);
        }
    }

    fn onRunEnd(reporter: *reporter_mod.Reporter, results: *reporter_mod.TestResults) !void {
        const self: *Self = @fieldParentPtr("reporter", reporter);
        for (self.reporters) |rep| {
            try rep.onRunEnd(results);
        }
    }

    fn onSuiteStart(reporter: *reporter_mod.Reporter, suite_name: []const u8) !void {
        const self: *Self = @fieldParentPtr("reporter", reporter);
        for (self.reporters) |rep| {
            try rep.onSuiteStart(suite_name);
        }
    }

    fn onSuiteEnd(reporter: *reporter_mod.Reporter, suite_name: []const u8) !void {
        const self: *Self = @fieldParentPtr("reporter", reporter);
        for (self.reporters) |rep| {
            try rep.onSuiteEnd(suite_name);
        }
    }

    fn onTestStart(reporter: *reporter_mod.Reporter, test_name: []const u8) !void {
        const self: *Self = @fieldParentPtr("reporter", reporter);
        for (self.reporters) |rep| {
            try rep.onTestStart(test_name);
        }
    }

    fn onTestEnd(reporter: *reporter_mod.Reporter, test_case: *const suite.TestCase) !void {
        const self: *Self = @fieldParentPtr("reporter", reporter);
        for (self.reporters) |rep| {
            try rep.onTestEnd(test_case);
        }
    }
};

// Tests
test "UIServerOptions default values" {
    const options = UIServerOptions{};

    try std.testing.expectEqual(@as(u16, 8080), options.port);
    try std.testing.expectEqualStrings("127.0.0.1", options.host);
    try std.testing.expectEqual(false, options.verbose);
}

test "UIServer initialization" {
    const allocator = std.testing.allocator;

    var server = UIServer.init(allocator, .{});
    defer server.deinit();

    try std.testing.expectEqual(@as(usize, 0), server.clients.items.len);
    // Note: server.server is null initially (not started)
}

test "UIReporter initialization" {
    const allocator = std.testing.allocator;

    var server = UIServer.init(allocator, .{});
    defer server.deinit();

    var ui_reporter = UIReporter.init(allocator, &server);
    defer ui_reporter.deinit();

    try std.testing.expectEqual(false, ui_reporter.reporter.use_colors);
    try std.testing.expectEqual(@as(usize, 0), ui_reporter.buffer.items.len);
}
