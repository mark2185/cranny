const std = @import("std");
const android_log = @cImport({
    @cInclude("android/log.h");
});

const native_activity = @cImport({
    @cInclude("android/native_activity.h");
});
const input = @cImport({
    @cInclude("android/input.h");
});

fn LOGI(text: [*c]const u8) void {
    _ = android_log.__android_log_write(4, "MANUAL_TAG_ZIG", text);
}

fn LOGFI(text: [*c]const u8, ...) callconv(.c) void {
    var ap = @cVaStart();
    defer @cVaEnd(&ap);

    _ = android_log.__android_log_print(4, "MANUAL_TAG_ZIG", text, @cVaArg(&ap, [*c]const u8));
}

const ANativeWindow = extern struct {};
const ARect = extern struct {};

var http_thread: ?std.Thread = null;

var server_running = false;

export fn accept4(sockfd: std.os.linux.fd_t, noalias addr: ?*std.os.linux.sockaddr, noalias addrlen: ?*std.os.linux.socklen_t) c_int {
    return std.c.accept(sockfd, addr, addrlen);
}

export fn openat64(fd: c_int, path: [*:0]const u8, oflag: std.os.linux.O, ...) c_int {
    return std.c.openat(fd, path, oflag);
}

export fn pwritev64(fd: c_int, iov: [*]const std.posix.iovec_const, iovcnt: c_uint, offset: i64) isize {
    return std.c.pwritev64(fd, iov, iovcnt, offset);
}

export fn preadv64(fd: c_int, iov: [*]const std.posix.iovec, iovcnt: c_uint, offset: i64) isize {
    return std.c.preadv64(fd, iov, iovcnt, offset);
}

export fn sendfile64(out_fd: std.os.linux.fd_t, in_fd: std.os.linux.fd_t, offset: ?*i64, count: usize) isize {
    return std.c.sendfile64(out_fd, in_fd, offset, count);
}

fn runServer(storage: []const u8) void {
    LOGI("+runServer()");
    defer LOGI("-runServer()");

    const address = std.net.Address.parseIp4("0.0.0.0", 7979) catch {
        LOGI("Could not parse IPv4");
        return;
    };

    var server = address.listen(.{}) catch |err| {
        LOGI("Error listening on the address!");
        LOGI(@errorName(err));
        return;
    };
    defer server.deinit();

    LOGI("Waiting for connection...");
    handleConnection(server.accept() catch |err| {
        LOGI("Could not accept connection");
        LOGI(@errorName(err));
        return;
    }, storage);

    // var accepted_addr: std.net.Address = undefined;
    // var addr_len: std.posix.socklen_t = @sizeOf(std.net.Address);
    // _ = std.posix.accept(server.stream.handle, &accepted_addr.any, &addr_len, std.posix.SOCK.CLOEXEC) catch LOGI("uh-oh");
    // _ = std.net.Server.Connection{
    // .stream = .{ .handle = fd },
    // .address = accepted_addr,
    // };
    // handleConnection(server.accept() catch {
    // return;
    // }, "path") catch {
    // LOGI("Error handling a connection!");
    // return;
    // };
}

fn getFilename(content_disposition: []const u8) ![]const u8 {
    if (!std.mem.containsAtLeast(u8, content_disposition, 1, "filename=")) {
        return (error{FilenameNotFound}).FilenameNotFound;
    }
    var it = std.mem.splitScalar(u8, content_disposition, ';');
    while (it.next()) |field| {
        if (std.mem.startsWith(u8, std.mem.trim(u8, field, " \t\n\r"), "filename=")) {
            LOGI("Found the filename!");
            return std.mem.trim(u8, field["filename=".len..], " =\"");
        }
    }
    unreachable;
}

fn handleConnection(conn: std.net.Server.Connection, storage: []const u8) void {
    defer conn.stream.close();

    var recv_buffer: [4096]u8 = undefined;
    var send_buffer: [4096]u8 = undefined;

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
                response.writer.writeAll("Bookshelf:\n") catch unreachable;
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
            LOGFI("Content length from the header: %d", request.head.content_length.?);
            LOGFI("Content length: %d", content_length);

            var yab: [4096]u8 = undefined;
            var reader = request.readerExpectNone(&yab); //catch {
            // std.debug.print("Reader expect continue failed: {any}\n", .{err});
            // return;
            // };

            // the body is structured as such:
            // <boundary>\r\n
            // Content-Disposition\r\n
            // Content-Type\r\n
            // \r\n
            const boundary = reader.takeDelimiterExclusive('\r') catch {
                LOGI("Cannot take delimiter");
                return;
            };
            _ = boundary;
            _ = reader.discard(.limited(2)) catch { // \r\n
                LOGI("Cannot take '\\r\\n'");
                return;
            };
            const content_disposition = reader.takeDelimiterExclusive('\r') catch unreachable;
            _ = reader.discard(.limited(2)) catch { // \r\n
                LOGI("Cannot take '\\r\\n'");
                return;
            };
            _ = reader.takeDelimiterExclusive('\r') catch unreachable; // Content-Type
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

            var str_buf: [64]u8 = @splat(0);
            @memcpy(&str_buf, filename);
            str_buf[filename.len] = 0;
            LOGFI("Filename: %s", &str_buf);

            // var file_buffer: [2048]u8 = undefined;
            // const exact: usize = content_length - reader.seek - (boundary.len + 6); // the ending boundary has two dashes extra
            const exact: usize = 1500;
            LOGFI("Exact: %d", exact);
            var file_writer = file.writer(&.{});
            LOGFI("Gotten file writer");
            // reader.streamExact(&file_writer.interface, exact) catch {
            // LOGI("naniiiiiiiii\n");
            // return;
            // };

            var remaining = content_length - reader.seek;
            while (remaining > 0) : (remaining -= 1024) {
                LOGFI("Remaining: %d", remaining);
                _ = reader.streamExact(&file_writer.interface, @min(1024, remaining)) catch {
                    LOGI("Stream exact failed");
                    break;
                };
                LOGI("Flushing!");
                file_writer.interface.flush() catch unreachable;
            }

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

comptime {
    @export(&zig_entrypoint, .{ .name = "ANativeActivity_onCreate" });
}

fn zig_entrypoint(activity: [*c]native_activity.ANativeActivity, _: *anyopaque, _: usize) callconv(.c) void {
    LOGI("Hello world!");
    defer LOGI("Goodbye world!");
    // _ = dlfcn.dlopen("/data/app-lib/com.manual.apk-1/libcranny.so", dlfcn.RTLD_NOW);

    // const err = dlfcn.dlerror();
    // if (err == null) {
    // LOGI("No error was found!");
    // } else {
    // LOGI(err);
    // }

    activity.*.callbacks.*.onStart = onStart;
    activity.*.callbacks.*.onStop = onStop;
}

const dlfcn = @cImport({
    @cInclude("dlfcn.h");
});

fn simple_http_transfer_experiment(_: [*c]native_activity.ANativeActivity, _: *anyopaque, _: usize) callconv(.c) void {
    LOGI("Hello world!");
    defer LOGI("Goodbye world!");
    _ = dlfcn.dlopen("/data/app-lib/com.manual.apk-1/libcranny.so", dlfcn.RTLD_NOW);
    const err = dlfcn.dlerror();
    if (err == null) {
        LOGI("No error was found!");
    } else {
        LOGI(err);
    }
}

fn buffered_io_experiment(activity: [*c]native_activity.ANativeActivity, _: *anyopaque, _: usize) callconv(.c) void {
    LOGI("Experiment start");
    defer LOGI("experiment end");

    var dir = std.fs.cwd().openDir(std.mem.span(activity.*.externalDataPath), .{}) catch unreachable;
    defer dir.close();

    var file_a = dir.openFile("file_a.txt", .{}) catch {
        LOGI("Cannot open file A");
        return;
    };
    var file_b = dir.createFile("file_b.txt", .{}) catch {
        LOGI("Cannot open file B");
        return;
    };
    LOGI("File B opened");

    defer {
        file_a.close();
        file_b.close();
    }

    var read_buffer: [1024]u8 = undefined;
    var write_buffer: [1024]u8 = undefined;

    var reader = file_a.readerStreaming(&read_buffer);
    var writer = file_b.writerStreaming(&write_buffer);

    const amount: usize = 1024;

    _ = reader.interface.streamRemaining(&writer.interface) catch LOGFI("Could not stream %d bytes!", amount);
    writer.interface.flush() catch LOGI("Could not flush");
}
