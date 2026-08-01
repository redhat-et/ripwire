#!/usr/bin/env bash
# qualitysymcheck.sh — §P6.6 gate: --quality-delta's sym= must be ROOT-RELATIVE, the same spelling p=
# already uses, even when the tool is invoked with an ABSOLUTE root.
#
# THE BUG. sym= is a canonical id `path::scope::name` (resolve.h::canonicalId) whose PATH segment is
# ing.files[fileId] AS THE CALLER SPELLED THE ROOT. `ripwire .` embeds relative paths, but `ripwire
# /abs/repo` embeds the FULL absolute path — so sym= carries a 150+ char absolute prefix while p= beside
# it (quality::Regression::path, via relForHash) is already correctly root-relative. Two checkouts of the
# same repo at different absolute paths then produce DIFFERENT sym= text for the identical finding, which
# breaks any diff/grep/dedup across checkouts. The fix: src/quality.h's quality::displaySym() normalizes
# sym's path segment with the same relForHash() every other sidecar key uses, DISPLAY-ONLY (canonId itself,
# and Regression::key — the ack-ratchet identity — are untouched; see arch.h's relForHash comment, the S2
# trap). Wired into both the XML and --json quality-delta emitters in src/main.cpp.
#
# qrowlocatorcheck.sh and qualitykindscheck.sh pin the row SHAPE (p=/gating=/kind coverage) but always
# invoke with a relative root ("cd $REPO && $BIN ."), so neither exercises the absolute-root case — this
# gate is the one that does, per §P6.6's own instruction to build a scratch
# sandbox rather than touch the real repo (a clean tree has no working-tree diff to report).
#
# Own temp git repo, own temp build-independent BIN. Needs git.
# Usage:  test/qualitysymcheck.sh   |   RIPWIRE_BIN=build/ripwire test/qualitysymcheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "  SKIP  qualitysymcheck (git not available)"; exit 0; }

# mktemp -d already returns an ABSOLUTE path — the whole point: invoke "$BIN" "$REPO" below, never
# "cd $REPO && $BIN .", so the bug's precondition (an absolute root) is actually exercised.
REPO="$( mktemp -d )"; TMP="$( mktemp -d )"; trap 'rm -rf "$REPO" "$TMP"' EXIT
echo "qualitysymcheck: BIN=$BIN  REPO=$REPO (absolute root)"

mkdir -p "$REPO/src"
# A scoped method in a HEADER (quality.h's isPublicApi gates the api-surface kind on .h/.hpp/.hh/.hxx —
# a .cpp-only definition never counts as "public surface") so canonicalId emits path::scope::name — a bare
# free function degrades to just the name and would give the normalization nothing to do. Also two
# identically-shaped .cpp methods so the "duplication" kind's space-joined members= list is exercised too
# (two "::"-bearing tokens joined by " | ", the separator reportNewClones actually uses in src/quality.h).
cat > "$REPO/src/widget.h" <<'EOF'
struct Widget
{
    int run( int a, int b ) { return a + b; }
};
EOF
cat > "$REPO/src/probe.cpp" <<'EOF'
#include "widget.h"
EOF
( cd "$REPO" && git init -q && git config user.email t@t && git config user.name t \
  && git add -A >/dev/null && git commit -qm init >/dev/null )

# Working-tree regression: grow run()'s param count — a public (header-declared) contract change, on a
# symbol that EXISTED at the baseline (preexisting-worse ⇒ gating), plus a same-shaped clone sibling
# (duplication kind, member-set sym=).
cat > "$REPO/src/widget.h" <<'EOF'
struct Widget
{
    int run( int a, int b, int c = 0, int d = 0, int e = 0 ) { return a + b + c + d + e; }
};
EOF
cat > "$REPO/src/probe.cpp" <<'EOF'
#include "widget.h"
struct Gadget
{
    int spin( int a, int b, int c, int d, int e, int f, int g, int h ) { int q = 0; for( int i = 0; i < a; ++i ) { q += i * b + c - d + e * f - g + h; } return q; }
};
struct Gizmo
{
    int spin( int a, int b, int c, int d, int e, int f, int g, int h ) { int q = 0; for( int i = 0; i < a; ++i ) { q += i * b + c - d + e * f - g + h; } return q; }
};
EOF

run(){ "$BIN" "$REPO" --quality-delta --no-cache "$@"; }   # NO cd — absolute root, on purpose

OUT="$( run 2>"$TMP/xerr" )"; rc=$?
printf '%s' "$OUT" > "$TMP/x"
ROWS="$( tr '<' '\n' < "$TMP/x" | grep '^r kind=' )"
NROWS="$( printf '%s\n' "$ROWS" | grep -c . )"
[ "$NROWS" -gt 0 ] && ok "fixture produced $NROWS row(s) under an absolute root (non-vacuous)" \
                   || { no "fixture produced 0 rows — the checks below would be vacuous"; cat "$TMP/xerr"; exit 1; }

# ── (a) NO row's sym= carries an absolute-path prefix ("/" or the repo's own absolute root) ────────────
ABS_SYMS="$( printf '%s\n' "$ROWS" | grep -oE 'sym="[^"]*"|members="[^"]*"' | grep -c "\"$REPO" )"
[ "$ABS_SYMS" -eq 0 ] \
    && ok "no sym=/members= value carries the sandbox's absolute path" \
    || { no "$ABS_SYMS sym=/members= value(s) still carry the absolute root"; printf '%s\n' "$ROWS" | grep -oE 'sym="[^"]*"|members="[^"]*"' | grep "\"$REPO" | head -5; }

SLASH_SYMS="$( printf '%s\n' "$ROWS" | grep -oE 'sym="/[^"]*"' | wc -l | tr -d ' ' )"
[ "$SLASH_SYMS" -eq 0 ] \
    && ok "no sym= value starts with a leading '/' (root-relative, matches p=)" \
    || no "$SLASH_SYMS sym= value(s) start with '/' — not root-relative"

# ── (b) the specific api-surface row on Widget::run: sym= path segment == p= path segment ───────────────
WROW="$( printf '%s\n' "$ROWS" | grep 'kind="api-surface"' | grep 'Widget::run' )"
[ -n "$WROW" ] && ok "Widget::run's api-surface (contract-change) row found" || no "Widget::run's api-surface row NOT found — fixture didn't trigger as expected"
if [ -n "$WROW" ]; then
    SYM_PATH="$( printf '%s' "$WROW" | sed -n 's/.*sym="\([^"]*\)::Widget::run".*/\1/p' )"
    P_PATH="$(   printf '%s' "$WROW" | sed -n 's/.* p="\([^"]*\)::[0-9]*".*/\1/p' )"
    # p= is "path:line" (colon), sym= path segment is followed by "::Widget::run" — extract p='s path only.
    P_PATH="$( printf '%s' "$WROW" | sed -n 's/.* p="\([^"]*\):[0-9]*".*/\1/p' )"
    [ "$SYM_PATH" = "src/widget.h" ] && ok "sym='s path segment is root-relative (\"$SYM_PATH\")" \
                                       || no "sym='s path segment is \"$SYM_PATH\", expected \"src/widget.h\""
    [ "$SYM_PATH" = "$P_PATH" ] && ok "sym='s path segment == p='s path segment (\"$P_PATH\") — comparable, same spelling" \
                                 || no "sym path \"$SYM_PATH\" != p path \"$P_PATH\" — still not the same spelling"
fi

# ── (c) the duplication row's members= list: BOTH member ids are root-relative, joined by " | " intact ──
DROW="$( printf '%s\n' "$ROWS" | grep 'kind="duplication"' | grep 'Gizmo::spin\|Gadget::spin' )"
if [ -n "$DROW" ]; then
    ok "duplication row (Gadget::spin / Gizmo::spin clone pair) found"
    printf '%s' "$DROW" | grep -q 'members="src/probe.cpp::Gadget::spin | src/probe.cpp::Gizmo::spin"' \
        && ok "duplication members= carries BOTH ids root-relative, \" | \"-joined intact" \
        || { no "duplication members= not in the expected root-relative, pipe-joined shape"; printf '%s\n' "$DROW"; }
else
    echo "  SKIP  duplication row not produced (clone detector did not pair Gadget/Gizmo — not this gate's concern)"
fi

# ── (d) --json mirrors the same normalization ────────────────────────────────────────────────────────
JOUT="$( run --json 2>/dev/null )"
J_ABS="$( printf '%s' "$JOUT" | grep -oE '"sym":"[^"]*"|"members":"[^"]*"' | grep -c "\"$REPO" )"
[ "$J_ABS" -eq 0 ] && ok "--json: no \"sym\"/\"members\" value carries the absolute root either" \
                   || no "--json: $J_ABS value(s) still carry the absolute root"
printf '%s' "$JOUT" | grep -q '"sym":"src/widget.h::Widget::run"' \
    && ok "--json \"sym\" for Widget::run is root-relative, matching the XML" \
    || no "--json \"sym\" for Widget::run is not the expected root-relative form"

# ── (e) determinism + xmllint (the usual discipline, exercised on the actual fix) ────────────────────
OUT2="$( run 2>/dev/null )"
[ "$OUT" = "$OUT2" ] && ok "deterministic (byte-identical run-to-run)" || no "non-deterministic output"
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$OUT" | xmllint --noout - && ok "xmllint-clean" || no "xmllint rejected the report"
fi

[ "$fail" -eq 0 ] && echo "qualitysymcheck: ALL PASS" || { echo "qualitysymcheck: SOME CHECKS FAILED"; exit 1; }
