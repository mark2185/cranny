const std = @import("std");

const android = @cImport({
    @cInclude("android/log.h");
    @cInclude("android/native_activity.h");
});

fn LOGI(msg: [*c]const u8) void {
    _ = android.__android_log_write(android.ANDROID_LOG_INFO, "COM_CRANNY_ZIG", msg);
}

export fn ANativeActivity_onCreate(activity: *android.ANativeActivity, _: *anyopaque, _: usize) void {
    // LOGI(activity.*.externalDataPath);
    activity.*.callbacks.*.onStart = &onStart;
    activity.*.callbacks.*.onStop = &onStop;
}

var worker: ?std.Thread = null;
var server_running: bool = false;

export fn accept4(
    sockfd: std.os.linux.fd_t,
    noalias addr: ?*std.os.linux.sockaddr,
    noalias addrlen: ?*std.os.linux.socklen_t,
    _: c_uint,
) c_int {
    LOGI("+accept4()");
    defer LOGI("-accept4()");
    return std.c.accept(sockfd, addr, addrlen);
}

export fn openat64(fd: c_int, path: [*:0]const u8, oflag: std.os.linux.O, ...) c_int {
    LOGI("+openat64()");
    defer LOGI("-openat64()");
    return std.c.openat(fd, path, oflag);
}

export fn pwritev64(fd: c_int, iov: [*]const std.posix.iovec_const, iovcnt: c_uint, offset: i64) isize {
    LOGI("+pwritev64()");
    defer LOGI("-pwritev64()");
    return std.c.pwritev64(fd, iov, iovcnt, offset);
}

export fn preadv64(fd: c_int, iov: [*]const std.posix.iovec, iovcnt: c_uint, offset: i64) isize {
    LOGI("+preadv64()");
    defer LOGI("-preadv64()");
    return std.c.preadv64(fd, iov, iovcnt, offset);
}

export fn sendfile64(out_fd: std.os.linux.fd_t, in_fd: std.os.linux.fd_t, offset: ?*i64, count: usize) isize {
    LOGI("+psendfile64()");
    defer LOGI("-psendfile64()");
    return std.c.sendfile64(out_fd, in_fd, offset, count);
}

fn onStart(_: [*c]android.ANativeActivity) callconv(.c) void {
    LOGI("+onStart()");
    if (worker == null) {
        server_running = true;
        worker = std.Thread.spawn(.{}, runServer, .{}) catch |err| return LOGI(@errorName(err));
    }

    defer LOGI("-onStart()");
}

fn onStop(_: [*c]android.ANativeActivity) callconv(.c) void {
    LOGI("+onStop()");
    if (worker) |t| {
        server_running = false;
        LOGI("Joining worker thread...");
        t.join();
        worker = null;
    }
    defer LOGI("-onStop()");
}

fn runServer() void {
    LOGI("+runServer()");
    defer LOGI("-runServer()");

    const address = std.Io.net.IpAddress.parseIp4("0.0.0.0", 7979) catch |err| return LOGI(@errorName(err));

    var threaded: std.Io.Threaded = .init_single_threaded;
    defer threaded.deinit();

    LOGI("Listening...");
    var server = address.listen(threaded.io(), .{}) catch |err| return LOGI(@errorName(err));
    defer server.deinit(threaded.io());

    LOGI("Waiting for a connection...");
    handleConnection(threaded.io(), server.accept(threaded.io()) catch |err| return LOGI(@errorName(err)), "/storage/emulated/0/Android/data/com.cranny.zig/files");
}

fn handleConnection(io: std.Io, stream: std.Io.net.Stream, storage: []const u8) void {
    LOGI("+handleConnection()");
    defer {
        stream.close(io);
        LOGI("-handleConnection()");
    }

    var recv_buffer: [512]u8 = undefined;
    var send_buffer: [512]u8 = undefined;

    var connection_br = stream.reader(io, &recv_buffer);
    var connection_bw = stream.writer(io, &send_buffer);

    var server = std.http.Server.init(&connection_br.interface, &connection_bw.interface);
    var request = server.receiveHead() catch |err| return LOGI(@errorName(err));
    defer request.respond("Thanks for all the fish!\n", .{}) catch |err| LOGI(@errorName(err));

    switch (request.head.method) {
        .POST => {
            LOGI("Processing a POST request");

            var dir = std.Io.Dir.cwd().openDir(io, storage, .{}) catch |err| return LOGI(@errorName(err));
            defer dir.close(io);

            var file = dir.createFile(io, "output.bin", .{}) catch |err| return LOGI(@errorName(err));
            defer file.close(io);

            var rbuf: [512]u8 = undefined;
            var reader = request.readerExpectContinue(&rbuf) catch |err| return LOGI(@errorName(err));

            var wbuf: [512]u8 = undefined;
            var file_writer = file.writer(io, &wbuf);
            _ = reader.streamRemaining(&file_writer.interface) catch |err| return LOGI(@errorName(err));

            file_writer.interface.flush() catch |err| return LOGI(@errorName(err));
        },
        else => LOGI("Request type not supported"),
    }
}
