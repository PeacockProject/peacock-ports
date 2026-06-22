# shellcheck shell=sh
# sddm-openrc — no source tarball; stage the OpenRC sddm service files.
# prepare() is a no-op; package() installs the init script + pam file into $pkgdir.

package() {
  install -Dm755 sddm.initd "$pkgdir/etc/init.d/sddm"
  install -Dm644 sddm.pam "$pkgdir/etc/pam.d/sddm"
}
