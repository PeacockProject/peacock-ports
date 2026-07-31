#!/bin/sh
# openSUSE desktop+DM stage (referenced by configure.toml `script`). Installs the chosen desktop
# environment and login manager INTO the flavor (run_in_target = chroot $ROOT) using the flavor's
# own zypper, then enables the DM so it starts after the OOBE completes.
#
# Provided by the blueprint runner:
#   $ANS_desktop $ANS_dm   captured answers
#   run_in_target <cmd>    chroot "$ROOT" <cmd>   ($ROOT = flavor rootfs / /flavors/<active>)
#   bp_log / bp_progress / bp_fail   line-protocol helpers
set -u

[ "$ANS_desktop" = "none" ] && { bp_log "no desktop selected — console only"; exit 0; }

bp_mounted=""
unbind_kernel_fs() {
	for m in $bp_mounted; do umount "$m" 2>/dev/null || umount -l "$m" 2>/dev/null || true; done
	bp_mounted=""
}
trap unbind_kernel_fs EXIT INT TERM
# A desktop install runs thousands of RPM scriptlets; without /proc and a real /dev (the container
# rootfs ships /dev EMPTY — no /dev/null) they fail in obscure ways. Bind what we can, always undo.
if [ "${ROOT:-/}" != "/" ]; then
	for d in /proc /sys /dev /dev/pts; do
		mkdir -p "$ROOT$d" 2>/dev/null || continue
		mount -o bind "$d" "$ROOT$d" 2>/dev/null && bp_mounted="$ROOT$d $bp_mounted"
	done
fi
in_flavor() { run_in_target /bin/sh -c 'PATH=/usr/sbin:/usr/bin:/sbin:/bin; exec "$@"' sh "$@"; }

# Re-point DNS at whatever the RUNNING base is using: prep-base.sh copied the installer's
# resolv.conf, which predates the network the user just joined in the OOBE, and this is the stage
# that actually needs name resolution. (Plain file, never a symlink — see prep-base.sh.)
if [ -s /etc/resolv.conf ]; then
	rm -f "$ROOT/etc/resolv.conf"
	cp /etc/resolv.conf "$ROOT/etc/resolv.conf" 2>/dev/null || true
fi

# openSUSE ships desktops as *patterns*. These package names were checked against the live
# ports/aarch64 Tumbleweed OSS repo: patterns-xfce-xfce and patterns-gnome-gnome are built per-arch
# (aarch64), patterns-kde-kde_plasma is noarch. XFCE additionally gets an X server pulled in
# explicitly because it has no Wayland session to fall back on.
case "$ANS_desktop" in
	XFCE)         de_pkgs="patterns-xfce-xfce xorg-x11-server" ;;
	"KDE Plasma") de_pkgs="patterns-kde-kde_plasma" ;;
	GNOME)        de_pkgs="patterns-gnome-gnome" ;;
	*)            bp_fail "unknown desktop: $ANS_desktop" ;;
esac

# Login manager -> package(s) + systemd unit.
case "${ANS_dm:-none}" in
	SDDM)    dm_pkg="sddm";                        dm_svc="sddm" ;;
	LightDM) dm_pkg="lightdm lightdm-gtk-greeter"; dm_svc="lightdm" ;;
	none)    dm_pkg="";                            dm_svc="" ;;
	*)       bp_fail "unknown login manager: $ANS_dm" ;;
esac

bp_progress 10
# First contact with the repos in a fresh rootfs: refresh metadata and take the repo signing keys
# non-interactively, otherwise every install stops on a key-trust prompt.
in_flavor zypper -n --gpg-auto-import-keys refresh || bp_fail "zypper refresh failed (network?)"
bp_progress 25

bp_log "installing $ANS_desktop ${ANS_dm:+($ANS_dm)} — this downloads packages"
# NOTE: no --no-recommends. openSUSE patterns pull most of their content through Recommends, so
# suppressing them would "install" a desktop that is an empty metapackage.
# shellcheck disable=SC2086
in_flavor zypper -n install $de_pkgs || bp_fail "desktop install failed (network?)"
bp_progress 70

if [ -n "$dm_pkg" ]; then
	# shellcheck disable=SC2086
	in_flavor zypper -n install $dm_pkg || bp_fail "login manager install failed (network?)"
fi
bp_progress 85

if [ -n "$dm_svc" ]; then
	# `systemctl enable` / `set-default` are pure filesystem operations, so they work fine in a
	# chroot with no systemd running. Both are needed: enable wires up display-manager.service,
	# set-default stops the guest booting straight into multi-user.target with no DM.
	in_flavor systemctl enable "${dm_svc}.service" || bp_fail "could not enable $dm_svc"
	in_flavor systemctl set-default graphical.target \
		|| bp_log "warning: could not set graphical.target as the default — the DM may not start"
	# openSUSE's legacy sysconfig switch, honoured by display-manager.service when that file exists.
	if [ -f "$ROOT/etc/sysconfig/displaymanager" ]; then
		sed -i "s/^DISPLAYMANAGER=.*/DISPLAYMANAGER=\"$dm_svc\"/" "$ROOT/etc/sysconfig/displaymanager" || true
	fi
	bp_log "enabled $dm_svc"
fi
bp_progress 100
