# shellcheck shell=bash
build() {
  # peacock may export ARCH as "arm64" (android naming); zig wants "aarch64".
  case "${ARCH:-aarch64}" in
    aarch64|arm64)            ZT="aarch64-linux-musl" ;;
    armv7|armv7h|armhf|arm)   ZT="arm-linux-musleabihf" ;;
    x86_64|amd64)             ZT="x86_64-linux-musl" ;;
    *)                        ZT="${ARCH}-linux-musl" ;;
  esac
  export ZIG_GLOBAL_CACHE_DIR=/tmp/zig-cache ZIG_LOCAL_CACHE_DIR=/tmp/zig-cache
  export CC="zig cc -target ${ZT}"
  # osm0sis Makefile uses $(CROSS_COMPILE)$(CC); clear CROSS_COMPILE (zig is the
  # full cross toolchain) and pass CC explicitly so its `ifeq ($(CC),cc)` default
  # doesn't kick in.
  make CC="$CC" CROSS_COMPILE= LDFLAGS="-static" mkbootimg unpackbootimg
}
package() {
  install -Dm755 mkbootimg     "$pkgdir/usr/bin/mkbootimg"
  install -Dm755 unpackbootimg "$pkgdir/usr/bin/unpackbootimg"
}
