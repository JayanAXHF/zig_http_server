const std = @import("std");
const builtin = @import("builtin");
const net = @import("std").net;

pub const Socket = struct {
    _address: std.net.Address,
    _stream: std.net.Stream,

    pub fn init(port: u16, host: [4]u8) !Socket {
        const addr = net.Address.initIp4(host, port);
        const socket = try std.posix.socket(addr.any.family, std.posix.SOCK.STREAM, std.posix.IPPROTO.TCP);
        const stream = net.Stream{ .handle = socket };
        return Socket{ ._address = addr, ._stream = stream };
    }
};
