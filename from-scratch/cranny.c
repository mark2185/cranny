#include <android/log.h>

void android_main(struct android_app* app) {
    __android_log_write(ANDROID_LOG_INFO, "MANUAL_TAG", "Hello world!");
}
