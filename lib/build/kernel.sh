# shellcheck shell=sh
# build_type = "kernel"
#
# arm64 (or $kernel_arch) kernel: a defconfig or in-port .config -> Image.gz +
# dtb -> $pkgdir/boot/{zImage,config,dtbs/...} (+ modules). Optionally a second,
# PRP-trimmed kernel when a PRP config is set -> staged into stage-prp/, which
# the harness packages as the <name>-prp subpackage (a PRP build dep).
#
# The port's ./build.sh sets:
#   kernel_defconfig   `make <defconfig>`     (or use kernel_config instead)
#   kernel_config      in-port .config file copied to .config
#                      (falls back to $KERNEL_CONFIG, exported by the harness
#                       from the manifest's kernel_config field)
#   kernel_dtb         dtb make target under arch/<arch>/boot/dts, no .dtb suffix
#                      e.g. "mediatek/oppo6765_20379" / "qcom/msm8953-xiaomi-daisy"
#   kernel_arch        default "arm64"
#   prp_kernel_config  in-port config for the recovery kernel (falls back to
#                      $PRP_KERNEL_CONFIG, exported from the manifest field)
# and MAY define these hooks (default no-ops), called after each config loads:
#   kernel_prepare_tree   one-time source/DTS fixups (before configuring)
#   kernel_configure      tweak .config for the full kernel
#   prp_configure         tweak .config for the PRP kernel
#
# Staging happens inside build() (not package()): the OS kernel must be staged
# BEFORE the PRP pass's `make clean` wipes its image. default_package() is a
# no-op; override package() in build.sh to add to the staged tree.
#
# NOTE: the single-kernel path is the proven one (oppo-a16). The dual path is
# correct-by-construction but unexercised — daisy uses its own verbatim build.sh.

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

# Stage the just-built kernel image + dtb + config (+ modules) into a tree.
# $1 = destination tree (e.g. "$pkgdir" or "stage-prp"); $2 = "modules" to also
# modules_install (OS kernel only).
_kernel_stage() {
  _dest="$1"; arch="$(_karch)"
  mkdir -p "$_dest/boot/dtbs/$(dirname "$kernel_dtb")"
  if [ -f "arch/$arch/boot/Image.gz" ]; then
    cp "arch/$arch/boot/Image.gz" "$_dest/boot/zImage"
  elif [ -f "arch/$arch/boot/Image" ]; then
    cp "arch/$arch/boot/Image" "$_dest/boot/zImage"
  else
    peacock_die "kernel image not found"
  fi
  dtb_out="arch/$arch/boot/dts/${kernel_dtb}.dtb"
  [ -s "$dtb_out" ] || peacock_die "DTB not built: $dtb_out"
  cp "$dtb_out" "$_dest/boot/dtbs/${kernel_dtb}.dtb"
  cp .config "$_dest/boot/config"
  if [ "${2:-}" = modules ] && grep -q '^CONFIG_MODULES=y' .config 2>/dev/null; then
    _kmake modules_install INSTALL_MOD_PATH="$_dest/usr"
  fi
}

kernel_prepare_tree() { :; }
kernel_configure() { :; }
prp_configure() { :; }

default_build() {
  : "${kernel_dtb:?kernel: set kernel_dtb in build.sh}"
  kernel_prepare_tree

  # --- full kernel -> $pkgdir (staged NOW, before any PRP clean) ---
  _kernel_load_config "${kernel_config:-${KERNEL_CONFIG:-}}"
  kernel_configure
  yes "" | _kmake olddefconfig
  _kmake -j"${jobs:-1}" Image.gz "${kernel_dtb}.dtb"
  grep -q '^CONFIG_MODULES=y' .config 2>/dev/null && _kmake -j"${jobs:-1}" modules || true
  _kernel_stage "$pkgdir" modules
  peacock_msg "staged OS kernel -> $pkgdir/boot/zImage"

  # --- PRP-trimmed kernel -> stage-prp/ (the <name>-prp subpackage) ---
  prp_cfg="${prp_kernel_config:-${PRP_KERNEL_CONFIG:-}}"
  if [ -n "$prp_cfg" ]; then
    _kmake clean || true
    _kernel_load_config "$prp_cfg"
    prp_configure
    yes "" | _kmake olddefconfig
    _kmake -j"${jobs:-1}" Image.gz "${kernel_dtb}.dtb"
    _kernel_stage stage-prp
    peacock_msg "staged PRP kernel -> stage-prp/boot/zImage"
  fi
}

# Staging is done in build() (must precede the PRP clean). Override package() in
# the port's build.sh to add to the already-staged $pkgdir tree.
default_package() { :; }

build() { default_build; }
package() { default_package; }
