const std = @import("std");
const log = @cImport({
    @cInclude("android/log.h");
});

const native_activity = @cImport({
    @cInclude("android/native_activity.h");
});
const input = @cImport({
    @cInclude("android/input.h");
});

fn LOGI(text: [*c]const u8) void {
    _ = log.__android_log_write(4, "MANUAL_TAG_ZIG", text);
}

fn LOGFI(text: [*c]const u8, ...) callconv(.c) void {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);

    _ = log.__android_log_print(4, "MANUAL_TAG_ZIG", text, @cVaArg(&ap, [*c]const u8));
}

const ANativeWindow = extern struct {};
const ARect = extern struct {};

var http_thread: ?std.Thread = null;

var server_running = false;

fn runServer(storage: []const u8) void {
    var buffer: [1024]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&buffer);
    const allocator = fba.allocator();

    LOGI("+runServer()");
    defer LOGI("-runServer()");

    const address = std.net.Address.parseIp4("0.0.0.0", 7979) catch {
        LOGI("Could not parse IPv4");
        return;
    };

    var server = address.listen(.{ .reuse_address = true, .force_nonblocking = true }) catch {
        LOGI("Error listening on the address!");
        return;
    };
    defer server.deinit();
    while (server_running) {
        handleConnection(allocator, server.accept() catch |err| {
            switch (err) {
                // No connection was made which means the call to accept would block
                error.WouldBlock => continue,
                else => LOGI("Uh-oh, an actual error occurred!"),
            }
            return;
        }, storage) catch {
            LOGI("Error handling a connection!");
            return;
        };
        LOGI("Connection successful!");
    }
}

fn onStart(activity: [*c]native_activity.ANativeActivity) callconv(.c) void {
    LOGI("+onStart()");
    defer LOGI("-onStart()");

    if (http_thread == null) {
        LOGI("Spawning a thread!");
        server_running = true;
        http_thread = std.Thread.spawn(.{}, runServer, .{std.mem.span(activity.*.externalDataPath)}) catch {
            LOGI("Could not spawn a thread");
            return;
        };
    }
}

fn onStop(_: [*c]native_activity.ANativeActivity) callconv(.c) void {
    LOGI("+onStop()");
    defer LOGI("-onStop()");
    if (http_thread) |t| {
        server_running = false;
        t.join();
        LOGI("HTTP server thread joined");
        http_thread = null;
    }
}

fn handleConnection(allocator: std.mem.Allocator, conn: std.net.Server.Connection, storage: []const u8) !void {
    defer conn.stream.close();

    var recv_buffer: [1024]u8 = undefined;
    var send_buffer: [1024]u8 = undefined;

    var connection_br = conn.stream.reader(&recv_buffer);
    var connection_bw = conn.stream.writer(&send_buffer);

    var server = std.http.Server.init(connection_br.interface(), &connection_bw.interface);
    var request = server.receiveHead() catch {
        LOGI("Unable to receive head from the HTTP request");
        return;
    };

    switch (request.head.method) {
        .GET => {
            LOGI("Got a GET request!");
            if (std.mem.eql(u8, request.head.target, "/list")) {
                var response = request.respondStreaming(&.{}, .{}) catch unreachable;
                var dir = std.fs.cwd().openDir(storage, .{ .iterate = true }) catch unreachable;
                defer dir.close();

                var it = dir.iterate();
                while (it.next() catch unreachable) |file| {
                    response.writer.writeAll(file.name) catch unreachable;
                    response.writer.writeAll("\n") catch unreachable;
                }
                response.endChunked(.{}) catch unreachable;
            }
        },
        .POST => {
            LOGI("Got a POST request!");
            if (std.mem.eql(u8, request.head.target, "/upload")) {
                // head strings expire here
                const body = try (try request.readerExpectContinue(&.{})).allocRemaining(allocator, .unlimited);
                defer allocator.free(body);
            }
        },
        else => LOGI("Got something else"),
    }
}

var q: *input.AInputQueue = undefined;

export fn ANativeActivity_onCreate(activity: [*c]native_activity.ANativeActivity, _: *anyopaque, _: usize) void {
    LOGI("Hello from ANativeActivity_onCreate!");
    activity.*.callbacks.*.onStart = onStart;
    activity.*.callbacks.*.onStop = onStop;

    // while (true) {
    // var event: *AInputEvent = undefined;
    // if (q) {
    // LOGI("input queue is a nullptr");
    // } else if (input.AInputQueue_hasEvents(q) == 1) {
    // LOGI("An event has been logged!");
    // }
    // }
    LOGI("Goodbye from ANativeActivity_onCreate!");
}
