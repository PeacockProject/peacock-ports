#!/bin/sh
set -u
printf '%s\n' "$ANS_host" > "$ROOT/etc/hostname"
bp_log "hostname -> $ANS_host"
