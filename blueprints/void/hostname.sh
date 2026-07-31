#!/bin/sh
# $ROOT is the flavor root in the OOBE phase, so a plain write is enough — no chroot needed.
# /etc/hostname is what Void's own docs prefer over the HOSTNAME= line in /etc/rc.conf.
set -u
printf '%s\n' "$ANS_host" > "$ROOT/etc/hostname"
bp_log "hostname -> $ANS_host"
