const std = @import("std");

const app_name = "cranny";
const pkg_name = "com.manual.apk";

const android_sdk_path = "/opt/android-sdk";
const ndk_version = "16.1.4479499";
const build_tools_version = "36.0.0";
const build_tools_path = android_sdk_path ++ "/build-tools/" ++ build_tools_version;
const adb_path = android_sdk_path ++ "/platform-tools/adb";

const libc_path = "libc_android16.txt";
const ndk_path = android_sdk_path ++ "/ndk/" ++ ndk_version;

const api_level = "19";
const android_jar_path = android_sdk_path ++ "/platforms/android-" ++ api_level ++ "/android.jar";

const apk_name = app_name ++ ".apk";

fn buildLib(b: *std.Build, target: std.Build.ResolvedTarget, comptime name: []const u8) *std.Build.Step.Compile {
    const module = b.createModule(.{
        .root_source_file = b.path(name ++ ".zig"),
        .target = target,
        // TODO: has to be ReleaseSmall this because of TLS on ARM, investigate
        .optimize = std.builtin.OptimizeMode.ReleaseSmall,
        .link_libc = true,
        .pic = true,
        .strip = false,
    });

    module.addLibraryPath(std.Build.LazyPath{
        .cwd_relative = std.fmt.comptimePrint("{s}/platforms/android-{s}/arch-arm/usr/lib", .{ ndk_path, api_level }),
    });

    module.addIncludePath(std.Build.LazyPath{ .cwd_relative = ndk_path ++ "/sysroot/usr/include" });

    module.linkSystemLibrary("log", .{});
    module.linkSystemLibrary("android", .{});

    const lib = b.addLibrary(.{
        .name = name,
        .linkage = .dynamic,
        .root_module = module,
    });
    lib.libc_file = b.path(libc_path);

    // TODO: investigate
    //lib.rdynamic = true;

    return lib;
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .arm,
            .os_tag = .linux,
            .abi = .androideabi,
            // TODO: investigate
            //.dynamic_linker = .init("/opt/android-sdk/ndk/25.2.9519653/toolchains/llvm/prebuilt/linux-x86_64/bin/ld.lld")
        },
    });

    const install_options = std.Build.Step.InstallArtifact.Options{ .dest_dir = .{ .override = .{ .custom = "lib/armeabi-v7a" } } };

    const libcranny = buildLib(b, target, "cranny");
    const libcranny_install = b.addInstallArtifact(libcranny, install_options);

    const libcheck = buildLib(b, target, "cranny");
    const check = b.step("check", "Step for zls build-on-save feature");
    check.dependOn(&libcheck.step);

    // entrypoint is used for manual dlopen of libcranny to get the error message
    const libentrypoint = buildLib(b, target, "entrypoint");
    const libentrypoint_install = b.addInstallArtifact(libentrypoint, install_options);

    // -=-=-=- Keystore generation -=-=-=-
    // this will be generated in the current directory
    // so it doesn't get regenerated every time you do a clean build
    // zig fmt: off
    const keystore = "my-key.keystore";
    const gen_keystore = b.addSystemCommand(&.{
        "keytool", "-genkey", "-v",
        "-keystore", keystore,
        "-alias", "mykey",
        "-keyalg", "RSA",
        "-keysize", "2048",
        "-validity", "10000",
        "-storepass", "password",
        "-keypass", "password",
        "-dname", "CN=example.com, OU=ID, O=Example, L=Doe, S=John, C=GB",
    });

    gen_keystore.step.dependOn(&libcranny_install.step);

    // -=-=-=- Packaging -=-=-=-
    const package_apk = b.addSystemCommand(&.{
        build_tools_path ++ "/aapt",
        "package",
        // "-v", // verbose
        "-f", // force overwriting files
        "-I", android_jar_path, // add an existing package to base include set
        "-M", "AndroidManifest.xml", // path to the AndroidManifest.xml
        "-F", "zig-out/temp.apk", // output file
    });

    package_apk.step.dependOn(&libcranny_install.step);
    package_apk.step.dependOn(&libentrypoint_install.step);

    // -=-=-=- Zipping -=-=-=-
    const zip_libs = b.addSystemCommand(&.{
        "sh", "-c",
        // has to be this way to have the correct filepaths, i.e. lib/<arch>/*.so
        "cd zig-out && zip temp.apk -D lib/**/*.so",
    });

    zip_libs.step.dependOn(&package_apk.step);

    // -=-=-=- Zip alignment -=-=-=-
    const zipalign = b.addSystemCommand(&.{
        build_tools_path ++ "/zipalign",
        "-v", "4",
        "-f",
        "zig-out/temp.apk",
        "zig-out/" ++ apk_name,
    });

    zipalign.step.dependOn(&zip_libs.step);

    // -=-=-=- Signing -=-=-=-
    const sign_apk = b.addSystemCommand(&.{
        build_tools_path ++ "/apksigner", "sign",
        "--key-pass", "pass:password",
        "--ks-pass", "pass:password",
        "--ks", keystore,
        "zig-out/" ++ apk_name,
    });

    sign_apk.step.dependOn(&zipalign.step);

    const install_apk = b.addSystemCommand(&.{ adb_path, "install", "-r", "zig-out/" ++ apk_name });
    install_apk.step.dependOn(&sign_apk.step);

    const run_app = b.addSystemCommand(&.{
        adb_path, "shell", "am", "start", pkg_name ++ "/android.app.NativeActivity",
    });
    run_app.step.dependOn(&install_apk.step);

    const install_step = b.getInstallStep();
    install_step.dependOn(&libcranny_install.step);
    install_step.dependOn(&libentrypoint_install.step);

    const run_step = b.step("run", "Run app");
    run_step.dependOn(&run_app.step);

    const uninstall_step = b.step("uninstall-app", "Uninstall app");
    uninstall_step.dependOn(&b.addSystemCommand(&.{ adb_path, "uninstall", pkg_name }).step);
    // zig fmt: on
}
