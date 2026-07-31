#!/usr/bin/env bash
# qrevtokencheck.sh — r27 gate (Lane C routing): no unvalidated revision token may reach a git argv from the
# quality path.
#
# THE CLASS. `shSingleQuote` stops SHELL injection, but the token still arrives as its own argv ENTRY and git
# reads a leading `-` as an OPTION. That is precisely how the P0.1 `--pr-context=--output=FILE` defect
# TRUNCATED a file outside the repo and exited 0. Two instances in the quality path:
#   1. LIVE (low severity only because merge-base cannot write files): `readBaselineHeadSha` returned
#      `line.substr(5)` verbatim out of `.ctxpack_quality_baseline` — a COMMITTED file, therefore
#      attacker-influenceable on a cloned repo — straight into `git merge-base --is-ancestor '<sha>' …`.
#   2. LATENT: `git archive --format=tar '<committish>'` was built with no separator and no resolution, and
#      `git archive --output=` demonstrably does write a file. Every caller passes "HEAD" or a rev-list sha
#      today, so it is one careless caller from being the same bug.
#
# The defense is a bare-object-name gate (40/64 lowercase hex), applied at the trust boundary where the value
# is read AND again at the sink, plus resolving the archive revision through `rev-parse --verify` with a
# TRAILING `--` (a leading `--` would make git read the revision as a pathspec).
#
# Checks:
#   (a) a hostile `head` stamp in the sidecar (an option-shaped value, a path-shaped value, a `--output=`
#       payload) writes NOTHING outside the repo and the run stays well-behaved.
#   (b) the hostile pin is DISTRUSTED: the answer equals the no-sidecar (git-HEAD auto-baseline) answer.
#   (c) a LEGITIMATE pinned sha is still honored — the gate must not break the ordinary self-heal contract.
#   (d) source shape: gitIsAncestor guards both operands; materializeCommitTree resolves the revision and
#       passes a TRAILING `--`, never a leading one.
#
# Own temp repo. Needs git.
# Usage:  test/qrevtokencheck.sh   |   CTXPACK_BIN=build/ctxpack test/qrevtokencheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
QSRC="$ROOT/src/quality.h"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "  SKIP  qrevtokencheck (git not available)"; exit 0; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
REPO="$WORK/repo"; VICTIM="$WORK/victim.txt"
printf 'PRISTINE-VICTIM-CONTENT\n' > "$VICTIM"
VICTIM_BEFORE="$( cat "$VICTIM" )"

mkdir -p "$REPO/inc"
printf 'int seed( int a );\n' > "$REPO/inc/api.h"
printf 'int seed( int a ) { return a + 1; }\n' > "$REPO/lib.cpp"
( cd "$REPO" && git init -q && git config user.email t@t && git config user.name t \
  && git add -A >/dev/null && git commit -qm init >/dev/null )
run(){ ( cd "$REPO" && "$BIN" . --quality-delta --no-cache 2>/dev/null ); }
rc_of(){ ( cd "$REPO" && "$BIN" . --quality-delta --no-cache >/dev/null 2>&1; echo $? ); }

echo "qrevtokencheck: BIN=$BIN"

# a working-tree change so the report is non-empty in every phase below.
cat >> "$REPO/inc/api.h" <<'EOF'
int added( int a );
EOF

NOSIDECAR="$( run )"; NOSIDECAR_RC="$( rc_of )"
[ -n "$NOSIDECAR" ] && ok "baseline phase: the no-sidecar (git-HEAD) report is non-empty" || no "no-sidecar report empty — checks are vacuous"

# ── (a)(b) hostile `head` stamps ───────────────────────────────────────────────────────────────────────────
BASEF="$REPO/.ctxpack_quality_baseline"
for payload in "--output=$VICTIM" "-e" "--upload-pack=touch $WORK/pwned" "$WORK/../victim.txt" "HEAD; touch $WORK/pwned2"; do
    printf '# ctxpack quality baseline v2\nhead %s\nloc deadbeef 10\n' "$payload" > "$BASEF"
    OUT="$( run )"; RC="$( rc_of )"
    [ "$( cat "$VICTIM" )" = "$VICTIM_BEFORE" ] \
        && ok "hostile head stamp '$payload': the file outside the repo is untouched" \
        || no "hostile head stamp '$payload' MODIFIED a file outside the repo"
    { [ ! -e "$WORK/pwned" ] && [ ! -e "$WORK/pwned2" ]; } \
        && ok "hostile head stamp '$payload': no side-effect file created" \
        || { no "hostile head stamp '$payload' created a side-effect file"; rm -f "$WORK/pwned" "$WORK/pwned2"; }
    { [ "$RC" -eq 0 ] || [ "$RC" -eq 2 ]; } \
        && ok "hostile head stamp '$payload': run stays well-behaved (exit $RC)" \
        || no "hostile head stamp '$payload': unexpected exit $RC"
done

# The tampered sidecar must be DISTRUSTED: it routes into the existing unreachable-pin self-heal, so the
# FINDINGS equal the no-sidecar git-HEAD answer, and the header says out loud that the sidecar was removed
# (never a silent substitution — the baseline= marker is the audit trail).
printf '# ctxpack quality baseline v2\nhead --output=%s\nloc deadbeef 10\n' "$VICTIM" > "$BASEF"
TAMPERED="$( run )"
rows_of(){ printf '%s' "$1" | tr '<' '\n' | grep '^r kind='; }
[ "$( rows_of "$TAMPERED" )" = "$( rows_of "$NOSIDECAR" )" ] \
    && ok "a tampered head stamp is distrusted — the findings equal the no-sidecar git-HEAD answer" \
    || { no "a tampered head stamp changed the findings"; rows_of "$TAMPERED" | head -3; }
printf '%s' "$TAMPERED" | grep -q 'baseline="git-HEAD (stale sidecar removed)"' \
    && ok "the tampered sidecar is self-healed away and the header says so (auditable, not silent)" \
    || { no "the tampered sidecar was not reported as removed"; printf '%s' "$TAMPERED" | tr '<' '\n' | grep '^quality-delta'; }

# ── (c) a LEGITIMATE pin still works ───────────────────────────────────────────────────────────────────────
rm -f "$BASEF"
( cd "$REPO" && "$BIN" . --quality-baseline --no-cache >/dev/null 2>&1 )
PINNED="$( sed -n 's/^head //p' "$BASEF" )"
case "$PINNED" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f]*) ok "--quality-baseline still writes a bare sha pin ($PINNED)";;
    *) no "--quality-baseline wrote a non-sha pin: '$PINNED'";;
esac
LEGIT_RC="$( rc_of )"
{ [ -f "$BASEF" ] && { [ "$LEGIT_RC" -eq 0 ] || [ "$LEGIT_RC" -eq 2 ]; }; } \
    && ok "a legitimate pinned sha is honored (sidecar survives, exit $LEGIT_RC — no false self-heal)" \
    || no "a legitimate pin was self-healed away (exit $LEGIT_RC) — the gate is too strict"

# ── (d) source shape ───────────────────────────────────────────────────────────────────────────────────────
awk '/^inline bool gitIsAncestor\(/,/^}/' "$QSRC" | grep -q 'isBareCommitSha( ancestor )' \
    && ok "gitIsAncestor guards its operands with isBareCommitSha at the sink" \
    || no "gitIsAncestor does not guard its operands — a future caller can reintroduce the hole"
MAT="$( awk '/^inline std::string materializeCommitTree\(/,/^}/' "$QSRC" )"
printf '%s' "$MAT" | grep -q 'gitResolveCommitSha( root, committish )' \
    && ok "materializeCommitTree resolves the revision through rev-parse --verify" \
    || no "materializeCommitTree still passes the caller's raw committish to git archive"
printf '%s' "$MAT" | grep -q 'shSingleQuote( rev ) + " -- ' \
    && ok "git archive gets a TRAILING -- separator (a leading one would make the revision a pathspec)" \
    || no "git archive has no trailing -- separator"
printf '%s' "$MAT" | grep -q 'archive --format=tar -- ' \
    && no "git archive has a LEADING -- : git would read the revision as a pathspec and archive nothing" \
    || ok "git archive has no leading -- (the revision is still a revision)"

# and the archive path still WORKS (the auto-HEAD baseline is built through it).
rm -f "$BASEF"
AUTO="$( run )"
printf '%s' "$AUTO" | grep -q 'baseline="git-HEAD"' \
    && ok "the git-archive HEAD-snapshot path still works after the -- change" \
    || { no "the HEAD-snapshot path broke — git archive returned nothing"; printf '%s' "$AUTO" | head -c 300; }

[ "$fail" -eq 0 ] && echo "qrevtokencheck: ALL PASS" || { echo "qrevtokencheck: SOME CHECKS FAILED"; exit 1; }
