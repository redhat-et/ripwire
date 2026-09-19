#!/usr/bin/env bash
# scoutheadconflictcheck.sh — gate for the r26 merge-base audit of --merge-scout.
#
# --merge-scout was ALREADY base-anchored (each arm is diffed against its own merge-base with HEAD, never
# against live HEAD), and that is the right anchor for "which of my branches fight EACH OTHER". The audit's
# finding was the other half: base-anchoring HIDES work that has already LANDED on HEAD since an arm forked.
# HEAD is not an arm, so no pairwise arm comparison can ever see it, and an arm that collides head-on with
# the live line reads as perfectly clean. That information is now kept as its OWN row class —
# head_conflicts= / <head-conflict> — never folded into the pairwise conflict count.
#
# Fixture: init commit defines alpha() and beta() in a.py, then
#   armA    (off init)   changes alpha
#   armB    (off init)   changes beta
#   HEAD    (mainline)   changes alpha TOO, after both arms forked
# so merge-base(armA,HEAD) = merge-base(armB,HEAD) = init != HEAD, and the live line collides with armA only.
#
# Asserts:
#   - armA reports head_conflicts="1" with a <head-conflict> row naming alpha
#   - armB reports head_conflicts="0" (it touched a symbol the live line left alone)
#   - the armA/armB PAIR still reports conflicts="0" — the head conflict is NOT folded into the pairwise
#     count, and the arm diff itself is still base-anchored (armA's own <sym> rows are unchanged)
#   - an arm forked off CURRENT HEAD reports head_conflicts="0" and costs no extra tree (the lane is skipped)
#   - determinism (byte-identical run-to-run) and xmllint-clean output
#
# Usage:
#   test/scoutheadconflictcheck.sh                            # uses build/ripwire
#   RIPWIRE_BIN=asan/ripwire test/scoutheadconflictcheck.sh
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
echo "scoutheadconflictcheck: BIN=$BIN"

# ── the fixture: HEAD moves AFTER both arms fork ──────────────────────────────────────────────────────
REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email "dev@x.com"
git -C "$REPO" config user.name  "Dev"

printf 'def alpha():\n    return 1\n\ndef beta():\n    return 1\n' >"$REPO/a.py"
git -C "$REPO" add -A
GIT_AUTHOR_DATE="2026-06-01T12:00:00" GIT_COMMITTER_DATE="2026-06-01T12:00:00" \
    git -C "$REPO" commit -qm "init"
MAIN="$( git -C "$REPO" symbolic-ref --short HEAD )"

git -C "$REPO" checkout -qb armA
printf 'def alpha():\n    return 100\n\ndef beta():\n    return 1\n' >"$REPO/a.py"
GIT_AUTHOR_DATE="2026-06-01T13:00:00" GIT_COMMITTER_DATE="2026-06-01T13:00:00" \
    git -C "$REPO" commit -qam "armA changes alpha"
git -C "$REPO" checkout -q "$MAIN"

git -C "$REPO" checkout -qb armB
printf 'def alpha():\n    return 1\n\ndef beta():\n    return 200\n' >"$REPO/a.py"
GIT_AUTHOR_DATE="2026-06-01T14:00:00" GIT_COMMITTER_DATE="2026-06-01T14:00:00" \
    git -C "$REPO" commit -qam "armB changes beta"
git -C "$REPO" checkout -q "$MAIN"

# the live line moves LAST, on the same symbol armA holds — the case no pairwise arm comparison can see
printf 'def alpha():\n    return 777\n\ndef beta():\n    return 1\n' >"$REPO/a.py"
GIT_AUTHOR_DATE="2026-06-01T15:00:00" GIT_COMMITTER_DATE="2026-06-01T15:00:00" \
    git -C "$REPO" commit -qam "the live line lands its own alpha"

OUT="$TMP/out.xml"
"$BIN" "$REPO" --merge-scout=armA,armB >"$OUT" 2>/dev/null

armAttrs(){ tr '<' '\n' <"$1" | grep "^arm ref=\"$2\"" | head -1; }

# ── the hidden collision is reported, on the right arm only ───────────────────────────────────────────
armAttrs "$OUT" armA | grep -q 'head_conflicts="1"' && ok 'armA reports head_conflicts="1"' \
                                                    || no "armA head_conflicts=1; got: $( armAttrs "$OUT" armA )"
grep -q '<head-conflict [^>]*alpha' "$OUT" && ok "the colliding symbol is named in a <head-conflict> row" \
                                           || no "the colliding symbol is named in a <head-conflict> row"
armAttrs "$OUT" armB | grep -q 'head_conflicts="0"' && ok 'armB reports head_conflicts="0"' \
                                                    || no "armB head_conflicts=0; got: $( armAttrs "$OUT" armB )"

# ── it is a SEPARATE class: the pairwise count and the base-anchored arm diff are untouched ───────────
tr '<' '\n' <"$OUT" | grep -q '^pair a="armA" b="armB" conflicts="0"' \
    && ok "the armA/armB pair still reports conflicts=0 (head conflict not folded in)" \
    || no "pair conflicts should stay 0; got: $( tr '<' '\n' <"$OUT" | grep '^pair ' )"
armAttrs "$OUT" armA | grep -q 'changed="1"' && ok "armA's base-anchored changed set is still 1 symbol" \
                                             || no "armA changed=1; got: $( armAttrs "$OUT" armA )"

# ── an arm forked off CURRENT HEAD skips the lane entirely ────────────────────────────────────────────
git -C "$REPO" checkout -qb armC
printf 'def alpha():\n    return 777\n\ndef beta():\n    return 300\n' >"$REPO/a.py"
GIT_AUTHOR_DATE="2026-06-01T16:00:00" GIT_COMMITTER_DATE="2026-06-01T16:00:00" \
    git -C "$REPO" commit -qam "armC forks off current HEAD"
git -C "$REPO" checkout -q "$MAIN"
FRESH="$TMP/fresh.xml"
"$BIN" "$REPO" --merge-scout=armC >"$FRESH" 2>/dev/null
armAttrs "$FRESH" armC | grep -q 'head_conflicts="0"' && ok 'an arm off current HEAD reports head_conflicts="0"' \
                                                      || no "armC head_conflicts=0; got: $( armAttrs "$FRESH" armC )"

# ── determinism + G4 ──────────────────────────────────────────────────────────────────────────────────
"$BIN" "$REPO" --merge-scout=armA,armB >"$TMP/a.xml" 2>/dev/null
"$BIN" "$REPO" --merge-scout=armA,armB >"$TMP/b.xml" 2>/dev/null
if cmp -s "$TMP/a.xml" "$TMP/b.xml"; then ok "deterministic (byte-identical run-to-run)"; else no "deterministic"; fi

if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$OUT" >/dev/null 2>&1; then ok "G4: xmllint-clean"; else no "G4: xmllint-clean"; fi
else
    ok "G4: xmllint unavailable — skipped"
fi

# ── UNAVAILABLE HEAD TREE: an unindexed HEAD is NOT an empty one — every diff against it is refused ────────────
# computeNamedArm refuses an arm whose base or tip tree could not be materialized (SymTreeIndex::isIndexed). Two
# other diffs read the memo without that check (CodeRabbit on #295): the head-conflict lane diffed base vs an
# unavailable HEAD as an empty tree — every base symbol "landed", so armB's beta became a false head conflict —
# and the working-tree arm diffed the real tree against it, so every symbol read as uncommitted work. The fault
# is a PATH shim that fails `git archive` of exactly HEAD's commit (a seam that reaches the Release binary too);
# control: the same shim passing everything through reproduces the healthy answer.
REALGIT="$( command -v git )"; SHIM="$TMP/gitshim"; mkdir -p "$SHIM"
cat >"$SHIM/git" <<SHEOF
#!/usr/bin/env bash
if [ -n "\${RW_SHIM_FAIL_ARCHIVE:-}" ]; then
    case " \$* " in *" archive "*"\${RW_SHIM_FAIL_ARCHIVE}"*) exit 128 ;; esac
fi
exec "$REALGIT" "\$@"
SHEOF
chmod +x "$SHIM/git"
HEADSHA="$( git -C "$REPO" rev-parse HEAD )"
printf 'def alpha():\n    return 777\n\ndef beta():\n    return 1\n\ndef gamma():\n    return 3\n' >"$REPO/a.py"   # dirty: the working-tree arm runs
PATH="$SHIM:$PATH" "$BIN" "$REPO" --merge-scout=armA,armB --no-cache >"$TMP/uc.xml" 2>/dev/null; rcC=$?
PATH="$SHIM:$PATH" RW_SHIM_FAIL_ARCHIVE="$HEADSHA" "$BIN" "$REPO" --merge-scout=armA,armB --no-cache >"$TMP/um.xml" 2>/dev/null; rcM=$?
git -C "$REPO" checkout -q -- a.py
WTREF="$( tr '<' '\n' <"$TMP/uc.xml" | sed -n 's/^arm ref="\([^"]*\)".*/\1/p' | grep -v '^arm[AB]$' | head -1 )"
if [ "$rcC" = 0 ] && armAttrs "$TMP/uc.xml" armB | grep -q 'head_conflicts="0">' \
   && [ -n "$WTREF" ] && armAttrs "$TMP/uc.xml" "$WTREF" | grep -q 'ok="1" changed="1"'; then
    ok "UNAVAIL control: pass-through shim — armB head_conflicts=0 (row carries no head_conflicts_ok=), working tree changed=1 (gamma)"
    armAttrs "$TMP/um.xml" armB | grep -q 'head_conflicts="0" head_conflicts_ok="0"' \
        && ok "UNAVAIL: an unavailable HEAD tree leaves armB's head conflicts UNKNOWN (head_conflicts_ok=\"0\"), not a false beta row" \
        || no "UNAVAIL: head-conflict lane diffed an unavailable HEAD as empty (exit $rcM): $( armAttrs "$TMP/um.xml" armB )"
    armAttrs "$TMP/um.xml" "$WTREF" | grep -q 'ok="0" changed="0"' \
        && ok "UNAVAIL: the working-tree arm refuses an unavailable HEAD (ok=\"0\" changed=\"0\"), not every symbol as new work" \
        || no "UNAVAIL: working-tree arm diffed against an unavailable HEAD: $( armAttrs "$TMP/um.xml" "$WTREF" )"
    grep -q 'head_conflicts_ok="0" (absent' "$TMP/um.xml" \
        && ok "UNAVAIL: the legend defines head_conflicts_ok=" || no "UNAVAIL: head_conflicts_ok= emitted with no definition in the legend"
else
    no "UNAVAIL control: the pass-through shim run is not the healthy answer (exit $rcC) — the mutation is void: $( armAttrs "$TMP/uc.xml" armB ) / ${WTREF:-no working-tree arm}"
fi

[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILURES"; exit 1
