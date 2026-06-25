# shellcheck shell=sh
# feather (ftr) — the Peacock package manager + trust keyring. Built fully static
# against musl via zig cc so it runs on-device (PRP / installer) with no glibc.
# prepare() (default) extracts the upstream tarball (strip 1); build() cross-
# compiles ftr; package() installs /usr/bin/ftr.

build() {
  # Map the kernel-style $ARCH the build injects to a zig musl target.
  case "${ARCH:-aarch64}" in
    arm64|aarch64)            ZIG_TARGET=aarch64-linux-musl ;;
    arm|armv7|armv7h|armhf)   ZIG_TARGET=arm-linux-musleabihf ;;
    x86_64|amd64)             ZIG_TARGET=x86_64-linux-musl ;;
    *)                        ZIG_TARGET="${ARCH}-linux-musl" ;;
  esac
  export ZIG_GLOBAL_CACHE_DIR=/tmp/zig-cache ZIG_LOCAL_CACHE_DIR=/tmp/zig-cache
  echo "Building feather (ftr) static for ${ZIG_TARGET} (ARCH=${ARCH:-?})..."
  make clean >/dev/null 2>&1 || true
  make build CC="zig cc -target ${ZIG_TARGET}"
}

package() {
  mkdir -p "$pkgdir/usr/bin"
  install -m 0755 ftr "$pkgdir/usr/bin/ftr"
}
