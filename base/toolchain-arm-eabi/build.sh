# shellcheck shell=sh
# toolchain-arm-eabi — prebuilt Linaro GCC 4.9 arm-eabi toolchain. There is
# nothing to compile: prepare() (default) extracts the prebuilt tarball
# (single top-level dir, strip 1) so bin/ lands at the build root. check()
# validates the extraction; package() stages the whole toolchain tree as the
# artifact.

check() {
  if [ ! -d bin ]; then
    echo "Toolchain bin/ not found after extraction"
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
