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
TARGET_CUSTOM_UDFPS := false
TARGET_OPTIMIZED_DEXOPT := true
TARGET_SUPPORTED_REFRESH_RATES := 60,120
SURFACE_FLINGER_BOOST := true
HBM_SUPPORTED := true
HBM_NODE := /sys/devices/platform/soc/5e00000.qcom,mdss_mdp/drm/card0/card0-DSI-1/hbm
PRODUCT_NO_CAMERA := true
TARGET_USE_MAPS := true
TARGET_USE_FILES := true
USE_REALITY_ENGINE := true
TARGET_USE_GPHOTOS := true

PRODUCT_PRODUCT_PROPERTIES += \
    ro.lunaris.maintainer=acerhizm \
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
PRODUCT_NAME := lineage_veux

PRODUCT_GMS_CLIENTID_BASE := android-xiaomi

PRODUCT_BUILD_PROP_OVERRIDES += \
    BuildDesc="veux_eea-user 13 TKQ1.221114.001 V816.0.13.0.TKCEUXM release-keys" \
    BuildFingerprint=Redmi/veux_eea/veux:13/TKQ1.221114.001/V816.0.13.0.TKCEUXM:user/release-keys \
    DeviceProduct=veux_eea
