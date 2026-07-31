#!/bin/sh
# alpine-minirootfs is a flat "./"-prefixed FHS archive (./bin ./etc ./usr ...), so it needs no
# --strip-components — verified against alpine-minirootfs-3.24.1-aarch64.tar.gz.
set -u
W="${BP_WORK:-/tmp}"
bp_progress 70
dest="$ANS_target/flavors/$ANS_flavor"
mkdir -p "$dest" "$ANS_target/peacock/etc"
tar -xpf "$W/flavor-base.tar.gz" -C "$dest" || bp_fail "extract failed"
printf '%s\n' "$ANS_flavor" > "$ANS_target/peacock/etc/active-flavor"
rm -f "$W/flavor-base.tar.gz"
bp_log "base extracted to /flavors/$ANS_flavor"
