#!/usr/bin/env bash
# nongitqmetricscheck.sh — rich retrieval on a non-git root must not spawn git merely to degrade.
set -u

ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
CORPUS="$TMP/corpus"; FAKEBIN="$TMP/bin"; CACHE="$TMP/cache"; mkdir -p "$CORPUS" "$FAKEBIN" "$CACHE"
cat > "$CORPUS/code.cpp" <<'EOF'
int helper( int x ) { return x + 1; }
int caller( int y ) { return helper( y ); }
EOF
cat > "$FAKEBIN/git" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$RIPWIRE_FAKE_GIT_TRACE"
exit 1
EOF
chmod +x "$FAKEBIN/git"
: > "$TMP/git.trace"

echo "nongitqmetricscheck: BIN=$BIN"
PATH="$FAKEBIN:$PATH" TMPDIR="$CACHE" RIPWIRE_FAKE_GIT_TRACE="$TMP/git.trace" \
    "$BIN" "$CORPUS" --for=helper --no-cache >"$TMP/out" 2>"$TMP/err"; rc=$?

[ "$rc" -eq 0 ] && ok "non-git --for succeeds" || no "non-git --for exited $rc"
[ -s "$TMP/out" ] && grep -q 'n="helper"' "$TMP/out" \
    && ok "retrieval still returns the requested symbol" || no "retrieval output lost helper"
grep -q 'amp="1"' "$TMP/out" \
    && ok "caller-only amp survives without history" || no "caller-only amp was not preserved"
[ ! -s "$TMP/git.trace" ] && ok "non-git retrieval spawns zero git subprocesses" \
    || { no "non-git retrieval invoked git"; sed -n '1,10p' "$TMP/git.trace"; }

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "FAILURES ABOVE"; exit 1; }
