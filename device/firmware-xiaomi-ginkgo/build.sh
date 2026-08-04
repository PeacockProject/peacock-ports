# shellcheck shell=sh
# firmware-xiaomi-ginkgo — stage the ginkgo vendor firmware into $pkgdir.
# prepare() (default) extracts the tarball (strip 1); no compile step.
#
# The tarball is already laid out as /lib/firmware, so the blob trees are copied
# across wholesale. The extraction script + manifest ride along so a device on a
# different ROM can regenerate the ROM-specific pieces (see package.toml).

package() {
  mkdir -p "$pkgdir/lib/firmware"

  # Blob trees, exactly as the kernel's firmware loader expects them:
  #   qcom/    modem + adsp (q6v5_pas), venus-5.4, a610 zap, a630 sqe, sm6125 qup
  #   ath10k/  WCN3990 board-2.bin + the deliberate firmware-5.bin stub
  #   qca/     WCN3950 bluetooth (crbtfw12/crnv12, renamed from the vendor's 21)
  #   novatek/ NT36672A touch, Tianma + EBBG panel variants
  for d in qcom ath10k qca novatek; do
    [ -d "$d" ] || { echo "Error: expected firmware tree '$d' missing from the source"; exit 1; }
    cp -a "$d" "$pkgdir/lib/firmware/"
  done

  # Keep the extractor available on-device: the a610 zap shader is re-signed per
  # ROM, so on a build other than the one these blobs came from the GPU may need
  # a locally-extracted copy.
  mkdir -p "$pkgdir/usr/share/peacock/firmware/ginkgo"
  for f in extract-firmware.sh firmware-manifest.txt README.md; do
    [ -f "$f" ] && install -m 0644 "$f" "$pkgdir/usr/share/peacock/firmware/ginkgo/"
  done
  [ -f "$pkgdir/usr/share/peacock/firmware/ginkgo/extract-firmware.sh" ] \
    && chmod 0755 "$pkgdir/usr/share/peacock/firmware/ginkgo/extract-firmware.sh"

  # Sanity gate: the firmware everything else depends on must actually be here.
  # A silently-empty /lib/firmware means no modem, wifi, video or GPU, and the
  # install would still look successful.
  for must in \
    lib/firmware/qcom/ginkgo/modem.mdt \
    lib/firmware/qcom/ginkgo/adsp.mdt \
    lib/firmware/qcom/venus-5.4/venus.mbn \
    lib/firmware/ath10k/WCN3990/hw1.0/board-2.bin \
    lib/firmware/qca/crbtfw12.tlv \
    lib/firmware/novatek/nt36672a-ginkgo.fw; do
    [ -s "$pkgdir/$must" ] || { echo "Error: $must missing or empty in the staged package"; exit 1; }
  done
}
