#!/usr/bin/env bash
# qsnapprefetchcheck.sh — the Phase-M gate for the qsnap PREFETCH file-cache warmer.
#
# WHAT PHASE M IS: a FILE-CACHE WARMER in the long-lived --mcp server, NOT an index mechanism. When a request
# observes git HEAD has MOVED since the last observation (a commit just landed), a DETACHED background thread
# runs the SAME quality::computeHeadSnapshot a lazy quality_delta would, writing the sha-keyed qsnap cache FILE
# so the NEXT quality_delta finds it warm. It is gated on a cheap file-count heuristic (default 500, §8 GO-at-
# scale) so small repos never pay a useless background burn; RIPWIRE_QSNAP_PREFETCH_MIN_FILES lowers it so this
# tiny fixture can exercise the mechanism (documented test surface).
#
# THE GATES (all must be green):
#   (a) atomic publish / torn-read fix — the qsnap write is tmp-file + rename(), so a reader NEVER observes a
#       half-written blob. Asserted structurally: the final blob is checksum-valid, no *.tmp.* residue remains,
#       and a concurrent sampler across repeated rewrites never catches a non-empty-but-invalid file.
#   (b) NON-VACUITY — in a fixture git repo above the (lowered) threshold, commit through the server's staleness
#       window, then poll that the qsnap for the NEW sha appears WITHOUT any quality_delta call (proving the
#       prefetch actually fired), then quality_delta and assert it took the WARM path (the qsnap file is served
#       un-rewritten: same inode/mtime — a cold miss would rename a fresh blob into place).
#   (c) DETERMINISM — quality_delta's response body is BYTE-IDENTICAL prefetch-fired vs prefetch-suppressed.
#   (d) SINGLE-FLIGHT — two rapid HEAD moves: no crash, and at most ONE concurrent worker (observed via the
#       RIPWIRE_MCP_TIMINGS "prefetch spawn"/"prefetch done" stderr lines — the live count never exceeds 1).
#   (e) TSan — run this whole script with a ThreadSanitizer binary (see below); every scenario asserts the
#       server stderr carries NO "ThreadSanitizer" warning (trivially true on a normal build; a real check on a
#       TSan build). Build + run:
#         cmake -S . -B tsan -DRIPWIRE_TSAN=ON && cmake --build tsan -j
#         RIPWIRE_BIN=tsan/ripwire test/qsnapprefetchcheck.sh
#
# MONOTONE FRESHNESS is by construction (stated, not timing-tested): computeHeadSnapshot re-reads gitHeadSha at
# run time and keys the qsnap by THAT sha, so a prefetched blob is byte-identical to what lazy would compute for
# the same sha and can never be served for a newer HEAD — the filename key IS the sha.
#
# Usage:
#   test/qsnapprefetchcheck.sh
#   RIPWIRE_BIN=build_p5w9/ripwire test/qsnapprefetchcheck.sh
#   RIPWIRE_BIN=tsan/ripwire       test/qsnapprefetchcheck.sh   # the (e) TSan half
#
# Exits non-zero on any failure. NEVER edits test/fixture — every mutation is on a scratch mktemp COPY.
# Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/fixture"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
command -v git     >/dev/null 2>&1 || { echo "git required"; exit 2; }

echo "qsnapprefetchcheck: BIN=$BIN"

# ── a checksum-validator for a qsnap blob: magic "QSNP" + fnv1a64 trailer over the body (native LE) ──
validate_qsnap() {
    python3 - "$1" <<'PY'
import sys, struct
try:
    b = open(sys.argv[1], "rb").read()
except OSError:
    print("ABSENT"); sys.exit(0)
if len(b) == 0:
    print("EMPTY"); sys.exit(0)
if len(b) < 4 + 4 + 8 + 8 or b[:4] != b"QSNP":
    print("INVALID"); sys.exit(0)
body = b[:-8]
trailer = struct.unpack("<Q", b[-8:])[0]
h = 14695981039346656037
for x in body:
    h = ((h ^ x) * 1099511628211) & 0xFFFFFFFFFFFFFFFF
print("VALID" if h == trailer else "INVALID")
PY
}

# ── build a scratch git repo COPY of the fixture; a private cache dir via TMPDIR (cacheDirLadder honors it) ──
new_repo() {   # echoes "WORK CACHE"
    local w c
    w="$( mktemp -d "$TMP/work.XXXXXX" )"
    c="$( mktemp -d "$TMP/cache.XXXXXX" )"
    cp -R "$FIX/"* "$w/"
    git -C "$w" init -q
    git -C "$w" config user.email "pf@x.com"
    git -C "$w" config user.name  "PF"
    git -C "$w" add -A
    git -C "$w" commit -q -m init
    echo "$w $c"
}

# ── inner text (tools/call result) for a JSON-RPC id from a server out file ──
inner_for_id() {
    grep "\"id\":$2" "$1" | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
if "error" in r: print("__ERROR__:" + r["error"].get("message",""))
else: print(r["result"]["content"][0]["text"])
'
}
wait_for_id() { local i; for i in $( seq 1 200 ); do grep -q "\"id\":$2" "$1" 2>/dev/null && return 0; sleep 0.05; done; return 1; }
# The private cache root adds ripwire/ below TMPDIR, then the blob family adds its 2-hex shard.
blob_paths() { find "$1" -maxdepth 3 -type f -name "$2" 2>/dev/null; }
blob_first() { blob_paths "$1" "$2" | head -1; }
qsnap_count() { blob_paths "$1" 'ripwire-qsnap-*.bin' | grep -c . ; }
# L3 (Linux probe): portable stat reader(s). GNU coreutils and BSD/macOS disagree on both the flag and the
# format directives, and the `stat -f FMT ... || stat -c FMT ...` fallback this gate used is a TRAP. On GNU,
# `-f` means FILESYSTEM status and takes NO format argument, so FMT is parsed as a second FILE: measured on
# coreutils 9.11, `stat -f %i FILE` PRINTS a six-line filesystem block for FILE on stdout and exits 1. The
# `||` arm then appends the right number under six lines of junk -- so a string compare fails, a numeric
# compare dies with "integer expression expected", and a `|| echo MISSING` variant reports MISSING forever
# (a gate that then passes by comparing nothing to nothing). Detect the flavour ONCE, use one form.
if stat --version >/dev/null 2>&1; then inode_mtime(){ stat -c '%i %Y' "$1" 2>/dev/null || echo "MISSING"; }   # GNU coreutils
else                                    inode_mtime(){ stat -f '%i %m' "$1" 2>/dev/null || echo "MISSING"; }   # BSD / macOS
fi
assert_no_tsan() { grep -q "ThreadSanitizer" "$1" 2>/dev/null && no "TSan WARNING in server stderr ($2)" || ok "no ThreadSanitizer warning in server stderr ($2)"; }

# ═══════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (a) atomic publish: no torn read — tmp+rename, checksum-valid, no residue ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════
read A_W A_C <<<"$( new_repo )"
# a background sampler: while quality_delta rewrites the qsnap repeatedly, the file must ALWAYS be ABSENT or
# checksum-VALID — never a non-empty partial one (the torn-read the direct-ofstream write allowed).
SAMPLE_BAD=0
( for i in $( seq 1 400 ); do
    f="$( blob_first "$A_C" 'ripwire-qsnap-*.bin' )"
    [ -n "$f" ] && { v="$( validate_qsnap "$f" )"; [ "$v" = "INVALID" ] && echo bad >>"$A_W/sampler.flag"; }
  done ) &
SAMPLER=$!
for i in $( seq 1 12 ); do
    rm -f $( blob_paths "$A_C" 'ripwire-qsnap-*.bin' )
    TMPDIR="$A_C/" "$BIN" "$A_W" --quality-delta >/dev/null 2>>"$A_W/err.txt"
done
wait $SAMPLER 2>/dev/null
[ -s "$A_W/sampler.flag" ] && no "(a) sampler caught a non-empty INVALID qsnap (torn read)" \
                           || ok "(a) qsnap never observed half-written across 12 rewrites (atomic rename)"
FINAL="$( blob_first "$A_C" 'ripwire-qsnap-*.bin' )"
[ -n "$FINAL" ] && [ "$( validate_qsnap "$FINAL" )" = "VALID" ] && ok "(a) final qsnap blob is checksum-valid" \
                                                               || no "(a) final qsnap blob missing/invalid"
# Y4: shard-aware lookup — the atomic-rename tmp file can land in either layout too.
[ -n "$( find "$A_C" -maxdepth 3 -type f -name '*.tmp.*' 2>/dev/null )" ] \
    && no "(a) stale *.tmp.* residue left behind (rename did not consume it)" \
    || ok "(a) no *.tmp.* residue after writes (rename consumed the tmp)"
assert_no_tsan "$A_W/err.txt" "a"

# ═══════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (b) NON-VACUITY: commit → prefetch fires (qsnap appears with NO quality_delta) → warm delta ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════
read B_W B_C <<<"$( new_repo )"
FIFO="$B_W/in.fifo"; mkfifo "$FIFO"
TMPDIR="$B_C/" RIPWIRE_QSNAP_PREFETCH_MIN_FILES=1 RIPWIRE_MCP_TIMINGS=1 \
    "$BIN" --mcp <"$FIFO" >"$B_W/out.txt" 2>"$B_W/err.txt" &
SRV=$!; exec 9>"$FIFO"
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' >&9
printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$B_W\",\"symbol\":\"perimeter\"}}}" >&9
wait_for_id "$B_W/out.txt" 2 || no "(b) server never answered the warm-up read (id=2)"
[ "$( qsnap_count "$B_C" )" -eq 0 ] && ok "(b) no qsnap before any commit (clean warm-up)" \
                                    || no "(b) unexpected qsnap present before commit"

# commit through the staleness window: edit a tracked file (bumps mtime → next request rebuilds) then commit.
printf '\n// prefetch-trigger edit\n' >> "$B_W/geometry.cpp"
git -C "$B_W" commit -q -am "edit that moves HEAD"
# a plain READ verb — its getIndex observes HEAD moved and kicks the prefetch. NO quality_delta is sent.
printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$B_W\",\"symbol\":\"perimeter\"}}}" >&9
wait_for_id "$B_W/out.txt" 3 || no "(b) server never answered the post-commit read (id=3)"

APPEARED=0
for i in $( seq 1 120 ); do [ "$( qsnap_count "$B_C" )" -ge 1 ] && { APPEARED=1; break; }; sleep 0.05; done
[ "$APPEARED" -eq 1 ] && ok "(b) qsnap for the NEW sha appeared WITHOUT any quality_delta (prefetch fired — non-vacuous)" \
                      || no "(b) qsnap never appeared after the commit — prefetch did NOT fire"
grep -q "ripwire-prefetch spawn" "$B_W/err.txt" && ok "(b) server logged a prefetch spawn" \
                                                || no "(b) no prefetch spawn logged"
# wait for the worker to finish writing, then snapshot the file identity.
for i in $( seq 1 60 ); do grep -q "ripwire-prefetch done" "$B_W/err.txt" && break; sleep 0.05; done
PF="$( blob_first "$B_C" 'ripwire-qsnap-*.bin' )"
ID_BEFORE="$( inode_mtime "$PF" )"

# now quality_delta over MCP — it must take the WARM path (qsnap HIT → file served un-rewritten, same inode).
printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"quality_delta\",\"arguments\":{\"path\":\"$B_W\"}}}" >&9
wait_for_id "$B_W/out.txt" 4 || no "(b) server never answered quality_delta (id=4)"
QD="$( inner_for_id "$B_W/out.txt" 4 )"
ID_AFTER="$( inode_mtime "$PF" )"
case "$QD" in
  *baseline*) ok "(b) quality_delta returned a well-formed result ($( echo "$QD" | head -c 60 )…)";;
  *) no "(b) quality_delta did not return a baseline result: $( echo "$QD" | head -c 120 )";;
esac
[ "$ID_BEFORE" = "$ID_AFTER" ] && [ "$ID_BEFORE" != "MISSING" ] \
    && ok "(b) quality_delta served the prewarmed qsnap un-rewritten (WARM path: inode/mtime unchanged)" \
    || no "(b) qsnap was rewritten by quality_delta (COLD path — prefetch did not warm it): '$ID_BEFORE' -> '$ID_AFTER'"

# measured warm-vs-cold delta on THIS corpus (report-only; the win is corpus-dependent, §8).
WARM_MS="$( grep 'verb=quality_delta' "$B_W/err.txt" | tail -1 | sed -E 's/.*wall_ms=([0-9.]+).*/\1/' )"
rm -f $( blob_paths "$B_C" 'ripwire-qsnap-*.bin' )        # force a COLD control (Y4: shard-aware)
printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"quality_delta\",\"arguments\":{\"path\":\"$B_W\"}}}" >&9
wait_for_id "$B_W/out.txt" 5
COLD_MS="$( grep 'verb=quality_delta' "$B_W/err.txt" | tail -1 | sed -E 's/.*wall_ms=([0-9.]+).*/\1/' )"
echo "  INFO  measured quality_delta wall: warm(qsnap hit)=${WARM_MS:-?}ms  cold(qsnap miss)=${COLD_MS:-?}ms  (this fixture is below GO-at-scale; the win grows with repo size — §8)"
assert_no_tsan "$B_W/err.txt" "b"
exec 9>&-; kill $SRV 2>/dev/null; wait $SRV 2>/dev/null

# ═══════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (c) DETERMINISM: quality_delta byte-identical prefetch-FIRED vs prefetch-SUPPRESSED ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════
run_qd_scenario() {   # $1 = min-files threshold (1 => fires, huge => suppressed); echoes the quality_delta result text
    local w c thr="$1"
    read w c <<<"$( new_repo )"
    local fifo="$w/in.fifo"; mkfifo "$fifo"
    TMPDIR="$c/" RIPWIRE_QSNAP_PREFETCH_MIN_FILES="$thr" RIPWIRE_MCP_TIMINGS=1 \
        "$BIN" --mcp <"$fifo" >"$w/out.txt" 2>"$w/err.txt" &
    local srv=$!; exec 8>"$fifo"
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' >&8
    printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$w\",\"symbol\":\"perimeter\"}}}" >&8
    wait_for_id "$w/out.txt" 2
    printf '\n// c-scenario edit\n' >> "$w/geometry.cpp"
    git -C "$w" commit -q -am "commit"
    printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$w\",\"symbol\":\"perimeter\"}}}" >&8
    wait_for_id "$w/out.txt" 3
    # give a prefetch (if enabled) time to land so the fired-case genuinely reads the warm blob.
    sleep 0.6
    printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"quality_delta\",\"arguments\":{\"path\":\"$w\"}}}" >&8
    wait_for_id "$w/out.txt" 4
    exec 8>&-; kill $srv 2>/dev/null; wait $srv 2>/dev/null
    assert_no_tsan "$w/err.txt" "c/thr=$thr" >&2
    inner_for_id "$w/out.txt" 4
}
QD_FIRED="$( run_qd_scenario 1 )"
QD_SUPPR="$( run_qd_scenario 999999 )"
# §B6 M5 (2026-07-29): quality_delta now carries the honest `at` (baseline sha) key on the MCP arm, the
# same key the CLI has. The two scenarios build SEPARATE sandboxes, so their HEAD shas differ by
# construction — the determinism this arm proves is "same findings across prefetch on/off", and the sha
# is a truthful input difference, not a prefetch effect. Compare with the at VALUE normalized; everything
# else must still be byte-identical.
QD_FIRED="$( printf '%s' "$QD_FIRED" | sed -E 's/"at":"[0-9a-f+dirty]*"/"at":"NORM"/' )"
QD_SUPPR="$( printf '%s' "$QD_SUPPR" | sed -E 's/"at":"[0-9a-f+dirty]*"/"at":"NORM"/' )"
if [ "$QD_FIRED" = "$QD_SUPPR" ] && [ -n "$QD_FIRED" ]; then
    ok "(c) quality_delta byte-identical fired-vs-suppressed: $( echo "$QD_FIRED" | head -c 70 )…"
else
    no "(c) quality_delta DIVERGED across prefetch on/off"
    printf '        fired: %s\n' "$( echo "$QD_FIRED" | head -c 160 )"
    printf '        suppr: %s\n' "$( echo "$QD_SUPPR" | head -c 160 )"
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (d) SINGLE-FLIGHT: two rapid HEAD moves → no crash, at most one concurrent worker ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════
read D_W D_C <<<"$( new_repo )"
FIFO="$D_W/in.fifo"; mkfifo "$FIFO"
TMPDIR="$D_C/" RIPWIRE_QSNAP_PREFETCH_MIN_FILES=1 RIPWIRE_MCP_TIMINGS=1 \
    "$BIN" --mcp <"$FIFO" >"$D_W/out.txt" 2>"$D_W/err.txt" &
SRV=$!; exec 9>"$FIFO"
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' >&9
printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$D_W\",\"symbol\":\"perimeter\"}}}" >&9
wait_for_id "$D_W/out.txt" 2
# two commits back-to-back, each followed immediately by a read verb → two HEAD-move observations in quick
# succession. Single-flight must drop the second while a worker runs (or serialize them) — never 2 at once.
for k in 1 2; do
    printf '\n// rapid move %s\n' "$k" >> "$D_W/geometry.cpp"
    git -C "$D_W" commit -q -am "rapid $k"
    printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":$((10+k)),\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$D_W\",\"symbol\":\"perimeter\"}}}" >&9
    wait_for_id "$D_W/out.txt" $((10+k))
done
sleep 0.8
# server still alive after rapid moves?
printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":99,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$D_W\",\"symbol\":\"area\"}}}" >&9
wait_for_id "$D_W/out.txt" 99 && ok "(d) server still responsive after two rapid HEAD moves (no crash)" \
                              || no "(d) server unresponsive after rapid HEAD moves (crash?)"
# scan the ordered spawn/done lines; the live worker count must NEVER exceed 1.
MAXLIVE="$( grep -E "ripwire-prefetch (spawn|done)" "$D_W/err.txt" | python3 -c '
import sys
live=0; mx=0
for ln in sys.stdin:
    if "spawn" in ln: live+=1; mx=max(mx,live)
    elif "done" in ln: live=max(0,live-1)
print(mx)
' )"
[ "${MAXLIVE:-0}" -le 1 ] && ok "(d) at most one concurrent prefetch worker (max live=${MAXLIVE:-0}; single-flight holds)" \
                          || no "(d) more than one concurrent worker (max live=$MAXLIVE) — single-flight broken"
assert_no_tsan "$D_W/err.txt" "d"
exec 9>&-; kill $SRV 2>/dev/null; wait $SRV 2>/dev/null

echo
[ "$fail" -eq 0 ] && { echo "qsnapprefetchcheck: ALL PASS"; exit 0; } || { echo "qsnapprefetchcheck: FAIL"; exit 1; }
