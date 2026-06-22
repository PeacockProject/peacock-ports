# shellcheck shell=sh
# samsung-jflte-fbdev-compat — build the patched xf86-video-fbdev driver and
# stage only the resulting fbdev_drv.so. prepare() (default) extracts the
# tarball and applies $patches; build() configures + compiles; package() installs
# the single .so into $pkgdir.

build() {
  ./configure --prefix=/usr
  make -j "${jobs:-1}"
}

package() {
  install -Dm755 src/.libs/fbdev_drv.so \
    "$pkgdir/usr/lib/xorg/modules/drivers/fbdev_drv.so"
}
