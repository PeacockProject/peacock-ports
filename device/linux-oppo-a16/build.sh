# shellcheck shell=sh
# linux-oppo-a16 — single MTK 4.19 vendor kernel.
#
# All build logic lives in the kernel build type (lib/build/kernel.sh):
# defconfig -> sanitize -> Image.gz + dtb -> stage. This port only supplies the
# device knobs below. (Define kernel_configure()/kernel_prepare_tree() here if
# this device ever needs config/DTS tweaks.)
#
# UNVERIFIED MTK 4.19 vendor build — may need iteration:
#   * defconfig: $OPPO_A16_DEFCONFIG overrides (tree also ships
#     oppo6765_20375_defconfig / oppo6765_21281_defconfig).
#   * toolchain: build.config.mtk.aarch64.gcc exists, so cross-GCC should work.

kernel_defconfig="${OPPO_A16_DEFCONFIG:-oppo6765_defconfig}"
kernel_dtb="mediatek/oppo6765_20379"
