#!/usr/bin/env bash
# readmedriftcheck.sh — README.md's ADVERTISED COUNTS must not drift from the things that justify
# them: the "N flags" claim from the binary's own --help table (arms A-D), and the lineage sentence's
# repository/paper/survey counts from docs/LINEAGE.md's own tables (arm E).
#
# WHY. README.md:15 states a flag count in prose ("Around that core sit N long flags advertised in
# `--help`…"). Nothing else in the suite checks that number against reality, so it silently goes
# stale the moment a flag is added, renamed, or removed — the exact failure showcasecapturecheck's
# caption arm exists to catch for a different document. This gate is that same discipline applied to
# the README's own flag-count sentence.
#
# DERIVATION. Reuses flagsurfacecheck.sh's own harvest idiom verbatim: `--help` text scraped with
# `grep -oE '\-\-[a-z][a-z0-9-]+' | sort -u`, i.e. anchored on the "--name" TOKEN, not on its column
# position. An earlier version of this gate anchored on a 4-space-indented line start (`^    --`),
# which undercounts — --help writes optional/alternative forms as "[--around-depth=N]" or
# "(--regex)", which a whitespace anchor misses entirely, and flagsurfacecheck.sh's own header
# comment warns against exactly this trap. Three in-tree derivations of "the flag count" existed at
# once (this gate's old 104, docs/docs_commands_build.py's 102, flagsurfacecheck.sh's 123) because
# each scraped --help slightly differently; arm (D) below pins this gate's derivation to
# flagsurfacecheck.sh's so the two can never drift apart again. (docs_commands_build.py's 102 counts
# a different, deliberately narrower thing — its own documented-vs-binary set — and is left alone;
# see CLAUDE.md.)
#
# Arms:
#   (A) derive the distinct flag count from --help and confirm it is a sane positive number
#   (B) the DRIFT arm — README.md's stated count must equal the derived count
#   (C) MUTATION CONTROL for (B) — a copy of README.md with a deliberately wrong count must be
#       caught red by the same comparison, proving the arm can actually see a mismatch
#   (D) CROSS-CHECK — this gate's derived count must equal flagsurfacecheck.sh's own harvested count
#       of the SAME --help text, so the two scripts' notions of "the flag count" can never disagree
#   (E) the LINEAGE arm — README.md's "M repositories and P papers … survey of N tools" sentence must
#       equal the row counts of docs/LINEAGE.md's own tables. Same discipline as (B), different
#       ground truth: an advertised number is an ENUMERATED number, so the enumeration is the
#       authority and the prose is checked against it. Sub-arms E1-E8 below; E4 is (E)'s mutation
#       control, exactly as (C) is (B)'s, and E6/E7 carry their own.
#   (F) the GATE-SCRIPT arm — README's "N gate scripts" count vs test/regression.sh's loop (F1-F3)
#   (G) the COLD-START arm — README's "start here" invocation must carry --max-tokens=N, and that N must
#       keep the bare map's head under 4,500 est_tokens (G1 presence, G2 property, G3 mutation, G4 promise)
#
# WHY E6-E8 EXIST. A count can be arithmetically correct and still be a lie about a SET. LINEAGE.md
# claims its folded tables and its surveyed table are DISJOINT — that is what makes "27 folded plus
# 220 surveyed" an addition rather than a subset relation, and it is the whole justification for
# printing both numbers in one sentence. Nothing checked it, and it was false in four places at once
# (Aider, Cody and octocode were folded rows repeated in the survey; RepoGraph was a §2 paper row
# repeated there too). E7's failure mode is cheaper still: `comby` was listed in two different
# surveyed rows, so N counted one tool twice and every row's n stayed internally consistent while
# doing it — E3 cannot see that, because E3 only ever looks at one row. E8 checks the other half of
# the honesty rule: a folded row must point at a real flag or source file, so the paths it points at
# have to exist.
#
# WHY (E) EXISTS AT ALL. Three counts in one README sentence, each justified by a different table in
# a different file, is the drift shape this suite has been bitten by twice (the flag count above; the
# docs/README.md entry count). A count nobody re-derives is a count that is already wrong and has not
# been caught yet. LINEAGE.md's header repeats the same three numbers in prose, so E5 checks THAT
# against the same tables too — a document whose own summary disagrees with its own rows is worse
# than one that never summarised.
#
# LINEAGE DERIVATION. Section-scoped markdown table rows, structural not textual:
#   M = body rows of the table under the "Folded" heading                       (repositories)
#   P = body rows under "Classic papers" + body rows under "Modern research"    (papers)
#   N = the sum of the trailing `n` column of the "Surveyed" table              (tools surveyed)
# A body row is a line starting with `|` that is neither the header row (the first such line in the
# section) nor the `| --- |` separator. Deriving N from a SUMMED COLUMN rather than by counting names
# across a whole table is what makes the number auditable per row; E3 then proves each row's declared
# `n` equals the count of its own comma-separated names, so the column cannot be quietly padded.
#
# Usage:  bash test/readmedriftcheck.sh      [RIPWIRE_BIN=path/to/binary]
# Exit:   0 = clean · 1 = at least one arm failed · 2 = usage / missing prerequisite

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
README="$ROOT/README.md"
LINEAGE="$ROOT/docs/LINEAGE.md"
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "readmedriftcheck: no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -f "$README" ] || { echo "readmedriftcheck: missing $README"; exit 2; }
[ -f "$LINEAGE" ] || { echo "readmedriftcheck: missing $LINEAGE — arm (E) has no ground truth to check against"; exit 2; }

HELP="$( "$BIN" --help 2>&1 )"

# ── (A) derive the distinct flag count from --help ──────────────────────────────────────────────────
# Reuses flagsurfacecheck.sh's own harvest idiom verbatim (see its "the advertised surface" comment).
# A 4-space-anchored `^    --` scrape undercounts: --help writes optional/alternative forms as
# "[--around-depth=N]" or "(--regex)", which a whitespace anchor misses entirely — flagsurfacecheck.sh's
# own header comment warns against exactly this trap. Anchoring on the "--name" TOKEN instead of its
# column position catches those forms too, which is why the two scripts disagreed (104 vs 123).
derived="$( printf '%s\n' "$HELP" | grep -oE '\-\-[a-z][a-z0-9-]+' | sort -u | wc -l | tr -d ' ' )"
if [ -z "$derived" ] || [ "$derived" -lt 50 ]; then
    no "(A) derived flag count from --help looks implausible ('$derived') — --help table layout may have changed"
else
    ok "(A) derived $derived distinct flags from --help ('--name' tokens, deduped by name, flagsurfacecheck.sh idiom)"
fi

# ── (B) README's stated count must equal the derived count ──────────────────────────────────────────
stated="$( grep -oE '[0-9]+ long flags advertised' "$README" | head -1 | grep -oE '^[0-9]+' )"
if [ -z "$stated" ]; then
    no "(B) could not find a '<N> long flags advertised' sentence in README.md to check"
elif [ "$stated" = "$derived" ]; then
    ok "(B) README.md states $stated flags, matching the derived count"
else
    no "(B) README.md states $stated flags but --help currently has $derived distinct flags — update README.md:15"
fi

# ── (C) mutation control — a wrong count in a COPY must be caught ───────────────────────────────────
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
wrong=$(( derived + 7 ))
sed -E "s/[0-9]+ long flags advertised/${wrong} long flags advertised/" "$README" > "$TMP/README_bad.md"
bad_stated="$( grep -oE '[0-9]+ long flags advertised' "$TMP/README_bad.md" | head -1 | grep -oE '^[0-9]+' )"
if [ "$bad_stated" = "$derived" ]; then
    no "(C) mutation control: injected wrong count ($bad_stated) was not actually different from derived ($derived) — control is vacuous"
elif [ -n "$bad_stated" ]; then
    ok "(C) mutation control: a fabricated count ($bad_stated) is correctly seen as disagreeing with the derived count ($derived)"
else
    no "(C) mutation control: could not parse the injected wrong count at all"
fi

# ── (D) cross-check — must equal flagsurfacecheck.sh's own harvest of the same --help text ──────────
# Runs the sibling gate itself (not a hand-copied re-derivation) so a future edit to EITHER script's
# scrape regex shows up here as a disagreement instead of two silently-diverging notions of "the count".
FLAGSURFACE_OUT="$( bash "$ROOT/test/flagsurfacecheck.sh" 2>&1 )"
flagsurface_count="$( printf '%s\n' "$FLAGSURFACE_OUT" | grep -oE 'harvested [0-9]+ advertised long flags' | head -1 | grep -oE '[0-9]+' )"
if [ -z "$flagsurface_count" ]; then
    no "(D) could not find flagsurfacecheck.sh's 'harvested N advertised long flags' line — did its output format change?"
elif [ "$flagsurface_count" = "$derived" ]; then
    ok "(D) this gate's derived count ($derived) matches flagsurfacecheck.sh's harvested count ($flagsurface_count)"
else
    no "(D) this gate derived $derived flags but flagsurfacecheck.sh harvested $flagsurface_count — the two scrapes have diverged again"
fi


# ── (E) the LINEAGE arm — the README's three advertised counts vs docs/LINEAGE.md's own tables ──────
# The extractor is shared by both files on purpose: LINEAGE.md bolds the numbers (`**29 repositories**
# and **37 papers**`) and README.md bolds the pair (`**29 repositories and 37 papers**`), so `*` is
# stripped before matching and ONE regex covers both spellings. Anchoring on the WORDS rather than on
# a line number or a bold-marker position means a rewrap or a re-bold cannot silently disarm the arm.
# The whole file is flattened to ONE line before matching, because prose wraps: an editor that broke
# "survey of\n220 tools" across a line boundary would otherwise make a line-oriented grep report "no
# sentence found" — loud, but for the wrong reason, and one reflow away from a maintainer deleting the
# arm as broken. Flattening makes the claimed rewrap-immunity actually true.
counts_from() {                      # $1 = file → prints "M P N" (empty field = not found)
    local f="$1" flat pair survey
    flat="$( sed 's/\*//g' "$f" | tr '\n' ' ' | tr -s ' ' )"
    pair="$(   printf '%s' "$flat" | grep -oE '[0-9]+ repositories and [0-9]+ papers' | head -1 )"
    survey="$( printf '%s' "$flat" | grep -oE 'survey of [0-9]+ tools'                | head -1 )"
    printf '%s %s %s\n' \
        "$( printf '%s' "$pair"   | grep -oE '^[0-9]+' )" \
        "$( printf '%s' "$pair"   | sed -E 's/^[0-9]+ repositories and ([0-9]+) papers$/\1/' )" \
        "$( printf '%s' "$survey" | grep -oE '[0-9]+' )"
}

# The structural derivation. Sections are markdown headings; a body row is a `|` line that is neither
# the section's first `|` line (its header) nor a `| --- |` separator. `n` is the surveyed table's
# LAST column, and each row's names are re-counted so the column cannot drift from what it summarises.
LINEAGE_AWK='
    /^#{2,3}[ ]/ { sec = $0; next }
    /^\|/ {
        if ( $0 ~ /^\|[ :|-]+\|[ :|-]*$/ ) next
        if ( seen[sec]++ == 0 ) next
        if ( sec ~ /Classic papers/  ) classic++
        if ( sec ~ /Modern research/ ) modern++
        if ( sec ~ /Folded/          ) folded++
        if ( sec ~ /Surveyed/ ) {
            split( $0, col, /\|/ )
            names = col[3]; declared = col[4]
            gsub( /^[ \t]+|[ \t]+$/, "", names ); gsub( /^[ \t]+|[ \t]+$/, "", declared )
            actual = split( names, nm, /,[ ]*/ )
            surveyed += declared + 0
            if ( actual != declared + 0 )
                printf "ROWMISMATCH\tdeclared=%s names=%d\t%.42s\n", declared, actual, names
        }
    }
    END { printf "CLASSIC\t%d\nMODERN\t%d\nFOLDED\t%d\nSURVEYED\t%d\n", classic+0, modern+0, folded+0, surveyed+0 }
'
awk "$LINEAGE_AWK" "$LINEAGE" > "$TMP/lineage.txt"
field(){ grep -E "^$1"$'\t' "$TMP/lineage.txt" | head -1 | cut -f2; }
d_classic="$( field CLASSIC )"; d_modern="$( field MODERN )"
d_folded="$(  field FOLDED  )"; d_surveyed="$( field SURVEYED )"
d_papers=$(( d_classic + d_modern ))
rowbad="$( grep -E '^ROWMISMATCH' "$TMP/lineage.txt" || true )"

# (E1) the tables must actually be there — a heading rename or a table turned into a bullet list would
#      otherwise derive 0/0/0, and 0 == 0 against a README nobody updated is a green-while-inert pass.
if [ "$d_classic" -lt 1 ] || [ "$d_modern" -lt 1 ] || [ "$d_folded" -lt 1 ] || [ "$d_surveyed" -lt 1 ]; then
    no "(E1) docs/LINEAGE.md derived implausible table sizes (classic=$d_classic modern=$d_modern folded=$d_folded surveyed=$d_surveyed) — a heading or table shape probably changed"
else
    ok "(E1) docs/LINEAGE.md tables derive as classic=$d_classic + modern=$d_modern papers, folded=$d_folded repositories, surveyed=$d_surveyed tools"
fi

# (E2) the README sentence must equal the derived counts
set -- $( counts_from "$README" )
r_repos="${1:-}"; r_papers="${2:-}"; r_tools="${3:-}"
if [ -z "$r_repos" ] || [ -z "$r_papers" ] || [ -z "$r_tools" ]; then
    no "(E2) could not find the lineage sentence's counts in README.md ('<M> repositories and <P> papers' / 'survey of <N> tools')"
elif [ "$r_repos" = "$d_folded" ] && [ "$r_papers" = "$d_papers" ] && [ "$r_tools" = "$d_surveyed" ]; then
    ok "(E2) README.md states $r_repos repositories / $r_papers papers / $r_tools tools, matching docs/LINEAGE.md's tables"
else
    no "(E2) README.md states $r_repos repositories / $r_papers papers / $r_tools tools but docs/LINEAGE.md's tables enumerate $d_folded / $d_papers / $d_surveyed — update the sentence, or the rows that justify it"
fi

# (E3) every surveyed row's declared `n` must equal the number of names it lists
if [ -n "$rowbad" ]; then
    no "(E3) surveyed row(s) whose n column disagrees with the names in the same row:"
    printf '%s\n' "$rowbad" | sed 's/^/          /'
else
    ok "(E3) every surveyed row's n column equals the number of tools named in that row"
fi

# (E4) mutation control for (E2) — the same control (C) provides for (B). A copy of README.md with a
#      deliberately wrong repository count must be seen to disagree; without this, (E2) passing proves
#      only that two numbers were read, never that a wrong one would be caught.
wrong_repos=$(( d_folded + 5 ))
sed -E "s/${d_folded} repositories and/${wrong_repos} repositories and/" "$README" > "$TMP/README_lineage_bad.md"
set -- $( counts_from "$TMP/README_lineage_bad.md" )
bad_repos="${1:-}"
if [ -z "$bad_repos" ]; then
    no "(E4) mutation control: could not re-extract a repository count from the mutated copy at all"
elif [ "$bad_repos" = "$d_folded" ]; then
    no "(E4) mutation control: the injected wrong count did not take ($bad_repos still equals the derived $d_folded) — the control is vacuous"
else
    ok "(E4) mutation control: a fabricated repository count ($bad_repos) is correctly seen as disagreeing with the derived count ($d_folded)"
fi

# (E5) docs/LINEAGE.md's own header prose must equal its own tables
set -- $( counts_from "$LINEAGE" )
l_repos="${1:-}"; l_papers="${2:-}"; l_tools="${3:-}"
if [ -z "$l_repos" ] || [ -z "$l_papers" ] || [ -z "$l_tools" ]; then
    no "(E5) docs/LINEAGE.md's header does not state its own three counts in the checkable form"
elif [ "$l_repos" = "$d_folded" ] && [ "$l_papers" = "$d_papers" ] && [ "$l_tools" = "$d_surveyed" ]; then
    ok "(E5) docs/LINEAGE.md's header ($l_repos / $l_papers / $l_tools) agrees with its own tables"
else
    no "(E5) docs/LINEAGE.md's header states $l_repos / $l_papers / $l_tools but its own tables enumerate $d_folded / $d_papers / $d_surveyed"
fi

# ── (E6/E7) the DISJOINTNESS arms — the set claim behind the counts ─────────────────────────────────
# NAME EXTRACTION, and why it is not a plain string compare. A folded row spells a tool the way its
# own project does ("[Sourcegraph / Cody]", "[aider repo-map]"); the survey table spells the same tool
# the way a catalogue does ("Cody", "Aider"). A whole-cell comparison sees no overlap and passes while
# the document counts one tool twice — which is exactly how Aider and Cody survived review. So each
# folded entry expands to a KEY SET: its normalised whole name, each slash-separated alternative, and
# (for §3a repository rows only) each space-separated word of four characters or more. Normalisation
# is lowercase-and-drop-everything-but-alphanumerics, so "grep.app" and "tree-sitter" compare as one
# token each and punctuation style cannot hide a duplicate.
#
# The word-split is deliberately NOT applied to §2, whose first column is prose ("Metric feedback into
# the loop"): splitting that into words would put common nouns in the key set and invite a false
# positive, and it is not needed — the §2 duplicate this arm was written for, RepoGraph, is the entire
# cell before the em dash. §2 therefore contributes only whole-name and slash-alternative keys.
LINEAGE_NAMES_AWK='
    function norm( s )      { s = tolower( s ); gsub( /[^a-z0-9]/, "", s ); return s }
    function trim( s )      { gsub( /^[ \t]+|[ \t]+$/, "", s ); return s }
    function linktext( c )  { if( match( c, /\[[^]]*\]/ ) ) return substr( c, RSTART + 1, RLENGTH - 2 ); return c }
    function emit( key, src ) { if( length( key ) >= 3 ) print "FOLDKEY\t" key "\t" src }
    function foldnames( raw, src,   parts, i, words, j, n, m, w ) {
        emit( norm( raw ), src )
        n = split( raw, parts, /[\/]/ )
        for( i = 1; i <= n; i++ ) {
            emit( norm( parts[ i ] ), src )
            if( src == "3a" ) {
                m = split( trim( parts[ i ] ), words, /[ ]+/ )
                if( m > 1 ) for( j = 1; j <= m; j++ ) { w = norm( words[ j ] ); if( length( w ) >= 4 ) emit( w, src ) }
            }
        }
    }
    /^#{2,3}[ ]/ { sec = $0; next }
    /^\|/ {
        if( $0 ~ /^\|[ :|-]+\|[ :|-]*$/ ) next
        if( seen[ sec ]++ == 0 ) next
        split( $0, col, /\|/ )
        cell = trim( col[ 2 ] )
        if( sec ~ /Folded/ ) { c = linktext( cell ); gsub( /\*/, "", c ); foldnames( trim( c ), "3a" ) }
        if( sec ~ /Modern research/ ) {
            idx = index( cell, "—" )
            if( idx > 0 ) cell = substr( cell, 1, idx - 1 )
            gsub( /\*/, "", cell )
            foldnames( trim( cell ), "2" )
        }
        if( sec ~ /Surveyed/ ) {
            n = split( trim( col[ 3 ] ), nm, /,[ ]*/ )
            for( i = 1; i <= n; i++ ) print "SURVEY\t" norm( nm[ i ] ) "\t" trim( nm[ i ] )
        }
    }
'

# $1 = lineage file, $2 = output prefix → writes "$2.overlap" and "$2.dupes"
disjointness_of() {
    awk "$LINEAGE_NAMES_AWK" "$1" > "$2.names"
    join -t"$( printf '\t' )" -1 1 -2 1 \
        <( grep '^FOLDKEY' "$2.names" | cut -f2,3 | sort -u ) \
        <( grep '^SURVEY'  "$2.names" | cut -f2,3 | sort -u ) > "$2.overlap"
    grep '^SURVEY' "$2.names" | cut -f2 | sort | uniq -d > "$2.dupes"
}

disjointness_of "$LINEAGE" "$TMP/live"
fold_keys="$(   grep -c '^FOLDKEY' "$TMP/live.names" )"
survey_names="$( grep -c '^SURVEY'  "$TMP/live.names" )"

# (E6) no name may be both folded and surveyed. RED-FIRST: a copy with a folded name planted into a
#      surveyed row must be caught, or a green E6 proves only that two lists were read.
disjointness_of <( sed -E 's/^\| Sanitizers \| /| Sanitizers | Serena, /' "$LINEAGE" ) "$TMP/planted"
if [ ! -s "$TMP/planted.overlap" ]; then
    no "(E6) mutation control is vacuous: a folded name (Serena) planted into a surveyed row was NOT detected as an overlap — the arm cannot see the thing it exists for"
elif [ -s "$TMP/live.overlap" ]; then
    no "(E6) docs/LINEAGE.md counts a tool twice — these names are both folded (§2/§3a) and surveyed (§3b), so the two counts overlap instead of adding:"
    cut -f2,3 "$TMP/live.overlap" | sed 's/^/          /'
else
    ok "(E6) §2+§3a and §3b are disjoint: $fold_keys folded keys vs $survey_names surveyed names, zero overlap (control: a planted 'Serena' is caught)"
fi

# (E7) no surveyed name may appear twice ANYWHERE in the surveyed table. E3 checks a row against
#      itself and is blind to this: `comby` sat in two rows, both rows' n were correct, and N was one
#      too high. RED-FIRST control as above.
disjointness_of <( sed -E 's/^\| Sanitizers \| /| Sanitizers | Valgrind, /' "$LINEAGE" ) "$TMP/dup"
if [ ! -s "$TMP/dup.dupes" ]; then
    no "(E7) mutation control is vacuous: a name duplicated inside the surveyed table was NOT detected — the arm cannot see the thing it exists for"
elif [ -s "$TMP/live.dupes" ]; then
    no "(E7) surveyed name(s) listed in more than one row of §3b — N counts them once per listing, so the total is inflated:"
    sed 's/^/          /' "$TMP/live.dupes"
else
    ok "(E7) all $survey_names surveyed names are globally unique across §3b's rows (control: a planted duplicate is caught)"
fi

# (E8) every repo-relative path docs/LINEAGE.md points at must exist. The honesty rule the document
#      states in its own header is that a folded lesson is "pointed at a real flag or source file", so
#      a dead pointer is a broken claim, not a typo. Deliberately EXISTENCE only: asserting that the
#      file also CONTAINS some identifier from the row was considered and rejected — a row's prose is
#      a lesson in English ("determinism is a product feature"), shares no tokens with the source it
#      cites, and any such rule would be a false-positive generator. Existence is cheap and exact.
missing_paths=""
for p in $( grep -oE '`(src|test|bench|third_party|docs)/[A-Za-z0-9_./-]+`' "$LINEAGE" | tr -d '`' | sort -u ); do
    [ -e "$ROOT/$p" ] || missing_paths="$missing_paths $p"
done
path_count="$( grep -oE '`(src|test|bench|third_party|docs)/[A-Za-z0-9_./-]+`' "$LINEAGE" | tr -d '`' | sort -u | wc -l | tr -d ' ' )"
if [ "$path_count" -lt 10 ]; then
    no "(E8) only $path_count repo-relative paths found in docs/LINEAGE.md — the rows cite source files, so this is implausibly few and the scrape has probably broken"
elif [ -n "$missing_paths" ]; then
    no "(E8) docs/LINEAGE.md points at path(s) that do not exist:$missing_paths"
else
    ok "(E8) all $path_count repo-relative paths cited by docs/LINEAGE.md exist in the tree"
fi

# ── (F) the GATE-SCRIPT count — README's third advertised number, and the only one nothing checked ──
# README.md's "In the tests" section states `test/regression.sh` names **N gate scripts**. That is an
# advertised count of an enumerated thing, exactly like the flag count in (B) and the lineage counts in
# (E), and this gate — whose whole job is "README's advertised counts must not drift" — did not cover
# it. It had drifted to 451 while the loop held 462: eleven gates landed and the README never moved,
# because nothing was watching. docs/EVALS.md's identical claims did NOT drift over the same period,
# for the obvious reason that manifestcheck.sh's §8 arm and its sibling arm re-derive them from the
# loop on every run. This arm is that same technique pointed at README.md.
#
# DERIVATION, not transcription: the loop is the single `for _g in NAME NAME ...; do` line in
# test/regression.sh, and its length is recomputed here on every run. The gates invoked individually
# above the loop (g1freshcheck, skillscan, htmlexport, compresscheck) are NOT part of it and are
# excluded, matching what manifestcheck.sh counts and what the README's own sentence refers to — the
# two numbers have to mean the same thing or "the authoritative list" is not one list.
REGRESSION="$ROOT/test/regression.sh"
if [ ! -f "$REGRESSION" ]; then
    no "(F) missing $REGRESSION — the README's gate-script count has no ground truth to check against"
else
    loopNames="$( python3 -c "
import re, sys
text = open( sys.argv[ 1 ] ).read()
m = re.search( r'for _g in (.*?); do', text, re.S )
sys.exit( 'no loop found' ) if not m else print( len( m.group( 1 ).split() ) )
" "$REGRESSION" 2>/dev/null )"
    readmeGates="$( grep -oE '\*\*[0-9]+ gate scripts\*\*' "$README" | head -1 | grep -oE '[0-9]+' )"

    # (F1) the derivation itself must be sane — a scrape that broke and yielded 0 or 3 would make every
    #      comparison below vacuous, and a vacuous PASS is the failure mode this whole lane is treating.
    if [ -z "$loopNames" ]; then
        no "(F1) could not derive the loop length from test/regression.sh — the 'for _g in ...; do' line is missing or its shape changed"
    elif [ "$loopNames" -lt 100 ]; then
        no "(F1) derived only $loopNames loop entries from test/regression.sh — implausibly few; the scrape has probably broken"
    else
        ok "(F1) derived $loopNames gate scripts from test/regression.sh's absorb loop"
    fi

    # (F2) the drift arm
    if [ -z "$readmeGates" ]; then
        no "(F2) could not find a '**N gate scripts**' sentence in README.md to check"
    elif [ -z "$loopNames" ]; then
        : # (F1) already reported the derivation failure; do not report the same fact twice
    elif [ "$readmeGates" = "$loopNames" ]; then
        ok "(F2) README.md states $readmeGates gate scripts, matching test/regression.sh's loop length"
    else
        no "(F2) README.md states $readmeGates gate scripts but test/regression.sh's loop names $loopNames — update the 'In the tests' sentence in README.md"
    fi

    # (F3) MUTATION CONTROL for (F2) — same discipline as (C) is for (B). A comparison that stopped
    #      comparing would read as a permanent PASS; prove a fabricated count is still seen as wrong.
    if [ -n "$loopNames" ]; then
        FTMP="$( mktemp -d )"
        wrongGates=$(( loopNames + 11 ))
        sed -E "s/\*\*[0-9]+ gate scripts\*\*/**${wrongGates} gate scripts**/" "$README" > "$FTMP/README_bad.md"
        badGates="$( grep -oE '\*\*[0-9]+ gate scripts\*\*' "$FTMP/README_bad.md" | head -1 | grep -oE '[0-9]+' )"
        if [ -z "$badGates" ]; then
            no "(F3) mutation control: could not parse the injected wrong gate count at all"
        elif [ "$badGates" = "$loopNames" ]; then
            no "(F3) mutation control: injected count ($badGates) was not actually different from the derived $loopNames — control is vacuous"
        else
            ok "(F3) mutation control: a fabricated gate count ($badGates) is correctly seen as disagreeing with the derived $loopNames"
        fi
        rm -rf "$FTMP"
    fi
fi

# ── (G) the COLD-START arm — README's "start here" invocation must disclose a budget ────────────────
# README.md teaches two "start here" invocations (the build-from-source block and "Four commands worth
# learning first"). A bare `ripwire .` is the commonest first call an agent makes in a session (13% of
# observed calls, capture-audit round 2026-09-04, finding P15) and costs ~9K est_tokens on this repo,
# where `--max-tokens=3000` serves the SAME head at under a third of that. The binary's own default is
# deliberately unchanged (owner call — dozens of gates parse the bare map); the guidance is what moves,
# and this arm keeps it moved. Three sub-arms, same shape as (B)/(C): the property, its mutation
# control, and a proof that the advertised budget line keeps the promise its comment makes.
#
# DERIVATION. A "start here" line is a fenced-bash line (README's own comment idiom marks it with the
# words "start here") that invokes ripwire on `.`; it is BARE when no `--` flag sits between the root
# argument and the comment. Anchored on the comment WORDS, not a line number, so a re-order of the
# Quickstart cannot disarm the arm; presence-guarded (G1) so a rewrite that drops the idiom fails loud
# instead of passing vacuously — the "green while inert" failure mode CONTRIBUTING.md §2 names.
start_here_lines(){ grep -nE '^\s*(\./build/)?ripwire[ ]+\.[ ].*#.*start here' "$1" || true; }
bare_start_here(){  start_here_lines "$1" | grep -vE '^[0-9]+:\s*(\./build/)?ripwire[ ]+\.[ ]+--' || true; }

start_count="$( start_here_lines "$README" | wc -l | tr -d ' ' )"
if [ "$start_count" -lt 1 ]; then
    no "(G1) README.md carries no fenced '# … start here' ripwire invocation — the cold-start idiom this arm guards has moved or been reworded"
else
    ok "(G1) README.md carries $start_count 'start here' cold-start invocation(s) to check"
    bare="$( bare_start_here "$README" )"
    if [ -n "$bare" ]; then
        no "(G2) README.md recommends a BARE cold-start map (~9K est_tokens here) — add --max-tokens=3000, the head is the same (P15):"
        printf '%s\n' "$bare" | sed 's/^/          /'
    else
        ok "(G2) every 'start here' invocation carries a flag — none is the bare ~9K-token map"
    fi
    # (G3) mutation control — a copy with the budget flag stripped from the start-here lines must be caught
    sed -E '/# .*start here/ s/ripwire[ ]+\.[ ]+--[a-z-]+(=[^ ]+)?/ripwire ./' "$README" > "$TMP/README_bare.md"
    if [ -z "$( bare_start_here "$TMP/README_bare.md" )" ]; then
        no "(G3) mutation control is vacuous: stripping the budget flag from the start-here line(s) was NOT detected as bare"
    else
        ok "(G3) mutation control: a start-here line with its budget flag stripped is correctly seen as bare"
    fi
fi

# (G4) the PROMISE arm — the budget the README recommends must actually keep the head. The comment on
#      the start-here line says the budgeted call serves the top of the same ranking at a fraction of
#      the tokens; that is a claim about the binary, so it is re-measured here rather than trusted.
#      Both maps run with --no-cache so the check cannot pass on a stale sidecar. Three properties:
#      the budgeted map is not empty (presence guard), it is a SUBSET of the bare map's rows (the head,
#      not a different ranking), and its est_tokens sits under the finding's 4,500 ceiling while the
#      bare map's sits above it — otherwise the recommendation saves nothing and the comment is wrong.
budget_flag="$( start_here_lines "$README" | grep -oE -- '--max-tokens=[0-9]+' | head -1 )"
if [ -z "$budget_flag" ]; then
    no "(G4) the start-here line names no --max-tokens=N budget to re-measure"
else
    ( cd "$ROOT" && "$BIN" . --no-cache ) > "$TMP/map_bare.xml" 2>/dev/null
    ( cd "$ROOT" && "$BIN" . --no-cache "$budget_flag" ) > "$TMP/map_budget.xml" 2>/dev/null
    verdict="$( python3 - "$TMP/map_bare.xml" "$TMP/map_budget.xml" <<'PY'
import re, sys
def rows( path ):
    text = open( path, encoding="utf-8" ).read()
    est = re.search( r'<r [^>]*est_tokens="(\d+)"', text )
    keys = set(); cur = ""
    for m in re.finditer( r'<(f|s) ([^>]*)>', text ):
        attrs = dict( re.findall( r'([a-z_]+)="([^"]*)"', m.group( 2 ) ) )
        if m.group( 1 ) == "f":
            cur = attrs.get( "p", "" ); continue
        keys.add( attrs.get( "id" ) or f'{cur}::{attrs.get("t")}::{attrs.get("n")}' )
    return ( int( est.group( 1 ) ) if est else -1 ), keys
bareEst, bare = rows( sys.argv[ 1 ] )
budEst,  bud  = rows( sys.argv[ 2 ] )
problems = []
if len( bud ) < 20:             problems.append( f"budgeted map has only {len(bud)} rows (presence guard)" )
if not bud <= bare:             problems.append( f"{len(bud - bare)} budgeted row(s) absent from the bare map — not a head, a different ranking" )
if not 0 < budEst <= 4500:      problems.append( f"budgeted est_tokens={budEst}, ceiling 4500" )
if not bareEst > 4500:          problems.append( f"bare est_tokens={bareEst} is already under the 4500 ceiling — the recommendation saves nothing" )
print( ( "FAIL " + "; ".join( problems ) ) if problems else f"OK bare={bareEst} budgeted={budEst} rows={len(bud)}/{len(bare)}" )
PY
)"
    case "$verdict" in
        OK*) ok "(G4) $budget_flag keeps the bare map's head under the ceiling (${verdict#OK })" ;;
        *)   no "(G4) $budget_flag does not keep the promise the start-here comment makes: ${verdict#FAIL }" ;;
    esac
fi

if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
else
    echo "SOME CHECKS FAILED"
fi
exit "$fail"
