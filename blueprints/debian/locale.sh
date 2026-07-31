#!/bin/sh
# Debian locale stage. Debian generates no locales at all out of the box and the generator ships in
# the `locales` package, so: make sure locale-gen exists, list the wanted locale in /etc/locale.gen,
# generate it, and record it in /etc/default/locale — Debian's system-wide locale file, read by PAM
# on every login. /etc/locale.conf (the Arch file) is NOT it; the container image even ships
# /etc/default/locale as a symlink *to* /etc/locale.conf, so replace the link with a real file and
# keep locale.conf in step for systemd/localectl.
set -u

if ! run_in_target test -x /usr/sbin/locale-gen; then
	bp_log "locale-gen missing — installing locales"
	run_in_target sh -c 'printf "#!/bin/sh\nexit 101\n" > /usr/sbin/policy-rc.d && chmod 755 /usr/sbin/policy-rc.d'
	run_in_target env DEBIAN_FRONTEND=noninteractive apt-get update >/dev/null 2>&1 \
		|| bp_fail "apt-get update failed (no network?)"
	run_in_target env DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-recommends install locales \
		|| bp_fail "installing locales failed"
	run_in_target rm -f /usr/sbin/policy-rc.d
fi

# /etc/locale.gen lists every known locale commented out — uncomment ours if it's there, append it
# if this is a stripped file. Done inside the flavor: its sed is guaranteed, the base's is not.
run_in_target sh -c "sed -i 's/^# *\\($ANS_locale UTF-8\\)\$/\\1/' /etc/locale.gen; grep -q '^$ANS_locale UTF-8' /etc/locale.gen || echo '$ANS_locale UTF-8' >> /etc/locale.gen" \
	|| bp_fail "could not edit /etc/locale.gen"
run_in_target locale-gen || bp_fail "locale-gen failed"

run_in_target rm -f /etc/default/locale
if run_in_target test -x /usr/sbin/update-locale; then
	run_in_target /usr/sbin/update-locale "LANG=$ANS_locale" || bp_fail "update-locale failed"
else
	run_in_target sh -c "printf 'LANG=%s\n' '$ANS_locale' > /etc/default/locale" || bp_fail "could not write /etc/default/locale"
fi
run_in_target sh -c "printf 'LANG=%s\n' '$ANS_locale' > /etc/locale.conf" || bp_fail "could not write /etc/locale.conf"

bp_log "locale -> $ANS_locale"
