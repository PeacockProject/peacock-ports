# shellcheck shell=sh
# toolchain-arm-linux-gnueabihf — prebuilt Linaro GCC 7.5 arm-linux-gnueabihf
# cross-compiler. Nothing to compile: prepare() (default) extracts the prebuilt
# tarball (single top-level dir, strip 1) so bin/ lands at the build root.
# check() validates the extraction; package() stages the whole tree as the
# artifact.

check() {
  if [ ! -d bin ]; then
    echo "Expected bin/ directory not found"
    exit 1
  fi
}

package() {
  # Stage the extracted prebuilt toolchain tree (everything except the source
  # tarball and port metadata) into the artifact dir.
  for f in *; do
    case "$f" in
      *.tar.xz | *.tar.gz | *.tar.bz2 | *.tar.zst | *.tar | build.sh | package.toml) continue ;;
    esac
    cp -a "$f" "$pkgdir/"
  done
}
