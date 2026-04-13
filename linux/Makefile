APKFILE = experiment.apk

ANDROID_SDK_PATH = /opt/android-sdk
BUILD_TOOLS = ${ANDROID_SDK_PATH}/build-tools/36.0.0

API_LEVEL = 25
ANDROID_JAR = ${ANDROID_SDK_PATH}/platforms/android-${API_LEVEL}/android.jar
BUILD_DIR = build

AAPT = ${BUILD_TOOLS}/aapt
ZIPALIGN = ${BUILD_TOOLS}/zipalign

KEYSTORE_FILE = my-key.keystore
DNAME = "CN=example.com, OU=ID, O=Example, L=Doe, S=John, C=GB"
${KEYSTORE_FILE}:
	keytool -genkey -v -keystore ${KEYSTORE_FILE} -alias mykey -keyalg RSA -keysize 2048 -validity 10000 -storepass hunter2 -keypass hunter2 -dname ${DNAME}

clean:
	@rm -rf ${BUILD_DIR}

uninstall:
	adb uninstall com.experiment.apk

install: ${BUILD_DIR}/${APKFILE}
	adb install -r $<

run: ${BUILD_DIR}/${APKFILE} install
	adb shell am start com.experiment.apk/android.app.NativeActivity

LLVM = /opt/android-sdk/ndk/30.0.14904198/toolchains/llvm/prebuilt/linux-x86_64
NDK_SYSROOT = ${LLVM}/sysroot

debug: install
	adb push --sync ${LLVM}/lib/clang/21/lib/linux/aarch64/lldb-server /data/local/tmp
	adb shell run-as com.experiment.apk cp /data/local/tmp/lldb-server .
	adb shell run-as com.experiment.apk chmod a+x ./lldb-server
	adb forward tcp:15000 tcp:15000
	adb forward tcp:16000 tcp:16000
	adb shell am start -D com.experiment.apk/android.app.NativeActivity
	adb shell run-as com.experiment.apk ./lldb-server platform --listen "*:15000" --gdbserver-port 16000

ZIG = /home/mark/workspace/gits/zig/build-latest/stage3/bin/zig

rpi: experiment.zig
	@mkdir -p ${BUILD_DIR}
	${ZIG} build-exe experiment.zig -target aarch64-linux-gnu -O Debug -fllvm -femit-bin=${BUILD_DIR}/armv8-server.exe

desktop: experiment.zig
	@mkdir -p ${BUILD_DIR}
	${ZIG} build-exe experiment.zig -O Debug -fllvm -femit-bin=${BUILD_DIR}/server.exe
	@# ${BUILD_DIR}/server.exe

${BUILD_DIR}/${APKFILE}: AndroidManifest.xml ${KEYSTORE_FILE} experiment.zig
	@mkdir -p ${BUILD_DIR}/lib/arm64-v8a
	
	${ZIG} build-lib experiment.zig \
		-dynamic \
		-target aarch64-linux-android \
		--library-directory ${NDK_SYSROOT}/usr/lib/aarch64-linux-android/36 \
		-I ${NDK_SYSROOT}/usr/include/ \
		--libc libc-armv8.txt \
		-llog -lc \
		-O Debug \
		-fllvm  \
		-freference-trace=6 \
		-femit-bin=${BUILD_DIR}/lib/arm64-v8a/libexperiment.so
	
	@# -v = verbose
	@# -I = add an existing package to base include set
	@# -M = path to the AndroidManifest.xml
	@# -f = force overwriting files
	@# -F = output file
	${AAPT} package -v -I ${ANDROID_JAR} -M AndroidManifest.xml -f -F ${BUILD_DIR}/temp.apk
	
	@# cd ${BUILD_DIR} && zip temp.apk -r build -D lib/*/*.so
	cd build && zip temp.apk -D lib/arm64-v8a/libexperiment.so
	
	@# zipalign gets angry if the apk already exists
	@rm -f ${BUILD_DIR}/${APKFILE}
	${ZIPALIGN} -v 4 ${BUILD_DIR}/temp.apk ${BUILD_DIR}/${APKFILE}
	
	${BUILD_TOOLS}/apksigner sign --key-pass pass:hunter2 --ks-pass pass:hunter2 --ks ${KEYSTORE_FILE} ${BUILD_DIR}/${APKFILE}
