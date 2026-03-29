const std = @import("std");

const armv7 = true;

pub fn build(b: *std.Build) !void {
    const ndk_version = "16.1.4479499";
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = if (armv7) .arm else .aarch64,
            .os_tag = .linux,
            .abi = if (armv7) .androideabi else .android,
            //.dynamic_linker = .init("/opt/android-sdk/ndk/25.2.9519653/toolchains/llvm/prebuilt/linux-x86_64/bin/ld.lld")
        },
    });

    const optimize = std.builtin.OptimizeMode.ReleaseSmall;

    const lib = b.createModule(.{
        .root_source_file = b.path("cranny.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
        .strip = false,
    });

    lib.addLibraryPath(std.Build.LazyPath{
        .cwd_relative = "/opt/android-sdk/ndk/" ++ ndk_version ++ "/platforms/android-19/arch-arm/usr/lib",
    });

    lib.addIncludePath(std.Build.LazyPath{ .cwd_relative = "/opt/android-sdk/ndk/" ++ ndk_version ++ "/sysroot/usr/include" });

    lib.linkSystemLibrary("log", .{});
    lib.linkSystemLibrary("android", .{});

    const libcranny = b.addLibrary(.{
        .name = "cranny",
        .linkage = .dynamic,
        .root_module = lib,
    });
    libcranny.rdynamic = true;

    libcranny.libc_file = b.path(if (armv7) "libc.txt" else "libc-armv8.txt");

    b.getInstallStep().dependOn(&b.addInstallArtifact(libcranny, .{
        .dest_dir = .{ .override = .{ .custom = "lib/armeabi-v7a" } },
    }).step);
}
