# shellcheck shell=sh
# openrc — meson/ninja build (not autotools), so type = "raw" + verbatim logic.
# prepare() extracts the tarball into $builddir; we build out-of-tree under
# ./build and stage into $pkgdir. Original `../stage` paths become $pkgdir.

build() {
  mkdir -p build
  cd build
  meson setup .. \
      --prefix=/usr \
      --sysconfdir=/etc \
      --sbindir=/usr/bin \
      --bindir=/usr/bin \
      --libdir=/usr/lib \
      --libexecdir=/usr/lib/rc \
      -Dbranding='"Peacock"' \
      -Dsysvinit=true

  ninja
}

package() {
  DESTDIR="$pkgdir" ninja -C build install

  # Fix shebangs or paths if needed
  # Create essential directories for openrc
  mkdir -p "$pkgdir/run/openrc"
  touch "$pkgdir/run/openrc/softlevel"

  # Keep OpenRC on live console output (tty/fbcon), disable file logger.
  if [ -f "$pkgdir/etc/rc.conf" ]; then
      sed -i 's/^#rc_logger="NO"/rc_logger="NO"/' "$pkgdir/etc/rc.conf"
  fi
}
