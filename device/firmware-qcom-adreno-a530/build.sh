# shellcheck shell=sh
# firmware-qcom-adreno-a530 — stage the Adreno A530 GPU firmware blobs from the
# extracted linux-firmware tree into $pkgdir. prepare() (default) extracts the
# tarball (strip 1); no compile step.

package() {
  mkdir -p "$pkgdir/lib/firmware/qcom"
  install -m 0644 qcom/a530_pm4.fw "$pkgdir/lib/firmware/qcom/"
  install -m 0644 qcom/a530_pfp.fw "$pkgdir/lib/firmware/qcom/"
}
