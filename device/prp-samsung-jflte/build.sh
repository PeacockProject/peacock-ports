# shellcheck shell=sh
# prp-samsung-jflte — build the PRP recovery boot.img for jflte. prepare()
# (default) extracts the PRP master tarball (strip 1); build() runs PRP's make
# targets verbatim; package() stages the resulting boot image into $pkgdir.

build() {
  if [ ! -f Makefile ] || [ ! -f configs/jflte.env ]; then
    echo "Error: PRP sources not found after extraction"
    exit 1
  fi

  OUT_DIR="${OUT_DIR:-$(pwd)/out/jflte}"
  mkdir -p "$OUT_DIR"

  make initramfs TARGET=jflte OUT_DIR="$OUT_DIR"
  make bootimg TARGET=jflte OUT_DIR="$OUT_DIR"

  BOOTIMG="$OUT_DIR/prp-jflte-recovery.img"
  if [ ! -f "$BOOTIMG" ]; then
    echo "Error: expected PRP boot image not found at $BOOTIMG"
    exit 1
  fi
}

package() {
  OUT_DIR="${OUT_DIR:-$(pwd)/out/jflte}"
  BOOTIMG="$OUT_DIR/prp-jflte-recovery.img"
  mkdir -p "$pkgdir/usr/share/peacock/recovery"
  install -m 0644 "$BOOTIMG" "$pkgdir/usr/share/peacock/recovery/prp-samsung-jflte-recovery.img"
}
