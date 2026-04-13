const socket = @cImport({
    @cInclude("sys/types.h");
    @cInclude("sys/socket.h");
    @cInclude("netinet/in.h");
    @cInclude("arpa/inet.h");
});

const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("unistd.h");
    @cInclude("libgen.h");
});

const print = @import("std").debug.print;
const process = @import("std").process;
const os = @import("std").os;
const mem = @import("std").mem;

pub fn main(init: process.Init) void {
    var args_it = init.minimal.args.iterate();
    _ = args_it.next().?; // executable name
    const filename = args_it.next().?;

    print("Filename: '{s}' ({any})\n", .{ filename, @TypeOf(filename) });

    const fptr = c.fopen(@ptrCast(filename), "rb");
    if (fptr == null) {
        print("Failed to open file", .{});
        return;
    }
    defer _ = c.fclose(fptr);

    _ = c.fseek(fptr, 0, c.SEEK_END);
    const file_size: u32 = @intCast(c.ftell(fptr));
    c.rewind(fptr);

    print("File size: {d}\n", .{file_size});

    var buffer: [4096]u8 = @splat(0);
    const i = blk: {
        var i: usize = filename.len;
        while (i > 0) : (i -= 1) {
            if (filename[i] == '/') {
                break :blk i + 1;
            }
        }
        break :blk 0;
    };

    mem.copyForwards(u8, &buffer, filename[i..]);

    const network_socket: c_int = socket.socket(socket.AF_INET, socket.SOCK_STREAM, 0);
    defer _ = c.close(network_socket);

    print("Socket created!\n", .{});

    // 192.168.1.41 in hex
    // 0xc0a80229,
    var server_address = socket.sockaddr_in{};
    server_address.sin_family = socket.AF_INET;
    server_address.sin_port = socket.htons(7979);
    const res = socket.inet_pton(socket.AF_INET, "192.168.1.41", &server_address.sin_addr);
    if (res == -1) {
        print("Inet pton failed", .{});
        return;
    }

    const connection_status = socket.connect(network_socket, @ptrCast(&server_address), @sizeOf(@TypeOf(server_address)));
    if (connection_status == -1) {
        print("Connection failed, status: {d}\n", .{connection_status});
        return;
    }

    print("Connection established!\n", .{});

    const filename_length: u32 = @intCast(filename.len);

    // transmission plan:
    //  - filename_length: u32
    //  - filename: [filename_length]u8
    //  - file_size: u32
    //  - file: [file_size]u8
    print("Sent {d} bytes (filename length, {d})\n", .{ socket.send(network_socket, &filename_length, @sizeOf(@TypeOf(filename_length)), 0), filename_length });
    print("Sent {d} bytes (filename, {s})\n", .{ socket.send(network_socket, &buffer, filename.len, 0), filename });
    print("Sent {d} bytes (file size, {d})\n", .{ socket.send(network_socket, &file_size, @sizeOf(@TypeOf(file_size)), 0), file_size });

    print("Starting transmission...\n", .{});
    var total_bytes_transferred: @TypeOf(file_size) = 0;
    while (total_bytes_transferred < file_size) {
        const payload_size = @min(buffer.len, @as(usize, @intCast(file_size - total_bytes_transferred)));
        const fread_res = c.fread(&buffer, @sizeOf(u8), @intCast(payload_size), fptr.?);
        if (fread_res == -1) {
            print("fread returned -1\n", .{});
            break;
        }
        const bytes_sent = socket.send(network_socket, &buffer, payload_size, 0);
        // print("Sent {d} bytes\n", .{bytes_sent});
        if (bytes_sent == -1) {
            print("Error sending data\n", .{});
            break;
        }
        total_bytes_transferred += @intCast(bytes_sent);
        // print("Transferred {d}/{d} bytes\n", .{ total_bytes_transferred, file_size });
    }
}
