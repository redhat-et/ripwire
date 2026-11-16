#!/usr/bin/env bash
# bundledemotecheck.sh — NOSKIP-BUNDLE-DEMOTE: a bundle's copy of a source definition must not outrank the source.
#
# NO-SKIP-INGEST indexes every tracked file, so a build output that concatenates the sources (TypeScript's lib/_tsc.js,
# 6 MB; skipped by the old 4 MiB --max-file-size default) is now parsed in full. Its copies of the compiler's functions
# then took the head of --for: a named identifier lifted at most two of its files, in file order, and lib/ sorts before
# src/. The rule (model.h kRankFlagBundleCopy, set at load by ingest_model.h markBundleCopies): a code definition in a
# bundle-shaped file (read lexically, or parsed at 4 MiB or more) whose name a non-bundle file also defines is a COPY.
# It takes the generated tier factor (filter.h), is no mention lift or ambiguity vote (mention.h) and no source-class
# anchor (subjectanchor.h), no second path endpoint (pathgaps.h, forgraphverb.h) and no second function to the callers verb or its hop
# (callhierarchy.h, forcallerhop.h).
# Demoted, never dropped: --defs still lists it, and a name defined only in a bundle is no copy. A source is a definition with a
# body: a prototype in a normal file makes no copy of the bundle's only body (arm (h); ingest_model.h isBundleCopySource).
# Every fixture is generated here (nothing large is committed where whole-repo runs would see it); each arm counts its
# premise and FAILS on zero.
#
#   bash test/bundledemotecheck.sh [BIN]          # lane no-skip-ingest ff0664260 FAILS arm (a); 506afce6f FAILS (h1) (h2)
#   BASE_BIN=<binary before the rule> bash test/bundledemotecheck.sh BIN   # adds arm (c2): no bundle, byte-identical output

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
# The 3-5 MiB fixtures sit far under their parse budget, which counts parser steps, not seconds (PARSE-BUDGET-DETERMINISTIC):
# a loaded machine cannot push them into a lexical read, so no RIPWIRE_PARSE_BUDGET scale is needed here.
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
            "function transformWidgets2(nodes, ctx) {\n    return nodes.map(function (n) { return visitWidget(n, ctx); });\n}\n\n"
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

# ── (d) a path question binds the SOURCE endpoint: the bundle's copy is no second endpoint (forgraphverb.h) ─────────
FOR_P="--for=what is the path from emitWidgets to $F?"
"$BIN" "$TMP/big" --no-cache "$FOR_P" --legend=compact >"$TMP/d.out" 2>/dev/null   # status: as above
gv="$( grep -oE '<!-- [^>]*--><graph_verb [^>]*>|<graph_verb [^>]*>' "$TMP/d.out" | grep -oE '<graph_verb [^>]*>' | head -1 )"
dverb="$( printf '%s' "$gv" | grep -oE ' verb="[^"]*"' | head -1 )"
dbun="$( tr '\n' ' ' <"$TMP/d.out" | grep -oE '<graph_verb .*</graph_verb>' | grep -o 'lib/bundle.js' | grep -c . )"
if [ -n "$gv" ] && printf '%s' "$gv" | grep -q " narrowed=\"$F\"" && printf '%s' "$dverb" | grep -q "src/compiler/transformer.ts:$F" && [ "${dbun:-0}" = 0 ]; then
    ok "(d) the path block binds the source endpoint ($dverb), narrowed=\"$F\", no bundle row in the block"
else
    no "(d) path block: ${gv:-no <graph_verb>} | bundle lines in block: ${dbun:-?}"
fi
# ── (e) the caller hop of a name-exact answer serves the source function's callers (forcallerhop.h) ─────────────────
"$BIN" "$TMP/big" --no-cache "--for=$F" --legend=compact >"$TMP/e.out" 2>/dev/null   # status: as above
ehop="$( grep -oE '<callers [^>]*>' "$TMP/e.out" | grep " of=\"$F\"" | head -1 )"
erow="$( grep -oE "<callers [^>]*of=\"$F\"[^>]*>(<s [^>]*>)*" "$TMP/e.out" | grep -o 'n="emitWidgets"' | grep -c . )"
if [ -n "$ehop" ] && [ "${erow:-0}" -ge 1 ]; then ok "(e) --for=$F carries the caller hop with the source caller emitWidgets"; else no "(e) caller hop: ${ehop:-absent}, emitWidgets rows ${erow:-0}"; fi

# ── (f) --callers unions the source function only; the copy's own file still selects the copy (callhierarchy.h) ────────
"$BIN" "$TMP/big" --no-cache "--callers=$F" --legend=compact >"$TMP/f.out" 2>/dev/null   # status: as above
"$BIN" "$TMP/big" --no-cache "--callers=lib/bundle.js:$F" --legend=compact >"$TMP/f2.out" 2>/dev/null   # status: as above
fdefs="$( grep -oE '<callers [^>]*>' "$TMP/f.out" | grep -oE ' defs="[0-9]+"' | head -1 )"
fbun="$( grep -oE '<s [^>]*>' "$TMP/f.out" | grep -c 'lib/bundle.js' )"
femit="$( grep -oE '<s [^>]*>' "$TMP/f.out" | grep -c 'n="emitWidgets"' )"
f2bun="$( grep -oE '<s [^>]*>' "$TMP/f2.out" | grep -c 'lib/bundle.js' )"
if [ "$fdefs" = ' defs="1"' ] && [ "${fbun:-0}" = 0 ] && [ "${femit:-0}" -ge 1 ] && [ "${f2bun:-0}" -ge 1 ]; then
    ok "(f) --callers=$F unions the source only (emitWidgets, no bundle row); --callers=lib/bundle.js:$F still lists the bundle's $f2bun"
else
    no "(f) --callers=$F:${fdefs:- no defs=} bundle rows ${fbun:-?} emitWidgets ${femit:-?}; file-qualified bundle rows ${f2bun:-?}"
fi

# ── (g) a bundler's numeric rename (esbuild: transformWidgets -> transformWidgets2) is a copy too (ingest_model.h bundleRenameBase) ─
# read from the ranker's own row dump (forrowfeatures.h RIPWIRE_ROW_FEATURES, the answer unchanged): the renamed copy takes the tier
# factor the exact copy takes, on the plain-word task of (a2) (a task that SPELLS the renamed name still finds it, as any other)
RIPWIRE_ROW_FEATURES="$TMP/g.tsv" "$BIN" "$TMP/big" --no-cache "--for=transform widgets nodes visit" --legend=compact >/dev/null 2>&1   # status: the dump below is the verdict
gtier(){ awk -F'\t' -v n="$1" 'NR == 2 { for( i = 1; i <= NF; ++i ) { c[$i] = i } } NR > 2 && $c["name"] == n && $c["file"] == "lib/bundle.js" { print $c["tier"]; exit }' "$TMP/g.tsv" 2>/dev/null; }
gren="$( gtier "${F}2" )"; gcopy="$( gtier "$F" )"
if [ -n "$gren" ] && [ -n "$gcopy" ] && [ "$gren" = "$gcopy" ] && [ "$gren" != 1 ]; then
    ok "(g) the renamed copy ${F}2 takes the exact copy's tier factor ($gren)"
else
    no "(g) tier factor: renamed ${F}2 ${gren:-absent}, exact copy ${gcopy:-absent} (want equal and below 1)"
fi

# ── (h) a PROTOTYPE is no source: the bundle's body of a name a normal file only declares is kept (ingest_model.h isBundleCopySource) ─
# NOSKIP-FIX: api.c declares `int widget_step(int x);` and calls it; the only BODY is in the bundle-shaped amalg.c. The prototype made
# that body a "copy", --callees dropped it beside the bodyless prototype and answered count="0" (noskipingestcheck arm 1, red on
# no-skip-ingest 506afce6f). Both bundle shapes: (h1) read lexically (over --max-file-size), (h2) parsed at 4 MiB or more.
python3 - "$TMP" <<'EOF'
import os, sys
t = sys.argv[1]
def w(p, s):
    os.makedirs(os.path.dirname(p), exist_ok=True); open(p, "w").write(s)
head = "int widget_step(int x)\n{\n    return leaf_work(x) + 1;\n}\n\nint leaf_work(int x)\n{\n    return x * 2;\n}\n\n"
for tree, limit in (("protolex", 64 * 1024), ("protobig", 4 * 1024 * 1024 + 4096)):
    parts, n, i = [head], len(head), 0
    while n < limit:
        f = f"int amalg_{i}(int x)\n{{\n    return x + {i};\n}}\n\n"
        parts.append(f); n += len(f); i += 1
    w(f"{t}/{tree}/amalg.c", "".join(parts))
    w(f"{t}/{tree}/api.c", "int widget_step(int x);\nint main(void)\n{\n    return widget_step(3);\n}\n")
EOF
for h in "h1 protolex --max-file-size=16K" "h2 protobig"; do
    set -- $h; arm="$1"; tree="$2"; shift 2
    "$BIN" "$TMP/$tree" --no-cache "$@" --callees=widget_step --legend=compact >"$TMP/$arm.out" 2>/dev/null   # status: --callees exits 0 on any corpus; the rows read below are the verdict
    "$BIN" "$TMP/$tree" --no-cache "$@" --defs=widget_step --legend=compact >"$TMP/$arm.defs" 2>/dev/null   # status: as above
    hdefs="$( defsfiles "$TMP/$arm.defs" widget_step | paste -sd' ' - )"
    hroot="$( grep -oE '<callees [^>]*>' "$TMP/$arm.out" | head -1 )"
    hleaf="$( grep -oE '<s [^>]*>' "$TMP/$arm.out" | grep -c 'n="leaf_work"' )"
    if [ "$hdefs" = "amalg.c api.c" ] && printf '%s' "$hroot" | grep -q ' defs="2"' && [ "${hleaf:-0}" -ge 1 ]; then
        ok "($arm) prototype in api.c, body in the bundle-shaped amalg.c (${*:-parsed at 4 MiB}): --callees=widget_step keeps the body (defs=2) and finds leaf_work"
    else
        no "($arm) --defs=widget_step [$hdefs]; ${hroot:-no <callees>}; leaf_work rows ${hleaf:-0}"
    fi
done

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
