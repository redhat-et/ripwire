#!/usr/bin/env bash
# qualityexcludecheck.sh — gate for A4-F5: --quality-delta's git-HEAD baseline must honor --exclude.
#
# The bug: computeHeadSnapshot ingested the HEAD tree with EMPTY filters while the working tree honored
# cfg.excludes. With --exclude=tests, a helper whose ONLY caller lives under tests/ is DEAD on the working
# side (tests/ filtered out → no caller) but ALIVE on the unfiltered HEAD side → the delta reports a phantom
# "dead-code" regression and exits 2 on an OTHERWISE-UNTOUCHED tree — the flagship "before I push" reflex
# punishing a clean tree. The fix threads cfg.excludes into computeHeadSnapshot so both trees see one file set.
#
# This gate builds a git repo whose working tree == HEAD (nothing edited) with exactly that shape:
#   src/lib.cpp:   helper() (called only from tests/) + mainThing()
#   tests/test_lib.cpp: the sole caller of helper()
# then asserts `--quality-delta --exclude=tests` exits 0 with no dead-code regression.
#
# REQUIRES the CLI to pass cfg.excludes to computeHeadSnapshot (main.cpp one-liner); against a binary that
# lacks it this gate FAILS with the exact phantom dead-code regression it guards against — that is the point.
# Uses its OWN temp repo. Does NOT edit regression.sh. Needs git.
# Usage:  test/qualityexcludecheck.sh   |   RIPWIRE_BIN=build/ripwire test/qualityexcludecheck.sh
set -u
BIN="${RIPWIRE_BIN:-./build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$PWD/$BIN"
fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }

REPO="$(mktemp -d)"; trap 'rm -rf "$REPO"' EXIT
mkdir -p "$REPO/src" "$REPO/tests"
cat > "$REPO/src/lib.cpp" <<'EOF'
int helper( int x ) { int s = 0; for( int i = 0; i < x; ++i ) { s += i * 2; } return s; }
int mainThing( int y ) { int t = y; while( t > 1 ) { t = t - 1; } return t; }
EOF
cat > "$REPO/tests/test_lib.cpp" <<'EOF'
extern int helper( int x );
int runTest() { return helper( 5 ) + 1; }
EOF
git -C "$REPO" init -q; git -C "$REPO" config user.email x@y; git -C "$REPO" config user.name x
git -C "$REPO" add -A; git -C "$REPO" commit -qm init

echo "qualityexcludecheck: BIN=$BIN"

# 1) the fixture must actually be exposed: WITHOUT --exclude, helper HAS a caller (tests/) → NOT dead → a
#    clean, untouched tree reports 0 regressions and exits 0. (Guards against a vacuous fixture.)
out_noexc="$("$BIN" "$REPO" --quality-delta --no-cache 2>&1)"; rc_noexc=$?
{ [ "$rc_noexc" -eq 0 ] && echo "$out_noexc" | grep -q 'regressions="0"'; } \
    && ok "untouched tree, no --exclude: exit 0, 0 regressions (control)" \
    || { no "control failed (exit=$rc_noexc)"; echo "     got: $(echo "$out_noexc" | grep -oE 'regressions="[0-9]+"')"; }

# 2) THE FIX: --exclude=tests on the SAME untouched tree must ALSO exit 0 with no dead-code regression — the
#    HEAD baseline now applies the same exclude, so helper is dead on BOTH sides (or on neither), never a delta.
out_exc="$("$BIN" "$REPO" --quality-delta --exclude=tests --no-cache 2>&1)"; rc_exc=$?
{ [ "$rc_exc" -eq 0 ] && ! echo "$out_exc" | grep -q 'kind="dead-code"'; } \
    && ok "untouched tree, --exclude=tests: exit 0, NO phantom dead-code regression (A4-F5 fixed)" \
    || { no "A4-F5 NOT fixed: --exclude=tests reports a phantom dead-code regression on an untouched tree (needs the main.cpp one-liner: computeHeadSnapshot( root, nullptr, cfg.maxFileBytes, cfg.excludes ))"
         echo "     exit=$rc_exc  got: $(echo "$out_exc" | grep -oE 'regressions="[0-9]+"|<r [^>]*/>' | head)"; }

# 3) determinism
r1="$("$BIN" "$REPO" --quality-delta --exclude=tests --no-cache 2>/dev/null)"
r2="$("$BIN" "$REPO" --quality-delta --exclude=tests --no-cache 2>/dev/null)"
[ "$r1" = "$r2" ] && ok "--quality-delta --exclude deterministic run-to-run" || no "non-deterministic output"

[ "$fail" -eq 0 ] && echo "qualityexcludecheck: ALL PASS" || { echo "qualityexcludecheck: SOME CHECKS FAILED"; exit 1; }
