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
    _ = android_log.__android_log_write(4, "MANUAL_TAG_ZIG", text);
}

const native_activity = @cImport({
    @cInclude("android/native_activity.h");
});

fn entrypoint(_: [*c]native_activity.ANativeActivity, _: *anyopaque, _: usize) callconv(.c) void {
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
