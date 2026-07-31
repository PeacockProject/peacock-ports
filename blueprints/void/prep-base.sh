#!/bin/sh
# Void post-extract prep.
#
# THE IMPORTANT PART: Void boots with runit, and runit is the init system the guest contract has
# the most trouble with. prp-install's apply_flavor_glue is what normally bakes in the
# /peacock/.flavor-ready signal that peacock-init (PID 1 on the base) waits 90 s for — and older
# glue only probed for systemd and OpenRC. A runit guest matched neither, got no signal, and the
# base declared the boot hung and dropped to PRP recovery every single time. Current prp-install
# does have a runit branch, but the glue that actually runs is whatever is baked into the PRP image
# on the device, which may predate it — so this script installs the service itself rather than
# relying on it. The shape below is deliberately identical to the glue's runit branch, so when both
# run the second is a no-op rewrite instead of a conflict.
#
# Everything else Void needs is already in the tarball: base-container-full ships runit, runit-void,
# shadow, sudo, tzdata, glibc-locales, ca-certificates and eudev. Unlike Alpine there is no
# bootstrap to do here.
#
# INSTALL phase: $ROOT is the PEACOCK BASE, not this flavor, so run_in_target is useless here.
set -u
bp_progress 80
root="$ANS_target/flavors/$ANS_flavor"
[ -d "$root/etc/runit" ] || bp_fail "extracted rootfs looks wrong: no $root/etc/runit (not a Void rootfs?)"

# --- DNS ------------------------------------------------------------------------------------
# The Void rootfs ships no /etc/resolv.conf, so there's no systemd-resolved dangling-symlink trap
# here — remove a symlink defensively anyway, or a copy would write THROUGH it into a /run the
# guest doesn't have and the guest would silently have no DNS.
[ -L "$root/etc/resolv.conf" ] && rm -f "$root/etc/resolv.conf"
cp /etc/resolv.conf "$root/etc/resolv.conf" 2>/dev/null \
	|| bp_log "WARN: no host /etc/resolv.conf to copy; the OOBE refreshes it from the base later"

# --- guest contract: touch /peacock/.flavor-ready within 90 s -------------------------------
# /peacock is bind-mounted into the guest by peacock-init, so this path is live at guest boot.
# runit restarts any supervised service whose run script exits, so signal once and then idle
# rather than churning a respawn loop for the life of the session. (`sleep infinity` isn't
# portable to a busybox sleep — loop instead.)
mkdir -p "$root/etc/sv/peacock-flavor-ready" "$root/etc/runit/runsvdir/default"
cat > "$root/etc/sv/peacock-flavor-ready/run" <<'EOF'
#!/bin/sh
exec 2>&1
: > /peacock/.flavor-ready 2>/dev/null || true
while :; do sleep 3600; done
EOF
chmod 755 "$root/etc/sv/peacock-flavor-ready/run"
# Enabling a runit service = symlinking it into the active runsvdir. runsvdir scans that directory
# and starts everything in it, so this is all "enable" means on Void.
ln -sf /etc/sv/peacock-flavor-ready "$root/etc/runit/runsvdir/default/peacock-flavor-ready"

bp_progress 92
bp_log "base prepared at /flavors/$ANS_flavor (runit flavor-ready service installed)"
