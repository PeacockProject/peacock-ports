#!/bin/sh
set -u
bp_progress 70
dest="$ANS_target/flavors/$ANS_flavor"
mkdir -p "$dest" "$ANS_target/peacock/etc"
tar -xpf /tmp/flavor-base.tar.gz -C "$dest" || bp_fail "extract failed"
printf '%s\n' "$ANS_flavor" > "$ANS_target/peacock/etc/active-flavor"
rm -f /tmp/flavor-base.tar.gz
bp_log "base extracted to /flavors/$ANS_flavor"
