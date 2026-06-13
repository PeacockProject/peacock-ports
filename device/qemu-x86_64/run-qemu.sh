#!/usr/bin/env bash
# run-qemu.sh — boot a PeacockOS (and optionally PRP recovery) x86_64 image in QEMU.
#
# Build the OS image first:
#   peacock build --device qemu-x86_64 --flavor arch --init openrc \
#       --desktop none --display-manager none
#
# Build the PRP initramfs (monolithic — overlay embedded) first if you want the
# recovery entry:
#   cd PRP && make initramfs TARGET=qemu-x86_64 OUT_DIR="$(pwd)/out/qemu-x86_64"
#
# Then:
#   ./run-qemu.sh                                   # headless, serial console here
#   ./run-qemu.sh --gui                             # graphical window (desktop / PRP GUI)
#   ./run-qemu.sh --image /path/to.img
#   ./run-qemu.sh --prp PRP/out/qemu-x86_64/initramfs.cpio.gz   # adds a PRP menu entry
#   ./run-qemu.sh --prp <initramfs> --prp-kernel /tmp/prp-qemu-vmlinuz
#
# How it works: we never modify the OS image. We build a tiny GRUB rescue ISO
# (BIOS, via SeaBIOS — no OVMF needed). Entry 1 loads the kernel + initramfs
# straight off the image's ROOT partition (LABEL=ROOT) and boots the Peacock
# base, which enters the active flavor — the same path the phone takes, minus
# lk2nd. Entry 2 (with --prp) boots PRP's monolithic initramfs embedded in the
# ISO itself; PRP is self-contained (the overlay rides in the initramfs), so it
# needs no disk and no root=.
#
# GUI note: GRUB sets an explicit graphics mode (gfxpayload), so the kernel
# inherits a linear framebuffer via sysfb -> simpledrm -> /dev/fb0. That's what
# lets PRP's LVGL GUI (and a flavor desktop) paint without any in-initramfs
# display-driver modules. We use -vga std (Bochs VBE) for the same reason.
set -euo pipefail

IMG="${PEACOCK_QEMU_IMG:-$HOME/.local/var/peacock/qemu-x86_64.img}"
PRP_INITRAMFS=""
PRP_KERNEL="${PRP_KERNEL:-/tmp/prp-qemu-vmlinuz}"
GUI=0
MEM="${QEMU_MEM:-2048}"
CPUS="${QEMU_CPUS:-2}"
GFXMODE="${QEMU_GFXMODE:-1024x768x32}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image)      IMG="$2"; shift 2 ;;
    --prp)        PRP_INITRAMFS="$2"; shift 2 ;;
    --prp-kernel) PRP_KERNEL="$2"; shift 2 ;;
    --gui)        GUI=1; shift ;;
    --mem)        MEM="$2"; shift 2 ;;
    --cpus)       CPUS="$2"; shift 2 ;;
    -h|--help)    sed -n '2,33p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

[[ -f "$IMG" ]] || { echo "image not found: $IMG (build it first — see --help)" >&2; exit 1; }
command -v qemu-system-x86_64 >/dev/null || { echo "need qemu-system-x86_64" >&2; exit 1; }
command -v grub-mkrescue >/dev/null || { echo "need grub-mkrescue (grub + xorriso)" >&2; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/iso/boot/grub"

CONSOLE="console=ttyS0,115200"
[[ "$GUI" == 1 ]] && CONSOLE="console=tty0 console=ttyS0,115200"

PRP_OK=0
if [[ -n "$PRP_INITRAMFS" ]]; then
  [[ -f "$PRP_INITRAMFS" ]] || { echo "PRP initramfs not found: $PRP_INITRAMFS" >&2; exit 1; }
  if [[ ! -f "$PRP_KERNEL" ]]; then
    echo "PRP kernel not found: $PRP_KERNEL" >&2
    echo "  pass --prp-kernel <vmlinuz> (e.g. the x86_64 vmlinuz from the OS image)" >&2
    exit 1
  fi
  mkdir -p "$WORK/iso/prp"
  cp "$PRP_KERNEL" "$WORK/iso/prp/vmlinuz"
  cp "$PRP_INITRAMFS" "$WORK/iso/prp/initramfs.cpio.gz"
  PRP_OK=1
fi

{
  echo "set timeout=5"
  echo "set default=0"
  echo "serial --unit=0 --speed=115200"
  echo "terminal_input serial console"
  echo "terminal_output serial console"
  echo "insmod all_video"
  echo "insmod part_gpt; insmod ext2"
  echo
  echo 'menuentry "PeacockOS (base -> flavor)" {'
  echo "    set gfxpayload=$GFXMODE"
  echo '    search --no-floppy --label ROOT --set=root'
  echo "    linux /flavors/arch/boot/vmlinuz-linux root=LABEL=ROOT rw $CONSOLE loglevel=7"
  echo '    initrd /flavors/arch/boot/initramfs-linux.img'
  echo '}'
  if [[ "$PRP_OK" == 1 ]]; then
    # PRP recovery: monolithic initramfs embedded in this ISO. Self-contained —
    # the overlay (LVGL prp-gui, busybox, dropbear) rides in the initramfs, so
    # no disk and no root= are needed. gfxpayload gives it /dev/fb0 for the GUI.
    echo
    echo 'menuentry "PRP recovery" {'
    echo "    set gfxpayload=$GFXMODE"
    echo "    linux /prp/vmlinuz $CONSOLE loglevel=7"
    echo '    initrd /prp/initramfs.cpio.gz'
    echo '}'
  fi
} > "$WORK/iso/boot/grub/grub.cfg"

ISO="$WORK/peacock-grub.iso"
grub-mkrescue -o "$ISO" "$WORK/iso" >/dev/null 2>&1

QEMU=(qemu-system-x86_64 -m "$MEM" -smp "$CPUS"
  -drive file="$IMG",format=raw,if=ide
  -cdrom "$ISO" -boot d -vga std)
[[ -e /dev/kvm ]] && QEMU+=(-enable-kvm -cpu host)

if [[ "$GUI" == 1 ]]; then
  QEMU+=(-display gtk -serial mon:stdio)
else
  QEMU+=(-display none -serial mon:stdio)
fi

echo "Booting $IMG${PRP_OK:+ (+PRP recovery entry)} ${GUI:+[gui]} — Ctrl-A X to quit (headless)"
exec "${QEMU[@]}"
