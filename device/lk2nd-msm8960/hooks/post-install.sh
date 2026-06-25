#!/bin/sh
# lk2nd-msm8960 post-install: flash the lk2nd bootloader to the boot partition.
#
# PRP-GATED: only flashes when PRP has resolved + exported the target. PRP owns
# the device-specific resolution (A/B active slot, recovery-partition layout)
# and passes the block device in PEACOCK_BOOT_DEV. With no target set (e.g. an
# off-device `ftr install`), this is a NO-OP — the image is just staged on disk,
# no block device is ever touched.
#
#   PEACOCK_BOOT_DEV  block device to flash lk2nd to (set by PRP)
#   FEATHER_PREFIX    install root (set by feather)
set -u

img="${FEATHER_PREFIX:-}/usr/share/peacock/bootloaders/lk2nd-msm8960.img"
[ -f "$img" ] || img="/usr/share/peacock/bootloaders/lk2nd-msm8960.img"

dev="${PEACOCK_BOOT_DEV:-}"
if [ -z "$dev" ] || [ ! -b "$dev" ]; then
	echo "lk2nd-msm8960: no flash target (PEACOCK_BOOT_DEV unset) — image staged, not flashing"
	exit 0
fi
[ -f "$img" ] || { echo "lk2nd-msm8960: image not found: $img" >&2; exit 1; }

echo "lk2nd-msm8960: flashing $img -> $dev"
# lk2nd lives at the start of the boot partition; the image is smaller than the
# partition, so writing it leaves any split-boot payload after it intact.
DD=dd; command -v dd >/dev/null 2>&1 || DD="busybox dd"
$DD if="$img" of="$dev" bs=4096 conv=fsync 2>/dev/null || { echo "lk2nd-msm8960: dd failed" >&2; exit 1; }
sync
echo "lk2nd-msm8960: flashed lk2nd to $dev"
