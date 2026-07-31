#!/bin/sh
# Void desktop+DM stage. Installs the chosen desktop and login manager INTO the flavor
# (run_in_target = chroot $ROOT) with the flavor's own xbps, then enables the services the runit
# way so they come up on the boot after the OOBE finishes.
#
# "Enabling" a service on Void is not a command — there is no rc-update or systemctl equivalent.
# runsvdir supervises exactly the directory /etc/runit/runsvdir/default/, so enabling a service
# means symlinking /etc/sv/<svc> into it, and that is all this script does. The symlink is created
# with `ln -sf` against the FLAVOR's own path names (not $ROOT-prefixed) via run_in_target, so the
# link target is correct from inside the guest.
#
# Provided by the runner: $ANS_desktop $ANS_dm, run_in_target, bp_log/bp_progress/bp_fail.
set -u

[ "$ANS_desktop" = "none" ] && { bp_log "no desktop selected — console only"; exit 0; }

# Everything a graphical session needs regardless of which DE was picked. The Void DE metapackages
# do not pull an X server. elogind is Void's logind (seat/session management); without it neither
# SDDM nor a Plasma/GNOME session can claim the seat.
common_pkgs="xorg-server xorg-input-drivers xorg-video-drivers xorg-fonts mesa-dri \
dbus elogind polkit"

# kde5 exists but is now a transitional dummy package — use the real Plasma packages.
case "$ANS_desktop" in
	XFCE)         de_pkgs="xfce4 xfce4-terminal" ;;
	"KDE Plasma") de_pkgs="plasma-desktop plasma-workspace konsole dolphin" ;;
	GNOME)        de_pkgs="gnome" ;;
	*)            bp_fail "unknown desktop: $ANS_desktop" ;;
esac

case "${ANS_dm:-none}" in
	SDDM)    dm_pkg="sddm";                          dm_svc="sddm" ;;
	LightDM) dm_pkg="lightdm lightdm-gtk-greeter";   dm_svc="lightdm" ;;
	none)    dm_pkg="";                              dm_svc="" ;;
	*)       bp_fail "unknown login manager: $ANS_dm" ;;
esac

bp_progress 10
bp_log "installing $ANS_desktop ${ANS_dm:+($ANS_dm)} — this downloads packages"
# shellcheck disable=SC2086
run_in_target xbps-install -Sy $common_pkgs $de_pkgs $dm_pkg \
	|| bp_fail "package install failed (network?)"
bp_progress 75

# dbus is needed by every DE here; udevd (device nodes for input/DRM) is already linked into the
# default runsvdir by the stock rootfs, so it isn't re-linked. Best-effort: a service directory
# that a given package version doesn't ship must not fail the whole install.
for svc in dbus; do
	if run_in_target test -d "/etc/sv/$svc"; then
		run_in_target ln -sf "/etc/sv/$svc" "/etc/runit/runsvdir/default/$svc" \
			|| bp_log "note: could not enable $svc"
	else
		bp_log "note: no '$svc' runit service to enable"
	fi
done
bp_progress 90

# The DM is the one service whose absence would leave a graphical install with no way in, so this
# one IS fatal.
if [ -n "$dm_svc" ]; then
	run_in_target test -d "/etc/sv/$dm_svc" || bp_fail "$dm_pkg installed but /etc/sv/$dm_svc is missing"
	run_in_target ln -sf "/etc/sv/$dm_svc" "/etc/runit/runsvdir/default/$dm_svc" \
		|| bp_fail "could not enable $dm_svc (runit)"
	bp_log "enabled $dm_svc"
fi
bp_progress 100
