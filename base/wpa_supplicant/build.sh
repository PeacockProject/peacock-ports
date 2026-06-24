# shellcheck shell=sh
# wpa_supplicant — static-musl Wi-Fi supplicant for PRP recovery.
#
# nl80211 (modern cfg80211 drivers) with a WEXT fallback, internal TLS + crypto
# (no openssl), linked statically against the libnl build_dep_package. Produces
# self-contained wpa_supplicant + wpa_cli that PRP's prp-net drives.

build() {
  case "${ARCH:-aarch64}" in
    arm64|aarch64)            ZIG_TARGET=aarch64-linux-musl ;;
    arm|armv7|armv7h|armhf)   ZIG_TARGET=arm-linux-musleabihf ;;
    x86_64|amd64)             ZIG_TARGET=x86_64-linux-musl ;;
    *)                        ZIG_TARGET="${ARCH}-linux-musl" ;;
  esac

  export HOME=/tmp
  export ZIG_GLOBAL_CACHE_DIR=/tmp/zig-cache ZIG_LOCAL_CACHE_DIR=/tmp/zig-cache

  cd wpa_supplicant

  cat > .config <<'EOF'
CONFIG_CTRL_IFACE=y
CONFIG_BACKEND=file
CONFIG_DRIVER_NL80211=y
CONFIG_DRIVER_WEXT=y
CONFIG_LIBNL32=y
CONFIG_TLS=internal
CONFIG_INTERNAL_LIBTOMMATH=y
EOF

  # libnl was staged into the chroot by build_dep_packages — find its headers,
  # static libs and pkg-config files at the standard /usr prefix.
  export PKG_CONFIG_PATH="/usr/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
  export CC="zig cc -target ${ZIG_TARGET}"
  export CFLAGS="-O2 -I/usr/include/libnl3"
  # pkg-config emits "-lnl-3" without "-L/usr/lib" (it treats /usr/lib as a
  # default path), but zig's cross target doesn't search the chroot's /usr/lib —
  # so point it there explicitly to find the libnl build_dep_package's static libs.
  export LDFLAGS="-static -L/usr/lib"

  echo "Building static-musl wpa_supplicant for ${ZIG_TARGET} (ARCH=${ARCH:-?})..."
  make -j"${jobs:-4}" wpa_supplicant wpa_cli
}

package() {
  cd "$builddir/wpa_supplicant"
  install -Dm0755 wpa_supplicant "$pkgdir/usr/sbin/wpa_supplicant"
  install -Dm0755 wpa_cli "$pkgdir/usr/bin/wpa_cli"
}
