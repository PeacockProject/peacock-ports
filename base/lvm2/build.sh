# shellcheck shell=sh
# lvm2 — uses non-standard make targets (device-mapper / install_device-mapper)
# that the autotools type can't express, so this is a raw port. Logic moved
# verbatim from the legacy inline script, with the install prefix repointed from
# $(pwd)/stage to $pkgdir (the artifact). install_device-mapper stages
# sbin/lib/include under $pkgdir directly, so the legacy "cp -a stage/..." copy-
# back is no longer needed. (prepare() already extracted.)

build() {
  ./configure \
    --prefix="$pkgdir" \
    --sbindir="$pkgdir/sbin" \
    --enable-static_link \
    --disable-selinux \
    --disable-udev_sync \
    --disable-systemd-journal \
    --without-systemd \
    --without-systemdsystemunitdir \
    --enable-applib \
    --enable-cmdlib
  make -j"${jobs:-1}" device-mapper
}

package() {
  make -j"${jobs:-1}" install_device-mapper
}
