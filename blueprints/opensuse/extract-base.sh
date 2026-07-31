#!/bin/sh
# Unpack the base into /flavors/opensuse. The linuxcontainers rootfs.tar.xz is a plain FHS root
# (members are ./bin, ./etc, ./usr … with no wrapper directory), so no --strip-components — and
# `tar -xpf` sniffs the compression, so .xz needs no extra flag.
set -u
W="${BP_WORK:-/tmp}"
bp_progress 70
dest="$ANS_target/flavors/$ANS_flavor"
mkdir -p "$dest" "$ANS_target/peacock/etc"
tar -xpf "$W/flavor-base.tar.xz" -C "$dest" || bp_fail "extract failed"

# Sanity-gate the archive shape before we commit to it: if a future image ever nests the root under
# a wrapper dir, everything downstream (init detection, the .flavor-ready glue, the OOBE chroot)
# fails in confusing ways — better to say so here.
[ -d "$dest/usr" ] && [ -d "$dest/etc" ] || bp_fail "extracted tree is not an FHS root (no usr//etc/) — archive layout changed"
[ -x "$dest/usr/lib/systemd/systemd" ] || bp_fail "no /usr/lib/systemd/systemd in the base — the flavor glue would install no readiness signal"

printf '%s\n' "$ANS_flavor" > "$ANS_target/peacock/etc/active-flavor"
rm -f "$W/flavor-base.tar.xz"
bp_log "base extracted to /flavors/$ANS_flavor"
