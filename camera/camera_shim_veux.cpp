/*
 * Copyright (C) 2026 The LineageOS Project / Antigravity / acerhizm
 * SPDX-License-Identifier: Apache-2.0
 *
 * Xiaomi Veux (108MP Samsung S5KHM2) Complete Camera HAL Shim
 * 
 * Features included:
 * 1. Safe Qualcomm Real HAL Loader:
 *    - Loads real Qualcomm stock HAL from /vendor/lib64/hw/camera.qcom.real.so
 *      within the vendor linker namespace with zero CFI mismatch.
 * 2. Dynamic Xiaomi Vendor Tag Descriptor Overlay:
 *    - Injects com.xiaomi.sessionparams.clientName (0x808d0000 / persist.vendor.cam.cname_tag)
 *    - Injects com.xiaomi.sessionparams.thirdPartyYUVSnapshot (0x808d0001 / persist.vendor.cam.3pyuv_tag)
 *      into vendor_tag_ops.
 * 3. Unconditional Stream Dataspace Sanitization:
 *    - Remaps all <=1080p preview/YUV streams (IMPLEMENTATION_DEFINED,
 *      YCbCr_420_888, YCrCb_420_SP) dataspace from 0x08c20000 (JFIF) to
 *      HAL_DATASPACE_UNKNOWN (0x0) to completely avoid Qualcomm CamX 108MP
 *      ZSLPreviewRaw_LT1080p_PLTV buffer crash during third-party video calling.
 * 4. Dynamic Session Parameters Injection:
 *    - Injects clientName ("com.whatsapp", etc.) and thirdPartyYUVSnapshot=1 into
 *      stream_list->session_parameters during configure_streams().
 * 5. Dual Property Sync & Auto Cleanup:
 *    - Automatically sets persist.vendor.camera.pkgname and persist.vendor.camera.clientname
 *      on session start and clears them on camera device close.
 * 6. Privileged Camera (Leica MiuiCamera 5.0 / GCam) Protection:
 *    - Whitelists com.android.camera, org.codeaurora.snapcam, com.shamim.cam,
 *      com.google.android.GoogleCamera, com.xiaomi.camera so native 108MP RAW/Pro
 *      modes remain 100% untouched.
 * 7. Full camera_module_t API 2.4/2.5 Forwarding:
 *    - get_physical_camera_info, notify_device_state_change, set_torch_mode,
 *      open_legacy, init forwarding.
 */

#define LOG_TAG "VeuxCameraShim"

#include <dlfcn.h>
#include <errno.h>
#include <inttypes.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <vector>
#include <string>

#include <log/log.h>
#include <cutils/properties.h>
#include <hardware/camera3.h>
#include <hardware/camera_common.h>
#include <system/camera_metadata.h>
#include <system/graphics.h>

#define REAL_HAL_PRIMARY_PATH "/vendor/lib64/hw/camera.qcom.real.so"

// Candidate fallback paths for real Qualcomm HAL binary
static const char* kCandidateRealHalPaths[] = {
    REAL_HAL_PRIMARY_PATH,
    "/system/vendor/lib64/hw/camera.qcom.real.so",
    "/odm/lib64/hw/camera.qcom.real.so",
    "/vendor/lib64/camera/com.qti.sensor.imx318.so",
    "/vendor/lib64/camera/com.qti.sensor.imx334.so",
};

// Xiaomi custom vendor tag section and names
#define XIAOMI_SECTION_SESSIONPARAMS    "com.xiaomi.sessionparams"
#define XIAOMI_TAG_NAME_CLIENT_NAME     "clientName"
#define XIAOMI_TAG_NAME_THIRD_PARTY_YUV "thirdPartyYUVSnapshot"

static void* g_real_hal_handle = nullptr;
static camera_module_t* g_real_camera_module = nullptr;
static pthread_mutex_t g_init_lock = PTHREAD_MUTEX_INITIALIZER;

// Vendor tag ops wrappers
static vendor_tag_ops_t g_shim_vendor_tag_ops;
static vendor_tag_ops_t g_real_vendor_tag_ops;
static bool g_vendor_tag_ops_hooked = false;

static uint32_t get_client_name_tag() {
    char prop[PROP_VALUE_MAX] = {};
    if (property_get("persist.vendor.cam.cname_tag", prop, "") > 0) {
        uint32_t tag = static_cast<uint32_t>(strtoul(prop, nullptr, 0));
        if (tag >= CAMERA_METADATA_VENDOR_TAG_BOUNDARY) return tag;
    }
    return 0x808d0000;
}

static uint32_t get_third_party_yuv_tag() {
    char prop[PROP_VALUE_MAX] = {};
    if (property_get("persist.vendor.cam.3pyuv_tag", prop, "") > 0) {
        uint32_t tag = static_cast<uint32_t>(strtoul(prop, nullptr, 0));
        if (tag >= CAMERA_METADATA_VENDOR_TAG_BOUNDARY) return tag;
    }
    return 0x808d0001;
}

// Function pointer types for original camera3_device_ops
typedef int (*orig_configure_streams_fn)(const struct camera3_device *, camera3_stream_configuration_t *);
typedef int (*orig_close_fn)(hw_device_t*);

#define MAX_CONCURRENT_CAMERAS 8

struct CameraSessionContext {
    const camera3_device_t* dev;
    orig_configure_streams_fn orig_configure_streams;
    orig_close_fn orig_close;
    camera3_device_ops_t wrapped_ops;
    int camera_id;
    camera_metadata_t* injected_session_params;
    bool in_use;
};

static CameraSessionContext g_sessions[MAX_CONCURRENT_CAMERAS];
static pthread_mutex_t g_sessions_lock = PTHREAD_MUTEX_INITIALIZER;

// ============================================================================
// 1. Privileged Client & Caller Detection
// ============================================================================
static std::string get_current_client_package(const camera_metadata_t* session_params) {
    char prop[PROP_VALUE_MAX] = {};
    if (property_get("persist.vendor.camera.pkgname", prop, "") > 0 && strlen(prop) > 0) {
        return std::string(prop);
    }
    if (property_get("persist.vendor.camera.clientname", prop, "") > 0 && strlen(prop) > 0) {
        return std::string(prop);
    }
    if (property_get("sys.camera.client.pkgname", prop, "") > 0 && strlen(prop) > 0) {
        return std::string(prop);
    }

    if (session_params) {
        camera_metadata_ro_entry_t entry;
        if (find_camera_metadata_ro_entry(session_params, get_client_name_tag(), &entry) == 0) {
            if (entry.count > 0 && entry.data.u8) {
                return std::string((const char*)entry.data.u8);
            }
        }
    }

    return "";
}

static bool is_privileged_package(const std::string& pkg) {
    if (pkg.empty()) return false;
    char priv_list[PROP_VALUE_MAX] = {};
    property_get("persist.vendor.camera.privapp.list", priv_list,
                 "com.android.camera,org.codeaurora.snapcam,com.shamim.cam,com.google.android.GoogleCamera,com.xiaomi.camera");
    
    char* list_copy = strdup(priv_list);
    if (!list_copy) return false;

    char* saveptr = nullptr;
    char* token = strtok_r(list_copy, ",", &saveptr);
    bool privileged = false;
    while (token != nullptr) {
        if (pkg == token) {
            privileged = true;
            break;
        }
        token = strtok_r(nullptr, ",", &saveptr);
    }
    free(list_copy);
    return privileged;
}

// ============================================================================
// 2. Dynamic Vendor Tag Descriptor Overlay
// ============================================================================
static int shim_vt_get_tag_count(const vendor_tag_ops_t *v) {
    (void)v;
    int orig_count = 0;
    if (g_real_vendor_tag_ops.get_tag_count) {
        orig_count = g_real_vendor_tag_ops.get_tag_count(&g_real_vendor_tag_ops);
    }
    return orig_count + 2;
}

static void shim_vt_get_all_tags(const vendor_tag_ops_t *v, uint32_t *tag_array) {
    (void)v;
    int orig_count = 0;
    if (g_real_vendor_tag_ops.get_tag_count) {
        orig_count = g_real_vendor_tag_ops.get_tag_count(&g_real_vendor_tag_ops);
    }
    if (g_real_vendor_tag_ops.get_all_tags && tag_array) {
        g_real_vendor_tag_ops.get_all_tags(&g_real_vendor_tag_ops, tag_array);
    }
    if (tag_array) {
        tag_array[orig_count] = get_client_name_tag();
        tag_array[orig_count + 1] = get_third_party_yuv_tag();
    }
}

static const char *shim_vt_get_section_name(const vendor_tag_ops_t *v, uint32_t tag) {
    (void)v;
    if (tag == get_client_name_tag() || tag == get_third_party_yuv_tag()) {
        return XIAOMI_SECTION_SESSIONPARAMS;
    }
    if (g_real_vendor_tag_ops.get_section_name) {
        return g_real_vendor_tag_ops.get_section_name(&g_real_vendor_tag_ops, tag);
    }
    return nullptr;
}

static const char *shim_vt_get_tag_name(const vendor_tag_ops_t *v, uint32_t tag) {
    (void)v;
    if (tag == get_client_name_tag()) {
        return XIAOMI_TAG_NAME_CLIENT_NAME;
    }
    if (tag == get_third_party_yuv_tag()) {
        return XIAOMI_TAG_NAME_THIRD_PARTY_YUV;
    }
    if (g_real_vendor_tag_ops.get_tag_name) {
        return g_real_vendor_tag_ops.get_tag_name(&g_real_vendor_tag_ops, tag);
    }
    return nullptr;
}

static int shim_vt_get_tag_type(const vendor_tag_ops_t *v, uint32_t tag) {
    (void)v;
    if (tag == get_client_name_tag() || tag == get_third_party_yuv_tag()) {
        return TYPE_BYTE;
    }
    if (g_real_vendor_tag_ops.get_tag_type) {
        return g_real_vendor_tag_ops.get_tag_type(&g_real_vendor_tag_ops, tag);
    }
    return -1;
}

// Forward declaration
static bool load_real_hal();


// ============================================================================
// 2.5 Qualcomm CamX ChiEntry & ABI Forwarding
// ============================================================================

// com.qti.chi.override.so and libcamerapostproc.so open /vendor/lib64/hw/camera.qcom.so
// via dlopen and look up "ChiEntry" via dlsym to populate g_chiContextOps (CamX function table).
// We forward ChiEntry, CamxMemAlloc, and CamxMemRelease to camera.qcom.real.so so all 24 ops
// in g_chiContextOps are populated with authentic pointers by Qualcomm's CamX core.
extern "C" __attribute__((visibility("default")))
void ChiEntry(void* ops) {
    if (!load_real_hal()) {
        ALOGE("%s: Failed to load real camera HAL!", __FUNCTION__);
        return;
    }
    typedef void (*ChiEntryFunc)(void*);
    static ChiEntryFunc real_ChiEntry = nullptr;
    if (!real_ChiEntry && g_real_hal_handle) {
        real_ChiEntry = (ChiEntryFunc)dlsym(g_real_hal_handle, "ChiEntry");
    }
    if (real_ChiEntry) {
        ALOGI("%s: Forwarding ChiEntry(%p) to real camera HAL (%p)...", __FUNCTION__, ops, real_ChiEntry);
        real_ChiEntry(ops);
        ALOGI("%s: Real ChiEntry completed successfully!", __FUNCTION__);
    } else {
        ALOGE("%s: ChiEntry symbol not found in real camera HAL: %s", __FUNCTION__, dlerror());
    }
}

extern "C" __attribute__((visibility("default")))
void* CamxMemAlloc(size_t size) {
    if (!load_real_hal()) return malloc(size);
    typedef void* (*CamxMemAllocFunc)(size_t);
    static CamxMemAllocFunc real_alloc = nullptr;
    if (!real_alloc && g_real_hal_handle) {
        real_alloc = (CamxMemAllocFunc)dlsym(g_real_hal_handle, "CamxMemAlloc");
    }
    return real_alloc ? real_alloc(size) : malloc(size);
}

extern "C" __attribute__((visibility("default")))
void CamxMemRelease(void* ptr) {
    if (!load_real_hal()) {
        free(ptr);
        return;
    }
    typedef void (*CamxMemReleaseFunc)(void*);
    static CamxMemReleaseFunc real_release = nullptr;
    if (!real_release && g_real_hal_handle) {
        real_release = (CamxMemReleaseFunc)dlsym(g_real_hal_handle, "CamxMemRelease");
    }
    if (real_release) {
        real_release(ptr);
    } else {
        free(ptr);
    }
}

// ============================================================================
// 3. Safe Real HAL Loader
// ============================================================================
static bool load_real_hal() {
    pthread_mutex_lock(&g_init_lock);
    if (g_real_camera_module != nullptr) {
        pthread_mutex_unlock(&g_init_lock);
        return true;
    }

    const size_t num_candidates = sizeof(kCandidateRealHalPaths) / sizeof(kCandidateRealHalPaths[0]);
    for (size_t i = 0; i < num_candidates; i++) {
        const char* path = kCandidateRealHalPaths[i];
        if (access(path, R_OK) == 0) {
            ALOGI("%s: Found candidate real HAL at '%s', loading via dlopen...", __FUNCTION__, path);
            g_real_hal_handle = dlopen(path, RTLD_NOW | RTLD_GLOBAL);
            if (g_real_hal_handle) {
                g_real_camera_module = (camera_module_t*)dlsym(g_real_hal_handle, HAL_MODULE_INFO_SYM_AS_STR);
                if (g_real_camera_module) {
                    ALOGI("%s: Successfully loaded real camera HAL from '%s' (HMI found)", __FUNCTION__, path);
                    pthread_mutex_unlock(&g_init_lock);
                    return true;
                } else {
                    ALOGE("%s: Loaded '%s' but symbol '%s' not found: %s",
                          __FUNCTION__, path, HAL_MODULE_INFO_SYM_AS_STR, dlerror());
                    dlclose(g_real_hal_handle);
                    g_real_hal_handle = nullptr;
                }
            } else {
                ALOGE("%s: dlopen('%s') failed: %s", __FUNCTION__, path, dlerror());
            }
        }
    }

    ALOGE("%s: FATAL: Unable to load real camera HAL from '%s'!", __FUNCTION__, REAL_HAL_PRIMARY_PATH);
    pthread_mutex_unlock(&g_init_lock);
    return false;
}

// ============================================================================
// 4. Session Parameters Injection & Stream Sanitization
// ============================================================================
static void inject_session_parameters(CameraSessionContext* ctx, camera3_stream_configuration_t *stream_list, const std::string& pkg) {
    if (!ctx || !stream_list) return;

    if (ctx->injected_session_params) {
        free_camera_metadata(ctx->injected_session_params);
        ctx->injected_session_params = nullptr;
    }

    camera_metadata_t* current_meta = (camera_metadata_t*)stream_list->session_parameters;
    size_t current_entry_count = current_meta ? get_camera_metadata_entry_count(current_meta) : 0;
    size_t current_data_count = current_meta ? get_camera_metadata_data_count(current_meta) : 0;

    camera_metadata_t* new_meta = allocate_camera_metadata(current_entry_count + 8, current_data_count + 256);
    if (!new_meta) {
        ALOGE("%s: Failed to allocate metadata buffer for session params injection!", __FUNCTION__);
        return;
    }

    if (current_meta) {
        append_camera_metadata(new_meta, current_meta);
    }

    // 1. Inject thirdPartyYUVSnapshot = 1
    const uint8_t third_party_snap = 1;
    uint32_t yuv_tag = get_third_party_yuv_tag();
    camera_metadata_entry_t entry;
    if (find_camera_metadata_entry(new_meta, yuv_tag, &entry) == 0) {
        update_camera_metadata_entry(new_meta, entry.index, &third_party_snap, 1, nullptr);
    } else {
        add_camera_metadata_entry(new_meta, yuv_tag, &third_party_snap, 1);
    }

    // 2. Inject clientName = pkg
    const std::string effective_pkg = pkg.empty() ? "com.whatsapp" : pkg;
    std::vector<uint8_t> pkg_bytes(effective_pkg.begin(), effective_pkg.end());
    pkg_bytes.push_back('\0');

    uint32_t cname_tag = get_client_name_tag();
    if (find_camera_metadata_entry(new_meta, cname_tag, &entry) == 0) {
        update_camera_metadata_entry(new_meta, entry.index, pkg_bytes.data(), pkg_bytes.size(), nullptr);
    } else {
        add_camera_metadata_entry(new_meta, cname_tag, pkg_bytes.data(), pkg_bytes.size());
    }

    ctx->injected_session_params = new_meta;
    stream_list->session_parameters = new_meta;
}

static int shim_configure_streams(const struct camera3_device *dev, camera3_stream_configuration_t *stream_list) {
    if (!dev || !stream_list) {
        return -EINVAL;
    }

    pthread_mutex_lock(&g_sessions_lock);
    CameraSessionContext* ctx = nullptr;
    for (int i = 0; i < MAX_CONCURRENT_CAMERAS; i++) {
        if (g_sessions[i].in_use && g_sessions[i].dev == dev) {
            ctx = &g_sessions[i];
            break;
        }
    }
    pthread_mutex_unlock(&g_sessions_lock);

    if (!ctx || !ctx->orig_configure_streams) {
        ALOGE("%s: Device %p not found in active sessions!", __FUNCTION__, dev);
        return -EINVAL;
    }

    std::string current_pkg = get_current_client_package((const camera_metadata_t*)stream_list->session_parameters);
    bool privileged = is_privileged_package(current_pkg);

    if (!privileged) {
        const std::string effective_pkg = current_pkg.empty() ? "com.whatsapp" : current_pkg;
        property_set("persist.vendor.camera.pkgname", effective_pkg.c_str());
        property_set("persist.vendor.camera.clientname", effective_pkg.c_str());
        property_set("persist.vendor.cam.strip3pjfif", "true");

        // 1. Unconditional Stream Dataspace Sanitization (All <= 1080p preview streams -> HAL_DATASPACE_UNKNOWN)
        for (uint32_t i = 0; i < stream_list->num_streams; i++) {
            camera3_stream_t* s = stream_list->streams[i];
            if (!s) continue;

            if (s->width <= 1920 && s->height <= 1080) {
                if (s->format == HAL_PIXEL_FORMAT_YCbCr_420_888 ||
                    s->format == HAL_PIXEL_FORMAT_YCrCb_420_SP ||
                    s->format == HAL_PIXEL_FORMAT_IMPLEMENTATION_DEFINED) {
                    
                    ALOGI("%s: [Camera %d] Sanitizing preview stream (fmt %#x %ux%u) dataspace "
                          "0x%x -> UNKNOWN (0x0) for package '%s'",
                          __FUNCTION__, ctx->camera_id, s->format, s->width, s->height,
                          s->data_space, effective_pkg.c_str());
                    s->data_space = HAL_DATASPACE_UNKNOWN;
                }
            }
        }

        // 2. Inject Xiaomi session parameters (clientName + thirdPartyYUVSnapshot)
        inject_session_parameters(ctx, stream_list, effective_pkg);
    } else {
        ALOGI("%s: [Camera %d] Privileged client '%s' detected, retaining native 108MP configuration",
              __FUNCTION__, ctx->camera_id, current_pkg.c_str());
    }

    return ctx->orig_configure_streams(dev, stream_list);
}

// Wrapper for hw_device_t -> close
static int shim_device_close(hw_device_t* dev) {
    if (!dev) return 0;
    camera3_device_t* cam3_dev = (camera3_device_t*)dev;

    pthread_mutex_lock(&g_sessions_lock);
    CameraSessionContext* ctx = nullptr;
    for (int i = 0; i < MAX_CONCURRENT_CAMERAS; i++) {
        if (g_sessions[i].in_use && g_sessions[i].dev == cam3_dev) {
            ctx = &g_sessions[i];
            break;
        }
    }

    orig_close_fn orig_close = nullptr;
    if (ctx) {
        orig_close = ctx->orig_close;
        if (ctx->injected_session_params) {
            free_camera_metadata(ctx->injected_session_params);
            ctx->injected_session_params = nullptr;
        }
        ctx->dev = nullptr;
        ctx->orig_configure_streams = nullptr;
        ctx->orig_close = nullptr;
        ctx->in_use = false;
        ALOGI("%s: Session closed and cleaned up for device %p", __FUNCTION__, cam3_dev);
    }
    pthread_mutex_unlock(&g_sessions_lock);

    // Reset package name property on camera closing
    property_set("persist.vendor.camera.pkgname", "");
    property_set("persist.vendor.camera.clientname", "");

    if (orig_close) {
        return orig_close(dev);
    }
    return 0;
}

// ============================================================================
// 5. Camera Module Open Hook
// ============================================================================
static int shim_module_open(const hw_module_t* module, const char* id, hw_device_t** device) {
    (void)module;
    if (!load_real_hal()) {
        return -ENODEV;
    }

    hw_device_t* real_device = nullptr;
    int res = g_real_camera_module->common.methods->open((const hw_module_t*)g_real_camera_module, id, &real_device);
    if (res != 0 || !real_device) {
        ALOGE("%s: Real camera HAL open failed for camera '%s' with error %d", __FUNCTION__, id ? id : "unknown", res);
        return res;
    }

    camera3_device_t* real_cam3 = (camera3_device_t*)real_device;
    if (real_cam3->common.version < CAMERA_DEVICE_API_VERSION_3_0) {
        *device = real_device;
        return 0;
    }

    pthread_mutex_lock(&g_sessions_lock);
    CameraSessionContext* ctx = nullptr;
    // Check if slot already exists for real_cam3
    for (int i = 0; i < MAX_CONCURRENT_CAMERAS; i++) {
        if (g_sessions[i].in_use && g_sessions[i].dev == real_cam3) {
            ctx = &g_sessions[i];
            break;
        }
    }
    if (!ctx) {
        for (int i = 0; i < MAX_CONCURRENT_CAMERAS; i++) {
            if (!g_sessions[i].in_use) {
                ctx = &g_sessions[i];
                break;
            }
        }
    }
    if (!ctx) {
        ALOGE("%s: Too many concurrent camera sessions! Fallback to direct device", __FUNCTION__);
        pthread_mutex_unlock(&g_sessions_lock);
        *device = real_device;
        return 0;
    }

    ctx->dev = real_cam3;
    ctx->camera_id = id ? atoi(id) : 0;
    ctx->orig_close = real_cam3->common.close;
    ctx->orig_configure_streams = real_cam3->ops->configure_streams;
    if (ctx->injected_session_params) {
        free_camera_metadata(ctx->injected_session_params);
        ctx->injected_session_params = nullptr;
    }
    ctx->in_use = true;

    // Copy original ops table into our wrapped_ops
    memcpy(&ctx->wrapped_ops, real_cam3->ops, sizeof(camera3_device_ops_t));
    ctx->wrapped_ops.configure_streams = shim_configure_streams;

    // Hook ops and close, but CRITICALLY: NEVER TOUCH real_cam3->priv!
    // Qualcomm CamX stores its internal C++ object (with vtable verified by Clang CFI)
    // in real_cam3->priv. Overwriting it causes SEGV_ACCERR in __cfi_slowpath!
    real_cam3->ops = &ctx->wrapped_ops;
    real_cam3->common.close = shim_device_close;
    pthread_mutex_unlock(&g_sessions_lock);

    *device = (hw_device_t*)real_cam3;
    ALOGI("%s: Successfully hooked camera3 device '%s' (dev=%p, priv=%p preserved)",
          __FUNCTION__, id ? id : "unknown", real_cam3, real_cam3->priv);
    return 0;
}

static int shim_get_number_of_cameras(void) {
    if (!load_real_hal()) return 0;
    return g_real_camera_module->get_number_of_cameras();
}

static int shim_get_camera_info(int camera_id, struct camera_info *info) {
    if (!load_real_hal()) return -ENODEV;
    return g_real_camera_module->get_camera_info(camera_id, info);
}

static int shim_set_callbacks(const camera_module_callbacks_t *callbacks) {
    if (!load_real_hal()) return -ENODEV;
    return g_real_camera_module->set_callbacks(callbacks);
}

static void shim_get_vendor_tag_ops(vendor_tag_ops_t* ops) {
    if (!load_real_hal() || !ops) return;
    if (g_real_camera_module->get_vendor_tag_ops) {
        g_real_camera_module->get_vendor_tag_ops(ops);
        if (!g_vendor_tag_ops_hooked) {
            memcpy(&g_real_vendor_tag_ops, ops, sizeof(vendor_tag_ops_t));
            g_vendor_tag_ops_hooked = true;
        }
    }

    g_shim_vendor_tag_ops.get_tag_count = shim_vt_get_tag_count;
    g_shim_vendor_tag_ops.get_all_tags = shim_vt_get_all_tags;
    g_shim_vendor_tag_ops.get_section_name = shim_vt_get_section_name;
    g_shim_vendor_tag_ops.get_tag_name = shim_vt_get_tag_name;
    g_shim_vendor_tag_ops.get_tag_type = shim_vt_get_tag_type;

    memcpy(ops, &g_shim_vendor_tag_ops, sizeof(vendor_tag_ops_t));
    ALOGI("%s: Successfully hooked vendor_tag_ops with Xiaomi overlay tags", __FUNCTION__);
}

static int shim_open_legacy(const struct hw_module_t* module, const char* id, uint32_t halVersion, struct hw_device_t** device) {
    (void)module;
    if (!load_real_hal()) return -ENODEV;
    if (g_real_camera_module->open_legacy) {
        return g_real_camera_module->open_legacy((const hw_module_t*)g_real_camera_module, id, halVersion, device);
    }
    return -ENOSYS;
}

static int shim_set_torch_mode(const char* camera_id, bool enabled) {
    if (!load_real_hal()) return -ENODEV;
    if (g_real_camera_module->set_torch_mode) {
        return g_real_camera_module->set_torch_mode(camera_id, enabled);
    }
    return -ENOSYS;
}

static int shim_init() {
    if (!load_real_hal()) return -ENODEV;
    if (g_real_camera_module->init) {
        return g_real_camera_module->init();
    }
    return 0;
}

static int shim_get_physical_camera_info(int physical_camera_id, camera_metadata_t **static_metadata) {
    if (!load_real_hal()) return -ENODEV;
    if (g_real_camera_module->get_physical_camera_info) {
        return g_real_camera_module->get_physical_camera_info(physical_camera_id, static_metadata);
    }
    return -ENOSYS;
}

static int shim_is_stream_combination_supported(int camera_id, const camera_stream_combination_t *streams) {
    if (!load_real_hal()) return -ENODEV;
    if (g_real_camera_module->is_stream_combination_supported) {
        return g_real_camera_module->is_stream_combination_supported(camera_id, streams);
    }
    return 0;
}

static void shim_notify_device_state_change(uint64_t deviceState) {
    if (!load_real_hal()) return;
    if (g_real_camera_module->notify_device_state_change) {
        g_real_camera_module->notify_device_state_change(deviceState);
    }
}

static hw_module_methods_t shim_module_methods = {
    .open = shim_module_open
};

camera_module_t HAL_MODULE_INFO_SYM = {
    .common = {
        .tag = HARDWARE_MODULE_TAG,
        .module_api_version = CAMERA_MODULE_API_VERSION_2_4,
        .hal_api_version = HARDWARE_HAL_API_VERSION,
        .id = CAMERA_HARDWARE_MODULE_ID,
        .name = "Xiaomi Veux Complete Camera HAL Shim",
        .author = "acerhizm",
        .methods = &shim_module_methods,
        .dso = nullptr,
        .reserved = {0}
    },
    .get_number_of_cameras = shim_get_number_of_cameras,
    .get_camera_info = shim_get_camera_info,
    .set_callbacks = shim_set_callbacks,
    .get_vendor_tag_ops = shim_get_vendor_tag_ops,
    .open_legacy = shim_open_legacy,
    .set_torch_mode = shim_set_torch_mode,
    .init = shim_init,
    .get_physical_camera_info = shim_get_physical_camera_info,
    .is_stream_combination_supported = shim_is_stream_combination_supported,
    .notify_device_state_change = shim_notify_device_state_change,
    .reserved = {0}
};
