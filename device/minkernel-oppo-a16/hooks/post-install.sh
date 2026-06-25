#!/bin/sh
# minkernel-oppo-a16 post-install: flash the MK chainloader boot.img to the boot
# partition. PRP-GATED — only flashes when PRP resolved + exported the target
# (PEACOCK_BOOT_DEV); off-device installs just stage the image (no-op).
set -u

img="${FEATHER_PREFIX:-}/usr/share/peacock/bootloaders/mk-oppo-a16-boot.img"
[ -f "$img" ] || img="/usr/share/peacock/bootloaders/mk-oppo-a16-boot.img"

dev="${PEACOCK_BOOT_DEV:-}"
if [ -z "$dev" ] || [ ! -b "$dev" ]; then
	echo "minkernel-oppo-a16: no flash target (PEACOCK_BOOT_DEV unset) — image staged, not flashing"
	exit 0
fi
[ -f "$img" ] || { echo "minkernel-oppo-a16: image not found: $img" >&2; exit 1; }

echo "minkernel-oppo-a16: flashing $img -> $dev"
DD=dd; command -v dd >/dev/null 2>&1 || DD="busybox dd"
$DD if="$img" of="$dev" bs=4096 conv=fsync 2>/dev/null || { echo "minkernel-oppo-a16: dd failed" >&2; exit 1; }
sync
echo "minkernel-oppo-a16: flashed boot.img to $dev"
