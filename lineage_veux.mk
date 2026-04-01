#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

# Inherit from those products. Most specific first.
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
TARGET_SUPPORTS_OMX_SERVICE := false
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)

# Inherit from device.
$(call inherit-product, $(LOCAL_PATH)/device.mk)

# Inherit some common Lunaris stuff.
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)

# Lunaris flags
WITH_GMS := true
WITH_BCR := true

# Display and specific Lunaris settings
TARGET_CUSTOM_UDFPS := false
TARGET_OPTIMIZED_DEXOPT := true
TARGET_SUPPORTED_REFRESH_RATES := 60,90,120
HBM_SUPPORTED := true
HBM_NODE := /sys/class/drm/sde-conn-1-DSI-1/bl_scale_sv
PRODUCT_NO_CAMERA := false

PRODUCT_PRODUCT_PROPERTIES += \
    ro.lunaris.maintainer=acerhizm \
    ro.product.mod_device=veux_global \
    ro.miui.ui.version.name=V140 \
    ro.miui.ui.version.code=13

# Boot animation
TARGET_SCREEN_HEIGHT := 2400
TARGET_SCREEN_WIDTH := 1080
TARGET_BOOT_ANIMATION_RES := 1080

PRODUCT_BRAND := Redmi
PRODUCT_DEVICE := veux
PRODUCT_MANUFACTURER := Xiaomi
PRODUCT_MODEL := 2201116SG
PRODUCT_NAME := lineage_veux

PRODUCT_GMS_CLIENTID_BASE := android-xiaomi

PRODUCT_BUILD_PROP_OVERRIDES += \
    BuildDesc="veux_eea-user 13 TKQ1.221114.001 V816.0.13.0.TKCEUXM release-keys" \
    BuildFingerprint=Redmi/veux_eea/veux:13/TKQ1.221114.001/V816.0.13.0.TKCEUXM:user/release-keys \
    DeviceProduct=veux_eea
