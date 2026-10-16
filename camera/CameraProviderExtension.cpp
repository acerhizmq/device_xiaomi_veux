#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <android/log.h>
#include <cutils/properties.h>

#include <atomic>
#include <string>
#include <utility>
#include <vector>

#define LOG_TAG "CameraProviderExtension"
#define ALOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// Torch runs on the rear camera's flash device only. camera-flash@1 and @3 are
// the same LED driver IC seen through the front and aux sensors; the kernel
// rejects writes there because the HAL never drives torch on them.
static const char* kTorchStrengthPath =
    "/sys/devices/platform/soc/5c1b000.qcom,cci0/5c1b000.qcom,cci0:qcom,camera-flash@0/torch_strength";

// Torch current the camera HAL programs on its own (register 0x04 = 0x2c).
static constexpr int32_t kTorchDefaultStrength = 44;
static constexpr int32_t kTorchMaxStrength = 127;

// torch_strength is write-only, so remember the level last requested.
static std::atomic<int32_t> sTorchStrength{kTorchDefaultStrength};

static void setTorchStrengthSysfs(int32_t torchStrength) {
    int fd = open(kTorchStrengthPath, O_WRONLY);
    if (fd < 0) {
        ALOGE("setTorchStrengthSysfs: Failed to open %s (errno: %d)", kTorchStrengthPath, errno);
        return;
    }

    char buf[16];
    int len = snprintf(buf, sizeof(buf), "%d", torchStrength);
    if (write(fd, buf, len) <= 0) {
        ALOGE("setTorchStrengthSysfs: Failed to write %d to %s (errno: %d)", torchStrength,
                kTorchStrengthPath, errno);
    }
    close(fd);
}

bool supportsTorchStrengthControlExt() {
    return true;
}

int32_t getTorchDefaultStrengthLevelExt() {
    return kTorchDefaultStrength;
}

int32_t getTorchMaxStrengthLevelExt() {
    return kTorchMaxStrength;
}

int32_t getTorchStrengthLevelExt() {
    return sTorchStrength.load();
}

void setTorchStrengthLevelExt(int32_t torchStrength, bool enabled) {
    if (!enabled) {
        // The HAL has already turned the torch off. Writing 0 only drops the
        // kernel's level override; it does not touch the flash hardware.
        sTorchStrength.store(kTorchDefaultStrength);
        setTorchStrengthSysfs(0);
        return;
    }

    if (torchStrength > kTorchMaxStrength) torchStrength = kTorchMaxStrength;
    if (torchStrength < 1) torchStrength = 1;

    sTorchStrength.store(torchStrength);
    setTorchStrengthSysfs(torchStrength);
}

// No per-app capture request overrides on veux.
std::vector<std::pair<std::string, uint8_t>> getCaptureRequestU8OverridesExt(
        const std::string& /* cameraId */, const std::string& /* packageName */) {
    return {};
}
