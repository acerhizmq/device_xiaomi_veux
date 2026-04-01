#include <fstream>
#include <string>
#include <android/log.h>
#include <unistd.h>
#include <dirent.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>

#define LOG_TAG "CameraProviderExtension"
#define ALOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

static const std::string kTorchLedPath = "/sys/class/leds/led:torch_0";
static const std::string kTorchLed1Path = "/sys/class/leds/led:torch_1";

static bool nodeExists(const std::string& path) {
    return access(path.c_str(), F_OK) == 0;
}

template <typename T>
static void set(const std::string& path, const T& value) {
    std::ofstream file(path);
    if (file.is_open()) {
        file << value;
        ALOGE("Successfully wrote %s to %s", std::to_string(value).c_str(), path.c_str());
    } else {
        ALOGE("Failed to open %s for writing", path.c_str());
    }
}

template <typename T>
static T get(const std::string& path, const T& def) {
    std::ifstream file(path);
    T result;
    if (file.is_open()) {
        file >> result;
        if (file.fail()) {
            ALOGE("Failed to read from %s", path.c_str());
            return def;
        }
        return result;
    }
    ALOGE("Failed to open %s for reading", path.c_str());
    return def;
}

bool supportsTorchStrengthControlExt() {
    ALOGE("supportsTorchStrengthControlExt called -> returning true (force)");
    return true;
}

bool supportsSetTorchModeExt() {
    ALOGE("supportsSetTorchModeExt called -> returning true (force)");
    return true;
}

int32_t getTorchDefaultStrengthLevelExt() {
    return 86; // 0x56 = LM36011 system default torch current
}

int32_t getTorchMaxStrengthLevelExt() {
    return 127; // LM36011 supports 0-127 torch current levels (7-bit)
}

int32_t getTorchStrengthLevelExt() {
    auto node = kTorchLedPath + "/brightness";
    int32_t strength = get(node, 0);
    ALOGE("getTorchStrengthLevelExt called: %d", strength);
    return strength;
}

#include <glob.h>

// New helper function for setting torch strength via sysfs node
static void setTorchStrengthSysfs(int32_t torchStrength) {
    ALOGE("setTorchStrengthSysfs: Setting torch strength to %d", torchStrength);
    
    glob_t glob_result;
    // Search pattern for the torch_strength node
    const char* pattern = "/sys/devices/platform/soc/*/*camera-flash*/torch_strength";
    
    int return_value = glob(pattern, GLOB_TILDE, NULL, &glob_result);
    bool found = false;

    if (return_value == 0) {
        for (size_t i = 0; i < glob_result.gl_pathc; ++i) {
            char* path = glob_result.gl_pathv[i];
            // Skip @0, @2, @3 if they aren't the main one, but usually multiple flashes exist.
            // For now, write to ALL found flash nodes to ensure the active one is hit.
            int fd = open(path, O_WRONLY);
            if (fd >= 0) {
                char buf[16];
                int len = snprintf(buf, sizeof(buf), "%d", torchStrength);
                if (write(fd, buf, len) > 0) {
                    ALOGE("setTorchStrengthSysfs: Successfully wrote %d to %s", torchStrength, path);
                    found = true;
                }
                close(fd);
            } else {
                ALOGE("setTorchStrengthSysfs: Failed to open %s (errno: %d)", path, errno);
            }
        }
    } else {
        ALOGE("setTorchStrengthSysfs: glob() failed or no nodes found (pattern: %s, return: %d)", pattern, return_value);
    }
    
    globfree(&glob_result);

    if (!found) {
        // Fallback for flatter hierarchies
        const char* pattern2 = "/sys/devices/platform/soc/*camera-flash*/torch_strength";
        if (glob(pattern2, GLOB_TILDE, NULL, &glob_result) == 0) {
             for (size_t i = 0; i < glob_result.gl_pathc; ++i) {
                int fd = open(glob_result.gl_pathv[i], O_WRONLY);
                if (fd >= 0) {
                    char buf[16];
                    int len = snprintf(buf, sizeof(buf), "%d", torchStrength);
                    write(fd, buf, len);
                    close(fd);
                    found = true;
                    ALOGE("setTorchStrengthSysfs: Found via fallback: %s", glob_result.gl_pathv[i]);
                }
            }
            globfree(&glob_result);
        }
    }

    if (!found) {
        ALOGE("setTorchStrengthSysfs: Could not find any writable torch_strength node!");
    }
}

void setTorchStrengthLevelExt(int32_t torchStrength, bool enabled) {
    if (!enabled) {
        torchStrength = 0;
    }
    // Clamp to valid kernel range (0-127)
    if (torchStrength > 127) torchStrength = 127;
    if (torchStrength < 0) torchStrength = 0;

    ALOGE("setTorchStrengthLevelExt called: strength=%d, enabled=%d", torchStrength, enabled);
    
    // Write to kernel sysfs bridge - cam_flash_i2c_apply_setting will
    // intercept the next torch open and apply this value to LM36011 reg 0x04
    setTorchStrengthSysfs(torchStrength);
}

void setTorchModeExt(bool enabled) {
    int32_t strength = getTorchDefaultStrengthLevelExt();
    setTorchStrengthLevelExt(enabled ? strength : 0, enabled);
}
