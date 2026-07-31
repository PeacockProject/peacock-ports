#!/bin/sh
# Kali hostname stage. Kali inherits Debian's convention: the hostname lives in TWO places,
# /etc/hostname and a 127.0.1.1 line in /etc/hosts. The second one is not cosmetic — with no entry
# resolving the machine's own name, sudo, dbus and X sessions each block on a failed lookup first.
# The container image ships the placeholder "LXC_NAME" in both.
set -u

printf '%s\n' "$ANS_host" > "$ROOT/etc/hostname"

# Edit /etc/hosts from INSIDE the flavor: the thin Peacock base is not guaranteed to have sed (it
# runs no service manager and its busybox applet links may not be installed), while the flavor is a
# complete Kali by definition.
run_in_target sh -c "sed -i '/^127\\.0\\.1\\.1[[:space:]]/d' /etc/hosts && printf '127.0.1.1\t%s\n' '$ANS_host' >> /etc/hosts" \
	|| bp_fail "could not update /etc/hosts"

bp_log "hostname -> $ANS_host"
