#!/bin/sh
# Debian desktop+DM stage. Installs the chosen desktop environment and login manager INTO the
# flavor (run_in_target = chroot $ROOT) with the flavor's own apt, then wires systemd so it
# actually comes up at boot.
#
# Provided by the blueprint runner:
#   $ANS_desktop $ANS_dm   captured answers
#   run_in_target <cmd>    chroot "$ROOT" <cmd>   ($ROOT = flavor rootfs / /flavors/<active>)
#   bp_log / bp_progress / bp_fail   line-protocol helpers
set -u

[ "$ANS_desktop" = "none" ] && { bp_log "no desktop selected — console only"; exit 0; }

# Debian package sets. Two things that are easy to get wrong:
#   * xserver-xorg is the metapackage that drags in the input/video drivers — the DE packages only
#     depend on the X *libraries*, so without it you get a desktop and no X server to run it on;
#   * we install with --no-install-recommends (the brief's rule, and it keeps a phone-sized
#     download), and Debian files terminal emulators under Recommends, so name them explicitly.
case "$ANS_desktop" in
	XFCE)         de_pkgs="xfce4 xfce4-goodies xfce4-terminal xserver-xorg" ;;
	"KDE Plasma") de_pkgs="kde-plasma-desktop konsole xserver-xorg" ;;
	GNOME)        de_pkgs="gnome-core xserver-xorg" ;;
	*)            bp_fail "unknown desktop: $ANS_desktop" ;;
esac

# Login manager -> package, systemd unit, and the binary path Debian records in
# /etc/X11/default-display-manager — the file every DM's postinst consults (through the shared
# default-x-display-manager debconf question) to decide which DM owns the display.
case "${ANS_dm:-none}" in
	SDDM)    dm_pkg="sddm";                        dm_svc="sddm";    dm_bin="/usr/bin/sddm" ;;
	LightDM) dm_pkg="lightdm lightdm-gtk-greeter"; dm_svc="lightdm"; dm_bin="/usr/sbin/lightdm" ;;
	none)    dm_pkg="";                            dm_svc="";        dm_bin="" ;;
	*)       bp_fail "unknown login manager: $ANS_dm" ;;
esac

# dpkg maintainer scripts expect /proc. peacock-init binds /dev, /run and the base-owned trees into
# the flavor before the OOBE, but on a namespace-capable kernel it leaves $ROOT/proc an empty
# directory — the guest's own /proc is only mounted later, inside its namespace. Mount one for the
# duration if we can; best effort, never fatal (dpkg copes, some postinsts just get noisier).
proc_tmp=0
if [ ! -e "$ROOT/proc/self" ]; then
	if mount -t proc proc "$ROOT/proc" 2>/dev/null || busybox mount -t proc proc "$ROOT/proc" 2>/dev/null; then
		proc_tmp=1
	else
		bp_log "note: no /proc inside the flavor — continuing without it"
	fi
fi

# In a chroot there is no init to talk to, so a service that tries to start mid-install either
# fails the package or leaves a stray daemon behind. policy-rc.d exiting 101 is the documented way
# to say "don't". It must not survive the stage, hence the EXIT trap.
run_in_target sh -c 'printf "#!/bin/sh\nexit 101\n" > /usr/sbin/policy-rc.d && chmod 755 /usr/sbin/policy-rc.d' \
	|| bp_fail "could not install policy-rc.d"
cleanup() {
	run_in_target rm -f /usr/sbin/policy-rc.d 2>/dev/null || true
	if [ "$proc_tmp" = 1 ]; then
		umount "$ROOT/proc" 2>/dev/null || busybox umount "$ROOT/proc" 2>/dev/null || true
	fi
	return 0
}
trap cleanup EXIT

# Preseed the DM choice BEFORE installing: with the file already present, each DM postinst takes it
# as the answer to the shared debconf question instead of claiming the display for whichever
# package happened to unpack first (a DE metapackage can pull in a second DM as a dependency).
if [ -n "$dm_bin" ]; then
	run_in_target mkdir -p /etc/X11
	run_in_target sh -c "printf '%s\n' '$dm_bin' > /etc/X11/default-display-manager"
fi

bp_progress 10
bp_log "installing $ANS_desktop ${ANS_dm:+($ANS_dm)} — this downloads packages"
run_in_target env DEBIAN_FRONTEND=noninteractive apt-get update || bp_fail "apt-get update failed (no network?)"
bp_progress 25
# shellcheck disable=SC2086
run_in_target env DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical \
	apt-get -y --no-install-recommends install $de_pkgs $dm_pkg \
	|| bp_fail "package install failed (network? disk space?)"
bp_progress 80

# Where a unit file lives differs between usr-merged and older layouts; resolve it rather than
# guessing, because the manual fallback below needs the real path.
unit_path() {
	for d in /usr/lib/systemd/system /lib/systemd/system; do
		if run_in_target test -e "$d/$1"; then printf '%s\n' "$d/$1"; return 0; fi
	done
	return 1
}

if [ -n "$dm_svc" ]; then
	run_in_target sh -c "printf '%s\n' '$dm_bin' > /etc/X11/default-display-manager"
	# Every Debian DM unit carries Alias=display-manager.service, so "which DM runs" is that single
	# symlink — repoint it and any other DM a metapackage dragged in simply stays idle.
	run_in_target rm -f /etc/systemd/system/display-manager.service
	if ! run_in_target systemctl enable "$dm_svc.service" >/dev/null 2>&1; then
		# systemctl only does the offline (filesystem) enable once it knows it is in a chroot, and
		# it learns that from /proc — without it, it tries the bus and fails. Make the same links.
		bp_log "systemctl unavailable in the chroot — wiring $dm_svc by symlink"
		u="$(unit_path "$dm_svc.service")" || bp_fail "no systemd unit for $dm_svc"
		run_in_target ln -sf "$u" /etc/systemd/system/display-manager.service \
			|| bp_fail "could not enable $dm_svc"
	fi
	# Enabling is only half of it: the DM is wanted by graphical.target and a container image boots
	# multi-user.target, so it would never be pulled in. graphical.target still requires
	# multi-user.target, so the base's peacock-flavor-ready unit keeps firing as before.
	if ! run_in_target systemctl set-default graphical.target >/dev/null 2>&1; then
		g="$(unit_path graphical.target)" || bp_fail "no graphical.target in the flavor"
		run_in_target ln -sf "$g" /etc/systemd/system/default.target \
			|| bp_fail "could not switch to graphical.target"
	fi
	bp_log "enabled $dm_svc"
else
	# No login manager wanted — make sure a DM pulled in as a dependency doesn't grab the display.
	run_in_target rm -f /etc/systemd/system/display-manager.service /etc/X11/default-display-manager
	bp_log "no login manager — log in on the console and use startx"
fi
bp_progress 100
