# Device status & compatibility pipeline

**Status:** design locked 2026-06-24. This document is the source of truth for how
per-device support/compatibility data flows to **peacockos.org** and
**wiki.peacockos.org**. Keep it current; it exists so this plan does not get lost.

## TL;DR

- Each device gets a **`status.toml`** next to its `device.toml`
  (`peacock-ports/device/<codename>/status.toml`). It holds curated, public-facing
  **specs + a support matrix** (works / partial / broken / untested).
- `device.toml` stays **build/flash only** (partitions, offsets, quirks). We do **not**
  add status fields to it.
- A generator renders every `status.toml` into two places:
  1. **peacockos.org** `/devices` (a compatibility table + per-device spec/support block),
  2. **wiki.peacockos.org** (a compatibility widget that pages can opt into).
- Prose and device **photos are author-supplied** (on the site and the wiki). The
  pipeline only owns the **spec + support matrix**; it never overwrites human content.
- On the wiki the matrix is **opt-in and live**: an editor drops a one-line tag and the
  current matrix is fetched at view time. No tag = no matrix. Never forced.

## Why a separate file

`device.toml` is consumed by the builder for partitions, boot image offsets and quirks.
Compatibility status changes far more often than build geometry and is *editorial*
(notes, maturity). Mixing the two churns the build metadata and risks breaking builds on
a copy-edit. `status.toml` is for humans and the website; `device.toml` is for the builder.

## `status.toml` schema

Schema modelled on the postmarketOS wiki device page (infobox + Features table) so it maps
onto something battle-tested. Status values mirror pmOS: **`works` | `partial` | `broken`
| `untested`**. Any key may have a `<key>_note` sibling with a short user-facing string.

```toml
[device]
codename     = "xiaomi-daisy"
name         = "Xiaomi Mi A2 Lite"
manufacturer = "Xiaomi"
released     = 2018
type         = "handset"            # handset | tablet | laptop | vm

[hardware]
chipset      = "Qualcomm Snapdragon 625 (MSM8953)"
architecture = "aarch64"
display      = "1080x2280 IPS LCD"
storage      = "32/64 GB"
memory       = "3/4 GB"

[software]
original_android = "Android 8.1"    # version the device shipped with
max_android      = "Android 10"     # latest stock from the vendor (optional)
kernel           = "downstream 4.9" # the kernel PeacockOS runs on this device
maturity         = "testing"        # stable | testing | experimental (overall)

# Support matrix. Each value: works | partial | broken | untested.
# Groups mirror the pmOS Features table. Omit a key if it does not apply.
[support.basics]        # flashing, usb_net, battery, screen, touch
[support.multimedia]    # accel_3d, audio, camera_rear, camera_front, camera_flash
[support.connectivity]  # wifi, bluetooth, gps
[support.modem]         # calls, sms, data
[support.misc]          # usb_otg, fingerprint, fde
[support.sensors]       # accelerometer, ambient_light, proximity, gyroscope, haptics
```

See any device's `status.toml` for a fully-populated example.

## The pipeline

The generator is **`site/scripts/gen-devices.py`** (Python, stdlib only). It reads
**every** `peacock-ports/device/*/status.toml` and emits:

1. **`site/devices/status.json`** — all devices, machine-readable. Deploys with the site
   to `peacockos.org/devices/status.json`.
2. **Site `/devices`** (`site/devices/index.html`) — **brand-grouped cards**: device
   photo + name + codename + platform + an **overall status badge (maturity) only**. No
   per-feature matrix on the site — the detailed breakdown is the wiki's job. Has a live
   **search box** filtering by device name / codename / brand / platform. Each card links
   to that device's wiki page. Reuses `index.html`'s chrome (head/header/footer).
3. **Wiki `devices`** (index) — brand-grouped **links**, one per device, regenerated.
4. **Wiki `devices/<codename>`** — **one page per device**, the detailed matrix + specs
   inside a marked block (`<!-- peacock:status:start … -->` / `:end`). The generator
   creates the page (with an author stub) if missing, else replaces **only** the marked
   block — author prose and photos around it survive every regen.

### Device photos

The **source photo lives in the device package**: `peacock-ports/device/<port>/image.png`
(or `.jpg`/`.webp`). The generator/CI converts it to an optimized webp at
`site/devices/img/<codename>.webp` (resized to max 800px, quality 82, stripped). The site
card uses it; the wiki references the same `peacockos.org/devices/img/<codename>.webp`. One
source photo per device, kept with the rest of its port. No image yet → the site shows a
gradient placeholder. Conversion needs **ImageMagick or cwebp** on the runner.

### Optional: live wiki widget (not yet wired)

Instead of the baked marked block, a device page could embed `<div
data-peacock-status="<codename>">` and a theme `injectBody` script could hydrate it from
`status.json` at view time (needs Wiki.js raw-HTML enabled). The baked marked block is
what's implemented; the widget stays an option.

## What the pipeline owns vs. what authors own

| | Owned by pipeline | Owned by author |
|---|---|---|
| Site `/devices` | the whole page (cards, search) — regenerated | nothing (it's generated; edit `status.toml` + drop a photo) |
| Wiki `devices` index | the whole page — regenerated | nothing |
| Wiki `devices/<codename>` | the marked status block only | everything else: prose, **photo**, install notes, quirks |

Photos and written prose are **always** the user's. The pipeline is data-only.

## The workflow (to build)

`.github/workflows/devices.yml` — orchestrated from the **site repo** (per the chosen
single-secret setup). On change to any `status.toml`:

1. checkout `peacock-ports` (public, read-only, no auth) for the `status.toml` files,
2. run `site/scripts/gen-devices.py` → `status.json` + regenerated site `/devices`,
3. commit the site changes to itself (Vercel redeploys),
4. the generator also pushes the wiki index + per-device pages via the GraphQL API using
   the `WIKI_API_TOKEN` secret (token in `infra/peacock-community/SECRETS.api-tokens.txt`,
   **not** committed). Locally it reads the token from that file.

**Trigger across repos:** `status.toml` lives in `peacock-ports` but the workflow is in
`site`. Until a `repository_dispatch` (needs a fine-grained PAT in peacock-ports) is wired,
the site workflow also runs on `workflow_dispatch` + a daily `schedule` so edits land
within a day or on demand.

## Status legend (for the rendered matrix)

- **works** — functional and considered reliable.
- **partial** — works with caveats; see the note.
- **broken** — present but not working / not yet implemented.
- **untested** — nobody has confirmed it either way.

## Open items

- [x] Generator `site/scripts/gen-devices.py` (brand-grouped cards + search on the site,
      one wiki page per device with a marked status block, status.json).
- [ ] **Build `.github/workflows/devices.yml`** (above) — the generator runs by hand for now.
- [ ] **Drop device photos** into `site/devices/img/<codename>.webp` (daisy, jflte,
      oppo6765, qemu-x86_64). Placeholders until then.
- [ ] **Push the site** so `/devices` goes live (wiki is already live).
- [ ] Fill author prose on each `devices/<codename>` wiki page (stubs created).
- [ ] Backfill spec `TODO`s (jflte chipset/RAM, displays, kernel versions) in each
      `status.toml` — they're specs, not test claims.
- [ ] Decide the cross-repo trigger for the workflow (dispatch PAT vs schedule-only).
- [ ] Optional: the live wiki widget instead of the baked marked block.
