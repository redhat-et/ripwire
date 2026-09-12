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
#   ripwire repo "--pr-context=--output=/path/victim.txt"     # exit 0, victim.txt clobbered with "1\t1\ta.c"
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
#   - WHO refuses, seen from the git child through an argv-logging PATH shim whose liveness is its own arm: a ref
#     beginning with '-' refuses (exit 1, names the ref) and its payload never reaches any git argv, single- and
#     multi-root — ripwire refuses it, git is never asked; a ref rev-parse answers with a non-bare name (`^HEAD` →
#     `^<sha>` at rc 0) refuses and no `^<sha>` reaches a git argv; a valid ref answers byte-identically through the
#     shim and reaches git only inside its own resolve probe
#   - a VALID base ref still works: exit 0, anchor="merge-base", the changed file present
#   - a non-git root with a base ref still DEGRADES to exit 0 (it is not a bad-ref refusal)
#   - determinism + xmllint-clean on the success path
#
# Usage:
#   test/prrefsafecheck.sh                            # uses build/ripwire
#   RIPWIRE_BIN=asan/ripwire test/prrefsafecheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
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
git -C "$REPO2" branch -q mainline   # so a multi-root run has a base ref BOTH roots resolve (the shim block's valid row)

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
    if [ "$rc" = 1 ]; then ok "$label: exit 1"; else no "$label: expected exit 1, got $rc"; fi
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
if [ "$rc" = 1 ]; then ok "unknown base ref exits 1 (not 0-with-an-empty-bundle)"; else no "unknown base ref: expected exit 1, got $rc"; fi
grep -q 'nosuchrefzzz' "$TMP/bad.err" && ok "the refusal names the offending ref on stderr" \
                                      || no "the refusal must name the offending ref on stderr"
[ -s "$TMP/bad.out" ] && no "a refusal must not also write a bundle to stdout" || ok "refusal writes no stdout payload"
grep -q '<pr-context' "$TMP/bad.out" 2>/dev/null && no 'refusal must not emit <pr-context files="0"> (reads as a clean tree)' \
                                                 || ok "refusal emits no clean-tree-looking bundle"

# ── the multi-root branch, which had no !ok check at all ───────────────────────────────────────────────
"$BIN" "$REPO" "$REPO2" --pr-context=nosuchrefzzz >"$TMP/mr.out" 2>"$TMP/mr.err"; rc=$?
if [ "$rc" = 1 ]; then ok "multi-root: unknown base ref exits 1"; else no "multi-root: expected exit 1, got $rc"; fi
printf 'PRECIOUS DATA DO NOT DELETE\n' >"$VICTIM"
BEFORE="$( cksum <"$VICTIM" )"
"$BIN" "$REPO" "$REPO2" "--pr-context=--output=$VICTIM" >/dev/null 2>&1; rc=$?
if [ "$rc" = 1 ]; then ok "multi-root: option-shaped ref exits 1"; else no "multi-root: option-shaped ref expected exit 1, got $rc"; fi
[ "$( cksum <"$VICTIM" )" = "$BEFORE" ] && ok "multi-root: the victim file is byte-identical (nothing written)" \
                                        || no "DATA LOSS: multi-root rewrote the victim file"

# ── the valid path still works exactly as before ──────────────────────────────────────────────────────
OUT="$TMP/good.xml"
"$BIN" "$REPO" --pr-context=mainline >"$OUT" 2>/dev/null; rc=$?
if [ "$rc" = 0 ]; then ok "a VALID base ref still exits 0"; else no "a valid base ref must still exit 0, got $rc"; fi
grep -q 'anchor="merge-base"' "$OUT" && ok 'a valid base ref still anchors at the merge base' \
                                     || no 'a valid base ref must still report anchor="merge-base"'
if grep -q '<file p="[^"]*extra\.py"' "$OUT"; then ok "the changed file is still reported"; else no "the changed file must still be reported"; fi

# a sha, a tag and HEAD~1 are all committish spellings the resolve must accept, not just branch names
SHA="$( git -C "$REPO" rev-parse mainline )"
if "$BIN" "$REPO" "--pr-context=$SHA" >/dev/null 2>&1; then ok "a raw sha is accepted"; else no "a raw sha must be accepted"; fi
if "$BIN" "$REPO" --pr-context=HEAD~1 >/dev/null 2>&1; then ok "a rev expression (HEAD~1) is accepted"; else no "HEAD~1 must be accepted"; fi

# ── a non-git root is a DEGRADE (exit 0), never a bad-ref refusal ──────────────────────────────────────
PLAIN="$TMP/plain"
mkdir -p "$PLAIN"
printf 'def x():\n    return 1\n' >"$PLAIN/x.py"
"$BIN" "$PLAIN" --pr-context=mainline >"$TMP/plain.out" 2>/dev/null; rc=$?
[ "$rc" = 0 ] && ok "a non-git root with a base ref still degrades to exit 0" \
              || no "a non-git root must degrade (exit 0), got $rc"

# ── WHO refuses a ref git could read as an option — ripwire, or git? Seen from the git CHILD's side ─────────
# The arms above prove exit 1 and an untouched victim; they cannot tell who refused. resolveBaseRefSha used to hand
# `rev-parse --verify --quiet '<ref>^{commit}'` a ref beginning with '-' as its own argv entry, stopped only because
# git's own rev-parse rejects one today. quality::gitResolveCommitSha refuses it before git is asked. The other half
# of that house rule — rev-parse's answer counts only as a bare object name (`^REF` answers `^<sha>` at rc 0) — held
# here already through a private copy; the `nonbare` rows fence it across the move to the shared resolver. A PATH
# shim logs every argv entry of every git call as `[entry]`, one call per line.
REALGIT="$( command -v git )"
mkdir -p "$TMP/shim"
cat >"$TMP/shim/git" <<EOF
#!/bin/bash
{ for a in "\$@"; do printf '[%s]' "\$a"; done; printf '\n'; } >> "$TMP/argv.log"
exec "$REALGIT" "\$@"
EOF
chmod +x "$TMP/shim/git"

# prctx MODE REF [shim] — MODE single = REPO, multi = REPO REPO2. With `shim` the run goes through the argv-logging git
# and leaves exactly its own git argv in $TMP/argv.log. Sets PC_RC; stdout / stderr land in $TMP/pc.out / $TMP/pc.err.
prctx()
{
    local roots=( "$REPO" ) path="$PATH"
    [ "$1" = multi ] && roots+=( "$REPO2" )
    [ "${3:-}" = shim ] && path="$TMP/shim:$PATH"
    rm -f "$TMP/argv.log"
    PATH="$path" "$BIN" "${roots[@]}" "--pr-context=$2" >"$TMP/pc.out" 2>"$TMP/pc.err"; PC_RC=$?
}

# liveness control: the shim sees a VALID ref's resolve probe as its own argv entry
prctx single mainline shim
grep -qF '[rev-parse][--verify][--quiet][mainline^{commit}]' "$TMP/argv.log" 2>/dev/null \
    && ok "shim liveness: a valid ref's resolve probe is logged as its own argv entry ([mainline^{commit}])" \
    || no "shim liveness: no resolve probe for mainline in the argv log — every argv arm below is vacuous: $( head -c 300 "$TMP/argv.log" 2>/dev/null )"

# mode|kind|ref|needle — `valid`: answers byte-identically to the unshimmed run; `nonbare`: rev-parse answers the ref at
# rc 0 with `^<sha>`; `dash`: git could read the ref as an option, and `needle` is the payload path that must never
# reach a git argv (nor be written).
ROWS="single|valid|mainline|
multi|valid|mainline|
single|nonbare|^HEAD|
single|nonbare|^mainline|
single|dash|--output=$TMP/pwned-output|$TMP/pwned-output
single|dash|--upload-pack=touch $TMP/pwned-uploadpack|$TMP/pwned-uploadpack
multi|dash|--output=$TMP/pwned-output-mr|$TMP/pwned-output-mr"
while IFS='|' read -r mode kind ref needle <&3; do
    label="$mode-root '$ref'"
    if [ "$kind" = valid ]; then
        prctx "$mode" "$ref"
        mv "$TMP/pc.out" "$TMP/unshimmed.out"
        prctx "$mode" "$ref" shim
        { [ "$PC_RC" -eq 0 ] && [ -s "$TMP/pc.out" ] && cmp -s "$TMP/pc.out" "$TMP/unshimmed.out"; } \
            && ok "$label answers byte-identically through the shim (rc=0, same bytes as the unshimmed run)" \
            || no "$label through the shim: rc=$PC_RC, or its answer differs from the unshimmed run"
        # a refused run never reaches the later git calls, so this arm counts only on an answered run — and only once the
        # resolved sha is seen reaching git (the merge-base call), or "no raw ref after the probe" would be vacuous
        OTHER="$( grep -F -- "$ref" "$TMP/argv.log" | grep -vF -- "[rev-parse][--verify][--quiet][$ref^{commit}]" )"
        { [ "$PC_RC" -eq 0 ] && grep -qF -- "[$SHA]" "$TMP/argv.log" && [ -z "$OTHER" ]; } \
            && ok "$label reaches git only inside its own resolve probe — later git calls are handed the sha (${SHA:0:10}…)" \
            || no "$label: rc=$PC_RC, the resolved sha never reached git, or the raw ref reached a git argv outside its resolve probe: $( printf '%s' "$OTHER" | head -1 | head -c 300 )"
        continue
    fi
    if [ "$kind" = nonbare ]; then
        # presence guard: on THIS fixture rev-parse must answer the ref at rc 0 with a non-bare name, or the refusal
        # below would pass for the boring reason (the ref simply does not resolve)
        PROBE="$( git -C "$REPO" rev-parse --verify --quiet "$ref^{commit}" 2>/dev/null )"; PROBERC=$?
        { [ "$PROBERC" -eq 0 ] && [ "${PROBE#^}" != "$PROBE" ]; } \
            && ok "precondition: rev-parse answers '$ref' at rc 0 with a non-bare name (${PROBE:0:10}…)" \
            || no "precondition: rev-parse does not answer '$ref' with a '^'-prefixed name here (rc=$PROBERC '$PROBE') — the arm cannot see the defect"
    fi
    prctx "$mode" "$ref" shim
    { [ "$PC_RC" -eq 1 ] && grep -qF -- "unknown base ref '$ref'" "$TMP/pc.err"; } \
        && ok "$label refuses as a bad ref (exit 1, names the ref)" \
        || no "$label did not refuse as a bad ref (rc=$PC_RC): $( head -c 300 "$TMP/pc.err" )"
    [ -s "$TMP/pc.out" ] && no "$label: a refusal must not also write a bundle to stdout" \
                         || ok "$label: the refusal writes no stdout payload"
    [ -s "$TMP/argv.log" ] \
        && ok "$label: the shim logged git calls during this very run (its argv arm is live)" \
        || no "$label: the shim logged nothing during this run — its argv arm is vacuous"
    if [ "$kind" = nonbare ]; then
        grep -Eq '\[\^[0-9a-f]{40}([0-9a-f]{24})?\]' "$TMP/argv.log" \
            && no "$label: rev-parse's non-bare answer reached git as an argv entry: $( grep -Eo '\[[a-z-]+\]\[\^[0-9a-f]+\]' "$TMP/argv.log" | head -2 | tr '\n' ' ' )" \
            || ok "$label: no '^<sha>' negation reached any git argv"
    else
        grep -qF -- "$needle" "$TMP/argv.log" \
            && no "$label reached a git argv: $( grep -F -- "$needle" "$TMP/argv.log" | head -1 | head -c 300 )" \
            || ok "$label never appears in any git argv (refused before git is asked)"
        if [ ! -e "$needle" ]; then ok "$label: nothing was written at the payload path"; else no "$label created $needle"; fi
    fi
done 3<<< "$ROWS"

# ── determinism + G4 on the success path ──────────────────────────────────────────────────────────────
"$BIN" "$REPO" --pr-context=mainline >"$TMP/a.xml" 2>/dev/null
"$BIN" "$REPO" --pr-context=mainline >"$TMP/b.xml" 2>/dev/null
if cmp -s "$TMP/a.xml" "$TMP/b.xml"; then ok "deterministic (byte-identical run-to-run)"; else no "deterministic"; fi

if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$OUT" >/dev/null 2>&1; then ok "G4: xmllint-clean"; else no "G4: xmllint-clean"; fi
else
    ok "G4: xmllint unavailable — skipped"
fi

[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILURES"; exit 1
