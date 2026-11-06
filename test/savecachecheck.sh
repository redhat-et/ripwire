#!/usr/bin/env bash
# savecachecheck.sh — A3-F9: saveCache must never destroy a GOOD cache on a failed write.
#
# Bug ( A3-F9, src/ingest.cpp saveCache): fwrite/fclose results were never
# checked. On a short write (e.g. ENOSPC) the truncated temp file still got rename()'d over the
# previous good cache — silently destroying it. The checksum trailer self-heals on next load (full
# reparse), so this was perf-only, but a good cache should never be clobbered with zero alert, unlike
# every neighboring degrade path in ingest.cpp (all of which fire DISCLOSE).
#
# This gate simulates a write failure the portable way: after populating a good cache, we make the
# CACHE FILE ITSELF read-only (chmod 0444) and its parent directory read-only too (chmod 0555) so a
# subsequent saveCache() cannot open/rename a replacement — fopen(tmp, "wb") or rename() must fail.
# We assert:
#   1. the pre-existing cache file survives BYTE-IDENTICAL (never clobbered by a torn write)
#   2. the run still completes and produces correct/well-formed output (degrades gracefully, doesn't crash)
#   3. after restoring write permission, a normal rerun still succeeds and the cache updates
#
# Usage:
#   bash test/savecachecheck.sh
#   RIPWIRE_BIN=build_a1/ripwire bash test/savecachecheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check; prints ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

echo "savecachecheck: BIN=$BIN  TMP=$TMP"

WORK="$TMP/proj"
mkdir -p "$WORK"
CACHEDIR="$TMP/cachedir"
mkdir -p "$CACHEDIR"
CACHE="$CACHEDIR/c.bin"

# ── step 1: populate a good, warm cache normally ──────────────────────────────────────────────────
printf 'int firstSymbol( void )\n{\n    return 1;\n}\n' > "$WORK/f.cpp"
"$BIN" "$WORK" --cache="$CACHE" --no-stable >"$TMP/cold.xml" 2>"$TMP/cold.err"
rc_cold=$?
if [ "$rc_cold" -eq 0 ] && [ -s "$CACHE" ]; then
    ok "cold run populates a non-empty cache file"
else
    no "cold run expected exit 0 + non-empty cache, got rc=$rc_cold size=$( wc -c < "$CACHE" 2>/dev/null || echo missing )"
    cat "$TMP/cold.err"
fi

if grep -q 'n="firstSymbol"' "$TMP/cold.xml" 2>/dev/null; then
    ok "cold run: firstSymbol present (fixture sanity)"
else
    no "cold run: firstSymbol missing — fixture did not parse as expected"
fi

# ── step 2: snapshot the good cache bytes, then EDIT the source so a rerun would try to rewrite it ─
cp "$CACHE" "$TMP/c.bin.good"
good_sum=$( shasum -a 256 "$TMP/c.bin.good" 2>/dev/null | awk '{print $1}' )
[ -n "$good_sum" ] || good_sum=$( sha256sum "$TMP/c.bin.good" 2>/dev/null | awk '{print $1}' )

printf 'int secondSymbol( void )\n{\n    return 2;\n}\n' >> "$WORK/f.cpp"

# ── step 3: lock the cache file AND its parent dir read-only — simulates a write failure (ENOSPC-like:
#    the temp can't be created/renamed into place), the portable no-root-required way ────────────────
chmod 0444 "$CACHE"
chmod 0555 "$CACHEDIR"

"$BIN" "$WORK" --cache="$CACHE" --no-stable >"$TMP/degraded.xml" 2>"$TMP/degraded.err"
rc_degraded=$?

# restore perms immediately so cleanup/further steps aren't blocked
chmod 0755 "$CACHEDIR"
chmod 0644 "$CACHE" 2>/dev/null

# ── check 1: the run must not crash — it degrades (still produces output for this invocation) ──────
if [ "$rc_degraded" -eq 0 ]; then
    ok "run against a read-only cache dir still exits 0 (degrades, doesn't crash)"
else
    no "run against a read-only cache dir expected exit 0, got $rc_degraded"
    cat "$TMP/degraded.err"
fi

# this invocation's OWN output should still reflect the current source (ingest doesn't depend on
# a successful cache write to produce a correct map for the current run)
if grep -q 'n="secondSymbol"' "$TMP/degraded.xml" 2>/dev/null; then
    ok "degraded run: secondSymbol present in this run's own output"
else
    no "degraded run: secondSymbol missing from this run's own output"
fi

# ── check 2: the OLD cache file on disk must be BYTE-IDENTICAL to the pre-failure snapshot ──────────
# (the bug: a truncated temp gets rename()'d over the good cache, destroying it even though the
#  checksum self-heals on next load — this must no longer happen: the old bytes must survive untouched)
new_sum=$( shasum -a 256 "$CACHE" 2>/dev/null | awk '{print $1}' )
[ -n "$new_sum" ] || new_sum=$( sha256sum "$CACHE" 2>/dev/null | awk '{print $1}' )
if [ "$good_sum" = "$new_sum" ] && [ -n "$good_sum" ]; then
    ok "old cache file survives byte-identical after a failed write (not clobbered)"
else
    no "old cache file was MODIFIED/destroyed by a failed write (good=$good_sum new=$new_sum) — REGRESSION"
fi

# no leftover per-pid temp files should remain in the cache dir
leftover=$( find "$CACHEDIR" -name '*.tmp' 2>/dev/null | wc -l | tr -d ' ' )
if [ "$leftover" = "0" ]; then
    ok "no leftover .tmp file after the failed write"
else
    no "leftover .tmp file(s) left behind after the failed write ($leftover found)"
fi

# ── step 4: restore write access — a normal rerun must still succeed and update the cache ───────────
chmod 0755 "$CACHEDIR"
chmod 0644 "$CACHE"

"$BIN" "$WORK" --cache="$CACHE" --no-stable >"$TMP/warm.xml" 2>"$TMP/warm.err"
rc_warm=$?
if [ "$rc_warm" -eq 0 ]; then
    ok "rerun after restoring write access exits 0"
else
    no "rerun after restoring write access expected exit 0, got $rc_warm"
    cat "$TMP/warm.err"
fi

if grep -q 'n="secondSymbol"' "$TMP/warm.xml" 2>/dev/null; then
    ok "post-restore rerun: secondSymbol present"
else
    no "post-restore rerun: secondSymbol missing"
fi

post_sum=$( shasum -a 256 "$CACHE" 2>/dev/null | awk '{print $1}' )
[ -n "$post_sum" ] || post_sum=$( sha256sum "$CACHE" 2>/dev/null | awk '{print $1}' )
if [ "$post_sum" != "$good_sum" ]; then
    ok "cache file updates again once write access is restored"
else
    no "cache file did not update after write access was restored"
fi

# ── well-formed XML on both the degraded and the recovered run ─────────────────────────────────────
command -v xmllint >/dev/null 2>&1 \
    && { xmllint --noout "$TMP/degraded.xml" 2>/dev/null \
         && ok "degraded run: xml well-formed" || no "degraded run: xml malformed"; } \
    || ok "degraded run: xml well-formed (xmllint absent — skipped)"

command -v xmllint >/dev/null 2>&1 \
    && { xmllint --noout "$TMP/warm.xml" 2>/dev/null \
         && ok "post-restore run: xml well-formed" || no "post-restore run: xml malformed"; } \
    || ok "post-restore run: xml well-formed (xmllint absent — skipped)"

# ── WARM-REWRITE: a refused file must not make every warm run rewrite the blob ─────────────────────
# A nest-refused file yields no facts and is written UNKNOWN (forgetNestRefusalsForCache), so every warm run
# re-reads and re-refuses it. Before the fix that re-read also set the pool's dirty flag, and the WHOLE blob was
# re-serialized on every warm run (envoy: a 146 MB write per warm run, for one deep_recursion.json).
# A rewrite is visible in the blob bytes: the header carries the write's wall-clock stamp, so any saveCache
# changes the checksum. Arms: (w1) a warm run over an unchanged tree with a refused file leaves the blob
# byte-identical, and still notes and rows the refusal; (w2) the positive twin, an edited source rewrites it;
# (w3) accepted -> refused rewrites it and rows the file; (w4) refused -> accepted rewrites it and indexes the key;
# (w5) after (w4) the next warm run writes nothing again.
WR="$TMP/wr"; mkdir -p "$WR"
WRC="$TMP/wr.cache"
blobsum(){ { shasum -a 256 "$WRC" 2>/dev/null || sha256sum "$WRC" 2>/dev/null; } | awk '{print $1}'; }
deepjson(){ python3 -c "import sys; open(sys.argv[1],'w').write('['*600 + ']'*600)" "$1"; }
wrrun(){ "$BIN" "$WR" --cache="$WRC" --no-stable "$@" >"$TMP/wr.out" 2>"$TMP/wr.err"; }
printf 'int wrKeep( void )\n{\n    return 1;\n}\n' > "$WR/k.cpp"
printf '{"wrshallowkey": [1]}\n' > "$WR/flip.json"
deepjson "$WR/deep.json"
if ! command -v python3 >/dev/null 2>&1; then
    printf '  SKIP  (w1-w5) python3 absent: no deep JSON fixture\n'
elif ! { wrrun; rc_w00=$?; [ "$rc_w00" -eq 0 ] && [ -s "$WRC" ]; }; then
    no "(w0) cold run over the refused-file fixture: expected rc=0 and a cache, got rc=$rc_w00 size=$( wc -c < "$WRC" 2>/dev/null || echo missing )"
else
    wrrun; rc_w0=$?                                    # first warm run: settles any one-time convergence
    s0=$( blobsum )
    wrrun; rc_w1=$?
    s1=$( blobsum )
    if [ "$rc_w0" -eq 0 ] && [ "$rc_w1" -eq 0 ] && [ -n "$s0" ] && [ "$s0" = "$s1" ] && grep -q 'deep.json: json nesting' "$TMP/wr.err"; then
        ok "(w1) warm run over an unchanged tree with a refused file writes nothing (blob byte-identical) and still notes the refusal"
    else
        no "(w1) WARM-REWRITE: warm run rc=$rc_w0/$rc_w1, blob $s0 -> $s1, refusal note: $( grep -c 'deep.json: json nesting' "$TMP/wr.err" )"
    fi
    wrrun --skipped; rc_sk=$?
    if [ "$rc_sk" -eq 0 ] && grep -qE '<f p="[^"]*deep\.json" why="nest-refused"' "$TMP/wr.out" && [ "$( blobsum )" = "$s1" ]; then
        ok "(w1) the warm --skipped run still rows deep.json as nest-refused, and writes nothing"
    else
        no "(w1) warm --skipped: rc=$rc_sk, row: $( grep -c 'deep\.json" why="nest-refused"' "$TMP/wr.out" ), blob moved: $( [ "$( blobsum )" = "$s1" ] && echo no || echo yes )"
    fi
    printf 'int wrKeep( void )\n{\n    return 2;\n}\nint wrAdded( void )\n{\n    return 3;\n}\n' > "$WR/k.cpp"
    wrrun; rc_w2=$?
    s2=$( blobsum )
    if [ "$rc_w2" -eq 0 ] && [ "$s2" != "$s1" ] && grep -q 'n="wrAdded"' "$TMP/wr.out"; then
        ok "(w2) positive twin: an edited source still rewrites the blob"
    else
        no "(w2) an edited source did not rewrite the blob (rc=$rc_w2, $s1 -> $s2) — the (w1) arm cannot see a rewrite"
    fi
    deepjson "$WR/flip.json"
    wrrun --skipped; rc_w3=$?
    s3=$( blobsum )
    if [ "$rc_w3" -eq 0 ] && [ "$s3" != "$s2" ] && grep -qE '<f p="[^"]*flip\.json" why="nest-refused"' "$TMP/wr.out"; then
        ok "(w3) accepted -> refused rewrites the blob and rows flip.json as nest-refused"
    else
        no "(w3) accepted -> refused: rc=$rc_w3, blob $s2 -> $s3, row: $( grep -c 'flip\.json" why="nest-refused"' "$TMP/wr.out" )"
    fi
    wrrun --skipped; rc_w3b=$?
    if [ "$rc_w3b" -eq 0 ] && [ "$( blobsum )" = "$s3" ] && grep -qE '<f p="[^"]*flip\.json" why="nest-refused"' "$TMP/wr.out"; then
        ok "(w3) the warm run after it writes nothing and still rows flip.json"
    else
        no "(w3) warm after accepted -> refused: rc=$rc_w3b, blob moved: $( [ "$( blobsum )" = "$s3" ] && echo no || echo yes ), row: $( grep -c 'flip\.json" why="nest-refused"' "$TMP/wr.out" )"
    fi
    printf '{"wrbackkey": [1]}\n' > "$WR/flip.json"
    wrrun; rc_w4=$?
    s4=$( blobsum )
    if [ "$rc_w4" -eq 0 ] && [ "$s4" != "$s3" ] && grep -q 'wrbackkey' "$TMP/wr.out"; then
        ok "(w4) refused -> accepted rewrites the blob and indexes the file's key"
    else
        no "(w4) refused -> accepted: rc=$rc_w4, blob $s3 -> $s4, key indexed: $( grep -c 'wrbackkey' "$TMP/wr.out" )"
    fi
    wrrun; rc_w5=$?
    if [ "$rc_w5" -eq 0 ] && [ "$( blobsum )" = "$s4" ] && grep -q 'wrbackkey' "$TMP/wr.out"; then
        ok "(w5) the warm run after (w4) writes nothing and serves the key from the cache"
    else
        no "(w5) warm after refused -> accepted: rc=$rc_w5, blob moved: $( [ "$( blobsum )" = "$s4" ] && echo no || echo yes )"
    fi
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
