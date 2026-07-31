#!/bin/sh
# Void locale (glibc variant — this is why the glibc rootfs was chosen over the musl one).
#
# Void does NOT use /etc/locale.gen + locale-gen. Its equivalent is /etc/default/libc-locales:
# uncomment the wanted line, then `xbps-reconfigure -f glibc-locales` regenerates /usr/lib/locale
# from it. The rootfs ships that file with only en_US.UTF-8 enabled, so anything else has to be
# uncommented first or setlocale() falls back to C at runtime.
set -u
conf="$ROOT/etc/default/libc-locales"
[ -f "$conf" ] || bp_fail "no /etc/default/libc-locales — is glibc-locales installed?"

# Every entry in that file is "<locale> <charset>", commented with a leading '#'. Match the exact
# locale name at the start of the line so tr_TR.UTF-8 can't be matched by a longer neighbour.
if grep -qE "^#[[:space:]]*$ANS_locale[[:space:]]" "$conf"; then
	sed -i "s/^#[[:space:]]*\($ANS_locale[[:space:]]\)/\1/" "$conf" \
		|| bp_fail "could not enable $ANS_locale in libc-locales"
elif ! grep -qE "^$ANS_locale[[:space:]]" "$conf"; then
	# Not listed at all (unlikely, the file is exhaustive) — append it rather than fail.
	printf '%s UTF-8\n' "$ANS_locale" >> "$conf"
fi

bp_progress 40
bp_log "generating $ANS_locale — this takes a moment"
run_in_target xbps-reconfigure -f glibc-locales || bp_fail "locale generation failed"
bp_progress 90

# /etc/locale.conf is what Void reads for the system-wide LANG (the rootfs ships it defaulting to
# en_US.UTF-8). Keep its LC_COLLATE=C: it makes `ls` and shell globbing sort by byte value, which
# is what almost everyone actually wants, and it is what Void itself ships.
printf 'LANG=%s\nLC_COLLATE=C\n' "$ANS_locale" > "$ROOT/etc/locale.conf"
bp_log "locale -> $ANS_locale"
