# TWRP for Huawei MediaPad M3 Lite 10 (bach / BAH-L09)

![Downloads](https://img.shields.io/github/downloads/superheher/twrp-bach-bah-l09/total)

TWRP recovery 3.5.2_10-0 for the Huawei MediaPad M3 Lite 10, codename **bach**, model **BAH-L09**. Built from the [TWRP minimal-manifest twrp-10.0-deprecated branch](https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp/tree/twrp-10.0-deprecated) plus device tree from [Huawei-Dev/android_device_huawei_bach@ten](https://github.com/Huawei-Dev/android_device_huawei_bach).

> **Pre-built recovery image is in [Releases](../../releases/latest).**

## Why this build

Existing community TWRP builds for bach (3.3.1-0, 3.3.1-3 from XDA) had two problems:

1. **3.3.1-0** doesn't boot on bach — the bootloader's recovery validator silently falls back to eRecovery (Huawei's network-OTA recovery). Despite many guides claiming it works as a "bootstrap recovery," empirically `Vol Up + Power` after `fastboot flash recovery twrp_3.3.1-0.img` loads eRecovery on this device, not TWRP.
2. **Some 3.3.1-3 community builds** boot, display the TWRP UI, but **don't respond to touch**. Root cause: the build configuration only blacklisted one of bach's two HBTP virtual input devices, and the second one (`hbtp_input`) competes with the real `huawei,ts_kit` touchscreen.

This build (3.5.2_10-0) addresses both:
- 3.5.2 base boots cleanly on bach via `Vol Up + Power` (no eRecovery fallback).
- `TW_INPUT_BLACKLIST := "hbtp_vm\x0ahbtp_input"` (newline-separated per TWRP source convention) blacklists both HBTP devices, so touch works.
- FBE-aware (`TW_INCLUDE_CRYPTO_FBE := true` + `TW_INCLUDE_FBE_METADATA_DECRYPT := true`) for LineageOS 17.1 (Android 10) `/data` access.

## Compatibility

| Codename | Model     | Status                 |
| -------- | --------- | ---------------------- |
| bach     | BAH-L09   | **Confirmed working**  |
| bach     | BAH-W09   | Likely (same hardware) |
| bach     | BAH-AL00  | Likely (same hardware) |
| bach     | BAH-L01   | Likely (same hardware) |

Bootloader must be unlocked (Huawei stopped issuing official codes in 2018; check XDA for current methods). Verify with `fastboot oem device-info` showing `Device unlocked: true`.

## Install

The bach bootloader has several quirks that affect the install procedure. Read all of this before flashing.

### Prerequisites
- USB cable + Linux/macOS/Windows host with `adb` + `fastboot` (Android Platform Tools).
- Bootloader unlocked.
- Device charged ≥ 50%.

### Entering fastboot

The standard `Vol Down + Power` does **not** work on bach. The correct combo:

1. Power off device fully (long-hold power until screen is black).
2. **Disconnect USB cable.**
3. Press and hold **Volume Down**.
4. While still holding Vol Down, **plug the USB cable in**.
5. Hold Vol Down for ~5 seconds after USB plug-in.

Device boots into fastboot mode. Verify with `fastboot devices`.

### Flashing TWRP

```bash
fastboot flash recovery twrp-3.5.2_10-0-bach-built-v3.img
```

### Booting TWRP — important

**Do not use `fastboot reboot recovery`** on bach — the bootloader silently treats it as a regular `fastboot reboot` and boots Android. If Android (stock EMUI) boots, it overwrites the recovery partition back to eRecovery on first boot, and you lose TWRP.

Also **do not use `fastboot boot twrp.img`** — the bach bootloader silently rejects unsigned RAM-boot images even when bootloader-unlocked.

Correct sequence:

1. After `fastboot flash recovery`, **physically power off the tablet from fastboot** (long-hold the power button until the device shuts down — do not let it reboot to system).
2. Wait for screen to be fully black.
3. **Hold `Volume Up + Power` together** until the Huawei logo appears, then release Power but keep holding Vol Up.
4. TWRP loads.

This avoids letting EMUI run, so the recovery partition stays as TWRP.

### After booting TWRP

1. **First-launch dialog**: pick "Keep Read Only" (we don't need to modify /system).
2. **Wipe → Format Data → type `yes`** to format `/data` as f2fs (clears any existing FBE-encrypted data).
3. **Reboot → Recovery** (TWRP's own advice after `Format Data` — re-mounts /data cleanly).
4. **Install your ROM ZIP** via your preferred method:
   - Recommended: `adb push ROM.zip /data/` then `adb shell twrp install /data/ROM.zip` (see [Known Issues](#known-issues) for why).
   - Or place ZIP on `/sdcard` via MTP and use TWRP's `Install` UI.

## Known issues

### ADB sideload not working

`adb sideload` from TWRP fails with `connection failed: closed` on the host side. Root cause: when TWRP transitions USB to sideload mode, the regular `adbd` keeps holding `/dev/usb-ffs/adb/ep0`, blocking `minadbd` from binding. Recovery log shows:

```
minadbd: cannot open control endpoint /dev/usb-ffs/adb/ep0: Device or resource busy
```

The underlying init-script issue on bach is that `sys.usb.configfs` is never set (kernel doesn't pass `androidboot.usbconfigfs` via cmdline), so the configfs-conditional `stop adbd` triggers in `bootable/recovery/etc/init.rc` never fire. Several attempted fixes (commenting `setprop sys.usb.ffs.ready 0`, adding `setprop sys.usb.configfs 1` to `on init`, adding an unconditional `on property:sys.usb.config=none / stop adbd` trigger) didn't resolve the issue end-to-end and need further investigation.

**Workaround that works perfectly:**

```bash
adb push your-rom.zip /data/
adb shell twrp install /data/your-rom.zip
```

The TWRP CLI (`/system/bin/twrp` inside the recovery) supports `install`, `wipe`, `format`, `backup`, `restore`, `mount`, `reboot`, etc. — see `adb shell twrp --help` for the full list. Functionally equivalent to sideload.

### Other

- **No HW disk encryption (FDE) support** — we built with `TARGET_HW_DISK_ENCRYPTION := false` because bach uses FBE on Android 10. Including FDE support requires `libcryptfs_hw.so` in the recovery ramdisk, which doesn't fit cleanly with bach's `vendor.qti.hardware.cryptfshw@1.0` HIDL setup. If you need FDE for some reason, this build won't decrypt FDE-encrypted /data.

## Build from source

This recovery is reproducible. Build with `repo` + `make` in a clean Ubuntu 20.04 environment (Podman/Docker container recommended for isolation).

### Quick start (container)

```bash
# 1. Bootstrap
mkdir -p ~/twrp/src && cd ~/twrp/src
podman run -d --name twrp-build -v ~/twrp:/twrp ubuntu:20.04 sleep infinity
podman exec twrp-build apt-get update
podman exec twrp-build apt-get install -y bc bison build-essential ccache curl flex \
    g++-multilib gcc-multilib git gnupg gperf imagemagick lib32readline-dev \
    lib32z1-dev libelf-dev liblz4-tool libsdl1.2-dev libssl-dev libxml2 \
    libxml2-utils lzop pngcrush rsync schedtool squashfs-tools xsltproc \
    zip zlib1g-dev openjdk-8-jdk python python3 python-is-python3

# 2. Repo init + sync
cd ~/twrp/src
podman exec twrp-build bash -c "cd /twrp/src && \
    repo init -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp.git \
              -b twrp-10.0-deprecated --depth=1"

# 3. Place local manifest (this repo's local_manifests/bach.xml)
mkdir -p .repo/local_manifests
cp /path/to/this/repo/local_manifests/bach.xml .repo/local_manifests/

# 4. Sync
podman exec twrp-build bash -c "cd /twrp/src && repo sync -j4 --force-sync"

# 5. Apply patches (this repo's apply_patches.sh)
cp /path/to/this/repo/apply_patches.sh ~/twrp/
podman exec twrp-build bash /twrp/apply_patches.sh

# 6. Build
podman exec twrp-build bash -c "cd /twrp/src && \
    source build/envsetup.sh && \
    lunch twrp_bach-eng && \
    ALLOW_MISSING_DEPENDENCIES=true WITH_DEXPREOPT=false mka recoveryimage -j8"

# Output: ~/twrp/src/out/target/product/bach/recovery.img
```

`ALLOW_MISSING_DEPENDENCIES=true` is needed because the minimal manifest doesn't include all the junit/mockito/dagger deps that some Soong rules transitively reference. `WITH_DEXPREOPT=false` avoids a Soong goroutine deadlock that surfaces when missing-dependencies mode is enabled.

Build time: ~1-3 hours from cold cache, ~2 minutes incremental on a modern machine.

### What `apply_patches.sh` does

1. **Creates `twrp_bach.mk`** from `lineage_bach.mk`, stripping LineageOS-specific includes that aren't in the TWRP minimal manifest.
2. **Patches `AndroidProducts.mk`** to add the new makefile and `twrp_bach-eng`/`twrp_bach-userdebug` lunch combos.
3. **Appends a TWRP block to `BoardConfig.mk`** with FBE flags, `TW_INPUT_BLACKLIST`, theme, brightness paths, etc.
4. **Neutralizes** `camera/QCamera2/Android.mk` (depends on missing project paths) and `libhidl/Android.mk` (duplicates a system module).
5. **Symlinks** `device/qcom/common/cryptfs_hw` → `vendor/qcom/opensource/cryptfs_hw` (TWRP's libcryptfsfde hardcodes the device-tree path).
6. **Patches** `bootable/recovery/prebuilt/Android.mk` to skip the prebuilt `vdc_pie` on Android 9+ (TWRP bug — duplicates the source-built one when `TW_CRYPTO_USE_SYSTEM_VOLD` is set).
7. **Disables** `TARGET_HW_DISK_ENCRYPTION` (bach uses FBE not FDE on Android 10; HW disk encryption pulls in libs that don't fit in the recovery ramdisk).
8. **Adds** include path for `tw_atomic.hpp` to `vold_decrypt/Android.mk` (TWRP missing-include bug).

The script is idempotent — safe to re-run after partial patches.

## Verification

The release `.img` was verified by:

1. **Static**: `qemu-aarch64-static -L <ramdisk-root> /system/bin/recovery --help` runs without linker errors, indicating all `NEEDED` shared libraries are present in the recovery ramdisk. Expected stderr: harmless missing `/sys/class/leds/...` and `/sys/devices/soc/...usb` paths (these exist on the actual MSM8937 device).
2. **Dynamic**: flashed to a real BAH-L09, verified TWRP UI loads, touch responds, `Format Data` succeeds, `/data` mounts as f2fs after format, `adb shell twrp install` successfully installs LineageOS 17.1.

Hashes are listed in each release.

## Credits

- **TeamWin** — TWRP itself (Apache 2.0).
- **surdu_petru** and prior bach maintainers — the device tree at [Huawei-Dev/android_device_huawei_bach](https://github.com/Huawei-Dev/android_device_huawei_bach).
- **LineageOS** — `android_vendor_qcom_opensource_cryptfs_hw` (`lineage-17.1`), `android_device_qcom_sepolicy` (`lineage-17.1-legacy-um`), and `android_vendor_qcom_opensource_interfaces` (`lineage-17.1`).
- **AOSP** — `platform/test/vts-testcase/hal` and `platform/system/bpf` at `android-10.0.0_r41` (re-added because the TWRP minimal manifest's `remove*.xml` strips them, but Soong needs them to parse the tree).
- **Huawei-Dev** — `android_kernel_huawei_bach@ten` and `android_vendor_huawei_bach@ten`.

## License

Apache 2.0 — see [LICENSE](./LICENSE). Note that the recovery image itself includes components from TWRP (Apache 2.0), Linux kernel (GPLv2), and various other projects under their respective licenses; consult the source repositories for details.
