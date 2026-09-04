#!/usr/bin/env bash
# completecheck.sh — T1 COMPLETENESS CLAIMS: the mirror of the floor vocabulary.
#
# The honesty vocabulary discloses UNCERTAINTY (counts_floor=, hits_capped=, shown=/capped=, <more/>).
# This gate pins the mirror: when an answer IS exhaustive, the tool says so machine-readably —
# `complete="1"` on the container element — so a consumer need not re-derive (re-grep, re-scan branches)
# an answer that already listed everything. A FALSE completeness claim is the worst bug this tool can
# ship, so most arms here are MUTATION arms: force each partiality condition and assert the attribute
# VANISHES.
#
# WHO MAY CLAIM (the probe's verdict, pinned by arms 10a/10b):
#   --grep     literal scans (and regex with the prefilter disabled): a full end-to-end read of every
#              indexed file, no collection ceiling reached, no unreadable file, every hit printed.
#              R-H (2026-08-19) adds the FIFTH condition: nothing was SPAN-TIER suppressed. The default
#              --grep serves the tightest non-empty tier, so an answer that held comment/string rows back
#              did not print every hit it found and may not claim exhaustiveness; grep-in=any (the
#              un-tiered listing) is where the claim lives now, and arm 4b is its mutation twin.
#              A prefiltered regex answer NEVER claims (the claim would rest on the analyzer, not on
#              a full read). The claim is complete-WITHIN-THE-INDEX: files the ingest skipped (the
#              skipped verb) were never scanned, and the legend must say so wherever the claim appears.
#   --whereis  every occurrence in every TEXT blob of every scanned ref's full tree printed; no blob
#              oversized/missing/short-read, no cap or page cut the listing.
#   NEVER: the five graph-count verbs (--uses/--callers/--callees/--impact/--edit-check). Their counts
#   are FLOORS of an unmodelable reality (src/graphlegend.h: dynamic dispatch, escaped fn-pointers,
#   unindexed macros contribute no edge) — §H4 retired exactly this absolutism from --uses' legend,
#   and a complete= there would resurrect it. counts_floor= and complete= are mutually exclusive.
#
# Usage:  test/completecheck.sh              # uses build/ripwire
#         RIPWIRE_BIN=asan/ripwire test/completecheck.sh
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
cd "$ROOT"
echo "completecheck: BIN=$BIN"

CORPUS=test/fixture

# the root START-TAG only — the legend COMMENT also spells complete= (it defines it), so every
# presence/absence assertion must parse the element, never grep the stream.
root_of(){ grep -o "<$1 [^>]*>" | head -1; }

# ── 1) a small literal scan claims: every hit printed, no ceiling, no cap ──────────────────────────────
"$BIN" "$CORPUS" --grep=distance --grep-in=any >"$TMP/g1.xml" 2>/dev/null; rc=$?
G1ROOT="$( root_of grep <"$TMP/g1.xml" )"
{ [ $rc -eq 0 ] && printf '%s' "$G1ROOT" | grep -q 'complete="1"'; } \
    && ok 'grep: small literal scan carries complete="1" on the root' \
    || { no "grep: literal scan lost complete= (rc=$rc)"; printf '%s\n' "$G1ROOT"; }

# ── 2) the claim never appears without its legend: definition + the within-the-index caveat ────────────
{ grep -q 'complete= ' "$TMP/g1.xml" || grep -q 'complete=(' "$TMP/g1.xml" || grep -q 'COMPLETENESS: complete=' "$TMP/g1.xml"; } \
    && ok 'grep: the legend defines complete= where the claim appears' \
    || no 'grep: complete= claimed but the legend never defines it'
grep -q 'complete-within-the-index' "$TMP/g1.xml" \
    && ok 'grep: the legend scopes the claim to the INDEX (skipped files are outside it)' \
    || no 'grep: the within-the-index caveat is missing from the legend'
grep -q 'skipped' "$TMP/g1.xml" \
    && ok 'grep: the legend names the skipped verb as the list of what is outside the claim' \
    || no 'grep: the legend does not point at the skipped surface'

# ── 3) the ZERO-hit claim — the strongest answer this verb can give ────────────────────────────────────
# With complete= present, hits="0" means "no occurrence exists in any indexed file", the exact claim
# the floor vocabulary forbids WITHOUT the attribute. This is the verify-a-claim terminator.
"$BIN" "$CORPUS" --grep=zqzq_no_such_token_zqzq >"$TMP/g0.xml" 2>/dev/null
G0ROOT="$( root_of grep <"$TMP/g0.xml" )"
{ printf '%s' "$G0ROOT" | grep -q 'hits="0"' && printf '%s' "$G0ROOT" | grep -q 'complete="1"'; } \
    && ok 'grep: an exhaustive zero-hit scan claims complete= (none exists in the index)' \
    || { no 'grep: zero-hit exhaustive scan does not claim'; printf '%s\n' "$G0ROOT"; }

# ── 4) MUTATION: a --limit cap must drop the claim ─────────────────────────────────────────────────────
# H4 (capture-audit 2026-09-04): the root now also states unindexed_hits= (the second, out-of-index
# population), so an unanchored hits=" match returns TWO numbers and every arithmetic below reads garbage.
# Anchored on the leading space, which is what makes it the root's OWN hits= attribute.
HITS="$( printf '%s' "$G1ROOT" | grep -oE ' hits="[0-9]*"' | head -1 | grep -o '[0-9]*' )"
if [ "${HITS:-0}" -ge 2 ]; then
    "$BIN" "$CORPUS" --grep=distance --limit=1 >"$TMP/g2.xml" 2>/dev/null
    G2ROOT="$( root_of grep <"$TMP/g2.xml" )"
    { printf '%s' "$G2ROOT" | grep -q 'capped="1"' && ! printf '%s' "$G2ROOT" | grep -q 'complete='; } \
        && ok 'grep MUTATION: forcing a row cap (limit=1) makes complete= vanish' \
        || { no 'grep MUTATION: complete= survived a row cap'; printf '%s\n' "$G2ROOT"; }
else
    no "grep: fixture yields fewer than 2 'distance' hits ($HITS) — the cap mutation has no room"
fi

# ── 5) MUTATION: an --offset that skips row 0 must drop the claim ──────────────────────────────────────
"$BIN" "$CORPUS" --grep=distance --offset=1 >"$TMP/g3.xml" 2>/dev/null
G3ROOT="$( root_of grep <"$TMP/g3.xml" )"
{ [ -n "$G3ROOT" ] && ! printf '%s' "$G3ROOT" | grep -q 'complete='; } \
    && ok 'grep MUTATION: a page that skips rows (offset=1) never claims' \
    || { no 'grep MUTATION: complete= survived offset=1'; printf '%s\n' "$G3ROOT"; }

# ── 5b) MUTATION (R-H): a SPAN-TIER-FILTERED listing never claims ──────────────────────────────────────
# The default --grep on this corpus holds `distance`'s comment mentions back (geometry.cpp's trailing
# `// edge: perimeter -> distance`), so the printed set is not every hit found — exactly the shape
# complete= must refuse. This is the fifth partiality condition, and its mutation arm.
"$BIN" "$CORPUS" --grep=distance >"$TMP/g3b.xml" 2>/dev/null
G3BROOT="$( root_of grep <"$TMP/g3b.xml" )"
printf '%s' "$G3BROOT" | grep -q 'suppressed_comment="' \
    && ok 'grep: the default answer on this corpus DOES suppress a comment row (the arm is live)' \
    || { no 'grep: nothing was tier-suppressed, so the next assertion proves nothing'; printf '%s\n' "$G3BROOT"; }
printf '%s' "$G3BROOT" | grep -q 'complete="1"' \
    && { no 'grep MUTATION: complete= survived a tier-filtered listing'; printf '%s\n' "$G3BROOT"; } \
    || ok 'grep MUTATION: a tier-filtered listing never claims'

# ── 6) an explicit page that COVERS the whole listing still claims ─────────────────────────────────────
"$BIN" "$CORPUS" --grep=distance --grep-in=any --limit=100000 >"$TMP/g4.xml" 2>/dev/null
G4ROOT="$( root_of grep <"$TMP/g4.xml" )"
printf '%s' "$G4ROOT" | grep -q 'complete="1"' \
    && ok 'grep: an explicit limit wide enough to show everything keeps the claim' \
    || { no 'grep: a whole-listing page lost the claim'; printf '%s\n' "$G4ROOT"; }

# ── 7) regex NEVER claims — in either prefilter mode ───────────────────────────────────────────────────
# Prefiltered, the claim would rest on the analyzer, not on a full read. And no-prefilter may not claim
# what prefiltered does not: the two modes are contractually BYTE-IDENTICAL (test/regexcheck.sh's
# soundness oracle diffs them — the prefilter is a performance switch, never an answer switch), so a
# mode-dependent attribute would break the oracle. complete= is a literal-scan claim only.
"$BIN" "$CORPUS" --regex='dist[a-z]+' >"$TMP/g5.xml" 2>/dev/null
G5ROOT="$( root_of grep <"$TMP/g5.xml" )"
{ [ -n "$G5ROOT" ] && ! printf '%s' "$G5ROOT" | grep -q 'complete='; } \
    && ok 'grep: a prefiltered regex answer never claims (the claim would rest on the analyzer)' \
    || { no 'grep: prefiltered regex claimed complete='; printf '%s\n' "$G5ROOT"; }
"$BIN" "$CORPUS" --regex='dist[a-z]+' --no-prefilter >"$TMP/g6.xml" 2>/dev/null
G6ROOT="$( root_of grep <"$TMP/g6.xml" )"
{ [ -n "$G6ROOT" ] && ! printf '%s' "$G6ROOT" | grep -q 'complete='; } \
    && ok 'grep: a no-prefilter regex answer never claims either (mode parity — the soundness oracle diffs the modes)' \
    || { no 'grep: no-prefilter regex claimed complete= (mode-dependent answer breaks the oracle)'; printf '%s\n' "$G6ROOT"; }

# ── 8) MUTATION: the collection ceiling (hits_capped) must drop the claim ──────────────────────────────
# kGrepCollectionBudget is 4,000,000 raw hits. Build a scratch corpus whose one pattern exceeds it:
# 11 markdown files x 400k occurrences (multiple hits per line — a hit is an occurrence, not a line).
# Each file stays under kDefaultMaxFileBytes (4 MB) or the ingest would SKIP it and grep would scan
# nothing: 4,000 x 9 bytes = 36 KB per line, x100 lines = 3.6 MB per file.
BUDGETDIR="$TMP/budget"; mkdir -p "$BUDGETDIR"
python3 - "$BUDGETDIR" <<'PYEOF'
import sys, os
d = sys.argv[1]
line = ("zqbudget " * 4000).rstrip() + "\n"          # 4,000 occurrences per line
for i in range(11):
    with open(os.path.join(d, f"bulk{i}.md"), "w") as f:
        for _ in range(100):                          # 400,000 per file; 4.4M total
            f.write(line)
PYEOF
"$BIN" "$BUDGETDIR" --grep=zqbudget --no-cache >"$TMP/g7.xml" 2>/dev/null
G7ROOT="$( root_of grep <"$TMP/g7.xml" )"
{ printf '%s' "$G7ROOT" | grep -q 'hits_capped="1"' && ! printf '%s' "$G7ROOT" | grep -q 'complete='; } \
    && ok 'grep MUTATION: reaching the collection ceiling (hits_capped) makes complete= vanish' \
    || { no 'grep MUTATION: complete= beside a floored total, or the ceiling never fired'; printf '%s\n' "$G7ROOT"; }

# ── 9) MUTATION: a file the scan cannot READ must drop the claim ───────────────────────────────────────
UNREADDIR="$TMP/unread"
cp -R "$CORPUS" "$UNREADDIR"
chmod 000 "$UNREADDIR/related.md" 2>/dev/null
if [ -r "$UNREADDIR/related.md" ]; then
    printf '  SKIP  grep MUTATION unreadable file (running as root — chmod 000 is not a barrier)\n'
else
    "$BIN" "$UNREADDIR" --grep=distance --no-cache >"$TMP/g8.xml" 2>/dev/null
    G8ROOT="$( root_of grep <"$TMP/g8.xml" )"
    { [ -n "$G8ROOT" ] && ! printf '%s' "$G8ROOT" | grep -q 'complete='; } \
        && ok 'grep MUTATION: an unreadable indexed file makes complete= vanish' \
        || { no 'grep MUTATION: complete= survived an unreadable file'; printf '%s\n' "$G8ROOT"; }
    chmod 644 "$UNREADDIR/related.md" 2>/dev/null
fi

# ── 10) the graph verbs NEVER claim — counts_floor= and complete= are mutually exclusive ───────────────
"$BIN" "$CORPUS" --uses=distance >"$TMP/u1.xml" 2>/dev/null
U1ROOT="$( root_of uses <"$TMP/u1.xml" )"
{ printf '%s' "$U1ROOT" | grep -q 'counts_floor="1"' && ! printf '%s' "$U1ROOT" | grep -q 'complete='; } \
    && ok 'uses: still a floor (counts_floor=), never complete= — the §H4 absolutism stays retired' \
    || { no 'uses: complete= appeared beside a floored count, or the floor marker is gone'; printf '%s\n' "$U1ROOT"; }
"$BIN" "$CORPUS" --callers=distance >"$TMP/c1.xml" 2>/dev/null
C1ROOT="$( root_of callers <"$TMP/c1.xml" )"
{ printf '%s' "$C1ROOT" | grep -q 'counts_floor="1"' && ! printf '%s' "$C1ROOT" | grep -q 'complete='; } \
    && ok 'callers: still a floor (counts_floor=), never complete=' \
    || { no 'callers: complete= appeared beside a floored count, or the floor marker is gone'; printf '%s\n' "$C1ROOT"; }

# ── 11) determinism + well-formedness of a claiming document ───────────────────────────────────────────
"$BIN" "$CORPUS" --grep=distance --grep-in=any >"$TMP/g1b.xml" 2>/dev/null
diff -q "$TMP/g1.xml" "$TMP/g1b.xml" >/dev/null \
    && ok 'grep: a claiming answer is byte-deterministic across runs' \
    || no 'grep: claiming answer differs across two runs'
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/g1.xml" 2>/dev/null && ok 'grep: claiming document is well-formed XML' || no 'grep: claiming document is malformed'
else
    printf '  SKIP  xmllint (not installed)\n'
fi

# ── 12) the MCP grep twin claims and un-claims with the CLI ────────────────────────────────────────────
mcp_call(){ printf '{"jsonrpc":"2.0","id":1,"method":"initialize"}\n{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"grep","arguments":{"path":"%s","pattern":"distance"%s}}}\n' "$1" "$2"; }
mcp_call "$CORPUS" ',"in":"any"' | "$BIN" --mcp >"$TMP/m1.json" 2>/dev/null
mcp_call "$CORPUS" ',"limit":1'  | "$BIN" --mcp >"$TMP/m2.json" 2>/dev/null
# inside the JSON-RPC wrapper the payload's quotes are ESCAPED: \"complete\":true
grep -q '\\"complete\\":true' "$TMP/m1.json" \
    && ok 'mcp grep: un-paged literal answer carries complete true' \
    || { no 'mcp grep: complete missing from an exhaustive answer'; grep -o '\\"hits_capped\\":[a-z]*' "$TMP/m1.json" | head -2; }
# the mutation only has power if the same file DOES carry the escaped hits_capped key (wrapper sanity)
grep -q '\\"hits_capped\\":' "$TMP/m2.json" && ! grep -q '\\"complete\\":true' "$TMP/m2.json" \
    && ok 'mcp grep MUTATION: limit=1 makes the claim vanish' \
    || no 'mcp grep MUTATION: complete true survived a row cap (or the wrapper shape changed)'

# ── whereis: the cross-branch claim ────────────────────────────────────────────────────────────────────
if command -v git >/dev/null 2>&1; then
    R="$TMP/repo"; mkdir -p "$R"
    export GIT_AUTHOR_NAME=ripwire GIT_AUTHOR_EMAIL=ripwire@example.invalid
    export GIT_COMMITTER_NAME=ripwire GIT_COMMITTER_EMAIL=ripwire@example.invalid
    export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"
    g(){ git -C "$R" "$@" >/dev/null 2>&1; }
    g init -q -b main
    g config commit.gpgsign false
    printf 'int zqWhereToken( int x )\n{\n    return x + 1;\n}\n' > "$R/alpha.cpp"
    g add alpha.cpp; g commit -qm base
    g checkout -qb side
    printf '// zqWhereToken is used here too\nint other() { return zqWhereToken( 2 ); }\n' > "$R/beta.cpp"
    g add beta.cpp; g commit -qm side
    g checkout -q main

    # ── 13) an uncut tree scan claims ──────────────────────────────────────────────────────────────────
    "$BIN" "$R" --whereis=zqWhereToken --no-cache >"$TMP/w1.xml" 2>/dev/null; rc=$?
    W1ROOT="$( root_of whereis <"$TMP/w1.xml" )"
    { [ $rc -eq 0 ] && printf '%s' "$W1ROOT" | grep -q 'complete="1"'; } \
        && ok 'whereis: an uncut full-tree scan carries complete="1"' \
        || { no "whereis: exhaustive scan lost complete= (rc=$rc)"; printf '%s\n' "$W1ROOT"; }
    grep -q 'complete=' "$TMP/w1.xml" && grep -q 'TEXT blob' "$TMP/w1.xml" \
        && ok 'whereis: the legend defines complete= and scopes it to text blobs' \
        || no 'whereis: the claim appears without its legend definition'

    # ── 14) MUTATION: a --limit cap must drop the claim ────────────────────────────────────────────────
    WHITS="$( printf '%s' "$W1ROOT" | grep -o 'hits="[0-9]*"' | grep -o '[0-9]*' )"
    if [ "${WHITS:-0}" -ge 2 ]; then
        "$BIN" "$R" --whereis=zqWhereToken --limit=1 --no-cache >"$TMP/w2.xml" 2>/dev/null
        W2ROOT="$( root_of whereis <"$TMP/w2.xml" )"
        { [ -n "$W2ROOT" ] && ! printf '%s' "$W2ROOT" | grep -q 'complete='; } \
            && ok 'whereis MUTATION: forcing a row cap (limit=1) makes complete= vanish' \
            || { no 'whereis MUTATION: complete= survived a row cap'; printf '%s\n' "$W2ROOT"; }
    else
        no "whereis: fixture yields fewer than 2 hits ($WHITS) — the cap mutation has no room"
    fi

    # ── 15) MUTATION: an OVERSIZED text blob (silently unscannable) must drop the claim ────────────────
    # kMaxBlobBytes is 2 MB; a symbol inside a larger blob is invisible to the scan, so the scan may
    # not claim exhaustiveness over a tree that contains one.
    g checkout -qb bigblob
    python3 - "$R/huge.txt" <<'PYEOF'
import sys
with open(sys.argv[1], "w") as f:
    f.write("filler line of ordinary text\n" * 80000)     # ~2.3 MB
    f.write("zqWhereToken hides in an oversized blob\n")
PYEOF
    g add huge.txt; g commit -qm bigblob
    g checkout -q main
    "$BIN" "$R" --whereis=zqWhereToken --no-cache >"$TMP/w3.xml" 2>/dev/null
    W3ROOT="$( root_of whereis <"$TMP/w3.xml" )"
    { [ -n "$W3ROOT" ] && ! printf '%s' "$W3ROOT" | grep -q 'complete='; } \
        && ok 'whereis MUTATION: an oversized blob in any scanned tree makes complete= vanish' \
        || { no 'whereis MUTATION: complete= survived an oversized (unscanned) blob'; printf '%s\n' "$W3ROOT"; }

    # ── 16) determinism + well-formedness of the claiming whereis ──────────────────────────────────────
    # Two FRESH runs at the same repo state (w1 predates the bigblob branch, so it is not comparable).
    "$BIN" "$R" --whereis=zqWhereToken --no-cache >"$TMP/w4a.xml" 2>/dev/null
    "$BIN" "$R" --whereis=zqWhereToken --no-cache >"$TMP/w4b.xml" 2>/dev/null
    diff -q "$TMP/w4a.xml" "$TMP/w4b.xml" >/dev/null \
        && ok 'whereis: a claiming answer is byte-deterministic across runs' \
        || no 'whereis: claiming answer differs across two runs'
    if command -v xmllint >/dev/null 2>&1; then
        xmllint --noout "$TMP/w1.xml" 2>/dev/null && ok 'whereis: claiming document is well-formed XML' || no 'whereis: claiming document is malformed'
    fi
else
    printf '  SKIP  whereis arms (git unavailable)\n'
fi

[ $fail -eq 0 ] && printf 'completecheck: ALL PASS\n' || printf 'completecheck: FAILURES ABOVE\n'
exit $fail
