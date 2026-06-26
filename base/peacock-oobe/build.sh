# shellcheck shell=sh
# peacock-oobe — static musl C binary via zig cc (mirrors dropbear/PRP recovery profile). This
# builds the headless --apply core; the LVGL UI mode (P5) is added later. Sources are vendored in
# the port (no tarball), so prepare() is the default no-op; build() compiles, package() stages.
build() {
  case "${ARCH:-arm64}" in
    arm64|aarch64)          ZIG_TARGET=aarch64-linux-musl ;;
    arm|armv7|armv7h|armhf) ZIG_TARGET=arm-linux-musleabihf ;;
    x86_64|amd64)           ZIG_TARGET=x86_64-linux-musl ;;
    *)                      ZIG_TARGET="${ARCH}-linux-musl" ;;
  esac
  export HOME=/tmp ZIG_GLOBAL_CACHE_DIR=/tmp/zig-cache ZIG_LOCAL_CACHE_DIR=/tmp/zig-cache
  echo "Building static peacock-oobe for ${ZIG_TARGET} (ARCH=${ARCH:-?})..."
  zig cc -target "${ZIG_TARGET}" -O2 -std=c11 -D_GNU_SOURCE -static \
    -ffunction-sections -fdata-sections -Wl,--gc-sections \
    main.c blueprint.c toml.c bp_verify.c tweetnacl.c -o peacock-oobe
}

package() {
  install -Dm755 peacock-oobe "$pkgdir/sbin/peacock-oobe"
}
