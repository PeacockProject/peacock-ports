#!/bin/sh
# Alpine desktop+DM stage. Installs the chosen desktop and login manager INTO the flavor
# (run_in_target = chroot $ROOT) with the flavor's own apk, then enables the services with OpenRC
# so they come up on the boot after the OOBE finishes.
#
# Two Alpine-specific traps this handles:
#   * Alpine splits every OpenRC init script into a separate `<pkg>-openrc` subpackage. Installing
#     `sddm` alone gives you the binary and NO /etc/init.d/sddm, so `rc-update add sddm` fails and
#     the device boots to a console with a display manager it can't start.
#   * The minirootfs has no X stack at all, not even fonts or DRI — the DE metapackages don't pull
#     an X server, so it's listed explicitly.
#
# Provided by the runner: $ANS_desktop $ANS_dm, run_in_target, bp_log/bp_progress/bp_fail.
set -u

[ "$ANS_desktop" = "none" ] && { bp_log "no desktop selected — console only"; exit 0; }

# Everything a graphical session needs regardless of which DE was picked. elogind is Alpine's
# logind (seat/session management); without it neither SDDM nor a Plasma/GNOME session can claim
# the seat.
common_pkgs="xorg-server xf86-input-libinput xf86-video-fbdev mesa-dri-gallium font-dejavu \
setxkbmap dbus dbus-openrc elogind elogind-openrc polkit-elogind"

case "$ANS_desktop" in
	XFCE)         de_pkgs="xfce4 xfce4-session xfce4-terminal" ;;
	"KDE Plasma") de_pkgs="plasma-desktop plasma-workspace konsole dolphin" ;;
	GNOME)        de_pkgs="gnome" ;;
	*)            bp_fail "unknown desktop: $ANS_desktop" ;;
esac

# The -openrc subpackage is what provides /etc/init.d/<svc>; without it rc-update has nothing to
# enable.
case "${ANS_dm:-none}" in
	SDDM)    dm_pkg="sddm sddm-openrc";                            dm_svc="sddm" ;;
	LightDM) dm_pkg="lightdm lightdm-gtk-greeter lightdm-openrc";  dm_svc="lightdm" ;;
	none)    dm_pkg="";                                            dm_svc="" ;;
	*)       bp_fail "unknown login manager: $ANS_dm" ;;
esac

bp_progress 10
bp_log "installing $ANS_desktop ${ANS_dm:+($ANS_dm)} — this downloads packages"
# shellcheck disable=SC2086
run_in_target apk add --no-cache $common_pkgs $de_pkgs $dm_pkg \
	|| bp_fail "package install failed (network?)"
bp_progress 75

# Device nodes for input/DRM come from eudev, which must run in the sysinit runlevel before
# anything graphical. Best-effort per service: the exact script names vary across Alpine releases
# and a missing optional one must not fail the whole install.
for svc in udev udev-trigger udev-settle; do
	run_in_target rc-update add "$svc" sysinit >/dev/null 2>&1 \
		|| bp_log "note: no '$svc' service to enable"
done
for svc in dbus elogind; do
	run_in_target rc-update add "$svc" default >/dev/null 2>&1 \
		|| bp_log "note: no '$svc' service to enable"
done
bp_progress 90

# The DM is the one service whose absence would leave a graphical install with no way in, so this
# one IS fatal.
if [ -n "$dm_svc" ]; then
	run_in_target rc-update add "$dm_svc" default || bp_fail "could not enable $dm_svc (openrc)"
	bp_log "enabled $dm_svc"
fi
bp_progress 100
