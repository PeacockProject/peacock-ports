#!/bin/sh
# Fedora timezone stage. /etc/localtime is a symlink into the zoneinfo tree — the link TEXT must be
# guest-absolute (/usr/share/zoneinfo/…), so create it host-side against $ROOT rather than through a
# chroot. `timedatectl set-timezone` is not an option: it needs a running systemd + dbus.
set -u
tz="$ANS_timezone"

# The base image already carries the full zoneinfo tree (tzdata is part of it), but verify instead
# of assuming — and only reach for the network if it really is missing.
if [ ! -e "$ROOT/usr/share/zoneinfo/$tz" ] && [ ! -d "$ROOT/usr/share/zoneinfo/Etc" ]; then
	bp_log "no zoneinfo in the flavor — installing tzdata"
	run_in_target /bin/sh -c 'PATH=/usr/sbin:/usr/bin:/sbin:/bin; exec dnf -y --setopt=install_weak_deps=False install tzdata' \
		|| bp_log "warning: tzdata install failed (no network?)"
fi

[ -e "$ROOT/usr/share/zoneinfo/$tz" ] || bp_fail "unknown timezone: $tz"
ln -sfn "/usr/share/zoneinfo/$tz" "$ROOT/etc/localtime" || bp_fail "could not set /etc/localtime"
bp_log "timezone -> $tz"
