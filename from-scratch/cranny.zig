const std = @import("std");
const log = @cImport({
    @cInclude("android/log.h");
});

fn LOGI(text: [*c]const u8) void {
    _ = log.__android_log_write(4, "MANUAL_TAG_ZIG", text);
}

// TODO: how to implement a variadic?
// LOGFI(text: [*c]const u8, ...) void {
// _ = __android_log_print(4, "MANUAL_TAG_ZIG", text,
// }

export fn zig_main() callconv(.c) void {
    _ = log.__android_log_write(4, "MANUAL_TAG_ZIG", "Hello from zig_main!");

    const address = std.net.Address.parseIp4("0.0.0.0", 7979) catch {
        LOGI("Could not parse IPv4");
        return;
    };

    var server = address.listen(.{}) catch {
        LOGI("Error listening!");
        return;
    };
    defer server.deinit();

    while (true) {
        handleConnection(server.accept() catch {
            LOGI("Error accepting connection!");
            return;
        }) catch {
            LOGI("Error handling a connection!");
            return;
        };
        LOGI("Connection successful!");
    }
}

fn handleConnection(conn: std.net.Server.Connection) !void {
    defer conn.stream.close();
    var buffer: [1024]u8 = undefined;

    var reader = conn.stream.reader(&buffer);
    var data_slices = [1][]u8{&buffer};
    _ = reader.interface().readVec(&data_slices) catch {
        LOGI("Error reading from connection stream");
        return;
    };
}
