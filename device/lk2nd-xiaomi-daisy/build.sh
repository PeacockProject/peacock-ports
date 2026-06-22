# shellcheck shell=sh
# lk2nd-xiaomi-daisy — bootloader type does extract + `make` + install.
# lk2nd-msm8953 is the SoC-wide target; daisy is auto-detected at runtime via
# DT probing. arm-none-eabi via c-toolchain.

make_args="TOOLCHAIN_PREFIX=arm-none-eabi-"
make_target="lk2nd-msm8953"
image="build-lk2nd-msm8953/lk2nd.img"
artifact="lk2nd-xiaomi-daisy.img"
