const std = @import("std");
const SocketConf = @import("http_server");
const RequestLib = @import("request");
const Response = @import("response");
const Method = RequestLib.Method;
const Request = RequestLib.Request;
const RouterLib = @import("root.zig");
const Router = RouterLib.Router;

const stdout = std.io.getStdOut().writer();

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    std.log.info("Allocator Leaked: {any}", .{gpa.detectLeaks()});
    const allocator = gpa.allocator();

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
