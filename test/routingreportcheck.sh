#!/usr/bin/env bash
# routingreportcheck.sh — gate for bench/routing_ab_report.py, the adoption-within-two A/B readout for
# the Claude Code prompt router pre-registered in docs/EVALS.md §4. Builds SYNTHETIC routing.jsonl /
# substitution.jsonl fixtures (never touches ~/.ripwire) covering the accounting edge cases the metric
# definition depends on, then asserts:
#
#   B  the refusal below the 40-recommended-per-arm floor — and that the floor cannot be bypassed
#   K/W/R  the pre-registered verdict at each of the three bands (KEEP/REWORD/REMOVE) once both arms
#          clear the floor
#   E  three accounting edge cases baked into one fixture: an "adoption" that lands on the 3rd
#      ripwire-family call (outside the two-call window) must NOT count; a control-arm row must count
#      toward control's n; an abstained prompt must be excluded from the recommended denominator
#   J  join coverage: a session with zero meter rows is correctly reported as uncovered
#   M  malformed input (a file with content, none of which parses as JSON) exits non-zero; a MISSING
#      file (not yet written) is not an error and still refuses cleanly
#   P  the script never prints anything that looks like prompt text — it has no field to print one
#      from, and a poisoned sibling file in the same directory is never opened at all
#
# Usage:  test/routingreportcheck.sh [PATH_TO_RIPWIRE]      ($1 is BIN; unused, kept for gate parity)
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
: "$BIN"   # unused -- this gate exercises bench/routing_ab_report.py, a standalone Python script
SCRIPT="$ROOT/bench/routing_ab_report.py"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -f "$SCRIPT" ] || { echo "no $SCRIPT"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "routingreportcheck: python3 is required"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "routingreportcheck: SCRIPT=$SCRIPT"

# ── the fixture builder: writes routing.jsonl + substitution.jsonl into $1, with $2 treatment-adopted
#    and $3 control-adopted counts out of a fixed $4-sized arm (default big enough to clear the floor),
#    plus the three baked-in edge cases (3rd-call adoption, abstain, no-meter session). Uses the real
#    `cksum` binary so session_hash/prompt_hash match EXACTLY what hooks/ripwire-claude-route.sh writes.
build_fixture()
{
    local dir="$1" tAdopt="$2" cAdopt="$3" armN="${4:-40}" edges="${5:-1}"
    mkdir -p "$dir"
    python3 - "$dir" "$tAdopt" "$cAdopt" "$armN" "$edges" <<'PYEOF'
import json, subprocess, sys

outdir, tAdopt, cAdopt, armN, edges = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])

def cksum(s):
    return subprocess.run(["cksum"], input=s.encode(), stdout=subprocess.PIPE).stdout.decode().split()[0]

routing = []
meter = []

def make_arm(arm, n, n_adopted, offset):
    for i in range(n):
        sh = cksum("fix-%s-%d" % (arm, i + offset))
        ph = cksum("fixp-%s-%d" % (arm, i + offset))
        routing.append({"v": 2, "at": "2026-09-01T10:00:00Z", "agent": "claude", "event": "UserPromptSubmit",
                         "status": "recommend", "intent": "connect-symbols", "recommended": "--connect",
                         "arm": arm, "session_hash": sh, "prompt_hash": ph, "prompt_bytes": 100})
        if i < n_adopted:
            routing.append({"v": 2, "at": "2026-09-01T10:00:05Z", "agent": "claude", "event": "RouteObservation",
                             "session_hash": sh, "prompt_hash": ph, "intent": "connect-symbols",
                             "recommended": "--connect", "arm": arm, "observed": "--connect",
                             "position": 1, "outcome": "adopted"})
        else:
            routing.append({"v": 2, "at": "2026-09-01T10:00:05Z", "agent": "claude", "event": "RouteObservation",
                             "session_hash": sh, "prompt_hash": ph, "intent": "connect-symbols",
                             "recommended": "--connect", "arm": arm, "observed": "--grep",
                             "position": 1, "outcome": "continued"})
            routing.append({"v": 2, "at": "2026-09-01T10:00:06Z", "agent": "claude", "event": "RouteObservation",
                             "session_hash": sh, "prompt_hash": ph, "intent": "connect-symbols",
                             "recommended": "--connect", "arm": arm, "observed": "--grep",
                             "position": 2, "outcome": "missed"})
        meter.append({"v": 2, "ts": "2026-09-01T10:00:00Z", "seq": 1, "session": "fix-%s-%d" % (arm, i + offset),
                       "tag": "x", "tool": "Bash", "class": "grep", "family": "native", "detail": "grep foo"})

make_arm("treatment", armN, tAdopt, 0)
make_arm("control", armN, cAdopt, 100000)

# edges=0 fixtures (the band-verdict fixtures) want an EXACT, unpolluted arm size so their percentages
# land on round numbers; edges=1 fixtures (the accounting-edge-case fixture, and the below-floor
# fixture, which deliberately wants a treatment arm 2 OVER the floor) get all three baked-in edge rows.
if edges:
    # EDGE 1 — an "adoption" on the 3rd ripwire-family call (position=3): the hook itself never writes
    # this (its pending file is gone by the 3rd call), but a rogue/future row like it must be discarded
    # by the window check, never trusted blindly from the log.
    sh3, ph3 = cksum("fix-edge3"), cksum("fixp-edge3")
    routing.append({"v": 2, "at": "2026-09-01T11:00:00Z", "agent": "claude", "event": "UserPromptSubmit",
                     "status": "recommend", "intent": "x", "recommended": "--for", "arm": "treatment",
                     "session_hash": sh3, "prompt_hash": ph3, "prompt_bytes": 50})
    routing.append({"v": 2, "at": "2026-09-01T11:00:01Z", "agent": "claude", "event": "RouteObservation",
                     "session_hash": sh3, "prompt_hash": ph3, "intent": "x", "recommended": "--for",
                     "arm": "treatment", "observed": "--for", "position": 3, "outcome": "adopted"})
    meter.append({"v": 2, "ts": "2026-09-01T11:00:00Z", "seq": 1, "session": "fix-edge3",
                   "tag": "x", "tool": "Bash", "class": "grep", "family": "native", "detail": "grep foo"})

    # EDGE 2 — an abstained prompt: must be excluded from the recommended denominator entirely.
    shA, phA = cksum("fix-abstain"), cksum("fixp-abstain")
    routing.append({"v": 2, "at": "2026-09-01T12:00:00Z", "agent": "claude", "event": "UserPromptSubmit",
                     "status": "abstain", "intent": "", "recommended": "", "arm": "treatment",
                     "session_hash": shA, "prompt_hash": phA, "prompt_bytes": 20})
    meter.append({"v": 2, "ts": "2026-09-01T12:00:00Z", "seq": 1, "session": "fix-abstain",
                   "tag": "x", "tool": "Bash", "class": "grep", "family": "native", "detail": "grep foo"})

    # EDGE 3 — a recommended prompt whose session has NO meter rows at all (session ended before any
    # observed tool call): must count toward n but show up as join-uncovered.
    shN, phN = cksum("fix-nometer"), cksum("fixp-nometer")
    routing.append({"v": 2, "at": "2026-09-01T13:00:00Z", "agent": "claude", "event": "UserPromptSubmit",
                     "status": "recommend", "intent": "y", "recommended": "--impact", "arm": "treatment",
                     "session_hash": shN, "prompt_hash": phN, "prompt_bytes": 30})
    # deliberately no meter row for fix-nometer

with open(outdir + "/routing.jsonl", "w") as fh:
    fh.write("\n".join(json.dumps(r) for r in routing) + "\n")
with open(outdir + "/substitution.jsonl", "w") as fh:
    fh.write("\n".join(json.dumps(r) for r in meter) + "\n")
PYEOF
}

run()
{
    python3 "$SCRIPT" --routing "$1/routing.jsonl" --meter "$1/substitution.jsonl" 2>"$1/stderr"
}

# ── B/E/J: one fixture, 40 per arm, treatment 30/40 adopted (75.0%), control 10/40 adopted (25.0%) —
#    +50pp, comfortably KEEP, so this same fixture also exercises the edge-case accounting.
D1="$TMP/d1"; build_fixture "$D1" 30 10 40
OUT1="$( run "$D1" )"; RC1=$?
[ "$RC1" = 0 ] && ok "exit 0 on a normal readout" || no "exit code was $RC1, expected 0"

# treatment: 40 arm rows + edge3 + nometer = 42 recommended; adopted = 30 (edge3's position=3 excluded)
echo "$OUT1" | grep -Eq '^treatment[[:space:]]+43[[:space:]]+42[[:space:]]+30[[:space:]]' \
    && ok "E1: treatment recommended=42 adopted=30 (3rd-call adoption excluded, abstain+nometer folded in)" \
    || { no "E1: treatment row wrong -- $( echo "$OUT1" | grep '^treatment' )"; }

echo "$OUT1" | grep -Eq '^control[[:space:]]+40[[:space:]]+40[[:space:]]+10[[:space:]]' \
    && ok "E2: control-arm row counted toward control n (recommended=40 adopted=10)" \
    || { no "E2: control row wrong -- $( echo "$OUT1" | grep '^control' )"; }

echo "$OUT1" | grep -Eq 'join coverage: 82/83' \
    && ok "E3/J: join coverage names the nometer session as uncovered (82/83)" \
    || { no "E3/J: join coverage line wrong -- $( echo "$OUT1" | grep 'join coverage' )"; }

echo "$OUT1" | grep -Eq '^KEEP -- treatment 71\.4% - control 25\.0% = \+46\.4pp' \
    && ok "K: KEEP verdict at +46.4pp (>= +10pp band)" \
    || { no "K: KEEP verdict wrong -- $( echo "$OUT1" | grep -E 'KEEP|REWORD|REMOVE|UNDERPOWERED' )"; }

# ── W: REWORD band -- 40/arm, treatment 18/40 (45.0%), control 16/40 (40.0%) = +5.0pp. edges=0: an
#    exact 40/40 split, no baked-in extras, so the rate lands on a round number.
D2="$TMP/d2"; build_fixture "$D2" 18 16 40 0
OUT2="$( run "$D2" )"
echo "$OUT2" | grep -Eq '^REWORD -- treatment 45\.0% - control 40\.0% = \+5\.0pp' \
    && ok "W: REWORD verdict at +5.0pp (0..+10pp band)" \
    || { no "W: REWORD verdict wrong -- $( echo "$OUT2" | grep -E 'KEEP|REWORD|REMOVE|UNDERPOWERED' )"; }

# ── R: REMOVE band -- 40/arm, treatment 12/40 (30.0%), control 16/40 (40.0%) = -10.0pp. edges=0, as above.
D3="$TMP/d3"; build_fixture "$D3" 12 16 40 0
OUT3="$( run "$D3" )"
echo "$OUT3" | grep -Eq '^REMOVE -- treatment 30\.0% - control 40\.0% = -10\.0pp' \
    && ok "R: REMOVE verdict at -10.0pp (<= 0pp band)" \
    || { no "R: REMOVE verdict wrong -- $( echo "$OUT3" | grep -E 'KEEP|REWORD|REMOVE|UNDERPOWERED' )"; }

# ── B: below the floor -- treatment has 39 (not 40) recommended, control has 40. Must refuse, name the
#    band and how many more each arm needs, and STAY refusing even though the ONLY difference from a
#    verdict-eligible fixture is a single missing row (no --force flag exists to override this).
D4="$TMP/d4"; build_fixture "$D4" 30 10 39
OUT4="$( run "$D4" )"; RC4=$?
echo "$OUT4" | grep -q 'UNDERPOWERED' && ok "B: refuses below the 40/arm floor" || no "B: did not refuse -- $OUT4"
echo "$OUT4" | grep -Eq 'needs >= 40 recommended prompts per arm' \
    && ok "B: refusal names the band (40 recommended/arm)" || no "B: refusal did not name the band"
echo "$OUT4" | grep -Eq 'treatment has 41 \(needs 0 more\)' \
    && ok "B: refusal names treatment's current n and shortfall (already clears 40)" \
    || no "B: treatment n/shortfall wrong -- $( echo "$OUT4" | grep treatment )"
echo "$OUT4" | grep -Eq 'control has 39 \(needs 1 more\)' \
    && ok "B: refusal names control's current n and shortfall (needs 1 more)" \
    || no "B: control n/shortfall wrong -- $( echo "$OUT4" | grep control )"
[ "$RC4" = 0 ] && ok "B: refusal exits 0 (a refusal is a correct answer)" || no "B: refusal exit code was $RC4, expected 0"

# ── M: malformed input -- a routing.jsonl with content, none of which parses as JSON, must exit non-zero.
D5="$TMP/d5"; mkdir -p "$D5"
printf 'this is not json\nneither is this\n' > "$D5/routing.jsonl"
printf '{"session":"s"}\n' > "$D5/substitution.jsonl"
python3 "$SCRIPT" --routing "$D5/routing.jsonl" --meter "$D5/substitution.jsonl" >"$D5/out" 2>"$D5/err"; RC5=$?
[ "$RC5" != 0 ] && ok "M: malformed routing.jsonl (0 of N lines parse) exits non-zero" \
                 || no "M: malformed input exited 0"

# ── missing file: NOT malformed -- a log that has not been written yet must refuse cleanly, exit 0.
D6="$TMP/d6"; mkdir -p "$D6"
printf '{"session":"s"}\n' > "$D6/substitution.jsonl"
python3 "$SCRIPT" --routing "$D6/routing.jsonl" --meter "$D6/substitution.jsonl" >"$D6/out" 2>"$D6/err"; RC6=$?
[ "$RC6" = 0 ] && ok "a not-yet-written routing.jsonl is not an error (exit 0, refuses on n=0)" \
               || no "missing routing.jsonl exited $RC6, expected 0"
grep -q UNDERPOWERED "$D6/out" && ok "missing routing.jsonl still prints the refusal line" \
                                || no "missing routing.jsonl did not refuse"

# ── P: no prompt-like text, ever -- the script has no field to print prompt text FROM (routing.jsonl
#      carries only a cksum + byte length by construction), and it must never open anything but the two
#      paths it is given. Prove the second half with a POISONED sibling file: if the script opened
#      every *.jsonl in the directory (a plausible bug -- e.g. a glob instead of the two named paths),
#      this file's distinctive marker would leak into stdout; it never should, because the script is
#      only ever given the two explicit --routing/--meter paths.
D7="$D1"   # reuse the KEEP fixture's directory -- it already has real routing+meter content
POISON_MARKER="ZZZ_POISONED_PROMPT_TEXT_MARKER_DO_NOT_LEAK_ZZZ"
echo "{\"prompt\":\"$POISON_MARKER\"}" > "$D7/sibling-should-never-be-opened.jsonl"
OUT7="$( run "$D7" )"
if echo "$OUT7" | grep -q "$POISON_MARKER"; then
    no "P: poisoned sibling file's content leaked into stdout"
else
    ok "P: poisoned sibling *.jsonl in the same dir never leaks (script opens only --routing/--meter)"
fi
# and a structural check: the script's own source never reads a "prompt" or "detail" field, which is
# where prompt/command text would have to come from if it were ever printed.
if grep -Eq '\.get\("prompt"|\["prompt"\]|\.get\("detail"|\["detail"\]' "$SCRIPT"; then
    no "P: script source reads a prompt/detail field -- it should never need to"
else
    ok "P: script source never reads a prompt or detail field (structurally cannot print prompt text)"
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# router= column / per-router readout (2026-09-03) -- the second router arm
# (hooks/ripwire-claude-toolroute.sh) shares routing.jsonl with router:"toolcall"; the prompt router's
# own rows now carry router:"prompt". Every fixture below is written directly (never via build_fixture,
# and never inside a `<<'HEREDOC'` wrapped in `$(...)` -- see test/toolcallroutefix/score_corpus.py's
# header for the bash-3.2 parser trap that combination hits).
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
D8="$TMP/d8"; mkdir -p "$D8"
python3 - "$D8" <<'PYEOF'
import json, subprocess, sys

outdir = sys.argv[1]

def cksum(s):
    return subprocess.run(["cksum"], input=s.encode(), stdout=subprocess.PIPE).stdout.decode().split()[0]

rows = []

# 40 "prompt"-router recommend rows, treatment arm, ALL adopted -- a clean KEEP once it clears the floor.
for i in range(40):
    sh, ph = cksum("d8-prompt-t-%d" % i), cksum("d8-prompt-tp-%d" % i)
    rows.append({"v": 2, "at": "2026-09-03T10:00:00Z", "agent": "claude", "router": "prompt",
                 "event": "UserPromptSubmit", "status": "recommend", "intent": "x",
                 "recommended": "--for", "arm": "treatment", "session_hash": sh, "prompt_hash": ph,
                 "prompt_bytes": 40})
    rows.append({"v": 2, "at": "2026-09-03T10:00:01Z", "agent": "claude", "router": "prompt",
                 "event": "RouteObservation", "session_hash": sh, "prompt_hash": ph, "intent": "x",
                 "recommended": "--for", "arm": "treatment", "observed": "--for", "position": 1,
                 "outcome": "adopted"})
# 40 "prompt"-router control rows, NONE adopted -- KEEP at +100pp once both clear the floor.
for i in range(40):
    sh, ph = cksum("d8-prompt-c-%d" % i), cksum("d8-prompt-cp-%d" % i)
    rows.append({"v": 2, "at": "2026-09-03T10:00:00Z", "agent": "claude", "router": "prompt",
                 "event": "UserPromptSubmit", "status": "recommend", "intent": "x",
                 "recommended": "--for", "arm": "control", "session_hash": sh, "prompt_hash": ph,
                 "prompt_bytes": 40})

# 50 "toolcall"-router decision rows (ToolCallRoute event, NO RouteObservation rows at all -- this
# router does not instrument adoption in this build). Split across both arms, well past the floor, so
# the readout has real recommend/abstain counts to show but must still refuse a verdict.
for i in range(25):
    sh = cksum("d8-tool-t-%d" % i)
    rows.append({"v": 2, "at": "2026-09-03T11:00:00Z", "agent": "claude", "router": "toolcall",
                 "event": "ToolCallRoute", "tool": "Bash", "shape": "grep", "status": "recommend",
                 "reason": "", "recommended": "--grep", "arm": "treatment", "session_hash": sh,
                 "detail_hash": cksum("d8-tool-detail-t-%d" % i)})
for i in range(25):
    sh = cksum("d8-tool-c-%d" % i)
    rows.append({"v": 2, "at": "2026-09-03T11:00:00Z", "agent": "claude", "router": "toolcall",
                 "event": "ToolCallRoute", "tool": "Read", "shape": "read", "status": "abstain",
                 "reason": "non-source", "recommended": "", "arm": "control", "session_hash": sh,
                 "detail_hash": cksum("d8-tool-detail-c-%d" % i)})

# a lone PRE-2026-09-03 row with no `router` field at all -- must fold into the "prompt" section, not
# vanish or form a phantom third router.
sh, ph = cksum("d8-legacy"), cksum("d8-legacy-p")
rows.append({"v": 2, "at": "2026-09-03T09:00:00Z", "agent": "claude", "event": "UserPromptSubmit",
             "status": "abstain", "intent": "", "recommended": "", "arm": "treatment",
             "session_hash": sh, "prompt_hash": ph, "prompt_bytes": 10})

with open(outdir + "/routing.jsonl", "w") as fh:
    fh.write("\n".join(json.dumps(r) for r in rows) + "\n")
with open(outdir + "/substitution.jsonl", "w") as fh:
    fh.write("")
PYEOF

OUT8="$( run "$D8" )"; RC8=$?
[ "$RC8" = 0 ] && ok "router fixture: exit 0" || no "router fixture: exit $RC8"
echo "$OUT8" | grep -q '=== router=prompt ===' && ok "router: prints a '=== router=prompt ===' section" \
    || no "router: no prompt section -- $OUT8"
echo "$OUT8" | grep -q '=== router=toolcall ===' && ok "router: prints a '=== router=toolcall ===' section" \
    || no "router: no toolcall section"
# the legacy no-router row folds into "prompt" -- treatment's prompt-router n is 40 (recommend rows)
# + 1 (the legacy abstain row) = 41 prompts, still 40 recommended.
echo "$OUT8" | sed -n '/=== router=prompt ===/,/=== router=toolcall ===/p' \
    | grep -Eq '^treatment[[:space:]]+41[[:space:]]+40[[:space:]]' \
    && ok "router: a pre-router-field row folds into router=prompt (41 prompts, 40 recommended)" \
    || no "router: legacy row did not fold into prompt -- $( echo "$OUT8" | grep '^treatment' | head -1 )"
echo "$OUT8" | grep -Eq '^KEEP -- treatment 100\.0% - control 0\.0%' \
    && ok "router: prompt section still computes a real KEEP verdict" \
    || no "router: prompt verdict wrong -- $( echo "$OUT8" | grep -E 'KEEP|REWORD|REMOVE|UNDERPOWERED' | head -1 )"
echo "$OUT8" | grep -q 'does not instrument adoption-within-two' \
    && ok "router: toolcall section states plainly it has no adoption instrument, prints no band verdict" \
    || no "router: toolcall section did not disclose its missing instrument"
echo "$OUT8" | sed -n '/=== router=toolcall ===/,$p' | grep -Eq '(KEEP|REWORD|REMOVE|UNDERPOWERED)' \
    && no "router: toolcall section printed a band verdict despite having no observation rows" \
    || ok "router: toolcall section never prints a fabricated band verdict"
echo "$OUT8" | sed -n '/=== router=toolcall ===/,$p' \
    | grep -Eq '^treatment[[:space:]]+25[[:space:]]+25[[:space:]]' \
    && ok "router: toolcall treatment arm shows its real recommend count (25/25)" \
    || no "router: toolcall treatment row wrong"
echo "$OUT8" | sed -n '/=== router=toolcall ===/,$p' \
    | grep -Eq '^control[[:space:]]+25[[:space:]]+0[[:space:]]' \
    && ok "router: toolcall control arm shows 0 recommended (all abstain rows)" \
    || no "router: toolcall control row wrong"

# --router=toolcall filters to just that section, and never touches the prompt section's numbers.
OUT8T="$( python3 "$SCRIPT" --routing "$D8/routing.jsonl" --meter "$D8/substitution.jsonl" --router toolcall )"
echo "$OUT8T" | grep -q '=== router=toolcall ===' && ok "--router=toolcall: shows the toolcall section" \
    || no "--router=toolcall: missing its own section"
echo "$OUT8T" | grep -q '=== router=prompt ===' && no "--router=toolcall: leaked the prompt section too" \
    || ok "--router=toolcall: does not print the prompt section"

echo ""
if [ "$fail" = 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME FAILED"
    exit 1
fi
