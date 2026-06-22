# shellcheck shell=sh
# compat-glibc — glibc 2.40 runtime tree staged into /compat/glibc. prepare()
# (default) extracts the single tarball (strip 1), matching the old manual
# `tar -xzf glibc-*.tar.gz --strip-components=1`. build() configures + compiles
# in an out-of-tree build/ subdir; package() installs into $pkgdir (the old
# DESTDIR stage). See package.toml [notes] for the cross-compile caveats.

build() {
  mkdir -p build && cd build
  case "${ARCH:-aarch64}" in
    aarch64)  TRIPLE=aarch64-linux-gnu ;;
    armv7h)   TRIPLE=arm-linux-gnueabihf ;;
    x86_64)   TRIPLE=x86_64-linux-gnu ;;
    *) echo "compat-glibc: unsupported ARCH=${ARCH}" >&2 ; exit 1 ;;
  esac
  ../configure --prefix=/compat/glibc --host="$TRIPLE" --enable-shared --disable-werror
  make -j"${jobs:-1}"
}

package() {
  make -C build install DESTDIR="$pkgdir"
}
