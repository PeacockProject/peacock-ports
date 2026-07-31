#!/bin/sh
# Alpine locale — or rather, the honest absence of one.
#
# Alpine is musl, and musl implements exactly two locales: "C" and "C.UTF-8". There is no
# locale-gen, no /etc/locale.gen, no /usr/lib/locale, no localedef; setlocale(LC_ALL,"tr_TR.UTF-8")
# just falls back to C. So this stage does NOT fake a locale-gen run. What it can honestly do:
#
#   * export LANG/CHARSET from a profile drop-in. That is what selects UTF-8 handling, and it is
#     what the musl-locales package (installed by the account stage) reads to find its LC_MESSAGES
#     catalogues — so program output really does get translated.
#   * leave collation, number and date formatting as C, because musl cannot do otherwise. Anyone
#     who needs real locale formatting on this device wants the Void or Arch flavor (glibc).
#
# Named 99- so it sorts after Alpine's stock /etc/profile.d/20locale.sh, which would otherwise pin
# LANG to its C.UTF-8 default.
set -u
mkdir -p "$ROOT/etc/profile.d"
cat > "$ROOT/etc/profile.d/99-peacock-locale.sh" <<EOF
# Set by the PeacockOS OOBE. musl supports only C/C.UTF-8 collation and formatting; LANG here
# selects the character set and the LC_MESSAGES catalogue (musl-locales), nothing more.
export CHARSET=UTF-8
export LANG=$ANS_locale
export LC_COLLATE=C
EOF
chmod 644 "$ROOT/etc/profile.d/99-peacock-locale.sh"

# Login managers and desktop sessions never source /etc/profile, but PAM does read
# /etc/environment — write it there too so a graphical login gets the same LANG.
printf 'LANG=%s\nCHARSET=UTF-8\n' "$ANS_locale" > "$ROOT/etc/environment"

bp_log "locale -> $ANS_locale (musl: messages only, formatting stays C)"
