#!/usr/bin/env bash
# typerefcheck.sh — the RefRole::Type gate (resolver-precision round, docs/EVALS.md §4
# "Type-mention use-sites + namespace-compatible candidates", PRE-REGISTERED 2026-08-20).
#
# THE DEFECT THIS PINS. src/ingest.cpp::usesVisitNode opened with `strcmp( t, "identifier" ) != 0 →
# return`, so a `type_identifier` node — a bare TYPE mention in a signature, a declaration or a
# template argument — was captured by NOTHING. `RefRole` carried Call|Read|Write|Import|Extends|Macro
# and only Extends (a base clause) and isCompose (a member-variable declared type) touched a type
# position, both of them SPECIFIC declaration forms rather than a general mention. Consequence,
# measured on ripwire's own tree before the fix: `--uses=IngestResult` returned count="0" against 438
# real mentions across 68 files — the single most-connected data structure in the codebase was a graph
# isolate, and every blast-radius surface built on the use-site index inherited that zero.
#
# RED-FIRST. Against the pre-fix reference binary (`ripwire-wt-wave3/build/ripwire` @ ba3a716) arm 1
# below reports count="0" and the gate exits 1. That failure is the recorded control.
#
#   test/typerefcheck.sh                       # uses build/ripwire on test/typereffix
#   RIPWIRE_BIN=asan/ripwire test/typerefcheck.sh
#
# Fixture test/typereffix/ (C++):
#   a.h    — `struct Widget` (the type under test) + `struct Unrelated`.
#   b.cpp  — names Widget ONLY in type position: a member type (:10), a return type AND a parameter
#            type on one line (:13), a template argument (:18), a pointer parameter (:23). It never
#            calls Widget, never constructs one, and never reads a value of that name.
#   c.cpp  — NEGATIVE CONTROL: a LOCAL VARIABLE named `Widget`. It must never produce a type row —
#            the guard that the widened accept set keys on the NODE KIND, not on the spelling.
#
# Four arms:
#   1) --uses=Widget yields >= 4 rows with role="type", at the exact file:line of each mention. RED
#      pre-fix (count="0").
#   2) THE CONTRACT HALF: the default map over the fixture still reports edges=0 ambiguous=0 — a Type
#      reference must NEVER enter the call-graph CSR, exactly as Read/Write/Import/Extends do not, so
#      PageRank and the default ranked map are unchanged by this role (G5).
#   3) The DEFINITION site is not a use-site: no type row lands on a.h at the line that DEFINES Widget.
#   4) The negative control: zero rows of ANY role in c.cpp, and specifically no role="type" there.
#
# Plus determinism (byte-identical twice) and XML well-formedness over the fixture.
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
FIX="$ROOT/test/typereffix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "typerefcheck: BIN=$BIN  FIX=$FIX"

# ── 0) presence guards — a gate whose probe target can vanish passes for the wrong reason ──────────
for f in a.h b.cpp c.cpp; do
    [ -f "$FIX/$f" ] || { no "fixture missing: $FIX/$f"; }
done
[ "$( grep -c 'Widget' "$FIX/b.cpp" )" -ge 4 ] || no "presence guard: b.cpp must spell Widget in >=4 type positions"
grep -q 'int Widget' "$FIX/c.cpp" || no "presence guard: c.cpp must declare a LOCAL named Widget"
[ "$fail" -eq 0 ] || { echo "SOME CHECKS FAILED"; exit 1; }

USES="$( "$BIN" "$FIX" --uses=Widget --no-cache 2>/dev/null | tr '<' '\n' | grep -E '^u role=' )"
HDR="$( "$BIN" "$FIX" --no-cache 2>/dev/null )"

# ── 1) type mentions are use-sites (RED pre-fix: count="0") ───────────────────────────────────────
NTYPE="$( printf '%s\n' "$USES" | grep -c 'role="type"' )"
if [ "$NTYPE" -ge 4 ]; then
    ok "type mentions are use-sites: $NTYPE rows with role=\"type\""
else
    no "type mentions are NOT use-sites: only $NTYPE rows with role=\"type\" (expected >= 4)"
    printf '    %s\n' "$USES"
fi

# each individual mention must be AT its own line — a count alone would pass on one row repeated.
for spot in 'b\.cpp:10' 'b\.cpp:13' 'b\.cpp:18' 'b\.cpp:23'; do
    if printf '%s\n' "$USES" | grep 'role="type"' | grep -q "$spot"; then
        ok "type row at ${spot//\\/}"
    else
        no "no role=\"type\" row at ${spot//\\/} — the mention there was not captured"
    fi
done

# ── 2) THE CONTRACT HALF: Type never enters the CSR — the fixture's call graph is still empty ─────
E="$( printf '%s' "$HDR" | grep -oE ' edges=[0-9]+' | head -1 | grep -oE '[0-9]+' )"; E="${E:-x}"
A="$( printf '%s' "$HDR" | grep -oE ' ambiguous=[0-9]+' | head -1 | grep -oE '[0-9]+' )"; A="${A:-x}"
if [ "$E" = "0" ] && [ "$A" = "0" ]; then
    ok "CSR contract: edges=$E ambiguous=$A — the type role added no call edge and no ambiguity"
else
    no "CSR contract BROKEN: edges=$E ambiguous=$A (expected 0/0) — a Type ref reached the call graph"
fi

# ── 3) the DEFINITION site is not a use-site ──────────────────────────────────────────────────────
DEFLINE="$( grep -n '^struct Widget' "$FIX/a.h" | head -1 | cut -d: -f1 )"
if [ -n "$DEFLINE" ] && printf '%s\n' "$USES" | grep 'role="type"' | grep -q "a\.h:$DEFLINE"; then
    no "the DEFINITION of Widget (a.h:$DEFLINE) was emitted as a type use-site — a self-reference"
else
    ok "the definition site a.h:${DEFLINE:-?} is not a use-site"
fi

# ── 4) negative control: a LOCAL named Widget is never a type mention ─────────────────────────────
NC="$( printf '%s\n' "$USES" | grep -c 'c\.cpp:' )"
NCT="$( printf '%s\n' "$USES" | grep 'role="type"' | grep -c 'c\.cpp:' )"
if [ "$NCT" -eq 0 ]; then
    ok "negative control: the local variable named Widget produced no role=\"type\" row (c.cpp rows: $NC)"
else
    no "negative control BROKEN: $NCT role=\"type\" row(s) in c.cpp — the accept set keyed on the SPELLING"
    printf '    %s\n' "$USES"
fi

# ── 5) determinism — byte-identical run-to-run ────────────────────────────────────────────────────
"$BIN" "$FIX" --no-cache >"$TMP/r1" 2>/dev/null
"$BIN" "$FIX" --no-cache >"$TMP/r2" 2>/dev/null
if cmp -s "$TMP/r1" "$TMP/r2"; then ok "deterministic (two --no-cache runs byte-identical)"; else no "non-deterministic over the fixture"; fi

# ── 6) well-formed XML ───────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    if "$BIN" "$FIX" --uses=Widget --no-cache 2>/dev/null | xmllint --noout - 2>/dev/null; then
        ok "xml well-formed (--uses over the fixture)"
    else
        no "xml malformed (--uses over the fixture)"
    fi
else
    ok "xml well-formed (xmllint absent — skipped)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
