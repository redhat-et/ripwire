#!/usr/bin/env bash
# gitquotepathcheck.sh — gate for A4-F13: git C-quoted paths must still resolve.
#
# git wraps a path containing a double-quote, backslash, tab, or control byte in double quotes with
# backslash escapes ("C-quoting") — and it does so EVEN with core.quotepath=false (that flag only
# suppresses octal-escaping of high-bit/UTF-8 bytes, not the quoting of quote/backslash/control bytes).
# Pre-F13, the co-change / churn / ownership miners and the --pr-context numstat mask took that quoted
# column verbatim, so such a file suffix-matched nothing and silently dropped from every git-derived view.
# This gate creates a file whose name contains a literal `"` (legal on APFS) and asserts it appears both
# in --pr-context (numstat mask path, prcontext.h) and in --cochange (BaseNameIndex resolver, gitmine.h).
#
# Usage:
#   test/gitquotepathcheck.sh
#   RIPWIRE_BIN=asan/ripwire test/gitquotepathcheck.sh
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
echo "gitquotepathcheck: BIN=$BIN"

# The file whose name embeds a literal double-quote. Skip cleanly if the filesystem rejects it.
QUOTED='src/wei"rd.cpp'
REPO="$TMP/repo"
mkdir -p "$REPO/src"
if ! ( echo 'int q(){return 0;}' >"$REPO/$QUOTED" ) 2>/dev/null; then
    echo "  SKIP  filesystem does not allow a '\"' in a filename — cannot exercise A4-F13 here"
    echo; echo "ALL PASS"; exit 0
fi

git -C "$REPO" init -q
git -C "$REPO" config user.email "dev@x.com"
git -C "$REPO" config user.name  "Dev"

# A companion file that will co-change with the quoted file, plus a static include so co-change resolves.
cat >"$REPO/src/partner.cpp" <<'EOF'
int partner(){ return 1; }
EOF

# Confirm git actually C-quotes this path (the premise of the finding). If not, the test is moot but harmless.
git -C "$REPO" add -A 2>/dev/null
echo "--- git status --porcelain (shows C-quoting) ---"
git -C "$REPO" -c core.quotepath=false status --porcelain
echo "------------------------------------------------"

# Two commits that BOTH touch the quoted file and partner.cpp → a co-change pair (support>=3 needs
# several; make 4 joint commits so the kSupport=3 threshold is crossed).
for i in 1 2 3 4; do
    echo "// rev $i" >>"$REPO/$QUOTED"
    echo "// rev $i" >>"$REPO/src/partner.cpp"
    git -C "$REPO" add -A 2>/dev/null
    GIT_AUTHOR_DATE="2026-06-0${i}T12:00:00" GIT_COMMITTER_DATE="2026-06-0${i}T12:00:00" \
        git -C "$REPO" commit -qm "rev $i"
done

# ── (A) --pr-context: make a working-tree edit to the quoted file, assert it appears as a changed file.
echo 'int extra(){return 7;}' >>"$REPO/$QUOTED"
POUT="$( "$BIN" "$REPO" --pr-context --no-cache 2>/dev/null )"
echo "pr-context output:"; echo "$POUT"; echo

# The path is XML-escaped in output (" → &quot;), so match on the unambiguous unescaped stem 'wei'.
echo "$POUT" | grep -q '<file p="[^"]*src/wei[^"]*rd\.cpp"' \
    && ok "A4-F13: C-quoted file appears as a changed <file> in --pr-context" \
    || no "A4-F13: C-quoted file dropped from --pr-context numstat mask"

# ── (B) --cochange: the quoted file's co-change partner (partner.cpp) must resolve. Query BY the quoted
#    file so its own commits are found (the resolver must unquote the git --name-only path to match it).
COUT="$( "$BIN" "$REPO" --cochange='wei"rd.cpp' --no-cache 2>/dev/null )"
echo "cochange output:"; echo "$COUT"; echo

echo "$COUT" | grep -q 'commits="[1-9]' \
    && ok "A4-F13: --cochange resolved the quoted file's own commit history (commits>0)" \
    || no "A4-F13: --cochange found 0 commits for the quoted file (resolver failed to unquote)"

echo "$COUT" | grep -q '<f p="[^"]*src/partner\.cpp"' \
    && ok "A4-F13: co-change partner src/partner.cpp resolved" \
    || no "A4-F13: co-change partner missing (quoted-file commits never resolved)"

# xmllint-clean on both.
{ echo "<root>"; echo "$POUT"; echo "$COUT"; echo "</root>"; } | xmllint --noout - 2>/dev/null \
    && ok "xmllint clean (wrapped)" \
    || no "xmllint reported malformed XML"

echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "SOME CHECKS FAILED"; exit 1; fi
