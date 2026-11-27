#!/usr/bin/env bash
# querycachereusecheck.sh — QUERY-COMPILE-CACHE: a re-ingest in one process does not recompile a tags.scm query the
# process already holds.
#
# THE COST (MEASURE-M5 §3, Job 3). In mcpframehonestycheck arm K each applied MCP edit took 265–314 ms, and about 60% of
# it was two full ingests (the pre-edit getIndex and the post-edit re-index), each one waiting on launchQueryCompiles
# (src/ingest_prewarm.h) to recompile the cpp tags.scm query with ts_query_new. collectGrammarsToCompile never asked
# compiledQueryCache() (src/ingest_crawl.h), which is process-lifetime and keyed by grammar alone, so every in-process
# re-ingest paid the compile again and installCompiledQueriesAndOpenGate then deleted the copy it displaced.
#
# THE ARMS (counts read off the RIPWIRE_STATS line `ripwire: stats query-reuse ingest=K needed=N held=H compiled=C`, printed by
# every ingest after the process's first: N = distinct grammars the miss set needs, H = of those, the ones whose compiled
# query the process cache already holds, C = the compiles this ingest launched):
#   P1  PREMISE — one stdio session, two replace_symbol_body edits: both answer without an error and both rewrite the file
#       to the expected bytes. A session whose edits failed would make few or no ingests and prove nothing.
#   P2  PREMISE — at least 2 re-ingest lines, and every one of them needs a grammar (N >= 1: the edited file is a miss each
#       time). A re-ingest whose miss set is empty compiles 0 on the base too, so it cannot count toward R1.
#   R1  every re-ingest compiles 0 (C == 0) and finds every needed grammar held (H == N). RED on the base: C == N.
#   I1  IDENTITY (non-NDEBUG): the session's stdout and its stderr outside [mem] and query-reuse lines equal the session run with
#       RIPWIRE_FAULT_QUERY_RECOMPILE=1, which recompiles every needed grammar (the old path). The switch's own premise:
#       that run shows C >= 1 on a re-ingest, or the compare would be vacuous.
#   D   determinism: two fresh sessions answer byte-identically (stdout; only the mtime-bearing index stamp hash is masked).
#
# Not armed here: a tags.scm compile ERROR cannot be provoked from a test (the queries are embedded at configure time).
# By construction a grammar whose compile failed is cached as nullptr, which the reuse test treats as NOT held, so it is
# recompiled and its stderr disclosure repeats on every ingest exactly as before.
#
# Usage:  bash test/querycachereusecheck.sh [BIN]   |   RIPWIRE_BIN=build/ripwire bash test/querycachereusecheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for JSON assertions"; exit 2; }
echo "querycachereusecheck: BIN=$BIN $( "$BIN" --version 2>/dev/null | head -1 )"

TMP="$( mktemp -d )"; trap '[ -n "${QCC_KEEP:-}" ] && echo "kept $TMP" || rm -rf "$TMP"' EXIT

# One session = a fresh one-file corpus, a fresh HOME (so the MCP cache starts empty), and three frames: initialize, then
# two edits. Every session uses the SAME corpus path ($TMP/w, recreated), because the index hash an answer reports covers
# the root; outputs land at $TMP/<tag>.{out,err,rc} and the edited file is copied to $TMP/<tag>.geo.cpp.
session()
{
    local tag="$1"; shift
    local w="$TMP/w"
    rm -rf "$w"; mkdir -p "$w" "$TMP/$tag.home"
    printf 'int alpha( int x )\n{\n    return x + 1;\n}\n\nint beta( int y )\n{\n    return alpha( y ) * 2;\n}\n' > "$w/geo.cpp"
    edit(){ printf '{"jsonrpc":"2.0","id":%s,"method":"tools/call","params":{"name":"replace_symbol_body","arguments":{"path":"%s","symbol":"%s","file":"geo.cpp","new_body":"%s"}}}\n' "$1" "$w" "$2" "$3"; }
    {
        printf '{"jsonrpc":"2.0","id":1,"method":"initialize"}\n'
        edit 2 alpha 'int alpha( int x )\n{\n    return x + 3;\n}'
        edit 3 beta 'int beta( int y )\n{\n    return alpha( y ) * 5;\n}'
    } > "$TMP/$tag.in"
    ( cd "$TMP" && env HOME="$TMP/$tag.home" RIPWIRE_STATS=1 "$@" "$BIN" --mcp < "$TMP/$tag.in" > "$TMP/$tag.out" 2> "$TMP/$tag.err" ); echo $? > "$TMP/$tag.rc"
    cp "$w/geo.cpp" "$TMP/$tag.geo.cpp"
    # the `[index: … hash=XXXXXXXX]` stamp covers the files' stat (mtime), so it differs between two sessions that write the
    # same bytes at different moments; it is the ONLY field masked, and nothing a query compile does can reach it
    sed -E 's/hash=[0-9a-f]{8}\]/hash=<H>]/g' "$TMP/$tag.out" > "$TMP/$tag.norm"
    grep -v -e '^\[mem\] ' -e '^ripwire: stats query-reuse ' "$TMP/$tag.err" > "$TMP/$tag.err.rest" || true
}

# the re-ingest stats lines of a session, one "needed held compiled" triple per line
reuse(){ sed -n 's/^ripwire: stats query-reuse ingest=[0-9]* needed=\([0-9]*\) held=\([0-9]*\) compiled=\([0-9]*\)$/\1 \2 \3/p' "$TMP/$1.err"; }

# both edits answered with a result (no error), in order
edits_ok(){ python3 - "$TMP/$1.out" <<'PY'
import json, sys
seen = {}
for line in open( sys.argv[1], encoding="utf-8", errors="replace" ):
    line = line.strip()
    if not line:
        continue
    r = json.loads( line )
    seen[ r.get( "id" ) ] = r
bad = [ i for i in ( 2, 3 ) if i not in seen or "error" in seen[ i ] or seen[ i ].get( "result", {} ).get( "isError" ) ]
print( "ok" if not bad else "bad ids %s" % bad )
PY
}

EXPECT="$TMP/expect.cpp"
printf 'int alpha( int x )\n{\n    return x + 3;\n}\n\nint beta( int y )\n{\n    return alpha( y ) * 5;\n}\n' > "$EXPECT"

# ── P1: the two edits apply ─────────────────────────────────────────────────────────────────────────────────
session a
verdict="$( edits_ok a 2>&1 )"
if [ "$( cat "$TMP/a.rc" )" = 0 ] && [ "$verdict" = ok ] && cmp -s "$TMP/a.geo.cpp" "$EXPECT"; then
    ok "P1 premise — both edits answered and the file holds the expected bytes"
else
    no "P1 premise — rc=$( cat "$TMP/a.rc" ) edits=$verdict file-match=$( cmp -s "$TMP/a.geo.cpp" "$EXPECT" && echo yes || echo no )"
fi

# ── P2 / R1: every re-ingest reuses the held query ────────────────────────────────────────────────────────
lines="$( reuse a | wc -l | tr -d ' ' )"
needy="$( reuse a | awk '$1 >= 1' | wc -l | tr -d ' ' )"
if [ "$lines" -ge 2 ] && [ "$needy" = "$lines" ]; then
    ok "P2 premise — $lines re-ingests in one process, each needing >= 1 grammar"
else
    no "P2 premise — $lines re-ingest lines, $needy of them needing a grammar (want >= 2, all needing): $( grep '^ripwire: stats query-reuse' "$TMP/a.err" | head -5 )"
fi
recompiled="$( reuse a | awk '$3 != 0 || $2 != $1' | wc -l | tr -d ' ' )"
compiles="$( reuse a | awk '{ s += $3 } END { print s + 0 }' )"
if [ "$lines" -ge 1 ] && [ "$recompiled" = 0 ]; then
    ok "R1 every re-ingest compiled 0 queries and found every needed grammar held ($lines re-ingests)"
else
    no "R1 $recompiled of $lines re-ingests recompiled; $compiles compiles in all after the first ingest (want 0)"
fi

# ── I1: identical answers against the recompile path ──────────────────────────────────────────────────────
session f RIPWIRE_FAULT_QUERY_RECOMPILE=1
fcompiles="$( reuse f | awk '{ s += $3 } END { print s + 0 }' )"
if [ "$( cat "$TMP/f.rc" )" != 0 ]; then
    no "I1 the fault-switch session itself failed (rc=$( cat "$TMP/f.rc" )): it cannot tell an NDEBUG binary from a broken one"
elif [ "$lines" = 0 ]; then
    no "I1 the session printed no query-reuse stats line, so the switch's effect cannot be read (a binary without the counter)"
elif [ "$fcompiles" -ge 1 ]; then
    if cmp -s "$TMP/a.norm" "$TMP/f.norm" && cmp -s "$TMP/a.err.rest" "$TMP/f.err.rest" && cmp -s "$TMP/f.geo.cpp" "$EXPECT"; then
        ok "I1 stdout + stderr (outside [mem] and query-reuse lines) + edited file equal the recompile path ($fcompiles recompiles there)"
    else
        no "I1 the reuse session differs from the recompile path: $( diff "$TMP/a.norm" "$TMP/f.norm" | head -4 ) $( diff "$TMP/a.err.rest" "$TMP/f.err.rest" | head -4 )"
    fi
elif [ "$compiles" -ge 1 ]; then
    no "I1 the default session already recompiles ($compiles), so the switch's run proves nothing — see R1"
else
    printf '  INFO  I1 this binary compiles fault switches out (NDEBUG); the identity arm runs on the plain-flavour leg\n'
fi

# ── D: determinism ─────────────────────────────────────────────────────────────────────────────────────────
session b
if [ -s "$TMP/a.norm" ] && cmp -s "$TMP/a.norm" "$TMP/b.norm"; then
    ok "D two fresh sessions answer byte-identically ($( wc -c < "$TMP/a.norm" | tr -d ' ' ) B)"
else
    no "D two fresh sessions differ: $( diff "$TMP/a.norm" "$TMP/b.norm" | head -4 )"
fi

[ "$fail" = 0 ] && echo "querycachereusecheck: ALL PASS" || echo "querycachereusecheck: FAIL"
exit "$fail"
