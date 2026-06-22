# shellcheck shell=sh
# oppo-a16-display-fix — OPPO A16 OpenRC display preflight + Xorg/SDDM quirks.
# No source tarball, so prepare() is a no-op. build() compiles the fbpan
# FBIOPAN_DISPLAY helper into $pkgdir; package() stages all config/service/
# wrapper files into $pkgdir.

build() {
  mkdir -p "$pkgdir/usr/local/bin"

  # ── fbpan: FBIOPAN_DISPLAY trigger ────────────────────────────────────
  # MTKFB in DECOUPLE mode stops reading the framebuffer.  FBIOPAN_DISPLAY
  # forces the OVL back to DIRECT_LINK so Xorg output is visible.
  cat > /tmp/fbpan.c <<'FBPAN'
#include <stdio.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <linux/fb.h>
#include <unistd.h>
#include <string.h>
int main() {
    int fd = open("/dev/fb0", O_RDWR);
    if (fd < 0) { perror("open"); return 1; }
    struct fb_var_screeninfo v;
    if (ioctl(fd, FBIOGET_VSCREENINFO, &v) < 0) {
        memset(&v, 0, sizeof(v));
        v.xres = 720; v.yres = 1600;
        v.xres_virtual = 720; v.yres_virtual = 1600;
        v.bits_per_pixel = 32;
    }
    v.xoffset = 0; v.yoffset = 0;
    v.activate = 0x80 | 0x100; /* FB_ACTIVATE_NOW | FB_ACTIVATE_FORCE */
    if (ioctl(fd, FBIOPAN_DISPLAY, &v) < 0) perror("FBIOPAN_DISPLAY");
    else printf("fbpan ok\n");
    close(fd);
    return 0;
}
FBPAN
  ${CROSS_COMPILE}gcc -static -o "$pkgdir/usr/local/bin/fbpan" /tmp/fbpan.c
  chmod 0755 "$pkgdir/usr/local/bin/fbpan"
}

package() {
  mkdir -p "$pkgdir/etc/init.d" "$pkgdir/etc/runlevels/boot" "$pkgdir/etc/runlevels/default"
  mkdir -p "$pkgdir/usr/local/sbin" "$pkgdir/usr/local/bin" "$pkgdir/etc/conf.d"
  mkdir -p "$pkgdir/etc/udev/rules.d" "$pkgdir/etc/X11/xorg.conf.d" "$pkgdir/etc/sddm.conf.d"
  mkdir -p "$pkgdir/etc/xdg/xfce4/xfconf/xfce-perchannel-xml"

  # ── cgroup v1 ──────────────────────────────────────────────────────────────
  # MT6765 kernel is cgroup-v1 only.  OpenRC defaults to unified (v2), which
  # leaves /sys/fs/cgroup unmounted and makes elogind crash.
  cat > "$pkgdir/etc/conf.d/cgroups" <<'EOF'
rc_cgroup_mode="legacy"
EOF

  # ── fb0 seat master ────────────────────────────────────────────────────────
  # elogind reports CanGraphical=false on fbdev-only devices unless fb0 is
  # tagged as the seat master.  Without this sddm never launches Xorg.
  # Also tag DRM (PowerVR GPU) and input devices so elogind sees a full seat.
  cat > "$pkgdir/etc/udev/rules.d/71-oppo-a16-seat.rules" <<'EOF'
SUBSYSTEM=="graphics", KERNEL=="fb0", TAG+="seat", ENV{ID_SEAT}="seat0", TAG+="master-of-seat"
SUBSYSTEM=="drm", KERNEL=="card0", TAG+="seat", ENV{ID_SEAT}="seat0"
SUBSYSTEM=="drm", KERNEL=="renderD128", TAG+="seat", ENV{ID_SEAT}="seat0"
SUBSYSTEM=="input", KERNEL=="event*", TAG+="seat", ENV{ID_SEAT}="seat0"
EOF

  # ── Xorg fbdev config ──────────────────────────────────────────────────────
  cat > "$pkgdir/etc/X11/xorg.conf.d/10-peacock-fbdev.conf" <<'EOF'
# Prevent Xorg from auto-probing the Mali GPU DRM device (13000000.mfg_doma).
# That device is render-only (no CRTCs/connectors) and its platform probe
# hangs indefinitely, blocking all of Xorg startup.
#
# DPMS must be fully disabled: MTKFB's blank/unblank kills the display
# pipeline (DSI/DDP/OVL) and the unblank path doesn't restore it.  With
# DPMS active, Xorg sends FB_BLANK on init which leaves the screen dead.
Section "ServerFlags"
    Option "AutoAddDevices" "false"
    Option "AutoAddGPU" "false"
    Option "BlankTime" "0"
    Option "StandbyTime" "0"
    Option "SuspendTime" "0"
    Option "OffTime" "0"
    Option "DPMS" "false"
EndSection

Section "Device"
    Identifier "PeacockFBDev"
    Driver "fbdev"
    Option "fbdev" "/dev/fb0"
    Option "ShadowFB" "true"
EndSection

Section "Screen"
    Identifier "PeacockScreen"
    Device "PeacockFBDev"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
    EndSubSection
EndSection
EOF

  # ── Input config ───────────────────────────────────────────────────────────
  cat > "$pkgdir/etc/X11/xorg.conf.d/40-peacock-input-libinput.conf" <<'EOF'
Section "InputClass"
    Identifier "PeacockTouchscreen"
    MatchIsTouchscreen "on"
    Driver "libinput"
    Option "CalibrationMatrix" "1 0 0 0 1 0 0 0 1"
    Option "Tapping" "on"
EndSection

Section "InputClass"
    Identifier "PeacockPointer"
    MatchIsPointer "on"
    Driver "libinput"
EndSection

Section "InputClass"
    Identifier "PeacockKeyboard"
    MatchIsKeyboard "on"
    Driver "libinput"
EndSection
EOF

  # ── Xorg VT1 wrapper ──────────────────────────────────────────────────────
  # MTKFB's fbcon binding doesn't implement VT switch callbacks, so
  # VT_WAITACTIVE hangs forever when Xorg tries to activate VT2.
  # This wrapper rewrites vtN → vt1 and adds -novtswitch so Xorg stays
  # on the already-active VT1 instead of blocking.
  cat > "$pkgdir/usr/local/bin/Xorg-vt1" <<'EOF'
#!/bin/sh
# Force Xorg to use VT1 — VT switching is broken without working fbcon
args=""
for arg in "$@"; do
    case "$arg" in
        vt[0-9]*) args="$args vt1" ;;
        *) args="$args $arg" ;;
    esac
done
exec /usr/lib/Xorg -novtswitch $args
EOF
  chmod 0755 "$pkgdir/usr/local/bin/Xorg-vt1"

  # ── SDDM config ────────────────────────────────────────────────────────────
  # MinimumVT=1 because tty2+ may not be accessible on this device.
  # Software rendering is required since mtkfb has no GPU/DRM acceleration.
  # ServerPath uses Xorg-vt1 wrapper to avoid VT switch hang.
  cat > "$pkgdir/etc/sddm.conf.d/zzz-oppo-a16.conf" <<'EOF'
[General]
MinimumVT=1
DisplayServer=x11
InputMethod=
RebootCommand=/usr/local/sbin/peacock-sddm-powerctl reboot
HaltCommand=/usr/local/sbin/peacock-sddm-powerctl poweroff
GreeterEnvironment=QT_QUICK_BACKEND=software,QSG_RHI_BACKEND=software,QT_XCB_NO_XI2=1,QT_OPENGL=software,LIBGL_ALWAYS_SOFTWARE=1

[Theme]
Current=peacock-phone

[X11]
ServerPath=/usr/local/bin/Xorg-vt1
ServerArguments=-nolisten tcp -noreset -keeptty -verbose 4 -logfile /var/log/Xorg.0.log -extension GLX -extension COMPOSITE -extension DAMAGE -extension MIT-SHM
EnableHiDPI=false
EOF

  # ── Power-control helper ───────────────────────────────────────────────────
  cat > "$pkgdir/usr/local/sbin/peacock-sddm-powerctl" <<'EOF'
#!/bin/sh
set -eu
action="${1:-}"
run_reboot() {
    command -v loginctl >/dev/null 2>&1 && loginctl reboot >/dev/null 2>&1 && exit 0
    /usr/bin/openrc-shutdown --reboot now >/dev/null 2>&1 && exit 0
    /sbin/reboot >/dev/null 2>&1 && exit 0
    echo 1 > /proc/sys/kernel/sysrq 2>/dev/null || true
    echo b > /proc/sysrq-trigger
}
run_poweroff() {
    command -v loginctl >/dev/null 2>&1 && loginctl poweroff >/dev/null 2>&1 && exit 0
    /usr/bin/openrc-shutdown --poweroff now >/dev/null 2>&1 && exit 0
    /sbin/poweroff >/dev/null 2>&1 && exit 0
    echo 1 > /proc/sys/kernel/sysrq 2>/dev/null || true
    echo o > /proc/sysrq-trigger
}
case "$action" in
    reboot)   run_reboot ;;
    poweroff) run_poweroff ;;
    *)        exit 2 ;;
esac
EOF
  chmod 0755 "$pkgdir/usr/local/sbin/peacock-sddm-powerctl"

  # ── xfwm4: compositing off ─────────────────────────────────────────────────
  # mtkfb fbdev has no OpenGL; xfwm4 compositing crashes without this.
  cat > "$pkgdir/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="use_compositing" type="bool" value="false"/>
    <property name="show_dock_shadow" type="bool" value="false"/>
    <property name="show_frame_shadow" type="bool" value="false"/>
    <property name="show_popup_shadow" type="bool" value="false"/>
  </property>
</channel>
EOF

  # ── XFCE session wrapper ───────────────────────────────────────────────────
  cat > "$pkgdir/usr/local/bin/peacock-startxfce" <<'EOF'
#!/bin/sh
set -eu
uid="$(id -u)"
logf="${HOME:-/tmp}/.local/share/sddm/peacock-startxfce.log"
mkdir -p "$(dirname "$logf")" 2>/dev/null || true
{
    echo "=== peacock-startxfce ==="
    echo "uid=$uid user=${USER:-unknown}"
    echo "date=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo unknown)"
} >> "$logf" 2>&1

# Ensure xdg runtime dir exists (logind may not set it on fbdev).
if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
    for cand in "/run/user/$uid" "/var/run/user/$uid" "/tmp/runtime-$uid"; do
        if mkdir -p "$cand" 2>/dev/null; then
            chmod 0700 "$cand" 2>/dev/null || true
            export XDG_RUNTIME_DIR="$cand"
            echo "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR (created)" >> "$logf" 2>&1
            break
        fi
    done
fi

# Force compositing off for this user.
cfg_home="${XDG_CONFIG_HOME:-${HOME:-/tmp}/.config}"
cfg_file="$cfg_home/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml"
mkdir -p "$(dirname "$cfg_file")" 2>/dev/null || true
if [ ! -f "$cfg_file" ]; then
    cat > "$cfg_file" <<'XFCFG'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="use_compositing" type="bool" value="false"/>
    <property name="show_dock_shadow" type="bool" value="false"/>
    <property name="show_frame_shadow" type="bool" value="false"/>
    <property name="show_popup_shadow" type="bool" value="false"/>
  </property>
</channel>
XFCFG
fi

if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && command -v dbus-run-session >/dev/null 2>&1; then
    echo "launch=dbus-run-session startxfce4" >> "$logf" 2>&1
    exec dbus-run-session -- /usr/bin/startxfce4 >> "$logf" 2>&1
fi
echo "launch=startxfce4" >> "$logf" 2>&1
exec /usr/bin/startxfce4 >> "$logf" 2>&1
EOF
  chmod 0755 "$pkgdir/usr/local/bin/peacock-startxfce"

  # ── xfwm4 wrapper (compositor=off, fallback to openbox) ───────────────────
  cat > "$pkgdir/usr/local/bin/peacock-xfwm4" <<'EOF'
#!/bin/sh
logf="${HOME:-/tmp}/.local/share/sddm/peacock-xfwm4.log"
mkdir -p "$(dirname "$logf")" 2>/dev/null || true
n=0
while [ "$n" -lt 6 ]; do
    /usr/bin/xfwm4 --compositor=off "$@" >> "$logf" 2>&1
    echo "xfwm4 exit $? iter=$n" >> "$logf" 2>&1
    n=$((n + 1))
    sleep 1
done
[ -x /usr/bin/openbox ] && exec /usr/bin/openbox "$@" >> "$logf" 2>&1
exit 0
EOF
  chmod 0755 "$pkgdir/usr/local/bin/peacock-xfwm4"

  # ── xfdesktop wrapper (disable-wm-check) ──────────────────────────────────
  cat > "$pkgdir/usr/local/bin/peacock-xfdesktop" <<'EOF'
#!/bin/sh
exec /usr/bin/xfdesktop --disable-wm-check "$@"
EOF
  chmod 0755 "$pkgdir/usr/local/bin/peacock-xfdesktop"

  # ── xfce4-panel wrapper (disable-wm-check) ────────────────────────────────
  cat > "$pkgdir/usr/local/bin/peacock-xfce4-panel" <<'EOF'
#!/bin/sh
exec /usr/bin/xfce4-panel --disable-wm-check "$@"
EOF
  chmod 0755 "$pkgdir/usr/local/bin/peacock-xfce4-panel"

  # ── Main display-fix init script ───────────────────────────────────────────
  cat > "$pkgdir/etc/init.d/oppo-a16-display-fix" <<'SCRIPT'
#!/sbin/openrc-run

description="OPPO A16 display preflight"

depend() {
    need localmount devfs
    before display-manager sddm lightdm greetd gdm ly
}

start() {
    checkpath -d -m 0755 /var/log
    LOG_FILE="/var/log/oppo-a16-display-fix.log"
    {
        echo "=== oppo-a16-display-fix start ==="
        date -u '+utc=%Y-%m-%dT%H:%M:%SZ'
    } >> "$LOG_FILE" 2>&1

    # ── Fix broken tty device nodes ───────────────────────────────────────
    # Some initramfs/devfs implementations create tty2-12 as regular text
    # files instead of proper character devices.  VT switching, Xorg, and
    # elogind all break without real ttys.
    for n in 0 1 2 3 4 5 6 7 8 9 10 11 12; do
        dev="/dev/tty${n}"
        if [ -e "$dev" ] && ! [ -c "$dev" ]; then
            rm -f "$dev"
            mknod "$dev" c 4 "$n"
            chmod 0620 "$dev"
            echo "fixed tty${n}: was not a char device" >> "$LOG_FILE" 2>&1
        elif ! [ -e "$dev" ]; then
            mknod "$dev" c 4 "$n"
            chmod 0620 "$dev"
            echo "created tty${n}" >> "$LOG_FILE" 2>&1
        fi
    done

    # ── Remove Mali DRM device ────────────────────────────────────────────
    # The Mali GPU (13000000.mfg_doma) exposes /dev/dri/card0 but has no
    # CRTCs or connectors (render-only).  Xorg's platform bus probes it
    # anyway and hangs for ~3 minutes in firmware_fallback_sysfs.
    # Removing the device node before Xorg starts avoids the hang.
    rm -f /dev/dri/card0 2>/dev/null
    echo "removed /dev/dri/card0 (Mali render-only)" >> "$LOG_FILE" 2>&1

    # ── Wake display pipeline ─────────────────────────────────────────────
    # MTKFB idle manager switches to DECOUPLE mode after ~50ms of no FB
    # activity.  In DECOUPLE the OVL stops reading the framebuffer so
    # nothing rendered by Xorg is visible.  Set idle timeout very high,
    # blank/unblank to reset the DSI pipeline, then FBIOPAN_DISPLAY to
    # force DIRECT_LINK mode so the OVL continuously reads from the FB.
    echo 999999 > /proc/displowpower/idletime 2>/dev/null
    echo 1 > /sys/class/graphics/fb0/blank 2>/dev/null
    sleep 1
    echo 0 > /sys/class/graphics/fb0/blank 2>/dev/null
    echo 4095 > /sys/class/leds/lcd-backlight/brightness 2>/dev/null
    if [ -x /usr/local/bin/fbpan ]; then
        /usr/local/bin/fbpan >> "$LOG_FILE" 2>&1
    fi
    echo "display wake done" >> "$LOG_FILE" 2>&1

    # Ensure udev is alive so fb0 gets tagged as seat master before elogind.
    if ! pidof udevd >/dev/null 2>&1; then
        /sbin/udevd --daemon >/dev/null 2>&1 || true
        /usr/lib/systemd/systemd-udevd --daemon >/dev/null 2>&1 || true
    fi
    /usr/bin/udevadm control --reload-rules >/dev/null 2>&1 || true
    /usr/bin/udevadm trigger --action=add --type=subsystems >/dev/null 2>&1 || true
    /usr/bin/udevadm trigger --action=add --type=devices >/dev/null 2>&1 || true
    /usr/bin/udevadm settle --timeout=10 >/dev/null 2>&1 || true
    echo "udevadm settle done" >> "$LOG_FILE" 2>&1

    # Ensure Xorg config dirs exist.
    checkpath -d -m 0755 /etc/X11/xorg.conf.d
    checkpath -d -m 0755 /etc/sddm.conf.d
    checkpath -d -m 0755 /etc/peacock

    # Detect touchscreen event node (Goodix on OPPO A16).
    touch_event="none"
    for ev in /dev/input/event*; do
        [ -e "$ev" ] || continue
        evnum="${ev##*/}"
        name=""
        if [ -f "/sys/class/input/${evnum}/device/name" ]; then
            name=$(cat "/sys/class/input/${evnum}/device/name" 2>/dev/null || true)
        fi
        lname=$(echo "$name" | tr '[:upper:]' '[:lower:]')
        case "$lname" in
            *goodix*|*touchscreen*|*touchpanel*)
                touch_event="$ev"
                break
                ;;
        esac
    done
    echo "touch_event=$touch_event" >> "$LOG_FILE" 2>&1

    # Static evdev touchscreen config if detected.
    rm -f /etc/X11/xorg.conf.d/41-peacock-touch-static.conf
    if [ "$touch_event" != "none" ]; then
        cat > /etc/X11/xorg.conf.d/41-peacock-touch-static.conf <<CFG
Section "InputDevice"
    Identifier "PeacockTouchDevice"
    Driver "evdev"
    Option "Device" "$touch_event"
    Option "Mode" "Absolute"
    Option "IgnoreRelativeAxes" "True"
    Option "IgnoreAbsoluteAxes" "False"
EndSection

Section "ServerLayout"
    Identifier "PeacockLayout"
    Screen 0 "PeacockScreen"
    InputDevice "PeacockTouchDevice" "CorePointer"
EndSection
CFG
        echo "wrote 41-peacock-touch-static.conf" >> "$LOG_FILE" 2>&1
    fi

    # Patch xfwm4 references in xfce4-session config if present.
    if [ -f /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml ]; then
        sed -i 's/value="xfwm4"/value="peacock-xfwm4"/g' \
            /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml || true
        sed -i 's/value="xfdesktop"/value="peacock-xfdesktop"/g' \
            /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml || true
        sed -i 's/value="xfce4-panel"/value="peacock-xfce4-panel"/g' \
            /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-session.xml || true
    fi

    # Patch .desktop XFCE session entry to use our wrapper.
    if [ -f /usr/share/xsessions/xfce.desktop ]; then
        sed -i 's|^Exec=.*|Exec=/usr/local/bin/peacock-startxfce|' \
            /usr/share/xsessions/xfce.desktop || true
    fi

    # Force compositing off for all existing users.
    for home_dir in /home/*; do
        [ -d "$home_dir" ] || continue
        cfg="$home_dir/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml"
        mkdir -p "$(dirname "$cfg")" || continue
        if [ -f "$cfg" ]; then
            sed -i 's/\(<property name="use_compositing" type="bool" value="\)true\(".*\)/\1false\2/' \
                "$cfg" || true
        else
            cat > "$cfg" <<'XFCFG'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="use_compositing" type="bool" value="false"/>
  </property>
</channel>
XFCFG
        fi
        user_name="$(basename "$home_dir")"
        chown -R "$user_name:$user_name" "$home_dir/.config" 2>/dev/null || true
    done

    # Avoid getty/VT races with sddm.
    rm -f /etc/runlevels/default/agetty.tty1 \
          /etc/runlevels/default/agetty.tty2 \
          /etc/runlevels/default/agetty.tty3

    echo "oppo-a16-display-fix done" >> "$LOG_FILE" 2>&1
}
SCRIPT
  chmod 0755 "$pkgdir/etc/init.d/oppo-a16-display-fix"

  # Run in boot runlevel so it completes before sddm in default.
  ln -sf /etc/init.d/oppo-a16-display-fix "$pkgdir/etc/runlevels/boot/oppo-a16-display-fix"

  # Ensure elogind is in default runlevel.
  mkdir -p "$pkgdir/etc/runlevels/default"
  ln -sf /etc/init.d/elogind "$pkgdir/etc/runlevels/default/elogind"

  # ── Custom sddm init (wait_for_graphical_seat) ─────────────────────────────
  # Replaces the generic sddm-openrc script with one that polls elogind's
  # CanGraphical property before launching sddm.  On fbdev-only hardware
  # elogind can cache CanGraphical=false before udev settles fb0's seat tag.
  cat > "$pkgdir/etc/init.d/sddm" <<'SDDINIT'
#!/usr/bin/openrc-run

supervisor=supervise-daemon
command="/usr/bin/sddm"
command_args="--log-file /var/log/sddm.log --debug"
supervise_daemon_args="--stdout /var/log/sddm.log --stderr /var/log/sddm.log"

wait_for_graphical_seat() {
    command -v busctl >/dev/null 2>&1 || return 0
    checkpath -f -m 0644 /var/log/sddm-preflight.log

    tries=0
    v="false"
    while [ "$tries" -lt 20 ]; do
        v="$(busctl --system get-property org.freedesktop.login1 /org/freedesktop/login1/seat/seat0 org.freedesktop.login1.Seat CanGraphical 2>/dev/null | cut -d" " -f2)"
        [ "$v" = "true" ] && break
        sleep 1
        tries=$((tries + 1))
    done
    echo "preflight can_graphical=$v wait_s=$tries" >> /var/log/sddm-preflight.log

    if [ "$v" != "true" ] && [ -x /etc/init.d/elogind ]; then
        rc-service elogind restart >/dev/null 2>&1 || true
        tries=0
        while [ "$tries" -lt 15 ]; do
            v="$(busctl --system get-property org.freedesktop.login1 /org/freedesktop/login1/seat/seat0 org.freedesktop.login1.Seat CanGraphical 2>/dev/null | cut -d" " -f2)"
            [ "$v" = "true" ] && break
            sleep 1
            tries=$((tries + 1))
        done
        echo "preflight after_elogind_restart can_graphical=$v wait_s=$tries" >> /var/log/sddm-preflight.log
    fi
    return 0
}

start_pre() {
    checkpath -d -m 0755 -o sddm:sddm /var/lib/sddm
    checkpath -d -m 0755 -o sddm:sddm /var/lib/sddm/.local
    checkpath -d -m 0755 -o sddm:sddm /var/lib/sddm/.local/share
    checkpath -d -m 0755 -o sddm:sddm /var/lib/sddm/.local/share/sddm
    checkpath -d -m 0755 -o sddm:sddm /var/run/sddm
    checkpath -f -m 0666 -o sddm:sddm /var/log/sddm.log
    wait_for_graphical_seat
}

depend() {
    need localmount
    after bootmisc consolefont modules netmount
    after oppo-a16-display-fix
    need elogind dbus
    use xfs
    provide xdm display-manager
}
SDDINIT
  chmod 0755 "$pkgdir/etc/init.d/sddm"
}
