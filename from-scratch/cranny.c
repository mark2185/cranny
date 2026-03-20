#include <android/log.h>

void zig_main();

void android_main(struct android_app* app) {
    __android_log_write(ANDROID_LOG_INFO, "MANUAL_TAG", "Hello world from android_main!");
    zig_main();
    __android_log_write(ANDROID_LOG_INFO, "MANUAL_TAG", "Goodbye cruel world from android_main!");
}
