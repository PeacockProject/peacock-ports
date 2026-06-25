#!/usr/bin/env bash
# pack-flavor-base.sh — producer for the on-device "flavor layer".
#
# Bootstraps a base-distro flavor (Arch/Alpine/Debian) with the distro's native
# tooling (via `peacock bootstrap-flavor`) and packs the result into a
# flavor-<flavor>-base feather package. Drop the .feather into the package store,
# then sign + index + upload it with the normal genmirror publish flow — it's an
# ordinary (large) package. On-device, prp-install lays it down with
#   ftr install --root <target>/flavors/<flavor> flavor-<flavor>-base
# so the phone needs NO pacman/apk/debootstrap.
#
# Ownership matters: a distro rootfs is root-owned with special files, so we pack
# with `sudo tar --numeric-owner` (Go's archive walker can't preserve uid/gid).
#
# Usage:
#   pack-flavor-base.sh --flavor arch --arch aarch64 --device xiaomi-daisy \
#                       [--init openrc] [--version YYYYMMDD] [--out <store>]
set -euo pipefail

FLAVOR="" ARCH="" DEVICE="" INIT="openrc" VERSION="" OUT_STORE=""
PEACOCK="${PEACOCK_BIN:-peacock}"

while [ $# -gt 0 ]; do
  case "$1" in
    --flavor)  FLAVOR="$2"; shift 2 ;;
    --arch)    ARCH="$2"; shift 2 ;;
    --device)  DEVICE="$2"; shift 2 ;;
    --init)    INIT="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --out)     OUT_STORE="$2"; shift 2 ;;
    *) echo "pack-flavor-base: unknown arg $1" >&2; exit 2 ;;
  esac
done

[ -n "$FLAVOR" ] || { echo "pack-flavor-base: --flavor required" >&2; exit 2; }
[ -n "$ARCH" ]   || { echo "pack-flavor-base: --arch required" >&2; exit 2; }
: "${OUT_STORE:=$HOME/.local/var/peacock/packages/$ARCH}"
# Date-stamp version by default; pass --version for reproducible names.
: "${VERSION:=$(date -u +%Y%m%d)}"

NAME="flavor-${FLAVOR}-base"
mkdir -p "$OUT_STORE"
STAGE="$(mktemp -d)"
trap 'sudo rm -rf "$STAGE" 2>/dev/null || true' EXIT
FILES="$STAGE/files"

echo "pack-flavor-base: bootstrapping $FLAVOR/$ARCH (device=${DEVICE:-none}, init=$INIT) …"
bootstrap_args=(--flavor "$FLAVOR" --arch "$ARCH" --init "$INIT" --out "$FILES")
[ -n "$DEVICE" ] && bootstrap_args+=(--device "$DEVICE")
"$PEACOCK" bootstrap-flavor "${bootstrap_args[@]}"

# layout=system: the feather's files/ tree overlays the install root verbatim —
# here that root is <target>/flavors/<flavor>, so the distro lands intact.
cat > "$STAGE/manifest.toml" <<EOF
[package]
name = "$NAME"
version = "$VERSION"
description = "$FLAVOR base-distro rootfs (the guest userland under /flavors/$FLAVOR). Bootstrapped with the distro's native tooling; install under <target>/flavors/$FLAVOR."

[install]
layout = "system"
EOF

FEATHER="$OUT_STORE/${NAME}-${VERSION}-1-${ARCH}.feather"
echo "pack-flavor-base: packing $FEATHER (ownership-preserving) …"
# manifest.toml (user-owned) + files/ (root-owned distro tree). --numeric-owner so
# uid/gid survive extraction on a device with a different passwd/group db.
sudo tar -czf "$FEATHER" --numeric-owner -C "$STAGE" manifest.toml files
sudo chown "$(id -u):$(id -g)" "$FEATHER"
echo "pack-flavor-base: done -> $FEATHER"
echo "  next: sign + index + upload with the genmirror publish flow."
