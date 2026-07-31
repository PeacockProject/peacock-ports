#!/bin/sh
# Kali timezone stage. Kali follows Debian: the zone is recorded TWICE — the /etc/localtime symlink
# (what glibc reads) and /etc/timezone (the textual name tzdata's debconf owns). Setting only the
# symlink works until the next tzdata upgrade, which reconfigures from /etc/timezone and silently
# puts the clock back — so write both, then let tzdata reconcile them itself. On a rolling
# distribution that upgrade is not hypothetical.
set -u

if ! run_in_target test -d /usr/share/zoneinfo; then
	# The container image ships tzdata, but don't assume a stripped rebuild does.
	bp_log "no zoneinfo in the flavor — installing tzdata"
	run_in_target sh -c 'printf "#!/bin/sh\nexit 101\n" > /usr/sbin/policy-rc.d && chmod 755 /usr/sbin/policy-rc.d'
	run_in_target env DEBIAN_FRONTEND=noninteractive apt-get update >/dev/null 2>&1 \
		|| bp_fail "apt-get update failed (no network?)"
	run_in_target env DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-recommends install tzdata \
		|| bp_fail "installing tzdata failed"
	run_in_target rm -f /usr/sbin/policy-rc.d
fi

run_in_target test -e "/usr/share/zoneinfo/$ANS_timezone" || bp_fail "unknown timezone: $ANS_timezone"
run_in_target ln -sf "/usr/share/zoneinfo/$ANS_timezone" /etc/localtime || bp_fail "could not set /etc/localtime"
run_in_target sh -c "printf '%s\n' '$ANS_timezone' > /etc/timezone" || bp_fail "could not write /etc/timezone"

# Best effort: makes dpkg's view agree with the two files above. Non-fatal — in a chroot without a
# configured debconf this is a no-op, and the files we just wrote are already authoritative.
run_in_target env DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -f noninteractive tzdata >/dev/null 2>&1 || true

bp_log "timezone -> $ANS_timezone"
