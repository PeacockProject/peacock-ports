#!/bin/sh
# Alpine post-extract prep. This does far more than arch's prep-base.sh, because what we just
# unpacked is not an operating system: alpine-minirootfs is a ~4 MB container seed carrying only
# busybox + apk + musl. Two things follow from that, and both would brick the boot if ignored.
#
#   1. NO OPENRC. The seed's /etc/inittab already calls /sbin/openrc, but /sbin/openrc does not
#      exist. That matters beyond "no services": prp-install runs apply_flavor_glue on this root
#      AFTER us, and it probes for systemd, then openrc (/sbin/openrc-run, /sbin/openrc), then
#      runit. A bare minirootfs matches none of them, so NO /peacock/.flavor-ready signal gets
#      installed — and peacock-init (PID 1 on the base) declares the guest hung after 90 s and
#      drops to PRP recovery. We therefore install the signal ourselves, by two independent
#      routes, and apk-add openrc so the glue's own probe succeeds as well.
#   2. NO USERLAND. No zoneinfo, no shadow, no doas/sudo — nothing the OOBE stages need.
#
# INSTALL phase: $ROOT is the PEACOCK BASE, not this flavor, so run_in_target is useless here.
# Everything below addresses the flavor root by path, and chroots into it explicitly for apk.
set -u
bp_progress 75
root="$ANS_target/flavors/$ANS_flavor"
[ -d "$root/etc" ] || bp_fail "extracted rootfs looks wrong: no $root/etc"

# --- DNS ------------------------------------------------------------------------------------
# The seed ships no /etc/resolv.conf at all, so the systemd-resolved dangling-symlink trap can't
# bite here — but remove a symlink defensively anyway, or a copy would write THROUGH it into a
# /run that doesn't exist in the guest and the guest would silently have no DNS.
[ -L "$root/etc/resolv.conf" ] && rm -f "$root/etc/resolv.conf"
cp /etc/resolv.conf "$root/etc/resolv.conf" 2>/dev/null \
	|| bp_log "WARN: no host /etc/resolv.conf to copy; the OOBE refreshes it from the base later"

# --- guest contract: touch /peacock/.flavor-ready within 90 s -------------------------------
# /peacock is bind-mounted into the guest by peacock-init, so this path is live at guest boot.
#
# (a) The OpenRC service. Same shape as apply_flavor_glue's openrc branch, written unconditionally
#     so it is already in place the moment openrc lands below (and harmlessly inert if it doesn't).
mkdir -p "$root/etc/init.d" "$root/etc/runlevels/default"
cat > "$root/etc/init.d/peacock-flavor-ready" <<'EOF'
#!/sbin/openrc-run
description="Signal the Peacock base that this flavor finished booting"
depend() { after *; }
start() { : > /peacock/.flavor-ready 2>/dev/null || true; }
EOF
chmod 755 "$root/etc/init.d/peacock-flavor-ready"
ln -sf /etc/init.d/peacock-flavor-ready "$root/etc/runlevels/default/peacock-flavor-ready"

# (b) The belt-and-braces route, independent of openrc and of the network. peacock-init picks
#     /sbin/init (busybox, always present) as the guest's PID 1, and busybox init reads
#     /etc/inittab unconditionally. Appended at the end of the file so it runs after the stock
#     "::wait:/sbin/openrc default" line; kept as a script rather than an inline command because
#     busybox init only shells out for commands containing metacharacters.
cat > "$root/sbin/peacock-flavor-ready" <<'EOF'
#!/bin/sh
: > /peacock/.flavor-ready 2>/dev/null || true
EOF
chmod 755 "$root/sbin/peacock-flavor-ready"
if ! grep -q 'peacock-flavor-ready' "$root/etc/inittab" 2>/dev/null; then
	cat >> "$root/etc/inittab" <<'EOF'

# Peacock guest contract: tell the base (peacock-init, PID 1) that this flavor finished booting.
# Without this the base treats the guest as hung after 90s and drops to recovery.
::wait:/sbin/peacock-flavor-ready
EOF
fi
bp_progress 82

# --- turn the seed into a bootable Alpine ----------------------------------------------------
# alpine-base is the canonical "minirootfs -> real Alpine" metapackage (openrc, busybox-openrc,
# alpine-conf, ...); the rest is what the OOBE stages need and the seed lacks.
BASE_PKGS="alpine-base openrc openrc-init busybox-openrc busybox-mdev-openrc \
udev-init-scripts-openrc eudev eudev-openrc util-linux agetty-openrc shadow tzdata \
doas doas-sudo-shim ca-certificates musl-locales dbus dbus-openrc"

# Deliberately best-effort, NOT bp_fail: the install phase runs out of PRP, whose busybox exposes
# no `chroot` symlink (only the raw applet), so we may have no way to execute the guest's apk from
# here at all. The identical package set is re-applied idempotently by the OOBE's first stage
# (account.sh), which runs on the booted base where the runner's own chroot shim is guaranteed to
# work. Everything needed for the guest to actually BOOT is already handled above without apk.
CH=""
if command -v chroot >/dev/null 2>&1; then
	CH="chroot"
elif command -v busybox >/dev/null 2>&1 && busybox --list 2>/dev/null | grep -qx chroot; then
	CH="busybox chroot"
fi

if [ -z "$CH" ]; then
	bp_log "WARN: no chroot available in this environment; deferring the Alpine base package set to the OOBE"
else
	bp_log "installing the Alpine base package set into the guest"
	mkdir -p "$root/proc" "$root/dev"
	mounted=""
	mount -t proc proc "$root/proc" 2>/dev/null && mounted="$root/proc"
	mount -o bind /dev "$root/dev" 2>/dev/null && mounted="$mounted $root/dev"
	# shellcheck disable=SC2086
	if $CH "$root" /sbin/apk add --no-cache $BASE_PKGS >/dev/null 2>&1; then
		bp_log "Alpine base package set installed (openrc is now present for the flavor glue)"
	else
		bp_log "WARN: apk add failed here (network? no /proc?) — the OOBE retries it on first boot"
	fi
	# Always tear these down: a bind mount left under the target blocks prp-install's later
	# unmount of the whole target filesystem.
	for m in $mounted; do
		umount "$m" 2>/dev/null || umount -l "$m" 2>/dev/null || bp_log "WARN: could not unmount $m"
	done
fi

bp_progress 92
bp_log "base prepared at /flavors/$ANS_flavor"
