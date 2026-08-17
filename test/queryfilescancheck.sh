#!/usr/bin/env bash
# queryfilescancheck.sh — gate for §R-J (Wave-2 harvest item, PLAN_EXTREPO_HARVEST_2026-08-15.md): the
# queries/*/tags.scm visibility fix.
#
# THE FINDING THIS CLOSES. In the 2026-08-15 harvest, an H-severity extraction bug's root cause lived at
# queries/cpp/tags.scm line 14 (the `qualified_identifier` capture) — and ripwire itself could not find it.
# queries/*/tags.scm carries the ".scm" extension, which has no grammar and no doc handler, so the crawl
# drops it as `why="unsupported-ext"` and it never gets a fileId. Every verb that answers from the index
# — --grep, --for, --whereis, all of them — was therefore blind to it. The tool could not locate the root
# cause of a bug in its own extraction rules.
#
# THE RECORDED RED STATE (probed 2026-08-17 against the wave2 baseline binary, integration/wave2-2026-08-17
# @ ab59ca8, BEFORE this lane's fix — reproduce with RIPWIRE_BIN pointed at that binary):
#   ./build/ripwire . --grep=qualified_identifier   → no <f p="queries/cpp/tags.scm"> row at all
#   ./build/ripwire . --grep=tags.scm               → same: zero hits inside queries/*/tags.scm
#   ./build/ripwire . --whereis=tags.scm             → unaffected (a different, git-ref-scoped surface;
#                                                       out of scope for this fix — see the lane report)
#   ./build/ripwire . --skipped                      → DOES list all 16 queries/*/tags.scm rows, each
#                                                       why="unsupported-ext" ext=".scm" — the crawl always
#                                                       knew about them; no VERB could search their TEXT.
#
# THE FIX (option (b) of the plan's two: --grep additionally scans the crawl's own unsupported-ext/
# text-looking population — CrawlSkips::unsupported, already computed at ingest time, capped at
# kMaxSkipRowsPerClass — rather than a new query-file INDEX tier). No kParserVer bump: nothing new is
# STORED, so no cache format change, no collision with the cache-keying work landing elsewhere this wave.
# See search.h's grepCollectAux for the scan and src/main.cpp's emitGrepReport / src/mcpverbs.h's
# grepHitsJson for the two emitters (CLI <unindexed> element + unindexed_files_scanned= root attribute;
# MCP "unindexed" array + "unindexed_files_scanned" key).
#
# Asserts:
#   (1) THE C1-HUNT REPLAY (decisive arm) — on ripwire's OWN tree, --grep='qualified_identifier' (the exact
#       token that names the capture syntax at the root-cause line) now returns a hit at
#       queries/cpp/tags.scm, and the reported LINE matches an INDEPENDENT oracle (/usr/bin/grep -n -F,
#       never hardcoded — a line number pinned by hand rots the moment the file is edited again).
#   (2) DISCLOSURE — unindexed_files_scanned= is present on the root and its value is independently
#       recomputed: walk --skipped's own unsupported-ext rows, exclude any whose first 4096 B contain a
#       NUL byte (the same sniff grepCollectAux runs) or whose size exceeds the crawl's max-file-size
#       ceiling, and the surviving count must equal the attribute.
#   (3) NO-REGRESSION — a corpus with zero unsupported-ext files (test/fixture) emits
#       unindexed_files_scanned="0" and NO <unindexed> element at all — the existing grepcheck/
#       grepcontextcheck/grepscancheck family's byte-level assertions over that same fixture are the
#       deeper proof (run alongside this gate in regression.sh), this is the shallow confirmation.
#   (4) BINARY-FILE GUARD — an unsupported-ext file whose bytes are NUL-poisoned but which STILL contains
#       the search pattern in its readable prefix must NOT produce a hit row, and must count toward
#       unindexed_files_skipped.
#   (5) CLI/MCP PARITY — the MCP `grep` verb's JSON carries the same unindexed_files_scanned fact for the
#       SAME C1-hunt query (mcpclidiffcheck.sh's LENS2 already pins the key exists on some query; this
#       pins it specifically on the query that matters, and that the MCP "unindexed" array also names
#       queries/cpp/tags.scm).
#   (6) DETERMINISM — the C1-hunt query, run twice, is byte-identical.
#   (7) WELL-FORMEDNESS — the new <unindexed> shape passes xmllint.
#
# Usage:
#   bash test/queryfilescancheck.sh
#   RIPWIRE_BIN=asan/ripwire bash test/queryfilescancheck.sh
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
command -v python3 >/dev/null 2>&1 || { echo "python3 required for JSON/independent-oracle assertions"; exit 2; }
cd "$ROOT"
echo "queryfilescancheck: BIN=$BIN"

# ── (1) THE C1-HUNT REPLAY — the decisive arm ────────────────────────────────────────────────────────────
"$BIN" . --grep=qualified_identifier >"$TMP/c1.xml" 2>/dev/null

TARGET="queries/cpp/tags.scm"
ORACLE_LINES="$( /usr/bin/grep -n -F 'qualified_identifier' "$ROOT/$TARGET" | cut -d: -f1 | sort -n | uniq )"
[ -n "$ORACLE_LINES" ] \
    && ok "(1a) independent oracle: /usr/bin/grep finds qualified_identifier in $TARGET (sanity check on the fixture itself)" \
    || { no "(1a) $TARGET no longer contains qualified_identifier at all — the C1-hunt replay has nothing to find (fixture drift, update the gate)"; }

RIPWIRE_LINES="$( python3 - "$TMP/c1.xml" "$TARGET" <<'PY'
import re, sys
xml, target = sys.argv[1], sys.argv[2]
text = open(xml, encoding='utf-8', errors='replace').read().split('-->', 1)[-1]
out = []
for fm in re.finditer(r'<f p="([^"]*)">(.*?)</f>', text, re.S):
    path = fm.group(1)
    if path != target and not path.endswith('/' + target):
        continue
    for hm in re.finditer(r'<hit l="(\d+)"', fm.group(2)):
        out.append(hm.group(1))
for l in sorted(set(out), key=int):
    print(l)
PY
)"

if [ -n "$RIPWIRE_LINES" ]; then
    ok "(1b) --grep=qualified_identifier on ripwire's own tree returns a hit at $TARGET (was INVISIBLE before this lane)"
else
    no "(1b) --grep=qualified_identifier still returns NO hit at $TARGET — the R-J fix regressed"
fi

if [ -n "$ORACLE_LINES" ] && [ -n "$RIPWIRE_LINES" ] && [ "$RIPWIRE_LINES" = "$ORACLE_LINES" ]; then
    ok "(1c) the reported line set matches the independent oracle exactly: $( printf '%s' "$RIPWIRE_LINES" | tr '\n' ',' | sed 's/,$//' )"
else
    no "(1c) line set mismatch — ripwire: [$( printf '%s' "$RIPWIRE_LINES" | tr '\n' ',' )] oracle: [$( printf '%s' "$ORACLE_LINES" | tr '\n' ',' )]"
fi

# no= (in=) on this hit — there is no symbol table for a file the index never carried
grep -q "<f p=\"$TARGET\">" "$TMP/c1.xml" && ! /usr/bin/grep -o "<f p=\"$TARGET\">[^<]*<hit[^>]*in=" "$TMP/c1.xml" >/dev/null 2>&1 \
    && ok "(1d) the $TARGET hit carries no in= — honest by construction (no field to check, not an empty one)" \
    || no "(1d) the $TARGET hit unexpectedly carries in= (there is no symbol table for this file)"

# ── (2) DISCLOSURE — unindexed_files_scanned= is present and independently recomputed ──────────────────────
SCANNED_ATTR="$( grep -o 'unindexed_files_scanned="[0-9]*"' "$TMP/c1.xml" | head -1 | grep -o '[0-9]*' )"
[ -n "$SCANNED_ATTR" ] \
    && ok "(2a) unindexed_files_scanned= is present on the root ($SCANNED_ATTR)" \
    || no "(2a) unindexed_files_scanned= is missing from the root entirely"

"$BIN" . --skipped >"$TMP/skipped.xml" 2>/dev/null
MAXBYTES="$( grep -o 'max_file_size="[0-9]*"' "$TMP/skipped.xml" | head -1 | grep -o '[0-9]*' )"
INDEPENDENT_SCANNED="$( python3 - "$TMP/skipped.xml" "$ROOT" "${MAXBYTES:-4194304}" <<'PY'
import re, sys
xml, root, maxbytes = sys.argv[1], sys.argv[2], int(sys.argv[3])
text = open(xml, encoding='utf-8', errors='replace').read()
n = 0
for m in re.finditer(r'<f p="([^"]*)" why="unsupported-ext" bytes="(\d+)"', text):
    path, nbytes = m.group(1), int(m.group(2))
    if nbytes > maxbytes:
        continue
    fp = path if path.startswith('/') else root + '/' + path.lstrip('./')
    try:
        with open(fp, 'rb') as fh:
            head = fh.read(4096)
    except OSError:
        continue
    if b'\x00' in head:
        continue
    n += 1
print(n)
PY
)"
if [ -n "$SCANNED_ATTR" ] && [ "$SCANNED_ATTR" = "$INDEPENDENT_SCANNED" ]; then
    ok "(2b) unindexed_files_scanned=$SCANNED_ATTR matches an independent recount of --skipped's unsupported-ext rows ($INDEPENDENT_SCANNED)"
else
    no "(2b) unindexed_files_scanned=$SCANNED_ATTR but an independent recount of --skipped's rows gives $INDEPENDENT_SCANNED"
fi

# ── (3) NO-REGRESSION — a corpus with zero unsupported-ext files stays silent about the new tier ──────────
"$BIN" test/fixture --grep=perimeter >"$TMP/fix.xml" 2>/dev/null
grep -q 'unindexed_files_scanned="0"' "$TMP/fix.xml" \
    && ok "(3a) test/fixture (no unsupported-ext files) reports unindexed_files_scanned=\"0\"" \
    || { no "(3a) test/fixture did not report unindexed_files_scanned=\"0\""; grep -o '<grep[^>]*>' "$TMP/fix.xml"; }
grep -q '<unindexed' "$TMP/fix.xml" \
    && no "(3b) test/fixture emitted an <unindexed> element with nothing to scan (should be omitted)" \
    || ok "(3b) no <unindexed> element on a corpus with nothing outside the index (absent-means-none)"

# ── (4) BINARY-FILE GUARD ────────────────────────────────────────────────────────────────────────────────
BFDIR="$TMP/binfix"
mkdir -p "$BFDIR/srcdir"
echo 'int QFSCANMARKER_fn() { return 1; }' > "$BFDIR/srcdir/main.cpp"
printf 'QFSCANMARKER before the NUL\x00binary tail QFSCANMARKER after' > "$BFDIR/blob.qfsguard"
"$BIN" "$BFDIR" --grep=QFSCANMARKER >"$TMP/bin.xml" 2>/dev/null
grep -q 'blob\.qfsguard' "$TMP/bin.xml" \
    && no "(4a) a NUL-poisoned unsupported-ext file produced a hit row — the binary sniff did not fire" \
    || ok "(4a) a NUL-poisoned unsupported-ext file produced NO hit row (binary sniff fired)"
grep -qE 'unindexed_files_skipped="[1-9]' "$TMP/bin.xml" \
    && ok "(4b) the skip is disclosed via unindexed_files_skipped= (not a silent drop)" \
    || { no "(4b) unindexed_files_skipped= is missing or zero despite the binary-guard skip"; grep -o '<grep[^>]*>' "$TMP/bin.xml"; }
grep -q 'QFSCANMARKER_fn' "$TMP/bin.xml" \
    && ok "(4c) the real (indexed) hit in srcdir/main.cpp is unaffected" \
    || no "(4c) the indexed hit went missing alongside the binary guard"

# ── (5) CLI/MCP PARITY on the C1-hunt query itself ──────────────────────────────────────────────────────
mcp_out="$( { printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"grep","arguments":{"path":"'"$ROOT"'","pattern":"qualified_identifier"}}}' \
    | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
print("__ERROR__:" + r["error"].get("message","") if "error" in r else r["result"]["content"][0]["text"])
'; } )"
case "$mcp_out" in
    __ERROR__*) no "(5a) MCP grep call errored: $mcp_out" ;;
    *)
        printf '%s' "$mcp_out" >"$TMP/mcp_response.json"
        python3 - "$TARGET" "$TMP/mcp_response.json" >"$TMP/mcp.res" 2>&1 <<'PY'
import json, sys
target = sys.argv[1]
with open(sys.argv[2]) as fh:
    j = json.load(fh)
problems = []
if "unindexed_files_scanned" not in j:
    problems.append("missing unindexed_files_scanned key")
names = [row.get("file", "") for row in j.get("unindexed", [])]
hit = any(n == target or n.endswith("/" + target) for n in names)
if not hit:
    problems.append("no %r row in the unindexed array (got %r)" % (target, names))
print("OK" if not problems else " | ".join(problems))
PY
        if [ "$( cat "$TMP/mcp.res" )" = "OK" ]; then
            ok "(5b) MCP grep carries unindexed_files_scanned= and names $TARGET in its unindexed array"
        else
            no "(5b) $( cat "$TMP/mcp.res" )"
        fi
        ;;
esac

# ── (6) determinism ──────────────────────────────────────────────────────────────────────────────────────
"$BIN" . --grep=qualified_identifier >"$TMP/c1_again.xml" 2>/dev/null
diff -q "$TMP/c1.xml" "$TMP/c1_again.xml" >/dev/null \
    && ok "(6) determinism: byte-identical C1-hunt output across two runs" \
    || no "(6) --grep=qualified_identifier output differs run-to-run"

# ── (7) well-formedness ──────────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/c1.xml" 2>/dev/null \
        && ok "(7) the <unindexed> answer is well-formed XML" \
        || { no "(7) malformed XML"; xmllint --noout "$TMP/c1.xml"; }
else
    ok "(7) xmllint not installed — skipped"
fi

if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "SOME CHECKS FAILED"; exit 1; fi
