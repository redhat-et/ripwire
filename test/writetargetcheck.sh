#!/usr/bin/env bash
# writetargetcheck.sh — A4-F24 gate: isWriteTarget honors its documented contract. The base object of a
# subscript/field-expression LHS (`a` in `a[i] = x`, `p` in `p->f = x`) must be reported role=write by
# --uses, while the index (`i`) and every RHS name stay role=read. Before the fix the base was mislabeled
# read, contradicting the header comment. Exits non-zero on any failure. Does NOT edit test/regression.sh.
#
#   test/writetargetcheck.sh
#   RIPWIRE_BIN=asan/ripwire test/writetargetcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
CORPUS="$ROOT/test/writetargetfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ]    || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$CORPUS" ] || { echo "no test/writetargetfix dir — fixture missing"; exit 2; }

echo "writetargetcheck: BIN=$BIN  CORPUS=$CORPUS"

# helper: "role basename:line" per use-site of SYM (basename so it is location-independent)
uses(){ "$BIN" "$CORPUS" --uses="$1" --no-cache 2>/dev/null | grep -o 'role="[a-z]*" p="[^"]*"' \
        | sed -E 's/role="([a-z]*)" p="([^"]*\/)?([^"/]*)"/\1 \3/'; }
has(){ uses "$1" | grep -qxF "$2"; }

# ── 1) array-element store: `buf[ idx ] = val` → buf is the WRITE target (the headline A4-F24 case) ──────
has buf "write lhs.cpp:14" && ok "buf[idx]=val: base buf labeled write @14" || { no "buf @14 not write (F24 regression)"; uses buf; }
has buf "write lhs.cpp:17" && ok "buf[idx]+=1: base buf labeled write @17 (augmented)" || { no "buf @17 not write"; uses buf; }

# ── 2) field store: `p->f = val` → base object p is the WRITE target ─────────────────────────────────────
has p "write lhs.cpp:16" && ok "p->f=val: base p labeled write @16" || { no "p @16 not write"; uses p; }

# ── 3) the index and RHS names stay READ (no over-classification: idx/val must NOT be write) ─────────────
has idx "read lhs.cpp:14" && ! uses idx | grep -qxF "write lhs.cpp:14" \
    && ok "index idx stays read @14 (not swept up as a write target)" || { no "idx @14 mislabeled"; uses idx; }
has val "read lhs.cpp:14" && ! uses val | grep -qxF "write lhs.cpp:14" \
    && ok "rhs val stays read @14" || { no "val @14 mislabeled"; uses val; }
has val "read lhs.cpp:16" && ok "rhs val stays read @16 (p->f = val)" || { no "val @16 not read"; uses val; }

# ── 4) determinism + well-formedness ────────────────────────────────────────────────────────────────────
A="$( "$BIN" "$CORPUS" --uses=buf --no-cache 2>/dev/null )"
B="$( "$BIN" "$CORPUS" --uses=buf --no-cache 2>/dev/null )"
[ "$A" = "$B" ] && ok "determinism (byte-identical run-to-run)" || no "non-deterministic --uses output"
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$A" | xmllint --noout - 2>/dev/null && ok "--uses xml well-formed" || no "--uses xml malformed"
else
    ok "xml well-formed (xmllint absent — skipped)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
