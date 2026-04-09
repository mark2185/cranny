const std = @import("std");

const app_name = "experiment";
const pkg_name = "com.experiment.apk";

const android_sdk_path = "/opt/android-sdk";
const ndk_version = "30.0.14904198";
const build_tools_version = "36.0.0";
const build_tools_path = android_sdk_path ++ "/build-tools/" ++ build_tools_version;
const adb_path = android_sdk_path ++ "/platform-tools/adb";

const libc_path = "libc-armv8.txt";
const ndk_path = android_sdk_path ++ "/ndk/" ++ ndk_version;
const llvm_path = ndk_path ++ "/toolchains/llvm/prebuilt/linux-x86_64";

const api_level = "25";
const android_jar_path = android_sdk_path ++ "/platforms/android-" ++ api_level ++ "/android.jar";

const apk_name = app_name ++ ".apk";

pub fn build(b: *std.Build) !void {
    const android_module = b.createModule(.{
        .root_source_file = b.path("experiment.zig"),
        .target = b.standardTargetOptions(.{
            .default_target = .{
                .cpu_arch = .aarch64,
                .os_tag = .linux,
                .abi = .android,
            },
        }),
        .optimize = std.builtin.OptimizeMode.ReleaseSmall,
        .link_libc = true,
        .pic = true,
        .strip = false,
    });

    android_module.addLibraryPath(std.Build.LazyPath{
        .cwd_relative = llvm_path ++ "/sysroot/usr/lib/aarch64-linux-android/36",
    });

    android_module.addIncludePath(std.Build.LazyPath{ .cwd_relative = llvm_path ++ "/sysroot/usr/include" });

    android_module.linkSystemLibrary("log", .{});
    android_module.linkSystemLibrary("android", .{});

    const libexperiment = b.addLibrary(.{
        .name = "experiment",
        .linkage = .dynamic,
        .root_module = android_module,
    });
    libexperiment.libc_file = b.path(libc_path);

    const install_options = std.Build.Step.InstallArtifact.Options{ .dest_dir = .{
        .override = .{
            .custom = "lib/arm64-v8a",
        },
    } };
    const libexperiment_install = b.addInstallArtifact(libexperiment, install_options);

    const check_build = b.addLibrary(.{
        .name = "experiment",
        .linkage = .dynamic,
        .root_module = android_module,
    });
    check_build.libc_file = b.path(libc_path);

    const check = b.step("check", "Check if experiment compiles");
    check.dependOn(&check_build.step);

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
        "-storepass", "hunter2",
        "-keypass", "hunter2",
        "-dname", "CN=example.com, OU=ID, O=Example, L=Doe, S=John, C=GB",
    });

    gen_keystore.step.dependOn(&libexperiment_install.step);

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

    package_apk.step.dependOn(&libexperiment_install.step);

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
        "--key-pass", "pass:hunter2",
        "--ks-pass", "pass:hunter2",
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
    install_step.dependOn(&libexperiment_install.step);

    const run_step = b.step("run", "Run app");
    run_step.dependOn(&run_app.step);

    const uninstall_step = b.step("uninstall-app", "Uninstall app");
    uninstall_step.dependOn(&b.addSystemCommand(&.{ adb_path, "uninstall", pkg_name }).step);
    // zig fmt: on
}
