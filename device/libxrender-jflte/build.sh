# shellcheck shell=sh
# libxrender-jflte — vanilla autotools libXrender with the jflte crash-guard
# patch (applied by prepare() via $patches). Only configure() needs overriding:
# keep codegen conservative for this legacy userspace/kernel combo and disable
# the static lib. compile()/package() use the autotools defaults
# (make -> make install DESTDIR=$pkgdir).

configure() {
  # Keep codegen conservative for this legacy userspace/kernel combo.
  export CFLAGS="${CFLAGS:-} -O2 -fno-strict-aliasing -fno-tree-vectorize"
  ./configure --prefix=/usr --disable-static
}
