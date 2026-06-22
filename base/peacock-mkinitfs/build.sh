# shellcheck shell=sh
# peacock-mkinitfs — Go CLI built from the upstream github tarball. prepare()
# (default) extracts the tarball in place (strip-components=1), replacing the
# manual tar -xzf the old inline script did. build() compiles the binary;
# package() stages it at /usr/bin/peacock-mkinitfs.

build() {
  go build -trimpath -ldflags "-s -w" -o peacock-mkinitfs ./cmd/peacock-mkinitfs
}

package() {
  mkdir -p "$pkgdir/usr/bin"
  cp peacock-mkinitfs "$pkgdir/usr/bin/peacock-mkinitfs"
}
