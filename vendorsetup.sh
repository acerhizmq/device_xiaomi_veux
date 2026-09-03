if [ ! -d "vendor/xiaomi/veux" ]; then
    git clone https://github.com/acerhizmq/vendor_xiaomi_veux.git -b 17 vendor/xiaomi/veux
fi

if [ ! -d "kernel/xiaomi/veux" ]; then
    git clone https://github.com/acerhizmq/kernel_xiaomi_veux.git -b 17 kernel/xiaomi/veux --depth=1
fi

if [ ! -d "hardware/xiaomi" ]; then
    git clone https://github.com/LineageOS/android_hardware_xiaomi.git hardware/xiaomi
fi

# Viper4Android
if [ ! -d "packages/apps/ViPER4AndroidFX" ]; then
    git clone https://github.com/AxionAOSP/android_packages_apps_ViPER4AndroidFX.git -b v4a packages/apps/ViPER4AndroidFX
fi

# Xiaomi Camera (MIUI Camera)
if [ ! -d "device/xiaomi/camera" ]; then
    git clone https://github.com/acerhizmq/device_xiaomi_camera.git device/xiaomi/camera
fi

if [ ! -d "vendor/xiaomi/camera" ]; then
    git clone https://github.com/acerhizmq/vendor_xiaomi_camera.git vendor/xiaomi/camera
fi

# Dolby
if [ ! -d "hardware/dolby" ]; then
    git clone https://github.com/acerhizmq/hardware_dolby.git hardware/dolby
fi

# Bluetooth
if [ ! -d "hardware/qcom-caf/bt" ]; then
    git clone https://github.com/acerhizmq/hardware_qcom_bt.git -b lineage-23.2-caf hardware/qcom-caf/bt
fi
