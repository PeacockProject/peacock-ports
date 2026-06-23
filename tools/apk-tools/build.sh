# shellcheck shell=sh
# apk-tools — build the `apk` binary (dynamic, glibc) for the PeacockOS build
# base. apk-tools is a plain Makefile project; FULL_VERSION must be passed
# explicitly because the tarball has no git metadata to derive it from. LUA=no
# drops the optional lua module. prepare() (default) extracts the tarball.

build() {
  make -j"${jobs:-1}" LUA=no FULL_VERSION="$pkgver"
  [ -f src/apk ] || peacock_die "apk binary not built (src/apk missing)"
}

package() {
  install -Dm0755 src/apk "$pkgdir/usr/bin/apk"
}
