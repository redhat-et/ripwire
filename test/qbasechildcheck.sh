#!/usr/bin/env bash
# qbasechildcheck.sh — gate for QD-BASE-CHILD (verbs_quality.h baseInChild / runBaseChild, os.h spawn_self).
#
# On a qbase miss the CLI's --quality-delta=A..B re-runs itself as a child that builds the base side and writes the qbase
# blob; the parent reads the blob as a cache hit, so the base tree's freed pages leave with the child. Every way that can
# fail falls back to the in-process base phase. RIPWIRE_STATS prints one `ripwire: stats qbase-child outcome=… why=…`
# line per spawn decision, which is what makes each path countable here. This gate proves:
#
#   (P)  premise: the cold pair answers with regression rows and exit 2, the base came from the child (outcome=child),
#        both commits were ingested (two cache-stats lines: the child's passed through), and one qbase blob exists;
#   (I)  RIPWIRE_TEST_QBASE_CHILD=inproc spawns nothing and answers byte-identically (stdout, stderr without the stats
#        lines, rc) — the in-process answer the child path must reproduce;
#   (F)  a spawn that fails (spawnfail), a child that exits non-zero (exit) and a half-written blob (partial) each fall
#        back (outcome=fallback, why=spawn|exit|blob) to the same answer; the partial blob is not left in the cache; a
#        child that crashes (crash) falls back too, and its own stderr is passed through (why=signal);
#   (N)  --no-cache: the child hands the blob over in a temp file — same answer, no qbase blob, no temp file left;
#   (R)  a base tree the child cannot materialize: the child's refusal is said once (outcome=failed) with its exit code,
#        exactly as in-process;
#   (D)  a once-per-site notice that fires in BOTH phases prints as often as in-process (debug builds print it once;
#        release builds never) — the fixture's symlink leaves the tree in both commits (the escaped-root notice);
#   (U)  a base the child must not store (quality.h baseScoreStorable: its ingest refused a file for nesting, or extracted
#        one partially — CodeRabbit 4572576455 on #655): the child hands it over in the temp blob only (outcome=child
#        blob=temp), no qbase blob is written, the answer is the in-process one byte for byte (which stores none either),
#        and a repeat spawns again. Red before the merge's fix: the child cached the weakened base (one qbase blob, and the
#        repeat hit it);
#   (W)  a warm repeat hits the blob and spawns no child;
#   (S)  a stray RIPWIRE_QBASE_CHILD naming another parent is ignored: the run answers, and spawns its own child;
#   (Z)  the size floor: unforced, the fixture (a git index far below 1 MiB) scores its base in-process
#        (outcome=inproc why=small) with the same answer;
#   (L)  no ripwire-qbase-child-* file is left under TMPDIR by any run above.
# The fixture is small, so every child-path run above sets RIPWIRE_TEST_QBASE_CHILD=force (the seams imply it).
#
# Usage:  bash test/qbasechildcheck.sh          (BIN=build/ripwire)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${RIPWIRE_BIN:-${1:-$ROOT/build/ripwire}}"
case "$BIN" in /*) ;; *) BIN="$PWD/$BIN" ;; esac
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
echo "qbasechildcheck: BIN=$BIN"

FX="$WORK/fx"; mkdir -p "$FX/src" "$FX/data"
cat > "$FX/src/a.py" <<'EOF'
def helper(x):
    return x + 1

def main():
    return helper(2)
EOF
# a symlink whose target leaves the tree: refused by the ingest of each commit, through one once-per-site notice. (Not a
# nest-refused file: that base is never stored, so the child never answers it — arm (U).)
printf 'outside\n' > "$WORK/outside.txt"; ln -s "$WORK/outside.txt" "$FX/data/escape.txt"
# the (U) arm's extract-throw marker, in a file both commits hold; it throws only under RIPWIRE_TEST_EXTRACT_THROW
printf 'def other():\n    return 3  # rw-throw-here\n' > "$FX/src/b.py"
git_(){ git -C "$FX" -c user.name=t -c user.email=t@t "$@"; }
git_ init -q && git_ add -A && git_ commit -qm base || no "fixture: base commit"
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
BASESHA="$( git_ rev-parse HEAD~1 )"

# run <tag> <tmpdir> [VAR=value…] -- <args…>: stdout/stderr/rc in $WORK/<tag>.{out,err,rc}; a fresh HOME per tag
run(){
    local tag="$1" tmp="$2"; shift 2
    local envs=()
    while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do envs+=( "$1" ); shift; done
    shift
    mkdir -p "$WORK/home-$tag"
    ( cd "$FX" && env HOME="$WORK/home-$tag" TMPDIR="$tmp" RIPWIRE_STATS=1 RIPWIRE_CACHE_STATS=1 ${envs[@]+"${envs[@]}"} "$BIN" . "$@" > "$WORK/$tag.out" 2> "$WORK/$tag.err" )
    echo $? > "$WORK/$tag.rc"
}
outcome(){ sed -n 's/^ripwire: stats qbase-child outcome=\([a-z]*\) why=\([a-z-]*\).*/\1 \2/p' "$WORK/$1.err" | tr '\n' ';'; }
spawns(){ grep -c '^ripwire: stats qbase-child outcome=[cf]' "$WORK/$1.err"; }
ingests(){ grep -c 'ripwire: cache-stats ' "$WORK/$1.err"; }
answer_err(){   # stderr without the stats families and the fallback's own debug disclosure
    grep -v -E '^ripwire: (stats|memory-projection|cache-stats|quality-passes)|^\[mem\]|base child unavailable' "$WORK/$1.err" \
        | sed -E 's/ripwire-qdpair-(base|target)[-a-z]*-[0-9]+/ripwire-qdpair-\1-PID/g; s#/(tmp|t)-[a-z-]+/#/T/#g'
}
same(){ cmp -s "$WORK/$1.out" "$WORK/$2.out" && cmp -s "$WORK/$1.rc" "$WORK/$2.rc" && [ "$( answer_err "$1" )" = "$( answer_err "$2" )" ]; }
blobs(){ find "$1" -name 'ripwire-qbase-*' -type f 2>/dev/null | grep -v -e '\.tmp\.' -e 'qbase-child' | wc -l | tr -d ' '; }
leftovers(){ find "$WORK" -name 'ripwire-qbase-child-*' 2>/dev/null | wc -l | tr -d ' '; }
PAIR="--quality-delta=HEAD~1..HEAD"

# (P)
mkdir -p "$WORK/t-cold"; run cold "$WORK/t-cold" RIPWIRE_TEST_QBASE_CHILD=force -- "$PAIR"
regs="$( sed -n 's/.*<quality-delta [^>]* regressions="\([0-9]*\)".*/\1/p' "$WORK/cold.out" | head -1 )"
if [ "${regs:-0}" -ge 1 ] && [ "$( cat "$WORK/cold.rc" )" = 2 ]; then ok "(P) the cold pair answers with $regs regression rows, exit 2"; else no "(P) the cold pair: ${regs:-no} regression rows, rc $( cat "$WORK/cold.rc" )"; sed 's/^/    /' "$WORK/cold.err" | grep -v '^\s*\[mem\]' | head; fi
if [ "$( outcome cold )" = "child -;" ]; then ok "(P) the base came from the child (outcome=child)"; else no "(P) outcome '$( outcome cold )', expected 'child -;' — the child path never ran"; fi
if [ "$( ingests cold )" = 2 ]; then ok "(P) two ingests (the child's line passed through)"; else no "(P) $( ingests cold ) ingests, expected 2"; fi
if [ "$( blobs "$WORK/t-cold" )" = 1 ]; then ok "(P) the child wrote one qbase blob"; else no "(P) $( blobs "$WORK/t-cold" ) qbase blobs, expected 1"; fi

# (I)
mkdir -p "$WORK/t-inproc"; run inproc "$WORK/t-inproc" RIPWIRE_TEST_QBASE_CHILD=inproc -- "$PAIR"
if [ "$( spawns inproc )" = 0 ] && [ "$( ingests inproc )" = 2 ]; then ok "(I) inproc spawned nothing and ran both ingests itself"; else no "(I) inproc: $( spawns inproc ) spawn lines, $( ingests inproc ) ingests"; fi
if same cold inproc; then ok "(I) the child path is byte-identical to the in-process answer"; else no "(I) the child path differs from the in-process answer"; diff <( answer_err inproc ) <( answer_err cold ) | head -8 | sed 's/^/    /'; fi

# the warm in-process answer (base from the blob): what a repeat call is compared with
run inproc-warm "$WORK/t-inproc" RIPWIRE_TEST_QBASE_CHILD=inproc -- "$PAIR"

# (F)
seen=0
for seam in spawnfail:spawn exit:exit partial:blob; do
    s="${seam%%:*}"; why="${seam#*:}"
    mkdir -p "$WORK/t-$s"; run "$s" "$WORK/t-$s" RIPWIRE_TEST_QBASE_CHILD="$s" -- "$PAIR"
    if [ "$( outcome "$s" )" = "fallback $why;" ]; then seen=$(( seen + 1 )); ok "(F) $s fell back (why=$why)"; else no "(F) $s: outcome '$( outcome "$s" )', expected 'fallback $why;'"; fi
    if same inproc "$s"; then ok "(F) $s answers byte-identically to in-process"; else no "(F) $s differs from the in-process answer"; diff <( answer_err inproc ) <( answer_err "$s" ) | head -8 | sed 's/^/    /'; fi
done
[ "$seen" = 3 ] || no "(F) saw $seen of 3 fallbacks"
# a crash is never silent: the child's own line is passed through, then the in-process answer
mkdir -p "$WORK/t-crash"; run crash "$WORK/t-crash" RIPWIRE_TEST_QBASE_CHILD=crash -- "$PAIR"
if [ "$( outcome crash )" = "fallback signal;" ] && grep -q 'test seam: the base child aborts' "$WORK/crash.err" \
    && cmp -s "$WORK/inproc.out" "$WORK/crash.out" && cmp -s "$WORK/inproc.rc" "$WORK/crash.rc"; then
    ok "(F) a crashing child is said (its line on stderr, why=signal) and the in-process answer follows (same stdout, rc)"
else
    no "(F) crash: outcome '$( outcome crash )', seam line $( grep -c 'base child aborts' "$WORK/crash.err" ), stdout/rc $( cmp -s "$WORK/inproc.out" "$WORK/crash.out" && echo same || echo differ )"
fi
# the partial blob was removed and the in-process phase rewrote a valid one: the next call hits it
run partial2 "$WORK/t-partial" RIPWIRE_TEST_QBASE_CHILD=force -- "$PAIR"
if [ "$( spawns partial2 )" = 0 ] && [ "$( ingests partial2 )" = 1 ] && same inproc-warm partial2; then ok "(F) after partial, the rewritten blob hits (no spawn, one ingest, same answer)"; else no "(F) after partial: $( spawns partial2 ) spawns, $( ingests partial2 ) ingests"; fi

# (N)
mkdir -p "$WORK/t-nocache"; run nocache "$WORK/t-nocache" RIPWIRE_TEST_QBASE_CHILD=force -- "$PAIR" --no-cache
if [ "$( outcome nocache )" = "child -;" ] && [ "$( blobs "$WORK/t-nocache" )" = 0 ] && same inproc nocache; then ok "(N) --no-cache: the child handed over a temp blob — same answer, no qbase blob"; else no "(N) --no-cache: outcome '$( outcome nocache )', $( blobs "$WORK/t-nocache" ) blobs"; fi

# (R) a TMPDIR that does not exist: no commit tree can be materialized, in the child or in-process
run refuse "$WORK/t-absent" RIPWIRE_TEST_QBASE_CHILD=force -- "$PAIR"
run refuse-inproc "$WORK/t-absent" RIPWIRE_TEST_QBASE_CHILD=inproc -- "$PAIR"
if [ "$( outcome refuse )" = "failed -;" ] && [ "$( cat "$WORK/refuse.rc" )" != 0 ] && grep -q 'could not materialize' "$WORK/refuse.err"; then ok "(R) the child's refusal is passed through (outcome=failed, rc $( cat "$WORK/refuse.rc" ))"; else no "(R) refusal: outcome '$( outcome refuse )', rc $( cat "$WORK/refuse.rc" )"; fi
if [ "$( grep -c 'could not materialize' "$WORK/refuse.err" )" = 1 ] && same refuse-inproc refuse; then ok "(R) said once, byte-identical to in-process"; else no "(R) the refusal differs from in-process"; diff <( answer_err refuse-inproc ) <( answer_err refuse ) | head -6 | sed 's/^/    /'; fi

# (D)
NOTICE="ingest: a symlink's target leaves the crawl root"
mkdir -p "$WORK/t-escaped"; run escaped "$WORK/t-escaped" -- --skipped   # the tree both commits hold the link in
esc="$( grep -o '<f p="data/escape.txt" why="escaped-root"' "$WORK/escaped.out" | grep -c . )"
if [ "$esc" = 1 ]; then ok "(D) premise: the symlink is refused as escaped-root (one --skipped row; both commits hold it)"; else no "(D) premise: $esc escaped-root rows, expected 1 — the fixture no longer reaches the notice"; fi
nc="$( grep -c "$NOTICE" "$WORK/cold.err" )"; ni="$( grep -c "$NOTICE" "$WORK/inproc.err" )"
if [ "$nc" = "$ni" ] && [ "$nc" -le 1 ]; then ok "(D) the once-per-site notice printed $nc time(s), as in-process ($ni)"; else no "(D) the notice printed $nc time(s) on the child path, $ni in-process"; fi

# (U) — two weakened bases: a nest-refused file (deep JSON in both commits) and a partially extracted one (the marker)
FU="$WORK/fu"; cp -R "$FX" "$FU"
gitu(){ git -C "$FU" -c user.name=t -c user.email=t@t "$@"; }
gitu checkout -q HEAD~1 && python3 -c 'print("[" * 600 + "]" * 600)' > "$FU/data/deep.json" && gitu add -A && gitu commit -qm "base with deep json" \
    && gitu cherry-pick "$( git -C "$FX" rev-parse HEAD )" >/dev/null || no "(U) fixture: deep-json commits"
runu(){ local tag="$1" dir="$2"; shift 2; ( FX="$dir"; run "$tag" "$@" ); }
useen=0
for cell in "nest:$FU:" "partial:$FX:RIPWIRE_TEST_EXTRACT_THROW=rw-throw-here"; do
    c="${cell%%:*}"; rest="${cell#*:}"; dir="${rest%%:*}"; thr="${rest#*:}"
    ue=( ${thr:+"$thr"} )
    for nc_ in "" "--no-cache"; do
        t="u-$c${nc_:+-nc}"
        mkdir -p "$WORK/t-$t" "$WORK/t-$t-in"
        runu "$t" "$dir" "$WORK/t-$t" RIPWIRE_TEST_QBASE_CHILD=force ${ue[@]+"${ue[@]}"} -- "$PAIR" $nc_
        runu "$t-in" "$dir" "$WORK/t-$t-in" RIPWIRE_TEST_QBASE_CHILD=inproc ${ue[@]+"${ue[@]}"} -- "$PAIR" $nc_
        if [ "$( outcome "$t" )" = "child -;" ] && grep -q '^ripwire: stats qbase-child outcome=child .* blob=temp$' "$WORK/$t.err" \
            && [ "$( blobs "$WORK/t-$t" )" = 0 ] && [ "$( blobs "$WORK/home-$t" )" = 0 ]; then
            useen=$(( useen + 1 )); ok "(U) $c ${nc_:-cached}: the child answered through the temp blob and stored no qbase blob"
        else
            no "(U) $c ${nc_:-cached}: outcome '$( outcome "$t" )', $( blobs "$WORK/t-$t" ) qbase blob(s), $( grep -o 'blob=[a-z-]*$' "$WORK/$t.err" ) — the child stored a weakened base"
        fi
        if same "$t-in" "$t" && [ "$( blobs "$WORK/t-$t-in" )" = 0 ]; then ok "(U) $c ${nc_:-cached}: byte-identical to in-process, which stores none either"; else no "(U) $c ${nc_:-cached}: differs from in-process (or in-process stored $( blobs "$WORK/t-$t-in" ) blob(s))"; diff <( answer_err "$t-in" ) <( answer_err "$t" ) | head -6 | sed 's/^/    /'; fi
    done
    # the premise: the base really was weakened, so the run said so (a nest-refusal line, or the extract-partial disclosure)
    if grep -q -e 'json nesting > 512 levels' -e 'RIPWIRE_TEST_EXTRACT_THROW' -e 'extract-partial' "$WORK/u-$c.err"; then ok "(U) $c premise: the weakened base was disclosed"; else no "(U) $c premise: no nest-refusal or extract-partial line — the fixture no longer weakens the base"; fi
    runu "u-$c-2" "$dir" "$WORK/t-u-$c" RIPWIRE_TEST_QBASE_CHILD=force ${ue[@]+"${ue[@]}"} -- "$PAIR"
    if [ "$( outcome "u-$c-2" )" = "child -;" ] && same "u-$c" "u-$c-2"; then ok "(U) $c: the repeat finds no blob, spawns again, same answer"; else no "(U) $c repeat: outcome '$( outcome "u-$c-2" )'"; fi
done
[ "$useen" = 4 ] || no "(U) saw $useen of 4 temp-only hand-overs"

# (W)
run warm "$WORK/t-cold" RIPWIRE_TEST_QBASE_CHILD=force -- "$PAIR"
if [ "$( spawns warm )" = 0 ] && [ "$( ingests warm )" = 1 ] && same inproc-warm warm; then ok "(W) the warm repeat hit the blob: no child, one ingest, same answer"; else no "(W) warm: $( spawns warm ) spawns, $( ingests warm ) ingests"; fi

# (S)
mkdir -p "$WORK/t-stray"; run stray "$WORK/t-stray" RIPWIRE_TEST_QBASE_CHILD=force RIPWIRE_QBASE_CHILD=1:"$BASESHA":"$BASESHA":"$WORK/stray.bin" -- "$PAIR"
if [ "$( outcome stray )" = "child -;" ] && same inproc stray && [ ! -e "$WORK/stray.bin" ]; then ok "(S) a stray RIPWIRE_QBASE_CHILD is ignored (own child, same answer)"; else no "(S) stray: outcome '$( outcome stray )'"; fi

# (Z)
mkdir -p "$WORK/t-small"; run small "$WORK/t-small" -- "$PAIR"
if [ "$( outcome small )" = "inproc small;" ] && [ "$( spawns small )" = 0 ] && same inproc small; then ok "(Z) below the size floor the base is scored in-process (why=small), same answer"; else no "(Z) small: outcome '$( outcome small )', $( spawns small ) spawns"; fi

# (L)
if [ "$( leftovers )" = 0 ]; then ok "(L) no ripwire-qbase-child-* file left"; else no "(L) $( leftovers ) ripwire-qbase-child-* files left"; find "$WORK" -name 'ripwire-qbase-child-*' | sed 's/^/    /'; fi

if [ "$fail" = 0 ]; then echo "qbasechildcheck: PASS"; else echo "qbasechildcheck: FAIL"; fi
exit "$fail"
