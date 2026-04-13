APPNAME = cranny
APKFILE = ${APPNAME}.apk
APP_PKG = com.manual.apk

ANDROID_SDK_PATH = /opt/android-sdk
NDK = ${ANDROID_SDK_PATH}/ndk/25.2.9519653
BUILD_TOOLS = ${ANDROID_SDK_PATH}/build-tools/36.0.0

# targeting xiaomi redmi s3
API_LEVEL = 25
ANDROID_JAR = ${ANDROID_SDK_PATH}/platforms/android-${API_LEVEL}/android.jar
BUILD_DIR = build

AAPT = ${BUILD_TOOLS}/aapt
ZIPALIGN = ${BUILD_TOOLS}/zipalign

all: ${BUILD_DIR}/cranny.apk

.PHONY: all install run uninstall

clean:
	rm -rf ${BUILD_DIR}
	@#rm -f ${KEYSTORE_FILE}

run: install
	adb shell am start ${APP_PKG}/android.app.NativeActivity

install: ${BUILD_DIR}/${APKFILE}
	adb install -r ${BUILD_DIR}/cranny.apk

uninstall:
	adb uninstall ${APP_PKG}

CC = ${NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/armv7a-linux-androideabi30-clang
CFLAGS += -ffunction-sections -Os -fdata-sections -Wall -fvisibility=hidden -fPIC -m32
LDFLAGS += -Wl,--gc-sections -Wl,-Map=${BUILD_DIR}/output.map -shared -landroid -llog

${BUILD_DIR}/lib/armeabi-v7a/lib${APPNAME}.so: cranny.zig
	zig build -p ${BUILD_DIR} -freference-trace=99

debug: install
	adb push --sync ${NDK}/toolchains/llvm/prebuilt/linux-x86_64/lib64/clang/14.0.7/lib/linux/aarch64/lldb-server /sdcard/
	adb shell run-as ${APP_PKG} cp /sdcard/lldb-server .
	adb forward tcp:15000 tcp:15000
	adb forward tcp:16000 tcp:16000
	adb shell run-as ${APP_PKG} ./lldb-server platform --listen "*:15000" --gdbserver-port 16000

KEYSTORE_FILE = my-key.keystore
DNAME = "CN=example.com, OU=ID, O=Example, L=Doe, S=John, C=GB"
${KEYSTORE_FILE}:
	mkdir -p build
	keytool -genkey -v -keystore ${KEYSTORE_FILE} -alias mykey -keyalg RSA -keysize 2048 -validity 10000 -storepass password -keypass password -dname ${DNAME}

${BUILD_DIR}/${APKFILE}: AndroidManifest.xml ${KEYSTORE_FILE} ${BUILD_DIR}/lib/armeabi-v7a/lib${APPNAME}.so
	mkdir -p ${BUILD_DIR}

	@# -v = verbose
	@# -I = add an existing package to base include set
	@# -M = path to the AndroidManifest.xml
	@# -f = force overwriting files
	@# -F = output file
	${AAPT} package -v -I ${ANDROID_JAR} -M AndroidManifest.xml -f -F ${BUILD_DIR}/temp.apk

	@# cd ${BUILD_DIR} && zip temp.apk -r build -D lib/*/*.so
	zip temp.apk -r build -D lib/*/*.so

	@# zipalign gets angry if the apk already exists
	@rm -f ${BUILD_DIR}/${APKFILE}
	${ZIPALIGN} -v 4 ${BUILD_DIR}/temp.apk ${BUILD_DIR}/${APKFILE}

	${BUILD_TOOLS}/apksigner sign --key-pass pass:password --ks-pass pass:password --ks ${KEYSTORE_FILE} ${BUILD_DIR}/${APKFILE}
