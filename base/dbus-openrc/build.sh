# shellcheck shell=sh
# dbus-openrc — no source tarball; just stage the OpenRC dbus service files.
# prepare() is a harmless no-op (nothing to extract); package() installs the
# init scripts and xinitrc fragment into $pkgdir.

package() {
  install -Dm755 dbus.initd "$pkgdir/etc/init.d/dbus"
  install -Dm755 dbus.user.initd "$pkgdir/etc/user/init.d/dbus"
  install -Dm644 80-dbus "$pkgdir/etc/X11/xinit/xinitrc.d/80-dbus.sh"
}
