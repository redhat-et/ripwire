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
#   A3  `Outer.leaf`: `import * as Inner` + `export { Inner as Outer }` publishes ns="Outer"; `Inner.leaf` is that file's own alias
#       only: a hedged proof, q_by="alias" (fix round 1; it printed no block before).
#   A4  sibling shapes that are NOT namespace hops: `import * as Hidden` with no local export, and `export { Mixed } from './other'`
#       beside a local `import * as Mixed` (a re-export of another module, not of the namespace import): neither is an ns= row.
#       `import * as Dflt` + `export default Dflt` is a JsExport record but not a local `export { }` clause (localExportClause):
#       no ns="default" row (fix round 1: the from-clause form is a ReExport record and never reaches that guard; this one does).
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
#       cpp/fwd.h:4; a commented-out `// using WidgetPtr = …` line is never a row; next="--grep=WidgetPtr". `GadgetRef` (a
#       function-pointer typedef; a plain `typedef T X;` is now an indexed definition): shape="typedef".
#   B6  Rust `ExprKind` (`use … as ExprKind`): literal row shape="import-as".
#   B7  a CONST-shaped key with no definition: the literal rung says held="lit" (the <lit> block lists it), no ld rows.
#   B8  every <shortkey> carries next=; a resolved name-exact route (`getWidgetPtrCount`) prints no <shortkey> (absence twin of B5).
#   B9  --token-budget: <shortkey held="budget"> with next=, no rungs; --json, --format=candidates: no block (a non-empty
#       answer); RIPWIRE_NO_SHORT_KEY=1 removes exactly the block.
#   C1  (fix round 1, MF1) a DIRECTORY on the path is a hedged proof, never exact: `utils.formatDate` with src/utils/legacy/old.ts
#       (the decoy) and src/helpers/date.ts reached by a consumer's `import * as utils from "../helpers"`: kept="2" exact="0",
#       q_by="alias" first, q_by="dir" second, no body. With the decoy alone: kept="1" exact="0" q_by="dir" (one hedged is no answer).
#   C2  every qualifier segment is proven: `Wrong.Fmt3.formatDate` and `Wrong::Fmt3::formatDate` (only the last segment is the owner)
#       are q_unmatched="1", never exact. Positive twin: B3.
#   C3  a consumer's own `import * as utils from '../helpers'` proves helpers for `utils.` (hedged, q_by="alias" on the def row).
#   C4  (MF2) a cued task whose qualifier nothing proves keeps every chain, q_unmatched="1"; a bare one keeps none (A5).
#   C5  the path's own tail (`legacy.old`, `utils.legacy`) and a package file (`src/utils/index.ts` for `utils`) are full proofs:
#       the def row carries no hedge; with a Strong chain the dir-only decoy is not listed.
#   C6  a dot-suffix stem: `Completions.getX` and `ts.Completions.getX` for ts/ts.Completions.ts are exact q_by="file";
#       `Wrong.Completions.getX` is not.
#   C7  `this.leaf` / `self.leaf` in a CUED task print no block (without the guard the qualifier `this` would be kept unproven), and
#       `--for=this.formatDate` prints no <shortkey>. Positive twin: C4.
#   C8  a namespace re-export cycle (a.ts `export * as B from './b'`, b.ts `export * as A from './a'`) ends: total="2", no capped=.
#   C11 (fix round 2, MF1a) a PATH-only proof (file stem, package index) of `utils.` is hedged q_by="path", never exact, when an
#       in-tree `import * as utils` binds utils to a module that does not reach the definition: g9 (tests/utils.ts), g4
#       (tests/utils/index.ts) list the alias first and agree with the <reexports> block; g12 (the real one renamed, so never a leaf
#       candidate) keeps the decoy hedged; a path tail beside that alias (`utils.legacy.formatDate`) is q_by="path" too. Twins: the
#       stem alone, and an alias that reaches the stem's own file, stay exact q_by="file"; the tail with no alias stays proven (C5).
#   C12 (fix round 2, MF1b) a MEMBER gets only its owner-path proof, never the file proof: a method in tests/utils.ts (with and without
#       the alias) and a function nested in a function (`nest.parseIt`) are not exact and carry no q_by="file". Twin: a top-level
#       function (`flat.topIt`) is exact q_by="file".
#   C10 a STORED owner scope (Python `class Cls` in m3.py): `m3.Cls.parseRow` is exact q_by="scope" (the scope and the stem prove
#       both segments); `wrong.Cls.parseRow` is q_unmatched; C++ `n3::Cls::runTask` is never exact (the index stores the innermost
#       owner only, so the namespace segment stays unproven: a disclosed floor, never a wrong exact).
#   C9  the literal rung's shapes type (Python `type X =`), define (`#define x 4`), const (a local `const x =`, in= its function)
#       and assign (`x = 3` at column 0, Lua); the row cap (8 lines: total="8" shown="6", 6 rows); the exact leaf's body cut
#       (truncated="1" past 8192 bytes); floor="1" when a file the scan must read is unreadable (SKIP when chmod cannot hide it).
# Every arm reads an answer whose run exited 0 and printed a <ctx root: a crash or an empty answer is a FAIL, never an absence pass.
#
# Usage: bash test/barrelshortkeycheck.sh [BIN]     (default build/ripwire; exits non-zero on any failure)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="${KEEP_TMP:-$( mktemp -d )}"; [ -n "${KEEP_TMP:-}" ] || trap 'rm -rf "$TMP"' EXIT
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
printf 'import * as Dflt from "./lib/m";\nexport default Dflt;\n' >"$W/src/defexp.ts"
printf 'export class Widget {\n  run(): number {\n    return 1;\n  }\n}\n' >"$W/src/other/widget.ts"
printf 'export { Widget } from "./other/widget";\n' >"$W/src/widgets.ts"
printf 'export function jleaf(n) {\n  return n;\n}\n' >"$W/js/lib.js"
printf 'import * as JS from "./lib.js";\nexport { JS };\n' >"$W/js/b.js"

# run ROOT OUT ARGS…: the answer, its exit code checked; a crash or an answer with no <ctx root fails the arm that reads it
run(){
    local root="$1" out="$2"; shift 2
    ( cd "$root" || exit 1; HOME="$TMP" "$BIN" "$root" --no-cache "$@" </dev/null 2>"$out.err" ) >"$out"
    local rc=$?
    if [ "$rc" -ne 0 ] || ! grep -q '<ctx \|"task":' "$out"; then no "run $* exited $rc or printed no answer"; return 1; fi
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
hasnt "$TMP/a1.xml" "A4 export default of a namespace import is no ns row" 'ns="default"'
}
run "$W" "$TMP/a2.xml" "--for=NS.leaf" && \
has   "$TMP/a2.xml" "A2 export * as NS from: ns row first" 'q="NS" total="4"/><rx p="src/ns.ts" l="1" from="./lib/m" ns="NS"/>'
run "$W" "$TMP/a3.xml" "--for=Outer.leaf" && \
has   "$TMP/a3.xml" "A3 export { Inner as Outer }: ns=Outer" '<rx p="src/renamed.ts" l="1" from="./lib/m" ns="Outer"/>'
run "$W" "$TMP/a3b.xml" "--for=Inner.leaf" && has "$TMP/a3b.xml" "A3 the unexported local alias is a hedged proof" '<def n="leaf" p="src/lib/m.ts" l="1" q="Inner" q_by="alias" total="4"/>'
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
printf '#pragma once\ntemplate <class T> struct Ptr { T* p; };\nstruct Widget { int n; };\nusing WidgetPtr = Ptr<Widget>;\nint getWidgetPtrCount();\ntypedef void (*GadgetRef)(int);\n// using WidgetPtr = OldPtr<Widget>;\nint useLimit() { return clamp(MAX_WIDGET_COUNT); }\n' >"$S/cpp/fwd.h"
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
for fmt in --format=candidates; do
    ( cd "$S" || exit 1; HOME="$TMP" "$BIN" "$S" --no-cache "$fmt" "--for=WidgetPtr" </dev/null 2>/dev/null ) >"$TMP/b9f.out"; frc=$?
    if [ "$frc" -eq 0 ] && [ -s "$TMP/b9f.out" ] && ! grep -q 'shortkey' "$TMP/b9f.out"; then ok "B9 $fmt carries no block"; else no "B9 $fmt carries no block (rc=$frc)"; fi
done
( cd "$S" || exit 1; RIPWIRE_NO_SHORT_KEY=1 HOME="$TMP" "$BIN" "$S" --no-cache "--for=WidgetPtr" </dev/null 2>/dev/null ) >"$TMP/b9off.xml"
python3 - "$TMP/b5.xml" "$TMP/b9off.xml" <<'PY'
import re, sys
on, off = (open(p).read() for p in sys.argv[1:3])
strip = lambda s: re.sub(r' (at|est_tokens)="[^"]*"', '', s)
i = on.find('<!-- shortkey:'); j = on.find('</shortkey>')
sys.exit(0 if i > 0 and j > i and strip(on[:i] + on[j + len('</shortkey>'):]) == strip(off) else 1)
PY
offrc=$?
if [ "$offrc" -eq 0 ]; then ok "B9 the off switch removes exactly the block"; else no "B9 the off switch changed more than the block"; fi

# ── fix round 1: the qualifier proof, every segment (C1-C8), and the literal rung's shapes and cuts (C9) ─────────────────────
F1="$TMP/f1"; mkdir -p "$F1/src/helpers" "$F1/src/utils/legacy" "$F1/src/app"
printf 'export function formatDate(d: number): string {\n  return String(d);\n}\n' >"$F1/src/helpers/date.ts"
printf 'export { formatDate } from "./date";\n' >"$F1/src/helpers/index.ts"
printf 'import * as utils from "../helpers";\nexport function main(): string {\n  return utils.formatDate(1);\n}\n' >"$F1/src/app/main.ts"
printf 'export function formatDate(x: string): string {\n  return "legacy" + x;\n}\n' >"$F1/src/utils/legacy/old.ts"
printf 'export { formatDate } from "./legacy/old";\n' >"$F1/src/utils/legacy.ts"
for i in 1 2 3 4 5 6; do printf 'export class Fmt%s {\n  formatDate(v: number): string {\n    return "x" + v;\n  }\n}\n' "$i" >"$F1/src/app/fmt$i.ts"; done
FD="$TMP/fd"; cp -R "$F1" "$FD"; rm -rf "$FD/src/helpers" "$FD/src/app/main.ts"                       # the decoy alone
FK="$TMP/fk"; cp -R "$F1" "$FK"; rm "$FK/src/app/main.ts"; printf 'export { formatDate } from "../helpers/date";\n' >"$FK/src/utils/index.ts"   # a package index
F3="$TMP/f3"; mkdir -p "$F3/src"; cp -R "$F1/src/helpers" "$F1/src/app" "$F3/src/"; rm "$F3"/src/app/fmt*.ts   # one definition, a consumer alias
F2="$TMP/f2"; mkdir -p "$F2/cyc"
printf 'export function cleaf(): number {\n  return 1;\n}\nexport * as A from "./a";\n' >"$F2/cyc/b.ts"
printf 'export * as B from "./b";\n' >"$F2/cyc/a.ts"
FT="$TMP/ft"; mkdir -p "$FT/ts"
printf 'export function getX(a: number): number {\n  return a;\n}\n' >"$FT/ts/ts.Completions.ts"
for i in 1 2 3 4 5 6; do printf 'export class G%s {\n  getX(v: number): number {\n    return v * %s;\n  }\n}\n' "$i" "$i" >"$FT/ts/g$i.ts"; done

run "$F1" "$TMP/c1.xml" "--for=utils.formatDate" && {
skhas   "$TMP/c1.xml" "C1 dir + alias: both hedged, cands=2"     '<rung n="leaf" key="formatDate" q="utils" kept="2" of="8" exact="0" cands="2"><d n="formatDate" t="fn" p="src/helpers/date.ts" l="1" q_by="alias"/><d n="formatDate" t="fn" p="src/utils/legacy/old.ts" l="1" q_by="dir"/></rung>'
skhasnt "$TMP/c1.xml" "C1 never exact"                             'exact="1"'
skhasnt "$TMP/c1.xml" "C1 no body for a hedged row"                '<b '
}
run "$FD" "$TMP/c1d.xml" "--for=utils.formatDate" && {
skhas   "$TMP/c1d.xml" "C1 one dir-only proof is not exact"        'kept="1" of="7" exact="0"><d n="formatDate" t="fn" p="src/utils/legacy/old.ts" l="1" q_by="dir"/>'
has     "$TMP/c1d.xml" "C1 the reexports def row says q_by=dir"    '<def n="formatDate" p="src/utils/legacy/old.ts" l="1" q="utils" q_by="dir"'
}
for qq in "Wrong.Fmt3.formatDate" "Wrong::Fmt3::formatDate"; do
run "$F1" "$TMP/c2.xml" "--for=$qq" && {
skhas   "$TMP/c2.xml" "C2 $qq: no segment-complete proof"          'kept="0" of="8" exact="0" q_unmatched="1">'
skhasnt "$TMP/c2.xml" "C2 $qq: never exact"                        'exact="1"'
}
done
run "$F3" "$TMP/c3.xml" "--for=where is utils.formatDate defined" && \
has     "$TMP/c3.xml" "C3 a consumer alias keeps the only definition, hedged" '<def n="formatDate" p="src/helpers/date.ts" l="1" q="utils" q_by="alias" total="1"/><rx p="src/helpers/index.ts" l="1" from="./date"/>'
run "$W" "$TMP/c4.xml" "--for=where is Wrong.leaf defined" && {
has     "$TMP/c4.xml" "C4 cued, nothing proves Q: the definition kept, q_unmatched" '<def n="leaf" p="src/lib/m.ts" l="1" q="Wrong" q_unmatched="1"'
}
run "$F1" "$TMP/c5.xml" "--for=legacy.old.formatDate" && has "$TMP/c5.xml" "C5 path tail legacy/old proves legacy.old" '<def n="formatDate" p="src/utils/legacy/old.ts" l="1" q="legacy.old" total="1"/>'
run "$FD" "$TMP/c5b.xml" "--for=utils.legacy.formatDate" && has "$TMP/c5b.xml" "C5 path tail utils/legacy proves utils.legacy" '<def n="formatDate" p="src/utils/legacy/old.ts" l="1" q="utils.legacy" total="1"/>'
run "$F1" "$TMP/c5d.xml" "--for=utils.legacy.formatDate" && has "$TMP/c5d.xml" "C11 the same tail beside an in-tree import * as utils of another module: q_by=path" '<def n="formatDate" p="src/utils/legacy/old.ts" l="1" q="utils.legacy" q_by="path" total="1"/>'
run "$FK" "$TMP/c5c.xml" "--for=where is utils.formatDate defined" && {
has     "$TMP/c5c.xml" "C5 a package index (src/utils/index.ts) proves utils" '<def n="formatDate" p="src/helpers/date.ts" l="1" q="utils" total="2"/><rx p="src/utils/index.ts"'
hasnt   "$TMP/c5c.xml" "C5 the dir-only decoy is not listed beside it" 'src/utils/legacy/old.ts'
}
run "$FT" "$TMP/c6.xml" "--for=Completions.getX" && skhas "$TMP/c6.xml" "C6 dot-suffix stem" 'q="Completions" kept="1" of="7" exact="1"><d n="getX" t="fn" p="ts/ts.Completions.ts" l="1" q_by="file"/>'
run "$FT" "$TMP/c6b.xml" "--for=ts.Completions.getX" && skhas "$TMP/c6b.xml" "C6 the whole stem" 'q="ts.Completions" kept="1" of="7" exact="1">'
run "$FT" "$TMP/c6c.xml" "--for=Wrong.Completions.getX" && skhas "$TMP/c6c.xml" "C6 a segment the stem lacks" 'q="Wrong.Completions" kept="0" of="7" exact="0" q_unmatched="1">'
run "$W" "$TMP/c7.xml" "--for=where is this.leaf defined" && noblock "$TMP/c7.xml" "C7 this.leaf (cued) is a member access: no block"
run "$W" "$TMP/c7b.xml" "--for=where is self.leaf defined" && noblock "$TMP/c7b.xml" "C7 self.leaf (cued) is a member access: no block"
run "$F1" "$TMP/c7c.xml" "--for=this.formatDate" && { if grep -q '<shortkey' "$TMP/c7c.xml"; then no "C7 this.formatDate prints no shortkey"; else ok "C7 this.formatDate prints no shortkey"; fi; }
run "$F2" "$TMP/c8.xml" "--for=B.cleaf" && {
has     "$TMP/c8.xml" "C8 namespace cycle ends with both hops"     '<def n="cleaf" p="cyc/b.ts" l="1" q="B" total="2"/>'
hasnt   "$TMP/c8.xml" "C8 no false capped="                         'capped="1"'
}

# ── fix round 2: a path proof the tree's own `import * as Q` contradicts (C11), a member never gets the file proof (C12) ─────────
mkbase(){ mkdir -p "$1/src/helpers" "$1/src/app" "$1/tests"; cp "$F1/src/helpers/date.ts" "$F1/src/helpers/index.ts" "$1/src/helpers/"; cp "$F1/src/app/main.ts" "$1/src/app/"; }
decoy='export function formatDate(x: string): string {\n  return "decoy" + x;\n}\n'
G9="$TMP/g9";   mkbase "$G9";  printf "$decoy" >"$G9/tests/utils.ts"                                  # a file-stem decoy
G4="$TMP/g4";   mkbase "$G4";  mkdir -p "$G4/tests/utils"; printf "$decoy" >"$G4/tests/utils/index.ts"  # a package-index decoy
G12="$TMP/g12"; mkbase "$G12"; printf "$decoy" >"$G12/tests/utils.ts"                                 # the real one renamed
printf 'export function fmt(d: number): string {\n  return String(d);\n}\n' >"$G12/src/helpers/date.ts"
printf 'export { fmt as formatDate } from "./date";\n' >"$G12/src/helpers/index.ts"
GS="$TMP/gs";   mkdir -p "$GS/tests"; printf "$decoy" >"$GS/tests/utils.ts"                            # the stem alone: no alias
GR="$TMP/gr";   mkdir -p "$GR/tests" "$GR/src/app"; printf "$decoy" >"$GR/tests/utils.ts"             # the alias reaches the stem's file
printf 'import * as utils from "../../tests/utils";\nexport function main(): string {\n  return utils.formatDate("1");\n}\n' >"$GR/src/app/main.ts"
G10="$TMP/g10"; mkbase "$G10"; printf 'export class DateUtil {\n  formatDate(x: string): string {\n    return "member" + x;\n  }\n}\n' >"$G10/tests/utils.ts"
GM="$TMP/gm";   mkdir -p "$GM/tests"; cp "$G10/tests/utils.ts" "$GM/tests/"                            # the member alone: no alias
printf 'export function outer(n: number): number {\n  function parseIt(v: number): number {\n    return v + 1;\n  }\n  return parseIt(n);\n}\n' >"$GM/tests/nest.ts"
printf 'export function topIt(v: number): number {\n  return v;\n}\n' >"$GM/tests/flat.ts"
for gg in G9:g9:tests/utils.ts G4:g4:tests/utils/index.ts; do
    d="${gg%%:*}"; rest="${gg#*:}"; n="${rest%%:*}"; dp="${rest#*:}"; eval "root=\$$d"
    run "$root" "$TMP/c11$n.xml" "--for=utils.formatDate" && {
    skhas   "$TMP/c11$n.xml" "C11 $n: the in-tree alias first, the path-only decoy hedged q_by=path" "<rung n=\"leaf\" key=\"formatDate\" q=\"utils\" kept=\"2\" of=\"2\" exact=\"0\" cands=\"2\"><d n=\"formatDate\" t=\"fn\" p=\"src/helpers/date.ts\" l=\"1\" q_by=\"alias\"/><d n=\"formatDate\" t=\"fn\" p=\"$dp\" l=\"1\" q_by=\"path\"/></rung>"
    skhasnt "$TMP/c11$n.xml" "C11 $n: never exact" 'exact="1"'
    has     "$TMP/c11$n.xml" "C11 $n: the reexports block agrees (helpers, q_by=alias)" '<def n="formatDate" p="src/helpers/date.ts" l="1" q="utils" q_by="alias" total="1"/>'
    }
done
run "$G12" "$TMP/c11r.xml" "--for=utils.formatDate" && {
skhas   "$TMP/c11r.xml" "C11 g12 (the real one renamed, never a leaf candidate): the stem decoy is hedged" '<rung n="leaf" key="formatDate" q="utils" kept="1" of="1" exact="0"><d n="formatDate" t="fn" p="tests/utils.ts" l="1" q_by="path"/></rung>'
skhasnt "$TMP/c11r.xml" "C11 g12: never exact" 'exact="1"'
}
run "$GS" "$TMP/c11s.xml" "--for=utils.formatDate" && skhas "$TMP/c11s.xml" "C11 twin: the stem alone (nothing aliases utils) stays exact" 'q="utils" kept="1" of="1" exact="1"><d n="formatDate" t="fn" p="tests/utils.ts" l="1" q_by="file"/>'
run "$GR" "$TMP/c11a.xml" "--for=utils.formatDate" && skhas "$TMP/c11a.xml" "C11 twin: an alias that reaches the stem's own file keeps it exact" 'q="utils" kept="1" of="1" exact="1"><d n="formatDate" t="fn" p="tests/utils.ts" l="1" q_by="file"/>'
run "$G10" "$TMP/c12.xml" "--for=utils.formatDate" && {
skhas   "$TMP/c12.xml" "C12 a method in tests/utils.ts is no file proof: only the alias is kept" '<rung n="leaf" key="formatDate" q="utils" kept="1" of="2" exact="0"><d n="formatDate" t="fn" p="src/helpers/date.ts" l="1" q_by="alias"/></rung>'
skhasnt "$TMP/c12.xml" "C12 never exact" 'exact="1"'
}
run "$GM" "$TMP/c12m.xml" "--for=utils.formatDate" && {
skhas   "$TMP/c12m.xml" "C12 the member alone (no alias): q_unmatched, not the file proof" 'q="utils" kept="0" of="1" exact="0" q_unmatched="1">'
skhasnt "$TMP/c12m.xml" "C12 the member alone: no q_by=file" 'q_by="file"'
}
run "$GM" "$TMP/c12n.xml" "--for=nest.parseIt" && skhas "$TMP/c12n.xml" "C12 a function nested in a function: q_unmatched, not the file proof" 'q="nest" kept="0" of="1" exact="0" q_unmatched="1">'
run "$GM" "$TMP/c12f.xml" "--for=flat.topIt" && skhas "$TMP/c12f.xml" "C12 twin: a top-level function keeps the file proof" 'q="flat" kept="1" of="1" exact="1"><d n="topIt" t="fn" p="tests/flat.ts" l="1" q_by="file"/>'

SC="$TMP/sc"; mkdir -p "$SC/py" "$SC/cpp"
for i in 1 2 3 4 5 6 7; do
    printf 'class Cls:\n    def parseRow(self, x):\n        return x * %s\n' "$i" >"$SC/py/m$i.py"
    printf 'namespace n%s {\nstruct Cls {\n  int runTask(int a);\n};\nint Cls::runTask(int a) { return a * %s; }\n}\n' "$i" "$i" >"$SC/cpp/k$i.cpp"
done
run "$SC" "$TMP/c10.xml" "--for=m3.Cls.parseRow" && skhas "$TMP/c10.xml" "C10 stored scope + stem: exact" 'q="m3.Cls" kept="1" of="7" exact="1"><d n="Cls.parseRow" t="fn" p="py/m3.py" l="2" q_by="scope"/>'
run "$SC" "$TMP/c10b.xml" "--for=wrong.Cls.parseRow" && skhas "$TMP/c10b.xml" "C10 stored scope, a wrong first segment" 'q="wrong.Cls" kept="0" of="7" exact="0" q_unmatched="1">'
run "$SC" "$TMP/c10c.xml" "--for=n3::Cls::runTask" && {
skhas   "$TMP/c10c.xml" "C10 C++ namespace segment unproven: q_unmatched" 'q="n3::Cls" kept="0" of="14" exact="0" q_unmatched="1">'
skhasnt "$TMP/c10c.xml" "C10 C++ never exact"                       'exact="1"'
}

L="$TMP/lit"; mkdir -p "$L/src" "$L/c" "$L/py" "$L/ts"
printf 'export function host(): number {\n  const localLimit = 4;\n  return localLimit;\n}\n' >"$L/src/host.ts"
printf '#ifndef X_H\n#define X_H\n#define widgetCount 4\nint useIt(void);\n#endif\n' >"$L/c/x.h"
printf '#include "x.h"\nint useIt(void) { return widgetCount; }\n' >"$L/c/x.c"
printf 'type RowMap = dict[str, int]\n\ndef go(m: RowMap) -> int:\n    return len(m)\n' >"$L/py/m.py"
printf 'fieldWidth = 3\nreturn fieldWidth\n' >"$L/py/a.lua"
for i in 1 2 3 4 5 6 7 8; do printf 'export function host%s(): number {\n  const capKey = %s;\n  return capKey;\n}\n' "$i" "$i" >"$L/src/f$i.ts"; done
python3 - "$L" <<'PY'
import sys
L = sys.argv[1]
body = "".join("  total += %d;\n" % i for i in range(800))
open(L + "/ts/ts.Big.ts", "w").write("export function hugeFn(): number {\n  let total = 0;\n" + body + "  return total;\n}\n")
for i in range(1, 7):
    open(L + "/ts/q%d.ts" % i, "w").write("export class Q%d {\n  hugeFn(v: number): number {\n    return v * %d;\n  }\n}\n" % (i, i))
PY
run "$L" "$TMP/c9a.xml" "--for=RowMap" && skhas "$TMP/c9a.xml" "C9 type shape" '<ld p="py/m.py" l="1" shape="type">'
run "$L" "$TMP/c9b.xml" "--for=widgetCount" && skhas "$TMP/c9b.xml" "C9 define shape (a non-CONST key)" '<ld p="c/x.h" l="3" shape="define">'
run "$L" "$TMP/c9c.xml" "--for=localLimit" && skhas "$TMP/c9c.xml" "C9 const shape, in= its function" '<ld p="src/host.ts" l="2" shape="const" in="host">'
run "$L" "$TMP/c9d.xml" "--for=fieldWidth" && skhas "$TMP/c9d.xml" "C9 assign shape at column 0" '<ld p="py/a.lua" l="1" shape="assign">'
c9e=1; run "$L" "$TMP/c9e.xml" "--for=capKey" && { c9e=0;
skhas "$TMP/c9e.xml" "C9 row cap: total=8 shown=6" '<rung n="literal" key="capKey" total="8" shown="6" exact="0">'
n=$( sk "$TMP/c9e.xml" | grep -o '<ld ' | wc -l | tr -d ' ' ); if [ "$n" = 6 ]; then ok "C9 row cap: 6 ld rows"; else no "C9 row cap: $n ld rows (want 6)"; fi
}
run "$L" "$TMP/c9f.xml" "--for=Big.hugeFn" && skhas "$TMP/c9f.xml" "C9 the exact leaf's body is cut past 8192 bytes" 'n="hugeFn" lines="1-518/804" truncated="1" next="--expand=ts/ts.Big.ts:1:hugeFn:519-804">'
( cd "$L" || exit 1; HOME="$TMP" "$BIN" "$L" --cache="$TMP/litcache" "--for=capKey" </dev/null >"$TMP/c9g0.xml" 2>/dev/null ) || no "C9 floor: the cache-priming run failed"
chmod 000 "$L/src/f3.ts"
if [ -r "$L/src/f3.ts" ]; then
    printf '  SKIP  C9 floor: chmod cannot hide a file from this user\n'
else
    ( cd "$L" || exit 1; HOME="$TMP" "$BIN" "$L" --cache="$TMP/litcache" "--for=capKey" </dev/null 2>/dev/null ) >"$TMP/c9g.xml"; frc=$?
    if [ "$frc" -eq 0 ] && sk "$TMP/c9g.xml" | grep -qF 'exact="0" floor="1">'; then ok "C9 floor=1 when a file is unreadable"; else no "C9 floor=1 when a file is unreadable (rc=$frc)"; fi
    if [ "$c9e" -ne 0 ] || sk "$TMP/c9e.xml" | grep -qF 'floor='; then no "C9 a clean scan prints no floor= (or its run failed)"; else ok "C9 a clean scan prints no floor="; fi
fi
chmod 644 "$L/src/f3.ts"

if [ "$fail" = 0 ]; then echo "barrelshortkeycheck: PASS"; else echo "barrelshortkeycheck: FAIL"; fi
exit "$fail"
