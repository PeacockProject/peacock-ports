# shellcheck shell=sh
# openssl — ./Configure is openssl's own perl-driven configurator, not
# autotools, so this is a raw port. Logic moved verbatim from the legacy inline
# script, with the install prefix repointed from $(pwd)/stage to $pkgdir (the
# artifact). install_sw stages bin/lib/include under $pkgdir directly, so the
# legacy "cp -a stage/{bin,lib,include} ./" copy-back is no longer needed.
# (prepare() already extracted.)

build() {
  ./Configure --prefix="$pkgdir" --openssldir="$pkgdir/ssl" --libdir=lib shared
  make -j"${jobs:-1}"
}

package() {
  make install_sw
}
