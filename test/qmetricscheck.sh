#!/usr/bin/env bash
# qmetricscheck.sh — VERB-FS QMETRICS (src/verbfs_qmetrics.h): the two whole-index derived results a served run recomputed
# after every snapshot load, kept per index.
#
# THE COST (results/PHASESPLIT_1125 §2, llvm-project, served warm --for, B1): after the snapshot load, main.cpp recomputes
#   computeQMetrics( ing, g )   235.5 ms main-thread wall   (tested= and lcom4= are the expensive half)
#   computeImpure( ing, g )      75.6 ms
# on every call, though both are pure functions of the index and the graph. Each is now served from a record in the cache
# directory (ripwire-verbfs-<rootKey>-<part>-….bin, parts qmetrics and impure) when a digest of EVERY input the
# computation reads from the model and the graph equals the stored one. The digest is kept as named components, so a miss
# says which input moved (why=files|symbols|refs|graph|shape) and each mutant below can blind exactly one of them.
#
# THE ARMS. Identity arms compare stdout (+ rc) of a served call against RIPWIRE_NO_VERBFS=1 (no record read or written)
# and against --no-cache (no cache of any kind). An identity arm passes on code with no record at all, so the record's use
# is proven by COUNTER arms (red on the base: the `[verbfs] qmetrics` / `[verbfs] impure` stats lines do not exist there)
# and each invalidation arm is paired with a MUTATION arm (a non-NDEBUG fault switch that blinds one key component) that
# must turn that arm's identity red.
#   S1  COUNTER: the second cached --for serves qmetrics and impure (served=1 why=ok); the first built them (wrote=1)
#   S2  IDENTITY on an unchanged index: --for, --metrics, --html=FILE (the file), --quality-panel, --exemplar,
#       --quality-delta, and MCP `for` + `exemplar` (served vs RIPWIRE_NO_VERBFS=1)
#   I1  a call added inside a test function (graph only: tested= moves)            why=graph    mutant NOGRAPH
#   I2  a side-effecting call added to a helper a const method calls (impure only)  why=refs     mutant NOREFS
#   I3  a file renamed into the test partition (only a path text moves)            why=files    mutant NOFILES
#   I4  a changed flag (--exclude=tests: the index loses its test file)             why=shape/…  mutant ANYDIGEST
#   I6  a symbol leaves the in-file test convention (def test_probe -> check_probe)  why=symbols  mutant NOSYMS
#   I5  a record of another version, another layout, a flipped payload byte, a truncated file: refused (why=version,
#       why=shape, why=checksum), answer unchanged, the next run writes a valid one; mutant NOSUM serves a damaged one
#   H   a new commit that changes no file keeps both records served, and the answer identical (git history is NOT an
#       input of either computation: amp='s co-change half is computed outside them, live)
#   K   RIPWIRE_NO_VERBFS=1 prints no qmetrics line and writes no record
#   D   determinism: two served calls are byte-identical (stdout and stderr)
#
# Usage:  bash test/qmetricscheck.sh [BIN]   |   RIPWIRE_BIN=build/ripwire bash test/qmetricscheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "qmetricscheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'chmod -R u+rwx "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
FIX="$TMP/fix"; mkdir -p "$FIX/src" "$FIX/tests" "$TMP/home" "$TMP/t"
export HOME="$TMP/home"
export TMPDIR="$TMP/t"
unset RIPWIRE_NO_VERBFS RIPWIRE_STATS RIPWIRE_NO_WARMSNAP
for v in $( env | grep -oE '^RIPWIRE_FAULT_[A-Z_]+' ); do unset "$v"; done

# ── the fixture: a C++ class with a const method (pure=), a composed field (lcom4=), and a test that reaches some methods
cat >"$FIX/src/widget.hpp" <<'E'
#pragma once
class Pool
{
public:
    int take();
    int give();
};
class Widget
{
public:
    int size() const { return helperCount(); }
    int arrange() { return m_pool.take() + layout(); }
    int layout() { return m_pool.give(); }
    int unrelated() { return 7; }
    int lonely() { return 9; }
private:
    Pool m_pool;
};
int helperCount();
E
cat >"$FIX/src/widget.cpp" <<'E'
#include "widget.hpp"
int Pool::take() { return 1; }
int Pool::give() { return 2; }
int helperCount() { return 3; }
E
cat >"$FIX/src/zz_helper.cpp" <<'E'
#include "widget.hpp"
int zzProbe() { Widget w; return w.lonely(); }
E
cat >"$FIX/tests/widget_test.cpp" <<'E'
#include "../src/widget.hpp"
void test_arrange() { Widget w; w.arrange(); }
E
cat >"$FIX/src/util.py" <<'E'
def helper():
    return 1


def test_probe():
    return helper()
E
gitq(){ git -C "$FIX" -c user.email=gate@example.invalid -c user.name=gate -c commit.gpgsign=false "$@" >/dev/null 2>&1; }
gitq init -q && gitq add -A && gitq commit -qm init

TASK='how does the widget arrange its pool and size'

# ── runners ───────────────────────────────────────────────────────────────────────────────────────────────────────
# run TAG MODE ARGS... : MODE warm = the served path (--cache=C); novfs = RIPWIRE_NO_VERBFS=1 (its own cache: the variable
# is keyed into the snapshot's options); nocache = --no-cache. stdout/stderr/rc into $TMP/TAG.{out,err,rc}.
run(){
    local tag="$1" mode="$2"; shift 2
    case "$mode" in
        warm)    ( cd "$FIX" && "$BIN" "$FIX" --cache="$TMP/c.bin" "$@" </dev/null >"$TMP/$tag.out" 2>"$TMP/$tag.err" ) ;;
        novfs)   ( cd "$FIX" && RIPWIRE_NO_VERBFS=1 "$BIN" "$FIX" --cache="$TMP/n.bin" "$@" </dev/null >"$TMP/$tag.out" 2>"$TMP/$tag.err" ) ;;
        nocache) ( cd "$FIX" && "$BIN" "$FIX" --no-cache "$@" </dev/null >"$TMP/$tag.out" 2>"$TMP/$tag.err" ) ;;
    esac
    echo $? >"$TMP/$tag.rc"
}
statrun(){ local tag="$1"; shift; RIPWIRE_STATS=1 run "$tag" warm "$@"; }
# field TAG PART KEY : the value of KEY= on the FIRST `[verbfs] PART` stats line of TAG (the run's own use of the part)
field(){ grep "^\[verbfs\] $2 " "$TMP/$1.err" | head -1 | grep -oE "(^| )$3=[^ ]+" | head -1 | cut -d= -f2; }
line(){ grep "^\[verbfs\] $2 " "$TMP/$1.err" | head -1; }
same(){ cmp -s "$TMP/$1.out" "$TMP/$2.out" && cmp -s "$TMP/$1.rc" "$TMP/$2.rc"; }
# ident LABEL ARGS... : the served answer equals both references; returns 0 when it does
ident(){
    local label="$1"; shift
    run "id.w" warm "$@"; run "id.n" novfs "$@"; run "id.c" nocache "$@"
    if [ "$( cat "$TMP/id.c.rc" )" != 0 ]; then no "$label: the --no-cache reference exited $( cat "$TMP/id.c.rc" )"; return 1; fi
    if same id.w id.c && same id.n id.c; then return 0; fi
    no "$label: served / no-verbfs / no-cache differ: $( diff "$TMP/id.w.out" "$TMP/id.c.out" | head -4 | tr '\n' ' ' )"
    return 1
}
recordOf(){ find "$TMP/t/ripwire" -name "ripwire-verbfs-*-$1-*.bin" 2>/dev/null | head -1; }
# the answers an invalidation arm compares: the quality lens (tested=, pure=) and the metrics map (tested=, lcom4=, cbo=)
identAll(){ ident "$1 --for" --for="$TASK" && ident "$1 --metrics" --metrics; }
# mut LABEL FAULT : a binary blinded by FAULT, served from the record of the state before the edit, must differ from --no-cache
MUT=0
# mutrun FAULT TAG ARGS... : a served run under one fault switch (exported for that run only), through run's own rc file
mutrun(){ local fault="$1"; shift; export "$fault=1"; run "$1" warm "${@:2}"; unset "$fault"; }
mut(){
    [ "$MUT" = 1 ] || return 0
    local label="$1" fault="$2" diffs=0
    run mu.c nocache --for="$TASK"; mutrun "$fault" mu.w --for="$TASK"
    same mu.w mu.c || diffs=1
    run mu.c nocache --metrics; mutrun "$fault" mu.w --metrics
    same mu.w mu.c || diffs=1
    if [ "$diffs" = 1 ]; then ok "MUT $label: $fault turns the identity red"; else no "MUT $label: the $fault mutant matched the reference: the arm cannot see a stale record"; fi
}
mcp(){   # OUT ROOTDIR VERB TASK [novfs] : the text of one MCP tools/call answer
    python3 - "$BIN" "$2" "$3" "$4" "${5:-}" >"$1" <<'PY'
import json, os, subprocess, sys
binp, root, verb, task, novfs = sys.argv[1:6]
env = dict(os.environ)
env.pop("RIPWIRE_STATS", None)
if novfs: env["RIPWIRE_NO_VERBFS"] = "1"
req = [{"jsonrpc": "2.0", "id": 0, "method": "initialize"},
       {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": verb, "arguments": {"task": task}}}]
p = subprocess.run([binp, root, "--mcp"], input="".join(json.dumps(r) + "\n" for r in req).encode(), capture_output=True, env=env, cwd=root)
for ln in p.stdout.decode("utf8", "replace").splitlines():
    try: r = json.loads(ln)
    except ValueError: continue
    if r.get("id") == 1:
        sys.stdout.write("".join(c.get("text", "") for c in r.get("result", {}).get("content", [])))
PY
}

# ── S1: the counter ───────────────────────────────────────────────────────────────────────────────────────────────
statrun s0 --for="$TASK"
statrun s1 --for="$TASK"
QREC="$( recordOf qmetrics )"; IREC="$( recordOf impure )"
if [ "$( field s0 qmetrics wrote )" = 1 ] && [ "$( field s0 impure wrote )" = 1 ] && [ -n "$QREC" ] && [ -n "$IREC" ]; then
    ok "S1a the first cached --for builds both records ($( line s0 qmetrics ) | $( line s0 impure ))"
else no "S1a no records after the first cached run: '$( line s0 qmetrics )' '$( line s0 impure )' (the base has no [verbfs] qmetrics line at all)"; fi
if [ "$( field s1 qmetrics served )" = 1 ] && [ "$( field s1 qmetrics why )" = ok ] && [ "$( field s1 impure served )" = 1 ] && [ "$( field s1 impure why )" = ok ]; then
    ok "S1b the second serves both ($( line s1 qmetrics ) | $( line s1 impure ))"
else no "S1b counter: '$( line s1 qmetrics )' '$( line s1 impure )'"; fi
if [ "$( field s1 qmetrics wrote )" = 0 ] && [ "$( field s1 impure wrote )" = 0 ]; then ok "S1c a served run rewrites neither record"; else no "S1c a served run wrote: '$( line s1 qmetrics )'"; fi
for v in FAULT_VERBFS_QMETRICS_NOGRAPH; do
    ( cd "$FIX" && env "RIPWIRE_$v=1" RIPWIRE_STATS=1 "$BIN" "$FIX" --cache="$TMP/c.bin" --for="$TASK" </dev/null >/dev/null 2>"$TMP/mprobe.err" )
    grep -q '^\[verbfs\] qmetrics .*fault=nograph' "$TMP/mprobe.err" && MUT=1
done
[ "$MUT" = 1 ] || printf '  INFO  MUT this binary compiles fault switches out (NDEBUG); the mutation arms run on the plain-flavour leg\n'
run warmfix warm --for="$TASK"   # the mutant probe served (or rewrote) under its own snapshot key; nothing below relies on it

# ── S2: identity on an unchanged index, every surface that prints QMetrics or the purity mask ───────────────────────
s2=0; s2n=0
for args in "--for=$TASK" "--metrics" "--quality-panel" "--exemplar=$TASK"; do
    s2n=$(( s2n + 1 )); ident "S2 $args" "$args" && s2=$(( s2 + 1 ))
done
rm -f "$TMP/h.w.html" "$TMP/h.n.html" "$TMP/h.c.html"
run hw warm --html="$TMP/h.w.html"; run hn novfs --html="$TMP/h.n.html"; run hc nocache --html="$TMP/h.c.html"
s2n=$(( s2n + 1 ))
if [ -s "$TMP/h.c.html" ] && cmp -s "$TMP/h.w.html" "$TMP/h.c.html" && cmp -s "$TMP/h.n.html" "$TMP/h.c.html" && same hw hc; then s2=$(( s2 + 1 )); else no "S2 --html: the written pages differ"; fi
printf '\n// a working-tree edit for the delta to report\nint deltaProbe( int a ) { if( a > 1 ) { if( a > 2 ) { return a; } } return 0; }\n' >>"$FIX/src/widget.cpp"
s2n=$(( s2n + 1 )); ident "S2 --quality-delta" --quality-delta && s2=$(( s2 + 1 ))
gitq checkout -- src/widget.cpp
run warm2 warm --for="$TASK"
mcp "$TMP/m.w.out" "$FIX" for "$TASK"; mcp "$TMP/m.n.out" "$FIX" for "$TASK" novfs
mcp "$TMP/e.w.out" "$FIX" exemplar "$TASK"; mcp "$TMP/e.n.out" "$FIX" exemplar "$TASK" novfs
s2n=$(( s2n + 1 ))
if [ -s "$TMP/m.w.out" ] && [ -s "$TMP/e.w.out" ] && cmp -s "$TMP/m.w.out" "$TMP/m.n.out" && cmp -s "$TMP/e.w.out" "$TMP/e.n.out"; then s2=$(( s2 + 1 ))
else no "S2 MCP for/exemplar: the answer with a record differs from RIPWIRE_NO_VERBFS=1 (or is empty)"; fi
if [ "$s2" = "$s2n" ]; then ok "S2 all ${s2n} surfaces identical on an unchanged index (--for --metrics --quality-panel --exemplar --html --quality-delta MCP)"
else no "S2 only ${s2} of ${s2n} surfaces identical"; fi
statrun s2s --metrics
if [ "$( field s2s qmetrics served )" = 1 ]; then ok "S2b --metrics is served from the record too"; else no "S2b --metrics: '$( line s2s qmetrics )'"; fi

# ── I1: graph only — a call added inside a test function ──────────────────────────────────────────────────────────
run pre1 warm --for="$TASK"
cat >"$FIX/tests/widget_test.cpp" <<'E'
#include "../src/widget.hpp"
void test_arrange() { Widget w; w.arrange(); w.unrelated(); }
E
mut "I1 a call added in a test" RIPWIRE_FAULT_VERBFS_QMETRICS_NOGRAPH
statrun i1s --for="$TASK"
if identAll "I1" && [ "$( field i1s qmetrics served )" = 0 ] && [ "$( field i1s qmetrics why )" = graph ]; then
    ok "I1 a call added inside a test function: recomputed (why=graph), identical"
else no "I1: '$( line i1s qmetrics )'"; fi

# ── I2: references only — a side-effecting call added to the helper a const method calls ───────────────────────────
run pre2 warm --for="$TASK"
cat >"$FIX/src/widget.cpp" <<'E'
#include "widget.hpp"
#include <cstdlib>
int Pool::take() { return 1; }
int Pool::give() { return 2; }
int helperCount() { std::exit( 3 ); }
E
mut "I2 a side effect added under a const method" RIPWIRE_FAULT_VERBFS_QMETRICS_NOREFS
statrun i2s --for="$TASK"
if identAll "I2" && [ "$( field i2s impure served )" = 0 ] && [ "$( field i2s impure why )" = refs ] && ! grep -q 'Widget::size[^|]*pure=1' "$TMP/id.w.out"; then
    ok "I2 a side effect under a const method: impure recomputed (why=refs), pure= gone, identical"
else no "I2: '$( line i2s impure )'"; fi

# ── I3: a path text only — a file renamed into the test partition ───────────────────────────────────────────────────
run pre3 warm --for="$TASK"
gitq mv src/zz_helper.cpp src/zz_helper_test.cpp
mut "I3 a file renamed into the test partition" RIPWIRE_FAULT_VERBFS_QMETRICS_NOFILES
statrun i3s --for="$TASK"
if identAll "I3" && [ "$( field i3s qmetrics served )" = 0 ] && [ "$( field i3s qmetrics why )" = files ]; then
    ok "I3 a file renamed into the test partition: recomputed (why=files), identical"
else no "I3: '$( line i3s qmetrics )'"; fi

# ── I4: a changed flag — --exclude=tests ────────────────────────────────────────────────────────────────────────────
run pre4 warm --for="$TASK"
if [ "$MUT" = 1 ]; then
    run mu.c nocache --metrics --exclude=tests
    mutrun RIPWIRE_FAULT_VERBFS_QMETRICS_ANYDIGEST mu.w --metrics --exclude=tests
    if ! same mu.w mu.c; then ok "MUT I4 a changed flag: RIPWIRE_FAULT_VERBFS_QMETRICS_ANYDIGEST turns the identity red"; else no "MUT I4: the any-digest mutant matched the reference"; fi
fi
statrun i4s --metrics --exclude=tests
if ident "I4 --metrics --exclude=tests" --metrics --exclude=tests && ident "I4 --for --exclude=tests" --for="$TASK" --exclude=tests && [ "$( field i4s qmetrics served )" = 0 ]; then
    ok "I4 a changed flag (--exclude=tests): recomputed (why=$( field i4s qmetrics why )), identical"
else no "I4: '$( line i4s qmetrics )'"; fi
statrun i4b --metrics
if identAll "I4b back without the flag" && [ "$( field i4b qmetrics served )" = 0 ]; then ok "I4b and back without it: recomputed again (why=$( field i4b qmetrics why )), identical"; else no "I4b: '$( line i4b qmetrics )'"; fi

# ── I6: a symbol's fields only — a function leaves the in-file test convention ──────────────────────────────────────
run pre6 warm --metrics
sed 's/def test_probe/def check_probe/' "$FIX/src/util.py" >"$TMP/util.py" && cat "$TMP/util.py" >"$FIX/src/util.py"
mut "I6 a symbol leaves the test convention" RIPWIRE_FAULT_VERBFS_QMETRICS_NOSYMS
statrun i6s --metrics
if identAll "I6" && [ "$( field i6s qmetrics served )" = 0 ] && [ "$( field i6s qmetrics why )" = symbols ]; then
    ok "I6 a function leaves the in-file test convention: recomputed (why=symbols), identical"
else no "I6: '$( line i6s qmetrics )'"; fi

# ── H: a new commit that changes no file ──────────────────────────────────────────────────────────────────────────
gitq add -A && gitq commit -qm 'the edits so far'
run hpre warm --for="$TASK"
gitq commit --allow-empty -qm 'an empty commit'
statrun hs --for="$TASK"
if [ "$( field hs qmetrics served )" = 1 ] && [ "$( field hs impure served )" = 1 ] && ident "H after a commit" --for="$TASK"; then
    ok "H a new commit changes neither input: both served, identical"
else no "H: '$( line hs qmetrics )' '$( line hs impure )'"; fi

# ── I5: an old, foreign or damaged record ───────────────────────────────────────────────────────────────────────────
QREC="$( recordOf qmetrics )"
damage(){   # FILE MODE : version | layout | payload | truncate | tested (rewrite every tested byte; the checksum then fails)
    python3 - "$1" "$2" <<'PY'
import struct, sys
p, mode = sys.argv[1:3]
b = bytearray(open(p, 'rb').read())
if mode == 'version':  b[8] ^= 0x7f                       # u32 after the 8-byte magic
elif mode == 'layout': b[16] ^= 0x01                      # the layout key (u64 at 16): another build's record
elif mode == 'payload': b[len(b) - 3] ^= 0x01             # one byte near the end of the payload
elif mode == 'truncate': b = b[:len(b) - 5]
elif mode == 'tested':
    # payload (after the 40-byte header): digest components (u64 count + u64 each), symbol count u64, tested (u64 n + n bytes)
    at = 40
    (k,) = struct.unpack_from('<Q', b, at); at += 8 + 8 * k
    at += 8
    (n,) = struct.unpack_from('<Q', b, at); at += 8
    for i in range(n): b[at + i] ^= 0x01
open(p, 'wb').write(bytes(b))
PY
}
if [ -n "$QREC" ]; then
    run i5pre warm --for="$TASK"; cp "$QREC" "$TMP/qrec.good"
    i5=""
    for mode in version layout payload truncate; do
        cp "$TMP/qrec.good" "$QREC"; damage "$QREC" "$mode"
        statrun i5$mode --for="$TASK"
        w="$( field i5$mode qmetrics why )"
        cp "$TMP/qrec.good" "$QREC"; damage "$QREC" "$mode"
        ident "I5 $mode" --for="$TASK" && i5="$i5 $mode=$w" || i5="$i5 $mode=DIFF"
    done
    statrun i5next --for="$TASK"
    if [ "$i5" = " version=version layout=shape payload=checksum truncate=checksum" ] && [ "$( field i5next qmetrics served )" = 1 ]; then
        ok "I5 another version, another build's layout, a flipped payload byte and a truncated file are refused (${i5# }), the answer is unchanged, and the next run is served again"
    else no "I5 refusals:${i5} next='$( line i5next qmetrics )'"; fi
    if [ "$MUT" = 1 ]; then
        cp "$TMP/qrec.good" "$QREC"; damage "$QREC" tested
        run mu.c nocache --metrics
        mutrun RIPWIRE_FAULT_VERBFS_QMETRICS_NOSUM mu.w --metrics
        if ! same mu.w mu.c; then ok "MUT I5 a damaged record: RIPWIRE_FAULT_VERBFS_QMETRICS_NOSUM (no checksum) turns the identity red"; else no "MUT I5: the no-checksum mutant matched the reference"; fi
        cp "$TMP/qrec.good" "$QREC"
    fi
else no "I5 no qmetrics record to damage"; fi

# ── K: the kill switch ────────────────────────────────────────────────────────────────────────────────────────────
rm -f "$( recordOf qmetrics )" "$( recordOf impure )"
( cd "$FIX" && RIPWIRE_NO_VERBFS=1 RIPWIRE_STATS=1 "$BIN" "$FIX" --cache="$TMP/c.bin" --for="$TASK" </dev/null >/dev/null 2>"$TMP/k.err" )
if ! grep -q '^\[verbfs\] \(qmetrics\|impure\) ' "$TMP/k.err" && [ -z "$( recordOf qmetrics )" ] && [ -z "$( recordOf impure )" ]; then ok "K RIPWIRE_NO_VERBFS=1 reads and writes no qmetrics or impure record"
else no "K the kill switch: $( grep '^\[verbfs\]' "$TMP/k.err" | head -2 | tr '\n' ' ' )"; fi

# ── D: determinism ────────────────────────────────────────────────────────────────────────────────────────────────
run d0 warm --for="$TASK"; run d1 warm --for="$TASK"; run d2 warm --for="$TASK"
if same d1 d2 && cmp -s "$TMP/d1.err" "$TMP/d2.err" && same d0 d1; then ok "D a building and two served calls are byte-identical"; else no "D the served answer is not deterministic"; fi

[ "$fail" = 0 ] && echo "qmetricscheck: PASS" || echo "qmetricscheck: FAIL"
exit "$fail"
