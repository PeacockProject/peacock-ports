# peacock build library — default phases + helpers.
#
# This is the one shared build library (bind-mounted read-only into the
# build sandbox at /peacock-buildlib). It is sourced first; then the
# build_type lib (make.sh / autotools.sh / kernel.sh); then the port's
# ./build.sh, whose function definitions override anything here
# (last-definition-wins). run_phases then drives prepare -> build ->
# check -> package.
#
# Contract the harness guarantees in the environment:
#   $pkgname $pkgver   package identity
#   $srcdir            working dir holding the downloaded tarball(s) + port files
#   $builddir          source root the build runs in (default: $srcdir)
#   $pkgdir            stage dir that becomes the artifact (the old stage/)
#   $jobs              parallelism
#   CROSS_COMPILE ARCH cross build (empty for native)
#   plus any port vars (configure_args, make_args, kernel_config, ...)

peacock_msg() { printf '>>> %s\n' "$*"; }
peacock_die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# peacock_extract <archive> — unpack into the current dir, stripping the
# leading top-level dir (override per-port with $strip).
peacock_extract() {
  local f="$1"
  [ -f "$f" ] || peacock_die "archive not found: $f"
  local n="${strip:-1}"
  case "$f" in
    *.tar.gz | *.tgz) tar -xzf "$f" --strip-components="$n" ;;
    *.tar.xz) tar -xJf "$f" --strip-components="$n" ;;
    *.tar.zst) tar --zstd -xf "$f" --strip-components="$n" ;;
    *.tar.bz2) tar -xjf "$f" --strip-components="$n" ;;
    *.tar) tar -xf "$f" --strip-components="$n" ;;
    *) peacock_die "unknown archive type: $f" ;;
  esac
}

# apply_patches — apply every file named in $patches (space-separated),
# -p1 from $builddir. No-op when unset.
apply_patches() {
  local p
  for p in ${patches:-}; do
    [ -f "$p" ] || peacock_die "patch not found: $p"
    peacock_msg "applying patch $p"
    patch -p1 <"$p"
  done
}

# default_prepare — extract the first source tarball in the working dir
# (in place), then apply patches. Ports override prepare() for anything
# custom; they can still call default_prepare.
default_prepare() {
  local tb
  tb="$(ls -1 ./*.tar.gz ./*.tgz ./*.tar.xz ./*.tar.zst ./*.tar.bz2 ./*.tar 2>/dev/null | head -n1)"
  if [ -n "$tb" ]; then
    peacock_msg "extracting $(basename "$tb")"
    peacock_extract "$tb"
  fi
  apply_patches
}

# Default phases. build_type libs and port build.sh override these.
prepare() { default_prepare; }
build() { :; }
check() { :; }
package() { :; }

# peacock_tidy — make the staged package lean before it's archived into a
# .feather: strip debug symbols from ELF binaries. Runs for EVERY port. A port
# can set no_strip=1 to keep symbols (e.g. a debug/-dev package).
#
# NOTE: we deliberately do NOT delete .a/.la here — static archives are a
# legitimate package payload consumed via build_dep_packages (e.g. util-linux's
# libblkid.a for lvm2, libnl for wpa_supplicant). strip skips them anyway (an
# `ar` archive isn't ELF). Runtime cruft like .a is trimmed at rootfs-assembly
# (see PRP build-overlay.sh), not stripped from the package.
peacock_tidy() {
  [ -d "$pkgdir" ] || return 0

  if [ "${no_strip:-0}" != "1" ]; then
    # Pick a strip that understands the target ELFs: the cross strip when
    # cross-compiling, else llvm-strip (arch-agnostic), else native strip
    # (works in a QEMU-mode same-arch chroot).
    local STRIPBIN=""
    if [ -n "${CROSS_COMPILE:-}" ] && command -v "${CROSS_COMPILE}strip" >/dev/null 2>&1; then
      STRIPBIN="${CROSS_COMPILE}strip"
    elif command -v llvm-strip >/dev/null 2>&1; then
      STRIPBIN="llvm-strip"
    elif command -v strip >/dev/null 2>&1; then
      STRIPBIN="strip"
    fi
    if [ -n "$STRIPBIN" ]; then
      peacock_msg "strip ($pkgname) via $STRIPBIN"
      find "$pkgdir" -type f 2>/dev/null | while IFS= read -r f; do
        case "$(LC_ALL=C file -b "$f" 2>/dev/null)" in
          *ELF*) "$STRIPBIN" --strip-unneeded "$f" 2>/dev/null || true ;;
        esac
      done
    else
      peacock_msg "strip: no strip tool found, skipping"
    fi
  fi
}

# run_phases — the driver the harness invokes. Fails on any error.
run_phases() {
  set -e
  cd "$builddir"
  peacock_msg "prepare ($pkgname $pkgver)"
  prepare
  peacock_msg "build ($pkgname)"
  build
  peacock_msg "check ($pkgname)"
  check
  peacock_msg "package ($pkgname -> $pkgdir)"
  mkdir -p "$pkgdir"
  package
  peacock_msg "tidy ($pkgname)"
  peacock_tidy
}
