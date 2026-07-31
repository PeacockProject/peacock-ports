#!/bin/sh
# Host-side on purpose: /etc/hostname and /etc/hosts are plain files inside the flavor, so there is
# nothing to gain from a chroot here.
set -u
printf '%s\n' "$ANS_host" > "$ROOT/etc/hostname"

# Keep the name locally resolvable. Without it sudo, GNOME/KDE session startup and half the desktop
# stack each burn a DNS timeout on "unable to resolve host <name>".
if [ -f "$ROOT/etc/hosts" ]; then
	grep -q "[[:space:]]$ANS_host\$" "$ROOT/etc/hosts" 2>/dev/null \
		|| printf '127.0.0.1\t%s\n' "$ANS_host" >> "$ROOT/etc/hosts"
else
	printf '127.0.0.1\tlocalhost\n::1\tlocalhost\n127.0.0.1\t%s\n' "$ANS_host" > "$ROOT/etc/hosts"
fi
bp_log "hostname -> $ANS_host"
