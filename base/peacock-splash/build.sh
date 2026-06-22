# shellcheck shell=sh
# peacock-splash — single C source compiled with the device cross toolchain
# (CROSS_COMPILE resolves per consuming arch). No tarball: splash.c, the logo
# header and stb_image.h are vendored in the port dir, so prepare() is a no-op.
# build() compiles the static binary; package() stages it plus splash.c verbatim
# from the old inline script.

build() {
  ${CROSS_COMPILE:-}gcc -static -O2 -s -o peacock-splash splash.c -lm
}

package() {
  mkdir -p "$pkgdir/usr/bin"
  cp splash.c "$pkgdir/usr/bin/splash.c"
  cp peacock-splash "$pkgdir/usr/bin/peacock-splash"
}
