#!/usr/bin/env bash
# affectedpathcheck.sh — AF5 (lane SW0 plan item 3c, 2026-11-21): one unusable item in an --affected FILE
# list must not cost the agent the answer for the rest of the list.
#
# THE DEFECT. `--affected=<files>` refused the WHOLE call (exit 1, nothing on stdout) when one listed item
# matched no indexed path and no indexed symbol. The common way to build that list is
# `git diff --name-only | paste -sd, -`, and a diff routinely names files the index does not hold: a deleted
# file, a ChangeLog, a generated, vendored or excluded file. SW0 hit it on a SWE-bench patch whose list held a
# `ChangeLog` — the agent got no tests to run for the source files it had just changed.
#
# THE CONTRACT (post-fix):
#   A  a mixed list ANSWERS (exit 0) for the usable items: the <test> rows are byte-identical to the answer
#      for the usable items alone.
#   B  ... and DISCLOSES every item it could not use: unused="N" on the root, one <unused item= reason=> row
#      per item, in list order. reason="not_indexed" = a file by that path exists but the ingest did not
#      index it; reason="not_found" = nothing on disk, no indexed path and no symbol matches it (deleted,
#      renamed or misspelled), with near= naming the closest indexed path when there is one.
#   C  ... and the legend defines unused= and the reasons, only when the root carries the attribute.
#   D  a list with NO usable item is still a refusal (exit 1), never a tests="0" answer — that zero would
#      mean "could not parse", not "none found" — and when it held more than one item the refusal says that
#      none of them resolved.
#   E  a list with no unusable item is byte-identical to before: no unused=, no <unused> row.
#   F  the MCP `affected` twin carries the same disclosure (one renderer, writeAffectedReport) and answers
#      the mixed list instead of erroring.
#   G  determinism (two runs byte-identical) and well-formedness (xmllint) of the mixed answer.
#   H  multi-root: the on-disk reason is read under every root.
#   M  mutation controls: the comparisons above are fed a deliberately wrong document and must FAIL, so a
#      green run cannot come from a comparator that accepts anything.
#
# RED-FIRST: on 36a95d732 arms A, B, C, F fail (the mixed list exits 1 with an empty stdout; MCP returns a
# -32602 error); D's single-item text, E, M pass on both binaries.
#
# Usage:  bash test/affectedpathcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/affectedpathcheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required (MCP arm, row reader)"; exit 2; }
echo "affectedpathcheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; mkdir -p "$R/src" "$R/test"
printf 'int leaf() { return 1; }\nint mid()  { return leaf(); }\n' > "$R/src/core.cpp"
printf 'void test_mid()  { mid();  }\n'                            > "$R/test/test_mid.cpp"
printf 'void test_leaf() { leaf(); }\n'                            > "$R/test/test_leaf.cpp"
printf '2026-11-21  a changelog entry\n'                           > "$R/ChangeLog"   # on disk, never indexed

run(){ perl -e 'alarm 20; exec @ARGV' "$BIN" "$R" "$@" --no-cache 2>/dev/null; }
runec(){ perl -e 'alarm 20; exec @ARGV' "$BIN" "$R" "$@" --no-cache >"$TMP/out.txt" 2>"$TMP/err.txt"; }
body(){ printf '%s' "$1" | perl -pe 's/<!--.*?-->//gs'; }                    # the document minus its legend comment
attr(){ body "$2" | grep -oE "<affected [^>]*" | grep -oE " $1=\"[^\"]*\"" | head -1 | sed 's/.*="//; s/"$//'; }
trows(){ body "$1" | grep -oE '<(test|g) [^>]*>' | LC_ALL=C sort; }   # the test rows, order-free
urows(){ body "$1" | grep -oE '<unused [^>]*/>'; }                    # the unused rows, list order

CLEAN="$( run --affected=src/core.cpp )"

# ── A: the mixed list answers for its usable item ──────────────────────────────────────────────────────
runec --affected=src/core.cpp,ChangeLog,src/obsolete_widget.cpp; MEC=$?
MIX="$( cat "$TMP/out.txt" )"
[ "$MEC" = 0 ] && ok "A --affected=src/core.cpp,ChangeLog,src/obsolete_widget.cpp → exit 0" \
               || no "A mixed list → exit $MEC (want 0): $( head -c 300 "$TMP/err.txt" )"
[ -n "$( trows "$CLEAN" )" ] && [ "$( trows "$MIX" )" = "$( trows "$CLEAN" )" ] \
    && ok "A the mixed answer's test rows ≡ --affected=src/core.cpp's ($( trows "$CLEAN" | wc -l | tr -d ' ' ) rows)" \
    || no "A mixed rows differ from the usable item alone: mixed=[$( trows "$MIX" | tr '\n' ' ' )] clean=[$( trows "$CLEAN" | tr '\n' ' ' )]"
[ "$( attr tests "$MIX" )" = "$( attr tests "$CLEAN" )" ] && [ "$( attr seeds "$MIX" )" = "$( attr seeds "$CLEAN" )" ] \
    && ok "A tests=/seeds= equal the usable item's (tests=$( attr tests "$CLEAN" ) seeds=$( attr seeds "$CLEAN" ))" \
    || no "A tests=/seeds= differ: mixed $( attr tests "$MIX" )/$( attr seeds "$MIX" ) vs $( attr tests "$CLEAN" )/$( attr seeds "$CLEAN" )"

# ── B: every unusable item disclosed, with its reason ──────────────────────────────────────────────────
WANT_U='<unused item="ChangeLog" reason="not_indexed"/>
<unused item="src/obsolete_widget.cpp" reason="not_found"/>'
[ "$( attr unused "$MIX" )" = "2" ] && ok "B root carries unused=\"2\"" || no "B root unused='$( attr unused "$MIX" )' (want 2)"
[ "$( urows "$MIX" )" = "$WANT_U" ] && ok "B one <unused> row per item, list order, reasons not_indexed / not_found" \
                                   || no "B unused rows wrong: [$( urows "$MIX" | tr '\n' ' ' )]"
NEAR="$( run --affected=src/core.cpp,src/cor.cpp )"
printf '%s' "$NEAR" | grep -qF '<unused item="src/cor.cpp" reason="not_found" near="src/core.cpp"/>' \
    && ok "B a misspelled item names its nearest indexed path (near=\"src/core.cpp\")" \
    || no "B no near= on the typo row: [$( urows "$NEAR" )]"
SYM="$( run --affected=src/core.cpp,zzznotasymbol )"
printf '%s' "$SYM" | grep -qF '<unused item="zzznotasymbol" reason="not_found"/>' \
    && ok "B an item that is neither a path nor a symbol is disclosed as not_found" \
    || no "B symbol-shaped bad item not disclosed: [$( urows "$SYM" )]"
QUOTE="$( run --affected='src/core.cpp,a"b<c' )"
printf '%s' "$QUOTE" | grep -qF '<unused item="a&quot;b&lt;c" reason="not_found"/>' \
    && ok "B the echoed item is XML-escaped" || no "B item not escaped: [$( urows "$QUOTE" )]"

# ── C: the legend defines it, exactly when present ─────────────────────────────────────────────────────
printf '%s' "$MIX" | sed 's/-->.*//' | grep -qF 'unused=N' \
    && ok "C the mixed answer's legend defines unused=" || no "C unused= emitted undefined"
printf '%s' "$CLEAN" | sed 's/-->.*//' | grep -qF 'unused=N' \
    && no "C a clean answer pays for the unused= clause" || ok "C a clean answer carries no unused= clause"

# ── D: nothing usable is still a refusal ───────────────────────────────────────────────────────────────
runec --affected=ChangeLog,src/obsolete_widget.cpp; AEC=$?
[ "$AEC" = 1 ] && [ ! -s "$TMP/out.txt" ] && ok "D --affected=ChangeLog,src/obsolete_widget.cpp → exit 1, empty stdout (no tests=\"0\" answer)" \
                                        || no "D all-unusable list → exit $AEC, stdout $( wc -c < "$TMP/out.txt" ) B"
grep -qF "none of the 2 items in the list resolved" "$TMP/err.txt" \
    && ok "D the refusal says plainly that none of the 2 items resolved" \
    || no "D refusal does not say none resolved: $( cat "$TMP/err.txt" )"
runec --affected=zzznotathing; SEC=$?
[ "$SEC" = 1 ] && grep -qF "'zzznotathing' matches no indexed file path (as a path pattern) and no indexed symbol" "$TMP/err.txt" \
    && ! grep -qF "none of the" "$TMP/err.txt" \
    && ok "D a single bad item keeps its existing refusal text, exit 1" \
    || no "D single-item refusal changed: exit $SEC $( cat "$TMP/err.txt" )"

# ── E: a clean list is unchanged ───────────────────────────────────────────────────────────────────────
printf '%s' "$CLEAN" | grep -qE ' unused="|<unused ' && no "E a clean list carries unused=/<unused>" \
                                                     || ok "E a clean list carries no unused= and no <unused> row"

# ── F: the MCP twin ────────────────────────────────────────────────────────────────────────────────────
mcp(){ printf '%s\n%s\n%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"affected","arguments":{"path":"'"$R"'","files":"'"$1"'"}}}' \
    | perl -e 'alarm 30; exec @ARGV' "$BIN" "$R" --mcp --no-cache 2>/dev/null | tail -1; }
mtext(){ python3 -c 'import json,sys
d=json.loads(sys.stdin.read() or "{}")
if "error" in d: print("ERROR "+json.dumps(d["error"])); sys.exit(0)
print("".join(c.get("text","") for c in d.get("result",{}).get("content",[])))'; }
MM="$( mcp 'src/core.cpp,ChangeLog,src/obsolete_widget.cpp' | mtext )"
case "$MM" in ERROR*) no "F MCP affected errored on the mixed list: $( printf '%s' "$MM" | head -c 300 )" ;;
              *) [ "$( urows "$MM" )" = "$WANT_U" ] && [ "$( trows "$MM" )" = "$( trows "$CLEAN" )" ] \
                     && ok "F MCP affected answers the mixed list with the same rows and the same <unused> rows" \
                     || no "F MCP mixed answer differs: unused=[$( urows "$MM" | tr '\n' ' ' )] rows=[$( trows "$MM" | tr '\n' ' ' )]" ;; esac
MA="$( mcp 'ChangeLog,src/obsolete_widget.cpp' | mtext )"
case "$MA" in ERROR*'none of the 2 items in the list resolved'*) ok "F MCP all-unusable list is still an error naming the cause" ;;
              *) no "F MCP all-unusable list: $( printf '%s' "$MA" | head -c 300 )" ;; esac

# ── G: determinism and well-formedness ────────────────────────────────────────────────────────────────
[ "$( run --affected=src/core.cpp,ChangeLog,src/obsolete_widget.cpp )" = "$MIX" ] && ok "G mixed answer byte-identical run to run" \
                                                                       || no "G mixed answer non-deterministic"
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$MIX" | xmllint --noout - 2>/dev/null && ok "G mixed answer is well-formed XML" || no "G mixed answer is not well-formed"
else
    printf '  SKIP  G xml well-formed (no xmllint)\n'
fi

# ── H: multi-root — the reason is read under EVERY root, not the first one alone ──────────────────────
R2="$TMP/repo2"; mkdir -p "$R2"
printf 'int other_root() { return 0; }\n' > "$R2/z.cpp"
printf 'a news entry\n'                  > "$R2/NEWS"
MR="$( perl -e 'alarm 20; exec @ARGV' "$BIN" "$R" "$R2" --affected=src/core.cpp,NEWS,ChangeLog --no-cache 2>/dev/null )"
[ "$( urows "$MR" )" = '<unused item="NEWS" reason="not_indexed"/>
<unused item="ChangeLog" reason="not_indexed"/>' ] \
    && ok "H multi-root: a non-indexed file in the SECOND root reads not_indexed, as in the first" \
    || no "H multi-root reasons wrong: [$( urows "$MR" | tr '\n' ' ' )]"

# ── M: mutation controls — each comparator must reject a wrong document ────────────────────────────────
MUT1="$( printf '%s' "$MIX" | sed 's|<unused item="src/obsolete_widget.cpp" reason="not_found"/>||' )"
[ "$( urows "$MUT1" )" = "$WANT_U" ] && no "M the unused-row comparator accepted a document missing one row" \
                                     || ok "M the unused-row comparator rejects a dropped <unused> row"
MUT2="$( printf '%s' "$MIX" | sed 's|</affected>|<test p="test/test_fake.cpp"/></affected>|' )"
[ "$( trows "$MUT2" )" = "$( trows "$CLEAN" )" ] && no "M the test-row comparator accepted an extra row" \
                                                 || ok "M the test-row comparator rejects an extra <test> row"
MUT3="$( printf '%s' "$MIX" | sed 's| unused="2"||' )"
[ "$( attr unused "$MUT3" )" = "2" ] && no "M the attr reader found unused= in a document without it" \
                                     || ok "M the attr reader rejects a document with unused= removed"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
