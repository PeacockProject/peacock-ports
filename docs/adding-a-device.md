# Adding a new device to peacock-ports

A walkthrough of bringing up a fresh mobile device under Peacock: how the
port files in `peacock-ports/device/` relate, what the minimum set is, and
how to iterate when the first boot inevitably fails. The two worked examples
at the end of this doc — `oppo-a16` (MediaTek MT6765) and `xiaomi-daisy`
(Qualcomm msm8953) — are the canonical patterns for MTK and qcom devices
respectively.

This doc only describes what is already in the tree. Where something is
under-documented in the actual ports, it is flagged inline as a **TODO**
rather than guessed at.

## 1. Prerequisites

On the host:

- A Linux host with passwordless `sudo`. The Peacock CLI shells out to
  `sudo` ~30 times during chroot + loop-device setup; this is tracked as
  tech-debt in `Peacock/BACKLOG.md` ("Replace `exec.Command(\"sudo\", ...)`
  everywhere").
- The full Peacock CLI toolchain — see `Peacock/README.md`. Until
  `peacock doctor` lands, the explicit list of host prereqs is scattered
  across `internal/host/`.
- `fastboot` (Android platform tools) on the host.
- `adb` is convenient but optional.
- A serial / UART cable if the SoC exposes one — invaluable for early-boot
  failures. TODO: the maintainer noted UART was not packed for oppo-a16 (see
  the "UART fallback" entry in `Peacock/BACKLOG.md`); on devices with no
  exposed UART, the PRP recovery rootfs is the primary debug channel.

On the device:

- Unlocked bootloader. Method varies wildly by OEM — Xiaomi requires an
  account + waiting period, OnePlus / OPPO require `fastboot oem unlock` or
  vendor-specific tools, Samsung Knox-fused devices may be unrecoverable.
- Either fastboot mode access (`adb reboot bootloader` or hardware key
  combo), OR a writable recovery partition you can sideload to. PRP can be
  flashed via either path; without one of the two there is no way in.

## 2. Identify the device

Before opening an editor, collect:

| Question | Where to find it |
|---|---|
| SoC | XDA threads, GSMArena, `/proc/cpuinfo` from any working Android shell. |
| Bootloader stack | Stock = `aboot` / Little Kernel for Qualcomm, MTK preloader for MediaTek. |
| Partition table | `cat /proc/partitions` on a working Android. For the canonical fastboot offsets, the GPT itself; `parted` will dump it. |
| Stock boot.img layout | `unpack_bootimg` (from Android platform tools or `mkbootimg`'s helper): gives you `base`, `kernel_offset`, `ramdisk_offset`, etc., that go into `device.toml`. |
| Kernel version that boots stock | Decompress `kernel` out of the stock boot.img, run `strings | grep "Linux version"`. |
| Mainline support status | Check the [postmarketOS device wiki](https://wiki.postmarketos.org/), kernel.org, and `msm8953-mainline/linux` (or the SoC's equivalent fork). |

Pick a device codename. The convention in this tree is OEM-shortcode joined
with a model token: `oppo-a16`, `xiaomi-daisy`, `samsung-jflte`. All
following filenames bake this in.

## 3. The minimum port set

Every device needs **at least** these four ports under `peacock-ports/`:

```
device/
├── <name>/                       device meta + boot params
│   ├── device.toml                 boot offsets, arch, quirks
│   └── package.toml                meta package pulling in everything else
│
├── linux-<name>/                 kernel package
│   └── package.toml                source + build script → stage/zImage
│
├── <bootloader-port>/            one of:
│   ├── minkernel-<name>/           MTK: builds mk chainloader boot.img
│   └── lk2nd-<name>/               qcom: builds lk2nd secondary bootloader
│
└── (optional but common)
    ├── firmware-<name>/          vendor blob extractor / installer
    ├── <name>-display-fix/       OpenRC + Xorg quirks for the panel
    ├── <name>-debug-netssh/      sshd-over-USB for early-boot debug
    └── <name>-sddm-quirk/        SDDM workarounds (e.g. `legacy-rootfs-ext4`)
```

### 3.1 `device/<name>/device.toml`

Boot-time parameters. The Peacock CLI parses this to drive `mkbootimg`.
Required keys, copied from `device/oppo-a16/device.toml`:

```toml
[device]
name = "OPPO A16"
architecture = "aarch64"           # or "armv7h"
flash_method = "fastboot-bootimg"  # only flow supported today

[boot]
cmdline = ""                       # extra kernel cmdline; ok to leave empty
generate_bootimg = true            # always true today

[boot.android]                     # Android boot.img header offsets
base           = "0x40078000"
page_size      = 2048
kernel_offset  = "0x00008000"
ramdisk_offset = "0x11a88000"
second_offset  = "0xbff88000"
tags_offset    = "0x07808000"

[quirks]
keep_fb_refresher_with_dm = false
xorg_force_vt1            = false
use_fb_refresher          = false
legacy_rootfs_ext4        = false
```

Get the `[boot.android]` values from `unpack_bootimg` on the stock boot.img.
Wrong offsets are the #1 cause of a silent-brick first boot — the device
will accept the image, fastboot will report success, and nothing comes up.

TODO: `[quirks]` are documented inline only via their consumers in
`internal/userland/`. A schema page for `device.toml` does not yet exist; new
quirk additions land in the Go side and propagate by example.

### 3.2 `device/<name>/package.toml`

A thin meta package that declares the per-device runtime dependency set. See
`device/oppo-a16/package.toml`: the body is essentially a 30-line
`dependencies_openrc = [...]` array and a no-op `script`. The point is to
have a single port that pulls in `linux-<name>`, the display-fix, and the
base userland in one shot.

### 3.3 Kernel: `device/linux-<name>/package.toml`

Two patterns live in the tree today:

- **Prebuilt** (oppo-a16 path). `source` points at a local tarball produced
  out-of-band — see `device/linux-oppo-a16/package.toml`'s
  `source = "file:///.../linux-oppo-a16-local-kernel-ab.tar.gz"`. The build
  script just copies `zImage` into `stage/`. This works while the kernel
  source lives elsewhere (e.g. the `experiments/android_kernel_oppo_mt6765`
  repo for MT6765 — see your local memory at
  `reference_kernel_source.md` for the path).
- **From-source** (xiaomi-daisy path). `source` is an upstream tarball URL;
  the build script applies a config, patches DTS files in-tree, builds
  `Image.gz`, and assembles a `zImage` (Image.gz + DTB). See
  `device/linux-xiaomi-daisy/package.toml`. The script also handles a `prp`
  kernel profile via `PEACOCK_KERNEL_PROFILE=prp` that disables modules for
  the recovery-kernel build.

Whichever pattern you pick, the artifact contract is **`stage/zImage`** at
the manifest's top level. Optionally also `stage/modules.tar.gz` if you
shipped modules (most peacockos targets do not — see the "Common pitfalls"
section below).

### 3.4 Bootloader

- **MediaTek**: add `device/minkernel-<name>/package.toml`. Pattern in
  `device/minkernel-oppo-a16/`: pulls `PeacockProject/MinKernel`, runs
  `make -C mk bootimg-nokernel DEVICE=<name>`, installs
  `mk-<name>-boot.img` at `stage/usr/share/peacock/bootloaders/`. The mk
  chainloader is a kernel-less Android boot.img you flash into the
  recovery slot; on boot it stages the real kernel from fastboot or from
  a known partition.

- **Qualcomm**: add `device/lk2nd-<name>/package.toml`. Pattern in
  `device/lk2nd-xiaomi-daisy/`: pulls `PeacockProject/lk2nd_peacock`,
  builds `make TOOLCHAIN_PREFIX=arm-none-eabi- lk2nd-<soc>` (e.g.
  `lk2nd-msm8953`), installs `lk2nd-<name>.img` at the same staging path.
  lk2nd auto-detects the device at runtime via DT probing — no per-device
  `LK2ND_DEVICE` knob for msm8953. Other SoCs may need it; check the
  lk2nd-msm8960 / msm8660 case for `samsung-jflte` (status: in progress —
  see `Peacock/task.md`).

TODO: there is no shared "bootloader" abstraction yet. The Peacock CLI hardcodes
the artifact path `/usr/share/peacock/bootloaders/`; both ports follow that
convention by hand.

### 3.5 Optional fix-up ports

These are not strictly required but the worked examples in the tree all
ship them:

- **`firmware-<name>/`** — extracts vendor blobs from a stock dump and
  installs them at `/lib/firmware/...`. Required if mainline lacks the
  WiFi/BT/GPU firmware; some devices boot far enough without it to be
  worth deferring.
- **`<name>-display-fix/`** — OpenRC service + Xorg config that runs at boot
  to coax the display pipeline into a working state.
  `device/oppo-a16-display-fix/package.toml` is the canonical example: ~500
  lines of OpenRC init script + Xorg config + xfwm4 wrapper. Most of it
  is MTK-specific (`FBIOPAN_DISPLAY` to coax MTKFB out of DECOUPLE mode,
  Mali render-only DRM device removal, VT-switch wrapper). Qualcomm
  msm8953 + DRM/KMS does not need this much fuss; daisy's
  `samsung-jflte-display-fix` and `samsung-jflte-fbdev-compat` are shorter.
- **`<name>-debug-netssh/`** — sshd-over-USB for early-boot debug. Pattern
  in `xiaomi-daisy-debug-netssh`.

## 4. Worked examples

### 4.1 oppo-a16 (MTK MT6765, prebuilt kernel path)

```
device/
├── oppo-a16/
│   ├── device.toml         aarch64 + Android boot.img offsets
│   └── package.toml        meta: depends on linux-oppo-a16 + display-fix +
│                           base userland
├── linux-oppo-a16/
│   └── package.toml        source=file:///.../linux-oppo-a16-local-…tar.gz;
│                           script copies zImage to stage/
├── minkernel-oppo-a16/
│   └── package.toml        builds mk-oppo-a16-boot.img from
│                           PeacockProject/MinKernel
└── oppo-a16-display-fix/
    └── package.toml        ~500-line OpenRC init script:
                            cgroup-v1 mode, fb0 seat tag, MTKFB DECOUPLE
                            workaround, Xorg-vt1 wrapper, xfwm4 compositor=off
```

The MTK boot story: flash `mk-oppo-a16-boot.img` once into the recovery
slot. On every subsequent reboot, mk runs first, then either jumps to the
peacock-staged kernel partition or waits for a fastboot kernel-stage.

### 4.2 xiaomi-daisy (qcom msm8953, mainline kernel)

```
device/
├── xiaomi-daisy/
│   ├── device.toml         aarch64; xorg_force_vt1=true quirk
│   └── package.toml        meta package
├── linux-xiaomi-daisy/
│   ├── config              kernel .config baked into the port
│   └── package.toml        from-source: msm8953-mainline/linux v6.16.3-r0,
│                           in-script DTS patches for the daisy panel,
│                           PEACOCK_KERNEL_PROFILE=prp branch disables
│                           modules for the recovery kernel
├── linux-xiaomi-daisy-prp/
│   └── package.toml        sibling port using $PRP_TMP scratch dir
├── lk2nd-xiaomi-daisy/
│   └── package.toml        builds lk2nd-msm8953 with
│                           arm-none-eabi- toolchain; auto-detects daisy at
│                           runtime via DT probe
└── firmware-xiaomi-daisy/
    └── package.toml        vendor blob installer
```

The qcom boot story: flash `lk2nd-xiaomi-daisy.img` to the `aboot` /
`boot` partition (depending on slot layout). lk2nd takes over from the
stock primary bootloader and either chainloads the peacock kernel.img or
drops to its built-in fastboot.

## 5. Building

End-to-end, once the four ports above exist:

```sh
cd Peacock
./peacock build-packages --device <name> -p linux-<name>
```

That runs **just** the kernel port build, which is the slow loop. It also
caches the chroot, so the second run is fast. To build everything that
goes on the device:

```sh
./peacock build --device <name> --init openrc
```

Outputs land in `Peacock/out/`:

- `boot.img` — kernel + initramfs in Android boot.img format.
- `mk-<name>-boot.img` or `lk2nd-<name>.img` — the bootloader artifact,
  copied out of the bootloader port's stage.
- `rootfs.tar.gz` — base userland.

Flag this in your head: the **first** time you build a device, expect at
least one of the four ports to fail. The build chroot caches successful
ports, so iterating one port at a time is fast.

## 6. First boot

Flow on hardware:

1. Boot the device into fastboot mode.
2. Flash the bootloader artifact once (`fastboot flash boot ...` for MTK
   mk; `fastboot flash aboot ...` or `boot` for qcom lk2nd — partition
   layout varies).
3. Stage the kernel boot.img and the rootfs. The exact handoff between
   peacock + mk/lk2nd is device-specific; see your local memory at
   `project_mk_stage_kernel.md` for the oppo-a16 workflow, and
   `feedback_flash_kernel.md` for the "flash directly to `peacock_boot` to
   avoid repeated staging" trick.
4. Reboot. Look at the screen.

What to expect:

- Splash from `peacock-splash` within ~5 seconds.
- Console scrollback (if you have UART) showing kernel boot → initramfs →
  pivot_root → OpenRC.
- SDDM login within ~30 seconds.

If none of that happens:

- **PRP** — the Peacock Recovery Partition. Flash a PRP boot.img into a
  separate slot and boot it instead. PRP gives you a serial console and a
  network-over-USB sshd; from there `dmesg`, `journalctl`, and disk
  inspection are all available.
- **ramoops** — kernel pstore. If the kernel panicked before pivot_root,
  the trace lands at `/sys/fs/pstore/console-ramoops-0` on the next boot.
  PRP mounts pstore by default.
- **fastboot recovery** — for MTK mk, you can re-enter fastboot from the
  mk stage menu (the maintainer's "post-touch-fix workflow" — TODO,
  documented in MinKernel's README but not echoed here).

## 7. Iteration loop

The fast inner loop:

1. Edit `package.toml` (or the kernel `config` for daisy-style ports).
2. `./peacock build-packages --device <name> -p <port>`.
3. Flash + reboot. For MTK: re-stage via `fastboot boot <new-boot.img>`
   instead of re-flashing. For qcom: `fastboot boot kernel.img` similarly.
4. Read PRP / UART / `dmesg` over USB.
5. Repeat.

TODO: per your local memory at `feedback_chroot_test.md`: chroot-test
services from PRP before booting peacockos live. The walkthrough should
echo this but the canonical workflow has not been written up in-tree.

## 8. Common pitfalls

- **Kernel config still has `CONFIG_MODULES=y`.** Peacockos does not
  package kernel modules yet (the OpenRC `modules` service hangs because
  the modules tree is not staged into the rootfs — see `Peacock/BACKLOG.md`
  "modules service hangs" and your local memory at
  `project_modules_service.md`). Disable modules in the kernel config and
  build all required drivers in-tree until module packaging lands. The
  xiaomi-daisy port already disables modules via its `prp` profile branch;
  use it as a reference.

- **Missing DTB selection.** The Peacock CLI auto-discovers the DTB out of
  the kernel build tree via `discoverKernelDTB` in
  `Peacock/cmd/peacock/build.go`, which scores candidate `.dtb` files
  against tokens extracted from the device name (so `oppo-a16` matches
  `*oppo*a16*.dtb`). If your device name does not tokenize into the DTB
  filename, the wrong DTB gets picked. Workaround: rename DTBs in the build
  script to include the device codename tokens. TODO: there is no explicit
  `dtb = "..."` knob in `device.toml` today; adding one would remove the
  guesswork.

- **Touchscreen drivers being kernel modules.** Same symptom as above:
  driver builds, modules.tar.gz contains it, peacock never installs it,
  touch never works. Build the touch driver in-tree in the kernel config
  (xiaomi-daisy enables `TOUCHSCREEN_GOODIX`, `TOUCHSCREEN_EDT_FT5X06`,
  `TOUCHSCREEN_FT6236` as built-ins for this reason).

- **SCP timeout on MTK.** MK's stage0 takes long enough that SCP (the
  sensor coprocessor) hits its boot timeout and crashes — leading to a
  NULL `sensorHub` deref ~18s in. MinKernel has SCP-reinit work that
  papers over this in the handoff; see your local memory at
  `project_scp_reinit.md`. TODO: SCP reinit was added but is not yet
  end-to-end verified working (see `Peacock/BACKLOG.md` "Boot stack" →
  "mk SCP reinit").

- **Wrong Android boot.img offsets.** The device fastboot-flashes the
  image, returns success, and then never gets to kernel decompression.
  Re-verify `[boot.android]` against `unpack_bootimg` of the stock boot.img;
  pay particular attention to `base` (the address everything else is
  relative to) and `page_size` (2048 for older SoCs, 4096 for newer).

- **PRP USB transfer speed slow.** TODO: open question per your local memory
  at `project_prp_usb_speed.md`. If you need to push a large rootfs over
  USB and it crawls, you're not imagining it — known issue.

- **`fastboot stage` re-runs every boot.** Once kernel iteration settles,
  flash to the `peacock_boot` partition directly from PRP to avoid the
  re-staging cycle (your local memory at `feedback_flash_kernel.md`).

## 9. References

- **`peacock-ports/SCHEMA.md`** — full manifest schema reference, including
  the `[install]` table and the worked examples for each layout.
- **`peacock-ports/device/oppo-a16/device.toml`** — canonical MTK
  `device.toml`. The Android boot.img `[boot.android]` table is the
  load-bearing block; copy and adjust offsets for your device.
- **`peacock-ports/device/xiaomi-daisy/device.toml`** — canonical qcom
  `device.toml`. Note `xorg_force_vt1 = true` — daisy needs Xorg held on
  VT1 because of MSM DRM behaviour, an example of how a quirk flips on or
  off per device.
- **`peacock-ports/device/linux-oppo-a16/package.toml`** — prebuilt kernel
  pattern. Three lines of script.
- **`peacock-ports/device/linux-xiaomi-daisy/package.toml`** — from-source
  kernel pattern. ~180 lines of script: config patching, DTS sed-fixups,
  DTB discovery, `Image.gz + DTB → zImage` assembly, optional modules
  stage. Useful as a copy-paste base for any mainline-based port.
- **`peacock-ports/device/minkernel-oppo-a16/package.toml`** — MTK
  bootloader port. Pattern is "tarball-from-master + `make
  bootimg-nokernel DEVICE=<name>` + install to /usr/share/peacock/
  bootloaders/".
- **`peacock-ports/device/lk2nd-xiaomi-daisy/package.toml`** — qcom
  bootloader port. Same shape, different `make` line.
- **`peacock-ports/device/oppo-a16-display-fix/package.toml`** — MTK display
  bring-up. Read this if you have any panel or compositor weirdness; many
  of the workarounds (cgroup-v1, fb0 seat tagging, MTKFB pan-display
  forcing) translate to other MTK devices verbatim.
- **`Peacock/cmd/peacock/build.go`** — the consuming code. Search for
  `discoverKernelDTB` (DTB selection), `stageExtlinuxBootAssets` (extlinux
  config emission), and `Boot.Android` to see how `device.toml` flows
  through.
- **`Peacock/task.md`** — per-device porting checklist. Update it as you
  go; new device entries go at the top.
- **`Peacock/BACKLOG.md`** — cross-repo backlog. The "Boot stack" and
  "Recovery (PRP)" sections list known papercuts you may hit.
