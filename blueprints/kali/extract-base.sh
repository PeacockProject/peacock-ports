#!/bin/sh
# Unpack the Kali base into /flavors/<flavor> on the target and record it as the active flavor.
# The image's members are "./bin", "./etc", … — a plain FHS root, so no --strip-components: the
# tarball must land with etc/ usr/ … directly under the flavor root or peacock-init finds no init.
set -u
W="${BP_WORK:-/tmp}"
bp_progress 70
dest="$ANS_target/flavors/$ANS_flavor"
mkdir -p "$dest" "$ANS_target/peacock/etc"
# -p keeps the setuid bits (sudo is 4755 in the image — losing that breaks the admin account).
tar -xpf "$W/flavor-base.tar.xz" -C "$dest" || bp_fail "extract failed"
[ -x "$dest/usr/lib/systemd/systemd" ] || bp_fail "no systemd in the extracted base — wrong archive?"
printf '%s\n' "$ANS_flavor" > "$ANS_target/peacock/etc/active-flavor"
rm -f "$W/flavor-base.tar.xz"
bp_log "base extracted to /flavors/$ANS_flavor"
