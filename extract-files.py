#!/usr/bin/env -S PYTHONPATH=../../../tools/extract-utils python3
#
# SPDX-FileCopyrightText: 2024 The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

from os import path

from extract_utils.file import File
from extract_utils.fixups_blob import (
    BlobFixupCtx,
    blob_fixup,
    blob_fixups_user_type,
)
from extract_utils.fixups_lib import (
    lib_fixups,
    lib_fixups_user_type,
)
from extract_utils.main import (
    ExtractUtils,
    ExtractUtilsModule,
)
from extract_utils.utils import (
    Color,
    color_print,
    run_cmd,
)


def lib_fixup_vendor_suffix(lib: str, partition: str, *args, **kwargs):
    return f'{lib}_{partition}' if partition == 'vendor' else None


lib_fixups: lib_fixups_user_type = {
    **lib_fixups,
}


def blob_fixup_merge_files(
    ctx: BlobFixupCtx,
    file: File,
    file_path: str,
    file_path_to_merge: str,
    token: str,
    *args,
    **kwargs,
):
    with open(file_path, 'r+', newline='', encoding='utf-8') as f1:
        if token not in f1.read():
            source = utils._ExtractUtils__args.source
            if source == 'adb':
                try:
                    data = run_cmd(
                        ['adb', 'shell', 'cat', f'/{file_path_to_merge}']
                    )
                except ValueError:
                    color_print(
                        f'{file_path_to_merge}: failed to read', color=Color.RED
                    )
            else:
                file_path_to_merge = path.join(source, file_path_to_merge)
                with open(
                    file_path_to_merge, 'r', newline='', encoding='utf-8'
                ) as f2:
                    data = f2.read()
            try:
                f1.write(data)
            except:
                color_print(f'{file.dst}: failed to merge', color=Color.RED)


blob_fixups: blob_fixups_user_type = {
    ('odm/etc/build_S88006AA1.prop', 'odm/etc/build_S88007AA1.prop', 'odm/etc/build_S88007EA1.prop', 'odm/etc/build_S88008BA1.prop', 'odm/etc/build_S88106BA1.prop', 'odm/etc/build_S88107BA1.prop'): blob_fixup()
        .regex_replace(r'(?m)^.*marketname.*\n?', '')
        .regex_replace(r'(?m)cert', 'model'),
    'system_ext/etc/init/wfdservice.rc': blob_fixup()
        .regex_replace(r'(start|stop) wfdservice\b', r'\1 wfdservice64'),
    'system_ext/lib64/libwfdnative.so': blob_fixup()
        .remove_needed('android.hidl.base@1.0.so'),
    'vendor/etc/camera/camxoverridesettings.txt': blob_fixup()
        .regex_replace('0x10080', '0')
        .regex_replace('0x1F', '0x0'),
    'vendor/etc/init/init.batterysecret.rc': blob_fixup()
        .regex_replace(r'on charger', r'on property:init.svc.vendor.charger=running'),
    'vendor/etc/libnfc-pn557.conf': blob_fixup()
        .call(blob_fixup_merge_files, 'vendor/libnfc-nxp_RF.conf', 'NXP RF', need_tmp_dir=False),
    'vendor/lib64/android.hardware.secure_element@1.0-impl.so': blob_fixup()
        .remove_needed('android.hidl.base@1.0.so'),
    'vendor/lib64/camera/components/com.qti.node.mialgocontrol.so': blob_fixup()
        .add_needed('libpiex_shim.so'),
    ('vendor/lib64/libwvhidl.so', 'vendor/lib64/mediadrm/libwvdrmengine.so'): blob_fixup()
        .add_needed('libcrypto_shim.so'),
}  # fmt: skip

module = ExtractUtilsModule(
    'veux',
    'xiaomi',
    blob_fixups=blob_fixups,
    lib_fixups=lib_fixups,
    check_elf=False,
)

if __name__ == '__main__':
    utils = ExtractUtils.device(module)
    utils.run()
