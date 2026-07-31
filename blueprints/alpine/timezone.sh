#!/bin/sh
# alpine-minirootfs carries no zoneinfo whatsoever — the tzdata package installed by the account
# stage (which this stage `requires`) is what makes /usr/share/zoneinfo exist at all. Check before
# symlinking so a bad answer fails loudly here instead of leaving a dangling /etc/localtime.
# /etc/timezone alongside the symlink is Alpine's own convention (what setup-timezone writes).
set -u
run_in_target test -f "/usr/share/zoneinfo/$ANS_timezone" \
	|| bp_fail "unknown timezone: $ANS_timezone (is tzdata installed?)"
run_in_target ln -sf "/usr/share/zoneinfo/$ANS_timezone" /etc/localtime \
	|| bp_fail "could not set the timezone"
printf '%s\n' "$ANS_timezone" > "$ROOT/etc/timezone"
bp_log "timezone -> $ANS_timezone"
