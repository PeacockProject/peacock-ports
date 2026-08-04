#!/bin/sh
# firmware-xiaomi-ginkgo post-install: extract the device's own vendor firmware
# into /lib/firmware.
#
# The blobs are Qualcomm's/Xiaomi's/Novatek's and are never redistributed. They
# are already present on this phone, and a PeacockOS install does not touch the
# stock partitions (it lives in a nested GPT inside a container partition), so
# the owner's firmware is simply copied on the owner's own hardware.
#
#   FEATHER_PREFIX  install root (set by feather)
#
# FAIL-SOFT BY DESIGN: a device whose vendor partition was wiped, or an
# off-device `ftr install`, must not fail the whole install — it warns and
# leaves /lib/firmware empty. The device still boots; it just has no modem,
# wifi, bluetooth, hardware video decode, touch, or GPU out of secure mode.
set -u

ROOT="${FEATHER_PREFIX:-}"
SHARE="$ROOT/usr/share/peacock/firmware/ginkgo"
SCRIPT="$SHARE/extract-firmware.sh"
MANIFEST="$SHARE/firmware-manifest.txt"
DEST="$ROOT/lib/firmware"
TAG="firmware-xiaomi-ginkgo:"

[ -f "$SCRIPT" ] || { echo "$TAG extractor missing ($SCRIPT) — skipping" >&2; exit 0; }

# Find a partition by its GPT name. busybox blkid/fdisk do not expose GPT names,
# so read the table with real sfdisk — the same approach prp-targets uses.
find_sfdisk() {
	for c in /sbin/sfdisk /usr/sbin/sfdisk /bin/sfdisk; do
		[ -x "$c" ] || continue
		case "$(readlink -f "$c" 2>/dev/null)" in *busybox*) continue ;; esac
		echo "$c"; return 0
	done
	return 1
}
SFDISK="$(find_sfdisk || true)"

part_by_name() {
	want="$1"
	[ -n "$SFDISK" ] || return 1
	for disk in /dev/mmcblk0 /dev/sda /dev/mmcblk1; do
		[ -b "$disk" ] || continue
		"$SFDISK" -d "$disk" 2>/dev/null | while IFS= read -r line; do
			case "$line" in
				*"name=\"$want\""*|*"name=$want,"*|*"name=$want")
					printf '%s\n' "${line%% *}" | sed 's/[,:]$//'
					;;
			esac
		done | head -1 | grep . && return 0
	done
	return 1
}

MNT="${ROOT}/run/peacock-fwsrc"
mounted=""
cleanup() {
	for m in $mounted; do umount "$m" 2>/dev/null || true; done
	[ -d "$MNT" ] && rmdir "$MNT"/* "$MNT" 2>/dev/null || true
}
trap cleanup EXIT

mount_ro() { # <partname> <subdir> -> echoes mountpoint, or nothing
	node="$(part_by_name "$1" 2>/dev/null || true)"
	[ -n "$node" ] && [ -b "$node" ] || return 1
	mp="$MNT/$2"
	mkdir -p "$mp" || return 1
	mount -o ro "$node" "$mp" 2>/dev/null || return 1
	mounted="$mounted $mp"
	echo "$mp"
}

VEN="$(mount_ro vendor vendor || true)"
if [ -z "$VEN" ]; then
	echo "$TAG could not mount the stock 'vendor' partition — no firmware extracted." >&2
	echo "$TAG the device will boot, but modem/wifi/bluetooth/video/touch/GPU will not work." >&2
	echo "$TAG extract manually later with $SCRIPT --from <vendor> --bt <bluetooth> --modem <NON-HLOS>" >&2
	exit 0
fi
BT="$(mount_ro bluetooth bluetooth || true)"
NH="$(mount_ro modem modem || true)"

echo "$TAG extracting vendor firmware from the device's own partitions"
set -- --from "$VEN" -o "$DEST"
[ -n "$BT" ] && set -- "$@" --bt "$BT"
[ -n "$NH" ] && set -- "$@" --modem "$NH"

if sh "$SCRIPT" "$@" >/dev/null 2>&1; then
	echo "$TAG firmware extracted to /lib/firmware"
else
	echo "$TAG extraction reported errors — some firmware may be missing" >&2
fi

# Verify against the manifest, but do NOT fail on mismatch: the GPU zap shader
# is ROM-specific (its .mdt and b01 are the signature segments, so a re-signed
# vendor image changes them without changing the payload), and qupv3fw.elf is
# absent from many vendor builds entirely.
if [ -f "$MANIFEST" ] && command -v sha256sum >/dev/null 2>&1; then
	bad=$( cd "$DEST" 2>/dev/null && sha256sum -c --ignore-missing "$MANIFEST" 2>/dev/null \
	       | grep -c ': FAILED' || true )
	if [ "${bad:-0}" -gt 0 ]; then
		echo "$TAG $bad file(s) differ from the reference manifest — expected on a" >&2
		echo "$TAG different ROM (zap shader is re-signed per build); not an error." >&2
	fi
fi
exit 0
