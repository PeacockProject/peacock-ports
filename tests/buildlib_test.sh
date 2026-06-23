#!/bin/sh
# buildlib_test.sh — unit tests for the lib/build phase model: default.sh
# helpers, the type libs (autotools/make/bootloader/kernel/raw), and the
# override mechanism a port's build.sh relies on. make/configure are stubbed
# so nothing is actually compiled; we assert the phases call the right things
# and that a build.sh can override ONE step and reuse the rest via default_*.
#
# Run from the peacock-ports root: ./tests/buildlib_test.sh
set -u

LIB="$(cd "$(dirname "$0")/.." && pwd)/lib/build"
[ -f "$LIB/default.sh" ] || { echo "buildlib_test: lib/build not found at $LIB" >&2; exit 2; }

fails=0
fail() { echo "  FAIL: $*" >&2; fails=$((fails + 1)); }
ok()   { echo "  ok: $*"; }

# --- peacock_extract strips the leading top-level dir (strip=1) ---
test_extract() {
	t=$(mktemp -d)
	mkdir -p "$t/top/sub"; echo hi > "$t/top/sub/f.txt"
	( cd "$t" && tar -czf src.tar.gz top )
	( cd "$t" && . "$LIB/default.sh" && strip=1 && peacock_extract src.tar.gz ) 2>/dev/null
	[ -f "$t/sub/f.txt" ] && ok "peacock_extract strips the top dir" \
		|| fail "peacock_extract: expected $t/sub/f.txt"
	rm -rf "$t"
}

# --- default_prepare no-ops (no error) when there is no source tarball ---
test_prepare_no_tarball() {
	t=$(mktemp -d)
	if ( cd "$t" && . "$LIB/default.sh" && default_prepare ) 2>/dev/null; then
		ok "default_prepare no-ops with no tarball"
	else
		fail "default_prepare errored with no tarball"
	fi
	rm -rf "$t"
}

# --- the override model: build.sh package() reuses default_install + adds a step ---
test_autotools_override() {
	t=$(mktemp -d); bin="$t/bin"; log="$t/calls.log"
	mkdir -p "$bin" "$t/build" "$t/pkg"
	cat > "$bin/make" <<EOF
#!/bin/sh
echo "make \$*" >> "$log"
EOF
	cat > "$t/build/configure" <<EOF
#!/bin/sh
echo "configure \$*" >> "$log"
EOF
	chmod +x "$bin/make" "$t/build/configure"
	# A port that's standard-except-the-install-step:
	cat > "$t/build.sh" <<'EOF'
package() {
	default_install
	: > "$pkgdir/EXTRA_RAN"
}
EOF
	out=$(
		PATH="$bin:$PATH"
		pkgname=demo; pkgver=1.0
		srcdir="$t"; builddir="$t/build"; pkgdir="$t/pkg"; jobs=2; prefix=/usr
		. "$LIB/default.sh"
		. "$LIB/autotools.sh"
		. "$t/build.sh"
		run_phases 2>&1
	)
	[ $? -eq 0 ] || fail "run_phases failed: $out"
	grep -q '^configure --prefix=/usr' "$log" || fail "default_configure didn't run ./configure --prefix (log: $(cat "$log" 2>/dev/null))"
	grep -q '^make -j2' "$log"                || fail "default_compile didn't run 'make -j2'"
	grep -q 'make install DESTDIR=' "$log"    || fail "default_install (reused by the override) didn't run 'make install'"
	[ -f "$t/pkg/EXTRA_RAN" ]                  || fail "the package() override's extra step didn't run"
	ok "autotools override: configure+compile ran, default_install reused, extra step ran"
	rm -rf "$t"
}

# --- peacock_die exits non-zero ---
test_die() {
	if ( . "$LIB/default.sh" && peacock_die boom ) 2>/dev/null; then
		fail "peacock_die returned 0"
	else
		ok "peacock_die exits non-zero"
	fi
}

# --- every type lib provides the build()/package() entry points ---
test_entrypoints() {
	for tl in autotools make bootloader kernel raw; do
		if ( . "$LIB/default.sh"; [ -f "$LIB/$tl.sh" ] && . "$LIB/$tl.sh"
		     command -v build >/dev/null && command -v package >/dev/null ); then
			ok "$tl: build() + package() defined"
		else
			fail "$tl.sh: build()/package() not defined"
		fi
	done
}

test_extract
test_prepare_no_tarball
test_autotools_override
test_die
test_entrypoints

if [ "$fails" -eq 0 ]; then
	echo "buildlib_test.sh: PASS"
else
	echo "buildlib_test.sh: FAIL ($fails)"; exit 1
fi
