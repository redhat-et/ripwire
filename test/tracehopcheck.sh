#!/usr/bin/env bash
# tracehopcheck.sh — gate for the TEST->SOURCE hop on --from-trace (and its MCP twin from_trace).
#
# THE LOSS THIS CLOSES. A failing-test trace names TEST frames, and only test frames: the innermost
# in-corpus frame is `test_listen` in `tests/test_listeners.py`, while the code an agent has to read
# and fix is `listen` in `src/listeners.py`. --from-trace did exactly what it promised — the innermost
# in-corpus frame, ranked first — and the source file the reader actually wants never appeared in the
# bundle at all. On a retrieval benchmark whose gold is the source file this is a near-total miss on
# the trace task; for an agent it is a bundle that shows the assertion and hides the subject.
#
# WHAT THE HOP DOES, and the honesty contract it keeps:
#   * it fires ONLY when the innermost in-corpus frame's symbol classifies as a test (filter.h's shared
#     isTestSymbol — the same predicate the tested= lens and --ignore-tests ask; never a second copy);
#   * via="callee" rows are REAL 1-hop call edges out of the test symbol into non-test code;
#   * via="basename" rows are the naming-convention pair (foo_test.go->foo.go, test_foo.py->foo.py,
#     foo.spec.ts->foo.ts, FooTest.java->Foo.java, tests/foo.rs->src/foo.rs), used only when no call
#     edge lands in that file — runner-mediated linkage is invisible to a static call graph, so this
#     tier is a guess and says so;
#   * the block is labelled heuristic="1", carries its own pre-cap candidate counts, and the legend
#     states the ranking change instead of performing it silently;
#   * the <trace> frame partition is UNCHANGED — the hop adds a sibling block, it does not rewrite the
#     frame map;
#   * a NON-test trace emits nothing of this: no block, no legend, no rank change (inertness).
#
# Arms:
#   (H1) callee hop fires on a python test trace: <test_hop via="callee"> names the source symbol and
#        the source FILE appears in <sigs> (it did not before).
#   (H2) basename pair fires when the test has NO call edge into source, and is labelled via="basename".
#   (H3) disclosure: heuristic="1" on the block, and the header legend names both mechanisms AND the
#        fact that the hop rows are ranked ahead of the remaining frames.
#   (H4) inertness: a NON-test trace's bundle contains no hop block and no hop legend.
#   (H5) the innermost frame keeps rank 1 in <trace> and keeps its full body — the hop ADDS, never displaces.
#   (H6) the source body is served beside the test body (<bodies> shows both).
#   (H7) counters close: rows= equals the number of <hop rows, and callee=+basename= equals rows=+capped=.
#   (H8) determinism (x3 byte-identical) and xmllint well-formedness on a hop-firing bundle.
#   (H9) the hop reaches the MCP from_trace verb too — same assembler, so the parity is asserted, not assumed.
#
# Operates on a private temp tree (never touches the real repo). No git needed.
# Usage:  test/tracehopcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/tracehopcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # make BIN absolute BEFORE we cd away
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/repo/src" "$WORK/repo/tests" "$WORK/traces"

# ── the fixture tree ────────────────────────────────────────────────────────────────────────────────
# src/listeners.py — the SOURCE the failing test exercises through a real call edge
cat > "$WORK/repo/src/listeners.py" <<'EOF'
def listen( addr ):
    return bind_socket( addr )

def bind_socket( addr ):
    return 0
EOF

# src/widget.py — the SOURCE only a basename convention pairs with (no call edge reaches it)
cat > "$WORK/repo/src/widget.py" <<'EOF'
def render_widget():
    return 1
EOF

# tests/test_listeners.py — calls listen(): the callee-hop case
cat > "$WORK/repo/tests/test_listeners.py" <<'EOF'
from src.listeners import listen

def test_listen():
    assert listen( "bad" ) == 0
EOF

# tests/test_widget.py — exercises the widget through the RUNNER only: no static edge at all
cat > "$WORK/repo/tests/test_widget.py" <<'EOF'
def test_widget_renders():
    assert True
EOF

# a failing-test traceback whose only in-corpus frame is the TEST (the shape this gate exists for)
cat > "$WORK/traces/callee.txt" <<'EOF'
Traceback (most recent call last):
  File "/build/tests/test_listeners.py", line 4, in test_listen
    assert listen( "bad" ) == 0
AssertionError
EOF

# the same shape, but the test reaches its subject only through the runner
cat > "$WORK/traces/basename.txt" <<'EOF'
Traceback (most recent call last):
  File "/build/tests/test_widget.py", line 2, in test_widget_renders
    assert True
AssertionError
EOF

# a NON-test trace: the innermost in-corpus frame is source, so the hop must stay completely inert
cat > "$WORK/traces/source.txt" <<'EOF'
Traceback (most recent call last):
  File "/build/src/listeners.py", line 2, in listen
    return bind_socket( addr )
  File "/build/src/listeners.py", line 5, in bind_socket
    return 0
ValueError: boom
EOF

R="$WORK/repo"
"$BIN" "$R" --from-trace="$WORK/traces/callee.txt"   > "$WORK/out.callee"   2>"$WORK/err.callee"
"$BIN" "$R" --from-trace="$WORK/traces/basename.txt" > "$WORK/out.basename" 2>/dev/null
"$BIN" "$R" --from-trace="$WORK/traces/source.txt"   > "$WORK/out.source"   2>/dev/null

# presence guard (CONTRIBUTING §2 "green while inert"): the fixture must actually produce the three
# bundles this gate then interrogates, and the callee edge the (H1) arm asserts must really exist.
[ -s "$WORK/out.callee" ] && [ -s "$WORK/out.basename" ] && [ -s "$WORK/out.source" ] \
  || { echo "  FAIL  fixture: --from-trace produced no bundle (see $WORK)"; exit 1; }
"$BIN" "$R" --callees=test_listen 2>/dev/null | grep -q 'n="listen"' \
  || { echo "  FAIL  fixture: the test_listen -> listen call edge is absent; (H1) could not observe a hop"; exit 1; }
grep -q 'n="test_listen"' "$WORK/out.callee" \
  || { echo "  FAIL  fixture: the trace's innermost frame did not resolve to test_listen"; exit 1; }

# ── (H1) the callee hop ────────────────────────────────────────────────────────────────────────────
if grep -q '<test_hop ' "$WORK/out.callee"; then ok "(H1a) a test-frame trace emits a <test_hop> block"
else no "(H1a) a test-frame trace emits a <test_hop> block"; fi

if grep -q '<hop [^>]*n="listen"[^>]*via="callee"' "$WORK/out.callee"; then ok "(H1b) the source symbol listen is a via=\"callee\" hop row"
else no "(H1b) the source symbol listen is a via=\"callee\" hop row"; fi

if grep -q 'p="src/listeners.py"' "$WORK/out.callee"; then ok "(H1c) the SOURCE file now appears in the bundle's <sigs>"
else no "(H1c) the SOURCE file now appears in the bundle's <sigs>"; fi

# the hop must be ranked ahead of nothing it should not be: the source file has to precede any
# remaining frame file, which on this fixture means the <sigs> rows span at least two files.
# RE-PINNED: P7 (terminality round A, lane R, 2026-09-05): the lens <sigs> is FLAT — <d … p="FILE" … r=N> rows in rank order, no <f p=> wrapper (test/forrankordercheck.sh) — count DISTINCT p= over the <d> rows, not <f> blocks.
if [ "$( grep -o '<d [^>]*>' "$WORK/out.callee" | grep -o ' p="[^"]*"' | sort -u | wc -l | tr -d ' ' )" -ge 2 ]; then ok "(H1d) the bundle's <sigs> rows span more than one file"
else no "(H1d) the bundle's <sigs> rows span more than one file"; fi

# ── (H2) the basename pair ─────────────────────────────────────────────────────────────────────────
if grep -q '<hop [^>]*via="basename"' "$WORK/out.basename"; then ok "(H2a) a runner-mediated test pairs its source by basename"
else no "(H2a) a runner-mediated test pairs its source by basename"; fi

if grep -q '<hop [^>]*n="render_widget"' "$WORK/out.basename"; then ok "(H2b) the basename-paired source symbol is served"
else no "(H2b) the basename-paired source symbol is served"; fi

# anchored at the ROW, not the document: the legend explains both mechanisms on every hop bundle, so a
# bare grep for via="callee" here would fail on the legend and prove nothing about the rows.
if grep -q '<hop [^>]*via="callee"' "$WORK/out.basename"; then no "(H2c) no callee row is invented where no call edge exists"
else ok "(H2c) no callee row is invented where no call edge exists"; fi

# ── (H3) disclosure ────────────────────────────────────────────────────────────────────────────────
if grep -q '<test_hop [^>]*heuristic="1"' "$WORK/out.callee"; then ok "(H3a) the block labels itself a heuristic"
else no "(H3a) the block labels itself a heuristic"; fi

for phrase in 'via="callee"' 'via="basename"' 'HEURISTIC' 'TEST-TO-SOURCE HOP'; do
  if grep -q -- "$phrase" "$WORK/out.callee"; then ok "(H3b) the legend explains: $phrase"
  else no "(H3b) the legend explains: $phrase"; fi
done

# the legend must say the rows are placed AHEAD of the remaining frames — a stated reorder, not a silent one
if grep -qi 'before the remaining' "$WORK/out.callee"; then ok "(H3c) the legend states the ranking change"
else no "(H3c) the legend states the ranking change"; fi

# ── (H4) inertness on a non-test trace ─────────────────────────────────────────────────────────────
if grep -q 'test_hop' "$WORK/out.source"; then no "(H4a) a source-frame trace carries no hop block"
else ok "(H4a) a source-frame trace carries no hop block"; fi
if grep -qi 'TEST-TO-SOURCE HOP' "$WORK/out.source"; then no "(H4b) a source-frame trace carries no hop legend"
else ok "(H4b) a source-frame trace carries no hop legend"; fi

# ── (H5) the innermost frame is not displaced ──────────────────────────────────────────────────────
if grep -q '<frame rank="1" n="test_listen"[^>]*innermost="1"' "$WORK/out.callee"; then ok "(H5a) the innermost frame keeps rank 1 in <trace>"
else no "(H5a) the innermost frame keeps rank 1 in <trace>"; fi
if grep -q '<b [^>]*n="test_listen"' "$WORK/out.callee"; then ok "(H5b) the innermost frame keeps its full body"
else no "(H5b) the innermost frame keeps its full body"; fi

# ── (H6) the source body rides along ───────────────────────────────────────────────────────────────
if grep -q '<b [^>]*n="listen"' "$WORK/out.callee"; then ok "(H6) the hopped-to source symbol's body is served too"
else no "(H6) the hopped-to source symbol's body is served too"; fi

# ── (H7) the counters close ────────────────────────────────────────────────────────────────────────
attrs="$( sed 's/.*<test_hop \([^>]*\)>.*/\1/' "$WORK/out.callee" )"
getn(){ printf '%s' "$attrs" | sed -n "s/.*$1=\"\([0-9]*\)\".*/\1/p"; }
rows="$( getn rows )"; callee="$( getn callee )"; basen="$( getn basename )"; capped="$( getn capped )"
actual="$( grep -o '<hop ' "$WORK/out.callee" | wc -l | tr -d ' ' )"
if [ -n "$rows" ] && [ "$rows" = "$actual" ]; then ok "(H7a) rows=$rows equals the <hop> rows actually emitted"
else no "(H7a) rows='$rows' vs $actual emitted <hop> rows"; fi
if [ -n "$callee" ] && [ -n "$basen" ] && [ -n "$capped" ] \
   && [ "$(( callee + basen ))" = "$(( actual + capped ))" ]; then ok "(H7b) callee+basename = rows+capped (candidates all accounted for)"
else no "(H7b) callee='$callee' basename='$basen' rows='$actual' capped='$capped' do not close"; fi

# ── (H8) determinism + well-formedness ─────────────────────────────────────────────────────────────
"$BIN" "$R" --from-trace="$WORK/traces/callee.txt" > "$WORK/d2" 2>/dev/null
"$BIN" "$R" --from-trace="$WORK/traces/callee.txt" > "$WORK/d3" 2>/dev/null
if cmp -s "$WORK/out.callee" "$WORK/d2" && cmp -s "$WORK/out.callee" "$WORK/d3"; then ok "(H8a) the hop bundle is byte-identical across three runs"
else no "(H8a) the hop bundle is byte-identical across three runs"; fi
if command -v xmllint >/dev/null 2>&1; then
  if xmllint --noout "$WORK/out.callee" 2>/dev/null && xmllint --noout "$WORK/out.basename" 2>/dev/null; then ok "(H8b) both hop bundles are well-formed XML"
  else no "(H8b) both hop bundles are well-formed XML"; fi
else
  ok "(H8b) xmllint absent — well-formedness arm skipped"
fi

# ── (H9) MCP parity — the from_trace verb shares the assembler ─────────────────────────────────────
printf '%s' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"from_trace","arguments":{"path":"'"$R"'","trace":"Traceback (most recent call last):\n  File \"/build/tests/test_listeners.py\", line 4, in test_listen\n    assert listen( \"bad\" ) == 0\nAssertionError\n"}}}' > "$WORK/mcp.jsonl"
printf '\n' >> "$WORK/mcp.jsonl"
"$BIN" --mcp < "$WORK/mcp.jsonl" > "$WORK/mcp.out" 2>/dev/null
if grep -q 'test_hop' "$WORK/mcp.out"; then ok "(H9) the MCP from_trace verb serves the hop too"
else no "(H9) the MCP from_trace verb serves the hop too"; fi

if [ "$fail" -ne 0 ]; then
  echo "FAILURES ABOVE — tracehopcheck"
  exit 1
fi
echo "tracehopcheck: all arms pass"
exit 0
