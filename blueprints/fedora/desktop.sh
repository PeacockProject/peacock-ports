#!/bin/sh
# Fedora desktop+DM stage (referenced by configure.toml `script`). Installs the chosen desktop
# environment and login manager INTO the flavor (run_in_target = chroot $ROOT) using the flavor's
# own dnf, then enables the DM so it starts after the OOBE completes.
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

# comps ids verified against Fedora 43's comps-Everything.aarch64.xml:
#   xfce-desktop-environment / kde-desktop-environment are <environment> ids;
#   GNOME has no such environment — "gnome-desktop-environment" exists only as a <category> — so the
#   installable id there is the plain <group> gnome-desktop.
# The "@id" spec is what both dnf4 and dnf5 accept from `install`; the fallback is the leaner
# same-DE <group> via `group install`, in case this image's dnf5 declines an environment spec.
case "$ANS_desktop" in
	XFCE)         de_spec="@xfce-desktop-environment"; de_alt="xfce-desktop" ;;
	"KDE Plasma") de_spec="@kde-desktop-environment";  de_alt="kde-desktop" ;;
	GNOME)        de_spec="@gnome-desktop";            de_alt="gnome-desktop" ;;
	*)            bp_fail "unknown desktop: $ANS_desktop" ;;
esac

# Login manager -> package(s) + systemd unit. Fedora's GTK greeter package is `lightdm-gtk`; there is
# no `lightdm-gtk-greeter` (that name only exists as lightdm-gtk-greeter-settings).
case "${ANS_dm:-none}" in
	SDDM)    dm_pkg="sddm";                dm_svc="sddm" ;;
	LightDM) dm_pkg="lightdm lightdm-gtk"; dm_svc="lightdm" ;;
	none)    dm_pkg="";                    dm_svc="" ;;
	*)       bp_fail "unknown login manager: $ANS_dm" ;;
esac

bp_progress 10
bp_log "installing $ANS_desktop ${ANS_dm:+($ANS_dm)} — this downloads packages"
# Weak deps deliberately stay ON here: a Fedora desktop group leans on Recommends for its session
# plumbing (portals, audio, themes, input) and comes out unusable without them.
in_flavor dnf -y install "$de_spec" \
	|| in_flavor dnf -y group install "$de_alt" \
	|| bp_fail "desktop install failed (network?)"
bp_progress 70

if [ -n "$dm_pkg" ]; then
	# shellcheck disable=SC2086
	in_flavor dnf -y install $dm_pkg || bp_fail "login manager install failed (network?)"
fi
bp_progress 85

if [ -n "$dm_svc" ]; then
	# `systemctl enable` / `set-default` are pure filesystem operations, so they work fine in a
	# chroot with no systemd running. Both are needed: enable wires up display-manager.service,
	# set-default stops the guest booting straight into multi-user.target with no DM.
	in_flavor systemctl enable "${dm_svc}.service" || bp_fail "could not enable $dm_svc"
	in_flavor systemctl set-default graphical.target \
		|| bp_log "warning: could not set graphical.target as the default — the DM may not start"
	bp_log "enabled $dm_svc"
fi
bp_progress 100
