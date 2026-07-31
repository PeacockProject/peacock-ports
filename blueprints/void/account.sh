#!/bin/sh
# Void account stage.
#
# Void's base-container-full rootfs already ships shadow, sudo, tzdata, glibc-locales and
# ca-certificates, so unlike Alpine there is no bootstrap to do — but this is still the first OOBE
# stage to run (nothing `requires` it), so it refreshes the guest's resolver and re-asserts the
# package set idempotently. That re-assert is best-effort on purpose: everything it names is
# already installed, so a network hiccup here must not block account creation.
#
# Provided by the runner: $ANS_user $ANS_pass, run_in_target, bp_log/bp_progress/bp_fail, $ROOT.
set -u

# The runner chroots into the flavor, so the flavor needs its own resolver config. The base is
# online at this point — hand it its DNS. Never write THROUGH a symlink into a /run the guest
# doesn't have.
[ -L "$ROOT/etc/resolv.conf" ] && rm -f "$ROOT/etc/resolv.conf"
cp /etc/resolv.conf "$ROOT/etc/resolv.conf" 2>/dev/null || true

bp_progress 10
# -S syncs the remote index first; -y is the non-interactive assume-yes. No-op for packages the
# rootfs already carries, which is all of them today.
run_in_target xbps-install -Sy shadow sudo tzdata glibc-locales ca-certificates >/dev/null 2>&1 \
	|| bp_log "note: could not refresh the base package set (offline?) — it ships in the rootfs anyway"
bp_progress 40

# wheel is Void's admin group and exists in the rootfs (gid 4); don't assume a future rootfs keeps
# it. Void has full coreutils, so getent is available here.
run_in_target getent group wheel >/dev/null 2>&1 || run_in_target groupadd wheel \
	|| bp_fail "could not create the wheel group"

# bash is the rootfs's interactive shell of choice and is already installed.
run_in_target useradd -m -G wheel -s /bin/bash "$ANS_user" || bp_fail "useradd failed"
printf '%s:%s' "$ANS_user" "$ANS_pass" | run_in_target chpasswd || bp_fail "chpasswd failed"
bp_progress 75

# ACTUALLY grant privilege. The arch blueprint puts the user in wheel and stops there, which leaves
# them with no way to escalate — Void's stock /etc/sudoers has the %wheel rule commented out. A
# drop-in is cleaner than editing sudoers, and Void's sudoers already ends with
# "@includedir /etc/sudoers.d". sudo refuses to read a drop-in that is group- or world-writable, so
# the 0440 matters.
mkdir -p "$ROOT/etc/sudoers.d"
printf '%%wheel ALL=(ALL:ALL) ALL\n' > "$ROOT/etc/sudoers.d/10-peacock-wheel"
chmod 0440 "$ROOT/etc/sudoers.d/10-peacock-wheel"

bp_progress 100
bp_log "account $ANS_user created (wheel, sudo)"
