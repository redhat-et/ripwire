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
. "$ROOT/test/lib/statcompat.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
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
# L1 (2026-09-19): the CLI default legend is compact; the run-clause and F-legend/F6 arms read the FULL legend's
# clauses (present AND absent), so those runs and their controls ask for --legend=full, the pre-change default.
OUT="$( "$BIN" "$REPO" --pr-context --no-cache --legend=full 2>/dev/null )"
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
if echo "$OUT" | grep -q '<s t="fn" n="helper"'; then ok "symbol helper present"; else no "symbol helper missing"; fi
if echo "$OUT" | grep -q '<s t="fn" n="core"'; then ok "symbol core present"; else no "symbol core missing"; fi

# callers: core calls helper; useCore + test_core call core
if echo "$OUT" | grep -q '<caller t="fn" n="core"'; then ok "helper's caller (core) present"; else no "helper's caller (core) missing"; fi
if echo "$OUT" | grep -q '<caller t="fn" n="useCore"'; then ok "core's caller (useCore) present"; else no "core's caller (useCore) missing"; fi
if echo "$OUT" | grep -q '<caller t="fn" n="test_core"'; then ok "core's caller (test_core) present"; else no "core's caller (test_core) missing"; fi

# blast radius includes user.cpp and test_core.cpp
echo "$OUT" | grep -q '<impact ' \
    && ok "impact (blast radius) block present" \
    || no "impact block missing"
if echo "$OUT" | grep -q '<f p="[^"]*src/user\.cpp"'; then ok "blast radius includes src/user.cpp"; else no "blast radius missing src/user.cpp"; fi

# affected test file
# M21(b) re-pin (capture-audit 2026-09-04): a tests_to_run row now always carries a run recipe or the
# explicit run_unknown="1" disclosure, so the row NEVER self-closes straight after p= (test/testrowruncheck.sh
# is the family gate). Pinned to the NEW contract — the path AND a disclosure — not loosened to a prefix match.
echo "$OUT" | grep -qE '<test p="[^"]*test/test_core\.cpp"( run="[^"]*"| run_unknown="1")/>' \
    && ok "affected test = test/test_core.cpp, with its run recipe or run_unknown disclosure" \
    || no "affected test missing test/test_core.cpp (or its run=/run_unknown= disclosure)"

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
if [ "$A" = "$B" ]; then ok "determinism: byte-identical run-to-run"; else no "determinism: output differs"; fi

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

# ── E1 (2026-09-12): the run=/run_unknown=/<g> clause rides only a document whose corpus CAN carry a test row ─
# The legend is written and priced before the files are rendered (the budget ladder fits est_tokens= to
# the envelope), so this bundle cannot gate the clause on the rows it ends up emitting the way --affected
# does. It gates on the one fact known before rendering that decides whether a <test>/<g> row is possible
# at all: does the corpus hold a test file. A corpus without one paid 330 B for a rule about rows it can
# never emit — measured on test/defaultceilingcheck.sh's 120-file fixture: est_tokens 7,989 -> 8,025,
# over the 8,000-token default budget. Red on the pre-fix binary (the clause rode every bundle).
{ echo "$OUT" | grep -q 'run_unknown=' && echo "$OUT" | grep -q '<g n= p='; } \
    && ok "run clause: a corpus WITH a test file carries run_unknown= and the <g n= p=> definition in its legend" \
    || no "run clause: the fixture has test/test_core.cpp yet the legend does not define run_unknown=/<g>"
NT="$TMP/notests"; mkdir -p "$NT/src"; git -C "$NT" init -q
git -C "$NT" config user.email a@x.com; git -C "$NT" config user.name A
printf 'int g( int x ) { return x; }\n' >"$NT/src/a.cpp"; git -C "$NT" add -A; git -C "$NT" commit -qm init
printf 'int h( int x ) { return g( x ) + 1; }\n' >>"$NT/src/a.cpp"
NTOUT="$( "$BIN" "$NT" --pr-context --no-cache --legend=full 2>/dev/null )"
if echo "$NTOUT" | grep -q 'files="1"'; then
    echo "$NTOUT" | grep -q 'run_unknown=' \
        && no "run clause: a corpus with NO test file still pays for the run=/run_unknown=/<g> clause" \
        || ok "run clause: a corpus with no test file carries no run=/run_unknown=/<g> clause (nothing it can be a rule about)"
else
    no "run clause: the no-test fixture did not produce a one-file bundle: $( echo "$NTOUT" | head -c 300 )"
fi

# ── E1 follow-up (CodeRabbit on #214, third thread): the clause follows the RENDERED rows, not the corpus ──
# "the corpus holds a test file" over-approximated: a test file elsewhere in the corpus, or a trim level whose
# testCap is 0, still bought the clause for a document that renders no test row. The legend is now built after
# the level is chosen and priced per candidate level from that level's OWN ROW COUNT — the emitter reports how
# many test files it wrote (PrTrimRender::testFiles) and both the pricer and the writer read that one number.
# A first fix grepped the rendered body for a `<test p="`/`<g ` opener instead; the review of #214 found the
# same mistake in partition.h, where a CDATA body quoting the literal text of the element answered yes with
# zero rows, so neither place asks the bytes any more. Two fixtures, both RED on 7ab0956a:
#   (i)  a test file OUTSIDE the selected range: test/t_other.cpp exercises src/b.cpp, and only src/a.cpp is
#        in the diff — no changed file reaches a test, so no row renders, so no clause;
#   (ii) the existing fixture (test_core.cpp IS reached) under a budget small enough that the ladder lands on a
#        level with testCap=0 (L2+): no row renders, so no clause even though the corpus and the diff both have one.
OT="$TMP/othertest"; mkdir -p "$OT/src" "$OT/test"; git -C "$OT" init -q
git -C "$OT" config user.email a@x.com; git -C "$OT" config user.name A
printf 'int ga( int x ) { return x; }\n' >"$OT/src/a.cpp"
printf 'int gb( int x ) { return x * 2; }\n' >"$OT/src/b.cpp"
printf 'int gb( int x );\nint test_gb( void ) { return gb( 1 ); }\n' >"$OT/test/t_other.cpp"
git -C "$OT" add -A; git -C "$OT" commit -qm init
printf 'int ha( int x ) { return ga( x ) + 1; }\n' >>"$OT/src/a.cpp"
OTOUT="$( "$BIN" "$OT" --pr-context --no-cache 2>/dev/null )"
# rows live in the BODY, after the root's start tag — the legend's own `<g n= p=…>` definition must not read as a row
OTBODY="${OTOUT#*<pr-context }"
if echo "$OTOUT" | grep -q 'files="1"' && ! echo "$OTBODY" | grep -qE '<(test|g) '; then
    echo "$OTOUT" | grep -q 'run_unknown=' \
        && no "run clause (i): a test file OUTSIDE the selected range still bought the clause for a document with no test row" \
        || ok "run clause (i): a test file outside the selected range buys no clause (no <test>/<g> row renders)"
else
    no "run clause (i): the other-test fixture did not produce a one-file, zero-test-row bundle: $( echo "$OTOUT" | head -c 300 )"
fi
TC0=""
for n in 300 400 500 600 800 1000 1200 1500; do
    o="$( "$BIN" "$REPO" --pr-context --no-cache --max-tokens=$n 2>/dev/null )"
    lvl="$( echo "$o" | grep -oE 'trim_level="[0-9]+"' | head -1 | grep -oE '[0-9]+' )"
    body="${o#*<pr-context }"
    if [ -n "$lvl" ] && [ "$lvl" -ge 2 ] && echo "$body" | grep -q '<tests count="[1-9]' && ! echo "$body" | grep -qE '<(test|g) '; then TC0=$n; TC0OUT="$o"; break; fi
done
if [ -z "$TC0" ]; then
    no "run clause (ii): no --max-tokens in 300..1500 landed on a testCap=0 level with tests counted but no row — the arm cannot bite"
else
    echo "$TC0OUT" | grep -q 'run_unknown=' \
        && no "run clause (ii): at --max-tokens=$TC0 (trim_level>=2, testCap=0) the document renders no test row yet still pays for the clause" \
        || ok "run clause (ii): at --max-tokens=$TC0 (trim_level>=2, testCap=0) no test row renders and no clause is paid for"
fi

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

# ── (F) THE EMITTER THROWS: renderToString releases what it owns, discloses, and the document still ships ──
#
# THE FINDING (CodeRabbit on #214, src/infra/emit.h). `emit( m )` was called outside any handler. A throw
# from it — std::bad_alloc out of the std::format fallback is the reachable one — skipped the fclose, the
# free, the alert and the documented empty-result fallback in one jump: the memstream and its buffer leaked
# and the caller got an exception where its contract says it gets ok == false.
#
# A throw path is unreachable from a gate by ordinary means, so this drives the in-source fault switch
# INFRA_FAULT_RENDER_EMIT_THROW=1 — serialize.h's isChargeBufferFaultInjected idiom (the INFRA_ prefix, not
# this project's, because src/infra/ is built to travel and test/infraportcheck.sh (C) refuses a layer file
# that names the host — it caught this switch's first spelling), and therefore living
# ONLY on the non-NDEBUG flavour, the same flavour DISCLOSE lives on. So, like estchargecheck #14,
# this arm establishes that flavour with its OWN probe rather than assuming it, and must never pass for lack
# of an alert it could not have seen.
#
# THE ARM BRINGS ITS OWN REPOSITORY, because every anchor into the live one is a property of the BRANCH.
# A bare `--pr-context` reads `git diff HEAD`, so on a clean checkout the change set is empty, no trim level
# is ever RENDERED, renderToString is never called, and the arm finds no alert and blames the seam for a
# fixture that asked it nothing. Anchoring at HEAD~3 fixed that locally and broke on CI, which checks out the
# PR's MERGE ref: there HEAD~1 is main's tip and three back is a different set of commits entirely, one that
# named no file this verb reports. Both spellings were the same mistake — test/gatecheck's "the gate fixture
# is the live repo" trap — and counting commits differently would only move it.
#
# So the fixture is BUILT here: a throwaway repo, two commits, one edited file. It is identical on a clean
# checkout, a dirty tree, a merge ref and a shallow clone, because none of those are inputs to it. (The live
# repo is still used for the charge-buffer probe below, which asks the BINARY a question and reads no git
# history at all.)
PRC_FAULT_OUT="$TMP/f_dg.out"; PRC_FAULT_ERR="$TMP/f_dg.err"
PRC_FIX="$TMP/f_repo"
mkdir -p "$PRC_FIX/src"
cat > "$PRC_FIX/src/core.cpp" <<'PRCEOF'
int coreHelper( int y )
{
    return y + 1;
}

int coreCompute( int x )
{
    return coreHelper( x ) * 2;
}
PRCEOF
cat > "$PRC_FIX/src/caller.cpp" <<'PRCEOF'
int coreCompute( int x );

int callerEntry( int n )
{
    return coreCompute( n ) + coreCompute( n + 1 );
}
PRCEOF
cat > "$PRC_FIX/src/other.cpp" <<'PRCEOF'
int unrelatedLeaf( int z )
{
    return z - 1;
}
PRCEOF
(
    cd "$PRC_FIX" \
    && git init -q \
    && git config user.email gate@example.invalid \
    && git config user.name gate \
    && git add -A \
    && git commit -qm base
) >/dev/null 2>&1
PRC_FAULT_BASE="$( cd "$PRC_FIX" && git rev-parse HEAD 2>/dev/null )"
# the second commit: ONE file changes, so the range names exactly the file whose <f> row the rows below count
cat > "$PRC_FIX/src/core.cpp" <<'PRCEOF'
int coreHelper( int y )
{
    return y + 2;
}

int coreCompute( int x )
{
    return coreHelper( x ) * 3;
}
PRCEOF
( cd "$PRC_FIX" && git add -A && git commit -qm edit ) >/dev/null 2>&1
if [ -z "$PRC_FAULT_BASE" ]; then
    no "(F) could not build the throwaway git fixture (no base sha) — the emitter-throw arm cannot run"
fi
#
# WHICH FLAVOUR IS THIS BINARY? ASK IT, WITH AN ALERT IT IS KNOWN TO EMIT.
# Both the fault switch and DISCLOSE exist only on the non-NDEBUG flavour, so on a Release build
# there is no alert to see and this arm must not read that silence as a regression. The first version of the
# probe settled the question by grepping `--version` for "release" — a LABEL, whose spelling is not this
# gate's to depend on, and which the plain build spells "dev" and the Release build spells neither. It
# answered "this flavour can see alerts" on macOS Release and then failed the SEAM for the missing alert:
# CI red on one job, for a property of the gate, not of the code under test. The binary is asked directly
# now, with the SIBLING fault switch (serialize.h's charge buffer), whose alert is independent of everything
# this arm changes — if that one speaks, this binary can speak, and only then is the emitter-throw alert
# required of it.
INFRA_PROBE_ERR="$TMP/f_probe.err"
RIPWIRE_FAULT_CHARGE_BUFFER=1 "$BIN" "$ROOT/src" --top-k=5 --pack-signatures --no-cache >/dev/null 2>"$INFRA_PROBE_ERR"
if grep -aq 'open_memstream failed' "$INFRA_PROBE_ERR"; then PRC_ALERTS=1; else PRC_ALERTS=0; fi
INFRA_FAULT_RENDER_EMIT_THROW=1 "$BIN" "$PRC_FIX" --pr-context="$PRC_FAULT_BASE" --legend=full >"$PRC_FAULT_OUT" 2>"$PRC_FAULT_ERR"
prc_f_rc=$?
# and the range must actually name a file, or every assertion below is vacuous
if [ "$( grep -aoc '<f ' "$PRC_FAULT_OUT" 2>/dev/null || echo 0 )" = "0" ] && ! grep -aq 'THREW' "$PRC_FAULT_ERR"; then
    "$BIN" "$PRC_FIX" --pr-context="$PRC_FAULT_BASE" --legend=full 2>/dev/null | grep -aq '<f ' \
        || no "(F) precondition: --pr-context over the fixture repo names no changed file, so the emitter-throw arm asserts nothing"
fi
#
# (F-legend) WHY THE est-unmeasured LABEL EXISTS, and what it costs a healthy document: NOTHING. The
# degrade's only signal used to be DISCLOSE, which Diagnostics.h compiles to `do {} while (0)`
# under NDEBUG — so the binary a user installs printed an est_tokens priced from an EMPTY body with nothing
# at all saying the number was never measured (review of #214; non-negotiable #3). The fix discloses it in
# truncated=, the attribute that already carries this class of fact, and DEFINES the label in the legend.
#
# The clause is gated on the label, exactly as E1 gated the run-hint clause on rows and for the same measured
# reason: unconditional, its ~390 B put test/defaultceilingcheck.sh's fixture (7,989 of the 8,000 default,
# 11 tokens spare) at 8,037 — over budget, on a document with nothing unmeasured about it. So this arm is
# FLAVOUR-INDEPENDENT in the only form that is honest: a healthy document states no such fact and pays no
# bytes for it, and (F6) below holds the defined-wherever-emitted rule that prbudgetcheck (#10) already
# holds budget-floor-exceeded to.
"$BIN" "$PRC_FIX" --pr-context="$PRC_FAULT_BASE" --legend=full >"$TMP/f_ctl_legend.out" 2>/dev/null
if grep -aq 'est-unmeasured' "$TMP/f_ctl_legend.out"; then
    no "(F-legend) an undegraded --pr-context document carries est-unmeasured — either a false disclosure or a clause charged to every reader who does not need it"
else
    ok "(F-legend) an undegraded document neither claims est-unmeasured nor pays for its definition (label-gated, like E1's run clause)"
fi

if [ "$PRC_ALERTS" -eq 0 ]; then
    # NO-ALERT FLAVOUR (NDEBUG). The fault switch is `constexpr false` here and the alert macro is compiled
    # out, so this arm cannot exercise the degrade at all and must not pretend to: the PLAIN build is what
    # proves it (CLAUDE.md). What is still assertable, and worth asserting, is that the verb this arm drives
    # is not broken on this flavour — the same document the alerting leg demands, minus the degrade.
    printf '  INFO  (F) this binary emits no DISCLOSE (NDEBUG): the emitter-throw degrade is unobservable BY DESIGN here, and the plain-flavour leg is what proves it\n'
    if grep -aq 'renderToString: the emitter THREW' "$PRC_FAULT_ERR"; then
        no "(F) a binary that cannot emit the charge-buffer alert emitted the emitter-throw one — the two disagree about this flavour"
    else
        ok "(F) consistency: no alert on a flavour that compiles them out"
    fi
    [ "$prc_f_rc" -eq 0 ] \
        && ok "(F1) --pr-context over the fixture repo exits 0 with the (compiled-out) fault requested" \
        || no "(F1) --pr-context exited $prc_f_rc on a flavour where the fault is not even compiled in"
    if grep -aq '</pr-context>' "$PRC_FAULT_OUT" && grep -aq '<pr-context' "$PRC_FAULT_OUT"; then
        ok "(F2) the document is CLOSED — a root, a body and a closing tag"
    else
        no "(F2) the --pr-context document is not a closed <pr-context> root ($( wc -c <"$PRC_FAULT_OUT" | tr -d ' ' ) B)"
    fi
    if command -v xmllint >/dev/null 2>&1; then
        xmllint --noout "$PRC_FAULT_OUT" 2>/dev/null \
            && ok "(F3) the document is well-formed XML (G4 holds)" \
            || no "(F3) the --pr-context document does not parse"
    fi
    f_rel="$( grep -ao '<f ' "$PRC_FAULT_OUT" | wc -l | tr -d ' ' )"
    [ "${f_rel:-0}" -gt 0 ] \
        && ok "(F4) the document carries $f_rel <f> row(s) — the verb is intact on this flavour" \
        || no "(F4) the document carries NO <f> row over $PRC_FAULT_BASE"
    # (F5) NO FALSE DISCLOSURE. Nothing degraded here (the switch is `constexpr false`), so the est-unmeasured
    #      label must be ABSENT: a truncation notice on a document that measured its own price would be the
    #      mirror-image defect of the silence it was added to end.
    grep -ao 'truncated="[^"]*"' "$PRC_FAULT_OUT" | grep -aq 'est-unmeasured' \
        && no "(F5) the document claims est-unmeasured on a flavour where the render fault is not compiled in — a disclosure with nothing behind it" \
        || ok "(F5) truncated= carries no est-unmeasured where nothing was left unmeasured"
elif ! grep -aq 'renderToString: the emitter THREW' "$PRC_FAULT_ERR"; then
    no "(F) INFRA_FAULT_RENDER_EMIT_THROW=1 produced no DISCLOSE on a binary that PROVED it can emit one (the charge-buffer probe alerted) — the seam regressed"
else
    ok "(F) observability probe: this binary emits alerts (the charge-buffer fault spoke) and the emitter-throw fault alerts too"
    # (F0) the alert names the CAUSE IT HAD. degradeMsg says the BUFFER failed; on this path it did not, so
    #      reusing it would have been a wrong reason attached to a right consequence.
    grep -aq 'open_memstream failed' "$PRC_FAULT_ERR" \
        && no "(F0) the emitter-throw alert blames open_memstream, which did not fail on this path" \
        || ok "(F0) the emitter-throw alert names the throw, not the buffer"
    # (F1) THE DOCUMENT STILL SHIPS. The whole point of the degrade: the caller loses the ESTIMATE, never the
    #      content. prcontext.h streams the floor level straight out when no level could be measured.
    [ "$prc_f_rc" -eq 0 ] \
        && ok "(F1) --pr-context over the fixture repo still exits 0 with every render throwing" \
        || no "(F1) --pr-context exited $prc_f_rc with the emitter-throw fault injected — the throw escaped instead of degrading"
    if grep -aq '</pr-context>' "$PRC_FAULT_OUT" && grep -aq '<pr-context' "$PRC_FAULT_OUT"; then
        ok "(F2) the degraded document is CLOSED — a root, a body and a closing tag, never an empty element"
    else
        no "(F2) the degraded --pr-context document is not a closed <pr-context> root ($( wc -c <"$PRC_FAULT_OUT" | tr -d ' ' ) B)"
    fi
    if command -v xmllint >/dev/null 2>&1; then
        xmllint --noout "$PRC_FAULT_OUT" 2>/dev/null \
            && ok "(F3) the degraded document is well-formed XML (G4 holds through the degrade)" \
            || no "(F3) the degraded --pr-context document does not parse — a degrade may not breach G4"
    fi
    # (F4) and it is not a stub. The direction here is the whole point and is easy to get backwards — this
    #      arm did, and caught itself: the degrade streams kPrTrims[0], the UNTRIMMED floor, while the
    #      undegraded run picks whichever level fits its token budget. So the degraded document carries at
    #      LEAST as many rows as the control and routinely more (40 against 4 on this tree). What the caller
    #      loses is the ESTIMATE; what it must never lose is content, and "same count" would assert the wrong
    #      invariant and fail on any tree whose control trims. Compared by ELEMENT COUNT, not bytes.
    f_files="$( grep -ao '<f ' "$PRC_FAULT_OUT" | wc -l | tr -d ' ' )"
    "$BIN" "$PRC_FIX" --pr-context="$PRC_FAULT_BASE" --legend=full >"$TMP/f_ctl.out" 2>/dev/null
    c_files="$( grep -ao '<f ' "$TMP/f_ctl.out" | wc -l | tr -d ' ' )"
    if [ "${f_files:-0}" -eq 0 ]; then
        no "(F4) the degraded document carries NO <f> row — the degrade lost the content it exists to keep"
    elif [ "$f_files" -ge "${c_files:-0}" ]; then
        ok "(F4) the degraded document carries $f_files <f> row(s) against the control's $c_files — content kept (the floor level is untrimmed), estimate lost"
    else
        no "(F4) the degraded document carries $f_files <f> row(s), FEWER than the control's $c_files — the degrade lost content, not just the charge"
    fi
    # (F5) AND THE WRONG NUMBER IS NOW LABELLED. est_tokens= here is the price of an EMPTY body (the ladder
    #      priced the failed probe and broke at level 0), while the bytes served are the untrimmed floor —
    #      so the number is modelled, not this document's price. Before the fix the ONLY signal was the alert
    #      above, which Release compiles out; truncated= is the channel that survives the flavour.
    f_trunc="$( grep -ao 'truncated="[^"]*"' "$PRC_FAULT_OUT" | head -1 )"
    if printf '%s' "$f_trunc" | grep -aq 'est-unmeasured'; then
        ok "(F5) the degraded root DISCLOSES the unmeasured price in truncated= ($f_trunc) — the one channel a Release binary keeps"
    else
        no "(F5) the degraded root prints an est_tokens priced from an empty body with no est-unmeasured in truncated= ($f_trunc) — a wrong number, silently (non-negotiable #3)"
    fi
    # (F6) and the label is DEFINED on the document that carries it — prbudgetcheck #10's rule for
    #      budget-floor-exceeded, applied to the label that now rides beside it.
    grep -aq 'est-unmeasured means' "$PRC_FAULT_OUT" \
        && ok "(F6) the degraded document ships the legend clause that defines est-unmeasured" \
        || no "(F6) the degraded document emits est-unmeasured but its own legend never defines the term"
fi

# ── (G) THE FINAL COPY THROWS: renderToString's last statement was outside its own contract ───────────
#
# THE FINDING (review of #214, src/infra/emit.h:269). `out.text.assign( buf, sz )` is the one allocation on
# the SUCCESS path, and it sat after the try/catch that arm (F) proves. A std::bad_alloc from it therefore
# escaped renderToString — whose whole documented contract is that a failure is ALERTED and returned as
# ok == false, never thrown — and, jumping over the `std::free( buf )` two lines below, LEAKED the memstream
# buffer on the way out. A no-throw contract with a throwing last statement.
#
# Driven by INFRA_FAULT_RENDER_COPY_THROW=1, the twin of arm (F)'s switch and injected immediately before the
# assign, where a real bad_alloc would land. Same flavour dependence as (F): the switch and the alert both
# live only on the non-NDEBUG build, so the PLAIN-flavour leg is what proves the degrade and the NDEBUG leg
# asserts only what is true there — exactly the structure (F) documents.
PRC_COPY_OUT="$TMP/g_copy.out"; PRC_COPY_ERR="$TMP/g_copy.err"
INFRA_FAULT_RENDER_COPY_THROW=1 "$BIN" "$PRC_FIX" --pr-context="$PRC_FAULT_BASE" >"$PRC_COPY_OUT" 2>"$PRC_COPY_ERR"
prc_g_rc=$?
if [ "$PRC_ALERTS" -eq 0 ]; then
    printf '  INFO  (G) this binary emits no DISCLOSE (NDEBUG): the copy-throw degrade is unobservable BY DESIGN here, and the plain-flavour leg is what proves it\n'
    if grep -aq 'renderToString: the final COPY' "$PRC_COPY_ERR"; then
        no "(G) a binary that cannot emit the charge-buffer alert emitted the copy-throw one — the two disagree about this flavour"
    else
        ok "(G) consistency: no alert on a flavour that compiles them out"
    fi
    [ "$prc_g_rc" -eq 0 ] \
        && ok "(G1) --pr-context exits 0 with the (compiled-out) copy fault requested" \
        || no "(G1) --pr-context exited $prc_g_rc on a flavour where the copy fault is not even compiled in"
    g_rel="$( grep -ao '<f ' "$PRC_COPY_OUT" | wc -l | tr -d ' ' )"
    [ "${g_rel:-0}" -gt 0 ] \
        && ok "(G2) the document carries $g_rel <f> row(s) — the verb is intact on this flavour" \
        || no "(G2) the document carries NO <f> row over $PRC_FAULT_BASE"
elif ! grep -aq 'renderToString: the final COPY' "$PRC_COPY_ERR"; then
    no "(G) INFRA_FAULT_RENDER_COPY_THROW=1 produced no DISCLOSE on a binary that PROVED it can emit one (the charge-buffer probe alerted) — the copy is still outside the no-throw contract"
else
    ok "(G) the final copy's throw is CAUGHT: the alert speaks instead of the exception escaping"
    # (G0) the alert names the cause it HAD. degradeMsg says the BUFFER failed and (F)'s literal says the
    #      EMITTER threw; here neither did — the copy out of a complete buffer did.
    { grep -aq 'open_memstream failed' "$PRC_COPY_ERR" || grep -aq 'the emitter THREW' "$PRC_COPY_ERR"; } \
        && no "(G0) the copy-throw alert blames the buffer or the emitter, neither of which failed on this path" \
        || ok "(G0) the copy-throw alert names the copy, not the buffer and not the emitter"
    [ "$prc_g_rc" -eq 0 ] \
        && ok "(G1) --pr-context still exits 0 with every final copy throwing — the throw degraded instead of escaping" \
        || no "(G1) --pr-context exited $prc_g_rc with the copy fault injected — the throw escaped renderToString's no-throw contract"
    if grep -aq '</pr-context>' "$PRC_COPY_OUT" && grep -aq '<pr-context' "$PRC_COPY_OUT"; then
        ok "(G2) the degraded document is CLOSED — a root, a body and a closing tag"
    else
        no "(G2) the degraded --pr-context document is not a closed <pr-context> root ($( wc -c <"$PRC_COPY_OUT" | tr -d ' ' ) B)"
    fi
    if command -v xmllint >/dev/null 2>&1; then
        xmllint --noout "$PRC_COPY_OUT" 2>/dev/null \
            && ok "(G3) the degraded document is well-formed XML (G4 holds through the degrade)" \
            || no "(G3) the degraded --pr-context document does not parse — a degrade may not breach G4"
    fi
    # (G4) the same content-kept/estimate-lost contract arm (F) asserts for its flavour of failure: a failed
    #      copy is a failed MEASUREMENT, so the floor level streams straight out and the price is disclosed.
    g_files="$( grep -ao '<f ' "$PRC_COPY_OUT" | wc -l | tr -d ' ' )"
    [ "${g_files:-0}" -gt 0 ] \
        && ok "(G4) the degraded document carries $g_files <f> row(s) — content kept, estimate lost" \
        || no "(G4) the degraded document carries NO <f> row — the degrade lost the content it exists to keep"
    g_trunc="$( grep -ao 'truncated="[^"]*"' "$PRC_COPY_OUT" | head -1 )"
    printf '%s' "$g_trunc" | grep -aq 'est-unmeasured' \
        && ok "(G5) a failed copy is disclosed in truncated= too ($g_trunc) — one label for every unmeasured level" \
        || no "(G5) the copy-degraded root prints an unmeasured est_tokens with no est-unmeasured in truncated= ($g_trunc)"
fi

if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "SOME CHECKS FAILED"; exit 1; fi
