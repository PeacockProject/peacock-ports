#!/bin/sh
# Minimal post-extract prep. $ROOT here is the Peacock BASE, not the flavor, so everything below is
# plain path surgery on $ANS_target/flavors/$ANS_flavor — no chroot.
set -u
bp_progress 90
root="$ANS_target/flavors/$ANS_flavor"

# DNS. The image ships /etc/resolv.conf as a symlink to /var/run/netconfig/resolv.conf, which is
# dangling until netconfig runs. Copying onto a dangling ABSOLUTE symlink would resolve against the
# *installer's* root and silently write to the host's /var/run — so unlink it first, then drop a
# real file. Without this the guest has no DNS and the OOBE's package stages all fail.
rm -f "$root/etc/resolv.conf"
cp /etc/resolv.conf "$root/etc/resolv.conf" 2>/dev/null || true
if ! grep -q '^[[:space:]]*nameserver' "$root/etc/resolv.conf" 2>/dev/null; then
	printf '# populated by the OOBE from the running base\n' > "$root/etc/resolv.conf"
	bp_log "warning: installer has no nameserver — DNS will be filled in at first boot"
fi

# …and keep it a real file. openSUSE hands resolv.conf to netconfig, which nothing owns yet — but a
# desktop install pulls in NetworkManager, and netconfig would then clobber the file on first boot.
# An empty DNS policy is netconfig's documented "do not touch resolv.conf" setting. The guest's
# networking belongs to the Peacock base anyway.
if [ -f "$root/etc/sysconfig/network/config" ]; then
	sed -i 's/^NETCONFIG_DNS_POLICY=.*/NETCONFIG_DNS_POLICY=""/' "$root/etc/sysconfig/network/config" || true
fi

# Mountpoint for the base's /peacock (that is where the .flavor-ready readiness signal lands).
mkdir -p "$root/peacock"

bp_log "base prepared at /flavors/$ANS_flavor"
