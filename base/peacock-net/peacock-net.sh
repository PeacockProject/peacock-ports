#!/bin/sh
# peacock-net — base Wi-Fi bring-up. Run by peacock-init BEFORE entering the flavor, using the
# credentials PRP saved at install. The flavor shares the base's network namespace, so it (and its
# first-boot OOBE) inherit the connection. No saved network -> no-op. Mirrors PRP's prp-net but
# against the installed base (real /lib/modules + /lib/firmware) and a pre-saved wpa config.
set -u
NETDIR=/peacock/etc/network
CONF="$NETDIR/wpa.conf"
[ -f "$CONF" ] || exit 0

log() { echo "peacock-net: $*" >&2; }

# Make sure busybox applet symlinks (modprobe/ip/...) exist — the install-time helper may not have
# run, and without modprobe nothing below works.
[ -x /usr/sbin/peacock-busybox-links ] && /usr/sbin/peacock-busybox-links 2>/dev/null || true
if command -v modprobe >/dev/null 2>&1; then
	[ -d /sys/module/firmware_class/parameters ] && echo /lib/firmware > /sys/module/firmware_class/parameters/path 2>/dev/null || true
	# Full wcnss/wcn36xx stack IN DEPENDENCY ORDER. QRTR (the QMI IPC router) is not a symbol dep of
	# the wcnss PIL, but the PIL needs it for its QMI handle, so it must be loaded explicitly; busybox
	# modprobe also won't reliably pull the qcom remoteproc dep chain, so list it. The wcnss chip
	# boots asynchronously, so wcn36xx (loaded last) can lose the race — reload it once if wlan0
	# never shows up.
	mods="$(cat "$NETDIR/wifi-modules" 2>/dev/null || true)"
	[ -n "$mods" ] || mods="qrtr qrtr_smd qmi_helpers qcom_common qcom_pil_info qcom_sysmon qcom_wcnss_pil wcnss_ctrl cfg80211 mac80211 wcn36xx"
	for m in $mods; do modprobe "$m" 2>/dev/null || true; done
	i=0; while [ "$i" -lt 10 ] && [ ! -e /sys/class/net/wlan0 ]; do sleep 1; i=$((i + 1)); done
	[ -e /sys/class/net/wlan0 ] || { modprobe -r wcn36xx 2>/dev/null; sleep 1; modprobe wcn36xx 2>/dev/null; sleep 3; }
fi

iface=
for d in /sys/class/net/*; do
	n=${d##*/}
	case "$n" in wlan*|wlp*) iface="$n"; break ;; esac
done
[ -n "$iface" ] || { log "no Wi-Fi interface"; exit 0; }
ip link set "$iface" up 2>/dev/null || ifconfig "$iface" up 2>/dev/null || true

mkdir -p /var/run/wpa_supplicant
wpa_supplicant -B -i "$iface" -c "$CONF" -Dnl80211 >/dev/null 2>&1
cc="$(cat "$NETDIR/wifi-country" 2>/dev/null || true)"
[ -n "$cc" ] && wpa_cli -i "$iface" set country "$cc" >/dev/null 2>&1 || true

i=0
while [ "$i" -lt 20 ]; do
	st=$(wpa_cli -i "$iface" status 2>/dev/null | sed -n 's/^wpa_state=//p')
	[ "$st" = "COMPLETED" ] && break
	i=$((i + 1)); sleep 1
done

busybox udhcpc -i "$iface" -s /usr/share/udhcpc/default.script -n -q -t 8 -T 2 >/dev/null 2>&1 \
	|| udhcpc -i "$iface" -s /usr/share/udhcpc/default.script -n -q >/dev/null 2>&1 || true
ip4=$(ip -4 addr show "$iface" 2>/dev/null | sed -n 's/.*inet \([0-9.]*\).*/\1/p' | head -1)
[ -n "$ip4" ] && log "connected $ip4" || log "associated but no IP (continuing)"
exit 0
