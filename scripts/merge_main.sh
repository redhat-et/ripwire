#!/usr/bin/env bash
# merge_main.sh — merge main into the current branch, settle every conflict that has a mechanical answer,
# regenerate every binary-free generated file, and stop on every other conflict for a person.
#
#   scripts/merge_main.sh                 # git fetch origin, then merge origin/main
#   scripts/merge_main.sh REF             # merge REF instead (no fetch unless REF is origin/…)
#   scripts/merge_main.sh --continue      # after resolving the conflicts it stopped on by hand and `git add`-ing them
#   scripts/merge_main.sh --sort-list     # only byte-sort test/regression.sh's absorb list
#   scripts/merge_main.sh --regen-after-build BIN   # after exit 3: build the merged tree, then re-record the files
#                                         # the merge commit marks REGEN AFTER BUILD from BIN, and commit them
#
# What it settles (scripts/merge_resolve.py has the rules): the absorb list in test/regression.sh (a set
# merge of both sides' additions and removals, byte-sorted), including once the old one-line list against the
# new one-name-per-line list; count lines in the gatecount site files whose sides differ only in a number a
# generator owns (any other digit, e.g. a hand-written "~210", stays a conflict) and the whole of
# docs/LIMITS.md and docs/TUNING.md, whose values are then recomputed by the generators below rather than
# chosen; and files the binary's own output pins
# (test/printf_parity.manifest, docs/COMMANDS.md, docs/captures/*), which are listed as REGEN AFTER BUILD
# because their right bytes exist only once the merged tree is built. Everything else stays a conflict.
# A merge that brings main's newer showcase capture marks it too, conflict or not (CAPTURE-DICTV-DRIFT, 2026-11-02):
# the capture's --legend-dict line records main's legend dictionary (dictv=, entries=), and a branch that adds a
# legend entry prints its own, so docscommandscheck (G) / showcasecapturecheck (I) go red after the merge.
# --regen-after-build BIN settles the marks of every merge since the last re-pin (a later merge with no marks
# does not hide an earlier one's), from BIN: the parity manifest with `UPDATE_GOLDEN=1 bash
# test/printffmtparitycheck.sh BIN`, keeping only labels whose pinned line differed between a marked merge's
# two parents (a label both parents agreed on that moves is refused and listed: that is the drift the gate
# exists to catch); the NEWEST capture's --legend-dict dictv=/entries= pair only (replaced wherever that exact
# pair is quoted: the capture, docs/COMMANDS.md, changelog.d/; no other capture bytes are re-recorded, and an
# older marked capture keeps main's side, being a record of an older binary that no gate compares with BIN),
# then `python3 docs/docs_commands_build.py --bin BIN`, which writes docs/COMMANDS.md, and its --check; then it
# commits what moved, naming every moved parity label in the message.
#
# The totals the docs publish (gate count, cap inventory, LIMITS/TUNING census) are the dated snapshot
# docs/counts.tsv and are not recomputed per branch, so two branches do not conflict on them;
# `python3 docs/counts_snapshot.py refresh` re-takes them (a maintainer step).
#
# Exit (--regen-after-build): 0 re-recorded and committed, or nothing marked; 1 a re-record or its check failed,
# nothing committed; 2 usage or precondition.
# Exit: 0 merged and committed, nothing left; 1 stopped on real conflicts, or --continue refused staged
# conflict markers, an unregistered gate file or a failed generator check (the merge is in progress: fix,
# `git add`, then --continue); 3 merged and committed, but the REGEN AFTER BUILD list must be regenerated
# after a build (commands printed, and the list is in the merge commit message); 2 usage, precondition or
# resolver error.
set -u
cd "$( git rev-parse --show-toplevel 2>/dev/null )" || { echo "merge_main: not inside a git work tree" >&2; exit 2; }
REF="origin/main"; mode=merge
REGEN_LOG="$( git rev-parse --git-path MERGE_MAIN_REGEN )"   # survives a stop for --continue
case "${1:-}" in
    --continue)  mode=continue ;;
    --sort-list) python3 scripts/merge_resolve.py --sort-list; exit $? ;;
    --regen-after-build)
                 mode=regen; RBIN="${2:-}"
                 [ -n "$RBIN" ] || { echo "merge_main: --regen-after-build needs the merged build's binary" >&2; exit 2; }
                 case "$RBIN" in /*) ;; *) RBIN="$OLDPWD/$RBIN" ;; esac ;;
    -h|--help)   awk 'NR > 1 && /^set -u$/ { exit } NR > 1' "$0"; exit 0 ;;
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
    # Shape AND membership, with the listing test/manifestcheck.sh builds (the set test/pargates.py runs): a gate
    # file kept by hand from a delete/modify conflict, or added on one side with its list line lost, is unregistered.
    local listing; listing="$( mktemp -t merge_main_ls.XXXXXX )" || { echo "merge_main: mktemp failed"; return 1; }
    # (a glob, not find -exec basename: ~760 forks took 48 s on a loaded machine; the glob skips dotfiles as find's ! -name '.*' does)
    local f; for f in test/*.sh; do [ -f "$f" ] && [ "$f" != test/regression.sh ] && { f="${f#test/}"; printf '%s\n' "${f%.sh}"; }; done | LC_ALL=C sort > "$listing"
    python3 test/lib/gateregistry.py test/regression.sh "$listing" || rc=1
    rm -f "$listing"
    git add -- README.md docs/EVALS.md present/deck5_ripwire_build.js docs/LIMITS.md docs/TUNING.md test/regression.sh
    return $rc
}

newestCapture(){ ls docs/captures/COMMANDS_showcase_*.md 2>/dev/null | LC_ALL=C sort | tail -1; }

if [ "$mode" = regen ]; then
    [ -x "$RBIN" ] || { echo "merge_main: $RBIN is not an executable" >&2; exit 2; }
    git rev-parse -q --verify MERGE_HEAD >/dev/null && { echo "merge_main: a merge is still in progress — finish it first" >&2; exit 2; }
    [ -z "$( git status --porcelain --untracked-files=no )" ] || { echo "merge_main: the work tree has uncommitted changes — commit or stash them first" >&2; exit 2; }
    # The marked lists are in the merge commits' messages (written there by this script; they survive a lost
    # terminal). Every merge on the first-parent chain since the last re-pin commit counts: a later merge with no
    # marks must not hide an earlier merge's pending ones. Bounded walk (200 commits).
    marked=""; markedMerges=""
    for c in $( git rev-list --first-parent -n 200 HEAD ); do
        subj="$( git show -s --format=%s "$c" )"
        case "$subj" in "Re-pin binary-pinned files"*|"Re-record binary-pinned files"*) break ;; esac
        git rev-parse -q --verify "$c^2" >/dev/null || continue
        m="$( git show -s --format=%B "$c" | sed -n '/^REGEN AFTER BUILD/,$p' | sed -n 's/^    //p' )"
        [ -n "$m" ] && { marked="$( printf '%s\n%s\n' "$marked" "$m" | grep . | LC_ALL=C sort -u )"; markedMerges="$markedMerges $c"; }
    done
    if [ -z "$marked" ]; then echo "merge_main: no merge since the last re-pin marks anything REGEN AFTER BUILD — nothing to re-record"; exit 0; fi
    rrc=0; movedLabels=""
    if printf '%s\n' "$marked" | grep -qx 'test/printf_parity.manifest'; then
        # labels a marked merge's two parents pinned differently (or only one pinned): the only ones a re-pin may move
        allowed="$( for c in $markedMerges; do
                        { git show "$c^1:test/printf_parity.manifest" 2>/dev/null; git show "$c^2:test/printf_parity.manifest" 2>/dev/null; } \
                            | LC_ALL=C sort | uniq -u | awk '{ print $1 }'
                    done | LC_ALL=C sort -u )"
        UPDATE_GOLDEN=1 bash test/printffmtparitycheck.sh "$RBIN" >/dev/null 2>&1 || { echo "merge_main: UPDATE_GOLDEN=1 bash test/printffmtparitycheck.sh $RBIN failed"; rrc=1; }
        movedLabels="$( { git show HEAD:test/printf_parity.manifest 2>/dev/null; cat test/printf_parity.manifest; } | LC_ALL=C sort | uniq -u | awk '{ print $1 }' | LC_ALL=C sort -u )"
        stray="$( printf '%s\n' "$movedLabels" | grep . | LC_ALL=C comm -23 - <( printf '%s\n' "$allowed" | grep . ) )"
        if [ -n "$stray" ]; then
            echo "merge_main: the re-pin moved parity label(s) both parents of the marked merge(s) pinned the same — refusing (the merged binary's output moved there; review it, then re-pin by hand with UPDATE_GOLDEN=1 and REVIEW THE DIFF):"
            printf '%s\n' "$stray" | sed 's/^/    /'
            rrc=1
        fi
        bash test/printffmtparitycheck.sh "$RBIN" >/dev/null 2>&1 || { echo "merge_main: test/printffmtparitycheck.sh is red after the re-pin"; rrc=1; }
    fi
    for oc in $( printf '%s\n' "$marked" | grep '^docs/captures/' ); do
        [ "$oc" = "$( newestCapture )" ] || echo "merge_main: $oc keeps main's side — an older capture records an older binary; only the newest capture's legend pair is compared with BIN (showcasecapturecheck (I))"
    done
    if printf '%s\n' "$marked" | grep -q '^docs/'; then
        cap="$( newestCapture )"
        old=""; live=""; lrc=0
        [ -n "$cap" ] && old="$( sed -n '/^## .*--legend-dict/,/^## /p' "$cap" | grep -oE 'dictv=[0-9a-f]+ entries=[0-9]+' | head -1 )"
        liveOut="$( "$RBIN" . --legend-dict 2>/dev/null )"; lrc=$?
        live="$( printf '%s\n' "$liveOut" | grep -oE 'dictv=[0-9a-f]+ entries=[0-9]+' | head -1 )"
        if [ -z "$cap" ] || [ -z "$old" ]; then echo "merge_main: no docs/captures/COMMANDS_showcase_*.md with a --legend-dict dictv=/entries= line"; rrc=1
        elif [ "$lrc" != 0 ] || [ -z "$live" ]; then echo "merge_main: '$RBIN . --legend-dict' failed (exit $lrc) or printed no dictv=/entries= line"; rrc=1
        elif [ "$old" != "$live" ]; then
            # the exact recorded pair, wherever it is quoted (the capture, docs/COMMANDS.md, a changelog fragment)
            git grep -lzF -e "$old" -- "$cap" docs/COMMANDS.md 'changelog.d/*.md' \
                | python3 -c '
import sys
old, new = sys.argv[ 1 ], sys.argv[ 2 ]
for p in [ x for x in sys.stdin.read().split( "\0" ) if x ]:
    t = open( p, encoding = "utf-8" ).read(); open( p, "w", encoding = "utf-8" ).write( t.replace( old, new ) )
    print( "merge_main: re-recorded %s -> %s in %s" % ( old, new, p ) )' "$old" "$live" || rrc=1
        fi
        python3 docs/docs_commands_build.py --bin "$RBIN" >/dev/null 2>&1 || { echo "merge_main: python3 docs/docs_commands_build.py --bin $RBIN failed"; rrc=1; }
        python3 docs/docs_commands_build.py --bin "$RBIN" --check >/dev/null 2>&1 || { echo "merge_main: docs/COMMANDS.md is stale after the regeneration (docs_commands_build --check)"; rrc=1; }
    fi
    if [ "$rrc" != 0 ]; then echo "merge_main: re-record failed — nothing committed; inspect git diff (git checkout -- . drops it)"; exit 1; fi
    moved="$( git status --porcelain --untracked-files=no | sed 's/^...//' )"
    if [ -z "$moved" ]; then echo "merge_main: the marked files already match $RBIN — nothing to commit"; exit 0; fi
    git add -u && git commit -q -m "Re-pin binary-pinned files from the merged build (parity labels, legend pair, COMMANDS.md)" \
        -m "scripts/merge_main.sh --regen-after-build, from: $( "$RBIN" --version 2>/dev/null | head -1 )" \
        -m "$( printf '%s\n' "$moved" | sed 's/^/    /' )" \
        -m "$( if [ -n "$movedLabels" ]; then printf 'parity labels re-pinned: %s' "$( printf '%s\n' $movedLabels | paste -sd' ' - )"; else printf 'parity labels re-pinned: none'; fi )" \
        || { echo "merge_main: git commit failed" >&2; exit 2; }
    echo "merge_main: committed $( git rev-parse --short HEAD ): re-pinned $( printf '%s ' $moved )${movedLabels:+(parity labels: $( printf '%s\n' $movedLabels | paste -sd' ' - ))}"
    exit 0
fi

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
    case "$rrc" in 0|1) ;; *) echo "merge_main: scripts/merge_resolve.py failed (exit $rrc) — the merge is in progress; inspect, or git merge --abort" >&2; exit 2 ;; esac
    if [ "$rrc" = 1 ]; then
        echo "merge_main: STOPPED on real conflicts (above, left=N). Resolve them, git add, then: scripts/merge_main.sh --continue"
        echo "            (not a plain git commit: --continue re-runs the generators, so the settled count lines get the merged values)"
        exit 1
    fi
else
    git rev-parse -q --verify MERGE_HEAD >/dev/null || { echo "merge_main: --continue but no merge is in progress" >&2; exit 2; }
fi

unmerged="$( git diff --name-only --diff-filter=U )"
[ -z "$unmerged" ] || { echo "merge_main: still unmerged: $unmerged" >&2; exit 1; }
regenerate || { echo "merge_main: a generator or check failed — the merge is left uncommitted; fix and run --continue"; exit 1; }
# `git add` clears a path's unmerged state whether or not its markers were removed: check the staged text itself.
# A path whose staged blob is MERGE_HEAD's own is main's text taken whole: whatever marker-shaped line it holds (an RST
# `=======` underline, test/restdocscheck.sh:77) is main's, not a leftover (MERGE-MAIN-RST-MARKER, 2026-11-03). Only the
# paths git flagged are looked up, and a path git printed quoted (an odd byte) is not found, so it stays reported.
markerHits=""
if git diff --cached --check HEAD | grep -q 'leftover conflict marker'; then
    for mp in $( git diff --cached --check HEAD | grep 'leftover conflict marker' | sed 's/:[0-9][0-9]*: leftover conflict marker.*$//' | LC_ALL=C sort -u ); do
        stagedBlob="$( git rev-parse -q --verify ":$mp" 2>/dev/null )"; mainBlob="$( git rev-parse -q --verify "MERGE_HEAD:$mp" 2>/dev/null )"
        [ -n "$stagedBlob" ] && [ "$stagedBlob" = "$mainBlob" ] && continue
        markerHits="$markerHits $mp"
    done
fi
if [ -n "$markerHits" ]; then
    for mp in $markerHits; do git diff --cached --check HEAD -- "$mp" | grep 'leftover conflict marker' | sed 's/^/    /' >&2; done
    echo "merge_main: conflict markers are still staged (git diff --cached --check HEAD, above) — the merge is left uncommitted; fix, git add, then --continue" >&2
    exit 1
fi
# Both sides bumped kParserVer past the merge base: the merged value must clear both, or a cache one side wrote under
# that number reads as the other's (MERGE-PARSERVER-CHECK, 2026-11-03). One side bumped, or neither: nothing to check.
parserVer(){ git show "$1:src/ingest_cache.h" 2>/dev/null | sed -n 's/^constexpr .*kParserVer *= *\([0-9][0-9]*\);.*$/\1/p' | head -1; }
pvLane="$( parserVer HEAD )"; pvMain="$( parserVer MERGE_HEAD )"; pvOut="$( parserVer "" )"
pvBaseRef="$( git merge-base HEAD MERGE_HEAD 2>/dev/null )"; pvBase=""   # (an empty ref would read the index)
[ -n "$pvBaseRef" ] && pvBase="$( parserVer "$pvBaseRef" )"
if [ -n "$pvLane" ] && [ -n "$pvMain" ] && [ -n "$pvOut" ] && [ -n "$pvBase" ] \
   && [ "$pvLane" -gt "$pvBase" ] && [ "$pvMain" -gt "$pvBase" ] && { [ "$pvOut" -le "$pvLane" ] || [ "$pvOut" -le "$pvMain" ]; }; then
    echo "merge_main: both sides bumped kParserVer: lane $pvLane, main $pvMain (merge base $pvBase), the merge has $pvOut — set it above both, e.g. max+2 = $(( (pvLane > pvMain ? pvLane : pvMain) + 2 )) for the rich pair (rich = kParserVer + 1), in src/ingest_cache.h, and update quality.h's kIngestParserVerMirror to match; git add both, then --continue (the merge is left uncommitted)" >&2
    exit 1
fi
# main brought a newer or changed showcase capture: its --legend-dict line records main's binary, not the merged one
# (CAPTURE-DICTV-DRIFT), so mark it for --regen-after-build whether or not it conflicted
if [ -n "$( git diff --cached --name-only HEAD -- docs/captures/ )" ]; then
    cap="$( newestCapture )"
    [ -n "$cap" ] && ! grep -qxF "$cap" "$REGEN_LOG" 2>/dev/null && printf '%s\n' "$cap" >> "$REGEN_LOG"
fi
mergedFrom="$( git rev-parse --short MERGE_HEAD )"
# The REGEN AFTER BUILD list goes into the merge commit too, so it survives a lost terminal.
commitMsg="$( git rev-parse --git-path MERGE_MSG )"
if [ -s "$REGEN_LOG" ] && [ -f "$commitMsg" ]; then
    { printf '\nREGEN AFTER BUILD (binary-pinned files that took main'"'"'s side; build, then scripts/merge_main.sh --regen-after-build BIN):\n'; sed 's/^/    /' "$REGEN_LOG"; } >> "$commitMsg"
fi
git commit --no-edit --quiet || { echo "merge_main: git commit failed" >&2; exit 2; }
echo "merge_main: merged $mergedFrom as $( git rev-parse --short HEAD )"

# Files the binary pins whose conflict was settled by taking main's side: the right bytes need the merged build.
if [ -s "$REGEN_LOG" ]; then
    echo "merge_main: REGEN AFTER BUILD — these binary-pinned files took main's side of a conflict; build, regenerate, commit:"
    sed 's/^/    /' "$REGEN_LOG"
    grep -q 'printf_parity' "$REGEN_LOG" && echo "    UPDATE_GOLDEN=1 bash test/printffmtparitycheck.sh      # test/printf_parity.manifest"
    grep -q 'docs/' "$REGEN_LOG"         && echo "    python3 docs/docs_commands_build.py --bin build/ripwire  # writes docs/COMMANDS.md (test/docscommandscheck.sh); the newest capture's --legend-dict pair needs --regen-after-build (test/showcasecapturecheck.sh (I))"
    echo "    or all of it at once: scripts/merge_main.sh --regen-after-build build/ripwire   # re-records, checks, commits"
    rm -f "$REGEN_LOG"
    exit 3
fi
rm -f "$REGEN_LOG"
exit 0
