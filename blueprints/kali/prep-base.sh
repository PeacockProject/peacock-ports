#!/bin/sh
# Post-extract prep for the Kali flavor base — the few things that must be true BEFORE the guest is
# ever booted or the OOBE runs. INSTALL phase, so $ROOT is the Peacock base: run_in_target would
# chroot into the wrong tree and every path below is addressed directly instead.
set -u
bp_progress 90
root="$ANS_target/flavors/$ANS_flavor"
[ -d "$root/etc" ] || bp_fail "no /etc under $root — extraction looks wrong"

# --- DNS ----------------------------------------------------------------------------------------
# Kali's image ships a REAL /etc/resolv.conf, which is worse than the symlink Debian's ships: it is
# a leftover copy of the build host's systemd-resolved stub ("nameserver 127.0.0.53", "search
# incus") and Kali does not even install systemd-resolved, so nothing will ever listen there. A
# "create it only if missing" check would keep that file and the guest would resolve nothing.
# Overwrite unconditionally; rm first in case a rebuild switches to the symlink form, since writing
# through a link into /run would land in the *installer's* /run instead of the guest.
rm -f "$root/etc/resolv.conf"
if grep -qE '^[[:space:]]*nameserver[[:space:]]+[0-9a-fA-F.:]+' /etc/resolv.conf 2>/dev/null &&
	! grep -qE '^[[:space:]]*nameserver[[:space:]]+127\.' /etc/resolv.conf 2>/dev/null; then
	cp /etc/resolv.conf "$root/etc/resolv.conf" || bp_fail "could not write the flavor's resolv.conf"
else
	printf 'nameserver 1.1.1.1\nnameserver 9.9.9.9\n' > "$root/etc/resolv.conf"
	bp_log "installer has no usable resolver — using public DNS in the flavor"
fi

# --- systemd's "first boot" trap ----------------------------------------------------------------
# The image's /etc/machine-id holds the literal string "uninitialized", which is systemd's marker
# for a never-booted system: ConditionFirstBoot fires and systemd-firstboot.service PROMPTS on the
# console for locale/keymap/timezone/root password. Our OOBE already asks all of that, and a prompt
# nobody answers keeps the guest from ever touching /peacock/.flavor-ready — the base then calls the
# boot hung after 90 s and drops to recovery. Give the install its own id (it also has to be unique
# per device, this rootfs is a clone) and mask the unit as belt-and-braces.
uuid="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || true)"
case "$uuid" in
	?*) printf '%s\n' "$uuid" | tr -d '-' > "$root/etc/machine-id" ;;
	*)  bp_log "WARN: no kernel UUID source — leaving machine-id uninitialized" ;;
esac
mkdir -p "$root/etc/systemd/system"
ln -sf /dev/null "$root/etc/systemd/system/systemd-firstboot.service"

# --- identity -----------------------------------------------------------------------------------
# The image ships the container placeholder "LXC_NAME" in both files. The OOBE hostname stage
# rewrites them, but it may not have run yet (or may be skipped), and Kali (like Debian) resolves
# its own name through /etc/hosts — an unresolvable hostname makes sudo and X sessions stall on
# lookups. Kali's stock hostname is "kali"; keep the Peacock default so every flavor behaves alike.
printf 'peacock\n' > "$root/etc/hostname"
cat > "$root/etc/hosts" <<'EOF'
127.0.0.1	localhost
127.0.1.1	peacock
::1		localhost ip6-localhost ip6-loopback
ff02::1		ip6-allnodes
ff02::2		ip6-allrouters
EOF

bp_log "base prepared at /flavors/$ANS_flavor (systemd guest)"
