# build_type = "autotools"
#
# ./configure && make && make install DESTDIR=. Honors:
#   $configure_args   extra ./configure flags
#   $prefix           install prefix (default /usr)
#   $make_args        extra args to `make`

build() {
  # shellcheck disable=SC2086
  ./configure --prefix="${prefix:-/usr}" ${configure_args:-}
  # shellcheck disable=SC2086
  make -j"${jobs:-1}" ${make_args:-}
}

package() {
  make install DESTDIR="$pkgdir"
}
