# shellcheck shell=sh
# peacock-init — Go program cross-compiled for the consuming device arch with
# CGO disabled. The source (main.go, go.mod) is vendored in the port dir, so
# there is no tarball and prepare() is a no-op. build() compiles the static
# binary; package() stages it at /sbin/peacock-init plus the /sbin/init symlink
# the initramfs hands off to. Logic moved verbatim from the old inline script.

build() {
  # Map the kernel-style $ARCH the build injects to GOARCH.
  case "${ARCH:-arm64}" in
    arm64)  GOARCH=arm64 ;;
    arm)    GOARCH=arm; export GOARM=7 ;;
    x86_64) GOARCH=amd64 ;;
    *)      GOARCH="${ARCH}" ;;
  esac
  export GOARCH GOOS=linux CGO_ENABLED=0
  # Offline + self-contained: no module deps, no toolchain download.
  export GOPROXY=off GOFLAGS=-mod=mod GOTOOLCHAIN=local
  export GOCACHE=/tmp/peacock-init-gocache GOPATH=/tmp/peacock-init-gopath HOME=/tmp

  echo "Building peacock-init for GOARCH=$GOARCH (ARCH=${ARCH:-?})..."
  go build -trimpath -ldflags "-s -w" -o peacock-init .
}

package() {
  mkdir -p "$pkgdir/sbin"
  cp peacock-init "$pkgdir/sbin/peacock-init"
  # /sbin/init -> peacock-init so the initramfs switch_root hands off to us.
  ln -sf peacock-init "$pkgdir/sbin/init"

  # Base filesystem skeleton. peacock-base is a meta package (no files), so the
  # persistent base dirs have to ship inside a real dependency feather — peacock-init
  # is always installed by both the image builder and on-device ftr, so both paths
  # get a sane root. (/tmp is mounted as tmpfs at boot by peacock-init; the dir here
  # is just a fallback mountpoint.)
  mkdir -p "$pkgdir/etc" "$pkgdir/root" "$pkgdir/home" \
           "$pkgdir/var/tmp" "$pkgdir/var/lib" "$pkgdir/run" \
           "$pkgdir/bin" "$pkgdir/tmp"
  # NOTE: keep /root at the default 0755 here — a 0700 dir owned by the build user blocks the
  # feather packager (a different uid) from reading it ("permission denied"). The flavor ships its
  # own correctly-permissioned /root; the base /root is just a fallback home.
  chmod 1777 "$pkgdir/var/tmp" "$pkgdir/tmp"
  # /var/run -> /run: peacock-net puts the wpa_supplicant control socket here.
  ln -sf /run "$pkgdir/var/run"
}
