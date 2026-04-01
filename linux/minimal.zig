const std = @import("std");

// data is sent via:
// curl --verbose --data-binary '@minimal.zig' --header 'Content-Type: application/octet-stream' 127.0.0.1:6868

pub fn main() void {
    const address = std.net.Address.parseIp4("0.0.0.0", 6868) catch @panic("Could not parse IPv4");

    var server = address.listen(.{ .reuse_address = true }) catch @panic("Error listening");
    defer server.deinit();

    std.debug.print("Listening for a connection...\n", .{});
    handleConnection(server.accept() catch @panic("Error accepting connection"));
}

fn handleConnection(connection: std.net.Server.Connection) void {
    defer connection.stream.close();

    var recv_buffer: [512]u8 = undefined;
    var send_buffer: [512]u8 = undefined;

    var connection_br = connection.stream.reader(&recv_buffer);
    var connection_bw = connection.stream.writer(&send_buffer);

    var server = std.http.Server.init(connection_br.interface(), &connection_bw.interface);
    var request = server.receiveHead() catch @panic("Unable to receive head from the HTTP request");

    handleRequest(&request);
}

fn handleRequest(request: *std.http.Server.Request) void {
    var file = std.fs.cwd().createFile("output.txt", .{}) catch @panic("Could not open file for writing!");
    defer file.close();

    var file_buffer: [64]u8 = undefined;
    var file_writer = file.writer(&file_buffer);

    var buf: [64]u8 = undefined;
    var reader = request.readerExpectNone(&buf);

    const streamed_bytes = reader.streamRemaining(&file_writer.interface) catch @panic("Failed to stream remaining data\n");

    std.debug.print("Streamed {d} bytes\n", .{streamed_bytes});

    file_writer.interface.flush() catch @panic("Failed to flush the file writer buffer");

    request.respond("Message received\n", .{}) catch @panic("Cannot respond to the request");
}
