#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <android/log.h>
#include <cutils/properties.h>

#define LOG_TAG "CameraProviderExtension"
#define ALOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

static const char* kTorchStrengthPaths[] = {
    "/sys/devices/platform/soc/5c1b000.qcom,cci0/5c1b000.qcom,cci0:qcom,camera-flash@0/torch_strength",
    "/sys/devices/platform/soc/5c1b000.qcom,cci0/5c1b000.qcom,cci0:qcom,camera-flash@1/torch_strength",
    "/sys/devices/platform/soc/5c1b000.qcom,cci0/5c1b000.qcom,cci0:qcom,camera-flash@3/torch_strength",
};

static void writeTorchStrengthPath(const char* path, int32_t torchStrength, bool* found) {
    int fd = open(path, O_WRONLY);
    if (fd < 0) {
        ALOGE("setTorchStrengthSysfs: Failed to open %s (errno: %d)", path, errno);
        return;
    }

    char buf[16];
    int len = snprintf(buf, sizeof(buf), "%d", torchStrength);
    if (write(fd, buf, len) > 0) {
        ALOGE("setTorchStrengthSysfs: Successfully wrote %d to %s", torchStrength, path);
        if (found != nullptr) {
            *found = true;
        }
    } else {
        ALOGE("setTorchStrengthSysfs: Failed to write %d to %s (errno: %d)", torchStrength, path,
                errno);
    }
    close(fd);
}

static void setTorchStrengthSysfs(int32_t torchStrength) {
    bool found = false;
    for (const char* path : kTorchStrengthPaths) {
        if (access(path, F_OK) == 0) {
            writeTorchStrengthPath(path, torchStrength, &found);
        }
    }

    if (!found) {
        ALOGE("setTorchStrengthSysfs: Could not write any veux torch_strength node!");
    }
}

bool supportsTorchStrengthControlExt() {
    return true;
}

bool supportsSetTorchModeExt() {
    return true;
}

int32_t getTorchDefaultStrengthLevelExt() {
    return 86; // 0x56 = LM36011 system default torch current
}

int32_t getTorchMaxStrengthLevelExt() {
    return 127; // LM36011 supports 0-127 torch current levels (7-bit)
}

int32_t getTorchStrengthLevelExt() {
    char value[16] = {};
    int fd = open(kTorchStrengthPaths[0], O_RDONLY);
    if (fd < 0) {
        return 0;
    }
    ssize_t n = read(fd, value, sizeof(value) - 1);
    close(fd);
    if (n <= 0) {
        return 0;
    }
    return static_cast<int32_t>(strtol(value, nullptr, 10));
}

void setTorchStrengthLevelExt(int32_t torchStrength, bool enabled) {
    // HAL setTorchMode(false) already extinguished the torch. sysfs strength=0 here
    // blocks cameraserver ~9s (CCI timeout on 3 nodes) and stalls QS reopen.
    if (!enabled) {
        return;
    }
    // Clamp to valid kernel range (0-127)
    if (torchStrength > 127) torchStrength = 127;
    if (torchStrength < 0) torchStrength = 0;

    setTorchStrengthSysfs(torchStrength);
}

void setTorchModeExt(bool enabled) {
    if (!enabled) {
        return;
    }
    setTorchStrengthLevelExt(getTorchDefaultStrengthLevelExt(), true);
}

int32_t getCameraCaptureFlashStrengthLevelExt() {
    return getTorchMaxStrengthLevelExt();
}

void applyCameraCaptureFlashStrengthToSysfs() {
    setTorchStrengthLevelExt(getCameraCaptureFlashStrengthLevelExt(), true);
}

void restoreTorchStrengthSysfsFromPersist() {
    char value[PROPERTY_VALUE_MAX];
    if (property_get("persist.flashlight.strength", value, "") <= 0) {
        return;
    }

    char* end = nullptr;
    long parsed = strtol(value, &end, 10);
    if (end == value || parsed < 0 || parsed > 127) {
        return;
    }

    setTorchStrengthLevelExt(static_cast<int32_t>(parsed), parsed > 0);
}
