# shellcheck shell=sh
# firmware-xiaomi-daisy — stage the daisy firmware blobs (GPU zap + wcnss/wifi)
# from the extracted firmware tree into $pkgdir. prepare() (default) extracts the
# tarball (strip 1); no compile step.

package() {
  # GPU (Adreno a506) zap shader.
  mkdir -p "$pkgdir/lib/firmware/qcom/msm8953/xiaomi/daisy"
  install -m 0644 gpu/a506_zap.b02 "$pkgdir/lib/firmware/qcom/msm8953/xiaomi/daisy/"
  install -m 0644 gpu/a506_zap.mdt "$pkgdir/lib/firmware/qcom/msm8953/xiaomi/daisy/"

  # WCNSS/Pronto wifi firmware. The mainline qcom_wcnss remoteproc loads
  # "wcnss.mdt" (+ its wcnss.bNN segments) from /lib/firmware (no DT override on
  # daisy), and wcn36xx loads the NV/board file from /lib/firmware/wlan/prima/.
  if [ -d wcnss ]; then
    install -m 0644 wcnss/wcnss.mdt "$pkgdir/lib/firmware/"
    for b in wcnss/wcnss.b*; do
      [ -f "$b" ] && install -m 0644 "$b" "$pkgdir/lib/firmware/"
    done
    mkdir -p "$pkgdir/lib/firmware/wlan/prima"
    install -m 0644 wcnss/WCNSS_qcom_wlan_nv.bin "$pkgdir/lib/firmware/wlan/prima/"
  fi
}
