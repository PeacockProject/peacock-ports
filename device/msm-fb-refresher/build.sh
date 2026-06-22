# shellcheck shell=sh
# msm-fb-refresher — compile the vendored refresher.c (static) for the target
# and stage it under /usr/bin. No source tarball, so prepare() is a no-op.

package() {
  mkdir -p "$pkgdir/usr/bin"
  cp refresher.c "$pkgdir/usr/bin/refresher.c"
  ${CROSS_COMPILE:-}gcc -static -o "$pkgdir/usr/bin/msm-fb-refresher" refresher.c
  STRIP_BIN="${CROSS_COMPILE:-}strip"
  $STRIP_BIN -s "$pkgdir/usr/bin/msm-fb-refresher" 2>/dev/null || strip -s "$pkgdir/usr/bin/msm-fb-refresher"
}
