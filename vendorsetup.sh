if [ ! -d "vendor/xiaomi/veux" ]; then
    git clone https://github.com/Project-Astraverse/vendor_xiaomi_veux.git vendor/xiaomi/veux
fi

if [ ! -d "kernel/xiaomi/veux" ]; then
    git clone https://github.com/Project-Astraverse/kernel_xiaomi_veux.git -b 16 kernel/xiaomi/veux --depth=1
fi

if [ ! -d "hardware/xiaomi" ]; then
    git clone https://github.com/LineageOS/android_hardware_xiaomi.git hardware/xiaomi
fi

# Viper4Android
if [ ! -d "packages/apps/ViPER4AndroidFX" ]; then
    git clone https://github.com/AxionAOSP/android_packages_apps_ViPER4AndroidFX.git -b v4a packages/apps/ViPER4AndroidFX
fi

if [ ! -d "vendor/xiaomi/miuicamera-veux" ]; then
    git clone https://github.com/Project-Astraverse/vendor_xiaomi_miuicamera-veux.git vendor/xiaomi/miuicamera-veux --depth=1
fi

# Dolby
if [ ! -d "hardware/dolby" ]; then
    git clone https://github.com/oscaro-resources/hardware_dolby.git hardware/dolby
fi
