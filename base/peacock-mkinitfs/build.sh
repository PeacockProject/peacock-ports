# shellcheck shell=sh
# peacock-mkinitfs — Go CLI built from the upstream github tarball. prepare()
# (default) extracts the tarball in place (strip-components=1), replacing the
# manual tar -xzf the old inline script did. build() compiles the binary;
# package() stages it at /usr/bin/peacock-mkinitfs.

build() {
  # Cross-compile for the consuming device arch (CGO off), mapping the
  # kernel-style $ARCH the build injects to GOARCH — same as peacock-init.
  # Without this, go build targets the host (x86_64) and the binary won't exec
  # on the device (ENOEXEC -> the shell parses it -> "syntax error").
  case "${ARCH:-arm64}" in
    arm64|aarch64) GOARCH=arm64 ;;
    arm)           GOARCH=arm; export GOARM=7 ;;
    x86_64|amd64)  GOARCH=amd64 ;;
    *)             GOARCH="${ARCH}" ;;
  esac
  export GOARCH GOOS=linux CGO_ENABLED=0
  echo "Building peacock-mkinitfs for GOARCH=$GOARCH (ARCH=${ARCH:-?})..."
  go build -trimpath -ldflags "-s -w" -o peacock-mkinitfs ./cmd/peacock-mkinitfs
}

package() {
  mkdir -p "$pkgdir/usr/bin"
  cp peacock-mkinitfs "$pkgdir/usr/bin/peacock-mkinitfs"
}
