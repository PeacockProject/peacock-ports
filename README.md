# peacock-ports

Source manifests for the Peacock meta-distro. Every base package, every
device port (kernel + bootloader + display fix-ups), and every `/compat/`
runtime shim lives here as a `package.toml` under `base/`, `device/`, or
`compat/`. The Peacock CLI builds these into binary packages today; the
feather package manager (`ftr`) will consume the same manifests from a
signed binary repo in Phase 6.

This repo is **just manifests** — no Go, no C. The build logic lives in
`PeacockProject/Peacock`; the on-device install logic lives in
`PeacockProject/feather`. Changing schema here without touching those is
fine as long as it stays back-compat.

## How it fits in

```
  peacock-ports/   ◄── you are here
    │
    ├── base/<name>/package.toml      legacy + cross-device system ports
    ├── device/<name>/package.toml    per-device kernels, firmware, fixups
    ├── device/<name>/device.toml     boot params (Android header offsets)
    ├── compat/<runtime>/package.toml /compat/<runtime>/ rootfs shims
    └── flavors/<flavor>/aliases.toml per-flavor build_deps name translation
        │
        ▼
   Peacock (the CLI) reads manifests, builds them in a chroot, produces
   either a stage dir (rootfs install) or a signed .feather archive
   (Phase 6, repo distribution).
```

Sibling repos:

- **[Peacock](../Peacock/)** — Go CLI that builds these ports into a bootable
  device image.
- **[feather](../feather/)** — `ftr`, the on-device package manager that will
  install these manifests' outputs at runtime.
- **[peacock-mkinitfs](../peacock-mkinitfs/)** — initramfs builder. Built as
  the `base/peacock-mkinitfs` port from this tree.

## Quick start

This repo on its own does nothing — you build it with the Peacock CLI:

```sh
# Lint every manifest with stdlib tomllib + check [install].layout is valid.
python3 tools/phase1-verify.py

# Build one port via the Peacock CLI (run from Peacock/, which symlinks
# peacock-ports/ next to its own source).
cd ../Peacock
./peacock build-packages --device oppo-a16 -p linux-oppo-a16
```

There's no host prereq beyond Python 3.11+ for the verifier. The real
prereqs are on the Peacock CLI side (see `Peacock/README.md`).

A `peacock doctor` subcommand to sweep prereqs is in flight.

## Project layout

```
peacock-ports/
├── base/                       cross-device packages installed at /usr
│   ├── bash/package.toml         GNU bash (the canonical layout=system example)
│   ├── busybox/                  busybox-static for initramfs
│   ├── peacock-mkinitfs/         the initramfs builder, as a port
│   ├── peacock-splash/           boot splash
│   ├── peacock-sddm-theme-…/     SDDM theme for phone form-factor
│   ├── openrc/, sddm/, dbus-…/   init + login stack
│   ├── util-linux/, lvm2/        initramfs-time userland
│   └── …                         (~28 ports today)
│
├── device/                     per-device kernels, bootloaders, fix-ups
│   ├── oppo-a16/                 device.toml + meta package (MTK MT6765)
│   ├── linux-oppo-a16/           prebuilt kernel for OPPO A16
│   ├── minkernel-oppo-a16/       mk chainloader boot.img
│   ├── oppo-a16-display-fix/     OpenRC + Xorg quirks for MTKFB
│   ├── xiaomi-daisy/             device.toml + meta package (qcom msm8953)
│   ├── linux-xiaomi-daisy/       mainline kernel for daisy
│   ├── lk2nd-xiaomi-daisy/       lk2nd secondary bootloader image
│   ├── samsung-jflte/, …         additional MTK/qcom devices
│   └── …
│
├── compat/                     /compat/<runtime>/ rootfs shims (Phase 7)
│   └── glibc/                    glibc 2.40 shim for musl-base flavors
│
├── flavors/                    per-flavor build_deps alias tables
│   ├── arch/aliases.toml         canonical identity map (Arch package names)
│   ├── debian/aliases.toml       arch → debian package name translation
│   └── alpine/aliases.toml       arch → alpine package name translation
│
├── tools/                      one-shot migration + CI verification scripts
│   ├── phase1-migrate.py         idempotent pass adding [install] to ports
│   └── phase1-verify.py          parse + validate every manifest
│
├── SCHEMA.md                   canonical package.toml schema reference
└── README.md                   you are here
```

## Schema

Full reference: [`SCHEMA.md`](./SCHEMA.md). At the top level a manifest
declares an install layout in `[install].layout`:

| Layout | Lands at | Owner |
|---|---|---|
| `system` | `/usr` | base distro (pacman / apt / apk) |
| `peacock` | `/peacock` | feather — Peacock platform layer |
| `app` | `/apps/<name>` | feather — per-app overlay |
| `compat` | `/compat/<runtime>` | feather — alternate-runtime rootfs |

All 51 ports landed before Phase 7 use `layout = "system"`. `compat/glibc`
is the first port to use `layout = "compat"`. No `layout = "peacock"` or
`layout = "app"` ports have landed yet — schema is reserved, real ports
arrive in Phase 4 / Phase 5 respectively. See `SCHEMA.md`'s "Worked
examples" section.

## Flavors

The `flavors/` directory maps a port's canonical `build_deps` entry (an Arch
package name today) to the right package name in each base flavor. When the
Peacock CLI runs `peacock build --flavor debian`, it translates each port's
`build_deps` through `flavors/debian/aliases.toml` before invoking
`apt-get install`.

- `flavors/arch/aliases.toml` — canonical identity map. Always present.
- `flavors/debian/aliases.toml` — populated as Debian-flavor builds land.
- `flavors/alpine/aliases.toml` — populated as Alpine-flavor builds land.

## Where to go next

- **Adding a new device** —
  [`docs/adding-a-device.md`](./docs/adding-a-device.md).
- **Manifest schema** — [`SCHEMA.md`](./SCHEMA.md). Includes worked examples
  for every `[install].layout` value.
- **Cross-repo backlog** — `Peacock/BACKLOG.md` (sibling repo).
- **CLI that consumes these manifests** —
  [`Peacock/README.md`](../Peacock/README.md).

## Tools

`tools/phase1-migrate.py` ran the one-shot mechanical pass adding `[install]`
to every existing manifest; it is idempotent and safe to re-run.
`tools/phase1-verify.py` parses every manifest with stdlib `tomllib` and
asserts a valid `[install].layout`. Useful as a CI check; the
`BACKLOG.md` "CI / automation" section calls it out as the minimum lint job
for this repo.

## License

TODO. No `LICENSE` file ships here. The Peacock CLI is unlicensed today;
feather is GPL-3.0. The manifests in this tree are configuration data with
no clear original authorship beyond the upstream source URLs they reference,
but a project-wide license decision is owed.

## Contributing

TODO. No `CONTRIBUTING.md` yet. Until one lands:

- One commit per port; subject line `<area>: <subject>` (`device:`, `base:`,
  `compat:`, `flavors:`, `schema:`, `docs:`, `tools:`).
- `python3 tools/phase1-verify.py` must pass.
- New schema keys must be optional and parsers must accept unknown keys
  (forward-compat — see `SCHEMA.md`'s "Parser expectations" section).
