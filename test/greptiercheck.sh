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
#   (3) F4 FALLBACK (code, else EVERYTHING ELSE): a literal that exists ONLY in comments is still
#       answered — with tier="comment", never an honest-looking empty.
#  (3c/3d) THE COLLAPSED LADDER (wave-3 verifier P4-B): below code there is no ranking — comment and
#       string are served TOGETHER as tier="comment+string". The ranked ladder it replaces inverted the
#       flagship answer: one `#` mention of an error message in a gate script outranked the string
#       literal that emits it. (3c) is the synthetic; (3d) is the verifier's own live repro, guarded by a
#       --grep-in=any liveness precondition so a moved anchor reds instead of passing vacuously.
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
echo "=== (3c) the COLLAPSED ladder — below code, comment and string serve TOGETHER ==="
# ═══════════════════════════════════════════════════════════════════════════
# Wave-3 verifier P4-B. The synthetic of arm (3d)'s live repro: an error message EMITTED as a string
# literal, and MENTIONED once in a gate script's `#` comment. Under the pre-fix ranked ladder
# (code > comment > string) that single comment outranked the emit site and buried it behind
# suppressed_string= — "tightest span type" and "most likely to be the answer" come apart exactly here.
cat >"$SB/src/ladder.c" <<'EOF'
int ladderHost( void )
{
    return reportFailure( "TIERTOKEN_ladder went wrong" );
}
EOF
cat >"$SB/src/laddercheck.sh" <<'EOF'
# check 9: a TIERTOKEN_ladder line must REJECT the whole file loudly
echo checking
EOF
L_OUT="$( "$BIN" "$SB" --no-cache --grep=TIERTOKEN_ladder 2>/dev/null )"
l_hits="$( attr hits "$L_OUT" )"
l_tier="$( attr tier "$L_OUT" )"
l_sup_c="$( attr suppressed_comment "$L_OUT" )"
l_sup_s="$( attr suppressed_string "$L_OUT" )"
if [ "$l_hits" = "2" ] && [ "$l_tier" = "comment+string" ] && [ -z "$l_sup_c" ] && [ -z "$l_sup_s" ]; then
    ok "(3c) an empty code tier serves comment AND string together, disclosed as tier=comment+string"
else
    no "(3c) expected hits=2 tier=comment+string with nothing suppressed, got hits=$l_hits tier=$l_tier suppressed_comment=$l_sup_c suppressed_string=$l_sup_s"
    printf '%s\n' "$L_OUT" | grep -o '<grep [^>]*>'
fi
if printf '%s' "$L_OUT" | grep -q 'ladder\.c' && printf '%s' "$L_OUT" | grep -q 'laddercheck\.sh'; then
    ok "(3c-b) BOTH the emit site and the gate-script mention are served"
else
    no "(3c-b) the collapsed tier dropped one of the two files — the P4-B inversion is back"
fi

# ── (3d) the verifier's OWN live repro, with a liveness precondition so it can never go vacuously green ──
# --grep-in=any establishes that both anchors still exist before the default view is judged; if the live
# text moves, this arm goes RED asking to be re-anchored rather than silently passing on an absent fixture.
#
# --exclude=docs (2026-09-04): docs/COMMANDS.md is generated FROM the capture and now quotes this very
# error message twice. Markdown has a grammar here, so those quotes classify as CODE tier, the code tier
# stops being empty, and the collapsed ladder correctly serves them and suppresses BOTH of P4-B's anchors
# — the arm went red on a corpus fact, not on the inversion it exists to catch. Excluding the generated
# doc tree restores the two-population corpus the arm is about (a string literal in src/ and a `#` comment
# in test/) without weakening it: the liveness precondition below still runs on the SAME excluded corpus,
# so an anchor that moves still reds.
V_ANY="$( "$BIN" "$ROOT" --no-cache --exclude=docs --grep="malformed rules line" --grep-in=any --limit=200 2>/dev/null )"
if printf '%s' "$V_ANY" | grep -q 'src/arch\.h' && printf '%s' "$V_ANY" | grep -q 'test/archcheck\.sh'; then
    V_DEF="$( "$BIN" "$ROOT" --no-cache --exclude=docs --grep="malformed rules line" --limit=200 2>/dev/null )"
    if printf '%s' "$V_DEF" | grep -q 'src/arch\.h' && printf '%s' "$V_DEF" | grep -q 'test/archcheck\.sh'; then
        ok "(3d) live repro: a pasted error message serves its EMIT SITE (src/arch.h) as well as the gate-script comment"
    else
        no "(3d) live repro: the default answer still buries one of the two — the P4-B ladder inversion is back"
        printf '%s\n' "$V_DEF" | grep -o '<grep [^>]*>'
    fi
else
    no "(3d) the live anchor moved: --grep-in=any no longer finds \"malformed rules line\" in BOTH src/arch.h and test/archcheck.sh — re-anchor this arm"
fi

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
# The EXACT constant, not `< 300` (wave-3 verifier P2-1): rebuilt with kGrepTierFileBudget 128 -> 12 the
# gate stayed ALL GREEN while the feature went ~90% inert on the real tree (tier_parsed="12"
# tier_unclassified="231" against 17 fully-tiered hit files at 128). A loose bound let the budget drop ~10x
# — a typo, or a well-meaning "let us be cheaper" edit — without turning anything red. This corpus has 300
# hit files, so the prefix is budget-limited and tier_parsed IS kGrepTierFileBudget, read back out.
if [ "$fb_budget" = "files" ] && [ "$fb_files" = "128" ]; then
    ok "(5) the file budget trips, is disclosed, and tier_parsed pins kGrepTierFileBudget exactly (128/300)"
else
    no "(5) expected tier_budget=files with tier_parsed=128 (kGrepTierFileBudget), got budget=$fb_budget files=$fb_files — if the constant moved DELIBERATELY, re-pin this arm in the same commit"
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
# The exact parsed count, not `< 16` (P2-1, the byte-budget half): this corpus is a FROZEN generator — 16
# files of identical construction — so how many fit under kGrepTierByteBudget is a pure function of the
# constant. `< 16` let the budget fall ~7x (to ~1.1 MB) with every arm green. 7 is the measured admitted
# prefix at 8 MB; if the constant moves deliberately, re-pin this number in the same commit.
if [ "$bb_budget" = "bytes" ] && [ "$bb_files" = "7" ]; then
    ok "(6) the byte budget trips before the file budget and is disclosed, tier_parsed pinned at 7/16"
else
    no "(6) expected tier_budget=bytes with tier_parsed=7 (the prefix kGrepTierByteBudget admits), got budget=$bb_budget files=$bb_files"
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

# ── (9b/9c) the BATCH sub-query's own hatch and its own refusal (wave-3 verifier P3-4/P6-1) ─────────────
# R-H's stated reason for putting `in` on the live MCP verb — an MCP-only agent that reads
# suppressed_comment= has no CLI to re-ask from — applies verbatim to `batch`, and was not applied there:
# the batch arm took the DEFAULTED GrepIn::Code and read no `in` field at all, so the one surface with no
# fallback was the one left closed. (The api-surface ack claimed both callers were updated; one was.)
mcpcall(){ printf '%s\n%s\n%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    "$1" | "$BIN" "$SB" --mcp --no-cache 2>/dev/null | tail -1; }

B_ANY="$( mcpcall '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"batch","arguments":{"path":"'"$SB"'","queries":[{"verb":"grep","pattern":"TIERTOKEN_frob","in":"any"}]}}}' )"
B_DEF="$( mcpcall '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"batch","arguments":{"path":"'"$SB"'","queries":[{"verb":"grep","pattern":"TIERTOKEN_frob"}]}}}' )"
b_any="$( jkey total "$B_ANY" )"
b_def="$( jkey total "$B_DEF" )"
# Both directions, so the arm cannot pass on a surface that ignores `in` (which would make the two equal)
# NOR on one that always un-tiers (which would make both 5).
if [ "$b_any" = "$a_hits" ] && [ "$b_def" = "$d_hits" ]; then
    ok "(9b) the batch grep sub-query honours in=\"any\" ($b_any) and still tiers by default ($b_def)"
else
    no "(9b) batch grep in= is not wired: in=any gave total=$b_any (expected $a_hits), default gave total=$b_def (expected $d_hits)"
    printf '%s\n' "$B_ANY" | cut -c1-400
fi

B_BAD="$( mcpcall '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"batch","arguments":{"path":"'"$SB"'","queries":[{"verb":"grep","pattern":"TIERTOKEN_frob","in":"Any"}]}}}' )"
if printf '%s' "$B_BAD" | grep -q 'invalid value for field: in'; then
    ok "(9c) the batch grep sub-query REFUSES an unknown in= value instead of silently tiering"
else
    no "(9c) batch grep swallowed in=\"Any\" — a closed value set that defaults on a typo hides the rows the caller asked for"
    printf '%s\n' "$B_BAD" | cut -c1-400
fi

# ── (9d) the LIVE grep verb refuses the same typo, on the same words (wave-3 verifier P6-2) ─────────────
# `in:"Any"` / `in:"all"` / `in:"comments"` used to read as the default and silently return the TIERED
# answer. The CLI twin has always refused, and its own comment says why: a typo would read as "code" and
# quietly suppress the very rows the user asked to see. Both MCP dialects now read the value through the
# same reader, so this arm and (9c) assert the SAME sentence — two dialects cannot drift on a closed set.
V_BAD="$( mcpcall '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"grep","arguments":{"path":"'"$SB"'","pattern":"TIERTOKEN_frob","in":"Any"}}}' )"
V_OK="$( mcpcall '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"grep","arguments":{"path":"'"$SB"'","pattern":"TIERTOKEN_frob","in":"code"}}}' )"
if printf '%s' "$V_BAD" | grep -q 'invalid value for field: in'; then
    ok "(9d) the live MCP grep verb REFUSES an unknown in= value, as the CLI twin does"
else
    no "(9d) the live MCP grep verb swallowed in=\"Any\" and answered — the closed set is enforced on one dialect only"
    printf '%s\n' "$V_BAD" | cut -c1-400
fi
# The refusal must not be over-broad: an EXPLICIT in="code" is a legal spelling of the default and answers.
[ "$( jkey total "$V_OK" )" = "$d_hits" ] \
    && ok "(9d-b) an explicit in=\"code\" still answers (the refusal is on unknown values, not on presence)" \
    || no "(9d-b) in=\"code\" was refused or changed the answer — the value check is too broad"

# ═══════════════════════════════════════════════════════════════════════════
echo "=== (11) M17 — a class label decided under a budget says so ==="
# ═══════════════════════════════════════════════════════════════════════════
# M17 (capture-audit 2026-09-04, lens1 F4). The served tier is chosen over the CLASSIFIED hits only —
# correctly, since an unclassified hit cannot vote for a tier nobody proved it belongs to. But the LABEL
# was then stated as a fact about the whole answer: live, --grep=deterministic said tier="comment+string",
# whose legend reading is "no hit is code", decided over 128 classified files while 892 of 1,357 hits were
# never classified — and the served rows included test/verify_radix.cpp's `deterministicShuffle`
# DEFINITION plus three of its call sites. Four code-tier rows under a label asserting there are none.
#
# The rule: whenever the label was decided over a partial classification, it carries tier_partial="1".
# Narrow on purpose — a complete classification that lands on comment is a proven fact and pays nothing.
PB="$TMP/partialbudget"; mkdir -p "$PB"
python3 - "$PB" <<'PARTIALPY'
import sys, os
d = sys.argv[1]
# 300 hit files so the file budget (128) stops the classification well short, every classified one
# carrying a COMMENT-ONLY mention — so the label the classified prefix elects is "comment". The ONE
# code-tier occurrence sits in the LAST file by path order, deep in the unclassified tail: it is served
# (unclassified is never suppressible) under a label that says no hit is code.
for i in range( 300 ):
    with open( os.path.join( d, "f%03d.c" % i ), "w" ) as fh:
        fh.write( "// PARTIALTOKEN_late in a comment\nint partialHost_%03d( void ) { return %d; }\n" % ( i, i ) )
with open( os.path.join( d, "f299.c" ), "a" ) as fh:
    fh.write( "int PARTIALTOKEN_late_fn( void ) { return 0; }\n" )
PARTIALPY
PB_OUT="$( "$BIN" "$PB" --no-cache --grep=PARTIALTOKEN_late --limit=1000 2>/dev/null )"
pb_tier="$( attr tier "$PB_OUT" )"
pb_budget="$( attr tier_budget "$PB_OUT" )"
pb_unc="$( attr tier_unclassified "$PB_OUT" )"
pb_partial="$( attr tier_partial "$PB_OUT" )"
# (11a) the SETUP is live — without this the marker arm below could pass on a fixture that stopped
# reproducing the shape (the (3d) lesson: a fixture that quietly stops exercising the case is worse than
# a red one).
if [ "$pb_tier" = "comment" ] && [ "$pb_budget" = "files" ] && [ -n "$pb_unc" ] && [ "$pb_unc" != "0" ]; then
    ok "(11a) the fixture reproduces M17: tier=comment elected over a budget-truncated classification ($pb_unc hits unclassified)"
else
    no "(11a) the M17 fixture stopped reproducing the shape: tier=$pb_tier tier_budget=$pb_budget tier_unclassified=$pb_unc — re-anchor it"
    printf '%s\n' "$PB_OUT" | grep -o '<grep [^>]*>'
fi
[ "$pb_partial" = "1" ] \
    && ok "(11b) the label decided under a partial classification carries tier_partial=1" \
    || no "(11b) tier=$pb_tier was asserted over $pb_unc unclassified hits with NO partial marker (tier_partial=$pb_partial)"
# (11c) and the code-tier row the label denies exists IS in the served set — which is what makes the
# unqualified label a false claim rather than merely an imprecise one.
printf '%s' "$PB_OUT" | grep -q 'in="PARTIALTOKEN_late_fn"' \
    && ok "(11c) the unclassified CODE-tier definition is served under the comment label (the claim M17 is about)" \
    || no "(11c) the fixture's code-tier definition is not in the answer — the arm cannot show the false claim"
# (11d) NOT blanket noise: a label decided over a COMPLETE classification pays nothing. P_OUT is arm (3)'s
# comments-only answer on the small sandbox, where every hit file was parsed.
if [ "$( attr tier "$P_OUT" )" = "comment" ] && [ -z "$( attr tier_partial "$P_OUT" )" ]; then
    ok "(11d) a fully classified comment label carries no partial marker (the marker is a claim, not decoration)"
else
    no "(11d) tier_partial appeared on a fully classified answer — the condition is too broad"
    printf '%s\n' "$P_OUT" | grep -o '<grep [^>]*>'
fi
# (11e) defined where it is met, and mirrored on the other dialect.
printf '%s' "$PB_OUT" | grep -o '<!--.*-->' | head -1 | grep -qi 'tier_partial' \
    && ok "(11e) the legend defines tier_partial in the answer that emits it" \
    || no "(11e) tier_partial was emitted and the legend never says what it means"
PB_MCP="$( printf '%s\n%s\n%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"grep","arguments":{"path":"'"$PB"'","pattern":"PARTIALTOKEN_late","limit":1000}}}' \
    | "$BIN" "$PB" --mcp --no-cache 2>/dev/null | tail -1 )"
printf '%s' "$PB_MCP" | grep -q 'tier_partial' \
    && ok "(11f) the MCP grep twin carries tier_partial too (one collection, one disclosure)" \
    || { no "(11f) the MCP grep twin dropped tier_partial — the two dialects state different confidence in the same label"; printf '%s\n' "$PB_MCP" | cut -c1-400; }
# (11g) THE PROPERTY, derived from live answers rather than from a fixture: on ANY answer, a tier= label
# and a non-zero tier_unclassified= together imply tier_partial="1", and a label with nothing unclassified
# implies its absence. Runs over the real tree, so a pattern nobody anticipated is still covered.
for q in deterministic "malformed rules line" TIERTOKEN_prose; do
    case "$q" in
        TIERTOKEN_prose) P_CORPUS="$SB" ;;
        *)               P_CORPUS="$ROOT" ;;
    esac
    Q_OUT="$( "$BIN" "$P_CORPUS" --no-cache --grep="$q" 2>/dev/null )"
    q_tier="$( attr tier "$Q_OUT" )"
    q_unc="$( attr tier_unclassified "$Q_OUT" )"
    q_par="$( attr tier_partial "$Q_OUT" )"
    if [ -z "$q_tier" ]; then
        ok "(11g) '$q': serves the code tier — no label to qualify"
    elif [ -n "$q_unc" ] && [ "$q_unc" != "0" ]; then
        [ "$q_par" = "1" ] && ok "(11g) '$q': tier=$q_tier over $q_unc unclassified hits, marked partial" \
                           || no "(11g) '$q': tier=$q_tier asserted over $q_unc unclassified hits with no tier_partial"
    else
        [ -z "$q_par" ] && ok "(11g) '$q': tier=$q_tier decided over a complete classification, unmarked" \
                        || no "(11g) '$q': tier_partial=1 on an answer that classified everything"
    fi
done

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
