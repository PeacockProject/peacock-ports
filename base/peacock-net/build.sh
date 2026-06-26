# shellcheck shell=sh
# peacock-net ships only static files; no compile. package() installs them into $pkgdir. (The
# builder copies top-level port files into the chroot, so the payload lives at the port root.)
build() { :; }

package() {
  install -Dm755 peacock-net.sh        "$pkgdir/sbin/peacock-net"
  install -Dm755 udhcpc-default.script "$pkgdir/usr/share/udhcpc/default.script"
  install -Dm644 regulatory.db         "$pkgdir/lib/firmware/regulatory.db"
  install -Dm644 regulatory.db.p7s     "$pkgdir/lib/firmware/regulatory.db.p7s"
}
