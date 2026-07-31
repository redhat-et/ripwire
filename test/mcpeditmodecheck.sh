#!/usr/bin/env bash
# mcpeditmodecheck.sh — gates for A3-F7 (file-mode preservation) and A3-F8 (no lockfile litter).
#
# A3-F7: mcpedit::atomicWrite created its temp via fopen (umask-default 0644) and renamed it over the target
#   with NO mode preservation — editing an executable script silently stripped +x. The fix fstat()s the
#   original, fchmod()s the temp to the original's mode before the rename, and fsync()s before rename. This
#   gate creates a 0755 fixture script, drives replace_symbol_body over it via JSON-RPC (same technique as
#   mcpeditracecheck.sh / mcpeditkindcheck.sh), and asserts the mode is STILL 0755 after the edit applied.
#   Verified to FAIL against the pre-fix binary (mode drops to 0644) and PASS on the fix.
#
# A3-F8: the per-file advisory edit lock used to be a "<path>.ctxpack-lock" sidecar created next to the target
#   and never unlinked — permanent litter in the user's repo, visible in git status. The fix moves the lock to
#   the per-user cache dir keyed by a hash of the target path (flock cross-process safety preserved). This gate
#   runs an edit verb inside a real git repo fixture and asserts NO .ctxpack-lock shows up in `git status`.
#
# Usage:  test/mcpeditmodecheck.sh   |   CTXPACK_BIN=asan/ctxpack test/mcpeditmodecheck.sh
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "mcpeditmodecheck: BIN=$BIN"

# portable "octal mode of a file" (BSD/macOS stat -f vs GNU stat -c)
file_mode(){
    stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null
}

# drive one replace_symbol_body call through the MCP server (spec-conforming params.arguments form),
# echo the tools/call response line.
mcp_replace(){ # $1=dir  $2=symbol  $3=new_body
    printf '%s\n' \
      '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
      "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"replace_symbol_body\",\"arguments\":{\"path\":\"$1\",\"symbol\":\"$2\",\"new_body\":\"$3\"}}}" \
      | "$BIN" --mcp 2>/dev/null | tail -1
}

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 1. A3-F7 — editing a 0755 script preserves its executable mode ==="
# ═══════════════════════════════════════════════════════════════════════════
W1="$TMP/f7"; mkdir -p "$W1"
# a C source marked executable (a real def to splice); assert its +x survives the edit's atomic rename.
cat > "$W1/exec.cpp" <<'CPP'
int run_tool( int x )
{
    return x + 1;
}
CPP
chmod 0755 "$W1/exec.cpp"
BEFORE_MODE="$( file_mode "$W1/exec.cpp" )"
[ "$BEFORE_MODE" = "755" ] || { echo "  (setup) could not set fixture mode to 0755 (got $BEFORE_MODE)"; }

R1="$( mcp_replace "$W1" run_tool 'int run_tool( int x )\n{\n    return x + 2;\n}' )"
AFTER_MODE="$( file_mode "$W1/exec.cpp" )"

case "$R1" in
    *applied*) : ;;
    *) no "F7 setup: the edit did not apply (cannot assess mode): $( echo "$R1" | head -c 160 )";;
esac
[ "$AFTER_MODE" = "755" ] \
    && ok "F7: 0755 executable source stays 0755 after replace_symbol_body (mode preserved across atomic rename)" \
    || no "F7: mode changed on edit — was $BEFORE_MODE, now $AFTER_MODE (atomicWrite dropped the mode bits)"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 2. A3-F8 — an edit verb leaves NO .ctxpack-lock in the repo (git status clean of it) ==="
# ═══════════════════════════════════════════════════════════════════════════
W2="$TMP/f8"; mkdir -p "$W2"
(
  cd "$W2" || exit 1
  git init -q 2>/dev/null
  git config user.email t@t 2>/dev/null; git config user.name t 2>/dev/null
)
cat > "$W2/mod.cpp" <<'CPP'
int widget( int x )
{
    return x + 1;
}
CPP
( cd "$W2" && git add mod.cpp 2>/dev/null && git commit -q -m init 2>/dev/null )

R2="$( mcp_replace "$W2" widget 'int widget( int x )\n{\n    return x + 3;\n}' )"
case "$R2" in
    *applied*) : ;;
    *) no "F8 setup: edit did not apply: $( echo "$R2" | head -c 160 )";;
esac

# no lockfile as a plain file anywhere in the tree
LOCK_FILES="$( find "$W2" -name '*.ctxpack-lock' 2>/dev/null )"
# nothing named .ctxpack-lock in git's view of the working tree
GIT_LOCK="$( cd "$W2" && git status --porcelain 2>/dev/null | grep -i 'ctxpack-lock' )"

{ [ -z "$LOCK_FILES" ] && [ -z "$GIT_LOCK" ]; } \
    && ok "F8: no .ctxpack-lock sidecar in the repo tree after an edit (lock lives in the per-user cache dir)" \
    || no "F8: a .ctxpack-lock leaked into the repo (files=[$LOCK_FILES] git=[$GIT_LOCK])"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 3. regression — the edit still actually changed the file content ==="
# ═══════════════════════════════════════════════════════════════════════════
grep -q 'return x + 3;' "$W2/mod.cpp" \
    && ok "regression: the edit committed the new body (F7/F8 changes did not break the write path)" \
    || no "regression: the edited body is not on disk (write path broken)"

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
