const std = @import("std");

pub fn main() void {
    const address = std.net.Address.parseIp4("0.0.0.0", 6868) catch @panic("Could not parse IPv4");

    var server = address.listen(.{ .reuse_address = true }) catch @panic("Error listening");
    defer server.deinit();

    std.debug.print("Listening for a connection...\n", .{});
    handleConnection(server.accept() catch @panic("Error accepting connection"));
}

fn handleRequest(request: *std.http.Server.Request) void {
    defer request.respond("I see you\n", .{}) catch @panic("Cannot respond to the request");

    std.debug.print("Content length: {d}\n", .{request.head.content_length.?});
    std.debug.print("Head: {any}\n", .{request.head.transfer_encoding});

    if (request.head.method == .GET) {}
    if (request.head.method == .POST) {
        var yab: [2048]u8 = undefined;
        // var reader = server.reader.bodyReader(&.{}, .chunked, content_length);
        var reader = request.readerExpectContinue(&yab) catch |err| {
            std.debug.print("Reader expect continue failed: {any}\n", .{err});
            return;
        };

        // the body should begin with the following lines:
        // <boundary>\r\n
        // Content-Disposition\r\n
        // Content-Type\r\n
        // \r\n
        const boundary = reader.takeDelimiterExclusive('\r') catch @panic("cannot discard");
        _ = reader.discard(.limited(2)) catch unreachable; // \r\n
        const content_disposition = reader.takeDelimiterExclusive('\r') catch @panic("cannot discard");
        _ = reader.discard(.limited(2)) catch unreachable; // \r\n
        const content_type = reader.takeDelimiterExclusive('\r') catch @panic("cannot discard");
        _ = reader.discard(.limited(4)) catch unreachable; // \r\n\r\n

        std.debug.print("Boundary: '{s}'\n", .{boundary});
        std.debug.print("Content-disposition: '{s}'\n", .{content_disposition});
        std.debug.print("Content-Type: '{s}'\n", .{content_type});

        const filename = getFilename(content_disposition) catch @panic("Could not get filename");
        var file = std.fs.cwd().createFile(filename, .{}) catch {
            std.debug.print("Could not open file for writing!", .{});
            return;
        };
        defer file.close();

        var file_buffer: [2048]u8 = undefined;
        const exact = request.head.content_length.? - reader.seek - (boundary.len + 6); // the ending boundary has two dashes extra
        std.debug.print("Exact: {d}\n", .{exact});
        var file_writer = file.writer(&file_buffer);
        reader.streamExact(&file_writer.interface, exact) catch {
            std.debug.print("naniiiiiiiii\n", .{});
        };

        file_writer.interface.flush() catch unreachable;

        // std.debug.print("Starting data now!", .{});
        // var total_read: usize = 0;
        // var buffer: [128]u8 = undefined;
        // while (true) {
        // const read_bytes = reader.readSliceShort(&buffer) catch {
        // @panic("Error reading short slice");
        // };

        // total_read += read_bytes;

        // if (read_bytes < buffer.len) {
        // std.debug.print("Reached the end of the file!\n", .{});
        // break;
        // }
        // }
    }
}

fn getFilename(input: []const u8) ![]const u8 {
    if (!std.mem.containsAtLeast(u8, input, 1, "filename=")) {
        return (error{FilenameNotFound}).FilenameNotFound;
    }
    var it = std.mem.splitScalar(u8, input, ';');
    while (it.next()) |field| {
        if (std.mem.startsWith(u8, std.mem.trim(u8, field, " \t\n\r"), "filename=")) {
            return std.mem.trim(u8, field["filename=".len..], " =\"");
        }
    }
    unreachable;
}

fn handleConnection(connection: std.net.Server.Connection) void {
    defer connection.stream.close();

    var recv_buffer: [2048]u8 = undefined;
    var send_buffer: [2048]u8 = undefined;

    var connection_br = connection.stream.reader(&recv_buffer);
    var connection_bw = connection.stream.writer(&send_buffer);

    var server = std.http.Server.init(connection_br.interface(), &connection_bw.interface);
    var request = server.receiveHead() catch @panic("Unable to receive head from the HTTP request");

    handleRequest(&request);
}
