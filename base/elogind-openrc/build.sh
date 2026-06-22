# shellcheck shell=sh
# elogind-openrc — no source tarball; stage the OpenRC elogind service files.
# prepare() is a no-op; package() installs the init script + conf.d into $pkgdir.

package() {
  install -Dm755 elogind.initd "$pkgdir/etc/init.d/elogind"
  install -Dm644 elogind.confd "$pkgdir/etc/conf.d/elogind"
}
