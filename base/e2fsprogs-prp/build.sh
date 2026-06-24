# shellcheck shell=sh
# e2fsprogs-prp — lean static-musl ext2/3/4 tools for the PRP installer, built
# with zig cc. Only the tools the installer needs to create/repair the target
# filesystem (mke2fs + mkfs.ext* links, e2fsck + fsck.ext* links, resize2fs,
# tune2fs). Fully static, no shared libs — self-contained like the other -prp
# ports. e2fsprogs bundles its own libuuid/libblkid, so no external deps.

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
  # musl: expose lseek64 (else llseek.c falls back to an undeclared my_llseek);
  # downgrade clang's implicit-decl error for the older autotools C.
  export CFLAGS="-O2 -fno-omit-frame-pointer -D_GNU_SOURCE -D_LARGEFILE64_SOURCE -Wno-error=implicit-function-declaration"
  export LDFLAGS="-static"

  echo "Configuring static-musl e2fsprogs for ${ZIG_TARGET} (ARCH=${ARCH:-?})..."
  ./configure \
    --host="${ZIG_TARGET}" \
    --disable-shared --disable-elf-shlibs \
    --disable-nls --disable-defrag --disable-fuse2fs \
    --disable-testio-debug --disable-rpath

  # Build everything (the top-level make generates lib/dirpaths.h + the libs in
  # the right order; targeting individual programs skips that codegen). We only
  # package the handful of tools we need, in package().
  make -j"${jobs:-4}"
}

package() {
  mkdir -p "$pkgdir/sbin"
  install -m 0755 misc/mke2fs    "$pkgdir/sbin/mke2fs"
  install -m 0755 e2fsck/e2fsck  "$pkgdir/sbin/e2fsck"
  install -m 0755 resize/resize2fs "$pkgdir/sbin/resize2fs"
  install -m 0755 misc/tune2fs   "$pkgdir/sbin/tune2fs"
  install -m 0755 misc/dumpe2fs  "$pkgdir/sbin/dumpe2fs"
  for ext in ext2 ext3 ext4; do
    ln -snf mke2fs "$pkgdir/sbin/mkfs.$ext"
    ln -snf e2fsck "$pkgdir/sbin/fsck.$ext"
  done
}
