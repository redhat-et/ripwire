#!/usr/bin/env bash
# det-gate.sh —  §8 byte-determinism gate: one baseline plus three comparisons, plus the WIDTH arm.
#
# ══ THE PRINCIPLE THIS GATE EXISTS TO STATE (CA4 §B15 — three rounds missed it) ═════════════════════════
#   A DETERMINISM OR WELL-FORMEDNESS GATE PROVES NOTHING ABOUT A FIXED BUFFER UNLESS ITS CORPUS CAN FILL
#   THAT BUFFER.
# The blind spot was never the VERB LIST. §H1 (a 640-byte stack-buffer overflow in --recall, leaking live
# stack bytes into an MCP reply) was already covered by TWO byte-determinism arms that predate the fix —
# recalltotalcheck.sh:134-137 and recallbudgetcheck.sh:164-168 — and BOTH passed on the leaking binary,
# because $ROOT is 44 bytes so ing.files[] entries run 60-90 B and the bug needed ~610. Nothing else in the
# suite reached even §B14's 228-byte entity-expanded threshold. 259 of 301 gate scripts carry a determinism
# assertion; corpus PATH LENGTH was the missing ingredient, and it is shared by the det-gate and the G4
# gate alike.
#
# So the width arm below plants a corpus at a ~600-byte ABSOLUTE path and makes BOTH assertions on it,
# because the two bug classes need different ones and one fixture serves both:
#   diff    catches §H1  — a leaked stack byte varies run to run (ASLR), so byte-identity fails.
#   xmllint catches §B14 — an snprintf truncation is PERFECTLY deterministic and byte-identical every run,
#                          so diff can never see it; only a parser can.
# It also diffs STDERR, which the arms above capture and never compare (so DEGRADED_PATH_ALERT is outside
# the gate), and it self-verifies its own premise: if the emitted p= is not actually wider than the buffers
# under test, the arm FAILS rather than passing for the wrong reason.
#
# Remaining, recorded rather than fixed here: no MemorySanitizer (an IN-BOUNDS uninitialised read is
# invisible to the current stack — §H1 was caught only because the read went out of bounds), and warm-vs-warm
# is compared nowhere (every arm passes --no-cache).

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
CORPUS="${2:-test/fixture}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"
trap 'rm -rf "$TMP"' EXIT

[ -x "$BIN" ] || { printf 'no ripwire binary at %s\n' "$BIN"; exit 2; }
cd "$ROOT"

"$BIN" "$CORPUS" --no-cache >"$TMP/baseline" 2>"$TMP/baseline.err" || exit 1
for runIndex in 1 2 3; do
    "$BIN" "$CORPUS" --no-cache >"$TMP/run-$runIndex" 2>"$TMP/run-$runIndex.err" || exit 1
    if ! diff -q "$TMP/baseline" "$TMP/run-$runIndex" >/dev/null; then
        printf 'FAIL: determinism comparison %s differs from baseline\n' "$runIndex"
        exit 1
    fi
done

# --match over a NESTING node kind must be byte-identical too. An outer and an inner call_expression can
# start at the SAME byte (`f(x).count()`), and astQuery's sort once lacked an endByte tie-break, so the
# parallel fan-out's arrival order leaked into the <m> BODY text (every p= identical, bodies swapped run
# to run). The tie needs a tree big enough to race: the fixture corpus never flapped, the repo root gave
# 3 distinct hashes in 6 pre-fix runs — so this arm deliberately runs on the repo itself, not $CORPUS.
"$BIN" . --match='(call_expression) @c' --no-cache >"$TMP/match-a" 2>"$TMP/match-a.err" || exit 1
"$BIN" . --match='(call_expression) @c' --no-cache >"$TMP/match-b" 2>"$TMP/match-b.err" || exit 1
if ! diff -q "$TMP/match-a" "$TMP/match-b" >/dev/null; then
    printf 'FAIL: --match over a nesting node kind differs between two runs — astQuery tie order is not total\n'
    exit 1
fi

printf 'PASS: baseline plus three comparisons are byte-identical (%s B)\n' \
    "$( wc -c <"$TMP/baseline" | tr -d ' ' )"
printf 'PASS: --match nesting-kind arm is byte-identical across two runs (%s B)\n' \
    "$( wc -c <"$TMP/match-a" | tr -d ' ' )"

# ══ THE WIDTH ARM (CA4 §B15) — the same verbs, on a corpus whose paths can FILL a fixed buffer ══════════
# Pure shell on purpose: this gate runs in CI (ci.yml:96-101, 163-168) and must not acquire a python3
# dependency. The deep directory is built by repeated mkdir, so a platform that refuses it degrades to a
# loud SKIP rather than a silent pass.
DEEPROOT="$TMP/w"
DEEP="$DEEPROOT"
SEG="$( printf 'd%.0s' $( seq 1 60 ) )"
mkdir -p "$DEEPROOT" || { printf 'FAIL: width arm could not create its sandbox root\n'; exit 1; }
while [ "${#DEEP}" -lt 580 ]; do
    if mkdir -p "$DEEP/$SEG" 2>/dev/null; then DEEP="$DEEP/$SEG"; else break; fi
done

if [ "${#DEEP}" -lt 520 ]; then
    printf 'SKIP: width arm — this filesystem capped the sandbox path at %s B (need >=520)\n' "${#DEEP}"
else
    # one C++ file (a symbol with callers, for --edit-check / --pack-task / --for) and one markdown doc
    # (for --recall). Both land in ing.files[] at the FULL absolute path, which is the thing under test.
    cat > "$DEEP/a.cpp" <<'CPPEOF'
int helperOne( int a ) { return a + 1; }
int helperTwo( int a, int b ) { return helperOne( a ) + b; }
int tgt( int a, int b ) { return helperTwo( a, b ) + helperOne( a ); }
int callerA( int x ) { return tgt( x, 1 ); }
int callerB( int x ) { return tgt( x, 2 ) + callerA( x ); }
int callerC( int x ) { return tgt( x, 3 ) + callerB( x ); }
CPPEOF
    cat > "$DEEP/notes.md" <<'MDEOF'
# deep notes
Kafka consumer rebalancing, partition assignment, offset commits and the sticky assignor.
Serialize the xml output under a token budget; the edit-check contract compares against git HEAD.
MDEOF

    # PREMISE: the arm's own precondition is the CORPUS path length, checked above against the sandbox we
    # built — never the EMITTED width, which is a property of the binary under test. A broken binary
    # truncates its p= to just under the buffer, so an emitted-width premise reads "corpus too narrow" and
    # skips exactly the run it exists to catch (measured: base_w3 emits a widest value of 506 B here — the
    # 512-byte truncation itself). The emitted width is reported as information, never as a gate.
    "$BIN" "$DEEPROOT" --no-cache >"$TMP/w-premise" 2>/dev/null || { printf 'FAIL: width arm baseline run failed\n'; exit 1; }
    WIDEST=$( tr '"' '\n' <"$TMP/w-premise" | awk '{ if ( length($0) > m ) m = length($0) } END { print m+0 }' )

    # $1 = label, $2 = xml|text (--recall's bundle is PROSE, not a document — it gets the diff assertion
    # only, which is the one §H1 needed; xmllint is the assertion §B14 needs and applies to the XML verbs).
    widthfail=0
    width_case() {
        label="$1"; dialect="$2"; shift 2
        "$BIN" "$DEEPROOT" "$@" --no-cache >"$TMP/w1.out" 2>"$TMP/w1.err" || { printf 'FAIL: width arm [%s] exited non-zero\n' "$label"; widthfail=1; return; }
        "$BIN" "$DEEPROOT" "$@" --no-cache >"$TMP/w2.out" 2>"$TMP/w2.err" || { printf 'FAIL: width arm [%s] exited non-zero on rerun\n' "$label"; widthfail=1; return; }
        cmp -s "$TMP/w1.out" "$TMP/w2.out" || { printf 'FAIL: width arm [%s] stdout is NOT byte-identical across two runs (the §H1 shape: a leaked stack byte varies run to run)\n' "$label"; widthfail=1; }
        cmp -s "$TMP/w1.err" "$TMP/w2.err" || { printf 'FAIL: width arm [%s] STDERR is not byte-identical across two runs\n' "$label"; widthfail=1; }
        if [ "$dialect" = xml ] && command -v xmllint >/dev/null 2>&1; then
            xmllint --noout "$TMP/w1.out" 2>"$TMP/w1.lint" || {
                printf 'FAIL: width arm [%s] emitted a document xmllint rejects at exit 0 (the §B14 shape: a fixed buffer truncated INSIDE the markup)\n' "$label"
                head -3 "$TMP/w1.lint"; widthfail=1; }
        fi
        # the §H1 tell that survives a text dialect: a leaked stack byte is a C0 control byte the bundle
        # never emits on purpose. \t \n \r are legitimate and are deleted first; high bytes are NOT control
        # bytes here — the separator line is literally "━" (U+2501, E2 94 81), so a naive [^[:print:]] test
        # flags every clean run (it did, on both binaries, before this narrowing).
        if [ "$dialect" = text ] && LC_ALL=C tr -d '\011\012\015' <"$TMP/w1.out" | LC_ALL=C grep -q '[[:cntrl:]]'; then
            printf 'FAIL: width arm [%s] emitted a control byte — the §H1 shape (raw stack bytes past the end of a fixed buffer)\n' "$label"
            widthfail=1
        fi
    }

    width_case "default map"        xml
    width_case "--recall"           text --recall="kafka rebalancing"
    width_case "--edit-check"       xml  --edit-check=tgt
    width_case "--pack-task"        xml  --pack-task="tgt helper rebalancing"
    width_case "--for --with-graph" xml  --for=tgt --with-graph

    [ "$widthfail" = 0 ] || exit 1
    printf 'PASS: width arm — 5 verbs x 2 runs at a %s B corpus path (widest emitted value %s B): stdout+stderr byte-identical AND xmllint-clean\n' \
        "${#DEEP}" "$WIDEST"
fi
