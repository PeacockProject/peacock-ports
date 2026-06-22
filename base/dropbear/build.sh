# shellcheck shell=sh
# dropbear — static musl build via zig cc. prepare() (default) extracts the
# single tarball (strip 1); build() configures + compiles, package() stages.
# Logic moved verbatim from the old inline script; the zig target mapping,
# configure flags and PROGRAMS set are byte-for-byte intentional.

build() {
  case "${ARCH:-arm64}" in
    arm64|aarch64)            ZIG_TARGET=aarch64-linux-musl ;;
    arm|armv7|armv7h|armhf)   ZIG_TARGET=arm-linux-musleabihf ;;
    x86_64|amd64)             ZIG_TARGET=x86_64-linux-musl ;;
    *)                        ZIG_TARGET="${ARCH}-linux-musl" ;;
  esac

  export HOME=/tmp
  export ZIG_GLOBAL_CACHE_DIR=/tmp/zig-cache ZIG_LOCAL_CACHE_DIR=/tmp/zig-cache
  export CC="zig cc -target ${ZIG_TARGET}"
  export CFLAGS="-O2 -fno-omit-frame-pointer"
  export LDFLAGS="-static"

  echo "Building static musl dropbear for ${ZIG_TARGET} (ARCH=${ARCH:-?})..."
  # Disable host-specific session bookkeeping (utmp/wtmp/lastlog/shadow) and zlib
  # so the static musl build is self-contained — matches PRP's recovery profile.
  ./configure \
    --host="${ZIG_TARGET}" \
    --enable-static \
    --disable-harden \
    --disable-zlib \
    --disable-syslog \
    --disable-shadow \
    --disable-lastlog \
    --disable-utmp \
    --disable-utmpx \
    --disable-wtmp \
    --disable-wtmpx

  # scp here is the bundled OpenSSH scp, so host-side `scp root@device:...` works.
  make -j"${jobs:-1}" PROGRAMS="dropbear dropbearkey dbclient scp"
}

package() {
  mkdir -p "$pkgdir/usr/sbin" "$pkgdir/usr/bin"
  install -m 0755 dropbear dropbearkey "$pkgdir/usr/sbin/"
  install -m 0755 dbclient scp "$pkgdir/usr/bin/"
  ln -snf dbclient "$pkgdir/usr/bin/ssh"
}
