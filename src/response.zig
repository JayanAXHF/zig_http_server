const std = @import("std");
const Connection = std.net.Server.Connection;
pub fn send_200(conn: Connection, html: []const u8, allocator: std.mem.Allocator) !void {
    const message = ("HTTP/1.1 200 OK\nContent-Length: " ++ "{d}" ++ "\nContent-Type: text/html\n" ++ "Connection: Closed\n\n" ++ "{s}");
    const fmt_message = try std.fmt.allocPrint(allocator, message, .{ html.len, html });
    _ = try conn.stream.write(fmt_message);
    allocator.free(fmt_message);
}

pub fn send_404(conn: Connection) !void {
    const message = ("HTTP/1.1 404 Not Found\nContent-Length: 50" ++ "\nContent-Type: text/html\n" ++ "Connection: Closed\n\n<html><body>" ++ "<h1>File not found!</h1></body></html>");
    _ = try conn.stream.write(message);
}

pub const Response = struct {
    status_code: u16,
    headers: std.StringHashMap([]const u8),
    body: []const u8,
    pub fn init(status_code: u16, headers: std.StringHashMap([]const u8), body: []const u8) Response {
        return Response{
            .status_code = status_code,
            .headers = headers,
            .body = body,
        };
    }
    pub fn send(self: Response, conn: Connection, allocator: std.mem.Allocator) !void {
        const message = ("HTTP/1.1 {d} {s}\nContent-Length: {d}\n{s}" ++ "Connection: Closed\n\n{s}");
        var headers_str = std.ArrayList([]const u8).init(allocator);
        defer headers_str.deinit();
        var header_iter = self.headers.iterator();
        while (header_iter.next()) |header| {
            try headers_str.append(header.key_ptr.*);
            try headers_str.append(": ");
            try headers_str.append(header.value_ptr.*);
            try headers_str.append("\n");
        }
        const fmt_message = try std.fmt.allocPrint(allocator, message, .{ self.status_code, self._get_reason_phrase(), self.body.len, headers_str.items, self.body });

        _ = try conn.stream.write(fmt_message);
        allocator.free(fmt_message);
    }
    fn _get_reason_phrase(self: Response) []const u8 {
        const status_code = self.status_code;
        return switch (status_code) {
            200...299 => "OK",
            300...399 => "Redirect",
            400...499 => "Bad Request",
            500...599 => "Internal Server Error",
            else => unreachable,
        };
    }
};
