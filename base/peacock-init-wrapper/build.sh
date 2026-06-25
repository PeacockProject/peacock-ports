# shellcheck shell=sh
# peacock-init-wrapper — the initramfs /init wrapper, cross-compiled for the
# consuming device arch (CGO disabled). Vendored Go source (main.go, go.mod), so
# prepare() is a no-op. peacock-mkinitfs prefers this prebuilt binary over
# compiling one with `go`, so on-device installs (PRP) need no Go toolchain.
# package() stages it at /usr/lib/peacock/init-wrapper.

build() {
  # Map the kernel-style $ARCH the build injects to GOARCH (same as peacock-init).
  case "${ARCH:-arm64}" in
    arm64|aarch64) GOARCH=arm64 ;;
    arm)           GOARCH=arm; export GOARM=7 ;;
    x86_64|amd64)  GOARCH=amd64 ;;
    *)             GOARCH="${ARCH}" ;;
  esac
  export GOARCH GOOS=linux CGO_ENABLED=0
  export GOPROXY=off GOFLAGS=-mod=mod GOTOOLCHAIN=local
  export GOCACHE=/tmp/peacock-init-wrapper-gocache GOPATH=/tmp/peacock-init-wrapper-gopath HOME=/tmp

  echo "Building peacock-init-wrapper for GOARCH=$GOARCH (ARCH=${ARCH:-?})..."
  go build -trimpath -ldflags "-s -w" -o init-wrapper .
}

package() {
  mkdir -p "$pkgdir/usr/lib/peacock"
  cp init-wrapper "$pkgdir/usr/lib/peacock/init-wrapper"
}
