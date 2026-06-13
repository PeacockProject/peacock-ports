#!/usr/bin/env bash
# run-qemu.sh — boot a PeacockOS (and optionally PRP) x86_64 image in QEMU.
#
# Build the image first:
#   peacock build --device qemu-x86_64 --flavor arch --init openrc \
#       --desktop none --display-manager none
#
# Then:
#   ./run-qemu.sh                 # headless, serial console in this terminal
#   ./run-qemu.sh --gui           # graphical window (for the desktop/GUI)
#   ./run-qemu.sh --image /path/to.img
#   ./run-qemu.sh --prp /path/to/prp-rootfs.img   # adds a PRP recovery menu entry
#
# How it works: we never modify the OS image. We build a tiny GRUB rescue ISO
# (BIOS, via SeaBIOS — no OVMF needed) whose grub.cfg loads the kernel +
# initramfs straight off the image's ROOT partition (LABEL=ROOT) and boots the
# Peacock base, which enters the active flavor — the same path the phone takes,
# minus lk2nd. A second menu entry boots PRP recovery when --prp is given.
set -euo pipefail

IMG="${PEACOCK_QEMU_IMG:-$HOME/.local/var/peacock/qemu-x86_64.img}"
PRP_IMG=""
GUI=0
MEM="${QEMU_MEM:-2048}"
CPUS="${QEMU_CPUS:-2}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image) IMG="$2"; shift 2 ;;
    --prp)   PRP_IMG="$2"; shift 2 ;;
    --gui)   GUI=1; shift ;;
    --mem)   MEM="$2"; shift 2 ;;
    --cpus)  CPUS="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
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

{
  echo "set timeout=5"
  echo "set default=0"
  echo "serial --unit=0 --speed=115200"
  echo "terminal_input serial console"
  echo "terminal_output serial console"
  echo "insmod part_gpt; insmod ext2"
  echo
  echo 'menuentry "PeacockOS (base -> flavor)" {'
  echo '    search --no-floppy --label ROOT --set=root'
  echo "    linux /flavors/arch/boot/vmlinuz-linux root=LABEL=ROOT rw $CONSOLE loglevel=7"
  echo '    initrd /flavors/arch/boot/initramfs-linux.img'
  echo '}'
  if [[ -n "$PRP_IMG" ]]; then
    # PRP recovery: boots the PRP kernel + initramfs, which mounts PRP_ROOTFS.
    # Requires a prp-qemu-x86_64 build (kernel + initramfs staged on the image's
    # ROOT under /boot, and the PRP_ROOTFS overlay as a separate disk).
    echo
    echo 'menuentry "PRP recovery" {'
    echo '    search --no-floppy --label ROOT --set=root'
    echo "    linux /boot/prp/vmlinuz root=LABEL=PRP_ROOTFS rw $CONSOLE loglevel=7"
    echo '    initrd /boot/prp/initramfs.img'
    echo '}'
  fi
} > "$WORK/iso/boot/grub/grub.cfg"

ISO="$WORK/peacock-grub.iso"
grub-mkrescue -o "$ISO" "$WORK/iso" >/dev/null 2>&1

QEMU=(qemu-system-x86_64 -m "$MEM" -smp "$CPUS"
  -drive file="$IMG",format=raw,if=ide
  -cdrom "$ISO" -boot d)
[[ -e /dev/kvm ]] && QEMU+=(-enable-kvm -cpu host)
[[ -n "$PRP_IMG" ]] && QEMU+=(-drive file="$PRP_IMG",format=raw,if=ide)

if [[ "$GUI" == 1 ]]; then
  QEMU+=(-vga virtio -display gtk -serial mon:stdio)
else
  QEMU+=(-nographic)
fi

echo "Booting $IMG${PRP_IMG:+ (+PRP $PRP_IMG)} ${GUI:+[gui]} — Ctrl-A X to quit (headless)"
exec "${QEMU[@]}"
