# shellcheck shell=sh
# prp-xiaomi-daisy — build the PRP recovery boot.img + PRP_ROOTFS overlay for
# daisy. prepare() (default) extracts PRP master (strip 1); build() runs PRP's
# make targets verbatim (the PRP-trimmed kernel + static busybox come from the
# ftr-installed build deps at /boot/zImage + /usr/bin/busybox); package() stages
# both images. daisy is non-monolithic, so the overlay ships as a separate image
# (flashed to boot_b) alongside the boot.img.

build() {
  if [ ! -f Makefile ] || [ ! -f configs/xiaomi-daisy.env ]; then
    echo "Error: PRP sources not found after extraction"
    exit 1
  fi
  OUT_DIR="${OUT_DIR:-$(pwd)/out/xiaomi-daisy}"
  mkdir -p "$OUT_DIR"

  # The PRP kernel + busybox were ftr-installed into this chroot as build deps;
  # point PRP's build at those installed paths.
  export KERNEL_IMAGE="${KERNEL_IMAGE:-/boot/zImage}"
  export BUSYBOX_STATIC="${BUSYBOX_STATIC:-/usr/bin/busybox}"

  make initramfs TARGET=xiaomi-daisy OUT_DIR="$OUT_DIR"
  make bootimg TARGET=xiaomi-daisy OUT_DIR="$OUT_DIR"
  if [ ! -f "$OUT_DIR/prp-xiaomi-daisy-recovery.img" ]; then
    echo "Error: expected PRP boot image not found"
    exit 1
  fi

  make overlay TARGET=xiaomi-daisy OUT_DIR="$OUT_DIR"
  if [ ! -f "$OUT_DIR/prp-rootfs.img" ]; then
    echo "Error: expected PRP overlay image not found"
    exit 1
  fi
}

package() {
  OUT_DIR="${OUT_DIR:-$(pwd)/out/xiaomi-daisy}"
  mkdir -p "$pkgdir/usr/share/peacock/recovery"
  install -m 0644 "$OUT_DIR/prp-xiaomi-daisy-recovery.img" \
    "$pkgdir/usr/share/peacock/recovery/prp-xiaomi-daisy-recovery.img"
  install -m 0644 "$OUT_DIR/prp-rootfs.img" \
    "$pkgdir/usr/share/peacock/recovery/prp-xiaomi-daisy-rootfs.img"
}
