#!/usr/bin/env bash
# epmanifestcheck.sh — MANIFEST ENTRY POINTS on a --for answer (lane ep-manifest; src/epmanifest.h; CONTRIBUTING family 10 slice 10a).
#
# THE CONTRACT THIS PINS (arms tagged [P] are RED on the pre-change binary 681b49e5; [G] arms are twins and near-miss negatives
# that hold on both binaries and must keep holding — PROCESS rule 4, no gate erosion):
#
#   TRIGGER  CLI --for (XML, default regime) whose ranked head shows a Python def that a manifest entry point names.
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
[ -f "$FX/edge/setup.cfg" ] && [ -f "$FX/edgetoml/pyproject.toml" ] && [ -f "$FX/cfg/setup.cfg" ] && [ -f "$FX/pyp/pyproject.toml" ] && [ -f "$FX/negcfg/config.cfg" ] && [ -f "$FX/sib/setup.cfg" ] && [ -f "$FX/pkgjson/package.json" ] && [ -f "$FX/pkgjsonstr/package.json" ] && [ -f "$FX/pkgjsonmiss/package.json" ] && [ -f "$FX/pkgjsonexp/package.json" ] && [ -f "$FX/pkgjsonempty/package.json" ] && [ -f "$FX/pkgjsonnm/package.json" ] && [ -f "$FX/pkgjsonnm/node_modules/dep/package.json" ] && [ -f "$FX/pkgjsonts/package.json" ] || { echo "fixture test/epmanifestfix missing"; exit 2; }

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
for a in cfg cfg2 cfgfull cfgoff pyp neg sib edge edgetoml pkgjson pkgjsonstr pkgjsonmiss pkgjsonexp pkgjsonempty pkgjsonnm pkgjsonnmdep pkgjsonts; do okrun "$TMP/$a" || no "run $a failed (rc=$(cat "$TMP/$a.rc"))"; done

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
[ "$PKGJSONEXP" = "[]" ]; verdict $? "J4 exports-only package.json yields no <ep>" "J4 exports produced rows: $PKGJSONEXP"
# J5
if grep -q 'n="idle"' "$TMP/pkgjsonempty"; then ok "J5 positive: idle row shown"; else no "J5 positive: idle row not shown"; fi
[ "$PKGJSONEMPTY" = "[]" ]; verdict $? "J5 no bin/main yields no <ep>" "J5 empty manifest produced rows: $PKGJSONEMPTY"
# J6
if has "$PKGJSONNM" "any(g['p']=='package.json' and g.get('group')=='bin' for g in d) and not any('node_modules' in g.get('p','') for g in d)"; then
    ok "J6 node_modules package.json is ignored; root bin still rides"; else no "J6 node_modules: $PKGJSONNM"; fi
if grep -q 'n="depStart"' "$TMP/pkgjsonnmdep"; then ok "J6b positive: depStart row shown"; else no "J6b positive: depStart row not shown"; fi
if grep -q 'n="rootStart"' "$TMP/pkgjsonnm"; then ok "J6b positive: root bin row shown in sibling root fixture"; else no "J6b positive: rootStart row not shown in pkgjsonnm"; fi
[ "$PKGJSONNMDEP" = "[]" ]; verdict $? "J6b a package.json under node_modules yields no <ep>" "J6b node_modules package.json produced rows: $PKGJSONNMDEP" 
# J7
if grep -q 'n="run"' "$TMP/pkgjsonts"; then ok "J7 positive: run row shown (src/index.ts)"; else no "J7 positive: run row not shown"; fi
[ "$PKGJSONTS" = "[]" ]; verdict $? "J7 TS main -> missing dist/ yields no <ep>" "J7 TS dist main produced rows: $PKGJSONTS" 
# N1
[ "$NEG" = "[]" ]; verdict $? "N1 a non-manifest .cfg yields no <ep>" "N1 config.cfg produced rows: $NEG"
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
m = lambda s: re.sub(r'est_tokens="\d+"', 'est_tokens="N"', s)
sys.exit(0 if m(a) == m(b) and a != open(sys.argv[1]).read() else 1)
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
python3 - "$TMP/$f.mut" <<'PY'; [ $? -ne 0 ]; verdict $? "L1-MUT $f: a clause without def= / used_capped= fails the L1 check" "L1-MUT $f: the L1 check passed a clause missing definitions (it cannot fail)"
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
cmp -s "$TMP/cfg" "$TMP/cfg2"; verdict $? "X1 deterministic" "X1 two runs differ"
if command -v xmllint >/dev/null 2>&1; then
    for f in cfg cfgfull pyp; do xmllint --noout "$TMP/$f" 2>/dev/null; verdict $? "X2 $f well-formed" "X2 $f not well-formed"; done
else
    echo "  SKIP  X2 xmllint not installed"
fi
python3 - "$TMP/cfg" "$TMP/cfgfull" <<'PY'; verdict $? "X3 no '--' inside a legend comment" "X3 '--' inside a legend comment"
import re, sys
for f in sys.argv[1:]:
    for c in re.findall(r"<!--(.*?)-->", open(f).read(), flags=re.S):
        if "--" in c: sys.exit(1)
PY

[ "$fail" -eq 0 ] && echo "epmanifestcheck: PASS" || echo "epmanifestcheck: FAIL"
exit "$fail"
