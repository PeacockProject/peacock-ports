# shellcheck shell=sh
# lk2nd-samsung-jflte — bootloader type does extract + `make` + install.
# lk2nd-msm8960 is the SoC-wide target; jflte is auto-detected at runtime via
# DT probing (samsung,jflte / qcom,msm8960). arm-none-eabi via c-toolchain.

make_args="TOOLCHAIN_PREFIX=arm-none-eabi-"
make_target="lk2nd-msm8960"
image="build-lk2nd-msm8960/lk2nd.img"
artifact="lk2nd-samsung-jflte.img"
