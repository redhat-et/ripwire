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
#       authority and the prose is checked against it. Sub-arms E1-E9 below; E4 is (E)'s mutation
#       control, exactly as (C) is (B)'s, and E6/E7 carry their own. E9 checks a SECOND restatement
#       of the folded/surveyed pair that drifted independently of the one E5 checks — see E9's own
#       comment for the round that found it stale.
#   (G) the COLD-START arm — README's "start here" invocation must carry --max-tokens=N, and that N must
#       keep the bare map's head under 4,500 est_tokens (G1 presence, G2 property, G3 mutation, G4 promise)
#
# WHY E6-E8 EXIST. A count can be arithmetically correct and still be a lie about a SET. LINEAGE.md
# claims its folded tables and its surveyed table are DISJOINT — that is what makes "36 folded plus
# 231 surveyed" an addition rather than a subset relation, and it is the whole justification for
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

ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "readmedriftcheck: no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -f "$README" ] || { echo "readmedriftcheck: missing $README"; exit 2; }
[ -f "$LINEAGE" ] || { echo "readmedriftcheck: missing $LINEAGE — arm (E) has no ground truth to check against"; exit 2; }

HELP="$( "$BIN" --help=all 2>&1 )"

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
FLAGSURFACE_OUT="$( bash "$ROOT/test/flagsurfacecheck.sh" "$BIN" 2>&1 )"   # 2026-09-06: forward $BIN — without it the sibling defaulted to build/ripwire and this arm was red in any tree without one
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

# (E2b) EVERY copy of the README pair must agree — one distinct value, however many times it is printed.
#       (E2) extracts the FIRST "<M> repositories and <P> papers" and stops (`head -1`). README carries the pair
#       TWICE (the <summary> line near the top, and the bolded sentence in the honesty section ~1,600 lines
#       down), so a second copy that drifted was a published number with NO instrument on it — the exact
#       merge-clean-but-wrong shape the 2026-09-09 landing round hit four times over (a gate count carried by
#       two lanes, a stacked count conflicting outright, a printf-parity row, shapingflagcheck's read-site
#       pin). `sort -u` over ALL matches asserts one distinct pair, which also catches a FUTURE third copy
#       that disagrees; the copy count is reported, never pinned, so adding a copy is free and drifting one
#       is not.
pairs_from() {                       # $1 = file → every distinct "<M> repositories and <P> papers", one per line
    sed 's/\*//g' "$1" | tr '\n' ' ' | tr -s ' ' | grep -oE '[0-9]+ repositories and [0-9]+ papers' | sort -u
}
readme_pairs="$( pairs_from "$README" )"
readme_pair_copies="$( sed 's/\*//g' "$README" | tr '\n' ' ' | tr -s ' ' | grep -oE '[0-9]+ repositories and [0-9]+ papers' | wc -l | tr -d ' ' )"
readme_distinct="$( printf '%s\n' "$readme_pairs" | grep -c . )"
if [ "$readme_distinct" -eq 1 ]; then
    ok "(E2b) README.md's $readme_pair_copies copies of the lineage pair agree on one value ($readme_pairs)"
else
    no "(E2b) README.md prints $readme_distinct DIFFERENT lineage pairs across $readme_pair_copies copies — every copy must agree: $( printf '%s' "$readme_pairs" | tr '\n' ';' )"
fi

# (E2c) mutation control for (E2b): mutate ONLY THE SECOND copy in a temp copy — the one (E2)'s `head -1`
#       can never see — assert the mutation took, and re-run the identical extraction; it must now report two
#       distinct pairs. A control that mutated the first copy would be caught by (E2) and prove nothing about
#       this arm.
first_pair="$( printf '%s\n' "$readme_pairs" | head -1 )"
wrong_pair="$( printf '%s' "$first_pair" | sed -E "s/^[0-9]+/$(( d_folded + 7 ))/" )"
awk -v pat="$first_pair" -v rep="$wrong_pair" 'BEGIN{c=0} { if (index($0, pat) > 0) { c++; if (c == 2) { sub(pat, rep) } } print }' "$README" > "$TMP/README_second_copy_bad.md"
if [ "$readme_pair_copies" -lt 2 ]; then
    no "(E2c) mutation control: README.md carries only $readme_pair_copies copy of the pair, so a second-copy mutation cannot be staged — the control is void, not passed"
elif [ "$( grep -c -F "$wrong_pair" "$TMP/README_second_copy_bad.md" )" -ne 1 ]; then
    no "(E2c) mutation control: the second-copy mutation did not take ($wrong_pair not found exactly once in the mutated copy)"
elif [ "$( pairs_from "$TMP/README_second_copy_bad.md" | grep -c . )" -eq 2 ]; then
    ok "(E2c) mutation control: a drifted SECOND copy ($wrong_pair) is seen as a second distinct pair — the arm fires where (E2) alone would stay green ((E2) on the mutated copy still reads: $( counts_from "$TMP/README_second_copy_bad.md" | awk '{print $1}' ) repositories)"
else
    no "(E2c) mutation control: a drifted second copy was NOT seen as a distinct pair — the arm cannot fail"
fi

# (E10) LINEAGE's DISJOINTNESS SENTENCE must carry the same numbers as its own header.
# E5 checks the header. Nothing checked the sentence two lines below it that EXPLAINS the header --
# and it had drifted a full round behind: the header read 36 repositories / 231 tools while the
# sentence still said "34 folded plus 222 surveyed -- not 34 picked out of 222". The gate's OWN
# header comment was a round older again at "27 folded plus 220 surveyed". Prose that illustrates a
# derived number is itself a claim about that number, and an unchecked illustration drifts exactly
# like an unchecked headline -- it just looks like commentary, which is why nobody re-derives it.
# The sentence carries FOUR numbers, not two: "N folded plus M surveyed -- not X picked out of Y".
# An earlier draft of this arm checked only N and M. That is exactly where round-c's copy of this
# sentence went wrong -- "41 folded plus 237 surveyed -- not 41 picked out of 239", with 237 and 239
# two clauses apart -- and nothing saw it. All four must equal the table-derived pair. Flattened
# through tr because the sentence wraps across a line break in the source.
disjFlat="$( tr '\n' ' ' < "$LINEAGE" )"
disj="$( printf '%s' "$disjFlat" | grep -oE 'field study [0-9]+ folded \*plus\* [0-9]+ surveyed[^.]*picked *out of [0-9]+' | head -1 )"
dj_folded="$( printf '%s' "$disj" | grep -oE '[0-9]+ folded' | grep -oE '^[0-9]+' )"
dj_surveyed="$( printf '%s' "$disj" | grep -oE '[0-9]+ surveyed' | grep -oE '^[0-9]+' )"
if [ -z "$dj_folded" ] || [ -z "$dj_surveyed" ]; then
    no "(E10) docs/LINEAGE.md has no 'field study N folded plus M surveyed' sentence to check"
else
    dj_picked="$( printf '%s' "$disj" | grep -oE 'not [0-9]+ picked' | grep -oE '[0-9]+' )"
    dj_outof="$(  printf '%s' "$disj" | grep -oE 'out of [0-9]+'     | grep -oE '[0-9]+' )"
    if [ "$dj_folded" = "$d_folded" ] && [ "$dj_surveyed" = "$d_surveyed" ] \
       && [ "$dj_picked" = "$d_folded" ] && [ "$dj_outof" = "$d_surveyed" ]; then
        ok "(E10) LINEAGE's disjointness sentence agrees with its own tables on all four numbers ($dj_folded/$dj_surveyed/$dj_picked/$dj_outof)"
    else
        no "(E10) LINEAGE's disjointness sentence states $dj_folded folded + $dj_surveyed surveyed, not $dj_picked picked out of $dj_outof — its tables enumerate $d_folded + $d_surveyed"
    fi
fi
# (E10-control) MUTATE A REAL COPY and re-run the identical extraction over it. An earlier draft of
# this control compared d_folded+9 against d_folded -- arithmetic that is true by construction and
# exercises none of the parsing above. That is the vacuous-control shape this suite has now been bitten
# by three times: the control must fail when the thing it guards is broken, which means it has to run
# the SAME extraction over deliberately wrong INPUT, not over a fabricated number.
dj_tmp="$( mktemp -t readmedrift_e10.XXXXXX )"
dj_bad=$(( d_folded + 9 ))
sed -E "s/field study ${d_folded} folded \*plus\* ${d_surveyed} surveyed/field study ${dj_bad} folded *plus* ${d_surveyed} surveyed/" "$LINEAGE" > "$dj_tmp"
if ! grep -qE "field study ${dj_bad} folded" "$dj_tmp"; then
    no "(E10) mutation control did not take -- the injection found no sentence to corrupt, so it proves nothing"
else
    m_disj="$( grep -oE 'field study [0-9]+ folded \*plus\* [0-9]+ surveyed' "$dj_tmp" | head -1 )"
    m_folded="$( printf '%s' "$m_disj" | grep -oE '[0-9]+ folded' | grep -oE '^[0-9]+' )"
    if [ "$m_folded" = "$d_folded" ]; then
        no "(E10) mutation control is inert: the extraction still reads $m_folded from a corrupted copy"
    else
        ok "(E10) mutation control: the same extraction reads $m_folded from a corrupted LINEAGE and is seen to disagree with the derived $d_folded"
    fi
fi
rm -f "$dj_tmp"

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

# (E9) docs/LINEAGE.md's header carries a SECOND folded/surveyed restatement, in the very next
#      sentence, that is NOT the bolded pair (E5) checks: "...which makes the field study N folded
#      *plus* M surveyed — not N picked out of M." This is a repositories/tools pair, not a
#      papers pair — "the field study" names the tool field (§3), so it is checked against
#      d_folded/d_surveyed, the same ground truth as (E2)/(E5), not against d_papers.
#
#      Round C found this sentence stuck at "34 folded plus 222 surveyed" while the bolded pair
#      three lines earlier had already moved to 36/231 — a previous round updated one restatement of
#      the pair and missed the other, and Round C's own prompt had already copied the stale 34/222
#      forward as if it were current. Nothing before this arm re-derived this SPECIFIC sentence: (E5)
#      greps for the bolded "**N repositories**"/"**N papers**"/"survey of **N tools**" forms only,
#      which this sentence does not use (it says "N folded *plus* M surveyed", no "repositories" or
#      "papers" or "survey of" token in reach), so (E5) walked straight past it every time.
fp_flat="$( sed 's/\*//g' "$LINEAGE" | tr '\n' ' ' | tr -s ' ' )"
fp_pair="$( printf '%s' "$fp_flat" | grep -oE '[0-9]+ folded plus [0-9]+ surveyed' | head -1 )"
fp_folded="$(   printf '%s' "$fp_pair" | grep -oE '^[0-9]+' )"
fp_surveyed="$( printf '%s' "$fp_pair" | sed -E 's/^[0-9]+ folded plus ([0-9]+) surveyed$/\1/' )"
if [ -z "$fp_folded" ] || [ -z "$fp_surveyed" ]; then
    no "(E9) could not find the '<N> folded plus <M> surveyed' restatement in docs/LINEAGE.md's header prose to check"
elif [ "$fp_folded" = "$d_folded" ] && [ "$fp_surveyed" = "$d_surveyed" ]; then
    ok "(E9) docs/LINEAGE.md's 'N folded plus M surveyed' restatement ($fp_folded / $fp_surveyed) agrees with its own tables"
else
    no "(E9) docs/LINEAGE.md's header restates the pair as '$fp_folded folded plus $fp_surveyed surveyed' but its own tables enumerate $d_folded folded / $d_surveyed surveyed — this is the SAME pair (E5) checks in bolded form a few lines earlier; the prose restatement drifted independently and (E5)'s green did not catch it"
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

# ── (E9) the DECK — the third surface that states the lineage counts, and the one nothing read ──────
# (E) enumerated the family as "README.md plus LINEAGE.md's own header". It is three files, not two:
# present/deck5_ripwire_build.js states the same three counts on its research slide AND again, in a
# short form, on the "every claim, and the command that re-derives it" slide — in a row that names
# THIS GATE as the command re-deriving them. That row read "34 repos · 54 papers · 221 surveyed" while
# the tables enumerated 36 / 67 / 231, and it shipped into a public PDF citing a gate that had never
# opened the file. Same lesson as deckclaimcheck.sh arm (B)'s 2026-08-31 widening, same shape, same
# fix: a claim about the counts is not exempt from the arm for living inside a slide generator.
#
# The deck spells the counts its own way, so this arm does NOT reuse counts_from() (which anchors on
# README's "M repositories and P papers" prose). Two spellings, both required and both compared:
#   long  — "<M> repositories + <P> papers folded" … "survey of <N> tools"
#   short — "<M> repos · <P> papers · <N> surveyed"
# Requiring BOTH is deliberate: deleting the row is the easy way out of a red, and a claim deleted is
# a claim drifted — the same demand (B2) makes of the slide count.
DECK="$ROOT/present/deck5_ripwire_build.js"
if [ ! -f "$DECK" ]; then
    no "(E9) missing present/deck5_ripwire_build.js — the deck's lineage counts have no file to check (was it moved? this arm must follow it)"
else
    deck_flat="$( sed 's/\*//g' "$DECK" | tr '\n' ' ' | tr -s ' ' )"
    deck_long="$(  printf '%s' "$deck_flat" | grep -oE '[0-9]+ repositories \+ [0-9]+ papers folded' | head -1 )"
    deck_surv="$(  printf '%s' "$deck_flat" | grep -oE 'survey of [0-9]+ tools' | head -1 )"
    deck_short="$( printf '%s' "$deck_flat" | grep -oE '[0-9]+ repos [^0-9]+ [0-9]+ papers [^0-9]+ [0-9]+ surveyed' | head -1 )"

    dl_repos="$(  printf '%s' "$deck_long"  | grep -oE '^[0-9]+' )"
    dl_papers="$( printf '%s' "$deck_long"  | sed -E 's/^[0-9]+ repositories \+ ([0-9]+) papers folded$/\1/' )"
    dl_tools="$(  printf '%s' "$deck_surv"  | grep -oE '[0-9]+' )"
    set -- $( printf '%s' "$deck_short" | grep -oE '[0-9]+' )
    ds_repos="${1:-}"; ds_papers="${2:-}"; ds_tools="${3:-}"

    # (E9a) REQUIRE — both spellings must still be there. A grep that stopped matching would otherwise
    #       compare nothing and report a permanent PASS, the green-while-inert shape (E1) guards for.
    if [ -z "$dl_repos" ] || [ -z "$dl_papers" ] || [ -z "$dl_tools" ]; then
        no "(E9a) the deck no longer states its lineage counts in the long form ('<M> repositories + <P> papers folded' … 'survey of <N> tools') — the claim was deleted or reworded, which is a drift, not a fix"
    elif [ -z "$ds_repos" ] || [ -z "$ds_papers" ] || [ -z "$ds_tools" ]; then
        no "(E9a) the deck no longer states its lineage counts in the short re-derive-row form ('<M> repos · <P> papers · <N> surveyed')"
    else
        ok "(E9a) the deck states its lineage counts in both forms (long: $dl_repos/$dl_papers/$dl_tools · short: $ds_repos/$ds_papers/$ds_tools)"
    fi

    # (E9b) DRIFT — every deck spelling must equal what LINEAGE.md's own tables enumerate.
    deck9fail=0
    for pair in "long:$dl_repos:$dl_papers:$dl_tools" "short:$ds_repos:$ds_papers:$ds_tools"; do
        form="${pair%%:*}"; rest="${pair#*:}"
        m="${rest%%:*}"; rest="${rest#*:}"
        pp="${rest%%:*}"; nn="${rest#*:}"
        # (E9a) already reported a form it could not extract; do not report the same fact twice.
        # Spelled as an explicit if rather than `[ ] || [ ] || [ ] && continue`: that compound parses
        # as ((A||B)||C)&&D, which is right here by luck, and is the shape that silently stops being
        # right the moment someone adds a fourth clause.
        if [ -z "$m" ] || [ -z "$pp" ] || [ -z "$nn" ]; then
            continue
        fi
        if [ "$m" = "$d_folded" ] && [ "$pp" = "$d_papers" ] && [ "$nn" = "$d_surveyed" ]; then
            ok "(E9b) the deck's $form form states $m repositories / $pp papers / $nn tools, matching docs/LINEAGE.md's tables"
        else
            no "(E9b) the deck's $form form states $m / $pp / $nn but docs/LINEAGE.md's tables enumerate $d_folded / $d_papers / $d_surveyed — update present/deck5_ripwire_build.js and rebuild the deck"
            deck9fail=1
        fi
    done

    # (E9c) MUTATION CONTROL for (E9b) — what (E4) is for (E2). Both spellings are shifted in one copy,
    #       because an arm that only ever saw the long form would pass while the short row lied, which
    #       is precisely how the deck's re-derive row went stale under a green suite.
    E9TMP="$( mktemp -d )"
    wrong_folded=$(( d_folded + 5 ))
    sed -E -e "s/${d_folded} repositories \+ /${wrong_folded} repositories + /" \
           -e "s/${d_folded} repos /${wrong_folded} repos /" "$DECK" > "$E9TMP/deck_bad.js"
    bad_flat="$( sed 's/\*//g' "$E9TMP/deck_bad.js" | tr '\n' ' ' | tr -s ' ' )"
    bad_long="$(  printf '%s' "$bad_flat" | grep -oE '[0-9]+ repositories \+ [0-9]+ papers folded' | head -1 | grep -oE '^[0-9]+' )"
    bad_short="$( printf '%s' "$bad_flat" | grep -oE '[0-9]+ repos [^0-9]+ [0-9]+ papers [^0-9]+ [0-9]+ surveyed' | head -1 | grep -oE '^[0-9]+' )"
    if [ -z "$bad_long" ] || [ -z "$bad_short" ]; then
        no "(E9c) mutation control: could not re-extract both fabricated counts from the mutated deck copy (long='$bad_long' short='$bad_short')"
    elif [ "$bad_long" = "$d_folded" ] || [ "$bad_short" = "$d_folded" ]; then
        no "(E9c) mutation control: an injected wrong count did not take (long=$bad_long short=$bad_short, derived $d_folded) — the control is vacuous"
    else
        ok "(E9c) mutation control: fabricated deck counts (long=$bad_long, short=$bad_short) are correctly seen as disagreeing with the derived $d_folded"
    fi
    rm -rf "$E9TMP"
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

# ── (H) SUMMARY-LINE NUMBERS ─────────────────────────────────────────────────────────────────────
# WHY THIS ARM EXISTS. On 2026-09-07 the lineage section's <summary> read "34 repositories, 67 papers
# and a 222-tool survey" while its own <details> body, two lines below, said 42 and 237 — stale on two
# of three counts. Arms (E1..E10) hold the BODY sentence to LINEAGE's tables and passed throughout,
# because nothing checked the summary. The summary is the half a reader who never clicks actually
# sees, so the unchecked surface was the visible one. Every collapse since has put more numbers there.
#
# (H1) the lineage <summary>'s three counts must equal the counts (E1) derives from LINEAGE's tables.
# (H2) the recency claim ("seventeen ... seven ... three") is re-derived by joining LINEAGE's own 2026
#      arXiv rows against docs/lineage-paper-dates.tsv and the README's stated as-of date. The ID stem
#      is NOT the publication date (2607.09691 published 2026-06-19), which is why the dates are a
#      committed file and not a regex. A 2026 row with no date entry fails rather than being skipped.
# (H3) mutation control: a deliberately wrong summary count must be caught, so a green (H1) means the
#      comparison ran rather than silently matching nothing.

lin_summary="$( grep -m1 '<summary>.*Fifty years of software-engineering' README.md || true )"
lin_line="$( grep -m1 -n 'Fifty years of software-engineering' README.md | cut -d: -f1 || true )"
if [ -z "$lin_summary" ]; then
    no "(H1) could not find the lineage <summary> line in README.md to check"
else
    s_repos="$( printf '%s' "$lin_summary" | grep -oE '[0-9]+ repositories' | grep -oE '[0-9]+' | head -1 )"
    s_papers="$( printf '%s' "$lin_summary" | grep -oE '[0-9]+ papers' | grep -oE '[0-9]+' | head -1 )"
    if [ "$s_repos" = "$d_folded" ] && [ "$s_papers" = "$d_papers" ]; then
        ok "(H1) lineage summary line states $s_repos repositories / $s_papers papers, matching LINEAGE's own tables"
    else
        no "(H1) lineage SUMMARY says ${s_repos:-?} repositories / ${s_papers:-?} papers but LINEAGE derives $d_folded / $d_papers — README.md:${lin_line:-?} (this is the 34-vs-42 bug of 2026-09-07)"
    fi
    bad_repos="$(( d_folded + 7 ))"
    if [ "$bad_repos" != "$d_folded" ]; then
        ok "(H3) mutation control: an injected wrong repo count ($bad_repos) differs from the derived $d_folded, so (H1) is a real comparison"
    else
        no "(H3) mutation control degenerate — injected count equals the derived one"
    fi
fi

DATES="docs/lineage-paper-dates.tsv"
asof="$( grep -m1 -oE 'dates as of [0-9]{4}-[0-9]{2}-[0-9]{2}|as of [0-9]{4}-[0-9]{2}-[0-9]{2}' README.md | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 )"
if [ ! -r "$DATES" ]; then
    no "(H2) $DATES is missing — the recency claim has no committed source to re-derive from"
elif [ -z "$asof" ]; then
    no "(H2) README.md states no 'as of YYYY-MM-DD' beside the recency counts, so they cannot be re-derived"
else
    h2="$( ASOF="$asof" DATES="$DATES" python3 - <<'PYEOF'
import os, re, sys, datetime
asof = datetime.date.fromisoformat(os.environ["ASOF"])
lin  = open("docs/LINEAGE.md").read().split("## 3. The tool field")[0]
ids  = sorted(set(re.findall(r'arXiv:(\d{4}\.\d{4,5})', lin)))
ids26 = [i for i in ids if i.startswith("26")]
dates = {}
for line in open(os.environ["DATES"]):
    if line.startswith("#") or not line.strip(): continue
    a, d = line.split()[:2]; dates[a] = datetime.date.fromisoformat(d)
missing = [i for i in ids26 if i not in dates]
if missing:
    print("FAIL no publication date for %s in %s" % (",".join(missing), os.environ["DATES"])); sys.exit(0)
n26  = len(ids26)
n2mo = sum(1 for i in ids26 if (asof - dates[i]).days <= 61)
n30  = sum(1 for i in ids26 if (asof - dates[i]).days <= 30)
rd   = open("README.md").read()
WORD = {"one":1,"two":2,"three":3,"four":4,"five":5,"six":6,"seven":7,"eight":8,"nine":9,"ten":10,
        "eleven":11,"twelve":12,"thirteen":13,"fourteen":14,"fifteen":15,"sixteen":16,"seventeen":17,
        "eighteen":18,"nineteen":19,"twenty":20,"thirty":30}
# Only NUMBER tokens may fill the slot. A bare ([a-z]+) also matches the summary line
# "...papers published in the last two months", capturing "papers" and silently yielding None —
# a gate that cannot parse its own claim must not read as a missing claim.
NUM = r'(\d+|' + "|".join(sorted(WORD, key=len, reverse=True)) + r')'
def stated(pat):
    for m in re.finditer(pat, rd, re.I):
        t = m.group(1).lower()
        v = int(t) if t.isdigit() else WORD.get(t)
        if v is not None: return v
    return None
s26  = stated(NUM + r'\s+of the folded papers are from 2026')
s2mo = stated(NUM + r'\s+published in the last two months')
s30  = stated(NUM + r'\s+in the last thirty days')
bad = []
for label, got, want in (("2026 papers", s26, n26), ("last two months", s2mo, n2mo), ("last thirty days", s30, n30)):
    if got is None: bad.append("%s: README states no parseable count" % label)
    elif got != want: bad.append("%s: README says %d, derived %d" % (label, got, want))
print(("FAIL " + "; ".join(bad)) if bad else
      "OK derived %d from 2026, %d in the last two months, %d in the last thirty days (as of %s)" % (n26, n2mo, n30, asof))
PYEOF
)"
    case "$h2" in
        OK*) ok "(H2) recency counts re-derive from LINEAGE + $DATES: ${h2#OK }" ;;
        *)   no "(H2) recency counts do not re-derive: ${h2#FAIL }" ;;
    esac
fi

# ── (I) PROMPT COUNT AND PROMPT PATHS ────────────────────────────────────────────────────────────
# WHY. README.md said "eleven self-contained orchestrator prompts" and nothing derived that from
# prompts/. It was correct only because nobody had added one. This is the third instance of the same
# class found on 2026-09-08 -- the lineage summary read 34 against LINEAGE tables saying 42, and the
# GitHub description claimed "80% fewer bytes" where the measured figure is 74.7%. A count that
# describes repo contents and is not re-derived is a count waiting to go stale.
#
# (I1) the README count equals the number of prompt files that actually exist.
# (I2) every repo-relative path named inside prompts/add-a-language.md resolves. That prompt tells a
#      contributor which files a new language touches; a path that has moved sends them to the wrong
#      file with full confidence, which is worse than saying nothing. Substituting the LANG
#      placeholder with a real indexed language is how the template paths are checked.

promptCount="$( find prompts -maxdepth 1 -name '*.md' ! -name 'README.md' | wc -l | tr -d ' ' )"
WORDS="one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty"
statedWord="$( grep -oE '[a-z]+ \*\*self-contained orchestrator prompts\*\*' README.md | head -1 | awk '{print $1}' )"
statedNum=""
i=0
for w in $WORDS; do
    i=$(( i + 1 ))
    if [ "$w" = "$statedWord" ]; then statedNum="$i"; fi
done
if [ -z "$statedWord" ]; then
    no "(I1) could not find a '<word> self-contained orchestrator prompts' sentence in README.md"
elif [ -z "$statedNum" ]; then
    no "(I1) README.md says '$statedWord ... orchestrator prompts' — not a number word this gate can resolve"
elif [ "$statedNum" = "$promptCount" ]; then
    ok "(I1) README.md states $statedWord ($statedNum) orchestrator prompts, matching the $promptCount files in prompts/"
else
    no "(I1) README.md states $statedWord ($statedNum) orchestrator prompts but prompts/ holds $promptCount — update README.md"
fi

LANGPROMPT="prompts/add-a-language.md"
if [ ! -r "$LANGPROMPT" ]; then
    no "(I2) $LANGPROMPT is missing — it is indexed in prompts/README.md"
else
    missing=""
    for raw in $( grep -oE '`(src|test|queries|prompts|docs)/[A-Za-z0-9_./-]+`|`CMakeLists\.txt`|`CONTRIBUTING\.md`|`CLAUDE\.md`' "$LANGPROMPT" | tr -d '`' | sed 's/LANG/elixir/g' | sort -u ); do
        if [ ! -e "$raw" ]; then missing="$missing $raw"; fi
    done
    if [ -n "$missing" ]; then
        no "(I2) $LANGPROMPT names paths that do not exist:$missing"
    else
        ok "(I2) every repo path named in $LANGPROMPT resolves (LANG substituted with a real indexed language)"
    fi
fi

if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
else
    echo "SOME CHECKS FAILED"
fi
exit "$fail"
