#!/usr/bin/env bash
# gitenvhermeticcheck.sh — a gate that builds a throwaway git repository must not let the CALLER's
# environment choose which repository it actually talked to.
#
# WHY THIS FILE EXISTS. `git -C DIR` changes the working DIRECTORY. It does not override the
# ENVIRONMENT, and GIT_DIR / GIT_WORK_TREE / GIT_COMMON_DIR / GIT_INDEX_FILE / GIT_OBJECT_DIRECTORY /
# GIT_ALTERNATE_OBJECT_DIRECTORIES / GIT_PREFIX all outrank it. So
#     REPO="$( mktemp -d )"; git -C "$REPO" init -q; …; HEADSHA="$( git -C "$REPO" rev-parse HEAD )"
# hands back a sha from SOMEBODY ELSE'S repository whenever one of those is exported — a git hook
# running the suite, a CI job that set GIT_DIR, `git rebase --exec`, a shell inside `git filter-branch`.
# The gate then passes or fails on data it never selected, which is worse than a red: it is a green that
# measured the wrong tree. `git init` is affected too (with GIT_DIR set it initialises THERE).
#
# It is the #298 story a second time. Two gates had already found this independently and hand-rolled a
# fix at the call site — dispatchordercheck (GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE) and pagingsweepcheck
# (the same three plus GIT_COMMON_DIR) — and NEITHER copy carried the object-directory names. Two
# partial copies and 155 unprotected siblings is exactly the shape that made #298 centralise the
# agent-home variables, so the git names went into the same helper, test/lib/clean-env.sh, rather than
# into a 156th copy.
#
# ARMS
#   (A) LIVENESS — the defect is real HERE, on this git, not merely in the documentation. Two throwaway
#       repositories with different HEADs; `git -C <fixture> rev-parse HEAD` is asked once with GIT_DIR
#       aimed at the OTHER one. It must answer the OTHER repository's sha. If this git ever stops
#       honouring GIT_DIR over -C the gate cannot conclude anything and exits 2 rather than pass
#       vacuously — (B) and (C) would both be green for the wrong reason.
#   (B) THE FIX — the identical call, in a shell that sourced test/lib/clean-env.sh first, must answer
#       the FIXTURE's own sha. (A) and (B) differ in exactly one thing: the source line.
#   (C) THE LIST — every name (A) can be run against must actually appear in the helper's unset lines.
#       The list is derived from the helper and compared with the pinned set below, so adding a name to
#       one without the other is a red, and the agent-home family #298 introduced is pinned the same way
#       (this gate is the only place both families are written down together).
#   (D) THE SWEEP — every test/*.sh that initialises a git repository must source the helper. The
#       population is derived, never pinned as a number: a gate that starts building a repo tomorrow is
#       in it automatically. A CONTROL copies one real gate, strips its source line, and requires the
#       same classifier to flag the copy — without it (D) would pass on a tree where nothing is
#       detectable.
#
# Usage: bash test/gitenvhermeticcheck.sh [ripwire-binary]   (the binary is accepted and unused: this is
# a harness-hygiene gate, and every gate in regression.sh is called with it.)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
HELPER="$ROOT/test/lib/clean-env.sh"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -f "$HELPER" ] || { echo "gitenvhermeticcheck: no helper at $HELPER"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "gitenvhermeticcheck: git missing (gate cannot run)"; exit 2; }

echo "gitenvhermeticcheck: HELPER=$HELPER"

mkrepo(){ # $1 = dir, $2 = file content; echoes the resulting HEAD sha
    mkdir -p "$1"
    git -C "$1" init -q
    git -C "$1" config user.email gate@example.invalid
    git -C "$1" config user.name gate
    printf '%s\n' "$2" > "$1/f.txt"
    git -C "$1" add -A
    git -C "$1" commit -qm "$2"
    git -C "$1" rev-parse HEAD
}

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== (A) LIVENESS: git -C is overridden by GIT_DIR on this git ==="
# ═══════════════════════════════════════════════════════════════════════════
OTHERSHA="$( mkrepo "$TMP/other" theirs )"
FIXSHA="$(   mkrepo "$TMP/fix"   ours   )"
[ -n "$OTHERSHA" ] && [ -n "$FIXSHA" ] && [ "$OTHERSHA" != "$FIXSHA" ] \
    || { echo "gitenvhermeticcheck: could not build two distinct throwaway repos — cannot conclude"; exit 2; }

LEAKED="$( GIT_DIR="$TMP/other/.git" git -C "$TMP/fix" rev-parse HEAD 2>/dev/null )"
if [ "$LEAKED" = "$OTHERSHA" ]; then
    ok "(A) with GIT_DIR set, \`git -C <fixture> rev-parse HEAD\` answers the OTHER repo (${OTHERSHA%%??????????????????????????????}…) — the defect is live"
elif [ "$LEAKED" = "$FIXSHA" ]; then
    echo "gitenvhermeticcheck: this git ignores GIT_DIR in favour of -C, so (B) and (D) would be green"
    echo "                     for the wrong reason. Cannot conclude — exiting 2 rather than passing."
    exit 2
else
    echo "gitenvhermeticcheck: the GIT_DIR probe answered neither repo ('$LEAKED') — cannot conclude"
    exit 2
fi

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== (B) THE FIX: the same call, after sourcing the helper, answers the fixture ==="
# ═══════════════════════════════════════════════════════════════════════════
# Run in a CHILD shell so the export is real and the source line is the only difference from (A).
FIXED="$( GIT_DIR="$TMP/other/.git" sh -c '. "$1" ; git -C "$2" rev-parse HEAD' sh "$HELPER" "$TMP/fix" 2>/dev/null )"
[ "$FIXED" = "$FIXSHA" ] \
    && ok "(B) after sourcing test/lib/clean-env.sh the same call answers the FIXTURE's own sha" \
    || no "(B) the helper did not restore the fixture's sha: got '$FIXED', want '$FIXSHA'"

# Every git-selecting name, not just GIT_DIR: each must be neutralised on its own. GIT_PREFIX and the
# object directories cannot flip a rev-parse, so they are asserted to be CLEARED rather than to change an
# answer — a weaker claim, stated as the weaker claim rather than dressed up as a behavioural one.
for V in GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PREFIX; do
    SEEN="$( env "$V=/nonexistent/leak" sh -c '. "$1" ; eval "printf %s \"\${$2-<unset>}\""' sh "$HELPER" "$V" 2>/dev/null )"
    [ "$SEEN" = "<unset>" ] \
        && ok "(B) $V is cleared by the helper" \
        || no "(B) $V survived the helper as '$SEEN'"
done

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== (C) THE LIST: the helper clears exactly the pinned names ==="
# ═══════════════════════════════════════════════════════════════════════════
PINNED="AGENTS_HOME CLAUDE_CONFIG_DIR CODEX_HOME GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_PREFIX GIT_WORK_TREE HERMES_HOME OPENCLAW_STATE_DIR RIPWIRE_DATA_HOME"
DERIVED="$( grep -E '^unset ' "$HELPER" | sed 's/^unset //' | tr ' ' '\n' | grep -v '^$' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ *$//' )"
[ "$DERIVED" = "$PINNED" ] \
    && ok "(C) the helper's unset lines name exactly the pinned set ($( printf '%s' "$PINNED" | wc -w | tr -d ' ' ) variables, both families)" \
    || no "(C) the helper's list drifted from the pin. derived={$DERIVED} pinned={$PINNED}"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== (D) THE SWEEP: every gate that builds a git repo sources the helper ==="
# ═══════════════════════════════════════════════════════════════════════════
# Population derived, never pinned: whatever initialises a repo today is in scope today.
sources_helper(){ grep -qE '^[[:space:]]*\.[[:space:]]+.*lib/clean-env\.sh' "$1"; }
builds_repo(){    grep -qE 'git (-C [^ ]+ )?init' "$1"; }

pop=0; bad=""
for g in "$ROOT"/test/*.sh; do
    builds_repo "$g" || continue
    pop=$(( pop + 1 ))
    sources_helper "$g" || bad="$bad $( basename "$g" )"
done
[ "$pop" -gt 0 ] \
    || { echo "gitenvhermeticcheck: the sweep found ZERO gates building a repo — the classifier broke"; exit 2; }
[ -z "$bad" ] \
    && ok "(D) all $pop gate(s) that initialise a git repository source test/lib/clean-env.sh" \
    || no "(D) $pop gate(s) build a repo;$bad do not source test/lib/clean-env.sh"

# CONTROL: strip the source line from a copy of a real member and require the classifier to flag it.
CTRL_SRC="$ROOT/test/qsnapproducercheck.sh"
if [ -f "$CTRL_SRC" ]; then
    grep -vE '^[[:space:]]*\.[[:space:]]+.*lib/clean-env\.sh' "$CTRL_SRC" > "$TMP/ctrl.sh"
    if builds_repo "$TMP/ctrl.sh" && ! sources_helper "$TMP/ctrl.sh"; then
        ok "(D) control: a copy of qsnapproducercheck.sh with its source line stripped IS flagged — the sweep discriminates"
    else
        no "(D) control: the stripped copy was not flagged; the sweep cannot detect the defect it reports"
    fi
else
    no "(D) control source test/qsnapproducercheck.sh is missing — the control cannot run"
fi

echo
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
