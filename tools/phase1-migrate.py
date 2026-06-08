#!/usr/bin/env python3
"""
Phase 1 schema migration.

Inserts the new [install] table (with layout = "system") into every
package.toml under base/ and device/, immediately after the [package]
table and before the next top-level table.

The pass is strictly additive and text-level: no TOML round-trip, no
key reordering, no quote-style normalization. If the [install] block
already exists in a file we skip it (idempotent).

Run from the repo root:

    python3 tools/phase1-migrate.py

Use --dry-run to print files that would change without writing.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

INSTALL_BLOCK = (
    "\n"
    "# Phase 1 schema migration — defaults to layout = \"system\"; revisit per-port later.\n"
    "[install]\n"
    "layout = \"system\"\n"
    "\n"
)


def find_manifests() -> list[Path]:
    return sorted(
        list((REPO_ROOT / "base").glob("*/package.toml"))
        + list((REPO_ROOT / "device").glob("*/package.toml"))
    )


def is_top_level_table_header(line: str) -> bool:
    """A line like `[foo]` (not `[[foo]]`, not `[foo.bar]` inline-only check)."""
    s = line.lstrip()
    if not s.startswith("["):
        return False
    if s.startswith("[["):
        return False
    # Strip any trailing comment then whitespace.
    head = s.split("#", 1)[0].rstrip()
    return head.startswith("[") and head.endswith("]")


def migrate_text(text: str) -> tuple[str, bool]:
    """Return (new_text, changed)."""
    if "[install]" in text:
        return text, False

    lines = text.splitlines(keepends=True)
    # Find the [package] header.
    pkg_idx = None
    for i, line in enumerate(lines):
        if line.lstrip().startswith("[package]"):
            pkg_idx = i
            break
    if pkg_idx is None:
        raise ValueError("no [package] table found")

    # Walk forward until we hit the next top-level table header (or EOF).
    insert_at = len(lines)
    for j in range(pkg_idx + 1, len(lines)):
        if is_top_level_table_header(lines[j]):
            insert_at = j
            break

    # Trim trailing blank lines from the [package] block so we don't end up
    # with multiple blank lines between [package] and our new comment.
    while insert_at > pkg_idx + 1 and lines[insert_at - 1].strip() == "":
        insert_at -= 1

    # Also avoid producing a doubled blank line below the install block when
    # the next table already had a leading blank line.
    suffix = lines[insert_at:]
    # The install block itself ends with "\n" so suffix starts at the next
    # token. Drop one leading blank line from suffix if present, since
    # INSTALL_BLOCK already supplies a single trailing blank.
    if suffix and suffix[0].strip() == "":
        suffix = suffix[1:]

    new_lines = lines[:insert_at] + [INSTALL_BLOCK] + suffix
    new_text = "".join(new_lines)
    return new_text, True


def main() -> int:
    parser = argparse.ArgumentParser(description="Phase 1 schema migration.")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    changed = 0
    skipped = 0
    manifests = find_manifests()
    for m in manifests:
        text = m.read_text()
        new_text, did_change = migrate_text(text)
        if did_change:
            changed += 1
            if args.dry_run:
                print(f"would update: {m.relative_to(REPO_ROOT)}")
            else:
                m.write_text(new_text)
                print(f"updated: {m.relative_to(REPO_ROOT)}")
        else:
            skipped += 1
            print(f"skipped (already migrated): {m.relative_to(REPO_ROOT)}")

    print(f"\n{len(manifests)} manifest(s) scanned, {changed} updated, {skipped} skipped.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
