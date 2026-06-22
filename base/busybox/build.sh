# shellcheck shell=sh
# busybox — static cross build. prepare() (default) extracts the single
# tarball (strip 1); build() configures + compiles a static busybox, package()
# stages the single binary. Logic moved verbatim from the old inline script;
# CROSS_COMPILE/config-sed/stublib steps are byte-for-byte intentional.

build() {
  echo "Configuring Busybox..."
  make defconfig
  # The deprecated `tc` applet no longer builds against modern kernel
  # headers (the CBQ structs it uses were removed). Disable it.
  sed -i -e 's/^CONFIG_TC=y/# CONFIG_TC is not set/' .config
  # Use busybox's own crypt instead of libc's. glibc moved crypt() to libxcrypt,
  # which ships no static .a — so a NATIVE glibc static link (e.g. the x86_64
  # target) can't find libcrypt. (Cross toolchains bundle one; native doesn't.)
  sed -i -e 's/^# CONFIG_USE_BB_CRYPT is not set/CONFIG_USE_BB_CRYPT=y/' .config
  grep -q '^CONFIG_USE_BB_CRYPT=y' .config || echo 'CONFIG_USE_BB_CRYPT=y' >> .config
  yes "" | make oldconfig

  echo "Building static Busybox (CROSS_COMPILE=${CROSS_COMPILE:-native})..."
  # busybox's trylink still PROBES -lcrypt even with built-in crypt; on a native
  # glibc target there isn't even a static libcrypt.a to probe against. Drop an
  # empty stub on the link path so the probe succeeds and crypt is excluded
  # (harmless where a real libcrypt.a exists — bb-crypt never references it).
  STUBLIB="$(pwd)/.peacock-stublib"; mkdir -p "$STUBLIB"; ar crs "$STUBLIB/libcrypt.a"
  # LDFLAGS must be ONE arg (the -L has a space before it) or make eats "-L..."
  # as its own flag. CROSS_COMPILE (no spaces) can expand unquoted.
  CC_ARG=""
  [ -n "${CROSS_COMPILE:-}" ] && CC_ARG="CROSS_COMPILE=${CROSS_COMPILE}"
  make LDFLAGS="--static -L$STUBLIB" $CC_ARG -j"${jobs:-1}" busybox
}

package() {
  echo "Staging busybox -> /usr/bin/busybox ..."
  mkdir -p "$pkgdir/usr/bin"
  install -m 0755 busybox "$pkgdir/usr/bin/busybox"
}
