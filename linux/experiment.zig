const std = @import("std");
const builtin = @import("builtin");

const android =
    if (builtin.abi.isAndroid())
        @cImport({
            @cInclude("android/log.h");
            @cInclude("android/native_activity.h");
        })
    else
        @compileError("Cannot use android on non-android platforms");

comptime {
    if (builtin.abi.isAndroid()) {
        @export(&android_entrypoint, .{ .name = "ANativeActivity_onCreate" });
    }
}

// zig fmt: off
const LOGI = if (builtin.abi.isAndroid()) android_log.LOGI else desktop.LOGI;
const LOGE = if (builtin.abi.isAndroid()) android_log.LOGE else desktop.LOGE;
const desktop = struct {
    fn LOGI(text: []const u8) void { std.debug.print("{s}\n", .{text}); }
    fn LOGE(text: []const u8) void { std.debug.print("{s}\n", .{text}); }
};
const android_log = struct {
    fn LOGI(text: [*c]const u8) void { _ = android.__android_log_write(android.ANDROID_LOG_INFO , "COM_EXPERIMENT_APK", text); }
    fn LOGE(text: [*c]const u8) void { _ = android.__android_log_write(android.ANDROID_LOG_ERROR, "COM_EXPERIMENT_APK", text); }
};
// zig fmt: on

var storage_path: []const u8 = undefined;

// data is sent via:
// curl --verbose --data-binary '@minimal.zig' --header 'Content-Type: application/octet-stream' 127.0.0.1:6868

fn doEverything() void {
    const address = std.Io.net.IpAddress.parseIp4("0.0.0.0", 6868) catch {
        LOGE("Could not parse IPv4");
        return;
    };

    var threaded: std.Io.Threaded = .init_single_threaded;
    defer threaded.deinit();

    var server = address.listen(threaded.io(), .{ .reuse_address = true }) catch {
        LOGE("Error listening");
        return;
    };
    defer server.deinit(threaded.io());

    LOGI("Listening for a connection...");
    handleConnection(threaded.io(), server.accept(threaded.io()) catch {
        LOGE("Error accepting connection");
        return;
    });
}

fn handleConnection(io: std.Io, stream: std.Io.net.Stream) void {
    LOGI("Handling a connection!");
    defer stream.close(io);

    var recv_buffer: [512]u8 = undefined;
    var send_buffer: [512]u8 = undefined;

    var connection_br = stream.reader(io, &recv_buffer);
    var connection_bw = stream.writer(io, &send_buffer);

    var server = std.http.Server.init(&connection_br.interface, &connection_bw.interface);
    var request = server.receiveHead() catch {
        LOGE("Unable to receive head from the HTTP request");
        return;
    };

    handleRequest(io, &request);
}

// desktop version
pub fn main() void {
    storage_path = ".";
    doEverything();
}

// android version
fn android_entrypoint(activity: [*c]android.ANativeActivity, _: *anyopaque, _: usize) callconv(.c) void {
    LOGI(std.mem.span(activity.*.externalDataPath));
    storage_path = std.mem.span(activity.*.externalDataPath);
    doEverything();
}

fn handleRequest(io: std.Io, request: *std.http.Server.Request) void {
    LOGI("Handling a request!");
    var filebuf: [128]u8 = @splat(0);
    const filepath = std.fmt.bufPrint(&filebuf, "{s}/output.txt", .{storage_path}) catch {
        LOGE("Could not create a filepath");
        return;
    };
    var file = std.Io.Dir.cwd().createFile(io, filepath, .{}) catch {
        LOGE("Could not open file for writing!");
        return;
    };
    defer file.close(io);

    var file_buffer: [512]u8 = undefined;
    var file_writer = file.writer(io, &file_buffer);

    // var buf: [512]u8 = undefined;
    var reader = request.readerExpectContinue(&.{}) catch {
        LOGE("Could not get a reader from the request!");
        return;
    };

    LOGI("Streaming remaining data!");
    _ = reader.streamRemaining(&file_writer.interface) catch {
        LOGE("Failed to stream remaining data\n");
        return;
    };
    LOGI("Streaming completed!");

    file_writer.interface.flush() catch {
        LOGE("Failed to flush the file writer buffer");
        return;
    };

    request.respond("Message received\n", .{}) catch {
        LOGE("Cannot respond to the request");
        return;
    };
}
