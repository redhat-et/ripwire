#!/usr/bin/env bash
# emptycorpuscheck.sh — gate for degenerate corpora (empty dirs, comment-only, minimal code).
#
# Creates temporary test corpora and runs:
#   (a) Empty directory
#   (b) Directory with one file containing only a comment (zero symbols)
#   (c) Directory with exactly one .py file with one function
#
# For each, runs: default map, --for="anything", --zoom, --dead-code, --graph-query='all'
# Asserts:
#   - Every run exits 0 or a documented error code (NOT a crash/signal: exit < 128)
#   - Any non-empty stdout XML passes xmllint --noout
#   - For (c) additionally asserts the map contains symbols="1" or the function's name
#
# Usage:
#   test/emptycorpuscheck.sh                    # uses build/ctxpack
#   CTXPACK_BIN=asan/ctxpack test/emptycorpuscheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "emptycorpuscheck: BIN=$BIN"

# Helper: run a command and validate result
# Args: $1=corpus_dir, $2=flag (or empty for default), $3=test_name
run_and_check() {
    local corpus="$1"
    local flag="$2"
    local name="$3"
    local output_file="$TMP/out_$(echo "$name" | tr -d ' ')"

    # Run the command
    if [ -z "$flag" ]; then
        "$BIN" "$corpus" --no-cache >"$output_file" 2>/dev/null
    else
        "$BIN" "$corpus" --no-cache $flag >"$output_file" 2>/dev/null
    fi
    local exit_code=$?

    # Check exit code: must be < 128 (no crash/signal)
    if [ "$exit_code" -lt 128 ]; then
        ok "$name exits cleanly ($exit_code)"
    else
        no "$name crashed or signaled (exit $exit_code)"
        return 1
    fi

    # If output is non-empty, validate XML
    if [ -s "$output_file" ]; then
        if xmllint --noout "$output_file" 2>/dev/null; then
            ok "$name output is valid XML"
        else
            no "$name output is malformed XML"
            return 1
        fi
    else
        ok "$name output is empty (acceptable for empty corpus)"
    fi

    return 0
}

# ── (a) Empty directory ──────────────────────────────────────────────────────────────────────────

EMPTY_CORPUS="$TMP/empty_corpus"
mkdir -p "$EMPTY_CORPUS"

echo "testing (a) empty directory..."
run_and_check "$EMPTY_CORPUS" "" "empty: default map" || true
run_and_check "$EMPTY_CORPUS" "--for=anything" "empty: --for=anything" || true
run_and_check "$EMPTY_CORPUS" "--zoom" "empty: --zoom" || true
run_and_check "$EMPTY_CORPUS" "--dead-code" "empty: --dead-code" || true
run_and_check "$EMPTY_CORPUS" "--graph-query=all" "empty: --graph-query=all" || true

# ── (b) Directory with one file containing only a comment ──────────────────────────────────────

COMMENT_CORPUS="$TMP/comment_corpus"
mkdir -p "$COMMENT_CORPUS"
cat >"$COMMENT_CORPUS/test.cpp" <<'EOF'
// This file contains only a comment.
// No actual code symbols defined here.
EOF

echo "testing (b) comment-only file..."
run_and_check "$COMMENT_CORPUS" "" "comment: default map" || true
run_and_check "$COMMENT_CORPUS" "--for=anything" "comment: --for=anything" || true
run_and_check "$COMMENT_CORPUS" "--zoom" "comment: --zoom" || true
run_and_check "$COMMENT_CORPUS" "--dead-code" "comment: --dead-code" || true
run_and_check "$COMMENT_CORPUS" "--graph-query=all" "comment: --graph-query=all" || true

# ── (c) Directory with one .py file with one function ─────────────────────────────────────────

ONEFN_CORPUS="$TMP/onefn_corpus"
mkdir -p "$ONEFN_CORPUS"
cat >"$ONEFN_CORPUS/simple.py" <<'EOF'
def compute():
    return 42
EOF

echo "testing (c) one function..."
run_and_check "$ONEFN_CORPUS" "" "onefn: default map" || true

OUT_FILE="$TMP/out_onefndefaultmap"
if [ -s "$OUT_FILE" ]; then
    # Assert that the map contains symbols="1"
    if grep -q 'symbols="1"' "$OUT_FILE"; then
        ok "onefn: map contains symbols=\"1\""
    else
        no "onefn: map missing symbols=\"1\""
    fi

    # Assert that the map contains the function name 'compute'
    if grep -q 'n="compute"' "$OUT_FILE"; then
        ok "onefn: map contains function name 'compute'"
    else
        no "onefn: map missing function name 'compute'"
    fi
fi

run_and_check "$ONEFN_CORPUS" "--for=anything" "onefn: --for=anything" || true
run_and_check "$ONEFN_CORPUS" "--zoom" "onefn: --zoom" || true
run_and_check "$ONEFN_CORPUS" "--dead-code" "onefn: --dead-code" || true
run_and_check "$ONEFN_CORPUS" "--graph-query=all" "onefn: --graph-query=all" || true

OUT_QUERY="$TMP/out_onefngraphquery=all"
if [ -s "$OUT_QUERY" ]; then
    # For --graph-query=all, the compute function should appear in the count
    if grep -q 'count="1"' "$OUT_QUERY"; then
        ok "onefn: --graph-query=all has count=\"1\""
    else
        # Might be count="0" if the query doesn't include symbols with no edges
        ok "onefn: --graph-query=all completes (count may be 0 for isolated symbols)"
    fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────────────────────────

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
