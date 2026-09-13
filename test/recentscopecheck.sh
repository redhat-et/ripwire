#!/usr/bin/env bash
# recentscopecheck.sh — gate for `--rank-by=churn-decay --in=DIR` (C1-b, 2026-09-12): the directory-scoped
# recent-changes block, ADDITIVE to the global one, with the symbol map collapsed to a counted stub.
#
# WHY THIS GATE EXISTS. "What changed recently in DIR?" is six of the thirty head-to-head questions, and the
# verb answered it with a whole-repo symbol map (196 KB of a 237 KB answer on the reference corpus) plus ONE
# global <recent n="40"> block that a directory with more than 40 recently-touched files never fits into.
# C1-b adds `--in=DIR`: the global block stays byte-identical (three of the six golds sit OUTSIDE the named
# directory and complete only through it), a second <recent scope="DIR"> block follows it with DIR's files
# only — p= root-relative, exactly as the global block spells them, because a sub-root-relative spelling
# missed every held-out gold (0/30 raw vs 19/30 prefixed) — cut at 40 rows with capped="1" and a pasteable
# next= that pages by --offset=N, and the symbol map the caller did not ask for becomes a disclosed stub
# <symbols total=N shown="0" next=/> (docs/METHODOLOGY.md §9.3: a disclosed cut is still terminal).
#
# Arms:
#   0  fixture guards: 53 commits; the bare run emits <recent n="40" of="53">.
#   1  --in=db: exit 0; a SECOND block <recent scope="db" n="40" of="45" … capped="1" next=…> follows the
#      global one; every <rc p=> in it starts with "db/" (root-relative, the global block's spelling).
#   2  the GLOBAL block is byte-identical to the run without --in= (additive, never replacing).
#   3  paging: next= is `--rank-by=churn-decay --in=db --offset=40`; the page returns the 5 rows the first
#      page did not, NO overlap, union == git's own file list for db/; the oldest db file (position 45)
#      is on page 2 and not on page 1; the pasted next= (shlex-split) reproduces page 2 byte-for-byte;
#      --limit=10 windows the page and next= carries --limit=10 --offset=10.
#   4  a gold OUTSIDE db (gold_outside.py, touched by HEAD) stays FIRST in the global block and is absent
#      from the scoped one.
#   5  the stub: <symbols total="N" shown="0" next="--rank-by=churn-decay"/> replaces the <f> groups;
#      N equals the un-stubbed map's shown= AND its <s> row count; the header's own shown= reads 0.
#   6  refusals (exit 1, empty stdout, a message that names the remedy): --in= on --rank-by=churn, on
#      --hotspots, alone, with --json, with --top-k=0; DIR missing, DIR a file, DIR absolute, DIR with "..".
#   7  a DIR with a space and a DIR starting with '-' work; a trailing slash normalises.
#   8  merge_bombs_skipped= rides BOTH blocks.
#   9  determinism (two runs byte-identical), well-formed XML, both legends define scope= and the stub.
#
# RED against the pre-change binary: `--in=` is an unknown flag, so every arm below fails.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/recentscopecheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "recentscopecheck: git is required"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "recentscopecheck: python3 is required (shlex for the pasted next=)"; exit 2; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
echo "recentscopecheck: BIN=$BIN"

# ── the fixture: one commit per file, ages distinct, HEAD's clock the anchor ─────────────────────────
# db/f00.py .. db/f44.py  — 45 files, f00 committed FIRST (oldest), f44 last: age ascending puts f44 at row 1
#                          and f00 at row 45, so the 40-row page cuts f00..f04 onto page 2.
# util/u0..u2.py          — 3 files, older than every db file.
# "my dir"/m0,m1.py       — a directory with a space.
# -dash/d0,d1.py          — a directory whose name starts with '-'.
# gold_outside.py         — touched by HEAD itself: the newest file in the repo, OUTSIDE db/.
REPO="$WORK/repo"; mkdir -p "$REPO/db" "$REPO/util" "$REPO/my dir" "$REPO/-dash"
git -C "$REPO" init -q 2>/dev/null
git -C "$REPO" config user.email rw@example.invalid
git -C "$REPO" config user.name  ripwire-gate
NOW="$( date +%s )"
BASE="$(( NOW - 400 * 86400 ))"
n=0
commitOne()   # $1 = path (relative), $2 = symbol name
{
    n=$(( n + 1 ))
    local stamp="$(( BASE + n * 86400 ))"
    printf 'def %s():\n    return %d\n' "$2" "$n" > "$REPO/$1"
    GIT_AUTHOR_DATE="$stamp +0000" GIT_COMMITTER_DATE="$stamp +0000" git -C "$REPO" add -A >/dev/null 2>&1
    GIT_AUTHOR_DATE="$stamp +0000" GIT_COMMITTER_DATE="$stamp +0000" git -C "$REPO" commit -q -m "touch $1" >/dev/null 2>&1
}
for i in 0 1 2; do commitOne "util/u$i.py" "util_$i"; done
for i in 0 1; do commitOne "my dir/m$i.py" "mdir_$i"; done
for i in 0 1; do commitOne "-dash/d$i.py" "dash_$i"; done
i=0
while [ "$i" -le 44 ]; do commitOne "db/f$( printf '%02d' "$i" ).py" "db_$i"; i=$(( i + 1 )); done
commitOne "gold_outside.py" "gold_outside"

# PRESENCE GUARDS (CONTRIBUTING §2): the arms are meaningless if the fixture has no history, or if the bare
# verb does not emit the global block the scoped one is measured against.
[ "$( git -C "$REPO" rev-list --count HEAD 2>/dev/null )" = 53 ] \
    && ok "arm 0a: fixture has 53 commits" \
    || no "arm 0a: fixture does not have 53 commits (got $( git -C "$REPO" rev-list --count HEAD 2>/dev/null ))"
[ "$( git -C "$REPO" ls-files db | grep -c . )" = 45 ] \
    && ok "arm 0b: db/ holds 45 tracked files (> the 40-row page)" \
    || no "arm 0b: db/ does not hold 45 tracked files"

run(){ perl -e 'alarm 60; exec @ARGV' "$BIN" "$REPO" --no-cache "$@"; }
firstBlock(){  printf '%s' "$1" | grep -oE '<recent [^>]*>.*</recent>' | sed -E 's#</recent>.*##' | head -1; }   # the GLOBAL block, inner rows included
scopedTag(){   printf '%s' "$1" | grep -oE '<recent scope="[^>]*>' | head -1; }   # the QUOTED attribute: the compact legend's prose spells <recent scope=DIR> bare
scopedRows(){  printf '%s' "$1" | sed -E 's#.*(<recent scope="[^>]*>)#\1#' | sed -E 's#</recent>.*##' | grep -oE '<rc p="[^"]*"' | sed 's/<rc p="//;s/"$//'; }
globalRows(){  firstBlock "$1" | grep -oE '<rc p="[^"]*"' | sed 's/<rc p="//;s/"$//'; }

BARE="$( run --rank-by=churn-decay 2>"$WORK/e0" )"; ec=$?
[ "$ec" = 0 ] && printf '%s' "$BARE" | grep -q '<recent n="40" of="53"' \
    && ok "arm 0c: the bare run emits <recent n=\"40\" of=\"53\"> (exit 0)" \
    || no "arm 0c: bare run exit=$ec, recent tag: $( printf '%s' "$BARE" | grep -oE '<recent [^>]*>' | head -1 )"
printf '%s' "$BARE" | grep -q '<recent scope="' && no "arm 0d: the bare run must NOT carry a scoped block" || ok "arm 0d: the bare run carries no scoped block"

# ── arm 1: --in=db adds a second, scoped block; every row is root-relative under db/ ─────────────────
IN="$( run --rank-by=churn-decay --in=db 2>"$WORK/e1" )"; ec=$?
if [ "$ec" = 0 ] && [ -n "$IN" ]; then
    ok "arm 1a: --rank-by=churn-decay --in=db accepted (exit 0, $( printf '%s' "$IN" | wc -c | tr -d ' ' ) B)"
else
    no "arm 1a: --in=db refused or empty (exit=$ec)"; sed 's/^/    /' "$WORK/e1" | head -3
fi
tag="$( scopedTag "$IN" )"
printf '%s' "$tag" | grep -q '^<recent scope="db" n="40" of="45" ' \
    && ok "arm 1b: scoped block opens <recent scope=\"db\" n=\"40\" of=\"45\" …> (got: $tag)" \
    || no "arm 1b: scoped block tag wrong or missing (got: '$tag')"
printf '%s' "$tag" | grep -q 'capped="1"' \
    && ok "arm 1c: the 45-file directory is capped=\"1\" at 40 rows" \
    || no "arm 1c: no capped=\"1\" on a 45-file directory"
gpos="$( printf '%s' "$IN" | grep -bo '<recent n=' | head -1 | cut -d: -f1 )"
spos="$( printf '%s' "$IN" | grep -bo '<recent scope="' | head -1 | cut -d: -f1 )"
[ -n "$gpos" ] && [ -n "$spos" ] && [ "$gpos" -lt "$spos" ] \
    && ok "arm 1d: the global block (byte $gpos) precedes the scoped one (byte $spos)" \
    || no "arm 1d: block order wrong (global at '$gpos', scoped at '$spos')"
rows1="$( scopedRows "$IN" )"
[ "$( printf '%s\n' "$rows1" | grep -c . )" = 40 ] \
    && ok "arm 1e: the scoped block prints 40 rows" \
    || no "arm 1e: scoped block prints $( printf '%s\n' "$rows1" | grep -c . ) rows, not 40"
bad="$( printf '%s\n' "$rows1" | grep -v '^db/' | head -3 | tr '\n' ' ' )"
[ -z "$bad" ] \
    && ok "arm 1f: every scoped p= starts with db/ (root-relative, the global block's own spelling)" \
    || no "arm 1f: scoped rows not under db/: $bad"
# the coordinator's binding finding: the SAME file must be spelled identically in both blocks
common="$( comm -12 <( printf '%s\n' "$rows1" | sort ) <( globalRows "$IN" | sort ) | grep -c . )"
[ "$common" -ge 1 ] \
    && ok "arm 1g: $common db/ paths appear in BOTH blocks with the identical spelling" \
    || no "arm 1g: no scoped p= matches a global p= byte-for-byte — the scoped spelling is not the global one"

# ── arm 2: the global block is byte-identical with and without --in= ────────────────────────────────
gb_bare="$( firstBlock "$BARE" )"; gb_in="$( firstBlock "$IN" )"
if [ -z "$gb_bare" ]; then
    no "arm 2: could not extract the global block from the bare run (vacuous)"
elif [ "$gb_bare" = "$gb_in" ]; then
    ok "arm 2: the global <recent> block is byte-identical with and without --in= ($( printf '%s' "$gb_bare" | wc -c | tr -d ' ' ) B)"
else
    no "arm 2: the global block CHANGED under --in=:"; printf '    bare: %.200s\n    in:   %.200s\n' "$gb_bare" "$gb_in"
fi

# ── arm 3: paging — next= is pasteable and the page is the exact remainder ──────────────────────────
next1="$( printf '%s' "$tag" | grep -oE 'next="[^"]*"' | sed 's/^next="//;s/"$//' )"
[ "$next1" = "--rank-by=churn-decay --in=db --offset=40" ] \
    && ok "arm 3a: next= is the page: $next1" \
    || no "arm 3a: next= is '$next1', expected '--rank-by=churn-decay --in=db --offset=40'"
P2="$( run --rank-by=churn-decay --in=db --offset=40 2>"$WORK/e3" )"; ec=$?
tag2="$( scopedTag "$P2" )"
[ "$ec" = 0 ] && printf '%s' "$tag2" | grep -q '^<recent scope="db" n="5" of="45" ' \
    && ok "arm 3b: page 2 opens <recent scope=\"db\" n=\"5\" of=\"45\" …> (got: $tag2)" \
    || no "arm 3b: page 2 exit=$ec, tag: '$tag2'"
printf '%s' "$tag2" | grep -q 'offset="40"' \
    && ok "arm 3c: page 2 says offset=\"40\"" \
    || no "arm 3c: page 2 lacks offset=\"40\""
[ -n "$tag2" ] && ! printf '%s' "$tag2" | grep -q 'capped=\|next=' \
    && ok "arm 3d: the last page carries no capped= and no next=" \
    || no "arm 3d: the last page must exist and carry neither capped= nor next= (got: '$tag2')"
rows2="$( scopedRows "$P2" )"
overlap="$( comm -12 <( printf '%s\n' "$rows1" | sort ) <( printf '%s\n' "$rows2" | sort ) | grep -c . )"
[ -n "$rows1" ] && [ -n "$rows2" ] && [ "$overlap" = 0 ] \
    && ok "arm 3e: pages 1 and 2 share no row" \
    || no "arm 3e: $overlap rows appear on both pages (or a page is empty)"
union="$( printf '%s\n%s\n' "$rows1" "$rows2" | grep . | sort -u )"
gitdb="$( git -C "$REPO" ls-files db | sort -u )"
[ "$union" = "$gitdb" ] && ok "arm 3f: page 1 ∪ page 2 == git's own db/ file list (45 files, none dropped, none invented)" \
                        || no "arm 3f: the two pages do not reproduce git's db/ list (union $( printf '%s\n' "$union" | grep -c . ), git $( printf '%s\n' "$gitdb" | grep -c . ))"
printf '%s\n' "$rows2" | grep -qx 'db/f00.py' && ! printf '%s\n' "$rows1" | grep -qx 'db/f00.py' \
    && ok "arm 3g: the oldest db file (row 45) is reachable on page 2 and absent from page 1" \
    || no "arm 3g: db/f00.py is not exactly on page 2 (page1: $( printf '%s\n' "$rows1" | grep -c 'db/f00.py' ), page2: $( printf '%s\n' "$rows2" | grep -c 'db/f00.py' ))"
# the pasted next=, split the way a shell would, reproduces page 2 byte for byte
PASTED="$( python3 -c 'import shlex,subprocess,sys; sys.stdout.write(subprocess.run([sys.argv[1],sys.argv[2],"--no-cache"]+shlex.split(sys.argv[3]),capture_output=True,text=True).stdout)' "$BIN" "$REPO" "$next1" )"
[ -n "$PASTED" ] && [ "$PASTED" = "$P2" ] \
    && ok "arm 3h: the pasted next= reproduces page 2 byte-for-byte" \
    || no "arm 3h: the pasted next= does not reproduce page 2"
L10="$( run --rank-by=churn-decay --in=db --limit=10 2>/dev/null )"
tagL="$( scopedTag "$L10" )"
printf '%s' "$tagL" | grep -q '^<recent scope="db" n="10" of="45" ' && printf '%s' "$tagL" | grep -q 'next="--rank-by=churn-decay --in=db --offset=10 --limit=10"' \
    && ok "arm 3i: --limit=10 windows the page (n=\"10\") and next= carries --offset=10 --limit=10" \
    || no "arm 3i: --limit=10 page wrong (got: $tagL)"
[ "$( scopedRows "$L10" | grep -c . )" = 10 ] && [ "$( scopedRows "$L10" | head -10 )" = "$( printf '%s\n' "$rows1" | head -10 )" ] \
    && ok "arm 3j: --limit=10's rows are the first 10 of the default page (same order)" \
    || no "arm 3j: --limit=10's rows differ from the default page's head"
P9="$( run --rank-by=churn-decay --in=db --offset=99 2>/dev/null )"
printf '%s' "$( scopedTag "$P9" )" | grep -q '^<recent scope="db" n="0" of="45" ' \
    && ok "arm 3k: an offset past the end is an empty page (n=\"0\" of=\"45\"), never an error" \
    || no "arm 3k: offset past the end: $( scopedTag "$P9" )"

# ── arm 4: a gold OUTSIDE the directory stays in the global block ───────────────────────────────────
[ "$( globalRows "$IN" | head -1 )" = "gold_outside.py" ] \
    && ok "arm 4a: gold_outside.py (HEAD's file) leads the global block under --in=db" \
    || no "arm 4a: global block's first row is '$( globalRows "$IN" | head -1 )', not gold_outside.py"
[ -n "$rows1" ] && ! printf '%s\n' "$rows1" "$rows2" | grep -q 'gold_outside' \
    && ok "arm 4b: the scoped block does not list the outside gold" \
    || no "arm 4b: gold_outside.py leaked into the scoped block (or the block is empty)"

# ── arm 5: the symbol map collapses to a counted stub ───────────────────────────────────────────────
stub="$( printf '%s' "$IN" | grep -oE '<symbols [^>]*/>' | head -1 )"
bareShown="$( printf '%s' "$BARE" | grep -oE ' shown=[0-9]+' | head -1 | tr -dc '0-9' )"
bareRows="$( printf '%s' "$BARE" | grep -o '<s ' | wc -l | tr -d ' ' )"
[ -n "$bareShown" ] && [ "$bareShown" = "$bareRows" ] && ok "arm 5 guard: the un-stubbed map shows $bareShown symbol rows (header shown= agrees with the <s> count)" \
                                                     || no "arm 5 guard: un-stubbed shown='$bareShown' vs <s> rows=$bareRows"
[ "$stub" = "<symbols total=\"$bareShown\" shown=\"0\" next=\"--rank-by=churn-decay\"/>" ] \
    && ok "arm 5a: the stub is $stub" \
    || no "arm 5a: stub is '$stub', expected <symbols total=\"$bareShown\" shown=\"0\" next=\"--rank-by=churn-decay\"/>"
printf '%s' "$IN" | grep -q '<f p=' && no "arm 5b: <f> groups are still emitted under --in= (the map was not stubbed)" || ok "arm 5b: no <f> group under --in= (the map is the stub)"
printf '%s' "$IN" | grep -qE ' shown=0 ' \
    && ok "arm 5c: the header's own shown= reads 0 under the stub (it cannot claim rows the document lacks)" \
    || no "arm 5c: header shown= is not 0 under the stub: $( printf '%s' "$IN" | grep -oE ' shown=[0-9]+' | head -1 )"
inBytes="$( printf '%s' "$IN" | wc -c | tr -d ' ' )"; bareBytes="$( printf '%s' "$BARE" | wc -c | tr -d ' ' )"
[ "$inBytes" -lt "$bareBytes" ] \
    && ok "arm 5d: the scoped answer is smaller than the bare map ($inBytes B < $bareBytes B) even with a second block added" \
    || no "arm 5d: scoped answer $inBytes B is not smaller than the bare $bareBytes B"

# ── arm 6: refusals — exit 1, empty stdout, a message that names the remedy ─────────────────────────
refuses(){   # $1 = label, $2 = expected stderr substring, $3.. = argv
    local label="$1" want="$2"; shift 2
    "$BIN" "$REPO" --no-cache "$@" >"$WORK/r.out" 2>"$WORK/r.err" </dev/null; local rc=$?
    if [ "$rc" != 1 ]; then
        no "$label: exit $rc, expected 1 ($( head -c 160 "$WORK/r.err" ))"
    elif [ -s "$WORK/r.out" ]; then
        no "$label: refused but wrote $( wc -c <"$WORK/r.out" | tr -d ' ' ) B to stdout"
    elif grep -qF -- "$want" "$WORK/r.err"; then
        ok "$label: refused (exit 1), message names \"$want\""
    else
        no "$label: refused with the WRONG message: $( head -1 "$WORK/r.err" )"
    fi
}
refuses "arm 6a: --in= with --rank-by=churn"  "--rank-by=churn-decay"  --rank-by=churn --in=db
refuses "arm 6b: --in= with --hotspots"       "--rank-by=churn-decay"  --hotspots --in=db
refuses "arm 6c: --in= alone"                 "--rank-by=churn-decay"  --in=db
refuses "arm 6d: --in= with --json"           "--json"                 --rank-by=churn-decay --in=db --json
refuses "arm 6e: --in= with --top-k=0"        "--top-k=0"              --rank-by=churn-decay --in=db --top-k=0
refuses "arm 6f: DIR does not exist"          "not a directory"        --rank-by=churn-decay --in=nope
refuses "arm 6g: DIR is a file"               "not a directory"        --rank-by=churn-decay --in=db/f00.py
refuses "arm 6h: DIR absolute"                "root-relative"          --rank-by=churn-decay "--in=$REPO/db"
refuses "arm 6i: DIR climbs out"              "root-relative"          --rank-by=churn-decay --in=../repo/db
refuses "arm 6j: DIR is the root itself"      "root-relative"          --rank-by=churn-decay --in=.
"$BIN" "$REPO" --no-cache --rank-by=churn-decay --in= >"$WORK/r.out" 2>"$WORK/r.err" </dev/null; rc=$?
[ "$rc" = 1 ] && [ ! -s "$WORK/r.out" ] \
    && ok "arm 6k: --in= with an empty value is refused" \
    || no "arm 6k: --in= (empty) exit $rc"

# ── arm 7: a space and a leading dash in DIR; a trailing slash normalises ───────────────────────────
SP="$( run --rank-by=churn-decay "--in=my dir" 2>"$WORK/e7" )"; ec=$?
tagS="$( scopedTag "$SP" )"
[ "$ec" = 0 ] && printf '%s' "$tagS" | grep -q '^<recent scope="my dir" n="2" of="2" ' \
    && ok "arm 7a: --in='my dir' works (exit 0, $tagS)" \
    || no "arm 7a: --in='my dir' exit=$ec, tag '$tagS'"; [ "$ec" = 0 ] || sed 's/^/    /' "$WORK/e7" | head -2
[ "$( scopedRows "$SP" | grep -c '^my dir/' )" = 2 ] \
    && ok "arm 7b: both rows are spelled 'my dir/…'" \
    || no "arm 7b: rows under 'my dir' wrong: $( scopedRows "$SP" | tr '\n' ' ' )"
printf '%s' "$tagS" | grep -q 'capped=\|next=' && no "arm 7c: a 2-file directory must not be capped" || ok "arm 7c: a 2-file directory carries no capped= and no next="
DA2="$( run --rank-by=churn-decay "--in=-dash" 2>"$WORK/e7d" )"; ec=$?
[ "$ec" = 0 ] && printf '%s' "$( scopedTag "$DA2" )" | grep -q '^<recent scope="-dash" n="2" of="2" ' \
    && ok "arm 7d: --in=-dash (a directory starting with '-') works" \
    || no "arm 7d: --in=-dash exit=$ec, tag '$( scopedTag "$DA2" )'"; [ "$ec" = 0 ] || sed 's/^/    /' "$WORK/e7d" | head -2
TS="$( run --rank-by=churn-decay --in=db/ 2>/dev/null )"
[ "$( scopedTag "$TS" )" = "$tag" ] \
    && ok "arm 7e: --in=db/ (trailing slash) is the same answer as --in=db" \
    || no "arm 7e: --in=db/ tag differs: $( scopedTag "$TS" )"

# ── arm 8: merge_bombs_skipped= rides both blocks ───────────────────────────────────────────────────
printf '%s' "$( printf '%s' "$IN" | grep -oE '<recent n=[^>]*>' | head -1 )" | grep -q 'merge_bombs_skipped="0"' \
    && ok "arm 8a: the global block carries merge_bombs_skipped=\"0\"" \
    || no "arm 8a: global block lacks merge_bombs_skipped= ($( printf '%s' "$IN" | grep -oE '<recent n=[^>]*>' | head -1 ))"
printf '%s' "$tag" | grep -q 'merge_bombs_skipped="0"' \
    && ok "arm 8b: the scoped block carries merge_bombs_skipped=\"0\"" \
    || no "arm 8b: scoped block lacks merge_bombs_skipped= ($tag)"

# ── arm 9: determinism, well-formedness, legends ────────────────────────────────────────────────────
IN2="$( run --rank-by=churn-decay --in=db 2>/dev/null )"
[ -n "$IN" ] && [ "$IN" = "$IN2" ] \
    && ok "arm 9a: two --in=db runs are byte-identical ($inBytes B)" \
    || no "arm 9a: two --in=db runs differ"
if command -v xmllint >/dev/null 2>&1; then
    if printf '%s' "$IN" | xmllint --noout - 2>"$WORK/xl"; then
        ok "arm 9b: --in=db output is well-formed XML"
    else
        no "arm 9b: xmllint rejected --in=db output"; head -3 "$WORK/xl" | sed 's/^/    /'
    fi
    printf '%s' "$SP" | xmllint --noout - 2>/dev/null \
        && ok "arm 9c: --in='my dir' output is well-formed XML" \
        || no "arm 9c: xmllint rejected --in='my dir' output"
else
    no "arm 9b: xmllint missing — cannot verify well-formedness"
fi
printf '%s' "$IN" | grep -q 'scope=DIR' && printf '%s' "$IN" | grep -q 'symbols total=' \
    && ok "arm 9d: the full legend defines scope= and the symbols stub" \
    || no "arm 9d: the full legend does not define scope= / the stub"
INC="$( run --rank-by=churn-decay --in=db --legend=compact 2>/dev/null )"; ec=$?
[ "$ec" = 0 ] && printf '%s' "$INC" | grep -q 'scope=' && printf '%s' "$INC" | grep -q '<symbols total=' \
    && ok "arm 9e: the compact legend defines scope= and the <symbols> stub" \
    || no "arm 9e: compact legend (exit $ec) lacks scope= / the stub: $( printf '%s' "$INC" | grep -oE '<!-- ripwire map[^>]*-->' | head -c 400 )"
[ "$( scopedTag "$INC" )" = "$tag" ] \
    && ok "arm 9f: --legend=compact leaves the scoped block byte-identical" \
    || no "arm 9f: the scoped tag moved under --legend=compact: $( scopedTag "$INC" )"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
