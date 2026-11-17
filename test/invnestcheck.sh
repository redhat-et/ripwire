#!/usr/bin/env bash
# invnestcheck.sh — the map inventory tier's <ls> rows NESTED under synthesised <lsd p=> wrappers, item 1 of the
# five lossless encodings pre-registered in docs/EVALS.md ("five LOSSLESS encodings for the map", 2026-11-16).
#
# WHAT IS BEING ASSERTED, and why it needs a gate of its own. The encoding removes a repeated path prefix from
# every row it groups: `<ls p="skills/hermes" …/>` becomes `<lsd p="skills"><ls p="hermes" …/>…</lsd>`. The whole
# claim is that NO answer content moves — the registration's Band A is a SET IDENTITY, not a byte count, and
# says one row of changed content fails the band whatever the saving. A byte count cannot see that, so this
# gate reads the rows back out and compares them against an independent rendering of the same data.
#
# THE ORACLE, and why it does not rot. src/serialize.h has a JSON twin of the XML inventory writer
# (writeMapInventoryJson), and both render the SAME in-memory MapInventory::dirs. The JSON surface stays FLAT
# on purpose: it is not the token-budgeted agent surface, its consumers parse structurally rather than paying
# per byte, and keeping it flat leaves this gate a reference the change itself cannot alter. So the comparison
# is XML-flattened versus JSON, from ONE binary and ONE index — no second build, no pinned expected output,
# and nothing that goes vacuous once the change is on main. (A gate that diffed against a pre-change binary
# would prove nothing the day after it landed.)
#
# The arms:
#   (A0) the subject repo actually produces an <inv> tier with rows, and at least one <lsd> group — otherwise
#        every arm below passes by vacuity, which is the failure shape this project calls a silent zero.
#   (A1) Band A: the flattened XML row multiset equals the JSON "ls" array — same count, same p=, same n=,
#        same f= membership. The flattening re-joins each <ls> to its ancestors' p= segments.
#   (A2) control: the comparison can FAIL. Three planted mutations of the XML (a dropped row, a changed n=,
#        a dropped f= name) must each be detected, or (A1) is not evidence.
#   (B1) Band B: <lsd> and its p= have a row in src/compactlegend.h's DICTIONARY, not merely in the emitter —
#        the legend is generated from the dictionary, so an emitted-but-unregistered name ships undocumented.
#   (C1) every <lsd> group pays for itself in bytes, by the model the emitter uses; and the whole document is
#        no larger than the same rows flat. A group that costs more than it saves is a bug, not a trade.
#   (D1) Band D: the row ORDER is exactly the stated rule — the JSON order with each group's rows made
#        contiguous at the position of the group's first row. §9.1 allows a reordering; this pins WHICH one.
#   (E1) Band E: the depth is the named constant kInventoryNestDepth, it is 2, and no <lsd> nests deeper.
#   (E2) the constant is reachable from docs/LIMITS.md, as Band E requires of a shipped default.
#
# RED-FIRST: (A0) fails on main before the emitter change (no <lsd> group exists), and (A1) fails if the
# flattening is wrong in either direction. (A2) is what proves (A1) is not a tautology.
#
# Usage: test/invnestcheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
echo "invnestcheck: BIN=$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

[ -x "$BIN" ] || { no "(0) no binary at $BIN"; echo "invnestcheck: FAILURES"; exit 1; }

# THE SUBJECT IS A GENERATED FIXTURE, not a corpus and not this repository. Two reasons, both learned by
# trying the alternatives: this repository's own tree is too flat — its one qualifying prefix saves 115 B
# against a ~560 B legend clause, so the document-level threshold correctly refuses it and every arm below
# would have nothing to read; and a real corpus is not on a CI runner. The fixture is sized so that BOTH
# nesting levels fire and the saving clears the clause, which is what makes (A1)/(C1)/(C2)/(D1) evidence.
#
# Shape, tuned empirically so BOTH nesting levels fire and the tier is active at all:
#   aaa/m0..m219.ts        220 code files that CONSUME the map's shown-row budget (path-first on equal rank),
#                          so everything below is UNSHOWN and reaches the inventory. computeMapInventory
#                          returns an inactive tier unless some unshown file has code symbols, so without
#                          this the whole tier is absent and every arm reads nothing.
#   packages/plugins/p*/src   60 rows sharing TWO segments -> the depth-2 wrapper
#   packages/pkg*/src         60 rows sharing ONE           -> the depth-1 wrapper they both sit under
#   vendor/v0..v2             3 rows, a small group
#   alone/, solo/, aaa/       single rows that must NOT be wrapped
FIX="$TMP/fixture"
mkdir -p "$FIX/aaa" "$FIX/alone" "$FIX/solo"
i=0
while [ "$i" -lt 220 ]; do
    printf 'export function shownFn%s(): number { return %s; }\n' "$i" "$i" > "$FIX/aaa/m$i.ts"
    i=$(( i + 1 ))
done
i=0
while [ "$i" -lt 60 ]; do
    mkdir -p "$FIX/packages/plugins/p$i/src" "$FIX/packages/pkg$i/src"
    printf 'export function plugFn%s(): number { return %s; }\n' "$i" "$i" > "$FIX/packages/plugins/p$i/src/mod.ts"
    printf 'export function pkgFn%s(): number { return %s; }\n'  "$i" "$i" > "$FIX/packages/pkg$i/src/mod.ts"
    i=$(( i + 1 ))
done
i=0
while [ "$i" -lt 3 ]; do
    mkdir -p "$FIX/vendor/v$i"
    printf 'export function vFn%s(): number { return %s; }\n' "$i" "$i" > "$FIX/vendor/v$i/mod.ts"
    i=$(( i + 1 ))
done
printf 'export function aloneFn(): number { return 1; }\n' > "$FIX/alone/mod.ts"
printf 'export function soloFn(): number { return 2; }\n'  > "$FIX/solo/mod.ts"

"$BIN" "$FIX" > "$TMP/map.xml" 2>"$TMP/map.err"  || { no "(0) the default map failed on the fixture: $( head -2 "$TMP/map.err" )"; echo "invnestcheck: FAILURES"; exit 1; }
"$BIN" "$FIX" --json > "$TMP/map.json" 2>"$TMP/json.err" || { no "(0) the --json map failed on the fixture: $( head -2 "$TMP/json.err" )"; echo "invnestcheck: FAILURES"; exit 1; }

python3 "$ROOT/test/invnest_reader.py" "$TMP/map.xml" "$TMP/map.json" "$ROOT" > "$TMP/out.txt" 2>"$TMP/py.err"; pyRc=$?
cat "$TMP/out.txt"
if [ "$pyRc" != 0 ] && [ ! -s "$TMP/out.txt" ]; then
    no "(0) the reader itself failed, so no arm ran: $( head -3 "$TMP/py.err" )"
fi
grep -q '  FAIL' "$TMP/out.txt" && fail=1

# ── (B1) Band B: <lsd p=> is REGISTERED in the dictionary, not merely emitted ───────────────────────────
# src/compactlegend.h's table is what the legend is generated FROM, so an attribute the emitter writes with
# no row there ships undocumented and the compact dialect's generic *_capped fallback does not cover it.
# Asserted against the dictionary rows AND against the binary's own --legend-dict, because the first proves
# the row was written and the second proves the build picked it up.
DICT="$ROOT/src/compactlegend.h"
# KEYED ON THE OWNER ELEMENT, not on the attribute name. The dictionary already holds three unrelated rows
# named "d" (<s d=N>'s hop count, <ns d=>'s hop-back, <caveat d=>'s detail), each scoped by its owning
# element, so a bare `{ "d",` match passed on main before this encoding existed — a false green caught by
# running this arm red-first. The row this encoding owes is the one whose TEXT documents `<lsd p=` and whose
# OWNER field is the nesting element itself, which is the shape <ls>'s own row uses ( `{ "n", "<ls p= n= f=>…",
# true, "ls" }` ): the element is documented on an attribute row scoped to it.
if ! grep -qE '"<lsd p=' "$DICT"; then
    no "(B1) Band B: src/compactlegend.h has no dictionary row documenting <lsd p= — the nesting wrapper ships undocumented, because the legend is generated from this table and not from the emitter"
elif ! grep -E '"<lsd p=' "$DICT" | grep -qE ', *"lsd" *[,}]'; then
    no "(B1) Band B: a row mentions <lsd p= but none is SCOPED to the lsd element (owner field \"lsd\") — the dictionary is keyed on ( attribute, owning element ), and a p= row filed under any other owner documents a different element"
elif ! "$BIN" --legend-dict 2>/dev/null | grep -qF '<lsd p='; then
    no "(B1) Band B: the row is in src/compactlegend.h but this binary's --legend-dict does not print it — the build did not pick the row up"
else
    ok "(B1) Band B: <lsd p=> has a dictionary row in src/compactlegend.h and this binary's --legend-dict defines it"
fi

# ── (F1) the other side of the document-level threshold: a FLAT tree carries no wrapper AND no clause ──
# This repository is the flat subject: one prefix qualifies per-group (skills/, 20 rows, 115 B) and the
# document-level check refuses it against the ~560 B clause. Both halves are asserted, because a document
# that dropped the wrappers and kept the clause would be the same bug wearing the opposite shape.
"$BIN" "$ROOT" > "$TMP/flat.xml" 2>/dev/null
flatD="$( grep -oE '<lsd p="[^"]*">' "$TMP/flat.xml" | wc -l | tr -d ' ' )"
flatC="$( grep -cF '<!-- lsd p=SEG:' "$TMP/flat.xml" || true )"
if [ "$flatD" != 0 ]; then
    no "(F1) this repository's tree saves 115 B of rows against a ~560 B legend clause, so the document-level threshold should have emitted NO wrapper — it emitted $flatD"
elif [ "$flatC" != 0 ]; then
    no "(F1) no wrapper was emitted but the <lsd p=SEG> legend clause was charged anyway ($flatC time(s)) — the document pays for vocabulary it does not use"
else
    ok "(F1) a flat tree (this repository) carries neither a <lsd> wrapper nor its legend clause, so the encoding cannot make a document larger"
fi

[ "$fail" = 0 ] && echo "invnestcheck: ALL PASS" || echo "invnestcheck: FAILURES"
exit "$fail"
