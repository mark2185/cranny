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

const ANativeActivityCallbacks = extern struct {
    onStart: *const fn (*ANativeActivity) callconv(.c) void,
    onResume: *const fn (*ANativeActivity) callconv(.c) void,
    onSaveInstance: *const fn (*ANativeActivity, usize) callconv(.c) *void,
    onPause: *const fn (*ANativeActivity) callconv(.c) void,
    onStop: *const fn (*ANativeActivity) callconv(.c) void,
    onDestroy: *const fn (*ANativeActivity) callconv(.c) void,
    onWindowFocusChanged: *const fn (*ANativeActivity, c_int) callconv(.c) void,
    onNativeWindowCreated: *const fn (*ANativeActivity, *ANativeWindow) callconv(.c) void,
    onNativeWindowResized: *const fn (*ANativeActivity, *ANativeWindow) callconv(.c) void,
    onNativeWindowRedrawNeeded: *const fn (*ANativeActivity, *ANativeWindow) callconv(.c) void,
    onNativeWindowDestroyed: *const fn (*ANativeActivity, *ANativeWindow) callconv(.c) void,
    onInputQueueCreated: *const fn (*ANativeActivity, *input.AInputQueue) callconv(.c) void,
    onInputQueueDestroyed: *const fn (*ANativeActivity, *input.AInputQueue) callconv(.c) void,
    onContentRectChanged: *const fn (*ANativeActivity, *const ARect) callconv(.c) void,
    onConfigurationChanged: *const fn (*ANativeActivity) callconv(.c) void,
    onLowMemory: *const fn (*ANativeActivity) callconv(.c) void,
};

const ANativeActivity = extern struct {
    callbacks: *ANativeActivityCallbacks,
};

var http_thread: ?std.Thread = null;

var server_running = false;

fn runServer() void {
    LOGI("+runServer()");
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
        }) catch {
            LOGI("Error handling a connection!");
            return;
        };
        LOGI("Connection successful!");
    }
    LOGI("-runServer()");
}

fn onStart(_: *ANativeActivity) callconv(.c) void {
    LOGI("Hello from onStart!");

    if (http_thread == null) {
        LOGI("Creating a thread!");
        server_running = true;
        http_thread = std.Thread.spawn(.{}, runServer, .{}) catch {
            LOGI("Could not spawn a thread");
            return;
        };
    }
}

fn onStop(_: *ANativeActivity) callconv(.c) void {
    LOGI("Hello from onStop!");
    LOGI("Spawned a thread!");
    if (http_thread) |t| {
        server_running = false;
        t.join();
        LOGI("HTTP server thread joined");
        http_thread = null;
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

    LOGFI("Got from the server: %s", &buffer);
}

fn onPause(_: *ANativeActivity) callconv(.c) void {
    // LOGI("pausing");
}

fn onResume(_: *ANativeActivity) callconv(.c) void {
    // LOGI("GUESS WHO'S BACK");
}

var q: *input.AInputQueue = undefined;

fn onInputQueueCreated(_: *ANativeActivity, input_queue: *input.AInputQueue) callconv(.c) void {
    // LOGI("Input queue created");
    q = input_queue;
}

// extern fn AInputQueue_hasEvents(_: *input.AInputQueue) i32;

export fn ANativeActivity_onCreate(activity: *ANativeActivity, _: *anyopaque, _: usize) void {
    LOGI("Hello from ANativeActivity_onCreate!");
    activity.callbacks.onStart = onStart;
    activity.callbacks.onStop = onStop;
    activity.callbacks.onPause = onPause;
    activity.callbacks.onResume = onResume;
    // activity.callbacks.onInputQueueCreated = onInputQueueCreated;

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
