#!/usr/bin/env bash
# qrowlocatorcheck.sh — r27 P2.5 gate: --quality-delta findings must be ACTIONABLE.
#
# THE COMPLAINT THIS PINS. The gate agents are told to run at every "done" moment printed rows like
# `sym="cc"` — a canonical id whose display tail is often a bare, one-letter local — with NO path on any row
# kind, so a finding could not be opened, greppable or otherwise. And a GATING row (the ones the header's
# gating= counts and the exit code fires on) was identifiable only by the ABSENCE of sev="minor" and of
# origin="new-symbol": absence-as-signal is the least machine-friendly encoding available. Finally, exit 2
# arrived with no explanation on any channel — `--token-budget` has printed one honest stderr line for this
# exact situation for rounds.
#
# Checks (XML and --json in lockstep — a consumer must not have to pick a format to get the facts):
#   (a) EVERY row carries p="path:line"; the path is ROOT-RELATIVE and the line is non-zero.
#   (b) the p= path actually EXISTS in the repo (a locator that does not resolve is worse than none).
#   (c) the count of rows carrying gating="1" EQUALS the header's gating="N".
#   (d) gating="1" never co-occurs with sev="minor" or origin="new-symbol" (it IS the exit predicate).
#   (e) exit 2 prints one stderr line naming the gating finding, in --token-budget's style.
#   (f) exit 0 prints NO such line (no crying wolf on a clean run).
#   (g) --json carries "p" and "gating":true with the same gating count, and the XML stays xmllint-clean.
#
# Own temp repo. Needs git; xmllint optional (that sub-check is skipped when absent).
# Usage:  test/qrowlocatorcheck.sh   |   RIPWIRE_BIN=build/ripwire test/qrowlocatorcheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "  SKIP  qrowlocatorcheck (git not available)"; exit 0; }

REPO="$( mktemp -d )"; TMP="$( mktemp -d )"; trap 'rm -rf "$REPO" "$TMP"' EXIT
run(){ ( cd "$REPO" && "$BIN" . --quality-delta --no-cache "$@" ); }

mkdir -p "$REPO/inc" "$REPO/src"
cat > "$REPO/inc/api.h" <<'EOF'
int seed( int a );
int twin( int a );
EOF
cat > "$REPO/src/lib.cpp" <<'EOF'
#include "../inc/api.h"
int seed( int a ) { return a + 1; }
int twin( int a ) { return a + 2; }
int knotty( int a, int b ) { int r = 0; for( int i = 0; i < a; ++i ) { if( i > b ) { r += i; } } return r; }
EOF
( cd "$REPO" && git init -q && git config user.email t@t && git config user.name t \
  && git add -A >/dev/null && git commit -qm init >/dev/null )

# Working-tree edits that produce SEVERAL kinds at once: a complexity+nesting+verbosity blow-up on a symbol
# that already existed (preexisting-worse ⇒ GATING), plus a new public export (new-symbol ⇒ never gates),
# plus a byte-identical copy of an existing function (duplication, a clone-kind row so its locator path is
# exercised too).
cat > "$REPO/src/lib.cpp" <<'EOF'
#include "../inc/api.h"
int seed( int a ) { return a + 1; }
int twin( int a ) { return a + 2; }
int knotty( int a, int b ) {
    int r = 0;
    for( int i = 0; i < a; ++i ) {
        if( i % 2 == 0 ) { if( i > b ) { r += i; } else { r -= 1; } }
        else { for( int j = 0; j < b; ++j ) { if( j > r ) { r += j; } else { r--; } } }
        while( r > b && r > 1 ) { r = r - 1; if( r % 3 == 0 ) { r += 2; } else { r -= 2; } }
        if( r < 0 ) { if( a > b ) { r = a; } else { r = b; } }
    }
    return r;
}
int seedCopy( int a ) { int q = 0; for( int i = 0; i < a; ++i ) { q += i * 3; } return q; }
int seedClone( int a ) { int q = 0; for( int i = 0; i < a; ++i ) { q += i * 3; } return q; }
EOF
cat >> "$REPO/inc/api.h" <<'EOF'
int addedExport( int a );
EOF

run >"$TMP/x" 2>"$TMP/xerr"; rc=$?
ROWS="$( tr '<' '\n' < "$TMP/x" | grep '^r kind=' )"
NROWS="$( printf '%s\n' "$ROWS" | grep -c . )"
[ "$NROWS" -gt 3 ] && ok "fixture produced $NROWS rows across several kinds (non-vacuous)" \
                   || { no "fixture produced only $NROWS rows — the checks below would be vacuous"; printf '%s\n' "$ROWS"; }

# ── (a)(b) p="path:line" on every row, root-relative, resolvable, non-zero line ────────────────────────────
missing="$( printf '%s\n' "$ROWS" | grep -vc ' p="' )"
[ "$missing" -eq 0 ] && ok "every row carries p=\"path:line\"" \
                     || { no "$missing row(s) have no p= locator"; printf '%s\n' "$ROWS" | grep -v ' p="' | head -3; }

badpath=0; badline=0
for loc in $( printf '%s\n' "$ROWS" | sed -n 's/.* p="\([^"]*\)".*/\1/p' ); do
    lp="${loc%:*}"; ln="${loc##*:}"
    [ -f "$REPO/$lp" ] || { badpath=$(( badpath + 1 )); echo "      unresolvable: $loc"; }
    case "$ln" in ''|*[!0-9]*|0) badline=$(( badline + 1 )); echo "      bad line: $loc";; esac
done
[ "$badpath" -eq 0 ] && ok "every p= path is root-relative and resolves to a real file" || no "$badpath p= path(s) do not resolve"
[ "$badline" -eq 0 ] && ok "every p= line number is a non-zero integer" || no "$badline p= line number(s) are 0/non-numeric"

# ── (c)(d) gating="1" is an explicit, self-consistent marker ───────────────────────────────────────────────
HDR_GATING="$( sed -n 's/.*<quality-delta [^>]*gating="\([0-9]*\)".*/\1/p' "$TMP/x" )"
ROW_GATING="$( printf '%s\n' "$ROWS" | grep -c ' gating="1"' )"
{ [ -n "$HDR_GATING" ] && [ "$HDR_GATING" = "$ROW_GATING" ]; } \
    && ok "rows marked gating=\"1\" ($ROW_GATING) == header gating=\"$HDR_GATING\"" \
    || no "gating row count $ROW_GATING != header gating=\"$HDR_GATING\""
[ "$ROW_GATING" -gt 0 ] && ok "the fixture has at least one gating row (non-vacuous)" || no "no gating rows — (c)/(e) are vacuous"

contra="$( printf '%s\n' "$ROWS" | grep ' gating="1"' | grep -cE 'sev="minor"|origin="new-symbol"' )"
[ "$contra" -eq 0 ] && ok "gating=\"1\" never co-occurs with sev=\"minor\" or origin=\"new-symbol\"" \
                    || { no "$contra gating row(s) also carry minor/new-symbol — the marker contradicts the predicate"; printf '%s\n' "$ROWS" | grep ' gating="1"' | grep -E 'sev="minor"|origin="new-symbol"' | head -2; }

# ── (e) one stderr line naming the gating finding at exit 2 ────────────────────────────────────────────────
[ "$rc" -eq 2 ] && ok "gating findings exit 2" || no "expected exit 2, got $rc"
if grep -q 'ripwire: --quality-delta gating: ' "$TMP/xerr"; then
    LINE="$( grep 'ripwire: --quality-delta gating: ' "$TMP/xerr" )"
    ok "exit 2 prints a gating line on stderr"
    printf '%s' "$LINE" | grep -q "gating: $HDR_GATING preexisting-worse major finding" \
        && ok "the stderr line reports the same gating count as the header" \
        || no "stderr gating count disagrees with the header ($HDR_GATING): $LINE"
    printf '%s' "$LINE" | grep -q ' at [^ ]*:[0-9]' \
        && ok "the stderr line names WHERE the first gating finding is" \
        || no "stderr gating line carries no file:line: $LINE"
    [ "$( grep -c 'ripwire: --quality-delta gating: ' "$TMP/xerr" )" -eq 1 ] \
        && ok "exactly one gating line on stderr (one line, like --token-budget)" \
        || no "more than one gating line printed"
else
    no "no gating explanation on stderr at exit 2"; head -3 "$TMP/xerr"
fi

# ── (f) a clean run says nothing ───────────────────────────────────────────────────────────────────────────
( cd "$REPO" && git checkout -q -- . )
run >"$TMP/clean" 2>"$TMP/cleanerr"; rcc=$?
{ [ "$rcc" -eq 0 ] && ! grep -q 'quality-delta gating' "$TMP/cleanerr"; } \
    && ok "a clean run exits 0 and prints no gating line (no crying wolf)" \
    || { no "clean run wrong (exit=$rcc)"; head -3 "$TMP/cleanerr"; }

# ── (g) --json parity + xmllint — restore the FULL dirty tree so the gating count is non-zero ─────────────
cat > "$REPO/src/lib.cpp" <<'EOF'
#include "../inc/api.h"
int seed( int a ) { return a + 1; }
int twin( int a ) { return a + 2; }
int knotty( int a, int b ) {
    int r = 0;
    for( int i = 0; i < a; ++i ) {
        if( i % 2 == 0 ) { if( i > b ) { r += i; } else { r -= 1; } }
        else { for( int j = 0; j < b; ++j ) { if( j > r ) { r += j; } else { r--; } } }
        while( r > b && r > 1 ) { r = r - 1; if( r % 3 == 0 ) { r += 2; } else { r -= 2; } }
        if( r < 0 ) { if( a > b ) { r = a; } else { r = b; } }
    }
    return r;
}
int seedCopy( int a ) { int q = 0; for( int i = 0; i < a; ++i ) { q += i * 3; } return q; }
int seedClone( int a ) { int q = 0; for( int i = 0; i < a; ++i ) { q += i * 3; } return q; }
EOF
cat >> "$REPO/inc/api.h" <<'EOF'
int addedExport( int a );
EOF
run --json >"$TMP/j" 2>/dev/null
grep -q '"p":"' "$TMP/j" && ok "--json rows carry \"p\"" || { no "--json rows have no \"p\" locator"; head -c 400 "$TMP/j"; echo; }
J_HDR="$( grep -o '"gating":[0-9][0-9]*' "$TMP/j" | head -1 | cut -d: -f2 )"
J_ROWS="$( grep -o '"gating":true' "$TMP/j" | wc -l | tr -d ' ' )"
{ [ -n "$J_HDR" ] && [ "$J_HDR" = "$J_ROWS" ] && [ "$J_ROWS" -gt 0 ]; } \
    && ok "--json \"gating\":true rows ($J_ROWS) == header \"gating\":$J_HDR (non-zero)" \
    || no "--json gating row count $J_ROWS != header $J_HDR (or both zero — vacuous)"
[ "$J_HDR" = "$HDR_GATING" ] \
    && ok "--json and XML agree on the gating count ($J_HDR)" \
    || no "--json gating=$J_HDR but XML gating=$HDR_GATING for the same tree"

if command -v xmllint >/dev/null 2>&1; then
    run >"$TMP/x2" 2>/dev/null
    xmllint --noout "$TMP/x2" 2>/dev/null && ok "G4: the report with p=/gating= is xmllint-clean" || no "G4: xmllint rejected the report"
else
    echo "  SKIP  xmllint not available (G4 sub-check)"
fi

[ "$fail" -eq 0 ] && echo "qrowlocatorcheck: ALL PASS" || { echo "qrowlocatorcheck: SOME CHECKS FAILED"; exit 1; }
