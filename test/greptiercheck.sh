#!/usr/bin/env bash
# greptiercheck.sh — gate for R-H (2026-08-15 harvest report-ugrep §F3+§F4, funded by wave-2 experiment E5):
# SPAN TIERS on --grep. Every hit is classified by the tree-sitter span it lands in — code / comment /
# string — and the default answer emits only the TIGHTEST NON-EMPTY tier, disclosing what it held back.
#
# The measured problem (report-ugrep §F3): 22-42% of a --grep answer's rows are comment/#include/prose
# mentions the verb could not enrich; --regex=mcp[A-Za-z]*Stale paid 19 rows for the 1 definition.
#
# The cost model (E5, PLAN_WAVE2_REPORTS_2026-08-17/exp-e5.md): a per-hit-file on-demand parse, NOT
# astQuery (which always walks the whole corpus). E5's third design condition — a disclosed bail-out for
# the giant-file ceiling — is arms (5)/(6) here.
#
# Asserts:
#   (1) TIERING FIRES: one literal in code, in a comment and in a string ⇒ the default answer shows the
#       CODE hit only, and discloses suppressed_comment=/suppressed_string= exactly.
#   (2) ESCAPE HATCH: --grep-in=any shows all three and carries NO tier attributes at all (a plain
#       untiered answer is byte-identical to the pre-lane shape — purely additive, no re-run hint).
#   (3) F4 FALLBACK (globally tightest NON-EMPTY tier): a literal that exists ONLY in comments is still
#       answered — with tier="comment", never an honest-looking empty.
#   (4) AN ANSWER THAT HELD NOTHING BACK CLAIMS NOTHING: a doc-file-only hit prints with no tier
#       vocabulary at all. (The unclassified population — hits the budget never reached — is arm (5c):
#       they are COUNTED in tier_unclassified= and always emitted, never suppressed.)
#   (5) BAIL-OUT (files): past kGrepTierFileBudget hit files the scan stops and says tier_budget="files";
#       the hits it did not classify are still emitted.
#   (6) BAIL-OUT (bytes): past kGrepTierByteBudget the scan stops and says tier_budget="bytes".
#   (7) COMPLETENESS: complete= is WITHHELD when rows were suppressed (a filtered listing may not claim
#       to be exhaustive) and still claimed on the same corpus under --grep-in=any.
#   (8) LEGEND: the tier prose appears exactly when a tier attribute does (legendcoveragecheck's rule,
#       enforced locally on both directions so a byte-frugal answer stays byte-frugal).
#   (9) MCP PARITY: the MCP grep verb suppresses the same rows and reports the same counters (search.h's
#       one-collection rule — the CLI verb and the MCP verb may never diverge).
#  (10) DETERMINISM + well-formedness on every tiered surface.
#
# MUTATION EVIDENCE: arms (1), (3), (5) and (6) all FAIL against the pre-lane baseline binary (the
# integration head this lane branched from), which has no tier axis at all — run
#   bash test/greptiercheck.sh /path/to/baseline/build/ripwire
# to see the gate red on baseline behaviour.
#
# Usage:
#   bash test/greptiercheck.sh                            # uses build/ripwire
#   bash test/greptiercheck.sh path/to/ripwire            # explicit binary (the mutation arm)
#   RIPWIRE_BIN=asan/ripwire bash test/greptiercheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
attr(){ printf '%s' "$2" | grep -oE "$1=\"[^\"]*\"" | head -1 | sed -E "s/^$1=\"//; s/\"$//"; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "greptiercheck: BIN=$BIN"

# ── the sandbox: ONE token (TIERTOKEN_frob) placed deliberately in all three spans ─────────────────────
# notes.md carries the same token: markdown HAS a grammar here (kLangTable's Markdown DOC tier), so its
# prose parses to code-tier nodes and the row is served — deliberately, since a doc hit is a real answer
# and the path tier already ranks docs last. The genuinely unclassifiable population is arm (5c)'s.
SB="$TMP/tiersandbox"
mkdir -p "$SB/src"
cat >"$SB/src/tiers.c" <<'EOF'
// TIERTOKEN_frob is named here in a COMMENT and must not print by default
const char* tierMessage = "TIERTOKEN_frob lives in a STRING literal too";
int TIERTOKEN_frob( int x )
{
    return x + 1;
}
/* TIERTOKEN_frob again, block comment */
int TIERTOKEN_onlycomment_caller( int y )
{
    // TIERTOKEN_onlycomment appears in comments and NOWHERE else
    return y;   /* TIERTOKEN_onlycomment second mention */
}
EOF
cat >"$SB/notes.md" <<'EOF'
TIERTOKEN_md is mentioned in markdown, which has no grammar to tier it by.
TIERTOKEN_frob is mentioned here too, and an unclassifiable row is never suppressed.
EOF

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (1) tiering fires: the default answer is the CODE tier only ==="
# ═══════════════════════════════════════════════════════════════════════════
D_OUT="$( "$BIN" "$SB" --no-cache --grep=TIERTOKEN_frob 2>/dev/null )"
d_hits="$( attr hits "$D_OUT" )"
d_comment="$( attr suppressed_comment "$D_OUT" )"
d_string="$( attr suppressed_string "$D_OUT" )"
if [ "$d_hits" = "2" ] && [ "$d_comment" = "2" ] && [ "$d_string" = "1" ]; then
    ok "(1) code hit + the doc-file mention kept, 2 comment + 1 string suppressed and disclosed"
else
    no "(1) expected hits=2 suppressed_comment=2 suppressed_string=1, got hits=$d_hits comment=$d_comment string=$d_string"
    printf '%s\n' "$D_OUT" | grep -o '<grep [^>]*>'
fi
# the surviving row must be the DEFINITION line, not one of the prose mentions
printf '%s' "$D_OUT" | grep -q 'in="TIERTOKEN_frob"' \
    && ok "(1b) the kept row is the definition (enclosing symbol present)" \
    || no "(1b) the kept row is not the definition — tier assignment picked the wrong hit"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (2) --grep-in=any: every tier, and NO tier attributes at all ==="
# ═══════════════════════════════════════════════════════════════════════════
A_OUT="$( "$BIN" "$SB" --no-cache --grep=TIERTOKEN_frob --grep-in=any 2>/dev/null )"
a_hits="$( attr hits "$A_OUT" )"
[ "$a_hits" = "5" ] && ok "(2) --grep-in=any keeps all 5 hits" || no "(2) --grep-in=any expected hits=5, got $a_hits"
if printf '%s' "$A_OUT" | grep -qE 'suppressed_comment=|suppressed_string=|tier_budget=|tier_unclassified=|tier="'; then
    no "(2b) --grep-in=any leaked a tier attribute onto an untiered answer"
else
    ok "(2b) an untiered answer carries no tier attribute (purely additive)"
fi

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (3) F4: the globally tightest NON-EMPTY tier — comments-only still answers ==="
# ═══════════════════════════════════════════════════════════════════════════
C_OUT="$( "$BIN" "$SB" --no-cache --grep=TIERTOKEN_onlycomment 2>/dev/null )"
c_hits="$( attr hits "$C_OUT" )"
c_tier="$( attr tier "$C_OUT" )"
# 3 occurrences: the function NAME (code) + 2 comment mentions. The name makes code non-empty, so the
# tightest tier is code and the 2 comment rows are suppressed — the ANCHOR of the fallback arm is the
# token below, which exists ONLY inside comments.
cat >"$SB/src/onlyprose.c" <<'EOF'
int proseHost( void )
{
    // TIERTOKEN_prose is discussed only in comments
    return 0;   /* TIERTOKEN_prose, second mention */
}
EOF
P_OUT="$( "$BIN" "$SB" --no-cache --grep=TIERTOKEN_prose 2>/dev/null )"
p_hits="$( attr hits "$P_OUT" )"
p_tier="$( attr tier "$P_OUT" )"
if [ "$p_hits" = "2" ] && [ "$p_tier" = "comment" ]; then
    ok "(3) a comments-only pattern still answers, disclosed as tier=comment"
else
    no "(3) expected hits=2 tier=comment on a comments-only pattern, got hits=$p_hits tier=$p_tier"
    printf '%s\n' "$P_OUT" | grep -o '<grep [^>]*>'
fi
[ "$c_hits" = "1" ] && ok "(3b) a token present in BOTH code and comments serves the code tier" \
                    || no "(3b) expected hits=1 (code tier) for TIERTOKEN_onlycomment, got $c_hits (tier=$c_tier)"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (4) a file with no grammar is never suppressed, and claims nothing ==="
# ═══════════════════════════════════════════════════════════════════════════
M_OUT="$( "$BIN" "$SB" --no-cache --grep=TIERTOKEN_md 2>/dev/null )"
m_hits="$( attr hits "$M_OUT" )"
if [ "$m_hits" = "1" ] && ! printf '%s' "$M_OUT" | grep -qE 'suppressed_comment=|suppressed_string=|tier_unclassified=|tier="'; then
    ok "(4) the markdown-only hit survives, and an answer that held nothing back says nothing"
else
    no "(4) expected hits=1 with NO tier vocabulary for a markdown-only hit, got hits=$m_hits"
    printf '%s\n' "$M_OUT" | grep -o '<grep [^>]*>'
fi

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (5) disclosed bail-out — the FILE budget ==="
# ═══════════════════════════════════════════════════════════════════════════
FB="$TMP/filebudget"; mkdir -p "$FB"
python3 - "$FB" <<'PY'
import sys, os
d = sys.argv[1]
# 300 files, each with ONE comment hit and ONE code hit of the same token: the tiered prefix suppresses
# its comment rows, and the untiered tail must still emit BOTH of its rows.
for i in range( 300 ):
    with open( os.path.join( d, "f%03d.c" % i ), "w" ) as fh:
        fh.write( "// BUDGETTOKEN_wide in a comment\nint BUDGETTOKEN_wide_%03d( void ) { return %d; }\n" % ( i, i ) )
PY
FB_OUT="$( "$BIN" "$FB" --no-cache --grep=BUDGETTOKEN_wide --limit=1000 2>/dev/null )"
fb_budget="$( attr tier_budget "$FB_OUT" )"
fb_files="$( attr tier_parsed "$FB_OUT" )"
fb_hits="$( attr hits "$FB_OUT" )"
fb_comment="$( attr suppressed_comment "$FB_OUT" )"
fb_unc="$( attr tier_unclassified "$FB_OUT" )"
if [ "$fb_budget" = "files" ] && [ -n "$fb_files" ] && [ "$fb_files" -lt 300 ]; then
    ok "(5) the file budget trips, is disclosed, and names how many files were tiered ($fb_files/300)"
else
    no "(5) expected tier_budget=files with tier_parsed<300, got budget=$fb_budget files=$fb_files"
    printf '%s\n' "$FB_OUT" | grep -o '<grep [^>]*>'
fi
# the tail's comment hits are still emitted — a budget may not silently delete rows it never looked at
if [ -n "$fb_hits" ] && [ -n "$fb_comment" ] && [ "$fb_hits" = "$(( 600 - fb_comment ))" ] && [ "$fb_comment" = "$fb_files" ]; then
    ok "(5b) exactly the tiered prefix's comment rows were suppressed; the untiered tail is emitted whole"
else
    no "(5b) budget arithmetic is off: hits=$fb_hits suppressed_comment=$fb_comment tier_parsed=$fb_files (expected hits = 600 - suppressed, suppressed == tier_parsed)"
fi
# and the rows it never looked at are COUNTED as unclassified, not silently folded into the code tier
[ -n "$fb_unc" ] && [ "$fb_unc" = "$(( ( 300 - fb_files ) * 2 ))" ] \
    && ok "(5c) every hit past the budget is counted in tier_unclassified ($fb_unc)" \
    || no "(5c) tier_unclassified=$fb_unc does not account for the untiered tail (expected $(( ( 300 - fb_files ) * 2 )))"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (6) disclosed bail-out — the BYTE budget (E5's giant-file ceiling) ==="
# ═══════════════════════════════════════════════════════════════════════════
BB="$TMP/bytebudget"; mkdir -p "$BB"
python3 - "$BB" <<'PY'
import sys, os
d = sys.argv[1]
# 16 files x ~1 MB of real C — big enough to pass any sane byte budget, few enough to stay under the
# file budget, so the two bail-outs are distinguishable by the value of tier_budget=.
body = "".join( "int giantFn_%05d( int a ) { return a * %d; }\n" % ( i, i ) for i in range( 22000 ) )
for i in range( 16 ):
    with open( os.path.join( d, "big%02d.c" % i ), "w" ) as fh:
        fh.write( "// GIANTTOKEN_heavy in a comment\n" )
        fh.write( body )
        fh.write( "int GIANTTOKEN_heavy_%02d( void ) { return 0; }\n" % i )
PY
BB_OUT="$( "$BIN" "$BB" --no-cache --grep=GIANTTOKEN_heavy 2>/dev/null )"
bb_budget="$( attr tier_budget "$BB_OUT" )"
bb_files="$( attr tier_parsed "$BB_OUT" )"
bb_comment="$( attr suppressed_comment "$BB_OUT" )"
[ -n "$bb_comment" ] && [ "$bb_comment" = "$bb_files" ] \
    && ok "(6b) exactly the tiered prefix's comment rows were suppressed under the byte budget" \
    || no "(6b) byte-budget arithmetic is off: suppressed_comment=$bb_comment tier_parsed=$bb_files"
if [ "$bb_budget" = "bytes" ] && [ -n "$bb_files" ] && [ "$bb_files" -lt 16 ]; then
    ok "(6) the byte budget trips before the file budget and is disclosed ($bb_files/16 files tiered)"
else
    no "(6) expected tier_budget=bytes with tier_parsed<16, got budget=$bb_budget files=$bb_files"
    printf '%s\n' "$BB_OUT" | grep -o '<grep [^>]*>'
fi

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (7) complete= is withheld from a tier-filtered listing ==="
# ═══════════════════════════════════════════════════════════════════════════
printf '%s' "$D_OUT" | grep -q 'complete="1"' \
    && no "(7) a listing that suppressed rows still claimed complete= — a false completeness claim" \
    || ok "(7) complete= withheld while rows are suppressed"
printf '%s' "$A_OUT" | grep -q 'complete="1"' \
    && ok "(7b) the same corpus under --grep-in=any DOES claim complete= (the claim still works)" \
    || no "(7b) --grep-in=any lost the completeness claim — the withholding is too broad"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (8) the legend defines the tier vocabulary exactly when it appears ==="
# ═══════════════════════════════════════════════════════════════════════════
D_LEGEND="$( printf '%s' "$D_OUT" | grep -o '<!--.*-->' | head -1 )"
A_LEGEND="$( printf '%s' "$A_OUT" | grep -o '<!--.*-->' | head -1 )"
printf '%s' "$D_LEGEND" | grep -qi 'suppressed_comment' \
    && ok "(8) the suppressing answer defines its own tier attributes in-band" \
    || no "(8) rows were suppressed and the legend never said what suppressed_comment means"
printf '%s' "$A_LEGEND" | grep -qi 'suppressed_comment' \
    && no "(8b) an untiered answer still pays for tier prose it can never emit" \
    || ok "(8b) an untiered answer pays no bytes for tier prose"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (9) MCP parity — the grep verb suppresses the same rows ==="
# ═══════════════════════════════════════════════════════════════════════════
MCP_OUT="$( printf '%s\n%s\n%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"grep","arguments":{"path":"'"$SB"'","pattern":"TIERTOKEN_frob"}}}' \
    | "$BIN" "$SB" --mcp --no-cache 2>/dev/null )"
# The JSON payload carries no matched TEXT (file/line/in only), so parity is asserted on the COUNTERS
# and the served row count — which is the fact that would diverge if the two surfaces filtered differently.
jkey(){ printf '%s' "$2" | grep -oE "\\\\\"$1\\\\\":[0-9]+" | head -1 | grep -oE '[0-9]+$'; }
mcpTotal="$( jkey total "$MCP_OUT" )"
mcpComment="$( jkey suppressed_comment "$MCP_OUT" )"
mcpString="$( jkey suppressed_string "$MCP_OUT" )"
# -n on the counters as well as equality: two surfaces that BOTH emit nothing are trivially "in parity",
# which would let this arm pass on a binary with no tier axis at all.
if [ -n "$mcpComment" ] && [ -n "$mcpString" ] && [ "$mcpTotal" = "$d_hits" ] && [ "$mcpComment" = "$d_comment" ] && [ "$mcpString" = "$d_string" ]; then
    ok "(9) the MCP grep verb serves the same rows and the same counters as the CLI verb"
else
    no "(9) MCP grep diverged from the CLI verb: total=$mcpTotal/$d_hits comment=$mcpComment/$d_comment string=$mcpString/$d_string"
    printf '%s\n' "$MCP_OUT" | tail -1 | cut -c1-400
fi

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (10) determinism + well-formed XML on every tiered surface ==="
# ═══════════════════════════════════════════════════════════════════════════
for q in TIERTOKEN_frob TIERTOKEN_prose TIERTOKEN_md; do
    r1="$( "$BIN" "$SB" --no-cache --grep="$q" 2>/dev/null )"
    r2="$( "$BIN" "$SB" --no-cache --grep="$q" 2>/dev/null )"
    [ "$r1" = "$r2" ] && ok "(10) --grep=$q is byte-identical across runs" || no "(10) --grep=$q is nondeterministic"
    if command -v xmllint >/dev/null 2>&1; then
        printf '%s' "$r1" | xmllint --noout - 2>/dev/null && ok "(10b) --grep=$q is well-formed XML" || no "(10b) --grep=$q is not well-formed XML"
    fi
done

echo
[ "$fail" = 0 ] && { echo "greptiercheck: PASS"; exit 0; } || { echo "greptiercheck: FAIL"; exit 1; }
