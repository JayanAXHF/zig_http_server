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
    body: ?[]const u8,
    headers: ?std.StringHashMap([]const u8),
    pub fn init(method: Method, uri: []const u8, version: []const u8, headers: ?std.StringHashMap([]const u8), body: ?[]const u8) Request {
        return Request{
            .method = method,
            .uri = uri,
            .version = version,
            .body = body,
            .headers = headers,
        };
    }
};

pub fn parse_request(allocator: std.mem.Allocator, text: []u8) !Request {
    var method_text = std.mem.splitScalar(u8, text, ' ');
    const method = Method.init(method_text.next() orelse "GET") catch unreachable;
    switch (method) {
        Method.GET => return try _parse_get_request(allocator, text),
        else => {
            std.log.info("{s}", .{text});
            return try _parse_post_request(allocator, text);
        },
    }
}

pub fn _parse_get_request(allocator: std.mem.Allocator, text: []u8) !Request {
    const line_index = std.mem.indexOfScalar(u8, text, '\n') orelse text.len;
    var iterator = std.mem.splitScalar(u8, text[0..line_index], ' ');
    const method = try Method.init(iterator.next().?);
    const uri = iterator.next().?;
    const version = iterator.next().?;
    var headers = std.StringHashMap([]const u8).init(allocator);
    defer headers.deinit();
    var header_text_iter = std.mem.splitSequence(u8, text[line_index..], "\r\n");
    while (header_text_iter.next()) |header_text| {
        var header = std.mem.splitScalar(u8, header_text, ':');
        const key = header.next().?;
        const value = header.next() orelse {
            std.log.err("Header missing value: {s}", .{key});
            continue;
        };

        try headers.put(key, value);
    }
    const request = Request.init(method, uri, version, headers, null);

    return request;
}

pub fn _parse_post_request(allocator: std.mem.Allocator, text: []u8) !Request {
    const line_index = std.mem.indexOfScalar(u8, text, '\n') orelse text.len;
    var iterator = std.mem.splitScalar(u8, text[0..line_index], ' ');
    const method = try Method.init(iterator.next().?);
    const uri = iterator.next().?;
    const version = iterator.next().?;
    var iter = std.mem.splitSequence(u8, text[line_index..], "\r\n\r\n");
    var headers = std.StringHashMap([]const u8).init(allocator);
    defer headers.deinit();

    var header_text_iter = std.mem.splitSequence(u8, iter.next().?, "\r\n");
    while (header_text_iter.next()) |header_text| {
        var header = std.mem.splitScalar(u8, header_text, ':');
        const key = header.next().?;
        const value = header.next().?;
        try headers.put(key, value);
    }

    const body = iter.next().?;

    const request = Request.init(method, uri, version, headers, body);
    std.log.info("Request: {any}", .{request});
    return request;
}
