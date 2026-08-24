#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

LINEAGE_BUILD := true

# Inherit from those products. Most specific first.
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
TARGET_SUPPORTS_OMX_SERVICE := false
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)

# Inherit from device.
$(call inherit-product, $(LOCAL_PATH)/device.mk)

# Rising flags
RISING_MAINTAINER := acerhizm
RISING_CHIPSET := Snapdragon® 695
RISING_BUILDTYPE := COMMUNITY
WITH_GMS := true
PRODUCT_BROKEN_VERIFY_USES_LIBRARIES := true
TARGET_ENABLE_BLUR := true
PRODUCT_NO_CAMERA := true
TARGET_INCLUDE_LIVE_WALLPAPERS := true
TARGET_SUPPORTS_GOOGLE_RECORDER := true
TARGET_SUPPORTS_QUICK_TAP := true
PRODUCT_OTA_ENFORCE_VINTF_KERNEL_REQUIREMENTS := false

# Inherit some common RisingOS stuff.
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)

PRODUCT_SYSTEM_DEFAULT_PROPERTIES += \
    ro.rising.chipset=Snapdragon® 695 \
    ro.rising.maintainer=acerhizm \
    ro.rising.releasetype=COMMUNITY

PRODUCT_PRODUCT_PROPERTIES += \
    ro.product.mod_device=veux_global \
    ro.miui.ui.version.name=V140 \
    ro.miui.ui.version.code=13 \
    ro.build.product=veux

# Boot animation
TARGET_SCREEN_HEIGHT := 2400
TARGET_SCREEN_WIDTH := 1080
TARGET_BOOT_ANIMATION_RES := 1080

PRODUCT_BRAND := Redmi
PRODUCT_DEVICE := veux
PRODUCT_MANUFACTURER := Xiaomi
PRODUCT_MODEL := 2201116SG
PRODUCT_NAME := rising_veux

PRODUCT_GMS_CLIENTID_BASE := android-xiaomi

PRODUCT_BUILD_PROP_OVERRIDES += \
    BuildDesc="veux_eea-user 13 TKQ1.221114.001 V816.0.13.0.TKCEUXM release-keys" \
    BuildFingerprint=Redmi/veux_eea/veux:13/TKQ1.221114.001/V816.0.13.0.TKCEUXM:user/release-keys \
    DeviceProduct=veux_eea
