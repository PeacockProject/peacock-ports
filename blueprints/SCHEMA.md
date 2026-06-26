# Blueprint schema

A **blueprint** is a declarative TOML of stages — each a UI spec + a shell **action** — served from
genmirror under `blueprints/<channel>/` and executed by the shared **blueprint runner**
(`bp_run_stage_action`). Nothing about installing or configuring PeacockOS is baked into the
recovery image or the builder; it's all served, so a change is a one-file re-upload — no PRP/image
rebuild.

## Layout (per-flavor folders)

```
blueprints/<channel>/
  index.toml                      # served flavor list — [[flavor]] id/name
  <flavor>/install.toml           # kind=install   — base-install instructions
  <flavor>/configure.toml         # kind=oobe      — first-boot setup
  <flavor>/stages/*.sh            # action_script files (path relative to <flavor>/)
```

Each flavor folder owns BOTH its install and its configure blueprints:

| file | `kind` | run by | `ROOT` | purpose |
|------|--------|--------|--------|---------|
| `<flavor>/install.toml` | `install` | **PRP** | the target mount | how to bring up THIS flavor's **base**: where to fetch its rootfs tarball, extract it into `/flavors/<flavor>`, post-extract prep + `active-flavor`. PRP owns only the *mechanism* (partition/mkfs/mount the target, Peacock base layer, bootloader). |
| `<flavor>/configure.toml` | `oobe` | **base OOBE** (first boot) + the **builder** (build time) | `/flavors/<active>` (boot) or the rootfs being built | first-boot setup: account, hostname, desktop, DM, timezone — the polymorphic UI the user fills in. |
| `index.toml` | — | PRP | — | lists available flavors (`[[flavor]]` id/name) so the installer's flavor list is served, not hardcoded. |

The same `configure.toml` actions run in two places via the `run_in_target` shim
(`chroot "$ROOT" "$@"`) — the builder at build time and the base OOBE on first boot — so it's the
**single source of truth** for flavor config (no duplicate `rootfs.go` heredocs).

The runner renders a screen per stage from the declared fields (a *polymorphic UI* — the UI is
whatever the TOML says), collects answers, and runs each stage's action.

## File layout (per flavor)

```toml
schema = 1                       # blueprint schema version (this doc = 1)
flavor = "arch"                  # must match the flavor-<name> metapackage
title  = "Arch (PeacockOS)"

[[stage]] ...                    # ordered stages (see below)
```

## Declarative — TOML declares, scripts execute

A blueprint TOML is **purely declarative**: it says *what to ask* (fields), *the steps* (with
description text + a `script` to run), and *digests* of any downloaded archive. The actual shell
logic lives in **scripts shipped alongside the TOML** in `blueprints/<channel>/<flavor>/`, each
**minisign-signed and verified** before it runs — same trust model as the TOMLs.

## `[archive]` (install blueprints)

```toml
[archive]                        # a downloadable flavor tarball + its digest
url    = "https://…/arch-base.tar.gz"
sha256 = "…"                     # the TOML is signed ⇒ this digest is trusted; the runner exposes
                                 # it as $BP_ARCHIVE_URL / $BP_ARCHIVE_SHA256, and fetch-base.sh
                                 # verifies the download against it before extraction.
```

## Stage

```toml
[[stage]]
id          = "desktop"          # unique within the blueprint; key in stage_status + requires
title       = "Choose a desktop" # screen title
description = "A desktop + login manager."   # description text shown under the title
requires    = ["account"]        # stage ids that must be `done` first (ordering DAG); default []
when        = "desktop != none"  # optional show-if over the answers store; "" = always shown
script      = "desktop.sh"        # sig-verified script in this flavor folder, run after capture
# action    = """ … """          # (alt) inline POSIX sh for trivial steps
# phase     = "install"|"oobe"    # defaults to the blueprint `kind`; rarely set explicitly

[[stage.field]] ...              # zero or more UI fields (a step with none is a pure action step)
```

- A stage names a **`script`** (preferred) or an inline `action`; the script is fetched + verified
  + run with `run_in_target`, `$ANS_<key>`, and `bp_log/bp_progress/bp_fail` available.
- `requires` is a DAG; the runner topologically sorts the stages.
- `phase` defaults to the blueprint's `kind` (`install`/`oobe`), so per-stage `phase` is rarely needed.

## Field

```toml
[[stage.field]]
key         = "user"             # answer key (stored in answers.toml [answers]); unique per blueprint
type        = "text"             # dropdown | text | password | toggle | info
label       = "USERNAME"         # shown above the control
options     = ["none","XFCE"]    # dropdown only
default     = "${host}-user"     # initial value; supports ${other_key} templating from the answers store
placeholder = "e.g. emre"        # text/password hint
validate    = "^[a-z_][a-z0-9_-]*$"   # optional regex checked on Next
required    = true               # blocks Next when empty; default false
when        = "desktop != none"  # optional per-field show-if; hidden fields are not captured
```

Field types:

| type       | control                       | captured value |
|------------|-------------------------------|----------------|
| `dropdown` | selector (`mk_dropdown`)      | the chosen option string |
| `text`     | one-line field (`mk_textfield`) | the entered text |
| `password` | masked field                  | the entered text — **never written to the answers store** |
| `toggle`   | switch                        | `"true"` / `"false"` |
| `info`     | static label (`mk_label`)     | nothing (display only) |

## `when` expressions

A tiny grammar evaluated against the live answers store: `key OP value`, where `OP` ∈ `==` / `!=`,
`value` is a bareword or `"quoted string"`, and terms join with `&&` / `||` (no parentheses).
Examples: `desktop != none`, `dm == SDDM && desktop != none`. Unknown keys compare as empty.

## Actions

Each stage may carry an inline `action` (POSIX sh) or an `action_script` path (fetched + verified
separately from genmirror). Either runs **after** the stage's fields are captured, with:

- answers injected as env: `$ANS_<key>` (e.g. `$ANS_user`, `$ANS_desktop`). The password is passed
  in the environment **only** for the stage that consumes it, never persisted.
- `run_in_target <cmd...>` available — `chroot "$ROOT" <cmd...>`; `$ROOT` is the flavor rootfs
  (build) or `/flavors/<active>` (OOBE). Use it for anything that must run *inside* the flavor
  (package installs, `useradd`, `localectl`, enabling services).
- stdout speaks the runner line-protocol: `STEP <i> <n> <title>` / `PROGRESS <0-100>` /
  `LOG <text>` / `DONE` / `ERROR <text>`. A helper `bp_log`/`bp_progress`/`bp_fail` is sourced.

Example:

```toml
action = """
bp_log "creating $ANS_user"
run_in_target useradd -m -G wheel "$ANS_user" || bp_fail "useradd failed"
printf '%s:%s' "$ANS_user" "$ANS_pass" | run_in_target chpasswd
"""
```

## Answers store

Persisted at **`/peacock/etc/oobe/answers.toml`** — base-owned, survives reboots and flavor
swaps, bind-mounted live into the flavor so the OOBE reads exactly what PRP wrote.

```toml
[meta]
schema       = 1
flavor       = "arch"
install_done = true       # PRP install-phase stages applied
oobe_done    = false      # first-boot OOBE-phase stages applied  ← the first-boot marker

[answers]                 # every captured non-password field
flavor   = "arch"
init     = "openrc"
host     = "peacock"
user     = "emre"
desktop  = "XFCE"
dm       = "SDDM"
timezone = "Europe/Istanbul"
locale   = "en_US.UTF-8"

[stage_status]            # lets a re-launched runner skip done stages / resume after a crash
account = "done"
desktop = "pending"       # done | pending | skipped
```

- `meta.oobe_done == false` is what `peacock-init` checks to decide whether to run the OOBE before
  entering the flavor on a given boot.
- Passwords are **never** stored here. The OOBE account stage asks fresh and applies immediately.
- `stage_status` enables resume: a DE download that failed mid-stage leaves the stage `pending`,
  so the next OOBE run retries only it.
