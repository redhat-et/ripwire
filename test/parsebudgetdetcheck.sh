#!/usr/bin/env bash
# parsebudgetdetcheck.sh — PARSE-BUDGET-DETERMINISTIC: the NO-SKIP parse budget must not depend on machine load.
#
# NO-SKIP-INGEST cut a parse (and the tags query after it) at a WALL-CLOCK deadline, 4 s + 1 s/MiB: a file near that edge
# was parsed on a quiet machine and read lexically on a loaded one — a different index for the same tree (ld-zed-06 flaked;
# vscode's md5 needed RIPWIRE_PARSE_BUDGET=20). The deciding cut is now a WORK budget counted in tree-sitter progress steps
# (ingest.h kParseBudget*), a function of the bytes and the grammar; wall clock and memory remain only as a disclosed
# BACKSTOP with its own mode, warning and --skipped word, retried on the next run. Every fixture is generated here.
#
#   (a) a file near the old wall edge gives byte-identical stdout+stderr+rc quiet, throttled (SIGSTOP 90 % of the time) and
#       under RIPWIRE_TEST_PARSE=slow:<us>; its RIPWIRE_PARSE_STEPS_LOG step count is the same under load;
#   (b) degenerate input (100 KB, 200 KB, 4 MiB of `{`) is still cut, in bounded time, and the warning names the WORK
#       budget in steps (tree-sitter patch 002 counts the query's quadratic sibling scan);
#   (c) RIPWIRE_TEST_PARSE=wall / =memory force each backstop: its own warning, --skipped why=lexical-wall / lexical-memory,
#       and a later run without it re-parses the file (a backstop record is never kept);
#   (d) negative: a small normal corpus meets no limit and is byte-identical quiet, throttled and slowed.
# Each arm counts its premise and FAILS on zero.
#
#   bash test/parsebudgetdetcheck.sh [BIN]     # lane no-skip-ingest 506afce6f FAILS (a), (b), (c)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
unset RIPWIRE_PARSE_BUDGET RIPWIRE_TEST_PARSE RIPWIRE_PARSE_STEPS_LOG
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "parsebudgetdetcheck: BIN=$BIN"

now(){ perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }
hdr(){ grep -oE '<!-- files=[^>]*-->' "$1" | head -1; }
attr(){ grep -oE "$2=\"?[0-9]+" "$1" | head -1 | grep -oE '[0-9]+$'; }
warns(){ grep -c '^ripwire: warning: ' "$1"; }
# run "$@" with the process stopped 90 % of the time: a loaded machine, about ten times slower on the wall clock (perl, so
# the 10 ms run window is not eaten by spawning sleep(1))
throttled(){
    "$@" &
    local pid=$!
    perl -MTime::HiRes=usleep -e '$p = shift; while( kill 0, $p ) { kill "STOP", $p; usleep 90000; kill "CONT", $p; usleep 10000 }' "$pid" &
    local th=$!
    wait "$pid"; local rc=$?
    kill "$th" 2>/dev/null; wait "$th" 2>/dev/null
    kill -CONT "$pid" 2>/dev/null
    return "$rc"
}
# run one map; $1 = tag, $2 = corpus, the rest = a prefix (env / throttled); writes $TMP/<tag>.{out,err,rc,secs}
run(){
    local tag="$1" dir="$2"; shift 2
    local t0; t0="$( now )"
    "$@" "$BIN" "$dir" --no-cache --legend=compact >"$TMP/$tag.out" 2>"$TMP/$tag.err"
    echo $? >"$TMP/$tag.rc"
    echo "$( now ) $t0" | awk '{ printf "%.2f\n", $1 - $2 }' >"$TMP/$tag.secs"
}
same(){
    local rcA rcB
    rcA="$( cat "$TMP/$1.rc" )"; rcB="$( cat "$TMP/$2.rc" )"
    [ "$rcA" = "$rcB" ] && cmp -s "$TMP/$1.out" "$TMP/$2.out" && cmp -s "$TMP/$1.err" "$TMP/$2.err"
}
slower(){ awk -v a="$( cat "$TMP/$1.secs" )" -v b="$( cat "$TMP/$2.secs" )" -v k="$3" 'BEGIN { exit !( a >= k * b ) }'; }

# ── fixtures ────────────────────────────────────────────────────────────────────────────────────────────────────────
python3 - "$TMP" <<'EOF'
import os, sys
t = sys.argv[1]
def w(p, s):
    os.makedirs(os.path.dirname(p), exist_ok=True); open(p, "w").write(s)
# (a) 1 MiB of ordinary C: ~0.4 s to extract on an M2. At RIPWIRE_PARSE_BUDGET=0.25 the old wall budget is 1.25 s (quiet
# fits, ten times slower does not) while the work budget (0.25 x (0.5M + 1M) = 375k steps) is 9.5x its ~39k steps and the
# wall backstop (0.25 x 50 s = 12.5 s) is 3x the throttled extraction.
parts, n, i = [], 0, 0
while n < 1024 * 1024:
    f = f"static int edge_fn_{i}(int x)\n{{\n    int y = edge_fn_{max(i - 1, 0)}(x) + {i};\n    if (y > {i}) {{ return y * 2; }}\n    return y;\n}}\n\n"
    parts.append(f); n += len(f); i += 1
w(f"{t}/edge/edge.c", "".join(parts) + "int edge_entry(void)\n{\n    return edge_fn_7(1);\n}\n")
# (b) degenerate: runs of '{' (tree-sitter's query status walk is quadratic on them)
for name, k in (("b100k", 100 * 1024), ("b200k", 200 * 1024), ("b4m", 4 * 1024 * 1024)):
    w(f"{t}/{name}/deep.c", "void deep_entry(void)\n{\n}\n" + "{" * k)
# (d) a small normal corpus, several languages
w(f"{t}/small/a.c", "int f(void)\n{\n    return g();\n}\nint g(void)\n{\n    return 1;\n}\n")
w(f"{t}/small/b.py", "def h():\n    return k()\n\ndef k():\n    return 2\n")
w(f"{t}/small/c.ts", "export function m(): number {\n  return n();\n}\nfunction n(): number {\n  return 3;\n}\n")
w(f"{t}/small/d.go", "package d\n\nfunc P() int {\n\treturn Q()\n}\n\nfunc Q() int {\n\treturn 4\n}\n")
EOF

# ── (a) a file near the old wall edge: the same bytes quiet and loaded ─────────────────────────────────────────────
export RIPWIRE_PARSE_BUDGET=0.25
run aq "$TMP/edge"
run at "$TMP/edge" throttled
run as "$TMP/edge" env RIPWIRE_TEST_PARSE=slow:80
if [ "$( attr "$TMP/aq.out" symbols )" -ge 8000 ] 2>/dev/null && ! grep -q 'lexical_files=' "$TMP/aq.out"; then
    ok "a: premise — quiet run parses edge.c ($( cat "$TMP/aq.secs" ) s; $( hdr "$TMP/aq.out" ))"
else
    no "a: premise — the quiet run did not parse edge.c ($( cat "$TMP/aq.secs" ) s; $( hdr "$TMP/aq.out" ); $( head -1 "$TMP/aq.err" ))"
fi
# identity first: a run that moved is red whatever its time (a wall cut also SHORTENS the loaded run); an identical run must
# also have been slowed, or the arm saw no load at all
if ! same aq at; then
    no "a: throttled run differs ($( cat "$TMP/at.secs" ) s vs $( cat "$TMP/aq.secs" ) s; $( hdr "$TMP/at.out" ); $( head -1 "$TMP/at.err" | cut -c1-200 ))"
elif slower at aq 3; then
    ok "a: throttled run ($( cat "$TMP/at.secs" ) s vs $( cat "$TMP/aq.secs" ) s) is byte-identical (stdout, stderr, rc)"
else
    no "a: premise — throttling did not slow the run ($( cat "$TMP/at.secs" ) s vs $( cat "$TMP/aq.secs" ) s)"
fi
if ! same aq as; then
    no "a: slowed run differs ($( hdr "$TMP/as.out" ); $( head -1 "$TMP/as.err" | cut -c1-200 ))"
elif slower as aq 2; then
    ok "a: RIPWIRE_TEST_PARSE=slow:80 run ($( cat "$TMP/as.secs" ) s vs $( cat "$TMP/aq.secs" ) s) is byte-identical"
else
    no "a: premise — RIPWIRE_TEST_PARSE=slow:80 did not slow the run ($( cat "$TMP/as.secs" ) s vs $( cat "$TMP/aq.secs" ) s): no test knob"
fi
RIPWIRE_PARSE_STEPS_LOG="$TMP/steps.q" "$BIN" "$TMP/edge" --no-cache >/dev/null 2>&1   # status: read from the log below; a missing log FAILs
throttled env RIPWIRE_PARSE_STEPS_LOG="$TMP/steps.t" "$BIN" "$TMP/edge" --no-cache >/dev/null 2>&1   # status: likewise
sq="$( grep 'edge\.c$' "$TMP/steps.q" 2>/dev/null | cut -f1 )"; st="$( grep 'edge\.c$' "$TMP/steps.t" 2>/dev/null | cut -f1 )"
if [ -n "$sq" ] && [ "${sq:-0}" -gt 1000 ]; then
    if [ "$sq" = "$st" ]; then ok "a: edge.c spends $sq steps quiet and $st loaded (RIPWIRE_PARSE_STEPS_LOG)"; else no "a: steps moved with load: $sq quiet, ${st:-none} loaded"; fi
else
    no "a: premise — no RIPWIRE_PARSE_STEPS_LOG line for edge.c (got '${sq:-}')"
fi
unset RIPWIRE_PARSE_BUDGET

# ── (b) degenerate input is still cut by the WORK budget, in bounded time ──────────────────────────────────────────
for d in b100k b200k b4m; do
    t0="$( now )"
    perl -e 'alarm 120; exec @ARGV' "$BIN" "$TMP/$d" --no-cache --legend=compact >"$TMP/b.$d.out" 2>"$TMP/b.$d.err"   # status: the alarm bounds the arm; the attributes and the warning below are the verdict
    secs="$( echo "$( now ) $t0" | awk '{ printf "%.1f\n", $1 - $2 }' )"
    if awk -v s="$secs" 'BEGIN { exit !( s <= 30 ) }'; then ok "b: $d cut in $secs s"; else no "b: $d took $secs s"; fi
    if [ "$( attr "$TMP/b.$d.out" lexical_files )" = 1 ] && grep -q 'n="deep_entry"' "$TMP/b.$d.out"; then ok "b: $d lexical_files=1, deep_entry indexed lexically"
    else no "b: $d $( hdr "$TMP/b.$d.out" )"; fi
    if grep -qE 'ran past its parse budget of [0-9.]+M steps; indexed lexically \(raise with RIPWIRE_PARSE_BUDGET=<scale>\)' "$TMP/b.$d.err"; then
        ok "b: $d warning names the work budget in steps"
    else
        no "b: $d warning: $( head -1 "$TMP/b.$d.err" | cut -c1-200 )"
    fi
done
"$BIN" "$TMP/b200k" --no-cache --skipped >"$TMP/b.sk" 2>/dev/null   # status: the row below is the verdict
if grep -qE '<h p="[^"]*deep\.c" why="lexical-budget"' "$TMP/b.sk"; then ok "b: --skipped rows it why=lexical-budget"; else no "b: no lexical-budget row"; fi
run bq "$TMP/b200k"
run bt "$TMP/b200k" throttled
if same bq bt; then ok "b: the cut itself is the same throttled ($( cat "$TMP/bt.secs" ) s vs $( cat "$TMP/bq.secs" ) s)"; else no "b: the degenerate cut moved with load"; fi

# ── (c) each backstop, forced: its own disclosure; never kept in the cache ─────────────────────────────────────────
for k in wall memory; do
    RIPWIRE_TEST_PARSE=$k "$BIN" "$TMP/edge" --no-cache --legend=compact >"$TMP/c.$k.out" 2>"$TMP/c.$k.err"   # status: the attributes and warning below are the verdict
    RIPWIRE_TEST_PARSE=$k "$BIN" "$TMP/edge" --no-cache --skipped >"$TMP/c.$k.sk" 2>/dev/null   # status: likewise
    if [ "$( attr "$TMP/c.$k.out" lexical_files )" = 1 ]; then ok "c: $k backstop: lexical_files=1"; else no "c: $k backstop: $( hdr "$TMP/c.$k.out" )"; fi
    if grep -qE "<h p=\"[^\"]*edge\\.c\" why=\"lexical-$k\"" "$TMP/c.$k.sk"; then ok "c: --skipped rows edge.c why=lexical-$k"; else no "c: no lexical-$k row"; fi
    grep -q 'ran past its parse budget' "$TMP/c.$k.err" && no "c: the $k backstop reads as the work budget"
done
if grep -q 'hit the [0-9]* s wall-clock backstop before its parse budget (this machine is slow or loaded: the result depends on load); indexed lexically, retried next run' "$TMP/c.wall.err"
then ok "c: the wall backstop says the result depends on load"; else no "c: wall warning: $( head -1 "$TMP/c.wall.err" | cut -c1-200 )"; fi
if grep -q 'reached half the memory limit before its parse budget (the result depends on memory pressure); indexed lexically, retried next run (raise with --max-memory=N)' "$TMP/c.memory.err"
then ok "c: the memory backstop says the result depends on memory pressure"; else no "c: memory warning: $( head -1 "$TMP/c.memory.err" | cut -c1-200 )"; fi
C="$TMP/edge.cache"
RIPWIRE_TEST_PARSE=wall "$BIN" "$TMP/edge" --cache="$C" --legend=compact >"$TMP/c.w1" 2>/dev/null   # status: the comparison below is the verdict
"$BIN" "$TMP/edge" --cache="$C" --legend=compact >"$TMP/c.w2" 2>"$TMP/c.w2.err"   # status: likewise
if [ "$( attr "$TMP/c.w1" lexical_files )" = 1 ]; then
    if ! grep -q 'lexical_files=' "$TMP/c.w2" && [ "$( attr "$TMP/c.w2" symbols )" -ge 8000 ] 2>/dev/null; then
        ok "c: the next run re-parses a backstop record (no lexical_files=, $( warns "$TMP/c.w2.err" ) warnings)"
    else
        no "c: a backstop record was kept: $( hdr "$TMP/c.w2" )"
    fi
else
    no "c: premise — the forced wall backstop did not cut the cached run ($( hdr "$TMP/c.w1" ))"
fi

# ── (d) negative: a normal corpus meets no limit and does not move with load ───────────────────────────────────────
run dq "$TMP/small"
run dt "$TMP/small" throttled
run ds "$TMP/small" env RIPWIRE_TEST_PARSE=slow:80
files="$( attr "$TMP/dq.out" files )"; sy="$( attr "$TMP/dq.out" symbols )"
if [ "${files:-0}" -ge 4 ] && [ "${sy:-0}" -ge 8 ]; then
    if [ "$( warns "$TMP/dq.err" )" = 0 ] && ! grep -qE 'lexical_files=|keys_cut=' "$TMP/dq.out"; then ok "d: no warning, no lexical attribute (saw files=$files symbols=$sy)"
    else no "d: a limit on the normal corpus: $( head -1 "$TMP/dq.err" ) $( hdr "$TMP/dq.out" )"; fi
    if same dq dt && same dq ds; then ok "d: byte-identical quiet, throttled and slowed"; else no "d: the normal corpus moved with load"; fi
else
    no "d: the negative corpus was not seen (files=${files:-none} symbols=${sy:-none})"
fi

[ "$fail" = 0 ] && echo "parsebudgetdetcheck: PASS" || echo "parsebudgetdetcheck: FAIL"
exit "$fail"
