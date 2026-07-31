#!/usr/bin/env bash
# publish-blueprints.sh — sign + upload flavor blueprints to genmirror.
#
# A flavor is served as a directory of files that the installer fetches and VERIFIES individually:
# install.toml, configure.toml and every stage *.sh, each with a detached .sig alongside, plus the
# top-level index.toml (the flavor list the PRP wizard reads). Signing happens HERE, locally — the
# secret key must never touch the mirror. Only the file + its .sig are uploaded.
#
#   ./tools/publish-blueprints.sh arch debian        # publish specific flavors
#   ./tools/publish-blueprints.sh --all              # every dir under blueprints/
#   ./tools/publish-blueprints.sh --index-only       # re-sign + push just index.toml
#
# Env overrides:
#   GENMIRROR_SEC   secret key            (default ~/.local/var/peacock/genmirror-keys/genmirror.sec)
#   GENMIRROR_PUB   public key, for the post-publish verification
#   GENMIRROR_HOST  ssh host              (default lijiang_ts)
#   GENMIRROR_DIR   blueprints dir on the host
#   CHANNEL         stable|testing        (default stable)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BP_SRC="$REPO_ROOT/blueprints"
SIGN="${FTR_SIGN:-$REPO_ROOT/../feather/tools/ftr-sign}"
SEC="${GENMIRROR_SEC:-$HOME/.local/var/peacock/genmirror-keys/genmirror.sec}"
PUB="${GENMIRROR_PUB:-$HOME/.local/var/peacock/genmirror-keys/genmirror.pub}"
HOST="${GENMIRROR_HOST:-lijiang_ts}"
CHANNEL="${CHANNEL:-stable}"
DEST="${GENMIRROR_DIR:-/home/tiel/sda1/peacock-services/caddy/config/genmirror/blueprints}/$CHANNEL"
COMMENT="${SIGN_COMMENT:-peacock blueprints}"

die() { printf 'publish-blueprints: %s\n' "$*" >&2; exit 1; }
[ -x "$SIGN" ] || die "ftr-sign not found/executable at $SIGN (set FTR_SIGN)"
[ -f "$SEC" ]  || die "secret key not found at $SEC (set GENMIRROR_SEC)"
[ -d "$BP_SRC" ] || die "no blueprints dir at $BP_SRC"

INDEX_ONLY=0
FLAVORS=()
for a in "$@"; do
	case "$a" in
		--all)        while IFS= read -r d; do FLAVORS+=("$(basename "$d")"); done \
		                   < <(find "$BP_SRC" -mindepth 1 -maxdepth 1 -type d | sort) ;;
		--index-only) INDEX_ONLY=1 ;;
		-h|--help)    sed -n '2,16p' "${BASH_SOURCE[0]}"; exit 0 ;;
		-*)           die "unknown flag: $a" ;;
		*)            FLAVORS+=("$a") ;;
	esac
done
[ "$INDEX_ONLY" = 1 ] || [ "${#FLAVORS[@]}" -gt 0 ] || die "nothing to do — pass flavor ids, --all, or --index-only"

# Sign $1 into $1.sig (in a temp staging dir so we never write .sig files into the git tree).
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
sign_into_stage() {
	local src="$1" rel="$2"
	mkdir -p "$STAGE/$(dirname "$rel")"
	cp "$src" "$STAGE/$rel"
	"$SIGN" "$SEC" "$src" "$STAGE/$rel.sig" "$COMMENT" >/dev/null \
		|| die "signing failed for $rel"
}

for f in "${FLAVORS[@]}"; do
	src="$BP_SRC/$f"
	[ -d "$src" ] || die "no such flavor dir: $src"
	[ -f "$src/install.toml" ]   || die "$f: missing install.toml"
	[ -f "$src/configure.toml" ] || die "$f: missing configure.toml"
	n=0
	# Only the files the runner actually fetches. Anything else in the dir is not served.
	while IFS= read -r p; do
		sign_into_stage "$p" "$f/$(basename "$p")"
		n=$((n + 1))
	done < <(find "$src" -maxdepth 1 -type f \( -name '*.toml' -o -name '*.sh' \) | sort)
	printf 'signed %-14s %2d file(s)\n' "$f" "$n"
done

if [ -f "$BP_SRC/index.toml" ]; then
	sign_into_stage "$BP_SRC/index.toml" "index.toml"
	printf 'signed %-14s index.toml\n' "(root)"
fi

# Upload. rsync in ONE pass over the staging tree so a file and its .sig always land together —
# publishing a .toml whose .sig is missing/stale makes the installer reject the flavor outright.
printf 'uploading to %s:%s …\n' "$HOST" "$DEST"
ssh "$HOST" "mkdir -p '$DEST'" || die "cannot reach $HOST"
rsync -a "$STAGE"/ "$HOST:$DEST/" || die "upload failed"

# Verify what the world actually SEES: re-fetch every published file + sig over HTTP and check the
# signature with the PUBLIC key, using the device's own verification code (PRP/gui/bp_verify.c) so
# this is the same accept/reject decision the installer will make. Catches a half-uploaded pair or
# a stale sig now, instead of on a user's phone. Built on demand; skipped if cc/sources are absent.
GUI_SRC="${BP_VERIFY_SRC:-$REPO_ROOT/../PRP/gui}"
VERIFIER=""
if [ -f "$PUB" ] && [ -f "$GUI_SRC/bp_verify.c" ] && command -v cc >/dev/null 2>&1; then
	cat > "$STAGE/.verify_main.c" <<'EOF'
#include <stdio.h>
#include "bp_verify.h"
int main(int argc, char **argv) {
	char err[256] = "";
	if (argc != 4) return 2;
	if (bp_verify_file(argv[1], argv[2], argv[3], err, sizeof err) == 0) return 0;
	fprintf(stderr, "%s\n", err);
	return 1;
}
EOF
	if cc -O1 -I"$GUI_SRC" "$STAGE/.verify_main.c" "$GUI_SRC/bp_verify.c" "$GUI_SRC/tweetnacl.c" \
	      -o "$STAGE/.bpverify" 2>/dev/null; then
		VERIFIER="$STAGE/.bpverify"
	fi
fi

BASE_URL="${GENMIRROR_URL:-https://genmirror.peacockos.org}/blueprints/$CHANNEL"
if [ -n "$VERIFIER" ]; then
	printf 'verifying published files over HTTP …\n'
	ok=0; bad=0
	while IFS= read -r rel; do
		mkdir -p "$STAGE/.dl/$(dirname "$rel")"
		curl -fsS --max-time 20 -o "$STAGE/.dl/$rel"     "$BASE_URL/$rel"     2>/dev/null || { bad=$((bad+1)); printf '  MISSING  %s\n' "$rel"; continue; }
		curl -fsS --max-time 20 -o "$STAGE/.dl/$rel.sig" "$BASE_URL/$rel.sig" 2>/dev/null || { bad=$((bad+1)); printf '  NO SIG   %s\n' "$rel"; continue; }
		if "$VERIFIER" "$STAGE/.dl/$rel" "$STAGE/.dl/$rel.sig" "$PUB" 2>/dev/null; then
			ok=$((ok+1))
		else
			bad=$((bad+1)); printf '  BAD SIG  %s\n' "$rel"
		fi
	done < <(cd "$STAGE" && find . -type f ! -name '*.sig' ! -name '.*' -printf '%P\n' | sort)
	printf 'verified %d file(s), %d problem(s)\n' "$ok" "$bad"
	[ "$bad" -eq 0 ] || die "published files failed verification — the installer WILL reject them"
else
	printf 'published. (verification skipped: need cc + %s + %s/bp_verify.c)\n' "$PUB" "$GUI_SRC"
fi
printf 'done.\n'
