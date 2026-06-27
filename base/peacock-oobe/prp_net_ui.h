#ifndef PRP_NET_UI_H
#define PRP_NET_UI_H

// Standalone Wi-Fi connect overlay, vendored from PRP for the first-boot OOBE's
// connectivity gate. On device it drives the base's `peacock-net` (wpa_supplicant
// + udhcpc) by forking it and polling its result files, so the GUI stays
// responsive. When peacock-net isn't present (the SDL sim) it falls back to the
// mock SSID list so the flow is still exercisable.

// Show the full-screen Wi-Fi overlay. mock_ssids is a "\n"-separated list used
// only when peacock-net is unavailable (may be NULL).
void prp_net_ui_show(int screen_w, int screen_h, int scale_pct, const char *mock_ssids);

// True if a Wi-Fi connection has been established this session (best-effort;
// set when peacock-net reports "ok", or on a mock connect in the sim).
int prp_net_ui_connected(void);

// Latest human-readable status line (e.g. "Connected · 192.168.1.5" or
// "Not connected"). Valid until the next call into this module.
const char *prp_net_ui_status(void);

#endif // PRP_NET_UI_H
