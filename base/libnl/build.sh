# shellcheck shell=sh
# libnl — static netlink library for cross builds, compiled with zig cc against
# musl. Only the static .a + headers + pkg-config files are needed (by
# wpa_supplicant's nl80211 driver), so shared libs and the CLI tools are off.

build() {
  case "${ARCH:-aarch64}" in
    arm64|aarch64)            ZIG_TARGET=aarch64-linux-musl ;;
    arm|armv7|armv7h|armhf)   ZIG_TARGET=arm-linux-musleabihf ;;
    x86_64|amd64)             ZIG_TARGET=x86_64-linux-musl ;;
    *)                        ZIG_TARGET="${ARCH}-linux-musl" ;;
  esac

  export HOME=/tmp
  export ZIG_GLOBAL_CACHE_DIR=/tmp/zig-cache ZIG_LOCAL_CACHE_DIR=/tmp/zig-cache
  export CC="zig cc -target ${ZIG_TARGET}"
  export CFLAGS="-O2 -fno-omit-frame-pointer"

  echo "Configuring static libnl for ${ZIG_TARGET} (ARCH=${ARCH:-?})..."
  ./configure \
    --host="${ZIG_TARGET}" \
    --prefix=/usr \
    --enable-static --disable-shared \
    --disable-cli

  make -j"${jobs:-4}"
}

package() {
  make install DESTDIR="$pkgdir"
}
