#!/bin/sh
# peacock-netdbg — bring up USB RNDIS + a passwordless-root dropbear for headless debugging over
# USB (ssh root@172.16.42.1). DEV ONLY: this is unauthenticated root over the USB gadget.
#
# Device-agnostic: auto-detects the UDC and the gadget net interface, so it works on any device
# whose kernel has USB gadget configfs (CONFIG_USB_CONFIGFS + USB_CONFIGFS_RNDIS). peacock-init
# execs it on boot when this package is installed; the first-boot OOBE also triggers it. Idempotent
# (a re-run is a no-op once dropbear is up). Everything goes through busybox by absolute path
# because the early base has no usable PATH/util-linux yet.
BB=/usr/bin/busybox
LOG=/tmp/peacock-netdbg.log
exec >>"$LOG" 2>&1
echo "=== peacock-netdbg ==="

# Already up? (idempotent across the peacock-init hook + the OOBE trigger.)
$BB pidof dropbear >/dev/null 2>&1 && { echo "already up"; exit 0; }

G=/sys/kernel/config/usb_gadget/peacock
$BB mkdir -p /sys/kernel/config 2>/dev/null
$BB mountpoint -q /sys/kernel/config 2>/dev/null || $BB mount -t configfs configfs /sys/kernel/config 2>/dev/null
[ -d /sys/kernel/config/usb_gadget ] || { echo "kernel has no USB gadget configfs — cannot bring up RNDIS"; exit 1; }

UDC=$($BB ls /sys/class/udc 2>/dev/null | $BB head -1)
[ -n "$UDC" ] || { echo "no UDC found"; exit 1; }
echo "UDC=$UDC"

[ -d "$G" ] && printf '' > "$G/UDC" 2>/dev/null
$BB mkdir -p "$G/strings/0x409" "$G/configs/c.1/strings/0x409" "$G/functions/rndis.usb0"
printf 0x04e8 > "$G/idVendor"; printf 0x6863 > "$G/idProduct"
printf Peacock   > "$G/strings/0x409/manufacturer"
printf PeacockOS > "$G/strings/0x409/product"
printf peacock   > "$G/strings/0x409/serialnumber"
printf PeacockOS > "$G/configs/c.1/strings/0x409/configuration"
printf 120       > "$G/configs/c.1/MaxPower"
printf 02:1A:11:00:00:01 > "$G/functions/rndis.usb0/dev_addr"
printf 02:1A:11:00:00:02 > "$G/functions/rndis.usb0/host_addr"
$BB ln -sf "$G/functions/rndis.usb0" "$G/configs/c.1/rndis.usb0" 2>/dev/null
printf '%s' "$UDC" > "$G/UDC" || { echo "UDC bind failed"; exit 1; }
echo "gadget bound to $UDC"

# Device-side IP on the gadget net interface (usb0/rndis0/...).
IFACE=""
for t in 1 2 3 4 5; do
  IFACE=$($BB ls /sys/class/net 2>/dev/null | $BB grep -E '^(usb|rndis)' | $BB head -1)
  [ -n "$IFACE" ] && break
  $BB sleep 1
done
[ -n "$IFACE" ] || IFACE=usb0
$BB ip addr add 172.16.42.1/24 dev "$IFACE" 2>/dev/null
$BB ip link set "$IFACE" up 2>/dev/null
echo "iface=$IFACE ip=172.16.42.1"

# DHCP so the USB host auto-gets an address (static 172.16.42.x on the host works too).
$BB mkdir -p /var/lib/misc 2>/dev/null; $BB touch /var/lib/misc/udhcpd.leases 2>/dev/null
printf 'start 172.16.42.20\nend 172.16.42.100\ninterface %s\noption subnet 255.255.255.0\noption lease 86400\n' "$IFACE" > /tmp/peacock-netdbg-udhcpd.conf
$BB udhcpd -f /tmp/peacock-netdbg-udhcpd.conf >/dev/null 2>&1 &
echo "udhcpd up"

# Passwordless root so `ssh root@172.16.42.1` works non-interactively (dropbear -B).
$BB sed -i 's#^root:[^:]*:#root::#' /etc/passwd 2>/dev/null
if [ -f /etc/shadow ]; then $BB sed -i 's#^root:[^:]*:#root::#' /etc/shadow 2>/dev/null; else printf 'root::19000:0:99999:7:::\n' > /etc/shadow; fi
[ -f /etc/dropbear/dropbear_rsa_host_key ] || { $BB mkdir -p /etc/dropbear; /usr/sbin/dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key >/dev/null 2>&1; }
/usr/sbin/dropbear -p 22 -B -r /etc/dropbear/dropbear_rsa_host_key && echo "dropbear up — ssh root@172.16.42.1"
