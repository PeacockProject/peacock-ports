# shellcheck shell=sh
# pbsplash — static pbsplash linked against tfblib, cross-built for armhf.
#
# The bundled sources ship as pbsplash-src.tar.gz with top-level pbsplash/ and
# tfblib/ dirs, so the default strip-components=1 extraction is WRONG here:
# prepare() is overridden to extract verbatim (tar -xf, no strip), matching the
# old inline script. build() generates the empty-font stub, builds libtfb.a and
# links pbsplash. package() stages the binary and assets into $pkgdir.

prepare() {
  # Extract bundled sources (top-level pbsplash/ + tfblib/) without stripping.
  tar -xf pbsplash-src.tar.gz
}

build() {
  # Provide an empty font list to avoid cmake codegen
  cat > tfblib/src/fonts_decls.c <<'EOF'
#include "font.h"
static const struct font_file *__font_file_list[] = {0};
const struct font_file **tfb_font_file_list = __font_file_list;
EOF

  TFB_CFLAGS="-I tfblib/include -I tfblib/src"
  ${CROSS_COMPILE:-}gcc -static -O2 -c tfblib/src/*.c tfblib/src/fonts_decls.c $TFB_CFLAGS
  ${CROSS_COMPILE:-}ar rcs libtfb.a *.o
  rm -f *.o

  PBS_CFLAGS="-I pbsplash/include -I tfblib/include -I tfblib/src"
  ${CROSS_COMPILE:-}gcc -static -O2 -o pbsplash-bin \
    pbsplash/src/animate.c pbsplash/src/nanosvg.c pbsplash/src/timespec.c pbsplash/src/pbsplash.c \
    libtfb.a -lm $PBS_CFLAGS
}

package() {
  mkdir -p "$pkgdir/usr/bin" "$pkgdir/usr/share/pbsplash"
  cp -a assets/* "$pkgdir/usr/share/pbsplash/"
  cp pbsplash-bin "$pkgdir/usr/bin/pbsplash"
}
