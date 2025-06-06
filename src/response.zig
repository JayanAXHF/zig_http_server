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
