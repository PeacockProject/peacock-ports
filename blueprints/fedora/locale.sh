#!/bin/sh
# Fedora locale stage.
#
# Fedora has NO /etc/locale.gen and NO locale-gen — that is an Arch/Debian mechanism. Fedora ships
# compiled locales as glibc-langpack-<lang> RPMs, and this container image carries only C.utf8 plus
# an EMPTY /usr/share/i18n/locales, so `localedef` has no source data to fall back on either: the
# langpack really is the only way to get the locale. LANG itself lives in /etc/locale.conf, which we
# write directly — `localectl set-locale` needs a running systemd + dbus that a chroot has not.
set -u

bp_mounted=""
unbind_kernel_fs() {
	for m in $bp_mounted; do umount "$m" 2>/dev/null || umount -l "$m" 2>/dev/null || true; done
	bp_mounted=""
}
trap unbind_kernel_fs EXIT INT TERM
# dnf/rpm want /proc and a real /dev (the container rootfs ships /dev empty) — see account.sh.
if [ "${ROOT:-/}" != "/" ]; then
	for d in /proc /sys /dev /dev/pts; do
		mkdir -p "$ROOT$d" 2>/dev/null || continue
		mount -o bind "$d" "$ROOT$d" 2>/dev/null && bp_mounted="$ROOT$d $bp_mounted"
	done
fi
in_flavor() { run_in_target /bin/sh -c 'PATH=/usr/sbin:/usr/bin:/sbin:/bin; exec "$@"' sh "$@"; }

loc="$ANS_locale"
lang="${loc%%_*}"                                       # en_US.UTF-8 -> en  -> glibc-langpack-en
have=$(printf '%s' "$loc" | tr 'A-Z' 'a-z' | tr -d '-') # locale -a spells it en_US.utf8

bp_progress 20
printf 'LANG=%s\n' "$loc" > "$ROOT/etc/locale.conf"

if in_flavor locale -a 2>/dev/null | grep -qix "$have"; then
	bp_log "locale $loc already compiled"
else
	bp_log "installing glibc-langpack-$lang"
	# Weak deps off: a langpack's Recommends drag in the matching hunspell/aspell dictionaries and
	# fonts, which is a lot of megabytes for a phone that only wants LANG set.
	in_flavor dnf -y --setopt=install_weak_deps=False install "glibc-langpack-$lang" \
		|| bp_log "warning: glibc-langpack-$lang failed to install (no network?) — LANG is set but the locale falls back to C.UTF-8"
fi

bp_progress 100
bp_log "locale -> $loc"
