const std = @import("std");

pub fn main() void {
    const address = std.net.Address.parseIp4("0.0.0.0", 6868) catch @panic("Could not parse IPv4");

    const listener = std.posix.socket(address.any.family, std.posix.SOCK.STREAM, std.posix.IPPROTO.TCP);
    defer std.posix.close(listener);

    std.posix.setsockopt(listener, std.posix.SOL.SOCKET, std.posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
}
