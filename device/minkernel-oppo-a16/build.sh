# shellcheck shell=sh
# minkernel-oppo-a16 — the bootloader type (lib/build/bootloader.sh) extracts,
# runs `make $make_args $make_target`, and installs $image under
# /usr/share/peacock/bootloaders/. This port only names the target + output.
#
# DEVICE is passed explicitly even though the Makefile defaults to oppo-a16, so
# the port stays self-documenting / copy-pasteable to sibling devices.

make_target="bootimg-nokernel DEVICE=oppo-a16"
image="out/bootimg/mk-oppo-a16-boot.img"
artifact="mk-oppo-a16-boot.img"
