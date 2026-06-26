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

if command -v modprobe >/dev/null 2>&1; then
	[ -d /sys/module/firmware_class/parameters ] && echo /lib/firmware > /sys/module/firmware_class/parameters/path 2>/dev/null || true
	mods="$(cat "$NETDIR/wifi-modules" 2>/dev/null || true)"
	[ -n "$mods" ] || mods="qcom_wcnss_pil cfg80211 mac80211 wcnss_ctrl wcn36xx"
	for m in $mods; do modprobe "$m" 2>/dev/null || true; done
fi

iface=
for d in /sys/class/net/*; do
	n=${d##*/}
	case "$n" in wlan*|wlp*) iface="$n"; break ;; esac
done
[ -n "$iface" ] || { log "no Wi-Fi interface"; exit 0; }
ip link set "$iface" up 2>/dev/null || ifconfig "$iface" up 2>/dev/null || true

mkdir -p /var/run/wpa_supplicant
wpa_supplicant -B -i "$iface" -c "$CONF" >/dev/null 2>&1
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
