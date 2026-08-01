#!/usr/bin/env bash
# tracecheck.sh — gate for --from-trace=FILE ('-'=stdin) (B11/L2): the
# trace-to-locus verb. Agents hand-translate stack traces / sanitizer reports / compiler errors into
# queries many times per session; this maps the frames of such a text artifact directly onto the indexed
# symbols, ranks the suspects innermost-first, and emits a --for-style bundle (top suspects' signatures +
# the innermost in-corpus symbol's FULL body).
#
# Covers, per the plan's gate spec — one fixture trace PER FORMAT over a small fixture tree:
#   (py)      Python traceback  (File "x.py", line N, in fn)   -> innermost is the LAST frame
#   (asan)    AddressSanitizer  (#k ... in fn path:line:col)   -> innermost is frame #0 (first)
#   (clang)   compiler diagnostic (path:line:col: error/note)  -> innermost is the first (primary) frame
#   (node)    node/js stack     (at fn (path:line:col))        -> innermost is the topmost frame
#   (generic) bare path:line fallback                          -> innermost is the first listed frame
# For each: the correct innermost IN-CORPUS symbol is rank 1; out-of-corpus frames are skipped-but-COUNTED
# (never ranked); the bundle is deterministic (byte-identical x3) and xmllint-clean; garbage input refuses
# loudly (nonzero exit, stderr message, NEVER an empty map); and '-' reads the trace from stdin.
#
# CA4 §B3 adds the budget half: --from-trace is the third member of the family cli.h enumerates by name
# ("--for / --pack-task / --from-trace"), and it was the one that stated a budget and never labelled an
# overrun. Arms (T1)-(T5) below pin the ledger, all three ceiling rungs, and the root attrs.
#
# TWO GATE DEFECTS FIXED HERE (CA4 §B15's lens — "what would make this gate pass without the property
# holding?"), both of which this file had:
#   1. it never exited non-zero. It printed "FAILURES ABOVE" and returned 0, and regression.sh's verdict is
#      `if bash test/$g.sh; then ok`, so tracecheck could NOT fail the suite. SIX real FAILs were sitting in
#      it, green, on base_w3 — five `grep -q '<bodies>'` assertions that stopped matching when <bodies>
#      gained shown=/total=/capped= (§B8.3's truncation-vocabulary sweep) plus the (A2a) body-identity arm
#      built on the same string. Fixed at the assertions AND with the exit below.
#   2. it ignored $1 — `test/tracecheck.sh asan/ripwire` silently tested build/ripwire. Same seam W3FIX
#      fixed in tokenbudgetcheck; both binding forms are live now.
#
# Operates on a private temp tree (never touches the real repo). No git needed.
# Usage:  test/tracecheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/tracecheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # make BIN absolute BEFORE we cd away
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/app" "$WORK/src" "$WORK/web" "$WORK/lib" "$WORK/traces"

# ── the small fixture tree: one file per language, functions at KNOWN line spans ────────────────────────
# app/main.py — python call chain: outer(2) -> middle(5) -> inner(8, raises)
cat > "$WORK/app/main.py" <<'EOF'
def outer():
    return middle()

def middle():
    return inner()

def inner():
    raise ValueError("boom")
EOF

# src/engine.cpp — C++ chain for the ASan fixture: main(13) -> dispatch(9) -> doWork(5, crash)
cat > "$WORK/src/engine.cpp" <<'EOF'
#include <cstdio>

void doWork() {
    int* p = nullptr;
    *p = 1;
}

void dispatch() {
    doWork();
}

int main() {
    dispatch();
    return 0;
}
EOF

# src/parser.cpp — C++ for the clang-error fixture: badcall() body has the error at line 5
cat > "$WORK/src/parser.cpp" <<'EOF'
struct Bar {};

int badcall() {
    Bar b;
    return b.foo();
}
EOF

# web/worker.js — JS chain for the node fixture: outer(8) -> middle(5) -> inner(2, throws)
cat > "$WORK/web/worker.js" <<'EOF'
function inner() {
  throw new Error("boom");
}
function middle() {
  inner();
}
function outer() {
  middle();
}
outer();
EOF

# lib/util.cpp — C++ for the generic fixture: alpha()@1..3, beta()@4..6
cat > "$WORK/lib/util.cpp" <<'EOF'
int alpha() {
    return 1;
}
int beta() {
    return 2;
}
EOF

# ── the fixture traces (each names ONE out-of-corpus frame to exercise skipped-but-counted) ─────────────
cat > "$WORK/traces/py.txt" <<'EOF'
Traceback (most recent call last):
  File "/ext/site-packages/runner.py", line 3, in <module>
    app.outer()
  File "app/main.py", line 2, in outer
    return middle()
  File "app/main.py", line 5, in middle
    return inner()
  File "app/main.py", line 8, in inner
    raise ValueError("boom")
ValueError: boom
EOF

cat > "$WORK/traces/asan.txt" <<'EOF'
==12345==ERROR: AddressSanitizer: SEGV on unknown address 0x000000000000
    #0 0x108a in doWork src/engine.cpp:5:8
    #1 0x109b in dispatch src/engine.cpp:9:5
    #2 0x10ac in main src/engine.cpp:13:5
    #3 0x10bd in __libc_start_main /usr/lib/libc.so.6:0
EOF

cat > "$WORK/traces/clang.txt" <<'EOF'
src/parser.cpp:5:14: error: no member named 'foo' in 'Bar'
    return b.foo();
             ^
src/parser.cpp:3:5: note: while compiling function 'badcall'
/opt/toolchain/include/type_traits:120:1: note: in expansion here
EOF

cat > "$WORK/traces/node.txt" <<'EOF'
Error: boom
    at inner (web/worker.js:2:9)
    at middle (web/worker.js:5:3)
    at outer (web/worker.js:8:3)
    at Object.<anonymous> (/ext/node_modules/run.js:1:1)
    at node:internal/main/run_main_module:23:47
EOF

cat > "$WORK/traces/generic.txt" <<'EOF'
lib/util.cpp:5
lib/util.cpp:2
/ext/vendor/thing.cpp:9
EOF

cat > "$WORK/traces/garbage.txt" <<'EOF'
this is not a stack trace at all
just some prose with no frames whatsoever
EOF

# F7: a hostile/garbled line number that overflows uint32_t (2^32 + 1 = 4294967297, which the
# unchecked `v*10+d` bug used to wrap mod 2^32 down to line 1 = alpha()'s def line) must degrade to
# <skipped>, never confidently resolve to alpha (or any other real symbol). The second, well-formed frame
# (line 5, inside beta's 4..6 span) is the sole suspect and must rank 1.
cat > "$WORK/traces/overflow.txt" <<'EOF'
lib/util.cpp:4294967297
lib/util.cpp:5
EOF

echo "tracecheck: BIN=$BIN  (temp fixture tree)"

tr_run(){ ( cd "$WORK" && "$BIN" . --from-trace="traces/$1" --no-cache 2>/dev/null ); }

# assert: format label, rank-1 innermost in-corpus symbol, and the skipped-frame count.
assert_format(){
    local name="$1" fmt="$2" rank1="$3" skipped="$4"
    local out; out="$( tr_run "$name.txt" )"
    printf '%s' "$out" | grep -q "format=\"$fmt\"" \
        && ok "($name) format detected = $fmt" || { no "($name) wrong/absent format label"; printf '%s\n' "$out"; }
    # rank 1 frame names the expected innermost in-corpus symbol
    printf '%s' "$out" | grep -oE '<frame rank="1"[^>]*>' | grep -q "n=\"$rank1\"" \
        && ok "($name) rank 1 = innermost in-corpus symbol '$rank1'" \
        || { no "($name) rank 1 is not '$rank1'"; printf '%s' "$out" | grep -oE '<frame rank="1"[^>]*>'; printf '%s\n' "$out"; }
    printf '%s' "$out" | grep -q "skipped=\"$skipped\"" \
        && ok "($name) out-of-corpus frames skipped-but-counted = $skipped" \
        || { no "($name) skipped count != $skipped"; printf '%s\n' "$out"; }
    # the innermost symbol's FULL body is emitted (a <bodies> block with a <b> element)
    # `<bodies` open-tag prefix, NOT `<bodies>`: the element carries shown=/total=/capped= since §B8.3 swept
    # the truncation vocabulary, so the closed form matched nothing and this arm was dark on every binary.
    printf '%s' "$out" | grep -q '<bodies[ >]' \
        && ok "($name) innermost symbol full body present (<bodies>)" \
        || { no "($name) no <bodies> block for the innermost symbol"; printf '%s\n' "$out"; }
}

# ── one fixture per format ──────────────────────────────────────────────────────────────────────────────
assert_format py      python   inner    1
assert_format asan    asan     doWork   1
assert_format clang   compiler badcall  1
assert_format node    node     inner    2
assert_format generic generic  beta     1

# ── F7: overflowed line number degrades to skipped, never a wrapped-to-line-1 false positive ─────
OV_OUT="$( tr_run overflow.txt )"
printf '%s' "$OV_OUT" | grep -q 'skipped="1"' \
    && ok "(overflow) huge line number (2^32+1) degrades to skipped, never wraps mod 2^32" \
    || { no "(overflow) huge line number did not land in skipped=1"; printf '%s\n' "$OV_OUT"; }
printf '%s' "$OV_OUT" | grep -oE '<frame rank="1"[^>]*>' | grep -q 'n="beta"' \
    && ok "(overflow) rank 1 is the valid frame (beta), not the wrapped-to-line-1 alpha" \
    || { no "(overflow) rank 1 is not beta — possible line-wrap regression"; printf '%s' "$OV_OUT" | grep -oE '<frame rank="1"[^>]*>'; printf '%s\n' "$OV_OUT"; }
printf '%s' "$OV_OUT" | grep -q '"alpha"' \
    && { no "(overflow) alpha appears anywhere in the bundle — the overflowed line wrapped and matched it"; printf '%s\n' "$OV_OUT"; } \
    || ok "(overflow) alpha (the line-1 def the old wraparound bug would hit) never appears as a suspect"

# ── determinism x3 (the node fixture — mixes in-corpus + two out-of-corpus frames) ──────────────────────
D1="$( tr_run node.txt )"; D2="$( tr_run node.txt )"; D3="$( tr_run node.txt )"
{ [ "$D1" = "$D2" ] && [ "$D2" = "$D3" ]; } \
    && ok "deterministic (byte-identical x3)" || no "non-deterministic --from-trace output"

# ── xml well-formed (all five bundles) ─────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    xmlfail=0
    for t in py asan clang node generic overflow; do
        tr_run "$t.txt" | xmllint --noout - 2>/dev/null || { xmlfail=1; echo "     malformed: $t"; }
    done
    [ "$xmlfail" = 0 ] && ok "xml well-formed (all six bundles)" || no "xml malformed"
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

# ── '-' reads the trace from stdin (identical to the file form apart from the source LABEL) ─────────────
# the only legitimate difference is the trace source name (src="traces/py.txt" vs src="<stdin>", echoed in
# both the header comment and the <trace src=...> attribute) — normalise those two spots, then demand equality.
# §B3: the source label now appears in THREE places, not two — ctxRootOpen's verbatim task= root attribute
# joined the header echo and <trace src=…>. Normalising only the old two is what made this arm red on the
# §B3 binary; the arm is doing its job (it caught a real new occurrence of the label it is written to ignore).
norm(){ printf '%s' "$1" | sed -E 's/src="[^"]*"/src="X"/; s/trace-to-locus for "[^"]*"/trace-to-locus for "X"/; s/<ctx task="[^"]*"/<ctx task="X"/'; }
STDIN_OUT="$( cd "$WORK" && "$BIN" . --from-trace=- --no-cache < "$WORK/traces/py.txt" 2>/dev/null )"
FILE_OUT="$( tr_run py.txt )"
[ "$( norm "$STDIN_OUT" )" = "$( norm "$FILE_OUT" )" ] \
    && ok "'-' reads the trace from stdin (identical bundle apart from the source label)" \
    || { no "stdin form differs from the file form beyond the source label"; diff <(norm "$STDIN_OUT") <(norm "$FILE_OUT") | head; }

# ── garbage input refuses loudly (nonzero exit, stderr message, NO map on stdout) ──────────────────────
G_OUT="$( cd "$WORK" && "$BIN" . --from-trace="traces/garbage.txt" --no-cache 2>/dev/null )"
G_ERR="$( cd "$WORK" && "$BIN" . --from-trace="traces/garbage.txt" --no-cache 2>&1 >/dev/null )"
G_RC="$( cd "$WORK" && "$BIN" . --from-trace="traces/garbage.txt" --no-cache >/dev/null 2>&1; echo $? )"
{ [ "$G_RC" -ne 0 ] && [ -z "$G_OUT" ] && printf '%s' "$G_ERR" | grep -qi 'no .*frame\|could not parse\|unparse'; } \
    && ok "garbage input refuses loudly (exit $G_RC, stderr message, empty stdout)" \
    || { no "garbage input should refuse loudly, never an empty map"; printf 'rc=%s out=[%s] err=%s\n' "$G_RC" "$G_OUT" "$G_ERR"; }

# ── missing trace file refuses loudly too ──────────────────────────────────────────────────────────────
M_RC="$( cd "$WORK" && "$BIN" . --from-trace="traces/does_not_exist.txt" --no-cache >/dev/null 2>&1; echo $? )"
[ "$M_RC" -ne 0 ] && ok "missing trace file refuses (exit $M_RC)" || no "missing trace file should refuse"

# ── composes with --token-budget (still a well-formed, non-empty bundle) ────────────────────────────────
TB_OUT="$( cd "$WORK" && "$BIN" . --from-trace="traces/py.txt" --token-budget=2000 --no-cache 2>/dev/null )"
printf '%s' "$TB_OUT" | grep -q '<trace ' \
    && { command -v xmllint >/dev/null 2>&1 && printf '%s' "$TB_OUT" | xmllint --noout - 2>/dev/null; } \
    && ok "composes with --token-budget (well-formed non-empty bundle)" \
    || { no "--token-budget composition broke the bundle"; printf '%s\n' "$TB_OUT"; }

# ── F6: a long frame PATH must never emit invalid XML. renderTraceBlock used to snprintf each <frame>/
#    <skipped> row into a fixed char row[640]; a path long enough to overflow it got silently truncated
#    mid-attribute, dropping the closing `"/>` (a G4 break — xmllint exit 1). Sanitizer output routinely
#    carries long, deeply-nested build paths, so this is not a corner case. Build a ~720-char relative
#    path (14 nested 50-char directory segments) well past the old 640-byte buffer, put a real function
#    at a known line inside it, and confirm the resulting <frame p="..."/> row is well-formed. ───────────
DEEP=""
for _ in $( seq 1 14 ); do DEEP="$DEEP/$( printf 'a%.0s' $( seq 1 50 ) )"; done
DEEP="${DEEP#/}"
mkdir -p "$WORK/$DEEP"
cat > "$WORK/$DEEP/deep.cpp" <<'EOF'
void longPathFn() {
    int x = 1;
}
EOF
DEEPPATH="$DEEP/deep.cpp"
printf '%d chars: path length under test\n' "${#DEEPPATH}"
cat > "$WORK/traces/longpath.txt" <<EOF
==1==ERROR: AddressSanitizer: SEGV on unknown address 0x000000000000
    #0 0x108a in longPathFn $DEEPPATH:1:6
    #1 0x109b in __libc_start_main /usr/lib/libc.so.6:0
EOF
LP_OUT="$( tr_run longpath.txt )"
printf '%s' "$LP_OUT" | grep -qF "$DEEPPATH" \
    && ok "F6: the long-path frame row carries the FULL untruncated path" \
    || { no "F6: the long-path frame row is missing or truncated the path"; printf '%s\n' "$LP_OUT"; }
printf '%s' "$LP_OUT" | grep -oE '<frame[^>]*/>' | grep -qE '"/>$' \
    && ok "F6: the <frame .../> row closes correctly (no mid-attribute truncation)" \
    || { no "F6: the <frame> row does not close with \"/> — truncated mid-attribute"; printf '%s\n' "$LP_OUT" | grep -oE '<frame[^>]*'; }
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$LP_OUT" | xmllint --noout - 2>/dev/null \
        && ok "F6: long-path trace bundle is xmllint-clean (G4)" \
        || { no "F6: long-path trace bundle is NOT well-formed XML (G4 break)"; printf '%s\n' "$LP_OUT"; }
else
    printf '  SKIP  F6 xmllint check (no xmllint)\n'
fi

# ════════════════════════════════════════════════════════════════════════════════════════════════════════
# §A2  — resolution HONESTY. Three defects, one fixture tree:
#   (a) the verb discarded the symbol NAME each frame carries and rebound by LINE against the current tree,
#       so a trace from a binary older than the checkout silently reported whatever squats on that line today
#       (and dumped ITS body). Name binds first now, with resolved_by= and a disclosed line_encloses= on
#       disagreement; ASan frame parsing splits at the LAST space so a DEMANGLED C++ name survives intact.
#   (b) in_corpus= counted file matches, so a frame whose line landed between symbol bodies was counted and
#       then appeared in NEITHER <frame> nor <skipped>. The partition closes now:
#       in_corpus = suspects + merged + unresolved, with an <unresolved> row per third-bucket frame.
#   (c) p= (the trace's line) vs <sigs> l= (the definition line) had nothing saying which was which.
# Every arm below FAILS against a pre-§A2 binary and passes here.
# ────────────────────────────────────────────────────────────────────────────────────────────────────────
mkdir -p "$WORK/a2/src" "$WORK/a2/traces"

# a2/src/mod.cpp — alpha()@1..4, a GAP at 5, beta()@6..9, delta()@11..14
cat > "$WORK/a2/src/mod.cpp" <<'EOF'
void alpha()
{
    int a = 1;
}

void beta()
{
    int b = 2;
}

void delta()
{
    int d = 4;
}
EOF

# two more files so a name can be AMBIGUOUS (gamma twice, neither in mod.cpp) and so a name can be ambiguous
# but narrowable by the frame's OWN file (delta twice, one of them in mod.cpp)
cat > "$WORK/a2/src/dup1.cpp" <<'EOF'
void gamma1() { }
void gamma() { }
void delta() { }
EOF
cat > "$WORK/a2/src/dup2.cpp" <<'EOF'
void gamma2() { }
void gamma() { }
EOF

a2_run(){ ( cd "$WORK/a2" && "$BIN" . --from-trace="traces/$1" --no-cache 2>/dev/null ); }
# the value of attribute $1 on the FIRST element matching $2 in the bundle $3 ('' when absent)
a2_attr(){ printf '%s' "$3" | grep -oE "<$2[^>]*>" | head -1 | grep -oE " $1=\"[^\"]*\"" | head -1 | sed -E "s/ $1=\"([^\"]*)\"/\1/"; }

# ── (a) stale line: the frame NAMES alpha but its line now sits inside beta ──────────────────────────────
cat > "$WORK/a2/traces/stale.txt" <<'EOF'
    #0 0x1 in alpha src/mod.cpp:8:1
    #1 0x2 in __libc_start_main /usr/lib/libc.so.6:0
EOF
STALE="$( a2_run stale.txt )"
[ "$( a2_attr n frame "$STALE" )" = "alpha" ] \
    && ok "(A2a) a stale-line frame resolves to the symbol it NAMES (alpha), not the one squatting on the line" \
    || { no "(A2a) rank 1 is not alpha — the frame's own name was discarded"; printf '%s' "$STALE" | grep -oE '<frame[^>]*>'; }
[ "$( a2_attr resolved_by frame "$STALE" )" = "name" ] \
    && ok "(A2a) resolved_by=\"name\" discloses HOW the frame bound" \
    || { no "(A2a) resolved_by=\"name\" missing on a name-resolved frame"; printf '%s' "$STALE" | grep -oE '<frame[^>]*>'; }
[ "$( a2_attr line_encloses frame "$STALE" )" = "beta" ] \
    && ok "(A2a) the name/line DISAGREEMENT is disclosed as line_encloses=\"beta\" (the trace predates the checkout)" \
    || { no "(A2a) line_encloses= absent/wrong — the disagreement was resolved silently"; printf '%s' "$STALE" | grep -oE '<frame[^>]*>'; }
printf '%s' "$STALE" | grep -q '<bodies[ >].*n="alpha"' \
    && ok "(A2a) the FULL body emitted is the RESOLVED symbol's (alpha), not the line squatter's" \
    || { no "(A2a) the emitted body is not alpha's"; printf '%s' "$STALE" | grep -oE '<b [^>]*>' | head -3; }
# (c) p= is the FRAME's own locator (the trace's verbatim path:line); the DEFINITION line travels in <sigs> l=
[ "$( a2_attr p frame "$STALE" )" = "src/mod.cpp:8" ] \
    && ok "(A2c) p= on the frame is the TRACE's own path:line, verbatim" \
    || { no "(A2c) p= is not the trace's own locator"; printf '%s' "$STALE" | grep -oE '<frame[^>]*>'; }
printf '%s' "$STALE" | grep -qE '<d l="1"[^>]*n="alpha"' \
    && ok "(A2c) the DEFINITION line lives in <sigs> l= (alpha at l=1), distinct from the frame's p=" \
    || { no "(A2c) <sigs> does not carry alpha's definition line"; printf '%s' "$STALE" | grep -oE '<d [^>]*>' | head -3; }
# the out-of-corpus frame still lands in <skipped>, unchanged by any of this
{ [ "$( a2_attr skipped trace "$STALE" )" = "1" ] && printf '%s' "$STALE" | grep -q '<skipped p="/usr/lib/libc.so.6"'; } \
    && ok "(A2) an out-of-corpus frame still lands in <skipped>, counted and listed (unchanged)" \
    || { no "(A2) the out-of-corpus frame is no longer skipped-but-counted"; printf '%s' "$STALE" | grep -oE '<trace[^>]*>|<skipped[^>]*>'; }

# ── (a) a DEMANGLED C++ frame name (spaces inside the parameter list) still yields the name ──────────────
cat > "$WORK/a2/traces/demangled.txt" <<'EOF'
    #0 0x1 in rw::alpha(int const&) src/mod.cpp:8:1
EOF
DEM="$( a2_run demangled.txt )"
{ [ "$( a2_attr n frame "$DEM" )" = "alpha" ] && [ "$( a2_attr resolved_by frame "$DEM" )" = "name" ]; } \
    && ok "(A2a) a demangled 'rw::alpha(int const&)' frame resolves by name (param list + namespace stripped)" \
    || { no "(A2a) the demangled frame name did not resolve — the ASan split cut it at the first space"; printf '%s' "$DEM" | grep -oE '<frame[^>]*>'; }

# ── (a) ambiguity is NOT a guess: two defs, neither in the frame's file → honest line fallback ───────────
cat > "$WORK/a2/traces/ambiguous.txt" <<'EOF'
    #0 0x1 in gamma src/mod.cpp:8:1
EOF
AMB="$( a2_run ambiguous.txt )"
{ [ "$( a2_attr resolved_by frame "$AMB" )" = "line" ] && [ "$( a2_attr n frame "$AMB" )" = "beta" ]; } \
    && ok "(A2a) an AMBIGUOUS name falls back to line-enclosure and stamps resolved_by=\"line\"" \
    || { no "(A2a) an ambiguous name was resolved anyway (a guess) or lost its resolved_by"; printf '%s' "$AMB" | grep -oE '<frame[^>]*>'; }
# ...but ambiguity the frame's OWN file narrows to one def IS resolvable by name
cat > "$WORK/a2/traces/narrowed.txt" <<'EOF'
    #0 0x1 in delta src/mod.cpp:8:1
EOF
NAR="$( a2_run narrowed.txt )"
{ [ "$( a2_attr n frame "$NAR" )" = "delta" ] && [ "$( a2_attr resolved_by frame "$NAR" )" = "name" ] \
  && [ "$( a2_attr line_encloses frame "$NAR" )" = "beta" ]; } \
    && ok "(A2a) a name ambiguous corpus-wide but UNIQUE in the frame's own file resolves by name" \
    || { no "(A2a) the frame's own file did not narrow the ambiguous name"; printf '%s' "$NAR" | grep -oE '<frame[^>]*>'; }

# ── (a) a frame with NO name at all (generic path:line) keeps the line behaviour, stamped ────────────────
cat > "$WORK/a2/traces/nameless.txt" <<'EOF'
src/mod.cpp:8
EOF
NAM="$( a2_run nameless.txt )"
{ [ "$( a2_attr n frame "$NAM" )" = "beta" ] && [ "$( a2_attr resolved_by frame "$NAM" )" = "line" ]; } \
    && ok "(A2a) a nameless frame keeps line-enclosure and says so (resolved_by=\"line\")" \
    || { no "(A2a) the nameless frame lost the line fallback or its disclosure"; printf '%s' "$NAM" | grep -oE '<frame[^>]*>'; }

# ── (b) a between-bodies frame is COUNTED and VISIBLE: the third bucket, <unresolved> ────────────────────
cat > "$WORK/a2/traces/gap.txt" <<'EOF'
    #0 0x1 in ghostFn src/mod.cpp:5:1
EOF
GAP="$( a2_run gap.txt )"
{ [ "$( a2_attr in_corpus trace "$GAP" )" = "1" ] && [ "$( a2_attr suspects trace "$GAP" )" = "0" ] \
  && [ "$( a2_attr unresolved trace "$GAP" )" = "1" ] && [ "$( a2_attr skipped trace "$GAP" )" = "0" ]; } \
    && ok "(A2b) a frame whose line falls BETWEEN bodies is counted in the third bucket (unresolved=1)" \
    || { no "(A2b) the between-bodies frame vanished from the counters"; printf '%s' "$GAP" | grep -oE '<trace[^>]*>'; }
printf '%s' "$GAP" | grep -q '<unresolved p="src/mod.cpp:5" n="ghostFn"/>' \
    && ok "(A2b) it is EMITTED as <unresolved p=\"file:line\" n=\"raw frame name\"/>, never dropped" \
    || { no "(A2b) no <unresolved> row for the between-bodies frame"; printf '%s' "$GAP" | grep -oE '<trace.*</trace>'; }

# ── (b) a dedup pair: two frames, one symbol → merged=1, and the arithmetic still closes ─────────────────
cat > "$WORK/a2/traces/dedup.txt" <<'EOF'
    #0 0x1 in alpha src/mod.cpp:3:1
    #1 0x2 in alpha src/mod.cpp:2:1
    #2 0x3 in ghostFn src/mod.cpp:5:1
    #3 0x4 in __libc_start_main /usr/lib/libc.so.6:0
EOF
DED="$( a2_run dedup.txt )"
{ [ "$( a2_attr merged trace "$DED" )" = "1" ] && [ "$( a2_attr suspects trace "$DED" )" = "1" ]; } \
    && ok "(A2b) two frames on ONE symbol rank it once and COUNT the fold (merged=1)" \
    || { no "(A2b) the deduped frame was not counted as merged"; printf '%s' "$DED" | grep -oE '<trace[^>]*>'; }

# ── (b) THE invariant, on every fixture bundle: in_corpus = suspects + merged + unresolved ───────────────
arith_ok(){
    local label="$1" out="$2"
    local ic sp mg ur
    ic="$( a2_attr in_corpus trace "$out" )"; sp="$( a2_attr suspects trace "$out" )"
    mg="$( a2_attr merged trace "$out" )";    ur="$( a2_attr unresolved trace "$out" )"
    { [ -n "$ic" ] && [ -n "$sp" ] && [ -n "$mg" ] && [ -n "$ur" ] && [ "$ic" -eq "$(( sp + mg + ur ))" ]; } \
        && ok "(A2b) [$label] in_corpus($ic) = suspects($sp) + merged($mg) + unresolved($ur)" \
        || { no "(A2b) [$label] the frame partition does not close: in_corpus=$ic suspects=$sp merged=$mg unresolved=$ur"; printf '%s' "$out" | grep -oE '<trace[^>]*>'; }
}
arith_ok stale     "$STALE"
arith_ok gap       "$GAP"
arith_ok dedup     "$DED"
arith_ok ambiguous "$AMB"
# ...and on the ORIGINAL per-format fixtures too (the same invariant, other corpora/formats)
for t in py asan clang node generic overflow; do arith_ok "$t" "$( tr_run "$t.txt" )"; done

# ── (c) the header legend states both conventions ───────────────────────────────────────────────────────
{ printf '%s' "$STALE" | grep -q 'in_corpus = suspects + merged + unresolved' \
  && printf '%s' "$STALE" | grep -q "p= on a frame is the FRAME's own locator" \
  && printf '%s' "$STALE" | grep -q 'definition sites live in <sigs> l='; } \
    && ok "(A2b/c) the header legend states the closing arithmetic AND which line convention p= carries" \
    || { no "(A2b/c) the header legend is missing the arithmetic or the p=/l= clause"; printf '%s' "$STALE" | head -c 900; echo; }

# ── determinism + G4 over the new fixtures ──────────────────────────────────────────────────────────────
A1="$( a2_run stale.txt )"; A2="$( a2_run stale.txt )"
[ "$A1" = "$A2" ] && ok "(A2) the name-resolved bundle is deterministic (byte-identical x2)" \
                  || no "(A2) non-deterministic name-resolved bundle"
if command -v xmllint >/dev/null 2>&1; then
    a2xml=0
    for t in stale demangled ambiguous narrowed nameless gap dedup; do
        a2_run "$t.txt" | xmllint --noout - 2>/dev/null || { a2xml=1; echo "     malformed: $t"; }
    done
    [ "$a2xml" = 0 ] && ok "(A2) all seven §A2 bundles are xmllint-clean (G4)" || no "(A2) a §A2 bundle is malformed XML"
else
    printf '  SKIP  (A2) xmllint (not installed)\n'
fi


# ══ CA4 §B3 — the budget ladder. --from-trace stated a budget and never labelled an overrun ═════════════
# Base measurement (base_w3, this fixture): --token-budget=50 emitted 2 031 B against a 135 B allowance with
# ZERO over_ceiling, while --pack-task printed its ledger and --for and --recall both labelled themselves.
# The allowance is the SAME bar the two siblings use, re-expressed against a post-headroom byte budget:
#   budget_bytes  = tokens x kMinBytesPerToken(2.36) x kBudgetHeadroom(0.90)
#   allowance     = budget_bytes x (kCeilingFirstEntryTolerance(1.15) / kBudgetHeadroom(0.90))
#                 = tokens x 2.36 x 1.15  == ceilingAllowanceBytes( tokens )   [serialize.h]
# Every arm below is red on base_w3 and green on the fixed binary.
tb_run(){ ( cd "$WORK" && "$BIN" . --from-trace="traces/py.txt" ${1:+--token-budget=$1} --no-cache 2>/dev/null ); }
allowance_of(){ python3 -c "import sys; print(int(int(sys.argv[1])*2.36*0.90*(1.15/0.90)))" "$1"; }

# (T1) the ledger EXISTS and states both numbers, at every budget including the default.
T1_DEF="$( tb_run '' )"
printf '%s' "$T1_DEF" | grep -qE 'budget=[0-9]+ bytes \(allowance [0-9]+ bytes' \
    && ok "(T1) --from-trace states a budget ledger (budget= + allowance=)" \
    || { no "(T1) no budget ledger in the --from-trace header"; printf '%s\n' "$T1_DEF" | head -c 400; }

# (T2) the ledger's arithmetic is the family's, not a second constant — re-derived here from the tokens.
for tb in 50 500 2000; do
    want="$( allowance_of "$tb" )"
    got="$( tb_run "$tb" | grep -oE 'allowance [0-9]+ bytes' | head -1 | grep -oE '[0-9]+' )"
    [ "$got" = "$want" ] \
        && ok "(T2) --token-budget=$tb allowance=$got == tokens x 2.36 x 1.15 (== ceilingAllowanceBytes)" \
        || no "(T2) --token-budget=$tb allowance=$got, expected $want — the lens drifted off the shared arithmetic"
done

# (T3) an overrun is LABELLED. A budget this small cannot fit the first whole signature, so the honest
#      answer is the complete bundle + over_ceiling — never a silent 15x overshoot, never a mutilated bundle.
for tb in 50 100 500; do
    out="$( tb_run "$tb" )";  n=$( printf '%s' "$out" | wc -c | tr -d ' ' );  want="$( allowance_of "$tb" )"
    if [ "$n" -gt "$want" ]; then
        printf '%s' "$out" | grep -q 'over_ceiling' \
            && ok "(T3) --token-budget=$tb: ${n}B over a ${want}B allowance AND says over_ceiling" \
            || no "(T3) --token-budget=$tb: ${n}B over a ${want}B allowance with NO over_ceiling label"
    else
        no "(T3) --token-budget=$tb did not overshoot ($n <= $want) — this arm no longer measures anything"
    fi
done

# (T4) the label is not unconditional: a budget the bundle FITS under must stay silent (a lens that always
#      cries over_ceiling is as useless as one that never does). 20000 tokens is ~54 KB of allowance.
T4="$( tb_run 20000 )";  t4n=$( printf '%s' "$T4" | wc -c | tr -d ' ' );  t4a="$( allowance_of 20000 )"
{ [ "$t4n" -le "$t4a" ] && ! printf '%s' "$T4" | grep -q 'over_ceiling'; } \
    && ok "(T4) a bundle that FITS (${t4n}B <= ${t4a}B) carries no over_ceiling label" \
    || no "(T4) over_ceiling fired on a conformant bundle (${t4n}B vs ${t4a}B allowance)"

# (T5) §B1.7 root attrs — the trace SOURCE is this lens's request text and is now carried VERBATIM in the
#      task= attribute (ctxRootOpen), beside the lossy readable echo in the comment. The bundle opened with a
#      bare <ctx> before, so a consumer had no machine-readable copy of what it had asked about at all.
printf '%s' "$T1_DEF" | grep -q '^<ctx task="traces/py.txt">' \
    && ok "(T5) the bundle root carries the verbatim source (ctxRootOpen task=)" \
    || { no "(T5) <ctx> has no verbatim task= root attribute"; printf '%s' "$T1_DEF" | head -c 80; echo; }

# (T6) every budgeted shape stays G4-clean and byte-deterministic — the ladder must not be able to splice a
#      header that breaks the document, and its choice is a pure function of its inputs.
if command -v xmllint >/dev/null 2>&1; then
    t6=0
    for tb in 50 500 2000 20000; do
        a="$( tb_run "$tb" )";  b="$( tb_run "$tb" )"
        [ "$a" = "$b" ] || { t6=1; echo "     non-deterministic at --token-budget=$tb"; }
        printf '%s' "$a" | xmllint --noout - 2>/dev/null || { t6=1; echo "     malformed at --token-budget=$tb"; }
    done
    [ "$t6" = 0 ] && ok "(T6) every budgeted bundle is xmllint-clean AND byte-identical across runs" \
                  || no "(T6) a budgeted bundle is malformed or non-deterministic"
else
    printf '  SKIP  (T6) xmllint (not installed)\n'
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
# CA4 §B15: this file used to stop at the line above and return 0 — six real FAILs rode along green for
# rounds because regression.sh's verdict is the EXIT CODE. A gate that cannot fail is not a gate.
exit "$fail"
