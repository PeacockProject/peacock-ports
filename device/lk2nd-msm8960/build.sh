# shellcheck shell=sh
# lk2nd-msm8960 — bootloader type does extract + `make lk2nd-msm8960` + install.
# One SoC-wide image; the specific device (e.g. samsung-jflte) is auto-detected
# at runtime via DT probing. arm-none-eabi via c-toolchain.

make_args="TOOLCHAIN_PREFIX=arm-none-eabi-"
make_target="lk2nd-msm8960"
image="build-lk2nd-msm8960/lk2nd.img"
artifact="lk2nd-msm8960.img"
