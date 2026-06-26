#!/bin/sh
set -u
run_in_target ln -sf "/usr/share/zoneinfo/$ANS_timezone" /etc/localtime || bp_fail "bad timezone"
bp_log "timezone -> $ANS_timezone"
