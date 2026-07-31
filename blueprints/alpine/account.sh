#!/bin/sh
# Alpine account stage.
#
# It carries a second job: because nothing `requires` it, this is the FIRST OOBE stage to run, and
# so it is where the guest's core package set is (re)installed. That is deliberate — prep-base.sh
# already tried during the PRP install, but the install phase runs out of PRP whose busybox has no
# `chroot` symlink, so it may not have been able to run apk at all. Here the runner's own
# run_in_target (chroot "$ROOT") is guaranteed to work and the base is online. `apk add` on an
# already-installed package is a no-op, so running it twice costs nothing, and folding it into an
# existing stage keeps the wizard screens identical to every other flavor's.
#
# Provided by the runner: $ANS_user $ANS_pass, run_in_target, bp_log/bp_progress/bp_fail, $ROOT.
set -u

# The runner chroots into the flavor, so the flavor needs its own resolver config. The base is
# online at this point — hand it its DNS. Never write THROUGH a symlink into a /run the guest
# doesn't have.
[ -L "$ROOT/etc/resolv.conf" ] && rm -f "$ROOT/etc/resolv.conf"
cp /etc/resolv.conf "$ROOT/etc/resolv.conf" 2>/dev/null || true

bp_progress 10
bp_log "installing the Alpine base package set (openrc, shadow, tzdata, doas)"
run_in_target apk add --no-cache alpine-base openrc openrc-init busybox-openrc \
	busybox-mdev-openrc udev-init-scripts-openrc eudev eudev-openrc util-linux \
	agetty-openrc shadow tzdata doas doas-sudo-shim ca-certificates musl-locales \
	dbus dbus-openrc || bp_fail "apk add of the base package set failed (network?)"
bp_progress 50

# wheel is Alpine's admin group and ships in the minirootfs, but don't assume a future seed keeps
# it. (No `getent` on busybox — read the file.)
grep -q '^wheel:' "$ROOT/etc/group" 2>/dev/null || run_in_target addgroup wheel \
	|| bp_fail "could not create the wheel group"

# shadow's useradd is installed above; fall back to busybox adduser if it somehow isn't, so a
# failed package step can't leave the device with no account at all.
if run_in_target test -x /usr/sbin/useradd; then
	run_in_target useradd -m -s /bin/sh "$ANS_user" || bp_fail "useradd failed"
else
	run_in_target adduser -D -s /bin/sh "$ANS_user" || bp_fail "adduser failed"
fi
# Secondary group in a separate call so either shadow's usermod or busybox's addgroup can do it.
run_in_target sh -c "usermod -aG wheel '$ANS_user' 2>/dev/null || addgroup '$ANS_user' wheel" \
	|| bp_fail "could not add $ANS_user to wheel"

printf '%s:%s' "$ANS_user" "$ANS_pass" | run_in_target chpasswd || bp_fail "chpasswd failed"
bp_progress 80

# ACTUALLY grant privilege. The arch blueprint puts the user in wheel and stops there, which leaves
# them with no way to escalate at all. doas is Alpine's idiomatic tool (in main, tiny); the
# doas-sudo-shim installed above also provides a `sudo` command that forwards to it, so muscle
# memory keeps working. Append rather than overwrite, and go through the chroot so we follow
# Alpine's /etc/doas.conf -> /etc/doas.d/doas.conf symlink instead of clobbering it.
run_in_target sh -c \
	'grep -q "^permit persist :wheel" /etc/doas.conf 2>/dev/null || echo "permit persist :wheel" >> /etc/doas.conf' \
	|| bp_fail "could not write the doas rule"
# doas refuses to read a config writable by group or other.
run_in_target chmod 0644 /etc/doas.conf || true

bp_progress 100
bp_log "account $ANS_user created (wheel, doas)"
