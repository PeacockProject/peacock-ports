# shellcheck shell=sh
# peacock-netdbg ships one static script; no compile. (The builder copies top-level port files
# into the chroot, so the payload lives at the port root.)
build() { :; }

package() {
  install -Dm755 peacock-netdbg.sh "$pkgdir/sbin/peacock-netdbg"
}
