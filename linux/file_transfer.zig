const std = @import("std");

pub fn main() void {
    var file_a = std.fs.cwd().openFile(std.mem.span(std.os.argv[1]), .{}) catch @panic("Cannot open file A");
    var file_b = std.fs.cwd().createFile(std.mem.span(std.os.argv[2]), .{}) catch @panic("Cannot open file B");

    defer {
        file_a.close();
        file_b.close();
    }

    std.debug.print("A: {any}\n", .{file_a.stat() catch @panic("Could not stat file A")});
    std.debug.print("B: {any}\n", .{file_b.stat() catch @panic("Could not stat file B")});

    var read_buffer: [1024]u8 = undefined;
    var write_buffer: [1024]u8 = undefined;

    var reader = file_a.readerStreaming(&read_buffer);
    var writer = file_b.writerStreaming(&write_buffer);

    reader.interface.streamExact(&writer.interface, 10) catch @panic("Could not stream 10 bytes");
    writer.interface.flush();
}
