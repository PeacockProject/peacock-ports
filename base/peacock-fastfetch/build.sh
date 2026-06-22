# shellcheck shell=sh
# peacock-fastfetch — no sources, no compilation: stages two boot scripts and
# an OpenRC service. prepare() is a no-op (no tarball); package() writes the
# files into $pkgdir verbatim from the old inline script.

package() {
mkdir -p $pkgdir/usr/bin $pkgdir/etc/init.d $pkgdir/etc/runlevels/default

cat > $pkgdir/usr/bin/peacock-fastfetch-boot <<'EOF'
#!/bin/sh
if [ ! -x /usr/bin/fastfetch ]; then
    echo "fastfetch: binary not found"
    exit 0
fi

echo "=== FASTFETCH BOOT SUMMARY ==="
# Keep output short/ASCII-ish so framebuffer text renderer can show it reliably.
/usr/bin/fastfetch --logo none 2>/dev/null \
  | /usr/bin/sed 's/[^[:print:]\t]//g' \
  | while IFS=: read -r key val; do
      case "$key" in
          OS|Kernel|Uptime|Packages|CPU|Memory|Swap|Battery|Locale|"Disk (/)")
              val="$(echo "$val" | /usr/bin/sed -E 's/^[[:space:]]+//; s/[[:space:]]+/ /g')"
              echo "$key: $val"
              ;;
      esac
    done \
  || true
echo "=== FASTFETCH END ==="
EOF

chmod 0755 $pkgdir/usr/bin/peacock-fastfetch-boot

cat > $pkgdir/usr/bin/peacock-fastfetch-fb <<'EOF'
#!/bin/sh
FBDEV="${FBDEV:-/dev/fb0}"

if [ ! -x /usr/bin/fastfetch ] || [ ! -x /usr/bin/peacock-splash ]; then
    exit 0
fi

# Wait until OpenRC default runlevel settles and rc logger stops.
sleep 4

LINE=1
MAX_LINES=26

/usr/bin/peacock-splash "FASTFETCH" 0 "$FBDEV" 000000 2>/dev/null || true

/usr/bin/fastfetch --logo none 2>/dev/null \
  | /usr/bin/sed 's/[^[:print:]\t]//g' \
  | while IFS=: read -r key val; do
      case "$key" in
          OS|Kernel|Uptime|Packages|CPU|Memory|Swap|Battery|Locale|"Disk (/)")
              val="$(echo "$val" | /usr/bin/sed -E 's/^[[:space:]]+//; s/[[:space:]]+/ /g')"
              /usr/bin/peacock-splash "$key: $val" "$LINE" "$FBDEV" 000000 noclear 2>/dev/null || true
              LINE=$((LINE + 1))
              [ "$LINE" -gt "$MAX_LINES" ] && break
              ;;
      esac
    done
EOF

chmod 0755 $pkgdir/usr/bin/peacock-fastfetch-fb

cat > $pkgdir/etc/init.d/peacock-fastfetch <<'EOF'
#!/sbin/openrc-run
description="Print fastfetch summary and repaint framebuffer at end of boot"
command="/usr/bin/peacock-fastfetch-boot"
start_post() {
    /usr/bin/peacock-fastfetch-fb >/dev/null 2>&1 &
}

depend() {
    after local netmount
}
EOF

chmod 0755 $pkgdir/etc/init.d/peacock-fastfetch
ln -sf /etc/init.d/peacock-fastfetch $pkgdir/etc/runlevels/default/peacock-fastfetch
}
