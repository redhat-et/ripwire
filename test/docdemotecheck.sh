#!/usr/bin/env bash
# docdemotecheck.sh — the shape-conditional documentation-tier demotion gate.
#
#   test/docdemotecheck.sh                        # uses build/ripwire on test/docdemotefix
#   test/docdemotecheck.sh /path/to/other/ripwire # positional binary (the RED baseline run)
#   RIPWIRE_BIN=asan/ripwire test/docdemotecheck.sh
#
# WHAT IS BEING GATED. --for / --pack-task classify the QUERY's shape before they rank. When the query
# text parses as stack frames / sanitizer output / a compiler diagnostic (trace-shaped), or is a pasted
# issue-template form (bug-report-form-shaped), the DOCUMENT tier is scored down: documents by the same
# shrink-only path multiplier the fixture/generated tier already uses, and repository meta-prose (issue
# templates, CONTRIBUTING, CHANGELOG, CODE_OF_CONDUCT, SECURITY, anything under .github/) by that same
# multiplier applied twice. Demotion, never exclusion — and every firing is disclosed verbatim in the
# route= attribute, which is what makes the behaviour readable instead of magic.
#
# WHY THE FIXTURE LOOKS THE WAY IT DOES. test/docdemotefix is a purpose-built corpus, and it is built to
# LOSE on the unfixed binary: its `.github/ISSUE_TEMPLATE/bug_report.md` is ordinary GitHub boilerplate,
# and a pasted bug report retains that boilerplate, so on the pre-change binary the template outranks
# every line of source code in the repository it belongs to. Its CHANGELOG.md quotes the failure sentence
# of the traceback, which is how a changelog wins a stack-trace query. Both are the shapes the external
# retrieval lanes measured, reduced to the smallest corpus that still exhibits them — arms (b0)/(c0)
# below assert that the loss is REAL on the unfixed binary rather than assumed, so this gate cannot pass
# by measuring a corpus where nothing was ever wrong.
#
# ARMS
#   (a)  presence guard — the meta-documents this gate reasons about are actually indexed.
#   (b0) RED WITNESS — the boilerplate documents outscore the code by a wide margin on the RAW lexical
#        evidence, so the demotion has something to undo (asserted through --no-route, which never demotes).
#   (b)  bug-report form — the shape fires, the route= says so, and rank 1 is code, not a document.
#   (c0) RED WITNESS — same, for the traceback query.
#   (c)  traceback — the shape fires, the route= says so, and rank 1 is code, not a document.
#   (d)  meta-doc harder — two documents with BYTE-IDENTICAL text, one under .github/ISSUE_TEMPLATE/ and
#        one under notes/, tie on the unfixed binary and order .github first (path order); under a shaped
#        query the notes/ copy must now win, which is only true if meta-prose took the extra factor.
#   (e)  demotion, not exclusion — documents still appear in a shaped query's ranked export.
#   (f)  UNSHAPED conceptual --for is byte-identical to the pre-change golden.
#   (g)  --recall (the documents-only verb) is byte-identical to the pre-change golden, shaped query and all.
#   (h)  --no-route is byte-identical to the pre-change golden: with no route= there is nowhere to
#        disclose the demotion, so it does not happen.
#   (i)  --pack-task carries the same shape verdict and the same disclosure as --for.
#   (j)  the MCP `for` verb carries it too (surface parity, not a second implementation).
#   (k)  determinism — a shaped --for run twice is byte-identical.
#
# The three goldens were captured from the PRE-CHANGE binary and are invariance pins: (f)/(g)/(h) are
# red if the change ever leaks into a path it promised not to touch. The fixture is copied to a tmp dir
# OUTSIDE any git repo and scanned through a RELATIVE path, so no churn attribute and no absolute path
# reaches a golden.
#
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for the rank assertions"; exit 2; }
echo "docdemotecheck: BIN=$BIN"

cp -R "$ROOT/test/docdemotefix" "$TMP/docdemotefix"
cd "$TMP"

# ── the three queries, spelled once ─────────────────────────────────────────────────────────────────────
# BUGQ keeps the template scaffolding a pasted issue keeps; TRACEQ's frames point OUTSIDE the corpus on
# purpose, so nothing here can pass on the query-mention anchor instead of on the ranking; CONCEPTQ is
# ordinary prose that must match NEITHER shape.
BUGQ=$'**Describe the bug**\nA clear and concise description of what the bug is: the flush drops a pinned page.\n\n**Steps to reproduce**\nSteps to reproduce the behavior:\n1. Go to the page and open it\n2. See the error\n\n**Expected behavior**\nA clear and concise description of what you expected to happen.\n\n**Screenshots**\nIf applicable, add screenshots to help explain your problem.\n\n**Additional context**\nAdd any other context about the problem here, including the version and the platform.'
TRACEQ=$'Traceback (most recent call last):\n  File "/usr/lib/python3.11/runpy.py", line 198, in _run_module_as_main\n    return _run_code(code, main_globals, None,\n  File "/usr/lib/python3.11/runpy.py", line 88, in _run_code\n    exec(code, run_globals)\nRuntimeError: eviction of a pinned page in the page cache during flush'
CONCEPTQ='how does the evictor choose a victim page'

# rank of the first row whose path matches $2 in a candidates export $1 (empty when absent)
rank_of(){ python3 - "$1" "$2" <<'PY'
import re, sys
text = open( sys.argv[1], encoding='utf-8', errors='replace' ).read()
for m in re.finditer( r'<cand r="(\d+)"[^>]*? p="([^"]*)"', text ):
    if m.group( 2 ) == sys.argv[2]:
        print( m.group( 1 ) ); break
PY
}
# path of the rank-1 row
top_path(){ python3 - "$1" <<'PY'
import re, sys
text = open( sys.argv[1], encoding='utf-8', errors='replace' ).read()
m = re.search( r'<cand r="1"[^>]*? p="([^"]*)"', text )
print( m.group( 1 ) if m else '' )
PY
}

# Two surfaces per query, on purpose. --format=candidates is the FLAT ranked export, so it is the one
# surface where a rank is readable directly; the default --for bundle is where the route= prose lives.
# Both must tell the same story, which is why both are asserted rather than whichever is convenient.
"$BIN" docdemotefix --for="$BUGQ"     --format=candidates --no-cache >"$TMP/bug.xml"      2>/dev/null
"$BIN" docdemotefix --for="$TRACEQ"   --format=candidates --no-cache >"$TMP/trace.xml"    2>/dev/null
"$BIN" docdemotefix --for="$CONCEPTQ" --format=candidates --no-cache >"$TMP/conceptc.xml" 2>/dev/null
"$BIN" docdemotefix --for="$BUGQ" --no-route --format=candidates --no-cache >"$TMP/noroute.xml" 2>/dev/null
"$BIN" docdemotefix --for="$BUGQ"     --no-cache >"$TMP/bugfor.xml"    2>/dev/null
"$BIN" docdemotefix --for="$TRACEQ"   --no-cache >"$TMP/tracefor.xml"  2>/dev/null
# RE-PIN 2026-09-05 (capture-audit verify-wave2 F6, lane V2): docdemotegolden_for.xml 5238 -> 5237 B (-1 B,
# est_tokens="2095" UNCHANGED). ONE identified change: the route= value's TRAILING "]" — the unbalanced half
# L10b's finding-9 trim left behind (it took the leading " [" only, so every route value on every dialect
# shipped a dangling bracket). Verified before re-pinning: with est_tokens= and that one trailing bracket
# normalised out, the live document and the previous golden are byte-identical — no ranking, demotion or
# route byte moved. Gate: routeoncecheck (a1)/(b)/(c)/(c2), which now assert BOTH ends on all five surfaces.
# RE-PIN 2026-09-04 (capture-audit wave-2 merge): docdemotegolden_for.xml 5236 -> 5234 B (-2 B, est_tokens
# 2096 -> 2095). ONE identified change: lane L10b's route= trim (finding 9 — the value no longer starts with
# " [", verbs_for.h computeLensRanking), which landed AFTER lane V1 re-pinned this golden on its own tree.
# Verified before re-pinning: with `route=" [routed:` -> `route="routed:` and est_tokens= normalised, the
# live document and the previous golden are byte-identical — no ranking, demotion or route byte moved.
# RE-PIN 2026-09-04 (capture-audit verify-wave1 N1, lane V1): docdemotegolden_for.xml 5195 -> 5236 B (+41 B,
# est_tokens="2080" -> "2096") and docdemotegolden_noroute.xml 9188 -> 9229 B (+41 B, est_tokens="3240" -> "3257").
# CAUSE: --for now prices its ROOT — est_tokens= moved from the header comment onto <ctx> and the legend gained
# the 41-byte clause defining it (over_ceiling="1" rides the root only under a --token-budget; none here).
# Verified before re-pinning: with est_tokens= and that one clause normalized out, old and new documents are
# byte-identical — no ranking, demotion or route byte moved (gate: estchargecheck #15 d; same re-pin as
# anchorcheck/routecheck the same day).
"$BIN" docdemotefix --for="$CONCEPTQ" --no-cache >"$TMP/concept.xml"   2>/dev/null
"$BIN" docdemotefix --for="$BUGQ" --no-route --no-cache >"$TMP/noroutefor.xml" 2>/dev/null
"$BIN" docdemotefix --recall="$BUGQ" --no-cache >"$TMP/recall.xml" 2>/dev/null

# ── (a) presence guard — the documents this gate reasons about exist in the index ────────────────────────
missing=0
for p in ".github/ISSUE_TEMPLATE/bug_report.md" "CHANGELOG.md" "CONTRIBUTING.md" \
         ".github/ISSUE_TEMPLATE/tier_probe.md" "notes/tier_probe.md" "src/evictor.py"; do
    grep -q "p=\"$p\"" "$TMP/noroute.xml" || { missing=1; printf '        absent from the index: %s\n' "$p"; }
done
[ "$missing" -eq 0 ] && ok "(a) presence: every fixture document and the source file are indexed and ranked" \
                      || no "(a) presence: the fixture did not index what this gate asserts about"

# ── (b0) RED WITNESS — on the RAW lexical evidence the template beats the code ──────────────────────────
nr_top="$( top_path "$TMP/noroute.xml" )"
case "$nr_top" in
    *.md) ok "(b0) red witness: raw lexical rank 1 for a pasted bug form is a document ($nr_top)";;
    *)    no "(b0) red witness: raw lexical rank 1 is '$nr_top', not a document — the fixture no longer exhibits the loss this gate exists to fix";;
esac

# ── (b) bug-report form — the shape fires, is disclosed, and code takes rank 1 ──────────────────────────
grep -q 'doc tier demoted' "$TMP/bugfor.xml" \
    && grep -q 'bug-report-form-shaped' "$TMP/bugfor.xml" \
    && ok "(b) bug-report form: route= discloses the demotion and names the shape" \
    || no "(b) bug-report form: no demotion disclosure in route= for a pasted issue-template query"
grep -q 'doc_tier="demoted:bug-report"' "$TMP/bug.xml" \
    && ok "(b) bug-report form: the flat candidates export carries the same fact as doc_tier=" \
    || no "(b) bug-report form: --format=candidates re-ranked without a doc_tier= attribute to say so"
bug_top="$( top_path "$TMP/bug.xml" )"
case "$bug_top" in
    src/*) ok "(b) bug-report form: rank 1 is source ($bug_top), not the issue template";;
    *)     no "(b) bug-report form: rank 1 is '$bug_top' — the document tier still wins";;
esac

# ── (c0) RED WITNESS + (c) traceback ────────────────────────────────────────────────────────────────────
"$BIN" docdemotefix --for="$TRACEQ" --no-route --format=candidates --no-cache >"$TMP/tracenr.xml" 2>/dev/null
tnr_top="$( top_path "$TMP/tracenr.xml" )"
case "$tnr_top" in
    *.md) ok "(c0) red witness: raw lexical rank 1 for a pasted traceback is a document ($tnr_top)";;
    *)    no "(c0) red witness: raw lexical rank 1 is '$tnr_top', not a document — the traceback loss is no longer in the fixture";;
esac
grep -q 'doc tier demoted' "$TMP/tracefor.xml" \
    && grep -q 'trace-shaped' "$TMP/tracefor.xml" \
    && ok "(c) traceback: route= discloses the demotion and names the shape" \
    || no "(c) traceback: no demotion disclosure in route= for a pasted traceback"
grep -q 'doc_tier="demoted:trace"' "$TMP/trace.xml" \
    && ok "(c) traceback: the flat candidates export carries the same fact as doc_tier=" \
    || no "(c) traceback: --format=candidates re-ranked without a doc_tier= attribute to say so"
tr_top="$( top_path "$TMP/trace.xml" )"
case "$tr_top" in
    src/*) ok "(c) traceback: rank 1 is source ($tr_top), not the changelog";;
    *)     no "(c) traceback: rank 1 is '$tr_top' — the document tier still wins";;
esac

# ── (d) repository meta-prose takes the factor TWICE ────────────────────────────────────────────────────
# The two tier_probe documents carry byte-identical text, so any rank difference between them is the tier
# and nothing else. On the unfixed binary they tie and .github/ sorts first.
meta_rank="$( rank_of "$TMP/bug.xml" ".github/ISSUE_TEMPLATE/tier_probe.md" )"
note_rank="$( rank_of "$TMP/bug.xml" "notes/tier_probe.md" )"
if [ -n "$meta_rank" ] && [ -n "$note_rank" ] && [ "$note_rank" -lt "$meta_rank" ]; then
    ok "(d) meta-prose demoted harder: notes/tier_probe.md r=$note_rank above the .github/ twin r=$meta_rank"
else
    no "(d) meta-prose not demoted harder: notes/ r='$note_rank' vs .github/ r='$meta_rank' (identical text, so only the tier can separate them)"
fi

# ── (e) demotion, NOT exclusion ─────────────────────────────────────────────────────────────────────────
grep -q 'p="[^"]*\.md"' "$TMP/bug.xml" \
    && ok "(e) documents are demoted, not removed — a .md row still ranks under a shaped query" \
    || no "(e) no document survived a shaped query: this is exclusion, which the tier contract forbids"

# ── (f) UNSHAPED conceptual --for is byte-identical to the pre-change golden ─────────────────────────────
grep -q 'doc tier demoted' "$TMP/concept.xml" \
    && no "(f) conceptual query claimed a demotion: the detector over-fires on ordinary prose" \
    || ok "(f) conceptual query: no demotion claimed"
grep -q 'doc_tier="' "$TMP/conceptc.xml" \
    && no "(f) conceptual query emitted a doc_tier= attribute: the detector over-fires on ordinary prose" \
    || ok "(f) conceptual query: no doc_tier= attribute on the candidates export either"
diff -q "$TMP/concept.xml" "$ROOT/test/docdemotegolden_for.xml" >/dev/null \
    && ok "(f) conceptual --for byte-identical to the pre-change golden" \
    || no "(f) conceptual --for drifted from test/docdemotegolden_for.xml"

# ── (g) --recall untouched ──────────────────────────────────────────────────────────────────────────────
diff -q "$TMP/recall.xml" "$ROOT/test/docdemotegolden_recall.golden" >/dev/null \
    && ok "(g) --recall byte-identical to the pre-change golden on the same shaped query" \
    || no "(g) --recall drifted from test/docdemotegolden_recall.golden — the documents lens must not take the ranking tier"

# ── (h) --no-route untouched ────────────────────────────────────────────────────────────────────────────
diff -q "$TMP/noroutefor.xml" "$ROOT/test/docdemotegolden_noroute.xml" >/dev/null \
    && ok "(h) --no-route byte-identical to the pre-change golden (no route= ⇒ no undisclosed demotion)" \
    || no "(h) --no-route drifted from test/docdemotegolden_noroute.xml"
grep -q 'doc_tier="' "$TMP/noroute.xml" \
    && no "(h) --no-route emitted a doc_tier= attribute: the opt-out path must not demote at all" \
    || ok "(h) --no-route carries no doc_tier= attribute"

# ── (i) --pack-task carries the same verdict and disclosure ─────────────────────────────────────────────
"$BIN" docdemotefix --pack-task="$BUGQ" --no-cache >"$TMP/pack.xml" 2>/dev/null
grep -q 'doc tier demoted' "$TMP/pack.xml" && grep -q 'bug-report-form-shaped' "$TMP/pack.xml" \
    && ok "(i) --pack-task discloses the same demotion as --for" \
    || no "(i) --pack-task did not disclose the demotion — the two verbs share one ranking and must share its disclosure"

# ── (j) the MCP `for` verb, same fact, same words ───────────────────────────────────────────────────────
python3 - "$BIN" "$TMP/docdemotefix" "$BUGQ" >"$TMP/mcp.txt" 2>/dev/null <<'PY'
import json, subprocess, sys
binp, root, task = sys.argv[1], sys.argv[2], sys.argv[3]
req = [ json.dumps( { "jsonrpc": "2.0", "id": 1, "method": "initialize" } ),
        json.dumps( { "jsonrpc": "2.0", "id": 2, "method": "tools/call",
                      "params": { "name": "for", "arguments": { "path": root, "task": task } } } ) ]
p = subprocess.run( [ binp, "--mcp" ], input = "\n".join( req ) + "\n",
                    capture_output = True, text = True )
for line in p.stdout.splitlines():
    try:
        r = json.loads( line )
    except Exception:
        continue
    if r.get( "id" ) == 2 and "result" in r:
        sys.stdout.write( r["result"]["content"][0]["text"] )
PY
if [ -s "$TMP/mcp.txt" ]; then
    grep -q 'doc tier demoted' "$TMP/mcp.txt" && grep -q 'bug-report-form-shaped' "$TMP/mcp.txt" \
        && ok "(j) MCP for verb discloses the same demotion as the CLI --for" \
        || no "(j) MCP for verb did not disclose the demotion — CLI/MCP ranking parity is broken"
else
    no "(j) MCP for verb returned nothing (the parity arm must not pass by producing no output)"
fi

# ── (k) determinism on the shaped route ─────────────────────────────────────────────────────────────────
"$BIN" docdemotefix --for="$BUGQ" --format=candidates --no-cache >"$TMP/bug2.xml" 2>/dev/null
diff -q "$TMP/bug.xml" "$TMP/bug2.xml" >/dev/null \
    && ok "(k) determinism: a shape-matched --for run twice is byte-identical" \
    || no "(k) determinism: two shape-matched --for runs differ"

[ "$fail" -eq 0 ] && echo "docdemotecheck: ALL PASS" || echo "docdemotecheck: FAILURES"
exit "$fail"
