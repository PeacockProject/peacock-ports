// prp_touch.c — touchscreen device picker, vendored verbatim from PRP/gui/prp_gui.c so the OOBE
// grabs the actual touch panel (scored by ABS/MT/BTN_TOUCH/INPUT_PROP_DIRECT/name) instead of the
// first event node (which is usually gpio-keys, hence "can't tap").
#define _POSIX_C_SOURCE 200809L
#include "prp_touch.h"
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/ioctl.h>
#include <linux/input.h>

static int strcasestr_like(const char *hay, const char *needle) {
    if(!hay || !needle || !*needle) return 0;
    size_t nl = strlen(needle);
    for(const char *p = hay; *p; p++) {
        if(strncasecmp(p, needle, nl) == 0) return 1;
    }
    return 0;
}

static int bit_is_set(const unsigned long *bits, int bit) {
    return (bits[bit / (int)(8 * sizeof(unsigned long))] >> (bit % (int)(8 * sizeof(unsigned long)))) & 1UL;
}

static int score_touch_name(const char *name) {
    int score = 0;
    if(!name || !*name) return score;

    if(strcasestr_like(name, "touch") || strcasestr_like(name, "goodix") || strcasestr_like(name, "synaptics") ||
       strcasestr_like(name, "atmel") || strcasestr_like(name, "mxt") || strcasestr_like(name, "fts") ||
       strcasestr_like(name, "ft5") || strcasestr_like(name, "ft6")) {
        score += 6;
    }
    if(strcasestr_like(name, "gpio-keys") || strcasestr_like(name, "key") || strcasestr_like(name, "power")) {
        score -= 8;
    }
    return score;
}

bool pick_touch_event(char *out_path, size_t out_sz) {
    char best_path[64] = {0};
    int best_score = -9999;

    for(int i = 0; i < 32; i++) {
        char dev_path[64];
        struct stat st;
        snprintf(dev_path, sizeof(dev_path), "/dev/input/event%d", i);
        if(stat(dev_path, &st) != 0) continue;

        int fd = open(dev_path, O_RDONLY | O_NONBLOCK);
        if(fd < 0) continue;

        unsigned long ev_bits[(EV_MAX + 8 * sizeof(unsigned long)) / (8 * sizeof(unsigned long))];
        unsigned long abs_bits[(ABS_MAX + 8 * sizeof(unsigned long)) / (8 * sizeof(unsigned long))];
        unsigned long key_bits[(KEY_MAX + 8 * sizeof(unsigned long)) / (8 * sizeof(unsigned long))];
#ifdef INPUT_PROP_MAX
        unsigned long prop_bits[(INPUT_PROP_MAX + 8 * sizeof(unsigned long)) / (8 * sizeof(unsigned long))];
#endif
        memset(ev_bits, 0, sizeof(ev_bits));
        memset(abs_bits, 0, sizeof(abs_bits));
        memset(key_bits, 0, sizeof(key_bits));
#ifdef INPUT_PROP_MAX
        memset(prop_bits, 0, sizeof(prop_bits));
#endif

        if(ioctl(fd, EVIOCGBIT(0, sizeof(ev_bits)), ev_bits) < 0 || !bit_is_set(ev_bits, EV_ABS)) {
            close(fd);
            continue;
        }
        if(ioctl(fd, EVIOCGBIT(EV_ABS, sizeof(abs_bits)), abs_bits) < 0) {
            close(fd);
            continue;
        }

        bool has_abs_xy = bit_is_set(abs_bits, ABS_X) && bit_is_set(abs_bits, ABS_Y);
        bool has_mt_xy = bit_is_set(abs_bits, ABS_MT_POSITION_X) && bit_is_set(abs_bits, ABS_MT_POSITION_Y);
        if(!has_abs_xy && !has_mt_xy) {
            close(fd);
            continue;
        }

        bool has_btn_touch = false;
        if(bit_is_set(ev_bits, EV_KEY) && ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(key_bits)), key_bits) >= 0) {
            has_btn_touch = bit_is_set(key_bits, BTN_TOUCH);
        }

        bool direct = false;
#ifdef INPUT_PROP_DIRECT
        if(ioctl(fd, EVIOCGPROP(sizeof(prop_bits)), prop_bits) >= 0) {
            direct = bit_is_set(prop_bits, INPUT_PROP_DIRECT);
        }
#endif

        char name[256] = {0};
        if(ioctl(fd, EVIOCGNAME(sizeof(name)), name) < 0) {
            name[0] = '\0';
        }
        close(fd);

        int name_score = score_touch_name(name);
        if(!direct && !has_btn_touch && !has_mt_xy && name_score <= 0) {
            continue;
        }

        int score = 0;
        if(direct) score += 8;
        if(has_btn_touch) score += 4;
        if(has_mt_xy) score += 3;
        if(has_abs_xy) score += 2;
        score += name_score;

        fprintf(stderr,
                "prp-gui: touch cand %s name='%s' abs_xy=%d mt_xy=%d btn_touch=%d direct=%d score=%d\n",
                dev_path, name[0] ? name : "unknown", has_abs_xy ? 1 : 0, has_mt_xy ? 1 : 0, has_btn_touch ? 1 : 0,
                direct ? 1 : 0, score);

        if(score > best_score) {
            best_score = score;
            snprintf(best_path, sizeof(best_path), "%s", dev_path);
        }
    }

    if(best_path[0] && best_score > -9999) {
        snprintf(out_path, out_sz, "%s", best_path);
        fprintf(stderr, "prp-gui: touch selected %s (score=%d)\n", out_path, best_score);
        return true;
    }

    return false;
}
