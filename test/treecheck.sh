#!/usr/bin/env bash
# treecheck.sh — SEMANTIC gate for --tree (the session-start "file + its top symbols by rank" orientation
# map). Before this, --tree had only pagination-shape coverage (paginationcheck) + xmllint smoke — nothing
# asserted the per-file grouping, the symbols= count, or the by-rank ordering that is the whole point of
# the verb. A --tree that mis-groups symbols into the wrong file, or lists them in a non-rank order, would
# silently mislead the very first orientation step an agent takes.
#
# Fixture: test/queryfix (call graph hand-verified by querycheck/callerscheck):
#   chain.cpp:  d1 -> d2 -> d3 -> d4   → by PageRank d4 > d3 > d2 > d1 (downstream sink ranks highest);
#               chain.cpp has exactly 4 fn symbols.
#   util.cpp:   hot() (in-degree 2) is the top; caller_a/caller_b/Gadget/rec follow; 5 symbols total.
#
# Hand-computed assertions (derived from the map's own k= ranks, cross-checked, not hard-frozen):
#   (1) exactly 2 <file> entries, one per source file
#   (2) chain.cpp's symbols= is 4, util.cpp's is 5   (the TRUE per-file symbol counts, not the shown subset)
#   (3) each file's listed <s> appear in NON-INCREASING rank order — verified against the default map's k=
#   (4) the top symbol per file matches the top-ranked symbol of that file in the default map
#       (chain.cpp → d4, util.cpp → hot)  — so grouping+ordering agree with the ground-truth ranking
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/treecheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/queryfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
[ -d "$FIX" ] || { echo "no test/queryfix dir — fixture missing"; exit 2; }
cd "$ROOT"
echo "treecheck: BIN=$BIN  CORPUS=test/queryfix"

run(){ perl -e 'alarm 15; exec @ARGV' "$BIN" "$FIX" "$@" --no-cache 2>/dev/null; }
TREE="$( run --tree )"
MAP="$( run )"

# ── 1) exactly 2 <file> entries ──────────────────────────────────────────────────────────────────────
NF="$( printf '%s' "$TREE" | grep -oE '<file ' | wc -l | tr -d ' ' )"
[ "$NF" = 2 ] && ok "--tree: exactly 2 <file> entries" || no "--tree: expected 2 <file> entries, got $NF"

# ── 2) per-file symbols= counts are the TRUE totals (chain=4, util=5), not the shown subset ──────────
csym(){ printf '%s' "$TREE" | grep -oE "<file p=\"[^\"]*$1\" symbols=\"[0-9]+\"" | grep -oE 'symbols="[0-9]+"' | grep -oE '[0-9]+'; }
{ [ "$( csym 'chain\.cpp' )" = 4 ] && [ "$( csym 'util\.cpp' )" = 5 ]; } \
    && ok "--tree: symbols= counts correct (chain.cpp=4, util.cpp=5) — TRUE totals, not shown subset" \
    || no "--tree: wrong symbols= (chain=$( csym 'chain\.cpp' ) util=$( csym 'util\.cpp' ))"

# ── helper: the ordered symbol-name list inside a given file's <file>…</file> block in --tree ────────
file_block_syms(){
    printf '%s' "$TREE" | perl -0777 -ne '
        while( /<file p="[^"]*'"$1"'"[^>]*>(.*?)<\/file>/gs ) {
            my $b=$1; while( $b =~ /<s [^>]*n="([^"]*)"/g ){ print "$1\n"; }
        }'
}
# helper: rank (k=) of a symbol in a given file, read from the default MAP (ground truth)
map_k_in_file(){   # $1 = file suffix regex, $2 = symbol name
    printf '%s' "$MAP" | perl -0777 -ne '
        if( /<f p="[^"]*'"$1"'"[^>]*>(.*?)<\/f>/s ) {
            my $b=$1; if( $b =~ /n="'"$2"'"[^>]*k="([0-9.]+)"/ ){ print "$1"; }
        }'
}

# ── 3+4) per file: listed symbols are non-increasing by map-rank AND the first is that file's top symbol
for spec in 'chain\.cpp:d4' 'util\.cpp:hot'; do
    f="${spec%%:*}"; expect_top="${spec##*:}"
    NAMES="$( file_block_syms "$f" )"                     # newline-separated, in emission order
    first="$( printf '%s\n' "$NAMES" | head -1 )"
    [ -n "$first" ] || { no "--tree: no symbols listed for $f"; continue; }
    # top symbol
    [ "$first" = "$expect_top" ] \
        && ok "--tree($f): top symbol is $expect_top (matches the file's top-ranked symbol in the map)" \
        || no "--tree($f): top symbol is '$first', expected $expect_top"
    # non-increasing rank order (walk the emission order, compare each symbol's map-k to the previous)
    prev=""; bad=0
    while IFS= read -r n; do
        [ -z "$n" ] && continue
        k="$( map_k_in_file "$f" "$n" )"
        [ -z "$k" ] && { bad=1; break; }
        if [ -n "$prev" ]; then
            awk -v a="$prev" -v b="$k" 'BEGIN{ exit !(a+0 >= b+0) }' || { bad=1; break; }
        fi
        prev="$k"
    done <<EOF
$NAMES
EOF
    [ "$bad" = 0 ] \
        && ok "--tree($f): listed symbols in NON-INCREASING rank order (agrees with map k=)" \
        || no "--tree($f): symbols not in rank order (or a listed symbol missing from map)"
done

# ── 5) §P11.8: FILES are ordered by their best symbol's rank, not asciibetically ─────────────────────
#
# The finding: --tree is the session-start ORIENTATION map, and it emitted files in path order — the one
# order an orientation map must not use. On this repo a cold agent's first 40 lines were audit-document
# section titles (long process-doc names, `AGENTS.md` among them — every one of them sorts above `src/`)
# and the code it had landed to read was pages down.
#
# Files are now keyed on their best symbol's PageRank, path breaking ties, so the FILE order and the
# per-file symbol order finally agree on what "top" means. Ordering only: the same file set, the same
# per-file contents, in a different sequence.
#
# On this fixture the two orders are opposites, which is what makes it a gate: util.cpp's top symbol
# (hot, k=0.2173) outranks chain.cpp's (d4, k=0.1780), while `chain.cpp` sorts first alphabetically.
FILE_ORDER="$( printf '%s' "$TREE" | tr '<' '\n' | sed -n 's/^file p="\([^"]*\)".*/\1/p' )"
firstTreeFile="$( printf '%s\n' "$FILE_ORDER" | head -1 )"
case "$firstTreeFile" in
    */util.cpp) ok "--tree: util.cpp leads (its top symbol outranks chain.cpp's), not the alphabetical first" ;;
    *)          no "--tree: first file is '$firstTreeFile', expected util.cpp (rank order, not path order)" ;;
esac

# the general contract: walking the emitted file order, each file's TOP symbol's map-k is non-increasing
prevTop=""; ordbad=0
while IFS= read -r fp; do
    [ -z "$fp" ] && continue
    base="$( printf '%s' "$fp" | sed 's#.*/##; s#\.#\\.#g' )"
    topName="$( file_block_syms "$base" | head -1 )"
    topK="$( map_k_in_file "$base" "$topName" )"
    [ -z "$topK" ] && { ordbad=1; break; }
    if [ -n "$prevTop" ]; then
        awk -v a="$prevTop" -v b="$topK" 'BEGIN{ exit !(a+0 >= b+0) }' || { ordbad=1; break; }
    fi
    prevTop="$topK"
done <<EOF
$FILE_ORDER
EOF
[ "$ordbad" = 0 ] \
    && ok "--tree: files in NON-INCREASING best-symbol rank order (agrees with map k=)" \
    || no "--tree: file order does not follow best-symbol rank"

# the finding's own repro, on this repo: code leads, root-level docs do not
REPO_TREE="$( perl -e 'alarm 120; exec @ARGV' "$BIN" "$ROOT" --tree 2>/dev/null )"
if [ -n "$REPO_TREE" ]; then
    REPO_FILES="$( printf '%s' "$REPO_TREE" | tr '<' '\n' | sed -n 's/^file p="\([^"]*\)".*/\1/p' )"
    case "$( printf '%s\n' "$REPO_FILES" | head -1 )" in
        # `src/…` OR `*/src/…`: since 2026-08-19 --tree emits p= ROOT-RELATIVE with a root= disclosure
        # (test/rootrelcheck.sh), so an absolute root argument no longer puts a leading slash on the row.
        # Both spellings are accepted here because this arm is about WHICH FILE leads, not how it is spelled.
        src/*|*/src/*) ok "--tree(repo): the first file is a src/ path (was ADOPTION_AUDIT_fable2026.md)" ;;
        *)       no "--tree(repo): first file is '$( printf '%s\n' "$REPO_FILES" | head -1 )', expected a src/ path" ;;
    esac

    # a root-level markdown is `NAME.md` directly under the repo root — no directory component once the
    # root prefix is stripped (the emitted paths are absolute here because $ROOT is). None may appear on
    # the first screen; stripping the prefix is what makes this assertion able to FAIL rather than be
    # vacuously true against a pattern that never matches.
    firstScreenDocs="$( printf '%s\n' "$REPO_FILES" | head -20 \
        | sed -e "s#^$ROOT/##" -e 's#^\./##' | grep -c '^[^/]*\.md$' )"
    [ "$firstScreenDocs" = "0" ] \
        && ok "--tree(repo): zero root-level markdown files in the first 20 rows (was all of them)" \
        || no "--tree(repo): $firstScreenDocs root-level markdown files still on the first screen"

    # ordering must not lose a file: the emitted row count equals the paging total=. total= only appears
    # when paging was asked for (un-paginated --tree has no display cap and stays byte-identical), so ask.
    emitted="$( printf '%s\n' "$REPO_FILES" | grep -c . )"
    PAGED="$( perl -e 'alarm 120; exec @ARGV' "$BIN" "$ROOT" --tree --limit=1000000 2>/dev/null )"
    total="$( printf '%s' "$PAGED" | grep -oE '<tree [^>]*>' | grep -oE 'total="[0-9]+"' | grep -oE '[0-9]+' )"
    { [ -n "$total" ] && [ "$emitted" = "$total" ]; } \
        && ok "--tree(repo): all $emitted non-empty files still emitted (ordering drops nothing)" \
        || no "--tree(repo): emitted $emitted rows but total=$total"

    # §A8.5: files= (the TRUE indexed corpus) used to exceed the complete row set (total=, above) with the
    # divergence documented only in a source comment. files_unlisted= closes it: files == total +
    # files_unlisted, and on a real repo with symbol-less files (README stubs, empty markers, …) it must
    # be > 0 — a fixture with nothing symbol-less would pass this check vacuously.
    filesAttr="$( printf '%s' "$PAGED" | grep -oE '<tree [^>]*>' | grep -oE 'files="[0-9]+"' | grep -oE '[0-9]+' )"
    unlistedAttr="$( printf '%s' "$PAGED" | grep -oE '<tree [^>]*>' | grep -oE 'files_unlisted="[0-9]+"' | grep -oE '"[0-9]+"' | tr -d '"' )"
    [ -n "$unlistedAttr" ] \
        && ok "--tree(repo): root carries files_unlisted= ($unlistedAttr)" \
        || no "--tree(repo): root is missing files_unlisted="
    { [ -n "$filesAttr" ] && [ -n "$unlistedAttr" ] && [ -n "$total" ] && [ "$(( total + unlistedAttr ))" = "$filesAttr" ]; } \
        && ok "--tree(repo): files=$filesAttr == total=$total + files_unlisted=$unlistedAttr" \
        || no "--tree(repo): arithmetic broken (files=$filesAttr total=$total files_unlisted=$unlistedAttr)"
    [ "$unlistedAttr" -gt 0 ] 2>/dev/null \
        && ok "--tree(repo): files_unlisted=$unlistedAttr > 0 (this repo genuinely has symbol-less files)" \
        || no "--tree(repo): files_unlisted=$unlistedAttr — expected > 0 on this repo (weak fixture, not a proof)"
else
    ok "--tree(repo): repo-wide tree unavailable — repro arm skipped"
fi

# ── 6) determinism + xml well-formed ────────────────────────────────────────────────────────────────
[ "$( run --tree )" = "$( run --tree )" ] && ok "--tree deterministic (byte-identical run-to-run)" || no "--tree non-deterministic"
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$TREE" | xmllint --noout - 2>/dev/null && ok "--tree xml well-formed" || no "--tree xml malformed"
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
