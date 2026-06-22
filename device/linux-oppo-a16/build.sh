# shellcheck shell=sh
# linux-oppo-a16 — MTK 4.19 vendor kernel, built from public source.
#
# Sourced by /peacock-buildlib (default.sh + raw.sh) after the source is
# extracted into $builddir. Defines build()/package(); prepare() (extract)
# and the $pkgdir/$jobs/$ARCH/$CROSS_COMPILE contract come from the library.
#
# UNVERIFIED MTK 4.19 vendor build — knobs that may need iteration:
#   * defconfig: $OPPO_A16_DEFCONFIG overrides (tree also ships
#     oppo6765_20375_defconfig / oppo6765_21281_defconfig).
#   * toolchain: build.config.mtk.aarch64.gcc exists, so cross-GCC should work;
#     if it demands clang, switch the resolved toolchain.
#   * -Werror: MTK trees often -Werror vs modern GCC; relaxed below, may need
#     KCFLAGS += -Wno-error=...

_oppo_make() {
  # ARCH/CROSS_COMPILE flow through as make vars when set (empty = native).
  set -- "ARCH=${ARCH:-arm64}" "$@"
  [ -n "${CROSS_COMPILE:-}" ] && set -- "CROSS_COMPILE=$CROSS_COMPILE" "$@"
  make "$@"
}

build() {
  def="${OPPO_A16_DEFCONFIG:-oppo6765_defconfig}"
  dtb="mediatek/oppo6765_20379"

  peacock_msg "oppo-a16 kernel: defconfig=$def (MTK 4.19 vendor)"
  _oppo_make "$def"

  # Re-derive compiler-capability symbols for the toolchain building here.
  sed -i \
    -e '/^CONFIG_CC_VERSION_TEXT=/d' \
    -e '/^CONFIG_CC_IS_/d' \
    -e '/^CONFIG_GCC_VERSION=/d' \
    -e '/^CONFIG_CLANG_VERSION=/d' \
    -e '/^CONFIG_LD_IS_/d' \
    -e '/^CONFIG_LD_VERSION=/d' \
    -e '/^CONFIG_LLD_VERSION=/d' \
    -e '/^CONFIG_CC_HAS_/d' \
    -e '/^CONFIG_CC_CAN_/d' \
    .config 2>/dev/null || true
  [ -x ./scripts/config ] && ./scripts/config --disable WERROR 2>/dev/null || true
  yes "" | _oppo_make olddefconfig

  peacock_msg "building Image.gz + ${dtb}.dtb"
  _oppo_make -j"${jobs:-1}" Image.gz "${dtb}.dtb"

  if grep -q '^CONFIG_MODULES=y' .config 2>/dev/null; then
    _oppo_make -j"${jobs:-1}" modules || true
  fi
}

package() {
  dtb="mediatek/oppo6765_20379"
  mkdir -p "$pkgdir/boot/dtbs/mediatek"

  if [ -f arch/arm64/boot/Image.gz ]; then
    cp arch/arm64/boot/Image.gz "$pkgdir/boot/zImage"
  elif [ -f arch/arm64/boot/Image ]; then
    cp arch/arm64/boot/Image "$pkgdir/boot/zImage"
  else
    peacock_die "kernel image not found"
  fi

  dtb_out="arch/arm64/boot/dts/${dtb}.dtb"
  [ -s "$dtb_out" ] || peacock_die "DTB not built: $dtb_out"
  cp "$dtb_out" "$pkgdir/boot/dtbs/mediatek/oppo6765_20379.dtb"
  cp .config "$pkgdir/boot/config"

  if grep -q '^CONFIG_MODULES=y' .config 2>/dev/null; then
    _oppo_make modules_install INSTALL_MOD_PATH="$pkgdir/usr" || true
  fi
  peacock_msg "staged $(ls -l "$pkgdir/boot/zImage" 2>/dev/null)"
}
