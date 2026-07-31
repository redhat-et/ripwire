#!/usr/bin/env bash
# prrefsafecheck.sh — SECURITY gate for --pr-context=BASEREF: the base ref never reaches git as an OPTION,
# and a ref that does not resolve is REFUSED loudly instead of rendering as a clean tree.
#
# ── the defect this gate exists for (P0.1, data loss) ─────────────────────────────────────────────────
# resolveDiffAnchor's unrelated-history fallback used to hand the RAW user ref back as the revision token
# for `git diff --numstat <token>`. shSingleQuote stops SHELL injection, but the token still arrives at
# git as its own argv entry — and `git diff` honors `--output=FILE`, which TRUNCATES and rewrites FILE.
# A ref beginning with `-` fails `merge-base` first, which is exactly what routed it into that fallback:
#
#   ctxpack repo "--pr-context=--output=/path/victim.txt"     # exit 0, victim.txt clobbered with "1\t1\ta.c"
#
# The fix resolves the ref through `rev-parse --verify ...^{commit}` FIRST and diffs the resulting 40-hex
# sha (a sha can never begin with `-`), with a trailing `--` so no later token can be read as an option.
#
# ── the second defect (P2.8, silent-typo) ────────────────────────────────────────────────────────────
# `--pr-context=BADREF` used to emit `<pr-context base="badref" files="0"/>` and exit 0 — in CI a typo'd
# base ref is then indistinguishable from a clean tree. Every sibling ref-taking verb (--merge-scout,
# --abi, --stray-content, --whereis, --plan) refuses with exit 1. The `!ok` check was also absent
# ENTIRELY from the multi-root branch, so a workspace run could not refuse at all.
#
# Asserts:
#   - an option-shaped ref (`--output=FILE`, `-p`) exits 1 and WRITES NOTHING — the pre-existing victim
#     file is byte-identical afterwards, and a non-existent victim path is still non-existent (the
#     ABSENCE assertion, not merely an exit code)
#   - the same, with a DIRTY tree (the numstat pass then has content to write — the orchestrator's repro)
#   - a plain unknown ref exits 1 and names the ref on stderr, with an EMPTY stdout (no payload)
#   - the multi-root form refuses the same way (the branch that had no check at all)
#   - a VALID base ref still works: exit 0, anchor="merge-base", the changed file present
#   - a non-git root with a base ref still DEGRADES to exit 0 (it is not a bad-ref refusal)
#   - determinism + xmllint-clean on the success path
#
# Usage:
#   test/prrefsafecheck.sh                            # uses build/ctxpack
#   CTXPACK_BIN=asan/ctxpack test/prrefsafecheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "prrefsafecheck: BIN=$BIN"

# ── fixture: an ordinary two-commit repo plus a second root for the multi-root form ───────────────────
REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email "dev@x.com"
git -C "$REPO" config user.name  "Dev"

printf 'def base():\n    return 1\n' >"$REPO/base.py"
GIT_AUTHOR_DATE="2026-06-01T12:00:00" GIT_COMMITTER_DATE="2026-06-01T12:00:00" \
    git -C "$REPO" add -A && git -C "$REPO" commit -qm "init"
git -C "$REPO" branch -q mainline

printf 'def base():\n    return 2\n'   >"$REPO/base.py"
printf 'def extra():\n    return 3\n'  >"$REPO/extra.py"
git -C "$REPO" add -A
GIT_AUTHOR_DATE="2026-06-01T13:00:00" GIT_COMMITTER_DATE="2026-06-01T13:00:00" \
    git -C "$REPO" commit -qm "work"

REPO2="$TMP/repo2"
mkdir -p "$REPO2"
git -C "$REPO2" init -q
git -C "$REPO2" config user.email "dev@x.com"
git -C "$REPO2" config user.name  "Dev"
printf 'def other():\n    return 1\n' >"$REPO2/other.py"
git -C "$REPO2" add -A
GIT_AUTHOR_DATE="2026-06-01T12:00:00" GIT_COMMITTER_DATE="2026-06-01T12:00:00" \
    git -C "$REPO2" commit -qm "init"

# ── the security assertion: an option-shaped ref must write NOTHING ───────────────────────────────────
# Two victims, because an exit code alone proves nothing: one that EXISTS (must stay byte-identical) and
# one that does NOT (must stay absent — `git diff --output=` creates the file even for an empty diff).
VICTIM="$TMP/victim.txt"
GHOST="$TMP/ghost.txt"
printf 'PRECIOUS DATA DO NOT DELETE\n' >"$VICTIM"
BEFORE="$( cksum <"$VICTIM" )"

optref_refused()   # $1 = the option-shaped ref, $2 = label
{
    local ref="$1" label="$2" rc
    "$BIN" "$REPO" "--pr-context=$ref" >"$TMP/opt.out" 2>"$TMP/opt.err"; rc=$?
    [ "$rc" = 1 ] && ok "$label: exit 1" || no "$label: expected exit 1, got $rc"
}

optref_refused "--output=$VICTIM" "option-shaped ref (--output=EXISTING)"
[ "$( cksum <"$VICTIM" )" = "$BEFORE" ] && ok "the existing victim file is byte-identical (nothing written)" \
                                        || no "DATA LOSS: the victim file was rewritten by git --output="

optref_refused "--output=$GHOST" "option-shaped ref (--output=NONEXISTENT)"
[ -e "$GHOST" ] && no "DATA LOSS: a file was CREATED at the attacker-named path ($GHOST)" \
                || ok "no file was created at the attacker-named path (absence asserted)"

optref_refused "-p" "option-shaped ref (bare -p)"

# ── the same, with a DIRTY tree: the exact orchestrator repro (the numstat pass has rows to write) ─────
printf 'def base():\n    return 99\n' >"$REPO/base.py"
printf 'PRECIOUS DATA DO NOT DELETE\n' >"$VICTIM"
BEFORE="$( cksum <"$VICTIM" )"
optref_refused "--output=$VICTIM" "option-shaped ref, DIRTY tree"
[ "$( cksum <"$VICTIM" )" = "$BEFORE" ] && ok "dirty tree: the victim file is byte-identical (nothing written)" \
                                        || no "DATA LOSS: dirty tree rewrote the victim file"
git -C "$REPO" checkout -q -- base.py

# ── P2.8: a typo'd ref refuses loudly, names the ref, and writes NO payload to stdout ──────────────────
"$BIN" "$REPO" --pr-context=nosuchrefzzz >"$TMP/bad.out" 2>"$TMP/bad.err"; rc=$?
[ "$rc" = 1 ] && ok "unknown base ref exits 1 (not 0-with-an-empty-bundle)" || no "unknown base ref: expected exit 1, got $rc"
grep -q 'nosuchrefzzz' "$TMP/bad.err" && ok "the refusal names the offending ref on stderr" \
                                      || no "the refusal must name the offending ref on stderr"
[ -s "$TMP/bad.out" ] && no "a refusal must not also write a bundle to stdout" || ok "refusal writes no stdout payload"
grep -q '<pr-context' "$TMP/bad.out" 2>/dev/null && no 'refusal must not emit <pr-context files="0"> (reads as a clean tree)' \
                                                 || ok "refusal emits no clean-tree-looking bundle"

# ── the multi-root branch, which had no !ok check at all ───────────────────────────────────────────────
"$BIN" "$REPO" "$REPO2" --pr-context=nosuchrefzzz >"$TMP/mr.out" 2>"$TMP/mr.err"; rc=$?
[ "$rc" = 1 ] && ok "multi-root: unknown base ref exits 1" || no "multi-root: expected exit 1, got $rc"
printf 'PRECIOUS DATA DO NOT DELETE\n' >"$VICTIM"
BEFORE="$( cksum <"$VICTIM" )"
"$BIN" "$REPO" "$REPO2" "--pr-context=--output=$VICTIM" >/dev/null 2>&1; rc=$?
[ "$rc" = 1 ] && ok "multi-root: option-shaped ref exits 1" || no "multi-root: option-shaped ref expected exit 1, got $rc"
[ "$( cksum <"$VICTIM" )" = "$BEFORE" ] && ok "multi-root: the victim file is byte-identical (nothing written)" \
                                        || no "DATA LOSS: multi-root rewrote the victim file"

# ── the valid path still works exactly as before ──────────────────────────────────────────────────────
OUT="$TMP/good.xml"
"$BIN" "$REPO" --pr-context=mainline >"$OUT" 2>/dev/null; rc=$?
[ "$rc" = 0 ] && ok "a VALID base ref still exits 0" || no "a valid base ref must still exit 0, got $rc"
grep -q 'anchor="merge-base"' "$OUT" && ok 'a valid base ref still anchors at the merge base' \
                                     || no 'a valid base ref must still report anchor="merge-base"'
grep -q '<file p="[^"]*extra\.py"' "$OUT" && ok "the changed file is still reported" || no "the changed file must still be reported"

# a sha, a tag and HEAD~1 are all committish spellings the resolve must accept, not just branch names
SHA="$( git -C "$REPO" rev-parse mainline )"
"$BIN" "$REPO" "--pr-context=$SHA" >/dev/null 2>&1 && ok "a raw sha is accepted" || no "a raw sha must be accepted"
"$BIN" "$REPO" --pr-context=HEAD~1 >/dev/null 2>&1 && ok "a rev expression (HEAD~1) is accepted" || no "HEAD~1 must be accepted"

# ── a non-git root is a DEGRADE (exit 0), never a bad-ref refusal ──────────────────────────────────────
PLAIN="$TMP/plain"
mkdir -p "$PLAIN"
printf 'def x():\n    return 1\n' >"$PLAIN/x.py"
"$BIN" "$PLAIN" --pr-context=mainline >"$TMP/plain.out" 2>/dev/null; rc=$?
[ "$rc" = 0 ] && ok "a non-git root with a base ref still degrades to exit 0" \
              || no "a non-git root must degrade (exit 0), got $rc"

# ── determinism + G4 on the success path ──────────────────────────────────────────────────────────────
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
