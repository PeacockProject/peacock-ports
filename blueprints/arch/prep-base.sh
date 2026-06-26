#!/bin/sh
set -u
bp_progress 90
root="$ANS_target/flavors/$ANS_flavor"
[ -f "$root/etc/resolv.conf" ] || cp /etc/resolv.conf "$root/etc/resolv.conf" 2>/dev/null || true
bp_log "base prepared at /flavors/$ANS_flavor"
