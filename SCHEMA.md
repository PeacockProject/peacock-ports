# peacock-ports `package.toml` schema

**Back-compat:** every existing port in this tree keeps working without changes.
All keys added by the Phase 1 meta-distro migration are optional, and a
mechanical pass has already filled in the one new key (`[install].layout`) that
the builder will eventually require — defaulted to `"system"` so today's Arch
pipeline behaves exactly as before.

This document is the canonical reference for what a `peacock-ports/<area>/<name>/package.toml`
file may contain. Parsers should accept unknown keys without erroring (forward-compat).

---

## Top-level tables

A manifest is a TOML document with the following tables. Only `[package]` and
`[build]` are present today across the 51-port baseline; `[install]`,
`[provides]`, and `[conflicts]` are introduced by this migration.

| Table | Required | Purpose |
|---|---|---|
| `[package]` | yes | Identity + metadata (name, version, description). |
| `[install]` | yes (new ports) | Where the package files land at install time. Defaults applied for legacy ports. |
| `[build]` | yes | How to fetch + build the source tree. |
| `[provides]` | no | Capability slots this port satisfies. |
| `[conflicts]` | no | Other ports this port cannot co-install with. |

---

## `[package]`

Identity and metadata.

| Key | Type | Status | Meaning |
|---|---|---|---|
| `name` | string | existing | Port name. Must be unique within `peacock-ports/`. |
| `version` | string | existing | Upstream version. Free-form, but should sort sensibly. |
| `description` | string | existing | One-line human description. |
| `provides` | array of string | existing | **Legacy** shorthand. Equivalent to declaring each entry in a top-level `[provides]` table with version `"*"`. Kept for back-compat (`base/bash` uses `provides = ["sh"]`). New ports should prefer the table form. |
| `depends` | array of string | existing | Runtime dependencies on other ports. Resolved by the Peacock CLI / feather at install time. |
| `flavor` | array of string | **new (optional)** | Base-distro flavors this port supports. Valid values: `"arch"`, `"debian"`, `"alpine"`. Absent ⇒ all flavors. |
| `runtime` | string | **new (optional)** | Where the package _runs_ at runtime: `"peacock"`, `"compat-glibc"`, `"compat-debian"`, `"compat-android-atl"`. Absent ⇒ runs against the base distro. This is independent of `[build]`, which describes where it is _built_. |

### `flavor` examples

```toml
flavor = ["arch", "debian"]   # builds on Arch and Debian, not Alpine
# flavor key absent             # builds on every flavor (default)
```

### `runtime` examples

```toml
runtime = "peacock"             # native peacock-platform package, no libc shim
runtime = "compat-glibc"        # links against glibc; on musl flavors, launched under /compat/glibc
runtime = "compat-debian"       # full debian rootfs userspace under /compat/debian
runtime = "compat-android-atl"  # binary runs through the Android Translation Layer
```

---

## `[install]` — NEW

Describes where the staged tree lands on the installed system. The builder
already produces a `stage/` directory; `[install]` is how feather knows _which
overlay namespace_ that stage tree belongs to.

| Key | Type | Required | Meaning |
|---|---|---|---|
| `layout` | string | yes (for new ports; legacy ports defaulted to `"system"` by the Phase 1 pass) | One of `"system"`, `"peacock"`, `"app"`, `"compat"`. |
| `prefix` | string | no | Install root. Default depends on `layout` (see below). |
| `files` | array of string | no | Explicit list of installed paths, relative to `prefix`. If absent, the full stage tree is installed. |

### `layout` values

| `layout` | Default `prefix` | Owner | Notes |
|---|---|---|---|
| `"system"` | `/usr` | base distro (pacman / apt / apk) | The classic path. All 51 existing ports use this after the migration. Builder still produces `stage/usr/...` exactly as today. |
| `"peacock"` | `/peacock` | feather | Peacock OS platform layer: shell, daemons, theme, vendor blobs. Same across flavors. |
| `"app"` | `/apps/<name>` | feather | Per-app overlay prefix. `<name>` is `[package].name`. App carries its own `bin/`, `lib/`, `share/`, `manifest.toml`. |
| `"compat"` | `/compat/<runtime>` | feather | Compat-runtime rootfs contents (glibc, debian, atl, ...). `<runtime>` is the value of `[package].runtime` minus the `compat-` prefix. |

### Worked examples

**`layout = "system"`** — every existing port after the Phase 1 migration:

```toml
[package]
name = "bash"
version = "5.3.9.1"
description = "The GNU Bourne Again shell (Arch version)"
provides = ["sh"]

[install]
layout = "system"
# prefix defaults to "/usr"

[build]
# ... unchanged
```

**`layout = "peacock"`** — Peacock OS shell:

```toml
[package]
name = "peacock-shell"
version = "0.1.0"
description = "Peacock OS mobile shell"
runtime = "peacock"

[install]
layout = "peacock"
# prefix defaults to "/peacock"
files = [
  "bin/peacock-shell",
  "lib/libpeacock-shell.so",
  "share/peacock-shell/",
]
```

**`layout = "app"`** — a third-party app:

```toml
[package]
name = "com.example.notes"
version = "1.2.3"
description = "Notes app for Peacock"
runtime = "compat-glibc"

[install]
layout = "app"
# prefix defaults to "/apps/com.example.notes"
# files defaults to full stage tree
```

**`layout = "compat"`** — a glibc rootfs slice shipped for musl-base flavors:

```toml
[package]
name = "compat-glibc-runtime"
version = "2.39"
description = "glibc rootfs for /compat/glibc"
flavor = ["alpine"]
runtime = "compat-glibc"

[install]
layout = "compat"
# prefix defaults to "/compat/glibc"
```

---

## `[build]`

How to obtain and build the sources. All keys here are existing; no new keys in
this migration.

| Key | Type | Status | Meaning |
|---|---|---|---|
| `source` | string | existing | Upstream tarball / git URL. |
| `checksum` | string | existing | Expected checksum of the source (may be empty during dev). |
| `build_deps` | array of string | existing | Build-time package names, resolved against the **base flavor**'s alias table at `flavors/<flavor>/aliases.toml`. |
| `build_dep_packages` | array of string | existing | Additional flavor-resolved build-time packages. Kept distinct from `build_deps` for historical reasons; treat both as build-deps. |
| `dependencies` | array of string | existing | Runtime dependencies in the **base distro** namespace (Arch package names today). Used by the legacy installer path. |
| `dependencies_openrc` | array of string | existing | Runtime dependencies that only apply when the target init system is OpenRC. |
| `dependencies_systemd` | array of string | existing | Runtime dependencies that only apply when the target init system is systemd. |
| `script` | string (multi-line) | existing | Shell script executed inside the build chroot. Expected to populate `stage/` with the install tree. |
| `use_qemu` | bool or `"auto"` | existing | Whether the build needs QEMU user emulation (for cross-builds). |
| `cross_compile` | string | existing | Cross-compile triplet prefix, e.g. `"aarch64-linux-gnu-"`. Empty = host build. |

---

## `[provides]` — NEW

Capability slots this port satisfies, as a table of `name = "version"` pairs.
Use this for declaring virtual capabilities other ports can depend on (e.g.
`peacock-shell = "0.1"` so apps can require any peacock-shell ≥ 0.1).

```toml
[provides]
peacock-shell = "0.1"
qt-platform-wayland = "6"
```

The legacy `[package].provides = ["sh"]` array form is equivalent to
`[provides]\n sh = "*"` and is kept working.

---

## `[conflicts]` — NEW

Ports that cannot be installed alongside this one. Same shape as `[provides]`:
`name = "constraint"`. A constraint of `"*"` means any version.

```toml
[conflicts]
peacock-shell-legacy = "*"
sddm-theme-other = ">=2.0"
```

---

## Parser expectations

- TOML parser: Python `tomllib` (3.11+) on the CLI side. All 51 baseline
  manifests parse cleanly both before and after the Phase 1 migration; see
  `tools/phase1-verify.py`.
- Unknown keys in any table must not cause a hard error — Phase 2+ may
  introduce additional optional keys.
- Order of tables in the file is not significant. The Phase 1 migration
  inserts `[install]` immediately after `[package]` as a convention, but
  parsers must not rely on it.
