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
    const socket = try SocketConf.Socket.init();
    try stdout.print("Server Addr: {any}\n", .{socket._address});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    std.log.info("Allocator Leaked: {any}", .{gpa.detectLeaks()});
    const allocator = gpa.allocator();

    var server = try socket._address.listen(.{});
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
            fn handle(_: Request, connection: *std.net.Server.Connection, _allocator: std.mem.Allocator) anyerror!void {
                std.log.info("POST /test", .{});
                try Response.send_200(connection.*, "<html><body><h1>POST /test</h1></body></html>", _allocator);
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

    while (true) {
        var buffer: [1000]u8 = undefined;
        var connection = try server.accept();

        try RequestLib.read_request(connection, buffer[0..buffer.len]);
        const request = RequestLib.parse_request(buffer[0..buffer.len]);

        try router.route(request, &connection, allocator);
        continue;
    }
}
