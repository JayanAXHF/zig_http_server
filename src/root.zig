const std = @import("std");
const SocketConf = @import("http_server");
const RequestLib = @import("request");
const Response = @import("response");
const Method = RequestLib.Method;
const Request = RequestLib.Request;
const ThreadPoolLib = @import("thread_pool");
const ThreadPool = ThreadPoolLib.ThreadPool;

const stdout = std.io.getStdOut().writer();

const handler_fn = fn (Request, *std.net.Server.Connection, std.mem.Allocator) anyerror!void;

pub const Endpoint = struct {
    method: Method,
    path: []const u8,
    handler: *const fn (Request, *std.net.Server.Connection, allocator: std.mem.Allocator) anyerror!void,

    pub fn init(method: Method, path: []const u8, handler: *const handler_fn) Endpoint {
        return Endpoint{
            .method = method,
            .path = path,
            .handler = handler,
        };
    }
};

pub const Router = struct {
    endpoints: []Endpoint,
    allocator: std.mem.Allocator,
    capacity: usize,
    len: usize,
    pub fn init(allocator: std.mem.Allocator, capacity: usize) !Router {
        var buf = try allocator.alloc(Endpoint, capacity);
        return Router{
            .endpoints = buf[0..],
            .allocator = allocator,
            .capacity = capacity,
            .len = 0,
        };
    }
    pub fn add(self: *Router, method: Method, path: []const u8, handler: *const handler_fn) !void {
        if (self.len + 1 > self.capacity) {
            var new_buf = try self.allocator.alloc(Endpoint, self.capacity * 2);

            @memcpy(new_buf[0..self.endpoints.len], self.endpoints[0..self.endpoints.len]);
            self.allocator.free(self.endpoints);
            self.endpoints = new_buf;
            self.capacity = 2 * self.capacity;
        }
        self.endpoints[self.len] = Endpoint.init(method, path, handler);
        self.len += 1;
        return;
    }

    pub fn route(router: Router, request: @import("request").Request, connection: *std.net.Server.Connection, allocator: std.mem.Allocator) !void {
        for (router.endpoints) |endpoint| {
            if (request.method == endpoint.method) {
                var uri_iter = std.mem.splitScalar(u8, request.uri, '?');
                const uri = uri_iter.next() orelse request.uri;
                if (std.mem.eql(u8, uri, endpoint.path)) {
                    std.log.info("Endpoint: {s}", .{endpoint.path});
                    try endpoint.handler(request, connection, allocator);
                    return;
                }
            }
        }
        try Response.send_404(connection.*);
        return;
    }
    pub fn start(self: *Router, port: u16, host: [4]u8) !void {
        std.log.info("Starting server...", .{});
        const socket = try SocketConf.Socket.init(port, host);
        try stdout.print("Server Addr: {any}\n", .{socket._address});
        var server = try socket._address.listen(.{});
        var thread_pool = try self.allocator.create(ThreadPool);
        thread_pool = try ThreadPool.init(self.allocator, 10);
        defer {
            thread_pool.deinit();
            self.allocator.destroy(thread_pool);
        }

        while (thread_pool.running) {
            std.log.info("Attempting to accept connection", .{});

            var conn = try server.accept();

            const _args = try self.allocator.create(struct { router: *Router, connection: *std.net.Server.Connection });
            _args.* = .{ .router = self, .connection = &conn };

            try thread_pool.queue_job(struct {
                fn job(any: *anyopaque) anyerror!void {
                    const args: *const struct { router: *Router, connection: *std.net.Server.Connection } = @ptrCast(@alignCast(any));
                    const _allocator = args.router.allocator;
                    const _router = args.router;

                    var buffer: [1000]u8 = undefined;
                    var connection = args.connection.*;
                    try RequestLib.read_request(connection, buffer[0..buffer.len]);
                    const request = try RequestLib.parse_request(_allocator, buffer[0..buffer.len]);
                    try _router.route(request, &connection, _allocator);
                }
            }.job, _args);

        }
    }
    pub fn deinit(self: *Router) void {
        self.allocator.free(self.endpoints);
    }
};
