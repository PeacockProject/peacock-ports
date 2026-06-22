# shellcheck shell=sh
# firmware-xiaomi-daisy — stage the daisy GPU zap firmware blobs from the
# extracted firmware tree into $pkgdir. prepare() (default) extracts the
# tarball (strip 1); no compile step.

package() {
  mkdir -p "$pkgdir/lib/firmware/qcom/msm8953/xiaomi/daisy"
  install -m 0644 gpu/a506_zap.b02 "$pkgdir/lib/firmware/qcom/msm8953/xiaomi/daisy/"
  install -m 0644 gpu/a506_zap.mdt "$pkgdir/lib/firmware/qcom/msm8953/xiaomi/daisy/"
}
