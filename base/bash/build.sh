# shellcheck shell=sh
# bash — vanilla autotools; only the install step needs a post-step: the
# /bin/sh -> bash symlink that OpenRC and many base scripts require. Reuse the
# autotools install, then add the link. (Rootfs /bin -> /usr/bin, so /usr/bin/sh.)

package() {
  default_install
  ln -sf bash "$pkgdir/usr/bin/sh"
}
