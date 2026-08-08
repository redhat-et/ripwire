#!/usr/bin/env bash
# docmdcachecheck.sh — gate for the markitdown-bridge doc cache (ingest doc post-pass).
# The bridge (pdf/docx/pptx/xlsx → markitdown popen) costs a Python-CLI start per file per run and the
# post-pass reruns every invocation, so bridge results are cached under cacheDirLadder() keyed by the
# doc's CONTENT HASH ("ripwire-docmd-<hash>.bin", evicted by the existing ripwire- family sweep).
# Asserts, against a FAKE markitdown on PATH (a shell script that logs each invocation):
#   1. cold run invokes the bridge exactly once for one .docx
#   2. warm run adds ZERO invocations (content-hash hit) and its stdout is byte-identical to cold
#   3. --no-cache disables the sidecar (bridge invoked again)
#   4. changing the doc's bytes re-invokes (the key is the content, not the path)
#   5. an EMPTY extraction is never cached (machine fact, not a byte fact): a no-output fake is
#      re-invoked on the next run rather than wedging "" into the cache
# Does NOT edit test/regression.sh (the orchestrator wires it).
#
#   RIPWIRE_BIN=build/ripwire bash test/docmdcachecheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

# Self-contained corpus + fake bridge. The fake ignores its input and emits fixed markdown, so the
# only observable that matters is HOW OFTEN it runs. Unique doc bytes per gate run keep this run's
# content hashes disjoint from any earlier blob in the shared cache dir (the dir is per-user tmp).
mkdir -p "$TMP/corpus" "$TMP/bin"
printf 'gate doc bytes %s $$=%s' "$( date +%s%N 2>/dev/null || date +%s )" "$$" > "$TMP/corpus/deck.docx"
printf 'int main(){ return 0; }\n' > "$TMP/corpus/a.cpp"
cat > "$TMP/bin/markitdown" <<'FAKE'
#!/bin/bash
echo "invoked $1" >> "$FAKE_LOG"
echo "# Extracted Deck"
echo "hello from fake markitdown"
FAKE
chmod +x "$TMP/bin/markitdown"
export FAKE_LOG="$TMP/invocations.log"; : > "$FAKE_LOG"
count(){ wc -l < "$FAKE_LOG" | tr -d ' '; }

echo "docmdcachecheck: BIN=$BIN"

# 1. cold — bridge fires once
PATH="$TMP/bin:$PATH" "$BIN" "$TMP/corpus" > "$TMP/cold.xml" 2>/dev/null
[ "$( count )" = "1" ] && ok "cold run invoked the bridge exactly once" || no "cold run: expected 1 invocation, got $( count )"

# 2. warm — zero new invocations, byte-identical map
PATH="$TMP/bin:$PATH" "$BIN" "$TMP/corpus" > "$TMP/warm.xml" 2>/dev/null
[ "$( count )" = "1" ] && ok "warm run added zero invocations (content-hash hit)" || no "warm run re-invoked the bridge ($( count ) total)"
diff -q "$TMP/cold.xml" "$TMP/warm.xml" >/dev/null && ok "warm map byte-identical to cold (determinism holds through the sidecar)" \
    || no "cold and warm maps differ"

# 3. --no-cache disables the sidecar
PATH="$TMP/bin:$PATH" "$BIN" "$TMP/corpus" --no-cache >/dev/null 2>&1
[ "$( count )" = "2" ] && ok "--no-cache bypasses the sidecar (bridge invoked again)" || no "--no-cache: expected 2 total invocations, got $( count )"

# 4. changed bytes → new content hash → re-extract
printf ' changed' >> "$TMP/corpus/deck.docx"
PATH="$TMP/bin:$PATH" "$BIN" "$TMP/corpus" >/dev/null 2>&1
[ "$( count )" = "3" ] && ok "changed doc bytes re-invoke the bridge (key is content)" || no "changed bytes: expected 3 total invocations, got $( count )"

# 5. empty extraction is never cached — a silent fake is re-invoked next run, not wedged
cat > "$TMP/bin/markitdown" <<'FAKE'
#!/bin/bash
echo "invoked $1" >> "$FAKE_LOG"
exit 0
FAKE
chmod +x "$TMP/bin/markitdown"
printf 'silent doc bytes %s' "$$" > "$TMP/corpus/deck.docx"
PATH="$TMP/bin:$PATH" "$BIN" "$TMP/corpus" >/dev/null 2>&1
PATH="$TMP/bin:$PATH" "$BIN" "$TMP/corpus" >/dev/null 2>&1
[ "$( count )" = "5" ] && ok "empty extraction not cached (silent bridge re-invoked each run)" || no "empty-extraction arm: expected 5 total invocations, got $( count )"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
