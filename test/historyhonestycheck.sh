#!/usr/bin/env bash
# historyhonestycheck.sh — whose history the churn and co-change signals read, and what a MOVE counts as.
#
# THE DEFECT, part 1 (research audit 2026-11-26, item 1). Nothing in src/ told a bot's commit from a person's:
# a dependency bot that rewrites one lockfile-shaped file fifty times made that file the top hotspot, the top
# --rank-by=churn symbol and the strongest co-change pair, and nothing on the answer said why. MSR'26
# (arXiv:2602.13170, 91 repos): automated accounts made 74% of hotspot edits. Measured on the fixture below
# with the pre-change binary: botfile.cpp churn="51" ranked FIRST, botfile.cpp<->botlock.cpp the top pair.
#
# THE DEFECT, part 2 (item 8; 2611.10530 on moved and rewritten lines). The walk ran with --no-renames, so a
# pure `git mv` listed BOTH paths: the move commit was a churn event on the new path, the file's history
# before it was lost to a dead path, and every file of a directory move co-changed with every other.
# Measured: sub/moved2.cpp churn="1" (the move itself) where its content had 2 edits and the move none.
#
# THE FIX (lane/history-honesty, src/gitmine.h). One reader, one policy, for every churn / decayed-churn /
# short-horizon-churn / co-change walk:
#   - a commit whose AUTHOR is a bot (a `[bot]` name or email, or a listed automation account) contributes
#     no paths, unless --include-bots; disclosed as bots_skipped=N after the answer;
#   - a commit with a Co-Authored-By trailer naming a coding agent is KEPT and counted, agent_commits=N;
#   - an EXACT move (a delete and an add of the same blob, paired from the blob ids --raw prints, never a blob read)
#     is no churn event, and
#     the file's older history is followed to its new path; disclosed as renames=N.
#   A block of lines moved inside one file is one edit of that file (churn counts commits, not lines).
#
# ARMS
#   1. --hotspots: botfile.cpp keeps only its one human commit, the human order is unchanged, bots_skipped=50.
#   2. --include-bots: the old ranking comes back — botfile.cpp churn=51 is first again.
#   3. agent_commits=1 (a Co-Authored-By: Claude trailer) and the agent's commit still counts.
#   4. a pure file move adds no churn and keeps the file's history (sub/moved2.cpp churn=2); renames=9.
#   5. a pure block move inside one file is ONE edit, not two (blockfile.cpp churn=2).
#   6. --cochange: the bot-only pair botfile.cpp<->botlock.cpp is gone, --include-bots brings it back, and two
#      files that only ever moved together (a directory moved out and back twice) are no pair.
#   7. --rank-by=churn: a human hotspot symbol outranks the bot's; the disclosure rides.
#   8. --situ=FILE carries the disclosure.
#   9. the warm churn cache (qchurn, --for's churn= lens) keys on the bot policy: default, then
#      --include-bots, then default again, each answers for its own policy from one private cache dir.
#  10. oracles: git's own log over the fixture agrees on 50 bot commits and 9 exact renames.
#  11. determinism: two --hotspots runs byte-identical.
#  12. the combined-diff walk asks git for no rename/copy detection, --follow, -B, pickaxe or --diff-filter (source
#      AND received argv, with a mutant per flag), and kGitLogRecordFormat is pinned.
#  13. every verb that prints the history_policy sentence passes xmllint (a `--` inside the comment broke them all).
#  14. MCP: two cochange calls in one session on different roots; the second carries none of the first's counts.
set -u
export RIPWIRE_NO_ROWLINES=1
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"       # BOTH seams — positional and env
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }
echo "historyhonestycheck: BIN=$BIN"

TMP="$( mktemp -d )"; R1="$( mktemp -d )"
trap '[ -n "${KEEP:-}" ] || rm -rf "$TMP" "$R1"' EXIT
QTMP="$TMP/qtmp"; mkdir -p "$QTMP"   # a private cache ladder for arm 9 (cacheDirLadder prefers TMPDIR)

mkfn(){ printf 'int %s( int x )\n{\n    if( x > 1 ) return x + 1;\n    return x - 1;\n}\n' "$1"; }
T=1780000000                                        # 2026-05-28; every commit is one hour after the last
tick(){ T=$(( T + 3600 )); export GIT_AUTHOR_DATE="@$T +0000" GIT_COMMITTER_DATE="@$T +0000"; }
as(){ export GIT_AUTHOR_NAME="$1" GIT_AUTHOR_EMAIL="$2" GIT_COMMITTER_NAME="$1" GIT_COMMITTER_EMAIL="$2"; }
C(){ tick; git -C "$R1" add -A >/dev/null; git -C "$R1" commit -qm "$@"; }
psel(){ awk -v s="${1#/}" '{ if( match( $0, /p="[^"]*"/ ) ) { v = substr( $0, RSTART + 3, RLENGTH - 4 );
        if( v == s || ( length(v) > length(s) && substr( v, length(v) - length(s) ) == "/" s ) ) print } }'; }
churn_of(){ tr '>' '\n' < "$1" | psel "$2" | grep -oE ' churn="[0-9]+"' | head -1 | tr -cd '0-9'; }
order_of(){ tr '>' '\n' < "$1" | grep -E '^<f p=' | grep -oE ' p="[^"]*"' | sed 's/^ p="//; s/"$//; s#.*/##' | tr '\n' ' '; }
num_of(){ grep -oE "$2=[0-9]+" "$1" | head -1 | cut -d= -f2; }

git -C "$R1" init -q -b main
as Hana hana@x.com
mkfn human1Fn > "$R1/human1.cpp"; mkfn human2Fn > "$R1/human2.cpp"; mkfn human3Fn > "$R1/human3.cpp"
mkfn botFn > "$R1/botfile.cpp"; printf 'lock 0\n' > "$R1/botlock.cpp"
mkfn movedFn > "$R1/moved.cpp"
{ mkfn blockA; mkfn blockB; } > "$R1/blockfile.cpp"
mkdir -p "$R1/dirA"; mkfn pairOneFn > "$R1/dirA/pone.cpp"
C "init"
for i in 1 2 3 4 5; do printf '// h1 %s\n' "$i" >> "$R1/human1.cpp"; C "h1 $i"; done
for i in 1 2 3;     do printf '// h2 %s\n' "$i" >> "$R1/human2.cpp"; C "h2 $i"; done
printf '// h3\n' >> "$R1/human3.cpp"; C "h3 with an agent" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
printf '// moved edit\n' >> "$R1/moved.cpp"; C "edit moved.cpp before the move"
mkfn pairTwoFn > "$R1/dirA/ptwo.cpp"; C "a second file in dirA, on its own"
# 49 commits by a [bot] author, 1 by a listed automation account (no [bot] in the name or the email)
as 'dependabot[bot]' '49699333+dependabot[bot]@users.noreply.github.com'
for i in $( seq 1 49 ); do printf '// bump %s\n' "$i" >> "$R1/botfile.cpp"; printf 'lock %s\n' "$i" > "$R1/botlock.cpp"; C "bump $i"; done
as 'GitHub Action' 'action@github.com'
printf '// bump 50\n' >> "$R1/botfile.cpp"; printf 'lock 50\n' > "$R1/botlock.cpp"; C "bump 50"
as Hana hana@x.com
mkdir -p "$R1/sub"; git -C "$R1" mv moved.cpp sub/moved2.cpp; C "pure move"
for i in 1 2; do git -C "$R1" mv dirA dirB; C "pure directory move out $i"; git -C "$R1" mv dirB dirA; C "pure directory move back $i"; done
{ mkfn blockB; mkfn blockA; } > "$R1/blockfile.cpp"; C "pure block move"
unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

# ── 10. oracles first: the fixture is what the arms claim ──────────────────────────────────────────────────────
BOTS="$( git -C "$R1" log --format='%an %ae' | grep -cE '\[bot\]|action@github\.com' )"
RENAMES="$( git -C "$R1" log -M100% --name-status --format= | grep -c '^R100' )"
[ "$BOTS" = 50 ] \
    && ok "oracle: git's own log holds 50 bot-authored commits" \
    || no "oracle: $BOTS bot commits, want 50 — the fixture is not what the arms claim"
[ "$RENAMES" = 9 ] \
    && ok "oracle: git -M100% sees exactly 9 exact renames (one file move, four two-file directory moves)" \
    || no "oracle: $RENAMES exact renames, want 9"

# ── 1. default --hotspots ─────────────────────────────────────────────────────────────────────────────────────
"$BIN" "$R1" --hotspots --limit=50 > "$TMP/h.out" 2> "$TMP/h.err"; rc=$?
[ "$rc" = 0 ] \
    && ok "--hotspots exits 0" \
    || no "--hotspots exit $rc: $( head -c 300 "$TMP/h.err" )"
CB="$( churn_of "$TMP/h.out" botfile.cpp )"
[ "$CB" = 1 ] && ok "--hotspots: botfile.cpp keeps only its one human commit (churn=1)" \
    || no "--hotspots: botfile.cpp churn='$CB', want 1 (51 = the 50 bot commits still count)"
ORD="$( order_of "$TMP/h.out" )"
HORD="$( printf '%s\n' $ORD | grep -E '^human[0-9]\.cpp$' | tr '\n' ' ' )"
case "$ORD" in
    "human1.cpp "*) [ "$HORD" = "human1.cpp human2.cpp human3.cpp " ] && ok "--hotspots: human1.cpp leads and the human order is unchanged ($ORD)" \
                        || no "--hotspots: the human files are ordered '$HORD', want human1 human2 human3" ;;
    *) no "--hotspots: order '$ORD', want human1.cpp first (botfile.cpp first = the bot's 50 commits still rank it)" ;;
esac
[ "$( num_of "$TMP/h.out" bots_skipped )" = 50 ] && ok "--hotspots discloses bots_skipped=50" \
    || no "--hotspots: no bots_skipped=50 on the answer: $( grep -o 'history_policy[^>]*' "$TMP/h.out" | head -c 300 )"

# ── 2. --include-bots brings the old ranking back ─────────────────────────────────────────────────────────────
"$BIN" "$R1" --hotspots --limit=50 --include-bots > "$TMP/hb.out" 2> "$TMP/hb.err"; rc=$?
[ "$rc" = 0 ] \
    && ok "--include-bots is accepted" \
    || no "--include-bots exit $rc: $( head -c 300 "$TMP/hb.err" )"
CBB="$( churn_of "$TMP/hb.out" botfile.cpp )"
ORDB="$( order_of "$TMP/hb.out" )"
[ "$CBB" = 51 ] \
    && ok "--include-bots: botfile.cpp churn=51 again" \
    || no "--include-bots: botfile.cpp churn='$CBB', want 51"
case "$ORDB" in
    "botfile.cpp "*) ok "--include-bots: botfile.cpp ranks first again (the old ranking)" ;;
    *) no "--include-bots: order '$ORDB', want botfile.cpp first" ;;
esac
grep -q 'bots_included=50' "$TMP/hb.out" && ok "--include-bots says what it kept (bots_included=50)" \
    || no "--include-bots: no bots_included=50 on the answer"

# ── 3. agent co-authored commits are counted and kept ─────────────────────────────────────────────────────────
[ "$( num_of "$TMP/h.out" agent_commits )" = 1 ] \
    && ok "agent_commits=1 disclosed" \
    || no "no agent_commits=1 on the answer"
[ "$( churn_of "$TMP/h.out" human3.cpp )" = 2 ] && ok "the agent co-authored commit still counts (human3.cpp churn=2)" \
    || no "human3.cpp churn='$( churn_of "$TMP/h.out" human3.cpp )', want 2"

# ── 4. a pure file move ───────────────────────────────────────────────────────────────────────────────────────
CM="$( churn_of "$TMP/h.out" sub/moved2.cpp )"
[ "$CM" = 2 ] && ok "pure move: sub/moved2.cpp churn=2 — its two content commits, followed across the move, and the move adds none" \
    || no "pure move: sub/moved2.cpp churn='$CM', want 2 (1 = the move counted and the history lost)"
[ "$( num_of "$TMP/h.out" renames )" = 9 ] \
    && ok "renames=9 disclosed" \
    || no "no renames=9 on the answer"

# ── 5. a pure block move inside one file ──────────────────────────────────────────────────────────────────────
[ "$( churn_of "$TMP/h.out" blockfile.cpp )" = 2 ] && ok "block move: blockfile.cpp churn=2 (init + ONE edit, not double-counted)" \
    || no "block move: blockfile.cpp churn='$( churn_of "$TMP/h.out" blockfile.cpp )', want 2"

# ── 6. --cochange ─────────────────────────────────────────────────────────────────────────────────────────────
"$BIN" "$R1" --cochange > "$TMP/c.out" 2>/dev/null
"$BIN" "$R1" --cochange --include-bots > "$TMP/cb.out" 2>/dev/null
pairhit(){ tr '>' '\n' < "$1" | grep -E '^<pair ' | grep 'botfile\.cpp' | grep -c 'botlock\.cpp'; }
[ "$( pairhit "$TMP/c.out" )" = 0 ] && ok "--cochange: the bot-only pair botfile.cpp<->botlock.cpp is gone" \
    || no "--cochange: the bot-only pair is still reported"
[ "$( pairhit "$TMP/cb.out" )" -ge 1 ] && ok "--cochange --include-bots: the pair comes back" \
    || no "--cochange --include-bots: no botfile.cpp<->botlock.cpp pair (the arm above is vacuous)"
grep -q 'bots_skipped=50' "$TMP/c.out" \
    && ok "--cochange discloses bots_skipped=50" \
    || no "--cochange: no bots_skipped=50"
dirpair(){ tr '>' '\n' < "$1" | grep -E '^<pair ' | grep 'pone\.cpp' | grep -c 'ptwo\.cpp'; }
[ "$( dirpair "$TMP/c.out" )" = 0 ] && ok "--cochange: two files that only ever MOVED together are not a co-change pair" \
    || no "--cochange: dirA/pone.cpp<->dirA/ptwo.cpp reported — a directory moved out and back twice read as four co-changes"

# ── 7. --rank-by=churn ────────────────────────────────────────────────────────────────────────────────────────
"$BIN" "$R1" --rank-by=churn > "$TMP/r.out" 2>/dev/null
rankpos(){ tr '>' '\n' < "$1" | grep -oE ' n="[A-Za-z0-9]+"' | grep -n "\"$2\"" | head -1 | cut -d: -f1; }
P_H="$( rankpos "$TMP/r.out" human1Fn )"; P_B="$( rankpos "$TMP/r.out" botFn )"
[ -n "$P_H" ] && [ -n "$P_B" ] && [ "$P_H" -lt "$P_B" ] && ok "--rank-by=churn: human1Fn ($P_H) outranks botFn ($P_B)" \
    || no "--rank-by=churn: human1Fn at '$P_H', botFn at '$P_B' — want human1Fn first"
grep -q 'bots_skipped=50' "$TMP/r.out" \
    && ok "--rank-by=churn discloses bots_skipped=50" \
    || no "--rank-by=churn: no bots_skipped=50"

# ── 8. --situ ─────────────────────────────────────────────────────────────────────────────────────────────────
"$BIN" "$R1" --situ=human1.cpp > "$TMP/s.out" 2>/dev/null
grep -q 'bots_skipped=50' "$TMP/s.out" \
    && ok "--situ discloses bots_skipped=50" \
    || no "--situ: no bots_skipped=50"

# ── 9. the warm churn cache keys on the bot policy ────────────────────────────────────────────────────────────
forchurn(){ tr '>' '\n' < "$1" | grep -F 'n="botFn"' | grep -oE ' churn="[0-9]+"' | head -1 | tr -cd '0-9'; }
env TMPDIR="$QTMP" "$BIN" "$R1" --for=botFn                > "$TMP/f1.out" 2>/dev/null
env TMPDIR="$QTMP" "$BIN" "$R1" --for=botFn --include-bots > "$TMP/f2.out" 2>/dev/null
env TMPDIR="$QTMP" "$BIN" "$R1" --for=botFn                > "$TMP/f3.out" 2>/dev/null
F1="$( forchurn "$TMP/f1.out" )"; F2="$( forchurn "$TMP/f2.out" )"; F3="$( forchurn "$TMP/f3.out" )"
NBLOB="$( find "$QTMP/ripwire" -maxdepth 2 -type f -name 'ripwire-qchurn-*.bin' 2>/dev/null | wc -l | tr -d ' ' )"
[ "$F1" = 1 ] && [ "$F2" = 51 ] && [ "$F3" = 1 ] \
    && ok "qchurn: --for churn= answers 1 / 51 / 1 for default / --include-bots / default from one cache" \
    || no "qchurn: --for churn= answered '$F1' / '$F2' / '$F3', want 1 / 51 / 1 (a warm blob served the other policy)"
[ "$NBLOB" = 2 ] \
    && ok "qchurn: one blob per bot policy ($NBLOB)" \
    || no "qchurn: $NBLOB blob(s), want 2 (one per policy)"

# ── 11. determinism ───────────────────────────────────────────────────────────────────────────────────────────
"$BIN" "$R1" --hotspots --limit=50 > "$TMP/h2.out" 2>/dev/null
cmp -s "$TMP/h.out" "$TMP/h2.out" \
    && ok "--hotspots is byte-identical across runs" \
    || no "--hotspots differs between two runs"

# ── 12. the combined-diff history walk asks git for no rename detection, and its record format is pinned ──────────
# src/gitmine.h kGitLogRecordWalkArgs says why: any rename/copy detection (-M100% included), --follow, -B, a pickaxe or a
# --diff-filter sets combine-diff.c's need_generic_pathscan and turns off find_paths_multitree for every merge (kubernetes,
# 12 months: 0.64 s -> 6.13 s of git). Checked twice: on the source's argument constants and on the argv git received.
# Each forbidden flag is also injected into a copy of both (a mutant per flag) and must be refused, so the arm cannot pass
# by matching nothing.
SRC="$ROOT/src/gitmine.h"
cat > "$TMP/walkargs.py" <<'PY'
import re, sys
FORBIDDEN = ( "-M", "-C", "--find-renames", "--find-copies", "--follow", "-S", "-G", "--diff-filter", "-B" )
def bad( tokens ):
    return [ t for t in tokens for f in FORBIDDEN if t == f or t.startswith( f + "=" ) or ( len( f ) == 2 and t.startswith( f ) ) ]
def const( src, name ):
    m = re.search( r'inline constexpr const char\* ' + name + r'\s*=\s*((?:"(?:[^"\\]|\\.)*"\s*)+);', src )
    return "".join( re.findall( r'"((?:[^"\\]|\\.)*)"', m.group( 1 ) ) ) if m else None
def source_tokens( src ):
    body = src[ src.index( "inline std::string gitLogRecordsCmd(" ): ]
    body = body[ : body.index( "\n}\n" ) ]
    body = body[ body.index( '" log ' ) + len( '" log' ): ]   # from the word log on: what precedes it is gitCmd's global options
    body = '"' + body
    parts = re.findall( r'"((?:[^"\\]|\\.)*)"|\b(k[A-Za-z]+)\b', body )
    text = " ".join( lit if lit else ( const( src, name ) or "" ) for lit, name in parts if name != "kGitLogRecordFormat" )
    return text.split()
mode, arg = sys.argv[ 1 ], sys.argv[ 2 ]
if mode == "source":
    src = open( arg ).read()
    toks = source_tokens( src )
    print( "TOKENS " + " ".join( toks ) )
    print( "BAD " + " ".join( bad( toks ) ) )
    print( "FORMAT " + ( const( src, "kGitLogRecordFormat" ) or "" ) )
elif mode == "argv":
    lines = [ l for l in open( arg, errors = "replace" ) if " log " in l and "--raw" in l ]
    print( "WALKS %d" % len( lines ) )
    for l in lines:
        toks = l.split( " log ", 1 )[ 1 ].replace( "'", " " ).split()
        print( "BAD " + " ".join( bad( toks ) ) )
PY
SRCOUT="$( python3 "$TMP/walkargs.py" source "$SRC" )"
SRCBAD="$( printf '%s\n' "$SRCOUT" | sed -n 's/^BAD //p' )"
SRCTOK="$( printf '%s\n' "$SRCOUT" | sed -n 's/^TOKENS //p' )"
case " $SRCTOK " in
    *" --no-renames "*" --raw "*" -c "*) SRCREAD=1 ;;
    *) SRCREAD=0 ;;
esac
if [ "$SRCREAD" = 0 ]; then
    no "source: could not read the walk's arguments from gitLogRecordsCmd ('$SRCTOK') — the extraction is stale"
elif [ -n "$SRCBAD" ]; then
    no "source: the walk's arguments carry $SRCBAD — see kGitLogRecordWalkArgs for why that costs 10x on merges"
else
    ok "source: the walk's arguments ($SRCTOK) carry no rename/pickaxe/filter flag"
fi
WANTFMT='%x00__C__%x00%ae%x00N%an%x00T%(trailers:key=Co-authored-by,valueonly,separator=%x01,unfold)%x00%at%x00%ct'
[ "$( printf '%s\n' "$SRCOUT" | sed -n 's/^FORMAT //p' )" = "$WANTFMT" ] \
    && ok "kGitLogRecordFormat is the pinned record format (a change to it changes every cached qchurn stream: bump kQChurnCacheScheme and re-pin here)" \
    || no "kGitLogRecordFormat moved: '$( printf '%s\n' "$SRCOUT" | sed -n 's/^FORMAT //p' )' — bump kQChurnCacheScheme (quality.h), then re-pin this arm"
: > "$TMP/walk.trace"
GIT_TRACE="$TMP/walk.trace" "$BIN" "$R1" --hotspots --limit=5 >/dev/null 2>&1
ARGVOUT="$( python3 "$TMP/walkargs.py" argv "$TMP/walk.trace" )"
NWALK="$( printf '%s\n' "$ARGVOUT" | sed -n 's/^WALKS //p' )"
ARGVBAD="$( printf '%s\n' "$ARGVOUT" | sed -n 's/^BAD //p' | tr -s ' \n' ' ' | sed 's/^ *//; s/ *$//' )"
[ "${NWALK:-0}" -ge 1 ] && [ -z "$ARGVBAD" ] && ok "argv: the $NWALK history walk(s) git received carry no rename/pickaxe/filter flag" \
    || no "argv: walks=${NWALK:-0}, forbidden flags received: '$ARGVBAD'"
mut_src_ok=0; mut_argv_ok=0; nmut=0
for f in -M100% -C --find-renames --find-copies=50% --follow -Sneedle -Gneedle --diff-filter=AM -B; do
    nmut=$(( nmut + 1 ))
    sed "s|kGitLogRecordWalkArgs = \"--no-renames|kGitLogRecordWalkArgs = \"$f --no-renames|" "$SRC" > "$TMP/mutant.h"
    [ -n "$( python3 "$TMP/walkargs.py" source "$TMP/mutant.h" | sed -n 's/^BAD //p' )" ] && mut_src_ok=$(( mut_src_ok + 1 ))
    sed "s| log | log $f |" "$TMP/walk.trace" > "$TMP/mutant.trace"
    [ -n "$( python3 "$TMP/walkargs.py" argv "$TMP/mutant.trace" | sed -n 's/^BAD //p' | tr -d ' \n' )" ] && mut_argv_ok=$(( mut_argv_ok + 1 ))
done
[ "$mut_src_ok" = "$nmut" ] && [ "$mut_argv_ok" = "$nmut" ] \
    && ok "mutation control: each of the $nmut forbidden flags, injected into the source and into the argv, is refused" \
    || no "mutation control: only $mut_src_ok/$nmut source and $mut_argv_ok/$nmut argv mutants were refused — the arm above can pass blind"

# ── 13. every verb that prints the history_policy sentence still prints a well-formed document ──────────────────
# The sentence rides in an XML comment, where `--` is not well-formed: it once named the flag with its dashes and every one
# of these answers failed xmllint whenever it printed (found by the PACK-PARTNERS lane on #777). Each arm requires the
# sentence to be PRESENT, so a verb that stopped printing it cannot pass by saying nothing. --situ answers in prose, not XML
# (its first line is a heading), so it is not an xmllint subject; arm 8 holds its sentence.
if command -v xmllint >/dev/null 2>&1; then
    ( cd "$R1" && printf '// dirty\n' >> human1.cpp )   # --quality-delta reads the working tree vs HEAD; one human edit
    for v in "--hotspots" "--cochange" "--rank-by=churn" "--rank-by=churn-decay" "--quality-delta" "--hotspots --include-bots"; do
        # shellcheck disable=SC2086
        "$BIN" "$R1" $v > "$TMP/x.out" 2>/dev/null
        if ! grep -q 'history_policy' "$TMP/x.out"; then
            no "xmllint: $v printed no history_policy sentence (the arm would be vacuous)"
        elif xmllint --noout "$TMP/x.out" 2>"$TMP/x.err"; then
            ok "xmllint: $v is well-formed with the history_policy sentence in it"
        else
            no "xmllint: $v is not well-formed: $( head -c 200 "$TMP/x.err" )"
        fi
    done
    git -C "$R1" checkout -q -- human1.cpp
else
    no "xmllint not found — the well-formedness arm cannot run"
fi

# ── 14. a long-lived MCP server reports each request's own counts ────────────────────────────────────────────────
# The census is a process-wide maximum; a server that never reset it would answer a later request on a bot-free root with
# the earlier root's bots_skipped=50. Two cochange calls in ONE session: the bot fixture, then a clean repo.
R2="$TMP/clean"; mkdir -p "$R2"; git -C "$R2" init -q -b main
for i in 1 2 3; do mkfn "clean${i}Fn" > "$R2/c$i.cpp"; printf '// e\n' >> "$R2/c1.cpp"; ( cd "$R2" && GIT_AUTHOR_NAME=Cleo GIT_AUTHOR_EMAIL=c@x.com GIT_COMMITTER_NAME=Cleo GIT_COMMITTER_EMAIL=c@x.com git add -A && GIT_AUTHOR_NAME=Cleo GIT_AUTHOR_EMAIL=c@x.com GIT_COMMITTER_NAME=Cleo GIT_COMMITTER_EMAIL=c@x.com git commit -qm "c$i" ); done
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"cochange\",\"arguments\":{\"path\":\"$R1\",\"file\":\"botfile.cpp\"}}}" \
  "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"cochange\",\"arguments\":{\"path\":\"$R2\",\"file\":\"c1.cpp\"}}}" \
  | ( cd "$R1" && perl -e 'alarm 120; exec @ARGV' "$BIN" "$R1" --mcp > "$TMP/mcp.out" 2>/dev/null )
MCP1="$( grep '"id":2' "$TMP/mcp.out" )"; MCP2="$( grep '"id":3' "$TMP/mcp.out" )"
[ -n "$MCP1" ] && [ -n "$MCP2" ] \
    && ok "mcp: both cochange calls answered in one session" \
    || no "mcp: missing answers (id2='${MCP1:0:80}' id3='${MCP2:0:80}')"
printf '%s' "$MCP1" | grep -q '"_history_policy":"[^"]*bots_skipped=50' \
    && ok "mcp: the bot-fixture call's envelope carries _history_policy with bots_skipped=50" \
    || no "mcp: the bot-fixture call's envelope has no _history_policy bots_skipped=50"
printf '%s' "$MCP2" | grep -q '_history_policy' \
    && no "mcp: the clean-root call carries a _history_policy — a count left over from the earlier call: $( printf '%s' "$MCP2" | grep -o '_history_policy[^,]*' | head -c 160 )" \
    || ok "mcp: the clean-root call carries no _history_policy (its walks left nothing out; nothing from the first call leaks)"

[ "$fail" = 0 ] && echo "historyhonestycheck: ALL PASS" || echo "historyhonestycheck: FAILURES"
exit "$fail"
