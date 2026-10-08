#!/usr/bin/env bash
# pincensuscheck.sh — the S6-C SILENT-PIN CENSUS surface gate (`--pin-census=FILE`).
#
#   test/pincensuscheck.sh                    # uses build/ripwire on test/pincensusfix
#   RIPWIRE_BIN=asan/ripwire test/pincensuscheck.sh
#
# WHY THIS GATE EXISTS. `src/graph.h`'s S6-C locality tie-break resolves a still-ambiguous call to the
# candidate whose canonical id shares the longest whole-SEGMENT prefix with the caller's, and when that
# leaves exactly one survivor it emits a CONFIDENT edge and deliberately does NOT increment `amb=`. The
# map's serialized form is `<c n="NAME"/>` — a callee NAME with no target identity — so nothing in the
# shipped output distinguishes a locality-pinned guess from a qualified, receiver-narrowed or otherwise
# evidence-backed resolution. `bench/scip_amb_precision.py` inherits that blindness: it groups by name
# collision, and a pinned site scores 1.0 by construction whether the pin was right or wrong.
#
# The census is the instrument that ends the blindness: an eval-only, flag-gated side file naming, per
# decided call site, the caller's canonical id, the callee name, the MECHANISM that decided it, and the
# canonical id of every surviving target. Arms (A) and (D) pin the SILENCE itself so a future change that
# quietly starts (or stops) counting these pins in `amb=` cannot pass; arms (C)/(D) pin the label's
# discrimination; (E)/(F) pin G5 additivity and determinism; (G) pins the oracle side of the join.
#
# THE FIXTURE (test/pincensusfix/, 2 Kotlin files, ~40 lines; Python until FE-A, whose bare call reaches no method —
# test/falseedgecheck.sh) reproduces both shapes in the smallest form:
#   pinned.kt — `Alpha.run` bare-calls `helper()`; `Alpha.helper` and its BASE `Beta.helper` both live in this
#               file (Beta became Alpha's base with FE-B, whose implicit receiver proves only the class and its
#               bases), so tier 1 keeps BOTH and S6-C decides: `pinned.kt::Alpha::` beats `pinned.kt::Beta::`.
#               ONE edge, NO `amb=` — the silent pin.
#   tied.kt   — `Eps.go` bare-calls `other()`; `Gamma.other` and `Delta.other` are SIBLINGS, so both
#               share exactly `tied.kt::` and NEITHER is more local. The tier stays full, the call
#               splits, `amb=` counts it — the honest control.
#
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
CORPUS="$ROOT/test/pincensusfix"
SCIPFIX="$ROOT/test/scipfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$CORPUS" ] || { echo "fixture missing: $CORPUS"; exit 2; }

echo "pincensuscheck: BIN=$BIN  CORPUS=$CORPUS"

# ── (A) THE SILENCE, reproduced — the subject of the census, asserted on the shipped map ───────────
# This arm is deliberately about CURRENT behaviour: the locality pin emits one confident edge and does
# not raise `amb=`. It is the documented S6-C contract; a change that alters it must come with its own
# registered justification, and this arm is where that shows up.
# L1 (2026-09-19): the CLI default legend is compact and its prose spells "symbols=:"; (K) reads the header
# count by first match, so this map asks for the full legend (rows are byte-identical across postures).
MAP="$( "$BIN" "$CORPUS" --no-cache --legend=full 2>/dev/null )"

# ── THE LOOKUP IS BOUND TO ITS FILE (PR #215 review, CodeRabbit 5191303552) ────────────────────────
# Row 6 (2026-09-12) replaced the row's path-repeating id="PATH::SCOPE::NAME" with sc="SCOPE" alone, and
# these arms were re-keyed onto n= plus sc= over the WHOLE map. That reads the right row on this fixture
# by LUCK — Alpha exists only in pinned.kt and Eps only in tied.kt, so nothing else can match — but it
# stopped PROVING that Alpha::run belongs to pinned.kt or Eps::go to tied.kt, which is half of what the
# subject of this census is. The canonical id composes as p::sc::n with p= coming from the enclosing
# <f p=>, so the lookup composes it the same way: the row must sit inside THAT file's block and carry
# THAT sc= and THAT n=. index() throughout, never a regex, so a '.' in a path is a '.'.
fileBlock()   # $1=map  $2=path  ->  that file's <f p="…"> … </f> block, nothing else
{
    printf '%s' "$1" | awk -v p="$2" '
        BEGIN { RS = "<"; ORS = "" }
        index( $0, "f p=\"" ) == 1 { inf = ( index( $0, "f p=\"" p "\"" ) == 1 ) }
        inf                         { print "<" $0 }
        index( $0, "/f>" )   == 1   { inf = 0 }
    '
}
fileScopedRow()   # $1=map  $2=path  $3=scope  $4=name  ->  the <s …> row(s) for p::sc::n, or empty
{
    fileBlock "$1" "$2" | awk -v sc="$3" -v n="$4" '
        BEGIN { RS = "<" }
        index( $0, "s " ) == 1 && index( $0, " n=\"" n "\"" ) > 0 && index( $0, " sc=\"" sc "\"" ) > 0 { print }
    '
}
RUN_ROW="$( fileScopedRow "$MAP" "pinned.kt" "Alpha" "run" )"
GO_ROW="$(  fileScopedRow "$MAP" "tied.kt"   "Eps"   "go"  )"
[ "$( printf '%s\n' "$RUN_ROW" | grep -c 's ' )" = 1 ] \
    && ok "(A) pinned.kt::Alpha::run resolves to exactly ONE row, p= sc= and n= all read" \
    || no "(A) pinned.kt::Alpha::run does not resolve to one row inside <f p=\"pinned.kt\">: $RUN_ROW"
[ "$( printf '%s\n' "$GO_ROW" | grep -c 's ' )" = 1 ] \
    && ok "(A) tied.kt::Eps::go resolves to exactly ONE row, p= sc= and n= all read" \
    || no "(A) tied.kt::Eps::go does not resolve to one row inside <f p=\"tied.kt\">: $GO_ROW"
# …and the CONTROL that makes those two arms mean something: the same lookup with the WRONG p= must
# find NOTHING. A whole-map grep on n=/sc= passes this fixture and can never fail it, which is exactly
# why it stopped being evidence. If the composition ever loses its p= half, these two go red.
[ -z "$( fileScopedRow "$MAP" "tied.kt" "Alpha" "run" )" ] \
    && ok "(A) control: Alpha::run is NOT found under p=\"tied.kt\" — the arm reads the path, not the name alone" \
    || no "(A) control: Alpha::run matched under the WRONG path — this lookup is not reading p="
[ -z "$( fileScopedRow "$MAP" "pinned.kt" "Eps" "go" )" ] \
    && ok "(A) control: Eps::go is NOT found under p=\"pinned.kt\"" \
    || no "(A) control: Eps::go matched under the WRONG path — this lookup is not reading p="

if printf '%s' "$RUN_ROW" | grep -q 'amb='; then
    no "(A) pinned.kt::Alpha::run carries amb= — the locality pin is no longer silent: $RUN_ROW"
else
    ok "(A) the locality pin is SILENT — pinned.kt::Alpha::run carries no amb="
fi
# the edge walk starts from that same file-bound row, not from the first n="run" anywhere in the map
N_HELPER="$( fileBlock "$MAP" "pinned.kt" | tr '>' '\n' | awk '/n="run" sc="Alpha"/{f=1} f{print} /\/s/{if(f)exit}' | grep -c 'n="helper"' )"
[ "$N_HELPER" = 1 ] && ok "(A) the pin emitted ONE confident edge (not a split)" \
    || no "(A) pinned.kt::Alpha::run emitted $N_HELPER helper edges, want 1"
printf '%s' "$GO_ROW" | grep -q 'amb="1"' && ok "(A) the tied control is HONEST — tied.kt::Eps::go carries amb=\"1\"" \
    || no "(A) tied.kt::Eps::go does not carry amb=\"1\": $GO_ROW"
printf '%s' "$MAP" | grep -q 'ambiguous=1 ' && ok "(A) header ambiguous=1 — the pin contributes ZERO to the disclosed gauge" \
    || no "(A) header ambiguous= is not 1: $( printf '%s' "$MAP" | grep -o 'ambiguous=[0-9]*' | head -1 )"

# ── (B) the census surface exists and declares itself ─────────────────────────────────────────────
"$BIN" "$CORPUS" --pin-census="$TMP/c1.tsv" --no-cache >"$TMP/map1" 2>"$TMP/err1"
rc=$?
if [ "$rc" = 0 ]; then ok "(B) --pin-census exits 0"; else { no "(B) --pin-census exited $rc"; sed 's/^/          /' "$TMP/err1"; }; fi
if [ -s "$TMP/c1.tsv" ]; then
    ok "(B) census file written ($( wc -l <"$TMP/c1.tsv" | tr -d ' ' ) lines)"
else
    no "(B) no census file at $TMP/c1.tsv"
fi
head -1 "$TMP/c1.tsv" 2>/dev/null | grep -q '^# ripwire pin-census v3' \
    && ok "(B) census declares its own format in a header line" \
    || no "(B) census header line missing/unrecognized: $( head -1 "$TMP/c1.tsv" 2>/dev/null )"

# ── (C) THE POINT — the census names the pinned site, its mechanism, and its TARGET IDENTITY ──────
# The map says `<c n="helper"/>`. The census must say WHICH helper, and that locality is what decided.
PIN_ROW="$( grep -E '^C	locality	' "$TMP/c1.tsv" 2>/dev/null | grep 'pinned.kt::Alpha::run' )"
if [ -n "$PIN_ROW" ]; then
    ok "(C) the locality-pinned site is labelled: $PIN_ROW"
else
    no "(C) no 'C<TAB>locality' row for pinned.kt::Alpha::run — the census cannot see the pin"
    grep -n 'Alpha::run' "$TMP/c1.tsv" 2>/dev/null | sed 's/^/          /'
fi
printf '%s' "$PIN_ROW" | grep -q 'pinned.kt::Alpha::helper' \
    && ok "(C) the census carries the pinned TARGET's canonical id (the identity <c n=.../> omits)" \
    || no "(C) the pinned row does not name pinned.kt::Alpha::helper — no identity to join an oracle against"
printf '%s' "$PIN_ROW" | grep -q 'pinned.kt::Beta::helper' \
    && no "(C) the pinned row also lists Beta::helper — that candidate was DROPPED, not emitted" \
    || ok "(C) the pinned row lists exactly the surviving target"

# ── (D) mutation control — the label DISCRIMINATES (a tie is not a pin) ───────────────────────────
TIE_ROW="$( grep -E '^C	split	' "$TMP/c1.tsv" 2>/dev/null | grep 'tied.kt::Eps::go' )"
if [ -n "$TIE_ROW" ]; then
    ok "(D) the full-tie site is labelled split, not locality: $TIE_ROW"
else
    no "(D) no 'C<TAB>split' row for tied.kt::Eps::go — the label does not discriminate, so (C) means nothing"
    grep -n 'Eps::go' "$TMP/c1.tsv" 2>/dev/null | sed 's/^/          /'
fi
printf '%s' "$TIE_ROW" | grep -q 'tied.kt::Gamma::other' && printf '%s' "$TIE_ROW" | grep -q 'tied.kt::Delta::other' \
    && ok "(D) the split row lists BOTH surviving targets" \
    || no "(D) the split row does not list both Gamma::other and Delta::other"
grep -E '^C	locality	' "$TMP/c1.tsv" 2>/dev/null | grep -q 'tied.kt::Eps::go' \
    && no "(D) tied.kt::Eps::go is ALSO labelled locality — the label is not exclusive" \
    || ok "(D) no locality label on the tied site"

# ── (E) G5 — the flag is purely additive: stdout is byte-identical with and without it ────────────
"$BIN" "$CORPUS" --no-cache >"$TMP/map0" 2>/dev/null
if cmp -s "$TMP/map0" "$TMP/map1"; then
    ok "(E) stdout byte-identical with and without --pin-census (G5: every flag is purely additive)"
else
    no "(E) --pin-census CHANGED the map — the census surface is not output-invariant"
    diff <( fold -w120 "$TMP/map0" ) <( fold -w120 "$TMP/map1" ) | head -6 | sed 's/^/          /'
fi

# ── (F) determinism — the census is a contract, not a nicety ──────────────────────────────────────
"$BIN" "$CORPUS" --pin-census="$TMP/c2.tsv" --no-cache >/dev/null 2>&1
"$BIN" "$CORPUS" --pin-census="$TMP/c3.tsv" --no-cache >/dev/null 2>&1
if cmp -s "$TMP/c1.tsv" "$TMP/c2.tsv" && cmp -s "$TMP/c2.tsv" "$TMP/c3.tsv"; then
    ok "(F) three census runs are byte-identical"
else
    no "(F) the census is not deterministic across runs"
    diff "$TMP/c1.tsv" "$TMP/c2.tsv" | head -6 | sed 's/^/          /'
fi

# ── (G) the ORACLE side — under --scip the census carries SCIP's covered sites in the SAME id space ─
# Without this the census has one side of the join and nothing to join it to. test/scipfix ships a
# generated index whose `run` -> `handler` site SCIP pins to alpha.cpp.
if [ -f "$SCIPFIX/index.scip" ]; then
    "$BIN" "$SCIPFIX" --exclude=make_index.py --scip="$SCIPFIX/index.scip" --pin-census="$TMP/o.tsv" --no-cache >/dev/null 2>&1
    ORA="$( grep -E '^O	' "$TMP/o.tsv" 2>/dev/null | grep 'handler' )"
    if [ -n "$ORA" ]; then
        ok "(G) the census carries SCIP oracle rows: $ORA"
    else
        no "(G) no 'O' oracle rows under --scip — the census cannot be joined against ground truth"
        head -5 "$TMP/o.tsv" 2>/dev/null | sed 's/^/          /'
    fi
    printf '%s' "$ORA" | grep -q 'alpha.cpp' \
        && ok "(G) the oracle row names SCIP's target by canonical id (alpha.cpp), not by name" \
        || no "(G) the oracle row does not carry alpha.cpp's canonical id"
    grep -cE '^O	' "$TMP/o.tsv" >/dev/null 2>&1 && grep -qE '^C	' "$TMP/o.tsv" \
        && ok "(G) both sides (C decisions + O oracle) are present in one census" \
        || no "(G) the --scip census is missing one of the two row kinds"
else
    no "(G) test/scipfix/index.scip missing — the oracle arm cannot run (regenerate: python3 test/scipfix/make_index.py test/scipfix/index.scip)"
fi

# ── (I) the join's load-bearing assumption: identities are STABLE across the two runs ─────────────
# The census is measured by joining a PLAIN run (what the resolver decided) to a --scip run (what the
# index says). That join is only meaningful if a symbol carries the same identity in both, so the
# assumption is asserted here rather than assumed: NodeIds come from the sorted crawl at ingest, before
# any resolution, and --scip changes nothing upstream of that. If this arm ever goes red, every precision
# number joined this way is void — which is why it is a gate and not a comment.
if [ -f "$SCIPFIX/index.scip" ]; then
    "$BIN" "$SCIPFIX" --exclude=make_index.py --pin-census="$TMP/plain.tsv" --no-cache >/dev/null 2>&1
    PLAIN_ID="$( awk -F'\t' '$1=="C" && $7=="handler" {print $6; exit}' "$TMP/plain.tsv" 2>/dev/null )"
    SCIP_ID="$( awk -F'\t' '$1=="O" && $3=="handler" {print $2; exit}' "$TMP/o.tsv" 2>/dev/null )"
    if [ -n "$PLAIN_ID" ] && [ "$PLAIN_ID" = "$SCIP_ID" ]; then
        ok "(I) the caller identity is byte-identical in the plain and --scip censuses ($PLAIN_ID)"
    else
        no "(I) caller identity DIFFERS between runs — plain='$PLAIN_ID' scip='$SCIP_ID'; the join is void"
    fi
    printf '%s' "$PLAIN_ID" | grep -q '#' \
        && ok "(I) identities carry the #NODEID handle (not a bare, name-keyed id)" \
        || no "(I) identity '$PLAIN_ID' has no #NODEID handle — the join degrades to name matching"
fi

# ── (J) the call-site LINE rides on every C row (format v2) ───────────────────────────────────────
# WHY. Phase-3 of the census (docs/EVALS.md "The census, RUN") found coverage — SCIP speaking on only
# 38% of locality-pinned sites — to be the binding constraint on n, and the loss sits in the (file,line)
# join `src/scip.h::buildScipOverlay` performs. Diagnosing WHICH lines fail needs the resolver's own
# 1-based call-site line beside each decision; without it the census cannot be joined to a SCIP
# occurrence at all and the failure classes can only be guessed. The line is the LAST column so every
# v1 consumer (`awk $6/$7`, `parts[7]`) keeps reading unchanged.
RUN_LINE="$( awk -F'\t' '$1=="C" && $6 ~ /^pinned\.kt::Alpha::run#/ && $7=="helper" {print $9; exit}' "$TMP/c1.tsv" 2>/dev/null )"
[ "$RUN_LINE" = 15 ] && ok "(J) the pinned site carries its call-site line as column 9 (15)" \
    || no "(J) column 9 of the pinned-site row is '$RUN_LINE', want 15 (pinned.kt:15 is \`return helper()\`)"
GO_LINE="$( awk -F'\t' '$1=="C" && $7=="other" {print $9; exit}' "$TMP/c1.tsv" 2>/dev/null )"
[ "$GO_LINE" = "$( grep -n 'return other()' "$CORPUS/tied.kt" | cut -d: -f1 )" ] \
    && ok "(J) the tied control carries its call-site line too ($GO_LINE)" \
    || no "(J) tied.kt::Eps::go row column 9 is '$GO_LINE', want the \`return other()\` line"
head -1 "$TMP/c1.tsv" 2>/dev/null | grep -q 'line' \
    && ok "(J) the header line names the new column" \
    || no "(J) the header does not declare the line column: $( head -1 "$TMP/c1.tsv" )"

# ── (K) the definition universe rides along as S rows (format v2) ─────────────────────────────────
# WHY. The other half of the SCIP join is the DEF side: `buildScipOverlay` maps a SCIP definition
# occurrence to a ripwire symbol by exact (file, line). Classifying a def-side miss needs every symbol
# ripwire holds with its line — a table no shipped surface lists in full (`--pack-signatures` is a
# top-50 payload). One `S` row per symbol: id (with #NODEID), kind tag, 1-based def line.
S_RUN="$( awk -F'\t' '$1=="S" && $2 ~ /^pinned\.kt::Alpha::run#/ {print $3 "/" $4; exit}' "$TMP/c1.tsv" 2>/dev/null )"
[ "$S_RUN" = "fn/14" ] && ok "(K) S row for pinned.kt::Alpha::run carries kind and def line (fn/14)" \
    || no "(K) S row for pinned.kt::Alpha::run is '$S_RUN', want fn/14"
N_S="$( grep -c '^S	' "$TMP/c1.tsv" )"
N_SYM="$( printf '%s' "$MAP" | grep -o 'symbols=[0-9]*' | head -1 | cut -d= -f2 )"
[ "$N_S" = "$N_SYM" ] && ok "(K) one S row per symbol ($N_S == header symbols=$N_SYM)" \
    || no "(K) $N_S S rows but the map header says symbols=$N_SYM"
grep -q "symbols=$N_SYM" <( tail -1 "$TMP/c1.tsv" ) && ok "(K) the summary line counts the S rows" \
    || no "(K) summary line lacks symbols=$N_SYM: $( tail -1 "$TMP/c1.tsv" )"

# ── (L) a field never holds a row separator: every id and callee is ESCAPED (format v3) ───────────
# WHY. An id can hold a line break verbatim. It first did through a C++ out-of-line member of a class
# template whose template-argument list spans source lines (`SmallVec<T, Alloc,\n GrowingPolicy, N>::grow`);
# that scope is now the bare template name (test/cpptmplscopecheck.sh), so the fixture reaches the same bytes
# through a C++ CONVERSION OPERATOR, whose name is its written type verbatim (`operator Pair<int,\n long>`).
# The map has always escaped it (`n="…&#10;…"`); the census wrote it RAW, so one C row became a 6-field line
# plus a continuation line starting with neither C, S, O nor #, and the S row for the same symbol broke
# the same way. A reader splitting lines drops or mis-keys the site (observed 2026-09-16: exactly one such
# row on a large private C++ corpus). The same exposure had five more spellings, each reproduced below on
# the pre-fix binary: a TAB inside the argument list (a 10-field row), a form feed (a line end to Python's
# splitlines(), and the one case here on the \xHH path with a leading 0), a backslash line splice, CRLF
# source (a raw CR, which Python's text mode also reads as a line end), and a `|` in a PATH — `|` is the
# targets separator, so `pipe|dir/far.hpp::far_helper#N` read back as TWO targets.
#
# THE FIXTURE is generated here, never committed: a directory named `pipe|dir` and CRLF bytes do not
# belong in the tree. The checker decodes and re-encodes with its OWN implementation of the rule the
# census header documents, so the round trip is asserted against the documented rule and not against
# the writer's reading of it; the presence guards read the MAP's sc=, an independent surface, to prove
# each awkward byte really reaches a symbol before the census is judged on it.
ESC="$TMP/esc"
mkdir -p "$ESC/pipe|dir"
printf '#include <cstddef>\nnamespace inplace {\ninline void grow_storage() {}\n}\n' >"$ESC/smallvec.hpp"
printf 'template <class A, class B> struct Pair {};\nclass SmallVec\n{\npublic:\n' >>"$ESC/smallvec.hpp"
printf '    operator Pair<int,\n              long>() const\n    {\n        inplace::grow_storage();\n        return {};\n    }\n' >>"$ESC/smallvec.hpp"
printf '    operator Pair<char, \\\nshort>() const\n    {\n        inplace::grow_storage();\n        return {};\n    }\n' >>"$ESC/smallvec.hpp"
printf '    operator Pair<bool,\tfloat>() const\n    {\n        inplace::grow_storage();\n        return {};\n    }\n' >>"$ESC/smallvec.hpp"
printf '    operator Pair<double,\fint>() const\n    {\n        inplace::grow_storage();\n        return {};\n    }\n};\n' >>"$ESC/smallvec.hpp"
printf 'inline void crlf_sink() {}\r\ntemplate <class A, class B> struct Pair {};\r\nclass Table\r\n{\r\npublic:\r\n    operator Pair<long,\r\n           int>() const\r\n    {\r\n        crlf_sink();\r\n        return {};\r\n    }\r\n};\r\n' >"$ESC/crlf.hpp"
printf 'inline void far_helper() {}\n' >"$ESC/pipe|dir/far.hpp"
printf '#include "pipe|dir/far.hpp"\nvoid near_caller()\n{\n    far_helper();\n}\n' >"$ESC/near.cpp"
cat >"$TMP/censusfields.py" <<'PY'
import re, sys

WIDTH = { b"C": 9, b"S": 4, b"O": 4 }

def rows( data ):
    body = data.split( b"\n" )
    if body and body[ -1 ] == b"":
        body.pop()
    return [ ( i + 1, l ) for i, l in enumerate( body ) if not l.startswith( b"#" ) ]

def misshapen( data ):
    """(line, head) of every non-comment line that is not a C/S/O row with that kind's full field count."""
    return [ ( n, l[ :60 ] ) for n, l in rows( data ) if l[ :2 ] not in ( b"C\t", b"S\t", b"O\t" ) or len( l.split( b"\t" ) ) != WIDTH[ l[ :1 ] ] ]

def decode( field ):
    out, i = bytearray(), 0
    while i < len( field ):
        if field[ i ] != 0x5C:
            out.append( field[ i ] )
            i += 1
            continue
        e = field[ i + 1 : i + 2 ]
        if e in ( b"\\", b"t", b"n", b"r" ):
            out.append( { b"\\": 0x5C, b"t": 0x09, b"n": 0x0A, b"r": 0x0D }[ e ] )
            i += 2
        elif e == b"x" and re.fullmatch( rb"[0-9a-f]{2}", field[ i + 2 : i + 4 ] ):
            out.append( int( field[ i + 2 : i + 4 ], 16 ) )
            i += 4
        else:
            raise ValueError( "undecodable escape at byte %d of %r" % ( i, field ) )
    return bytes( out )

def encode( raw ):
    out = bytearray()
    for b in raw:
        if b == 0x5C:
            out += b"\\\\"
        elif b in ( 0x09, 0x0A, 0x0D ):
            out += { 0x09: b"\\t", 0x0A: b"\\n", 0x0D: b"\\r" }[ b ]
        elif b < 0x20 or b == 0x7C:
            out += b"\\x%02x" % b
        else:
            out.append( b )
    return bytes( out )

def say( passed, text ):
    print( ( "PASS " if passed else "FAIL " ) + text )

mode, tsv = sys.argv[ 1 ], sys.argv[ 2 ]
data = open( tsv, "rb" ).read()
bad = misshapen( data )
say( not bad, "(L) %s: all %d non-comment lines are C/S/O rows with their full field count (C=9 S=4 O=4)%s"
     % ( tsv.rsplit( "/", 1 )[ -1 ], len( rows( data ) ), "" if not bad else "; misshapen: %r" % bad[ :3 ] ) )
if mode == "shape":
    sys.exit( 0 )

xml = open( sys.argv[ 3 ], "rb" ).read()
good = [ l.split( b"\t" ) for n, l in rows( data ) if ( n, l[ :60 ] ) not in bad ]
crows = [ p for p in good if p[ 0 ] == b"C" ]
sids = { p[ 1 ] for p in good if p[ 0 ] == b"S" }

def xmlspell( raw ):
    # escapeXml's rule: TAB/LF/CR become character references, every OTHER C0 byte is scrubbed to a space
    # (xmlSafeByte). So for the form feed the map proves only that the name spans that position; the
    # round-trip verdict, which must decode \x0c out of the census, is what proves the byte itself.
    raw = bytes( b if b >= 0x20 or b in ( 0x09, 0x0A, 0x0D ) else 0x20 for b in raw )
    return raw.replace( b"&", b"&amp;" ).replace( b"<", b"&lt;" ).replace( b">", b"&gt;" ).replace( b"\t", b"&#9;" ).replace( b"\n", b"&#10;" ).replace( b"\r", b"&#13;" )

# (label, the raw caller id before #NODEID, the conversion-operator NAME the map must spell, the callee)
CALLERS = [
    ( "a template-argument list spanning two lines (LF)", b"smallvec.hpp::SmallVec::operator Pair<int,\n              long>",
      b"operator Pair<int,\n              long>", b"grow_storage" ),
    ( "a backslash line splice", b"smallvec.hpp::SmallVec::operator Pair<char, \\\nshort>",
      b"operator Pair<char, \\\nshort>", b"grow_storage" ),
    ( "a TAB inside the argument list", b"smallvec.hpp::SmallVec::operator Pair<bool,\tfloat>",
      b"operator Pair<bool,\tfloat>", b"grow_storage" ),
    ( "a FORM FEED inside the argument list (the \\xHH path, a zero-padded low byte)",
      b"smallvec.hpp::SmallVec::operator Pair<double,\x0cint>",
      b"operator Pair<double,\x0cint>", b"grow_storage" ),
    ( "CRLF source", b"crlf.hpp::Table::operator Pair<long,\r\n           int>", b"operator Pair<long,\r\n           int>", b"crlf_sink" ),
]
for label, raw, name, callee in CALLERS:
    say( b' n="' + xmlspell( name ) + b'"' in xml, "(L) presence: the map's n= holds %s — the fixture reaches the byte" % label )
    hit = [ p for p in crows if p[ 6 ] == callee and re.fullmatch( re.escape( raw ) + rb"#[0-9]+", decode( p[ 5 ] ) ) ]
    if len( hit ) != 1:
        say( False, "(L) %s: want ONE C row whose caller_id decodes to %r, found %d" % ( label, raw, len( hit ) ) )
        continue
    field = hit[ 0 ][ 5 ]
    say( encode( decode( field ) ) == field and field in sids and not re.search( rb"[\x00-\x1f|]", field ),
         "(L) %s: caller_id %s round-trips (decode, re-encode byte-identical), is an S row id verbatim, holds no raw separator"
         % ( label, field.decode( "utf-8", "replace" ) ) )

far = [ p for p in crows if p[ 5 ].startswith( b"near.cpp::near_caller#" ) and p[ 6 ] == b"far_helper" ]
say( b'p="pipe|dir/far.hpp"' in xml, "(L) presence: the map carries p=\"pipe|dir/far.hpp\" — a `|` reaches a target id" )
if len( far ) == 1:
    parts = far[ 0 ][ 7 ].split( b"|" )
    say( len( parts ) == 1 and re.fullmatch( rb"pipe\|dir/far\.hpp::far_helper#[0-9]+", decode( parts[ 0 ] ) ) is not None and parts[ 0 ] in sids,
         "(L) a `|` in a path: the targets field splits on | into ONE id (%s), which decodes to pipe|dir/far.hpp::far_helper and is an S row id"
         % far[ 0 ][ 7 ].decode() )
else:
    say( False, "(L) want ONE near_caller -> far_helper C row, found %d" % len( far ) )

# THE CONSERVATION LINE still closes on the escaped file, and the summary counts what a line reader reads.
disp = dict( kv.split( b"=" ) for kv in re.search( rb"^# dispositions (.*)$", data, re.M ).group( 1 ).split() )
summ = dict( kv.split( b"=" ) for kv in re.search( rb"^# summary (.*)$", data, re.M ).group( 1 ).split() )
buckets = sum( int( v ) for k, v in disp.items() if k != b"calls" )
bound = sum( 1 for p in crows if p[ 1 ] != b"external" )
say( int( disp[ b"calls" ] ) == buckets and disp[ b"unaccounted" ] == b"0" and int( disp[ b"bound" ] ) == bound,
     "(L) dispositions reconcile: calls=%s == bucket sum %d, unaccounted=%s, bound=%s == %d non-external C rows"
     % ( disp[ b"calls" ].decode(), buckets, disp[ b"unaccounted" ].decode(), disp[ b"bound" ].decode(), bound ) )
say( int( summ[ b"rows" ] ) == len( crows ) and int( summ[ b"symbols" ] ) == len( sids ),
     "(L) summary rows=%s symbols=%s == the %d C rows and %d S ids a line reader parses"
     % ( summ[ b"rows" ].decode(), summ[ b"symbols" ].decode(), len( crows ), len( sids ) ) )

# CONTROL: undo ONE escape inside a C ROW of the real census (never a `#` line, whose prose spells the
# escape too) and re-run the identical shape extraction over it. If the splitter could not see a raw line
# break, every PASS above would be a reading of nothing.
m = re.search( rb"^C\t[^\n]*?(\\n)", data, re.M )
mutated = data[ :m.start( 1 ) ] + b"\n" + data[ m.end( 1 ): ] if m else data
say( m is not None and mutated != data and len( misshapen( mutated ) ) >= 1,
     "(L) control: one escape un-done in a real C row -> the same shape check reports %d misshapen line(s)" % len( misshapen( mutated ) ) )
PY
"$BIN" "$ESC" --no-cache --pin-census="$TMP/esc.tsv" >"$TMP/esc.xml" 2>"$TMP/esc.err" || no "(L) the escape-fixture run exited non-zero: $( head -1 "$TMP/esc.err" )"
"$BIN" "$ESC" --no-cache --pin-census="$TMP/esc2.tsv" >/dev/null 2>&1
cmp -s "$TMP/esc.tsv" "$TMP/esc2.tsv" && ok "(L) the escaped census is byte-identical across two runs" \
    || no "(L) the escaped census differs between two runs"
head -1 "$TMP/esc.tsv" 2>/dev/null | grep -q '^# ripwire pin-census v3' && grep -q '^# v3 field escape' "$TMP/esc.tsv" \
    && ok "(L) the header declares format v3 and documents the field escape" \
    || no "(L) the header does not declare v3 + its field escape: $( head -1 "$TMP/esc.tsv" 2>/dev/null )"
# Verdicts go to a FILE and are read back on fd 3, never through a pipe: a row printed in a pipeline
# subshell would set fail=1 in a copy of this shell and exit 0. The count is pinned so a checker that
# stops early cannot shrink the arm to the verdicts it happened to reach.
python3 "$TMP/censusfields.py" escape "$TMP/esc.tsv" "$TMP/esc.xml" >"$TMP/esc.verdicts" 2>&1; prc=$?
python3 "$TMP/censusfields.py" shape "$TMP/c1.tsv" >>"$TMP/esc.verdicts" 2>&1 || prc=1
if [ -f "$TMP/o.tsv" ]; then
    python3 "$TMP/censusfields.py" shape "$TMP/o.tsv" >>"$TMP/esc.verdicts" 2>&1 || prc=1
else
    no "(L) no --scip census from (G) — the O-row shape cannot be checked"
fi
while IFS= read -r v <&3; do
    case "$v" in
        "PASS "*) ok "${v#PASS }" ;;
        "FAIL "*) no "${v#FAIL }" ;;
        *)        no "(L) checker: $v" ;;
    esac
done 3<"$TMP/esc.verdicts"
N_VERDICTS="$( grep -cE '^(PASS|FAIL) ' "$TMP/esc.verdicts" )"
[ "$prc" = 0 ] && [ "$N_VERDICTS" = 18 ] && ok "(L) the field checker ran to the end (18 verdicts, exit 0)" \
    || no "(L) the field checker exited $prc with $N_VERDICTS verdicts, want 0 and 18"

# ── (H) an empty value is REFUSED, never silently treated as "no census" ──────────────────────────
"$BIN" "$CORPUS" --pin-census= --no-cache >/dev/null 2>"$TMP/empty.err"
rc=$?
if [ "$rc" != 0 ] && grep -qi 'pin-census' "$TMP/empty.err"; then
    ok "(H) --pin-census= (empty) is refused by name"
else
    no "(H) --pin-census= (empty) was not refused (rc=$rc): $( head -1 "$TMP/empty.err" )"
fi

[ "$fail" = 0 ] && { echo "pincensuscheck: OK"; exit 0; }
echo "pincensuscheck: FAILURES ABOVE"; exit 1
