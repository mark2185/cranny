const std = @import("std");

const pkg_name = "com.cranny.zig";

const android_sdk_path = "/opt/android-sdk";
const ndk_version = "16.1.4479499";
const build_tools_version = "36.0.0";
const build_tools_path = android_sdk_path ++ "/build-tools/" ++ build_tools_version;
const adb_path = android_sdk_path ++ "/platform-tools/adb";

const libc_path = "src/libc_android16.txt";
const ndk_path = android_sdk_path ++ "/ndk/" ++ ndk_version;

const api_level = "19";
const android_jar_path = android_sdk_path ++ "/platforms/android-" ++ api_level ++ "/android.jar";

const apk_name = "cranny.apk";

pub fn build(b: *std.Build) !void {
    const android_module = b.createModule(.{
        .root_source_file = b.path("src/cranny.zig"),
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .arm,
            .os_tag = .linux,
            .abi = .androideabi,
            .android_api_level = 19,
        }),
        .optimize = .ReleaseSmall,
        .link_libc = true,
        .pic = true,
        .strip = false,
    });

    android_module.addLibraryPath(std.Build.LazyPath{
        .cwd_relative = std.fmt.comptimePrint("{s}/platforms/android-{s}/arch-arm/usr/lib", .{ ndk_path, api_level }),
    });

    android_module.addIncludePath(std.Build.LazyPath{ .cwd_relative = ndk_path ++ "/sysroot/usr/include" });

    android_module.linkSystemLibrary("log", .{});
    android_module.linkSystemLibrary("android", .{});

    const libcranny = b.addLibrary(.{
        .name = "cranny",
        .linkage = .dynamic,
        .root_module = android_module,
    });
    libcranny.libc_file = b.path(libc_path);

    const install_options = std.Build.Step.InstallArtifact.Options{ .dest_dir = .{ .override = .{ .custom = "lib/armeabi-v7a" } } };
    const libcranny_install = b.addInstallArtifact(libcranny, install_options);

    const libcheck = libcranny;
    const check = b.step("check", "Step for zls build-on-save feature");
    check.dependOn(&libcheck.step);

    // entrypoint is used for manual dlopen of libcranny to get the error message
    const entrypoint_module = b.createModule(.{
        .root_source_file = b.path("src/entrypoint.zig"),
        .target = android_module.resolved_target,
        .optimize = .ReleaseSmall,
        .link_libc = true,
        .pic = true,
        .strip = false,
    });

    entrypoint_module.addLibraryPath(std.Build.LazyPath{
        .cwd_relative = std.fmt.comptimePrint("{s}/platforms/android-{s}/arch-arm/usr/lib", .{ ndk_path, api_level }),
    });

    entrypoint_module.addIncludePath(std.Build.LazyPath{ .cwd_relative = ndk_path ++ "/sysroot/usr/include" });

    entrypoint_module.linkSystemLibrary("log", .{});
    entrypoint_module.linkSystemLibrary("android", .{});

    const libentrypoint = b.addLibrary(.{
        .name = "entrypoint",
        .linkage = .dynamic,
        .root_module = entrypoint_module,
        // .use_llvm = true,
    });
    libentrypoint.libc_file = b.path(libc_path);
    const libentrypoint_install = b.addInstallArtifact(libentrypoint, install_options);

    const client_install = b.addExecutable(.{
        .name = "client",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/client.zig"),
            .target = b.resolveTargetQuery(.{ .cpu_arch = .x86_64, .os_tag = .linux }),
            .optimize = .Debug,
            .link_libc = true,
        }),
        .use_llvm = true,
    });
    b.installArtifact(client_install);

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
        "-S", "res/",
        "-F", "zig-out/temp.apk", // output file
    });

    package_apk.step.dependOn(&libcranny_install.step);
    package_apk.step.dependOn(&libentrypoint_install.step);

    // -=-=-=- Zipping -=-=-=-
    const zip_libs = b.addSystemCommand(&.{
        "sh", "-c",
        // has to be this way to have the correct filepaths, i.e. lib/<arch>/*.so
        "cd zig-out && " ++ build_tools_path ++ "/aapt add temp.apk lib/armeabi-v7a/lib*.so",
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

    // generate the keystore only if it doesn't exist
    // {
        // var threaded = std.Io.Threaded.init_single_threaded;
        // _ = std.Io.Dir.cwd().openFile( threaded.io(), keystore, .{}) catch {
            // sign_apk.step.dependOn(&gen_keystore.step);
        // };
    // }

    const install_apk = b.addSystemCommand(&.{ adb_path, "install", "-r", "zig-out/" ++ apk_name });
    install_apk.step.dependOn(&sign_apk.step);

    const run_app = b.addSystemCommand(&.{
        adb_path, "shell", "am", "start", pkg_name ++ "/android.app.NativeActivity",
    });
    run_app.step.dependOn(&install_apk.step);

    const install_step = b.getInstallStep();
    install_step.dependOn(&libcranny_install.step);
    install_step.dependOn(&libentrypoint_install.step);
    install_step.dependOn(&sign_apk.step);

    const run_step = b.step("run", "Run app");
    run_step.dependOn(&client_install.step);
    run_step.dependOn(&run_app.step);

    const uninstall_step = b.step("uninstall-app", "Uninstall app");
    uninstall_step.dependOn(&b.addSystemCommand(&.{ adb_path, "uninstall", pkg_name }).step);
    // zig fmt: on
}
