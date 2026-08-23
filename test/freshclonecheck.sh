#!/usr/bin/env bash
# freshclonecheck.sh — the FRESH-CLONE battery arm named (but not built) by the CI-green round
# (PLAN_HARVEST_REPORTS_2026-08-20/ci-green-lane.md, "Why local diverged"): our own battery only ever
# runs inside a configured, long-lived developer worktree, so it samples exactly ONE value of every input
# that is actually AMBIENT — a developer's git config, a fixture's inherited branch name, the checkout's
# own absolute path length — and can never see the variance that flips CI red with no code change. This
# is the arm that would have caught it: it builds nothing, clones the repo's own HEAD into a genuinely
# fresh, unconfigured checkout, and re-runs a small subset of the gates whose PAST failures were exactly
# that class of bug.
#
# THE SUBSET, chosen for a documented environment-shaped failure each, not swept in from the full ~450:
#   qdrefpaircheck     — Class 1 (ci-green-lane.md): the short-horizon-churn facet read `git blame`
#                         through a developer's `blame.ignoreRevsFile`, which a fresh clone never sets
#                         (nobody has run the file's own "enable once per clone" instruction there). Also
#                         exercises the `diff.algorithm`/`diff.external` pin from the same class.
#   fornotesbudgetcheck — Class 4: its throwaway `git init` fixture inherited `init.defaultBranch` from
#                         whatever the MACHINE default happens to be; a fresh clone's git config is the
#                         machine's real ambient default, the same one a CI runner supplies — unlike a
#                         long-lived worktree, which has whatever branch name it was created with baked
#                         into old fixtures/muscle memory, never re-derived.
#   grepbytescheck      — this lane's own fix: median payload reduction vs `grep -rn` used to be a
#                         function of the checkout's absolute path LENGTH (19.7%/37.4%/55.9% at 9/49/125
#                         chars against a hard 30% bar). A fresh clone's path is whatever the CLONE
#                         target directory happens to be named, exactly the uncontrolled input the bug
#                         lived in — the gate's own fix (pin the corpus to a fixed $TMP-relative copy) is
#                         re-proven here by construction: it passes regardless of where this script's own
#                         $TMP happens to land.
# Left OUT, deliberately, to hit the time budget: the format gate (scripts/formatcheck.sh, not a
# test/*check.sh, wired into the battery separately per the round's own recommendation #2) and the wider
# churn/co-change family (qchurncheck, cochangeboostcheck, …) — qdrefpaircheck already exercises the git-
# config-sensitive code path they share, and running the whole family here would blow the budget without
# adding a new FAILURE CLASS, only more instances of one already covered.
#
# BUDGET: kept under ~120s on a laptop — a `--depth 1` clone of this repo runs ~3s, and the three gates
# together run ~30-35s warm (measured on this lane: qdrefpaircheck ~20s, grepbytescheck ~8s,
# fornotesbudgetcheck ~3s). No build happens here: RIPWIRE_BIN (or $1) names an ALREADY-BUILT binary,
# reused as-is inside the clone — the clone supplies fresh SOURCE/git state, not a fresh binary.
#
# Usage:
#   test/freshclonecheck.sh                          # uses build/ripwire
#   RIPWIRE_BIN=asan/ripwire test/freshclonecheck.sh
# Exits non-zero if the clone fails, or any of the three subset gates fails inside it.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "freshclonecheck: git required"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "freshclonecheck: BIN=$BIN"

# ── clone HEAD, depth 1 — a genuinely unconfigured checkout, no ambient repo-local git config carried
#    over (blame.ignoreRevsFile, ad-hoc branch names, cache state) and no build/ directory at all. Uses
#    file:// so this stays a pure git operation, no network, and reproducible offline.
CLONE="$TMP/freshclone"
START="$( date +%s )"
if git clone --quiet --depth 1 "file://$ROOT" "$CLONE" 2>"$TMP/clone.err"; then
    ok "fresh clone of HEAD ($( git -C "$ROOT" rev-parse --short HEAD )) into an unconfigured checkout"
else
    no "git clone --depth 1 file://\$ROOT failed:"
    sed 's/^/    /' "$TMP/clone.err"
    echo "freshclonecheck: FAILURES"
    exit 1
fi
[ -d "$CLONE/test" ] && [ -d "$CLONE/src" ] \
    && ok "clone has the expected tree (test/, src/)" \
    || { no "clone is missing test/ or src/ — something is wrong with the clone itself"; echo "freshclonecheck: FAILURES"; exit 1; }
[ -d "$CLONE/build" ] \
    && no "clone has a build/ directory — this gate is supposed to build NOTHING (fix the .gitignore assumption if this fires)" \
    || ok "no build/ directory in the clone (nothing was built — the invoking binary is reused via RIPWIRE_BIN)"

# ── the subset, run FROM INSIDE the clone (so each gate's own $ROOT-derivation resolves to the fresh
#    checkout, not this one) but pointed at the ALREADY-BUILT binary passed in above ──────────────────
SUBSET="qdrefpaircheck fornotesbudgetcheck grepbytescheck"
for g in $SUBSET; do
    GS="$CLONE/test/$g.sh"
    [ -f "$GS" ] || { no "$g.sh is not present in the fresh clone (renamed/moved without updating this gate's subset list)"; continue; }
    t0="$( date +%s )"
    if RIPWIRE_BIN="$BIN" bash "$GS" >"$TMP/$g.out" 2>&1; then
        t1="$( date +%s )"
        ok "$g (fresh clone, $(( t1 - t0 ))s) — same verdict as the configured worktree"
    else
        t1="$( date +%s )"
        no "$g FAILED inside a fresh clone (worktree-only green — exactly the disease this arm exists to catch), $(( t1 - t0 ))s:"
        tail -n 15 "$TMP/$g.out" | sed 's/^/    /'
    fi
done

END="$( date +%s )"
ELAPSED=$(( END - START ))
if [ "$ELAPSED" -le 120 ]; then
    ok "total wall time ${ELAPSED}s (budget: ~120s)"
else
    no "total wall time ${ELAPSED}s exceeded the ~120s budget — the subset needs trimming, not the budget widening (see this file's own header on why the subset stays small)"
fi

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
