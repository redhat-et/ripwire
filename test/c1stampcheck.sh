#!/usr/bin/env bash
# c1stampcheck.sh — C1-STAMP: a served --for asks git ONE question (the live `status --porcelain`), the six small ones
# come from the STAMP record (src/gitstampcache.h), and a record is never served once a file its answers depend on moved.
#
# THE OBSERVABLE is git's own trace: GIT_TRACE2_EVENT names one fixed file per cache directory (it is a GIT_* variable,
# so it is part of the snapshot's options key, and a path that changed per call would refuse the snapshot every time).
# Every `start` event is one git process. A "stamp question" is one of the six the record answers:
#   rev-parse --verify HEAD · log -1 --format=%ct · log --since … --format=%H · rev-parse --show-toplevel ·
#   rev-parse --is-shallow-repository
# The reference for every answer is a COLD run: a fresh cache directory and --no-cache (no record is read or written).
#
# ARMS
#   A   served child count: on a tree the snapshot serves (snapshot-stats graph=loaded, the vacuity guard), the --for call
#       starts exactly ONE git process and it is `status`. RED on fec2ab27c, which starts seven.
#   B   identity: that served answer is byte-identical to the cold one.
#   Invalidation — each primes a record (call 1 records, call 2 must be served: zero stamp questions), changes ONE input,
#   and then requires (i) the next call re-asks git (stamp questions > 0), (ii) its answer equals a cold run's on the
#   changed tree, and (iii) where the change leaves a recordable state, the call after it is served again:
#     C1 `git commit --allow-empty` (HEAD moves, no file changes; at= must change)
#     C2 a branch switch to a branch whose tree is the same (at= must change)
#     C3 `git pack-refs --all` (the loose ref disappears into packed-refs)
#     C4 a `git config` change in the repository's config
#     C5 the shallow file appears (at= gains +shallow) and disappears (it loses it)
#     C6 a detached HEAD at the same commit, then a commit on it (at= must change)
#     C7 a worktree whose .git is a FILE: served from the second call, invalidated by a commit inside it
#     C8 HOME moves (another global config): re-asked
#     C9 GIT_DIR (with GIT_WORK_TREE) names another repository, a copy one commit ahead: the record is bypassed, git is
#        asked, and at= is the other repository's HEAD, as in a cold run
#     C10 a flipped byte, a truncation and another version in the record file: each refused cleanly
#   D   a directory that is not a git repo: no git process at all, warm or cold, and no record written.
#   E   the dirty bit is live: an untracked file appears (+dirty on the very next call) and disappears (gone on the next).
#   M   MUTATION CONTROLS — the same arms against the real binary with RIPWIRE_TEST_GITSTAMP_MUTANT set:
#       trust  (a record served without re-reading its dependencies): C1-C8 must each FAIL;
#       gitenv (the GIT_* bypass skipped): C9 must FAIL.
#       An arm that passes under its mutant could not have caught the defect it names.
#
#   bash test/c1stampcheck.sh [./build/ripwire]
#
# Exits non-zero on any failure. Prints ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "c1stampcheck: git required"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "c1stampcheck: python3 required (record damage)"; exit 2; }
TMP="$( cd "$( mktemp -d )" && pwd -P )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
echo "c1stampcheck: BIN=$BIN  TMP=$TMP"

H="$TMP/home"; mkdir -p "$H"                 # an empty HOME: no global git config but the ones an arm writes
Q="how parse_config calls helper"
G(){ local d="$1"; shift; HOME="$H" GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_DATE="2025-03-01T00:00:00Z" GIT_COMMITTER_DATE="2025-03-01T00:00:00Z" \
     git -C "$d" -c user.name=c1 -c user.email=c1@example.invalid -c commit.gpgsign=false "$@"; }

# mkfix DIR — two commits on main, a branch `side` one empty commit ahead of it (the same tree), a sub/ directory
mkfix()
{
    mkdir -p "$1/sub"
    printf 'int helper(int x){return x+1;}\nint parse_config(int a){return helper(a)*2;}\n' >"$1/a.c"
    printf 'int parse_config(int);\nint main(){return parse_config(3);}\n' >"$1/main.c"
    printf 'int parse_config(int);\nint sub_entry(){return parse_config(5);}\n' >"$1/sub/s.c"
    G "$1" init -q -b main && G "$1" add -A && G "$1" commit -qm one && G "$1" commit -q --allow-empty -m two \
      && G "$1" checkout -q -b side && G "$1" commit -q --allow-empty -m side && G "$1" checkout -q main
}

# call ROOT CACHE LABEL [VAR=VALUE...] — one warm --for; $LAST_ALL = git processes, $LAST_STAMP = stamp questions
LAST_ALL=0; LAST_STAMP=0
call()
{
    local root="$1" cache="$2" label="$3"; shift 3
    mkdir -p "$cache"
    env -i HOME="$H" PATH="$PATH" TMPDIR="$cache" GIT_TRACE2_EVENT="$cache/trace.json" RIPWIRE_SNAPSHOT_STATS=1 "$@" \
        "$BIN" "$root" --for="$Q" >"$TMP/$label.out" 2>"$TMP/$label.err"
    touch "$cache/trace.json"
    LAST_ALL="$( grep -c '"event":"start"' "$cache/trace.json" )"
    LAST_STAMP="$( grep '"event":"start"' "$cache/trace.json" \
        | grep -cE '"rev-parse","--verify"|"--format=%ct"|"--format=%H"|"--show-toplevel"|"--is-shallow-repository"' )"
    mv "$cache/trace.json" "$TMP/$label.trace"
}
# cold ROOT LABEL [VAR=VALUE...] — the reference: a fresh cache directory and --no-cache
COLDN=0
cold()
{
    local root="$1" label="$2"; shift 2
    COLDN=$(( COLDN + 1 )); mkdir -p "$TMP/cold.$COLDN"
    env -i HOME="$H" PATH="$PATH" TMPDIR="$TMP/cold.$COLDN" "$@" "$BIN" "$root" --for="$Q" --no-cache >"$TMP/$label.out" 2>/dev/null
}
atOf(){ head -c 4096 "$1" | sed -n 's/^<ctx [^>]* at="\([^"]*\)".*/\1/p' | head -1; }

# Each arm reports into ARMFAIL (its own checks) and prints them indented; `arm NAME FN ARGS` runs it normally (must pass)
# and `mutant MODE NAME FN ARGS` runs it under the mutation (must fail).
ARMFAIL=0
chk(){ if [ "$1" = 1 ]; then printf '        ok  %s\n' "$2"; else printf '        no  %s\n' "$2"; ARMFAIL=1; fi; }
eqcold(){ local w="$1" c="$2"; [ -s "$TMP/$c.out" ] && cmp -s "$TMP/$w.out" "$TMP/$c.out" && echo 1 || echo 0; }
prime()   # prime ROOT CACHE TAG [env] — record, then require the second call to be served
{
    local r="$1" c="$2" t="$3"; shift 3
    call "$r" "$c" "$t.p1" "$@"; call "$r" "$c" "$t.p2" "$@"
    chk "$( [ "$LAST_STAMP" = 0 ] && echo 1 || echo 0 )" "primed: the second call asked no stamp question ($LAST_STAMP)"
}
# after ROOT CACHE TAG STEP RESERVE [env] — the call after a change: re-asked, cold-identical, and (RESERVE=1) served again
after()
{
    local r="$1" c="$2" t="$3" s="$4" reserve="$5"; shift 5
    call "$r" "$c" "$t.$s" "$@"
    chk "$( [ "$LAST_STAMP" -gt 0 ] && echo 1 || echo 0 )" "$s: the next call re-asked git ($LAST_STAMP stamp questions)"
    cold "$r" "$t.$s.cold" "$@"
    chk "$( eqcold "$t.$s" "$t.$s.cold" )" "$s: its answer equals a cold run's (at=$( atOf "$TMP/$t.$s.out" ))"
    if [ "$reserve" = 1 ]; then
        call "$r" "$c" "$t.$s.again" "$@"
        chk "$( [ "$LAST_STAMP" = 0 ] && eqcold "$t.$s.again" "$t.$s.cold" )" "$s: the call after it is served again, same bytes ($LAST_STAMP)"
    fi
}
moved(){ chk "$( [ -n "$2" ] && [ "$1" != "$2" ] && echo 1 || echo 0 )" "at= moved: $1 -> $2"; }

arm_commit()   { local r="$1" c="$2" t="$3"; shift 3; prime "$r" "$c" "$t" "$@"; local a0; a0="$( atOf "$TMP/$t.p2.out" )"
                 G "$r" commit -q --allow-empty -m three; after "$r" "$c" "$t" commit 1 "$@"; moved "$a0" "$( atOf "$TMP/$t.commit.out" )"; }
arm_branch()   { local r="$1" c="$2" t="$3"; shift 3; prime "$r" "$c" "$t" "$@"; local a0; a0="$( atOf "$TMP/$t.p2.out" )"
                 G "$r" checkout -q side; after "$r" "$c" "$t" switch 1 "$@"; moved "$a0" "$( atOf "$TMP/$t.switch.out" )"; }
arm_packrefs() { local r="$1" c="$2" t="$3"; shift 3; prime "$r" "$c" "$t" "$@"
                 G "$r" pack-refs --all; chk "$( [ ! -e "$r/.git/refs/heads/main" ] && echo 1 || echo 0 )" "the loose ref is gone"
                 after "$r" "$c" "$t" packrefs 1 "$@"; }
arm_config()   { local r="$1" c="$2" t="$3"; shift 3; prime "$r" "$c" "$t" "$@"
                 G "$r" config ripwire.c1stamp yes; after "$r" "$c" "$t" config 1 "$@"; }
arm_shallow()  { local r="$1" c="$2" t="$3"; shift 3; prime "$r" "$c" "$t" "$@"
                 G "$r" rev-parse HEAD~1 >"$r/.git/shallow"; after "$r" "$c" "$t" shallow-on 1 "$@"
                 chk "$( atOf "$TMP/$t.shallow-on.out" | grep -q '+shallow' && echo 1 || echo 0 )" "at= gained +shallow"
                 rm -f "$r/.git/shallow"; after "$r" "$c" "$t" shallow-off 1 "$@"
                 chk "$( atOf "$TMP/$t.shallow-off.out" | grep -q '+shallow' && echo 0 || echo 1 )" "at= lost +shallow (paired with the gain above)"; }
arm_detached() { local r="$1" c="$2" t="$3"; shift 3; prime "$r" "$c" "$t" "$@"; local a0; a0="$( atOf "$TMP/$t.p2.out" )"
                 G "$r" checkout -q --detach; after "$r" "$c" "$t" detach 1 "$@"
                 G "$r" commit -q --allow-empty -m detached; after "$r" "$c" "$t" detached-commit 1 "$@"
                 moved "$a0" "$( atOf "$TMP/$t.detached-commit.out" )"; }
arm_worktree() { local r="$1" c="$2" t="$3"; shift 3; local w="$r-wt"
                 G "$r" worktree add -q -b wtb "$w" main 2>/dev/null
                 chk "$( [ -f "$w/.git" ] && echo 1 || echo 0 )" "the worktree's .git is a file"
                 prime "$w" "$c" "$t" "$@"; cold "$w" "$t.p2.cold" "$@"; chk "$( eqcold "$t.p2" "$t.p2.cold" )" "served answer equals a cold run's"
                 local a0; a0="$( atOf "$TMP/$t.p2.out" )"
                 G "$w" commit -q --allow-empty -m inwt; after "$w" "$c" "$t" wtcommit 1 "$@"; moved "$a0" "$( atOf "$TMP/$t.wtcommit.out" )"; }
arm_home()     { local r="$1" c="$2" t="$3"; shift 3; prime "$r" "$c" "$t" "$@"
                 mkdir -p "$TMP/home2-$t"; printf '[core]\n\tabbrev = 12\n' >"$TMP/home2-$t/.gitconfig"
                 H0="$H"; H="$TMP/home2-$t"; after "$r" "$c" "$t" home 1 "$@"; H="$H0"; }
arm_gitdir()   { local r="$1" c="$2" t="$3"; shift 3; local o="$r-other"
                 cp -R "$r" "$o"; G "$o" commit -q --allow-empty -m other
                 local want; want="$( G "$o" rev-parse HEAD | cut -c1-9 )"
                 prime "$r" "$c" "$t" "$@"
                 call "$r" "$c" "$t.gitdir" GIT_DIR="$o/.git" GIT_WORK_TREE="$r" "$@"
                 cold "$r" "$t.gitdir.cold" GIT_DIR="$o/.git" GIT_WORK_TREE="$r" "$@"
                 chk "$( eqcold "$t.gitdir" "$t.gitdir.cold" )" "with GIT_DIR naming another repository the answer equals a cold run's"
                 chk "$( atOf "$TMP/$t.gitdir.out" | grep -q "^$want" && echo 1 || echo 0 )" "and at= is that repository's HEAD ($want: $( atOf "$TMP/$t.gitdir.out" ))"
                 chk "$( [ "$LAST_STAMP" -gt 0 ] && echo 1 || echo 0 )" "the record was bypassed: git was asked ($LAST_STAMP)"; }
arm_record()   { local r="$1" c="$2" t="$3"; shift 3; prime "$r" "$c" "$t" "$@"
                 local f; f="$( find "$c" -name 'ripwire-qstamp-*.bin' | head -1 )"
                 chk "$( [ -n "$f" ] && echo 1 || echo 0 )" "a STAMP record exists in the cache directory"
                 [ -n "$f" ] || return 0
                 for how in flip cut version; do
                     python3 - "$f" "$how" <<'PYDAMAGE'
import sys
path, how = sys.argv[ 1 ], sys.argv[ 2 ]
b = bytearray( open( path, 'rb' ).read() )
if how == 'flip':
    b[ len( b ) // 2 ] ^= 0x01
elif how == 'cut':
    b = b[ : len( b ) * 2 // 3 ]
else:
    b[ 8 ] = ( b[ 8 ] + 1 ) % 256          # the u32 version follows the u64 magic (the checksum refuses it first)
open( path, 'wb' ).write( b )
PYDAMAGE
                     after "$r" "$c" "$t" "rec-$how" 1 "$@"
                 done; }

# ── fixtures, all made before one pause: the snapshot's racy rule wants two seconds behind its signatures ──────────
ARMS="commit branch packrefs config shallow detached worktree home gitdir record"
mkfix "$TMP/fixA" >/dev/null || { echo "c1stampcheck: fixture failed"; exit 2; }
for a in $ARMS; do mkfix "$TMP/n-$a" >/dev/null; [ "$a" = record ] || mkfix "$TMP/m-$a" >/dev/null; done
mkfix "$TMP/dirty" >/dev/null
mkdir -p "$TMP/nogit/sub"; cp "$TMP/fixA/a.c" "$TMP/fixA/main.c" "$TMP/nogit/"
sleep 2

# ── A / B: the served --for ───────────────────────────────────────────────────────────────────────────────────────
echo "A/B: served --for on a fixture"
for i in 1 2 3; do call "$TMP/fixA" "$TMP/cA" "A.w$i"; done
call "$TMP/fixA" "$TMP/cA" "A.served"
if grep -q 'graph=loaded' "$TMP/A.served.err"; then ok "A0 the measured call is served by the snapshot (graph=loaded)"; else no "A0 the measured call is not served: $( grep snapshot-stats "$TMP/A.served.err" )"; fi
only="$( grep '"event":"start"' "$TMP/A.served.trace" | grep -c '"status","--porcelain"' )"
if [ "$LAST_ALL" = 1 ] && [ "$only" = 1 ]; then ok "A  one git process, and it is the status ($LAST_ALL)"
else no "A  served --for started $LAST_ALL git processes ($LAST_STAMP stamp questions), want exactly the status"; fi
cold "$TMP/fixA" "A.cold"
if [ "$( eqcold A.served A.cold )" = 1 ]; then ok "B  served answer is byte-identical to a cold run's"; else no "B  served answer differs from a cold run's"; fi

# ── C / M: invalidation, and each arm's mutation control ──────────────────────────────────────────────────────────
# The record arm has no mutant: a damaged file is refused by its format checks, which neither mutant touches.
mutmode(){ case "$1" in gitdir) echo gitenv ;; record) echo none ;; *) echo trust ;; esac; }
for a in $ARMS; do
    echo "C $a"
    ARMFAIL=0; "arm_$a" "$TMP/n-$a" "$TMP/c-n-$a" "n-$a"
    if [ "$ARMFAIL" = 0 ]; then ok "C $a"; else no "C $a"; fi
    mm="$( mutmode "$a" )"
    [ "$mm" = none ] && continue
    echo "M $a (RIPWIRE_TEST_GITSTAMP_MUTANT=$mm — must fail)"
    ARMFAIL=0; "arm_$a" "$TMP/m-$a" "$TMP/c-m-$a" "m-$a" RIPWIRE_TEST_GITSTAMP_MUTANT="$mm"
    if [ "$ARMFAIL" = 1 ]; then ok "M $a — the arm catches the $mm mutant"; else no "M $a — the arm PASSED under the $mm mutant: it cannot catch that defect"; fi
done

# ── D: not a git repository ───────────────────────────────────────────────────────────────────────────────────────
echo "D: not a git repo"
call "$TMP/nogit" "$TMP/cD" D1; d1="$LAST_ALL"; call "$TMP/nogit" "$TMP/cD" D2; d2="$LAST_ALL"
cold "$TMP/nogit" D.cold
if [ "$d1" = 0 ] && [ "$d2" = 0 ]; then ok "D  no git process on a non-repo ($d1, $d2)"; else no "D  git ran on a non-repo ($d1, $d2)"; fi
if [ -z "$( find "$TMP/cD" -name 'ripwire-qstamp-*' )" ]; then ok "D  no STAMP record written"; else no "D  a STAMP record was written for a non-repo"; fi
if [ "$( eqcold D2 D.cold )" = 1 ]; then ok "D  answer equals a cold run's"; else no "D  answer differs from a cold run's"; fi

# ── E: the dirty bit is live ──────────────────────────────────────────────────────────────────────────────────────
echo "E: dirty appears and disappears"
call "$TMP/dirty" "$TMP/cE" E1; call "$TMP/dirty" "$TMP/cE" E2
e0="$( atOf "$TMP/E2.out" )"
printf 'scratch\n' >"$TMP/dirty/notes.txt"
call "$TMP/dirty" "$TMP/cE" E3; cold "$TMP/dirty" E3.cold; e1="$( atOf "$TMP/E3.out" )"
rm -f "$TMP/dirty/notes.txt"
call "$TMP/dirty" "$TMP/cE" E4; cold "$TMP/dirty" E4.cold; e2="$( atOf "$TMP/E4.out" )"
case "$e0" in *+dirty*) no "E  the clean tree already reads dirty ($e0)" ;; *) ok "E  clean before ($e0)" ;; esac
case "$e1" in *+dirty*) ok "E  +dirty on the very next call ($e1)" ;; *) no "E  an untracked file did not make the next call dirty ($e1)" ;; esac
if [ -z "$e2" ]; then no "E  no at= after the file went"
else case "$e2" in *+dirty*) no "E  still dirty after the file went ($e2)" ;; *) ok "E  clean again on the next call ($e2)" ;; esac; fi
if [ "$( eqcold E3 E3.cold )" = 1 ] && [ "$( eqcold E4 E4.cold )" = 1 ]; then ok "E  both answers equal cold runs'"; else no "E  a dirty-flip answer differs from a cold run's"; fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "c1stampcheck: FAILURES above"
exit "$fail"
