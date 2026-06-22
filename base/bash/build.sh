# shellcheck shell=sh
# bash — vanilla autotools (the autotools type runs configure/make/install).
# Override package() only to add the /bin/sh -> bash symlink that OpenRC and
# many base scripts require. (Rootfs uses /bin -> /usr/bin, so /usr/bin/sh.)

package() {
  make install DESTDIR="$pkgdir"
  ln -sf bash "$pkgdir/usr/bin/sh"
}
