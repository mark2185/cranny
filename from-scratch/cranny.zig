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

fn getFilename(content_disposition: []const u8) ![]const u8 {
    if (!std.mem.containsAtLeast(u8, content_disposition, 1, "filename=")) {
        return (error{FilenameNotFound}).FilenameNotFound;
    }
    var it = std.mem.splitScalar(u8, content_disposition, ';');
    while (it.next()) |field| {
        if (std.mem.startsWith(u8, std.mem.trim(u8, field, " \t\n\r"), "filename=")) {
            return std.mem.trim(u8, field["filename=".len..], " =\"");
        }
    }
    unreachable;
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
            if (!std.mem.eql(u8, request.head.target, "/upload")) {
                LOGI("Not an upload request!");
                return;
            }

            const content_length = blk: {
                var it = request.iterateHeaders();
                while (it.next()) |h| {
                    if (std.mem.eql(u8, "Content-Length", h.name)) {
                        break :blk std.fmt.parseInt(u16, h.value, 10) catch unreachable;
                    }
                }
                break :blk 0;
            };
            // LOGFI("Content length: %d", request.head.content_length.?);
            LOGFI("Content length: %d", content_length);

            var yab: [2048]u8 = undefined;
            var reader = request.readerExpectContinue(&yab) catch {
                // std.debug.print("Reader expect continue failed: {any}\n", .{err});
                return;
            };

            // the body should begin with the following lines:
            // <boundary>\r\n
            // Content-Disposition\r\n
            // Content-Type\r\n
            // \r\n
            const boundary = reader.takeDelimiterExclusive('\r') catch {
                LOGI("Cannot take delimiter");
                return;
            };
            _ = reader.discard(.limited(2)) catch { // \r\n
                LOGI("Cannot take '\\r\\n'");
                return;
            };
            const content_disposition = reader.takeDelimiterExclusive('\r') catch unreachable;
            _ = reader.discard(.limited(2)) catch { // \r\n
                LOGI("Cannot take '\\r\\n'");
                return;
            };
            _ = reader.takeDelimiterExclusive('\r') catch unreachable;
            _ = reader.discard(.limited(4)) catch { // \r\n\r\n
                LOGI("Cannot take '\\r\\n'");
                return;
            };

            var dir = std.fs.cwd().openDir(storage, .{}) catch unreachable;
            defer dir.close();

            const filename = getFilename(content_disposition) catch unreachable;
            var file = dir.createFile(filename, .{}) catch {
                LOGI("Could not open file for writing!");
                return;
            };
            defer file.close();

            var file_buffer: [2048]u8 = undefined;
            const exact = content_length - reader.seek - (boundary.len + 6); // the ending boundary has two dashes extra
            LOGFI("Exact: %d", exact);
            var file_writer = file.writer(&file_buffer);
            LOGFI("Gotten file writer");
            reader.streamExact64(&file_writer.interface, exact) catch {
                LOGI("naniiiiiiiii\n");
            };

            LOGI("Flushing!");
            file_writer.interface.flush() catch unreachable;

            request.respond("bye\n", .{}) catch unreachable;
            LOGI("Request processed!");
            LOGFI("File %s created!", @as([*c]const u8, @ptrCast(storage)));
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

export fn ANativeActivity_onCreate(activity: [*c]native_activity.ANativeActivity, _: *anyopaque, _: usize) void {
    activity.*.callbacks.*.onStart = onStart;
    activity.*.callbacks.*.onStop = onStop;
}
