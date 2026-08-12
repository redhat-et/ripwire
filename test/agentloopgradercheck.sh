#!/usr/bin/env bash
# agentloopgradercheck.sh — the ANSWER grader's contract (bench/agentloop/grade_answers.py).
#
# WHY THIS GATE EXISTS. The E1 bank grades ANSWERS, not patches, and every one of its verdicts is a
# number somebody will later quote. Three of the grader's behaviours are not "nice to have" — they are
# the protocol, and a silent regression in any of them voids a funded round without turning anything
# red:
#
#   1. NON-CIRCULARITY (protocol §3). A `gt_command` that invokes ripwire produces a key from the
#      instrument under test, which is not a key. Such a row must be REFUSED. The hard part is that
#      NINE rows of the real bank legitimately name `ripwire/src` as a PATH argument to grep/ls, so a
#      naive "mentions ripwire" refusal would throw away a third of the bank. Both directions are
#      asserted here; a fix to one that breaks the other is the exact failure this arm catches.
#   2. SEALED JUDGEMENT (protocol §3.2). Where the answer key has a judgement half, a human seals it
#      BEFORE any run. The grader must REFUSE those rows without a key file — never improvise the
#      judgement, never fall back to "score what I can and call it a pass".
#   3. HONEST PARTIALS. An `accept_rule` is prose. The grader parses a closed clause grammar; a clause
#      it does not understand must DEMOTE the verdict to PARTIAL, never be skipped silently on the way
#      to PASS. This is CLAUDE.md non-negotiable 3 applied to a scoring surface.
#
# The fixture corpus is generated here rather than committed: six tiny files that no other gate should
# ever have to index, and a fixture whose content is visible in the gate that depends on it.
set -u

ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
FIX="$ROOT/bench/agentloop/fixtures/grader"
GRADER="$ROOT/bench/agentloop/grade_answers.py"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

command -v python3 >/dev/null 2>&1 || { echo "agentloopgradercheck: python3 required"; exit 2; }
[ -f "$GRADER" ]            || { echo "agentloopgradercheck: no grader at $GRADER"; exit 2; }
[ -f "$FIX/instances.tsv" ] || { echo "agentloopgradercheck: no fixture bank at $FIX"; exit 2; }

# ── the fixture corpus: two sibling checkouts under one pin root, the shape every gt_command uses ──
PINS="$TMP/pins"
mkdir -p "$PINS/fixturerepo/src" "$PINS/fixturerepo/docs" "$PINS/ripwire/src"
cat >"$PINS/fixturerepo/src/alpha.h" <<'EOF'
#pragma once
// fixture corpus - see test/agentloopgradercheck.sh
void alphaInit();
EOF
cat >"$PINS/fixturerepo/src/beta.cpp" <<'EOF'
#include "alpha.h"
struct BetaRecipe { int n; };
void betaRun()
{
    alphaInit();
}
EOF
cat >"$PINS/fixturerepo/src/gamma.h" <<'EOF'
#pragma once
static const int kFixtureCount = 16;
EOF
printf 'first doc\n'  >"$PINS/fixturerepo/docs/one.md"
printf 'second doc\n' >"$PINS/fixturerepo/docs/two.md"
cp "$PINS/fixturerepo/src/alpha.h" "$PINS/ripwire/src/alpha.h"

grade(){ python3 "$GRADER" --instances "$1" --results "$FIX/results.json" --pin-root "$PINS" \
                           --allow-unpinned "${@:2}"; }

# ── 1. the committed fixture grade table, byte for byte ─────────────────────────────────────────────
grade "$FIX/instances.tsv" --key "$FIX/sealed_key.json" >"$TMP/out.txt" 2>&1
rc=$?
grep -v '^#' "$TMP/out.txt" >"$TMP/table.tsv"
if diff -u "$FIX/expected.tsv" "$TMP/table.tsv" >"$TMP/diff.txt"; then
    ok "fixture grade table matches bench/agentloop/fixtures/grader/expected.tsv exactly"
else
    no "fixture grade table drifted from the committed expectation:"
    head -30 "$TMP/diff.txt"
fi
if [ "$rc" = 3 ]; then
    ok "exit 3 when a row was REFUSED (owner action needed, not a silent skip)"
else
    no "expected exit 3 with a refused row present, got $rc"
fi

# every verdict class the grader can emit is exercised by the fixture — a table that matches but
# covers only PASS would be a green gate over an untested grader.
for verdict in PASS FAIL PARTIAL HALLUCINATED NO_ANSWER GT_EMPTY REFUSED_CIRCULAR; do
    if grep -q "	$verdict	" "$TMP/table.tsv"; then
        ok "fixture exercises verdict $verdict"
    else
        no "fixture never produces verdict $verdict — that path is untested"
    fi
done

# ── 2. NON-CIRCULARITY, both directions ─────────────────────────────────────────────────────────────
if grep -q '^F06	.*REFUSED_CIRCULAR' "$TMP/table.tsv"; then
    ok "a gt_command that INVOKES ripwire is refused (protocol §3)"
else
    no "F06 (gt_command = 'ripwire fixturerepo --for=alpha ...') was not refused — the key would be "
    no "produced by the instrument under test"
fi
if grep -q '^F11	.*	PASS	' "$TMP/table.tsv"; then
    ok "a gt_command that merely NAMES ripwire/ as a path argument is NOT refused"
else
    no "F11 was refused or failed — nine rows of the real bank name ripwire/src as a grep path and "
    no "would be thrown away by an over-broad circularity test"
fi

# ── 3. the sealed-key refusal ───────────────────────────────────────────────────────────────────────
grade "$FIX/instances.tsv" >"$TMP/nokey.txt" 2>&1
if grep -q '^F05	.*REFUSED_NO_KEY' "$TMP/nokey.txt"; then
    ok "a V row REFUSES without --key (the judgement half is human-sealed pre-run, protocol §3.2)"
else
    no "F05 was scored without a sealed key — the grader improvised a judgement:"
    grep '^F05' "$TMP/nokey.txt" | head -2
fi
if grep -q '^F05	.*	PASS	' "$TMP/table.tsv"; then
    ok "the same V row PASSES once the sealed key is supplied"
else
    no "F05 did not pass with its sealed key present"
fi

# ── 4. the pin is verified, and the fixture escape hatch is not reachable by accident ───────────────
python3 "$GRADER" --instances "$FIX/instances.tsv" --results "$FIX/results.json" \
                  --pin-root "$PINS" --key "$FIX/sealed_key.json" 2>&1 | grep -v '^#' >"$TMP/pinned.txt"
if grep -q 'REFUSED_PIN' "$TMP/pinned.txt"; then
    ok "pin_ref=FIXTURE rows refuse without --allow-unpinned (a real run cannot take that path)"
else
    no "unpinned rows were graded without --allow-unpinned"
fi

# ── 5. exit 0 when nothing is refused — the contract a caller scripts against ───────────────────────
head -1 "$FIX/instances.tsv" >"$TMP/clean.tsv"
grep -E '^(F01|F11)	' "$FIX/instances.tsv" >>"$TMP/clean.tsv"
if grade "$TMP/clean.tsv" >"$TMP/clean.out" 2>&1; then
    ok "exit 0 when every row produced a verdict and none was refused"
else
    no "expected exit 0 on a refusal-free bank, got $?"
    tail -5 "$TMP/clean.out"
fi
if grep -q '^F12' "$TMP/table.tsv"; then
    no "a RETIRED row reached the grader"
else
    ok "RETIRED rows are excluded from grading"
fi

# ── 6. contract checks that need no fixture run ─────────────────────────────────────────────────────
python3 - "$ROOT" >"$TMP/contract.txt" 2>&1 <<'PY'
import pathlib, sys
sys.path.insert( 0, str( pathlib.Path( sys.argv[1] ) / "bench" / "agentloop" ) )
import grade_answers as G

def ok( m ): print( "PASS " + m )
def no( m ): print( "FAIL " + m )

# the circularity predicate itself, on the two shapes the real bank actually contains
( ok if G.is_circular( "ripwire . --for=x --max-tokens=4000" ) else no )( "bare invocation is circular" )
( ok if G.is_circular( "ls x | /opt/homebrew/bin/ripwire --expand=Y" ) else no )( "piped absolute invocation is circular" )
for legit in ( "grep -rn 'gitChurnCounts' ripwire/src ripwire/test",
               "ls ripwire/src/namesplit.h ripwire/src/naminglens.h",
               "for R in ctxpack ripwire; do sed -n '/pipeline/,+20p' $R/docs/ARCHITECTURE.md; done" ):
    ( no if G.is_circular( legit ) else ok )( "path argument is NOT an invocation: %s" % legit[ :46 ] )

# the seal predicate is conservative by design: a V row always, and any judgement half
( ok if G.needs_seal( dict( grader="V", accept_rule="anything" ) ) else no )( "every V row needs a seal" )
( ok if G.needs_seal( dict( grader="E", accept_rule="recall >=0.9; the per-site classification is "
                            "scored separately against a human-sealed key" ) ) else no )(
    "an E row with a classification half needs a seal" )
( no if G.needs_seal( dict( grader="F", accept_rule=">=4 of {a.h, b.h}; 0 fabricated paths" ) ) else ok )(
    "a purely mechanical F row needs no seal" )

# an unrecognised clause must DEMOTE, never be skipped on the way to PASS
parsed, unparsed = G.parse_clauses( "recall >=0.8; the enclosing function" )
( ok if len( parsed ) == 1 and len( unparsed ) == 1 else no )( "unparsed clauses are reported, not dropped" )

# the three transcript shapes the three harnesses emit
import json
claude = json.dumps( dict( result="x <<<ANSWER>>>\nsrc/a.h\n<<<END ANSWER>>>" ) )
codex  = json.dumps( dict( type="item.completed", item=dict( type="agent_message",
                                                             text="<<<ANSWER>>>\nsrc/a.h\n<<<END ANSWER>>>" ) ) )
oc     = json.dumps( dict( type="text", part=dict( text="<<<ANSWER>>>\nsrc/a.h\n<<<END ANSWER>>>" ) ) )
for name, blob in ( ( "claude", claude ), ( "codex", codex ), ( "opencode", oc ) ):
    got = G.fenced_answer( G.transcript_answer_text( blob ) )
    ( ok if got == "src/a.h" else no )( "%s transcript yields the fenced answer (%r)" % ( name, got ) )
( ok if G.fenced_answer( "no fence here" ) is None else no )( "an unfenced message yields no answer" )

# the derivation shell: macOS ships bash 3.2, which has no globstar, and a `**` row that silently
# matches nothing is protocol §4's false zero. Either a capable shell exists or `**` rows refuse.
shell = G.globstar_shell()
print( ( "PASS globstar-capable shell found (%s)" % shell ) if shell else
       "PASS no globstar shell — `**` rows will REFUSE rather than derive a false-zero key" )
PY
while IFS= read -r line; do
    case "$line" in
        PASS*) ok "${line#PASS }" ;;
        FAIL*) no "${line#FAIL }" ;;
        *)     [ -n "$line" ] && printf '        %s\n' "$line" ;;
    esac
done < "$TMP/contract.txt"
grep -q 'Traceback' "$TMP/contract.txt" && no "grader contract checks raised"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
