#if 1
#include <android/native_activity.h>
#include <android/log.h>
void onStart(ANativeActivity* activity) {
    __android_log_write(ANDROID_LOG_INFO, "MANUAL_TAG", "Look at me, ma, I'm starting!");
}

void onPause(ANativeActivity* activity) {
    __android_log_write(ANDROID_LOG_INFO, "MANUAL_TAG", "Time for a pause!");
}

void onResume(ANativeActivity* activity) {
    __android_log_write(ANDROID_LOG_INFO, "MANUAL_TAG", "GUESS WHO'S BACK");
}

__attribute__((visibility("default")))
void ANativeActivity_onCreate(ANativeActivity * activity, void* savedState, size_t savedStateSize) {
    __android_log_write(ANDROID_LOG_INFO, "MANUAL_TAG", "I am filling up the callbacks of the activity");
    activity->callbacks->onStart = onStart;
    activity->callbacks->onResume = onResume;
    activity->callbacks->onPause = onPause;
}
#else
#include <android/log.h>
#include <android/native_app_glue/android_native_app_glue.h>

extern void zig_main();

int32_t handle_input(struct android_app* app, AInputEvent* event)
{
    __android_log_write(ANDROID_LOG_INFO, "MANUAL_TAG", "Responding to a handle input!");
    return 0;
}

void handle_cmd(struct android_app* app, int32_t cmd) {
    __android_log_write(ANDROID_LOG_INFO, "MANUAL_TAG", "Responding to an event!");
    switch (cmd) {
        case APP_CMD_PAUSE:
            __android_log_write(ANDROID_LOG_INFO, "MANUAL_TAG", "Responding to a pause event!");
            break;
    }
}

void android_main(struct android_app* app) {
    __android_log_write(ANDROID_LOG_INFO, "MANUAL_TAG", "Hello world from android_main!");
    app->onAppCmd = handle_cmd;
    app->onInputEvent = handle_input;
    while (1) {
        struct android_poll_source * source;
        const int res = ALooper_pollAll(0, NULL, NULL, &source);
        switch (res) {
            case ALOOPER_POLL_CALLBACK:
                break;
        }
    }
    /* zig_main(); */
    __android_log_write(ANDROID_LOG_INFO, "MANUAL_TAG", "Goodbye cruel world from android_main!");
}
#endif
