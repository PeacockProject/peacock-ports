# shellcheck shell=sh
# util-linux-prp — lean static-musl subset for PRP recovery.
#
# Only the partition tools busybox does poorly: the full fdisk/sfdisk plus
# blkid/partx/losetup. Built fully static against musl via zig cc, so the PRP
# rootfs needs no glibc, ncurses, readline or dynamic linker — self-contained
# like busybox/dropbear. --disable-all-programs starts from nothing; we enable
# only what we need + the libs they require, and grab the .static variants.

build() {
  case "${ARCH:-aarch64}" in
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

  # Don't --disable-all-programs + re-enable: that makes cfdisk an explicit
  # target and configure then HARD-fails on the missing ncurses. Instead leave
  # the default program set (cfdisk soft-skips itself with no ncurses) and just
  # `make` the specific .static targets — that builds only those tools + the
  # libs they need, not the rest of util-linux.
  echo "Configuring lean static-musl util-linux for ${ZIG_TARGET} (ARCH=${ARCH:-?})..."
  ./configure \
    --host="${ZIG_TARGET}" \
    --enable-static-programs=fdisk,sfdisk,blkid,partx,losetup \
    --without-readline --without-ncurses --without-ncursesw --without-tinfo --without-slang \
    --without-systemd --without-systemdsystemunitdir --without-python \
    --without-udev --without-cryptsetup \
    --disable-nls --disable-rpath --disable-bash-completion --disable-asciidoc \
    --disable-pylibmount --disable-makeinstall-chown --disable-makeinstall-setuid

  make -j"${jobs:-4}" fdisk.static sfdisk.static blkid.static partx.static losetup.static
}

package() {
  mkdir -p "$pkgdir/sbin"
  for t in fdisk sfdisk blkid partx losetup; do
    if [ -f "$t.static" ]; then
      install -m 0755 "$t.static" "$pkgdir/sbin/$t"
    else
      echo "WARN: $t.static not produced" >&2
    fi
  done
}
