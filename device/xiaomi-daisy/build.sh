# shellcheck shell=sh
# device-xiaomi-daisy — Xiaomi Mi A2 Lite device meta/quirk port. No source
# tarball, so prepare() is a no-op; package() stages the daisy seat-init
# OpenRC service, SDDM/Xorg config and session files into $pkgdir.

package() {
  mkdir -p \
      "$pkgdir/etc/init.d" \
      "$pkgdir/etc/X11/xinit/xinitrc.d" \
      "$pkgdir/etc/X11/xorg.conf.d" \
      "$pkgdir/etc/sddm.conf.d" \
      "$pkgdir/etc/runlevels/boot" \
      "$pkgdir/etc/runlevels/default" \
      "$pkgdir/usr/local/share/xsessions" \
      "$pkgdir/usr/local/share/wayland-sessions" \
      "$pkgdir/usr/local/sbin"

  cat > "$pkgdir/usr/local/sbin/peacock-daisy-seat-init" <<'EOF'
#!/bin/sh
set -eu

# sddm/elogind won't start X until seat devices are visible.
if ! pidof udevd >/dev/null 2>&1; then
    /usr/sbin/udevd --daemon >/dev/null 2>&1 || true
fi

udevadm trigger --action=add >/dev/null 2>&1 || true
udevadm settle >/dev/null 2>&1 || true
exit 0
EOF
  chmod 0755 "$pkgdir/usr/local/sbin/peacock-daisy-seat-init"

  cat > "$pkgdir/etc/init.d/peacock-daisy-seat-init" <<'EOF'
#!/sbin/openrc-run
description="Initialize udev seat devices for sddm on xiaomi-daisy"

command="/usr/local/sbin/peacock-daisy-seat-init"

depend() {
    need localmount devfs
    after modules
    before sddm
}
EOF
  chmod 0755 "$pkgdir/etc/init.d/peacock-daisy-seat-init"

  ln -sf /etc/init.d/peacock-daisy-seat-init "$pkgdir/etc/runlevels/boot/peacock-daisy-seat-init"
  ln -sf /etc/init.d/peacock-daisy-seat-init "$pkgdir/etc/runlevels/default/peacock-daisy-seat-init"

  # Override builder-default SDDM settings for daisy:
  # - use Peacock phone theme
  # - disable Qt virtual keyboard plugin so only theme keyboard is shown
  cat > "$pkgdir/etc/sddm.conf.d/zz-peacock-daisy.conf" <<'EOF'
[General]
InputMethod=
GreeterEnvironment=QT_QUICK_BACKEND=software,QSG_RHI_BACKEND=software,QT_XCB_NO_XI2=1

[Theme]
Current=peacock-phone
EOF

  # Ensure an X11 session dbus bus exists on OpenRC/elogind boots.
  cat > "$pkgdir/etc/X11/xinit/xinitrc.d/90-peacock-dbus.sh" <<'EOF'
#!/bin/sh
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && command -v dbus-launch >/dev/null 2>&1; then
    eval "$(dbus-launch --sh-syntax --exit-with-session)"
fi
EOF
  chmod 0755 "$pkgdir/etc/X11/xinit/xinitrc.d/90-peacock-dbus.sh"

  # Force XFCE X11 session through dbus-run-session so xfce settings/xfconf
  # can reliably connect on OpenRC + elogind systems.
  cat > "$pkgdir/usr/local/share/xsessions/xfce.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Xfce Session
Comment=Use this session to run Xfce as your desktop environment
Exec=dbus-run-session -- startxfce4
TryExec=startxfce4
DesktopNames=XFCE
EOF

  # Hide Wayland session on daisy until compositor/runtime is shipped.
  cat > "$pkgdir/usr/local/share/wayland-sessions/xfce-wayland.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Xfce Session (Wayland)
Hidden=true
EOF

  # Daisy touch calibration for Goodix panel under Xorg/libinput.
  cat > "$pkgdir/etc/X11/xorg.conf.d/40-peacock-daisy-touch.conf" <<'EOF'
Section "InputClass"
    Identifier "Peacock Daisy Touch Calibration"
    MatchProduct "Goodix Capacitive TouchScreen"
    MatchIsTouchscreen "on"
    Driver "libinput"
    Option "CalibrationMatrix" "3.841 0 -0.0075 0 1.811 -0.0075 0 0 1"
EndSection
EOF
}
