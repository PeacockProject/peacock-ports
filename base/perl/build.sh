# shellcheck shell=sh
# perl — ./Configure is perl's own configurator, not autotools, so this is a
# raw port. Logic moved verbatim from the legacy inline script: configure with
# the /usr/local prefix, build, install into $pkgdir via DESTDIR, then relocate
# usr/local/* up to the $pkgdir top level. (prepare() already extracted.)

build() {
  ./Configure -des -Dprefix="/usr/local"
  make -j"${jobs:-1}"
}

package() {
  make install DESTDIR="$pkgdir"
  if [ -d "$pkgdir/usr/local" ]; then
    if [ -d "$pkgdir/usr/local/bin" ]; then
      mkdir -p "$pkgdir/bin"
      cp -a "$pkgdir/usr/local/bin/." "$pkgdir/bin/"
    fi
    if [ -d "$pkgdir/usr/local/lib" ]; then
      mkdir -p "$pkgdir/lib"
      cp -a "$pkgdir/usr/local/lib/." "$pkgdir/lib/"
    fi
    if [ -d "$pkgdir/usr/local/include" ]; then
      mkdir -p "$pkgdir/include"
      cp -a "$pkgdir/usr/local/include/." "$pkgdir/include/"
    fi
    if [ -d "$pkgdir/usr/local/share" ]; then
      mkdir -p "$pkgdir/share"
      cp -a "$pkgdir/usr/local/share/." "$pkgdir/share/"
    fi
    if [ -d "$pkgdir/usr/local/man" ]; then
      mkdir -p "$pkgdir/man"
      cp -a "$pkgdir/usr/local/man/." "$pkgdir/man/"
    fi
    rm -rf "$pkgdir/usr/local"
  fi
}
