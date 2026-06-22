# shellcheck shell=sh
# samsung-jflte-fbdevhw-compat — compile the patched fbdevhw.c from the
# xorg-server tree into a standalone libfbdevhw.so and stage it. prepare()
# (default) extracts the tarball and applies $patches.

build() {
  cc -fPIC -O2 \
     -DXORG_VERSION_CURRENT='XORG_VERSION_NUMERIC(21,1,21,0,0)' \
     -I/usr/include/xorg \
     -I/usr/include/pixman-1 \
     -Ihw/xfree86/fbdevhw \
     -shared \
     -o libfbdevhw.so \
     hw/xfree86/fbdevhw/fbdevhw.c
}

package() {
  install -Dm755 libfbdevhw.so "$pkgdir/usr/lib/xorg/modules/libfbdevhw.so"
}
