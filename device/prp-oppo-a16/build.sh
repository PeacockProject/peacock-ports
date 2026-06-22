# shellcheck shell=sh
# prp-oppo-a16 — build the PRP recovery boot.img for oppo-a16. prepare()
# (default) extracts the PRP master tarball (strip 1); build() runs PRP's make
# targets verbatim; package() stages the recovery image into $pkgdir.
# scripts/common.sh resolve_kernel_image picks up $KERNEL_IMAGE if set, else
# walks the peacock build-cache for linux-oppo-a16 outputs.

build() {
  if [ ! -f Makefile ] || [ ! -f configs/oppo-a16.env ]; then
    echo "Error: PRP sources not found after extraction"
    exit 1
  fi
  OUT_DIR="${OUT_DIR:-$(pwd)/out/oppo-a16}"
  mkdir -p "$OUT_DIR"

  make initramfs TARGET=oppo-a16 OUT_DIR="$OUT_DIR"
  make bootimg TARGET=oppo-a16 OUT_DIR="$OUT_DIR"

  BOOTIMG="$OUT_DIR/prp-oppo-a16-recovery.img"
  if [ ! -f "$BOOTIMG" ]; then
    echo "Error: expected PRP boot image not found at $BOOTIMG"
    exit 1
  fi
}

package() {
  OUT_DIR="${OUT_DIR:-$(pwd)/out/oppo-a16}"
  mkdir -p "$pkgdir/usr/share/peacock/recovery"
  install -m 0644 "$OUT_DIR/prp-oppo-a16-recovery.img" \
    "$pkgdir/usr/share/peacock/recovery/prp-oppo-a16-recovery.img"
}
