#!/usr/bin/env python3
"""
Phase 1 schema migration verification.

For every package.toml under base/ and device/:
  1. Parses it with Python's stdlib tomllib (3.11+).
  2. Confirms presence of [install].layout.

Exits 0 if all manifests are valid and migrated; non-zero otherwise.

Run from the repo root:

    python3 tools/phase1-verify.py
"""

from __future__ import annotations

import sys
import tomllib
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

VALID_LAYOUTS = {"system", "peacock", "app", "compat"}


def find_manifests() -> list[Path]:
    return sorted(
        list((REPO_ROOT / "base").glob("*/package.toml"))
        + list((REPO_ROOT / "device").glob("*/package.toml"))
    )


def main() -> int:
    manifests = find_manifests()
    failures: list[str] = []
    parsed = 0
    for m in manifests:
        rel = m.relative_to(REPO_ROOT)
        try:
            with m.open("rb") as fh:
                data = tomllib.load(fh)
        except tomllib.TOMLDecodeError as exc:
            failures.append(f"{rel}: TOML parse error: {exc}")
            continue
        parsed += 1
        install = data.get("install")
        if not isinstance(install, dict):
            failures.append(f"{rel}: missing [install] table")
            continue
        layout = install.get("layout")
        if layout not in VALID_LAYOUTS:
            failures.append(
                f"{rel}: [install].layout = {layout!r}, expected one of {sorted(VALID_LAYOUTS)}"
            )

    print(f"parsed {parsed}/{len(manifests)} manifest(s) cleanly")
    if failures:
        print(f"\n{len(failures)} failure(s):")
        for f in failures:
            print(f"  - {f}")
        return 1
    print(f"all {len(manifests)} manifest(s) have valid [install].layout")
    return 0


if __name__ == "__main__":
    sys.exit(main())
