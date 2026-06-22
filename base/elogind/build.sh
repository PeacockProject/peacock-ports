# shellcheck shell=sh
# elogind — meson/ninja build (not autotools), so type = "raw" + verbatim logic.
# prepare() extracts the tarball into $builddir; build out-of-tree under ./build
# and stage into $pkgdir. Original `$PWD/stage` becomes $pkgdir; the JOBS probe
# is replaced by the harness-provided ${jobs:-1}.

build() {
  meson setup build \
      --prefix=/usr \
      --libexecdir=/usr/lib/elogind \
      -Dmode=release \
      -Ddefault-hierarchy=unified \
      -Dcgroup-controller=openrc \
      -Ddefault-kill-user-processes=false \
      -Dinstall-sysconfdir=true \
      -Dutmp=true \
      -Dsmack=false \
      -Dselinux=disabled \
      -Dxenctrl=disabled \
      -Daudit=disabled \
      -Dpolkit=disabled \
      -Dman=disabled \
      -Dhalt-path=/usr/bin/halt \
      -Dpoweroff-path=/usr/bin/poweroff \
      -Dreboot-path=/usr/bin/reboot \
      -Dkexec-path=/usr/bin/kexec

  meson compile -C build -j "${jobs:-1}"
}

package() {
  DESTDIR="$pkgdir" meson install -C build
}
