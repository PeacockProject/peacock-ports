// prp_touch — find the real touchscreen input node (vendored from PRP's prp_gui.c picker).
#ifndef PRP_TOUCH_H
#define PRP_TOUCH_H
#include <stdbool.h>
#include <stddef.h>
// Pick the best /dev/input/eventN touchscreen into out_path; false if none found.
bool pick_touch_event(char *out_path, size_t out_sz);
#endif
