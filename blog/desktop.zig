const std = @import("std");

pub fn main() !void {
    const address = try std.Io.net.IpAddress.parseIp4("0.0.0.0", 7979);

    var threaded: std.Io.Threaded = .init_single_threaded;
    defer threaded.deinit();

    var server = try address.listen(threaded.io(), .{ .reuse_address = true });
    defer server.deinit(threaded.io());

    std.debug.print("Listening for a connection...\n", .{});
    try handleConnection(threaded.io(), try server.accept(threaded.io()));
}

fn handleConnection(io: std.Io, stream: std.Io.net.Stream) !void {
    defer stream.close(io);

    var recv_buffer: [512]u8 = undefined;
    var send_buffer: [512]u8 = undefined;

    var connection_br = stream.reader(io, &recv_buffer);
    var connection_bw = stream.writer(io, &send_buffer);

    var server = std.http.Server.init(&connection_br.interface, &connection_bw.interface);
    var request = try server.receiveHead();

    try handleRequest(io, &request);
}

fn handleRequest(io: std.Io, request: *std.http.Server.Request) !void {
    std.debug.print("Handling a request!\n", .{});

    var file = try std.Io.Dir.cwd().createFile(io, "output.bin", .{});
    defer file.close(io);

    var fbuf: [512]u8 = undefined;
    var file_writer = file.writer(io, &fbuf);

    var rbuf: [512]u8 = undefined;
    var reader = try request.readerExpectContinue(&rbuf);

    std.debug.print("Streaming remaining data!\n", .{});
    _ = try reader.streamRemaining(&file_writer.interface);
    std.debug.print("Streaming completed!\n", .{});

    try file_writer.interface.flush();
    try request.respond("Thanks for all the fish!\n", .{});
}
