const std = @import("std");
const SocketConf = @import("http_server");
const RequestLib = @import("request");
const Response = @import("response");
const Method = RequestLib.Method;
const Request = RequestLib.Request;
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

            // Copy existing elements into new buffer
            @memcpy(new_buf[0..self.endpoints.len], self.endpoints[0..self.endpoints.len]);

            // Free the old buffer
            self.allocator.free(self.endpoints);

            // Update to new buffer and capacity
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
                if (std.mem.eql(u8, request.uri, endpoint.path)) {
                    std.log.info("Endpoint: {s}", .{endpoint.path});
                    try endpoint.handler(request, connection, allocator);
                    return;
                }
            }
        }
        try Response.send_404(connection.*);
        return;
    }
    pub fn deinit(self: *Router) void {
        self.allocator.free(self.endpoints);
    }
};
