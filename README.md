# peacock-ports

Source manifests for the Peacock meta-distro. Each port lives at
`base/<name>/package.toml` (cross-flavor / cross-device base layer) or
`device/<name>/package.toml` (per-device kernels, firmware, fixups). The
Peacock CLI and, in Phase 4+, the feather package manager consume these
manifests to build signed binary packages for each (port, flavor, arch) triple.

## Schema

See [`SCHEMA.md`](./SCHEMA.md) for the full `package.toml` schema, including the
Phase 1 additions (`flavor`, `runtime`, `[install]`, `[provides]`, `[conflicts]`)
and worked examples.

## Install layouts

Every port declares an install layout in `[install].layout`. Four values are
defined:

- **`system`** — base distro at `/usr`. All 51 existing ports use this after
  the Phase 1 migration.
- **`peacock`** — Peacock OS platform layer at `/peacock` (shell, daemons,
  theme, vendor blobs).
- **`app`** — third-party app at `/apps/<name>` with its own `bin/`, `lib/`,
  `share/`.
- **`compat`** — alternate-runtime rootfs slice at `/compat/<runtime>` (e.g.
  `/compat/glibc`, `/compat/debian`, `/compat/atl`).

## Flavors

The `flavors/` directory holds per-flavor `build_deps` alias tables, one
subdirectory per base distro: `flavors/arch/`, `flavors/debian/`,
`flavors/alpine/`. Each contains an `aliases.toml` mapping a port's `build_deps`
entry (canonical Arch name) to the right package name in that flavor.

- `flavors/arch/aliases.toml` is the canonical identity map.
- `flavors/debian/aliases.toml` and `flavors/alpine/aliases.toml` start empty and
  are populated as Debian- and Alpine-flavor ports land.

## Tools

`tools/phase1-migrate.py` ran the one-shot mechanical pass adding `[install]`
to every existing manifest; it is idempotent and safe to re-run.
`tools/phase1-verify.py` parses every manifest with stdlib `tomllib` and
asserts a valid `[install].layout`. Useful as a CI check.
