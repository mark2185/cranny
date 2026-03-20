APPNAME = cranny
APKFILE = ${APPNAME}.apk

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
	adb shell am start com.manual.apk/android.app.NativeActivity

install: ${BUILD_DIR}/${APKFILE}
	adb install -r ${BUILD_DIR}/cranny.apk

uninstall:
	adb uninstall com.manual.apk

CC = ${NDK}/toolchains/llvm/prebuilt/linux-x86_64/bin/armv7a-linux-androideabi30-clang
CFLAGS += -ffunction-sections -Os -fdata-sections -Wall -fvisibility=hidden -fPIC -m32 -landroid -llog
LDFLAGS += -Wl,--gc-sections -Wl,-Map=${BUILD_DIR}/output.map -shared

# the library *has* to be in lib/{arch}/ in the APK file
# otherwise it fails to install with an "INSTALL_FAILED_NO_MATCHING_ABIS: Failed to extract native libraries, res=-113]" error
${BUILD_DIR}/lib/armeabi-v7a/lib${APPNAME}.so: cranny.c
	mkdir -p ${BUILD_DIR}/lib/armeabi-v7a
	$(CC) $(CFLAGS) $^ -o ${BUILD_DIR}/lib/armeabi-v7a/lib${APPNAME}.so \
		-L${NDK}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/arm-linux-androideabi/${API_LEVEL} \
		${NDK}/sources/android/native_app_glue/android_native_app_glue.c \
		${LDFLAGS}

KEYSTORE_FILE = my-key.keystore
DNAME = "CN=example.com, OU=ID, O=Example, L=Doe, S=John, C=GB"
${KEYSTORE_FILE}:
	mkdir -p build
	keytool -genkey -v -keystore ${KEYSTORE_FILE} -alias mykey -keyalg RSA -keysize 2048 -validity 10000 -storepass password -keypass password -dname ${DNAME}

${BUILD_DIR}/${APKFILE}: ${BUILD_DIR}/lib/armeabi-v7a/lib${APPNAME}.so AndroidManifest.xml ${KEYSTORE_FILE}
	mkdir -p ${BUILD_DIR}
	
	@# -v = verbose
	@# -I = add an existing package to base include set
	@# -M = path to the AndroidManifest.xml
	@# -f = force overwriting files
	@# -F = output file
	${AAPT} package -v -I ${ANDROID_JAR} -M AndroidManifest.xml -f -F ${BUILD_DIR}/temp.apk 
	
	cd ${BUILD_DIR} && zip temp.apk -D lib/armeabi-v7a/lib${APPNAME}.so
	
	@# zipalign gets angry if the apk already exists
	@rm -f ${BUILD_DIR}/${APKFILE}
	${ZIPALIGN} -v 4 ${BUILD_DIR}/temp.apk ${BUILD_DIR}/${APKFILE}
	
	${BUILD_TOOLS}/apksigner sign --key-pass pass:password --ks-pass pass:password --ks ${KEYSTORE_FILE} ${BUILD_DIR}/${APKFILE}
