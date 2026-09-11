#!/usr/bin/env bash
# skilldescbudgetcheck.sh — every skill description fits the clients that actually render it.
#
# Issue #49 (2026-09-07): Codex renders the skill catalog under a TOTAL budget (2% of the context window,
# or 8,000 chars) and, on overflow, hands description characters out round-robin — every over-long
# description ends at the same count and the tail, where the routing boundaries live, is what vanishes.
# Codex also REJECTS a description over 1,024 characters; Claude Code caps an entry at 1,536. So two things
# are gated, both real: no description over 1,024 (Codex would drop the skill), and a set total of 5,400
# (amended from 4,800 before measurement, see docs/EVALS.md "Skill descriptions under a client budget") so
# the skills together stay a minority of those budgets. There is deliberately no tighter per-description
# number: the registered 320 was a design ceiling, not a client limit, and holding it pushed routing
# boundaries and stop rules out of the text — retired 2026-09-10 (the amendment in that EVALS section).
# Length = the YAML content (whitespace-normalized, block-scalar marker excluded), exactly what a client
# reads; bench/skilldesc_budget.py is the measurement and this gate's body.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
fail=0
ok()  { echo "  ok   $*"; }
no()  { echo "  FAIL $*"; fail=1; }

out="$( python3 "$ROOT/bench/skilldesc_budget.py" "$ROOT/skills" --limit=1024 2>&1 )"; rc=$?
summary="$( printf '%s\n' "$out" | tail -1 )"
printf '%s\n' "$out" | sed 's/^/    /'
[ "$rc" -eq 0 ] \
    && ok "every skill description is at or under Codex's 1,024-character hard limit" \
    || no "a skill description exceeds 1,024 characters — Codex rejects the skill outright ($summary)"

total="$( printf '%s' "$summary" | sed -n 's/.* total=\([0-9]*\).*/\1/p' )"
count="$( printf '%s' "$summary" | sed -n 's/.*skills=\([0-9]*\).*/\1/p' )"
[ -n "$total" ] && [ "$total" -le 5400 ] \
    && ok "set total ${total} chars over ${count} skills (ceiling 5400)" \
    || no "set total ${total:-?} chars exceeds the 5400 ceiling — the skills as a set crowd out every other skill the user installs"

# the measurement must agree with the gate's own notion of a description: a description written as a
# folded block scalar and the same text inline must measure identically (the > marker is not content)
tmp="$( mktemp -d )"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/a/ripwire-x" "$tmp/a/ripwire-y"
printf -- '---\nname: ripwire-x\ndescription: >\n  one two   three\n  four\n---\nbody\n' > "$tmp/a/ripwire-x/SKILL.md"
printf -- '---\nname: ripwire-y\ndescription: one two three four\n---\nbody\n' > "$tmp/a/ripwire-y/SKILL.md"
lens="$( python3 "$ROOT/bench/skilldesc_budget.py" "$tmp/a" --limit=1024 | awk 'NF==3{print $1}' | sort -u | tr '\n' ' ' )"
[ "$lens" = "18 " ] \
    && ok "block-scalar and inline descriptions measure identically (18 chars, marker excluded)" \
    || no "measurement disagrees between block-scalar and inline forms: '$lens'"

# the per-description arm must be able to go red: a synthetic 1,100-character description has to fail it
mkdir -p "$tmp/b/ripwire-z"
printf -- '---\nname: ripwire-z\ndescription: %s\n---\nbody\n' "$( printf 'x%.0s' $( seq 1 1100 ) )" > "$tmp/b/ripwire-z/SKILL.md"
python3 "$ROOT/bench/skilldesc_budget.py" "$tmp/b" --limit=1024 >/dev/null 2>&1 \
    && no "a 1,100-character description passed the 1,024 limit — the per-description arm cannot go red" \
    || ok "a 1,100-character description fails the 1,024 limit (the arm can go red)"

# the binary's own skill discovery must see the same set the measurement measured: --eval-skills reports
# K = candidate skills (ripwire-router excluded); a stub or stale binary, or a SKILL.md the binary cannot
# parse, breaks the agreement here rather than passing on the Python arm alone
k="$( "$BIN" "$ROOT/skills" --eval-skills="$ROOT/test/skillevalfix/prompts.tsv" --no-cache 2>/dev/null | sed -n 's/.*over K=\([0-9]*\) candidate skills.*/\1/p' | head -1 )"
[ -n "$k" ] && [ -n "$count" ] && [ "$k" -eq $(( count - 1 )) ] \
    && ok "the binary discovers K=${k} candidate skills = ${count} SKILL.md minus the router" \
    || no "the binary's --eval-skills sees K=${k:-?} candidate skills but the tree holds ${count:-?} SKILL.md (router excluded expects $(( ${count:-1} - 1 )))"

[ "$fail" -eq 0 ] && echo "skilldescbudgetcheck: ALL PASS" || echo "skilldescbudgetcheck: FAILURES"
exit "$fail"
