#!/usr/bin/env bash
# qchurnmemocheck.sh — r27 P3 gate: --quality-delta must spawn `git diff --unified=0 HEAD -- <path>` ONCE PER
# PATH, not once per symbol.
#
# THE FINDING. `churnEditTouchesHotLine` (the SELF-vs-AMBIENT classifier) is called per symbol with no memo,
# and each call popen'd its own `git diff`. A subprocess-shim log on this repo showed EIGHT byte-identical
# spawns for a single dirty file. The diff is a PURE function of (HEAD, working tree), both fixed for the life
# of one call — the code's own section comment already said so. Fix: a run-scoped, caller-owned
# HashMap<path, vector<DiffHunk>>.
#
# HOW THIS IS MEASURED (and why it is not a timing test — timings are not gateable): a shim `git` earlier on
# PATH appends its argv to a log and execs the real git. The gate then asserts a STRUCTURAL invariant:
#   spawns of `diff --unified=0 … -- <path>`  ==  distinct paths in that set.
# That is timing-free, deterministic, and fails loudly the moment the memo is removed or bypassed.
#
# It also pins the OUTPUT: the memoized run must be byte-identical to the pre-memo answer on the same tree
# ("faster must never change the answer"), checked here as byte-identity across repeated runs plus a
# non-vacuous churn row.
#
# Checks:
#   (a) the fixture actually produces short-horizon-churn rows (otherwise everything below is vacuous);
#   (b) `git diff --unified=0` spawn count == distinct-path count (the memo is doing its job);
#   (c) more than one CHURN ROW lands on the memoized path — i.e. the memo saved real spawns, so (b) is not
#       passing merely because there was nothing to memoize;
#   (d) the report is byte-identical run-to-run (determinism law).
#
# Own temp repo. Needs git.
# Usage:  test/qchurnmemocheck.sh   |   RIPWIRE_BIN=build/ripwire test/qchurnmemocheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "  SKIP  qchurnmemocheck (git not available)"; exit 0; }
REALGIT="$( command -v git )"

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
REPO="$WORK/repo"; SHIM="$WORK/shim"; LOG="$WORK/gitlog.txt"
mkdir -p "$REPO/src" "$SHIM"

# the shim: log the argv, then exec the real git (so behavior is unchanged).
cat > "$SHIM/git" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$LOG"
exec "$REALGIT" "\$@"
EOF
chmod +x "$SHIM/git"

# ── fixture: one file, MANY symbols, two in-window commits that rewrite most of them ──────────────────────
# Gate 1 needs >= 2 commits on the file inside the 14-day window; gate 2 needs each symbol present in the
# baseline with a DIFFERENT body now; gate 3 needs the body to have already changed across window commits.
# Eight symbols in ONE file is exactly the shape that produced eight identical git spawns.
gen(){   # $1 = the per-symbol constant
    { for n in 1 2 3 4 5 6 7 8; do printf 'int sym%s(){ return %s%s; }\n' "$n" "$1" "$n"; done
      printf 'int drive(){ return sym1()+sym2()+sym3()+sym4()+sym5()+sym6()+sym7()+sym8(); }\n'; }
}
( cd "$REPO" && "$REALGIT" init -q && "$REALGIT" config user.email t@t && "$REALGIT" config user.name t )
gen 1 > "$REPO/src/f.cpp"; ( cd "$REPO" && "$REALGIT" add -A >/dev/null && "$REALGIT" commit -qm c1 >/dev/null )
gen 2 > "$REPO/src/f.cpp"; ( cd "$REPO" && "$REALGIT" add -A >/dev/null && "$REALGIT" commit -qm c2 >/dev/null )
gen 3 > "$REPO/src/f.cpp"                                     # the uncommitted rewrite

echo "qchurnmemocheck: BIN=$BIN"

: > "$LOG"
OUT="$( cd "$REPO" && PATH="$SHIM:$PATH" "$BIN" . --quality-delta --no-cache 2>/dev/null )"

CHURN="$( printf '%s' "$OUT" | tr '<' '\n' | grep -c 'kind="short-horizon-churn"' )"
[ "$CHURN" -ge 2 ] \
    && ok "fixture produces $CHURN short-horizon-churn rows on one file (non-vacuous)" \
    || { no "fixture produced $CHURN churn rows — the memo check would be vacuous"; printf '%s' "$OUT" | tr '<' '\n' | grep '^r kind=' | head -5; }

SPAWNS="$( grep -c 'diff --unified=0' "$LOG" )"
PATHS="$( grep 'diff --unified=0' "$LOG" | sed 's/.* -- //' | sort -u | grep -c . )"
[ "$SPAWNS" -gt 0 ] && ok "the churn SELF/AMBIENT classifier ran (${SPAWNS} unified=0 diff spawn(s) logged)" \
                    || no "no 'git diff --unified=0' spawn logged — the shim or the fixture is wrong"
[ "$SPAWNS" -eq "$PATHS" ] \
    && ok "ONE spawn per PATH: $SPAWNS spawn(s) for $PATHS distinct path(s) — the run-scoped memo holds" \
    || { no "$SPAWNS spawns for only $PATHS distinct path(s) — the per-path memo is gone or bypassed"
         grep 'diff --unified=0' "$LOG" | sort | uniq -c | sort -rn | head -3; }
[ "$CHURN" -gt "$SPAWNS" ] \
    && ok "the memo saved real work: $CHURN churn rows served by $SPAWNS spawn(s)" \
    || no "churn rows ($CHURN) <= spawns ($SPAWNS) — nothing was actually deduplicated"

# ── determinism: faster must never change the answer ──────────────────────────────────────────────────────
OUT2="$( cd "$REPO" && "$BIN" . --quality-delta --no-cache 2>/dev/null )"
[ "$OUT" = "$OUT2" ] && ok "the memoized report is byte-identical run-to-run (determinism law)" \
                     || no "the memoized report is not byte-stable"

[ "$fail" -eq 0 ] && echo "qchurnmemocheck: ALL PASS" || { echo "qchurnmemocheck: SOME CHECKS FAILED"; exit 1; }
