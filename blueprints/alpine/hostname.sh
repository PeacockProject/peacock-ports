#!/bin/sh
# $ROOT is the flavor root in the OOBE phase, so a plain write is enough — no chroot needed.
set -u
printf '%s\n' "$ANS_host" > "$ROOT/etc/hostname"
bp_log "hostname -> $ANS_host"
