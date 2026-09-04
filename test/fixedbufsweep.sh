#!/usr/bin/env bash
# fixedbufsweep.sh — CA4 §B14: THE SWEEP. Every fixed `char[]` buffer whose contents can reach stdout as
# markup, classified, with a gate that fails when a NEW one appears.
#
# ══ WHY A SWEEP AND NOT A THIRD FIX ═════════════════════════════════════════════════════════════════════
# This class has now been fixed three times at the site that failed, and the RULE never became a sweep:
#   1. test/tracecheck.sh:246-249 records it verbatim for renderTraceBlock's `char row[640]` — fixed, gated,
#      and scoped to tracelocus.h ONLY.
#   2. test/churnjoincheck.sh:580-590 asserts the same idea on the INPUT side and greps src/gitmine.h ONLY,
#      leaving prcontext.h and quality.h outside both the grep and the claim.
#   3. §B14 then found SIX live emitters snprintf'ing already-escaped, unbounded path text into char[512].
# So this gate does not test a site. It re-derives the whole POPULATION from source every run and refuses to
# pass on a member it has never been told about.
#
# ══ THE RULE (stated once, in src/serialize.h above escapeXml — read it there) ═══════════════════════════
# Never snprintf ALREADY-ESCAPED or already-markup text into a fixed char[]. Compose it on std::string. The
# test that separates a breaching site from a safe one is WHICH SIDE OF THE BUFFER THE ESCAPER SITS ON:
#   escape-then-snprintf  -> the cut lands in the ESCAPED form (mid-entity, mid-attribute-name, mid-UTF-8,
#                            or before the element's own `/>`): a broken document at exit 0.
#   snprintf-then-escape  -> the cut only shortens PROSE, and the escaper runs over the shortened text.
# Length is not the danger; the escaping is. A char[512] breaks at 228 RAW bytes once `&` expands 5:1 and
# `'` 6:1 before the buffer is written.
#
# ══ THE ENUMERATION ═════════════════════════════════════════════════════════════════════════════════════
# Method: balanced-paren extraction of every `snprintf(` in `git ls-files src/`, so a call broken across
# lines counts ONCE. Note the audit's "156 snprintf mentions / 37 %s-bearing calls" mixed two units — 156 is
# a LINE count (`git grep -c`) and the %s figure was a line count too; calls and lines are not the same
# population, which is why the gate reports all of them separately.
#
# NO CURRENT COUNT IS WRITTEN IN THIS COMMENT. The header used to carry "after the 8 conversions: 153
# mentions" while the gate PRINTED 154 — stale in the merge that landed it, which is the exact rot this file
# exists to prevent, committed by the file preventing it. The live figures are DERIVED and printed by the
# INFO line and PINNED by arm (S6); the only historical numbers kept here are the before-picture, which is
# history and cannot rot: 156 mentions / 146 calls / 36 %s-bearing lines before §B14's 8 conversions.
#
# CLASSIFICATION OF THE SURVIVORS: 0 breaching · everything else safe / latent / not-markup
# (see the TABLE below; every row carries its worst-case arithmetic). The two LATENT rows both sit outside
# the lane that wrote this gate and are carried forward, not fixed:
#   prcontext.h  tail[256]  248 B worst case -- SEVEN bytes of margin
#   serialize.h  hb[176]    ~160 B worst case -- acd/nccd are %.1f/%.2f on DOUBLES, formally unbounded
#
# THE 8 CONVERTED (6 breaching + 2 latent), and what each did at a 612-616 B corpus path:
#
#   #  site                                    buffer        BEFORE (base_w3)              AFTER
#   1  editcheck.h  <edit-check> head          char[512]     document REJECTED by xmllint  parses
#   2  editcheck.h  <c> caller row             char[512]     4 of 4 rows unterminated      0 of 4
#   3  packtask.h   buildD1Row <s>             char[512]     rows truncated + swallowed    0 of 3
#   4  packtask.h   renderNameOnlyRows <s>     char[512]     (same document, <far> tier)   0 of 3
#   5  packtask.h   <test> row (TWO unbounded  char[512]     document REJECTED             0 of 1
#                   interpolands: path+runner)
#   6  serialize.h  mermaid node line          char[512]     8 node lines collapsed to 1,  8 lines,
#                                                            each losing `"]` AND its \n   0 malformed
#   7  serialize.h  map header stats           char[480]     latent: 496 B worst case      composed
#   8  serialize.h  partAttr / rb              char[40]/[24] latent: 41 B / off-by-one      composed
#
#   Sites 1-5 breach G4 AT EXIT 0 — a caller cannot detect them. Site 6 never breached G4 (it lives inside
#   appendCdataSafe); it is the "well-formed but says something FALSE" member, and only a SHAPE assertion
#   sees it, which is why arm (S5) carries one. Site 7's cut deletes the trailing ` -->` and turns the
#   entire document into one unterminated comment.
#
#   Row counts are given as "n of m" only on the AFTER side by design: on the broken binary a truncated row
#   swallows its successors, so the document is one malformed blob and per-row counting is not meaningful.
#   The measurement that IS meaningful on both sides is the parse verdict, and it is in the table above.
#
# ══ ARMS ════════════════════════════════════════════════════════════════════════════════════════════════
#   (S1) POPULATION — every snprintf call in src/ that interpolates a STRING is a KNOWN row in the table
#        below. An unknown one FAILS: a new emitter must be classified, not merely written. "Interpolates a
#        string" means ANY string conversion — `%s`, `%.*s`, `%-20s`, `%.9s` — not the literal two characters
#        `%s`, which is what this arm matched for one round while src/ already used `%.*s` in an XML open tag.
#   (S2) NO STALE ROWS — a table row matching nothing FAILS too, so the table cannot rot into fiction the way
#        xmlCommentText's "all six echo sites" did (trap #12).
#   (S3) THE SIX CONVERTED SITES stay converted — the fixed emitters must not carry a fixed buffer again.
#   (S4) §B4 ANTI-ROT — serialize.h's `CALL-SITES: N` for xmlCommentText must equal the re-derived count.
#   (S5) LIVE — the six converted emitters, exercised at a ~600-byte corpus path, must be xmllint-clean.
#        A static gate proves the shape; this proves the fix. (test/det-gate.sh and test/xmlwellformed.sh
#        carry the same width fixture for the determinism and G4 halves — see §B15.)
#   (S6) THE COUNTS ARE ASSERTED — mentions / calls / string-interpolating sites / rows / width-form sites
#        are pinned next to the table and re-derived every run, so no figure in this file is printed without
#        being checked. The header's own count had already rotted by one before this arm existed.
#
# Usage:  test/fixedbufsweep.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/fixedbufsweep.sh
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"

fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for the source sweep"; exit 2; }

echo "fixedbufsweep: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

# ── (S1)+(S2)+(S3)+(S4): the static sweep ───────────────────────────────────────────────────────────────
python3 - "$ROOT" <<'PY'
import os, re, subprocess, sys

ROOT = sys.argv[1]
bad  = 0
def ok_( m ): print( "  PASS  " + m )
def no_( m ):
    global bad
    bad = 1
    print( "  FAIL  " + m )

# ── THE TABLE. One row per (file, buffer name), with the count of call sites sharing that buffer and the
#    classification. Re-derived from source 2026-07-30, AFTER §B14's six conversions.
#
#    breaching : an interpoland is already-escaped/already-markup AND unbounded. There must be none.
#    safe      : the cut can only shorten prose, or every interpoland is bounded by construction and the
#                buffer provably fits the widest format.
#    latent    : bounded by construction, but the margin is thin enough that a future edit can cross it.
#                Recorded, not fixed — each row says why, and what it costs when it goes.
#    not-markup: the result never reaches stdout as a document (a cache filename, a stderr diagnostic).
TABLE = {
    # ── the paper-round (2026-08-28) serving-shape emitters — all three interpolate ONLY fixed vocabulary
    # and integers, so every worst case is compile-time arithmetic, not input-dependent ───────────────────
    ( "src/verbs_for.h", "attrBuf" ):  ( 1, "safe", "attrBuf[48]: ' confidence=\"%s\" margin_pct=\"%d\"' where %s is the two-value literal high|low and %d is a 0..100 percent — worst case ' confidence=\"high\" margin_pct=\"100\"' = 34 B against 47 usable + NUL, 13 B of margin. No user text can reach either interpoland." ),
    ( "src/packtask.h", "tag" ):       ( 1, "safe", "tag[112]: '<bodies shown=\"0\" total=\"%zu\" capped=\"%d\"%s></bodies>' — %zu is a vector size (20 digits at absolute most), %d is 0|1, %s is the literal ' compress=\"1\"' or empty. Worst case 40 fixed + 20 + 1 + 13 = 74 B against 111 usable. Escaper irrelevant: no interpoland carries text." ),
    ( "src/serialize.h", "open" ):     ( 1, "safe", "open[112]: '<bodies shown=\"%zu\" total=\"%zu\" capped=\"%d\"%s>' — two sizes, a 0|1, and the same fixed compress literal. Worst case 33 fixed + 40 + 1 + 13 = 87 B against 111 usable. Same all-numeric/fixed-vocab class as its packtask.h sibling." ),
    # ── src/cli.h ────────────────────────────────────────────────────────────────────────────────────────
    ( "src/cli.h", "example" ):        ( 1, "not-markup", "example[64]: ' %s=100' with the FLAG NAME from kIntFlags/the paging arms (longest ~20 B). A stderr refusal example, never a document." ),
    ( "src/cli.h", "flag" ):           ( 1, "not-markup", "flag[32] (`%.*s`, so INVISIBLE to the pre-wave-3 population): applyIntFlag's echoed flag name. `bare` is f.prefix minus its trailing '=', and f.prefix is a literal in the compile-time kIntFlags table — 13 rows, longest '--connect-radius=' ⇒ bare 16 B against 31 usable + NUL, 15 B of margin. The `.*` precision is int( bare.size() ) and bounds NOTHING; the bound is the table. Result goes to refuseFlagValue, which fprintf's it to STDERR — never a document." ),
    # ── src/infra/profileScope.h — the opt-in self-profiler's REPORT formatter ───────────────────────────
    # Not markup by construction, and doubly so: the report is human-readable text printed to stdout by
    # prof::report(), never an element of the XML document; and the whole facility compiles to ((void)0)
    # unless -DRIPWIRE_PROFILE=ON, so none of these three buffers exists in a normal binary. A truncation
    # here shortens one line of a developer's timing table. It cannot land inside a tag.
    ( "src/infra/profileScope.h", "nameBuf" ):  ( 2, "not-markup", "nameBuf[160] x2 at :721/:723: '%s [%s]' over trim_pretty's fn[96] plus Site::description, a compile-time string literal from the PROFILE_SCOPE_DESCRIBE call site. Printed as a timing-table row, never emitted as a document." ),
    ( "src/infra/profileScope.h", "locBuf" ):   ( 1, "not-markup", "locBuf[64] at :724: '%s:%d' over Site::file (__FILE__, a compile-time literal) and Site::line. Same timing table; a truncated path costs a developer legibility, nothing else." ),
    ( "src/infra/profileScope.h", "indented" ): ( 1, "not-markup", "indented[208] at :759: '%*s%s%s' — a width-form pad (depth*2, and depth is capped at 64 by print_tree_node's own guard) over nameBuf[160] plus the literal ' *'. Same timing table." ),
    # ── src/lanes.h — THE REFERENCE SAFE SHAPE ───────────────────────────────────────────────────────────
    ( "src/lanes.h", "buf" ):          ( 3, "safe",       "buf[640] x3: snprintf-THEN-escape. :723 interpolates an UNBOUNDED file path and is still safe for exactly that reason — the warning text is escaped downstream, so a cut shortens prose and can never land inside markup. This is the shape §B14's six were not." ),
    # ── src/main.cpp ─────────────────────────────────────────────────────────────────────────────────────
    ( "src/main.cpp", "tail" ):        ( 1, "not-markup", "tail[48]: the cache FILENAME ('rich'/'lean' + a %016llx). Bounded and never emitted." ),
    ( "src/verbs_for.h", "nb" ):       ( 2, "safe",       "nb[160] x2: the mention/doc-mention header notes. Every %s is the plural '' or 's'; everything else is %u." ),
    ( "src/verbs_report.h", "exemptAttr" ): ( 1, "safe",       "exemptAttr[40]: ' exempt=\"%s\"' with groupExemptKind's fixed vocabulary (longest 'fixture' = 7 B, total 19 B)." ),
    ( "src/verbs_report.h", "hdr" ):    ( 1, "safe",       "hdr[512]: runSkipped's <skipped ...> root (§L1). 175 B of literal + ELEVEN %zu/%llu counters at 20 B worst case = 395 B, plus the ONE %s, which is the compile-time literal ' rows_capped=\"1\"' or '' (18 B) = 413 B against 511 usable. No path, no name, nothing user-supplied reaches this buffer — every emitted path goes through escapeXml straight into the writer, outside it." ),
    ( "src/verbs_report.h", "row" ):    ( 2, "safe",       "row[96] + row[192], runSkipped's two row emitters (§L1). row[96] at the <f> drop row: '\" why=\"%s\" bytes=\"%llu\" ext=\"' where %s is the CLOSED vocabulary {oversize, excluded, unsupported-ext} (15 B longest) = ~60 B. row[192] at the <h> parse-health row: three %s from the closed why= vocabulary (31 B for the joined 'degraded-parse,minified-suspect'), one %u, two %.3f of ratios that are <=1.0 by construction (errBytes sums DISJOINT top-most ERROR spans, ws sample is its own denominator) and 14 B even if a future edit broke that, one %u = ~131 B. Both p= values are written by escapeXml OUTSIDE the buffer." ),
    # ── src/mcpverbs.h ───────────────────────────────────────────────────────────────────────────────────
    ( "src/mcpverbs.h", "nb" ):        ( 4, "safe",       "nb[160] x4: the CLI notes' MCP twins, byte-identical format. Plural '' / 's' only." ),
    # ── src/packtask.h ───────────────────────────────────────────────────────────────────────────────────
    ( "src/packtask.h", "open" ):      ( 2, "safe",       "open[160] (`%.*s` x2, so INVISIBLE to the pre-wave-3 population, and it is an XML OPEN TAG — the shape §B14 is about): packTaskListSection's '<TAG EXTRA shown=\"%zu\" total=\"%zu\" capped=\"%d\">'. Safe by ARITHMETIC, not by shape. 30 B of literal ('<' 1 + ' shown=\"' 8 + '\" total=\"' 9 + '\" capped=\"' 10 + '\">' 2). tag comes from the FOUR call sites (:448 'far', :610 'callers', :659 'notes', :698 'tests') ⇒ 7 B. extraAttr is farAttr[32]/callersAttr[32] or the empty literal, and those two are themselves ' of_top=\"%zu\"' snprintf'd into a char[32] ⇒ 31 B at most. Two %zu ⇒ 20 digits each, %d ⇒ 1. Worst case 30+7+31+20+20+1 = 109 B + NUL against 160: 50 B of margin. NOTE both `.*` precisions are int( v.size() ) — they print a string_view, they do not clamp it; the bound is the caller vocabulary and the char[32] feeding extraAttr. SECOND SITE (2026-08-28 serving-shape round, :903): restatePackTaskBodiesWrapper restates the bodies open tag into its own open[112] — two %zu at 20 digits, a fixed capped literal, and a %s that is the 13 B compress literal or empty, ~35 B of literal in total, worst case 88 B against 111 usable. All-numeric/fixed-vocab, same class as the first site." ),
    # ── src/partition.h ──────────────────────────────────────────────────────────────────────────────────
    ( "src/partition.h", "h" ):        ( 2, "safe",       "h[288] x2: <bundle role=\"%s\" ...>; role is the fixed 'core'/'slice' vocabulary, the rest %zu/%u/%d." ),
    ( "src/partition.h", "pb" ):       ( 1, "safe",       "pb[96]: the JSON part header; the %s is '' or ',' (the separator)." ),
    # ── src/prcontext.h ──────────────────────────────────────────────────────────────────────────────────
    ( "src/prcontext.h", "tail" ):     ( 1, "latent",     "tail[256]: truncated=\"%s\" is ESCAPE-THEN-SNPRINTF in shape, but the value is bounded — kPrTrims[].dropped is a const table (longest 48 B) plus ';budget-floor-exceeded' (22 B), none of which escapes. Worst case 88 lit + 90 digits + 70 = 248 B + NUL against 256: SEVEN bytes of margin. A fifth trim level or one more attribute crosses it." ),
    # ── src/quality.h ────────────────────────────────────────────────────────────────────────────────────
    ( "src/quality.h", "tail" ):       ( 1, "not-markup", "tail[96]: the qsnap/qheadsnap cache FILENAME; family + two hex digests + %016llx, all fixed-width." ),
    # ── src/serialize.h ──────────────────────────────────────────────────────────────────────────────────
    ( "src/serialize.h", "fitAttr" ):  ( 1, "safe",       "fitAttr[96]: two %zu plus the literal ' over_ceiling=1'." ),
    ( "src/serialize.h", "attr" ):     ( 2, "safe",       "attr[352] x2: the per-symbol metric attrs. Widest 26 lit + 4x10 digits + 11 role + qbuf(<=95) + ambs(<=35: amb= + lpin=) + kbuf(<=23) = 230 B." ),
    ( "src/serialize.h", "tail" ):     ( 2, "safe",       "tail[192] x2: the <d> row tail. Widest 34 lit+digits + inAttr(<=23) + lens(qbuf, <=79) + pure(9) = 145 B." ),
    ( "src/serialize.h", "hdr" ):      ( 2, "safe",       "hdr[64] x2 (packBodies/packOutline): '<b t=\"%s\" l=\"%u\" p=\"' — symTag's fixed vocabulary + a line number. THE ESCAPED PATH IS APPENDED AFTER, on std::string. snprintf-then-append: textbook safe." ),
    ( "src/serialize.h", "db" ):       ( 1, "safe",       "db[64 + kPageDisclosureCap]: <deps files=...> plus pageDisclosure's own capped buffer, sized against that cap by construction." ),
    ( "src/serialize.h", "hb" ):       ( 1, "latent",     "hb[176]: <health .../>; shape= is a fixed vocabulary but acd/nccd are %.1f/%.2f on DOUBLES, formally unbounded. Realistic worst case 66 lit + 60 digits + 24 float + 10 shape = 160 B, ~16 B of margin. Truncation drops the '/>' and orphans the element." ),
    ( "src/serialize.h", "fit" ):      ( 1, "safe",       "fit[160]: the JSON max_tokens/fit_bytes twin; the %s is the literal ',\"over_ceiling\":true'." ),
    ( "src/serialize.h", "num" ):      ( 1, "safe",       "num[64]: ',\"calls_total\":%u,\"calls_capped\":%s,...' — the %s is 'true'/'false'. Worst case 56 B." ),
}

# ── THE POPULATION, and why it is not `"%s" in text` ────────────────────────────────────────────────────
# It was, for one round, and the wave-3 verifier proved that blind: a WIDTH/PRECISION string conversion
# (`%.*s`, `%-20s`, `%.9s`) is a string interpoland and did not match. src/ already used that form in an XML
# OPEN TAG (packtask.h:134). The verifier injected a NEW char[512] emitter interpolating an already-escaped
# path into an XML attribute via `%.*s` — the exact §B14 defect — and this gate reported its counts
# UNCHANGED and ALL PASS. So the population is every STRING CONVERSION.
#   * scanned over the call's STRING LITERALS only, so a `n % size` in an ARGUMENT cannot masquerade as a
#     "% s" conversion (' ' is a legal printf flag, so the naive scan has that false positive);
#   * `%%` is consumed as its own token, so an escaped percent is never read as a conversion;
#   * `%.*s` and `%*s` consume TWO arguments — a precision/width int AND the pointer. That precision is NOT
#     a clamp when it is spelled `int( v.size() )`: it is just how a string_view is printed. A row's
#     arithmetic must bound the VIEW, never assume the `.*` bounds it.
STRLIT = re.compile( r'"(?:[^"\\]|\\.)*"' )
CONV   = re.compile( r'%%|%[-+ #0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|h|ll|l|j|z|t|L)?(?P<conv>[diouxXeEfgGaAcsp])' )

# ── re-derive every snprintf call in src/, balanced-paren, so a call broken across lines is one call ─────
files = subprocess.run( [ "git", "ls-files", "src/" ], cwd = ROOT, capture_output = True, text = True ).stdout.split()
found    = {}
formsAt  = {}
mentions = 0
calls    = 0
for rel in files:
    src = open( os.path.join( ROOT, rel ), "rb" ).read().decode( "utf-8", errors = "replace" )
    mentions += sum( 1 for L in src.split( "\n" ) if "snprintf" in L )
    for m in re.finditer( r"snprintf\s*\(", src ):
        j = m.end() - 1
        depth = 0;  instr = False;  inchr = False;  esc = False
        while j < len( src ):
            c = src[j]
            if   esc:      esc = False
            elif c == "\\": esc = True
            elif instr:
                if c == '"':  instr = False
            elif inchr:
                if c == "'":  inchr = False
            elif c == '"':  instr = True
            elif c == "'":  inchr = True
            elif c == "(":  depth += 1
            elif c == ")":
                depth -= 1
                if depth == 0: break
            j += 1
        text  = " ".join( src[ m.start() : j + 1 ].split() )
        calls += 1
        forms = sorted( set( mm.group( 0 ) for mm in CONV.finditer( "".join( STRLIT.findall( text ) ) )
                             if mm.group( 0 ) != "%%" and mm.group( "conv" ) == "s" ) )
        if not forms: continue
        buf  = text[ text.index( "(" ) + 1 : ].split( "," )[0].strip()
        line = src[ : m.start() ].count( "\n" ) + 1
        found.setdefault( ( rel, buf ), [] ).append( line )
        formsAt.setdefault( ( rel, buf ), set() ).update( forms )

sites  = sum( len(v) for v in found.values() )
widths = sorted( k for k, v in formsAt.items() if any( f != "%s" for f in v ) )
print( "  INFO  re-derived: %d 'snprintf' mentions (lines), %d calls, %d interpolating a STRING (%d of them "
       "via a width/precision form), %d (file,buffer) rows, in %d src/ files"
       % ( mentions, calls, sites, len( widths ), len( found ), len( files ) ) )
for k in widths:
    print( "  INFO  width/precision string conversion: %s buffer '%s' line(s) %s forms %s — invisible to the "
           "pre-wave-3 `\"%%s\" in text` population" % ( k[0], k[1], ",".join( str(x) for x in found[k] ), sorted( formsAt[k] ) ) )

# (S1) every derived site is a known row, with the expected multiplicity
unknown = sorted( k for k in found if k not in TABLE )
if unknown:
    for f, b in unknown:
        no_( "UNCLASSIFIED string-interpolating snprintf: %s buffer '%s' at line(s) %s -- classify it in test/fixedbufsweep.sh's "
             "TABLE (breaching/safe/latent/not-markup) and, if the escaper runs BEFORE the buffer, compose on "
             "std::string instead (see the FIXED-BUFFER RULE above escapeXml in src/serialize.h)"
             % ( f, b, ",".join( str(x) for x in found[ (f,b) ] ) ) )
else:
    ok_( "(S1) all %d string-interpolating snprintf call sites in src/ are classified (%d table rows)"
         % ( sum( len(v) for v in found.values() ), len( TABLE ) ) )

for key, ( n, cls, why ) in sorted( TABLE.items() ):
    got = len( found.get( key, [] ) )
    if got == 0:
        no_( "(S2) STALE table row: %s buffer '%s' matches nothing in source -- delete the row" % key )
    elif got != n:
        no_( "(S2) %s buffer '%s': table says %d call site(s), source has %d (lines %s) -- update the row"
             % ( key[0], key[1], n, got, ",".join( str(x) for x in found[key] ) ) )
if not bad:
    ok_( "(S2) no stale or miscounted table rows" )

# (S6) THE COUNTS ARE ASSERTED, not narrated. Until wave 3 this gate's own header carried "after the 8
# conversions: 153 'snprintf' mentions" while the gate PRINTED 154 — stale in the very merge that landed it,
# which is precisely the "count in a comment nobody re-derives" §B4 and this file exist to prevent. A number
# that is printed but not checked is the thing this round has now caught four times. So the numbers live
# HERE, in one place, and drifting one reds the gate with the new value already spelled out.
# RE-PIN 2026-07-30 (§B11.3, the edit-check fold disclosure). mentions 154 -> 155 and calls 136 -> 137: a
# CONSTANT +1 on both, which is the signature of a single fixed-size addition, and it is exactly that —
# `std::snprintf( defsAttr, sizeof( defsAttr ), " defs=\"%zu\"", … )` in editcheck.h. Re-derived from the
# diff rather than from the delta: the src/ diff adds two snprintf LINES and removes one, and the
# removed/added pair is the SAME `callersOpen` call with `incompatible="%zu"` appended to its format, so the
# net new CALL is one. editcheck.h itself goes 4 -> 5 mentions, which is that same one call. sites/rows are
# unmoved because the new call interpolates only %zu — it is not a string-interpolating site, so it neither
# joins the 30 nor needs a TABLE row, and (S1)/(S2) both stayed green across the change.
EXPECTED = { "mentions": 217, "calls": 195, "sites": 41, "rows": 28, "widthforms": 3 }   # 2026-09-04 (capture-audit L5, H6/F2): +1 call/+1 mention — packLego's iface start-tag snprintf became an if/else PAIR so the TARGETED form can carry defs= (serialize.h ~5460). Re-derived from the diff, not from the delta: one snprintf line became two, both into the SAME `char hdr[64]` (widened from 48 for the extra ` defs="%zu"`), and both interpolate only %zu — no %s, nothing escaped — so neither joins the string-interpolating population and sites/rows are unmoved. (S1)/(S2) stayed green across the change
#            2026-09-03 (Phase 5 external= round): +1 call/+1 mention — the JSON header's `"external":%zu,` snprintf into the existing hdr[256] (one %zu, ≤ 32 B, the `"locality_pinned":%zu,` twin beside it); no %s, nothing escaped — re-read and sized before this pin
#            2026-09-03 (round 5 merge): mentions 213 -> 216 with calls/sites/rows UNCHANGED. Re-read, not re-counted:
#            all three new mentions are DATA, not buffers -- src/externalnames.h lists "snprintf"/"vsnprintf" as C stdlib
#            NAMES the external-name veto recognises, and its provenance comment quotes <stdio.h>'s contents. No new
#            snprintf CALL and no new fixed buffer entered src/ in this round beyond the one Phase 5 site already rowed.
# 2026-09-03 (round 4 merge): +1 call/+1 mention — quality.h ack-ledger lockfile name "ripwire-sidecar-%016llx.lock" into a sized buffer, bounded hex (re-read, not just counted)
derived  = { "mentions": mentions, "calls": calls, "sites": sites, "rows": len( found ), "widthforms": len( widths ) }
drift    = { k: ( EXPECTED[k], derived[k] ) for k in EXPECTED if EXPECTED[k] != derived[k] }
if drift:
    no_( "(S6) the pinned enumeration has drifted: %s — re-derive the TABLE against the new population, then "
         "set EXPECTED in test/fixedbufsweep.sh to { %s }. Do not update the number without re-reading the "
         "sites it counts: that is how this gate's own header rotted."
         % ( ", ".join( "%s pinned %d, source has %d" % ( k, a, b ) for k, ( a, b ) in sorted( drift.items() ) ),
             ", ".join( '"%s": %d' % ( k, derived[k] ) for k in sorted( derived ) ) ) )
else:
    ok_( "(S6) the enumeration is ASSERTED and holds: %d mentions, %d calls, %d string-interpolating sites "
         "(%d via a width/precision form), %d table rows" % ( mentions, calls, sites, len( widths ), len( found ) ) )

# (S1b) nothing is allowed to be classified 'breaching'
breaching = [ k for k, v in TABLE.items() if v[1] == "breaching" ]
if breaching:
    no_( "(S1b) %d site(s) still classified 'breaching': %s" % ( len( breaching ), breaching ) )
else:
    ok_( "(S1b) zero sites classified 'breaching'" )

# (S3) the six §B14 conversions stay converted: these (file, buffer) pairs must NOT reappear
CONVERTED = [ ( "src/editcheck.h", "head" ), ( "src/editcheck.h", "row" ),
              ( "src/packtask.h",  "head" ), ( "src/packtask.h",  "row" ),
              ( "src/serialize.h", "line" ), ( "src/serialize.h", "stats" ),
              ( "src/serialize.h", "partAttr" ), ( "src/serialize.h", "rb" ) ]
back = [ k for k in CONVERTED if k in found ]
if back:
    for f, b in back:
        no_( "(S3) §B14 REGRESSION: %s buffer '%s' is a fixed char[] with a string interpoland again (line %s)"
             % ( f, b, found[ (f,b) ] ) )
else:
    ok_( "(S3) all 8 §B14 conversions still compose on std::string (6 breaching + 2 latent, editcheck/packtask/serialize)" )

# (S4) §B4 anti-rot: serialize.h's stated CALL-SITES count for xmlCommentText == the re-derived count.
ser = open( os.path.join( ROOT, "src/serialize.h" ) ).read()
m   = re.search( r"^//\s+CALL-SITES:\s*(\d+)\s*$", ser, re.M )
if not m:
    no_( "(S4) serialize.h has no '// CALL-SITES: N' line above xmlCommentText -- the §B4 enumeration is unstated again" )
else:
    stated = int( m.group( 1 ) )
    live   = 0
    for rel in files:
        s = open( os.path.join( ROOT, rel ), "rb" ).read().decode( "utf-8", errors = "replace" )
        for mm in re.finditer( r"\bxmlCommentText\s*\(", s ):
            # a CALL, not a mention. Two exclusions, both of which this gate got wrong on its first run:
            #   * the definition itself (`inline std::string xmlCommentText(`);
            #   * every occurrence inside a `//` comment — the name appears in prose across five files
            #     ("xmlCommentText (serialize.h) is the ONE scrub"), and a bare `git grep -c` counts those
            #     four extra hits as call sites. Counting mentions instead of calls is the same defect this
            #     arm exists to catch, one level up.
            lineStart = s.rfind( "\n", 0, mm.start() ) + 1
            before    = s[ lineStart : mm.start() ]
            if "//" in before: continue
            if "inline" in before: continue
            live += 1
    if stated == live:
        ok_( "(S4) xmlCommentText's stated CALL-SITES (%d) == the re-derived count -- §B4's 'all six' cannot rot again" % stated )
    else:
        no_( "(S4) serialize.h says 'CALL-SITES: %d' for xmlCommentText, source has %d -- update the LIST and the number "
             "together (this is exactly the rot §B4 recorded: a count in a comment that nobody re-derives)" % ( stated, live ) )

sys.exit( bad )
PY
[ $? -eq 0 ] || fail=1

# ── (S5) LIVE: the six converted emitters at a corpus path wide enough to have broken them ──────────────
# A static gate proves the SHAPE; only a run proves the FIX. Same sandbox shape test/det-gate.sh's width arm
# uses, in pure shell so this gate has no more dependencies than the sweep above.
WDIR="$TMP/wide"; WD="$WDIR"
WSEG="$( printf 'd%.0s' $( seq 1 60 ) )"
mkdir -p "$WDIR"
while [ "${#WD}" -lt 580 ]; do
    if mkdir -p "$WD/$WSEG" 2>/dev/null; then WD="$WD/$WSEG"; else break; fi
done

if [ "${#WD}" -lt 520 ]; then
    printf '  SKIP  (S5) live width arm — filesystem capped the sandbox path at %s B (need >=520)\n' "${#WD}"
elif ! command -v xmllint >/dev/null 2>&1; then
    printf '  SKIP  (S5) live width arm — xmllint not installed\n'
else
    cat > "$WD/w.cpp" <<'WEOF'
int helperOne( int a ) { return a + 1; }
int tgt( int a, int b ) { return helperOne( a ) + b; }
int callerA( int x ) { return tgt( x, 1 ); }
int callerB( int x ) { return tgt( x, 2 ) + callerA( x ); }
WEOF
    mkdir -p "$WD/test"
    printf 'int test_tgt() { return tgt( 1, 2 ); }\n' > "$WD/test/tgt_test.cpp"

    live_case(){
        label="$1"; shift
        "$BIN" "$WDIR" "$@" --no-cache >"$TMP/live.xml" 2>/dev/null
        if [ ! -s "$TMP/live.xml" ]; then no "(S5) $label produced no output at width"; return; fi
        xmllint --noout "$TMP/live.xml" 2>"$TMP/live.lint" \
            && ok "(S5) $label at a ${#WD} B corpus path — xmllint clean" \
            || { no "(S5) $label at width — xmllint rejected the output at exit 0 (a fixed buffer cut inside the markup)"; head -3 "$TMP/live.lint"; }
    }
    live_case "--edit-check (sites 1-2: <edit-check> head, <c> row)"        --edit-check=tgt
    live_case "--pack-task (sites 3-5: <s> d1, <s> far, <test> + runner)"   --pack-task="tgt helper one"
    live_case "--for --with-graph (site 6: mermaid node line)"              --for=tgt --with-graph

    # site 6 is the "well-formed but says something false" member: it lives inside appendCdataSafe, so it
    # never breached G4 — the tell is that a truncated node label lost its closing `"]` AND its newline and
    # glued the next declaration on. Assert the SHAPE, not just the parse: every mermaid node line must end
    # in `"]` and each declares exactly one node.
    # NOT an awk range on /^flowchart LR/: the whole XML document is ONE line (G4 forbids '\n' outside
    # CDATA), so `flowchart LR` sits mid-line behind `<![CDATA[` and never matches a line anchor — the range
    # selected nothing and the arm passed on the BROKEN binary. The node declarations themselves DO start
    # their own lines (inside the CDATA), so match those directly, and require at least one.
    "$BIN" "$WDIR" --for=tgt --with-graph --no-cache 2>/dev/null >"$TMP/graph.xml"
    merm_n=$(     grep -cE '^n[0-9]+\['            "$TMP/graph.xml" || true )
    merm_bad=$(   grep -E  '^n[0-9]+\['            "$TMP/graph.xml" | grep -cvE '"\]$' || true )
    merm_glued=$( grep -cE '^n[0-9]+\[.*\].*n[0-9]+' "$TMP/graph.xml" || true )
    if [ "$merm_n" -lt 2 ]; then
        no "(S5) mermaid arm found only $merm_n node declaration(s) — it is not measuring the graph it claims to"
    elif [ "$merm_bad" = 0 ] && [ "$merm_glued" = 0 ]; then
        ok "(S5) all $merm_n mermaid node lines close with \"] and none glues a second declaration on (site 6)"
    else
        no "(S5) mermaid corruption at width: $merm_bad of $merm_n node line(s) unterminated, $merm_glued glued"
    fi
fi

echo
[ "$fail" = 0 ] && echo "ALL PASS" || echo "SOME CHECKS FAILED"
exit "$fail"
