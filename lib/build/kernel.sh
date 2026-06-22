# shellcheck shell=sh
# build_type = "kernel"
#
# arm64 (or $kernel_arch) kernel: a defconfig or in-port .config -> Image.gz +
# dtb -> $pkgdir/boot/{zImage,config,dtbs/...} (+ modules). Optionally a second,
# PRP-trimmed kernel when $prp_kernel_config is set -> $pkgdir/boot/zImage-prp.
#
# The port's ./build.sh sets:
#   kernel_defconfig   `make <defconfig>`     (or use kernel_config instead)
#   kernel_config      in-port .config file copied to .config
#   kernel_dtb         dtb make target under arch/<arch>/boot/dts, no .dtb suffix
#                      e.g. "mediatek/oppo6765_20379" / "qcom/msm8953-xiaomi-daisy"
#   kernel_arch        default "arm64"
#   prp_kernel_config  optional in-port config for the recovery kernel
# and MAY define these hooks (default no-ops), called after each config loads:
#   kernel_prepare_tree   one-time source/DTS fixups (before configuring)
#   kernel_configure      tweak .config for the full kernel
#   prp_configure         tweak .config for the PRP kernel
#
# NOTE: the dual (PRP) path is not yet validated against the daisy dual-kernel
# port — verify zImage-prp staging / appended-dtb + the -prp subpackage before
# migrating those. Single-kernel ports (no prp_kernel_config) are the proven path.

_karch() { printf '%s' "${kernel_arch:-arm64}"; }
_kmake() {
  set -- "ARCH=$(_karch)" "$@"
  [ -n "${CROSS_COMPILE:-}" ] && set -- "CROSS_COMPILE=$CROSS_COMPILE" "$@"
  make "$@"
}

# Strip baked-in compiler-capability symbols so they re-derive for the toolchain
# actually building here (an imported .config bakes in the original compiler's).
kernel_sanitize_config() {
  sed -i \
    -e '/^CONFIG_CC_VERSION_TEXT=/d' \
    -e '/^CONFIG_CC_IS_/d' \
    -e '/^CONFIG_GCC_VERSION=/d' \
    -e '/^CONFIG_CLANG_VERSION=/d' \
    -e '/^CONFIG_AS_IS_/d' \
    -e '/^CONFIG_AS_VERSION=/d' \
    -e '/^CONFIG_LD_IS_/d' \
    -e '/^CONFIG_LD_VERSION=/d' \
    -e '/^CONFIG_LLD_VERSION=/d' \
    -e '/^CONFIG_CC_HAS_/d' \
    -e '/^CONFIG_CC_CAN_/d' \
    -e '/^CONFIG_TOOLS_SUPPORT_RELR=/d' \
    .config 2>/dev/null || true
}

_kernel_load_config() {  # $1: optional config file; else use $kernel_defconfig
  if [ -n "$1" ]; then
    cp "$1" .config
  else
    _kmake "${kernel_defconfig:?kernel: set kernel_defconfig or kernel_config in build.sh}"
  fi
  kernel_sanitize_config
  # vendor kernels frequently -Werror against modern toolchains
  [ -x ./scripts/config ] && ./scripts/config --disable WERROR 2>/dev/null || true
  yes "" | _kmake olddefconfig
}

kernel_prepare_tree() { :; }
kernel_configure() { :; }
prp_configure() { :; }

build() {
  : "${kernel_dtb:?kernel: set kernel_dtb in build.sh}"
  kernel_prepare_tree

  # --- full kernel ---
  _kernel_load_config "${kernel_config:-}"
  kernel_configure
  yes "" | _kmake olddefconfig
  _kmake -j"${jobs:-1}" Image.gz "${kernel_dtb}.dtb"
  grep -q '^CONFIG_MODULES=y' .config 2>/dev/null && _kmake -j"${jobs:-1}" modules || true

  # --- PRP-trimmed kernel (optional) ---
  if [ -n "${prp_kernel_config:-}" ]; then
    _kmake clean || true
    _kernel_load_config "$prp_kernel_config"
    prp_configure
    yes "" | _kmake olddefconfig
    _kmake -j"${jobs:-1}" Image.gz "${kernel_dtb}.dtb"
    if [ -f "arch/$(_karch)/boot/Image.gz" ]; then
      cp "arch/$(_karch)/boot/Image.gz" .peacock-prp-image
    elif [ -f "arch/$(_karch)/boot/Image" ]; then
      cp "arch/$(_karch)/boot/Image" .peacock-prp-image
    fi
  fi
}

package() {
  arch="$(_karch)"
  mkdir -p "$pkgdir/boot/dtbs/$(dirname "$kernel_dtb")"

  if [ -f "arch/$arch/boot/Image.gz" ]; then
    cp "arch/$arch/boot/Image.gz" "$pkgdir/boot/zImage"
  elif [ -f "arch/$arch/boot/Image" ]; then
    cp "arch/$arch/boot/Image" "$pkgdir/boot/zImage"
  else
    peacock_die "kernel image not found"
  fi

  dtb_out="arch/$arch/boot/dts/${kernel_dtb}.dtb"
  [ -s "$dtb_out" ] || peacock_die "DTB not built: $dtb_out"
  cp "$dtb_out" "$pkgdir/boot/dtbs/${kernel_dtb}.dtb"
  cp .config "$pkgdir/boot/config"

  grep -q '^CONFIG_MODULES=y' .config 2>/dev/null && \
    _kmake modules_install INSTALL_MOD_PATH="$pkgdir/usr" || true

  [ -f .peacock-prp-image ] && cp .peacock-prp-image "$pkgdir/boot/zImage-prp"
  peacock_msg "staged $(ls -l "$pkgdir/boot/zImage" 2>/dev/null)"
}
