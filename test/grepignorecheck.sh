#!/usr/bin/env bash
# grepignorecheck.sh — grep's UNINDEXED aux scan honours .gitignore, exactly as the crawl already does.
#
# THE DEFECT THIS PINS. ripwire's documented default is ripgrep's: in a git work tree the crawl honours
# git's ignore rules. It did — for every file it could have INDEXED. But --grep/--regex additionally scan
# the crawl's "unsupported-ext, text-looking" population (CrawlSkips::unsupported, search.h grepCollectAux)
# and print those hits in the trailing <unindexed> block, and THAT population was recorded before the
# ignore verdict was ever consulted: collectSources classified the extension first (recordPreSizeDrop, which
# rowed any grammar-less, non-asset extension as unsupported-ext) and tested the ignore set only on what
# survived. A file that was BOTH gitignored AND of an unindexed extension was therefore never asked, and
# grep read it and served it. Measured 2026-09-09 on a private validation corpus:
#   ripwire <root> --regex='^#include' --grep-in=any   → four hits inside <dir>/personality.cpp.bak
#   git check-ignore -v <dir>/personality.cpp.bak      → .gitignore:78:<dir>/*.bak
#   rg '^#include'                                      → does not open it
# The header's own counters agreed with the leak: unindexed_files_scanned= counted the file, and the
# skipped verb's unsupported_ext= counted it too, so nothing disclosed that an ignored file had been read.
#
# THE CONTRACT. The unsupported-ext class is not merely REPORTED, it is SERVED — so it may hold only files
# the repository did not ask to hide, on the same rule the class already applies to --exclude (an
# --exclude'd .ml is requested absence, not a language this build cannot read). A file dropped that way is
# in NO class: not unsupported-ext, and not ignored= either, because ignored= describes only what would
# OTHERWISE HAVE BEEN INDEXED — the number the map header's accounting invariant carries. And the two
# counts that describe this population — the grep root's unindexed_files_scanned= and the skipped verb's
# unsupported_ext= — must describe what was ACTUALLY scanned: a file dropped here is counted nowhere.
#
# Assertions (RED-FIRST: recorded against the pre-fix binary — A B C D G fail, the rest already pass):
#   0  presence guards — git really ignores the hidden file, really does NOT ignore the tracked-anyway
#      one, and (when rg is on PATH) the independent tool agrees about the hidden file
#   A  --grep: the set of files served (indexed block AND unindexed block) is EXACTLY the set git does
#      not ignore that contains the needle — an independent oracle, `git ls-files -co --exclude-standard`
#      piped to grep -l; and the gitignored file appears NOWHERE in the answer
#   B  --regex: the same equality for the pattern the report was filed with, '^#include'
#   C  unindexed_files_scanned= counts only what was served (it is the number of aux files git does not
#      ignore, derived from git check-ignore, never from ripwire)
#   D  --skipped agrees: unsupported_ext= equals that same number, equals unindexed_files_scanned=, the
#      hidden file has no row, the <e x= files=/> histogram counts it out, and ignored= is untouched
#      (the file is in neither class — the accounting invariant test/gitignorecheck.sh arm 4 pins)
#   E  --no-ignore is a real escape hatch: the hidden file is served again and both counts grow by one
#   F  a NON-GIT root is unchanged: every text file is served (the feature may not shrink a corpus it
#      cannot explain)
#   G  the MCP grep verb serves the same population (it reuses grepCollectAux over the same rows)
#   H  determinism: two default runs byte-identical
#   I  MUTATION self-tests — each assertion can see its own regression
#   J  G4: xmllint --noout clean
#
# Usage:  test/grepignorecheck.sh              # uses build/ripwire
#         RIPWIRE_BIN=asan/ripwire test/grepignorecheck.sh
# Exits non-zero on any failure. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "grepignorecheck: no git on PATH — the feature's whole premise; SKIP"; exit 0; }
cd "$ROOT"
echo "grepignorecheck: BIN=$BIN"

# ── the fixture: one git repo, four text files of an UNINDEXED extension, and one indexed control ──────
#   main.cpp             tracked, indexed — proves the indexed half of the answer still works
#   personality.cpp.bak  untracked, IGNORED by `*.bak`           → must not be served (the defect)
#   kept.bak             matches `*.bak` but force-added, TRACKED → must be served (git's rule, rg's blind spot)
#   stale.scm            tracked, unsupported-ext                 → must be served
#   draft.scm            UNTRACKED and NOT ignored                → must be served (untracked ≠ ignored)
# Every text file carries the shared needle so one grep shows the whole served set; only the indexed file
# lacks a `#include` line, so the regex arm's oracle set differs from the literal arm's by exactly it.
R="$TMP/repo"; mkdir -p "$R"
printf '*.bak\n' >"$R/.gitignore"
printf 'int rwIgnMainSymbol( int a ) { return a; }\n// rwIgnNeedleShared indexed\n' >"$R/main.cpp"
printf '#include <hidden.h>\nrwIgnNeedleShared hidden\nrwIgnNeedleHiddenOnly\n'      >"$R/personality.cpp.bak"
printf '#include <tracked.h>\nrwIgnNeedleShared tracked\n'                           >"$R/kept.bak"
printf '#include <stale.h>\nrwIgnNeedleShared stale\n'                               >"$R/stale.scm"
printf '#include <draft.h>\nrwIgnNeedleShared draft\n'                               >"$R/draft.scm"
(
    cd "$R" || exit 1
    git init -q . >/dev/null 2>&1
    git config user.email gate@example.invalid
    git config user.name  gate
    git add .gitignore main.cpp stale.scm >/dev/null 2>&1
    git add -f kept.bak >/dev/null 2>&1          # tracked THOUGH .gitignore names it — the point of arm 0/A
    git commit -qm fixture >/dev/null 2>&1
)
AUX_FILES="personality.cpp.bak kept.bak stale.scm draft.scm"
HIDDEN="personality.cpp.bak"

# ── extractors ─────────────────────────────────────────────────────────────────────────────────────────
# served(): every <f p="…"> in the answer, indexed block AND unindexed block, sorted unique.
served(){
    python3 -c '
import re, sys
xml = sys.stdin.read().split( "-->", 1 )[ -1 ]
print( "\n".join( sorted( set( re.findall( r"<f p=\"([^\"]*)\"", xml ) ) ) ) )
'
}
# attr NAME < answer → the value of the first NAME="…" on the root element, or empty
attr(){ grep -oE " $1=\"[0-9]+\"" | head -1 | grep -oE '[0-9]+'; }

# ── oracles, both independent of ripwire ───────────────────────────────────────────────────────────────
# oracle ERE: the files git does NOT ignore (tracked, plus untracked-but-unignored) that contain ERE.
oracle(){ ( cd "$R" && git ls-files -co --exclude-standard -z | xargs -0 grep -lE -- "$1" 2>/dev/null | sort -u ); }
# oracle_all ERE: every file under the tree that contains ERE, ignore rules NOT applied (the --no-ignore
# and non-git expectation).
oracle_all(){ ( cd "$1" && grep -rlE --exclude-dir=.git -- "$2" . 2>/dev/null | sed 's|^\./||' | sort -u ); }
# the number of aux files git does not ignore — from git check-ignore, so C/D never learn it from ripwire
AUX_UNIGNORED=0
for f in $AUX_FILES; do ( cd "$R" && git check-ignore -q "$f" ) || AUX_UNIGNORED=$(( AUX_UNIGNORED + 1 )); done
AUX_TOTAL="$( printf '%s\n' $AUX_FILES | grep -c . )"

rw(){ "$BIN" "$R" "$@" --grep-in=any --limit=100000 --no-cache 2>/dev/null; }

# ── 0) presence guards ─────────────────────────────────────────────────────────────────────────────────
( cd "$R" && git check-ignore -q "$HIDDEN" ) \
    && ok "(0) git ignores $HIDDEN (the fixture is what the arms assume)" \
    || no "(0) git does NOT ignore $HIDDEN — every later arm is vacuous"
( cd "$R" && git check-ignore -q kept.bak ) \
    && no "(0) git ignores kept.bak though it is tracked — the fixture's force-add did not take" \
    || ok "(0) git does not ignore the TRACKED kept.bak despite the *.bak rule"
[ "$AUX_UNIGNORED" -eq $(( AUX_TOTAL - 1 )) ] \
    && ok "(0) $AUX_UNIGNORED of $AUX_TOTAL aux files survive git's ignore rules (exactly the hidden one does not)" \
    || no "(0) expected $(( AUX_TOTAL - 1 )) unignored aux files, git says $AUX_UNIGNORED"
if command -v rg >/dev/null 2>&1; then
    ( cd "$R" && rg -l rwIgnNeedleShared . 2>/dev/null | grep -q "$HIDDEN" ) \
        && no "(0) rg served $HIDDEN — the independent tool disagrees with git about the fixture" \
        || ok "(0) rg does not open $HIDDEN (independent tool agrees)"
else
    ok "(0) rg absent — independent-tool cross-check skipped"
fi

# ── A) --grep: the served set is exactly git's not-ignored set; the hidden file appears nowhere ───────
A_OUT="$( rw --grep=rwIgnNeedleShared )"
A_RW="$( printf '%s' "$A_OUT" | served )"
A_OR="$( oracle rwIgnNeedleShared )"
if [ "$A_RW" = "$A_OR" ]; then
    ok "(A) --grep serves exactly the files git does not ignore: $( printf '%s' "$A_OR" | tr '\n' ' ' )"
else
    no "(A) --grep's served set differs from git's not-ignored set"
    printf '        ripwire: %s\n' "$( printf '%s' "$A_RW" | tr '\n' ' ' )"
    printf '        git    : %s\n' "$( printf '%s' "$A_OR" | tr '\n' ' ' )"
fi
printf '%s' "$A_OUT" | grep -q "$HIDDEN" \
    && no "(A) the gitignored $HIDDEN appears in the --grep answer" \
    || ok "(A) the gitignored $HIDDEN appears nowhere in the --grep answer"
# the hidden file's PRIVATE needle: a zero here is the whole point, and the legend's complete= governs it
[ "$( rw --grep=rwIgnNeedleHiddenOnly | served | grep -c . )" -eq 0 ] \
    && ok "(A) a needle that lives only in the ignored file answers zero files" \
    || no "(A) a needle that lives only in the ignored file still finds it"

# ── B) --regex, the pattern the report was filed with ─────────────────────────────────────────────────
B_RW="$( rw --regex='^#include' | served )"
B_OR="$( oracle '^#include' )"
if [ "$B_RW" = "$B_OR" ]; then
    ok "(B) --regex='^#include' serves exactly git's not-ignored set: $( printf '%s' "$B_OR" | tr '\n' ' ' )"
else
    no "(B) --regex's served set differs from git's not-ignored set"
    printf '        ripwire: %s\n' "$( printf '%s' "$B_RW" | tr '\n' ' ' )"
    printf '        git    : %s\n' "$( printf '%s' "$B_OR" | tr '\n' ' ' )"
fi

# ── C) unindexed_files_scanned= describes what was served ─────────────────────────────────────────────
C_N="$( printf '%s' "$A_OUT" | attr unindexed_files_scanned )"
[ "${C_N:-x}" = "$AUX_UNIGNORED" ] \
    && ok "(C) unindexed_files_scanned=$C_N = the $AUX_UNIGNORED aux files git does not ignore" \
    || no "(C) unindexed_files_scanned=${C_N:-absent}, want $AUX_UNIGNORED — the counter still counts the file the scan must not read"

# ── D) --skipped agrees with the grep root, and the hidden file is in NO class ─────────────────────────
D_OUT="$( "$BIN" "$R" --skipped --no-cache 2>/dev/null )"
D_UNS="$( printf '%s' "$D_OUT" | attr unsupported_ext )"
D_IGN="$( printf '%s' "$D_OUT" | attr ignored )"
[ "${D_UNS:-x}" = "$AUX_UNIGNORED" ] \
    && ok "(D) --skipped unsupported_ext=$D_UNS = the $AUX_UNIGNORED aux files git does not ignore" \
    || no "(D) --skipped unsupported_ext=${D_UNS:-absent}, want $AUX_UNIGNORED"
[ "${D_UNS:-x}" = "${C_N:-y}" ] \
    && ok "(D) unsupported_ext= ($D_UNS) and unindexed_files_scanned= ($C_N) describe the same population" \
    || no "(D) unsupported_ext=${D_UNS:-absent} disagrees with unindexed_files_scanned=${C_N:-absent}"
printf '%s' "$D_OUT" | grep -q "p=\"$HIDDEN\"" \
    && no "(D) --skipped still rows $HIDDEN ($( printf '%s' "$D_OUT" | grep -oE "p=\"$HIDDEN\" why=\"[^\"]*\"" | head -1 | grep -oE 'why="[^"]*"' ))" \
    || ok "(D) --skipped has no row for $HIDDEN — requested absence of an unread language is no class"
printf '%s' "$D_OUT" | grep -q '<e x=".bak" files="1"/>' \
    && ok "(D) the <e x=.bak> histogram counts the tracked .bak only (files=1)" \
    || no "(D) the <e x=.bak> histogram still counts the ignored file: $( printf '%s' "$D_OUT" | grep -oE '<e x=".bak" files="[0-9]+"/>' | head -1 )"
[ "${D_IGN:-x}" = "0" ] \
    && ok "(D) ignored=0 — an ignored file of an unindexed extension is not counted as would-have-been-indexed" \
    || no "(D) ignored=${D_IGN:-absent}: the accounting invariant (indexed+oversize+excluded+ignored) now counts a file that could never have been indexed"

# ── E) --no-ignore is a real escape hatch ──────────────────────────────────────────────────────────────
E_OUT="$( rw --grep=rwIgnNeedleShared --no-ignore )"
E_RW="$( printf '%s' "$E_OUT" | served )"
E_OR="$( oracle_all "$R" rwIgnNeedleShared )"
[ "$E_RW" = "$E_OR" ] \
    && ok "(E) --no-ignore serves every text file, ignored or not: $( printf '%s' "$E_OR" | tr '\n' ' ' )" \
    || { no "(E) --no-ignore did not restore the full set"; printf '        ripwire: %s\n        tree   : %s\n' "$( printf '%s' "$E_RW" | tr '\n' ' ' )" "$( printf '%s' "$E_OR" | tr '\n' ' ' )"; }
E_N="$( printf '%s' "$E_OUT" | attr unindexed_files_scanned )"
E_UNS="$( "$BIN" "$R" --skipped --no-ignore --no-cache 2>/dev/null | attr unsupported_ext )"
[ "${E_N:-x}" = "$AUX_TOTAL" ] && [ "${E_UNS:-x}" = "$AUX_TOTAL" ] \
    && ok "(E) under --no-ignore both counts grow to $AUX_TOTAL (unindexed_files_scanned=$E_N, unsupported_ext=$E_UNS)" \
    || no "(E) under --no-ignore the counts are unindexed_files_scanned=${E_N:-absent} unsupported_ext=${E_UNS:-absent}, want $AUX_TOTAL"

# ── F) a NON-GIT root is unchanged ─────────────────────────────────────────────────────────────────────
cp -R "$R" "$TMP/nogit"; rm -rf "$TMP/nogit/.git"
F_RW="$( "$BIN" "$TMP/nogit" --grep=rwIgnNeedleShared --grep-in=any --limit=100000 --no-cache 2>/dev/null | served )"
F_OR="$( oracle_all "$TMP/nogit" rwIgnNeedleShared )"
[ "$F_RW" = "$F_OR" ] \
    && ok "(F) a non-git root serves every text file (no ignore rules to honour)" \
    || { no "(F) a non-git root lost files — the feature shrank a corpus it cannot explain"; printf '        ripwire: %s\n' "$( printf '%s' "$F_RW" | tr '\n' ' ' )"; }

# ── G) the MCP grep verb serves the same population ───────────────────────────────────────────────────
mcp_text(){
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$1" \
        | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c '
import sys, json
r = json.load( sys.stdin )
print( "__ERROR__:" + r[ "error" ].get( "message", "" ) if "error" in r else r[ "result" ][ "content" ][ 0 ][ "text" ] )
'
}
call(){ printf '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"%s","arguments":%s}}' "$1" "$2"; }
mcp_text "$( call grep '{"path":"'"$R"'","pattern":"rwIgnNeedleShared"}' )" >"$TMP/mcp.json"
G_RW="$( python3 -c '
import json, sys
j = json.load( open( sys.argv[ 1 ] ) )
files = { h.get( "file", "" ) for h in j.get( "hits", [] ) } | { r.get( "file", "" ) for r in j.get( "unindexed", {} ).get( "rows", [] ) }
print( "\n".join( sorted( files ) ) )
print( "scanned=%s" % j.get( "unindexed_files_scanned", "absent" ) )
' "$TMP/mcp.json" 2>/dev/null )"
G_SET="$( printf '%s\n' "$G_RW" | grep -v '^scanned=' )"
G_N="$( printf '%s\n' "$G_RW" | grep '^scanned=' | cut -d= -f2 )"
[ "$G_SET" = "$A_OR" ] \
    && ok "(G) MCP grep serves exactly git's not-ignored set" \
    || { no "(G) MCP grep's served set differs from git's not-ignored set"; printf '        mcp: %s\n' "$( printf '%s' "$G_SET" | tr '\n' ' ' )"; head -c 300 "$TMP/mcp.json"; echo; }
[ "${G_N:-x}" = "$AUX_UNIGNORED" ] \
    && ok "(G) MCP unindexed_files_scanned=$G_N agrees with the CLI" \
    || no "(G) MCP unindexed_files_scanned=${G_N:-absent}, want $AUX_UNIGNORED"

# ── H) determinism ─────────────────────────────────────────────────────────────────────────────────────
rw --grep=rwIgnNeedleShared >"$TMP/d1"; rw --grep=rwIgnNeedleShared >"$TMP/d2"
if diff -q "$TMP/d1" "$TMP/d2" >/dev/null; then ok "(H) two runs byte-identical"; else no "(H) output is nondeterministic"; fi

# ── I) MUTATION self-tests: each assertion must be able to see its own regression ─────────────────────
# (A) equality: the oracle with the hidden file appended is the pre-fix served set — must NOT equal.
MUT_A="$( printf '%s\n%s\n' "$A_OR" "$HIDDEN" | sort -u )"
[ "$MUT_A" = "$A_OR" ] \
    && no "(I) mutation (hidden file added to the served set): still equals the oracle — (A) is decoration" \
    || ok "(I) mutation (hidden file added to the served set) correctly FAILS assertion (A)"
# (A) absence: the probe must SEE the hidden file when it is legitimately served (the --no-ignore answer).
printf '%s' "$E_OUT" | grep -q "$HIDDEN" \
    && ok "(I) mutation control: the absence probe sees $HIDDEN in the --no-ignore answer — (A) is not vacuous" \
    || no "(I) mutation control: the absence probe cannot see $HIDDEN even when it is served"
# (C)/(D) counters: the --no-ignore count differs from the default expectation, so the comparison can fire.
[ "${E_N:-x}" = "$AUX_UNIGNORED" ] \
    && no "(I) mutation (count under --no-ignore) still equals the default expectation — (C) is decoration" \
    || ok "(I) mutation (count under --no-ignore = ${E_N:-absent}) correctly FAILS assertion (C)"
# (B) regex: perturbing one path in the served set must break the oracle comparison.
MUT_B="$( printf '%s\n' "$B_OR" | sed '1s/$/.moved/' )"
[ "$MUT_B" = "$B_OR" ] \
    && no "(I) mutation (one path renamed): still equals the oracle — (B) is decoration" \
    || ok "(I) mutation (one path renamed) correctly FAILS assertion (B)"

# ── J) G4: well-formed XML ─────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    if printf '%s' "$A_OUT" | xmllint --noout - 2>/dev/null; then ok "(J) xml well-formed (xmllint)"; else no "(J) xml malformed"; fi
    if printf '%s' "$D_OUT" | xmllint --noout - 2>/dev/null; then ok "(J) --skipped xml well-formed (xmllint)"; else no "(J) --skipped xml malformed"; fi
else
    ok "(J) xmllint absent — skipped"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
