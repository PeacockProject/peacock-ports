# shellcheck shell=sh
# build_type = "autotools"
#
# ./configure -> make -> make install DESTDIR=$pkgdir, decomposed so a port's
# ./build.sh can override ONE step and reuse the rest (last-definition-wins).
#
# Overridable entry points (call the matching default_* to reuse the impl):
#   configure()   default: ./configure --prefix=$prefix $configure_args
#   compile()     default: make -j$jobs $make_args
#   package()     default: make install DESTDIR=$pkgdir $make_install_args
#
# So a port that's standard-except-one-step writes just that step, e.g.:
#   configure() { ./autogen.sh; default_configure; }                  # pre-step
#   configure() { ./configure --prefix=/usr --enable-weird; }         # replace
#   package()   { default_install; ln -sf foo "$pkgdir/usr/bin/bar"; } # post-step
#
# Honors $prefix (default /usr), $configure_args, $make_args, $make_install_args.

default_configure() {
  # shellcheck disable=SC2086
  ./configure --prefix="${prefix:-/usr}" ${configure_args:-}
}
default_compile() {
  # shellcheck disable=SC2086
  make -j"${jobs:-1}" ${make_args:-}
}
default_install() {
  # shellcheck disable=SC2086
  make install DESTDIR="$pkgdir" ${make_install_args:-}
}

configure() { default_configure; }
compile() { default_compile; }
build() { configure; compile; }
package() { default_install; }
