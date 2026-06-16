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

# Inherit some common Matrixx stuff.
$(call inherit-product, vendor/matrixx/config/common_full_phone.mk)

# Boot animation
TARGET_SCREEN_HEIGHT := 2400
TARGET_SCREEN_WIDTH := 1080

PRODUCT_BRAND := Redmi
PRODUCT_DEVICE := veux
PRODUCT_MANUFACTURER := Xiaomi
PRODUCT_MODEL := 2201116SG
PRODUCT_NAME := matrixx_veux

PRODUCT_GMS_CLIENTID_BASE := android-xiaomi

PRODUCT_BUILD_PROP_OVERRIDES += \
    BuildDesc="veux_eea-user 13 TKQ1.221114.001 V816.0.13.0.TKCEUXM release-keys" \
    BuildFingerprint=Redmi/veux_eea/veux:13/TKQ1.221114.001/V816.0.13.0.TKCEUXM:user/release-keys \
    DeviceProduct=veux_eea
    
PRODUCT_PRODUCT_PROPERTIES += \
    ro.build.product=veux

# Matrixx Stuff
WITH_GMS := true
MATRIXX_MAINTAINER := Amrito
TARGET_SUPPORTED_REFRESH_RATES := 60,120
TARGET_INCLUDE_PIXEL_LAUNCHER := true
TARGET_DEFAULT_PIXEL_LAUNCHER := true
WITH_BCR := true
