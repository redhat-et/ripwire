#!/usr/bin/env bash
# cacheisolationcheck.sh — Ripwire-owned cache artifacts stay out of the shared TMPDIR root.
set -u

ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/statcompat.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ echo "  PASS  $1" || { fail=1; echo "  FAIL  could not write the PASS line for: $1"; }; return 0; }
no(){ echo "  FAIL  $1"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

# Under MSYS the shell converts POSIX paths in argv and TMPDIR for a native binary, but not
# inside JSON on stdin, and GNU stat reports an emulated mode instead of the real DACL.
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) win32=1 ;; *) win32=0 ;; esac
native_path(){ if [ "$win32" = 1 ]; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
# The DACL helper needs a native Windows Python: Cygwin's own python reports sys.platform "cygwin".
WINPY=""
if [ "$win32" = 1 ]; then
    for candidate in python py python3; do
        if command -v "$candidate" >/dev/null 2>&1 \
            && "$candidate" -c 'import sys; sys.exit(sys.platform != "win32")' 2>/dev/null; then
            WINPY="$candidate"; break
        fi
    done
fi
winpy(){
    if [ -z "$WINPY" ]; then echo "no native Windows Python (python, py or python3 with sys.platform win32) on PATH"; return 1; fi
    "$WINPY" "$( native_path "$ROOT/test/cache_ladder_windows.py" )" "$@"
}
check_private_mode(){
    if [ "$win32" = 1 ]; then
        if sddl="$( winpy --owner-only "$( native_path "$1" )" )"; then
            ok "private directory DACL is owner-only ($sddl)"
        else
            no "private directory DACL is not owner-only: $sddl"
        fi
    else
        mode="$( mode_of "$1" )"
        if [ "$mode" = "700" ]; then ok "private directory mode is 0700"; else no "private directory mode is $mode, expected 700"; fi
    fi
}

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
SHARED="$TMP/shared"; CORPUS="$TMP/corpus"; mkdir -p "$SHARED" "$CORPUS"
mkdir -m 0755 "$SHARED/ripwire"   # the binary must repair an existing permissive directory
printf 'int target( void ) { return 1; }\n' > "$CORPUS/code.cpp"
printf 'unrelated' > "$SHARED/not-ripwire"

echo "cacheisolationcheck: BIN=$BIN"

# Exercise the CLI parse cache, the MCP parse cache, and the per-target edit lock in one private TMPDIR.
TMPDIR="$SHARED" "$BIN" "$CORPUS" >/dev/null 2>"$TMP/cli.err"
printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"replace_symbol_body","arguments":{"path":"'"$( native_path "$CORPUS" )"'","symbol":"target","new_body":"int target( void ) { return 2; }"}}}' \
    | TMPDIR="$SHARED" "$BIN" --mcp >"$TMP/mcp.out" 2>"$TMP/mcp.err"

PRIVATE="$SHARED/ripwire"
if [ -d "$PRIVATE" ]; then ok "creates a dedicated TMPDIR/ripwire directory"; else no "missing private directory: $PRIVATE"; fi

[ -d "$PRIVATE" ] && check_private_mode "$PRIVATE"

topArtifacts="$( find "$SHARED" -mindepth 1 -maxdepth 1 -name 'ripwire-*' -print 2>/dev/null )"
[ -z "$topArtifacts" ] && ok "shared TMPDIR root has no ripwire-* artifacts" \
    || { no "ripwire artifacts leaked into shared TMPDIR root"; printf '%s\n' "$topArtifacts"; }

cacheCount="$( find "$PRIVATE" -mindepth 2 -maxdepth 2 -type f -name 'ripwire-mcp-*.cache' 2>/dev/null | wc -l | tr -d ' ' )"
lockCount="$( find "$PRIVATE/locks" -mindepth 2 -maxdepth 2 -type f -name 'ripwire-edit-*.lock' 2>/dev/null | wc -l | tr -d ' ' )"
if [ "$cacheCount" -ge 1 ]; then ok "MCP cache is sharded under the private directory"; else no "no sharded MCP cache found"; fi
if [ "$lockCount" -ge 1 ]; then ok "edit lock is sharded under the private locks subtree"; else no "no sharded edit lock found"; fi

if [ -f "$SHARED/not-ripwire" ]; then ok "unrelated TMPDIR content remains untouched"; else no "unrelated TMPDIR content was removed"; fi

# The Win32 DACL repair is observable without a noisy wall-clock threshold.
if [ "$win32" = 1 ]; then
    if winpy "$( native_path "$BIN" )"; then
        ok "native Windows ACL repair, warm no-rewrite, and junction refusal"
    else
        no "native Windows cache ACL regression"
    fi
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "FAILURES ABOVE"; exit 1; }
