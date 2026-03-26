const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{ .default_target = .{ .cpu_arch = .arm, .os_tag = .linux, .abi = .androideabi, .dynamic_linker = .init("/opt/android-sdk/ndk/25.2.9519653/toolchains/llvm/prebuilt/linux-x86_64/bin/ld.lld") } });

    const optimize = std.builtin.OptimizeMode.ReleaseSmall;

    // TODO: why does dlopen fail for a debug build
    // const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSmall });

    const lib = b.createModule(.{
        .root_source_file = b.path("cranny.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
        .strip = false,
    });

    lib.addLibraryPath(std.Build.LazyPath{
        .cwd_relative = "/opt/android-sdk/ndk/25.2.9519653/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/arm-linux-androideabi/26",
    });

    lib.addIncludePath(std.Build.LazyPath{ .cwd_relative = "/opt/android-sdk/ndk/25.2.9519653/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include" });

    lib.linkSystemLibrary("log", .{});
    lib.linkSystemLibrary("android", .{});

    const libcranny = b.addLibrary(.{
        .name = "cranny",
        .linkage = .dynamic,
        .root_module = lib,
    });
    libcranny.rdynamic = true;

    libcranny.libc_file = b.path("libc.txt");

    b.getInstallStep().dependOn(&b.addInstallArtifact(libcranny, .{
        .dest_dir = .{ .override = .{ .custom = "lib/armeabi-v7a" } },
    }).step);
}
