comptime {
    @export(&entrypoint, .{ .name = "ANativeActivity_onCreate" });
}

const dlfcn = @cImport({
    @cInclude("dlfcn.h");
});

const android_log = @cImport({
    @cInclude("android/log.h");
});

fn LOGI(text: [*c]const u8) void {
    _ = android_log.__android_log_write(4, "COM_CRANNY_ZIG", text);
}

const native_activity = @cImport({
    @cInclude("android/native_activity.h");
});

const std = @import("std");

fn entrypoint(_: [*c]native_activity.ANativeActivity, _: *anyopaque, _: usize) callconv(.c) void {
    LOGI("+entrypoint()");
    defer LOGI("-entrypoint()");

    const locations: []const [*c]const u8 = &.{ "/data/app-lib/com.cranny.zig-1/libcranny.so", "/data/app-lib/com.cranny.zig-2/libcranny.so" };
    for (locations) |loc| {
        _ = dlfcn.dlopen(loc, dlfcn.RTLD_NOW);
        const err = dlfcn.dlerror();
        if (err != null) {
            LOGI(err);
        }
    }
}
