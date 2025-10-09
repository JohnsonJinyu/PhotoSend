#include <napi/native_api.h>

// Define domain and tag BEFORE including hilog/log.h
#define LOG_DOMAIN 0x0001
#define LOG_TAG "NativeCamera"

#include <hilog/log.h>
#include <gphoto2/gphoto2.h>

// Minimal NAPI method: initialize camera and log summary
static napi_value InitCamera(napi_env env, napi_callback_info info) {
    GPContext *context = gp_context_new();

    Camera *camera = nullptr;
    int ret = gp_camera_new(&camera);
    if (ret < GP_OK || camera == nullptr) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "Failed to create camera object, ret=%{public}d", ret);
        if (context) gp_context_unref(context);
        return nullptr;
    }

    ret = gp_camera_init(camera, context);
    if (ret < GP_OK) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "Failed to init camera, ret=%{public}d", ret);
        gp_camera_free(camera);
        gp_context_unref(context);
        return nullptr;
    }

    CameraText text;
    ret = gp_camera_get_summary(camera, &text, context);
    if (ret >= GP_OK) {
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "Camera Summary: %{public}s", text.text);
    } else {
        OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, "Get summary failed, ret=%{public}d", ret);
    }

    gp_camera_exit(camera, context);
    gp_camera_free(camera);
    gp_context_unref(context);

    return nullptr;
}

// NAPI module registration
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor props[] = {
        {"initCamera", nullptr, InitCamera, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    napi_define_properties(env, exports, sizeof(props) / sizeof(props[0]), props);
    return exports;
}

NAPI_MODULE(entry, Init)