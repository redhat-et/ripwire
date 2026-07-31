#!/usr/bin/env bash
# w3fixlegendcheck.sh — the W3FIX-LEGENDS gate: eleven legend / refusal / disclosure findings from the
# capture-audit-3 final verifier, each pinned by a LIVE number rather than by the sentence that claims it.
#
# The round's lesson was that written definitions rot on contact with code — three of the eleven were
# definitions that had been WRONG since the wave that added them. So every arm below computes the quantity
# independently (or reads it from a second emitter) and compares; nothing here asserts that a legend contains
# a word without also proving the word is true.
#
#   1  partition   shared_symbols is TWO-OR-MORE (not EVERY), shared/union == overlap_mean AT N=2 by identity
#                  and diverges at N>=3; the six previously-undefined root counters are defined and the
#                  modules+split / core+partition arithmetic they claim holds.
#   2  doc-drift   corpus= is its own population (a raised crawl ceiling makes corpus < files=), clean=
#                  satisfies docs-clean == <doc> rows, prose>0 with anchors=0 still scans.
#   3  dead-code   the ./-anchor pins the ROOT under an ABSOLUTE root spelling (was: refused).
#   4  situ H6/M9  sections [2] and [3] disclose their caps; the JSON twin carries script_gates_unmodelled
#                  and agrees with --test-gate's.
#   5  ID leak     an automated sweep over LIVE emitted text (legends + refusals) for internal audit IDs.
#   6  gitmine     the --since degrade ALERT agrees with the stderr line and with window= (PLAIN build only).
#   7  ext-surface the showcase caption names the attributes the unpaged root actually emits.
#   8  --help      the redaction paragraph's coverage list matches what is really redacted.
#   9  selector    an UNINDEXED file half says so; the five newly-routed arms carry the shared diagnosis.
#  10  limit="0"   the sentinel is defined in-band and the INPUT flag still refuses 0.
#  11  tree        the files identity reads true on a PAGED run.
#
#   RIPWIRE_BIN=build/ripwire      bash test/w3fixlegendcheck.sh
#   RIPWIRE_BIN=build_base/ripwire bash test/w3fixlegendcheck.sh   # must FAIL (pre-fix binary)
#
# NOTE arm 6 observes a DEGRADED_PATH_ALERT, which -DNDEBUG compiles out. It runs only when the binary can
# emit one (probed, not assumed) and says so loudly when it skips, so a Release build cannot make it pass for
# the wrong reason.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative binary
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for the JSON + sweep arms"; exit 2; }
echo "w3fixlegendcheck: BIN=$BIN  ROOT=$ROOT"

attr(){ grep -oE "$1=\"[^\"]*\"" | head -1 | sed -E 's/^[^"]*"//; s/"$//'; }

# The FIRST XML comment of a document, extracted by delimiter rather than by a `[^>]*` character class: a
# legend may legitimately contain a '>' (doc-drift's now says "the number of <doc> rows"), and a regex that
# cannot span one silently returns nothing — which reads as "the legend does not say that", i.e. exactly the
# false-negative a wording gate must not have.
firstComment(){ python3 -c '
import sys
s = open( sys.argv[1], encoding="utf-8", errors="replace" ).read()
i = s.find( "<!--" );  j = s.find( "-->", i )
print( s[ i : j + 3 ] if i >= 0 and j > i else "" )
' "$1"; }

# ══ 1. --partition: the shared_symbols definition, and the six counters the legend now defines ═════════════
echo "── 1. partition root counters"
PTASK="rank symbols by pagerank"
for N in 2 3 4; do
    "$BIN" "$ROOT" --pack-task="$PTASK" --partition=$N >"$TMP/p$N" 2>/dev/null
done
P2ROOT="$( grep -oE '<ctx-partitions[^>]*>' "$TMP/p2" )"
SH2="$( printf '%s' "$P2ROOT" | attr shared_symbols )"
UN2="$( printf '%s' "$P2ROOT" | attr union_symbols )"
OM2="$( printf '%s' "$P2ROOT" | attr overlap_mean )"

# (1a) THE definition. At N=2 there is exactly one pair, so "ids named by two or more partitions" over "ids
#      named by any" IS that pair's intersection over its union — i.e. shared/union must EQUAL overlap_mean.
#      Under the OLD definition ("the ids EVERY partition names") the two would also coincide at N=2, so this
#      arm alone cannot separate them; arm 1b does that.
python3 - "$SH2" "$UN2" "$OM2" <<'PY' >"$TMP/p2id"
import sys
sh,un,om=int(sys.argv[1]),int(sys.argv[2]),float(sys.argv[3])
print("OK" if un and abs(sh/un-om)<=0.001 else f"BAD {sh}/{un}={sh/un if un else 0:.4f} vs {om}")
PY
[ "$( cat "$TMP/p2id" )" = OK ] \
    && ok "N=2: shared/union ($SH2/$UN2) == overlap_mean ($OM2) — the pairwise identity the legend now claims" \
    || no "N=2 identity broken: $( cat "$TMP/p2id" )"

# (1b) the definition SEPARATOR: "two or more" must be >= "every". At N>=3 an EVERY-count is a global
#      intersection and can only be <= the two-or-more count; on a real corpus it is strictly smaller, and
#      shared_symbols must therefore also exceed the N=2 value rather than collapsing toward it.
SH3="$( grep -oE '<ctx-partitions[^>]*>' "$TMP/p3" | attr shared_symbols )"
SH4="$( grep -oE '<ctx-partitions[^>]*>' "$TMP/p4" | attr shared_symbols )"
if [ "${SH3:-0}" -gt "${SH2:-0}" ] && [ "${SH4:-0}" -gt "${SH3:-0}" ]; then
    ok "shared_symbols GROWS with the partition count ($SH2 -> $SH3 -> $SH4) — two-or-more semantics, not a global intersection"
else
    no "shared_symbols did not grow with N ($SH2 -> ${SH3:-<none>} -> ${SH4:-<none>}): an EVERY-partition intersection would shrink"
fi

# (1c) the divergence the legend promises from 3 partitions on.
for N in 3 4; do
    R="$( grep -oE '<ctx-partitions[^>]*>' "$TMP/p$N" )"
    S="$( printf '%s' "$R" | attr shared_symbols )"; U="$( printf '%s' "$R" | attr union_symbols )"
    O="$( printf '%s' "$R" | attr overlap_mean )"
    python3 - "$S" "$U" "$O" <<'PY' >"$TMP/div"
import sys
s,u,o=int(sys.argv[1]),int(sys.argv[2]),float(sys.argv[3])
r=s/u if u else 0.0
print("DIVERGES" if abs(r-o)>0.001 else f"SAME {r:.4f}=={o}")
PY
    [ "$( cat "$TMP/div" )" = DIVERGES ] \
        && ok "N=$N: shared/union ($S/$U) differs from overlap_mean ($O) — the divergence starts at 3+, as stated" \
        || no "N=$N: shared/union did NOT diverge from overlap_mean ($( cat "$TMP/div" )) — the legend's 3+ claim is wrong"
done

# (1d) core_budget_tokens + partition_budget_tokens == budget_per_agent_tokens (the legend says they sum).
AG="$( printf '%s' "$P2ROOT" | attr budget_per_agent_tokens )"
CB="$( printf '%s' "$P2ROOT" | attr core_budget_tokens )"
PB="$( printf '%s' "$P2ROOT" | attr partition_budget_tokens )"
[ "$(( CB + PB ))" = "$AG" ] \
    && ok "core_budget_tokens($CB) + partition_budget_tokens($PB) == budget_per_agent_tokens($AG)" \
    || no "the per-agent budget split does not sum: $CB + $PB != $AG"

# (1e) modules + split == the group count the bundles were packed from, on a corpus where the split FIRES
#      (few modules, many partitions requested) — the arithmetic the legend now asserts.
"$BIN" "$ROOT/test/zoomfix" --pack-task="engine run scheduler" --partition=16 >"$TMP/zp" 2>/dev/null
ZR="$( grep -oE '<ctx-partitions[^>]*>' "$TMP/zp" )"
ZP="$( printf '%s' "$ZR" | attr partitions )";  ZQ="$( printf '%s' "$ZR" | attr requested )"
ZM="$( printf '%s' "$ZR" | attr modules )";     ZS="$( printf '%s' "$ZR" | attr split )"
if [ -n "$ZM" ] && [ "$(( ZM + ZS ))" = "$ZP" ] && [ "$ZP" -lt "$ZQ" ]; then
    ok "K<N: modules($ZM) + split($ZS) == partitions($ZP), and partitions < requested($ZQ) — both legend clauses hold"
else
    no "modules+split != partitions on the K<N corpus (modules=${ZM:-<none>} split=${ZS:-<none>} partitions=${ZP:-<none>} requested=${ZQ:-<none>})"
fi

# (1g) THE TEXT. The numbers above were already right before this fix — only the SENTENCE describing them was
#      wrong, which is precisely the failure mode this round kept hitting. So the wording is pinned too, both
#      directions: the false claim must be gone AND the true one present, beside the arms that measure it.
PLEG="$( firstComment "$TMP/p2" )"
case "$PLEG" in
    *"shared_symbols counts the ids EVERY partition names"*) no "the partition legend still defines shared_symbols as 'the ids EVERY partition names' (the code counts two-or-more)";;
    *"the ids TWO OR MORE partitions name"*) ok "the partition legend defines shared_symbols as TWO OR MORE, matching measureOverlap";;
    *) no "the partition legend gives no shared_symbols definition: $( printf '%s' "$PLEG" | head -c 120 )";;
esac
case "$PLEG" in
    *"does NOT equal overlap_mean"*) no "the partition legend still asserts flat non-equality with overlap_mean (false at partitions=2)";;
    *"COINCIDE at partitions=2"*)    ok "the partition legend states the partitions=2 coincidence instead of a flat non-equality claim";;
    *) no "the partition legend does not address the shared/union vs overlap_mean relation";;
esac
for TERM in requested modules split core_symbols core_budget_tokens partition_budget_tokens; do
    case "$PLEG" in
        *"$TERM"*) ok "the partition legend defines $TERM=";;
        *) no "the partition legend still leaves $TERM= undefined";;
    esac
done

# (1f) surface= == core_symbols + the assignable remainder: on the unreachable-N corpus the whole surface IS
#      the core, which is exactly the "partitions=0, nothing left to carve" clause.
"$BIN" "$ROOT/test/deadfix" --pack-task="orphan function" --partition=8 >"$TMP/dp" 2>/dev/null
DR="$( grep -oE '<ctx-partitions[^>]*>' "$TMP/dp" )"
DP="$( printf '%s' "$DR" | attr partitions )"; DQ="$( printf '%s' "$DR" | attr requested )"
[ "${DP:-x}" = 0 ] && [ "${DQ:-x}" = 8 ] \
    && ok "unreachable N: partitions=0 requested=8 — the 'surface fit entirely in the core' clause is reachable" \
    || no "expected partitions=0 requested=8 on the tiny corpus, got partitions=${DP:-<none>} requested=${DQ:-<none>}"

# ══ 2. --doc-drift: corpus= is its own population; clean= satisfies its identity ═══════════════════════════
echo "── 2. doc-drift counters"
"$BIN" "$ROOT" --doc-drift >"$TMP/dd" 2>/dev/null
DDROOT="$( grep -oE '<doc-drift[^>]*>' "$TMP/dd" )"
DOCS="$( printf '%s' "$DDROOT" | attr docs )"; CLEAN="$( printf '%s' "$DDROOT" | attr clean )"
# the output is MINIFIED (one line), so `grep -c` would count lines, not rows — count occurrences.
ROWS="$( grep -o '<doc p=' "$TMP/dd" | wc -l | tr -d ' ' )"
[ "$(( DOCS - CLEAN ))" = "${ROWS:-0}" ] \
    && ok "clean=: docs($DOCS) - clean($CLEAN) == the <doc> row count ($ROWS) — the identity the legend states" \
    || no "docs - clean != <doc> rows ($DOCS - $CLEAN != ${ROWS:-0}) — clean='s definition is wrong"

# (2a) the SUPERSET claim's counterexample: doc-drift's own 4 MiB read ceiling is independent of the crawl
#      ceiling, so a raised --max-file-size indexes a file this walk still refuses => corpus < files=.
BIGSB="$TMP/bigsb"; mkdir -p "$BIGSB"
printf 'int kFoo[3] = {1,2,3};\nvoid f(){}\n' >"$BIGSB/small.cpp"
python3 - "$BIGSB/big.cpp" <<'PY'
import sys
# ~4.8 MB in few LINES (long comment lines parse fast; 600k short lines would not)
with open(sys.argv[1],'w') as fh:
    fh.write('int kBig[7] = {0,0,0,0,0,0,0};\n')
    fh.write(('// ' + 'x'*4000 + '\n')*1200)
PY
printf 'kFoo has `= 3` entries and `kBig[7]` is the big one.\nSee `small.cpp:1`.\n' >"$BIGSB/README.md"
BIGFILES="$( "$BIN" "$BIGSB" --no-cache --max-file-size=100M 2>/dev/null | grep -oE 'files=[0-9]+' | head -1 | grep -oE '[0-9]+' )"
BIGCORP="$( "$BIN" "$BIGSB" --no-cache --max-file-size=100M --doc-drift 2>/dev/null | grep -oE '<doc-drift[^>]*>' | attr corpus )"
if [ -n "$BIGFILES" ] && [ -n "$BIGCORP" ] && [ "$BIGCORP" -lt "$BIGFILES" ]; then
    ok "corpus= is NOT a superset of files=: a raised crawl ceiling gives files=$BIGFILES but corpus=$BIGCORP"
else
    no "could not reproduce corpus < files= (files=${BIGFILES:-<none>} corpus=${BIGCORP:-<none>}) — the counterexample the legend now admits"
fi

# (2b) corpus="0" means NO ANCHOR SHAPE AT ALL, not anchors="0": prose-only docs still scan.
PROSB="$TMP/prosesb"; mkdir -p "$PROSB"
printf 'void f(){}\n' >"$PROSB/a.cpp"
printf 'The doc claims `kNeverExisted = 5` and `kAlsoGone[9]`.\n' >"$PROSB/README.md"
PR="$( "$BIN" "$PROSB" --no-cache --doc-drift 2>/dev/null | grep -oE '<doc-drift[^>]*>' )"
PA="$( printf '%s' "$PR" | attr anchors )"; PP="$( printf '%s' "$PR" | attr prose )"; PC="$( printf '%s' "$PR" | attr corpus )"
if [ "${PA:-x}" = 0 ] && [ "${PP:-0}" -gt 0 ] && [ "${PC:-0}" -gt 0 ]; then
    ok "anchors=0 with prose=$PP still SCANNED (corpus=$PC) — corpus=\"0\" is about raw shapes, not anchors="
else
    no "prose-only corpus: expected anchors=0 prose>0 corpus>0, got anchors=${PA:-<none>} prose=${PP:-<none>} corpus=${PC:-<none>}"
fi
NOSB="$TMP/nosb"; mkdir -p "$NOSB"
printf 'void f(){}\n' >"$NOSB/a.cpp"; printf 'Just prose, no anchors here.\n' >"$NOSB/README.md"
NC="$( "$BIN" "$NOSB" --no-cache --doc-drift 2>/dev/null | grep -oE '<doc-drift[^>]*>' | attr corpus )"
[ "${NC:-x}" = 0 ] && ok "a genuinely anchor-free tree DOES report corpus=\"0\" (the sentinel still means something)" \
                   || no "anchor-free tree reported corpus=${NC:-<none>}, expected 0"

# (2c) THE TEXT, for the same reason as 1g: every number above was already correct before the fix; the legend
#      was the defective artefact. Pin the retraction and the replacement together.
DLEG="$( firstComment "$TMP/dd" )"
case "$DLEG" in
    *"it is a SUPERSET of the indexed corpus"*) no "the doc-drift legend still calls corpus= a SUPERSET of files= (contradicted by its own MINUS clause, and false on a raised crawl ceiling)";;
    *"its OWN population"*) ok "the doc-drift legend describes corpus= as its own population";;
    *) no "the doc-drift legend gives no corpus= relation at all";;
esac
case "$DLEG" in
    *"text this walk can read"*) no "the doc-drift legend still describes the auxiliary corpus as 'text this walk can read' (a content claim; it is an extension whitelist)";;
    *) ok "the auxiliary corpus is not described as a content test";;
esac
case "$DLEG" in
    *"clean="*) ok "the doc-drift legend defines clean=";;
    *) no "clean= is still undefined in the doc-drift legend";;
esac
case "$DLEG" in
    *"no anchor SHAPE whatsoever"*) ok "the corpus=\"0\" clause says SHAPES, so anchors=0 with prose>0 is covered";;
    *"which happens when the docs raised no anchor. "*) no "the corpus=\"0\" clause still says 'no anchor', which anchors=0 + prose>0 disproves";;
    *) no "the corpus=\"0\" clause is missing or reworded unrecognisably";;
esac
case "$DLEG" in
    *"before any check ran"*) no "prose= is still described as dropped 'before any check ran' — the drop IS a corpus lookup";;
    *"itself a corpus lookup"*) ok "prose= is described as a corpus lookup, and as the VALUE shapes only";;
    *) no "the prose= clause does not state when the drop happens";;
esac

# ══ 3. --dead-code: the ./-anchor under an ABSOLUTE root spelling ══════════════════════════════════════════
echo "── 3. dead-code ./-anchor is root-spelling independent"
dcCount(){ "$BIN" "$1" --dead-code="$2" 2>/dev/null | grep -oE '<dead-code count="[0-9]+"' | grep -oE '[0-9]+'; }
for F in ./src ./test ./bench src test; do
    RELC="$( cd "$ROOT" && dcCount . "$F" )"
    ABSC="$( dcCount "$ROOT" "$F" )"
    if [ -n "$RELC" ] && [ "$RELC" = "$ABSC" ]; then
        ok "--dead-code=$F: relative root == absolute root (count=$RELC)"
    else
        no "--dead-code=$F: rel=${RELC:-<refused>} abs=${ABSC:-<refused>} — the anchored match is root-spelling dependent"
    fi
done
# the ANCHOR must still MEAN something: ./src excludes the interior test/*/src/* path that bare src matches.
ANCH="$( dcCount "$ROOT" ./src )"; BARE="$( dcCount "$ROOT" src )"
[ -n "$ANCH" ] && [ -n "$BARE" ] && [ "$ANCH" -lt "$BARE" ] \
    && ok "the ./-anchor still narrows under an absolute root (./src=$ANCH < src=$BARE)" \
    || no "./src ($ANCH) vs src ($BARE): the anchor stopped distinguishing anything"

# ══ 4. --situ H6 disclosures + the M9 JSON twin ════════════════════════════════════════════════════════════
echo "── 4. situ cap disclosures + JSON twin"
# a sandbox where the test count EXCEEDS the 25-row cap (this repo's own probes stay under it).
SITSB="$TMP/situsb"; mkdir -p "$SITSB/test"
printf 'int coreFn(){ return 7; }\n' >"$SITSB/core.cpp"
i=1; while [ $i -le 30 ]; do printf 'int coreFn();\nint t%02d_main(){ return coreFn(); }\n' "$i" >"$SITSB/test/t$i.cpp"; i=$(( i + 1 )); done
"$BIN" "$SITSB" --no-cache --situ=core.cpp >"$TMP/situ30" 2>&1
S2LINE="$( grep -E '^  \[2\]' "$TMP/situ30" || true )"
S2ROWS="$( sed -n '/\[2\]/,/\[3\]/p' "$TMP/situ30" | grep -c 'test/t[0-9]*\.cpp' || true )"
case "$S2LINE" in
    *"(30)"*"showing 25 of 30 tests"*) ok "situ [2]: '(30) (showing 25 of 30 tests)' with ${S2ROWS} rows — the cap is disclosed";;
    *) no "situ [2] does not disclose its 25-row cap: $S2LINE";;
esac
[ "${S2ROWS:-0}" = 25 ] && ok "situ [2]: exactly 25 rows listed, matching the disclosure" \
                        || no "situ [2] listed ${S2ROWS:-0} rows, disclosure says 25"
# section [3] on this repo (git history required for co-change partners).
"$BIN" "$ROOT" --situ=src/graph.h >"$TMP/situ3" 2>&1
S3LINE="$( grep -E '^  \[3\]' "$TMP/situ3" || true )"
S3ROWS="$( sed -n '/\[3\]/,$p' "$TMP/situ3" | grep -c 'co-edited in' || true )"
S3TOT="$( printf '%s' "$S3LINE" | grep -oE '\(([0-9]+)\)' | head -1 | grep -oE '[0-9]+' )"
if [ "${S3TOT:-0}" -gt 8 ]; then
    case "$S3LINE" in
        *"showing 8 of ${S3TOT} files"*) ok "situ [3]: total $S3TOT, '(showing 8 of $S3TOT files)', $S3ROWS rows";;
        *) no "situ [3] has $S3TOT partners but discloses no cap: $S3LINE";;
    esac
else
    skip "situ [3]: only ${S3TOT:-0} co-change partners here (<= 8) — nothing to disclose on this history"
fi
# an UNTRUNCATED section must stay byte-clean of the note (the disclosure is not unconditional noise).
case "$( grep -E '^  \[2\]' "$TMP/situ3" || true )" in
    *showing*) no "situ [2] printed a showing-note on an untruncated section";;
    *)         ok "situ [2] on an untruncated section prints NO note (byte-unchanged when nothing dropped)";;
esac
# M9: the JSON twin's disclosure, and it must agree with --test-gate's own.
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"situational_awareness","arguments":{"path":"'"$ROOT"'","diff":"src/graph.h"}}}' \
  | "$BIN" --mcp 2>/dev/null | tail -1 >"$TMP/sitmcp"
MCPSG="$( python3 -c '
import sys,json
r=json.load(open(sys.argv[1]))
d=json.loads(r["result"]["content"][0]["text"])
print(d.get("script_gates_unmodelled","<absent>"))
' "$TMP/sitmcp" )"
GATESG="$( "$BIN" "$ROOT" --test-gate --json 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin).get("script_gates_unmodelled","<absent>"))' )"
if [ "$MCPSG" = "<absent>" ]; then
    no "M9: situational_awareness JSON has no script_gates_unmodelled key"
elif [ "$MCPSG" = "$GATESG" ]; then
    ok "M9: situational_awareness script_gates_unmodelled=$MCPSG == --test-gate --json's ($GATESG) — one counter, both twins"
else
    no "M9: situational_awareness says $MCPSG but --test-gate --json says $GATESG — two numbers under one name"
fi

# ══ 5. audit-ID leak sweep over LIVE emitted text ══════════════════════════════════════════════════════════
echo "── 5. audit-ID leak sweep (live emitted legends + refusals)"
python3 - "$BIN" "$ROOT" <<'PY' >"$TMP/sweep" 2>&1
import re, subprocess, sys
BIN, ROOT = sys.argv[1], sys.argv[2]
# Authored-text surfaces only. Verbs that echo CORPUS content verbatim (--grep/--regex/--match hit lines,
# --expand bodies, --recall doc bodies, --notes) are excluded by construction: this repo's own sources
# legitimately contain audit IDs, and a sweep that flagged them would be measuring the corpus, not the tool.
PROBES = [
    ['--tree'], ['--hotspots'], ['--clones'], ['--lint'], ['--metrics'], ['--deps'], ['--owners'],
    ['--communities'], ['--impact=rankGraphTeleport'], ['--callers=rankGraphTeleport'],
    ['--callees=rankGraphTeleport'], ['--uses=rankGraphTeleport'], ['--around=rankGraphTeleport'],
    ['--edit-check=rankGraphTeleport'], ['--external-surface'], ['--dead-code'], ['--doc-drift'],
    ['--test-gate'], ['--situ=src/graph.h'], ['--affected=src/graph.h'], ['--path=main,rankGraphTeleport'],
    ['--connect=rankGraphTeleport,runEval,getIndex'], ['--whereis=rankGraphTeleport'],
    ['--mentions=rankGraphTeleport'], ['--seams'], ['--exercises=rankGraphTeleport'], ['--lego=Config'],
    ['--exemplar=rank symbols'], ['--pr-context'], ['--quality-delta'], ['--arch=nosuch'],
    # --arch=nosuch REFUSES, so the arch DOCUMENT was never emitted for this sweep to read — the same
    # only-vectors-are-refusals hole that hid --edit-check from argvdiffcheck. A rules file that parses is
    # what puts the legend on screen (read-only: no --baseline, so no sidecar is written).
    ['--arch=test/archmetricsfix/sibling.arch'], ['--doctor'],
    ['--metrics', '--json'], ['--test-gate', '--json'], ['--help'],
    ['--partition=3', '--pack-task=rank symbols'],
    # refusal surfaces (stderr)
    ['--callers=zzz.h:rankGraphTeleport'], ['--lego=NoSuchType'], ['--dead-code=nosuchdir'], ['--limit=0'],
    ['--expand=NoSuchSym'], ['--outline=NoSuchSym'], ['--connect=a,b'], ['--partition=99', '--pack-task=x'],
]
# Internal audit-ID shapes. Two exclusions, both to avoid measuring the environment instead of the text:
#   * a match inside a filesystem path (a worktree may literally be named ".../wt-r30-w3fixc")
#   * a § that NAMES its document ("DESIGN_traceEvals.md §3.2") — a resolvable citation, not a leak
# ABS-\d joins the family: the pattern required a DOT between letters and digits, so `ABS-4` — a live plan
# ID sitting in --arch's emitted legend — was not a leak this sweep could see. Kept narrow and named rather
# than generalised to [A-Z]{2,4}-\d, which would flag UTF-8, FNV-1a and every other legitimate hyphenated
# token in the tree's prose.
ID      = re.compile(r'(?<![\w/.-])(?:§\s*\d|[ABPV]\d{1,2}\.\d{1,2}[a-z]?|V\d-\d|W\d+FIX|ABS-\d|r30)(?![\w/-])')
DOCCITE = re.compile(r'(?:\.md|[A-Z]{3,}_[A-Za-z0-9]+)\s*§')
COMMENT = re.compile(r'<!--(.*?)-->', re.S)
PLAIN   = ('--help', '--json', '--doctor', '--quality-delta', '--pr-context')
leaks = 0
for probe in PROBES:
    p = subprocess.run([BIN, ROOT] + probe, capture_output=True, text=True)
    texts = COMMENT.findall(p.stdout)
    if any(f in probe or f.lstrip('-') in ' '.join(probe) for f in PLAIN) or any(a.startswith('--situ') for a in probe):
        texts = texts + [p.stdout]
    texts.append(p.stderr)
    for t in texts:
        for m in ID.finditer(t):
            if DOCCITE.search(t[max(0, m.start() - 40):m.end()]):
                continue
            print("LEAK", ' '.join(probe), '->', repr(t[max(0, m.start() - 70):m.end() + 50]))
            leaks += 1
print("PROBES", len(PROBES))
print("LEAKS", leaks)
PY
SWEEPN="$( grep -oE '^LEAKS [0-9]+$' "$TMP/sweep" | grep -oE '[0-9]+' )"
# the surface count is PRINTED by the sweep, not written here: this line said "44" while the list held 45,
# which is the count-in-a-comment-nobody-re-derives shape the round keeps finding. It now cannot disagree.
SWEEPP="$( grep -oE '^PROBES [0-9]+$' "$TMP/sweep" | grep -oE '[0-9]+' )"
if [ "${SWEEPN:-x}" = 0 ]; then
    ok "no internal audit ID in any of the ${SWEEPP:-?} probed emitted-text surfaces"
else
    no "audit-ID leak(s) in emitted text: ${SWEEPN:-<sweep did not run>}"
    grep '^LEAK ' "$TMP/sweep" | head -6
fi
# the ONE the verifier named, pinned by name so a future re-introduction is unambiguous.
#
# Three PROPERTIES, not one phrase. The original arm matched a single sentence ("EXACT-arity evidence only")
# and so went red the moment that sentence was rewritten for a reason it had no opinion about — a gate keyed
# to wording rather than to what the wording has to SAY. What it has to say is now spelled out:
#   (a) no plan ID in the emitted text (the reason this arm exists);
#   (b) the arity RULE is stated — the reader is told a call is flagged only when every candidate carries a
#       FIXED arity that disagrees;
#   (c) the BINDING limit is stated, and the old absolute claim is gone. The flag is one-sided in the arity
#       and says nothing about whether the call site binds to this definition at all (call edges are matched
#       by NAME), so a legend promising "provably … never a guess" is making a claim the tool cannot keep —
#       measured: a clean, compiling tree carries a nonzero incompatible= on several shared names.
"$BIN" "$ROOT" --edit-check=rankGraphTeleport >"$TMP/ec" 2>/dev/null
if grep -q 'B2\.2' "$TMP/ec"; then
    no "--edit-check's legend still ships the 'B2.2' plan ID"
elif ! grep -q 'FIXED arity' "$TMP/ec"; then
    no "--edit-check's legend no longer states the arity RULE (want: every candidate has a FIXED arity that disagrees)"
elif grep -qE 'never a guess|PROVABLY incompatible' "$TMP/ec"; then
    no "--edit-check's legend still claims the flag is PROVEN — it is one-sided in the arity only, not a proof of binding"
elif ! grep -q 'matched by NAME' "$TMP/ec"; then
    no "--edit-check's legend states no BINDING limit — a name-based edge can flag a caller on an untouched tree"
else
    ok "--edit-check's legend states the arity RULE + the name-binding limit, with no plan ID and no proof claim"
fi

# ══ 6. gitmine --since degrade alert (PLAIN build only — NDEBUG deletes the observation) ═══════════════════
echo "── 6. --since degrade alert (needs the PLAIN build)"
"$BIN" "$ROOT" --rank-by=churn --since=notadate >"$TMP/since.out" 2>"$TMP/since.err"
if ! grep -q 'math degraded' "$TMP/since.err"; then
    skip "no DEGRADED_PATH_ALERT observed — this binary is a Release/NDEBUG build; run this arm against the PLAIN build"
else
    if grep -q 'all-history' "$TMP/since.err"; then
        no "the --since alert still promises 'all-history', contradicting the stderr line and window="
    elif grep -q "calling verb's own default window applies" "$TMP/since.err"; then
        ok "the --since alert says the calling verb's own default window applies (agrees with the stderr line)"
    else
        no "the --since alert wording is neither the old nor the corrected one: $( grep 'math degraded' "$TMP/since.err" | head -1 )"
    fi
    WIN="$( grep -oE 'window="[^"]*"' "$TMP/since.out" | head -1 | sed -E 's/^[^"]*"//; s/"$//' )"
    [ -n "$WIN" ] && [ "$WIN" != "all" ] \
        && ok "…and the run it describes really used a bounded window (window=\"$WIN\"), so all-history was never true" \
        || no "expected a bounded window= on the churn root, got '${WIN:-<none>}'"
fi

# ══ 7. --external-surface caption names the attributes the unpaged root emits ══════════════════════════════
echo "── 7. external-surface caption"
"$BIN" "$ROOT" --external-surface >"$TMP/xs" 2>/dev/null
XSROOT="$( grep -oE '<external-surface[^>]*>' "$TMP/xs" )"
case "$XSROOT" in
    *' total='*) no "the UNPAGED external-surface root carries total= after all — the caption claim needs revisiting";;
    *' names="'*' shown="'*' capped="'*) ok "unpaged root emits names=/shown=/capped= and no total= ($XSROOT)";;
    *) no "unexpected external-surface root shape: $XSROOT";;
esac
XSPAGE="$( "$BIN" "$ROOT" --external-surface --limit=3 2>/dev/null | grep -oE '<external-surface[^>]*>' )"
case "$XSPAGE" in
    *' total="'*) ok "total= appears only under paging, as the caption now says";;
    *) no "paged external-surface root has no total=: $XSPAGE";;
esac
CAP="$( grep -n 'external-surface' "$ROOT/test/showcase_capture.py" | head -1 )"
case "$CAP" in
    *"NOW carries total/shown/capped"*) no "the showcase caption still claims total/shown/capped on the unpaged root";;
    *"names/shown/capped"*)             ok "the showcase caption names names/shown/capped";;
    *) no "showcase caption for --external-surface does not name the attributes at all: $CAP";;
esac

# ══ 8. --help redaction paragraph matches what is really redacted ══════════════════════════════════════════
echo "── 8. redaction coverage vs --help"
REDSB="$TMP/redsb"; mkdir -p "$REDSB"
KEY=AKIAIOSFODNN7EXAMPLE
{ printf '// doc: the key is %s here\n' "$KEY"
  printf 'const char* apiKey = "%s";\n' "$KEY"
  printf 'int leaky( const char* key = "%s" ){ const char* secret_token = "%s"; return 1; }\n' "$KEY" "$KEY"
} >"$REDSB/a.cpp"
verbatim(){ "$BIN" "$REDSB" --no-cache "$@" 2>/dev/null | grep -c "$KEY" || true; }
[ "$( verbatim --expand=leaky )" = 0 ] && ok "BODIES are redacted (--expand leaks 0 verbatim keys)" \
                                       || no "--expand leaked the key verbatim — the help claims bodies are redacted"
[ "$( verbatim --for="leaky key" )" = 0 ] && ok "SIGNATURES are redacted (--for leaks 0 verbatim keys)" \
                                          || no "--for leaked a default-argument key verbatim — the help claims signatures are redacted"
[ "$( verbatim --grep="$KEY" )" -gt 0 ] && ok "--grep hit lines are NOT redacted, as the help now states (the secret-auditor exception)" \
                                        || no "--grep redacted its hit line — the help's stated exception is wrong"
[ "$( verbatim --regex='AKIA\w+' )" -gt 0 ] && ok "--regex hit lines are NOT redacted, as stated" \
                                            || no "--regex behaviour disagrees with the help"
HELPTXT="$( "$BIN" --help 2>&1 )"
case "$HELPTXT" in
    *"credentials in emitted bodies are redacted"*) no "--help still carries the stale bodies-only redaction sentence";;
esac
case "$HELPTXT" in
    *"SIGNATURES"*) ok "--help names SIGNATURES in the redaction coverage list";;
    *) no "--help's redaction paragraph does not mention signatures";;
esac
case "$HELPTXT" in
    *"NOT redacted"*) ok "--help names the residuals (the NOT-redacted list)";;
    *) no "--help's redaction paragraph names no residuals";;
esac

# ══ 9. selector refusal: unindexed PATH half, and the five newly-routed arms ═══════════════════════════════
echo "── 9. selector refusal honesty"
refuse(){ "$BIN" "$ROOT" "$@" 2>&1 >/dev/null | head -1; }
# (9a) an unindexed file half must NOT be described as a file that "defines no X".
for V in --uses --callers --callees --impact --around --edit-check; do
    M="$( refuse "$V=zzz_no_such.h:rankGraphTeleport" )"
    case "$M" in
        *"that file defines no"*) no "$V still claims 'that file defines no ...' about an UNINDEXED path: $M";;
        *"no indexed file matches 'zzz_no_such.h'"*) ok "$V: an unindexed path half is named as the fault";;
        *) no "$V: unexpected refusal for an unindexed path half: $M";;
    esac
done
M="$( refuse "--lego=zzz_no_such.h:Config" )"
case "$M" in *"no indexed file matches"*) ok "--lego: unindexed path half named as the fault";;
             *) no "--lego: $M";; esac
# (9b) the file-IS-indexed case must keep the enriched sentence (the good one, unchanged).
M="$( refuse "--uses=src/main.cpp:rankGraphTeleport" )"
case "$M" in *"that file defines no 'rankGraphTeleport'"*"src/graph.h"*) ok "an INDEXED file with the wrong name keeps the defining-files diagnosis";;
             *) no "the indexed-file branch changed: $M";; esac
# (9c) the five arms the sweep had missed now carry the shared diagnosis.
for PROBE in "--expand=zzz_no_such.h:rankGraphTeleport" "--outline=zzz_no_such.h:rankGraphTeleport" \
             "--connect=zzz_no_such.h:rankGraphTeleport,runEval" "--path=zzz_no_such.h:rankGraphTeleport,runEval" \
             "--affected=zzz_no_such.h:rankGraphTeleport"; do
    M="$( refuse "$PROBE" )"
    case "$M" in
        *"no indexed file matches 'zzz_no_such.h'"*) ok "${PROBE%%=*}: routed through the shared selector refusal";;
        *) no "${PROBE%%=*} still refuses in the old dialect: $M";;
    esac
done
# (9d) --expand/--outline must KEEP their flag-first tail (agents grep it).
case "$( refuse "--expand=zzz_no_such.h:rankGraphTeleport" )" in
    *"--expand=zzz_no_such.h:rankGraphTeleport matched no symbol"*) ok "--expand keeps its 'matched no symbol' tail ahead of the diagnosis";;
    *) no "--expand's historic tail was dropped by the routing";;
esac
# (9e) a bare unknown name keeps the historic wording (no invented file story).
case "$( refuse "--uses=NoSuchSymbolAtAll" )" in
    *"no indexed file matches"*) no "a bare unknown name got the file-half story";;
    *NoSuchSymbolAtAll*)         ok "a bare unknown name keeps the plain not-found wording";;
    *) no "unexpected bare-name refusal";;
esac

# ══ 10. limit="0" — defined in band, and refused as INPUT ══════════════════════════════════════════════════
echo "── 10. limit=\"0\" sentinel"
for V in "--grep=DEGRADED_PATH_ALERT" "--impact=rankGraphTeleport" "--tree"; do
    OUT="$( "$BIN" "$ROOT" $V --offset=5 2>/dev/null )"
    ROOTEL="$( printf '%s' "$OUT" | grep -oE '<(grep|impact|tree) [^>]*>' | head -1 )"
    case "$ROOTEL" in
        *'limit="0"'*) ok "$V --offset=5 emits limit=\"0\" (offset without limit -> the verb's own default page)";;
        *) no "$V --offset=5 did not emit limit=\"0\": $ROOTEL";;
    esac
done
# the INPUT flag must still refuse 0, which is what makes "never a zero-row page" true.
case "$( refuse "--grep=x" "--limit=0" )" in
    *"--limit needs a positive integer"*) ok "--limit=0 is REFUSED as input, so limit=\"0\" on output is unambiguous";;
    *) no "--limit=0 was accepted — the output sentinel is then ambiguous";;
esac
# in-band definition on the two adopting verbs.
for V in "--grep=DEGRADED_PATH_ALERT" "--impact=rankGraphTeleport"; do
    "$BIN" "$ROOT" $V >"$TMP/inband" 2>/dev/null;  L="$( firstComment "$TMP/inband" )"
    case "$L" in
        *'limit="0" means no explicit limit'*) ok "${V%%=*}: the legend DEFINES limit=\"0\" on the first screen";;
        *) no "${V%%=*}: limit=\"0\" is still undefined in band";;
    esac
done

# ══ 11. --tree: the files identity reads true paged and unpaged ════════════════════════════════════════════
echo "── 11. tree files identity"
TU="$( "$BIN" "$ROOT" --tree 2>/dev/null | grep -oE '<tree [^>]*>' )"
TF="$( printf '%s' "$TU" | attr files )"; TUL="$( printf '%s' "$TU" | attr files_unlisted )"
TROWS="$( "$BIN" "$ROOT" --tree 2>/dev/null | grep -o '<file p=' | wc -l | tr -d ' ' )"   # minified: count occurrences
[ "$(( TUL + TROWS ))" = "$TF" ] \
    && ok "unpaged: files_unlisted($TUL) + rows($TROWS) == files($TF)" \
    || no "unpaged tree identity broken: $TUL + ${TROWS:-0} != $TF"
TP="$( "$BIN" "$ROOT" --tree --limit=2 2>/dev/null | grep -oE '<tree [^>]*>' )"
TPT="$( printf '%s' "$TP" | attr total )"; TPS="$( printf '%s' "$TP" | attr shown )"
if [ "$(( TUL + TPT ))" = "$TF" ] && [ "${TPS:-0}" = 2 ]; then
    ok "paged: files_unlisted($TUL) + total($TPT) == files($TF) while only shown=$TPS rows print — the LISTABLE-set wording"
else
    no "paged tree: $TUL + ${TPT:-0} != $TF (or shown=${TPS:-0} != 2)"
fi
"$BIN" "$ROOT" --tree >"$TMP/treeleg" 2>/dev/null;  TREELEG="$( firstComment "$TMP/treeleg" )"
case "$TREELEG" in
    *"files equals the listed rows plus files_unlisted on every run"*) no "the tree legend still claims the rows-based identity 'on every run'";;
    *"LISTABLE file set"*) ok "the tree legend states the identity over the LISTABLE set, not the printed rows";;
    *) no "the tree legend states no files identity at all: $TREELEG";;
esac

# ══ G4 across every document this gate touched ═════════════════════════════════════════════════════════════
echo "── G4"
if command -v xmllint >/dev/null 2>&1; then
    g4=0
    for V in "--doc-drift" "--tree" "--tree --limit=2" "--grep=DEGRADED_PATH_ALERT" "--impact=rankGraphTeleport" \
             "--dead-code=./src" "--edit-check=rankGraphTeleport" "--external-surface"; do
        "$BIN" "$ROOT" $V 2>/dev/null | xmllint --noout - 2>/dev/null || { no "G4: $V is not well-formed XML"; g4=1; }
    done
    "$BIN" "$ROOT" --pack-task="$PTASK" --partition=3 2>/dev/null | xmllint --noout - 2>/dev/null \
        || { no "G4: --partition=3 is not well-formed XML"; g4=1; }
    [ $g4 = 0 ] && ok "every touched document is xmllint-clean (9 including the partitioned bundle)"
else
    skip "xmllint unavailable — G4 arm not run"
fi

echo
[ $fail = 0 ] && { echo "w3fixlegendcheck: ALL PASS"; exit 0; } || { echo "w3fixlegendcheck: FAILURES"; exit 1; }
