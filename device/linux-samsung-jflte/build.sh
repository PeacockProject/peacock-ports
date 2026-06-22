# shellcheck shell=sh
# linux-samsung-jflte — LineageOS msm8960 (arm-eabi) 32-bit kernel. build() is
# the former inline build verbatim (3 patches + gcc-wrapper py3 fixup + zImage
# + modules into ./stage); package() stages the outputs into $pkgdir/boot +
# /lib/modules. Single kernel (no prp_kernel_config). UNVERIFIED — run a build.

build() {
echo "Copying config..."
cp "${KERNEL_CONFIG:-config}" .config

echo "Applying netns compatibility patch..."
patch -p1 < netns-compat.patch

echo "Disabling downstream continuous splash path..."
patch -p1 < disable-cont-splash.patch

echo "Applying Samsung USB composite Kconfig compatibility patch..."
patch -p1 < usb-samsung-composite-kconfig.patch

echo "Compiling Kernel (Real)..."
# Keep this build fully inside the chroot and avoid host toolchains.
# We rely on ARCH (set by the builder) and only use CROSS_COMPILE if provided.
perl - <<'PL'
use strict;
use warnings;

my $path = "scripts/gcc-wrapper.py";
exit 0 unless -f $path;

open my $in, "<", $path or die $!;
my @out;
while (my $line = <$in>) {
    chomp $line;
    if ($line =~ /^(\s*)print\s*>>\s*sys\.stderr\s*,\s*(.*)$/) {
        my ($indent, $expr) = ($1, $2);
        $expr =~ s/\s+$//;
        if ($expr =~ s/,\s*$//) {
            $line = $indent . "print(" . $expr . ", end=' ', file=sys.stderr)";
        } else {
            $line = $indent . "print(" . $expr . ", file=sys.stderr)";
        }
    }
    if ($line =~ /^\s*interpret_warning\(line\)\s*$/) {
        $line =~ s/interpret_warning\(line\)/interpret_warning(line.decode(errors='replace') if isinstance(line, bytes) else line)/;
    }
    if ($line =~ /^if __name__ == '__main__':/) {
        push @out, "def interpret_warning(line):";
        push @out, "    return";
    }
    push @out, $line;
}
close $in;

open my $outf, ">", $path or die $!;
print $outf join("\n", @out) . "\n";
PL
MAKE_ARGS="ARCH=${ARCH:-arm} KCFLAGS=-Wno-error"
if [ -n "${CROSS_COMPILE:-}" ]; then
  MAKE_ARGS="$MAKE_ARGS CROSS_COMPILE=${CROSS_COMPILE}"
fi
JOBS="${PEACOCK_JOBS:-4}"
if [ -z "$JOBS" ] || [ "$JOBS" -lt 1 ]; then
  JOBS=1
fi
yes "" | make $MAKE_ARGS oldconfig
make $MAKE_ARGS -j"$JOBS" zImage
# Only build modules if they're enabled in the config
if grep -q "^CONFIG_MODULES=y" .config 2>/dev/null; then
  make $MAKE_ARGS -j"$JOBS" modules
  rm -rf stage
  mkdir -p stage
  make $MAKE_ARGS modules_install INSTALL_MOD_PATH="$(pwd)/stage"
else
  echo "Modules disabled in config, skipping module build"
  rm -rf stage
  mkdir -p stage
fi

if [ ! -f "arch/arm/boot/zImage" ]; then
    echo "Error: zImage not found after build!"
    exit 1
fi

# Move artifact to root of build dir so builder finds it (mock expectation)
cp arch/arm/boot/zImage zImage
if [ -d "stage/lib/modules" ]; then
  tar -czf modules.tar.gz -C stage lib/modules
fi
}

package() {
  mkdir -p "$pkgdir/boot"
  cp zImage "$pkgdir/boot/zImage"
  cp .config "$pkgdir/boot/config"
  if [ -d stage/lib/modules ]; then
    mkdir -p "$pkgdir/lib"
    cp -a stage/lib/modules "$pkgdir/lib/modules"
  fi
}
