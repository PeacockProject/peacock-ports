#!/bin/sh
# The Void rootfs is a flat "./"-prefixed FHS archive (./bin ./etc ./usr ...), so it needs no
# --strip-components — verified against void-aarch64-ROOTFS-20250202.tar.xz. It is usr-merged
# (./bin, ./sbin, ./lib are symlinks into ./usr), which tar reproduces faithfully; peacock-init
# still finds /sbin/init because that relative symlink resolves inside the flavor root.
#
# Compression is XZ, not gzip. `tar -xpf` auto-detects it, but only if the extracting tar has xz
# support — BusyBox needs CONFIG_FEATURE_SEAMLESS_XZ (on in `make defconfig`, which is what
# peacock-ports/base/busybox builds with). The explicit fallbacks below cover a tar without it, and
# the failure message names the real cause rather than a generic "extract failed".
set -u
W="${BP_WORK:-/tmp}"
bp_progress 70
dest="$ANS_target/flavors/$ANS_flavor"
src="$W/flavor-base.tar.xz"
mkdir -p "$dest" "$ANS_target/peacock/etc"

if tar -xpf "$src" -C "$dest" 2>/dev/null; then
	:
elif command -v xz >/dev/null 2>&1 && xz -dc "$src" | tar -xpf - -C "$dest"; then
	:
elif command -v xzcat >/dev/null 2>&1 && xzcat "$src" | tar -xpf - -C "$dest"; then
	:
elif command -v unxz >/dev/null 2>&1 && unxz -c "$src" | tar -xpf - -C "$dest"; then
	:
else
	bp_fail "extract failed — no XZ support in this environment's tar/busybox (need seamless xz, or an xz/xzcat/unxz applet)"
fi

printf '%s\n' "$ANS_flavor" > "$ANS_target/peacock/etc/active-flavor"
rm -f "$src"
bp_log "base extracted to /flavors/$ANS_flavor"
