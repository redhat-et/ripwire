#!/usr/bin/env bash
# mergechurncheck.sh — the MERGE-COMMIT history gate: content introduced by a merge commit ITSELF must be
# mined, and ordinary merged-branch work must NOT be counted twice.
#
# THE DEFECT (carried in from capture-audit-4, deferred into PLAN_h4QualifiedCalls_2026-07-30.md's round
# because the fix moves churn counts corpus-wide). Every history miner here runs `git log --name-only`, and
# with no --diff-merges mode git prints NO paths at all for a merge commit. So a file whose only history is a
# merge commit — an "evil merge": a conflict resolved by writing content neither parent had, or a file added
# while resolving — has zero history lines anywhere in the stream. It read churn=0, it was missing from
# --owners entirely, and nothing disclosed it: a measured-looking zero. Measured on the ripwire repo itself
# before the fix: 2 of 1028 tracked paths (IDEAS_fieldNotes_2026-07-25.md, NEXT_SESSION_2026-07-26.md) had
# no --owners row at all while being ordinary, present, tracked files.
#
# THE FIX, and why THIS shape (measured, not chosen by taste — the numbers are this fixture's, re-derivable
# by running the variants against it):
#
#   variant                      branchfile.cpp   mergeonly.cpp   shared.cpp   ripwire-repo path-lines
#                                (truth: 3)       (truth: 1)      (truth: 4)   (baseline 3618)
#   ------------------------------------------------------------------------------------------------
#   today (no flag)              3  ok            0  MISSING      3  MISSING   3618
#   -m                           4  DOUBLE        2  DOUBLE       5  DOUBLE    7026  (+94%)
#   --diff-merges=first-parent   4  DOUBLE        1  ok           4  ok        4811  (+33%)
#   --first-parent               1  LOST          1  ok           3  MISSING   3289  (-9%, 3 paths lost)
#   -c  (combined)               3  ok            1  ok           4  ok        3817  (+5.5%, 2 paths recovered)
#
# `-c` lists, for a merge, exactly the files that differ from EVERY parent — precisely "what this merge itself
# did", and nothing else. Bare `-m` diffs the merge against each parent in turn, so every ordinary merged
# branch commit's work is counted a second time inside the merge; `--diff-merges=first-parent` does the same
# for the first parent's side; `--first-parent` stops walking branch commits at all and DEFLATES them.
#
# The contract this gate pins:
#   1. A file introduced by a merge commit alone has its real churn and a real --owners row (attributed to the
#      merge's author), on --hotspots, --owners and --for's churn= lens.
#   2. A conflict resolved with new content in the merge counts that merge for the resolved file.
#   3. Ordinary merged-branch work is counted ONCE — never once per parent (the -m trap).
#   4. Files untouched by any merge are byte-for-byte unmoved.
#   5. The tool's numbers re-derive from THE SAME command the tool runs (trap #12: `git log -- <path>` applies
#      history simplification and answers a different question — it SELECTS the merge but prints no path for it).
#
# EXPIRY NOTE: like test/churnjoincheck.sh, this fixture hardcodes 2026-06 commit dates and --hotspots mines a
# wall-clock "12 months ago" window, so both gates go quiet together after 2027-06. Fix them as a pair.
#
# Usage:  test/mergechurncheck.sh              # build/ripwire
#         test/mergechurncheck.sh asan/ripwire # positional seam
#         RIPWIRE_BIN=asan/ripwire test/mergechurncheck.sh   # env seam
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"       # BOTH seams — positional and env
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }
echo "mergechurncheck: BIN=$BIN  ROOT=$ROOT"

TMP="$( mktemp -d )"; R1="$( mktemp -d )"
trap 'rm -rf "$TMP" "$R1"' EXIT

# a C++ file with one function of non-zero cognitive complexity (so --hotspots ranks it at all)
mkfn(){ printf 'int %s( int x )\n{\n    if( x > 1 ) return x + 1;\n    return x - 1;\n}\n' "$1"; }
D(){ export GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1"; }
C(){ git -C "$R1" add -A >/dev/null; git -C "$R1" commit -qm "$1"; }
# attr_of FILE PATHSUFFIX ATTR — the ATTR value of the row whose p= ends with PATHSUFFIX ("" if no such row)
attr_of(){ tr '>' '\n' < "$1" | grep -F "$2\"" | grep -oE "$3=\"[^\"]*\"" | head -1 | sed 's/^[^"]*"//; s/"$//'; }

# ── the fixture: ONE evil merge over an ordinary merged branch ───────────────────────────────────────
# History, read commit by commit (these readings ARE the literals asserted below — never computed from the
# tool, never from the same git flag the code uses):
#   b1    base@x.com   creates base.cpp, shared.cpp
#   s1..s3 side@x.com  on branch `side`: creates then twice appends branchfile.cpp   -> branchfile.cpp = 3
#   s4    side@x.com   on branch `side`: appends shared.cpp
#   m2    base@x.com   on main: appends base.cpp                                     -> base.cpp       = 2 (b1, m2)
#   m3    base@x.com   on main: appends shared.cpp  (conflicts with s4)
#   MERGE merger@x.com merges `side`, resolves shared.cpp by REWRITING it, and adds mergeonly.cpp
#                                        -> shared.cpp = 4 (b1, s4, m3, MERGE);  mergeonly.cpp = 1 (MERGE)
mkdir -p "$R1"
git -C "$R1" init -q -b main
git -C "$R1" config user.email base@x.com; git -C "$R1" config user.name Basedev
mkfn baseFn   > "$R1/base.cpp"
mkfn sharedFn > "$R1/shared.cpp"
D 2026-06-01T12:00:00; C b1

git -C "$R1" checkout -q -b side
git -C "$R1" config user.email side@x.com; git -C "$R1" config user.name Sidedev
mkfn branchFn > "$R1/branchfile.cpp"
D 2026-06-02T12:00:00; C s1
printf '// s2\n' >> "$R1/branchfile.cpp"; D 2026-06-03T12:00:00; C s2
printf '// s3\n' >> "$R1/branchfile.cpp"; D 2026-06-04T12:00:00; C s3
printf '// side edit\n' >> "$R1/shared.cpp"; D 2026-06-05T12:00:00; C s4

git -C "$R1" checkout -q main
git -C "$R1" config user.email base@x.com; git -C "$R1" config user.name Basedev
printf '// m2\n' >> "$R1/base.cpp";   D 2026-06-06T12:00:00; C m2
printf '// main edit\n' >> "$R1/shared.cpp"; D 2026-06-07T12:00:00; C m3

git -C "$R1" config user.email merger@x.com; git -C "$R1" config user.name Mergedev
D 2026-06-08T12:00:00
git -C "$R1" merge --no-commit --no-ff side >/dev/null 2>&1 || true   # conflicts on shared.cpp by construction
mkfn mergeOnlyFn > "$R1/mergeonly.cpp"
mkfn sharedFn    > "$R1/shared.cpp"; printf '// resolved in the merge itself\n' >> "$R1/shared.cpp"
C "merge side (evil: adds mergeonly.cpp, rewrites shared.cpp)"
unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE

# the fixture must actually BE what the literals describe — a two-parent merge, or every assertion below is
# measuring the wrong repo (a silently fast-forwarded "merge" would make this gate pass for the wrong reason)
PARENTS="$( git -C "$R1" log -1 --format=%P HEAD | wc -w | tr -d ' ' )"
[ "$PARENTS" = 2 ] && ok "fixture: HEAD is a real two-parent merge commit" \
    || no "fixture: HEAD has $PARENTS parent(s), want 2 — the merge fast-forwarded and this gate would be vacuous"

# ── 1. --hotspots churn: the recovered file, the recovered resolution, and the NOT-doubled branch work ──
"$BIN" "$R1" --hotspots --limit=50 > "$TMP/h.out" 2>"$TMP/h.err"
C_MERGEONLY="$( attr_of "$TMP/h.out" /mergeonly.cpp churn )"
C_SHARED="$(    attr_of "$TMP/h.out" /shared.cpp    churn )"
C_BRANCH="$(    attr_of "$TMP/h.out" /branchfile.cpp churn )"
C_BASE="$(      attr_of "$TMP/h.out" /base.cpp      churn )"

[ "$C_MERGEONLY" = 1 ] && ok "--hotspots: mergeonly.cpp is RANKED with churn=1 (its only history is the merge)" \
    || no "--hotspots: mergeonly.cpp churn='$C_MERGEONLY', want 1 (empty = the file has no row at all: a merge-only file read as churn=0 and dropped out of the ranking)"
[ "$C_SHARED" = 4 ] && ok "--hotspots: shared.cpp churn=4 — the merge's own conflict resolution counts" \
    || no "--hotspots: shared.cpp churn='$C_SHARED', want 4 (b1, s4, m3, MERGE)"
[ "$C_BRANCH" = 3 ] && ok "--hotspots: branchfile.cpp churn=3 — merged-branch work counted ONCE, not once per parent" \
    || no "--hotspots: branchfile.cpp churn='$C_BRANCH', want 3 (4 = the bare '-m' double-count; 1 = --first-parent dropped the branch commits)"
[ "$C_BASE" = 2 ] && ok "--hotspots: base.cpp churn=2 — a file no merge touched is unmoved" \
    || no "--hotspots: base.cpp churn='$C_BASE', want 2"

# ── 2. --owners: the merge's author owns what the merge introduced ───────────────────────────────────
"$BIN" "$R1" --owners --detail=1 --limit=50 > "$TMP/o.out" 2>/dev/null
O_MERGEONLY="$( attr_of "$TMP/o.out" /mergeonly.cpp top )"
A_SHARED="$(    attr_of "$TMP/o.out" /shared.cpp    authors )"
O_BRANCH="$(    attr_of "$TMP/o.out" /branchfile.cpp top )"
A_BRANCH="$(    attr_of "$TMP/o.out" /branchfile.cpp authors )"

[ "$O_MERGEONLY" = "merger@x.com" ] && ok "--owners: mergeonly.cpp HAS a row, owned by the merge's author" \
    || no "--owners: mergeonly.cpp top='$O_MERGEONLY', want merger@x.com (empty = no row: the file is missing from --owners entirely)"
[ "$A_SHARED" = 3 ] && ok "--owners: shared.cpp has 3 authors — the merger is one of them" \
    || no "--owners: shared.cpp authors='$A_SHARED', want 3 (base, side, merger)"
[ "$O_BRANCH" = "side@x.com" ] && [ "$A_BRANCH" = 1 ] \
    && ok "--owners: branchfile.cpp still has exactly its ONE branch author (the merger is not folded in)" \
    || no "--owners: branchfile.cpp top='$O_BRANCH' authors='$A_BRANCH', want side@x.com / 1"

# ── 3. --for's churn= quality lens rides the OTHER miner (resolveCommitStream + the qchurn memo) ──────
"$BIN" "$R1" --for="mergeOnlyFn branchFn" > "$TMP/f.out" 2>/dev/null
F_MERGE="$( tr '>' '\n' < "$TMP/f.out" | grep -F 'n="mergeOnlyFn"' | grep -oE 'churn="[0-9]+"' | head -1 | tr -cd '0-9' )"
F_BRANCH="$( tr '>' '\n' < "$TMP/f.out" | grep -F 'n="branchFn"'   | grep -oE 'churn="[0-9]+"' | head -1 | tr -cd '0-9' )"
[ "$F_MERGE" = 1 ] && ok "--for churn=: mergeOnlyFn's file carries churn=1" \
    || no "--for churn= for mergeOnlyFn is '$F_MERGE', want 1 (empty = no churn attribute at all — the second miner is still merge-blind)"
[ "$F_BRANCH" = 3 ] && ok "--for churn=: branchFn's file is 3, not doubled" \
    || no "--for churn= for branchFn is '$F_BRANCH', want 3"

# ── 4. the ORACLE, re-derived with THE SAME command the code runs (trap #12) ─────────────────────────
# `git log -- <path>` applies history simplification and answers a DIFFERENT question; this asserts both
# halves so a future reader cannot "fix" the oracle into the wrong one.
ORACLE_MERGEONLY="$( git -c core.quotepath=false -C "$R1" log -c --name-only --format= 2>/dev/null | grep -cx mergeonly.cpp )"
ORACLE_BRANCH="$(    git -c core.quotepath=false -C "$R1" log -c --name-only --format= 2>/dev/null | grep -cx branchfile.cpp )"
BLIND_MERGEONLY="$(  git -c core.quotepath=false -C "$R1" log    --name-only --format= 2>/dev/null | grep -cx mergeonly.cpp )"
[ "$ORACLE_MERGEONLY" = "$C_MERGEONLY" ] && [ "$ORACLE_BRANCH" = "$C_BRANCH" ] \
    && ok "the tool's churn re-derives from its own command (\`git log -c --name-only\`): $ORACLE_MERGEONLY / $ORACLE_BRANCH" \
    || no "tool vs its own command disagree: mergeonly $C_MERGEONLY vs $ORACLE_MERGEONLY, branchfile $C_BRANCH vs $ORACLE_BRANCH"
[ "$BLIND_MERGEONLY" = 0 ] \
    && ok "the OLD command (\`git log --name-only\`, no -c) still prints ZERO lines for mergeonly.cpp — the defect is real, not a fixture artifact" \
    || no "the old merge-blind command printed $BLIND_MERGEONLY line(s) for mergeonly.cpp — this fixture no longer reproduces the defect"

# ── 5. determinism ───────────────────────────────────────────────────────────────────────────────────
"$BIN" "$R1" --hotspots --limit=50 > "$TMP/h2.out" 2>/dev/null
cmp -s "$TMP/h.out" "$TMP/h2.out" && ok "--hotspots is byte-identical across runs (det-gate)" \
    || no "--hotspots differs between two runs on the same tree"

# ── 6. no degrade alert fires on this ordinary repo (the plain build is the one that can observe it) ──
grep -q 'DEGRADED' "$TMP/h.err" \
    && no "--hotspots emitted a degrade alert on a clean fixture: $( head -c 300 "$TMP/h.err" )" \
    || ok "no degrade alert on a clean merge-bearing repo"

[ "$fail" = 0 ] && echo "mergechurncheck: ALL PASS" || echo "mergechurncheck: FAILURES"
exit "$fail"
