# build_type = "make"
#
# Plain Makefile projects. Honors:
#   $make_args          extra args to `make` (build)
#   $make_install_args  extra args to `make install`
#   $prefix             install prefix (default /usr)
# ARCH / CROSS_COMPILE are passed through from the environment as make
# variables when set (kernels and many firmware Makefiles want them).

_peacock_make_vars() {
  local v=""
  [ -n "${ARCH:-}" ] && v="$v ARCH=$ARCH"
  [ -n "${CROSS_COMPILE:-}" ] && v="$v CROSS_COMPILE=$CROSS_COMPILE"
  printf '%s' "$v"
}

build() {
  # shellcheck disable=SC2086
  make $(_peacock_make_vars) -j"${jobs:-1}" ${make_args:-}
}

package() {
  # shellcheck disable=SC2086
  make $(_peacock_make_vars) install \
    DESTDIR="$pkgdir" PREFIX="${prefix:-/usr}" ${make_install_args:-}
}
