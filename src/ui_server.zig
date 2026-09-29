const std = @import("std");
const reporter_mod = @import("reporter.zig");
const suite = @import("suite.zig");
const test_history = @import("test_history.zig");
const compat = @import("compat.zig");

/// Options for the UI server
pub const UIServerOptions = struct {
    /// Port to listen on
    port: u16 = 8080,
    /// Host to bind to
    host: []const u8 = "127.0.0.1",
    /// Enable verbose logging
    verbose: bool = false,
};

/// UI Server for web-based test visualization.
pub const UIServer = struct {
    allocator: std.mem.Allocator,
    options: UIServerOptions,
    mutex: compat.Mutex = .{},
    history: ?*test_history.TestHistory = null,
    threaded_io: std.Io.Threaded,
    listener: ?std.Io.net.Server = null,
    thread: ?std.Thread = null,
    running: std.atomic.Value(bool) = .init(false),
    active_client: ?std.Io.net.Stream = null,
    clients: std.ArrayList(std.Io.net.Stream) = .empty,

    const Self = @This();
    const index_html = @embedFile("ui/index.html");

    pub const Error = error{
        AlreadyStarted,
        InvalidRequest,
        ServerStopped,
    };

    pub fn init(allocator: std.mem.Allocator, options: UIServerOptions) Self {
        return .{
            .allocator = allocator,
            .options = options,
            .threaded_io = .init(allocator, .{ .environ = .empty }),
        };
    }

    pub fn deinit(self: *Self) void {
        self.stop();
        self.clients.deinit(self.allocator);
        self.threaded_io.deinit();
    }

    /// Bind the configured address and start accepting HTTP clients.
    pub fn start(self: *Self) !void {
        if (self.running.load(.acquire) or self.listener != null) return Error.AlreadyStarted;

        const io = self.threaded_io.io();
        const address = if (std.ascii.eqlIgnoreCase(self.options.host, "localhost"))
            std.Io.net.IpAddress{ .ip4 = .loopback(self.options.port) }
        else
            try std.Io.net.IpAddress.parse(self.options.host, self.options.port);

        self.listener = try address.listen(io, .{ .reuse_address = true });
        self.options.port = self.listener.?.socket.address.getPort();
        self.running.store(true, .release);
        self.thread = std.Thread.spawn(.{}, serve, .{self}) catch |err| {
            self.running.store(false, .release);
            self.listener.?.deinit(io);
            self.listener = null;
            return err;
        };

        if (self.options.verbose) {
            std.debug.print("UI Server: listening on http://{s}:{d}\n", .{ self.options.host, self.options.port });
        }
    }

    /// Stop accepting connections and close every active event stream.
    pub fn stop(self: *Self) void {
        const was_running = self.running.swap(false, .acq_rel);
        if (was_running) {
            if (self.listener) |server| {
                const listening_stream = std.Io.net.Stream{ .socket = server.socket };
                listening_stream.shutdown(self.threaded_io.io(), .both) catch {};
                server.socket.close(self.threaded_io.io());
            }
        }

        // A client may have connected without finishing its request headers.
        // Shutting down that in-flight socket ensures shutdown cannot hang
        // waiting for the request parser; the accept thread remains its owner.
        self.mutex.lock();
        if (self.active_client) |client| client.shutdown(self.threaded_io.io(), .both) catch {};
        self.mutex.unlock();

        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }

        self.listener = null;

        self.mutex.lock();
        defer self.mutex.unlock();
        for (self.clients.items) |client| client.close(self.threaded_io.io());
        self.clients.clearRetainingCapacity();
    }

    /// Return the actual bound port. This differs from the requested port when
    /// port zero asks the operating system for an ephemeral port.
    pub fn port(self: *const Self) u16 {
        return self.options.port;
    }

    fn serve(self: *Self) void {
        while (self.running.load(.acquire)) {
            self.acceptClient() catch |err| {
                if (!self.running.load(.acquire)) return;
                if (self.options.verbose) {
                    std.debug.print("UI Server error: {s}\n", .{@errorName(err)});
                }
                compat.sleep(10 * std.time.ns_per_ms);
            };
        }
    }

    /// Accept and serve one HTTP client connection.
    pub fn acceptClient(self: *Self) !void {
        if (!self.running.load(.acquire)) return Error.ServerStopped;
        const stream = if (self.listener) |*listener|
            try listener.accept(self.threaded_io.io())
        else
            return Error.ServerStopped;
        if (!self.running.load(.acquire)) {
            stream.close(self.threaded_io.io());
            return Error.ServerStopped;
        }

        self.mutex.lock();
        self.active_client = stream;
        self.mutex.unlock();

        const disposition = self.handleClient(stream) catch |err| {
            self.finishClient(false) catch {};
            return err;
        };
        try self.finishClient(disposition == .event_stream);
    }

    const ClientDisposition = enum { close, event_stream };

    fn handleClient(self: *Self, stream: std.Io.net.Stream) !ClientDisposition {
        var read_buffer: [4096]u8 = undefined;
        var stream_reader = stream.reader(self.threaded_io.io(), &read_buffer);
        const request_line_raw = (try stream_reader.interface.takeDelimiter('\n')) orelse return Error.InvalidRequest;
        const request_line = std.mem.trimEnd(u8, request_line_raw, "\r");
        var parts = std.mem.splitScalar(u8, request_line, ' ');
        const method = parts.next() orelse return Error.InvalidRequest;
        const target = parts.next() orelse return Error.InvalidRequest;
        _ = parts.next() orelse return Error.InvalidRequest;

        const is_get = std.mem.eql(u8, method, "GET");
        const is_events = std.mem.eql(u8, target, "/events");
        const is_index = std.mem.eql(u8, target, "/") or std.mem.eql(u8, target, "/index.html");

        while (true) {
            const header_raw = (try stream_reader.interface.takeDelimiter('\n')) orelse return Error.InvalidRequest;
            if (std.mem.trimEnd(u8, header_raw, "\r").len == 0) break;
        }

        if (!is_get) {
            try self.respond(stream, "405 Method Not Allowed", "text/plain; charset=utf-8", "Method Not Allowed\n");
        } else if (is_events) {
            try self.openEventStream(stream);
            return .event_stream;
        } else if (is_index) {
            try self.respond(stream, "200 OK", "text/html; charset=utf-8", index_html);
        } else {
            try self.respond(stream, "404 Not Found", "text/plain; charset=utf-8", "Not Found\n");
        }
        return .close;
    }

    fn finishClient(self: *Self, keep_open: bool) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        const client = self.active_client orelse return;
        self.active_client = null;

        if (keep_open and self.running.load(.acquire)) {
            self.clients.append(self.allocator, client) catch |err| {
                client.close(self.threaded_io.io());
                return err;
            };
        } else {
            client.close(self.threaded_io.io());
        }
    }

    fn respond(self: *Self, stream: std.Io.net.Stream, status: []const u8, content_type: []const u8, body: []const u8) !void {
        var write_buffer: [2048]u8 = undefined;
        var stream_writer = stream.writer(self.threaded_io.io(), &write_buffer);
        try stream_writer.interface.print(
            "HTTP/1.1 {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
            .{ status, content_type, body.len },
        );
        try stream_writer.interface.writeAll(body);
        try stream_writer.interface.flush();
    }

    fn openEventStream(self: *Self, stream: std.Io.net.Stream) !void {
        var write_buffer: [512]u8 = undefined;
        var stream_writer = stream.writer(self.threaded_io.io(), &write_buffer);
        try stream_writer.interface.writeAll(
            "HTTP/1.1 200 OK\r\n" ++
                "Content-Type: text/event-stream\r\n" ++
                "Cache-Control: no-cache\r\n" ++
                "Connection: keep-alive\r\n" ++
                "X-Accel-Buffering: no\r\n\r\n" ++
                "event: connected\ndata: {}\n\n",
        );
        try stream_writer.interface.flush();
    }

    fn sendEvent(self: *Self, stream: std.Io.net.Stream, event: []const u8, data: []const u8) !void {
        var write_buffer: [1024]u8 = undefined;
        var stream_writer = stream.writer(self.threaded_io.io(), &write_buffer);
        try stream_writer.interface.print("event: {s}\ndata: {s}\n\n", .{ event, data });
        try stream_writer.interface.flush();
    }

    /// Broadcast an event to all connected clients. A disconnected browser is
    /// removed without disrupting the test run or the remaining clients.
    pub fn broadcast(self: *Self, event: []const u8, data: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var index: usize = 0;
        while (index < self.clients.items.len) {
            const client = self.clients.items[index];
            self.sendEvent(client, event, data) catch {
                client.close(self.threaded_io.io());
                _ = self.clients.swapRemove(index);
                continue;
            };
            index += 1;
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

    fn encode(self: *Self, value: anytype) !void {
        self.buffer.clearRetainingCapacity();
        var writer: std.Io.Writer.Allocating = .fromArrayList(self.reporter.allocator, &self.buffer);
        defer self.buffer = writer.toArrayList();
        try std.json.Stringify.value(value, .{}, &writer.writer);
    }

    fn onRunStart(reporter: *reporter_mod.Reporter, total: usize) !void {
        const self: *Self = @fieldParentPtr("reporter", reporter);
        try self.encode(.{ .total = total });
        try self.server.broadcast("run_start", self.buffer.items);
    }

    fn onRunEnd(reporter: *reporter_mod.Reporter, results: *reporter_mod.TestResults) !void {
        const self: *Self = @fieldParentPtr("reporter", reporter);

        try self.encode(.{
            .total = results.total,
            .passed = results.passed,
            .flaky = results.flaky,
            .failed = results.failed,
            .skipped = results.skipped,
        });
        try self.server.broadcast("run_end", self.buffer.items);
    }

    fn onSuiteStart(reporter: *reporter_mod.Reporter, suite_name: []const u8) !void {
        const self: *Self = @fieldParentPtr("reporter", reporter);

        try self.encode(.{ .name = suite_name });
        try self.server.broadcast("suite_start", self.buffer.items);
    }

    fn onSuiteEnd(reporter: *reporter_mod.Reporter, suite_name: []const u8) !void {
        const self: *Self = @fieldParentPtr("reporter", reporter);

        try self.encode(.{ .name = suite_name });
        try self.server.broadcast("suite_end", self.buffer.items);
    }

    fn onTestStart(reporter: *reporter_mod.Reporter, test_name: []const u8) !void {
        const self: *Self = @fieldParentPtr("reporter", reporter);

        try self.encode(.{ .name = test_name });
        try self.server.broadcast("test_start", self.buffer.items);
    }

    fn onTestEnd(reporter: *reporter_mod.Reporter, test_case: *const suite.TestCase) !void {
        const self: *Self = @fieldParentPtr("reporter", reporter);

        try self.encode(.{
            .name = test_case.name,
            .status = @tagName(test_case.status),
            .execution_time_ns = test_case.execution_time_ns,
            .error_message = test_case.error_message orelse "",
        });
        try self.server.broadcast("test_end", self.buffer.items);
    }
};

/// Multi-Reporter - broadcasts events to multiple reporters
pub const MultiReporter = struct {
    reporter: reporter_mod.Reporter,
    reporters: []*reporter_mod.Reporter,
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
}

test "UIReporter initialization" {
    const allocator = std.testing.allocator;

    var server = UIServer.init(allocator, .{});
    defer server.deinit();

    var ui_reporter = UIReporter.init(allocator, &server);
    defer ui_reporter.deinit();

    try std.testing.expectEqual(false, ui_reporter.reporter.use_colors);
    try std.testing.expectEqual(@as(usize, 0), ui_reporter.buffer.items.len);

    try ui_reporter.reporter.onSuiteStart("quoted \"suite\"\nname");
    try std.testing.expectEqualStrings("{\"name\":\"quoted \\\"suite\\\"\\nname\"}", ui_reporter.buffer.items);
}

fn writeTestRequest(io: std.Io, stream: std.Io.net.Stream, target: []const u8) !void {
    var write_buffer: [512]u8 = undefined;
    var writer = stream.writer(io, &write_buffer);
    try writer.interface.print("GET {s} HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n", .{target});
    try writer.interface.flush();
}

fn expectLine(reader: *std.Io.Reader, expected: []const u8) !void {
    const raw = (try reader.takeDelimiter('\n')) orelse return error.EndOfStream;
    try std.testing.expectEqualStrings(expected, std.mem.trimEnd(u8, raw, "\r"));
}

test "UI server serves the embedded page on an ephemeral port" {
    var server = UIServer.init(std.testing.allocator, .{ .port = 0 });
    defer server.deinit();
    try server.start();
    try std.testing.expect(server.port() != 0);

    var client_io: std.Io.Threaded = .init(std.testing.allocator, .{ .environ = .empty });
    defer client_io.deinit();
    const io = client_io.io();
    const address = std.Io.net.IpAddress{ .ip4 = .loopback(server.port()) };
    const stream = try address.connect(io, .{ .mode = .stream });
    defer stream.close(io);
    try writeTestRequest(io, stream, "/");

    var read_buffer: [4096]u8 = undefined;
    var stream_reader = stream.reader(io, &read_buffer);
    const response = try stream_reader.interface.allocRemaining(std.testing.allocator, .limited(UIServer.index_html.len + 1024));
    defer std.testing.allocator.free(response);
    try std.testing.expect(std.mem.startsWith(u8, response, "HTTP/1.1 200 OK\r\n"));
    try std.testing.expect(std.mem.indexOf(u8, response, "Zig Test Framework - Live Results") != null);
}

test "UI server streams broadcast events over SSE" {
    var server = UIServer.init(std.testing.allocator, .{ .port = 0 });
    defer server.deinit();
    try server.start();

    var client_io: std.Io.Threaded = .init(std.testing.allocator, .{ .environ = .empty });
    defer client_io.deinit();
    const io = client_io.io();
    const address = std.Io.net.IpAddress{ .ip4 = .loopback(server.port()) };
    const stream = try address.connect(io, .{ .mode = .stream });
    defer stream.close(io);
    try writeTestRequest(io, stream, "/events");

    var read_buffer: [4096]u8 = undefined;
    var stream_reader = stream.reader(io, &read_buffer);
    try expectLine(&stream_reader.interface, "HTTP/1.1 200 OK");
    while (true) {
        const raw = (try stream_reader.interface.takeDelimiter('\n')) orelse return error.EndOfStream;
        if (std.mem.trimEnd(u8, raw, "\r").len == 0) break;
    }
    try expectLine(&stream_reader.interface, "event: connected");
    try expectLine(&stream_reader.interface, "data: {}");
    try expectLine(&stream_reader.interface, "");

    try server.broadcast("run_start", "{\"total\":2}");
    try expectLine(&stream_reader.interface, "event: run_start");
    try expectLine(&stream_reader.interface, "data: {\"total\":2}");
    try expectLine(&stream_reader.interface, "");
}

test "UI server shutdown cancels an incomplete HTTP request" {
    var server = UIServer.init(std.testing.allocator, .{ .port = 0 });
    defer server.deinit();
    try server.start();

    var client_io: std.Io.Threaded = .init(std.testing.allocator, .{ .environ = .empty });
    defer client_io.deinit();
    const io = client_io.io();
    const address = std.Io.net.IpAddress{ .ip4 = .loopback(server.port()) };
    const stream = try address.connect(io, .{ .mode = .stream });
    defer stream.close(io);

    var write_buffer: [128]u8 = undefined;
    var writer = stream.writer(io, &write_buffer);
    try writer.interface.writeAll("GET / HTTP/1.1\r\n");
    try writer.interface.flush();

    var request_is_active = false;
    for (0..100) |_| {
        server.mutex.lock();
        request_is_active = server.active_client != null;
        server.mutex.unlock();
        if (request_is_active) break;
        compat.sleep(std.time.ns_per_ms);
    }
    try std.testing.expect(request_is_active);

    server.stop();
    try std.testing.expect(!server.running.load(.acquire));
}
