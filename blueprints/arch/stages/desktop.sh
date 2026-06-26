#!/bin/sh
# Arch desktop+DM stage (referenced by arch.toml `action_script`). Installs the chosen desktop
# environment and login manager INTO the flavor (run_in_target = chroot $ROOT) using the flavor's
# own pacman, then enables the DM so it starts after the OOBE completes.
#
# Provided by the blueprint runner:
#   $ANS_desktop $ANS_dm   captured answers
#   run_in_target <cmd>    chroot "$ROOT" <cmd>   ($ROOT = flavor rootfs / /flavors/<active>)
#   bp_log / bp_progress / bp_fail   line-protocol helpers
set -u

[ "$ANS_desktop" = "none" ] && { bp_log "no desktop selected — console only"; exit 0; }

# Desktop environment -> package set.
case "$ANS_desktop" in
	XFCE)         de_pkgs="xfce4 xfce4-goodies xorg-server" ;;
	"KDE Plasma") de_pkgs="plasma-meta kde-applications-meta" ;;
	GNOME)        de_pkgs="gnome gnome-extra" ;;
	*)            bp_fail "unknown desktop: $ANS_desktop" ;;
esac

# Login manager -> package + service name (openrc service id; systemd unit is <name>.service).
case "${ANS_dm:-none}" in
	SDDM)    dm_pkg="sddm";    dm_svc="sddm" ;;
	LightDM) dm_pkg="lightdm lightdm-gtk-greeter"; dm_svc="lightdm" ;;
	none)    dm_pkg="";        dm_svc="" ;;
	*)       bp_fail "unknown login manager: $ANS_dm" ;;
esac

bp_progress 10
bp_log "installing $ANS_desktop ${ANS_dm:+($ANS_dm)} — this downloads packages"
# shellcheck disable=SC2086
run_in_target pacman -Sy --noconfirm $de_pkgs $dm_pkg || bp_fail "package install failed (network?)"
bp_progress 80

# Enable the DM so it starts on the next boot (after OOBE finishes). Detect the flavor's init.
if [ -n "$dm_svc" ]; then
	if run_in_target test -d /run/systemd/system || run_in_target test -x /usr/lib/systemd/systemd; then
		run_in_target systemctl enable "${dm_svc}.service" || bp_fail "could not enable $dm_svc (systemd)"
	else
		run_in_target rc-update add "$dm_svc" default || bp_fail "could not enable $dm_svc (openrc)"
	fi
	bp_log "enabled $dm_svc"
fi
bp_progress 100
