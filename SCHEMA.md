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
| `type` | string | current | Build-phase set sourced from `lib/build/<type>.sh`: `autotools` \| `make` \| `kernel` \| `bootloader` \| `raw` (default). Drives prepare→build→check→package; a sibling `build.sh` overrides any phase. The canonical replacement for `script`. |
| `script` | string (multi-line) | **deprecated** | Legacy inline build script that populated `stage/`. Removed from every port; retained only in the parser for back-compat. New ports MUST use `type` + `build.sh` — CI rejects new inline `script`. |
| `use_qemu` | bool or `"auto"` | existing | Whether the build needs QEMU user emulation (for cross-builds). |
| `cross_compile` | string | existing | Cross-compile triplet prefix, e.g. `"aarch64-linux-gnu-"`. Empty = host build. |

### Build model: `type` + `build.sh` (replaces inline `script`)

Build logic lives in a `build.sh` next to `package.toml`, not in TOML. The
harness sources `lib/build/default.sh`, then `lib/build/<type>.sh`, then the
port's `build.sh`, and runs `prepare → build → check → package`. Contract:

- `prepare()` extracts the first source tarball (`--strip-components=1`) and applies `$patches`.
- `build()` compiles; `package()` populates `$pkgdir` (the install tree — the old `stage/`).
- Env: `$srcdir $builddir $pkgdir $jobs`, plus `ARCH`/`CROSS_COMPILE` when cross. Helpers: `peacock_msg`, `peacock_die`, `peacock_extract`.
- Each type exposes overridable `default_*` steps (`default_configure` / `default_compile` / `default_install`, …) so a port overrides one step and reuses the rest — e.g. `package() { default_install; ln -sf foo "$pkgdir/usr/bin/bar"; }`.
- A kernel port that sets `prp_kernel_config` additionally stages a PRP-trimmed kernel into `stage-prp/`, which the harness packages as the `<name>-prp` subpackage.

A vanilla port needs only `type = "autotools"` (no `build.sh`). See `lib/build/*.sh`
and `base/bash`, `base/bc`, `device/minkernel-oppo-a16` for examples.

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

---

## Repository tree conventions

The `peacock-ports/` tree is organised by where a port lives at install time,
not by language or upstream provenance:

| Top-level dir | Purpose | Typical `[install].layout` |
|---|---|---|
| `base/` | Base-distro packages that land at `/usr` via the legacy installer path. | `system` |
| `device/` | Device-specific ports (bootloaders, vendor fixups, kernel forks). | `system` (mostly) |
| `compat/` | **New.** Per-runtime compat shim trees that land under `/compat/<runtime>/`. Sibling of `base/` and `device/`. | `compat` |

### `compat/<runtime>/` convention

- Each immediate subdirectory of `compat/` is named after the runtime it
  vendors — for example `compat/glibc/`, and (planned) `compat/debian/`,
  `compat/atl/`, `compat/peacock-v1/`.
- Ports under `compat/` **must** set both:
  - `[install].layout = "compat"`
  - `[package].runtime = "<name>"` matching the directory name.
- `[install].prefix` defaults to `/compat/<runtime>` and should be set
  explicitly for clarity (see the first example below).
- `[package].flavor` lists the base flavors this shim is needed on. A glibc
  shim, for instance, only makes sense for musl-base flavors (`alpine`); on
  glibc-native flavors (`arch`, `debian`) the shim is a redundant no-op.

### First example

`compat/glibc/package.toml` is the canonical reference for compat-layout
ports. It ships the glibc 2.40 runtime tree so that musl-base flavors
(Alpine, postmarketOS-musl-Arch) can run glibc-only binaries (Steam, Discord,
proprietary IDEs) via `/compat/glibc/`.

See also the `[notes]` table in that manifest for the cross-compile caveats —
this is a build skeleton; Phase 8+ will add a binary-cache prebuilt path so
on-device musl hosts do not have to cross-compile glibc.

---

## Worked examples

The short `[install]`-table snippets earlier in this document show the
syntax in isolation. The three subsections below point at full real (or, for
`layout = "app"`, hypothetical) `package.toml` files so the `[install]` +
`[package]` + `[build]` triple is visible together.

### Worked example: `layout = "system"`

The 51-port baseline all uses `layout = "system"` after the Phase 1
mechanical pass. The canonical short example is
[`base/bash/package.toml`](./base/bash/package.toml):

```toml
[package]
name = "bash"
version = "5.3.9.1"
description = "The GNU Bourne Again shell (Arch version)"
provides = ["sh"]

# Phase 1 schema migration — defaults to layout = "system"; revisit per-port later.
[install]
layout = "system"

[build]
source = "https://ftp.gnu.org/gnu/bash/bash-5.3.tar.gz"
checksum = ""
build_deps = ["gcc", "make", "bison", "ncurses", "awk", "grep", "sed"]
script = """
tarball="$(ls -1 bash-*.tar.gz 2>/dev/null | head -n1)"
if [ -n "$tarball" ]; then
  tar -xzf "$tarball" --strip-components=1
fi
./configure --prefix=/usr
make -j4
make install DESTDIR="$(pwd)/stage"
ln -sf bash stage/usr/bin/sh
cp -a stage/usr ./
"""
```

Things to notice:

- `[install].prefix` is omitted; it defaults to `/usr` for
  `layout = "system"`.
- The build script stages everything under `stage/usr/...`, matching the
  default prefix.
- The legacy `[package].provides = ["sh"]` array shorthand is preserved —
  equivalent to a top-level `[provides]\n sh = "*"`.

### Worked example: `layout = "app"`

> **No `app/` ports have landed in the ports tree yet.** This subsection is
> a hypothetical manifest showing the canonical shape Phase 5 apps will
> use. See the Phase 5 entry in `Peacock/BACKLOG.md` for the open work
> blocking the first real app port.

A speculative `app/com.example.notes/package.toml`:

```toml
[package]
name = "com.example.notes"
version = "1.2.3"
description = "Notes app for Peacock OS"
runtime = "compat-glibc"            # links against glibc; uses /compat/glibc
                                    # on musl-base flavors transparently

[install]
layout = "app"
# prefix defaults to "/apps/com.example.notes"
# files defaults to the full stage tree; explicit list only if you want
# to ship a subset of what the build produced
files = [
  "bin/notes",
  "lib/libnotes-core.so",
  "share/com.example.notes/",
  "manifest.toml",                  # the runtime launcher manifest, separate
                                    # from this build-time package.toml
]

[build]
source = "https://example.com/notes-1.2.3.tar.gz"
checksum = ""
build_deps = ["base-devel", "qt6-base"]
script = """
tar -xzf notes-*.tar.gz --strip-components=1
cmake -S . -B build -DCMAKE_INSTALL_PREFIX=/apps/com.example.notes
cmake --build build -j"$(nproc)"
cmake --install build --prefix /apps/com.example.notes \
      --destdir "$(pwd)/stage"
"""

[provides]
com.example.notes = "1.2"

[conflicts]
com.example.notes-legacy = "*"
```

Things to notice:

- The package name uses reverse-DNS — convention for `layout = "app"` so
  `/apps/<name>/` is globally unique.
- `[install].prefix` defaults to `/apps/<name>` where `<name>` is
  `[package].name`. The cmake invocation above bakes that prefix into the
  install layout via `DESTDIR + --prefix`.
- `runtime = "compat-glibc"` lets the app declare its libc requirement
  once; `ftr` handles namespace pivoting at launch time on musl flavors
  (this part of `ftr` does not exist yet — Phase 5 work).
- Per-app state goes to `/data/com.example.notes/`, not anywhere under
  `/apps/`. The manifest schema does not currently describe `/data/`
  policy; that schema lands with Phase 5 too.

### Worked example: `layout = "compat"`

The canonical reference is [`compat/glibc/package.toml`](./compat/glibc/package.toml).
A trimmed version showing the load-bearing pieces:

```toml
[package]
name = "compat-glibc"
version = "2.40"
description = "glibc 2.40 runtime tree for /compat/glibc/, used by musl-base flavors..."
flavor = ["alpine"]                 # only musl-base flavors need this shim
runtime = "glibc"

# Phase 7 schema migration — first compat-layout port.
[install]
layout = "compat"
prefix = "/compat/glibc"

[build]
source = "https://ftp.gnu.org/gnu/glibc/glibc-2.40.tar.gz"
checksum = ""
build_deps = ["base-devel", "bison", "gawk", "python"]
script = """
# ... configures --prefix=/compat/glibc, builds, installs to stage/.
"""

[provides]
glibc = "2.40"

[notes]
status = "skeleton"
caveats = [
  "This is a build skeleton. Actual cross-compile for Alpine targets...",
  # ...
]
```

Things to notice:

- `prefix` is set explicitly to `/compat/glibc` even though the default
  `/compat/<runtime>` would resolve to the same string — the convention is
  to be explicit for `layout = "compat"` so the install path is greppable.
- `[package].runtime = "glibc"` matches the directory name `compat/glibc/`
  per the "Repository tree conventions" section above.
- `[package].flavor = ["alpine"]` declares this port is only meaningful on
  musl-base flavors. Building it on Arch still works but produces a
  harmless duplicate glibc tree.
- The non-standard `[notes]` table is preserved by the parser (round-trips
  cleanly) even though no consumer reads it yet — useful for parking
  caveats on the port for future readers.
