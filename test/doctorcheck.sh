#!/usr/bin/env bash
# doctorcheck.sh — gate for --doctor (AUDIT3 standing item): self-diagnosis verb.
#
# --doctor is a DIAGNOSTIC verb (environment-dependent output is its whole point), so unlike every
# other absorb gate this one does NOT assert byte-identical / golden output. Instead it asserts:
#   (A) happy path: exit 0, all 6 <c> rows present, xmllint-clean, checks="N" matches N emitted rows.
#   (B) an unwritable cache dir (via TMPDIR) makes the cache-dir row ok="0" and the whole run exit 1.
#   (C) a non-repo target dir makes the git row ok="1" repo="0" (degrade, not a failure).
#   (D) non-vacuity without a source mutation: assert the check COUNT in checks="N" equals the number
#       of emitted <c ...> rows (a doctor that silently dropped a check would still exit 0/1 plausibly,
#       but the count would betray it).
#   (G) tracked-binary staleness (field-notes §Smaller): a binary committed, then its same-stem source
#       edited in a LATER commit with the binary never recommitted, fires stale="1" ok="0" (git-commit-order,
#       never mtime); a binary + source committed TOGETHER in their most recent touch stays stale="0" ok="1".
#
# Usage:
#   test/doctorcheck.sh
#   RIPWIRE_BIN=build_p5w4/ripwire test/doctorcheck.sh
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
echo "doctorcheck: BIN=$BIN"

# A small ad-hoc target dir (git repo, one file) — --doctor needs a root positional.
REPO="$TMP/repo"
mkdir -p "$REPO"
echo 'int f(){return 0;}' >"$REPO/f.cpp"
git -C "$REPO" init -q
git -C "$REPO" config user.email "dev@x.com"
git -C "$REPO" config user.name  "Dev"
git -C "$REPO" add -A
git -C "$REPO" commit -qm init >/dev/null

# ── (A) happy path ──────────────────────────────────────────────────────────────────────────────
# binary-path is the one check whose "ok" genuinely depends on this MACHINE's state (is the PATH
# copy of ripwire the same file as the one under test?) — on a dev box with a stale `which ripwire`
# that's a REAL finding, not a gate bug. So the happy path pins PATH to a dir containing exactly this
# $BIN (same file, same inode either way it's resolved) to make check 1 deterministically ok="1", and
# gives it its own scratch TMPDIR so the cache-dir row isn't at the mercy of whatever blobs already
# live in the real one.
BINDIR="$TMP/bin"; mkdir -p "$BINDIR"; cp "$BIN" "$BINDIR/ripwire"; chmod +x "$BINDIR/ripwire"
HAPPYCACHE="$TMP/happycache"; mkdir -p "$HAPPYCACHE"

OUT="$( PATH="$BINDIR:$PATH" TMPDIR="$HAPPYCACHE" "$BINDIR/ripwire" "$REPO" --doctor --no-cache 2>/dev/null )"
RC=$?
echo "happy-path output:"; echo "$OUT"; echo "(exit=$RC)"; echo

[ "$RC" -eq 0 ] && ok "happy path exits 0" || no "happy path exit code was $RC, expected 0"

echo "$OUT" | grep -q '<doctor checks="6"' && ok "checks=\"6\"" || no "missing checks=\"6\""

for row in binary-path grammars cache-dir git tree-sitter tracked-binaries; do
    echo "$OUT" | grep -q "<c n=\"$row\" ok=" \
        && ok "row present: $row" \
        || no "row missing: $row"
done

# §A10.4: the git row's head= is a 9-hex-char sha, matching the at= convention (gitstamp.h) every
# other repo-reading verb uses — it used to print the full 40-char HEAD sha, a width outlier next to
# --merge-scout's (now also fixed) base= and --stray-content/--pr-context's base_sha=.
HEAD_ATTR="$( echo "$OUT" | grep -oE '<c n="git"[^/]*head="[0-9a-f]+"' | grep -oE 'head="[0-9a-f]+"' )"
echo "$HEAD_ATTR" | grep -qE '^head="[0-9a-f]{9}"$' \
    && ok "doctor git row head= is a 9-hex-char sha (matches at= width, §A10.4)" \
    || no "doctor git row head= is not 9 hex chars: $HEAD_ATTR"

echo "$OUT" | xmllint --noout - 2>/dev/null && ok "xmllint clean" || no "xmllint reported malformed XML"

# §P11 doctor item: hint= is a FAILURE-only attribute — an all-green run must carry none.
echo "$OUT" | grep -q 'hint=' \
    && no "happy path (all checks ok) wrongly carries a hint= somewhere" \
    || ok "happy path carries no hint= (hint= is failure-only)"

# (D) non-vacuity via count assertion: checks="N" must equal the number of emitted <c rows.
DECLARED="$( echo "$OUT" | grep -o 'checks="[0-9]*"' | grep -o '[0-9]*' )"
EMITTED="$(  echo "$OUT" | grep -o '<c n=' | wc -l | tr -d ' ' )"
[ "$DECLARED" = "$EMITTED" ] \
    && ok "checks=\"$DECLARED\" matches $EMITTED emitted <c> rows (non-vacuous)" \
    || no "checks=\"$DECLARED\" != $EMITTED emitted rows"

# ── (B) unwritable cache dir → cache-dir row ok="0", overall exit 1 ────────────────────────────
CACHEDIR="$TMP/cachedir"
mkdir -p "$CACHEDIR"
chmod 0500 "$CACHEDIR"
UOUT="$( TMPDIR="$CACHEDIR" "$BIN" "$REPO" --doctor --no-cache 2>/dev/null )"
URC=$?
chmod 0700 "$CACHEDIR"   # restore before any cleanup/trap touches it

echo "unwritable-cache output:"; echo "$UOUT"; echo "(exit=$URC)"; echo

echo "$UOUT" | grep -q '<c n="cache-dir" ok="0"' \
    && ok "unwritable cache dir -> cache-dir row ok=\"0\"" \
    || no "unwritable cache dir did not flag cache-dir row"

[ "$URC" -eq 1 ] && ok "unwritable cache dir -> overall exit 1" || no "overall exit was $URC, expected 1"

# §P11 doctor item: a failing check carries a hint= naming the derived verdict, not just raw facts.
echo "$UOUT" | grep -oE '<c n="cache-dir" ok="0"[^<]*/>' | grep -q 'hint="' \
    && ok "unwritable cache dir -> cache-dir row carries hint=" \
    || no "unwritable cache dir: cache-dir row has no hint="

# ── (C) non-repo target dir → git row ok="1" repo="0" (degrade, not sickness) ───────────────────
NONREPO="$TMP/nonrepo"
mkdir -p "$NONREPO"
echo 'int f(){return 0;}' >"$NONREPO/f.cpp"
NOUT="$( "$BIN" "$NONREPO" --doctor --no-cache 2>/dev/null )"

echo "non-repo output:"; echo "$NOUT"; echo

echo "$NOUT" | grep -q '<c n="git" ok="1"' \
    && ok "non-repo dir -> git row still ok=\"1\" (git itself reachable)" \
    || no "non-repo dir: git row not ok=\"1\""

echo "$NOUT" | grep -q 'repo="0"' \
    && ok "non-repo dir -> repo=\"0\"" \
    || no "non-repo dir: repo= attr missing/not 0"

echo "$NOUT" | xmllint --noout - 2>/dev/null && ok "xmllint clean (non-repo)" || no "xmllint reported malformed XML (non-repo)"

# ── (E) copied-but-identical binary: install.sh COPIES (never symlinks), so dev/ino always differ
#     from a same-content build — same_file="0" alone false-positives every working install. The
#     content-equality fallback (equal mtime AND equal size) must flag ok="1" copied="1" instead. ──
COPYDIR="$TMP/copydir"; mkdir -p "$COPYDIR"
cp -p "$BIN" "$COPYDIR/ripwire"; chmod +x "$COPYDIR/ripwire"   # -p preserves mtime -> identical mtime+size, different inode
COPYCACHE="$TMP/copycache"; mkdir -p "$COPYCACHE"
COUT="$( PATH="$COPYDIR:$PATH" TMPDIR="$COPYCACHE" "$BIN" "$REPO" --doctor --no-cache 2>/dev/null )"

echo "copied-binary output:"; echo "$COUT"; echo

echo "$COUT" | grep -q '<c n="binary-path" ok="1"' \
    && ok "copied binary (equal mtime+size) -> binary-path row ok=\"1\"" \
    || no "copied binary did not flag ok=\"1\""
echo "$COUT" | grep -q 'copied="1"' \
    && ok "copied binary -> copied=\"1\" attribute present" \
    || no "copied binary missing copied=\"1\" attribute"

# ── (F) genuine-stale binary: mtime forced apart (size still equal) -> still a real mismatch, must
#     stay ok="0" with no copied="1" (the fallback must not paper over an actually-stale shadow). ──
STALEDIR="$TMP/staledir"; mkdir -p "$STALEDIR"
cp -p "$BIN" "$STALEDIR/ripwire"; chmod +x "$STALEDIR/ripwire"
touch -t 202001010000 "$STALEDIR/ripwire"   # force a different mtime; size stays identical
STALECACHE="$TMP/stalecache"; mkdir -p "$STALECACHE"
SOUT="$( PATH="$STALEDIR:$PATH" TMPDIR="$STALECACHE" "$BIN" "$REPO" --doctor --no-cache 2>/dev/null )"

echo "genuine-stale output:"; echo "$SOUT"; echo

echo "$SOUT" | grep -q '<c n="binary-path" ok="0"' \
    && ok "genuine-stale binary (mtime differs) -> binary-path row ok=\"0\"" \
    || no "genuine-stale binary did not flag ok=\"0\""
echo "$SOUT" | grep -q 'copied="1"' \
    && no "genuine-stale binary wrongly carries copied=\"1\"" \
    || ok "genuine-stale binary carries no copied=\"1\" (fallback did not paper over it)"

# §P11 doctor item: binary-path's ok="0" row names which of self=/which= is the STALE (older) one.
echo "$SOUT" | grep -oE '<c n="binary-path" ok="0"[^<]*/>' | grep -q 'hint="STALE:' \
    && ok "genuine-stale binary -> binary-path row carries hint=\"STALE: ...\"" \
    || no "genuine-stale binary: binary-path row has no hint="
STALEHINT="$( echo "$SOUT" | grep -oE 'hint="STALE:[^"]*"' )"
echo "$STALEHINT" | grep -qF "$STALEDIR/ripwire" \
    && ok "hint= correctly names the OLDER (staledir) binary as stale, not the newer one" \
    || no "hint= did not name the older binary: $STALEHINT"

# ── (G) tracked-binary staleness (field-notes §Smaller) ─────────────────────────────────────────
# Two dedicated repos so the fixture is unambiguous: STALEREPO commits a binary, then edits its same-
# stem source in a LATER commit without ever recommitting the binary (the motivating "sweep committed
# rebuilt binaries blind" shape, inverted: here the SOURCE moved and the binary was left behind — same
# git-order violation the check is built to catch either direction of). FRESHREPO commits a binary and
# its source TOGETHER as their most recent touch — never separately re-edited — so it must stay quiet.
# Both use the same PATH/TMPDIR trick as the happy path so every OTHER row stays ok=1 and the overall
# exit code is pinned entirely by the tracked-binaries row.
STALEREPO="$TMP/stalebinrepo"; mkdir -p "$STALEREPO/bin"
git -C "$STALEREPO" init -q
git -C "$STALEREPO" config user.email "dev@x.com"
git -C "$STALEREPO" config user.name  "Dev"
printf 'int f(){return 1;}\n' >"$STALEREPO/bin/tool.cpp"
printf 'MZ\x00\x00binarystub'  >"$STALEREPO/bin/tool"        # NUL byte -> sniffs as binary content
git -C "$STALEREPO" add -A && git -C "$STALEREPO" commit -qm "add tool + tool.cpp together" >/dev/null
printf 'int f(){return 2;}\n' >"$STALEREPO/bin/tool.cpp"      # source edited AFTER — binary never recommitted
git -C "$STALEREPO" add -A && git -C "$STALEREPO" commit -qm "edit tool.cpp only" >/dev/null

GOUT="$( PATH="$BINDIR:$PATH" TMPDIR="$HAPPYCACHE" "$BINDIR/ripwire" "$STALEREPO" --doctor --no-cache 2>/dev/null )"
GRC=$?
echo "tracked-binary-staleness (stale case) output:"; echo "$GOUT"; echo "(exit=$GRC)"; echo

echo "$GOUT" | grep -q '<c n="tracked-binaries" ok="0"' \
    && ok "G: source edited after its binary's last commit -> tracked-binaries row ok=\"0\"" \
    || no "G: stale binary/source pair did not flag ok=\"0\""
echo "$GOUT" | grep -qE 'stale="1"[^/]*p0="bin/tool"[^/]*src0="bin/tool\.cpp"|p0="bin/tool"[^/]*src0="bin/tool\.cpp"[^/]*stale="1"|stale="1"' \
    && ok "G: stale count is reported (stale=\"1\")" || no "G: stale=\"1\" not reported"
echo "$GOUT" | grep -qF 'p0="bin/tool"' && echo "$GOUT" | grep -qF 'src0="bin/tool.cpp"' \
    && ok "G: the specific stale (binary, source) pair is named (p0/src0)" \
    || no "G: stale pair was not named in the row"
echo "$GOUT" | grep -oE '<c n="tracked-binaries" ok="0"[^<]*/>' | grep -q 'hint="' \
    && ok "G: stale tracked-binaries row carries hint=" \
    || no "G: stale tracked-binaries row has no hint="
[ "$GRC" -eq 1 ] && ok "G: a stale tracked binary fails the overall --doctor exit (1)" || no "G: overall exit was $GRC, expected 1"
echo "$GOUT" | xmllint --noout - 2>/dev/null && ok "G: xmllint clean (stale case)" || no "G: xmllint reported malformed XML (stale case)"

FRESHREPO="$TMP/freshbinrepo"; mkdir -p "$FRESHREPO/bin"
git -C "$FRESHREPO" init -q
git -C "$FRESHREPO" config user.email "dev@x.com"
git -C "$FRESHREPO" config user.name  "Dev"
printf 'int g(){return 1;}\n' >"$FRESHREPO/bin/tool.cpp"
printf 'MZ\x00\x00binarystub'  >"$FRESHREPO/bin/tool"
git -C "$FRESHREPO" add -A && git -C "$FRESHREPO" commit -qm "add tool + tool.cpp together, never touched again" >/dev/null

FOUT="$( PATH="$BINDIR:$PATH" TMPDIR="$HAPPYCACHE" "$BINDIR/ripwire" "$FRESHREPO" --doctor --no-cache 2>/dev/null )"
FRC=$?
echo "tracked-binary-staleness (fresh case) output:"; echo "$FOUT"; echo "(exit=$FRC)"; echo

echo "$FOUT" | grep -q '<c n="tracked-binaries" ok="1"' \
    && ok "G: binary + source committed together (never re-edited) -> tracked-binaries row ok=\"1\"" \
    || no "G: fresh binary/source pair wrongly flagged"
echo "$FOUT" | grep -q 'stale="0"' && ok "G: fresh pair reports stale=\"0\"" || no "G: fresh pair did not report stale=\"0\""
[ "$FRC" -eq 0 ] && ok "G: a fresh tracked binary does not fail the overall --doctor exit" || no "G: overall exit was $FRC, expected 0"
echo "$FOUT" | xmllint --noout - 2>/dev/null && ok "G: xmllint clean (fresh case)" || no "G: xmllint reported malformed XML (fresh case)"

# non-git root degrades quietly (ok=1, non_git=1) — mirrors the git-row's own non-repo degrade in (C).
NGOUT="$( "$BIN" "$NONREPO" --doctor --no-cache 2>/dev/null )"
echo "$NGOUT" | grep -q '<c n="tracked-binaries" ok="1"' && echo "$NGOUT" | grep -q 'non_git="1"' \
    && ok "G: a non-git root degrades the tracked-binaries row to ok=\"1\" non_git=\"1\"" \
    || { no "G: non-git root did not degrade cleanly"; echo "$NGOUT"; }

# ── multi-root refusal (v1 single-root-only cut) ────────────────────────────────────────────────
REPO2="$TMP/repo2"; mkdir -p "$REPO2"; echo 'int g(){return 0;}' >"$REPO2/g.cpp"
MOUT="$( "$BIN" "$REPO" "$REPO2" --doctor --no-cache 2>&1 )"
MRC=$?
[ "$MRC" -eq 1 ] && ok "multi-root --doctor refuses (exit 1)" || no "multi-root --doctor exit was $MRC, expected 1"
echo "$MOUT" | grep -qi 'doctor' && ok "multi-root refusal names --doctor" || no "multi-root refusal message missing"

echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "SOME CHECKS FAILED"; exit 1; fi
