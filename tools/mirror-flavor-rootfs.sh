#!/usr/bin/env bash
# mirror-flavor-rootfs.sh — mirror a distro's rootfs tarball onto genmirror and print the
# url+sha256 to paste into that flavor's install.toml [archive] block.
#
# WHY THIS EXISTS: a flavor's install.toml pins a tarball URL + digest, and the digest is the trust
# anchor (the TOML is signed; the tarball is not). Pointing straight at an upstream URL is fragile —
# images.linuxcontainers.org prunes to the few most recent dated builds, so a pinned dated URL 404s
# within about a week, and a "latest" URL breaks the digest instead. So we mirror, exactly like the
# arch flavor already does.
#
#   ./tools/mirror-flavor-rootfs.sh debian https://…/rootfs.tar.xz [expected-sha256]
#
# Env: GENMIRROR_HOST (default lijiang_ts), GENMIRROR_ROOT, CHANNEL (stable), ARCH (aarch64),
#      GENMIRROR_URL (https://genmirror.peacockos.org), CACHE_DIR.
set -euo pipefail

ID="${1:-}"; SRC_URL="${2:-}"; EXPECT="${3:-}"
[ -n "$ID" ] && [ -n "$SRC_URL" ] || { sed -n '2,18p' "${BASH_SOURCE[0]}"; exit 2; }

HOST="${GENMIRROR_HOST:-lijiang_ts}"
CHANNEL="${CHANNEL:-stable}"
ARCH="${ARCH:-aarch64}"
GM_ROOT="${GENMIRROR_ROOT:-/home/tiel/sda1/peacock-services/caddy/config/genmirror}"
GM_URL="${GENMIRROR_URL:-https://genmirror.peacockos.org}"
CACHE="${CACHE_DIR:-${TMPDIR:-/tmp}/peacock-flavor-mirror}"
DEST_DIR="$GM_ROOT/flavors/$CHANNEL/$ARCH"

die() { printf 'mirror-flavor-rootfs: %s\n' "$*" >&2; exit 1; }

# Keep upstream's compression in the published name — tar auto-detects, but the extension should not
# lie about the bytes.
case "$SRC_URL" in
	*.tar.gz|*.tgz)   EXT=tar.gz ;;
	*.tar.xz)         EXT=tar.xz ;;
	*.tar.zst)        EXT=tar.zst ;;
	*.tar.bz2)        EXT=tar.bz2 ;;
	*)                die "unrecognised archive extension in $SRC_URL (expected .tar.{gz,xz,zst,bz2})" ;;
esac
NAME="$ID-base.$EXT"
mkdir -p "$CACHE"
LOCAL="$CACHE/$NAME"

printf 'fetching %s\n' "$SRC_URL"
curl -fL --retry 3 --retry-delay 2 -o "$LOCAL" "$SRC_URL" || die "download failed"
SUM="$(sha256sum "$LOCAL" | awk '{print $1}')"
SIZE="$(stat -c%s "$LOCAL")"
printf 'downloaded %s bytes, sha256 %s\n' "$SIZE" "$SUM"

# If the caller passed the upstream-published checksum, this is the integrity gate: it proves we
# mirrored the bytes upstream actually vouches for, not a truncated or MITM'd download.
if [ -n "$EXPECT" ]; then
	[ "$SUM" = "$EXPECT" ] || die "SHA256 MISMATCH — upstream says $EXPECT, got $SUM. Refusing to publish."
	printf 'digest matches the upstream-published checksum\n'
else
	printf 'WARNING: no expected sha256 given — publishing the bytes as downloaded, unverified against upstream\n'
fi

printf 'uploading to %s:%s/%s\n' "$HOST" "$DEST_DIR" "$NAME"
ssh "$HOST" "mkdir -p '$DEST_DIR'" || die "cannot reach $HOST"
rsync -a --partial "$LOCAL" "$HOST:$DEST_DIR/$NAME" || die "upload failed"

# Re-hash on the MIRROR so a corrupted transfer can't silently ship a tarball whose digest no longer
# matches what we're about to pin.
REMOTE_SUM="$(ssh "$HOST" "sha256sum '$DEST_DIR/$NAME'" | awk '{print $1}')"
[ "$REMOTE_SUM" = "$SUM" ] || die "post-upload digest mismatch on the mirror ($REMOTE_SUM != $SUM)"
printf 'verified on the mirror\n\n'

cat <<EOF
Paste into blueprints/$ID/install.toml:

[archive]
url    = "$GM_URL/flavors/$CHANNEL/$ARCH/$NAME"
sha256 = "$SUM"
EOF
