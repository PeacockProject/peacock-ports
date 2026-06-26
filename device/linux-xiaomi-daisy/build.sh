# shellcheck shell=sh
# linux-xiaomi-daisy — mainline msm8953 kernel + a PRP-trimmed recovery kernel
# from one source tree. Verbatim move of the former inline build: stage/ ->
# $pkgdir (OS kernel package); stage-prp/ kept as-is (the harness packages it
# as the linux-xiaomi-daisy-prp subpackage). prepare() extracts the source.
# UNVERIFIED — lead device + dual kernel; run a real build before trusting.

build() {
ARCH_DEF="${ARCH:-arm64}"
MAKE_ARGS="ARCH=$ARCH_DEF"
if [ -n "${CROSS_COMPILE:-}" ]; then
  MAKE_ARGS="$MAKE_ARGS CROSS_COMPILE=${CROSS_COMPILE}"
fi
JOBS="${PEACOCK_JOBS:-4}"
if [ -z "$JOBS" ] || [ "$JOBS" -lt 1 ]; then
  JOBS=1
fi

# Strip compiler-capability symbols an imported config bakes in; they must
# be re-derived for the toolchain actually building here.
sanitize_config() {
  sed -i \
    -e '/^CONFIG_CC_VERSION_TEXT=/d' \
    -e '/^CONFIG_CC_IS_/d' \
    -e '/^CONFIG_GCC_VERSION=/d' \
    -e '/^CONFIG_CLANG_VERSION=/d' \
    -e '/^CONFIG_AS_IS_/d' \
    -e '/^CONFIG_AS_VERSION=/d' \
    -e '/^CONFIG_LD_IS_/d' \
    -e '/^CONFIG_LD_VERSION=/d' \
    -e '/^CONFIG_LLD_VERSION=/d' \
    -e '/^CONFIG_CC_HAS_/d' \
    -e '/^CONFIG_CC_CAN_/d' \
    -e '/^CONFIG_TOOLS_SUPPORT_RELR=/d' \
    .config
}

# Daisy panel/touch DTS fixups. Idempotent (guarded greps / status flips),
# so applying once per pass on the shared tree is safe.
apply_daisy_dts() {
  for dts in \
    arch/arm64/boot/dts/qcom/msm8953-xiaomi-daisy.dts \
    arch/arm64/boot/dts/qcom/msm8953-xiaomi-daisy-r5.dts; do
    [ -f "$dts" ] || continue
    if grep -q 'compatible = "xiaomi,daisy-panel";' "$dts" 2>/dev/null; then
      sed -i \
        's/compatible = "xiaomi,daisy-panel";/compatible = "mdss,ili7807-fhdplus", "xiaomi,daisy-panel";/' \
        "$dts"
    fi
    sed -i '/&gt917d_ts {/,/};/ s/status = "disabled";/status = "okay";/' "$dts"
    sed -i '/&ft5406_ts {/,/};/ s/status = "disabled";/status = "okay";/' "$dts"
  done
}

# Sets DTB_TARGET / DTB_MAKE_TARGET for the daisy board.
detect_dtb() {
  DTB_TARGET=""
  DTB_MAKE_TARGET=""
  if [ -f "arch/arm64/boot/dts/qcom/msm8953-xiaomi-daisy.dts" ]; then
    DTB_TARGET="arch/arm64/boot/dts/qcom/msm8953-xiaomi-daisy.dtb"
    DTB_MAKE_TARGET="qcom/msm8953-xiaomi-daisy.dtb"
  elif [ -f "arch/arm64/boot/dts/qcom/msm8953-xiaomi-daisy-r5.dts" ]; then
    DTB_TARGET="arch/arm64/boot/dts/qcom/msm8953-xiaomi-daisy-r5.dtb"
    DTB_MAKE_TARGET="qcom/msm8953-xiaomi-daisy-r5.dtb"
  fi
}

# Stage the daisy DTB into $pkgdir/boot/dtbs/qcom (canonical name). Bulletproof:
# build the DTB if it's missing, accept either the standard or -r5 source, and
# FAIL LOUDLY if the staged file is empty. A silently-empty dtbs/ previously
# shipped a DTB-less kernel feather and bricked the boot ("No DTB configured").
stage_daisy_dtb() {
  mkdir -p "$pkgdir/boot/dtbs/qcom"
  # Ensure the DTB is actually built (an earlier make target may have skipped it).
  if [ -n "${DTB_MAKE_TARGET:-}" ] && [ ! -f "${DTB_TARGET:-/nonexistent}" ]; then
    make ${MAKE_ARGS:-} "$DTB_MAKE_TARGET" || true
  fi
  src=""
  for c in \
    "${DTB_TARGET:-}" \
    arch/arm64/boot/dts/qcom/msm8953-xiaomi-daisy.dtb \
    arch/arm64/boot/dts/qcom/msm8953-xiaomi-daisy-r5.dtb; do
    if [ -n "$c" ] && [ -f "$c" ]; then src="$c"; break; fi
  done
  [ -n "$src" ] || { echo "Error: daisy DTB not found after build"; exit 1; }
  cp "$src" "$pkgdir/boot/dtbs/qcom/msm8953-xiaomi-daisy.dtb"
  [ -s "$pkgdir/boot/dtbs/qcom/msm8953-xiaomi-daisy.dtb" ] || { echo "Error: staged daisy DTB is empty"; exit 1; }
  echo "Staged daisy DTB: $src ($(wc -c < "$src") bytes)"
}

##############################################################################
# PASS 1 — full kernel ($KERNEL_CONFIG) -> zImage (+ modules)
##############################################################################
echo "=== PASS 1: full daisy kernel (${KERNEL_CONFIG:-config}) ==="
cp "${KERNEL_CONFIG:-config}" .config
sanitize_config
echo "Refreshing config..."
yes "" | make $MAKE_ARGS olddefconfig

echo "Disabling pointer-auth flags that break with current GCC..."
if [ -x ./scripts/config ]; then
  ./scripts/config --disable ARM64_PTR_AUTH || true
  ./scripts/config --disable ARM64_PTR_AUTH_KERNEL || true
  ./scripts/config --disable BUILTIN_RETURN_ADDRESS_STRIPS_PAC || true
  ./scripts/config --disable CC_HAS_BRANCH_PROT_PAC_RET || true
  ./scripts/config --disable CC_HAS_BRANCH_PROT_PAC_RET_BTI || true
fi
yes "" | make $MAKE_ARGS olddefconfig

echo "Applying daisy critical built-ins for early panel/touch bring-up..."
if [ -x ./scripts/config ]; then
  for sym in \
    INPUT_EVDEV \
    INPUT_PM8941_PWRKEY \
    POWER_RESET_QCOM_PON \
    DRM \
    DRM_MSM \
    DRM_MSM_MDSS \
    DRM_MSM_MDP5 \
    DRM_MSM_DSI \
    DRM_MSM_DSI_14NM_PHY \
    DRM_PANEL \
    DRM_PANEL_MSM8953_GENERATED \
    DRM_PANEL_MDSS_ILI7807_FHDPLUS \
    TOUCHSCREEN_GOODIX \
    TOUCHSCREEN_EDT_FT5X06 \
    TOUCHSCREEN_FT6236
  do
    ./scripts/config --enable "$sym" || true
  done

  for sym in \
    DRM_PANEL_MDSS_OTM1911_FHD \
    DRM_PANEL_MDSS_OTM1911_FHDPLUS \
    DRM_PANEL_XIAOMI_OTM1911
  do
    ./scripts/config --disable "$sym" || true
  done
  # Force the wifi stack to build as modules. The full config has them =m, but a bare
  # olddefconfig drops them when their deps aren't pre-satisfied — exactly why the OS kernel
  # feather shipped ZERO .ko (no wlan0 on the base). Force the whole chain HERE, before the
  # single resolving olddefconfig below, so the subsystem stays on through resolution (mirrors
  # PASS 2). No extra olddefconfig — the existing one resolves everything.
  for sym in WCN36XX MAC80211 CFG80211 QCOM_WCNSS_CTRL RPMSG_CHAR QCOM_WCNSS_PIL QCOM_RPROC_COMMON QCOM_PIL_INFO; do
    ./scripts/config --module "$sym" || true
  done
fi

apply_daisy_dts
yes "" | make $MAKE_ARGS olddefconfig

detect_dtb
echo "Compiling kernel Image.gz + target DTB..."
if [ -n "$DTB_MAKE_TARGET" ]; then
  make $MAKE_ARGS -j"$JOBS" Image.gz "$DTB_MAKE_TARGET"
else
  # Fallback keeps build functional if upstream renames dtb targets.
  make $MAKE_ARGS -j"$JOBS" Image.gz dtbs
fi

# Full-kernel package tree (installed into the OS rootfs by ftr):
#   $pkgdir/boot/zImage            kernel image (Image.gz + dtb)
#   $pkgdir/boot/dtbs/qcom/...      device tree
#   $pkgdir/lib/modules/...         modules (busybox modprobe + depmod -b default path)
echo "Compiling modules..."
rm -rf "$pkgdir" stage-prp
mkdir -p "$pkgdir/boot"
if grep -q "^CONFIG_MODULES=y" .config 2>/dev/null; then
  make $MAKE_ARGS -j"$JOBS" modules
  # Install to /lib/modules (NOT /usr/lib/modules): the base's busybox modprobe and the
  # install-time `depmod -b <root>` both default to <root>/lib/modules. STRIP keeps it small.
  make $MAKE_ARGS modules_install INSTALL_MOD_STRIP=1 INSTALL_MOD_PATH="$pkgdir"
  # Drop the build/source symlinks (they dangle into the build chroot + confuse depmod).
  rm -f "$pkgdir"/lib/modules/*/build "$pkgdir"/lib/modules/*/source 2>/dev/null || true
  # Hard gate against the silent "0 .ko" regression: the wifi driver MUST be present.
  if ! ls "$pkgdir"/lib/modules/*/kernel/drivers/net/wireless/ath/wcn36xx/wcn36xx.ko* >/dev/null 2>&1; then
    echo "FATAL: wcn36xx.ko missing from the OS kernel package — wifi would be dead on the base"
    exit 1
  fi
fi

stage_daisy_dtb
# zImage is the gzip-compressed kernel ALONE. The DTB is passed separately via
# the extlinux `fdt` directive — arm64 has no appended-DTB support, so the old
# `cat Image.gz + dtb` just bloated zImage with trailing bytes lk2nd and the
# kernel both ignore (and masked the empty-dtbs bug above).
if [ -f "arch/arm64/boot/Image.gz" ]; then
  cp arch/arm64/boot/Image.gz "$pkgdir/boot/zImage"
elif [ -f "arch/arm64/boot/Image" ]; then
  cp arch/arm64/boot/Image "$pkgdir/boot/zImage"
else
  echo "Error: kernel image not found"
  exit 1
fi
# Ship the resolved kernel config (PRP's check-kernel-config.sh reads it).
cp .config "$pkgdir/boot/config"

##############################################################################
# PASS 2 — PRP-trimmed kernel ($PRP_KERNEL_CONFIG) -> zImage-prp
# Recovery-focused: no modules, trimmed stacks, single daisy panel built-in.
# Skipped when prp_kernel_config is unset.
##############################################################################
if [ -n "${PRP_KERNEL_CONFIG:-}" ] && [ -f "${PRP_KERNEL_CONFIG}" ]; then
  echo "=== PASS 2: PRP daisy kernel (${PRP_KERNEL_CONFIG}) ==="
  # Clean the tree so the very different config doesn't reuse pass-1 objects.
  # Keeps source (incl. the DTS fixups above) and our $pkgdir/ dir — EXCEPT `make clean`
  # find-deletes every *.ko/*.dtb in the tree, and $pkgdir is ./stage INSIDE the tree, so it
  # wipes the modules PASS 1 just staged into ./stage/lib/modules. That was the real reason the
  # OS kernel feather shipped ZERO .ko (no wlan0 on the base). Move them OUTSIDE the tree across
  # the clean, then restore. (The DTB hits the same trap and is re-staged at the end of build().)
  MODSAVE=""
  if [ -d "$pkgdir/lib/modules" ]; then
    MODSAVE="$(mktemp -d -t kmod-save-XXXXXX)"
    mv "$pkgdir/lib/modules" "$MODSAVE/modules"
  fi
  make $MAKE_ARGS clean || true
  if [ -n "$MODSAVE" ]; then
    mkdir -p "$pkgdir/lib"
    mv "$MODSAVE/modules" "$pkgdir/lib/modules"
    rmdir "$MODSAVE" 2>/dev/null || true
  fi

  cp "${PRP_KERNEL_CONFIG}" .config
  sanitize_config
  echo "Refreshing config..."
  yes "" | make $MAKE_ARGS olddefconfig

  echo "Applying PRP kernel trim (recovery-focused built-ins only)..."
  PRP_TMP="${PRP_TMP:-$(mktemp -d -t prp-build-XXXXXX)}"
  trap 'rm -rf "$PRP_TMP"' EXIT
  if [ -x ./scripts/config ]; then
    # Keep loadable-module support so the wifi stack can ship as .ko on the PRP
    # ROOTFS and be modprobe'd after it mounts. The boot part only boots into
    # prp-rootfs; wifi (wcn36xx) lives on the overlay, not the boot kernel.
    ./scripts/config --enable MODULES || true

    # The wifi stack stays modular; every OTHER modular symbol is disabled for a
    # lean, deterministic recovery kernel.
    WIFI_KEEP=" WCN36XX MAC80211 CFG80211 QCOM_WCNSS_CTRL RPMSG_CHAR QCOM_WCNSS_PIL QCOM_RPROC_COMMON QCOM_PIL_INFO "
    awk -F= '/^CONFIG_[A-Z0-9_]+=m$/{sub(/^CONFIG_/, "", $1); print $1}' "${PRP_KERNEL_CONFIG}" >"$PRP_TMP"/modules.list
    while IFS= read -r sym; do
      [ -n "$sym" ] || continue
      case "$WIFI_KEEP" in *" $sym "*) continue ;; esac
      ./scripts/config --disable "$sym" || true
    done <"$PRP_TMP"/modules.list
    # Force the wifi stack modular (olddefconfig may otherwise drop/flip them).
    for sym in WCN36XX MAC80211 CFG80211 QCOM_WCNSS_CTRL RPMSG_CHAR QCOM_WCNSS_PIL QCOM_RPROC_COMMON QCOM_PIL_INFO; do
      ./scripts/config --module "$sym" || true
    done

    # Trim heavy non-recovery stacks that materially increase build time.
    cat >"$PRP_TMP"/trim-force-n.list <<'EOF'
MEDIA_SUPPORT
SOUND
XFS_FS
BTRFS_FS
NFS_FS
NFSD
NFS_V4
NFS_V3
NFS_V2
CIFS
SMB_SERVER
9P_FS
AF_RXRPC
RDS
TIPC
CAIF
NFC
BT
IP_DCCP
IP_SCTP
USB_STORAGE
USB_UAS
USB_HID
USB_NET_DRIVERS
HID_PICOLCD
HID_STEAM
HID_NINTENDO
HID_PLAYSTATION
HID_XBOX
HID_XIAOMI
EOF
    while IFS= read -r sym; do
      [ -n "$sym" ] || continue
      ./scripts/config --disable "$sym" || true
    done < "$PRP_TMP"/trim-force-n.list

    # Force minimal symbols required by PRP on daisy.
    cat >"$PRP_TMP"/trim-force-y.list <<'EOF'
DEVTMPFS
DEVTMPFS_MOUNT
EXT4_FS
MMC
MMC_BLOCK
INPUT
INPUT_EVDEV
TOUCHSCREEN_GOODIX
TOUCHSCREEN_EDT_FT5X06
TOUCHSCREEN_FT6236
EOF
    while IFS= read -r sym; do
      [ -n "$sym" ] || continue
      ./scripts/config --enable "$sym" || true
    done < "$PRP_TMP"/trim-force-y.list
  fi

  echo "Applying PRP display policy (single daisy panel)..."
  # PRP should not rely on initramfs module loading. Keep only the daisy panel
  # reported by lk2nd/fastboot OEM data as built-in.
  cat >"$PRP_TMP"/display-force-y.list <<'EOF'
CONFIG_DRM
CONFIG_DRM_MSM
CONFIG_DRM_MSM_MDSS
CONFIG_DRM_MSM_MDP5
CONFIG_DRM_MSM_DSI
CONFIG_DRM_MSM_DSI_14NM_PHY
CONFIG_DRM_PANEL
CONFIG_DRM_PANEL_MSM8953_GENERATED
CONFIG_DRM_PANEL_MDSS_ILI7807_FHDPLUS
CONFIG_BACKLIGHT_CLASS_DEVICE
CONFIG_LCD_CLASS_DEVICE
CONFIG_EXTCON
EOF
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    sed -i \
      -e "/^${key}=.*/d" \
      -e "/^# ${key} is not set$/d" \
      .config
    printf '%s=y\n' "$key" >> .config
  done < "$PRP_TMP"/display-force-y.list

  cat >"$PRP_TMP"/display-force-n.list <<'EOF'
CONFIG_DRM_PANEL_MDSS_ILI7807_FHD
CONFIG_DRM_PANEL_MDSS_OTM1911_FHD
CONFIG_DRM_PANEL_MDSS_OTM1911_FHDPLUS
CONFIG_DRM_PANEL_MDSS_OTM1911
CONFIG_DRM_PANEL_XIAOMI_OTM1911
CONFIG_DRM_PANEL_HIMAX_HX8399C_FHDPLUS
CONFIG_DRM_PANEL_TENOR_HX8399C_AUO
CONFIG_DRM_PANEL_XIAOMI_YSL_HX8394F
EOF
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    sed -i \
      -e "/^${key}=.*/d" \
      -e "/^# ${key} is not set$/d" \
      .config
    printf '# %s is not set\n' "$key" >> .config
  done < "$PRP_TMP"/display-force-n.list

  apply_daisy_dts
  yes "" | make $MAKE_ARGS olddefconfig

  # Re-assert touchscreen drivers as built-ins, then a FINAL module sweep: with
  # MODULES=y the repeated olddefconfig passes re-default many symbols to =m, so
  # keep ONLY the wifi stack modular and disable everything else (lean kernel).
  if [ -x ./scripts/config ]; then
    ./scripts/config --enable TOUCHSCREEN_GOODIX || true
    ./scripts/config --enable TOUCHSCREEN_EDT_FT5X06 || true
    ./scripts/config --enable TOUCHSCREEN_FT6236 || true
    yes "" | make $MAKE_ARGS olddefconfig
    WIFI_KEEP=" WCN36XX MAC80211 CFG80211 QCOM_WCNSS_CTRL RPMSG_CHAR QCOM_WCNSS_PIL QCOM_RPROC_COMMON QCOM_PIL_INFO "
    awk -F= '/^CONFIG_[A-Z0-9_]+=m$/{sub(/^CONFIG_/,"",$1);print $1}' .config >"$PRP_TMP"/m-final.list
    while IFS= read -r sym; do
      [ -n "$sym" ] || continue
      case "$WIFI_KEEP" in *" $sym "*) continue ;; esac
      ./scripts/config --disable "$sym" || true
    done <"$PRP_TMP"/m-final.list
    for sym in WCN36XX MAC80211 CFG80211 QCOM_WCNSS_CTRL RPMSG_CHAR QCOM_WCNSS_PIL QCOM_RPROC_COMMON QCOM_PIL_INFO; do
      ./scripts/config --module "$sym" || true
    done
    yes "" | make $MAKE_ARGS olddefconfig
  fi

  # MODULES is intentionally ON now (the wifi stack ships as .ko on the rootfs).
  # Flag — but don't fail on — any NON-wifi module that survived (deps selected
  # by built-ins can't be dropped; they're harmless, just note them).
  STRAY_M=$(awk -F= '/^CONFIG_[A-Z0-9_]+=m$/{sub(/^CONFIG_/,"",$1);print $1}' .config \
    | grep -ivE '^(WCN36XX|MAC80211|CFG80211|QCOM_WCNSS_CTRL|RPMSG_CHAR|QCOM_WCNSS_PIL|QCOM_RPROC_COMMON|QCOM_PIL_INFO)$' || true)
  if [ -n "$STRAY_M" ]; then
    echo "Note: non-wifi modules still =m after PRP trim (harmless):"
    echo "$STRAY_M" | tr '\n' ' '; echo
  fi

  if grep -E '^CONFIG_DRM_PANEL_.*OTM1911.*=y$' .config >"$PRP_TMP"/display-otm1911-clash.list 2>/dev/null; then
    echo "Error: conflicting OTM1911 panel symbols still enabled:"
    cat "$PRP_TMP"/display-otm1911-clash.list
    exit 1
  fi

  detect_dtb
  if [ -z "$DTB_MAKE_TARGET" ]; then
    echo "Error: daisy DTB source not found"
    exit 1
  fi
  echo "Compiling PRP kernel Image.gz + daisy DTB only..."
  make $MAKE_ARGS -j"$JOBS" Image.gz "$DTB_MAKE_TARGET"

  # Build + stage the (wifi) modules. They are NOT in the boot kernel — they ship
  # under stage-prp/usr/lib/modules and get modprobe'd from the PRP rootfs after
  # it mounts. INSTALL_MOD_STRIP keeps them small.
  echo "Compiling PRP kernel modules (wifi stack)..."
  make $MAKE_ARGS -j"$JOBS" modules
  make $MAKE_ARGS modules_install INSTALL_MOD_STRIP=1 INSTALL_MOD_PATH="$PWD/stage-prp/usr"
  # Drop the build/source symlinks (they point into the build chroot).
  rm -f stage-prp/usr/lib/modules/*/build stage-prp/usr/lib/modules/*/source 2>/dev/null || true

  # PRP-kernel package tree (stage-prp/) — packaged separately as
  # linux-xiaomi-daisy-prp, a build dependency of PRP images only, never
  # shipped in the OS rootfs. It IS the kernel within that package, so it
  # is just boot/zImage (Image.gz + dtb concatenated).
  prp_dtb=""
  for d in \
    arch/arm64/boot/dts/qcom/msm8953-xiaomi-daisy.dtb \
    arch/arm64/boot/dts/qcom/msm8953-xiaomi-daisy-r5.dtb; do
    [ -f "$d" ] && prp_dtb="$d" && break
  done
  [ -n "$prp_dtb" ] || { echo "Error: PRP daisy DTB not found after build"; exit 1; }
  mkdir -p stage-prp/boot
  cat arch/arm64/boot/Image.gz "$prp_dtb" > stage-prp/boot/zImage
  cp .config stage-prp/boot/config
fi

# PASS 2's `make clean` recursively deletes EVERY *.dtb in the tree, including
# the one PASS 1 staged into $pkgdir/boot/dtbs (zImage/config survive — they're
# not *.dtb). Re-stage the main DTB now: it's hardware-only and identical
# across the two kernel configs, so the just-rebuilt one is correct. Without
# this the feather ships an empty dtbs/, extlinux gets no `fdt`, and the device
# dies at boot with "No DTB configured".
stage_daisy_dtb

# Final gate: the wifi modules MUST survive into the package. PASS 2's `make clean` wiped them
# before (the move-aside above fixes that) — fail loudly rather than silently shipping a base with
# no wlan0 again.
if ! ls "$pkgdir"/lib/modules/*/kernel/drivers/net/wireless/ath/wcn36xx/wcn36xx.ko* >/dev/null 2>&1; then
  echo "FATAL: wcn36xx.ko missing from \$pkgdir after PASS 2 — wifi would be dead on the base"
  exit 1
fi
}

package() { :; }
