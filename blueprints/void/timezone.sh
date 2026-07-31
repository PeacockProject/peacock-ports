#!/bin/sh
# tzdata ships in the Void rootfs, so /usr/share/zoneinfo is already populated. Check before
# symlinking so a bad answer fails loudly here instead of leaving a dangling /etc/localtime.
# The symlink is what Void's own docs prefer over the TIMEZONE= line in /etc/rc.conf (that one
# needs a reboot to take effect and is only read by runit's stage-1 hwclock script).
set -u
run_in_target test -f "/usr/share/zoneinfo/$ANS_timezone" || bp_fail "unknown timezone: $ANS_timezone"
run_in_target ln -sf "/usr/share/zoneinfo/$ANS_timezone" /etc/localtime \
	|| bp_fail "could not set the timezone"
bp_log "timezone -> $ANS_timezone"
