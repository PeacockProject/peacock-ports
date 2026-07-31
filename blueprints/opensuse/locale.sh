#!/bin/sh
# openSUSE locale stage.
#
# openSUSE has NO /etc/locale.gen and NO locale-gen — that is an Arch/Debian mechanism. Locales come
# from the glibc-locale RPM (glibc-locale-base in the image only carries C.utf8 + en_US.utf8), and
# this container rootfs has no /usr/share/i18n at all, so `localedef` has nothing to compile from:
# the package really is the only way to get another locale. LANG itself lives in /etc/locale.conf,
# which we write directly — `localectl set-locale` needs a running systemd + dbus a chroot has not.
set -u

bp_mounted=""
unbind_kernel_fs() {
	for m in $bp_mounted; do umount "$m" 2>/dev/null || umount -l "$m" 2>/dev/null || true; done
	bp_mounted=""
}
trap unbind_kernel_fs EXIT INT TERM
# zypper/rpm want /proc and a real /dev (the container rootfs ships /dev empty) — see account.sh.
if [ "${ROOT:-/}" != "/" ]; then
	for d in /proc /sys /dev /dev/pts; do
		mkdir -p "$ROOT$d" 2>/dev/null || continue
		mount -o bind "$d" "$ROOT$d" 2>/dev/null && bp_mounted="$ROOT$d $bp_mounted"
	done
fi
in_flavor() { run_in_target /bin/sh -c 'PATH=/usr/sbin:/usr/bin:/sbin:/bin; exec "$@"' sh "$@"; }

loc="$ANS_locale"
have=$(printf '%s' "$loc" | tr 'A-Z' 'a-z' | tr -d '-')  # locale -a spells it en_US.utf8

bp_progress 20
printf 'LANG=%s\n' "$loc" > "$ROOT/etc/locale.conf"

if in_flavor locale -a 2>/dev/null | grep -qix "$have"; then
	bp_log "locale $loc already compiled"
else
	bp_log "installing glibc-locale (full locale data)"
	in_flavor zypper -n --gpg-auto-import-keys install glibc-locale \
		|| bp_log "warning: glibc-locale failed to install (no network?) — LANG is set but the locale falls back to C.UTF-8"
fi

bp_progress 100
bp_log "locale -> $loc"
