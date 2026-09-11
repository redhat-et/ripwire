#!/usr/bin/env bash
# verify-agent-integration.sh — prove ripwire's wiring works on an agent WE CANNOT RUN.
#
# WHY THIS EXISTS. `ripwire wrap <agent>` prints a recipe, and `skills/install.sh` deploys skills into a
# discovery root. Both claims are checked in CI against the FILESYSTEM. Neither is checked against the
# agent, because the maintainers do not have openclaw, Hermes, Windsurf or Gemini installed. Everything
# below the "phase 2" line is therefore a claim this project cannot verify alone, and this script exists
# so that verifying it costs a stranger one command and a copy-paste instead of an afternoon.
#
#   bash scripts/verify-agent-integration.sh openclaw
#
# It is READ-MOSTLY: phase 1 installs into a throwaway HOME (never your real one) unless you pass
# --live. Phase 2 prints prompts for you to paste into the agent. The last section is a filled-in
# markdown report — paste that into the PR, INCLUDING any FAIL lines. A FAIL is the useful outcome;
# it is the only way this project finds out that a recipe it publishes does not work.
set -u

ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ -x "$BIN" ] || BIN="$( command -v ripwire || true )"
AGENT="${1:-}"
LIVE=0
for a in "$@"; do [ "$a" = "--live" ] && LIVE=1; done

pass=0; failn=0; RESULTS=""
ok()   { pass=$(( pass + 1 ));  RESULTS="$RESULTS
- [x] $*"; printf '  PASS  %s\n' "$*"; }
no()   { failn=$(( failn + 1 )); RESULTS="$RESULTS
- [ ] **FAIL** $*"; printf '  FAIL  %s\n' "$*"; }
note() { RESULTS="$RESULTS
- _$*_"; printf '  note  %s\n' "$*"; }

[ -n "$AGENT" ] || { echo "usage: bash scripts/verify-agent-integration.sh <agent> [--live]"; "$BIN" wrap 2>&1 | sed 's/^/  /'; exit 2; }
[ -x "$BIN" ] || { echo "no ripwire binary — build with 'cmake -S . -B build && cmake --build build -j' or install first"; exit 2; }

echo "== phase 1 — checks this script can make on its own =="

OUT="$( "$BIN" wrap "$AGENT" --force 2>&1 )" \
    && ok "\`ripwire wrap $AGENT\` exits 0" \
    || no "\`ripwire wrap $AGENT\` failed: $( printf '%s' "$OUT" | head -1 )"

FLAG="$( printf '%s' "$OUT" | grep -oE 'install\.sh( --[a-z-]+)?' | head -1 | sed 's/install\.sh *//' )"
DEST="$( printf '%s' "$OUT" | sed -n 's/.*# deploy to \(.*\) (drift-gated).*/\1/p' | head -1 )"

if printf '%s' "$OUT" | grep -q 'install\.sh'; then
    SANDBOX="$( mktemp -d )"
    if [ "$LIVE" -eq 1 ]; then
        H="$HOME"; echo "  (--live: installing into your REAL home)"
    else
        H="$SANDBOX"; echo "  (sandbox HOME=$SANDBOX — pass --live to install for real)"
    fi
    if OUTPUT="$( HOME="$H" AGENTS_HOME="${AGENTS_HOME:-$H/.agents}" CODEX_HOME="${CODEX_HOME:-$H/.codex}" \
                  bash "$ROOT/skills/install.sh" ${FLAG:+$FLAG} 2>&1 )"; then
        ok "\`skills/install.sh ${FLAG:-(no flag)}\` — the exact command the recipe printed — succeeds"
        N="$( printf '%s' "$OUTPUT" | grep -c '^installed ' )"
        [ "$N" -gt 0 ] && ok "$N skills deployed" || no "installer reported success but deployed 0 skills"
        # `sh -c "echo \"$DEST\""` does NOT expand a leading ~ inside double quotes, so this resolved to a
        # literal "~/.claude/skills", the glob below matched nothing, and the "every skill resolves" check
        # passed having examined zero files. Expand the tilde explicitly.
        RESOLVED="$( HOME="$H" AGENTS_HOME="${AGENTS_HOME:-$H/.agents}" sh -c "echo ${DEST/#\~/$H}" 2>/dev/null )"
        BROKEN=0; SEEN=0
        for l in "$RESOLVED"/ripwire-*; do
            [ -e "$l" ] || continue
            SEEN=$(( SEEN + 1 ))
            [ -f "$l/SKILL.md" ] || BROKEN=$(( BROKEN + 1 ))
        done
        [ "$SEEN" -gt 0 ] || no "resolved skills root '$RESOLVED' contains no ripwire-* entries — this check examined nothing"
        [ "$BROKEN" -eq 0 ] && ok "every deployed skill resolves to a readable SKILL.md" \
                            || no "$BROKEN deployed skill(s) have no readable SKILL.md — a symlink the agent cannot follow"
    else
        no "\`skills/install.sh ${FLAG:-}\` FAILED: $( printf '%s' "$OUTPUT" | head -1 )"
    fi
    rm -rf "$SANDBOX"
else
    note "no skills line for $AGENT — this agent has no verified skills-discovery root, which is itself the claim"
fi

CAVEAT="$( printf '%s' "$OUT" | sed -n 's/^# NOTE: \(.*\)/\1/p' | grep -v 'PATH' | head -1 )"
[ -n "$CAVEAT" ] && note "the recipe states a CONDITION — confirm it holds on your machine: $CAVEAT"

echo
echo "== phase 2 — ONLY YOU CAN DO THIS. Nothing above proves the agent behaves. =="
cat <<EOF
  1. Wire it up:  run the commands \`ripwire wrap $AGENT\` printed, in a real repo.
  2. Start $AGENT there and paste this, VERBATIM:

         What does ripwire do, and when should you reach for it instead of grep?

     PASS = it answers from the wiring (the paste-block or a skill), without you explaining.
     FAIL = "I don't know what ripwire is."  <- report this, it is the interesting result.

  3. Then paste a real task:

         Use ripwire to find where this repo parses command-line flags, then read the top hit.

     PASS = it RUNS ripwire (you see the command) rather than falling back to grep + open-every-file.
     FAIL = it knows the tool exists and still does not reach for it. Also worth reporting: that is a
            wording problem in the paste-block, not a bug in $AGENT, and it is fixable.

  4. If the recipe offered an MCP alternative, register that instead and repeat step 3.
EOF

echo
echo "== paste this into the PR =="
cat <<EOF

<details><summary><b>verify-agent-integration.sh $AGENT</b> — $( uname -s ) $( uname -m )</summary>

\`ripwire $( "$BIN" --version 2>/dev/null | head -1 )\` · agent version: <!-- paste \`$AGENT --version\` -->

**Phase 1 (automated): $pass passed, $failn failed**
$RESULTS

**Phase 2 (by hand):**
- [ ] step 2 — the agent knows what ripwire is without being told
- [ ] step 3 — the agent actually invokes it on a real task
- [ ] step 4 — MCP alternative works (or: n/a, no MCP form for this agent)

Notes:
</details>
EOF
[ "$failn" -eq 0 ] || exit 1
