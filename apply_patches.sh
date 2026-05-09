#!/bin/bash
# TWRP 3.5.2_10-0 build patches for Huawei MediaPad M3 Lite 10 (bach / BAH-L09)
# Run AFTER `repo sync` completes. Idempotent — safe to re-run.
#
# Source tree must be the TWRP minimal-manifest twrp-10.0-deprecated branch with
# local_manifests/bach.xml applied (see README.md for full build steps).
set -euo pipefail

DEV=/twrp/src/device/huawei/bach

if [ ! -d "$DEV" ]; then
    echo "ERROR: $DEV does not exist — repo sync didn't complete?"
    exit 1
fi

cd "$DEV"

echo "=== 1. Create twrp_bach.mk from lineage_bach.mk ==="
if [ ! -f twrp_bach.mk ]; then
    cp lineage_bach.mk twrp_bach.mk
    sed -i 's/lineage_bach/twrp_bach/g' twrp_bach.mk
    sed -i '/inherit-product.*vendor\/lineage\/config/d' twrp_bach.mk
    sed -i '/^LINEAGE_BUILDTYPE/d' twrp_bach.mk
    echo "    twrp_bach.mk created (LOS-specific lines removed)"
else
    echo "    twrp_bach.mk already exists, skipping"
fi

echo "=== 2. Patch AndroidProducts.mk ==="
if ! grep -q twrp_bach.mk AndroidProducts.mk; then
    cat >> AndroidProducts.mk <<'EOF'

# TWRP additions
PRODUCT_MAKEFILES += \
    $(LOCAL_DIR)/twrp_bach.mk

COMMON_LUNCH_CHOICES += \
    twrp_bach-userdebug \
    twrp_bach-eng
EOF
    echo "    AndroidProducts.mk patched"
else
    echo "    AndroidProducts.mk already has twrp_bach, skipping"
fi

echo "=== 3. Append TWRP block to BoardConfig.mk ==="
if ! grep -q "^# === TWRP block (added by build script) ===" BoardConfig.mk; then
    cat >> BoardConfig.mk <<'EOF'

# === TWRP block (added by build script) ===
TW_THEME := portrait_hdpi
TW_EXTRA_LANGUAGES := true
TW_INCLUDE_NTFS_3G := true
TW_INCLUDE_RESETPROP := true
TW_INCLUDE_REPACKTOOLS := true
TW_USE_TOOLBOX := true
# Both HBTP virtual input devices must be blacklisted on bach — kernel registers
# both hbtp_vm and hbtp_input when CONFIG_INPUT_HBTP_INPUT=y, and hbtp_input
# competes with the real huawei,ts_kit touchscreen (TWRP boots, displays UI,
# but doesn't respond to touch). Newline-separated per TWRP source convention.
TW_INPUT_BLACKLIST := "hbtp_vm\x0ahbtp_input"
TW_DEFAULT_BRIGHTNESS := 162
TW_BRIGHTNESS_PATH := "/sys/class/leds/lcd-backlight/brightness"
TW_MAX_BRIGHTNESS := 255
TW_SCREEN_BLANK_ON_BOOT := true

# FBE / decryption (point of 3.5.2 vs 3.3.1-0 for LOS 17.1 + GApps workflow)
TW_INCLUDE_CRYPTO := true
TW_INCLUDE_CRYPTO_FBE := true
TW_INCLUDE_FBE_METADATA_DECRYPT := true
BOARD_USES_METADATA_PARTITION := true
# Logcat for diagnostic visibility
TWRP_INCLUDE_LOGCAT := true
TARGET_USES_LOGD := true
PLATFORM_VERSION := 16.1.0
PLATFORM_SECURITY_PATCH := 2099-12-31
EOF
    echo "    BoardConfig.mk TWRP block appended"
else
    echo "    BoardConfig.mk already has TWRP block, skipping"
fi

echo "=== 4. Neutralize Android.mk files unfit for TWRP-only build ==="
# Camera QCamera2 references project-path-for,qcom-media/qcom-display, not in TWRP manifest.
CAMERA_MK="$DEV/camera/QCamera2/Android.mk"
if [ -f "$CAMERA_MK" ] && ! grep -q "Camera HAL disabled for TWRP build" "$CAMERA_MK"; then
    echo "# Camera HAL disabled for TWRP build - depends on qcom-media/qcom-display project-paths not in TWRP manifest" > "$CAMERA_MK"
    echo "    camera/QCamera2/Android.mk neutralized"
else
    echo "    camera/QCamera2/Android.mk already neutralized or absent"
fi

# device libhidl Android.mk duplicates android.hidl.base@1.0 already defined by system/libhidl
LIBHIDL_MK="$DEV/libhidl/Android.mk"
if [ -f "$LIBHIDL_MK" ] && ! grep -q "device libhidl Android.mk disabled" "$LIBHIDL_MK"; then
    echo "# device libhidl Android.mk disabled for TWRP build - duplicates system/libhidl module" > "$LIBHIDL_MK"
    echo "    libhidl/Android.mk neutralized"
else
    echo "    libhidl/Android.mk already neutralized or absent"
fi

# Disable device sepolicy includes (Huawei sepolicy references LineageOS-internal types
# like gallery_app, adbroot_exec, hal_lineage_livedisplay_qti, proc_appinfo)
if grep -q "^BOARD_PLAT_PRIVATE_SEPOLICY_DIR.*VENDOR_PATH" "$DEV/BoardConfig.mk"; then
    sed -i 's|^BOARD_PLAT_PRIVATE_SEPOLICY_DIR.*VENDOR_PATH.*|# &|' "$DEV/BoardConfig.mk"
    sed -i 's|^BOARD_SEPOLICY_DIRS.*VENDOR_PATH.*|# &|' "$DEV/BoardConfig.mk"
    echo "    BoardConfig.mk: device sepolicy includes commented out"
fi

for te in "$DEV"/sepolicy/private/*.te "$DEV"/sepolicy/vendor/*.te; do
    if [ -f "$te" ] && [ -s "$te" ]; then
        : > "$te"
    fi
done

echo ""
echo "=== 5. Symlink cryptfs_hw to expected path ==="
# TWRP libcryptfsfde Android.mk hardcodes -I device/qcom/common/cryptfs_hw,
# but our cryptfs_hw repo is at vendor/qcom/opensource/cryptfs_hw.
mkdir -p /twrp/src/device/qcom/common
if [ ! -e /twrp/src/device/qcom/common/cryptfs_hw ]; then
    ln -sfn ../../../vendor/qcom/opensource/cryptfs_hw /twrp/src/device/qcom/common/cryptfs_hw
    echo "    symlink created"
else
    echo "    symlink already present"
fi

echo "=== 6a. Patch TWRP prebuilt to skip prebuilt vdc_pie on Android 9+ ==="
# When TW_CRYPTO_USE_SYSTEM_VOLD is set, both prebuilt and crypto/vold_decrypt try
# to define vdc_pie. The crypto/vold_decrypt one is gated by PLATFORM_SDK_VERSION>=28
# but the prebuilt isn't gated (TWRP bug). Patch prebuilt to skip when SDK >= 28.
PREBUILT_MK=/twrp/src/bootable/recovery/prebuilt/Android.mk
if ! grep -q "PLATFORM_SDK_VERSION.*-lt 28" "$PREBUILT_MK"; then
    python3 - <<'PYEOF'
path = "/twrp/src/bootable/recovery/prebuilt/Android.mk"
with open(path) as f: text = f.read()
old = '''ifeq ($(TW_INCLUDE_CRYPTO), true)
    ifneq ($(TW_CRYPTO_USE_SYSTEM_VOLD),)
        # Prebuilt vdc_pie for pre-Pie SDK Platforms
        include $(CLEAR_VARS)
        LOCAL_MODULE := vdc_pie
        LOCAL_MODULE_TAGS := optional
        LOCAL_MODULE_CLASS := RECOVERY_EXECUTABLES
        LOCAL_MODULE_PATH := $(TARGET_RECOVERY_ROOT_OUT)/system/bin
        LOCAL_SRC_FILES := vdc_pie-$(TARGET_ARCH)
        include $(BUILD_PREBUILT)
    endif
endif'''
new = '''ifeq ($(TW_INCLUDE_CRYPTO), true)
    ifneq ($(TW_CRYPTO_USE_SYSTEM_VOLD),)
      ifeq ($(shell test $(PLATFORM_SDK_VERSION) -lt 28; echo $$?),0)
        # Prebuilt vdc_pie for pre-Pie SDK Platforms (Pie+ uses source-built one in crypto/vold_decrypt)
        include $(CLEAR_VARS)
        LOCAL_MODULE := vdc_pie
        LOCAL_MODULE_TAGS := optional
        LOCAL_MODULE_CLASS := RECOVERY_EXECUTABLES
        LOCAL_MODULE_PATH := $(TARGET_RECOVERY_ROOT_OUT)/system/bin
        LOCAL_SRC_FILES := vdc_pie-$(TARGET_ARCH)
        include $(BUILD_PREBUILT)
      endif
    endif
endif'''
if old in text:
    text = text.replace(old, new)
    open(path, "w").write(text)
    print("    bootable/recovery/prebuilt/Android.mk vdc_pie SDK guard added")
PYEOF
fi

echo "=== 6b. Disable TARGET_HW_DISK_ENCRYPTION ==="
# Bach uses FBE (not FDE) on Android 10. HW disk encryption is for legacy FDE.
# With TARGET_HW_DISK_ENCRYPTION=true (default in surdu_petru's tree), libcryptfsfde
# (in TWRP recovery) requires libcryptfs_hw.so + vendor.qti.hardware.cryptfshw@1.0.so
# in the recovery ramdisk — but those Soong modules are product_specific and don't
# go to recovery. Adding `recovery_available: true` to cryptfs_hw works, but the
# vendor.qti.hardware.cryptfshw@1.0 is a hidl_interface which doesn't support that
# property. Solution: disable HW_DISK_ENCRYPTION — libtwrpfscrypt handles FBE for us.
if grep -q "^TARGET_HW_DISK_ENCRYPTION := true" "$DEV/BoardConfig.mk"; then
    sed -i 's|^TARGET_HW_DISK_ENCRYPTION := true|TARGET_HW_DISK_ENCRYPTION := false|' "$DEV/BoardConfig.mk"
    echo "    TARGET_HW_DISK_ENCRYPTION disabled"
fi

# Belt-and-suspenders cleanup
sed -i '/^    recovery_available: true,$/d' /twrp/src/vendor/qcom/opensource/cryptfs_hw/Android.bp 2>/dev/null || true
sed -i '/^    recovery_available: true,$/d' /twrp/src/vendor/qcom/opensource/interfaces/cryptfshw/1.0/Android.bp 2>/dev/null || true

echo "=== 6c. Add missing tw_atomic.hpp include path to vold_decrypt Android.mk ==="
VOLD_MK=/twrp/src/bootable/recovery/crypto/vold_decrypt/Android.mk
if [ -f "$VOLD_MK" ] && ! grep -q "twrpinstall/include" "$VOLD_MK"; then
    sed -i 's|LOCAL_C_INCLUDES += system/extras/ext4_utils/include|LOCAL_C_INCLUDES += system/extras/ext4_utils/include bootable/recovery/twrpinstall/include|' "$VOLD_MK"
    echo "    vold_decrypt/Android.mk -I twrpinstall/include added"
fi

echo ""
echo "=== Verification ==="
echo "twrp_bach.mk:"
ls -la twrp_bach.mk
echo ""
echo "AndroidProducts.mk tail:"
tail -10 AndroidProducts.mk
echo ""
echo "BoardConfig.mk TWRP section:"
sed -n '/# === TWRP block (added by build script) ===/,$p' BoardConfig.mk | head -25
