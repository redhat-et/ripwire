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
#       authority and the prose is checked against it. Sub-arms E1-E5 below; E4 is (E)'s mutation
#       control, exactly as (C) is (B)'s.
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
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
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
# The extractor is shared by both files on purpose: LINEAGE.md bolds the numbers (`**27 repositories**
# and **27 papers**`) and README.md bolds the pair (`**27 repositories and 27 papers**`), so `*` is
# stripped before matching and ONE regex covers both spellings. Anchoring on the WORDS rather than on
# a line number or a bold-marker position means a rewrap or a re-bold cannot silently disarm the arm.
counts_from() {                      # $1 = file → prints "M P N" (empty field = not found)
    local f="$1" pair survey
    pair="$(   sed 's/\*//g' "$f" | grep -oE '[0-9]+ repositories and [0-9]+ papers' | head -1 )"
    survey="$( sed 's/\*//g' "$f" | grep -oE 'survey of [0-9]+ tools'                | head -1 )"
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

if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
else
    echo "SOME CHECKS FAILED"
fi
exit "$fail"
