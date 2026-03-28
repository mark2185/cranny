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
        handleConnection(server.accept() catch |err| {
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
    }
}

fn handleConnection(conn: std.net.Server.Connection, storage: []const u8) !void {
    defer conn.stream.close();

    var recv_buffer: [1024]u8 = undefined;
    var send_buffer: [1024]u8 = undefined;

    var connection_br = conn.stream.reader(&recv_buffer);
    var connection_bw = conn.stream.writer(&send_buffer);

    var server = std.http.Server.init(connection_br.interface(), &connection_bw.interface);
    var request = server.receiveHead() catch |err| {
        LOGI("Unable to receive head from the HTTP request");
        LOGI(@errorName(err));
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
                const content_length = blk: {
                    var it = request.iterateHeaders();
                    while (it.next()) |h| {
                        if (std.mem.eql(u8, "Content-Length", h.name)) {
                            break :blk std.fmt.parseInt(u16, h.value, 10) catch unreachable;
                        }
                    }
                    break :blk 0;
                };

                LOGFI("Content length: %d", content_length);

                // head strings expire here
                var write_buffer: [1024]u8 = undefined;
                var read_buffer: [1024]u8 = undefined;
                // var fba = std.heap.FixedBufferAllocator.init(&write_buffer);
                // const allocator = fba.allocator();

                var dir = std.fs.cwd().openDir(storage, .{}) catch unreachable;
                defer dir.close();

                LOGFI("Storage: %s", @as([*c]const u8, @ptrCast(storage)));
                var file = dir.createFile("test-file.txt", .{ .truncate = true }) catch {
                    LOGI("Could not open file for writing!");
                    return;
                };
                defer file.close();

                var file_writer = file.writerStreaming(&write_buffer);

                const body = request.readerExpectNone(&read_buffer);
                LOGI("Starting streaming!");
                body.streamExact(&file_writer.interface, 1024) catch {
                    LOGI("Stream remaining failed");
                    return;
                };

                // LOGFI("Bytes streamed: %d", bytes_streamed);
                // body.streamRemaining(
                //.allocRemaining(allocator, .limited(buffer.len)) catch {
                // LOGI("Failed to alloc remaining");
                // return;
                // };
                // defer allocator.free(body);

                request.respond("bye\n", .{}) catch unreachable;
                LOGI("Request processed!");
            }
        },
        else => LOGI("Got something else"),
    }
}

fn onStart(activity: [*c]native_activity.ANativeActivity) callconv(.c) void {
    LOGI("+onStart()");
    defer LOGI("-onStart()");

    if (http_thread == null) {
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

var q: *input.AInputQueue = undefined;

export fn ANativeActivity_onCreate(activity: [*c]native_activity.ANativeActivity, _: *anyopaque, _: usize) void {
    LOGI("Hello from ANativeActivity_onCreate!");
    activity.*.callbacks.*.onStart = onStart;
    activity.*.callbacks.*.onStop = onStop;
}
