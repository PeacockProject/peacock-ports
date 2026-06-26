#!/bin/sh
set -u
run_in_target sh -c "echo '$ANS_locale UTF-8' >> /etc/locale.gen && locale-gen"
printf 'LANG=%s\n' "$ANS_locale" | run_in_target tee /etc/locale.conf >/dev/null
bp_log "locale -> $ANS_locale"
