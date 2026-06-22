# shellcheck shell=sh
# samsung-jflte-fb-logger — stage the framebuffer refresher wrapper and its
# OpenRC service into $pkgdir. No source/compile; prepare() is a no-op.

prepare() { :; }

package() {
  mkdir -p "$pkgdir/usr/bin" "$pkgdir/etc/init.d" "$pkgdir/etc/runlevels/sysinit"

  cat > "$pkgdir/usr/bin/peacock-fb-refresher" <<'EOF'
#!/bin/sh
set -eu

# Some kernels create only /dev/graphics/fb0 (Android-style). Link it if needed.
if [ -e /dev/graphics/fb0 ] && [ ! -e /dev/fb0 ]; then
    ln -sf /dev/graphics/fb0 /dev/fb0
fi

# Wait briefly for fb0 to report a usable mode so the refresher doesn't exit early.
i=0
while [ "$i" -lt 120 ]; do
    if [ -e /dev/fb0 ] || [ -e /dev/graphics/fb0 ]; then
        if [ -r /sys/class/graphics/fb0/virtual_size ]; then
            vs="$(cat /sys/class/graphics/fb0/virtual_size 2>/dev/null || true)"
            [ -n "$vs" ] && [ "$vs" != "0,0" ] && break
        else
            break
        fi
    fi
    i=$((i+1))
    sleep 0.1
done

exec /usr/bin/msm-fb-refresher --loop
EOF

  chmod 0755 "$pkgdir/usr/bin/peacock-fb-refresher"

  cat > "$pkgdir/etc/init.d/peacock-fb-refresher" <<'EOF'
#!/sbin/openrc-run
description="Keep MSM framebuffer refreshing"
command="/usr/bin/peacock-fb-refresher"
command_background="yes"
pidfile="/run/peacock-fb-refresher.pid"

depend() {
    need localmount
    before bootmisc
}
EOF

  chmod 0755 "$pkgdir/etc/init.d/peacock-fb-refresher"
  ln -sf /etc/init.d/peacock-fb-refresher \
    "$pkgdir/etc/runlevels/sysinit/peacock-fb-refresher"
}
