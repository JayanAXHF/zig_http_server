const std = @import("std");
const SocketConf = @import("http_server");
const RequestLib = @import("request");
const Response = @import("response");
const Method = RequestLib.Method;
const Request = RequestLib.Request;
const RouterLib = @import("root.zig");
const Router = RouterLib.Router;

// NOTE: Setting up logex
const logex = @import("logex");

// Define a basic custom formatting function that simply
// prefixes the log line with `[custom]` for demo purposes
pub fn formatFn(
    writer: anytype,
    comptime record: *const logex.Record,
    context: *const logex.Context,
) @TypeOf(writer).Error!void {
    const coloured_level = "\x1B[" ++ switch (record.level) {
        .debug => "35",
        .info => "32",
        .warn => "33",
        .err => "31",
    };
    var timestamp_buf: [100]u8 = undefined;
    const timestamp = std.fmt.bufPrint(&timestamp_buf, "{s}", .{context.timestamp orelse ""}) catch unreachable;
    var level_buf: [5]u8 = undefined;
    _ = std.ascii.upperString(level_buf[0..], record.level.asText());
    try writer.print("\x1B[0;90m{s} {s}m{s}\x1B[39m {s}\n", .{ timestamp, coloured_level, level_buf, context.message });
}

const ConsoleAppender = logex.appenders.Console(.debug, .{
    // Configure the console appender to use our custom format function
    .format = .{ .custom = formatFn },
});
const Logger = logex.Logex(.{ConsoleAppender});

pub const std_options: std.Options = .{
    .logFn = Logger.logFn,
};

const stdout = std.io.getStdOut().writer();
const stdin = std.io.getStdIn().reader();

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    std.log.info("Allocator Leaked: {any}", .{gpa.detectLeaks()});
    const allocator = gpa.allocator();
    try Logger.init(.{ .show_timestamp = logex.TimestampOptions.default }, .{.init});
    const check_thread = try std.Thread.spawn(.{}, struct {
        fn check() !void {
            var buffer: [10]u8 = undefined;

            while (true) {
                const input = try stdin.readUntilDelimiter(&buffer, '\n');
                // Trim whitespace from input
                const trimmed = std.mem.trim(u8, input, " \t\r\n");

                if (std.mem.eql(u8, trimmed, "exit")) {
                    std.log.info("Exit command received, shutting down...", .{});
                    std.process.exit(0);
                }

                std.log.err("Unknown command: '{s}'. Type 'exit' to quit.", .{trimmed});
            }
        }
    }.check, .{});
    check_thread.detach();

    const endpoints: []const RouterLib.Endpoint = &[_]RouterLib.Endpoint{
        RouterLib.Endpoint.init(Method.GET, "/", struct {
            fn handle(_: Request, connection: *std.net.Server.Connection, _allocator: std.mem.Allocator) anyerror!void {
                std.log.info("GET request", .{});
                try Response.send_200(connection.*, "<html><body><h1>GET request</h1></body></html>", _allocator);
                std.log.info("200 OK", .{});
                return;
            }
        }.handle),
        RouterLib.Endpoint.init(Method.GET, "/test", struct {
            fn handle(_: Request, connection: *std.net.Server.Connection, _allocator: std.mem.Allocator) anyerror!void {
                std.log.info("GET /test", .{});
                try Response.send_200(connection.*, "<html><body><h1>GET /test</h1></body></html>", _allocator);
                std.log.info("200 OK", .{});
                return;
            }
        }.handle),
        RouterLib.Endpoint.init(Method.POST, "/post", struct {
            fn handle(request: Request, connection: *std.net.Server.Connection, _allocator: std.mem.Allocator) anyerror!void {
                std.log.info("POST /test", .{});
                const body = request.body orelse "test";
                var headers = std.StringHashMap([]const u8).init(_allocator);
                defer headers.deinit();
                try headers.put("Content-Type", "text/html");
                const response = Response.Response.init(200, headers, body);
                try response.send(connection.*, _allocator);
                std.log.info("200 OK", .{});
                return;
            }
        }.handle),
        RouterLib.Endpoint.init(Method.POST, "/sleepy", struct {
            fn handle(request: Request, connection: *std.net.Server.Connection, _allocator: std.mem.Allocator) anyerror!void {
                std.log.info("POST /test", .{});
                const body = request.body orelse "test";
                var headers = std.StringHashMap([]const u8).init(_allocator);
                defer headers.deinit();
                try headers.put("Content-Type", "text/html");
                const response = Response.Response.init(200, headers, body);
                std.time.sleep(10 * std.time.ns_per_s);
                try response.send(connection.*, _allocator);
                std.log.info("200 OK", .{});
                return;
            }
        }.handle),
        RouterLib.Endpoint.init(Method.GET, "/test_params", struct {
            fn handle(request: Request, connection: *std.net.Server.Connection, _allocator: std.mem.Allocator) anyerror!void {
                std.log.info("GET /test_params", .{});
                const params = hashMapToSimpleString(_allocator, request.params) catch unreachable;
                var headers = std.StringHashMap([]const u8).init(_allocator);
                defer headers.deinit();
                try headers.put("Content-Type", "text/html");
                const response = Response.Response.init(200, headers, params);
                std.time.sleep(10 * std.time.ns_per_s);
                try response.send(connection.*, _allocator);
                std.log.info("200 OK", .{});
                return;
            }
        }.handle),
    };
    var router = try Router.init(allocator, endpoints.len);
    defer {
        router.deinit();
        const leaked = gpa.detectLeaks();
        std.log.info("Allocator Leaked: {any}", .{leaked});
    }
    for (endpoints) |endpoint| {
        try router.add(endpoint.method, endpoint.path, endpoint.handler);
    }

    try router.start(3490, [4]u8{ 127, 0, 0, 1 });
}
fn hashMapToSimpleString(allocator: std.mem.Allocator, maybe_map: ?std.StringHashMap([]const u8)) ![]const u8 {
    if (maybe_map == null) {
        return "null";
    }
    const map = maybe_map.?;
    const count = map.count();
    if (count == 0) {
        return "empty";
    }
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();
    var iter = map.iterator();
    var processed: usize = 0;

    while (iter.next()) |entry| {
        processed += 1;
        if (processed > count * 2) { // Give some buffer
            std.log.err("HashMap iterator corruption detected", .{});
            break;
        }
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;

        if (key.len > 1024 or value.len > 1024) {
            std.log.warn("Large key ({}) or value ({}) length", .{ key.len, value.len });
        }
        try result.appendSlice(key);
        try result.appendSlice("=");
        try result.appendSlice(value);
        try result.append('\n');
    }
    return result.toOwnedSlice();
}
