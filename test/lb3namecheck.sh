#!/bin/bash
# lb3namecheck — LB-3 name-field recovery: (a) query-side stem variants reach a class-name subtoken
# ("splits" finds SplitChunksPlugin when NO other query token touches it), (b) the basename-only
# BM25 field reaches a file-level concept ("cache store" finds cachestore.js whose symbols never
# say cache), (c) scan-vs-persisted-stats postings parity holds with both levers armed.
#
# Fixture discipline (first version of this gate was refuted by its own controls): the lever token
# is the ONLY carrier that can reach the target — every other query token is planted in NOISE
# symbols so an un-levered target scores 0 and ranks below them. Each positive arm has a negative
# control (lever off ⇒ target absent from top-3) proving the lever, not ambient rank, did the work.
# Red-first: at a418b5a both positive arms FAIL because the levers do not exist yet.
set -u
BIN="${1:-${RIPWIRE_BIN:-./build/ripwire}}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/lb3name.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
FAIL=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1"; FAIL=1; }

REPO="$TMP/corpus"
mkdir -p "$REPO/lib" "$REPO/store"

# target A — concept only in the CLASS NAME, and only via the stem: query says "splits", name
# subtoken is "split". No doc comment; body words never appear in query A.
cat > "$REPO/lib/SplitChunksPlugin.js" <<'EOF'
class SplitChunksPlugin
{
    apply( compiler ) { return compiler.hook( this.options ); }
    prepare( graph ) { return graph.walk(); }
}
module.exports = SplitChunksPlugin;
EOF
# target B — concept only in the BASENAME; symbols/bodies carry no query-B token (separator in the basename: a single lowercase run would defeat the subtokenizer by design).
cat > "$REPO/store/cache_store.js" <<'EOF'
function put( key, value ) { table[key] = value; }
function take( key ) { return table[key]; }
module.exports = { put, take };
EOF
# noise — carries every NON-lever token of both queries (modules, cleanly, results, kept) so an
# un-levered target scores 0 and sits beneath these.
cat > "$REPO/lib/modules.js" <<'EOF'
// modules helpers: keep results kept cleanly for modules
function listModules( modules ) { return modules.filter( m => m.live ); }
function cleanlyKept( results ) { return results.kept; }
function keptResults( results ) { return results; }
module.exports = { listModules, cleanlyKept, keptResults };
EOF
cat > "$REPO/lib/results.js" <<'EOF'
// results kept cleanly across modules
function resultsOf( modules ) { return modules.map( m => m.result ); }
function keepResults( results ) { return results.slice(); }
module.exports = { resultsOf, keepResults };
EOF

run(){ env -u TMPDIR XDG_CACHE_HOME="$TMP/xdg" "$@"; }
mkdir -p "$TMP/xdg"
top3(){ tr '<' '\n' < "$1" | grep -E '^cand r="[123]" ' | grep -c "$2"; }

# ── (a) stem variants: the plural is the ONLY route to the class name ───────────────────────────
Q_A="splits modules cleanly"
run env RIPWIRE_QSTEM=1 "$BIN" "$REPO" --for="$Q_A" --format=candidates > "$TMP/a_on.xml" 2>/dev/null
run env RIPWIRE_QSTEM=0 "$BIN" "$REPO" --for="$Q_A" --format=candidates > "$TMP/a_off.xml" 2>/dev/null
[ "$(top3 "$TMP/a_on.xml" SplitChunksPlugin)" -ge 1 ] \
    && ok "(a) QSTEM=1: 'splits' stem-reaches SplitChunksPlugin into candidates top-3" \
    || no "(a) QSTEM=1: SplitChunksPlugin not in top-3 for '$Q_A'"
[ "$(top3 "$TMP/a_off.xml" SplitChunksPlugin)" -eq 0 ] \
    && ok "(a-ctl) QSTEM=0: target absent from top-3 (lever, not ambient rank, does the work)" \
    || no "(a-ctl) QSTEM=0: target already top-3 — fixture no longer proves the lever"

# ── (b) basename field: the basename is the ONLY route to the file ──────────────────────────────
Q_B="where are results kept in the cache store"
run env RIPWIRE_BASENAME_W=3 "$BIN" "$REPO" --for="$Q_B" --format=candidates > "$TMP/b_on.xml" 2>/dev/null
run env RIPWIRE_BASENAME_W=0 "$BIN" "$REPO" --for="$Q_B" --format=candidates > "$TMP/b_off.xml" 2>/dev/null
[ "$(top3 "$TMP/b_on.xml" cache_store)" -ge 1 ] \
    && ok "(b) BASENAME_W=3: basename-only concept surfaces top-3" \
    || no "(b) BASENAME_W=3: cache_store.js absent from top-3 for '$Q_B'"
[ "$(top3 "$TMP/b_off.xml" cache_store)" -eq 0 ] \
    && ok "(b-ctl) BASENAME_W=0: control stays absent (lever did the work)" \
    || no "(b-ctl) control already surfaces cache_store.js — fixture no longer proves the lever"

# ── (c) postings parity with both levers armed: cached (persisted-stats) vs --no-cache (scan) ───
run env RIPWIRE_QSTEM=1 RIPWIRE_BASENAME_W=3 "$BIN" "$REPO" --for="$Q_A" > "$TMP/c_warm.xml" 2>/dev/null
run env RIPWIRE_QSTEM=1 RIPWIRE_BASENAME_W=3 "$BIN" "$REPO" --for="$Q_A" --no-cache > "$TMP/c_scan.xml" 2>/dev/null
cmp -s "$TMP/c_warm.xml" "$TMP/c_scan.xml" \
    && ok "(c) parity: scan and persisted-stats branches byte-identical with levers armed" \
    || no "(c) parity: branches diverge with levers armed"

[ "$FAIL" -eq 0 ] && echo "lb3namecheck: ALL PASS" || echo "lb3namecheck: FAILURES"
exit "$FAIL"
