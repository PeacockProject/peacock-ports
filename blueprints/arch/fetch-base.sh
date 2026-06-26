#!/bin/sh
# Download + digest-verify the flavor base tarball. The runner exports the (trusted, because the
# TOML is signed) $BP_ARCHIVE_URL + $BP_ARCHIVE_SHA256 from install.toml's [archive] block.
set -u
# Stage on $BP_WORK if the caller sets it (e.g. the installer points it at the target disk so a big
# base tarball doesn't fill a RAM tmpfs); default /tmp.
W="${BP_WORK:-/tmp}"
mkdir -p "$W"
bp_progress 35
bp_log "fetching the base rootfs"
curl -fsSL "$BP_ARCHIVE_URL" -o "$W/flavor-base.tar.gz" || wget -q -O "$W/flavor-base.tar.gz" "$BP_ARCHIVE_URL" \
	|| bp_fail "download failed ($BP_ARCHIVE_URL)"
echo "$BP_ARCHIVE_SHA256  $W/flavor-base.tar.gz" | sha256sum -c - >/dev/null 2>&1 \
	|| bp_fail "base archive digest mismatch — refusing to install"
bp_log "base archive verified"
