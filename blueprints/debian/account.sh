#!/bin/sh
# Debian account stage. OOBE phase: $ROOT is the flavor root, so run_in_target = chroot into Debian.
#
# Two Debian-isms the Arch script doesn't cover:
#   * the admin group is `sudo`, not `wheel`;
#   * membership alone grants nothing — it only matters because sudo is installed and its sudoers
#     carries a rule for the group. So we make sure sudo exists and we write our OWN rule rather
#     than trusting whatever /etc/sudoers the image happened to ship.
set -u

# apt-get in a chroot has no init to talk to: policy-rc.d exiting 101 is the documented way to tell
# every maintainer script "do not start this service". Only needed on the install path below.
apt_guard_on() {
	run_in_target sh -c 'printf "#!/bin/sh\nexit 101\n" > /usr/sbin/policy-rc.d && chmod 755 /usr/sbin/policy-rc.d'
}
apt_guard_off() { run_in_target rm -f /usr/sbin/policy-rc.d 2>/dev/null || true; }

run_in_target getent group sudo >/dev/null 2>&1 || run_in_target groupadd sudo \
	|| bp_fail "could not create the sudo group"

# Desktop hardware access lives in supplementary groups on Debian; add only the ones this image
# actually defines so a missing group can't fail the whole useradd.
groups="sudo"
for g in audio video input render plugdev netdev bluetooth; do
	run_in_target getent group "$g" >/dev/null 2>&1 && groups="$groups,$g"
done

run_in_target useradd -m -s /bin/bash -G "$groups" "$ANS_user" || bp_fail "useradd failed"
printf '%s:%s' "$ANS_user" "$ANS_pass" | run_in_target chpasswd || bp_fail "chpasswd failed"

if ! run_in_target test -x /usr/bin/sudo; then
	bp_log "sudo missing from the base image — installing it"
	apt_guard_on
	run_in_target env DEBIAN_FRONTEND=noninteractive apt-get update >/dev/null 2>&1 \
		|| { apt_guard_off; bp_fail "apt-get update failed (no network?)"; }
	run_in_target env DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-recommends install sudo \
		|| { apt_guard_off; bp_fail "installing sudo failed"; }
	apt_guard_off
fi

# A syntax error anywhere under /etc/sudoers.d takes sudo out entirely, so validate the drop-in and
# throw it away if it doesn't parse rather than shipping a system nobody can administer.
run_in_target sh -c 'printf "%%sudo ALL=(ALL:ALL) ALL\n" > /etc/sudoers.d/90-peacock-admin && chmod 0440 /etc/sudoers.d/90-peacock-admin' \
	|| bp_fail "could not write the sudoers drop-in"
if run_in_target test -x /usr/sbin/visudo; then
	run_in_target /usr/sbin/visudo -cf /etc/sudoers.d/90-peacock-admin >/dev/null 2>&1 || {
		run_in_target rm -f /etc/sudoers.d/90-peacock-admin
		bp_fail "the sudoers drop-in did not validate — left unwritten"
	}
fi

bp_log "account $ANS_user created (admin via the sudo group)"
