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
# T9 (2026-09-19, CodeRabbit thread 4054594304, queued from train-8): a base whose git TREE is non-empty but
# contributes ZERO files to the ingest — every path excluded, or none has a supported extension — used to be
# indistinguishable from a real git-archive/ingest FAILURE (both left SymTreeIndex::isIndexed=false via the
# removed commitTreeIsEmpty heuristic). quality::materializeCommitTree now checks git archive's own exit
# status separately from tar's, so a materialize that truly succeeds is trusted, and an empty ingest of it is
# a real empty index. Arms T9(a)/(b) cover the two routes (no supported extension, all-excluded); T9(c)
# reuses the PATH-shim technique below to prove a GENUINE archive failure still refuses, now with an in-band
# reason= (T9(c)/(d)); T9(e) proves that disclosure survives a Release (NDEBUG) build.
#
# Usage:
#   test/scoutheadconflictcheck.sh                            # uses build/ripwire
#   RIPWIRE_BIN=asan/ripwire test/scoutheadconflictcheck.sh
#   RIPWIRE_RELEASE_BIN=relbuild/ripwire test/scoutheadconflictcheck.sh   # T9(e); else it looks for
#                                                                          # relbuild/ripwire or build_release/ripwire next to ROOT
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
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
    [ "$rcM" = 0 ] && armAttrs "$TMP/um.xml" armB | grep -q 'head_conflicts="0" head_conflicts_ok="0"' \
        && ok "UNAVAIL: an unavailable HEAD tree leaves armB's head conflicts UNKNOWN (head_conflicts_ok=\"0\"), not a false beta row" \
        || no "UNAVAIL: head-conflict lane diffed an unavailable HEAD as empty (exit $rcM): $( armAttrs "$TMP/um.xml" armB )"
    armAttrs "$TMP/um.xml" "$WTREF" | grep -q 'ok="0" reason="tree_unavailable" changed="0"' \
        && ok "UNAVAIL: the working-tree arm refuses an unavailable HEAD (ok=\"0\" reason=\"tree_unavailable\" changed=\"0\"), not every symbol as new work" \
        || no "UNAVAIL: working-tree arm diffed against an unavailable HEAD: $( armAttrs "$TMP/um.xml" "$WTREF" )"
    grep -qE 'head_conflicts_ok="0" \(absent|head_conflicts_ok=0: ' "$TMP/um.xml" \
        && ok "UNAVAIL: the legend defines head_conflicts_ok=" || no "UNAVAIL: head_conflicts_ok= emitted with no definition in the legend"
else
    no "UNAVAIL control: the pass-through shim run is not the healthy answer (exit $rcC) — the mutation is void: $( armAttrs "$TMP/uc.xml" armB ) / ${WTREF:-no working-tree arm}"
fi

# ── LEGAL EMPTY BASE: a merge-base whose TREE has zero files is not a materialize/ingest FAILURE ───────
# CodeRabbit review (src/mergescout.h:245-267, indexCommittish): a committish that materializes fine but
# ingests with zero files (a genuinely empty tree — e.g. the very first commit of a history, before
# anything was added) used to be indistinguishable from a materialize/ingest FAILURE — both left
# SymTreeIndex::isIndexed=false, so computeNamedArm refused a perfectly legal comparison (ok="0"
# changed="0", as though the tree could not be read), and the SAME check in headChangedKeysSince marked
# head_conflicts_ok="0" too. Fixture: a `git commit-tree` seed commit with the well-known EMPTY tree,
# no parent; mainline adds f1.py as SEED's child; armE branches off SEED DIRECTLY (before f1.py exists)
# and adds its own g1.py — so merge-base(armE, mainline) IS the empty-tree seed commit.
REPO2="$TMP/repo2"
mkdir -p "$REPO2"
git -C "$REPO2" init -q
git -C "$REPO2" config user.email "dev@x.com"
git -C "$REPO2" config user.name  "Dev"
EMPTY_TREE="$( git -C "$REPO2" hash-object -t tree /dev/null )"
SEED="$( GIT_AUTHOR_DATE="2026-06-01T10:00:00" GIT_COMMITTER_DATE="2026-06-01T10:00:00" \
         git -C "$REPO2" commit-tree "$EMPTY_TREE" -m "seed (empty tree)" )"
git -C "$REPO2" checkout -qb mainline "$SEED"
printf 'def f_one():\n    return 1\n' >"$REPO2/f1.py"
git -C "$REPO2" add -A
GIT_AUTHOR_DATE="2026-06-01T11:00:00" GIT_COMMITTER_DATE="2026-06-01T11:00:00" \
    git -C "$REPO2" commit -qm "mainline adds f1"
git -C "$REPO2" checkout -qb armE "$SEED"
printf 'def g_one():\n    return 2\n' >"$REPO2/g1.py"
git -C "$REPO2" add -A
GIT_AUTHOR_DATE="2026-06-01T10:30:00" GIT_COMMITTER_DATE="2026-06-01T10:30:00" \
    git -C "$REPO2" commit -qm "armE adds g1, off the empty-tree seed"
git -C "$REPO2" checkout -q mainline

EOUT="$TMP/empty-base.xml"
"$BIN" "$REPO2" --merge-scout=armE --no-cache >"$EOUT" 2>/dev/null
armAttrs "$EOUT" armE | grep -q 'ok="1"' \
    && ok "empty-base: armE (merge-base = empty-tree seed) reports ok=\"1\", not refused as unavailable" \
    || no "empty-base: armE wrongly refused (a legal empty base read as an unavailable tree): $( armAttrs "$EOUT" armE )"
ARME_ROW="$( armAttrs "$EOUT" armE )"
if printf '%s' "$ARME_ROW" | grep -q 'changed="1"' \
   && grep -q '<arm ref="armE"[^>]*changed="1"[^>]*><sym p="g1\.py" id="g_one"/></arm>' "$EOUT"; then
    ok "empty-base: armE's g_one counts as added against the empty base (changed=1)"
else
    no "empty-base: armE's own symbol did not surface as changed: $ARME_ROW"
fi
armAttrs "$EOUT" armE | grep -q 'head_conflicts_ok="0"' \
    && no "empty-base: head_conflicts_ok=\"0\" still leaks from the SAME isIndexed check on a legal empty base: $( armAttrs "$EOUT" armE )" \
    || ok "empty-base: head_conflicts_ok stays correct (absent = held) — the empty base did not poison the head-conflict lane either"

# ── T9: A NON-EMPTY TREE WITH NOTHING TO INGEST IS NOT AN UNAVAILABLE ONE ──────────────────────────────
# The empty-base fixture above covers a GIT TREE that is itself empty (the well-known empty-tree hash). The
# bug this lane closes (CodeRabbit thread 4054594304, queued from train-8) is narrower and was NOT covered by
# that fixture: a tree that is NOT empty in git's eyes — it holds real bytes — but contributes zero files to
# the ingest, either because every path the base touched is excluded, or because none of its files has a
# supported extension. commitTreeIsEmpty (removed) only asked "is the git tree object the empty-tree hash",
# so both shapes below used to answer "no" and fall through to a real-failure refusal (ok="0" changed="0",
# indistinguishable from a genuine git-archive failure). Fixture: mainline holds only README.txt (unsupported
# extension); armF branches off it and adds a real body symbol in a.cc.
REPO4="$TMP/repo4"
mkdir -p "$REPO4"
git -C "$REPO4" init -q
git -C "$REPO4" config user.email "dev@x.com"
git -C "$REPO4" config user.name  "Dev"
printf 'hello\n' >"$REPO4/README.txt"
git -C "$REPO4" add -A
GIT_AUTHOR_DATE="2026-06-01T10:00:00" GIT_COMMITTER_DATE="2026-06-01T10:00:00" \
    git -C "$REPO4" commit -qm "mainline: README.txt only, no supported extension"
git -C "$REPO4" checkout -qb armF
printf 'int main(){return 0;}\n' >"$REPO4/a.cc"
git -C "$REPO4" add -A
GIT_AUTHOR_DATE="2026-06-01T11:00:00" GIT_COMMITTER_DATE="2026-06-01T11:00:00" \
    git -C "$REPO4" commit -qm "armF adds a.cc"
git -C "$REPO4" checkout -q master 2>/dev/null || git -C "$REPO4" checkout -q main

# (a) no-supported-files base: the merge-base's own tree (README.txt only) is non-empty but has nothing this
#     tool can parse — ok="1" and armF's own symbol counts as added against it.
NSOUT="$TMP/no-supported.xml"
"$BIN" "$REPO4" --merge-scout=armF --no-cache >"$NSOUT" 2>/dev/null
armAttrs "$NSOUT" armF | grep -q 'ok="1"' \
    && ok "T9(a) no-supported-files base: armF reports ok=\"1\", not refused as unavailable" \
    || no "T9(a) no-supported-files base: armF wrongly refused: $( armAttrs "$NSOUT" armF )"
grep -q '<arm ref="armF"[^>]*changed="1"[^>]*><sym p="a\.cc" id="main"/>' "$NSOUT" \
    && ok "T9(a) armF's own main() counts as added against the no-supported-files base" \
    || no "T9(a) armF's symbol did not surface as changed: $( armAttrs "$NSOUT" armF )"

# (b) all-excluded base: the merge-base's tree holds a SUPPORTED file, but --exclude drops every path in it —
#     same shape by a different route (the excludes config, not the language grammar), same required answer.
REPO5="$TMP/repo5"
mkdir -p "$REPO5"
git -C "$REPO5" init -q
git -C "$REPO5" config user.email "dev@x.com"
git -C "$REPO5" config user.name  "Dev"
printf 'def vendored():\n    return 1\n' >"$REPO5/vendor.py"
git -C "$REPO5" add -A
GIT_AUTHOR_DATE="2026-06-01T10:00:00" GIT_COMMITTER_DATE="2026-06-01T10:00:00" \
    git -C "$REPO5" commit -qm "mainline: one file, entirely under --exclude"
git -C "$REPO5" checkout -qb armG
printf 'def new_thing():\n    return 2\n' >"$REPO5/g.py"
git -C "$REPO5" add -A
GIT_AUTHOR_DATE="2026-06-01T11:00:00" GIT_COMMITTER_DATE="2026-06-01T11:00:00" \
    git -C "$REPO5" commit -qm "armG adds g.py"
git -C "$REPO5" checkout -q master 2>/dev/null || git -C "$REPO5" checkout -q main

EXOUT="$TMP/all-excluded.xml"
"$BIN" "$REPO5" --merge-scout=armG --exclude=vendor.py --no-cache >"$EXOUT" 2>/dev/null
armAttrs "$EXOUT" armG | grep -q 'ok="1"' \
    && ok "T9(b) all-excluded base: armG reports ok=\"1\", not refused as unavailable" \
    || no "T9(b) all-excluded base: armG wrongly refused: $( armAttrs "$EXOUT" armG )"
grep -q '<arm ref="armG"[^>]*changed="1"[^>]*><sym p="g\.py" id="new_thing"/>' "$EXOUT" \
    && ok "T9(b) armG's own new_thing() counts as added against the all-excluded base" \
    || no "T9(b) armG's symbol did not surface as changed: $( armAttrs "$EXOUT" armG )"

# (c) A GENUINE materialize failure must still refuse — and now DISCLOSE why, in-band, on the row itself. Reuse
#     the PATH-shim technique from the UNAVAIL section above, this time failing the ARM's own tip (not HEAD),
#     so this exercises computeNamedArm's own tree-unavailable path rather than the head-conflict lane's.
ARMFSHA="$( git -C "$REPO4" rev-parse armF )"
FAILOUT="$TMP/tree-unavailable.xml"
PATH="$SHIM:$PATH" RW_SHIM_FAIL_ARCHIVE="$ARMFSHA" "$BIN" "$REPO4" --merge-scout=armF --no-cache >"$FAILOUT" 2>/dev/null
armAttrs "$FAILOUT" armF | grep -q 'ok="0" reason="tree_unavailable"' \
    && ok "T9(c) a genuine git-archive failure still refuses (ok=\"0\") AND now names reason=\"tree_unavailable\" in-band" \
    || no "T9(c) expected ok=\"0\" reason=\"tree_unavailable\"; got: $( armAttrs "$FAILOUT" armF )"
# TRAIN 9: the default posture is the COMPACT legend, so (d) now asserts BOTH dialects — the compact one on the
# answer the arm above already produced (the default), and the full prose on a second run with the posture flag.
# Each dialect is checked in its OWN wording: a reading that exists only in the one nobody gets by default is the
# failure this arm is for.
grep -q 'reason=no_merge_base (no merge base with HEAD' "$FAILOUT" \
    && ok "T9(d) compact: the legend defines reason=no_merge_base verbatim" \
    || no "T9(d) compact: the legend does not define reason=\"no_merge_base\""
grep -q 'reason=tree_unavailable (a side' "$FAILOUT" \
    && ok "T9(d) compact: the legend defines reason=tree_unavailable verbatim" \
    || no "T9(d) compact: the legend does not define reason=\"tree_unavailable\""
grep -q 'ok=1 on an arm row means the comparison RAN' "$FAILOUT" \
    && ok "T9(d) compact: the legend defines ok= for the ok=\"1\" posture" \
    || no "T9(d) compact: the legend does not define the ok=\"1\" posture"
grep -q 'ok=0 means it did not run at all' "$FAILOUT" \
    && ok "T9(d) compact: the legend defines ok= for the ok=\"0\" posture" \
    || no "T9(d) compact: the legend does not define the ok=\"0\" posture"
FULLOUT="$TMP/tree-unavailable-full.xml"
PATH="$SHIM:$PATH" RW_SHIM_FAIL_ARCHIVE="$ARMFSHA" "$BIN" "$REPO4" --merge-scout=armF --no-cache --legend=full >"$FULLOUT" 2>/dev/null
grep -q 'reason="no_merge_base" (no merge base with HEAD' "$FULLOUT" \
    && ok "T9(d) full: the legend defines both reason= values (no_merge_base spelled verbatim)" \
    || no "T9(d) full: the legend does not define reason=\"no_merge_base\""
grep -q 'reason="tree_unavailable" (a side' "$FULLOUT" \
    && ok "T9(d) full: the legend defines reason=\"tree_unavailable\" verbatim" \
    || no "T9(d) full: the legend does not define reason=\"tree_unavailable\""
grep -q 'ok="1" on an arm row means' "$FULLOUT" \
    && ok "T9(d) full: the legend defines ok= for the ok=\"1\" posture" \
    || no "T9(d) full: the legend does not define the ok=\"1\" posture"
grep -q 'ok="0" means it did not run at all' "$FULLOUT" \
    && ok "T9(d) full: the legend defines ok= for the ok=\"0\" posture" \
    || no "T9(d) full: the legend does not define the ok=\"0\" posture"

# (e) RELEASE LEG: the reason must survive an NDEBUG build. DISCLOSE( sink, why ) writes the sink field (what
#     reason= reads) in EVERY build — only its accompanying debug TRACE is compiled out under NDEBUG — so this
#     asserts the field, not the trace, still reaches the answer when built with -DCMAKE_BUILD_TYPE=Release.
RELBIN="${RIPWIRE_RELEASE_BIN:-}"
# TRAIN 9: CI builds its Release flavour into build/ and sets no env var, so the two fallback paths below
# exist on a developer's machine and nowhere else. The binary under test IS the Release binary on that leg —
# ask --version (the forautobodycheck/kotlincheck reading) before looking for a second one. And when no
# Release build exists anywhere, this arm SKIPs with its reason named: an arm that cannot run is not a
# failure, and the plain-flavour legs still prove (a)-(d).
SHC_FLAVOUR="$( "$BIN" --version 2>/dev/null | sed -nE 's/^[^(]*\(([^,)]*).*/\1/p' )"
case "$SHC_FLAVOUR" in
    Release|RelWithDebInfo|MinSizeRel) [ -z "$RELBIN" ] && RELBIN="$BIN" ;;
esac
if [ -z "$RELBIN" ]; then
    for cand in "$ROOT/relbuild/ripwire" "$ROOT/build_release/ripwire"; do
        [ -x "$cand" ] && RELBIN="$cand" && break
    done
fi
if [ -n "$RELBIN" ] && [ -x "$RELBIN" ]; then
    RELOUT="$TMP/tree-unavailable-release.xml"
    PATH="$SHIM:$PATH" RW_SHIM_FAIL_ARCHIVE="$ARMFSHA" "$RELBIN" "$REPO4" --merge-scout=armF --no-cache >"$RELOUT" 2>"$TMP/release.stderr"
    armAttrs "$RELOUT" armF | grep -q 'ok="0" reason="tree_unavailable"' \
        && ok "T9(e) RELEASE: reason=\"tree_unavailable\" still reaches the answer under NDEBUG" \
        || no "T9(e) RELEASE: reason= missing/wrong under NDEBUG: $( armAttrs "$RELOUT" armF )"
    if [ -s "$TMP/release.stderr" ]; then
        no "T9(e) RELEASE: expected the debug trace to be silent (NDEBUG strips it), but stderr was non-empty: $( head -c 200 "$TMP/release.stderr" )"
    else
        ok "T9(e) RELEASE: the debug trace is silent, as NDEBUG demands — reason= is carrying the disclosure now, not stderr"
    fi
else
    printf '  SKIP  T9(e) RELEASE: this binary is a %s build and no Release one is available (set RIPWIRE_RELEASE_BIN, or build one at $ROOT/relbuild); the Release CI leg runs this arm\n' "${SHC_FLAVOUR:-dev}"
fi

[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILURES"; exit 1
