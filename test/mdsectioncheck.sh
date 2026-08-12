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
#     wikilink machinery), [text](#anchor) → doc-section→doc-section IN-FILE; `backtick`
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
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/mdsectionfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
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
guard(){ grep -qF -- "$2" "$1" && ok "fixture spells $3" || no "fixture LOST $3 — its arm below would pass by finding nothing"; }
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
guard "$G" '(#result-tables)'              'the in-file anchor link'
guard "$G" '[[decoy]]'                     'the wikilink to decoy'
guard "$G" '[zqref]: decoy.md'             'the reference-style link definition'
guard "$G" '`codeIdentFn`'                 'the backtick doc→code mention'
[ "$( grep -l '^# Install Steps' "$FIX/partner.md" "$FIX/decoy.md" | wc -l | tr -d ' ' )" -eq 2 ] \
    && ok "partner.md and decoy.md share the heading  # Install Steps  (the decoy pair exists)" \
    || no "the Install Steps decoy pair is gone"
grep -qE '^#' "$FIX/plainprose.md" && no "plainprose.md grew a heading — the whole-doc fallback arm is dead" \
    || ok "plainprose.md is heading-less (the whole-doc fallback arm has its subject)"
grep -qF 'zqplainprose' "$FIX/plainprose.md" && ok "plainprose.md carries zqplainprose" || no "plainprose.md lost zqplainprose"
[ "$( head -c 300 "$FIX/deepquote.md" | tr -dc '>' | wc -c | tr -d ' ' )" -eq 300 ] \
    && ok "deepquote.md still opens 300 blockquote markers" || no "deepquote.md lost its 300-deep marker run"
grep -q $'\r' "$FIX/crlf.md" && ok "crlf.md really has CRLF line endings" || no "crlf.md lost its CR bytes"
grep -qF 'zqaltextension' "$FIX/alt.markdown" && ok "alt.markdown carries zqaltextension" || no "alt.markdown lost zqaltextension"
grep -qF 'zqCodeAnchorFn' "$FIX/helpers.c" && ok "helpers.c defines zqCodeAnchorFn" || no "helpers.c lost zqCodeAnchorFn"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== default map: exit/wellformed/deep-quote guard, and the section symbol set ==="
# ═══════════════════════════════════════════════════════════════════════════
MAP="$TMP/map.xml"
$BIN "$FIX" --no-cache >"$MAP" 2>"$TMP/map.err"
RC=$?
[ "$RC" -eq 0 ] && ok "default map exits 0" || no "default map exited $RC: $( head -3 "$TMP/map.err" )"
xmllint --noout "$MAP" 2>/dev/null && ok "map passes xmllint --noout" || no "map is not well-formed XML"

# deep-quote guard: deepquote.md is refused BEFORE the parse with a one-line note (the yaml
# posture); nearlimit.md (150 deep) parses fine and gets NO note.
grep -q 'deepquote\.md.*nesting' "$TMP/map.err" \
    && ok "deepquote.md refused with a nesting note (scanner OOB depth never reaches the parser)" \
    || no "deepquote.md was NOT refused — the markdown depth guard is missing (scanner serialize() OOB class)"
grep -q 'nearlimit\.md' "$TMP/map.err" \
    && no "nearlimit.md (150 deep) drew a stderr note — the guard is overbroad" \
    || ok "nearlimit.md (150 deep) parses without a note (guard is not overbroad)"
[ "$( grep -cv 'deepquote\.md' "$TMP/map.err" )" -eq 0 ] \
    && ok "no other stderr beyond the deepquote note" \
    || no "unexpected stderr: $( grep -v 'deepquote\.md' "$TMP/map.err" | head -2 )"

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
grep -qF '::Orientation Guide::Cache Warm Path"' "$MAP" \
    && ok "Cache Warm Path is scoped under Orientation Guide" \
    || no "Cache Warm Path carries no Orientation Guide scope (heading hierarchy missing)"
grep -qF '::Deployment Rollout Setext::Rollback Plan"' "$MAP" \
    && ok "Rollback Plan (setext H2) is scoped under Deployment Rollout Setext (setext H1)" \
    || no "setext hierarchy missing (Rollback Plan not scoped under the setext H1)"
grep -qF '::Rollback Plan::Deep Appendix"' "$MAP" \
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
edge(){ grep -qF "$1 -> $2" "$TMP/edges.txt" && ok "edge: $1 -> $2  ($3)" || no "edge MISSING: $1 -> $2  ($3)"; }
edge "Cache Warm Path" "partner"        'inline [text](partner.md) link, attributed to its section'
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
python3 - "$TMP/for.xml" <<'PYEOF' && ok "the section row's sig is the heading line (never the section body)" || no "the section row's sig leaks the section body"
import sys, re
xml = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'<d[^>]*n="Cache Warm Path"[^>]*>(.*?)</d>', xml, re.S)
sys.exit(0 if m and 'Cache Warm Path' in m.group(1) and 'zqcachewarmbody' not in m.group(1) else 1)
PYEOF

echo "--- code-query pollution: a name-exact code query is answered by the code symbol first ---"
$BIN "$FIX" --no-cache --for="zqCodeAnchorFn" >"$TMP/forcode.xml" 2>/dev/null
python3 - "$TMP/forcode.xml" <<'PYEOF' && ok "--for=zqCodeAnchorFn: first row is the C function, not a doc section" || no "--for=zqCodeAnchorFn: a doc section displaced the code answer"
import sys, re
xml = open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'<d [^>]*n="([^"]*)"', xml)
sys.exit(0 if m and m.group(1) == 'zqCodeAnchorFn' else 1)
PYEOF

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== --expand serves the SECTION span (heading → next same-or-higher heading) ==="
# ═══════════════════════════════════════════════════════════════════════════
xp(){ # xp SELECTOR OUTFILE
    $BIN "$FIX" --no-cache --expand="$1" --top-k=0 >"$2" 2>/dev/null
}
has(){ grep -qF "$2" "$1" && ok "$3" || no "$4"; }
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
grep -qF 'plainprose.md' "$TMP/r2" && ok "…as its whole doc (the disclosed fallback)" || no "plainprose.md separator missing"

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
diff -q "$TMP/cold" "$TMP/warm" >/dev/null && ok "cache transparency (warm == cold)" || no "cache transparency: warm run differs from cold"

# ── verdict ─────────────────────────────────────────────────────────────────
echo
if [ "$fail" = 0 ]; then
    echo "ALL PASS"
else
    echo "FAILURES PRESENT"
    exit 1
fi
