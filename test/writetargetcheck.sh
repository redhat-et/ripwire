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
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
CORPUS="$ROOT/test/writetargetfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ]    || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$CORPUS" ] || { echo "no test/writetargetfix dir — fixture missing"; exit 2; }

echo "writetargetcheck: BIN=$BIN  CORPUS=$CORPUS"

# helper: "role basename:line" per use-site of SYM (basename so it is location-independent)
uses(){ "$BIN" "$CORPUS" --uses="$1" --no-cache 2>/dev/null | grep -o 'role="[a-z]*" p="[^"]*"' \
        | sed -E 's/role="([a-z]*)" p="([^"]*\/)?([^"/]*)"/\1 \3/'; }
has(){ uses "$1" | grep -qxF "$2"; }

# ── 1) array-element store: `buf[ idx ] = val` → buf is the WRITE target (the headline A4-F24 case) ──────
if has buf "write lhs.cpp:14"; then ok "buf[idx]=val: base buf labeled write @14"; else { no "buf @14 not write (F24 regression)"; uses buf; }; fi
if has buf "write lhs.cpp:17"; then ok "buf[idx]+=1: base buf labeled write @17 (augmented)"; else { no "buf @17 not write"; uses buf; }; fi

# ── 2) field store: `p->f = val` → base object p is the WRITE target ─────────────────────────────────────
if has p "write lhs.cpp:16"; then ok "p->f=val: base p labeled write @16"; else { no "p @16 not write"; uses p; }; fi

# ── 3) the index and RHS names stay READ (no over-classification: idx/val must NOT be write) ─────────────
has idx "read lhs.cpp:14" && ! uses idx | grep -qxF "write lhs.cpp:14" \
    && ok "index idx stays read @14 (not swept up as a write target)" || { no "idx @14 mislabeled"; uses idx; }
has val "read lhs.cpp:14" && ! uses val | grep -qxF "write lhs.cpp:14" \
    && ok "rhs val stays read @14" || { no "val @14 mislabeled"; uses val; }
if has val "read lhs.cpp:16"; then ok "rhs val stays read @16 (p->f = val)"; else { no "val @16 not read"; uses val; }; fi

# ── 4) determinism + well-formedness ────────────────────────────────────────────────────────────────────
A="$( "$BIN" "$CORPUS" --uses=buf --no-cache 2>/dev/null )"
B="$( "$BIN" "$CORPUS" --uses=buf --no-cache 2>/dev/null )"
if [ "$A" = "$B" ]; then ok "determinism (byte-identical run-to-run)"; else no "non-deterministic --uses output"; fi
if command -v xmllint >/dev/null 2>&1; then
    if printf '%s' "$A" | xmllint --noout - 2>/dev/null; then ok "--uses xml well-formed"; else no "--uses xml malformed"; fi
else
    ok "xml well-formed (xmllint absent — skipped)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
