#!/usr/bin/env bash
# prcontextcheck.sh — gate for Wave-4: --pr-context[=BASEREF] (the no-LLM review-evidence bundle).
#
# Builds a synthetic git repo with a known call graph (helper <- core <- {useCore, test_core}),
# commits it, modifies core.cpp, runs --pr-context, and asserts the changed file's section shows:
#   - its symbols (helper, core)
#   - callers of each (core calls helper; useCore + test_core call core)
#   - blast radius (user.cpp + test/test_core.cpp are dependents)
#   - the affected TEST file (test/test_core.cpp)
#   - owners (single author)
# Plus: determinism (byte-identical run-to-run), xmllint-clean (wrapped in a synthetic root), and the
# non-git / clean-tree degrade paths (comment + files="0", exit 0).
#
# Usage:
#   test/prcontextcheck.sh                          # uses build/ripwire
#   RIPWIRE_BIN=asan/ripwire test/prcontextcheck.sh
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

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "prcontextcheck: BIN=$BIN"

# ── Build a synthetic git repo with a known call graph ──────────────────────────────────────────────
REPO="$TMP/repo"
mkdir -p "$REPO/src" "$REPO/test"
git -C "$REPO" init -q
git -C "$REPO" config user.email "dev@x.com"
git -C "$REPO" config user.name  "Dev"

cat >"$REPO/src/core.cpp" <<'EOF'
int helper() { return 42; }
int core() { return helper(); }
EOF
cat >"$REPO/src/user.cpp" <<'EOF'
extern int core();
int useCore() { return core(); }
EOF
cat >"$REPO/test/test_core.cpp" <<'EOF'
extern int core();
int test_core() { return core() == 42 ? 0 : 1; }
EOF
git -C "$REPO" add -A
GIT_AUTHOR_DATE="2026-06-01T12:00:00" GIT_COMMITTER_DATE="2026-06-01T12:00:00" \
    git -C "$REPO" commit -qm "init"

# Modify core.cpp → working-tree diff (helper changes 42 → 43).
cat >"$REPO/src/core.cpp" <<'EOF'
int helper() { return 43; }
int core() { return helper(); }
EOF

# ── Run --pr-context (working tree) ────────────────────────────────────────────────────────────────
OUT="$( "$BIN" "$REPO" --pr-context --no-cache 2>/dev/null )"
if [ -z "$OUT" ]; then no "pr-context: output is empty"; echo; echo "SOME CHECKS FAILED"; exit 1; fi
echo "pr-context output:"; echo "$OUT"; echo

# exactly one changed file section, and it is core.cpp
echo "$OUT" | grep -q 'files="1"' \
    && ok "one changed file reported" \
    || no "expected files=1, got: $( echo "$OUT" | grep -o 'files="[0-9]*"' | head -1 )"

echo "$OUT" | grep -q '<file p="[^"]*src/core\.cpp" symbols="2">' \
    && ok "changed file section = src/core.cpp with 2 symbols" \
    || no "no <file> section for src/core.cpp with symbols=2"

# changed symbols present
echo "$OUT" | grep -q '<s t="fn" n="helper"' && ok "symbol helper present" || no "symbol helper missing"
echo "$OUT" | grep -q '<s t="fn" n="core"'   && ok "symbol core present"   || no "symbol core missing"

# callers: core calls helper; useCore + test_core call core
echo "$OUT" | grep -q '<caller t="fn" n="core"'      && ok "helper's caller (core) present"      || no "helper's caller (core) missing"
echo "$OUT" | grep -q '<caller t="fn" n="useCore"'   && ok "core's caller (useCore) present"     || no "core's caller (useCore) missing"
echo "$OUT" | grep -q '<caller t="fn" n="test_core"' && ok "core's caller (test_core) present"   || no "core's caller (test_core) missing"

# blast radius includes user.cpp and test_core.cpp
echo "$OUT" | grep -q '<impact ' \
    && ok "impact (blast radius) block present" \
    || no "impact block missing"
echo "$OUT" | grep -q '<f p="[^"]*src/user\.cpp"' && ok "blast radius includes src/user.cpp" || no "blast radius missing src/user.cpp"

# affected test file
echo "$OUT" | grep -q '<test p="[^"]*test/test_core\.cpp"/>' \
    && ok "affected test = test/test_core.cpp" \
    || no "affected test missing test/test_core.cpp"

# owners block present (single author, bf=1). §B3: <owners> now also carries shown=/capped= (the nested
# <author> row disclosure) after bf=, so this pin drops the trailing '>' and matches the attr PREFIX only —
# asserting authors=/bf= meaning, not the exact attribute list (trap-ledger #10 shape).
echo "$OUT" | grep -q '<owners authors="1" bf="1"' \
    && ok "owners: single author, bf=1" \
    || no "owners block wrong: $( echo "$OUT" | grep -o '<owners[^>]*>' | head -1 )"

# ── --pr-context=BASEREF form (diff vs HEAD == working-tree here) ────────────────────────────────────
OUT_REF="$( "$BIN" "$REPO" --pr-context=HEAD --no-cache 2>/dev/null )"
echo "$OUT_REF" | grep -q 'base="HEAD"[^>]*files="1"' \
    && ok "--pr-context=HEAD reports 1 changed file" \
    || no "--pr-context=HEAD wrong header: $( echo "$OUT_REF" | grep -o 'base="[^"]*" files="[0-9]*"' | head -1 )"

# ── xmllint: the bundle is well-formed (wrap in a synthetic root so multiple top nodes are legal) ────
{ echo "<root>"; echo "$OUT"; echo "</root>"; } | xmllint --noout - 2>/dev/null \
    && ok "xmllint clean (wrapped)" \
    || no "xmllint reported malformed XML"

# ── A3-F10: a pure mode flip (chmod, content untouched) must NOT count as a changed file, and the
#    skipped count must be reported so the information isn't silently lost. Flip src/user.cpp to 755
#    (content already committed, unmodified) alongside the real core.cpp content edit above.
# L3 (Linux probe): portable stat reader(s). GNU coreutils and BSD/macOS disagree on both the flag and the
# format directives, and the `stat -f FMT ... || stat -c FMT ...` fallback this gate used is a TRAP. On GNU,
# `-f` means FILESYSTEM status and takes NO format argument, so FMT is parsed as a second FILE: measured on
# coreutils 9.11, `stat -f %i FILE` PRINTS a six-line filesystem block for FILE on stdout and exits 1. The
# `||` arm then appends the right number under six lines of junk -- so a string compare fails, a numeric
# compare dies with "integer expression expected", and a `|| echo MISSING` variant reports MISSING forever
# (a gate that then passes by comparing nothing to nothing). Detect the flavour ONCE, use one form.
if stat --version >/dev/null 2>&1; then   # GNU coreutils
    mode_of(){ stat -c '%a'  "$1" 2>/dev/null; }
else                                     # BSD / macOS
    mode_of(){ stat -f '%Lp' "$1" 2>/dev/null; }
fi
ORIG_MODE="$( mode_of "$REPO/src/user.cpp" )"
chmod 755 "$REPO/src/user.cpp"
MODEOUT="$( "$BIN" "$REPO" --pr-context --no-cache 2>/dev/null )"

echo "$MODEOUT" | grep -q 'files="1"' \
    && ok "A3-F10: mode-only chmod not counted as a changed file (still files=1)" \
    || no "A3-F10: chmod inflated the changed-file count: $( echo "$MODEOUT" | grep -o 'files="[0-9]*"' | head -1 )"

echo "$MODEOUT" | grep -qv '<file p="[^"]*src/user\.cpp"' \
    && ok "A3-F10: chmod-only src/user.cpp does NOT appear as a changed <file>" \
    || no "A3-F10: src/user.cpp (chmod-only) wrongly appeared as a changed file"

echo "$MODEOUT" | grep -q 'skipped_mode_only="1"' \
    && ok "A3-F10: skipped_mode_only=\"1\" reported on <pr-context>" \
    || no "A3-F10: skipped_mode_only missing/wrong: $( echo "$MODEOUT" | grep -o 'skipped_mode_only="[0-9]*"' | head -1 )"

# restore the fixture's mode so later checks in this script see the original tree.
chmod "$ORIG_MODE" "$REPO/src/user.cpp"

# ── Determinism ─────────────────────────────────────────────────────────────────────────────────────
A="$( "$BIN" "$REPO" --pr-context --no-cache 2>/dev/null )"
B="$( "$BIN" "$REPO" --pr-context --no-cache 2>/dev/null )"
[ "$A" = "$B" ] && ok "determinism: byte-identical run-to-run" || no "determinism: output differs"

# ── Degrade: non-git dir → comment + files=0, exit 0 ────────────────────────────────────────────────
NG="$TMP/nongit"; mkdir -p "$NG"; echo 'int f(){return 0;}' >"$NG/a.cpp"
NGOUT="$( "$BIN" "$NG" --pr-context --no-cache 2>/dev/null )"; NGRC=$?
{ [ "$NGRC" -eq 0 ] && echo "$NGOUT" | grep -q 'files="0"'; } \
    && ok "non-git dir degrades (files=0, exit 0)" \
    || no "non-git degrade wrong (rc=$NGRC): $NGOUT"

# ── Degrade: clean tree → files=0, exit 0 ───────────────────────────────────────────────────────────
CLEAN="$TMP/clean"; mkdir -p "$CLEAN"; git -C "$CLEAN" init -q
git -C "$CLEAN" config user.email a@x.com; git -C "$CLEAN" config user.name A
echo 'int f(){return 0;}' >"$CLEAN/a.cpp"; git -C "$CLEAN" add -A; git -C "$CLEAN" commit -qm init
COUT="$( "$BIN" "$CLEAN" --pr-context --no-cache 2>/dev/null )"; CRC=$?
{ [ "$CRC" -eq 0 ] && echo "$COUT" | grep -q 'files="0"'; } \
    && ok "clean tree degrades (files=0, exit 0)" \
    || no "clean-tree degrade wrong (rc=$CRC): $COUT"

# ── §P11.7: files ordered by BLAST RADIUS, and a doc file's headings collapsed to a count ───────────
#
# The finding: the flagship review bundle emitted its <file> sections in PATH order, so on this repo
# `CHANGELOG.md` led and spent the reader's whole first screen on 31 markdown headings rendered as
# callers="0" symbol rows, with the files something actually depends on below the fold.
#
# Two fixes, both about what the first screen says:
#   (a) files are ordered by transitive-dependent count DESC (path breaks ties), so the most
#       consequential file leads. Still a total, deterministic order.
#   (b) a doc file's section symbols collapse into one sections="N" count on <changed-symbols> instead
#       of one row each. A section has no callers by construction, so every one of those rows carried
#       the same zero — the count is the only fact they held. count= is untouched and still counts EVERY
#       symbol, so count minus sections is exactly the number of rows that follow, and a file with no
#       section symbols emits no sections= at all (every code file stays byte-identical).
#
# Its own repo rather than the fixture above: that one asserts files="1", and this arm needs a diff
# that touches a doc AND a source file at once.
DOCREPO="$TMP/docrepo"
mkdir -p "$DOCREPO/src"
git -C "$DOCREPO" init -q
git -C "$DOCREPO" config user.email "dev@x.com"
git -C "$DOCREPO" config user.name  "Dev"

# AAA_changelog.md sorts FIRST alphabetically and has ZERO dependents; src/engine.cpp sorts second and
# is what user.cpp depends on — so path order and impact order are exact opposites here.
cat >"$DOCREPO/AAA_changelog.md" <<'EOF'
# Changelog

## 1.0 — first

Some prose.

## 1.1 — second

More prose.

## 1.2 — third

Even more prose.
EOF
cat >"$DOCREPO/src/engine.cpp" <<'EOF'
int helper() { return 42; }
int core() { return helper(); }
EOF
cat >"$DOCREPO/src/user.cpp" <<'EOF'
extern int core();
int useCore() { return core(); }
EOF
git -C "$DOCREPO" add -A
GIT_AUTHOR_DATE="2026-06-01T12:00:00" GIT_COMMITTER_DATE="2026-06-01T12:00:00" \
    git -C "$DOCREPO" commit -qm "init"

# the diff: one doc file and one source file, both changed
cat >>"$DOCREPO/AAA_changelog.md" <<'EOF'

## 1.3 — fourth

Newest prose.
EOF
cat >"$DOCREPO/src/engine.cpp" <<'EOF'
int helper() { return 43; }
int core() { return helper(); }
EOF

"$BIN" "$DOCREPO" --pr-context --no-cache >"$TMP/docpr" 2>/dev/null
echo "pr-context (doc + src diff):"; cat "$TMP/docpr"; echo

grep -q 'files="2"' "$TMP/docpr" \
    && ok "§P11.7: both changed files reported (ordering drops nothing)" \
    || no "§P11.7: expected files=2, got $( grep -o 'files="[0-9]*"' "$TMP/docpr" | head -1 )"

# (a) the SOURCE file leads, though the doc sorts first alphabetically
firstFile="$( tr '<' '\n' <"$TMP/docpr" | sed -n 's/^file p="\([^"]*\)".*/\1/p' | head -1 )"
case "$firstFile" in
    src/engine.cpp|*/src/engine.cpp) ok "§P11.7: src/engine.cpp emits FIRST (impact order, not alphabetical)" ;;
    *)                no "§P11.7: first <file> is '$firstFile', want src/engine.cpp" ;;
esac
lastFile="$( tr '<' '\n' <"$TMP/docpr" | sed -n 's/^file p="\([^"]*\)".*/\1/p' | tail -1 )"
case "$lastFile" in
    AAA_changelog.md|*/AAA_changelog.md) ok "§P11.7: the zero-dependent doc file sorts LAST" ;;
    *)                  no "§P11.7: last <file> is '$lastFile', want AAA_changelog.md" ;;
esac

# (b) the doc's headings are one count, not one row each. The exact heading total is the ingest's
#     business (it models the document structure, not this gate), so assert the CONTRACT instead: every
#     symbol in a pure-doc file is a section, count= still counts them all, and none of them became a row.
docSym="$(  tr '<' '\n' <"$TMP/docpr" | sed -n 's/^changed-symbols count="\([0-9]*\)" sections="[0-9]*".*/\1/p' | head -1 )"
docSec="$(  tr '<' '\n' <"$TMP/docpr" | sed -n 's/^changed-symbols count="[0-9]*" sections="\([0-9]*\)".*/\1/p' | head -1 )"

{ [ -n "$docSec" ] && [ "$docSec" -ge 4 ]; } \
    && ok "§P11.7: the doc file reports sections=\"$docSec\" (its headings, collapsed into a count)" \
    || { no "§P11.7: no plausible sections= on the doc file"; grep -o '<changed-symbols[^>]*>' "$TMP/docpr"; }

[ "$( grep -c '<s t="sec"' "$TMP/docpr" )" = "0" ] \
    && ok "§P11.7: zero per-heading symbol rows survive the collapse" \
    || no "§P11.7: $( grep -c '<s t="sec"' "$TMP/docpr" ) per-heading rows still emitted"

# count= must still count EVERY symbol — the collapse is a row-shape change, not a lost fact
{ [ -n "$docSym" ] && [ "$docSym" = "$docSec" ]; } \
    && ok "§P11.7: count=$docSym still counts every symbol (count minus sections = the rows that follow: 0)" \
    || { no "§P11.7: changed-symbols count ($docSym) and sections ($docSec) disagree"; grep -o '<changed-symbols[^>]*>' "$TMP/docpr"; }

# a code file must be byte-identical to before — no sections= attribute at all
tr '<' '\n' <"$TMP/docpr" | grep '^changed-symbols' | grep -v 'sections=' | grep -q 'count=' \
    && ok "§P11.7: the code file's changed-symbols carries NO sections= (code output unchanged)" \
    || no "§P11.7: sections= leaked onto a file with no section symbols"

{ echo "<root>"; cat "$TMP/docpr"; echo "</root>"; } | xmllint --noout - 2>/dev/null \
    && ok "§P11.7: xmllint clean (wrapped)" \
    || no "§P11.7: malformed XML"

"$BIN" "$DOCREPO" --pr-context --no-cache >"$TMP/docpr2" 2>/dev/null
diff -q "$TMP/docpr" "$TMP/docpr2" >/dev/null \
    && ok "§P11.7: determinism (byte-identical run-to-run)" \
    || no "§P11.7: impact ordering is non-deterministic"

# ── Summary ─────────────────────────────────────────────────────────────────────────────────────────
echo
# §P10.4: dependents>0 beside files="0" was an impossible-looking state (files= excluded changed files
# while dependents= did not). files= is now the reached TOTAL; the invariant is directly checkable.
if "$BIN" "$ROOT" --pr-context=HEAD~3 2>/dev/null | grep -qE 'dependents="[1-9][0-9]*" files="0"'; then
    no "P10.4 regression: an <impact> row shows dependents>0 beside files=0"
else
    ok "P10.4 invariant: dependents>0 always implies files>0 (files= is the reached total)"
fi

if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "SOME CHECKS FAILED"; exit 1; fi
