#!/usr/bin/env bash
# pranchorcheck.sh — gate for the r26 merge-base audit of --pr-context=BASEREF.
#
# --pr-context=BASEREF used to run a plain two-dot `git diff BASEREF`, which answers "how do these two
# trees differ TODAY" instead of "what did THIS work change since it forked". That is the same failure
# --abi was corrected for (abicheck.h §AUTHORSHIP) and --stray-content was born with (crossref.h §1), and
# it is wrong in BOTH directions on any base ref that has moved:
#   phantom  a file only BASEREF touched shows up, and burns a full evidence section on a file this work
#            never opened
#   MISSED   a file BOTH sides changed to the SAME content is invisible (the trees agree) even though this
#            work really did change it — a changed file the reviewer never sees. The worse of the two.
#
# Fixture: one init commit, then two lines off it —
#   mainline  changes theirs.py, and changes converge.py to content X
#   feature   changes mine.py,   and changes converge.py to the SAME content X   (this is HEAD)
# so `git diff mainline` (two-dot) would list theirs.py (phantom) and hide converge.py (missed), while
# `git diff merge-base(mainline,HEAD)` lists exactly {mine.py, converge.py}.
#
# Asserts:
#   - the BASEREF form reports anchor="merge-base" and a base_sha=
#   - base_moved="1" — the path only mainline moved is COUNTED, not silently filtered
#   - theirs.py is NOT a <file> section (the phantom is gone)
#   - mine.py IS a <file> section (the ordinary case still works)
#   - converge.py IS a <file> section (the MISSED case two-dot hid is now visible)
#   - the working-tree default (no BASEREF) emits NO anchor= attribute at all — byte-compatible header
#   - unrelated history degrades to anchor="ref-tip-two-dot" rather than refusing or lying
#   - determinism (byte-identical run-to-run) and xmllint-clean output
#
# Usage:
#   test/pranchorcheck.sh                            # uses build/ripwire
#   RIPWIRE_BIN=asan/ripwire test/pranchorcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "pranchorcheck: BIN=$BIN"

# ── the fixture: a base ref that has MOVED since this work forked ─────────────────────────────────────
REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email "dev@x.com"
git -C "$REPO" config user.name  "Dev"

printf 'def shared():\n    return 1\n'  >"$REPO/shared.py"
printf 'def mine():\n    return 1\n'    >"$REPO/mine.py"
printf 'def theirs():\n    return 1\n'  >"$REPO/theirs.py"
printf 'def converge():\n    return 1\n'>"$REPO/converge.py"
git -C "$REPO" add -A
GIT_AUTHOR_DATE="2026-06-01T12:00:00" GIT_COMMITTER_DATE="2026-06-01T12:00:00" \
    git -C "$REPO" commit -qm "init"
BASE="$( git -C "$REPO" rev-parse HEAD )"

# mainline: moves theirs.py, and lands the SAME converge.py content the feature line will reach on its own
git -C "$REPO" checkout -qb mainline
printf 'def theirs():\n    return 222\n'  >"$REPO/theirs.py"
printf 'def converge():\n    return 999\n'>"$REPO/converge.py"
GIT_AUTHOR_DATE="2026-06-01T13:00:00" GIT_COMMITTER_DATE="2026-06-01T13:00:00" \
    git -C "$REPO" commit -qam "mainline moves theirs + converge"

# feature: the line under review. Forks from BASE, not from mainline's tip.
git -C "$REPO" checkout -q "$BASE" 2>/dev/null
git -C "$REPO" checkout -qb feature
printf 'def mine():\n    return 111\n'    >"$REPO/mine.py"
printf 'def converge():\n    return 999\n'>"$REPO/converge.py"
GIT_AUTHOR_DATE="2026-06-01T14:00:00" GIT_COMMITTER_DATE="2026-06-01T14:00:00" \
    git -C "$REPO" commit -qam "feature moves mine + converge"

# sanity: the fixture really does exhibit both directions under a two-dot diff
git -C "$REPO" diff --numstat mainline | grep -q 'theirs\.py'   || no "fixture: two-dot should list theirs.py (phantom)"
git -C "$REPO" diff --numstat mainline | grep -q 'converge\.py' && no "fixture: two-dot should HIDE converge.py (missed)"

OUT="$TMP/out.xml"
"$BIN" "$REPO" --pr-context=mainline >"$OUT" 2>/dev/null

# ── the anchor is stated, and it is the merge base ────────────────────────────────────────────────────
grep -q 'anchor="merge-base"' "$OUT" && ok 'BASEREF form reports anchor="merge-base"' \
                                     || no 'BASEREF form reports anchor="merge-base"'
grep -q 'base_sha="' "$OUT" && ok "the anchor sha is named (base_sha=)" || no "the anchor sha is named (base_sha=)"

# ── the excluded class is COUNTED, not silently filtered ──────────────────────────────────────────────
grep -q 'base_moved="1"' "$OUT" && ok 'base_moved="1" counts the path only the base ref moved' \
                                || no "base_moved=1 expected; got: $( grep -o 'base_moved="[0-9]*"' "$OUT" | head -1 )"

# ── the phantom is gone, the real changes are present ─────────────────────────────────────────────────
grep -q '<file p="[^"]*theirs\.py"' "$OUT" && no "theirs.py must NOT be a section (phantom: only the base ref moved it)" \
                                           || ok "theirs.py is not a section (phantom removed)"
grep -q '<file p="[^"]*mine\.py"' "$OUT" && ok "mine.py is a section (ordinary changed file)" \
                                         || no "mine.py is a section (ordinary changed file)"
grep -q '<file p="[^"]*converge\.py"' "$OUT" && ok "converge.py is a section (the case two-dot HID)" \
                                             || no "converge.py is a section (the case two-dot HID)"

# ── the working-tree default is untouched: no anchoring question, so no anchoring attribute ───────────
printf 'def mine():\n    return 112\n' >"$REPO/mine.py"
DEF="$TMP/default.xml"
"$BIN" "$REPO" --pr-context >"$DEF" 2>/dev/null
grep -q 'anchor="' "$DEF" && no "working-tree default must emit NO anchor= attribute" \
                          || ok "working-tree default emits no anchor= attribute (header byte-compatible)"
git -C "$REPO" checkout -q -- mine.py

# ── unrelated history: degrade to the two-dot view, and SAY so ────────────────────────────────────────
ORPHAN="$TMP/orphan"
git -C "$REPO" checkout -q --orphan orphanline
git -C "$REPO" rm -rq --cached . 2>/dev/null
printf 'def alone():\n    return 1\n' >"$REPO/alone.py"
git -C "$REPO" add alone.py
GIT_AUTHOR_DATE="2026-06-01T15:00:00" GIT_COMMITTER_DATE="2026-06-01T15:00:00" \
    git -C "$REPO" commit -qm "unrelated root"
git -C "$REPO" checkout -qf feature
"$BIN" "$REPO" --pr-context=orphanline >"$ORPHAN" 2>/dev/null
grep -q 'anchor="ref-tip-two-dot"' "$ORPHAN" && ok 'unrelated history degrades to anchor="ref-tip-two-dot"' \
                                             || no 'unrelated history degrades to anchor="ref-tip-two-dot"'

# ── determinism + G4 ──────────────────────────────────────────────────────────────────────────────────
"$BIN" "$REPO" --pr-context=mainline >"$TMP/a.xml" 2>/dev/null
"$BIN" "$REPO" --pr-context=mainline >"$TMP/b.xml" 2>/dev/null
cmp -s "$TMP/a.xml" "$TMP/b.xml" && ok "deterministic (byte-identical run-to-run)" || no "deterministic"

if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$OUT" >/dev/null 2>&1 && ok "G4: xmllint-clean" || no "G4: xmllint-clean"
else
    ok "G4: xmllint unavailable — skipped"
fi

[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILURES"; exit 1
