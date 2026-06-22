# shellcheck shell=sh
# build_type = "bootloader"
#
# Builds a firmware / boot image with `make` and installs it under
# /usr/share/peacock/bootloaders/. prepare() (extract) comes from default.sh.
#
# The port's ./build.sh sets these vars (no inline make logic needed):
#   make_target   make target(s)             e.g. "lk2nd-msm8953"
#                                             or  "bootimg-nokernel DEVICE=oppo-a16"
#   make_args     extra make vars (optional)  e.g. "TOOLCHAIN_PREFIX=arm-none-eabi-"
#   image         path to the built image     e.g. "build-lk2nd-msm8953/lk2nd.img"
#   artifact      installed filename          (optional; default basename "$image")
# Ports needing more can still override build()/package() in build.sh.

build() {
  [ -n "${make_target:-}" ] || peacock_die "bootloader: \$make_target unset (set it in build.sh)"
  # shellcheck disable=SC2086
  make -j"${jobs:-1}" ${make_args:-} ${make_target}
}

package() {
  [ -n "${image:-}" ] || peacock_die "bootloader: \$image unset"
  [ -f "$image" ] || peacock_die "bootloader: image not found at $image"
  name="${artifact:-$(basename "$image")}"
  install -Dm0644 "$image" "$pkgdir/usr/share/peacock/bootloaders/$name"
  peacock_msg "installed bootloader: $name"
}
