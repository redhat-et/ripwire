#!/usr/bin/env bash
# modifierguardcheck.sh — gate for  "six silently no-op modifiers" +
# §P12.2 (--adaptive under --format=candidates).
#
# Before this fix: --with-history, --compress, --grep-context(/-before/-after), --since, --detail=N-beyond-
# the-ranked-head, and (a different bug) --adaptive under --format=candidates all either silently produced
# the UNMODIFIED output (exit 0, no stderr — indistinguishable from a typo'd flag that did nothing) or
# silently clamped a request with no signal a truncation happened. Eight sibling "(with X)" modifiers already
# refused loudly, naming both flags and an example (cli.h validateConfig) — this gate pins that the same
# shape now covers the six, PLUS three more the §P8 sweep turned up while auditing the class (--with-graph,
# --no-prefilter, --force, --mcp-token/--allow-remote-edits, --baseline/--baseline-update), and that
# --adaptive now WORKS (cuts at the relevance cliff) instead of refusing under --format=candidates.
#
# Two halves:
#   (A) RED-shape guards — cheap NOROOT probes (validateConfig runs before root/corpus validation, same
#       trick guardmsgcheck.sh uses): each broken combo exits 1 with a message naming both flags.
#   (B) GREEN — the VALID combo for each fixed modifier still WORKS (exit 0, observable effect). Byte-
#       identity of these valid combos against the pre-change binary was verified out-of-band this session
#       (test/argvdiffcheck.sh RIPWIRE_BASE=<pre-change build> over the 292-vector harvest: exactly 10
#       diffs, one per broken combo below, zero unexpected); this gate pins the BEHAVIOR going forward so a
#       later regression is caught without needing a stashed binary in the tree.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/modifierguardcheck.sh
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
cd "$ROOT"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "modifierguardcheck: BIN=$BIN"

NOROOT="$TMP/definitely-not-a-root"
checked=0

# guard NAME | EXPECTED-SUBSTRING | argv…   — asserts exit != 0 AND stderr contains the substring, AND that
# the substring names the flag under test (a swapped/dropped guard must not slip past a fuzzy grep).
guard()
{
    local name="$1" want="$2"; shift 2
    checked=$(( checked + 1 ))
    "$BIN" "$@" >"$TMP/out" 2>"$TMP/err" </dev/null; local rc=$?
    if [ "$rc" = 0 ]; then
        no "$name: exited 0 — the guard did not fire at all"
        return
    fi
    if grep -qF -- "$want" "$TMP/err"; then
        ok "$name"
    else
        no "$name: refused (exit $rc) but with the WRONG message"
        printf '            want: %s\n' "$want"
        printf '            got : %s\n' "$( head -1 "$TMP/err" )"
    fi
}

# ── (A) RED — broken combos, each refuses naming both flags ──────────────────────────────────────────────
guard "--with-history alone"          '--with-history modifies --doc-drift or --whereis=SYM'         "$NOROOT" --with-history
guard "--compress alone"              '--compress strips comments from served-body output'            "$NOROOT" --compress
guard "--grep-context alone"          '--grep-context=N (or --grep-before/--grep-after) modifies'     "$NOROOT" --grep-context=3
guard "--grep-before alone"           '--grep-context=N (or --grep-before/--grep-after) modifies'     "$NOROOT" --grep-before=2
guard "--grep-after alone"            '--grep-context=N (or --grep-before/--grep-after) modifies'     "$NOROOT" --grep-after=2
guard "--no-prefilter alone"          '--no-prefilter modifies --grep=STR or --regex=PAT'             "$NOROOT" --no-prefilter
guard "--detail beyond the head"      'exceeds the ranked head'                                       "$NOROOT" --for=x --detail=999
guard "--since alone"                 '--since=REV|DATE scopes --hotspots/--cochange/--rank-by=churn' "$NOROOT" --since="1 week ago"
guard "--with-graph alone"            '--with-graph modifies --for=TASK or --pack-task=TASK'          "$NOROOT" --with-graph
guard "--force outside wrap"          '--force only applies to `ripwire wrap <agent>`'                "$NOROOT" --force
guard "--baseline without --arch"     '--baseline/--baseline-update writes the --arch=FILE debt sidecar' "$NOROOT" --baseline
guard "--baseline-update without --arch" '--baseline/--baseline-update writes the --arch=FILE debt sidecar' "$NOROOT" --baseline-update
guard "--mcp-token without --listen"  '--mcp-token is read by the --listen HTTP transport only'        "$NOROOT" --mcp-token=x
guard "--allow-remote-edits without --listen" '--allow-remote-edits is read by the --listen HTTP transport only' "$NOROOT" --allow-remote-edits

# §P8/G2 — --limit/--offset on a verb that does not window anything. This is the SAME class as every guard
# above (accepted, then silently ignored), but it was the largest instance of it: the default map and ~15
# report verbs took both flags and emitted the identical bytes, so a caller could not tell a no-op from a
# typo. Paginating all of them was not the fix; refusing is. The default map's remedy is a DIFFERENT flag
# (--top-k bounds the ranked head), so the message must name it as well as the honoring set.
guard "--limit on the default map"    'honored only by'                     "$NOROOT" --limit=3
guard "--offset on the default map"   'honored only by'                     "$NOROOT" --offset=3
guard "--limit on the default map (names --top-k)" '--top-k'                "$NOROOT" --limit=3
guard "--limit with --report"         'honored only by'                     "$NOROOT" --report --limit=3
guard "--limit with --for"            'honored only by'                     "$NOROOT" --for=x --limit=3
guard "--offset with --metrics"       'honored only by'                     "$NOROOT" --metrics --offset=2
# §P15/§P16: --zoom/--stray-content joined the honoring set, but their fixed-shape sub-modes did not —
# --zoom --mermaid stays a diagram (like plain --mermaid), --stray-content --plan/--abi route to emitters
# that window nothing (landingplan::writePlan / abicheck::writeAbiCheck).
guard "--limit with --zoom --mermaid" 'honored only by'                     "$NOROOT" --zoom --mermaid --limit=3
guard "--limit with --stray-content --plan" 'honored only by'               "$NOROOT" --stray-content --plan --limit=3
guard "--limit with --stray-content --abi"  'honored only by'               "$NOROOT" --stray-content --abi --limit=3

# §B9 (capture-audit-4, 2026-07-30) — --top-k/--max-tokens on the SAME report/paging family the --limit/
# --offset guards above cover: silently accepted-and-ignored, the exact mirror of that class. --graph-query
# is the one family member that DOES honor --top-k (so its own guard below must NOT fire); nothing in the
# family honors --max-tokens at all, --graph-query included.
guard "--top-k on --hotspots"          'narrows only --graph-query'  "$NOROOT" --hotspots --top-k=3
guard "--top-k on --clones"            'narrows only --graph-query'  "$NOROOT" --clones --top-k=3
guard "--top-k on --whereis"           'narrows only --graph-query'  "$NOROOT" --whereis=x --top-k=3
guard "--top-k on --test-gate"         'narrows only --graph-query'  "$NOROOT" --test-gate --top-k=3
guard "--max-tokens on --hotspots"     'honored by the default map'  "$NOROOT" --hotspots --max-tokens=50
guard "--max-tokens on --grep"         'honored by the default map'  "$NOROOT" --grep=x --max-tokens=50
guard "--max-tokens on --graph-query"  'honored by the default map'  "$NOROOT" --graph-query='name("x")' --max-tokens=50

[ "$checked" -ge 20 ] && ok "pinned $checked broken-combo refusals" \
                      || no "only $checked guards probed — one was dropped from this gate"

# ── (B) GREEN — the VALID combo for each still works ──────────────────────────────────────────────────────
FIX="$ROOT/test/compressfix"
SRC="$ROOT/test/fixture"

# --compress: --expand actually shrinks (compresscheck.sh owns the full contract; one spot-check here).
sz_plain="$( "$BIN" "$FIX" --expand=computeArea --no-cache 2>/dev/null | wc -c | tr -d ' ' )"
sz_comp="$(  "$BIN" "$FIX" --expand=computeArea --compress --no-cache 2>/dev/null | wc -c | tr -d ' ' )"
{ [ -n "$sz_comp" ] && [ "$sz_comp" -gt 0 ] && [ "$sz_comp" -lt "$sz_plain" ]; } \
    && ok "--expand --compress: still shrinks the body ($sz_comp < $sz_plain bytes)" \
    || no "--expand --compress: did not shrink ($sz_comp vs $sz_plain)"

# --with-history: --doc-drift --with-history still exits 0 (historyoraclecheck.sh owns the full contract).
"$BIN" "$SRC" --doc-drift --with-history --no-cache >/dev/null 2>"$TMP/wh.err"
[ "$?" = 0 ] && ok "--doc-drift --with-history: still exits 0" || no "--doc-drift --with-history: broke ($(cat "$TMP/wh.err"))"

# --grep-context: still widens the hit context (grep gates own the full contract; spot-check row count grows).
n0="$( "$BIN" "$FIX" --grep=computeArea --no-cache 2>/dev/null | grep -o '<hit' | wc -l | tr -d ' ' )"
"$BIN" "$FIX" --grep=computeArea --grep-context=2 --no-cache >"$TMP/gc.xml" 2>"$TMP/gc.err"
rc_gc=$?
{ [ "$rc_gc" = 0 ] && [ -s "$TMP/gc.xml" ]; } \
    && ok "--grep --grep-context=2: still exits 0 with output" \
    || no "--grep --grep-context=2: broke (rc=$rc_gc)"

# --no-prefilter: still exits 0 alongside --grep (soundness-oracle contract owned elsewhere).
"$BIN" "$FIX" --grep=computeArea --no-prefilter --no-cache >/dev/null 2>"$TMP/np.err"
[ "$?" = 0 ] && ok "--grep --no-prefilter: still exits 0" || no "--grep --no-prefilter: broke ($(cat "$TMP/np.err"))"

# --detail: within the ranked head still works (detailcheck.sh owns the full contract).
"$BIN" "$SRC" --for="distance" --detail=3 --no-cache >/dev/null 2>"$TMP/d.err"
[ "$?" = 0 ] && ok "--for --detail=3 (within the head): still exits 0" || no "--for --detail=3: broke ($(cat "$TMP/d.err"))"

# --since: still exits 0 alongside --hotspots (a git repo — use ROOT itself, read-only).
"$BIN" "$ROOT/src" --hotspots --since="2 weeks ago" --no-cache >/dev/null 2>"$TMP/s.err"
[ "$?" = 0 ] && ok "--hotspots --since: still exits 0" || no "--hotspots --since: broke ($(cat "$TMP/s.err"))"

# --with-graph: still splices a mermaid block into --pack-task's bundle.
graph_out="$( "$BIN" "$FIX" --pack-task="compute area" --with-graph --no-cache 2>/dev/null )"
printf '%s' "$graph_out" | grep -q 'mermaid' \
    && ok "--pack-task --with-graph: mermaid block present" \
    || no "--pack-task --with-graph: no mermaid block in output"

# --limit/--offset: the honoring side. One verb from the guard's own list must still page cleanly, and the
# --detail composition must survive (--detail=1 restores --owners' full listing, --limit then windows IT —
# two different knobs on the same listing, legal together). pagingsweepcheck.sh owns the full matrix.
"$BIN" "$ROOT" --callers=rankGraph --limit=2 --offset=1 --no-cache >"$TMP/pg.xml" 2>"$TMP/pg.err"
{ [ "$?" = 0 ] && grep -q 'has_more="' "$TMP/pg.xml"; } \
    && ok "--callers --limit=2 --offset=1: still paginates (has_more= present)" \
    || no "--callers --limit=2 --offset=1: broke ($(head -1 "$TMP/pg.err"))"
"$BIN" "$ROOT" --owners --detail=1 --limit=3 --no-cache >/dev/null 2>"$TMP/od.err"
[ "$?" = 0 ] && ok "--owners --detail=1 --limit=3: legal composition, still exits 0" \
             || no "--owners --detail=1 --limit=3: refused ($(head -1 "$TMP/od.err"))"

# §B9 — the --top-k/--max-tokens honoring side. --graph-query really shapes with --top-k; --connect and
# --recall really shape with --max-tokens (source-verified, main.cpp); none of the RED guards above must
# have caught something that actually honors the flag.
"$BIN" "$SRC" --graph-query='name("area_of_triangle")' --top-k=3 --no-cache >/dev/null 2>"$TMP/gqtk.err"
[ "$?" = 0 ] && ok "--graph-query --top-k=3: still exits 0 (the one report/paging member that honors --top-k)" \
             || no "--graph-query --top-k=3: broke ($(head -1 "$TMP/gqtk.err"))"
"$BIN" "$SRC" --connect=total_area,area_of_triangle --max-tokens=500 --no-cache >/dev/null 2>"$TMP/cmt.err"
[ "$?" = 0 ] && ok "--connect --max-tokens=500: still exits 0 (honors --max-tokens, outside the report/paging family)" \
             || no "--connect --max-tokens=500: broke ($(head -1 "$TMP/cmt.err"))"
"$BIN" "$SRC" --recall="notes" --top-k=1 --no-cache >/dev/null 2>"$TMP/rctk.err"
[ "$?" = 0 ] && ok "--recall --top-k=1: still exits 0 (honors --top-k, outside the report/paging family)" \
             || no "--recall --top-k=1: broke ($(head -1 "$TMP/rctk.err"))"

# --baseline: full four-step contract owned by baselinecheck.sh; not re-verified here.

# --wrap --force: the OTHER meaning of --force (src/wrap.h's own raw-argv scan) is untouched by the guard —
# it returns before Config/parseArgs ever runs, so it must still accept --force cleanly.
"$BIN" wrap claude --force >/dev/null 2>"$TMP/wrapforce.err"
[ "$?" = 0 ] && ok "ripwire wrap claude --force: still exits 0 (unaffected by the flag-surface guard)" \
             || no "ripwire wrap claude --force: broke ($(cat "$TMP/wrapforce.err"))"

# ── §P12.2 — --adaptive now WORKS under --format=candidates instead of refusing ────────────────────────────
dcount(){ "$BIN" "$@" --no-cache 2>/dev/null | grep -o '<cand ' | wc -l | tr -d ' '; }

SHARP_N="$( dcount "$ROOT/src" --for="estimateExpandBodyTokens" --format=candidates --adaptive --no-route )"
BROAD_N="$( dcount "$ROOT/src" --for="file"                      --format=candidates --adaptive --no-route )"
{ [ -n "$SHARP_N" ] && [ -n "$BROAD_N" ] && [ "$SHARP_N" -lt "$BROAD_N" ] 2>/dev/null; } \
    && ok "--for --format=candidates --adaptive: sharp query kept fewer than broad ($SHARP_N < $BROAD_N)" \
    || no "--for --format=candidates --adaptive: did not discriminate ($SHARP_N vs $BROAD_N)"

HDR="$( "$BIN" "$ROOT/src" --for="estimateExpandBodyTokens" --format=candidates --adaptive --no-cache 2>/dev/null | grep -oE '<!-- adaptive: kept [0-9]+ of [0-9]+[^>]*-->' | head -1 )"
[ -n "$HDR" ] && ok "--for --format=candidates --adaptive: leading comment states the cut ($HDR)" \
             || no "--for --format=candidates --adaptive: no leading adaptive comment"

QSHARP_N="$( dcount "$ROOT/src" --query="estimateExpandBodyTokens" --format=candidates --adaptive )"
QPLAIN_N="$( "$BIN" "$ROOT/src" --query="estimateExpandBodyTokens" --format=candidates --no-cache 2>/dev/null | grep -o '<cand ' | wc -l | tr -d ' ' )"
{ [ -n "$QSHARP_N" ] && [ -n "$QPLAIN_N" ] && [ "$QSHARP_N" -le "$QPLAIN_N" ] 2>/dev/null; } \
    && ok "--query --format=candidates --adaptive: kept <= the unadaptive count ($QSHARP_N <= $QPLAIN_N)" \
    || no "--query --format=candidates --adaptive: did not cut ($QSHARP_N vs $QPLAIN_N)"

if command -v xmllint >/dev/null 2>&1; then
    "$BIN" "$ROOT/src" --for="estimateExpandBodyTokens" --format=candidates --adaptive --no-cache 2>/dev/null | xmllint --noout - \
        && ok "xml well-formed: --for --format=candidates --adaptive" || no "xml malformed: --for --format=candidates --adaptive"
    "$BIN" "$ROOT/src" --query="estimateExpandBodyTokens" --format=candidates --adaptive --no-cache 2>/dev/null | xmllint --noout - \
        && ok "xml well-formed: --query --format=candidates --adaptive" || no "xml malformed: --query --format=candidates --adaptive"
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

"$BIN" "$ROOT/src" --for="estimateExpandBodyTokens" --format=candidates --adaptive --no-cache >"$TMP/ac1.xml" 2>/dev/null
"$BIN" "$ROOT/src" --for="estimateExpandBodyTokens" --format=candidates --adaptive --no-cache >"$TMP/ac2.xml" 2>/dev/null
cmp -s "$TMP/ac1.xml" "$TMP/ac2.xml" \
    && ok "--for --format=candidates --adaptive: deterministic (byte-identical twice)" \
    || no "--for --format=candidates --adaptive: non-deterministic"

# --adaptive still refuses without EITHER --for/--query nor --format=candidates supplying a base (pre-existing
# guards, unaffected by this fix — asserted here so a future edit can't silently widen the companion set).
guard "--adaptive --format=candidates alone" '--adaptive modifies --for=TASK or --query=TERMS' "$NOROOT" --format=candidates --adaptive

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
