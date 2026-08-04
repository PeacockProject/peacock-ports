# shellcheck shell=sh
# firmware-xiaomi-ginkgo — stage the extractor + manifest. There is no compile
# step and, deliberately, no firmware payload: the blobs are pulled off the
# device's own partitions by hooks/post-install.sh. prepare() (default) extracts
# the ginkgo-firmware tarball (strip 1).

package() {
  mkdir -p "$pkgdir/usr/share/peacock/firmware/ginkgo"
  install -m 0755 extract-firmware.sh   "$pkgdir/usr/share/peacock/firmware/ginkgo/"
  install -m 0644 firmware-manifest.txt "$pkgdir/usr/share/peacock/firmware/ginkgo/"
  install -m 0644 README.md             "$pkgdir/usr/share/peacock/firmware/ginkgo/"

  # /lib/firmware must exist for the hook to extract into, and for the kernel's
  # firmware loader to search even when extraction was skipped.
  mkdir -p "$pkgdir/lib/firmware"

  # Guard against ever shipping blobs by accident: this package must contain
  # only text. If a future edit stages a vendor file, fail the build loudly
  # rather than publish unlicensed firmware to the mirror.
  found=$(find "$pkgdir" -type f \
    \( -name '*.mbn' -o -name '*.mdt' -o -name '*.b[0-9][0-9]' \
       -o -name '*.tlv' -o -name '*.elf' -o -name '*.fw' -o -name '*.bin' \) \
    -print 2>/dev/null | head -5)
  if [ -n "$found" ]; then
    echo "Error: firmware-xiaomi-ginkgo must not contain vendor blobs; found:" >&2
    echo "$found" >&2
    exit 1
  fi
}
