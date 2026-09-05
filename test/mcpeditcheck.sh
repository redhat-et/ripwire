#!/usr/bin/env bash
# mcpeditcheck.sh — gate for the W4-#8 symbol-addressed EDIT verbs
#   replace_symbol_body / insert_before_symbol / insert_after_symbol.
#
# These are ripwire's FIRST write verbs, so the SAFETY CONTRACT is the feature. This gate exercises
# every branch of that contract, and asserts that every REFUSAL leaves the target file byte-identical:
#
#   1. replace_symbol_body: splice a function body → re-read shows the exact splice, and the bytes
#      OUTSIDE the def span (the prefix before the def and the suffix after it) are byte-identical to
#      the original (cmp the prefix/suffix regions).
#   2. insert_before_symbol / insert_after_symbol: correct placement + the SEAM rule (E1, terminality
#      round A 2026-09-05, test/editroundtripcheck.sh): the inserted block is padded — newlines only, never
#      removed — until it is separated from the anchor by the same blank-line run the file already has at
#      that seam (geometry.cpp separates definitions by ONE blank line, so the pad is "\n\n" each way); a
#      payload already carrying its separator is not padded again; the byte at endByte is preserved exactly.
#   3. ambiguous symbol (same name in a second file) → error listing BOTH candidates as file:line;
#      file unchanged.
#   4. not-found symbol → error listing nearest names; file unchanged.
#   5. stale-index refusal → with a long-lived server, build the index (read verb), then rewrite the
#      file with DIFFERENT content while PRESERVING its mtime (the case the mtime watch is blind to) →
#      the edit is REFUSED and the file keeps the external content (never spliced against stale offsets).
#   6. after a successful edit, a follow-up find_symbol sees the NEW content (index refreshed).
#   7. determinism of error messages (an ambiguous-symbol refusal is byte-identical across two calls).
#   8. the fixture COPY's final state after the full replace/insert sequence == an expected file we
#      construct here (cmp — exactly derivable).
#
# NEVER edits test/fixture itself: every mutation happens on a scratch COPY in a mktemp dir.
#
# Usage:
#   test/mcpeditcheck.sh
#   RIPWIRE_BIN=asan/ripwire test/mcpeditcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.
# Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/fixture"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for JSON assertions"; exit 2; }

echo "mcpeditcheck: BIN=$BIN  FIX=$FIX"

# ─── helpers ─────────────────────────────────────────────────────────────────

mcp_call() { printf '%s\n' "$@" | "$BIN" --mcp 2>/dev/null; }

# extract the tools/call (id=2) inner text, or __ERROR__:<message> on error.
inner_or_err() {
    tail -1 "$1" | python3 -c '
import sys, json
r = json.load(sys.stdin)
if "error" in r:
    print("__ERROR__:" + r["error"].get("message",""))
else:
    print(r["result"]["content"][0]["text"])
'
}

# a fresh scratch COPY of the fixture (NEVER touch test/fixture).
fresh_copy() {
    local d; d="$( mktemp -d "$TMP/work.XXXXXX" )"
    cp -R "$FIX/"* "$d/"
    printf '%s' "$d"
}

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 1. replace_symbol_body: exact splice, surrounding bytes byte-identical ==="
# ═══════════════════════════════════════════════════════════════════════════
W1="$( fresh_copy )"
ORIG="$W1/geometry.cpp"
cp "$ORIG" "$TMP/geo.orig"

# perimeter is defined in BOTH geometry.cpp and geometry.h (a declaration) → disambiguate with file.
NEWBODY='double perimeter( const Point* pts, int n )\n{\n    return 42.0;\n}'
mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"replace_symbol_body\",\"arguments\":{\"path\":\"$W1\",\"symbol\":\"perimeter\",\"file\":\"geometry.cpp\",\"new_body\":\"$NEWBODY\"}}}" \
    >"$TMP/r1"
R1="$( inner_or_err "$TMP/r1" )"
case "$R1" in
    __ERROR__*) no "replace_symbol_body: unexpected error: ${R1#__ERROR__:}";;
    *'"applied":"replace_symbol_body"'*) ok "replace_symbol_body: returned a success payload";;
    *) no "replace_symbol_body: unexpected result: $( echo "$R1" | head -c 200 )";;
esac

# the new body is present, verbatim.
grep -q "return 42.0;" "$ORIG" \
    && ok "replace_symbol_body: new body spliced into the file" \
    || no "replace_symbol_body: new body not found in file"

# span reported in the payload; the PREFIX [0,start) and SUFFIX [end,eof) must be byte-identical to
# the same regions of the original. Compute from the reported span and cmp the regions.
python3 - "$TMP/geo.orig" "$ORIG" "$R1" <<'PY' >"$TMP/r1_regions"
import sys, json
orig = open(sys.argv[1], "rb").read()
new  = open(sys.argv[2], "rb").read()
pay  = json.loads(sys.argv[3])
a = pay["span"]["start"]; b = pay["span"]["end"]
# prefix [0,a) identical in both; suffix after the span identical to the original's tail.
# original span length = len(orig) - (len(new) - (b - a))
orig_span_len = len(orig) - (len(new) - (b - a))
pfx_ok = orig[:a] == new[:a]
sfx_ok = orig[a+orig_span_len:] == new[b:]
print("PFX_OK" if pfx_ok else "PFX_BAD")
print("SFX_OK" if sfx_ok else "SFX_BAD")
PY
grep -q PFX_OK "$TMP/r1_regions" \
    && ok "replace_symbol_body: prefix bytes before the span are byte-identical" \
    || no "replace_symbol_body: prefix bytes changed"
grep -q SFX_OK "$TMP/r1_regions" \
    && ok "replace_symbol_body: suffix bytes after the span are byte-identical" \
    || no "replace_symbol_body: suffix bytes changed"

# F-16: span is the POST-EDIT range (its length is the PAYLOAD's length), not the region overwritten
# in the OLD file — replaced_bytes is that separate number. orig_span_len below is computed the OLD
# way (from file-size deltas, same formula as the prefix/suffix check above); replaced_bytes must equal
# it exactly.
python3 - "$TMP/geo.orig" "$ORIG" "$R1" <<'PY' >"$TMP/r1_replaced"
import sys, json
orig = open(sys.argv[1], "rb").read()
new  = open(sys.argv[2], "rb").read()
pay  = json.loads(sys.argv[3])
a = pay["span"]["start"]; b = pay["span"]["end"]
orig_span_len = len(orig) - (len(new) - (b - a))
print("MATCH" if pay.get("replaced_bytes") == orig_span_len else "MISMATCH got=%r want=%r" % (pay.get("replaced_bytes"), orig_span_len))
PY
grep -q '^MATCH' "$TMP/r1_replaced" \
    && ok "replace_symbol_body: replaced_bytes equals the OLD span length, distinct from the post-edit span=" \
    || no "replace_symbol_body: replaced_bytes disagrees with the old span length: $( cat "$TMP/r1_replaced" )"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 1b. F-07: a CRLF-dominant target's payload is harmonized, never left mixed ==="
# ═══════════════════════════════════════════════════════════════════════════
W1B="$( mktemp -d "$TMP/work.XXXXXX" )"
printf 'int crlfFn( int n )\r\n{\r\n    return n + 1;\r\n}\r\n' > "$W1B/crlf.cpp"
NEWBODY_LF='int crlfFn( int n )\n{\n    return 7;\n}'
mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"replace_symbol_body\",\"arguments\":{\"path\":\"$W1B\",\"symbol\":\"crlfFn\",\"new_body\":\"$NEWBODY_LF\"}}}" \
    >"$TMP/rcrlf"
RCRLF="$( inner_or_err "$TMP/rcrlf" )"
case "$RCRLF" in
    __ERROR__*) no "F-07: unexpected error: ${RCRLF#__ERROR__:}";;
    *'"file_eol":"crlf"'*'"eol_normalized":true'*) ok "F-07: receipt discloses file_eol=crlf and eol_normalized=true";;
    *) no "F-07: receipt did not disclose the CRLF harmonization: $( echo "$RCRLF" | head -c 200 )";;
esac
# no BARE '\n' anywhere in the result — every '\n' must be immediately preceded by '\r'.
if python3 -c "
import sys
b = open('$W1B/crlf.cpp','rb').read()
bad = any(b[i]==10 and (i==0 or b[i-1]!=13) for i in range(len(b)))
sys.exit(1 if bad else 0)
"; then
    ok "F-07: the spliced file carries NO bare LF — uniformly CRLF, not mixed"
else
    no "F-07: the spliced file still has a bare LF mixed with CRLF"
fi
grep -q 'return 7' "$W1B/crlf.cpp" && ok "F-07: the new body is present" || no "F-07: new body missing after CRLF splice"

# a plain-LF target is left untouched — normalization is Crlf-target-only.
W1C="$( mktemp -d "$TMP/work.XXXXXX" )"
printf 'int lfFn( int n )\n{\n    return n + 1;\n}\n' > "$W1C/lf.cpp"
mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"replace_symbol_body\",\"arguments\":{\"path\":\"$W1C\",\"symbol\":\"lfFn\",\"new_body\":\"int lfFn( int n )\\n{\\n    return 7;\\n}\"}}}" \
    >"$TMP/rlf"
RLF="$( inner_or_err "$TMP/rlf" )"
case "$RLF" in
    *'"file_eol":"lf"'*'"eol_normalized":false'*) ok "F-07: an LF-dominant target reports file_eol=lf, eol_normalized=false (untouched)";;
    *) no "F-07: LF-target receipt unexpected: $( echo "$RLF" | head -c 200 )";;
esac

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 2. insert_before / insert_after: placement + newline rule ==="
# ═══════════════════════════════════════════════════════════════════════════

# insert_before distance (text WITHOUT trailing newline) → text, then '\n', then 'double distance'.
W2="$( fresh_copy )"
mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"insert_before_symbol\",\"arguments\":{\"path\":\"$W2\",\"symbol\":\"distance\",\"file\":\"geometry.cpp\",\"text\":\"// INSERTED-BEFORE\"}}}" \
    >"$TMP/r2b"
[ "$( inner_or_err "$TMP/r2b" | grep -c '__ERROR__' )" = "0" ] \
    && ok "insert_before_symbol: returned a success payload" \
    || no "insert_before_symbol: returned an error: $( inner_or_err "$TMP/r2b" )"
python3 - "$W2/geometry.cpp" <<'PY' >"$TMP/r2b_chk"
import sys
src = open(sys.argv[1], "rb").read().decode()
i = src.find("// INSERTED-BEFORE")
# exactly one '\n' between the marker and the following 'double distance'
seg = src[i:]
print("OK" if seg.startswith("// INSERTED-BEFORE\n\ndouble distance") else "BAD:" + repr(seg[:60]))
PY
[ "$( cat "$TMP/r2b_chk" )" = "OK" ] \
    && ok "insert_before_symbol: seam rule — padded to the file's one-blank-line separator (separator_padded=2)" \
    || no "insert_before_symbol: seam rule wrong: $( cat "$TMP/r2b_chk" )"
grep -q 'separator_padded[^0-9]*2' "$TMP/r2b" \
    && ok "insert_before_symbol: the receipt discloses separator_padded:2" \
    || no "insert_before_symbol: the receipt does not disclose separator_padded:2"

# insert_after distance (text WITHOUT leading newline) → closing '}', '\n', text; byte at endByte preserved.
W2b="$( fresh_copy )"
mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"insert_after_symbol\",\"arguments\":{\"path\":\"$W2b\",\"symbol\":\"distance\",\"file\":\"geometry.cpp\",\"text\":\"// INSERTED-AFTER\"}}}" \
    >"$TMP/r2a"
[ "$( inner_or_err "$TMP/r2a" | grep -c '__ERROR__' )" = "0" ] \
    && ok "insert_after_symbol: returned a success payload" \
    || no "insert_after_symbol: returned an error: $( inner_or_err "$TMP/r2a" )"
python3 - "$W2b/geometry.cpp" <<'PY' >"$TMP/r2a_chk"
import sys
src = open(sys.argv[1], "rb").read().decode()
i = src.find("// INSERTED-AFTER")
# the marker must be immediately preceded by "}\n" (def's closing brace, then the prepended newline),
# and the byte at endByte (the original '\n' after '}') must be preserved right before it.
before = src[i-3:i]
print("OK" if before == "}\n\n" else "BAD:" + repr(src[i-8:i+20]))
PY
[ "$( cat "$TMP/r2a_chk" )" = "OK" ] \
    && ok "insert_after_symbol: seam rule — padded to the file's one-blank-line separator, endByte byte preserved" \
    || no "insert_after_symbol: seam rule wrong: $( cat "$TMP/r2a_chk" )"

# seam rule pads to the separator and no further: text that ALREADY ends with '\n' gains exactly one more (the
# blank line), never two; text carrying "\n\n" is left alone (editroundtripcheck (G) pins the zero-pad case).
W2c="$( fresh_copy )"
mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"insert_before_symbol\",\"arguments\":{\"path\":\"$W2c\",\"symbol\":\"distance\",\"file\":\"geometry.cpp\",\"text\":\"// PRENL\\n\"}}}" \
    >/dev/null
python3 - "$W2c/geometry.cpp" <<'PY' >"$TMP/r2c_chk"
import sys
src = open(sys.argv[1], "rb").read().decode()
i = src.find("// PRENL")
seg = src[i:]
print("OK" if seg.startswith("// PRENL\n\ndouble distance") else "BAD:" + repr(seg[:40]))
PY
[ "$( cat "$TMP/r2c_chk" )" = "OK" ] \
    && ok "insert_before_symbol: an existing trailing '\\n' is padded by exactly one more, to the separator" \
    || no "insert_before_symbol: pad past the separator: $( cat "$TMP/r2c_chk" )"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 3. ambiguous symbol → error listing BOTH candidates; file unchanged ==="
# ═══════════════════════════════════════════════════════════════════════════
# Add a SECOND definition of a uniquely-named function in a second file, so it is ambiguous across files.
W3="$( fresh_copy )"
cat >"$W3/dup_a.cpp" <<'EOF'
void widget_twin() { }
EOF
cat >"$W3/dup_b.cpp" <<'EOF'
void widget_twin() { }
EOF
cp "$W3/dup_a.cpp" "$TMP/dup_a.orig"
mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"replace_symbol_body\",\"arguments\":{\"path\":\"$W3\",\"symbol\":\"widget_twin\",\"new_body\":\"void widget_twin() { return; }\"}}}" \
    >"$TMP/r3"
R3="$( inner_or_err "$TMP/r3" )"
case "$R3" in
    __ERROR__*ambiguous*dup_a.cpp*dup_b.cpp*) ok "ambiguous: error lists BOTH candidate files (dup_a.cpp + dup_b.cpp)";;
    __ERROR__*ambiguous*) no "ambiguous: error is ambiguous-typed but missing a candidate: ${R3#__ERROR__:}";;
    *) no "ambiguous: expected an ambiguity refusal, got: $( echo "$R3" | head -c 200 )";;
esac
cmp -s "$W3/dup_a.cpp" "$TMP/dup_a.orig" \
    && ok "ambiguous: target file left byte-identical (no partial write)" \
    || no "ambiguous: target file was modified despite the refusal"

# 7. determinism of the error message (two identical ambiguous calls → byte-identical responses).
mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"replace_symbol_body\",\"arguments\":{\"path\":\"$W3\",\"symbol\":\"widget_twin\",\"new_body\":\"x\"}}}" \
    >"$TMP/r3_a"
mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"replace_symbol_body\",\"arguments\":{\"path\":\"$W3\",\"symbol\":\"widget_twin\",\"new_body\":\"x\"}}}" \
    >"$TMP/r3_b"
diff -q "$TMP/r3_a" "$TMP/r3_b" >/dev/null \
    && ok "ambiguous: error message is deterministic (byte-identical across two calls)" \
    || no "ambiguous: error message non-deterministic"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 4. not-found symbol → error with nearest-names hint; file unchanged ==="
# ═══════════════════════════════════════════════════════════════════════════
W4="$( fresh_copy )"
cp "$W4/geometry.cpp" "$TMP/geo4.orig"
mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"replace_symbol_body\",\"arguments\":{\"path\":\"$W4\",\"symbol\":\"perimetre\",\"new_body\":\"x\"}}}" \
    >"$TMP/r4"
R4="$( inner_or_err "$TMP/r4" )"
case "$R4" in
    __ERROR__*not\ found*nearest:*) ok "not-found: error reports 'not found' + a nearest-names hint";;
    __ERROR__*not\ found*) ok "not-found: error reports 'not found' (no nearest hint, acceptable)";;
    *) no "not-found: expected a not-found refusal, got: $( echo "$R4" | head -c 200 )";;
esac
cmp -s "$W4/geometry.cpp" "$TMP/geo4.orig" \
    && ok "not-found: target file left byte-identical" \
    || no "not-found: target file was modified despite the refusal"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 5. stale-index refusal (content changed, mtime preserved) — edit REFUSED, file unchanged ==="
# ═══════════════════════════════════════════════════════════════════════════
# Drive a LONG-LIVED server over a FIFO: (a) read verb builds the index; (b) rewrite the file with
# different content but restore its mtime; (c) attempt an edit → must be REFUSED and file unchanged.
#
# S1 note: mcpStale now catches a content-changed-but-mtime-preserved
# edit via a per-file content-hash compare (it used to be blind to it). So getIndex() REBUILDS from the new
# content BEFORE the edit verb runs: the rewritten file ("totally different content …") no longer defines
# `distance`, so resolveOneForEdit refuses with a "not found" message rather than the edit verb's own later
# "changed since index" byte-hash refusal. BOTH are correct refusals that leave the file byte-identical —
# the safety contract (the invariant this gate protects) is unchanged; only the refusal MESSAGE moved
# earlier because the index is no longer stale. This gate accepts either refusal path.
W5="$( fresh_copy )"
GEO5="$W5/geometry.cpp"
FIFO="$W5/in.fifo"; mkfifo "$FIFO"
"$BIN" --mcp <"$FIFO" >"$W5/out.txt" 2>/dev/null &
SRV=$!
exec 9>"$FIFO"
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' >&9
printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$W5\",\"symbol\":\"distance\"}}}" >&9

# wait deterministically for the read-verb response (id=2) to land BEFORE we rewrite — this makes the
# index-built-before-rewrite ordering guaranteed, not timing-dependent.
for _ in $( seq 1 100 ); do
    grep -q '"id":2' "$W5/out.txt" 2>/dev/null && break
    sleep 0.05
done

# rewrite with DIFFERENT content, then restore the ORIGINAL mtime so mcpStale()'s mtime watch stays blind.
REF="$TMP/ref5"; touch -r "$GEO5" "$REF"
printf 'totally different content — byte hash no longer matches the index\n' > "$GEO5"
touch -r "$REF" "$GEO5"
cp "$GEO5" "$TMP/geo5.external"

printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"replace_symbol_body\",\"arguments\":{\"path\":\"$W5\",\"symbol\":\"distance\",\"file\":\"geometry.cpp\",\"new_body\":\"SPLICED\"}}}" >&9

for _ in $( seq 1 100 ); do
    grep -q '"id":3' "$W5/out.txt" 2>/dev/null && break
    sleep 0.05
done
exec 9>&-
wait "$SRV" 2>/dev/null

R5="$( grep '"id":3' "$W5/out.txt" | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
print("__ERROR__:" + r["error"].get("message","")) if "error" in r else print(r["result"]["content"][0]["text"])
' )"
case "$R5" in
    __ERROR__*changed\ since\ index*) ok "stale-index: edit REFUSED with 'changed since index' message (edit-verb byte-hash guard)";;
    __ERROR__*not\ found*)             ok "stale-index: edit REFUSED with 'not found' (S1: index rebuilt from new content, symbol gone)";;
    __ERROR__*) no "stale-index: refused but wrong message: ${R5#__ERROR__:}";;
    *) no "stale-index: edit was NOT refused (applied against stale offsets): $( echo "$R5" | head -c 200 )";;
esac
cmp -s "$GEO5" "$TMP/geo5.external" \
    && ok "stale-index: file keeps the external content (never spliced)" \
    || no "stale-index: file was modified despite the refusal"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 6. after a successful edit, follow-up find_symbol sees the NEW content ==="
# ═══════════════════════════════════════════════════════════════════════════
# One long-lived server: edit distance's body to add a NEW callee (call newcallee()), then find_symbol
# on 'distance' must report the new callee in its 'calls' list (index rebuilt from the post-edit file).
W6="$( fresh_copy )"
# add a definition of newcallee so the call edge resolves after the edit.
cat >>"$W6/geometry.cpp" <<'EOF'

double newcallee() { return 1.0; }
EOF
FIFO6="$W6/in.fifo"; mkfifo "$FIFO6"
"$BIN" --mcp <"$FIFO6" >"$W6/out.txt" 2>/dev/null &
SRV6=$!
exec 8>"$FIFO6"
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' >&8
# edit distance's body to call newcallee()
printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"replace_symbol_body\",\"arguments\":{\"path\":\"$W6\",\"symbol\":\"distance\",\"file\":\"geometry.cpp\",\"new_body\":\"double distance( Point a, Point b )\\n{\\n    return newcallee();\\n}\"}}}" >&8
for _ in $( seq 1 100 ); do grep -q '"id":2' "$W6/out.txt" 2>/dev/null && break; sleep 0.05; done
# now query distance — its calls must include newcallee (proves the index refreshed from the new bytes)
printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$W6\",\"symbol\":\"distance\"}}}" >&8
for _ in $( seq 1 100 ); do grep -q '"id":3' "$W6/out.txt" 2>/dev/null && break; sleep 0.05; done
exec 8>&-
wait "$SRV6" 2>/dev/null
R6="$( grep '"id":3' "$W6/out.txt" | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
print(r["result"]["content"][0]["text"]) if "result" in r else print("__ERROR__")
' )"
case "$R6" in
    *newcallee*) ok "index refreshed: post-edit find_symbol(distance) sees the new callee 'newcallee'";;
    *) no "index NOT refreshed: distance's calls do not include newcallee: $( echo "$R6" | head -c 200 )";;
esac

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 8. full sequence → final state == an expected file we construct (cmp) ==="
# ═══════════════════════════════════════════════════════════════════════════
# Apply a deterministic sequence to a fresh copy of geometry.cpp and cmp against a hand-built expected file.
#   (i)  replace_symbol_body distance  -> a fixed 3-line body
#   (ii) insert_after_symbol  distance -> a one-line comment (no leading newline in text; the seam rule pads
#        it to the fixture's one-blank-line separator, "\n\n")
W8="$( fresh_copy )"
mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"replace_symbol_body\",\"arguments\":{\"path\":\"$W8\",\"symbol\":\"distance\",\"file\":\"geometry.cpp\",\"new_body\":\"double distance( Point a, Point b )\\n{\\n    return 0.0;\\n}\"}}}" \
    >/dev/null
mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"insert_after_symbol\",\"arguments\":{\"path\":\"$W8\",\"symbol\":\"distance\",\"file\":\"geometry.cpp\",\"text\":\"// tail-comment\"}}}" \
    >/dev/null

# Build the expected file: take the ORIGINAL fixture, replace the distance def span, then insert after it.
# The original distance def is bytes [40, 224) in the fixture (sig start .. closing brace). Rather than
# hardcode offsets, reconstruct expected by string surgery on the known original text.
python3 - "$FIX/geometry.cpp" "$TMP/expected8.cpp" <<'PY'
import sys, re
orig = open(sys.argv[1]).read()
# the distance definition, exactly as it appears in the fixture (sig through closing brace).
old_def = ('double distance( Point a, Point b )\n'
           '{\n'
           '    const double dx = a.x - b.x;\n'
           '    const double dy = a.y - b.y;\n'
           '    return std::sqrt( dx * dx + dy * dy );\n'
           '}')
new_def = ('double distance( Point a, Point b )\n'
           '{\n'
           '    return 0.0;\n'
           '}')
assert old_def in orig, "fixture distance def shape changed — update the gate"
i = orig.index(old_def)
end = i + len(old_def)
# replace_symbol_body: swap the def; insert_after_symbol: padded to the separator after the def ("\n\n" —
# the fixture keeps one blank line between definitions), inserted at the new def's endByte, preserving the
# byte that followed the def (the original '\n').
expected = orig[:i] + new_def + '\n\n// tail-comment' + orig[end:]
open(sys.argv[2], "w").write(expected)
PY
cmp -s "$W8/geometry.cpp" "$TMP/expected8.cpp" \
    && ok "full sequence: final file == the exactly-derived expected file (cmp clean)" \
    || { no "full sequence: final file differs from expected"; diff "$TMP/expected8.cpp" "$W8/geometry.cpp" | head -20; }

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 9. @FILE:LINE line-seeds address the edit verbs (2026-08-30 decision round) ==="
# ═══════════════════════════════════════════════════════════════════════════
# The agent editing from a diff hunk holds exactly FILE:LINE — the seed resolves the target through
# graph.h::resolveAtSeed with the shared at-diagnoses; the safety contract downstream is UNCHANGED.
W9="$( fresh_copy )"
cp "$W9/geometry.cpp" "$TMP/geo9.orig"

# (9a) a resolvable seed (line 6 = inside `distance`) edits THAT definition; the receipt discloses
# the resolved symbol AND resolved_from_seed (the of=-echo posture: the seed as typed)
NB9='double distance( Point a, Point b )\n{\n    return 9.0;\n}'
mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"replace_symbol_body\",\"arguments\":{\"path\":\"$W9\",\"symbol\":\"@geometry.cpp:6\",\"new_body\":\"$NB9\"}}}" \
    >"$TMP/r9a"
R9A="$( inner_or_err "$TMP/r9a" )"
case "$R9A" in
    *'"symbol":"distance"'*'"resolved_from_seed":"@geometry.cpp:6"'*) ok "(9a) @seed edit: resolved to distance, receipt discloses resolved_from_seed";;
    *) no "(9a) @seed edit: receipt wrong: $( echo "$R9A" | head -c 300 )";;
esac
grep -q "return 9.0;" "$W9/geometry.cpp" \
    && ok "(9a) @seed edit: the seed's definition body spliced" \
    || no "(9a) @seed edit: new body not found in file"

# (9b) a FAULTED seed refuses with the shared at-diagnosis and the file stays byte-identical
W9B="$( fresh_copy )"
cp "$W9B/geometry.cpp" "$TMP/geo9b.orig"
mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"replace_symbol_body\",\"arguments\":{\"path\":\"$W9B\",\"symbol\":\"@geometry.cpp:3\",\"new_body\":\"$NB9\"}}}" \
    >"$TMP/r9b"
R9B="$( inner_or_err "$TMP/r9b" )"
case "$R9B" in
    __ERROR__*'no indexed symbol spans line 3'*) ok "(9b) @faulted-seed: refused with the at-diagnosis";;
    *) no "(9b) @faulted-seed: expected the at-diagnosis error: $( echo "$R9B" | head -c 300 )";;
esac
cmp -s "$W9B/geometry.cpp" "$TMP/geo9b.orig" \
    && ok "(9b) @faulted-seed: file byte-identical after the refusal" \
    || no "(9b) @faulted-seed: file changed on a refusal"

# (9c) a `file` hint cannot narrow a seed — the seed already names exactly one file and line
mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"insert_after_symbol\",\"arguments\":{\"path\":\"$W9B\",\"symbol\":\"@geometry.cpp:6\",\"file\":\"geometry.cpp\",\"text\":\"// x\"}}}" \
    >"$TMP/r9c"
R9C="$( inner_or_err "$TMP/r9c" )"
case "$R9C" in
    __ERROR__*'line seed'*) ok "(9c) @seed + file hint: refused (the seed already names one file)";;
    *) no "(9c) @seed + file hint: expected the hint-conflict refusal: $( echo "$R9C" | head -c 300 )";;
esac
cmp -s "$W9B/geometry.cpp" "$TMP/geo9b.orig" \
    && ok "(9c) @seed + file hint: file byte-identical after the refusal" \
    || no "(9c) @seed + file hint: file changed on a refusal"

# (9d) a seed resolving to a markdown heading/Section refuses — the edit-safety kind guard holds for
# seed-addressed targets exactly as for name-addressed ones (nothing may WRITE through a Section)
cp "$W9B/notes.md" "$TMP/notes9.orig"
mcp_call \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"replace_symbol_body\",\"arguments\":{\"path\":\"$W9B\",\"symbol\":\"@notes.md:1\",\"new_body\":\"# nope\"}}}" \
    >"$TMP/r9d"
R9D="$( inner_or_err "$TMP/r9d" )"
case "$R9D" in
    __ERROR__*'heading/section'*) ok "(9d) @seed on a doc Section: refused by the kind guard";;
    *) no "(9d) @seed on a doc Section: expected the heading/section refusal: $( echo "$R9D" | head -c 300 )";;
esac
cmp -s "$W9B/notes.md" "$TMP/notes9.orig" \
    && ok "(9d) @seed on a doc Section: doc byte-identical after the refusal" \
    || no "(9d) @seed on a doc Section: doc changed on a refusal"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
