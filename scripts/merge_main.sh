#!/usr/bin/env bash
# merge_main.sh — merge main into the current branch, settle every conflict that has a mechanical answer,
# regenerate every binary-free generated file, and stop only on a real (content) conflict.
#
#   scripts/merge_main.sh                 # git fetch origin, then merge origin/main
#   scripts/merge_main.sh REF             # merge REF instead (no fetch unless REF is origin/…)
#   scripts/merge_main.sh --continue      # after resolving the conflicts it stopped on by hand and `git add`-ing them
#   scripts/merge_main.sh --sort-list     # only byte-sort test/regression.sh's absorb list
#
# What it settles (scripts/merge_resolve.py has the rules): the absorb list in test/regression.sh (a set
# merge of both sides' additions and removals, byte-sorted); lines a generator owns (`gatecount` markers,
# the README cap-inventory sentence, the whole of docs/LIMITS.md and docs/TUNING.md), whose values are then
# recomputed by the generators below rather than chosen; and files the binary's own output pins
# (test/printf_parity.manifest, docs/COMMANDS.md, docs/captures/*), which are listed as REGEN AFTER BUILD
# because their right bytes exist only once the merged tree is built. Everything else stays a conflict.
#
# Exit: 0 merged and committed, nothing left; 1 stopped on real conflicts (the merge is in progress: fix,
# `git add`, then --continue); 3 merged and committed, but the REGEN AFTER BUILD list must be regenerated
# after a build (commands printed); 2 usage or precondition error.
set -u
cd "$( git rev-parse --show-toplevel 2>/dev/null )" || { echo "merge_main: not inside a git work tree" >&2; exit 2; }
REF="origin/main"; mode=merge
REGEN_LOG="$( git rev-parse --git-path MERGE_MAIN_REGEN )"   # survives a stop for --continue
case "${1:-}" in
    --continue)  mode=continue ;;
    --sort-list) python3 scripts/merge_resolve.py --sort-list; exit $? ;;
    -h|--help)   sed -n '2,20p' "$0"; exit 0 ;;
    -*)          echo "merge_main: unknown option $1" >&2; exit 2 ;;
    "")          ;;
    *)           REF="$1" ;;
esac

regenerate() {
    # Binary-free generators, each followed by its own --check: a generator that ran but left a stale site is
    # a failure here, not a surprise in CI.
    local rc=0
    python3 docs/gatecount_build.py >/dev/null            || { echo "merge_main: docs/gatecount_build.py refused (see its message: python3 docs/gatecount_build.py)"; rc=1; }
    python3 docs/limits_build.py >/dev/null               || { echo "merge_main: docs/limits_build.py refused"; rc=1; }
    python3 bench/capsweep/capsweep.py emit >/dev/null    || { echo "merge_main: capsweep emit refused"; rc=1; }
    python3 docs/gatecount_build.py --check               || rc=1
    python3 docs/limits_build.py --check                  || rc=1
    python3 bench/capsweep/capsweep.py emit --check >/dev/null || { echo "merge_main: docs/TUNING.md is stale after capsweep emit"; rc=1; }
    bash -n test/regression.sh                            || { echo "merge_main: test/regression.sh does not parse"; rc=1; }
    python3 test/lib/gateregistry.py test/regression.sh   || rc=1
    git add -- README.md docs/EVALS.md present/deck5_ripwire_build.js docs/LIMITS.md docs/TUNING.md test/regression.sh
    return $rc
}

if [ "$mode" = merge ]; then
    git rev-parse -q --verify MERGE_HEAD >/dev/null && { echo "merge_main: a merge is already in progress — finish it with --continue or git merge --abort" >&2; exit 2; }
    [ -z "$( git status --porcelain --untracked-files=no )" ] || { echo "merge_main: the work tree has uncommitted changes — commit or stash them first" >&2; exit 2; }
    case "$REF" in origin/*) git fetch --quiet origin || { echo "merge_main: git fetch origin failed" >&2; exit 2; } ;; esac
    git rev-parse -q --verify "$REF^{commit}" >/dev/null || { echo "merge_main: $REF is not a commit" >&2; exit 2; }
    if git merge-base --is-ancestor "$REF" HEAD; then echo "merge_main: $REF is already merged"; exit 0; fi
    git -c merge.conflictStyle=diff3 merge --no-ff --no-commit "$REF" >/dev/null 2>&1
    if git rev-parse -q --verify MERGE_HEAD >/dev/null; then :; else echo "merge_main: git merge did not start (fast-forward refused or error)" >&2; exit 2; fi
    python3 scripts/merge_resolve.py | tee "$REGEN_LOG.all"; rrc=${PIPESTATUS[0]}
    grep '^REGEN ' "$REGEN_LOG.all" | sed 's/^REGEN //' > "$REGEN_LOG"; rm -f "$REGEN_LOG.all"
    [ "$rrc" = 2 ] && exit 2
    if [ "$rrc" = 1 ]; then
        echo "merge_main: STOPPED on real conflicts (above, left=N). Resolve them, git add, then: scripts/merge_main.sh --continue"
        exit 1
    fi
else
    git rev-parse -q --verify MERGE_HEAD >/dev/null || { echo "merge_main: --continue but no merge is in progress" >&2; exit 2; }
fi

unmerged="$( git diff --name-only --diff-filter=U )"
[ -z "$unmerged" ] || { echo "merge_main: still unmerged: $unmerged" >&2; exit 1; }
regenerate || { echo "merge_main: a generator or check failed — the merge is left uncommitted; fix and run --continue"; exit 1; }
git commit --no-edit --quiet || { echo "merge_main: git commit failed" >&2; exit 2; }
echo "merge_main: merged $( git rev-parse --short MERGE_HEAD 2>/dev/null || echo "$REF" ) as $( git rev-parse --short HEAD )"

# Files the binary pins whose conflict was settled by taking main's side: the right bytes need the merged build.
if [ -s "$REGEN_LOG" ]; then
    echo "merge_main: REGEN AFTER BUILD — these binary-pinned files took main's side of a conflict; build, regenerate, commit:"
    sed 's/^/    /' "$REGEN_LOG"
    grep -q 'printf_parity' "$REGEN_LOG" && echo "    UPDATE_GOLDEN=1 bash test/printffmtparitycheck.sh      # test/printf_parity.manifest"
    grep -q 'docs/' "$REGEN_LOG"         && echo "    python3 docs/docs_commands_build.py --help            # docs/COMMANDS.md and its capture (test/docscommandscheck.sh, test/showcasecapturecheck.sh)"
    rm -f "$REGEN_LOG"
    exit 3
fi
rm -f "$REGEN_LOG"
exit 0
