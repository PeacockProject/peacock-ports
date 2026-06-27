#!/bin/sh
# peacock-net — base Wi-Fi. Two roles from one script:
#   peacock-net                       connect on boot from saved creds (run by peacock-init)
#   peacock-net scan                  SSIDs -> /tmp/peacock-net-scan (one per line) + stdout
#   peacock-net connect <ssid> [psk]  "ok <ip>" / "fail <reason>" -> /tmp/peacock-net-status, and
#                                     persists creds to /peacock/etc/network/wpa.conf (save_config)
#   peacock-net status                "<ssid> <ip>" or "disconnected"
#   peacock-net set-country <CC>      persist ISO-3166 alpha-2 regulatory country (5GHz/DFS)
#
# Backed by wpa_supplicant + wpa_cli + busybox udhcpc. The first-boot OOBE forks the subcommands and
# polls the /tmp result files (so its UI stays responsive), mirroring PRP's prp-net. The wcnss/wcn36xx
# module chain + firmware live on the installed base (device kernel + firmware-<codename>).
set -u
NETDIR=/peacock/etc/network
CONF="$NETDIR/wpa.conf"
WPA_CTRL=/var/run/wpa_supplicant
SCAN_OUT=/tmp/peacock-net-scan
STATUS_OUT=/tmp/peacock-net-status
WIFI_COUNTRY="${PEACOCK_WIFI_COUNTRY:-$(cat "$NETDIR/wifi-country" 2>/dev/null || true)}"
log() { echo "peacock-net: $*" >&2; }

WIFI_MODULES_TRIED=0
wifi_present() {
	for d in /sys/class/net/*; do
		{ [ -d "$d/wireless" ] || [ -e "$d/phy80211" ]; } && return 0
	done
	return 1
}
load_wifi_modules() {
	[ "$WIFI_MODULES_TRIED" = 1 ] && return 0
	WIFI_MODULES_TRIED=1
	wifi_present && return 0
	# Self-heal busybox applet symlinks (modprobe/ip/...) in case the install-time helper didn't run.
	[ -x /usr/sbin/peacock-busybox-links ] && /usr/sbin/peacock-busybox-links 2>/dev/null || true
	command -v modprobe >/dev/null 2>&1 || return 0
	[ -d /sys/module/firmware_class/parameters ] && echo /lib/firmware > /sys/module/firmware_class/parameters/path 2>/dev/null || true
	# Full wcnss/wcn36xx stack IN DEPENDENCY ORDER. QRTR (the QMI IPC router) is needed for the wcnss
	# PIL's QMI handle but isn't a symbol dep, so load it explicitly; busybox modprobe won't pull the
	# qcom remoteproc chain either, so list it. The wcnss chip boots async, so wcn36xx (last) can lose
	# the race — reload it once if wlan0 never shows up.
	mods="$(cat "$NETDIR/wifi-modules" 2>/dev/null || true)"
	[ -n "$mods" ] || mods="qrtr qrtr_smd qmi_helpers qcom_common qcom_pil_info qcom_sysmon qcom_wcnss_pil wcnss_ctrl cfg80211 mac80211 wcn36xx"
	log "loading wifi stack"
	for m in $mods; do modprobe "$m" 2>/dev/null || true; done
	i=0; while [ "$i" -lt 10 ] && ! wifi_present; do sleep 1; i=$((i + 1)); done
	wifi_present || { modprobe -r wcn36xx 2>/dev/null; sleep 1; modprobe wcn36xx 2>/dev/null; sleep 3; }
	return 0
}
detect_iface() {
	load_wifi_modules
	for d in /sys/class/net/*; do
		[ -e "$d" ] || continue
		n=$(basename "$d")
		if [ -d "$d/wireless" ] || [ -e "$d/phy80211" ]; then echo "$n"; return 0; fi
		case "$n" in wlan*|wlp*) echo "$n"; return 0 ;; esac
	done
	return 1
}
iface_up() { ip link set "$1" up 2>/dev/null || ifconfig "$1" up 2>/dev/null || true; }
ipof() { ip -4 addr show "$1" 2>/dev/null | sed -n 's/.*inet \([0-9.]*\).*/\1/p' | head -1; }
dhcp() {
	busybox udhcpc -i "$1" -s /usr/share/udhcpc/default.script -n -q -t 8 -T 2 >/dev/null 2>&1 \
		|| udhcpc -i "$1" -s /usr/share/udhcpc/default.script -n -q >/dev/null 2>&1 || true
}
# Ensure a wpa_supplicant control instance is up on $1, creating a minimal config (ctrl_interface +
# update_config so wpa_cli can add/save networks) if none exists yet.
ensure_wpa() {
	iface="$1"; iface_up "$iface"
	if ! wpa_cli -i "$iface" status >/dev/null 2>&1; then
		mkdir -p "$WPA_CTRL" "$NETDIR"
		if [ ! -f "$CONF" ]; then
			printf 'ctrl_interface=%s\nupdate_config=1\n' "$WPA_CTRL" >"$CONF"
			[ -n "$WIFI_COUNTRY" ] && printf 'country=%s\n' "$WIFI_COUNTRY" >>"$CONF"
		fi
		wpa_supplicant -B -i "$iface" -c "$CONF" -Dnl80211 >/dev/null 2>&1
		i=0; while [ "$i" -lt 10 ]; do wpa_cli -i "$iface" status >/dev/null 2>&1 && break; i=$((i + 1)); sleep 1; done
		wpa_cli -i "$iface" status >/dev/null 2>&1 || return 1
	fi
	[ -n "$WIFI_COUNTRY" ] && wpa_cli -i "$iface" set country "$WIFI_COUNTRY" >/dev/null 2>&1
	return 0
}

cmd_scan() {
	: >"$SCAN_OUT"
	iface=$(detect_iface) || { log "no wifi interface"; return 1; }
	ensure_wpa "$iface" || { log "wpa_supplicant not ready"; return 1; }
	wpa_cli -i "$iface" scan >/dev/null 2>&1; sleep 3
	# scan_results columns: bssid / freq / signal / flags / ssid(rest)
	wpa_cli -i "$iface" scan_results 2>/dev/null \
		| awk 'NR>1 { s=""; for (i=5;i<=NF;i++) s=s (i>5?" ":"") $i; if (s!="") print s }' \
		| sort -u | grep -v '^$' >"$SCAN_OUT"
	cat "$SCAN_OUT"
}
cmd_connect() {
	ssid="$1"; psk="${2:-}"; : >"$STATUS_OUT"
	iface=$(detect_iface) || { echo "fail no-interface" >"$STATUS_OUT"; return 1; }
	ensure_wpa "$iface" || { echo "fail wpa-init" >"$STATUS_OUT"; return 1; }
	for id in $(wpa_cli -i "$iface" list_networks 2>/dev/null | awk 'NR>1{print $1}'); do
		wpa_cli -i "$iface" remove_network "$id" >/dev/null 2>&1
	done
	id=$(wpa_cli -i "$iface" add_network 2>/dev/null | tail -1)
	wpa_cli -i "$iface" set_network "$id" ssid "\"$ssid\"" >/dev/null 2>&1
	if [ -n "$psk" ]; then wpa_cli -i "$iface" set_network "$id" psk "\"$psk\"" >/dev/null 2>&1
	else wpa_cli -i "$iface" set_network "$id" key_mgmt NONE >/dev/null 2>&1; fi
	wpa_cli -i "$iface" enable_network "$id" >/dev/null 2>&1
	i=0; while [ "$i" -lt 25 ]; do
		st=$(wpa_cli -i "$iface" status 2>/dev/null | sed -n 's/^wpa_state=//p')
		[ "$st" = "COMPLETED" ] && break; i=$((i + 1)); sleep 1
	done
	[ "${st:-}" = "COMPLETED" ] || { echo "fail auth" >"$STATUS_OUT"; log "association failed"; return 1; }
	dhcp "$iface"
	ip=$(ipof "$iface")
	if [ -n "$ip" ]; then
		# update_config=1 makes save_config persist the ssid/psk into CONF for connect-on-boot.
		wpa_cli -i "$iface" save_config >/dev/null 2>&1 || true
		echo "ok $ip" >"$STATUS_OUT"; log "connected $ip"; return 0
	fi
	# Associated but no lease: on a 5GHz/DFS channel with no regulatory country the radio can't TX.
	# Signal the UI (distinct status + rc 2) to prompt for the region rather than blame the password.
	freq=$(wpa_cli -i "$iface" status 2>/dev/null | sed -n 's/^freq=//p')
	if [ -z "$WIFI_COUNTRY" ] && [ "${freq:-0}" -ge 5000 ] 2>/dev/null; then
		echo "fail need-country" >"$STATUS_OUT"; log "dhcp failed on 5GHz, no country set"; return 2
	fi
	echo "fail dhcp" >"$STATUS_OUT"; log "dhcp failed"; return 1
}
cmd_status() {
	iface=$(detect_iface) || { echo "disconnected"; return 0; }
	ssid=$(wpa_cli -i "$iface" status 2>/dev/null | sed -n 's/^ssid=//p')
	ip=$(ipof "$iface")
	{ [ -n "$ssid" ] && [ -n "$ip" ]; } && echo "$ssid $ip" || echo "disconnected"
}
cmd_set_country() {
	cc="$1"; case "$cc" in [A-Za-z][A-Za-z]) ;; *) log "invalid country: $cc"; return 2 ;; esac
	cc=$(printf '%s' "$cc" | tr 'a-z' 'A-Z'); mkdir -p "$NETDIR"
	printf '%s\n' "$cc" >"$NETDIR/wifi-country"; WIFI_COUNTRY="$cc"
	iface=$(detect_iface 2>/dev/null) && wpa_cli -i "$iface" set country "$cc" >/dev/null 2>&1
	echo "$cc"
}
# Connect on boot from saved creds (peacock-init's bringUpNetwork). No saved network -> no-op.
cmd_up() {
	[ -f "$CONF" ] || exit 0
	iface=$(detect_iface) || { log "no Wi-Fi interface"; exit 0; }
	ensure_wpa "$iface" || exit 0
	i=0; while [ "$i" -lt 20 ]; do
		st=$(wpa_cli -i "$iface" status 2>/dev/null | sed -n 's/^wpa_state=//p')
		[ "$st" = "COMPLETED" ] && break; i=$((i + 1)); sleep 1
	done
	dhcp "$iface"
	ip=$(ipof "$iface")
	[ -n "$ip" ] && log "connected $ip" || log "associated but no IP (continuing)"
	exit 0
}

case "${1:-}" in
	scan)        cmd_scan ;;
	connect)     shift; [ $# -ge 1 ] || { log "connect needs <ssid>"; exit 2; }; cmd_connect "$@" ;;
	status)      cmd_status ;;
	set-country) shift; [ $# -ge 1 ] || { log "set-country needs <CC>"; exit 2; }; cmd_set_country "$1" ;;
	"")          cmd_up ;;
	*)           echo "usage: peacock-net [scan | connect <ssid> [psk] | status | set-country <CC>]" >&2; exit 2 ;;
esac
