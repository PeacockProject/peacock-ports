# shellcheck shell=sh
# peacock-oobe — one static musl binary: the headless --apply blueprint core AND the LVGL/fbdev
# first-boot UI. Mirrors PRP's build-gui.sh device build: fetch LVGL + lv_drivers, compile them with
# the vendored UI sources (prp_fbdev, fonts, oobe_wizard, oobe_uimain) + the blueprint engine, all
# static via zig cc. Port sources are flat (the builder copies only top-level files into the chroot).
LVGL_TAG="v8.3.11"
LVD_REF="release/v8.3"

build() {
  case "${ARCH:-arm64}" in
    arm64|aarch64)          ZIG_TARGET=aarch64-linux-musl ;;
    arm|armv7|armv7h|armhf) ZIG_TARGET=arm-linux-musleabihf ;;
    x86_64|amd64)           ZIG_TARGET=x86_64-linux-musl ;;
    *)                      ZIG_TARGET="${ARCH}-linux-musl" ;;
  esac
  export HOME=/tmp ZIG_GLOBAL_CACHE_DIR=/tmp/zig-cache ZIG_LOCAL_CACHE_DIR=/tmp/zig-cache

  echo "peacock-oobe: fetching LVGL ${LVGL_TAG} + lv_drivers ${LVD_REF}"
  curl -L --fail -o lvgl.tar.gz "https://codeload.github.com/lvgl/lvgl/tar.gz/refs/tags/${LVGL_TAG}"
  curl -L --fail -o lvd.tar.gz  "https://codeload.github.com/lvgl/lv_drivers/tar.gz/refs/heads/${LVD_REF}"
  tar -xzf lvgl.tar.gz
  tar -xzf lvd.tar.gz
  LVGL_DIR=$(find . -maxdepth 1 -type d -name 'lvgl-*' | head -1)
  LVD_DIR=$(find . -maxdepth 1 -type d -name 'lv_drivers-*' | head -1)
  [ -d "$LVGL_DIR" ] || { echo "lvgl source missing"; exit 1; }
  [ -d "$LVD_DIR" ]  || { echo "lv_drivers source missing"; exit 1; }

  # lv_drivers v8.3 evdev marks press only when tracking_id == 0; real panels use non-zero IDs.
  # Treat any non-negative tracking_id as pressed (same fix as PRP's build-gui.sh).
  if command -v perl >/dev/null 2>&1; then
    perl -0pi -e 's/else if\(in\.value == 0\)\s*evdev_button = LV_INDEV_STATE_PR;/else if(in.value != -1) evdev_button = LV_INDEV_STATE_PR;/' "$LVD_DIR/indev/evdev.c" || true
  fi

  # Include tree so third-party code can include "lvgl/lvgl.h" + "lv_drivers/...".
  INC=include
  rm -rf "$INC"; mkdir -p "$INC/lvgl"
  ln -snf "$(cd "$LVGL_DIR" && pwd)/lvgl.h" "$INC/lvgl/lvgl.h"
  ln -snf "$(cd "$LVGL_DIR" && pwd)/src" "$INC/lvgl/src"
  ln -snf "$(cd "$LVD_DIR" && pwd)" "$INC/lv_drivers"
  cp -a lv_conf.h "$INC/lv_conf.h"
  cp -a lv_drv_conf.h "$INC/lv_drv_conf.h"

  LVGL_SRCS=$(find "$LVGL_DIR/src" -type f -name '*.c' | sort)
  [ -n "$LVGL_SRCS" ] || { echo "lvgl sources not found"; exit 1; }

  echo "peacock-oobe: compiling (static ${ZIG_TARGET})"
  # shellcheck disable=SC2086
  zig cc -target "$ZIG_TARGET" -static -Os -ffunction-sections -fdata-sections \
    -Wl,--gc-sections -std=c11 -D_GNU_SOURCE -DLV_CONF_INCLUDE_SIMPLE=1 \
    -I"$INC" -I"$INC/lv_drivers" -I"$INC/lv_drivers/indev" -I. \
    $LVGL_SRCS \
    "$LVD_DIR/indev/evdev.c" \
    prp_fbdev.c pk_serif_30.c pk_serif_44.c pk_mono_16.c pk_mono_20.c \
    oobe_wizard.c oobe_uimain.c prp_touch.c \
    blueprint.c toml.c bp_verify.c tweetnacl.c main.c \
    -lm -lpthread \
    -o peacock-oobe
}

package() {
  install -Dm755 peacock-oobe "$pkgdir/sbin/peacock-oobe"
}
