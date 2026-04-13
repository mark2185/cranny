const android = @cImport({
    @cInclude("dlfcn.h");
    @cInclude("android/log.h");
});

export fn ANativeActivity_onCreate(_: *anyopaque, _: *anyopaque, _: usize) void {
    _ = android.__android_log_write(android.ANDROID_LOG_INFO, "COM_CRANNY_ZIG", "HELLO WORLD");
    _ = android.dlopen("/data/app-lib/com.cranny.zig-1/libcranny.so", android.RTLD_NOW);
    if (android.dlerror()) |msg| {
        _ = android.__android_log_write(android.ANDROID_LOG_INFO, "COM_CRANNY_ZIG", msg);
    }
}
