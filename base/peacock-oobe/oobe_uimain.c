// peacock-oobe framebuffer UI entry (LVGL + fbdev + evdev), mirrors PRP's prp_gui.c boot: init
// fbdev, optional DPI upscale, register display + touch, run the OOBE wizard loop. Reached when
// peacock-oobe is invoked WITHOUT --apply (peacock-init runs it on first boot). The wizard forks
// `peacock-oobe --apply` for the actual work and exit(0)s on Continue.
#define _POSIX_C_SOURCE 200809L
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <linux/input.h>

#define LV_CONF_INCLUDE_SIMPLE 1
#include "lvgl/lvgl.h"
#include "lv_drivers/indev/evdev.h"

#include "prp_fbdev.h"
#include "prp_theme.h"
#include "prp_touch.h"
#include "oobe_wizard.h"

static volatile sig_atomic_t g_stop = 0;
static void on_sig(int s) { (void)s; g_stop = 1; }

// Touch coords are panel-pixel; when we render at a logical (downscaled) resolution, map them back.
static int g_touch_div = 1;
extern int evdev_root_x;
extern int evdev_root_y;
static void evdev_read_scaled(lv_indev_drv_t *drv, lv_indev_data_t *data) {
    evdev_read(drv, data);
    int raw_x = evdev_root_x, raw_y = evdev_root_y;
    if(g_touch_div > 1) {
        data->point.x = (lv_coord_t)(evdev_root_x / g_touch_div);
        data->point.y = (lv_coord_t)(evdev_root_y / g_touch_div);
    }
    // DEBUG: log on ANY change (state or raw coords) — shows whether event2 emits touch events at
    // all in the base (vs PRP). If nothing logs while tapping, the device isn't producing events.
    static int dbg_n = 0, pstate = -1, px = -999999, py = -999999;
    if(dbg_n < 40 && ((int)data->state != pstate || raw_x != px || raw_y != py)) {
        FILE *f = fopen("/peacock/etc/oobe/touch-debug.log", "a");
        if(f) { fprintf(f, "ev%d state=%d raw=(%d,%d) point=(%d,%d) div=%d\n",
                        dbg_n, (int)data->state, raw_x, raw_y, (int)data->point.x, (int)data->point.y, g_touch_div);
                fflush(f); fsync(fileno(f)); fclose(f); }
        pstate = (int)data->state; px = raw_x; py = raw_y; dbg_n++;
    }
}

// Read one trimmed line from a file into a static buffer; NULL if absent/empty.
static char *read_trim(const char *path) {
    FILE *f = fopen(path, "r");
    if(!f) return NULL;
    static char buf[256];
    if(!fgets(buf, sizeof buf, f)) { fclose(f); return NULL; }
    fclose(f);
    size_t n = strlen(buf);
    while(n && (buf[n-1] == '\n' || buf[n-1] == '\r' || buf[n-1] == ' ' || buf[n-1] == '\t')) buf[--n] = '\0';
    return buf[0] ? buf : NULL;
}

int oobe_run_ui(const char *root, int scale, const char *fbdev) {
    signal(SIGINT, on_sig);
    signal(SIGTERM, on_sig);
    // DEBUG: bring up USB RNDIS + ssh on the live system (if the helper is present) so we can
    // diagnose without rebooting to PRP. Backgrounded; harmless if absent.
    if(access("/sbin/peacock-netdbg", X_OK) == 0) system("/sbin/peacock-netdbg &");
    if(!fbdev || !*fbdev) fbdev = "/dev/fb0";

    // Active flavor (for the title + the blueprint dir): the active-flavor file, else basename(root).
    static char flavor[64] = "";
    char *af = read_trim("/peacock/etc/active-flavor");
    if(af) snprintf(flavor, sizeof flavor, "%s", af);
    else if(root) { const char *b = strrchr(root, '/'); snprintf(flavor, sizeof flavor, "%s", b ? b + 1 : root); }

    // Blueprint source: <genmirror blueprints base>/<flavor>, from /peacock/etc/blueprints-base.
    static char bp_base[512] = "";
    char *gb = read_trim("/peacock/etc/blueprints-base");
    if(gb && flavor[0]) snprintf(bp_base, sizeof bp_base, "%s/%s", gb, flavor);

    lv_init();
    prp_fbdev_t fb;
    if(!prp_fbdev_init(&fb, fbdev)) { fprintf(stderr, "peacock-oobe: fbdev init failed (%s)\n", fbdev); return 1; }
    prp_fbdev_clear(&fb, 0x0000);

    int sw = fb.width, sh = fb.height;
    // DPI upscale: explicit --scale wins; otherwise auto from panel width (peacock-init passes no
    // scale, and a high-DPI phone panel renders an unreadable, barely-tappable UI at 1x). Mirrors
    // PRP's logical-render + fbdev upscale. daisy (1080 wide) -> 2x logical 540-wide.
    int factor = (scale > 0) ? scale / 100 : (fb.width >= 1600 ? 3 : fb.width >= 880 ? 2 : 1);
    if(factor < 1) factor = 1;
    if(factor > 1) {
        sw = (int)fb.width / factor;
        sh = (int)fb.height / factor;
        prp_fbdev_set_scale(factor);
        g_touch_div = factor;
        fprintf(stderr, "peacock-oobe: DPI %dx -> logical %dx%d (panel %ux%u)\n",
                factor, sw, sh, fb.width, fb.height);
    }

    static lv_disp_draw_buf_t draw_buf;
    const uint32_t buf_lines = 64;
    size_t buf_px = (size_t)sw * (size_t)buf_lines;
    lv_color_t *b1 = malloc(buf_px * sizeof(lv_color_t));
    lv_color_t *b2 = malloc(buf_px * sizeof(lv_color_t));
    if(!b1 || !b2) { fprintf(stderr, "peacock-oobe: OOM\n"); return 1; }
    lv_disp_draw_buf_init(&draw_buf, b1, b2, (uint32_t)buf_px);

    lv_disp_drv_t disp_drv;
    lv_disp_drv_init(&disp_drv);
    disp_drv.draw_buf = &draw_buf;
    disp_drv.flush_cb = prp_fbdev_flush;
    disp_drv.hor_res = (lv_coord_t)sw;
    disp_drv.ver_res = (lv_coord_t)sh;
    lv_disp_t *disp = lv_disp_drv_register(&disp_drv);
    lv_disp_set_bg_color(disp, lv_color_hex(PK_BG));
    lv_disp_set_bg_opa(disp, LV_OPA_COVER);

    // Pick the ACTUAL touchscreen (scored by ABS/MT/BTN_TOUCH/DIRECT/name), not the first event
    // node — grabbing gpio-keys is why "Get started" couldn't be tapped. Input nodes can appear a
    // touch after fbdev, so retry briefly.
    evdev_init();
    bool ok = false;
    char ev[64] = {0};
    for(int tries = 0; tries < 30 && !ok; tries++) {
        if(pick_touch_event(ev, sizeof ev)) ok = evdev_set_file(ev);
        if(!ok) usleep(200000);
    }
    if(ok) {
        // MUST be static: LVGL v8's lv_indev_drv_register stores a POINTER to this driver, not a
        // copy. A block/stack local would dangle the moment we leave this scope, and LVGL would
        // never call read_cb — which is exactly why touch was dead while rendering worked.
        static lv_indev_drv_t indev;
        lv_indev_drv_init(&indev);
        indev.type = LV_INDEV_TYPE_POINTER;
        indev.read_cb = evdev_read_scaled;
        lv_indev_drv_register(&indev);
        fprintf(stderr, "peacock-oobe: touch input %s\n", ev);
    } else {
        fprintf(stderr, "peacock-oobe: no touch input\n");
    }

    // DEBUG: snapshot the input topology + the pick so we can diagnose touch after a boot.
    FILE *d = fopen("/peacock/etc/oobe/touch-debug.log", "w");
    if(d) {
        fprintf(d, "panel %ux%u factor %d logical %dx%d touch_div %d\npicked: %s\n",
                fb.width, fb.height, factor, sw, sh, g_touch_div, ok ? ev : "NONE");
        for(int i = 0; i < 16; i++) {
            char p[64]; snprintf(p, sizeof p, "/dev/input/event%d", i);
            int fd = open(p, O_RDONLY | O_NONBLOCK);
            if(fd < 0) continue;
            char nm[128] = "";
            unsigned long evb = 0, absb[2] = {0}, prop = 0;
            ioctl(fd, EVIOCGNAME(sizeof nm), nm);
            ioctl(fd, EVIOCGBIT(0, sizeof evb), &evb);
            ioctl(fd, EVIOCGBIT(EV_ABS, sizeof absb), absb);
#ifdef EVIOCGPROP
            ioctl(fd, EVIOCGPROP(sizeof prop), &prop);
#endif
            close(fd);
            fprintf(d, "  event%d ev=%lx abs=%lx prop=%lx name=%s\n", i, evb, absb[0], prop, nm);
        }
        fflush(d); fsync(fileno(d)); fclose(d); sync(); // survive an unclean reboot
    }

    oobe_cfg_t cfg = {0};
    cfg.screen_w = sw;
    cfg.screen_h = sh;
    cfg.scale_pct = 100;
    cfg.flavor = flavor[0] ? flavor : NULL;
    cfg.root = root ? root : "/";
    cfg.blueprint_base_url = bp_base[0] ? bp_base : NULL;
    cfg.blueprint_pubkey = "/etc/feather/genmirror.pub";
    cfg.blueprint_local = NULL;
    prp_oobe_show(&cfg);

    while(!g_stop) {
        lv_tick_inc(5);
        lv_timer_handler();
        usleep(5000);
    }
    return 0;
}
