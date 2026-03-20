/// Writes the constant string text to the log, with priority prio and tag tag.
/// Returns: 1 if the message was written to the log, or -EPERM if it was not; see __android_log_is_loggable().
/// Source: https://developer.android.com/ndk/reference/group/logging
extern fn __android_log_write(prio: c_int, tag: [*c]const u8, text: [*c]const u8) c_int;

/// Writes a formatted string to the log, with priority prio and tag tag.
/// The details of formatting are the same as for printf(3)
/// Returns: 1 if the message was written to the log, or -EPERM if it was not; see __android_log_is_loggable().
/// Source: https://man7.org/linux/man-pages/man3/printf.3.html
extern fn __android_log_print(prio: c_int, tag: [*c]const u8, text: [*c]const u8, ...) c_int;

const std = @import("std");

fn logI(tag: [*c]const u8, text: [*c]const u8) void {
    _ = __android_log_write(4, tag, text);
}

export fn zig_main() callconv(.c) void {
    _ = __android_log_write(4, "MANUAL_TAG_ZIG", "Hello from zig_main!");

    const address = std.net.Address.parseIp4("127.0.0.1", 7979) catch {
        logI("MANUAL_TAG_ZIG", "Could not parse IPv4");
        return;
    };

    var server = address.listen(.{}) catch {
        logI("MANUAL_TAG_ZIG", "Error listening!");
        return;
    };
    defer server.deinit();
}
