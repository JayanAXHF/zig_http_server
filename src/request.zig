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
    params: ?std.StringHashMap([]const u8) = null,

    pub fn init(method: Method, uri: []const u8, version: []const u8, headers: ?std.StringHashMap([]const u8), body: ?[]const u8, params: ?std.StringHashMap([]const u8)) Request {
        return Request{
            .method = method,
            .uri = uri,
            .version = version,
            .body = body,
            .headers = headers,
            .params = params,
        };
    }
    pub fn deinit(self: *Request) void {
        if (self.params) |*params| {
            params.deinit();
        }
        if (self.headers) |*headers| {
            headers.deinit();
        }
    }
};

pub fn parse_request(allocator: std.mem.Allocator, text: []u8) !Request {
    var method_text = std.mem.splitScalar(u8, text, ' ');
    const method = Method.init(method_text.next() orelse "GET") catch unreachable;
    switch (method) {
        Method.GET => return try _parse_get_request(allocator, text),
        Method.POST => {
            std.log.debug("\n{s}", .{text});
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
        if (std.mem.eql(u8, header_text, "")) {
            continue;
        }
        var header = std.mem.splitScalar(u8, header_text, ':');
        std.log.debug("Header: {s}", .{header_text});
        const key = header.next().?;
        const value = header.next() orelse {
            std.log.err("Header missing value: {s}", .{key});
            continue;
        };

        try headers.put(key, value);
    }
    const params = try parse_params(allocator, uri);
    const request = Request.init(method, uri, version, headers, null, params);

    return request;
}

pub fn _parse_post_request(allocator: std.mem.Allocator, text: []u8) !Request {
    const line_index = std.mem.indexOfScalar(u8, text, '\n') orelse text.len;
    var iterator = std.mem.splitScalar(u8, text[0..line_index], ' ');
    const method = try Method.init(iterator.next().?);
    const uri = iterator.next().?;
    const version = iterator.next().?;
    const header_section = std.mem.trim(u8, text[line_index..], "\n\n");
    var iter = std.mem.splitSequence(u8, header_section, "\r\n\r\n");
    var headers = std.StringHashMap([]const u8).init(allocator);
    defer headers.deinit();

    var header_text_iter = std.mem.splitSequence(u8, iter.next().?, "\r\n");
    while (header_text_iter.next()) |header_text| {
        std.log.debug("Header: {s}", .{header_text});
        var header = std.mem.splitScalar(u8, header_text, ':');
        const key = header.next().?;
        const value = header.next().?;
        try headers.put(key, value);
    }

    const body = iter.next().?;

    const params = try parse_params(allocator, uri);
    const request = Request.init(method, uri, version, headers, body, params);
    return request;
}

pub fn parse_params(allocator: std.mem.Allocator, uri: []const u8) !?std.StringHashMap([]const u8) {
    var uri_iter = std.mem.splitScalar(u8, uri, '?');
    _ = uri_iter.next() orelse null;
    const params_str = uri_iter.next() orelse return null;
    var params = std.StringHashMap([]const u8).init(allocator);
    var param_iter = std.mem.splitScalar(u8, params_str, '&');
    while (param_iter.next()) |param| {
        var param_iter2 = std.mem.splitScalar(u8, param, '=');
        const key = param_iter2.next().?;
        const value = param_iter2.next().?;
        const owned_key = try allocator.dupe(u8, key);
const owned_value = try allocator.dupe(u8, value);
        try params.put(owned_key, owned_value);
    }
    return params;
}
