const std = @import("std");
const log = @cImport({
    @cInclude("android/log.h");
});

// const native_activity = @cImport({
// @cInclude("android/native_activity.h");
// });

fn LOGI(text: [*c]const u8) void {
    _ = log.__android_log_write(4, "MANUAL_TAG_ZIG", text);
}

const ANativeActivity = struct {};

export fn ANativeActivity_onCreate(_: *ANativeActivity, _: *anyopaque, _: u32) void {
    LOGI("Hello from ANativeActivity_onCreate!");
}

// TODO: how to implement a variadic?
// LOGFI(text: [*c]const u8, ...) void {
// _ = __android_log_print(4, "MANUAL_TAG_ZIG", text,
// }

fn zig_main() callconv(.c) void {
    LOGI("Hello from zig_main!");
    // log.__android_log_print(4, "MANUAL_TAG_ZIG", "Sdk version: %d", native_activity.ANativeActivity.sdkVersion);

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
        LOGI("Waiting for a connection on port 7979!");
        // std.Thread.sleep(100_000_000);
        handleConnection(server.accept() catch {
            LOGI("Error accepting connection on port 7979!");
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
