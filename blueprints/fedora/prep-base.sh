#!/bin/sh
# Minimal post-extract prep. $ROOT here is the Peacock BASE, not the flavor, so everything below is
# plain path surgery on $ANS_target/flavors/$ANS_flavor — no chroot.
set -u
bp_progress 90
root="$ANS_target/flavors/$ANS_flavor"

# DNS. The image ships /etc/resolv.conf as a symlink to /run/systemd/resolve/stub-resolv.conf, which
# is dangling until systemd-resolved runs. Copying onto a dangling ABSOLUTE symlink would resolve
# against the *installer's* root and silently write to the host's /run — so unlink it first, then
# drop a real file. Without this the guest has no DNS and the OOBE's package stages all fail.
rm -f "$root/etc/resolv.conf"
cp /etc/resolv.conf "$root/etc/resolv.conf" 2>/dev/null || true
if ! grep -q '^[[:space:]]*nameserver' "$root/etc/resolv.conf" 2>/dev/null; then
	printf '# populated by the OOBE from the running base\n' > "$root/etc/resolv.conf"
	bp_log "warning: installer has no nameserver — DNS will be filled in at first boot"
fi

# …and keep it a real file: systemd-resolved is preset-enabled in this image and would replace it
# with the stub symlink on the guest's first boot. The guest's networking belongs to the Peacock
# base, so mask the unit; glibc's nsswitch falls through "resolve" (UNAVAIL) to plain "dns".
mkdir -p "$root/etc/systemd/system"
ln -sf /dev/null "$root/etc/systemd/system/systemd-resolved.service"

# Mountpoint for the base's /peacock (that is where the .flavor-ready readiness signal lands).
mkdir -p "$root/peacock"

bp_log "base prepared at /flavors/$ANS_flavor"
