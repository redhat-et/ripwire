#!/usr/bin/env bash
# yamllangcheck.sh — YAML config-key ingest coverage gate.
#
# ripwire indexes YAML (.yml/.yaml) as a DATA language, the same posture as JSON/TOML: mapping
# keys become searchable symbols (t="sec") so CI workflows / k8s manifests / ansible playbooks
# are findable by --for / --grep with their enclosing key as the symbol — but YAML emits NO call
# edges and a YAML key NEVER resolves a same-spelled code symbol (lang-incompatible with
# everything, graph.h::langCompatible).
#
# THE TWO THINGS THIS GATE EXISTS TO PIN — and why it is a copy of neither sibling gate:
#   1. SEQUENCE TRANSPARENCY. JSON's rule is "top-level + second-level object keys". Applied
#      literally to YAML it captures 27.1% of real keys, and 25.3% of ALL keys — the
#      `steps:` / `containers:` / `tasks:` shape, keys directly inside a sequence element — are
#      dropped 100%. YAML's rule is mapping-depth <= 2 with sequence levels NOT counted (44.0%
#      measured on the breadth corpus). The tasks.yaml arms are red against a literal JSON port.
#   2. THE PRE-PARSE DEPTH GUARD. tree-sitter-yaml's external scanner serialize() writes 4 bytes
#      per indent level behind a guard that only proves 1 fits: at 254 block indent levels it
#      writes past the end of the 1024-byte serialization buffer (SIGABRT in a plain build,
#      SILENT memory corruption under NDEBUG). ripwire refuses such files BEFORE any parse via an
#      O(n) byte prescan (ingest.h kMaxYamlNestDepth), and the vendored scanner itself carries the
#      one-line bounds fix under the third_party/patches convention. The deep-indent arm below
#      generates a file PAST the cliff — under the asan flavour that arm is a live tripwire for
#      BOTH layers (guard gone AND patch gone = out-of-bounds write = hard failure).
#
# Measured on the breadth corpus (90 public repos, bench-assets/r4/repos) — the numbers that
# chose this design, recorded so a future reader can re-derive it (see docs/EVALS.md §6):
#   4 449 YAML files / 34 209 keys (570 of them GitHub workflow files). JSON's root-depth rule
#   captures 27.1%; sequence-transparent mdepth<=2 captures 44.0%. Anchors in 1.73% of files,
#   aliases 1.55% (alias-AS-KEY: 0 in 4 449 files), merge keys 0.22%, multi-doc 0.11% (max 5
#   docs), block scalars in 20.5% of files — 384 of them contain key-like text a regex would
#   mint symbols from (the strongest argument for a real parser). Size ceiling 512 KB, not
#   JSON's 256 KB, which would drop NeMo's real 293 KB cicd-main.yml.
#
# Fixtures (test/yamlfix/): workflow.yml (GH-Actions-shaped: anchors, merge key, block scalar,
# flow mapping, quoted/dotted/non-string keys, duplicate keys), multidoc.yml (--- streams),
# tasks.yaml (the sequence-transparency shape, and the .yaml sibling extension).
#
# Usage:
#   test/yamllangcheck.sh
#   RIPWIRE_BIN=asan/ripwire test/yamllangcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.
# Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/yamlfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for XML assertions"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }

echo "yamllangcheck: BIN=$BIN  FIX=$FIX"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== presence guards: the fixtures really contain what the arms below assert ==="
# ═══════════════════════════════════════════════════════════════════════════
# CONTRIBUTING §2 / METHODOLOGY §1 "vanished probe target": every arm below searches the map
# for a construct. If a fixture ever stops SPELLING that construct, the arm would pass by
# finding nothing on both sides. Assert the probe target exists before asserting the property.
WF="$FIX/workflow.yml"; MD="$FIX/multidoc.yml"; TK="$FIX/tasks.yaml"
for f in "$WF" "$MD" "$TK"; do [ -f "$f" ] || { echo "fixture file $f missing"; exit 2; }; done
guard(){ if grep -qF -- "$2" "$1"; then ok "fixture contains $3"; else no "fixture LOST $3 — every arm below would pass by finding nothing"; fi; }
guard "$WF" 'pipelinename:'        'a top-level key  pipelinename:'
guard "$WF" 'branchfilter:'        'a depth-3 key  branchfilter:'
guard "$WF" 'stepslist:'           'a depth-3 key owning a sequence  stepslist:'
guard "$WF" '&anchordefaults'      'an anchor  &anchordefaults'
guard "$WF" '<<: *anchordefaults'  'a merge key  <<: *anchordefaults'
guard "$WF" 'scriptrun: |'         'a literal block scalar  scriptrun: |'
guard "$WF" 'fakekeyinscalar: 1'   'key-like text INSIDE the block scalar  fakekeyinscalar:'
guard "$WF" '1234: '               'a non-string key  1234:'
guard "$WF" 'dotted.plain.key:'    'a dotted plain key  dotted.plain.key:'
guard "$WF" '"quoted.dotted":'     'a quoted key  "quoted.dotted":'
guard "$WF" 'flowopts: {'          'a flow mapping  flowopts: { … }'
guard "$MD" 'doctwochild:'         'a second-document depth-2 key  doctwochild:'
guard "$TK" '- taskitemname:'      'a key directly inside a sequence element  - taskitemname:'
guard "$TK" '- - nestedseqkey:'    'a key under a nested sequence  - - nestedseqkey:'
[ "$( grep -c '^dupkey:' "$WF" )" -eq 2 ] \
    && ok "fixture has 2 dupkey: spellings (the duplicate-keys-both-minted arm has something to count)" \
    || no "fixture no longer has exactly 2 top-level dupkey: lines"
[ "$( grep -c '^---$' "$MD" )" -eq 2 ] \
    && ok "fixture multidoc.yml has 2 document markers" \
    || no "fixture multidoc.yml no longer has exactly 2 --- markers"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== default map: exits 0, well-formed, clean stderr, edges=0 ==="
# ═══════════════════════════════════════════════════════════════════════════
MAP_OUT="$TMP/map.xml"
$BIN "$FIX" --no-cache >"$MAP_OUT" 2>"$TMP/map.err"
MAP_EXIT=$?
if [ "$MAP_EXIT" -eq 0 ]; then ok "default map: exits 0 on YAML fixture"; else no "default map: exited $MAP_EXIT: $( cat "$TMP/map.err" )"; fi

command -v xmllint >/dev/null 2>&1 && { if xmllint --noout "$MAP_OUT"; then ok "default map: passes xmllint --noout"; else no "default map: xmllint failed"; fi; }

# no degrade / ABI-mismatch warning must reach stderr on the clean fixtures
[ -s "$TMP/map.err" ] && no "default map: unexpected stderr (ABI/degrade?): $( cat "$TMP/map.err" )" || ok "default map: clean stderr (no ABI mismatch / degrade)"

# edges=0: YAML is data, no call graph
EDGES="$( grep -o 'edges=[0-9]*' "$MAP_OUT" | head -1 )"
if [ "$EDGES" = "edges=0" ]; then ok "default map: $EDGES (YAML is data — no call edges)"; else no "default map: expected edges=0, got $EDGES"; fi

# ─── parse per-file symbols once ────────────────────────────────────────────
python3 - "$MAP_OUT" <<'PYEOF' >"$TMP/parsed.json"
import sys, re, json, html
xml = open(sys.argv[1], encoding='utf-8').read()
files = re.findall(r'<f p="([^"]+)"[^>]*>(.*?)</f>', xml, re.S)
out = {}
for path, body in files:
    name = path.split('/')[-1]
    syms = []
    for sm in re.finditer(r'<s t="(\w+)" n="([^"]*)"([^>]*)', body):
        t, n, rest = sm.group(1), html.unescape(sm.group(2)), sm.group(3)
        # same-name defs are MERGED into one row carrying overloads="N" (see the map legend), so the
        # def count for a name is 1 unless the row says otherwise.
        ov = re.search(r'overloads="(\d+)"', rest)
        syms.append({"t": t, "n": n, "defs": int(ov.group(1)) if ov else 1})
    out[name] = syms
print(json.dumps(out))
PYEOF

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== the design table: mapping-depth <= 2, sequences transparent, values never descended ==="
# ═══════════════════════════════════════════════════════════════════════════
python3 - "$TMP/parsed.json" <<'PYEOF' >"$TMP/yaml_check"
import json, sys
d = json.load(open(sys.argv[1]))
wf = d.get("workflow.yml", []); md = d.get("multidoc.yml", []); tk = d.get("tasks.yaml", [])
allsyms = wf + md + tk
wfn = set(s["n"] for s in wf); mdn = set(s["n"] for s in md); tkn = set(s["n"] for s in tk)

# depth-1 and depth-2 keys — the capture set
d1 = {"pipelinename", "on", "jobsblock", "defaultsblock", "prodtarget",
      "1234", "dotted.plain.key", '"quoted.dotted"', "flowopts", "dupkey"}
d2 = {"pushtrigger", "buildjob", "timeoutmins", "scriptrun", "flowa", "flowb"}
# depth >= 3 keys — dropped by the rule
d3plus = {"branchfilter", "runsondrop", "stepslist", "usesaction", "stepname", "runcmd"}
# never symbols: the anchor's name, the merge key, block-scalar interior text, split dotted parts
never = {"anchordefaults", "<<", "fakekeyinscalar", "anotherfakekey", "quoted.dotted", "key"}

print("SYMS:%d" % len(allsyms))
print("ALL_SEC:%s" % (all(s["t"] == "sec" for s in allsyms) if allsyms else False))
print("D1_OK:%s"   % d1.issubset(wfn));  print("MISSING_D1:%s" % (",".join(sorted(d1 - wfn)) or "none"))
print("D2_OK:%s"   % d2.issubset(wfn));  print("MISSING_D2:%s" % (",".join(sorted(d2 - wfn)) or "none"))
print("D3_DROPPED:%s" % (not (d3plus & wfn))); print("LEAKED_D3:%s" % (",".join(sorted(d3plus & wfn)) or "none"))
print("NEVER_OK:%s" % (not (never & wfn))); print("LEAKED_NEVER:%s" % (",".join(sorted(never & wfn)) or "none"))
# sequence transparency: keys directly inside sequence elements are depth 1 / 2
seq_keys = {"taskitemname", "aptmodule", "pkgnamekey", "nestedseqkey"}
print("SEQ_OK:%s"  % seq_keys.issubset(tkn)); print("MISSING_SEQ:%s" % (",".join(sorted(seq_keys - tkn)) or "none"))
# multi-doc: each document re-enters at depth 1
mdoc = {"docone", "doctwo", "doctwochild"}
print("MDOC_OK:%s" % mdoc.issubset(mdn)); print("MISSING_MDOC:%s" % (",".join(sorted(mdoc - mdn)) or "none"))
# duplicate keys: BOTH minted (one merged row carrying overloads=2)
print("DUP_DEFS:%d" % sum(s["defs"] for s in wf if s["n"] == "dupkey"))
# merge key not expanded: the anchored map's key exists ONCE (a `<<:` expansion would add a second def)
print("MERGE_DEFS:%d" % sum(s["defs"] for s in wf if s["n"] == "timeoutmins"))
PYEOF
cat "$TMP/yaml_check"

grep -q "SYMS:0" "$TMP/yaml_check" \
    && no "yamlfix: extracted ZERO symbols — .yml/.yaml is not indexed at all" \
    || ok "yamlfix: extracted $( grep -o '^SYMS:[0-9]*' "$TMP/yaml_check" | cut -d: -f2 ) symbol(s)"
grep -q "ALL_SEC:True" "$TMP/yaml_check" \
    && ok "every symbol tagged t=\"sec\"" \
    || no "some symbols are not t=\"sec\" (or none extracted)"
grep -q "D1_OK:True" "$TMP/yaml_check" \
    && ok "top-level keys are symbols (incl. non-string \`on\`/\`1234\` under their LITERAL text, dotted key whole, quoted key with quotes)" \
    || no "missing depth-1 keys: $( grep '^MISSING_D1:' "$TMP/yaml_check" )"
grep -q "D2_OK:True" "$TMP/yaml_check" \
    && ok "depth-2 keys are symbols (block AND flow mapping style)" \
    || no "missing depth-2 keys: $( grep '^MISSING_D2:' "$TMP/yaml_check" )"
grep -q "D3_DROPPED:True" "$TMP/yaml_check" \
    && ok "depth>=3 keys are NOT symbols (the mdepth<=2 cut)" \
    || no "depth>=3 keys leaked in: $( grep '^LEAKED_D3:' "$TMP/yaml_check" )"
grep -q "NEVER_OK:True" "$TMP/yaml_check" \
    && ok "no symbol for: anchor name / \`<<\` merge key / block-scalar interior / split dotted parts / unquoted quoted-key" \
    || no "forbidden symbols minted: $( grep '^LEAKED_NEVER:' "$TMP/yaml_check" )"
grep -q "SEQ_OK:True" "$TMP/yaml_check" \
    && ok "sequence transparency: keys inside sequence elements (tasks.yaml, .yaml ext) ARE symbols — the 25.3% shape JSON's rule drops" \
    || no "sequence-element keys MISSING: $( grep '^MISSING_SEQ:' "$TMP/yaml_check" ) — this is JSON's root-depth rule ported literally"
grep -q "MDOC_OK:True" "$TMP/yaml_check" \
    && ok "multi-document stream: each document re-enters at depth 1" \
    || no "multi-doc keys missing: $( grep '^MISSING_MDOC:' "$TMP/yaml_check" )"
grep -q "^DUP_DEFS:2$" "$TMP/yaml_check" \
    && ok "duplicate keys: both minted (2 defs, one row carrying overloads=2)" \
    || no "duplicate-key def count wrong: $( grep '^DUP_DEFS:' "$TMP/yaml_check" ) (expected 2)"
grep -q "^MERGE_DEFS:1$" "$TMP/yaml_check" \
    && ok "merge key dropped, alias never expanded: \`timeoutmins\` has exactly 1 def" \
    || no "merge/alias handling wrong: $( grep '^MERGE_DEFS:' "$TMP/yaml_check" ) (expected 1 — an expansion would mint a second def)"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== --grep lands on a yaml key (the navigable unit), cold and through the cache ==="
# ═══════════════════════════════════════════════════════════════════════════
# A dotted plain key must survive as ONE name all the way to a verb's enclosing-symbol field:
# ingest's generic def path runs captured names through finalSegment(), which splits on "." and
# would report this hit as in="key" — a name that collides with every other `key` in a repo.
GREP_OUT="$( $BIN "$FIX" --grep=dotted.plain.key --no-cache 2>/dev/null )"
echo "$GREP_OUT" | grep -q 'in="dotted.plain.key"' \
    && ok "--grep=dotted.plain.key (cold): enclosing symbol in=\"dotted.plain.key\" (config is navigable)" \
    || no "--grep=dotted.plain.key (cold) did not report in=\"dotted.plain.key\": $GREP_OUT"

# …and again WARM, through a cache round-trip, in a cache dir this gate owns: the name is
# persisted and reloaded rather than recomputed, so a serialization that re-split it would be
# invisible to every cold arm. The private TMPDIR makes the arm un-satisfiable by a developer's
# warm cache and un-poisonable by one (the trap tomllangcheck actually hit).
CACHEDIR="$TMP/tmpdir"; mkdir -p "$CACHEDIR"
TMPDIR="$CACHEDIR" $BIN "$FIX" >/dev/null 2>&1                               # cold: populate
GREP_WARM="$( TMPDIR="$CACHEDIR" $BIN "$FIX" --grep=dotted.plain.key 2>/dev/null )"
echo "$GREP_WARM" | grep -q 'in="dotted.plain.key"' \
    && ok "--grep=dotted.plain.key (warm): the dotted name survives the cache round-trip" \
    || no "--grep=dotted.plain.key (warm) did not report in=\"dotted.plain.key\": $GREP_WARM"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== cross-language isolation: a YAML key never becomes a code edge target ==="
# ═══════════════════════════════════════════════════════════════════════════
# Mirrors the json/toml isolation arms, INCLUDING the mutation: without it, an "edges=1"
# assertion is satisfied for free by a build in which YAML contributes nothing.
XL="$TMP/yamlxlang"; mkdir -p "$XL"
cat > "$XL/deploy.yml" <<'YAMLEOF'
serde: a yaml key spelled like a js function
YAMLEOF
cat > "$XL/app.js" <<'JSEOF'
function serde() { return 1; }
function main() { return serde(); }
JSEOF
XL_OUT="$( $BIN "$XL" --no-cache 2>/dev/null )"
XL_EDGES="$( echo "$XL_OUT" | grep -o 'edges=[0-9]*' | head -1 )"
if [ "$XL_EDGES" = "edges=1" ]; then ok "mixed YAML+JS: $XL_EDGES (only the JS-internal main->serde edge)"; else no "mixed YAML+JS: expected edges=1, got $XL_EDGES"; fi
# the YAML side must actually be in the map, or the isolation claim is vacuous
if echo "$XL_OUT" | grep -q 'deploy.yml'; then ok "mixed YAML+JS: deploy.yml IS indexed (isolation arm is not vacuous)"; else no "mixed YAML+JS: deploy.yml absent from the map"; fi
XL_CR="$( $BIN "$XL" --callers=serde --no-cache 2>/dev/null )"
echo "$XL_CR" | grep -q 'count="1"' && echo "$XL_CR" | grep -q 'app.js' \
    && ok "--callers=serde: count=1, from app.js (the YAML \`serde\` key is NOT a caller/target)" \
    || no "--callers=serde unexpected (YAML key leaked into the graph?): $XL_CR"

# mutation: rename the JS call site → the ONLY edge must vanish (non-tautological)
sed 's/return serde()/return serdeX()/' "$XL/app.js" >"$XL/app.js.tmp" && mv "$XL/app.js.tmp" "$XL/app.js"
XL_MUT="$( $BIN "$XL" --no-cache 2>/dev/null | grep -o 'edges=[0-9]*' | head -1 )"
if [ "$XL_MUT" = "edges=0" ]; then ok "mutation: renamed JS call site → edges=0 (the edge assertion is real)"; else no "mutation: expected edges=0 after rename, got $XL_MUT"; fi

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== determinism: default map twice, byte-identical ==="
# ═══════════════════════════════════════════════════════════════════════════
$BIN "$FIX" --no-cache >"$TMP/det_a.xml" 2>/dev/null
$BIN "$FIX" --no-cache >"$TMP/det_b.xml" 2>/dev/null
diff -q "$TMP/det_a.xml" "$TMP/det_b.xml" >/dev/null \
    && ok "determinism: default map byte-identical across two runs" \
    || no "determinism: default map differs across runs"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== the pre-parse depth guard: past-the-cliff indentation is refused BEFORE any parse ==="
# ═══════════════════════════════════════════════════════════════════════════
# tree-sitter-yaml's serialize() cliff is at ~253 block indent levels (see the header). This arm
# generates a file PAST the cliff. Contract: exit 0, the file is SKIPPED with a one-line stderr
# note (the JSON deep-nest house style), and it contributes no symbols. Under the asan flavour
# this arm is the live tripwire for both protective layers: if the prescan guard AND the vendored
# scanner patch both regressed, the out-of-bounds write aborts the run right here.
DEEP="$TMP/deepyaml"; mkdir -p "$DEEP"
python3 - "$DEEP/deep.yml" <<'PYEOF'
import sys
with open(sys.argv[1], "w") as f:
    for i in range(300):                       # 300 block indent levels — past the 253-level cliff
        f.write(" " * i + "deepnest%d:\n" % i)
    f.write(" " * 300 + "leafdeep: 1\n")
PYEOF
$BIN "$DEEP" --no-cache >"$TMP/deep.xml" 2>"$TMP/deep.err"
DEEP_EXIT=$?
if [ "$DEEP_EXIT" -eq 0 ]; then ok "deep-indent: exits 0 (no SIGABRT — guard + patch both live)"; else no "deep-indent: exited $DEEP_EXIT (the serialize() cliff?): $( cat "$TMP/deep.err" | head -3 )"; fi
grep -q "yaml nesting" "$TMP/deep.err" \
    && ok "deep-indent: skipped with the one-line stderr note (house skip style)" \
    || no "deep-indent: no 'yaml nesting' skip note on stderr: $( cat "$TMP/deep.err" | head -3 )"
grep -q 'deepnest0' "$TMP/deep.xml" \
    && no "deep-indent: deep.yml was PARSED (guard did not fire before the parse)" \
    || ok "deep-indent: deep.yml contributes no symbols (refused before the parse)"

# …and the guard must not over-fire: ordinary real-world nesting stays indexed
NORM="$TMP/normyaml"; mkdir -p "$NORM"
python3 - "$NORM/normal.yml" <<'PYEOF'
import sys
with open(sys.argv[1], "w") as f:
    for i in range(12):                        # 12 levels — deeper than any common workflow/manifest
        f.write("  " * i + "normalnest%d:\n" % i)
    f.write("  " * 12 + "normalleaf: 1\n")
PYEOF
$BIN "$NORM" --no-cache >"$TMP/norm.xml" 2>"$TMP/norm.err"
grep -q 'normalnest0' "$TMP/norm.xml" \
    && ok "guard calibration: a 12-level file is still indexed (its top-level key is a symbol)" \
    || no "guard calibration: a 12-level file was dropped — the depth guard over-fires"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== KNOWN GAP (help wanted: prompts/help-wanted/nesting-refusals-visible.md): the refused deep.yml is invisible to --skipped and to warm runs, and --match parses it anyway ==="
# ═══════════════════════════════════════════════════════════════════════════
# The depth guard above refuses deep.yml before the parse, and says so ONLY as one stderr line on a COLD run.
# Measured on main:
#   - --skipped never rows the file; its only trace is an anonymous unmeasured="1";
#   - a warm run stat-hits the cache record saveCache wrote for it, so nothing is printed at all;
#   - --match's structural-query walk (astQueryGrouped) parses the refused file with no prescan, which leaves the
#     vendored scanner patch as that path's only layer.
# Each KNOWN GAP arm asserts TODAY's behaviour, so it PASSES now. Flipping them is the acceptance test for the
# prompt: a refused file is rowed in --skipped on cold AND warm runs, and --match applies the same refusal. A FAIL
# on a KNOWN GAP arm means the gap moved: rewrite the arm to assert the fixed behaviour, never delete it.
KGY="$TMP/kgyaml"; mkdir -p "$KGY"
cp "$DEEP/deep.yml" "$KGY/deep.yml"
printf 'kgsiblingkey: 1\n' > "$KGY/sibling.yml"
$BIN "$KGY" --cache="$TMP/kgyaml.cache" >"$TMP/kgy_cold.xml" 2>"$TMP/kgy_cold.err"; KGY_COLD_RC=$?
$BIN "$KGY" --cache="$TMP/kgyaml.cache" >"$TMP/kgy_warm.xml" 2>"$TMP/kgy_warm.err"; KGY_WARM_RC=$?
KGY_LIVE=0
if [ "$KGY_COLD_RC" -eq 0 ] && [ "$KGY_WARM_RC" -eq 0 ] && grep -q 'deep.yml: yaml nesting' "$TMP/kgy_cold.err" \
   && grep -q 'kgsiblingkey' "$TMP/kgy_warm.xml" && cmp -s "$TMP/kgy_cold.xml" "$TMP/kgy_warm.xml"; then
    ok "(kg-yaml) presence: the cold run refuses deep.yml on stderr; the warm run serves the same map from the cache, sibling indexed"
    KGY_LIVE=1
else
    no "(kg-yaml) presence: expected rc=0 twice, a cold refusal note for deep.yml and a warm map identical to the cold one (cold rc=$KGY_COLD_RC, warm rc=$KGY_WARM_RC) — the arms below would be vacuous: $( head -2 "$TMP/kgy_cold.err" )"
fi
if [ "$KGY_LIVE" -eq 1 ]; then
    grep -q 'deep.yml' "$TMP/kgy_warm.err" \
        && no "KNOWN GAP MOVED (prompts/help-wanted/nesting-refusals-visible.md): the warm run now names deep.yml on stderr — rewrite this arm to assert the warm refusal is visible" \
        || ok "KNOWN GAP (help wanted: prompts/help-wanted/nesting-refusals-visible.md): a WARM run says nothing about the refused deep.yml — flipping this is the acceptance test"
    for mode in cold warm; do
        if [ "$mode" = cold ]; then
            $BIN "$KGY" --no-cache --skipped >"$TMP/kgy_sk_$mode.xml" 2>/dev/null; SK_RC=$?
        else
            $BIN "$KGY" --cache="$TMP/kgyaml.cache" --skipped >"$TMP/kgy_sk_$mode.xml" 2>/dev/null; SK_RC=$?
        fi
        if [ "$SK_RC" -ne 0 ] || ! grep -q '<skipped indexed="2"' "$TMP/kgy_sk_$mode.xml"; then
            no "(kg-yaml) $mode --skipped: exit $SK_RC or no <skipped indexed=\"2\"> report — the arm cannot observe the gap"
        elif grep -qE '<f p="[^"]*deep\.yml"' "$TMP/kgy_sk_$mode.xml"; then
            no "KNOWN GAP MOVED (prompts/help-wanted/nesting-refusals-visible.md): $mode --skipped now rows deep.yml — rewrite this arm to assert the row, its why=, and its legend clause"
        else
            ok "KNOWN GAP (help wanted: prompts/help-wanted/nesting-refusals-visible.md): $mode --skipped has no row for the refused deep.yml (only an anonymous unmeasured= counts it) — flipping this is the acceptance test"
        fi
    done
fi
# --match: evaluated on a clean exit only. A crashed run prints nothing, and "no hits in an empty document" would pass
# for the very defect this arm exists to expose.
$BIN "$KGY" --no-cache --match='(block_mapping_pair)' >"$TMP/kgy_match.xml" 2>"$TMP/kgy_match.err"; KGY_M_RC=$?
if [ "$KGY_M_RC" -ne 0 ]; then
    no "(kg-yaml) --match over the refused deep.yml exited $KGY_M_RC — a parse the guard exists to prevent went wrong (the vendored scanner patch is --match's only layer): $( head -2 "$TMP/kgy_match.err" )"
elif ! grep -q 'deep.yml: yaml nesting' "$TMP/kgy_match.err"; then
    no "(kg-yaml) --match: the same run's ingest did not refuse deep.yml — the arm cannot show the two paths disagree"
elif grep -q '<m p="deep\.yml:' "$TMP/kgy_match.xml"; then
    ok "KNOWN GAP (help wanted: prompts/help-wanted/nesting-refusals-visible.md): --match returns hits INSIDE deep.yml in the same run whose ingest refused it — flipping this is the acceptance test"
else
    no "KNOWN GAP MOVED (prompts/help-wanted/nesting-refusals-visible.md): --match no longer returns hits inside the refused deep.yml — rewrite this arm to assert the refusal and its disclosure"
fi

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== .dSYM bundles are pruned: debug-symbol relocations never become symbols ==="
# ═══════════════════════════════════════════════════════════════════════════
# The round's prerequisite finding: a .dSYM bundle carries yaml-format relocation files, and the
# private validation corpus holds 197 of them and ZERO real .yml config — an unpruned .dSYM ships
# hundreds of pure-noise t="sec" symbols. The prune is a NAME-SUFFIX rule (bundles are named after
# their product), so the arm uses a product-named bundle, not a literal ".dSYM" dir.
DS="$TMP/dsymcorpus"; mkdir -p "$DS/MyApp.dSYM/Contents/Resources"
printf 'dsymrelockey: should never be indexed\n' > "$DS/MyApp.dSYM/Contents/Resources/reloc.yml"
printf 'realconfigkey: 1\n' > "$DS/app.yml"
DS_OUT="$( $BIN "$DS" --no-cache 2>/dev/null )"
printf '%s' "$DS_OUT" | grep -q 'realconfigkey' \
    && ok ".dSYM prune: the sibling real .yml IS indexed (arm is not vacuous)" \
    || no ".dSYM prune: the sibling real .yml vanished — the prune is too wide"
printf '%s' "$DS_OUT" | grep -q 'dsymrelockey' \
    && no ".dSYM prune: a .yml inside MyApp.dSYM was indexed — kCrawlSkipDirs' suffix rule is not firing" \
    || ok ".dSYM prune: MyApp.dSYM contributes nothing"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== the 512 KB ceiling: YAML's own line, deliberately NOT JSON's 256 KB ==="
# ═══════════════════════════════════════════════════════════════════════════
# .yml wears the same hazard as .json (a large DATA class behind a config extension) so it gets
# a ceiling — but at 512 KB, because JSON's 256 KB would drop real config (NeMo's 293 KB
# cicd-main.yml). Both sides pinned: a ~300 KB file (over JSON's line) stays indexed, a ~600 KB
# file is skipped and COUNTED in skipped_oversize (disclosure, not disappearance).
BIGY="$TMP/bigyaml"; mkdir -p "$BIGY"
python3 - "$BIGY/mid_config.yml" "$BIGY/huge_data.yml" <<'PYEOF'
import sys
with open(sys.argv[1], "w") as f:              # ~300 KB — over 256 KB, under 512 KB
    f.write("midmarker: 1\n")
    for i in range(9000):
        f.write("midkey%d: value padding padding %d\n" % (i, i))
with open(sys.argv[2], "w") as f:              # ~600 KB — over 512 KB
    f.write("hugemarker: 1\n")
    for i in range(18000):
        f.write("hugekey%d: value padding padding %d\n" % (i, i))
PYEOF
MIDSZ="$( wc -c < "$BIGY/mid_config.yml" )"; HUGESZ="$( wc -c < "$BIGY/huge_data.yml" )"
[ "$MIDSZ" -gt 262144 ] && [ "$MIDSZ" -lt 524288 ] || no "mid fixture ($MIDSZ B) is not between 256 KB and 512 KB (fixture bug)"
[ "$HUGESZ" -gt 524288 ] || no "huge fixture ($HUGESZ B) is not larger than 512 KB (fixture bug)"
OBIG="$( $BIN "$BIGY" --no-cache 2>/dev/null )"
printf '%s' "$OBIG" | grep -q 'mid_config' \
    && ok "ceiling: a ${MIDSZ}-byte .yml (over JSON's 256 KB line) is still indexed" \
    || no "ceiling: a ${MIDSZ}-byte .yml was dropped — YAML inherited JSON's 256 KB ceiling"
printf '%s' "$OBIG" | grep -q 'huge_data' \
    && no "ceiling: a ${HUGESZ}-byte .yml was indexed — the 512 KB YAML ceiling is missing" \
    || ok "ceiling: a ${HUGESZ}-byte .yml is not in the map"
printf '%s' "$OBIG" | grep -q 'skipped_oversize=1' \
    && ok "ceiling: the skip is COUNTED (header skipped_oversize=1) — disclosure, not disappearance" \
    || no "ceiling: skipped_oversize=1 absent from the header — the drop is undisclosed"

echo
if [ "$fail" -eq 0 ]; then echo "yamllangcheck: ALL PASS"; else echo "yamllangcheck: FAILURES"; exit 1; fi
