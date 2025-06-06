const std = @import("std");
const Connection = std.net.Server.Connection;
pub fn read_request(conn: Connection, buffer: []u8) !void {
    const reader = conn.stream.reader();
    _ = try reader.read(buffer);
}

const Map = std.static_string_map.StaticStringMap;
pub const Method = enum {
    GET,
    POST,
    pub fn init(text: []const u8) !Method {
        return MethodMap.get(text).?;
    }
    pub fn is_supported(m: []const u8) bool {
        const method = MethodMap.get(m);
        if (method) |_| {
            return true;
        }
        return false;
    }
};
const MethodMap = Map(Method).initComptime(.{
    .{ "GET", Method.GET },
    .{ "POST", Method.POST },
});

pub const Request = struct {
    method: Method,
    version: []const u8,
    uri: []const u8,
    body: []const u8,
    pub fn init(method: Method, uri: []const u8, version: []const u8, body: []const u8) Request {
        return Request{
            .method = method,
            .uri = uri,
            .version = version,
            .body = body,
        };
    }
};

pub fn parse_request(text: []u8) Request {
    var method_text = std.mem.splitScalar(u8, text, ' ');
    const method = Method.init(method_text.next().?) catch unreachable;
    switch (method) {
        Method.GET => return _parse_get_request(text),
        else => {
            std.log.info("{s}", .{text});
            return _parse_post_request(text);
        },
    }
}

pub fn _parse_get_request(text: []u8) Request {
    const line_index = std.mem.indexOfScalar(u8, text, '\n') orelse text.len;
    var iterator = std.mem.splitScalar(u8, text[0..line_index], ' ');
    const method = try Method.init(iterator.next().?);
    const uri = iterator.next().?;
    const version = iterator.next().?;
    const request = Request.init(method, uri, version, "");
    return request;
}

pub fn _parse_post_request(text: []u8) Request {
    const line_index = std.mem.indexOfScalar(u8, text, '\n') orelse text.len;
    var iterator = std.mem.splitScalar(u8, text[0..line_index], ' ');
    const method = try Method.init(iterator.next().?);
    const uri = iterator.next().?;
    const version = iterator.next().?;
    var iter = std.mem.splitSequence(u8, text[line_index..], "\r\n\r\n");
    _ = iter.next();
    const body = iter.next().?;
    const request = Request.init(method, uri, version, body);
    std.log.info("Request: {any}", .{request});
    return request;
}
