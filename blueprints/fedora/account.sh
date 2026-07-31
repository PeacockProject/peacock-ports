#!/bin/sh
# Fedora account stage. $ROOT is the flavor root here, so run_in_target chroots into Fedora.
#
# Two things the runner does NOT do for us and that this rootfs needs:
#   * run_in_target is a bare `chroot "$ROOT" "$@"` — the program is resolved with the CALLER's
#     PATH, and peacock-init hands children an empty one (execvp then only searches /bin:/usr/bin).
#     So always enter through an absolute /bin/sh that sets PATH itself.
#   * the container rootfs ships an EMPTY /dev (no /dev/null, no /dev/urandom for shadow's salt) and
#     nothing mounts /proc — bind them for the duration of the stage, and always tear them down.
set -u

bp_mounted=""
unbind_kernel_fs() {
	for m in $bp_mounted; do umount "$m" 2>/dev/null || umount -l "$m" 2>/dev/null || true; done
	bp_mounted=""
}
trap unbind_kernel_fs EXIT INT TERM
if [ "${ROOT:-/}" != "/" ]; then
	for d in /proc /sys /dev /dev/pts; do
		mkdir -p "$ROOT$d" 2>/dev/null || continue
		# prepend, so the teardown loop unmounts /dev/pts before /dev
		mount -o bind "$d" "$ROOT$d" 2>/dev/null && bp_mounted="$ROOT$d $bp_mounted"
	done
fi

# "$@" is passed through as real argv — never interpolated into the -c string.
in_flavor() { run_in_target /bin/sh -c 'PATH=/usr/sbin:/usr/bin:/sbin:/bin; exec "$@"' sh "$@"; }

bp_progress 10
# Fedora ships a wheel group, but create it idempotently so we never depend on the image's group
# table staying that way. -f makes an existing group a success.
in_flavor groupadd -f wheel || bp_fail "groupadd wheel failed"

in_flavor useradd -m -G wheel -s /bin/bash "$ANS_user" || bp_fail "useradd failed"
printf '%s:%s' "$ANS_user" "$ANS_pass" \
	| run_in_target /bin/sh -c 'PATH=/usr/sbin:/usr/bin:/sbin:/bin; exec chpasswd' \
	|| bp_fail "chpasswd failed"
bp_progress 60

# Membership in wheel grants nothing by itself — it needs a sudoers rule AND sudo installed. Fedora
# happens to enable %wheel in /etc/sudoers already, but state it explicitly so the guarantee holds
# even if the base image changes. sudo reads /etc/sudoers.d via the includedir at the end of
# /etc/sudoers; a filename containing '.' or '~' is ignored, and the mode must be 0440.
if [ ! -x "$ROOT/usr/bin/sudo" ]; then
	bp_log "sudo is not installed — pulling it in"
	in_flavor dnf -y --setopt=install_weak_deps=False install sudo \
		|| bp_log "warning: could not install sudo (no network?) — $ANS_user will have no admin rights"
fi
mkdir -p "$ROOT/etc/sudoers.d"
printf '%s\n' '%wheel ALL=(ALL:ALL) ALL' > "$ROOT/etc/sudoers.d/10-peacock-wheel"
chmod 0440 "$ROOT/etc/sudoers.d/10-peacock-wheel"

bp_progress 100
bp_log "account $ANS_user created (admin via wheel)"
