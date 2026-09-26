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
#      --hotspots, alone, with --json, with --top-k=0; DIR missing, DIR a file, DIR absolute, DIR with "..";
#      and (6l/6m/6n) the DISPATCH-voided class — a report verb that answers before the default map ever
#      renders, which cli.h cannot see because it does not know the winner.
#   7  a DIR with a space and a DIR starting with '-' work; a trailing slash normalises; plus a mutation
#      control that proves the two "carries no capped=/next=" assertions can actually SEE those attributes.
#   8  merge_bombs_skipped= rides BOTH blocks.
#   9  determinism (two runs byte-identical), well-formed XML, both legends define scope= and the stub.
#  10  next= names THIS run's corpus and window, in full, however long — no length ceiling drops it.
#  11  the scoped block's ABSENCE rule is the global block's: absent ⇒ no history mined.
#  12  the crawl CEILING rides next= too: a hint emitted under --max-file-size=N replays N, so the page it
#      names is a page of the same corpus (it dropped the flag and landed on of="3" against of="2").
#  13  "history was mined" is propagated, not inferred from the rows: a window whose only commit touched no
#      INDEXED file prints n="0", where it used to print no block and read as "no history mined".
#
# RED against the pre-change binary: `--in=` is an unknown flag, so every arm below fails.
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/recentscopecheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "recentscopecheck: git is required"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "recentscopecheck: python3 is required (shlex for the pasted next=)"; exit 2; }
# A MISSING TOOL IS AN ENVIRONMENT, NOT A REGRESSION (CodeRabbit, review 5195637558). Both of these were
# handled below the line instead of here, and each failed in a way that blamed the binary: without perl,
# run() returned "" and nearly every arm reported the tool as broken; without xmllint, arm 9b printed FAIL
# and test/regression.sh reported this gate as a product regression for a tool the machine never had.
# Exit 2 is the house cannot-conclude, and it names WHICH tool so the reader does not have to guess.
command -v perl    >/dev/null 2>&1 || { echo "recentscopecheck: perl is required (the per-run 60 s alarm in run())"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "recentscopecheck: xmllint is required (arms 9b/9c verify well-formedness)"; exit 2; }

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

# EVERY RUN OF THE BINARY IN THIS GATE GOES THROUGH HERE, and that is a population rule, not a style one
# (CodeRabbit, review of #212, on the continuation replay below). A hang in an unbounded probe does not fail
# an arm: it burns the whole gate budget and pargates kills the gate with NO verdict row, which reads as a
# broken gate rather than a hung product. The review named one site; swept, this file had NINE that bypassed
# this helper — refuses(), composes(), the replayed next=, the derived shaper loop, --top-k=0, the case-fold
# and empty-value arms, and both runs inside wsFor() — two of them added by the very commits that fixed the
# earlier findings. They all route through runAt (or carry their own timeout, for the python replay) now, so
# a new arm inherits the bound by using the helper every other arm uses.
runAt(){ local r="$1"; shift; perl -e 'alarm 60; exec @ARGV' "$BIN" "$r" --no-cache "$@"; }   # arms 12/13 bring their own repo
run(){ runAt "$REPO" "$@"; }
# THE PASTED next=, split the way a shell would — one copy, used by arms 3h, 10d and 12d. Three inline
# copies of this python one-liner is the duplicate --exemplar would have found; it takes the repo because
# the corpus arms below are measured on fixtures of their own.
# BOUNDED like every other run here (see the sweep note above runAt): a replayed next= is a command this
# gate did not write, so it is exactly the invocation that could hang, and an unbounded subprocess.run would
# hang the whole gate with no row rather than failing this arm.
pasteNext(){ python3 -c 'import shlex,subprocess,sys
try:
    sys.stdout.write(subprocess.run([sys.argv[1],sys.argv[2],"--no-cache"]+shlex.split(sys.argv[3]),capture_output=True,text=True,timeout=60).stdout)
except subprocess.TimeoutExpired:
    sys.exit("pasteNext: the replayed continuation did not finish in 60s: " + sys.argv[3])' "$BIN" "$1" "$2"; }
firstBlock(){  printf '%s' "$1" | grep -oE '<recent [^>]*>.*</recent>' | sed -E 's#</recent>.*##' | head -1; }   # the GLOBAL block, inner rows included
scopedTag(){   printf '%s' "$1" | grep -oE '<recent scope="[^>]*>' | head -1; }   # the QUOTED attribute: the compact legend's prose spells <recent scope=DIR> bare
scopedRows(){  printf '%s' "$1" | sed -E 's#.*(<recent scope="[^>]*>)#\1#' | sed -E 's#</recent>.*##' | grep -oE '<rc p="[^"]*"' | sed 's/<rc p="//;s/"$//'; }
globalRows(){  firstBlock "$1" | grep -oE '<rc p="[^"]*"' | sed 's/<rc p="//;s/"$//'; }

# L1 (2026-09-19): the CLI default legend is compact and spells '<recent n= of=>' and '<s ' inside its comment, which firstBlock,
# the '<recent n=' greps and the '<s ' row counts would read as real elements; BARE/IN/M1/uns.xml ask for the full legend.
BARE="$( run --rank-by=churn-decay --legend=full 2>"$WORK/e0" )"; ec=$?
[ "$ec" = 0 ] && printf '%s' "$BARE" | grep -q '<recent n="40" of="53"' \
    && ok "arm 0c: the bare run emits <recent n=\"40\" of=\"53\"> (exit 0)" \
    || no "arm 0c: bare run exit=$ec, recent tag: $( printf '%s' "$BARE" | grep -oE '<recent [^>]*>' | head -1 )"
printf '%s' "$BARE" | grep -q '<recent scope="' && no "arm 0d: the bare run must NOT carry a scoped block" || ok "arm 0d: the bare run carries no scoped block"

# ── arm 1: --in=db adds a second, scoped block; every row is root-relative under db/ ─────────────────
IN="$( run --rank-by=churn-decay --legend=full --in=db 2>"$WORK/e1" )"; ec=$?
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
# capped= compares the PAGE to the total, so a LAST page of a cut listing still says capped="1" — pageview.h
# rule 3 (M2) defines it that way on purpose, and has_more="0" is what ends a paging loop. The assertion that
# matters here is has_more="0" with NO next=: nothing further to fetch, and nothing pasteable claiming there is.
if [ -n "$tag2" ] && printf '%s' "$tag2" | grep -q 'has_more="0"' && printf '%s' "$tag2" | grep -q 'next_offset="45"' && ! printf '%s' "$tag2" | grep -qE 'next='; then
    ok "arm 3d: the last page says has_more=\"0\" next_offset=\"45\" and carries no next="
else
    no "arm 3d: the last page must say has_more=\"0\" next_offset=\"45\" with no next= (got: '$tag2')"
fi
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
PASTED="$( pasteNext "$REPO" "$next1" )"
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
# The stub does NOT borrow the paging vocabulary: total= there would be the --top-k PAGE SIZE on a document
# whose header says symbols=N (pageview.h rule 2 reserves total= for THE total), and a shown= would drag a
# capped= with it (rule 3). It says what it is instead — stubbed="1" plus would_show=, the rows the same run
# without --in= would PRINT.
[ "$stub" = "<symbols stubbed=\"1\" would_show=\"$bareShown\" next=\"--rank-by=churn-decay\"/>" ] \
    && ok "arm 5a: the stub is $stub" \
    || no "arm 5a: stub is '$stub', expected <symbols stubbed=\"1\" would_show=\"$bareShown\" next=\"--rank-by=churn-decay\"/>"
printf '%s' "$stub" | grep -qE ' total=| shown=| capped=' \
    && no "arm 5a2: the stub must carry NO total=/shown=/capped= — that vocabulary belongs to a page (got: $stub)" \
    || ok "arm 5a2: the stub borrows no paging attribute (no total=, no shown=, no capped=)"
printf '%s' "$IN" | grep -q '<f p=' && no "arm 5b: <f> groups are still emitted under --in= (the map was not stubbed)" || ok "arm 5b: no <f> group under --in= (the map is the stub)"
printf '%s' "$IN" | grep -qE ' shown=0 ' \
    && ok "arm 5c: the header's own shown= reads 0 under the stub (it cannot claim rows the document lacks)" \
    || no "arm 5c: header shown= is not 0 under the stub: $( printf '%s' "$IN" | grep -oE ' shown=[0-9]+' | head -1 )"
# The map was not RANKED at all under the stub, so the header must not carry a convergence disclosure for a
# power iteration that never ran (prconverge.h isPageRank=false).
printf '%s' "$BARE" | grep -q 'pr_iters=' \
    && ok "arm 5c2 guard: the un-stubbed run DOES carry pr_iters= (the arm below can fail)" \
    || no "arm 5c2 guard: the bare churn-decay run carries no pr_iters= — arm 5c2 is vacuous"
printf '%s' "$IN" | grep -q 'pr_iters=' \
    && no "arm 5c2: the stubbed run carries pr_iters= for a ranking it never computed" \
    || ok "arm 5c2: no pr_iters=/pr_converged= under the stub — no power iteration ran"
inBytes="$( printf '%s' "$IN" | wc -c | tr -d ' ' )"; bareBytes="$( printf '%s' "$BARE" | wc -c | tr -d ' ' )"
[ "$inBytes" -lt "$bareBytes" ] \
    && ok "arm 5d: the scoped answer is smaller than the bare map ($inBytes B < $bareBytes B) even with a second block added" \
    || no "arm 5d: scoped answer $inBytes B is not smaller than the bare $bareBytes B"

# ── arm 6: refusals — exit 1, empty stdout, a message that names the remedy ─────────────────────────
refuses(){   # $1 = label, $2 = expected stderr substring, $3.. = argv
    local label="$1" want="$2"; shift 2
    runAt "$REPO" "$@" >"$WORK/r.out" 2>"$WORK/r.err" </dev/null; local rc=$?
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
# (the old arm 6e asserted the substring "--top-k=0", which the payload-only refusal ALSO printed — so
# deleting the --in guard left it green. Arms 6t/6u below assert the guard's own distinctive sentence, and
# arm 6v asserts that exactly one refusal is printed.)
refuses "arm 6f: DIR does not exist"          "not a directory"        --rank-by=churn-decay --in=nope
refuses "arm 6g: DIR is a file"               "not a directory"        --rank-by=churn-decay --in=db/f00.py
refuses "arm 6h: DIR absolute"                "root-relative"          --rank-by=churn-decay "--in=$REPO/db"
refuses "arm 6i: DIR climbs out"              "root-relative"          --rank-by=churn-decay --in=../repo/db
refuses "arm 6j: DIR is the root itself"      "root-relative"          --rank-by=churn-decay --in=.
# THE PREEMPTION CLASS (CodeRabbit, then the Fable review, on #212). cli.h can say "--rank-by=churn-decay is not
# selected"; it cannot say "something else is going to ANSWER". The refusal is DERIVED in main.cpp from the flag
# tables (inPreemptedBy, the shape htmlPreemptedBy uses) rather than from a list of verbs, so these arms are
# samples of a closed class and not the class itself: a report verb (6l/6m), the one that reaches the default map
# through a branch ahead of churn (6o --map-diff), the body riders that ride the map --in stubs (6p/6q), and the
# surfaces that dispatch before the map exists at all (6r --doctor, 6s --batch). 6n is the subtle member:
# --query DOES reach runDefaultMap, but through the lexical branch that replaces the churn ranking, so no
# <recent> block of either kind is built there either — voided like the rest, not a composition.
refuses "arm 6l: --in= voided by --lint winning dispatch"     "--lint"     --rank-by=churn-decay --in=db --lint
refuses "arm 6m: --in= voided by --hotspots winning dispatch" "--hotspots" --rank-by=churn-decay --in=db --hotspots
refuses "arm 6n: --in= voided by --query winning dispatch"    "--query"    --rank-by=churn-decay --in=db --query=f00
refuses "arm 6o: --in= voided by --map-diff"                  "--map-diff" --rank-by=churn-decay --in=db --map-diff
refuses "arm 6p: --in= voided by --expand"                    "--expand"   --rank-by=churn-decay --in=db --expand=db_0
refuses "arm 6q: --in= voided by --pack-signatures"           "--pack-signatures" --rank-by=churn-decay --in=db --pack-signatures
refuses "arm 6r: --in= voided by --doctor"                    "--doctor"   --rank-by=churn-decay --in=db --doctor
refuses "arm 6s: --in= voided by --batch"                     "--batch"    --rank-by=churn-decay --in=db --batch=-

# INERT IS NOT COMPETING (CodeRabbit, review of #212). firstFlagOutside answers "which set flag is not a
# ride-along", and the generic refusal then says that flag "answers instead". For --no-redact that was FALSE:
# it selects no operation, it only stops body redaction, and a scoped run serves no bodies at all (the symbol
# map is the counted stub). It is refused ahead of the generic diagnostic now, saying exactly that. Arm 6s2b is
# the control: a flag that really does emit its own answer must KEEP the generic wording, or this fix would
# have replaced one wrong sentence with another.
refuses "arm 6s2: --in= with --no-redact says INERT, not answers-instead" "has nothing to un-redact" --rank-by=churn-decay --in=db --no-redact
refuses "arm 6s2b control: a real competitor keeps answers-instead"       "answers instead"          --rank-by=churn-decay --in=db --external-surface
# AND THE ARM THAT WAS MISSING. Both arms above pass --in, so neither could see that the new branch had no
# --in guard at all: it refused a plain `--no-redact` run while quoting --in=DIR at it. This one has no --in.
nr="$( runAt "$REPO" --no-redact --expand=db_0 2>&1 >/dev/null | head -1 )"
case "$nr" in
    *"--in=DIR"*) no "arm 6s2c: a run with NO --in was refused by the --in=DIR branch: $nr" ;;
    *)            ok "arm 6s2c: --no-redact without --in is untouched by the scoped refusal (stderr: ${nr:-clean})" ;;
esac

# AND THE MEMBER THE FIRST AUDIT MISSED, plus the derivation that makes a third impossible to miss
# (CodeRabbit, review of #212). The first audit of this class reported "every other flag hits its own pairing
# refusal first, and --external-surface is the only one reaching the generic diagnostic". That predicate was
# measured this time, over the derived universe (test/flaguniverse.py) rather than a sample: 119 of the 171
# bool/view rows firstFlagOutside walks reach the generic line, and 43 of them answer when run alone. So
# "answers alone" is not the predicate either -- --metrics answers alone, and what it answers IS the default
# map, decorated. The predicate is STRUCTURAL and already in main.cpp: a flag in kMapShapingFlags SHAPES the
# default map instead of answering instead of it, and kMapShapingFlags minus kInRideAlong is exactly
# {--no-redact, --metrics, --map-diff}. --map-diff is the one that genuinely preempts (it takes its own
# ranking branch ahead of churn-decay), so the inert set is the other two.
#
# Arm 6s2e derives that set HERE, from the two tables, and asserts every member says "inert" -- so a flag
# added to kMapShapingFlags tomorrow without a kInRideAlong row is caught tomorrow by this arm rather than by
# the next review. The set is re-read from source on every run; nothing about it is pinned in this file.
refuses "arm 6s2d: --in= with --metrics says INERT, not answers-instead" "inert here" --rank-by=churn-decay --in=db --metrics
refuses "arm 6s2d2 control: --map-diff really does preempt, so it keeps answers-instead" "answers instead" --rank-by=churn-decay --in=db --map-diff

shapers="$( python3 - "$ROOT/src/main.cpp" <<'PYEOF'
import re, sys
src = open(sys.argv[1]).read()
def table(name):
    body = src[src.index("kMapShapingFlags[] =" if name == "shape" else "kInRideAlong[] ="):]
    body = body[:body.index("};")]
    return set(re.findall(r'"(--[a-z0-9-]+)"', body))
inert = sorted(table("shape") - table("ride") - {"--map-diff"})
print(" ".join(inert))
PYEOF
)"
if [ -z "$shapers" ]; then
    no "arm 6s2e: derived the inert-shaper set as EMPTY -- the scrape of kMapShapingFlags/kInRideAlong broke, and an empty set would pass every assertion below vacuously"
else
    bad=""
    for f in $shapers; do
        runAt "$REPO" --rank-by=churn-decay --in=db "$f" >/dev/null 2>"$WORK/shaper.err" </dev/null
        grep -qF -- "inert here" "$WORK/shaper.err" || bad="$bad $f($( head -c 60 "$WORK/shaper.err" ))"
    done
    [ -z "$bad" ] && ok "arm 6s2e: every map-shaping flag that cannot ride along refuses as INERT, derived from the tables: $shapers" \
                  || no "arm 6s2e: derived inert shapers whose refusal does NOT say inert:$bad"
fi

# THE SHAPING FLAGS — one refusal per bad combination, and the composers really compose. --in used to be a row in
# kPagingHonoringVerbs, which is a VERB list: membership made validateShapingFlagsHonored refuse all three budget
# flags with a message that hands the caller a list of verbs and claims the default map honours the budgets it had
# just refused, and --top-k=0 printed THREE refusals at once. --in is a MODIFIER now: it refuses --top-k (any N —
# the map it sizes is the stub) in ONE message of its own, and --max-tokens/--token-budget shape the document that
# IS emitted.
refuses "arm 6t: --in= with --top-k=5"  "--top-k=N sizes exactly the rows the stub does not print" --rank-by=churn-decay --in=db --top-k=5
refuses "arm 6u: --in= with --top-k=0"  "--top-k=N sizes exactly the rows the stub does not print" --rank-by=churn-decay --in=db --top-k=0
runAt "$REPO" --rank-by=churn-decay --in=db --top-k=0 >/dev/null 2>"$WORK/tk0.err" </dev/null
[ "$( grep -c 'ripwire:' "$WORK/tk0.err" )" = 1 ] \
    && ok "arm 6v: --in= --top-k=0 prints exactly ONE refusal (it used to print three)" \
    || no "arm 6v: --in= --top-k=0 printed $( grep -c 'ripwire:' "$WORK/tk0.err" ) refusals: $( tr '\n' '|' <"$WORK/tk0.err" | head -c 300 )"
composes(){   # $1 = label, $2.. = argv — exit 0, a scoped block, stderr carries no refusal
    local label="$1"; shift
    runAt "$REPO" "$@" >"$WORK/c.out" 2>"$WORK/c.err" </dev/null; local rc=$?
    if [ "$rc" != 0 ]; then
        no "$label: exit $rc, expected 0 ($( head -c 200 "$WORK/c.err" ))"
    elif ! grep -q '<recent scope=' "$WORK/c.out"; then
        no "$label: exit 0 but no scoped block was emitted"
    elif grep -q 'ripwire:' "$WORK/c.err"; then
        no "$label: composed, but stderr carries a notice: $( head -c 200 "$WORK/c.err" )"
    else
        ok "$label: composes (exit 0, a scoped block, stderr clean)"
    fi
}
composes "arm 6w: --in= with --max-tokens"   --rank-by=churn-decay --in=db --max-tokens=4000
composes "arm 6x: --in= with --token-budget" --rank-by=churn-decay --in=db --token-budget=4000
composes "arm 6y: --in= with --limit/--offset" --rank-by=churn-decay --in=db --limit=5 --offset=2

# ── arm 6z: DIR is validated against the CRAWL, not only the filesystem ─────────────────────────────
# inDirIsUnderRoot asks the filesystem, and the filesystem answers a different question: on a case-folding
# volume --in=DB is a directory, a symlink alias is a directory, and a subtree --exclude dropped is a
# directory. All three used to exit 0 with <recent scope=… n="0" of="0"> — the typo-reads-as-nothing-changed
# answer the refusal exists to prevent. Each must now refuse, naming the crawl.
ln -s db "$REPO/dblink" 2>/dev/null
refuses "arm 6z1: --in=DIR excluded from the crawl" "no indexed file is under" --rank-by=churn-decay --exclude=db/ --in=db
refuses "arm 6z2: --in=DIR through a symlink alias" "no indexed file is under" --rank-by=churn-decay --in=dblink
if [ -d "$REPO/DB" ]; then   # only on a case-folding volume (APFS): elsewhere the fs check refuses first, which is also correct
    refuses "arm 6z3: --in=DIR case-folded by the volume" "no indexed file is under" --rank-by=churn-decay --in=DB
else
    runAt "$REPO" --rank-by=churn-decay --in=DB >"$WORK/cf.out" 2>"$WORK/cf.err" </dev/null; cfrc=$?
    [ "$cfrc" = 1 ] && [ ! -s "$WORK/cf.out" ] \
        && ok "arm 6z3: --in=DB refused (this volume is case-SENSITIVE, so the filesystem check refuses first — also correct)" \
        || no "arm 6z3: --in=DB exit $cfrc with $( wc -c <"$WORK/cf.out" | tr -d ' ' ) B on stdout"
fi
rm -f "$REPO/dblink"
runAt "$REPO" --rank-by=churn-decay --in= >"$WORK/r.out" 2>"$WORK/r.err" </dev/null; rc=$?
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
if printf '%s' "$tagS" | grep -q 'capped="0"' && ! printf '%s' "$tagS" | grep -qE 'next='; then
    ok "arm 7c: a 2-file directory says capped=\"0\" and carries no next="
else
    no "arm 7c: a 2-file directory must say capped=\"0\" with no next= (got: $tagS)"
fi
# MUTATION CONTROL for the negative half of arms 3d and 7c: the pattern must SEE a tag that carries next=, or
# a green there proves nothing. POSIX BRE does not define \\| as alternation, so the pre-fix spelling
# ('capped=\\|next=') could pass both on a tag that carried them (CodeRabbit, #212); every alternation in this
# gate is grep -qE now, and this arm is what keeps that true.
if printf '%s' '<recent scope="x" n="1" of="2" capped="1" next="--rank-by=churn-decay --in=x --offset=1">' | grep -qE 'next=' \
   && printf '%s' '<recent scope="x" n="1" of="2" capped="1" has_more="1">' | grep -qE 'capped=|next=' \
   && ! printf '%s' '<recent scope="x" n="1" of="1" capped="0">' | grep -qE 'next='; then
    ok "arm 7c control: the negative pattern sees next= on a mutant tag and stays quiet on a clean one"
else
    no "arm 7c control: the negative pattern cannot see next= on a mutant tag — arms 3d and 7c are inert"
fi
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
# merge_bombs_skipped= counts the WINDOW's skipped commits, not DIR's. Stamping it on a directory-scoped
# element reads as "N commits under DIR were skipped", which is a wrong answer for any DIR smaller than the
# repository — so it rides the GLOBAL block alone.
printf '%s' "$tag" | grep -q 'merge_bombs_skipped=' \
    && no "arm 8b: the scoped block carries merge_bombs_skipped= — that is the WINDOW's count, not DIR's ($tag)" \
    || ok "arm 8b: the scoped block carries no merge_bombs_skipped= (the window's count rides the global block alone)"

# ── arm 9: determinism, well-formedness, legends ────────────────────────────────────────────────────
IN2="$( run --rank-by=churn-decay --legend=full --in=db 2>/dev/null )"
[ -n "$IN" ] && [ "$IN" = "$IN2" ] \
    && ok "arm 9a: two --in=db runs are byte-identical ($inBytes B)" \
    || no "arm 9a: two --in=db runs differ"
# xmllint's presence is a PREREQUISITE (checked at the top, exit 2): an absent tool cannot make these two
# arms fail, and the `else no "xmllint missing"` that used to sit here reported the environment as a defect.
if printf '%s' "$IN" | xmllint --noout - 2>"$WORK/xl"; then
    ok "arm 9b: --in=db output is well-formed XML"
else
    no "arm 9b: xmllint rejected --in=db output"; head -3 "$WORK/xl" | sed 's/^/    /'
fi
printf '%s' "$SP" | xmllint --noout - 2>/dev/null \
    && ok "arm 9c: --in='my dir' output is well-formed XML" \
    || no "arm 9c: xmllint rejected --in='my dir' output"
printf '%s' "$IN" | grep -q 'scope=DIR' && printf '%s' "$IN" | grep -q 'symbols stubbed=1 would_show=' \
    && ok "arm 9d: the full legend defines scope= and the stubbed=/would_show= symbols stub" \
    || no "arm 9d: the full legend does not define scope= / the stub"
printf '%s' "$IN" | grep -q 'more than 100 INDEXED files' \
    && ok "arm 9d2: the full legend says merge_bombs_skipped= counts INDEXED files (what the rule measures)" \
    || no "arm 9d2: the full legend still says 'files' where the rule counts INDEXED files"
INC="$( run --rank-by=churn-decay --in=db --legend=compact 2>/dev/null )"; ec=$?
[ "$ec" = 0 ] && printf '%s' "$INC" | grep -q 'scope=' && printf '%s' "$INC" | grep -q 'stubbed=1 would_show=' \
    && ok "arm 9e: the compact legend defines scope= and the <symbols> stub" \
    || no "arm 9e: compact legend (exit $ec) lacks scope= / the stub: $( printf '%s' "$INC" | grep -oE '<!-- ripwire map[^>]*-->' | head -c 400 )"
# ...and DELETES the full clause it restates. Without a kCompactProsePrefixes row the ~640 B in=DIR prose
# survived beside the compact terms and was charged into est_tokens — the defect that row was added for.
printf '%s' "$INC" | grep -q '<!-- in=DIR:' \
    && no "arm 9e2: the full in=DIR prose clause survived --legend=compact (it is charged twice over)" \
    || ok "arm 9e2: --legend=compact replaces the in=DIR prose clause, as it does every other legend sentence"
bareCompactB="$( run --rank-by=churn-decay --legend=compact 2>/dev/null | wc -c | tr -d ' ' )"
inCompactB="$( printf '%s' "$INC" | wc -c | tr -d ' ' )"
[ -n "$bareCompactB" ] && [ "$inCompactB" -lt "$bareCompactB" ] \
    && ok "arm 9e3: the compact scoped answer is smaller than the compact bare map ($inCompactB B < $bareCompactB B)" \
    || no "arm 9e3: compact --in= is $inCompactB B against a bare $bareCompactB B"
[ "$( scopedTag "$INC" )" = "$tag" ] \
    && ok "arm 9f: --legend=compact leaves the scoped block byte-identical" \
    || no "arm 9f: the scoped tag moved under --legend=compact: $( scopedTag "$INC" )"

# ── arm 10: next= names THIS run's corpus, and says nothing rather than a hint that pastes wrong ────
# Both next= strings were hand-spelled as "--rank-by=churn-decay [--since=V]", so every corpus flag was
# dropped from the invocation the tool told the caller to paste: --in=db --exclude=db/f00.py reported a total
# the pasted page could not reproduce. One composer builds both now, replaying the run's own flags.
EX="$( run --rank-by=churn-decay --in=db --exclude=db/f00.py 2>/dev/null )"
tagEx="$( scopedTag "$EX" )"
nextEx="$( printf '%s' "$tagEx" | grep -oE 'next="[^"]*"' | sed 's/^next="//;s/"$//' )"
stubEx="$( printf '%s' "$EX" | grep -oE '<symbols [^>]*/>' | head -1 | grep -oE 'next="[^"]*"' | sed 's/^next="//;s/"$//' )"
ofEx="$( printf '%s' "$tagEx" | grep -oE 'of="[0-9]+"' | head -1 | tr -dc '0-9' )"
[ "$ofEx" = 44 ] \
    && ok "arm 10a guard: --exclude really shrinks the corpus (of=\"44\" against 45 unexcluded) and the page is still cut — the arms below can fail" \
    || no "arm 10a guard: --exclude=db/f00.py gave of='$ofEx', expected 44 — arms 10b/10d are vacuous"
case "$nextEx" in
    *--exclude=db/f00.py*) ok "arm 10b: the scoped next= replays --exclude: $nextEx" ;;
    *)                 no "arm 10b: the scoped next= drops --exclude — it names a DIFFERENT corpus: '$nextEx'" ;;
esac
case "$stubEx" in
    *--exclude=db/f00.py*) ok "arm 10c: the stub's next= replays --exclude: $stubEx" ;;
    *)                 no "arm 10c: the stub's next= drops --exclude: '$stubEx'" ;;
esac
# and the pasted page must reproduce the page it names, on the same corpus
P2EX="$( pasteNext "$REPO" "$nextEx" )"
ofP2="$( scopedTag "$P2EX" | grep -oE 'of="[0-9]+"' | head -1 | tr -dc '0-9' )"
[ -n "$ofP2" ] && [ "$ofP2" = "$ofEx" ] \
    && ok "arm 10d: the pasted next= lands on the SAME corpus (of=\"$ofP2\" both sides)" \
    || no "arm 10d: the pasted next= sees of=\"$ofP2\" where the page it came from saw of=\"$ofEx\""
# past 120 B the pasteable next= attribute used to be ABSENT — a hand-hacked "policed" ceiling in
# nextAttrXml that discarded a complete, runnable invocation instead of naming the loss (an earlier draft
# of this fix; REVERTED). The ruling: a complete answer in the fewest bytes still means a follow-up
# TERMINATES the search, so nextAttrXml (2026-09-25) now carries NO length ceiling at all — the full
# invocation is emitted whatever it costs, and it must actually paste and run.
# RED on origin/main (the base silently drops next= past 120 B — absent, and has_more="1" is the reader's
# only signal a page exists past this one, with no route back to it).
LONG="$( run --rank-by=churn-decay --in=db --exclude=util/u0.py --exclude=my --exclude=-dash --exclude=gold_outside.py --since='3 years ago' --limit=39 --offset=1 2>/dev/null )"
tagLong="$( scopedTag "$LONG" )"
# XML-unescape (the attribute's --since='3 years ago' round-trips through &apos;): the byte count and the
# pasted invocation must both be measured on the DECODED string, the same one nextAttrXml built and sized.
nextLong="$( printf '%s' "$tagLong" | grep -oE 'next="[^"]*"' | sed 's/^next="//;s/"$//' \
             | sed "s/&quot;/\"/g; s/&apos;/'/g; s/&lt;/</g; s/&gt;/>/g; s/&amp;/\&/g" )"
if [ -z "$tagLong" ]; then
    no "arm 10e: the long-invocation run emitted no scoped block (vacuous)"
elif [ -z "$nextLong" ]; then
    no "arm 10e: the over-120-byte next= is absent — nextAttrXml must emit it in full: $tagLong"
elif [ "${#nextLong}" -le 120 ]; then
    no "arm 10e: the fixture's next= is only ${#nextLong} B (<=120) — not a real test of the no-ceiling rule: $nextLong"
else
    ok "arm 10e: the over-120-byte next= is emitted in full (${#nextLong} B), never dropped"
fi
# and — the north star's own test — the full next= must actually PASTE AND RUN and land on the same page
if [ -n "$nextLong" ]; then
    ofLong="$( printf '%s' "$tagLong" | grep -oE 'of="[0-9]+"' | head -1 | tr -dc '0-9' )"
    P2LONG="$( pasteNext "$REPO" "$nextLong" )"
    ofP2Long="$( scopedTag "$P2LONG" | grep -oE 'of="[0-9]+"' | head -1 | tr -dc '0-9' )"
    [ -n "$ofP2Long" ] && [ "$ofP2Long" = "$ofLong" ] \
        && ok "arm 10f: the full over-120-byte next= runs and lands on the SAME corpus (of=\"$ofP2Long\" both sides)" \
        || no "arm 10f: the over-120-byte next= did not reproduce its own page — pasted of=\"$ofP2Long\", original of=\"$ofLong\": $nextLong"
else
    no "arm 10f: no next= to paste (arm 10e already failed)"
fi

# ── arm 11: the scoped block's ABSENCE rule is the global block's ──────────────────────────────────
# The legend promises "a SECOND recent block, riding when the global one does". A run that mined NOTHING
# printed no global block and a scoped n="0" of="0" anyway — a block claiming to have looked under DIR when
# no commit was read at all. Absent now means "no history mined"; n="0" means "mined, nothing under DIR".
EMPTYW="$( run --rank-by=churn-decay --in=db --since=HEAD 2>/dev/null )"
if printf '%s' "$EMPTYW" | grep -q '<recent '; then
    no "arm 11a: a window that mined nothing still printed a <recent> block: $( printf '%s' "$EMPTYW" | grep -oE '<recent [^>]*>' | head -2 | tr '\n' ' ' )"
else
    ok "arm 11a: a window that mined nothing prints NEITHER block (absence means 'no history mined')"
fi
printf '%s' "$EMPTYW" | grep -q '<symbols stubbed=' \
    && ok "arm 11b: the symbol map is still the stub on that run (the flag was honoured, not ignored)" \
    || no "arm 11b: no stub on the empty-window run — --in= was silently dropped"
EMPTYD="$( run --rank-by=churn-decay --in=util 2>/dev/null )"
printf '%s' "$( scopedTag "$EMPTYD" )" | grep -q '^<recent scope="util" n="3" of="3" ' \
    && ok "arm 11c guard: a directory WITH history prints its rows (n=\"3\" of=\"3\") — 11a is about absence, not emptiness" \
    || no "arm 11c guard: --in=util did not print 3 rows: $( scopedTag "$EMPTYD" )"

# ── arm 12: the corpus flag the continuation DROPPED — --max-file-size (CodeRabbit, review 5195637558) ──
# next= replays --exclude / --no-ignore / --ignore-tests / --since, and omitted the crawl's SIZE CEILING. A
# caller who pasted the hint re-crawled at the default 4 MB, indexed the files the run that emitted it had
# dropped as oversize, and landed on a page of a different answer: MEASURED of="2" on the run against of="3"
# on the page it named. Its own fixture, because the main one holds no oversize file and adding one there
# would move every of= above.
CEIL="$WORK/ceil"; mkdir -p "$CEIL/d"
git -C "$CEIL" init -q 2>/dev/null
git -C "$CEIL" config user.email rw@example.invalid
git -C "$CEIL" config user.name  ripwire-gate
ceilCommit(){ git -C "$CEIL" add -A >/dev/null 2>&1; git -C "$CEIL" commit -q -m "$1" >/dev/null 2>&1; }
printf 'def s1():\n    return 1\n' > "$CEIL/d/s1.py"; ceilCommit d/s1.py
printf 'def s2():\n    return 2\n' > "$CEIL/d/s2.py"; ceilCommit d/s2.py
{ printf 'def big():\n    return 0\n'; i=0; while [ "$i" -lt 200 ]; do printf '# filler %d — this file exists to exceed the 2K probe ceiling\n' "$i"; i=$(( i + 1 )); done; } > "$CEIL/d/big.py"
ceilCommit d/big.py
bigB="$( wc -c < "$CEIL/d/big.py" | tr -d ' ' )"
[ "$bigB" -gt 2048 ] \
    && ok "arm 12 guard: d/big.py is $bigB B, past the 2K ceiling the arms below crawl under" \
    || no "arm 12 guard: d/big.py is only $bigB B — arms 12a-12d are vacuous"
C1="$( runAt "$CEIL" --rank-by=churn-decay --in=d --max-file-size=2K --limit=1 2>/dev/null )"
tagC="$( scopedTag "$C1" )"
ofC="$( printf '%s' "$tagC" | grep -oE 'of="[0-9]+"' | head -1 | tr -dc '0-9' )"
[ "$ofC" = 2 ] \
    && ok "arm 12a guard: --max-file-size=2K really shrinks the corpus (of=\"2\" of d/'s 3 files) — the arms below can fail" \
    || no "arm 12a guard: --max-file-size=2K gave of='$ofC', expected 2 — arms 12b/12d are vacuous"
nextC="$( printf '%s' "$tagC" | grep -oE 'next="[^"]*"' | sed 's/^next="//;s/"$//' )"
case "$nextC" in
    *--max-file-size=*) ok "arm 12b: the scoped next= replays the crawl ceiling: $nextC" ;;
    *)                  no "arm 12b: the scoped next= drops --max-file-size — it names a DIFFERENT corpus: '$nextC'" ;;
esac
stubC="$( printf '%s' "$C1" | grep -oE '<symbols [^>]*/>' | head -1 | grep -oE 'next="[^"]*"' | sed 's/^next="//;s/"$//' )"
case "$stubC" in
    *--max-file-size=*) ok "arm 12c: the stub's next= replays the crawl ceiling: $stubC" ;;
    *)                  no "arm 12c: the stub's next= drops --max-file-size: '$stubC'" ;;
esac
PC="$( pasteNext "$CEIL" "$nextC" )"
ofPC="$( scopedTag "$PC" | grep -oE 'of="[0-9]+"' | head -1 | tr -dc '0-9' )"
[ -n "$ofPC" ] && [ "$ofPC" = "$ofC" ] \
    && ok "arm 12d: the pasted next= lands on the SAME corpus (of=\"$ofPC\" both sides)" \
    || no "arm 12d: the pasted next= sees of=\"$ofPC\" where the page it came from saw of=\"$ofC\""
# and the hint stays SHORT at the default: a flag that did not shape THIS crawl is not replayed, because the
# 120-byte budget is spent on the flags that can move of=.
nextDflt="$( scopedTag "$( runAt "$CEIL" --rank-by=churn-decay --in=d --limit=1 2>/dev/null )" | grep -oE 'next="[^"]*"' | sed 's/^next="//;s/"$//' )"
[ "$nextDflt" = "--rank-by=churn-decay --in=d --offset=1 --limit=1" ] \
    && ok "arm 12e: at the DEFAULT ceiling the hint carries no --max-file-size ($nextDflt)" \
    || no "arm 12e: the default-ceiling hint is '$nextDflt', expected '--rank-by=churn-decay --in=d --offset=1 --limit=1'"

# ── arm 13: "history was mined" is a FACT that travels, not one read back off the rows ──────────────
# A window can hold commits none of whose paths are INDEXED — the commit that DELETES a file is the smallest
# case, and a window of --exclude'd paths is the next. The annotation used to be inferred from what was
# emitted (no rows and no skipped merge bomb ⇒ no block), so that run was byte-indistinguishable from
# --since=HEAD, which reads no commit at all. Arm 11a's promise — "absent ⇒ no history mined" — was
# therefore FALSE in exactly this case. mined.anyHistory travels through ChurnRanking now and both blocks
# ride on the fact (src/prcontext.h's E1 rule: gate on the count, never on a match over the body).
MINED="$WORK/mined"; mkdir -p "$MINED/d"
git -C "$MINED" init -q 2>/dev/null
git -C "$MINED" config user.email rw@example.invalid
git -C "$MINED" config user.name  ripwire-gate
printf 'def keep():\n    return 1\n' > "$MINED/d/keep.py"; git -C "$MINED" add -A >/dev/null 2>&1; git -C "$MINED" commit -q -m c1 >/dev/null 2>&1
printf 'def gone():\n    return 2\n' > "$MINED/gone.py";   git -C "$MINED" add -A >/dev/null 2>&1; git -C "$MINED" commit -q -m c2 >/dev/null 2>&1
SINCE="$( git -C "$MINED" rev-parse HEAD )"
rm -f "$MINED/gone.py"; git -C "$MINED" add -A >/dev/null 2>&1; git -C "$MINED" commit -q -m c3 >/dev/null 2>&1
wCommits="$( git -C "$MINED" rev-list --count "$SINCE"..HEAD 2>/dev/null )"
wTouched="$( git -C "$MINED" log --name-only --format= "$SINCE"..HEAD 2>/dev/null | grep -c . )"
[ "$wCommits" = 1 ] && [ "$wTouched" = 1 ] && [ -z "$( git -C "$MINED" ls-files gone.py )" ] \
    && ok "arm 13 guard: the window holds 1 commit touching 1 path (gone.py), and gone.py is NOT in the index" \
    || no "arm 13 guard: window has $wCommits commit(s)/$wTouched path(s), gone.py tracked='$( git -C "$MINED" ls-files gone.py )' — arms 13a-13d are vacuous"
M1="$( runAt "$MINED" --rank-by=churn-decay --legend=full --since="$SINCE" 2>/dev/null )"
gTag="$( printf '%s' "$M1" | grep -oE '<recent [^>]*>' | head -1 )"
printf '%s' "$gTag" | grep -q '^<recent n="0" of="0" merge_bombs_skipped="0">' \
    && ok "arm 13a: a window that MINED a commit but touched no indexed file says n=\"0\" of=\"0\" ($gTag)" \
    || no "arm 13a: mined-but-zero-rows printed '$gTag', expected <recent n=\"0\" of=\"0\" merge_bombs_skipped=\"0\">"
M2="$( runAt "$MINED" --rank-by=churn-decay --in=d --since="$SINCE" 2>/dev/null )"
sTag="$( scopedTag "$M2" )"
printf '%s' "$sTag" | grep -q '^<recent scope="d" n="0" of="0" capped="0"' \
    && ok "arm 13b: the scoped block rides it too — <recent scope=\"d\" n=\"0\" of=\"0\" capped=\"0\" …>" \
    || no "arm 13b: the scoped block on a mined-but-empty window is '$sTag'"
printf '%s' "$sTag" | grep -qE 'next=' \
    && no "arm 13c: an empty scoped page must carry no next= ($sTag)" \
    || ok "arm 13c: an empty scoped page carries no next= (there is no page to fetch)"
# THE CONTRAST, and the whole point: a window that read NOTHING still prints neither block, so the two
# answers no longer look the same.
M3="$( runAt "$MINED" --rank-by=churn-decay --in=d --since=HEAD 2>/dev/null )"
if printf '%s' "$M3" | grep -q '<recent '; then
    no "arm 13d: --since=HEAD mines no commit, so it must print NEITHER block (got: $( printf '%s' "$M3" | grep -oE '<recent [^>]*>' | head -2 | tr '\n' ' ' ))"
elif printf '%s' "$M2" | grep -q '<recent '; then
    ok "arm 13d: mined-with-zero-rows (a block) and mined-nothing (no block) are now DIFFERENT documents"
else
    no "arm 13d: both windows print no block — the two answers are still indistinguishable"
fi


# THE NO-EVIDENCE NOTICE CANNOT CLAIM A RANKING THE SCOPED RUN NEVER RAN (CodeRabbit, review of #212). With no
# commits in the window the unscoped map really does fall back to the uniform prior, and the notice says so.
# Under --in=DIR nothing is ranked at all -- the rank vector is default-constructed and zero-filled, which is
# why no pr_iters= rides the header -- so the same sentence said three false things at once: it named a
# "uniform (structural) ranking" that did not run, called the document "this map" when the map is the counted
# stub and both <recent> blocks are absent, and offered --rank-by=pagerank as the byte-identical comparison
# when that flag is REFUSED beside --in. This arm pins all three, and 13f is the control: the unscoped
# no-evidence run must KEEP the uniform sentence, since there it is true.
nev="$( runAt "$REPO" --rank-by=churn-decay --in=db --since=HEAD 2>&1 >/dev/null | grep 'found no commits' | head -1 )"
if [ -z "$nev" ]; then
    no "arm 13e: a scoped run whose window mines nothing printed no no-evidence notice at all"
else
    bad=""
    case "$nev" in *"uniform (structural) ranking"*) bad="$bad claims-a-ranking-it-did-not-run" ;; esac
    case "$nev" in *"this map is"*)                  bad="$bad calls-the-stub-a-map" ;; esac
    case "$nev" in *"--rank-by=pagerank (header"*)   bad="$bad offers-a-comparison---in-refuses" ;; esac
    case "$nev" in *"nothing was ranked"*)           ;; *) bad="$bad does-not-say-nothing-was-ranked" ;; esac
    if [ -z "$bad" ]; then
        ok "arm 13e: the scoped no-evidence notice states what happened — nothing ranked, no block, the stub — and offers no refused comparison"
    else
        no "arm 13e: the scoped no-evidence notice is still wrong:$bad ($nev)"
    fi
fi
nevU="$( runAt "$REPO" --rank-by=churn-decay --since=HEAD 2>&1 >/dev/null | grep 'found no commits' | head -1 )"
case "$nevU" in
    *"uniform (structural) ranking"*"--rank-by=pagerank"*)
        ok "arm 13f control: the UNSCOPED no-evidence run keeps the uniform-fallback sentence, where it is true" ;;
    "") no "arm 13f control: the unscoped no-evidence run printed no notice — arm 13e could be passing on a deleted sentence" ;;
    *)  no "arm 13f control: the unscoped notice lost the uniform-fallback wording: $nevU" ;;
esac

# WHAT would_show= COUNTS, pinned against the run it names (CodeRabbit, review of #212). The stub's number is
# `keep`, which is the un-stubbed header's own shown=, and shown= counts symbol DEFINITIONS individually --
# the print loop collapses a const/non-const overload pair into ONE row carrying overloads=2. So the rows the
# unscoped document prints FOLLOW from would_show rather than equalling it, and the legend used to call it
# "how many symbol ROWS the same run without in= would print", which is a number that document does not
# contain: measured on this repo, shown=200 over 193 rows with 7 rows at overloads=2.
#
# Post-collapse rows are not available in the stub: which definitions make the top-K cut is a fact about the
# RANKING, and the ranking is exactly what the stub skips (no pr_iters= rides its header). So the arms pin the
# IDENTITY the map legend already publishes for shown= -- rows + sum(overloads-1) = shown = would_show --
# rather than demanding an equality that would cost the stub its reason to exist. It is named as the DEFINITION
# COUNT it is and NOT labelled a ceiling (owner decision 2026-09-14): a floor/ceiling marker in this tool means
# "we could not see everything", while would_show is exact and only its UNIT differs from a reader's guess, so
# spending the marker here would weaken it everywhere it is used honestly.
#
# 14a runs on a corpus that HAS overloads in the cut, so the two numbers genuinely differ and an arm asserting
# plain equality would fail; 14b is the no-overload control, where the identity degenerates to equality, so a
# fix that quietly replaced the definition count with the row count could not pass both.
wsFor(){   # $1 = corpus dir -> "would_show rows surplus"
    local dir="$1"
    local ws rows surplus
    ws="$( runAt "$dir" --rank-by=churn-decay --in="$2" 2>/dev/null | sed -n 's/.*would_show="\([0-9]*\)".*/\1/p' )"
    runAt "$dir" --rank-by=churn-decay --legend=full >"$WORK/uns.xml" 2>/dev/null
    rows="$( grep -o '<s ' "$WORK/uns.xml" | wc -l | tr -d ' ' )"
    surplus="$( grep -o 'overloads="[0-9]*"' "$WORK/uns.xml" | grep -o '[0-9]*' | awk '{s+=$1-1} END{print s+0}' )"
    printf '%s %s %s\n' "${ws:-NONE}" "$rows" "$surplus"
}

read -r ws rows surplus <<EOF
$( wsFor "$REPO" db )
EOF
if [ "$ws" = "NONE" ]; then
    no "arm 14a: the stub printed no would_show= at all on the gate fixture"
elif [ "$(( rows + surplus ))" = "$ws" ]; then
    if [ "$surplus" -gt 0 ]; then
        ok "arm 14a: would_show= is the unscoped run's shown= exactly, counting definitions over a cut that DOES collapse overloads: rows=$rows + sum(overloads-1)=$surplus = would_show=$ws"
    else
        ok "arm 14a: would_show=$ws matches rows=$rows with no overloads in the cut on this fixture (the identity holds; 14b is the corpus that exercises the collapse)"
    fi
else
    no "arm 14a: would_show=$ws is not the unscoped run's shown=: rows=$rows + sum(overloads-1)=$surplus = $(( rows + surplus ))"
fi

# 14b: the CONTROL, on a corpus built to hold a const/non-const overload pair -- the shape the identity exists
# for. Both members must be printed (they are the only two symbols), so the surplus is 1 and would_show is
# strictly greater than the row count: an implementation that emitted rows instead of definitions reds here,
# and one that emitted the corpus total reds on the arithmetic.
OVL="$WORK/ovl"
mkdir -p "$OVL/lib"
cat > "$OVL/lib/dup.h" <<'CPPEOF'
struct Holder
{
    int  value() const { return v; }
    int& value()       { return v; }
    int  v = 0;
};
CPPEOF
( cd "$OVL" && git init -q . && git add -A && git -c user.name=gate -c user.email=gate@gate commit -qm ovl ) >/dev/null 2>&1
read -r ws2 rows2 surplus2 <<EOF
$( wsFor "$OVL" lib )
EOF
if [ "$ws2" = "NONE" ]; then
    no "arm 14b control: no would_show= on the overload corpus"
elif [ "$surplus2" -lt 1 ]; then
    no "arm 14b control: the overload corpus printed NO collapsed row (surplus=$surplus2) — the fixture no longer exercises the collapse, so 14a's equality could be passing vacuously"
elif [ "$(( rows2 + surplus2 ))" = "$ws2" ] && [ "$ws2" -gt "$rows2" ]; then
    ok "arm 14b control: on a corpus whose cut collapses an overload pair, would_show=$ws2 EXCEEDS the $rows2 row(s) by exactly the surplus $surplus2 — a definition count, and the published identity still yields the rows"
else
    no "arm 14b control: would_show=$ws2, rows=$rows2, surplus=$surplus2 — the identity does not hold"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
