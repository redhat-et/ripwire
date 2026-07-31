#!/usr/bin/env bash
# prmaskanchorcheck.sh — gate for the --pr-context changed-file JOIN: the ONE offset-derived join
# (gitmine.h), no private anchored-then-suffix copy.
#
# git reports REPO-relative paths ("src/util.py"); ing.files carry the root spelling the user passed. The
# join used to be a bare SUFFIX match with a '/' boundary check, which is ambiguous the moment a tree
# vendors a copy of its own layout: a changed `src/util.py` ALSO matched `deps/src/util.py`, and the
# bundle spent a full evidence section (symbols, callers, blast radius, co-change, owners) on a file the
# diff never touched — a phantom, the same class §ANCHORING removed on the revision side.
#
# The first fix tried `<root>/<git path>` exactly and kept the suffix match as a fallback for the SUBDIR-root
# form. §H6b deleted BOTH halves: the anchored pass only fires when the crawl root IS the repo toplevel, and
# the fallback marked EVERY boundary-suffix match — the same over-permissive join §H6 removed from gitmine.h,
# surviving here in a third private copy. The verb now calls the ONE shared join
# (ctx::markChangedFilesFromGitPaths), which derives the git-root→index-root offset per root and binds each
# changed path to the one file whose own derived git spelling it is, or to nothing.
#
# Asserts:
#   - the vendored twin (deps/src/util.py) is NOT a section, and files="1"
#   - the genuinely changed src/util.py IS a section
#   - the same verdict for a relative root ("." and "repo") — the anchoring is string-based, not cwd-based
#   - the SUBDIR-root form still finds its file, in BOTH spellings ("repo/src" AND "." from inside it —
#     §H6b: the second one returned a FALSE ZERO plus a false sentence while the first passed)
#   - a change OUTSIDE the crawl root marks nothing inside it (the over-mark half of §H6b)
#   - a vendored file that REALLY changed is still reported (no over-narrowing)
#   - determinism + xmllint-clean
#
# Usage:
#   test/prmaskanchorcheck.sh                            # uses build/ripwire
#   test/prmaskanchorcheck.sh /path/to/other/ripwire     # positional binary (the RED run)
#   RIPWIRE_BIN=asan/ripwire test/prmaskanchorcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

# trap #15: the pr-context LEGEND text itself contains the literal files="0" (it explains the attribute), so a
# document-wide grep for a count reads the tool's own prose back. Anchor every count read to the ROOT ELEMENT.
hdrfiles(){ grep -o '<pr-context[^>]*>' "$1" | head -1 | grep -o 'files="[0-9]*"' | head -1 | grep -o '[0-9]*'; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "prmaskanchorcheck: BIN=$BIN"

# ── fixture: a tree that vendors a copy of its own layout ─────────────────────────────────────────────
REPO="$TMP/repo"
mkdir -p "$REPO/src" "$REPO/deps/src"
git -C "$REPO" init -q
git -C "$REPO" config user.email "dev@x.com"
git -C "$REPO" config user.name  "Dev"

printf 'def util():\n    return 1\n'     >"$REPO/src/util.py"
printf 'def vendored():\n    return 1\n' >"$REPO/deps/src/util.py"
git -C "$REPO" add -A
GIT_AUTHOR_DATE="2026-06-01T12:00:00" GIT_COMMITTER_DATE="2026-06-01T12:00:00" \
    git -C "$REPO" commit -qm "init"

printf 'def util():\n    return 2\n' >"$REPO/src/util.py"
GIT_AUTHOR_DATE="2026-06-01T13:00:00" GIT_COMMITTER_DATE="2026-06-01T13:00:00" \
    git -C "$REPO" commit -qam "change only src/util.py"

# sanity: git really did change exactly one path
[ "$( git -C "$REPO" diff --numstat HEAD~1 HEAD | wc -l | tr -d ' ' )" = 1 ] \
    || no "fixture: expected exactly one changed path in the diff"

OUT="$TMP/out.xml"
"$BIN" "$REPO" --pr-context=HEAD~1 >"$OUT" 2>/dev/null

grep -q '<file p="[^"]*deps/src/util\.py"' "$OUT" && no "the vendored twin deps/src/util.py must NOT be a section (phantom)" \
                                                  || ok "the vendored twin is not a section (phantom removed)"
grep -q '<file p="[^"]*[^s]/src/util\.py"' "$OUT" && ok "the genuinely changed src/util.py IS a section" \
                                                  || no "the genuinely changed src/util.py must still be a section"
[ "$( hdrfiles "$OUT" )" = "1" ] && ok 'files="1" (only the real change counted)' \
                                 || no "expected files=1; got: $( hdrfiles "$OUT" )"

# ── the anchoring is string-based: a relative root spelling behaves identically ────────────────────────
( cd "$REPO" && "$BIN" . --pr-context=HEAD~1 >"$TMP/dot.xml" 2>/dev/null )
grep -q '<file p="\./deps/src/util\.py"' "$TMP/dot.xml" && no 'root "." : the vendored twin must NOT be a section' \
                                                        || ok 'root "." : the vendored twin is not a section'
grep -q '<file p="\./src/util\.py"' "$TMP/dot.xml" && ok 'root "." : the real change is a section' \
                                                   || no 'root "." : the real change must be a section'

( cd "$TMP" && "$BIN" repo --pr-context=HEAD~1 >"$TMP/rel.xml" 2>/dev/null )
grep -q '<file p="repo/deps/src/util\.py"' "$TMP/rel.xml" && no 'root "repo": the vendored twin must NOT be a section' \
                                                          || ok 'root "repo": the vendored twin is not a section'
grep -q '<file p="repo/src/util\.py"' "$TMP/rel.xml" && ok 'root "repo": the real change is a section' \
                                                     || no 'root "repo": the real change must be a section'

# ── a root that is a SUBDIR of the repo still resolves ────────────────────────────────────────────────
( cd "$TMP" && "$BIN" repo/src --pr-context=HEAD~1 >"$TMP/sub.xml" 2>/dev/null )
grep -q '<file p="repo/src/util\.py"' "$TMP/sub.xml" && ok "subdir root 'repo/src' finds its changed file" \
                                                     || no "subdir root 'repo/src' must find its changed file"

# ── §H6b — the SAME subdir, spelled "." from inside it. This is the spelling the old private join lost.
# The arm above passes on the pre-§H6b binary by luck of spelling: index paths read "repo/src/util.py", which
# ends with git's "src/util.py", so the suffix fallback bound it. Spell the root "." and every index path
# reads "./util.py", which is NOT a boundary-suffix of "src/util.py" — the anchored pass misses (the root is
# not the repo toplevel), the fallback finds nothing, and the verb reported files="0" plus the sentence
# "no changed files in the index (clean tree, or the diff touched only non-indexed files)". Both halves false:
# the file IS indexed, as ./util.py, and it DID change. Measured on the pre-fix binary; the same tree's
# already-fixed seam answered correctly from the same cwd (--for churn=, --owners files=).
( cd "$REPO/src" && "$BIN" . --pr-context=HEAD~1 >"$TMP/dotsub.xml" 2>/dev/null )
DOTSUBFILES="$( hdrfiles "$TMP/dotsub.xml" )"
[ "${DOTSUBFILES:-0}" = "1" ] && ok "subdir root '.' finds its changed file: files=\"$DOTSUBFILES\" (§H6b false zero closed)" \
                              || no "subdir root '.' reports files=\"${DOTSUBFILES:-<none>}\", expected 1 (§H6b false zero)"
grep -q '<file p="\./util\.py"' "$TMP/dotsub.xml" && ok "subdir root '.' lists it at its own indexed spelling ./util.py" \
                                                  || no "subdir root '.' must list ./util.py"
grep -q 'no changed files in the index' "$TMP/dotsub.xml" \
    && no "subdir root '.' still prints 'no changed files in the index' for a tree whose indexed file changed" \
    || ok "subdir root '.' does not print the false 'no changed files' sentence"
# the sibling seams, from the same cwd, are the control: they were always right, which is what made the
# private join's answer a DISAGREEMENT rather than a limitation of the corpus.
( cd "$REPO/src" && "$BIN" . --owners >"$TMP/dotown.xml" 2>/dev/null )
grep -q 'files="[1-9]' "$TMP/dotown.xml" && ok "control: --owners from the same cwd binds git history (the seam that was already fixed)" \
                                         || no "control FAILED: --owners from '.' binds nothing — the fixture, not the join, is at fault"

# ── §H6b, the OVER-MARK half: a change OUTSIDE the crawl root must mark NOTHING inside it ─────────────
# The old fallback marked every boundary-suffix match, so a changed `b/util.py` that lives OUTSIDE the crawl
# root bound to `<root>/x/b/util.py` INSIDE it — a full evidence section (symbols, callers, blast radius,
# co-change, owners) for a file the diff never touched, at exit 0. Measured pre-fix: files="1" naming
# ./x/b/util.py for a diff whose only row was b/util.py.
OUTREPO="$TMP/outrepo"
mkdir -p "$OUTREPO/a/x/b" "$OUTREPO/b"
git -C "$OUTREPO" init -q
git -C "$OUTREPO" config user.email "dev@x.com"
git -C "$OUTREPO" config user.name  "Dev"
printf 'def inside():\n    return 1\n'  >"$OUTREPO/a/x/b/util.py"
printf 'def outside():\n    return 1\n' >"$OUTREPO/b/util.py"
printf 'def amain():\n    return 2\n'   >"$OUTREPO/a/main.py"
git -C "$OUTREPO" add -A
git -C "$OUTREPO" commit -qm init
printf 'def outside():\n    return 2\n' >"$OUTREPO/b/util.py"
git -C "$OUTREPO" commit -qam "change ONLY the file outside the crawl root"
[ "$( git -C "$OUTREPO" diff --numstat HEAD~1 HEAD | wc -l | tr -d ' ' )" = 1 ] \
    || no "fixture: expected exactly one changed path in the outside-root diff"
( cd "$OUTREPO/a" && "$BIN" . --pr-context=HEAD~1 >"$TMP/outside.xml" 2>/dev/null )
OUTFILES="$( hdrfiles "$TMP/outside.xml" )"
[ "${OUTFILES:-1}" = "0" ] && ok "a change outside the crawl root marks nothing inside it: files=\"0\"" \
                           || no "phantom: files=\"${OUTFILES:-?}\" for a diff that touched no indexed file ($( grep -o '<file p="[^"]*"' "$TMP/outside.xml" | head -1 ))"
grep -q '<file p="[^"]*x/b/util\.py"' "$TMP/outside.xml" \
    && no "phantom section for ./x/b/util.py, which the diff never touched (§H6b over-mark)" \
    || ok "no phantom section for the same-tailed file inside the root"
# and THAT zero must still carry its sentence — the honest empty bundle, not a silently blank one
grep -q 'no changed files in the index' "$TMP/outside.xml" \
    && ok "the genuine zero still says 'no changed files in the index' (honest empty, not silent)" \
    || no "a genuine zero lost its explanatory sentence"

# ── no over-narrowing: a vendored file that REALLY changed is still reported ───────────────────────────
printf 'def vendored():\n    return 2\n' >"$REPO/deps/src/util.py"
GIT_AUTHOR_DATE="2026-06-01T14:00:00" GIT_COMMITTER_DATE="2026-06-01T14:00:00" \
    git -C "$REPO" commit -qam "change the vendored copy"
"$BIN" "$REPO" --pr-context=HEAD~1 >"$TMP/vend.xml" 2>/dev/null
grep -q '<file p="[^"]*deps/src/util\.py"' "$TMP/vend.xml" && ok "a vendored file that really changed IS reported" \
                                                           || no "a vendored file that really changed must be reported"
grep -q '<file p="[^"]*[^s]/src/util\.py"' "$TMP/vend.xml" && no "src/util.py must NOT be a section for a deps-only change" \
                                                           || ok "src/util.py is not a section for a deps-only change"

# ── determinism + G4 ──────────────────────────────────────────────────────────────────────────────────
"$BIN" "$REPO" --pr-context=HEAD~1 >"$TMP/a.xml" 2>/dev/null
"$BIN" "$REPO" --pr-context=HEAD~1 >"$TMP/b.xml" 2>/dev/null
cmp -s "$TMP/a.xml" "$TMP/b.xml" && ok "deterministic (byte-identical run-to-run)" || no "deterministic"

if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$OUT" >/dev/null 2>&1 && ok "G4: xmllint-clean" || no "G4: xmllint-clean"
else
    ok "G4: xmllint unavailable — skipped"
fi

[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILURES"; exit 1
