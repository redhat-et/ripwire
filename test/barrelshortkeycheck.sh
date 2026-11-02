#!/usr/bin/env bash
# barrelshortkeycheck.sh — lane barrel-short-key: (A) the barrel chain on a --for answer's <reexports> (src/forreexport.h): TS/JS
# NAMESPACE hops and the QUALIFIER RULE; (B) SHORT-KEY-FOR, the <shortkey> fallback ladder of a name-exact route that resolved no
# definition (src/forreexport.h renderShortKeyFallback, called from src/verbs_for.h).
#
# Before the lane: `import * as X from './m'; export { X }` and `export * as X from './m'` were never rows, a dotted subject
# (`X.leaf`) got no block without a cue word and, when cued, printed every same-named definition (a decoy first when its chain was
# longer); a name-exact route with no definition printed reason="no_candidates", an empty <sigs> and no next=.
#
# Fixtures are built at runtime (never under a .gitignored path). Arms:
#   A1  `Scope.leaf`: the def under the namespace is printed with q="Scope", the namespace hop src/barrel.ts (import * as Scope +
#       export { Scope }) is the FIRST rx row, the star hop src/index.ts follows; the same-named decoy src/other/decoy.ts is NOT listed.
#   A2  `NS.leaf`: `export * as NS from` is a row ns="NS", printed first (path to the qualifier before the rest of the walk).
#   A3  `Outer.leaf`: `import * as Inner` + `export { Inner as Outer }` publishes ns="Outer"; `Inner.leaf` proves nothing: no block.
#   A4  sibling shapes that are NOT namespace hops: `import * as Hidden` with no local export, and `export { Mixed } from './other'`
#       beside a local `import * as Mixed` (a re-export of another module, not of the namespace import): neither is an ns= row.
#   A5  `Wrong.leaf` (no proof of the qualifier) and `this.leaf` (a member access, not a qualifier): no block. Positive twin: A1.
#   A6  JS: `import * as JS from './lib.js'; export { JS }` in .js files: ns="JS".
#   A7  a bare subject (`Widget`, the whole task) prints its chain with no cue word; an uncued multi-word task does not (N3 holds).
#   A8  a file-stem qualifier (`m.leaf` for src/lib/m.ts) is proven at the definition's own file.
#   B1  `Utils.formatDate` (7 same-leaf defs: the route declines and serves none): rungs="leaf", exact="1", q_by="ns", the body of
#       src/utils/date.ts:1, next="--expand=…"; the decoys are not exact and src/legacy/old.ts is not in the block.
#   B2  `Wrong.formatDate`: q_unmatched="1" exact="0" (the same-leaf rows, hedged), never exact="1"; next="--defs=formatDate".
#   B3  `Fmt3.formatDate`: a TS method (no stored owner scope) proven by the class's line span: kept="1" q_by="scope" fmt3.ts.
#   B4  `Utils.parseInput`: two definitions both published under Utils: kept="2" cands="2" exact="0" (hedged, never exact).
#   B5  C++ `WidgetPtr` (a `using` alias the index does not store): substring row getWidgetPtrCount, literal row shape="using"
#       cpp/fwd.h:4; a commented-out `// using WidgetPtr = …` line is never a row; next="--grep=WidgetPtr". `GadgetRef`: shape="typedef".
#   B6  Rust `ExprKind` (`use … as ExprKind`): literal row shape="import-as".
#   B7  a CONST-shaped key with no definition: the literal rung says held="lit" (the <lit> block lists it), no ld rows.
#   B8  every <shortkey> carries next=; a resolved name-exact route (`getWidgetPtrCount`) prints no <shortkey> (absence twin of B5).
#   B9  --token-budget: <shortkey held="budget"> with next=, no rungs; --json: no block; RIPWIRE_NO_SHORT_KEY=1 removes exactly the block.
# Every arm reads an answer whose run exited 0 and printed a <ctx root: a crash or an empty answer is a FAIL, never an absence pass.
#
# Usage: bash test/barrelshortkeycheck.sh [BIN]     (default build/ripwire; exits non-zero on any failure)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "FAIL: no binary at $BIN"; exit 1; }
echo "barrelshortkeycheck: $( "$BIN" --version 2>/dev/null )"

# ── fixture W: the barrel chain (TS + JS) ───────────────────────────────────────────────────────────────────────────────────────
W="$TMP/w"; mkdir -p "$W/src/lib" "$W/src/other" "$W/js"
printf 'export function leaf(a: number): number {\n  return a + 1;\n}\nexport function other(): number {\n  return 2;\n}\n' >"$W/src/lib/m.ts"
printf 'export function leaf(b: string): string {\n  return b;\n}\n' >"$W/src/other/decoy.ts"
printf 'import * as Scope from "./lib/m";\nexport { Scope };\n' >"$W/src/barrel.ts"
printf 'export * from "./barrel";\n' >"$W/src/index.ts"
printf 'export * as NS from "./lib/m";\n' >"$W/src/ns.ts"
printf 'import * as Inner from "./lib/m";\nexport { Inner as Outer };\n' >"$W/src/renamed.ts"
printf 'import * as Hidden from "./lib/m";\nexport const hiddenLeaf = Hidden.leaf;\n' >"$W/src/noexport.ts"
printf 'import * as Mixed from "./lib/m";\nexport { Mixed } from "./other/decoy";\nexport const mixedLeaf = Mixed.leaf;\n' >"$W/src/fromother.ts"
printf 'export class Widget {\n  run(): number {\n    return 1;\n  }\n}\n' >"$W/src/other/widget.ts"
printf 'export { Widget } from "./other/widget";\n' >"$W/src/widgets.ts"
printf 'export function jleaf(n) {\n  return n;\n}\n' >"$W/js/lib.js"
printf 'import * as JS from "./lib.js";\nexport { JS };\n' >"$W/js/b.js"

# run ROOT OUT ARGS…: the answer, its exit code checked; a crash or an answer with no <ctx root fails the arm that reads it
run(){
    local root="$1" out="$2"; shift 2
    ( cd "$root" || exit 1; HOME="$TMP" "$BIN" "$root" --no-cache "$@" </dev/null 2>"$out.err" ) >"$out"
    local rc=$?
    if [ "$rc" -ne 0 ] || ! grep -q '<ctx \|"schema"' "$out"; then no "run $* exited $rc or printed no answer"; return 1; fi
    return 0
}
rx(){ grep -o '<reexports>.*</reexports>' "$1" | sed 's/<!--[^>]*-->//'; }
has(){ if rx "$1" | grep -qF -- "$3"; then ok "$2"; else no "$2 (missing: $3)"; fi; }
hasnt(){ if rx "$1" | grep -qF -- "$3"; then no "$2 (present: $3)"; else ok "$2"; fi; }
noblock(){ if grep -q '<reexports>' "$1"; then no "$2 (a <reexports> block printed)"; else ok "$2"; fi; }

run "$W" "$TMP/a1.xml" "--for=Scope.leaf" && {
has   "$TMP/a1.xml" "A1 def under the namespace, q=Scope"  '<def n="leaf" p="src/lib/m.ts" l="1" q="Scope"'
has   "$TMP/a1.xml" "A1 namespace hop barrel.ts is the first row" 'total="4"/><rx p="src/barrel.ts" l="1" from="./lib/m" ns="Scope"/>'
has   "$TMP/a1.xml" "A1 star hop index.ts follows"         '<rx p="src/index.ts" l="1" from="./barrel" glob="1"/>'
hasnt "$TMP/a1.xml" "A1 same-named decoy not listed"       'src/other/decoy.ts'
hasnt "$TMP/a1.xml" "A4 import * as Hidden with no export is no ns row" 'ns="Hidden"'
hasnt "$TMP/a1.xml" "A4 export { Mixed } from another module is no ns row" 'ns="Mixed"'
}
run "$W" "$TMP/a2.xml" "--for=NS.leaf" && \
has   "$TMP/a2.xml" "A2 export * as NS from: ns row first" 'q="NS" total="4"/><rx p="src/ns.ts" l="1" from="./lib/m" ns="NS"/>'
run "$W" "$TMP/a3.xml" "--for=Outer.leaf" && \
has   "$TMP/a3.xml" "A3 export { Inner as Outer }: ns=Outer" '<rx p="src/renamed.ts" l="1" from="./lib/m" ns="Outer"/>'
run "$W" "$TMP/a3b.xml" "--for=Inner.leaf" && noblock "$TMP/a3b.xml" "A3 the unexported local name proves nothing"
run "$W" "$TMP/a5.xml" "--for=Wrong.leaf" && noblock "$TMP/a5.xml" "A5 unproven qualifier: no block"
run "$W" "$TMP/a5b.xml" "--for=this.leaf" && noblock "$TMP/a5b.xml" "A5 this.leaf is a member access: no block"
run "$W" "$TMP/a6.xml" "--for=JS.jleaf" && \
has   "$TMP/a6.xml" "A6 JS namespace hop"                  '<rx p="js/b.js" l="1" from="./lib.js" ns="JS"/>'
run "$W" "$TMP/a7.xml" "--for=Widget" && \
has   "$TMP/a7.xml" "A7 bare subject prints its chain"     '<rx p="src/widgets.ts" l="1" from="./other/widget"/>'
run "$W" "$TMP/a7b.xml" "--for=Widget internals explained" && noblock "$TMP/a7b.xml" "A7 uncued multi-word task: no block"
run "$W" "$TMP/a8.xml" "--for=m.leaf" && \
has   "$TMP/a8.xml" "A8 file-stem qualifier proven at the def's file" '<def n="leaf" p="src/lib/m.ts" l="1" q="m"'

# ── fixture S: SHORT-KEY-FOR ────────────────────────────────────────────────────────────────────────────────────────────────────
S="$TMP/s"; mkdir -p "$S/src/utils" "$S/src/legacy" "$S/cpp" "$S/rs/src"
printf 'export function formatDate(d: number): string {\n  return String(d);\n}\nexport function parseInput(s: string): number {\n  return Number(s);\n}\n' >"$S/src/utils/date.ts"
printf 'export function parseInput(s: string): string {\n  return s.trim();\n}\n' >"$S/src/utils/text.ts"
printf 'export * from "./date";\nexport * from "./text";\n' >"$S/src/utils/all.ts"
printf 'import * as Utils from "./utils/all";\nexport { Utils };\n' >"$S/src/index.ts"
printf 'export function formatDate(x: string): string {\n  return x;\n}\n' >"$S/src/legacy/old.ts"
for i in 1 2 3 4 5; do
    printf 'export class Fmt%s {\n  formatDate(v: number): string {\n    return "x" + v;\n  }\n  parseInput(v: string): string {\n    return v;\n  }\n}\n' "$i" >"$S/src/legacy/fmt$i.ts"
done
printf '#pragma once\ntemplate <class T> struct Ptr { T* p; };\nstruct Widget { int n; };\nusing WidgetPtr = Ptr<Widget>;\nint getWidgetPtrCount();\ntypedef Ptr<Widget> GadgetRef;\n// using WidgetPtr = OldPtr<Widget>;\nint useLimit() { return clamp(MAX_WIDGET_COUNT); }\n' >"$S/cpp/fwd.h"
printf '#include "fwd.h"\nint getWidgetPtrCount() { return 1; }\n' >"$S/cpp/fwd.cpp"
printf '[package]\nname = "rs"\nversion = "0.1.0"\n' >"$S/rs/Cargo.toml"
printf 'pub mod pb { pub enum Kind { A } }\nuse crate::pb::Kind as ExprKind;\npub fn f(_k: ExprKind) {}\n' >"$S/rs/src/lib.rs"

sk(){ python3 -c 'import re,sys; s=open(sys.argv[1]).read(); i=s.find("<shortkey "); print(re.sub(r"<!--.*?-->","",s[i:],flags=re.S) if i>=0 else "")' "$1"; }
skhas(){ if sk "$1" | grep -qF -- "$3"; then ok "$2"; else no "$2 (missing: $3)"; fi; }
skhasnt(){ if sk "$1" | grep -qF -- "$3"; then no "$2 (present: $3)"; else ok "$2"; fi; }

run "$S" "$TMP/b1.xml" "--for=Utils.formatDate" && {
skhas   "$TMP/b1.xml" "B1 leaf rung exact, proven by the namespace" '<rung n="leaf" key="formatDate" q="Utils" kept="1" of="7" exact="1"><d n="formatDate" t="fn" p="src/utils/date.ts" l="1" q_by="ns"/></rung>'
skhas   "$TMP/b1.xml" "B1 the exact leaf's body is printed"       '<b t="fn" l="1" p="src/utils/date.ts" n="formatDate">'
skhas   "$TMP/b1.xml" "B1 next= expands it, the ladder stops"     'rungs="leaf" next="--expand=src/utils/date.ts:1:formatDate"'
skhasnt "$TMP/b1.xml" "B1 the decoy is not in the block"          'src/legacy/old.ts'
}
run "$S" "$TMP/b2.xml" "--for=Wrong.formatDate" && {
skhas   "$TMP/b2.xml" "B2 unproven qualifier: q_unmatched, exact=0" 'kept="0" of="7" exact="0" q_unmatched="1">'
skhasnt "$TMP/b2.xml" "B2 never exact"                             'exact="1"'
skhas   "$TMP/b2.xml" "B2 next= lists the leaf's definitions"      'next="--defs=formatDate"'
}
run "$S" "$TMP/b3.xml" "--for=Fmt3.formatDate" && \
skhas   "$TMP/b3.xml" "B3 method proven by its class's line span"  'kept="1" of="7" exact="1"><d n="formatDate" t="method" p="src/legacy/fmt3.ts" l="2" q_by="scope"/>'
run "$S" "$TMP/b4.xml" "--for=Utils.parseInput" && {
skhas   "$TMP/b4.xml" "B4 two proven: hedged cands=2"               'kept="2" of="7" exact="0" cands="2">'
skhasnt "$TMP/b4.xml" "B4 never exact"                              'exact="1"'
}
run "$S" "$TMP/b5.xml" "--for=WidgetPtr" && {
skhas   "$TMP/b5.xml" "B5 substring rung"                           '<d n="getWidgetPtrCount" t="fn" p="cpp/fwd.cpp" l="2"/>'
skhas   "$TMP/b5.xml" "B5 literal using row"                        '<ld p="cpp/fwd.h" l="4" shape="using"><![CDATA[using WidgetPtr = Ptr<Widget>;]]></ld>'
skhasnt "$TMP/b5.xml" "B5 a commented-out declaration is no row"    'l="7"'
skhas   "$TMP/b5.xml" "B5 next= greps the key"                      'next="--grep=WidgetPtr"'
}
run "$S" "$TMP/b5b.xml" "--for=GadgetRef" && skhas "$TMP/b5b.xml" "B5 typedef shape" '<ld p="cpp/fwd.h" l="6" shape="typedef">'
run "$S" "$TMP/b6.xml" "--for=ExprKind" && skhas "$TMP/b6.xml" "B6 Rust use … as row" '<ld p="rs/src/lib.rs" l="2" shape="import-as">'
run "$S" "$TMP/b7.xml" "--for=MAX_WIDGET_COUNT" && {
skhas   "$TMP/b7.xml" "B7 CONST key: literal rung held=lit"         '<rung n="literal" key="MAX_WIDGET_COUNT" held="lit" exact="0"/>'
skhasnt "$TMP/b7.xml" "B7 no ld rows of its own"                    '<ld '
}
nsk=0; nnext=0
for f in "$TMP"/b*.xml; do
    c=$( grep -c '<shortkey of=' "$f" ); nsk=$(( nsk + c ))
    n=$( grep -o '<shortkey of="[^"]*" found="0" rungs="[^"]*" next="--' "$f" | wc -l | tr -d ' ' ); nnext=$(( nnext + n ))
done
if [ "$nsk" -ge 8 ] && [ "$nsk" = "$nnext" ]; then ok "B8 every shortkey carries next= ($nnext of $nsk)"; else no "B8 shortkeys with next= $nnext of $nsk (want all, at least 8)"; fi
run "$S" "$TMP/b8.xml" "--for=getWidgetPtrCount" && { if grep -q '<shortkey' "$TMP/b8.xml"; then no "B8 a resolved name-exact route prints no shortkey"; else ok "B8 a resolved name-exact route prints no shortkey"; fi; }
run "$S" "$TMP/b9.xml" "--for=WidgetPtr" --token-budget=2000 && {
if grep -q '<shortkey held="budget" of="WidgetPtr" next="--for=WidgetPtr"/>' "$TMP/b9.xml" && ! grep -q '<rung ' "$TMP/b9.xml"; then ok "B9 token budget: held marker, no rungs"; else no "B9 token budget: held marker, no rungs"; fi
}
run "$S" "$TMP/b9.json" --json "--for=WidgetPtr" && { if grep -q 'shortkey' "$TMP/b9.json"; then no "B9 --json carries no block"; else ok "B9 --json carries no block"; fi; }
( cd "$S" || exit 1; RIPWIRE_NO_SHORT_KEY=1 HOME="$TMP" "$BIN" "$S" --no-cache "--for=WidgetPtr" </dev/null 2>/dev/null ) >"$TMP/b9off.xml"
python3 - "$TMP/b5.xml" "$TMP/b9off.xml" <<'PY' && ok "B9 the off switch removes exactly the block" || no "B9 the off switch changed more than the block"
import re, sys
on, off = (open(p).read() for p in sys.argv[1:3])
strip = lambda s: re.sub(r' (at|est_tokens)="[^"]*"', '', s)
i = on.find('<!-- shortkey:'); j = on.find('</shortkey>')
sys.exit(0 if i > 0 and j > i and strip(on[:i] + on[j + len('</shortkey>'):]) == strip(off) else 1)
PY

if [ "$fail" = 0 ]; then echo "barrelshortkeycheck: PASS"; else echo "barrelshortkeycheck: FAIL"; fi
exit "$fail"
