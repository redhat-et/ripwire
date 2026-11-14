#!/usr/bin/env bash
# qbasecachecheck.sh — gate for QD-PAIR-BASE-CACHE (verbs_quality.h scoreBaseCommit, quality.h's "qbase" blob family).
#
# The base side of --quality-delta=A..B (its Snapshot for the selected kinds and its C-family macro names) is stored by
# base sha in a self-validating blob, so a repeat A..B with the same base archives, parses and scores only the target.
# The ingest of each commit prints one `cache-stats` line under RIPWIRE_CACHE_STATS, so the base ingest is countable:
# a cold pair prints two, a pair whose base came from the blob prints one. This gate proves:
#
#   (P)  premise: the cold pair answers with regression rows (so "byte-equal" below compares a real answer), runs two
#        ingests, and writes exactly one qbase blob;
#   (H)  a repeat call HITS (one ingest, no new blob) and is byte-identical to the cold call (stdout, stderr without the
#        stats lines, rc);
#   (N)  --no-cache neither reads nor writes the blob (two ingests, no new blob) and answers byte-identically;
#   (X)  a changed --exclude MISSES (two ingests, a second blob); so does a changed --quality-kinds selection. The build's
#        producer identity is folded into the same key string as both (verbs_quality.h scoreBaseCommit: the qsnap key plus the kinds);
#   (C)  a corrupt blob is REFUSED: the corrupt line on stderr, two ingests, the same answer, and the rewritten blob hits
#        on the next call;
#   (T)  a truncated blob is refused the same way.
#
# Usage:  bash test/qbasecachecheck.sh          (BIN=build/ripwire)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"   # the fixture is a git repo: no inherited GIT_DIR / GIT_WORK_TREE may select the caller's (CodeRabbit 4572576459)
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
case "$BIN" in /*) ;; *) BIN="$PWD/$BIN" ;; esac
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
echo "qbasecachecheck: BIN=$BIN"

FX="$WORK/fx"; mkdir -p "$FX/src" "$FX/tests" "$WORK/home" "$WORK/tmp"
cat > "$FX/src/a.py" <<'EOF'
def helper(x):
    return x + 1

def main():
    return helper(2)
EOF
printf 'def test_a():\n    assert True\n' > "$FX/tests/test_a.py"
git_(){ git -C "$FX" -c user.name=t -c user.email=t@t "$@"; }
git_ init -q && git_ add -A && git_ commit -qm base || no "fixture: base commit"
# the target: a deeper function and a swallowed error, so the pair has regression rows
cat > "$FX/src/a.py" <<'EOF'
def helper(x):
    if x > 0:
        if x > 1:
            if x > 2:
                if x > 3:
                    if x > 4:
                        return x
    try:
        return x + 1
    except Exception:
        pass

def main():
    return helper(2)
EOF
git_ commit -qam target || no "fixture: target commit"

run(){   # run <tag> <args…>: stdout/stderr/rc in $WORK/<tag>.{out,err,rc}
    local tag="$1"; shift
    ( cd "$FX" && env HOME="$WORK/home" TMPDIR="$WORK/tmp" RIPWIRE_CACHE_STATS=1 "$BIN" . "$@" > "$WORK/$tag.out" 2> "$WORK/$tag.err" ); echo $? > "$WORK/$tag.rc"
}
ingests(){ grep -c 'ripwire: cache-stats ' "$WORK/$1.err"; }
blobs(){ find "$WORK/home" "$WORK/tmp" -name 'ripwire-qbase-*' -type f 2>/dev/null | grep -v '\.tmp\.' | sort; }
same(){   # same <a> <b>: stdout, stderr without the stats and corrupt lines, rc
    cmp -s "$WORK/$1.out" "$WORK/$2.out" && cmp -s "$WORK/$1.rc" "$WORK/$2.rc" \
        && [ "$( grep -v 'cache-stats \|base Snapshot cache corrupt' "$WORK/$1.err" )" = "$( grep -v 'cache-stats \|base Snapshot cache corrupt' "$WORK/$2.err" )" ]
}
PAIR="--quality-delta=HEAD~1..HEAD"

# (P)
run cold "$PAIR"
regs="$( sed -n 's/.*<quality-delta [^>]* regressions="\([0-9]*\)".*/\1/p' "$WORK/cold.out" | head -1 )"
if [ "${regs:-0}" -ge 1 ]; then ok "(P) the cold pair answers with $regs regression rows (rc $( cat "$WORK/cold.rc" ))"; else no "(P) the cold pair has no regression rows — nothing to compare"; sed 's/^/    /' "$WORK/cold.err" | head; fi
# rc 2: the target made old code worse (the regression rows above), so the answer must say so in its exit status too
if [ "$( cat "$WORK/cold.rc" )" = 2 ]; then ok "(P) the cold pair exits 2 (a regression)"; else no "(P) the cold pair exited $( cat "$WORK/cold.rc" ), expected 2"; fi
if [ "$( ingests cold )" = 2 ]; then ok "(P) the cold pair ran two ingests"; else no "(P) the cold pair ran $( ingests cold ) ingests, expected 2"; fi
if [ "$( blobs | wc -l | tr -d ' ' )" = 1 ]; then ok "(P) one qbase blob written"; else no "(P) $( blobs | wc -l | tr -d ' ' ) qbase blobs after the cold pair, expected 1"; fi
BLOB="$( blobs | head -1 )"

# (H)
run hit "$PAIR"
if [ "$( ingests hit )" = 1 ]; then ok "(H) the repeat call hit the blob (one ingest: the target)"; else no "(H) the repeat call ran $( ingests hit ) ingests, expected 1"; fi
if same cold hit; then ok "(H) the hit answer is byte-identical to the cold one"; else no "(H) the hit answer differs from the cold one"; diff "$WORK/cold.out" "$WORK/hit.out" | head -5; fi
if [ "$( blobs | wc -l | tr -d ' ' )" = 1 ]; then ok "(H) no new blob"; else no "(H) a hit wrote another blob"; fi

# (N)
run nocache "$PAIR" --no-cache
if [ "$( ingests nocache )" = 2 ] && same cold nocache && [ "$( blobs | wc -l | tr -d ' ' )" = 1 ]; then
    ok "(N) --no-cache read no blob (two ingests), wrote none, same answer"
else
    no "(N) --no-cache: $( ingests nocache ) ingests, $( blobs | wc -l | tr -d ' ' ) blobs, same=$( same cold nocache && echo 1 || echo 0 )"
fi

# (X)
run excl "$PAIR" --exclude=no_such_dir/
if [ "$( ingests excl )" = 2 ] && [ "$( blobs | wc -l | tr -d ' ' )" = 2 ]; then ok "(X) a changed --exclude missed (two ingests, its own blob)"; else no "(X) changed --exclude: $( ingests excl ) ingests, $( blobs | wc -l | tr -d ' ' ) blobs"; fi
run kinds "$PAIR" --quality-kinds=complexity
if [ "$( ingests kinds )" = 2 ] && [ "$( blobs | wc -l | tr -d ' ' )" = 3 ]; then ok "(X) a changed --quality-kinds missed (two ingests, its own blob)"; else no "(X) changed --quality-kinds: $( ingests kinds ) ingests, $( blobs | wc -l | tr -d ' ' ) blobs"; fi

# (C) one flipped byte in the middle of the blob
python3 - "$BLOB" <<'PY'
import sys
p = sys.argv[1]; b = bytearray( open( p, "rb" ).read() ); b[ len( b ) // 2 ] ^= 0xFF; open( p, "wb" ).write( bytes( b ) )
PY
run corrupt "$PAIR"
if grep -q 'base Snapshot cache corrupt — recomputing' "$WORK/corrupt.err" && [ "$( ingests corrupt )" = 2 ] && same cold corrupt; then
    ok "(C) a corrupt blob is refused (stderr line, two ingests) and the answer is unchanged"
else
    no "(C) corrupt blob: line=$( grep -c 'cache corrupt' "$WORK/corrupt.err" ) ingests=$( ingests corrupt ) same=$( same cold corrupt && echo 1 || echo 0 )"
fi
run rehit "$PAIR"
if [ "$( ingests rehit )" = 1 ] && ! grep -q 'cache corrupt' "$WORK/rehit.err" && same cold rehit; then ok "(C) the rewritten blob hits on the next call"; else no "(C) after the rewrite: $( ingests rehit ) ingests"; fi

# (T) truncated to half
python3 - "$BLOB" <<'PY'
import sys
p = sys.argv[1]; b = open( p, "rb" ).read(); open( p, "wb" ).write( b[ : len( b ) // 2 ] )
PY
run trunc "$PAIR"
if grep -q 'base Snapshot cache corrupt — recomputing' "$WORK/trunc.err" && [ "$( ingests trunc )" = 2 ] && same cold trunc; then ok "(T) a truncated blob is refused and recomputed"; else no "(T) truncated blob: ingests=$( ingests trunc )"; fi

# (D) a base whose ingest extracted a file only partially is answered but never stored (quality.h baseScoreStorable): a hit
#     would replay the answer without the extract-partial disclosure only the ingest prints. RIPWIRE_TEST_EXTRACT_THROW makes
#     the worker throw on the file holding the marker (it is in both commits). Red before (CodeRabbit 4572576455 on #655): the
#     pair wrote a blob, and the repeat hit it (one ingest) with no disclosure of the base side.
FD="$WORK/fd"; cp -R "$FX" "$FD"; rm -rf "$WORK/home-d" "$WORK/tmp-d"; mkdir -p "$WORK/home-d" "$WORK/tmp-d"
git -C "$FD" -c user.name=t -c user.email=t@t checkout -q HEAD~1 && printf '# rw-throw-here\n' >> "$FD/tests/test_a.py" \
    && git -C "$FD" -c user.name=t -c user.email=t@t commit -qam "base with marker" && git -C "$FD" -c user.name=t -c user.email=t@t cherry-pick "$( git -C "$FX" rev-parse HEAD )" >/dev/null \
    || no "(D) fixture: marker commits"
rund(){ local tag="$1"; shift; ( cd "$FD" && env HOME="$WORK/home-d" TMPDIR="$WORK/tmp-d" RIPWIRE_CACHE_STATS=1 RIPWIRE_TEST_EXTRACT_THROW=rw-throw-here "$BIN" . "$@" > "$WORK/$tag.out" 2> "$WORK/$tag.err" ); echo $? > "$WORK/$tag.rc"; }
dblobs(){ find "$WORK/home-d" "$WORK/tmp-d" -name 'ripwire-qbase-*' -type f 2>/dev/null | grep -v '\.tmp\.' | grep -c .; }
rund d1 "$PAIR"
rund d2 "$PAIR"
dpart="$( grep -c 'extract-partial\|worker exception' "$WORK/d2.err" )"
if [ "$( cat "$WORK/d1.rc" )" = 2 ] && [ "$( dblobs )" = 0 ] && [ "$( ingests d2 )" = 2 ] && cmp -s "$WORK/d1.out" "$WORK/d2.out"; then
    ok "(D) a base with a partially extracted file answers (rc 2) but writes no blob; the repeat ingests both commits again"
else
    no "(D) rc $( cat "$WORK/d1.rc" ), $( dblobs ) blob(s), repeat ingests $( ingests d2 ), same=$( cmp -s "$WORK/d1.out" "$WORK/d2.out" && echo 1 || echo 0 ), partial lines $dpart"
fi

[ "$fail" = 0 ] && echo "qbasecachecheck: PASS" || echo "qbasecachecheck: FAIL"
exit "$fail"
