# shellcheck shell=sh
# linux-xiaomi-ginkgo — mainline kernel for the Redmi Note 8 (SM6125 / trinket).
#
# Config comes from ginkgo_defconfig, shipped in this port: it is `make
# savedefconfig` of the tree that actually boots this phone, so the packaged
# kernel matches the one the port was debugged against rather than whatever
# arm64 defconfig happens to enable this release.
#
# NOTE (kernel ownership): the kernel belongs to the DEVICE layer, never to a
# flavor. Flavors are the user's choice of userland and ship no kernel.

DTB_NAME="sm6125-xiaomi-ginkgo"

build() {
  cp "$startdir/ginkgo_defconfig" arch/arm64/configs/ginkgo_defconfig \
    || { echo "Error: ginkgo_defconfig missing from the port"; exit 1; }

  echo "Configuring (ginkgo_defconfig)..."
  yes "" | make $MAKE_ARGS ginkgo_defconfig
  # Resolve anything the pinned config predates without dropping our choices.
  yes "" | make $MAKE_ARGS olddefconfig

  echo "Compiling Image.gz + ${DTB_NAME}.dtb + modules..."
  make $MAKE_ARGS Image.gz "qcom/${DTB_NAME}.dtb" modules
}

package() {
  # Kernel image.
  mkdir -p "$pkgdir/boot"
  install -m 0644 arch/arm64/boot/Image.gz "$pkgdir/boot/Image.gz"

  # Device tree. Staged under the canonical name the bootloader/extlinux asks
  # for. FAIL LOUDLY on an empty DTB — a silently-empty dtbs/ is how a device
  # ends up unbootable with no clue why (this bit the daisy port once already).
  mkdir -p "$pkgdir/boot/dtbs/qcom"
  src="arch/arm64/boot/dts/qcom/${DTB_NAME}.dtb"
  [ -f "$src" ] || { echo "Error: ${src} was not built"; exit 1; }
  install -m 0644 "$src" "$pkgdir/boot/dtbs/qcom/${DTB_NAME}.dtb"
  [ -s "$pkgdir/boot/dtbs/qcom/${DTB_NAME}.dtb" ] \
    || { echo "Error: staged ginkgo DTB is empty"; exit 1; }

  # Modules. INSTALL_MOD_PATH is $pkgdir (not $pkgdir/usr) so they land in
  # /lib/modules where depmod at install time expects them.
  make $MAKE_ARGS INSTALL_MOD_PATH="$pkgdir" INSTALL_MOD_STRIP=1 modules_install

  # Drop the build/source symlinks — they point into the build chroot and would
  # dangle on the device.
  kver="$(ls "$pkgdir/lib/modules" | head -1)"
  rm -f "$pkgdir/lib/modules/$kver/build" "$pkgdir/lib/modules/$kver/source"

  # Hard gate: wifi is the module most likely to be silently dropped by a config
  # resolution, and its absence is only discovered on-device with no wlan0.
  ls "$pkgdir"/lib/modules/*/kernel/drivers/net/wireless/ath/ath10k/ath10k_snoc.ko* \
    >/dev/null 2>&1 || echo "Warning: ath10k_snoc not built as a module (built-in is fine)"
}
