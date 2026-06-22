# shellcheck shell=sh
# sddm — cmake build (Qt6 main + Qt5 greeter/components), so type = "raw" +
# verbatim logic. prepare() extracts the tarball into $builddir. Original
# `$PWD/stage` becomes $pkgdir; the JOBS probe is replaced by ${jobs:-1}.

build() {
  export CMAKE_BUILD_PARALLEL_LEVEL="${jobs:-1}"

  cmake -B build -S . \
      -DCMAKE_INSTALL_PREFIX=/usr \
      -DCMAKE_INSTALL_LIBEXECDIR=/usr/lib/sddm \
      -DBUILD_WITH_QT6=ON \
      -DDBUS_CONFIG_DIR=/usr/share/dbus-1/system.d \
      -DDBUS_CONFIG_FILENAME=sddm_org.freedesktop.DisplayManager.conf \
      -DBUILD_MAN_PAGES=ON \
      -DUSE_ELOGIND=yes \
      -DNO_SYSTEMD=yes \
      -DUID_MAX=60513 \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5
  cmake --build build -j "${jobs:-1}"

  cmake -B build5 -S . \
      -DCMAKE_INSTALL_PREFIX=/usr \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5
  cmake --build build5/src/greeter -j "${jobs:-1}"
  cmake --build build5/components -j "${jobs:-1}"
}

package() {
  DESTDIR="$pkgdir" cmake --install build
  DESTDIR="$pkgdir" cmake --install build5/src/greeter
  DESTDIR="$pkgdir" cmake --install build5/components

  install -d "$pkgdir"/usr/lib/sddm/sddm.conf.d
  "$pkgdir"/usr/bin/sddm --example-config > "$pkgdir"/usr/lib/sddm/sddm.conf.d/default.conf
  sed -r 's|DefaultPath=.*|DefaultPath=/usr/local/sbin:/usr/local/bin:/usr/bin|g' -i "$pkgdir"/usr/lib/sddm/sddm.conf.d/default.conf
  sed -e "/^InputMethod/s/qtvirtualkeyboard//" -i "$pkgdir"/usr/lib/sddm/sddm.conf.d/default.conf

  install -Dm644 sddm.sysusers "$pkgdir"/usr/lib/sysusers.d/sddm.conf
  install -Dm644 sddm.tmpfiles "$pkgdir"/usr/lib/tmpfiles.d/sddm.conf
}
