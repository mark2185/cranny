const android = @cImport({
    @cInclude("android/log.h");
    @cInclude("android/native_activity.h");
});

const c_socket = @cImport({
    @cInclude("sys/types.h");
    @cInclude("sys/socket.h");
    @cInclude("sys/endian.h");
    @cInclude("netinet/in.h");
    @cInclude("pthread.h");
    @cInclude("string.h");
});

const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("unistd.h");
});
const mem = @import("std").mem;

fn LOGI(text: [*c]const u8) void {
    _ = android.__android_log_write(4, "MANUAL_TAG_ZIG", text);
}

fn LOGFI(text: [*c]const u8, ...) callconv(.c) void {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);

    _ = android.__android_log_print(4, "MANUAL_TAG_ZIG", text, @cVaArg(&ap, [*c]const u8));
}

comptime {
    @export(&entrypoint, .{ .name = "ANativeActivity_onCreate" });
}

fn run(_: ?*anyopaque) callconv(.c) ?*anyopaque {
    const socket: c_int = c_socket.socket(c_socket.AF_INET, c_socket.SOCK_STREAM, 0);
    defer _ = c.close(socket);

    LOGI("socket created");

    const server_address = c_socket.sockaddr_in{
        .sin_family = c_socket.AF_INET,
        // 11039 is 7979 in big-endian
        .sin_port = 11039,
        .sin_addr = c_socket.in_addr{
            .s_addr = c_socket.INADDR_ANY,
        },
    };

    LOGI("server address created");

    const bind_result = c_socket.bind(socket, @ptrCast(&server_address), @sizeOf(@TypeOf(server_address)));
    if (bind_result == -1) {
        LOGI("Bind failed!");
        return &.{};
    }

    LOGI("bind successful");

    const listen_result = c_socket.listen(socket, 1);
    if (listen_result == -1) {
        LOGI("Listen returned -1");
        return &.{};
    }
    LOGI("Listening...");

    const client = c_socket.accept(socket, null, null);
    defer _ = c.close(client);

    LOGI("Connection accepted");
    // LOGFI("Client fd: %d", client);

    // transmission plan:
    //  - filename_length: u32
    //  - filename: [filename_length]u8
    //  - file_size: u32
    //  - file: [file_size]u8

    var filename_length: u32 = undefined;
    LOGFI("Received %d bytes (filename_length)", c_socket.recv(client, &filename_length, @sizeOf(@TypeOf(filename_length)), 0));

    var file_name: [256]u8 = @splat(0);

    var i: usize = 0;
    const external_data_path = "/storage/sdcard0/books/";
    while (external_data_path[i] != 0) : (i += 1) {
        file_name[i] = external_data_path[i];
    }

    LOGFI("Received %d bytes (filename)", c_socket.recv(client, &file_name[i], filename_length, 0));
    LOGFI("File name: '%s'", @as([*c]const u8, @ptrCast(&file_name)));

    const fptr = c.fopen(@ptrCast(&file_name), "wb");
    if (fptr == null) {
        LOGI("Could not open file");
        return &.{};
    }
    defer _ = c.fclose(fptr.?);

    const file_size: u32 = blk: {
        var ret: u32 = undefined;
        LOGFI("Received %d bytes (file_size)", c_socket.recv(client, &ret, @sizeOf(@TypeOf(ret)), 0));
        break :blk ret;
    };
    LOGFI("File size: %d bytes", file_size);

    LOGI("Starting transmission...");
    var total_bytes_transferred: u32 = 0;
    var buffer: [4096]u8 = undefined;
    while (total_bytes_transferred < file_size) {
        const payload_size: usize = @min(buffer.len, @as(usize, @intCast(file_size - total_bytes_transferred)));
        LOGFI("Payload size: %d", payload_size);
        const bytes_received = c_socket.recv(client, &buffer, payload_size, 0);
        if (bytes_received == -1) {
            LOGI("Recv returned -1");
            break;
        }
        total_bytes_transferred += @intCast(bytes_received);
        LOGFI("Bytes received: %d", bytes_received);
        // LOGFI("Transferred %d/%d bytes", total_bytes_transferred, file_size);
        LOGFI("Total bytes remaining %d", file_size - total_bytes_transferred);
        const fwrite_res = c.fwrite(&buffer, @sizeOf(u8), @intCast(bytes_received), fptr.?);
        if (fwrite_res == -1) {
            LOGI("fwrite returned -1");
            break;
        }
    }

    return &.{};
}

/// it's gonna be blocking, I don't care
fn onStart(_: [*c]android.ANativeActivity) callconv(.c) void {
    LOGI("+onStart()");
    defer LOGI("-onStart()");

    var tid: c_socket.pthread_t = undefined;
    _ = c_socket.pthread_create(&tid, null, &run, null);
}

fn entrypoint(activity: [*c]android.ANativeActivity, _: *anyopaque, _: usize) callconv(.c) void {
    LOGI("Hello world!");
    LOGFI("%s", activity.*.externalDataPath);
    defer LOGI("Goodbye world!");

    activity.*.callbacks.*.onStart = onStart;
}
