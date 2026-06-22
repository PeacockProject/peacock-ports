# shellcheck shell=sh
# build_type = "make"
#
# Plain Makefile projects, decomposed for per-step override (see autotools.sh).
#   compile()   default: make $vars -j$jobs $make_args
#   package()   default: make $vars install DESTDIR=$pkgdir PREFIX=$prefix $make_install_args
# Reuse with default_compile / default_install; honors $make_args,
# $make_install_args, $prefix (default /usr). ARCH / CROSS_COMPILE pass through
# as make vars when set (kernels and many firmware Makefiles want them).

_peacock_make_vars() {
  v=""
  [ -n "${ARCH:-}" ] && v="$v ARCH=$ARCH"
  [ -n "${CROSS_COMPILE:-}" ] && v="$v CROSS_COMPILE=$CROSS_COMPILE"
  printf '%s' "$v"
}

default_compile() {
  # shellcheck disable=SC2086
  make $(_peacock_make_vars) -j"${jobs:-1}" ${make_args:-}
}
default_install() {
  # shellcheck disable=SC2086
  make $(_peacock_make_vars) install \
    DESTDIR="$pkgdir" PREFIX="${prefix:-/usr}" ${make_install_args:-}
}

compile() { default_compile; }
build() { compile; }
package() { default_install; }
