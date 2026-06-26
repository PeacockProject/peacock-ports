#!/bin/sh
set -u
run_in_target useradd -m -G wheel "$ANS_user" || bp_fail "useradd failed"
printf '%s:%s' "$ANS_user" "$ANS_pass" | run_in_target chpasswd || bp_fail "chpasswd failed"
bp_log "account $ANS_user created"
