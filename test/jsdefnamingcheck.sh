#!/usr/bin/env bash
# jsdefnamingcheck.sh — JS/TS definitions carry the names the source gives them (lane js-def-naming):
#   (1) a JS/TS method row prints the class whose body holds it (memberowner.h, by graph.h containedOwnersOf — the rule the
#       written-spelling tier binds `Class.method` by), so two same-file namesakes read Environment.render / Template.render;
#       and a printed p= (`file:LINE`, a definition's own signature line) is a selector, tried only after every name tier;
#   (2) a module-scope object literal records its binding name (model.h LocalBindKind::JsObjectLiteral), so `Widget.run`
#       beside both `const Widget = { run() {} }` and `class Widget { run() {} }` is unknown, never the class alone;
#   (3) a bare `module.exports = <anonymous fn>` is a function named by the file's stem (`is-stream`).
#
# RED-FIRST (recorded 2026-10-27 against the base binary built_from=bbbb5c5c1): every arm marked RED failed there; every
# KEEP arm already passed. Fix 1 (review rv-js-def-naming F3/F2/F4/G1) is red on the pre-fix lane binary (built_from=140e35830, same
# behaviour as 9717ead0): the two oneline.js refusals, Widget.run's found="2", and the four namespace arms (Gate.open, Zone.Gate.open,
# Zone2.Door.close, Door.close's count). Each target calls its own helper, which is the discriminator the arms grep for.
#
# Usage:  test/jsdefnamingcheck.sh [BIN]   (BIN falls back to RIPWIRE_BIN, then build/ripwire). Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/jsdefnamingfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "jsdefnamingcheck: BIN=$BIN  FIX=$FIX"

run(){ local sub="$1"; shift; ( cd "$FIX/$sub" && "$BIN" "$FIX/$sub" --no-cache "$@" 2>&1 ); }
# has SUB 'LABEL' NEEDLE ARGS...: the answer exits 0 and contains NEEDLE (a fixed string)
has(){
    local sub="$1" label="$2" needle="$3"; shift 3
    local out rc; out="$( run "$sub" "$@" )"; rc=$?
    if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -qF -- "$needle"; then ok "$label"; else no "$label (rc=$rc, want $needle)"; printf '%s\n' "$out" | tail -c 400; echo; fi
}
# lacks SUB 'LABEL' NEEDLE ARGS...: the run exits 0 (a crash is not an absence) and the answer does not contain NEEDLE. An absence-only arm
# needs a `has` control on the same run (fix 1, G1): a needle that cannot occur passes whatever the answer says.
lacks(){
    local sub="$1" label="$2" needle="$3"; shift 3
    local out rc; out="$( run "$sub" "$@" )"; rc=$?
    if [ "$rc" -ne 0 ]; then no "$label (rc=$rc: the run failed, so its absence proves nothing)"; printf '%s\n' "$out" | tail -c 400; echo
    elif printf '%s' "$out" | grep -qF -- "$needle"; then no "$label (found $needle)"; printf '%s\n' "$out" | tail -c 400; echo; else ok "$label"; fi
}
# bind SUB SPEC WANT [NOT...]: --callees=SPEC exits 0, names helper WANT and none of NOT
bind(){
    local sub="$1" spec="$2" want="$3"; shift 3
    local out rc bad=""; out="$( run "$sub" --callees="$spec" )"; rc=$?
    for n in "$@"; do printf '%s' "$out" | grep -q "n=\"$n\"" && bad="$bad $n"; done
    if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "n=\"$want\"" && [ -z "$bad" ]; then ok "bind   $sub $spec -> $want"
    else no "bind   $sub $spec (rc=$rc, want $want, wrong:$bad)"; printf '%s\n' "$out" | tail -c 400; echo; fi
}
# refuse SUB SPEC [N [NAME...]]: --callees=SPEC exits 1 with found="0" (the contract: nothing listed) and, when N > 1, refused="N" (N
# definitions fit, none chosen — the true count, fix 1 F4; N omitted: nothing matched, no refused=) and, for each NAME, a stderr line listing it
refuse(){
    local sub="$1" spec="$2" n="${3:-0}" out rc want='found="0"'; [ "$#" -ge 3 ] && shift 3 || shift 2
    [ "$n" -gt 1 ] && want="found=\"0\" refused=\"$n\""
    out="$( run "$sub" --callees="$spec" )"; rc=$?
    local missing=""; for nm in "$@"; do printf '%s' "$out" | grep -qF -- "$nm" || missing="$missing $nm"; done
    if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qF -- "$want" && [ -z "$missing" ]; then ok "refuse $sub $spec ($want)"
    else no "refuse $sub $spec (rc=$rc, want $want, unlisted:$missing)"; printf '%s\n' "$out" | tail -c 400; echo; fi
}

echo "-- (1) a JS method row names the class whose body holds it"
has   js 'RED  --callers rows: Template.render'               'n="Template.render" p="src/environment.js:8"'    --callers=jdnTplHelper
has   js 'RED  --callers rows: Environment.render'            'n="Environment.render" p="src/environment.js:2"' --callers=jdnEnvHelper
has   js 'RED  --path hop rows print the owner'                '<s t="method" n="Template.render"'               --path=Template.render,jdnTplHelper
has   js 'RED  the TS/JS owner clause rides with such a row'   'On a TS/JS row Owner is the class'               --legend=full --callers=jdnTplHelper
has   js 'KEEP ... the same run answers (control for the absence)' 'n="onlyNamed"'                              --legend=full --callers=jdnNamedHelper
lacks js 'KEEP no owner row, no TS/JS owner clause'            'On a TS/JS row Owner'                            --legend=full --callers=jdnNamedHelper
has   js 'KEEP a free function row prints, bare (control)'     'n="onlyNamed"'                                   --callers=jdnNamedHelper
lacks js 'KEEP a free function row is not owned'               '.onlyNamed"'                                     --callers=jdnNamedHelper
lacks js 'KEEP a member of a literal a method returns stays bare' 'n="Nest.inner"'                               --callers=jdnNestHelper
has   js 'KEEP ... and still prints, bare'                     'n="inner"'                                       --callers=jdnNestHelper
bind  js 'Template.render' jdnTplHelper jdnEnvHelper           # KEEP: the printed name resolves back (written-spelling tier)

echo "-- (1) a printed p= (file:LINE) selects that definition, after every name tier"
bind   js 'src/environment.js:8' jdnTplHelper jdnEnvHelper     # RED: Template.render's own line
bind   js 'src/environment.js:2' jdnEnvHelper jdnTplHelper     # RED: Environment.render's
refuse js 'src/environment.js:3'                               # KEEP: a body line names no definition
refuse js 'src/environment.js:99'                              # KEEP: past the end
# fix 1 F3: two definitions starting on one line are refused (they were: the innermost, unnamed), listing each n= the answer would print
refuse js 'src/oneline.js:1' 2 'n=OneP' 'n=OneP.oq'            # RED: `class OneP { oq() {} }`
refuse js 'src/oneline.js:3' 2 'n=innerArrow' 'n=outerArrow'   # RED: a nested arrow on its parent's line
has    js 'KEEP one definition on its line still selects (oneline.js:2)' 'n="OneP.oq"' --callers=src/oneline.js:2
has    js 'KEEP a numeric name beats the line (cfg.json:3 = both keys "3")' 'defs="2"' --callers=lib/cfg.json:3
has    js 'RED  a line no name spells binds by line (cfg.json:4 = key x)'   'defs="1"' --callers=lib/cfg.json:4

echo "-- (2) an object literal named like a class makes the spelling unknown"
refuse ts 'Widget.run' 2                                       # RED: base bound the class's run beside the literal's; fix 1 F4: found="2", not "0"
bind   ts 'src/widget-class.ts:Widget.run' jdnClassHelper jdnLitHelper   # KEEP: the file narrows to the class
bind   ts 'Kit.run' jdnKitHelper jdnLitHelper                  # KEEP: a literal with another name (kitMock) is not Kit

echo "-- (1) a class inside a TS namespace: the printed owner row and the full chain both resolve back (fix 1 F2)"
has    ts 'KEEP the row prints the class alone (the name the next arms feed back)' 'n="Gate.open"'                                    --callers=jdnNsHelper
bind   ts 'Gate.open' jdnNsHelper                              # RED: the printed name resolves back
bind   ts 'Zone.Gate.open' jdnNsHelper                         # RED: ... and so does the namespace-qualified spelling
bind   ts 'Zone2.Door.close' jdnNsHelper                       # KEEP-able: the full chain tells two same-named classes apart
refuse ts 'Door.close' 2                                       # KEEP: the printed name is shared by two namespaces' classes: refused, with its count

echo "-- (3) a bare module.exports function is named by its file's stem"
bind   js 'is-stream' jdnStreamHelper                          # RED: base had no symbol (the calls sat in <file-scope>)
bind   js 'onlyNamed' jdnNamedHelper                           # KEEP: a named function expression keeps its own name
refuse js 'only'                                               # KEEP: ... and is not also the stem
bind   js 'propFn' jdnPropHelper                               # KEEP: module.exports.NAME = fn is NAME
refuse js 'prop'
refuse js 'decoy'                                              # KEEP: moduleLike.exports / a local `exports2` export nothing

[ "$fail" -eq 0 ] && echo "jsdefnamingcheck: PASS" || echo "jsdefnamingcheck: FAIL"
exit "$fail"
