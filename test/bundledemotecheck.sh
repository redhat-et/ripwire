#!/usr/bin/env bash
# bundledemotecheck.sh — NOSKIP-BUNDLE-DEMOTE: a bundle's copy of a source definition must not outrank the source.
#
# NO-SKIP-INGEST indexes every tracked file, so a build output that concatenates the sources (TypeScript's lib/_tsc.js,
# 6 MB; skipped by the old 4 MiB --max-file-size default) is now parsed in full. Its copies of the compiler's functions
# then took the head of --for: a named identifier lifted at most two of its files, in file order, and lib/ sorts before
# src/. The rule (model.h kRankFlagBundleCopy, set at load by ingest_model.h markBundleCopies): a code definition in a
# bundle-shaped file (read lexically, or parsed at 4 MiB or more) whose name a non-bundle file also defines is a COPY.
# It takes the generated tier factor (filter.h), is no mention lift or ambiguity vote (mention.h) and no source-class
# anchor (subjectanchor.h). Demoted, never dropped: --defs still lists it, and a name defined only in a bundle is no copy.
# Every fixture is generated here (nothing large is committed where whole-repo runs would see it); each arm counts its
# premise and FAILS on zero.
#
#   bash test/bundledemotecheck.sh [BIN]          # lane no-skip-ingest ff0664260 FAILS arm (a)
#   BASE_BIN=<binary before the rule> bash test/bundledemotecheck.sh BIN   # adds arm (c2): no bundle, byte-identical output

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
# A loaded machine must not push the 3-5 MiB fixtures past their parse budget (a lexical read is bundle-shaped by itself, so
# arm (c) would see a demotion and (c2) a stderr warning): the budget scale is raised well past any measured parse time.
export RIPWIRE_PARSE_BUDGET=20
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "bundledemotecheck: BIN=$BIN"

# ── fixtures, generated here ────────────────────────────────────────────────────────────────────────────────────────
# big/: src/compiler/transformer.ts defines transformWidgets (F), src/compiler/emitter.ts calls it; lib/bundle.js (5 MiB of
#       ordinary functions) carries its own copy of F, called from inside the bundle, and bundleOnlyHelper (G), defined nowhere
#       else. under/: the same tree with the bundle cut to 3 MiB — below the bundle shape, so nothing is demoted.
python3 - "$TMP" <<'EOF'
import os, sys
t = sys.argv[1]
def w(p, s):
    os.makedirs(os.path.dirname(p), exist_ok=True); open(p, "w").write(s)
def bundle(limit):
    head = ("function transformWidgets(nodes, ctx) {\n    return nodes.map(function (n) { return visitWidget(n, ctx); });\n}\n\n"
            "function bundleOnlyHelper(table, key) {\n    return table[key] === undefined ? null : table[key];\n}\n\n")
    parts, n, i = [head], len(head), 0
    while n < limit:
        f = f"function filler_{i}(x) {{\n    var r = transformWidgets([x], {i});\n    return bundleOnlyHelper(r, {i});\n}}\n\n"
        parts.append(f); n += len(f); i += 1
    return "".join(parts)
src = {
    "src/compiler/transformer.ts": "export function transformWidgets(nodes: Widget[], ctx: Context): Widget[] {\n    return nodes.map(n => visitWidget(n, ctx));\n}\n\n"
                                   "export function visitWidget(n: Widget, ctx: Context): Widget {\n    return ctx.visit(n);\n}\n",
    "src/compiler/emitter.ts": "import { transformWidgets } from './transformer';\n\nexport function emitWidgets(ws: Widget[], ctx: Context): void {\n"
                               "    const out = transformWidgets(ws, ctx);\n    ctx.write(out);\n}\n",
    "src/compiler/types.ts": "export interface Widget { kind: number; }\nexport interface Context { visit(n: Widget): Widget; write(ws: Widget[]): void; }\n",
}
for tree, limit in (("big", 5 * 1024 * 1024), ("under", 3 * 1024 * 1024)):
    for rel, body in src.items():
        w(f"{t}/{tree}/{rel}", body)
    w(f"{t}/{tree}/lib/bundle.js", bundle(limit))
EOF

# The <d> rows of a --for answer, in output order, as "path n=name" lines.
drows(){ grep -oE '<d [^>]*>' "$1" | awk '{ p = "?"; n = "?"; if( match( $0, / p="[^"]*"/ ) ) p = substr( $0, RSTART + 4, RLENGTH - 5 ); if( match( $0, / n="[^"]*"/ ) ) n = substr( $0, RSTART + 4, RLENGTH - 5 ); print p " n=" n }'; }
firstrow(){ drows "$1" | grep -n " n=$2\$" | head -1; }   # "N:path n=name" — the first row naming it, and its position
defsfiles(){ tr '>' '\n' <"$1" | grep -oE '<d n="'"$2"'" [^/]* p="[^":]*' | sed -E 's/.* p="//' | sort; }
F='transformWidgets'; G='bundleOnlyHelper'
FOR_F="--for=what calls $F and would need updating if its signature grew?"
FOR_G="--for=where is $G defined and what does it return?"

# ── premise: the bundle is indexed and holds both copies ────────────────────────────────────────────────────────────
"$BIN" "$TMP/big" --no-cache --defs=$F --legend=compact >"$TMP/p.F" 2>/dev/null   # status: --defs exits 0 on any corpus; the rows read below are the verdict, and a missing one FAILs
"$BIN" "$TMP/big" --no-cache --defs=$G --legend=compact >"$TMP/p.G" 2>/dev/null   # status: as above
pf="$( defsfiles "$TMP/p.F" $F | paste -sd' ' - )"; pg="$( defsfiles "$TMP/p.G" $G | paste -sd' ' - )"
if [ "$pf" = "lib/bundle.js src/compiler/transformer.ts" ]; then ok "premise: --defs=$F lists both copies ($pf)"; else no "premise: --defs=$F lists [$pf], want the bundle's and the source's"; fi
if [ "$pg" = "lib/bundle.js" ]; then ok "premise: --defs=$G lists its sole definition, in the bundle"; else no "premise: --defs=$G lists [$pg], want lib/bundle.js only"; fi

# ── (a) F in the source and in a 5 MiB bundle: the source copy ranks first ─────────────────────────────────────────
"$BIN" "$TMP/big" --no-cache "$FOR_F" --legend=compact >"$TMP/a.out" 2>/dev/null   # status: --for exits 0 on any corpus; the rows read below are the verdict
na="$( drows "$TMP/a.out" | grep -c " n=$F\$" )"
src_at="$( drows "$TMP/a.out" | grep -n "^src/compiler/transformer.ts n=$F\$" | head -1 | cut -d: -f1 )"
bun_at="$( drows "$TMP/a.out" | grep -n "^lib/bundle.js n=$F\$" | head -1 | cut -d: -f1 )"
if [ "${na:-0}" -ge 1 ] && [ -n "$src_at" ] && { [ -z "$bun_at" ] || [ "$src_at" -lt "$bun_at" ]; }; then
    ok "(a) the source copy of $F ranks first: <d> row $src_at, the bundle's ${bun_at:-not shown} ($na rows name it)"
else
    no "(a) $F rows=${na:-0}: source at ${src_at:-absent}, bundle at ${bun_at:-absent}; first: $( firstrow "$TMP/a.out" $F )"
fi
# (a2) the lexical tier, without the name lift: a task that does not spell F still ranks the source copy above the bundle's
"$BIN" "$TMP/big" --no-cache "--for=transform widgets nodes visit" --legend=compact >"$TMP/a2.out" 2>/dev/null   # status: as above
src2="$( drows "$TMP/a2.out" | grep -n "^src/compiler/transformer.ts n=$F\$" | head -1 | cut -d: -f1 )"
bun2="$( drows "$TMP/a2.out" | grep -n "^lib/bundle.js n=$F\$" | head -1 | cut -d: -f1 )"
if [ -n "$src2" ] && { [ -z "$bun2" ] || [ "$src2" -lt "$bun2" ]; }; then
    ok "(a2) a plain-word task ranks the source copy first: row $src2, the bundle's ${bun2:-not shown}"
else
    no "(a2) plain-word task: source at ${src2:-absent}, bundle at ${bun2:-absent}"
fi

# ── (b) G only in the bundle: no copy, still found and lifted ──────────────────────────────────────────────────────
"$BIN" "$TMP/big" --no-cache "$FOR_G" --legend=compact >"$TMP/b.out" 2>/dev/null   # status: as above
gat="$( drows "$TMP/b.out" | grep -n "^lib/bundle.js n=$G\$" | head -1 | cut -d: -f1 )"
if [ "${gat:-0}" = 1 ]; then ok "(b) the sole definition of $G (bundle only) is still the head row"; else no "(b) $G at row ${gat:-absent}, want 1: $( drows "$TMP/b.out" | head -3 | paste -sd'|' - )"; fi

# ── (c) negative: a 3 MiB copy is no bundle — nothing is demoted, the file-order lift stands ─────────────────────────
"$BIN" "$TMP/under" --no-cache "$FOR_F" --legend=compact >"$TMP/c.out" 2>"$TMP/c.err"; crc=$?   # status: rc kept for (c2)
csrc="$( drows "$TMP/c.out" | grep -n "^src/compiler/transformer.ts n=$F\$" | head -1 | cut -d: -f1 )"
cbun="$( drows "$TMP/c.out" | grep -n "^lib/bundle.js n=$F\$" | head -1 | cut -d: -f1 )"
if [ -n "$csrc" ] && [ -n "$cbun" ] && [ "$cbun" -lt "$csrc" ]; then
    ok "(c) under the bundle shape both copies stay lifted in file order (lib row $cbun, src row $csrc): no demotion fired"
else
    no "(c) under the bundle shape: lib at ${cbun:-absent}, src at ${csrc:-absent} (want both, lib first as before the rule)"
fi
# (c2) with BASE_BIN: the same corpus answers byte for byte as the binary before the rule (stdout, stderr, rc)
if [ -n "${BASE_BIN:-}" ]; then
    "$BASE_BIN" "$TMP/under" --no-cache "$FOR_F" --legend=compact >"$TMP/c.base.out" 2>"$TMP/c.base.err"; brc=$?   # status: compared below
    if [ "$crc" = "$brc" ] && cmp -s "$TMP/c.out" "$TMP/c.base.out" && cmp -s "$TMP/c.err" "$TMP/c.base.err" && [ -s "$TMP/c.out" ]; then
        ok "(c2) no bundle: stdout ($( wc -c <"$TMP/c.out" | tr -d ' ' ) B), stderr and rc=$crc byte-identical to BASE_BIN"
    else
        no "(c2) no bundle: output differs from BASE_BIN (rc $crc vs $brc; stdout $( wc -c <"$TMP/c.out" | tr -d ' ' ) vs $( wc -c <"$TMP/c.base.out" | tr -d ' ' ) B; stderr: $( head -c 200 "$TMP/c.err" ) | $( head -c 200 "$TMP/c.base.err" ))"
    fi
else
    echo "  NOTE  (c2) skipped: set BASE_BIN to compare the no-bundle corpus byte for byte with the binary before the rule"
fi

if [ "$fail" = 0 ]; then echo "bundledemotecheck: ALL PASS"; exit 0; fi
echo "bundledemotecheck: FAILURES ABOVE"; exit 1
