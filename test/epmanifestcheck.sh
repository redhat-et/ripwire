#!/usr/bin/env bash
# epmanifestcheck.sh — MANIFEST ENTRY POINTS on a --for answer (lane ep-manifest; src/epmanifest.h; CONTRIBUTING family 10 slice 10a).
#
# THE CONTRACT THIS PINS (arms tagged [P] are RED on the pre-change binary 681b49e5; [G] arms are twins and near-miss negatives
# that hold on both binaries and must keep holding — PROCESS rule 4, no gate erosion):
#
#   TRIGGER  CLI --for (XML, default regime) whose ranked head shows a def a manifest entry point names (Python module:attr or Rust [[bin]] main).
#   WHAT     <ep p= l= group= [used_at= used_in= used_total=]><e n= target= def=|external=1|unresolved=1/>…</ep> after the tail.
#   NOT      a non-manifest file, --json, --token-budget=N, --signatures-only, RIPWIRE_NO_EP_MANIFEST=1 carry none.
#
# Arms:
#   C1 [P] setup.cfg inline group `x.report = fmt = pkg.mod:Fmt`: <ep p="setup.cfg" l="5" group="x.report"> with
#          e n="fmt" target="pkg.mod:Fmt" def="pkg/mod.py:1"
#   C2 [P] two consumers, both listed, hedged by text: used_at = pkg/loader.py:6 and pkg/second.py:2, used_in = load reload_reports
#   C3 [G] near-miss consumers are NOT listed: a comment, `name == "x.report"` (not a .group), a producer `_ep(group="x.report")`
#   C4 [P] entry_points(group="y.other") is a consumer (load_other); duplicate entry names across groups: two groups each with n="fmt",
#          distinct targets (pkg.mod:Fmt / pkg.mod:Other)
#   C5 [P] unresolved: `bad = pkg.mod:Missing` carries unresolved="1"; external: `ext = otherpkg.thing:Thing` carries external="1"
#   C6 [P] a group with no consumer (z.quiet) has a row and NO used_at= (no guess)
#   P1 [P] pyproject variant (src layout): [project.entry-points."x.report"] → def="src/pkg/mod.py:1", used_at=src/pkg/loader.py:5
#          (`.select(group=…)`); [project.scripts] → group="console_scripts", def="src/pkg/cli.py:1", no used_at=
#   S1 [P] siblings: a `key: value` group line, a dotted method target (plug.mod:Fmt.render → the method, not the same-named
#          top-level render), a package target (plug/sub/__init__.py), iter_entry_points("g"), entry_points()["g"] and a later group= keyword (entry_points(name=, group=)) consumers;
#          [G] m.get("g") on a non-entry_points receiver is not a consumer
#   K1 [P] the runaway guards disclose: a 13-entry group shows 12 with entries_capped="1" entries_total="13"; 4 consumers show 3
#          with used_capped="1" used_total="4"
#   E1 [P] a module found only by a deeper same-suffix path (setup.cfg `fmt = cli:Fmt`, only tools/cli.py exists): unresolved="1", no def=
#   E2 [P] `sp = pkg.mod : Fmt` (blanks around the colon) prints target="pkg.mod:Fmt" and resolves to pkg/mod.py:1
#   E3 [P] an empty group name (`= bare = pkg.mod:Fmt`) yields no <ep>
#   E4 [P] pyproject `[project.entry-points."x.report"]  # see [docs]`: group="x.report", not a name bent by the comment's `]`
#   (C2/C3 also pin the closing quote: loader.py `prefix_only` compares "x.report.extra", which must not be listed for x.report)
#   B1 [P] Cargo.toml `[[bin]]` gen-docs + app: <ep p="Cargo.toml" … group="bin"> with e n="gen-docs" target="tools/gen.rs"
#          def="tools/gen.rs:3" and e n="app" target="src/app.rs" def="src/app.rs:3"
#   B2 [G] a [[bin]] path not in the tree: external="1", never a def guess (cargoabs ghost)
#   B3 [G] a [[bin]] file with no fn main: unresolved="1" (cargonommain empty)
#   B4 [G] [[example]] / [[test]] tables are not binaries: no <ep> (cargoex)
#   B5 [G] a workspace root Cargo.toml with no [[bin]]: no <ep> (cargows root)
#   B6 [P] workspace member crates each with src/main.rs: implicit bin row from member Cargo.toml (cargows/crate-a)
#   B7 [P] an omitted [[bin]] path follows Cargo inference (package bin src/main.rs, named bin src/bin/NAME.rs); a [[bin]] inside a multi-line string is no entry (cargoinf)
#   N1 [G] a non-manifest .cfg (config.cfg, same text): no <ep>
#   N2 [G] no <ep>, byte-identical to RIPWIRE_NO_EP_MANIFEST=1: --json, --token-budget=3000, --signatures-only
#   N3 [G] prefix identity: the answer minus <ep> and its clause, est_tokens masked, equals RIPWIRE_NO_EP_MANIFEST=1
#   R1 [P] (CodeRabbit 4381174525) the groups register rows <sigs> EMITS: --pack-budget-bytes=1 leaves only Fmt in <sigs> (shown=1), so only x.report rides (Other / Lonely were dropped)
#   R2 [P] every head row that a group registers dropped (load_other alone shown): no <ep> and no clause   R3 [G] --pack-budget-bytes=300 drops only reload_reports (no target): all three groups stay
#   J1 [P] package.json bin object: <ep p="package.json" group="bin"> e n="tool-cli" target="bin/cli.js" def="bin/cli.js:…"
#   J2 [P] "bin": "cli.js" (string): entry name = package name
#   J3 [P] bin path missing in tree: external="1"
#   J4 [G] "exports" only: no <ep>
#   J5 [G] no bin/main: no <ep>
#   J6 [G] package.json under node_modules: no <ep>
#   J7 [G] TS main -> dist/ not in tree: no <ep> (main target never matches a shown row)
#   L1 [P] the clause rides (compact and full) and defines every attribute <ep>/<e> carry, searched in the ep clause alone as whole names (CodeRabbit 4381174537),
#          capped attributes included; L1-MUT [G] a clause missing one definition makes the same check fail (the arm can fail)
#   X1 [G] determinism  X2 [G] xmllint well-formed (when xmllint exists)  X3 [G] no "--" inside the legend comment
#
# Usage:  bash test/epmanifestcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/epmanifestcheck.sh
# BIN is $1, else RIPWIRE_BIN, else build/ripwire; the first output line names the binary used. Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
unset RIPWIRE_NO_EP_MANIFEST
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "epmanifestcheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
verdict(){ if [ "$1" -eq 0 ]; then ok "$2"; else no "$3"; fi; }   # rc, the PASS line, the FAIL line

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
FX="$ROOT/test/epmanifestfix"
[ -f "$FX/edge/setup.cfg" ] && [ -f "$FX/edgetoml/pyproject.toml" ] && [ -f "$FX/cfg/setup.cfg" ] && [ -f "$FX/pyp/pyproject.toml" ] && [ -f "$FX/negcfg/config.cfg" ] && [ -f "$FX/sib/setup.cfg" ] && [ -f "$FX/cargo/Cargo.toml" ] && [ -f "$FX/cargoabs/Cargo.toml" ] && [ -f "$FX/cargonommain/Cargo.toml" ] && [ -f "$FX/cargoex/Cargo.toml" ] && [ -f "$FX/cargows/Cargo.toml" ] && [ -f "$FX/pkgjson/package.json" ] && [ -f "$FX/pkgjsonstr/package.json" ] && [ -f "$FX/pkgjsonmiss/package.json" ] && [ -f "$FX/pkgjsonexp/package.json" ] && [ -f "$FX/pkgjsonempty/package.json" ] && [ -f "$FX/pkgjsonnm/package.json" ] && [ -f "$FX/pkgjsonnm/node_modules/dep/package.json" ] && [ -f "$FX/pkgjsonts/package.json" ] || { echo "fixture test/epmanifestfix missing"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"

Q='--for=how is the Fmt report formatter registered and loaded'
# run DIR OUT [args...]: the answer (stdout) and its exit code (OUT.rc); a run that fails is a FAIL, never an absence
run(){ local dir="$1" out="$2"; shift 2; ( cd "$dir" || exit 97; "$BIN" "$dir" --no-cache "$@" >"$out" 2>"$out.err" ); echo $? >"$out.rc"; }
okrun(){ [ "$(cat "$1.rc")" = "0" ] && [ -s "$1" ]; }

run "$FX/cfg" "$TMP/cfg" "$Q"
run "$FX/cfg" "$TMP/cfg2" "$Q"
run "$FX/cfg" "$TMP/cfgfull" "$Q" --legend=full
RIPWIRE_NO_EP_MANIFEST=1 run "$FX/cfg" "$TMP/cfgoff" "$Q"
run "$FX/pyp" "$TMP/pyp" '--for=how is the Fmt report formatter and the pkgtool main command registered'
run "$FX/negcfg" "$TMP/neg" "$Q"
run "$FX/sib" "$TMP/sib" '--for=how are the report formatter render and init hooks registered'
run "$FX/edge" "$TMP/edge" "$Q"
run "$FX/edgetoml" "$TMP/edgetoml" "$Q"
QCARGO='--for=cargo run --bin gen-docs entry'
run "$FX/cargo" "$TMP/cargo" "$QCARGO"
run "$FX/cargoabs" "$TMP/cargoabs" "$QCARGO"
run "$FX/cargonommain" "$TMP/cargonommain" "$QCARGO"
run "$FX/cargoinf" "$TMP/cargoinf" '--for=cargo run --bin tool entry'
run "$FX/cargoex" "$TMP/cargoex" '--for=how does the sample example run'
run "$FX/cargows" "$TMP/cargows" '--for=how does this workspace root start'
run "$FX/cargows/crate-a" "$TMP/cargowsa" '--for=how does crate-a main start'
QPKG='--for=how does the tool-cli command start'
QSTR='--for=how does the cli.js main export start'
QMISS='--for=how does the miss-pkg ok bin command start'
QEXP='--for=how does the exp-pkg package export run'
QEMPTY='--for=how does the empty-pkg package idle export'
QNM='--for=how does rootStart start the root cli command'
QTS='--for=how does the ts-pkg package main export run'
run "$FX/pkgjson" "$TMP/pkgjson" "$QPKG"
run "$FX/pkgjsonstr" "$TMP/pkgjsonstr" "$QSTR"
run "$FX/pkgjsonmiss" "$TMP/pkgjsonmiss" "$QMISS"
run "$FX/pkgjsonexp" "$TMP/pkgjsonexp" "$QEXP"
run "$FX/pkgjsonempty" "$TMP/pkgjsonempty" "$QEMPTY"
run "$FX/pkgjsonnm" "$TMP/pkgjsonnm" "$QNM"
run "$FX/pkgjsonnm/node_modules/dep" "$TMP/pkgjsonnmdep" '--for=how does depStart start'
run "$FX/pkgjsonts" "$TMP/pkgjsonts" "$QTS"
for a in cfg cfg2 cfgfull cfgoff pyp neg sib edge edgetoml cargo cargoabs cargonommain cargoinf cargoex cargows cargowsa pkgjson pkgjsonstr pkgjsonmiss pkgjsonexp pkgjsonempty pkgjsonnm pkgjsonnmdep pkgjsonts; do okrun "$TMP/$a" || no "run $a failed (rc=$(cat "$TMP/$a.rc"))"; done

# eps FILE -> one JSON line: [{attrs..., "e": [{attrs}]}] of every <ep> element
eps(){ python3 - "$1" <<'PY'
import json, re, sys
t = open(sys.argv[1], encoding="utf-8", errors="replace").read()
t = re.sub(r"<!--.*?-->", "", t, flags=re.S)
out = []
for m in re.finditer(r"<ep( [^>]*)>(.*?)</ep>", t, flags=re.S):
    d = dict(re.findall(r'(\w+)="([^"]*)"', m.group(1)))
    d["e"] = [dict(re.findall(r'(\w+)="([^"]*)"', e)) for e in re.findall(r"<e( [^>]*)/>", m.group(2))]
    out.append(d)
print(json.dumps(out))
PY
}
CFG="$( eps "$TMP/cfg" )"; PYP="$( eps "$TMP/pyp" )"; NEG="$( eps "$TMP/neg" )"; SIB="$( eps "$TMP/sib" )"
EDGE="$( eps "$TMP/edge" )"; EDGETOML="$( eps "$TMP/edgetoml" )"
CARGO="$( eps "$TMP/cargo" )"; CARGOABS="$( eps "$TMP/cargoabs" )"; CARGONM="$( eps "$TMP/cargonommain" )"
CARGOINF="$( eps "$TMP/cargoinf" )"; CARGOEX="$( eps "$TMP/cargoex" )"; CARGOWS="$( eps "$TMP/cargows" )"; CARGOWSA="$( eps "$TMP/cargowsa" )"
PKGJSON="$( eps "$TMP/pkgjson" )"; PKGJSONSTR="$( eps "$TMP/pkgjsonstr" )"; PKGJSONMISS="$( eps "$TMP/pkgjsonmiss" )"
PKGJSONEXP="$( eps "$TMP/pkgjsonexp" )"; PKGJSONEMPTY="$( eps "$TMP/pkgjsonempty" )"; PKGJSONNM="$( eps "$TMP/pkgjsonnm" )"; PKGJSONNMDEP="$( eps "$TMP/pkgjsonnmdep" )"; PKGJSONTS="$( eps "$TMP/pkgjsonts" )"
has(){ python3 -c "import json,sys; d=json.loads(sys.argv[1]); sys.exit(0 if ($2) else 1)" "$1"; }
grp(){ echo "[g for g in d if g.get('group')=='$1']"; }

# C1
if has "$CFG" "any(g['p']=='setup.cfg' and g['l']=='5' and any(e=={'n':'fmt','target':'pkg.mod:Fmt','def':'pkg/mod.py:1'} for e in g['e']) for g in $(grp x.report))"; then
    ok "C1 setup.cfg inline group links fmt -> pkg/mod.py:1 Fmt"; else no "C1 setup.cfg x.report row: $CFG"; fi
# C2 + C3
if has "$CFG" "any(g.get('used_at')=='pkg/loader.py:6 pkg/second.py:2' and g.get('used_in')=='load reload_reports' and 'used_total' not in g for g in $(grp x.report))"; then
    ok "C2/C3 both real consumers listed; comment, name==, producer call not listed"; else no "C2/C3 x.report used_at: $CFG"; fi
# C4
if has "$CFG" "any(g.get('used_at')=='pkg/loader.py:22' and g.get('used_in')=='load_other' for g in $(grp y.other)) and [e['target'] for g in d for e in g['e'] if e['n']=='fmt']==['pkg.mod:Fmt','pkg.mod:Other']"; then
    ok "C4 entry_points(group=) consumer; duplicate name fmt in two groups, distinct targets"; else no "C4 y.other / duplicate names: $CFG"; fi
# C5
if has "$CFG" "any(e=={'n':'bad','target':'pkg.mod:Missing','unresolved':'1'} for g in d for e in g['e']) and any(e=={'n':'ext','target':'otherpkg.thing:Thing','external':'1'} for g in d for e in g['e'])"; then
    ok "C5 unresolved=1 for a missing attribute, external=1 for a module outside the tree"; else no "C5 unresolved/external: $CFG"; fi
# C6
if has "$CFG" "len($(grp z.quiet))==1 and 'used_at' not in $(grp z.quiet)[0] and 'used_in' not in $(grp z.quiet)[0]"; then
    ok "C6 a group with no consumer carries no used_at= (no guess)"; else no "C6 z.quiet: $CFG"; fi
# P1
if has "$PYP" "any(g['p']=='pyproject.toml' and g.get('used_at')=='src/pkg/loader.py:5' and g.get('used_in')=='load_reports' and g['e']==[{'n':'fmt','target':'pkg.mod:Fmt','def':'src/pkg/mod.py:1'}] for g in $(grp x.report)) and any(g['e']==[{'n':'pkgtool','target':'pkg.cli:main','def':'src/pkg/cli.py:1'}] and 'used_at' not in g for g in $(grp console_scripts))"; then
    ok "P1 pyproject entry-points + project.scripts (src layout), select(group=) consumer"; else no "P1 pyproject: $PYP"; fi
# S1
if has "$SIB" "any(g['l']=='2' and g.get('used_at')=='plug/use.py:5' and g['e']==[{'n':'m','target':'plug.mod:Fmt.render','def':'plug/mod.py:3'}] for g in $(grp x.hooks)) and any(g.get('used_at')=='plug/use.py:7 plug/use.py:31' and g.get('used_in')=='go by_name' and {'n':'i','target':'plug.sub:Init','def':'plug/sub/__init__.py:1'} in g['e'] for g in $(grp x.pkg))"; then
    ok "S1 key: group line, dotted method target, package target, iter_entry_points / entry_points()[] consumers, m.get not"; else no "S1 siblings: $SIB"; fi
# K1
if has "$SIB" "any(len(g['e'])==12 and g.get('entries_capped')=='1' and g.get('entries_total')=='13' and g.get('used_capped')=='1' and g.get('used_total')=='4' and len(g['used_at'].split())==3 for g in $(grp x.many))"; then
    ok "K1 entry and consumer caps disclose *_capped=1 with the total"; else no "K1 caps: $SIB"; fi
# E1: a module found only by a deeper same-suffix path (tools/cli.py for `cli`) is not that module: unresolved, never a def
if has "$EDGE" "any(e=={'n':'fmt','target':'cli:Fmt','unresolved':'1'} for g in $(grp x.report) for e in g['e'])"; then
    ok "E1 a suffix-only module match (tools/cli.py for cli:Fmt) is unresolved=1, not a def"; else no "E1 suffix-only module: $EDGE"; fi
# E2: `mod : attr` (blanks around the colon) is printed and resolved as pkg.mod:Fmt
if has "$EDGE" "any(e=={'n':'sp','target':'pkg.mod:Fmt','def':'pkg/mod.py:1'} for g in $(grp x.report) for e in g['e'])"; then
    ok "E2 'pkg.mod : Fmt' reads as target pkg.mod:Fmt -> pkg/mod.py:1"; else no "E2 mod : attr: $EDGE"; fi
# E3: a group line with an empty name (`= bare = pkg.mod:Fmt`) yields no <ep>
if has "$EDGE" "not any(g.get('group','x')=='' for g in d) and len(d)==1"; then
    ok "E3 an empty group name yields no <ep>"; else no "E3 empty group: $EDGE"; fi
# E4: a TOML header with a trailing comment holding a `]` names the right group
if has "$EDGETOML" "any(g['e']==[{'n':'fmt','target':'pkg.mod:Fmt','def':'pkg/mod.py:1'}] for g in $(grp x.report)) and len(d)==1"; then
    ok "E4 a [..]  # see [docs] header comment does not bend the group name"; else no "E4 header comment: $EDGETOML"; fi

# B1
if has "$CARGO" "len(d)==1 and d[0]['p']=='Cargo.toml' and d[0]['group']=='bin' and sorted((e['n'],e['target'],e.get('def','')) for e in d[0]['e'])==[('app','src/app.rs','src/app.rs:3'),('gen-docs','tools/gen.rs','tools/gen.rs:3')]"; then
    ok "B1 Cargo.toml [[bin]] links gen-docs and app to their main fns"; else no "B1 cargo [[bin]]: $CARGO"; fi
# B2
if has "$CARGOABS" "any(e=={'n':'ghost','target':'missing/nowhere.rs','external':'1'} for g in d for e in g['e']) and not any('def' in e for g in d for e in g['e'] if e['n']=='ghost')"; then
    ok "B2 a [[bin]] path outside the tree is external=1, never a def"; else no "B2 missing bin path: $CARGOABS"; fi
# B3
if has "$CARGONM" "any(e=={'n':'empty','target':'tools/empty.rs','unresolved':'1'} for g in d for e in g['e'])"; then
    ok "B3 a [[bin]] file without fn main is unresolved=1"; else no "B3 no-main bin file: $CARGONM"; fi
# B4
if has "$CARGOEX" "d==[]" && grep -q 'examples/sample.rs' "$TMP/cargoex"; then   # the example file is shown: the empty answer is the reader's
    ok "B4 [[example]] is not a binary manifest row"; else no "B4 example produced ep: $CARGOEX"; fi
# B5
if okrun "$TMP/cargows" && has "$CARGOWS" "d==[]"; then
    ok "B5 workspace root Cargo.toml with no [[bin]] yields no <ep>"; else no "B5 workspace root ep: $CARGOWS"; fi
# B6
if has "$CARGOWSA" "any(g['p']=='Cargo.toml' and g['group']=='bin' and any(e=={'n':'crate-a','target':'src/main.rs','def':'src/main.rs:3'} for e in g['e']) for g in d)"; then
    ok "B6 workspace member implicit src/main.rs bin row"; else no "B6 workspace member bin: $CARGOWSA"; fi
# B7
if has "$CARGOINF" "any(g['group']=='bin' and sorted((e['n'],e['target'],e.get('def','')) for e in g['e'])==[('demo','src/main.rs','src/main.rs:3'),('tool','src/bin/tool.rs','src/bin/tool.rs:3')] for g in d)"; then
    ok "B7 an omitted [[bin]] path follows Cargo inference; a [[bin]] inside a multi-line string is no entry"; else no "B7 inferred bin paths: $CARGOINF"; fi
# J1
if has "$PKGJSON" "any(g['p']=='package.json' and g.get('group')=='bin' and any(e.get('n')=='tool-cli' and e.get('target')=='bin/cli.js' and str(e.get('def','')).startswith('bin/cli.js:') for e in g['e']) for g in d)"; then
    ok "J1 package.json bin object links tool-cli -> bin/cli.js"; else no "J1 package.json bin: $PKGJSON"; fi
# J2
if has "$PKGJSONSTR" "any(g.get('group')=='bin' and any(e.get('n')=='cli-pkg' and e.get('target')=='cli.js' and 'def' in e for e in g['e']) for g in d)"; then
    ok "J2 string bin uses the package name as the entry name"; else no "J2 string bin: $PKGJSONSTR"; fi
# J3
if has "$PKGJSONMISS" "any(g.get('group')=='bin' and any(e.get('n')=='tool' and e.get('target')=='missing/cli.js' and e.get('external')=='1' for e in g['e']) and any(e.get('n')=='ok' and e.get('target')=='index.js' and 'def' in e for e in g['e']) for g in d)"; then
    ok "J3 a bin path outside the tree is external=1 beside an in-tree bin"; else no "J3 missing bin path: $PKGJSONMISS"; fi
# J4
if grep -q 'n="run"' "$TMP/pkgjsonexp"; then ok "J4 positive: run row shown"; else no "J4 positive: run row not shown (query did not reach src/index.js)"; fi
okrun "$TMP/pkgjsonexp" && [ "$PKGJSONEXP" = "[]" ]; verdict $? "J4 exports-only package.json yields no <ep>" "J4 exports produced rows: $PKGJSONEXP"
# J5
if grep -q 'n="idle"' "$TMP/pkgjsonempty"; then ok "J5 positive: idle row shown"; else no "J5 positive: idle row not shown"; fi
okrun "$TMP/pkgjsonempty" && [ "$PKGJSONEMPTY" = "[]" ]; verdict $? "J5 no bin/main yields no <ep>" "J5 empty manifest produced rows: $PKGJSONEMPTY"
# J6
if has "$PKGJSONNM" "any(g['p']=='package.json' and g.get('group')=='bin' for g in d) and not any('node_modules' in g.get('p','') for g in d)"; then
    ok "J6 node_modules package.json is ignored; root bin still rides"; else no "J6 node_modules: $PKGJSONNM"; fi
if grep -q 'n="depStart"' "$TMP/pkgjsonnmdep"; then ok "J6b positive: depStart row shown"; else no "J6b positive: depStart row not shown"; fi
if grep -q 'n="rootStart"' "$TMP/pkgjsonnm"; then ok "J6b positive: root bin row shown in sibling root fixture"; else no "J6b positive: rootStart row not shown in pkgjsonnm"; fi
okrun "$TMP/pkgjsonnmdep" && [ "$PKGJSONNMDEP" = "[]" ]; verdict $? "J6b a package.json under node_modules yields no <ep>" "J6b node_modules package.json produced rows: $PKGJSONNMDEP" 
# J7
if grep -q 'n="run"' "$TMP/pkgjsonts"; then ok "J7 positive: run row shown (src/index.ts)"; else no "J7 positive: run row not shown"; fi
okrun "$TMP/pkgjsonts" && [ "$PKGJSONTS" = "[]" ]; verdict $? "J7 TS main -> missing dist/ yields no <ep>" "J7 TS dist main produced rows: $PKGJSONTS" 
# F1-F3 (the fold of #459 + #460, fixtures built at run time): one format table decides how a target is read
F="$TMP/fold"; mkdir -p "$F/py/pkg" "$F/dot/bin" "$F/lit/tools" || no "F fixture dirs"
printf '[options.entry_points]\nx.report =\n    fmt = pkg.mod:Fmt\n    whole = pkg.mod\n' >"$F/py/setup.cfg"
printf 'class Fmt:\n    pass\n\n\ndef main():\n    pass\n' >"$F/py/pkg/mod.py"; : >"$F/py/pkg/__init__.py"
printf '{\n  "name": "dot-pkg",\n  "description": "say \\"bin\\": in a string",\n  "files": ["bin"],\n  "publishConfig": {\n    "bin": "nested.js"\n  },\n  "bin": {\n    "dot-cli": "./bin/cli.js"\n  }\n}\n' >"$F/dot/package.json"   # top-level "bin" on line 8
printf '// the dot-cli command: its exported function, not the module body (line 1), is the entry\nexport function dotStart() {\n  return 1;\n}\n' >"$F/dot/bin/cli.js"
printf 'from importlib.metadata import entry_points\n\n\ndef load_bins():\n    return entry_points(group="bin")\n' >"$F/dot/load.py"   # a Python loader shape quoting "bin" (the scan reads .py)
printf '[package]\nname = "pyish"\n\n[[bin]]\nname = "pyish"\npath = "pkg/mod.py"\n' >"$F/py/Cargo.toml"   # read only for a .rs row
mkdir -p "$F/anon" || no "F fixture anon"
printf '{\n  "main": "start.js"\n}\n' >"$F/anon/package.json"   # no "name": the entry is named by its key, never an invented name
printf '// the anonymous package main\nexport function anonStart() {\n  return 1;\n}\n' >"$F/anon/start.js"
printf '[package]\nname = "lit"\n\n[[ bin ]]  # a spaced header with a comment\nname = '"'"'gen'"'"'\npath = '"'"'tools/gen.rs'"'"'\n' >"$F/lit/Cargo.toml"
printf 'fn helper() {}\n\nfn main() {\n    helper();\n}\n' >"$F/lit/tools/gen.rs"
run "$F/py" "$TMP/fpy" "$Q"
run "$F/py" "$TMP/fpy2" '--for=how is the Fmt report formatter and the main function registered'
run "$F/dot" "$TMP/fdot" '--for=how does dotStart start the dot-cli command'
run "$F/anon" "$TMP/fanon" '--for=how does anonStart start the package main'
run "$F/lit" "$TMP/flit" '--for=cargo run --bin gen entry main helper'
for a in fpy fpy2 fdot fanon flit; do okrun "$TMP/$a" || no "run $a failed (rc=$(cat "$TMP/$a.rc"))"; done
FPY="$( eps "$TMP/fpy" )"; FPY2="$( eps "$TMP/fpy2" )"; FDOT="$( eps "$TMP/fdot" )"; FANON="$( eps "$TMP/fanon" )"; FLIT="$( eps "$TMP/flit" )"
# F1: a module-only Python target (`whole = pkg.mod`) is a module, never a file path: in the tree it is unresolved=1, not external=1
if has "$FPY" "any({'n':'fmt','target':'pkg.mod:Fmt','def':'pkg/mod.py:1'} in g['e'] and {'n':'whole','target':'pkg.mod','unresolved':'1'} in g['e'] for g in $(grp x.report))"; then
    ok "F1 a module-only setup.cfg target reads as a module (unresolved=1), beside a resolved module:attr"; else no "F1 module-only target: $FPY"; fi
# F1b: the format table's extensions: a Python row reads setup.cfg, never the Cargo.toml beside it (whose bin names its main)
if grep -q 'n="main"' "$TMP/fpy2" && has "$FPY2" "len($(grp x.report))==1 and $(grp bin)==[]"; then
    ok "F1b a shown Python main reads setup.cfg, not a Cargo.toml [[bin]] that names its file"; else no "F1b format by extension: $FPY2"; fi
# F2: a package.json path written "./bin/cli.js" resolves through the one path resolver
if has "$FDOT" "any(g['p']=='package.json' and g['l']=='8' and g['e']==[{'n':'dot-cli','target':'./bin/cli.js','def':'bin/cli.js:2'}] and 'used_at' not in g for g in $(grp bin))"; then
    ok "F2 l= is the top-level bin key (not a nested one, a value or an escaped quote in a string); a ./-prefixed package.json bin path links to its exported function; a manifest-key group carries no used_at= (a loader quoting \"bin\" is not scanned)"; else no "F2 ./ path: $FDOT"; fi
# F2b: a package.json with no "name" names its main entry by the key, not by an invented package name
if has "$FANON" "any(g['p']=='package.json' and g['e']==[{'n':'main','target':'start.js','def':'start.js:2'}] for g in $(grp main))"; then
    ok "F2b a nameless package.json main entry is n=main -> start.js:2"; else no "F2b nameless package: $FANON"; fi
# F3: Cargo literal strings ('x') and a spaced [[ bin ]] header with a trailing comment read through the shared TOML helpers
if has "$FLIT" "any(g['p']=='Cargo.toml' and g['e']==[{'n':'gen','target':'tools/gen.rs','def':'tools/gen.rs:3'}] for g in $(grp bin))"; then
    ok "F3 Cargo [[ bin ]] header + literal-string name/path -> tools/gen.rs:3 main"; else no "F3 cargo literal strings: $FLIT"; fi
# V (fix round 1 of the fold, fixtures built at run time; [P] = red on 0f256cc7): every manifest path join, Cargo's order, npm's bin name
V="$TMP/v"; mkdir -p "$V/a/up/src" "$V/a/shared" "$V/f/packages/a" "$V/f/shared" "$V/w/src/bin" "$V/w/tools" "$V/o/src/bin" "$V/s" "$V/nn" "$V/ab/src" "$V/at/src" "$V/q/pkg" "$V/qt/src" "$V/ql/src" || no "V fixture dirs"
printf '[package]\nname = "up"\n\n[[bin]]\nname = "up"\npath = "src/main.rs"\n\n[[bin]]\nname = "sharedgen"\npath = "../shared/gen.rs"\n' >"$V/a/up/Cargo.toml"
printf 'fn main() {\n    println!("up");\n}\n' >"$V/a/up/src/main.rs"; printf 'fn main() {\n    println!("gen");\n}\n' >"$V/a/shared/gen.rs"
printf '{\n  "name": "a",\n  "bin": {\n    "a-cli": "./a.js",\n    "b-cli": "../../shared/b.js"\n  }\n}\n' >"$V/f/packages/a/package.json"
printf 'export function startA() {\n  return 1;\n}\n' >"$V/f/packages/a/a.js"; printf 'export function startB() {\n  return 2;\n}\n' >"$V/f/shared/b.js"
printf '[package]\nname = "win"\n\n[[bin]]\nname = "app"\npath = "src/app.rs"\n\n[[bin]]\nname = "gen"\npath = "src\\\\bin\\\\gen.rs"\n\n[[bin]]\nname = "lit"\npath = '"'"'src\\bin\\lit.rs'"'"'\n\n[[bin]]\nname = "mid"\npath = "./tools/../src/app.rs"\n\n[[bin]]\nname = "esc"\npath = "../../../nowhere/x.rs"\n\n[[bin]]\nname = "abs"\npath = "/src/app.rs"\n' >"$V/w/Cargo.toml"
for b in app bin/gen bin/lit; do printf 'fn main() {\n    println!("x");\n}\n' >"$V/w/src/$b.rs"; done
printf '[[bin]]\nname = "ord"\n\n[[bin]]\nname = "aux"\n\n[package]\nname = "ord"\n' >"$V/o/Cargo.toml"   # [[bin]] before [package]: Cargo still names ord src/main.rs
printf 'fn main() {\n    println!("ord");\n}\n' >"$V/o/src/main.rs"; printf 'fn main() {\n    println!("aux");\n}\n' >"$V/o/src/bin/aux.rs"
printf '{\n  "name": "@acme/tool",\n  "bin": "./cli.js"\n}\n' >"$V/s/package.json"; printf 'export function startTool() {\n  return 1;\n}\n' >"$V/s/cli.js"
mkdir -p "$V/s2" && printf '{\n  "name": "@acme/objs",\n  "bin": {\n    "@acme/obj-cli": "./obj.js"\n  }\n}\n' >"$V/s2/package.json" && printf 'export function startObj() {\n  return 1;\n}\n' >"$V/s2/obj.js"
printf '{\n  "bin": "./nn.js",\n  "main": "nn.js"\n}\n' >"$V/nn/package.json"; printf 'export function startNn() {\n  return 1;\n}\n' >"$V/nn/nn.js"   # nameless: npm drops the string bin; main stays
printf '[package]\nname = "nob"\nautobins = false  # no inferred binary\n' >"$V/ab/Cargo.toml"; printf '[package]\nname = "yesb"\nautobins = true\n' >"$V/at/Cargo.toml"
for d in ab at; do printf 'fn main() {\n    println!("x");\n}\n' >"$V/$d/src/main.rs"; done
printf '[project]\nname = "qq"\ndescription = """\nExample:\n[project.scripts]\nghost = "pkg.cli:run_cli"\n"""\n\n[project.scripts]\nreal = "pkg.cli:run_real"\n' >"$V/q/pyproject.toml"
printf 'def run_cli():\n    return 1\n\n\ndef run_real():\n    return 2\n' >"$V/q/pkg/cli.py"; : >"$V/q/pkg/__init__.py"
printf '[package]\nname = "quietc"\n' >"$V/qt/Cargo.toml"; printf '[package]\nname = "loudc"\n\n[[bin]]\nname = "loudc"\npath = "src/main.rs"\n' >"$V/ql/Cargo.toml"
for d in qt ql; do printf 'fn compute_total(x: u32) -> u32 {\n    x + 1\n}\n\nfn main() {\n    let t = compute_total(2);\n    println!("{}", t);\n}\n' >"$V/$d/src/main.rs"; done
QOFF='--for=who passes the argument to compute_total and what next.run returns'
run "$V/a" "$TMP/va" '--for=cargo run --bin up main entry'
run "$V/f" "$TMP/vf" '--for=how does the a-cli command start startA startB'
run "$V/w" "$TMP/vw" '--for=cargo run --bin gen entry main'
run "$V/o" "$TMP/vo" '--for=cargo run --bin ord main entry'
run "$V/s" "$TMP/vs" '--for=how does the tool command start startTool'
run "$V/s2" "$TMP/vs2" '--for=how does the obj-cli command start startObj'
run "$V/nn" "$TMP/vnn" '--for=how does startNn start the package main'
run "$V/ab" "$TMP/vab" '--for=cargo run main entry'
run "$V/at" "$TMP/vat" '--for=cargo run main entry'
run "$V/q" "$TMP/vq" '--for=how do run_cli and run_real start'
run "$V/qt" "$TMP/vqt" "$QOFF"
run "$V/qt" "$TMP/vqtcue" '--for=what does main print when you cargo run it'
run "$V/qt" "$TMP/vqtname" '--for=what does quietc print at startup, compute_total'
run "$V/qt" "$TMP/vqtnear" '--for=what does quietcx print at startup, compute_total'
run "$V/ql" "$TMP/vql" "$QOFF"
run "$FX/cargows" "$TMP/cargowsm" '--for=how does crate-a main start'
VR="va vf vw vo vs vs2 vnn vab vat vq vqt vqtcue vqtname vqtnear vql cargowsm"
for a in $VR; do okrun "$TMP/$a" || no "run $a failed (rc=$(cat "$TMP/$a.rc"))"; done
good(){ local a; for a in "$@"; do okrun "$TMP/$a" || return 1; done; }   # every named run exited 0 and printed an answer
VA="$( eps "$TMP/va" )"; VF="$( eps "$TMP/vf" )"; VW="$( eps "$TMP/vw" )"; VO="$( eps "$TMP/vo" )"; VS="$( eps "$TMP/vs" )"; VS2="$( eps "$TMP/vs2" )"; VNN="$( eps "$TMP/vnn" )"
VAB="$( eps "$TMP/vab" )"; VAT="$( eps "$TMP/vat" )"; VQ="$( eps "$TMP/vq" )"; VQT="$( eps "$TMP/vqt" )"; VQTCUE="$( eps "$TMP/vqtcue" )"; VQTNAME="$( eps "$TMP/vqtname" )"; VQTNEAR="$( eps "$TMP/vqtnear" )"; VQL="$( eps "$TMP/vql" )"; CARGOWSM="$( eps "$TMP/cargowsm" )"
# V1 [P] a "../" target resolves to the indexed file it names, in both path formats (an indexed file never reads external=1)
if good va && has "$VA" "any(g['p']=='up/Cargo.toml' and g['e']==[{'n':'up','target':'src/main.rs','def':'up/src/main.rs:1'},{'n':'sharedgen','target':'../shared/gen.rs','def':'shared/gen.rs:1'}] for g in d)"; then
    ok "V1 Cargo path ../shared/gen.rs from up/ -> shared/gen.rs:1 main"; else no "V1 cargo ../ path: $VA"; fi
if good vf && has "$VF" "any(g['p']=='packages/a/package.json' and {'n':'b-cli','target':'../../shared/b.js','def':'shared/b.js:1'} in g['e'] and {'n':'a-cli','target':'./a.js','def':'packages/a/a.js:1'} in g['e'] for g in d)"; then
    ok "V1b package.json bin ../../shared/b.js -> shared/b.js:1, beside ./a.js"; else no "V1b package.json ../ path: $VF"; fi
# V2 [P] a Windows path (basic-string "src\\bin\\gen.rs", literal 'src\bin\lit.rs') is the same file; [G] a mid-path "tools/.." folds;
#    an escape above the root and an absolute path stay external=1 (no file there is indexed)
if good vw && has "$VW" "any(g['p']=='Cargo.toml' and {'n':'gen','target':'src\\\\\\\\bin\\\\\\\\gen.rs','def':'src/bin/gen.rs:1'} in g['e'] and {'n':'lit','target':'src\\\\bin\\\\lit.rs','def':'src/bin/lit.rs:1'} in g['e'] and {'n':'mid','target':'./tools/../src/app.rs','def':'src/app.rs:1'} in g['e'] and {'n':'esc','target':'../../../nowhere/x.rs','external':'1'} in g['e'] and {'n':'abs','target':'/src/app.rs','external':'1'} in g['e'] for g in d)"; then
    ok "V2 Windows backslash paths (basic and literal strings) and a tools/.. path resolve; an escape above the root and an absolute path stay external=1"; else no "V2 path normalization: $VW"; fi
# V3 [P] [[bin]] tables before [package]: the package's own bin defaults to src/main.rs, another to src/bin/<name>.rs
if good vo && has "$VO" "any(g['p']=='Cargo.toml' and g['l']=='1' and g['e']==[{'n':'ord','target':'src/main.rs','def':'src/main.rs:1'},{'n':'aux','target':'src/bin/aux.rs','def':'src/bin/aux.rs:1'}] for g in d)"; then
    ok "V3 [[bin]] before [package]: ord -> src/main.rs, aux -> src/bin/aux.rs (Cargo's defaults, filled after the scan)"; else no "V3 bin before package: $VO"; fi
# V4 [P] npm installs a bin under its name's last segment: a scoped string bin and a scoped object key; [P] a nameless string bin is dropped, its main stays
if good vs && has "$VS" "any(g['p']=='package.json' and g['e']==[{'n':'tool','target':'./cli.js','def':'cli.js:1'}] for g in $(grp bin))"; then
    ok "V4 scoped string bin @acme/tool installs the command tool"; else no "V4 scoped string bin: $VS"; fi
if good vs2 && has "$VS2" "any(g['e']==[{'n':'obj-cli','target':'./obj.js','def':'obj.js:1'}] for g in $(grp bin))"; then
    ok "V4b scoped object key @acme/obj-cli installs the command obj-cli"; else no "V4b scoped object key: $VS2"; fi
if good vnn && has "$VNN" "$(grp bin)==[] and any(g['e']==[{'n':'main','target':'nn.js','def':'nn.js:1'}] for g in $(grp main))"; then
    ok "V4c a nameless package.json string bin is no entry (npm drops it); its main is n=main"; else no "V4c nameless string bin: $VNN"; fi
# V5 [P] autobins = false (a trailing comment) infers no package bin; [G] autobins = true does
if good vab vat && grep -q 'n="main"' "$TMP/vab" && has "$VAB" "d==[]" && has "$VAT" "any(g['e']==[{'n':'yesb','target':'src/main.rs','def':'src/main.rs:1'}] for g in d)"; then
    ok "V5 autobins = false: no inferred bin though main is shown; autobins = true: yesb -> src/main.rs:1"; else no "V5 autobins: $VAB / $VAT"; fi
# V6 [P] a pyproject multi-line string that spells a [project.scripts] table is a value; [G] the real table after it still reads
if good vq && has "$VQ" "any(g['e']==[{'n':'real','target':'pkg.cli:run_real','def':'pkg/cli.py:5'}] for g in $(grp console_scripts)) and not any(e['n']=='ghost' for g in d for e in g['e'])"; then
    ok "V6 pyproject description = \"\"\" ... [project.scripts] ghost ... \"\"\" registers nothing; the real table after it does"; else no "V6 pyproject multi-line: $VQ"; fi
# V7 an implicit-only Cargo group (no [[bin]]) rides only on a binary cue: [P] quiet on an off-topic task whose main is shown (next.run is no cue);
#    [G] a cue word, the package name; [P] a longer word holding the name is not it; [G] an explicit [[bin]] rides on the same off-topic task
if good vqt && grep -q 'n="main"' "$TMP/vqt" && has "$VQT" "d==[]"; then
    ok "V7 implicit-only group quiet on an off-topic task (main shown, next.run not a cue)"; else no "V7 implicit group off-topic: $VQT"; fi
if good vqtcue vqtname && has "$VQTCUE" "any(g['e']==[{'n':'quietc','target':'src/main.rs','def':'src/main.rs:5'}] for g in d)" && has "$VQTNAME" "any(g['e'][0]['n']=='quietc' for g in d)"; then
    ok "V7b implicit-only group rides on a cue word (main, run) and on the package name"; else no "V7b implicit group cue: $VQTCUE / $VQTNAME"; fi
if good vqtnear && grep -q 'n="main"' "$TMP/vqtnear" && has "$VQTNEAR" "d==[]"; then
    ok "V7c 'quietcx' does not name the package quietc"; else no "V7c name boundary: $VQTNEAR"; fi
if good vql && grep -q 'n="main"' "$TMP/vql" && has "$VQL" "any(g['e']==[{'n':'loudc','target':'src/main.rs','def':'src/main.rs:5'}] for g in d)"; then
    ok "V7d an explicit [[bin]] group rides on the same off-topic task"; else no "V7d explicit group off-topic: $VQL"; fi
# B5 positive twin: at the same workspace root, a member's main is shown and its own Cargo.toml group rides; the root manifest adds none
if good cargowsm && has "$CARGOWSM" "'Cargo.toml' not in [g['p'] for g in d] and any(g['p']=='crate-a/Cargo.toml' and g['e']==[{'n':'crate-a','target':'src/main.rs','def':'crate-a/src/main.rs:3'}] for g in d)"; then
    ok "B5 positive: the workspace root run shows crate-a's own group, none from the root Cargo.toml"; else no "B5 positive twin: $CARGOWSM"; fi
# M (fix round 2, fixtures built at run time; [P] = red on 14161f0e): a package.json `main` resolves as Node loads it — the exact
#    path, then .js .ts .mjs .cjs, then /index.js /index.ts; a trailing / is a directory; `bin` stays an exact file
M="$TMP/m"; mkdir -p "$M/idx" "$M/dot/lib" "$M/slash/lib" "$M/ord" "$M/tsonly" "$M/mono/packages/a" "$M/mono/packages/b" "$M/bin/bin" || no "M fixture dirs"
fn(){ printf 'export function %s() {\n  return 1;\n}\n' "$1" >"$2"; }
printf '{\n  "name": "idx",\n  "main": "index"\n}\n' >"$M/idx/package.json"; fn startIdx "$M/idx/index.js"
printf '{\n  "name": "dotlib",\n  "main": "./lib"\n}\n' >"$M/dot/package.json"; fn startDotLib "$M/dot/lib/index.js"
printf '{\n  "name": "slashlib",\n  "main": "lib/"\n}\n' >"$M/slash/package.json"; fn startLibFile "$M/slash/lib.js"; fn startSlashLib "$M/slash/lib/index.js"
printf '{\n  "name": "ordp",\n  "main": "./app"\n}\n' >"$M/ord/package.json"; fn startAppJs "$M/ord/app.js"; fn startAppTs "$M/ord/app.ts"
printf '{\n  "name": "tsonly",\n  "main": "index"\n}\n' >"$M/tsonly/package.json"; printf 'export function startTs(): number {\n  return 1;\n}\n' >"$M/tsonly/index.ts"
printf '{\n  "name": "a",\n  "main": "index"\n}\n' >"$M/mono/packages/a/package.json"; fn startMonoA "$M/mono/packages/a/index.js"
printf '{\n  "name": "b",\n  "main": "nothing"\n}\n' >"$M/mono/packages/b/package.json"; fn startMonoB "$M/mono/packages/b/b.js"
printf '{\n  "name": "binx",\n  "bin": {\n    "cli": "bin/cli",\n    "ok": "ok.js"\n  }\n}\n' >"$M/bin/package.json"; fn startCli "$M/bin/bin/cli.js"; fn startOk "$M/bin/ok.js"
run "$M/idx" "$TMP/midx" '--for=how does startIdx start the package main'
run "$M/dot" "$TMP/mdot" '--for=how does startDotLib start the package main'
run "$M/slash" "$TMP/mslash" '--for=how do startSlashLib and startLibFile start the package main'
run "$M/ord" "$TMP/mord" '--for=how do startAppJs and startAppTs start the package main'
run "$M/tsonly" "$TMP/mts" '--for=how does startTs start the package main'
run "$M/mono" "$TMP/mmono" '--for=how do startMonoA and startMonoB start the package main'
run "$M/bin" "$TMP/mbin" '--for=how do startOk and startCli start the cli command'
MR="midx mdot mslash mord mts mmono mbin"
for a in $MR; do okrun "$TMP/$a" || no "run $a failed (rc=$(cat "$TMP/$a.rc"))"; done
MIDX="$( eps "$TMP/midx" )"; MDOT="$( eps "$TMP/mdot" )"; MSLASH="$( eps "$TMP/mslash" )"; MORD="$( eps "$TMP/mord" )"; MTS="$( eps "$TMP/mts" )"; MMONO="$( eps "$TMP/mmono" )"; MBIN="$( eps "$TMP/mbin" )"
# M1 [P] an extensionless main "index" -> index.js
if good midx && has "$MIDX" "any(g['p']=='package.json' and g['e']==[{'n':'idx','target':'index','def':'index.js:1'}] for g in $(grp main))"; then
    ok "M1 main \"index\" -> index.js:1 (the .js probe)"; else no "M1 extensionless main: $MIDX"; fi
# M2 [P] a directory main "./lib" -> lib/index.js
if good mdot && has "$MDOT" "any(g['e']==[{'n':'dotlib','target':'./lib','def':'lib/index.js:1'}] for g in $(grp main))"; then
    ok "M2 main \"./lib\" -> lib/index.js:1 (the directory index)"; else no "M2 directory main: $MDOT"; fi
# M3 [P] a trailing slash "lib/" is the directory: lib/index.js, never the lib.js beside it (both shown)
if good mslash && grep -q 'n="startLibFile"' "$TMP/mslash" && has "$MSLASH" "any(g['e']==[{'n':'slashlib','target':'lib/','def':'lib/index.js:1'}] for g in $(grp main))"; then
    ok "M3 main \"lib/\" -> lib/index.js:1, not lib.js (a trailing / skips the extension probes)"; else no "M3 trailing-slash main: $MSLASH"; fi
# M4 [P] index.ts only -> index.ts (the .ts probe)
if good mts && has "$MTS" "any(g['e']==[{'n':'tsonly','target':'index','def':'index.ts:1'}] for g in $(grp main))"; then
    ok "M4 main \"index\" with only index.ts -> index.ts:1"; else no "M4 ts-only main: $MTS"; fi
# M5 [P] the fixed order: "./app" with app.js and app.ts both present (both shown) is app.js
if good mord && grep -q 'n="startAppTs"' "$TMP/mord" && has "$MORD" "any(g['e']==[{'n':'ordp','target':'./app','def':'app.js:1'}] for g in $(grp main))"; then
    ok "M5 main \"./app\" with app.js and app.ts -> app.js:1 (.js before .ts)"; else no "M5 probe order: $MORD"; fi
# M6 [P] a miss: b's main "nothing" matches no file and rides nowhere (its b.js is shown); a's "index" beside it resolves
if good mmono && grep -q 'n="startMonoB"' "$TMP/mmono" && has "$MMONO" "[g['p'] for g in d]==['packages/a/package.json'] and d[0]['e']==[{'n':'a','target':'index','def':'packages/a/index.js:1'}]"; then
    ok "M6 a main that matches no probe resolves to nothing (no b group); a sibling package's \"index\" -> packages/a/index.js:1"; else no "M6 miss beside a hit: $MMONO"; fi
# M7 [G] a bin is an exact file: "bin/cli" stays external=1 although bin/cli.js exists; "ok.js" beside it resolves
if good mbin && has "$MBIN" "any(g['e']==[{'n':'cli','target':'bin/cli','external':'1'},{'n':'ok','target':'ok.js','def':'ok.js:1'}] for g in $(grp bin))"; then
    ok "M7 an extensionless bin \"bin/cli\" is not probed (external=1 beside bin/cli.js); ok.js -> ok.js:1"; else no "M7 bin not probed: $MBIN"; fi
# N1
okrun "$TMP/neg" && grep -q 'n="Fmt"' "$TMP/neg" && [ "$NEG" = "[]" ]; verdict $? "N1 a non-manifest .cfg yields no <ep> (Fmt shown)" "N1 config.cfg produced rows: $NEG"
# N2
for v in --json --token-budget=3000 --signatures-only; do
    run "$FX/cfg" "$TMP/n2on" "$Q" "$v"; RIPWIRE_NO_EP_MANIFEST=1 run "$FX/cfg" "$TMP/n2off" "$Q" "$v"
    if okrun "$TMP/n2on" && okrun "$TMP/n2off" && cmp -s "$TMP/n2on" "$TMP/n2off" && ! grep -q '<ep ' "$TMP/n2on"; then ok "N2 $v: no <ep>, byte-identical to off"; else no "N2 $v differs or carries <ep>"; fi
done
# N3 prefix identity (compact legend)
python3 - "$TMP/cfg" "$TMP/cfgoff" <<'PY'; verdict $? "N3 answer minus <ep> and its clause equals RIPWIRE_NO_EP_MANIFEST=1 (est_tokens masked)" "N3 prefix identity broken"
import re, sys
a = open(sys.argv[1]).read(); b = open(sys.argv[2]).read()
a = re.sub(r"<ep [^>]*>.*?</ep>", "", a, flags=re.S)
a = re.sub(r"; ep p= l= group=:.*?groups_total= if cut", "", a, flags=re.S)
# K-WRONGSYM: <syms> lists the shown files' symbols that NO WORD OF THE ANSWER names (src/forfilesyms.h), and the <ep> block names
# some (used_in=load_other), so the answer without it lists one row more. Both sides are read less the <syms> block and its legend
# comment (the rest is the prefix identity); the off side must carry the row the on side lost, or the strip proves nothing.
syms = re.compile(r'<!-- (?:ripwire for )?syms:(?:(?!-->).)*--><syms .*?</syms>(?=</ctx>)', re.S)
sa, sb = syms.search(a), syms.search(b)
twin = sa is not None and sb is not None and 'n="load_other"' in sb.group(0) and 'n="load_other"' not in sa.group(0)
a, b = syms.sub('', a), syms.sub('', b)
m = lambda s: re.sub(r'est_tokens="\d+"', 'est_tokens="N"', s)
sys.exit(0 if twin and m(a) == m(b) and a != open(sys.argv[1]).read() else 1)
PY
# R1-R3: the manifest is picked from the rows <sigs> emitted, not from the head it was asked to render
Q2='--for=load other group consumer'
run "$FX/cfg" "$TMP/r1" "$Q" --pack-budget-bytes=1
run "$FX/cfg" "$TMP/r2" "$Q2" --pack-budget-bytes=1
run "$FX/cfg" "$TMP/r3" "$Q" --pack-budget-bytes=300
for a in r1 r2 r3; do okrun "$TMP/$a" || no "run $a failed (rc=$(cat "$TMP/$a.rc"))"; done
R1="$( eps "$TMP/r1" )"; R3="$( eps "$TMP/r3" )"
if grep -q '<sigs shown="1" ' "$TMP/r1" && has "$R1" "[g['group'] for g in d]==['x.report']"; then
    ok "R1 one <sigs> row (Fmt): only the group registering it rides, not y.other / z.quiet"; else no "R1 groups for a dropped target: $R1"; fi
if grep -q '<sigs shown="1" ' "$TMP/r2" && ! grep -q '<ep ' "$TMP/r2" && ! grep -q '; ep p= l= group=' "$TMP/r2"; then
    ok "R2 no group registers an emitted row: no <ep>, no clause"; else no "R2 an <ep> or its clause rides over a row <sigs> dropped"; fi
if grep -q '<sigs shown="8" ' "$TMP/r3" && has "$R3" "sorted(g['group'] for g in d)==['x.report','y.other','z.quiet']"; then
    ok "R3 the dropped row registers nothing: all three groups stay"; else no "R3 a trim that dropped no target changed the groups: $R3"; fi
# L1
for f in cfg cfgfull; do
python3 - "$TMP/$f" <<'PY'; verdict $? "L1 $f: the clause rides and defines every <ep>/<e> attribute" "L1 $f: clause missing or an attribute undefined"
import re, sys
t = open(sys.argv[1]).read()
leg = " ".join(re.findall(r"<!--(.*?)-->", t, flags=re.S))
m = re.search(r"; ep p= l= group=:.*?(?:groups_total= if cut|the total it was cut from)", leg, flags=re.S)
if not m: sys.exit(1)
clause = m.group(0)   # the ep clause alone: p= l= n= target= are defined by the root and hops clauses too
attrs = set()
for el in re.findall(r"<(?:ep|e) ([^>]*?)/?>", re.sub(r"<!--.*?-->", "", t, flags=re.S)):
    attrs |= set(re.findall(r'(\w+)="', el))
attrs |= {"used_capped", "used_total", "entries_capped", "entries_total", "groups_capped", "groups_total"}   # present only when cut
sys.exit(0 if all(re.search(r"(?<!\w)" + a + "=", clause) for a in attrs) else 1)
PY
done
# L1-MUT: drop one definition from the ep clause (def= in the compact clause, used_capped= in both): the same check must go red
for f in cfg cfgfull; do
sed -e 's/def=file:line/DEF-GONE/' -e 's/used_capped=/USED-GONE=/' "$TMP/$f" >"$TMP/$f.mut"
python3 - "$TMP/$f.mut" <<'PY'; [ $? -ne 0 ] && okrun "$TMP/$f" && grep -q '; ep p= l= group=' "$TMP/$f"; verdict $? "L1-MUT $f: a clause without def= / used_capped= fails the L1 check" "L1-MUT $f: the L1 check passed a clause missing definitions (it cannot fail)"
import re, sys
t = open(sys.argv[1]).read()
leg = " ".join(re.findall(r"<!--(.*?)-->", t, flags=re.S))
m = re.search(r"; ep p= l= group=:.*?(?:groups_total= if cut|the total it was cut from)", leg, flags=re.S)
if not m: sys.exit(1)
clause = m.group(0)
attrs = {"def", "used_capped"}
sys.exit(0 if all(re.search(r"(?<!\w)" + a + "=", clause) for a in attrs) else 1)
PY
done
# X1 X2 X3
okrun "$TMP/cfg" && okrun "$TMP/cfg2" && grep -q '<ep ' "$TMP/cfg" && cmp -s "$TMP/cfg" "$TMP/cfg2"; verdict $? "X1 deterministic" "X1 two runs differ"
if command -v xmllint >/dev/null 2>&1; then
    for f in cfg cfgfull pyp cargo; do xmllint --noout "$TMP/$f" 2>/dev/null; verdict $? "X2 $f well-formed" "X2 $f not well-formed"; done
else
    echo "  SKIP  X2 xmllint not installed"
fi
python3 - "$TMP/cfg" "$TMP/cfgfull" <<'PY'; [ $? -eq 0 ] && okrun "$TMP/cfg" && okrun "$TMP/cfgfull" && grep -q '<!--' "$TMP/cfg" && grep -q '<!--' "$TMP/cfgfull"; verdict $? "X3 no '--' inside a legend comment" "X3 '--' inside a legend comment"
import re, sys
for f in sys.argv[1:]:
    for c in re.findall(r"<!--(.*?)-->", open(f).read(), flags=re.S):
        if "--" in c: sys.exit(1)
PY

[ "$fail" -eq 0 ] && echo "epmanifestcheck: PASS" || echo "epmanifestcheck: FAIL"
exit "$fail"
