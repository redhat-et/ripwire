#!/usr/bin/env bash
# mdsectioncheck.sh — the MARKDOWN SECTION TIER gate (collapse-queue G2/G3, design ratified
# 2026-08-12: "a heading is to a doc what a function is to a file").
#
# What the tier promises, and what each arm below pins:
#   - a heading (ATX 1-6 AND setext ===/---) is a t="sec" SYMBOL whose SPAN runs from the
#     heading to the next same-or-higher heading — so --expand serves the SECTION body, --for
#     ranks the SECTION (not the whole-doc dump), and --recall answers section-granular where
#     sections exist (whole-doc stays the DISCLOSED fallback for heading-less docs);
#   - heading hierarchy is the nesting graph: a section's scope is its parent heading, so the
#     canonical id is path::Parent::Child — identity stays PATH-QUALIFIED (the churn-keying
#     lesson: same heading text across files must never collide);
#   - markdown links are edges: [text](other.md) / [label]: other.md → doc→doc (file node, the
#     wikilink machinery), [text](#anchor) → doc-section→doc-section IN-FILE,
#     [text](other.md#slug) → that file's heading (stem if the heading is absent); `backtick`
#     mentions stay doc→code and now attribute to their ENCLOSING SECTION;
#   - fenced/tilde/indented code, html blocks, YAML front-matter and blockquoted headings are
#     NOT document structure: nothing inside them becomes a symbol, and fenced code is never
#     double-indexed as code (the grammar that owns the language never sees it);
#   - both pollution directions hold: doc sections do not displace a code query's answer, and
#     --recall (docs-only) never emits code file content;
#   - the scanner-bounds guard: tree-sitter-markdown's serialize() memcpys open_blocks with NO
#     bounds check (OOB at ~255 nested blockquotes/list markers — probed 2026-08-12, rc=134
#     under ASan on 300x '>'; silent heap corruption under NDEBUG). Two layers, the yaml
#     posture: a pre-parse depth guard (skip-as-data with a stderr note) plus
#     third_party/patches/markdown/001-serialize-bounds.patch (vendorpatchcheck arm H class
#     "upfront"). The guard fires below the overflow depth, so the patch's live tripwire is
#     the recorded standalone probe + arm H's static audit; the nearlimit fixture keeps the
#     scanner exercised under the asan flavour.
#
# Scope disclosed: .md and .markdown ONLY (docparse's notebook/html/csv extraction keeps its
# own whole-doc path); other formats deferred — the mine says markdown dominates doc traffic.
#
# Usage:
#   test/mdsectioncheck.sh
#   RIPWIRE_BIN=asan/ripwire test/mdsectioncheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.
# Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/mdsectionfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint required for well-formedness assertions"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }

echo "mdsectioncheck: BIN=$BIN  FIX=$FIX"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== presence guards: the fixture really spells what the arms below assert ==="
# ═══════════════════════════════════════════════════════════════════════════
G="$FIX/guide.md"
guard(){ if grep -qF -- "$2" "$1"; then ok "fixture spells $3"; else no "fixture LOST $3 — its arm below would pass by finding nothing"; fi; }
guard "$G" 'zqfrontkey'                    'the front-matter key zqfrontkey'
guard "$G" '# Orientation Guide'           'the H1  # Orientation Guide'
guard "$G" '## Cache Warm Path'            'the H2  ## Cache Warm Path'
guard "$G" '## Closed Heading ##'          'the closed-form H2  ## Closed Heading ##'
guard "$G" 'Deployment Rollout Setext'     'the setext H1 text'
guard "$G" '========================='     'the setext H1 underline'
guard "$G" 'Rollback Plan'                 'the setext H2 text'
guard "$G" '-------------'                 'the setext H2 underline'
guard "$G" '### Deep Appendix'             'the H3  ### Deep Appendix'
guard "$G" '# zqfencephantom'              'the fenced decoy heading'
guard "$G" 'zqFencedPhantomFn'             'the fenced C++ decoy function'
guard "$G" '# zqtildephantom'              'the tilde-fenced decoy heading'
guard "$G" '# zqhtmlphantom'               'the html-block decoy heading'
guard "$G" '# zqindentphantom'             'the indented-code decoy heading'
guard "$G" '> # Quoted Phantom'            'the blockquoted decoy heading'
guard "$G" '(partner.md)'                  'the inline link to partner.md'
guard "$G" '(partner.md#install-steps)'    'the cross-file heading link'
guard "$G" '(alt.markdown#no-such-heading)'  'the cross-file link whose heading is absent'
guard "$G" '(#result-tables)'              'the in-file anchor link'
guard "$G" '[[decoy]]'                     'the wikilink to decoy'
guard "$G" '[zqref]: decoy.md'             'the reference-style link definition'
guard "$G" '`codeIdentFn`'                 'the backtick doc→code mention'
[ "$( grep -l '^# Install Steps' "$FIX/partner.md" "$FIX/decoy.md" | wc -l | tr -d ' ' )" -eq 2 ] \
    && ok "partner.md and decoy.md share the heading  # Install Steps  (the decoy pair exists)" \
    || no "the Install Steps decoy pair is gone"
grep -qE '^#' "$FIX/plainprose.md" && no "plainprose.md grew a heading — the whole-doc fallback arm is dead" \
    || ok "plainprose.md is heading-less (the whole-doc fallback arm has its subject)"
if grep -qF 'zqplainprose' "$FIX/plainprose.md"; then ok "plainprose.md carries zqplainprose"; else no "plainprose.md lost zqplainprose"; fi
# deepquote.md is GENERATED, never committed: a committed 300-deep file would put the guard's stderr
# note into every repo-wide run (xmlwellformed's --owners arm merges stderr and caught exactly that).
DEEPFIX="$TMP/deepfix"
mkdir -p "$DEEPFIX"
python3 -c "open('$DEEPFIX/deepquote.md','w').write('>'*300 + ' three hundred nested blockquote markers on one line\n')"
[ "$( head -c 300 "$DEEPFIX/deepquote.md" | tr -dc '>' | wc -c | tr -d ' ' )" -eq 300 ] \
    && ok "deepquote.md (generated) opens 300 blockquote markers" || no "deepquote.md generation failed"
if grep -q $'\r' "$FIX/crlf.md"; then ok "crlf.md really has CRLF line endings"; else no "crlf.md lost its CR bytes"; fi
if grep -qF 'zqaltextension' "$FIX/alt.markdown"; then ok "alt.markdown carries zqaltextension"; else no "alt.markdown lost zqaltextension"; fi
if grep -qF 'zqCodeAnchorFn' "$FIX/helpers.c"; then ok "helpers.c defines zqCodeAnchorFn"; else no "helpers.c lost zqCodeAnchorFn"; fi
head -1 "$FIX/setext0.md" | grep -qx 'Setext At Byte Zero' \
    && ok "setext0.md opens with setext heading TEXT at byte 0 (the identity-collision shape)" \
    || no "setext0.md no longer opens with its setext heading at byte 0"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== default map: exit/wellformed/deep-quote guard, and the section symbol set ==="
# ═══════════════════════════════════════════════════════════════════════════
MAP="$TMP/map.xml"
$BIN "$FIX" --no-cache >"$MAP" 2>"$TMP/map.err"
RC=$?
if [ "$RC" -eq 0 ]; then ok "default map exits 0"; else no "default map exited $RC: $( head -3 "$TMP/map.err" )"; fi
if xmllint --noout "$MAP" 2>/dev/null; then ok "map passes xmllint --noout"; else no "map is not well-formed XML"; fi

# deep-quote guard, on its own GENERATED corpus: refused BEFORE the parse with a one-line note (the
# yaml posture). The committed fixture dir stays note-free — nearlimit.md (150 deep) parses fine.
$BIN "$DEEPFIX" --no-cache >"$TMP/deep.xml" 2>"$TMP/deep.err"
DEEP_RC=$?
if [ "$DEEP_RC" -eq 0 ]; then ok "deep corpus exits 0"; else no "deep corpus exited $DEEP_RC"; fi
grep -q 'deepquote\.md.*nesting' "$TMP/deep.err" \
    && ok "deepquote.md refused with a nesting note (scanner OOB depth never reaches the parser)" \
    || no "deepquote.md was NOT refused — the markdown depth guard is missing (scanner serialize() OOB class)"
grep -q 'nearlimit\.md' "$TMP/map.err" \
    && no "nearlimit.md (150 deep) drew a stderr note — the guard is overbroad" \
    || ok "nearlimit.md (150 deep) parses without a note (guard is not overbroad)"
[ -s "$TMP/map.err" ] \
    && no "unexpected stderr on the committed fixture: $( head -2 "$TMP/map.err" )" \
    || ok "clean stderr on the committed fixture (no note pollutes repo-wide runs)"

# ── #157 FLIPPED (was KNOWN GAP, prompts/help-wanted/nesting-refusals-visible.md): the markdown twin of yamllangcheck's block ──
# #157 closed the gap this block used to pin as four passing-on-the-bug KNOWN GAP arms: refuseNesting
# (ingest_prewarm.h) now itemizes the markdown guard's refusals into --skipped, forgetNestRefusalsForCache
# forgets the record so a warm run re-refuses and re-rows it, and astQueryGrouped's worker checks
# IngestResult::nestRefusedFile before parsing so --match can no longer return a hit from a refused file.
# NOTE on stderr: like yamllangcheck's twin, the warm run's stderr note REAPPEARS every warm run under this
# fix (forgetNestRefusalsForCache's documented cost, matching Kotlin's own pre-existing behaviour) — that is
# not asserted here; CONTRIBUTING says never assert DISCLOSE's stderr text, only the --skipped row. Its own
# generated corpus, never the committed fixture (the committed dir must stay note-free, see above).
KGM="$TMP/kgmd"; mkdir -p "$KGM"
cp "$DEEPFIX/deepquote.md" "$KGM/deepquote.md"
# The sibling carries one shallow block quote: the --match='(block_quote)' arm below needs a positive control,
# or a walk that skipped EVERY file would pass it too (CodeRabbit on #331).
printf '# Kg Sibling Heading\n\nzqkgsibling prose\n\n> zqkgsibling quote\n' > "$KGM/sibling.md"
$BIN "$KGM" --cache="$TMP/kgmd.cache" >"$TMP/kgm_cold.xml" 2>"$TMP/kgm_cold.err"; KGM_COLD_RC=$?
$BIN "$KGM" --cache="$TMP/kgmd.cache" >"$TMP/kgm_warm.xml" 2>"$TMP/kgm_warm.err"; KGM_WARM_RC=$?
KGM_LIVE=0
if [ "$KGM_COLD_RC" -eq 0 ] && [ "$KGM_WARM_RC" -eq 0 ] && grep -q 'deepquote\.md.*nesting' "$TMP/kgm_cold.err" \
   && grep -qF 'n="Kg Sibling Heading"' "$TMP/kgm_warm.xml" && cmp -s "$TMP/kgm_cold.xml" "$TMP/kgm_warm.xml"; then
    ok "(kg-md) presence: the cold run refuses deepquote.md on stderr; the warm run serves the same map from the cache, sibling indexed"
    KGM_LIVE=1
else
    no "(kg-md) presence: expected rc=0 twice, a cold refusal note for deepquote.md and a warm map identical to the cold one (cold rc=$KGM_COLD_RC, warm rc=$KGM_WARM_RC) — the arms below would be vacuous: $( head -2 "$TMP/kgm_cold.err" )"
fi
if [ "$KGM_LIVE" -eq 1 ]; then
    for mode in cold warm; do
        if [ "$mode" = cold ]; then
            $BIN "$KGM" --no-cache --skipped >"$TMP/kgm_sk_$mode.xml" 2>/dev/null; SK_RC=$?
        else
            $BIN "$KGM" --cache="$TMP/kgmd.cache" --skipped >"$TMP/kgm_sk_$mode.xml" 2>/dev/null; SK_RC=$?
        fi
        DQ_BYTES="$( wc -c < "$KGM/deepquote.md" | tr -d ' ' )"
        if [ "$SK_RC" -ne 0 ] || ! grep -q '<skipped indexed="2"' "$TMP/kgm_sk_$mode.xml"; then
            no "(kg-md) $mode --skipped: exit $SK_RC or no <skipped indexed=\"2\"> report — the arm cannot observe the fix"
        elif ! grep -qE "<f p=\"[^\"]*deepquote\\.md\" why=\"nest-refused\" bytes=\"$DQ_BYTES\" ext=\"\\.md\"/>" "$TMP/kgm_sk_$mode.xml"; then
            no "#157 REGRESSED: $mode --skipped has no exact nest-refused row for deepquote.md (why=/bytes=$DQ_BYTES/ext=.md): $( grep -o '<f p="[^"]*deepquote[^/]*/>' "$TMP/kgm_sk_$mode.xml" )"
        elif ! grep -q 'nest_refused="1"' "$TMP/kgm_sk_$mode.xml"; then
            no "#157 REGRESSED: $mode --skipped header is missing nest_refused=\"1\": $( grep -o '<skipped [^>]*>' "$TMP/kgm_sk_$mode.xml" )"
        elif ! grep -qF 'nest_refused= counts indexed files a pre-parse nesting guard' "$TMP/kgm_sk_$mode.xml"; then
            no "#157 REGRESSED: $mode --skipped legend carries no nest_refused= clause"
        else
            ok "#157 FIXED: $mode --skipped rows deepquote.md (why=\"nest-refused\" bytes=\"$DQ_BYTES\" ext=\".md\"), header nest_refused=\"1\", legend present"
        fi
        grep -qE '<f p="[^"]*sibling\.md" why="nest-refused"' "$TMP/kgm_sk_$mode.xml" \
            && no "#157 REGRESSED: $mode --skipped rows sibling.md as nest-refused too — the guard is refusing the whole tree, not the one hostile file"
    done
fi
$BIN "$KGM" --no-cache --match='(block_quote)' >"$TMP/kgm_match.xml" 2>"$TMP/kgm_match.err"; KGM_M_RC=$?
if [ "$KGM_M_RC" -ne 0 ]; then
    no "(kg-md) --match over the refused deepquote.md exited $KGM_M_RC — a parse the guard exists to prevent went wrong (the vendored scanner clamp is --match's only layer): $( head -2 "$TMP/kgm_match.err" )"
elif ! grep -q 'deepquote\.md.*nesting' "$TMP/kgm_match.err"; then
    no "(kg-md) --match: the same run's ingest did not refuse deepquote.md — the arm cannot show the two paths agree"
elif grep -q '<m p="deepquote\.md:' "$TMP/kgm_match.xml"; then
    no "#157 REGRESSED: --match returns hits INSIDE deepquote.md in the same run whose ingest refused it — the bypass is back"
elif ! grep -q 'nest_refused="1"' "$TMP/kgm_match.xml"; then
    no "#157 REGRESSED: --match's answer does not disclose nest_refused=\"1\" over a tree holding one refused file: $( grep -o '<match [^>]*>' "$TMP/kgm_match.xml" )"
elif ! grep -q '<m p="sibling\.md:' "$TMP/kgm_match.xml"; then
    no "(kg-md) --match: no hit in sibling.md, the positive control — a walk that skipped every file would pass the arms above: $( grep -o '<match [^>]*>' "$TMP/kgm_match.xml" )"
else
    ok "#157 FIXED: --match returns zero hits inside the refused deepquote.md, still hits sibling.md, and discloses nest_refused=\"1\""
fi

sec(){ # sec NAME — the map carries a t="sec" symbol with exactly this name
    if grep -qF "<s t=\"sec\" n=\"$1\"" "$MAP"; then ok "section symbol present: $1"; else no "section symbol MISSING: $1"; fi
}
sec "Orientation Guide"
sec "Cache Warm Path"
sec "Closed Heading"
sec "Result Tables"
sec "Deep Appendix"
sec "Near Limit Doc"
sec "CRLF Heading"
sec "Alt Extension Doc"
echo "--- setext headings are sections too (=== is H1, --- is H2) ---"
sec "Deployment Rollout Setext"
sec "Rollback Plan"
# the byte-0 identity collision (caught 2026-08-12): a setext heading whose paragraph OPENS the file
# puts its name at byte 0, where the whole-file node's dedup identity used to sit — the two then tied
# on every sort key and std::sort's instability flipped the unique() survivor with worker arrival
# order (bench scoreboards flapping in --merge-scout). BOTH symbols must exist, every run.
sec "Setext At Byte Zero"
sec "setext0"
[ "$( grep -oF '<s t="sec" n="Install Steps"' "$MAP" | wc -l | tr -d ' ' )" -eq 2 ] \
    && ok "Install Steps exists TWICE — one per file, identity path-qualified, never merged" \
    || no "Install Steps did not survive as two per-file symbols"

echo "--- nothing inside fences / html / indented code / front-matter / blockquotes is structure ---"
absent(){ # absent TOKEN WHY
    if grep -qF "$1" "$MAP"; then no "map leaked $2 ($1)"; else ok "no leak: $2"; fi
}
absent 'n="zqfencephantom'   'a heading from inside a ``` fence'
absent 'n="zqtildephantom'   'a heading from inside a ~~~ fence'
absent 'n="zqhtmlphantom'    'a heading from inside an html block'
absent 'n="zqindentphantom'  'a heading from inside an indented code block'
absent 'n="zqFencedPhantomFn' 'a code SYMBOL from inside a fenced block (double-index guard)'
absent 'n="zqfrontkey'       'a front-matter key as a symbol'
absent 'n="Quoted Phantom'   'a blockquoted heading as a symbol'
absent 'n=""'                'an empty-named symbol (the bare # heading)'
grep -q 'n="Closed Heading #' "$MAP" && no "closing ##s survived into a heading name" \
    || ok "closing ##s stripped from the heading name"
grep -q $'n="CRLF Heading\r' "$MAP" && no "a CR byte survived into a CRLF heading name" \
    || ok "CRLF heading name carries no CR byte"

echo "--- hierarchy: a section's scope is its parent heading (canonical id path::Parent::Child) ---"
# row 6 (2026-09-12): the row prints n= then sc= (the scope CHAIN, e.g. sc="Deployment Rollout Setext::Rollback Plan");
# the canonical id composes as <f p=>::sc::n, so "scoped under X" is "sc= ends with X" on the row named n=.
grep -qE 'n="Cache Warm Path" sc="([^"]*::)?Orientation Guide"' "$MAP" \
    && ok "Cache Warm Path is scoped under Orientation Guide" \
    || no "Cache Warm Path carries no Orientation Guide scope (heading hierarchy missing)"
grep -qE 'n="Rollback Plan" sc="([^"]*::)?Deployment Rollout Setext"' "$MAP" \
    && ok "Rollback Plan (setext H2) is scoped under Deployment Rollout Setext (setext H1)" \
    || no "setext hierarchy missing (Rollback Plan not scoped under the setext H1)"
grep -qE 'n="Deep Appendix" sc="([^"]*::)?Rollback Plan"' "$MAP" \
    && ok "Deep Appendix (H3) is scoped under Rollback Plan (the nearest shallower heading)" \
    || no "Deep Appendix is not scoped under Rollback Plan"

echo "--- links are edges: doc→doc via file node, doc-section→doc-section in-file ---"
python3 - "$MAP" <<'PYEOF' >"$TMP/edges.txt"
import sys, re
xml = open(sys.argv[1], encoding='utf-8').read()
for m in re.finditer(r'<s t="sec" n="([^"]*)"[^>]*>(.*?)</s>', xml, re.S):
    src = m.group(1)
    for c in re.finditer(r'<c n="([^"]*)"', m.group(2)):
        print(f"{src} -> {c.group(1)}")
PYEOF
edge(){ if grep -qF "$1 -> $2" "$TMP/edges.txt"; then ok "edge: $1 -> $2  ($3)"; else no "edge MISSING: $1 -> $2  ($3)"; fi; }
edge "Cache Warm Path" "partner"        'inline [text](partner.md) link, attributed to its section'
edge "Cache Warm Path" "Install Steps"  'cross-file [text](partner.md#install-steps) — that file'\''s heading'
edge "Cache Warm Path" "alt"           'cross-file [text](alt.markdown#no-such-heading) falls back to the file stem'
edge "Cache Warm Path" "Result Tables"  'in-file [text](#result-tables) anchor — doc-section→doc-section'
edge "Result Tables"   "decoy"          '[[wikilink]], attributed to its section'
edge "Deep Appendix"   "decoy"          'reference-style [zqref]: decoy.md definition'

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== --for ranks the SECTION, and its signature is the heading, not the doc dump ==="
# ═══════════════════════════════════════════════════════════════════════════
# the query is the BODY-ONLY marker token — it appears in no heading NAME, so this row can
# only surface if section bodies are lexically indexed (pre-tier, heading spans carried no body
# and a name-match could fake this arm green).
$BIN "$FIX" --no-cache --for="zqcachewarmbody" >"$TMP/for.xml" 2>/dev/null
grep -qF 'n="Cache Warm Path"' "$TMP/for.xml" \
    && ok "--for on a section-body token returns THAT section's row" \
    || no "--for does not surface the section for its own body token (whole-doc-dump residual)"
if python3 - "$TMP/for.xml" <<'PYEOF'; then ok "the section row's sig is the heading line (never the section body)"; else no "the section row's sig leaks the section body"; fi
import sys, re
xml = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'<d[^>]*n="Cache Warm Path"[^>]*>(.*?)</d>', xml, re.S)
sys.exit(0 if m and 'Cache Warm Path' in m.group(1) and 'zqcachewarmbody' not in m.group(1) else 1)
PYEOF

echo "--- code-query pollution: a name-exact code query is answered by the code symbol first ---"
$BIN "$FIX" --no-cache --for="zqCodeAnchorFn" >"$TMP/forcode.xml" 2>/dev/null
if python3 - "$TMP/forcode.xml" <<'PYEOF'; then ok "--for=zqCodeAnchorFn: first row is the C function, not a doc section"; else no "--for=zqCodeAnchorFn: a doc section displaced the code answer"; fi
import sys, re
xml = open(sys.argv[1], encoding='utf-8').read()
# \bn= would still bite on in=/churn= tails after greedy backtracking; anchor on the attribute
# BOUNDARY (a preceding space) and take the FIRST <d row's n= non-greedily.
m = re.search(r'<d (?:[^>]*? )?n="([^"]*)"', xml)
sys.exit(0 if m and m.group(1) == 'zqCodeAnchorFn' else 1)
PYEOF

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== --expand serves the SECTION span (heading → next same-or-higher heading) ==="
# ═══════════════════════════════════════════════════════════════════════════
xp(){ # xp SELECTOR OUTFILE
    $BIN "$FIX" --no-cache --expand="$1" --top-k=0 >"$2" 2>/dev/null
}
has(){ if grep -qF "$2" "$1"; then ok "$3"; else no "$4"; fi; }
hasnot(){ grep -qF "$2" "$1" && no "$4" || ok "$3"; }

xp "guide.md:Cache Warm Path" "$TMP/x1"
has    "$TMP/x1" 'zqcachewarmbody'     "Cache Warm Path body contains its own prose" "Cache Warm Path expand is missing its own body (span is still the bare heading line)"
hasnot "$TMP/x1" 'zqorientbody'        "…and not the parent H1's prose" "Cache Warm Path expand leaked the PARENT section's prose"
hasnot "$TMP/x1" 'zqresulttables'      "…and stops before the next H2" "Cache Warm Path expand ran past the next same-level heading"

xp "guide.md:Orientation Guide" "$TMP/x2"
has    "$TMP/x2" 'zqorientbody'        "Orientation Guide (H1) contains its own prose" "Orientation Guide expand is missing its own body"
has    "$TMP/x2" 'zqcachewarmbody'     "…and its child H2's prose (children are inside the span)" "Orientation Guide expand is missing its child section"
hasnot "$TMP/x2" 'zqsetextbody1'       "…and CLOSES at the setext H1 (span rule crosses heading forms)" "Orientation Guide expand ran past the setext H1 — the span rule ignores setext levels"

xp "guide.md:Deployment Rollout Setext" "$TMP/x3"
has    "$TMP/x3" 'zqsetextbody1'       "setext H1 section contains its own prose" "setext H1 expand is missing its own body"
has    "$TMP/x3" 'zqsetextbody2'       "…and its nested setext H2's prose" "setext H1 expand is missing its nested H2"
hasnot "$TMP/x3" 'zqresulttables'      "…and nothing from before the heading" "setext H1 expand leaked earlier content"

xp "guide.md:Rollback Plan" "$TMP/x4"
has    "$TMP/x4" 'zqsetextbody2'       "setext H2 section contains its own prose" "setext H2 expand is missing its own body"
hasnot "$TMP/x4" 'zqsetextbody1'       "…and not its parent's prose" "setext H2 expand leaked the parent's prose"

echo "--- path-qualified decoy separation: same heading text, two files, two bodies ---"
xp "decoy.md:Install Steps" "$TMP/x5"
has    "$TMP/x5" 'zqdecoyinstall'      "decoy.md:Install Steps serves the DECOY body" "decoy.md:Install Steps is missing its own body"
hasnot "$TMP/x5" 'zqpartnerinstall'    "…and never the partner's" "decoy.md:Install Steps leaked partner.md's body — identity collided across files"
xp "partner.md:Install Steps" "$TMP/x6"
has    "$TMP/x6" 'zqpartnerinstall'    "partner.md:Install Steps serves the PARTNER body" "partner.md:Install Steps is missing its own body"
hasnot "$TMP/x6" 'zqdecoyinstall'      "…and never the decoy's" "partner.md:Install Steps leaked decoy.md's body"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== --recall is section-granular where sections exist; whole-doc where none do ==="
# ═══════════════════════════════════════════════════════════════════════════
$BIN "$FIX" --no-cache --recall="zqcachewarmbody" >"$TMP/r1" 2>/dev/null
has    "$TMP/r1" 'zqcachewarmbody'     "recall serves the matching section's prose" "recall lost the matching prose entirely"
hasnot "$TMP/r1" 'zqorientbody'        "…without the sibling/parent prose (section-granular)" "recall still dumps the WHOLE doc for a doc that has sections"
hasnot "$TMP/r1" 'zqdeepappendix'      "…and without the far tail of the doc" "recall still reaches the far tail of the doc"
grep -qF '[sections:' "$TMP/r1" \
    && ok "the section cut is DISCLOSED in the bundle ([sections: marker)" \
    || no "recall went section-granular silently (no [sections: disclosure marker)"

$BIN "$FIX" --no-cache --recall="zqplainprose" >"$TMP/r2" 2>/dev/null
has    "$TMP/r2" 'zqplainprose'        "a heading-less doc is still recalled" "the heading-less doc vanished from recall"
if grep -qF 'plainprose.md' "$TMP/r2"; then ok "…as its whole doc (the disclosed fallback)"; else no "plainprose.md separator missing"; fi

echo "--- doc-query pollution: --recall (docs-only) never emits code content ---"
$BIN "$FIX" --no-cache --recall="zqcachewarmbody cache warm compute" >"$TMP/r3" 2>/dev/null
hasnot "$TMP/r3" 'zqCodeAnchorFn( int warmCount )' "no code body in a recall bundle" "recall emitted helpers.c content — the docs-only corpus leaked code"
hasnot "$TMP/r3" 'helpers.c  (relevance' "no code file separator in a recall bundle" "recall ranked a code FILE as a document"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== doc→code mention machinery still reaches the section tier ==="
# ═══════════════════════════════════════════════════════════════════════════
$BIN "$FIX" --no-cache --mentions=codeIdentFn >"$TMP/men.xml" 2>/dev/null
grep -qF 'guide.md' "$TMP/men.xml" && ok "--mentions=codeIdentFn names guide.md (backtick doc→code edge)" \
    || no "--mentions=codeIdentFn lost the guide.md mention"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== cross-file [text](path#slug) binds the EXACT (file, slug) heading, never a bare name ==="
# ═══════════════════════════════════════════════════════════════════════════
# Each arm reads --callees of ONE linking section and compares the rows' n=@p= (file, no line). The
# fixture is built so a name-only resolver lands on the wrong target: the linking file has its own
# `## Install`; docs/a/notes.md and docs/b/notes.md both exist; docs/README.md shadows the root README.
AFIX="$ROOT/test/mdanchorfix"
[ -d "$AFIX" ] || { echo "no fixture at $AFIX"; exit 2; }
callees(){ # callees DIR SECTION → "n@file" per callee row, sorted, one per line
    $BIN "$1" --no-cache --callees="$2" --legend=compact 2>/dev/null \
        | python3 -c '
import sys, re
for m in re.finditer(r"<s t=\"[a-z]+\" n=\"([^\"]*)\" p=\"([^\":]*)", sys.stdin.read()):
    print(m.group(1) + "@" + m.group(2))' | sort
}
want(){ # want DIR SECTION EXPECTED(newline list) WHY
    got="$( callees "$1" "$2" )"
    if [ "$got" = "$3" ]; then ok "$4"; else no "$4 — got [$( echo "$got" | tr '\n' ' ' )] want [$( echo "$3" | tr '\n' ' ' )]"; fi
}
want "$AFIX" "Self Collision"    'Install@docs/b/partner.md'      "a link to ../b/partner.md#install binds partner's Install, not the linking file's own ## Install"
want "$AFIX" "Path Choice"       'Setup@docs/b/notes.md'          "../b/notes.md#setup binds docs/b/notes.md, not the same-directory notes.md"
want "$AFIX" "Root Readme Link"  'Languages@README.md'            "../../README.md#languages binds the ROOT README, not docs/README.md"
want "$AFIX" "Dup Link"          'Notes@docs/b/dup.md'            "#notes over two ## Notes gives ONE edge (first heading wins)"
want "$AFIX" "Func Name"         'do_work@docs/b/partner.md'      "a heading named like a .py function binds the section, never the function"
want "$AFIX" "Missing Anchor"    'partner@docs/b/partner.md'      "#no-such-heading falls back to that file's own node"
want "$AFIX" "Missed Readme"     'README@docs/b/README.md'        "../b/README.md#no-such-heading pins docs/b/README.md, not the same-directory README"
want "$AFIX" "Bare Readme"       'README@docs/b/README.md'        "a bare ../b/README.md pins that file, not the same-directory README"
if $BIN "$AFIX" --no-cache --callees='Missing Anchor' --legend=compact 2>/dev/null | grep -q 'n="partner"[^>]*anchor="missing"' \
 && ! $BIN "$AFIX" --no-cache --callees='Bare Readme' --legend=compact 2>/dev/null | grep -q 'anchor="missing"'; then
    ok "a slug the file does not have is anchor=missing, and a bare link is not"
else
    no "anchor=missing missed the slug fallback, or a bare link carried it"
fi
if $BIN "$AFIX" --no-cache --format=columnar --callees='Func Name' --legend=compact 2>/dev/null | grep -q '<via>2</via>'; then
    ok "columnar via is 2 for a direct markdown link"
else
    no "columnar via did not write 2 for the markdown link"
fi
want "$AFIX" "Fence Only"        ''                               "a link inside a fenced block makes no edge"
# anchor="missing" is a CLAIM that the heading is absent, so it is made only when the slug is provably absent. Four shapes the
# slug function does not model reach the same file-node fallback as a truly missing heading (a non-ASCII or percent-encoded slug,
# GitHub's -N duplicate suffix, and a file that is only one heading line, whose heading IS the file node): each keeps its edge
# and carries NO mark. Each arm links from its own section, so the rows do not merge into one pair.
mkdir -p "$TMP/amiss/docs"
printf '%s\n' '# Doc' '' '## Überblick' '' 'x' '' '## 概要' '' 'y' '' '## Dup' '' 'a' '' '## Dup' '' 'b' '' '## Real Heading' '' 'z' > "$TMP/amiss/docs/t.md"
printf '%s\n' '# Title' > "$TMP/amiss/docs/one.md"
printf '%s\n' '# Links' '' \
    '## UberLink' '' '[a](t.md#überblick)' '' '## GaiLink' '' '[a](t.md#概要)' '' '## DupLink' '' '[a](t.md#dup-1)' '' \
    '## OneLink' '' '[a](one.md#title)' '' '## PctLink' '' '[a](t.md#real%20heading)' '' '## EncLink' '' '[a](t.md#%C3%BCberblick)' '' \
    '## MissLink' '' '[a](t.md#nonexistent)' '' '## MissNumLink' '' '[a](t.md#bar-2)' '' '## OneMissLink' '' '[a](one.md#nothere)' \
    > "$TMP/amiss/docs/links.md"
amiss_row(){ $BIN "$TMP/amiss" --no-cache --callees="$1" --legend=compact 2>/dev/null; }
amiss_unmarked(){ # amiss_unmarked SECTION TARGET WHY: the edge exists (via=link) and says nothing about a missing anchor
    row="$( amiss_row "$1" )"
    if printf '%s' "$row" | grep -q "n=\"$2\"[^>]*via=\"link\"" && ! printf '%s' "$row" | grep -q 'anchor="missing"'; then ok "$3"; else no "$3 — got [$( printf '%s' "$row" | grep -o '<s [^>]*>' )]"; fi
}
amiss_marked(){ # amiss_marked SECTION TARGET WHY: the same fallback, marked, because the slug is absent
    if amiss_row "$1" | grep -q "n=\"$2\"[^>]*via=\"link\"[^>]*anchor=\"missing\""; then ok "$3"; else no "$3"; fi
}
amiss_unmarked UberLink "t"     "#überblick (a non-ASCII slug, heading present) keeps the file edge, no anchor=missing"
amiss_unmarked GaiLink  "t"     "#概要 (a CJK slug, heading present) keeps the file edge, no anchor=missing"
amiss_unmarked DupLink  "t"     "#dup-1 (GitHub's duplicate suffix, second ## Dup present) keeps the file edge, no anchor=missing"
amiss_unmarked OneLink  "Title" "one.md#title (the file is just that heading) keeps the file edge, no anchor=missing"
amiss_unmarked PctLink  "t"     "#real%20heading (percent-encoded, heading present) keeps the file edge, no anchor=missing"
amiss_unmarked EncLink  "t"     "#%C3%BCberblick (percent-encoded UTF-8, heading present) keeps the file edge, no anchor=missing"
amiss_marked MissLink    "t"     "a plain ASCII slug no heading has is still anchor=missing"
amiss_marked MissNumLink "t"     "#bar-2 with no ## Bar (the -N stem is absent) is still anchor=missing"
amiss_marked OneMissLink "Title" "one.md#nothere (a heading-only file, other slug) is still anchor=missing"

# The same claim rests on mdSlugOf matching the slug GitHub gives the RENDERED heading. A heading that holds inline markup (a link,
# _emphasis_, an HTML tag, `*`) is slugged from its raw source by mdSlugOf, so a link that names the rendered slug misses it. A file
# with such a heading proves nothing by a miss: the edge stays, unmarked. A plain file, and snake_case (no emphasis), still mark.
mkdir -p "$TMP/mkup"
printf '%s\n' '# Doc' '' '## See [docs](x.md)' '' 'a' '' '## _Setup_' '' 'b' '' '## Plain Head' '' 'c' > "$TMP/mkup/m.md"
printf '%s\n' '# _Solo_' > "$TMP/mkup/solo.md"
printf '%s\n' '# Doc' '' '## snake_case' '' 'a' '' '## Other' '' 'b' > "$TMP/mkup/s.md"
printf '%s\n' '# Links' '' \
    '## SeeLink' '' '[a](m.md#see-docs)' '' '## SetupLink' '' '[a](m.md#setup)' '' '## PlainLink' '' '[a](m.md#plain-head)' '' \
    '## MarkupMiss' '' '[a](m.md#nonexistent)' '' '## SoloLink' '' '[a](solo.md#solo)' '' \
    '## SnakeLink' '' '[a](s.md#snake_case)' '' '## SnakeMiss' '' '[a](s.md#absent)' > "$TMP/mkup/links.md"
mkup_row(){ $BIN "$TMP/mkup" --no-cache --callees="$1" --legend=compact 2>/dev/null; }
mkup_unmarked(){ # mkup_unmarked SECTION TARGET WHY: the edge exists (via=link) and says nothing about a missing anchor
    row="$( mkup_row "$1" )"
    if printf '%s' "$row" | grep -q "n=\"$2\"[^>]*via=\"link\"" && ! printf '%s' "$row" | grep -q 'anchor="missing"'; then ok "$3"; else no "$3 — got [$( printf '%s' "$row" | grep -o '<s [^>]*>' )]"; fi
}
mkup_unmarked SeeLink    "m"             "#see-docs over '## See [docs](x.md)' (rendered slug see-docs) keeps the file edge, no anchor=missing"
mkup_unmarked SetupLink  "m"             "#setup over '## _Setup_' (rendered slug setup) keeps the file edge, no anchor=missing"
mkup_unmarked MarkupMiss "m"             "a slug no heading has, in a file whose headings hold inline markup, is not provably absent: no anchor=missing"
mkup_unmarked SoloLink   "_Solo_"        "#solo over a file that is just '# _Solo_' keeps the file edge, no anchor=missing"
if mkup_row PlainLink | grep -q 'n="Plain Head"[^>]*via="link"' && ! mkup_row PlainLink | grep -q 'anchor="missing"'; then ok "a plain heading in the markup file still binds exactly"; else no "a plain heading beside markup headings lost its exact bind"; fi
if mkup_row SnakeLink | grep -q 'n="snake_case"[^>]*via="link"' && ! mkup_row SnakeLink | grep -q 'anchor="missing"'; then ok "#snake_case binds the snake_case heading exactly"; else no "#snake_case did not bind its heading"; fi
if mkup_row SnakeMiss | grep -q 'n="s"[^>]*via="link"[^>]*anchor="missing"'; then ok "a missing slug beside a snake_case heading (no emphasis) is still anchor=missing"; else no "snake_case wrongly counted as inline markup: the plain miss lost its mark"; fi

# --json map rows read the same edge-kind byte as the XML twin: a markdown link is "via":"link" (never "name"), and a missing
# anchor is "anchor":"missing".
if $BIN "$TMP/amiss" --no-cache --json 2>/dev/null | python3 -c '
import sys, json
d = json.load(sys.stdin)
rows = {s["n"]: s for f in d["r"] for s in f.get("s", [])}
c = {x["n"]: x for x in rows["MissLink"]["c"]}
u = {x["n"]: x for x in rows["UberLink"]["c"]}
assert c["t"].get("via") == "link" and c["t"].get("anchor") == "missing", c
assert u["t"].get("via") == "link" and "anchor" not in u["t"], u
'; then ok "--json map: a link row is via=link (anchor=missing only on the provably missing one), not via=name"; else no "--json map rows spell a markdown link as via=name or drop its anchor mark"; fi

# Callers that reach a namesake only through a markdown link are no by-name hit (near_sink): Caller links d.md#install, a different
# section than b.md's Install, whose name it shares. The link is proven; nothing was matched by name.
mkdir -p "$TMP/ngap"
printf '%s\n' '# B' '' '## Start' '' 'hello' '' '## Install' '' 'steps' > "$TMP/ngap/b.md"
printf '%s\n' '# C' '' '## Caller' '' '[x](d.md#install)' > "$TMP/ngap/c.md"
printf '%s\n' '# D' '' '## Install' '' 'other' > "$TMP/ngap/d.md"
NG="$( $BIN "$TMP/ngap" --no-cache --path='Start,b.md::B::Install' --legend=compact 2>/dev/null )"
if printf '%s' "$NG" | grep -q '<near_sink' && ! printf '%s' "$NG" | grep -q 'withheld="name\|why="[a-z,:0-9]*name'; then ok "near_sink: a markdown link to a same-named heading is no by-name hit"; else no "near_sink counted a markdown link as a by-name call (withheld=name / why=name): $( printf '%s' "$NG" | grep -o '<ns [^>]*>' )"; fi

# names-only <calls> rows (--for hops) merge only rows of the same anchor state: Hub links a.md#b (a real heading named B, l=3)
# and b.md#nope (missing, so the file node B, l=1). The merged row used to read l="1,3" anchor="missing", marking the good link.
# BAND CF (2026-11-17): each row names its file, the two B rows being in two files (a.md, b.md), which is a second reason they are two rows.
mkdir -p "$TMP/nmerge"
printf '%s\n' '# Hub' '' '## Hub Section' '' 'zqhubtoken [first](b.md#nope) and [second](a.md#b) and [third](e.md#zzz)' > "$TMP/nmerge/x.md"
printf '%s\n' '# A' '' '## B' '' 'text' > "$TMP/nmerge/a.md"
printf '%s\n' '# B' > "$TMP/nmerge/b.md"
printf '%s\n' '# E' '' '## Other' > "$TMP/nmerge/e.md"
NM="$( $BIN "$TMP/nmerge" --no-cache --for=zqhubtoken --legend=compact 2>/dev/null | grep -o '<calls total="3">.*</calls>' )"
if printf '%s' "$NM" | grep -q '<c n="B" l="3" p="a.md" via="link"/>' && printf '%s' "$NM" | grep -q '<c n="B" l="1" p="b.md" via="link" anchor="missing"/>' && ! printf '%s' "$NM" | grep -q 'l="1,3"'; then ok "--for hops: the good B link and the missing-anchor B link stay two rows"; else no "--for hops merged a good link into a missing-anchor row: [$NM]"; fi

# A --for head that already defines via="name" must still define via="link" when a hop row carries it (run has a proven and a
# by-name callee; Hub Section links): the link reading rides on its own presence, not on the name legend's.
mkdir -p "$TMP/vlink/pkg/x" "$TMP/vlink/other"
printf 'class A:\n    def process(self):\n        return 1\n' > "$TMP/vlink/pkg/x/a.py"
printf 'def helper():\n    return 3\n\ndef run(obj):\n    # zqshared\n    helper()\n    return obj.process()\n' > "$TMP/vlink/pkg/x/c.py"
printf 'def target():\n    return 2\n\nclass B:\n    def process(self):\n        return target()\n' > "$TMP/vlink/other/b.py"
printf '%s\n' '# Guide' '' '## Hub Section' '' 'zqshared see [more](dd.md#zzz) and [ok](dd.md#real-part)' > "$TMP/vlink/guide.md"
printf '%s\n' '# DD' '' '## Real Part' '' 'x' > "$TMP/vlink/dd.md"
for leg in default full; do
    if [ "$leg" = default ]; then VL="$( $BIN "$TMP/vlink" --no-cache --for=zqshared 2>/dev/null )"; else VL="$( $BIN "$TMP/vlink" --no-cache --for=zqshared --legend=full 2>/dev/null )"; fi
    if printf '%s' "$VL" | grep -q 'via="name"' && printf '%s' "$VL" | grep -q 'via="link"' && printf '%s' "$VL" | grep -q 'markdown link, not a call'; then ok "--for ($leg legend): a via=name head and a via=link hop row both carry their legend"; else no "--for ($leg legend): via=link rows ride without their legend, or the fixture lost a row kind"; fi
done
# --callers lists every matched def in <def ix= t= p=> (cross_kind when a heading and a function share the name).
# The edge is the <s> row: it must name the section, never the .py function.
if $BIN "$AFIX" --no-cache --callers=do_work --legend=compact 2>/dev/null | python3 -c '
import sys, re
xml = sys.stdin.read()
kind = { m.group(1): m.group(2) for m in re.finditer(r"<def ix=\"(\d+)\" t=\"([a-z]+)\"", xml) }
rows = list(re.finditer(r"<s t=\"[a-z]+\"([^>]*)/?>", xml))
ok = bool(rows) and "fn" in kind.values() and "sec" in kind.values()
saw_sec = False
saw_fn = False
for m in rows:
    attrs = m.group(1)
    p = re.search(r" p=\"([^\"]*)\"", attrs)
    of = re.search(r"of_def=\"(\d+)", attrs)
    via = re.search(r" via=\"([^\"]*)\"", attrs)
    if p and "tools.py" in p.group(1):
        ok = False
    if of and kind.get(of.group(1)) == "fn":
        saw_fn = True
        if via and via.group(1) == "link":
            ok = False
    else:
        if not via or via.group(1) != "link":
            ok = False
        else:
            saw_sec = True
sys.exit(0 if ok and saw_sec and saw_fn else 1)
'; then ok "the section caller stays via=link and the Python caller of do_work is unmarked"; else no "the doc link leaked onto the .py function, or the section row lacks via=link"; fi
if ( cd "$AFIX" && $BIN . --no-cache --callers=do_work --legend=compact ) 2>/dev/null | grep -q 'n="Func Name"[^>]*via="link"'; then
    ok "a dot crawl root still pins the markdown link (./docs/... matches docs/...)"
else
    no "a dot crawl root dropped the markdown link pin"
fi
QUAL=$($BIN "$AFIX" --no-cache --callers='docs/a/tools.py:do_work' --legend=compact 2>/dev/null || true)
if printf '%s' "$QUAL" | grep -q 'count="[1-9]' && printf '%s' "$QUAL" | grep -q 'n="use_work"' && ! printf '%s' "$QUAL" | grep -q 'via="link"'; then
    ok "the .py do_work has a real caller and that row is not via=link"
else
    no "the qualified .py do_work callers were empty or carried via=link"
fi
if $BIN "$AFIX" --no-cache --callees='Self Collision' --legend=compact 2>/dev/null | grep -q 'n="Install"[^>]*via="link"'; then
    ok "Self Collision's callee Install is via=link"
else
    no "Self Collision's callee Install lacks via=link"
fi
if $BIN "$AFIX" --no-cache --json --callees='Self Collision' 2>/dev/null | grep -q '"via":"link"'; then
    ok "the JSON callee row spells via=link"
else
    no "the JSON callee row lacks via=link"
fi
if $BIN "$AFIX" --no-cache --json --callers=do_work 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
rows = d.get("callers", [])
sec = any(r.get("t") == "sec" and r.get("via") == "link" for r in rows)
fn = any(r.get("t") == "fn" and r.get("via") == "link" for r in rows)
sys.exit(0 if sec and d.get("via_link_note") and not fn else 1)
'; then ok "the JSON callers answer marks the section row and carries via_link_note"; else no "the JSON callers answer lacks via_link_note, or the function row is marked via=link"; fi
mcp_text(){
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$1" \
        | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
print("__ERROR__:" + r["error"].get("message", "") if "error" in r else r["result"]["content"][0]["text"])
'
}
call(){ printf '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"%s","arguments":%s}}' "$1" "$2"; }
M="$( mcp_text "$( call find_referencing_symbols '{"path":"'"$AFIX"'","symbol":"do_work"}' )" )"
printf '%s' "$M" | python3 -c '
import json, sys
d = json.load(sys.stdin)
rows = d.get("calledBy", [])
sec = any(r.get("kind") == "sec" and r.get("via") == "link" for r in rows)
fn = any("tools.py" in r.get("file", "") and r.get("via") == "link" for r in rows)
sys.exit(0 if sec and d.get("via_link_note") and not fn else 1)
' && ok "find_referencing_symbols marks the section row via=link and carries via_link_note" \
  || no "find_referencing_symbols lacks via=link on the section row, or marks the .py caller"
M="$( mcp_text "$( call find_symbol '{"path":"'"$AFIX"'","symbol":"Self Collision"}' )" )"
printf '%s' "$M" | python3 -c '
import json, sys
d = json.load(sys.stdin)
rows = d.get("calls", [])
hit = any(r.get("name") == "Install" and r.get("via") == "link" for r in rows)
sys.exit(0 if hit and d.get("via_link_note") else 1)
' && ok "find_symbol marks Install via=link and carries via_link_note" \
  || no "find_symbol lacks via=link on Install or lacks via_link_note"

# A direct doc caller is via="link" on --safe-delete and --impact. The counts still include it.
mkdir -p "$TMP/runfix/src" "$TMP/runfix/docs"
printf '%s\n' 'def run():' '    return 1' '' 'def main():' '    run()' > "$TMP/runfix/src/app.py"
printf '%s\n' '# API' '' '## run' > "$TMP/runfix/docs/api.md"
printf '%s\n' '# Guide' '' '## Run Notes' '' 'see [run](api.md#run)' > "$TMP/runfix/docs/guide.md"
SD="$( $BIN "$TMP/runfix" --no-cache --safe-delete=run --legend=compact 2>/dev/null )"
printf '%s' "$SD" | grep -q 'callers="2"' \
  && printf '%s' "$SD" | grep -q 'n="Run Notes"[^>]*via="link"' \
  && ! printf '%s' "$SD" | grep -q 'n="main"[^>]*via="link"' \
  && ok "safe-delete marks Run Notes via=link and still counts both callers" \
  || no "safe-delete dropped the link mark or the caller count"
IM="$( $BIN "$TMP/runfix" --no-cache --impact=run --legend=compact 2>/dev/null )"
printf '%s' "$IM" | grep -q 'reaches="2"' \
  && printf '%s' "$IM" | grep -q 'n="Run Notes"[^>]*via="link"' \
  && ! printf '%s' "$IM" | grep -q 'n="main"[^>]*via="link"' \
  && ok "impact marks Run Notes via=link and still counts both rows" \
  || no "impact dropped the link mark or the reach count"
IJ="$( $BIN "$TMP/runfix" --no-cache --impact=run --json 2>/dev/null )"
printf '%s' "$IJ" | grep -q 'via_link_note' \
  && ok "impact json carries via_link_note" \
  || no "impact json omitted via_link_note"

# In-file anchors, wikilinks, and root-relative links are via="link". A code call on the same name stays unmarked.
mkdir -p "$TMP/kinds/src" "$TMP/kinds/docs" "$TMP/kinds/notes"
printf '%s\n' 'def api():' '    return 1' '' 'def main():' '    api()' > "$TMP/kinds/src/app.py"
printf '%s\n' '# api' > "$TMP/kinds/docs/api.md"
printf '%s\n' '# decoy' > "$TMP/kinds/notes/api.md"
printf '%s\n' '# Guide' '' '## Hub' '' '[down](#later)' '' '[a](api.md)' '' '[b](/docs/api.md)' '' '[[api]]' '' '## Later' '' 'notes' > "$TMP/kinds/docs/guide.md"
HUB="$( $BIN "$TMP/kinds" --no-cache --callees=Hub --legend=compact 2>/dev/null )"
printf '%s' "$HUB" | grep -q 'n="Later"[^>]*via="link"' \
  && printf '%s' "$HUB" | grep -q 'n="api"[^>]*via="link"' \
  && ok "in-file, wikilink, and root-relative links are via=link" \
  || no "an in-file, wikilink, or root-relative link lost via=link"
API="$( $BIN "$TMP/kinds" --no-cache --callers=api --legend=compact 2>/dev/null )"
printf '%s' "$API" | grep -q 'n="Hub"[^>]*via="link"' \
  && printf '%s' "$API" | grep -q 'n="main"' \
  && ! printf '%s' "$API" | grep -q 'n="main"[^>]*via="link"' \
  && ok "a code call to api stays unmarked while the doc link stays via=link" \
  || no "the code call was marked via=link, or the doc link lost the mark"
printf '%s' "$HUB" | grep -q 'docs/api.md:[0-9]*"[^>]*via="link"' \
  && ! printf '%s' "$HUB" | grep -q 'notes/api.md' \
  && ok "a leading-slash link joins the crawl root, not the other api.md" \
  || no "the leading-slash link missed docs/api.md or hit the decoy"
PTH="$( $BIN "$TMP/kinds" --no-cache --path=Hub,Later --legend=compact 2>/dev/null )"
printf '%s' "$PTH" | grep -q 'n="Later"[^>]*via="link"' \
  && ok "path marks the Later hop via=link" \
  || no "path lost via=link on the Later hop"
CON="$( $BIN "$TMP/kinds" --no-cache --connect=Hub,Later --legend=compact 2>/dev/null )"
printf '%s' "$CON" | grep -q 'via="link"' \
  && ok "connect marks the Hub to Later edge via=link" \
  || no "connect lost via=link on the Hub to Later edge"

echo "--- warm == cold after editing ONLY the target file (the cached ref must stay unbound) ---"
cp -R "$AFIX" "$TMP/anchorcopy"
rm -f "$TMP/anchor.cache"
$BIN "$TMP/anchorcopy" --cache="$TMP/anchor.cache" --callees="Self Collision" --legend=compact >/dev/null 2>&1
sed -i.bak 's/^## Install$/## Install Steps Renamed/' "$TMP/anchorcopy/docs/b/partner.md"
rm -f "$TMP/anchorcopy/docs/b/partner.md.bak"
grep -q '^## Install Steps Renamed$' "$TMP/anchorcopy/docs/b/partner.md" || no "fixture edit did not apply (sed)"
$BIN "$TMP/anchorcopy" --cache="$TMP/anchor.cache" --callees="Self Collision" --legend=compact >"$TMP/ac_warm" 2>/dev/null
$BIN "$TMP/anchorcopy" --no-cache --callees="Self Collision" --legend=compact >"$TMP/ac_cold" 2>/dev/null
if [ -s "$TMP/ac_cold" ] && diff -q "$TMP/ac_cold" "$TMP/ac_warm" >/dev/null; then ok "warm run equals cold run after only the target heading changed"; else no "warm run differs from cold after a target-only edit (a stale bound ref)"; fi
if grep -q 'n="partner"' "$TMP/ac_warm"; then ok "…and the dead anchor degraded to the partner file edge"; else no "the renamed-heading link lost its edge on the warm run"; fi

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== determinism ×3 and cache transparency on the md fixture ==="
# ═══════════════════════════════════════════════════════════════════════════
$BIN "$FIX" --no-cache >"$TMP/d1" 2>/dev/null
$BIN "$FIX" --no-cache >"$TMP/d2" 2>/dev/null
$BIN "$FIX" --no-cache >"$TMP/d3" 2>/dev/null
if [ -s "$TMP/d1" ] && diff -q "$TMP/d1" "$TMP/d2" >/dev/null && diff -q "$TMP/d1" "$TMP/d3" >/dev/null; then
    ok "determinism: 3 byte-identical runs ($( wc -c <"$TMP/d1" | tr -d ' ' ) B)"
else
    no "determinism: runs differ (or empty output)"
fi
rm -f "$TMP/cache.bin"
$BIN "$FIX" --cache="$TMP/cache.bin" >"$TMP/cold" 2>/dev/null
$BIN "$FIX" --cache="$TMP/cache.bin" >"$TMP/warm" 2>/dev/null
if diff -q "$TMP/cold" "$TMP/warm" >/dev/null; then ok "cache transparency (warm == cold)"; else no "cache transparency: warm run differs from cold"; fi

# ── verdict ─────────────────────────────────────────────────────────────────
echo
if [ "$fail" = 0 ]; then
    echo "ALL PASS"
else
    echo "FAILURES PRESENT"
    exit 1
fi
