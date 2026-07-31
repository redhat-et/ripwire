#!/usr/bin/env bash
# mcpstalecheck.sh — the G-B1 gate: MCP READ verbs must not serve a STALE index after a
# content-changed-but-mtime-preserved edit (RESEARCH_agentQuality2026 §3b.1).
#
# The bug (reproduced in the audit): mcpStale() compared file mtime by EQUALITY only. A long-lived
# --mcp server that has warmed its in-memory index, then sees a file whose CONTENT changed while its
# mtime was restored (`touch -r` after an edit), keeps serving the OLD index — silently wrong answers to
# the agent. The `_index` stamp (also derived from (path,mtime)) stayed unchanged while the answers
# changed, so the caller couldn't even detect the staleness out-of-band.
#
# The fix (S1): add the file SIZE as a second staleness discriminator (free from the same stat() as mtime)
# AND fold the per-file content hash into the `_index` stamp. A content edit that changes the byte length —
# i.e. essentially every real edit (adding/renaming/removing a symbol, inserting a line) — is now caught
# EVEN WITH the mtime restored, and the stamp moves on ANY content change. (The same-(mtime,size) corner —
# a same-length rename + touch -r — is the documented irreducible residual: catching it would require a
# whole-tree re-read on every verb call, ~13× the warm-path cost — see mcpStale's comment in src/mcp.h. The
# EDIT verbs' own per-write byte-hash guard covers that corner for writes.)
#
# This gate drives a LONG-LIVED server over a FIFO (same technique as mcpeditcheck.sh step 5 /
# situdiffcheck.sh's stdio piping): warm the index with a read verb, then make a length-CHANGING content
# edit (rename `distance` -> `distanceXY`) and restore BOTH the file's mtime and its parent directory's
# mtime, so ONLY the content+size changed (mtime is the preserved `touch -r` attack signal). A second read
# verb call in the SAME server process MUST reflect the new symbol, and the `_index` stamp MUST change. On
# the pre-fix binary this FAILS (mtime alone is blind) — that failing gate is the executable spec.
#
# Usage:
#   test/mcpstalecheck.sh
#   CTXPACK_BIN=asan/ctxpack test/mcpstalecheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.
# NEVER edits test/fixture itself — every mutation happens on a scratch COPY in a mktemp dir.
# Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative CTXPACK_BIN
FIX="$ROOT/test/fixture"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for JSON assertions"; exit 2; }

echo "mcpstalecheck: BIN=$BIN  FIX=$FIX"

# ─── a scratch git repo COPY of the fixture (the plan asks for a scratch git repo copy) ───────────
WORK="$( mktemp -d "$TMP/work.XXXXXX" )"
cp -R "$FIX/"* "$WORK/"
git -C "$WORK" init -q 2>/dev/null
git -C "$WORK" config user.email "stale@x.com" 2>/dev/null
git -C "$WORK" config user.name  "Stale" 2>/dev/null
git -C "$WORK" add -A 2>/dev/null
git -C "$WORK" commit -q -m init 2>/dev/null
GEO="$WORK/geometry.cpp"

# ─── extract the tools/call inner text for a given id from the server's output ────────────────────
inner_for_id() {
    # $1 = out file, $2 = id
    grep "\"id\":$2" "$1" | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
if "error" in r:
    print("__ERROR__:" + r["error"].get("message",""))
else:
    print(r["result"]["content"][0]["text"])
'
}
# extract the _index envelope stamp for a given id (empty if absent)
stamp_for_id() {
    grep "\"id\":$2" "$1" | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
print(r.get("result",{}).get("_index",""))
'
}
wait_for_id() {
    # $1 = out file, $2 = id — deterministic wait so ordering is not timing-dependent
    local i
    for i in $( seq 1 200 ); do
        grep -q "\"id\":$2" "$1" 2>/dev/null && return 0
        sleep 0.05
    done
    return 1
}

# ═══════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== stale-read: length-changing content edit + mtime restore → read verb must reflect it ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════
# Drive a LONG-LIVED server over a FIFO:
#   1. initialize + a read verb (for) → WARMS the in-memory index.
#   2. rename distance() -> distanceXY() (length CHANGES; size+mtime catches it), restore file's mtime AND
#      parent dir's mtime so nothing but the bytes changed.
#   3. a second read verb → MUST see the change (distanceXY present / distance gone), and the _index
#      stamp MUST differ from the pre-edit stamp.

FIFO="$WORK/in.fifo"; mkfifo "$FIFO"
"$BIN" --mcp <"$FIFO" >"$WORK/out.txt" 2>/dev/null &
SRV=$!
exec 9>"$FIFO"

INIT='{"jsonrpc":"2.0","id":1,"method":"initialize"}'
# Observable: find_symbol for the POST-edit symbol name `distanceXY`. This resolves against the IN-MEMORY
# symbol table (ix.ing.symbols), NOT a fresh disk read — so it is only satisfied if mcpStale() actually
# forced a REBUILD. (grep would be a false-positive here: buildGrepIndex re-reads files from disk on every
# call, so grep reflects new content even from a stale index — it does not exercise the staleness path.)
# On a stale index `distanceXY` is not a known symbol → "not found"; on a rebuilt index it resolves.
FS1="{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$WORK\",\"symbol\":\"distanceXY\"}}}"

# A stamp probe on a symbol that resolves BOTH before and after (`perimeter`, untouched by the edit) — an
# error/not-found response carries no _index field, so distanceXY (which misses pre-edit) can't source a stamp.
STAMP1="{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$WORK\",\"symbol\":\"perimeter\"}}}"

printf '%s\n' "$INIT" >&9
printf '%s\n' "$STAMP1" >&9
printf '%s\n' "$FS1" >&9
wait_for_id "$WORK/out.txt" 2 || no "server never answered the warm-up read verb (id=2)"

FS_BEFORE="$( inner_for_id "$WORK/out.txt" 2 )"
STAMP_BEFORE="$( stamp_for_id "$WORK/out.txt" 8 )"

# sanity: BEFORE the edit, the post-edit symbol name `distanceXY` does not exist (it is still `distance`).
case "$FS_BEFORE" in
    __ERROR__*) ok "warm-up: find_symbol('distanceXY') MISSES pre-edit (index sees the original 'distance')";;
    *) no "warm-up: 'distanceXY' unexpectedly resolves pre-edit: $( echo "$FS_BEFORE" | head -c 200 )";;
esac

# --- the touch -r attack: length-CHANGING content edit (distance -> distanceXY), mtime + dir-mtime restored ---
SZ_ORIG="$( python3 -c "import os;print(os.path.getsize('$GEO'))" )"   # original size, captured pre-edit
DIRREF="$TMP/dirref"; touch -r "$WORK" "$DIRREF"      # remember the parent dir's mtime
FREF="$TMP/fref";     touch -r "$GEO"  "$FREF"        # remember the file's mtime
python3 - "$GEO" <<'PY'
import sys
p = sys.argv[1]
b = open(p, "rb").read()
b2 = b.replace(b"distance", b"distanceXY")   # +4 bytes per occurrence → size changes
assert b2 != b, "content must actually change"
assert len(b2) != len(b), "edit must change the byte length (the realistic case size+mtime catches)"
open(p, "wb").write(b2)
PY
touch -r "$FREF"   "$GEO"                              # restore the file mtime — THE touch -r ATTACK (mtime lies)
touch -r "$DIRREF" "$WORK"                             # restore the parent dir mtime (only content+size changed)

# confirm the MTIME was truly restored (the attack is real: mtime-equality alone would be blind).
MT_OK=$( python3 -c "import os;print('yes' if os.stat('$GEO').st_mtime==os.stat('$FREF').st_mtime else 'no')" 2>/dev/null || echo "?" )
[ "$MT_OK" = "yes" ] \
    && ok "edit's MTIME was restored by touch -r (mtime-equality alone is blind → the size discriminator is what catches it)" \
    || no "mtime not restored ($MT_OK) — the test would then pass via the mtime path, not the S1 size fix"

# --- second read verb in the SAME long-lived server process: must reflect the change ----------------
FS2="{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$WORK\",\"symbol\":\"distanceXY\"}}}"
STAMP2="{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"tools/call\",\"params\":{\"name\":\"find_symbol\",\"arguments\":{\"path\":\"$WORK\",\"symbol\":\"perimeter\"}}}"
printf '%s\n' "$FS2" >&9
printf '%s\n' "$STAMP2" >&9
wait_for_id "$WORK/out.txt" 4 || no "server never answered the post-edit read verb (id=4)"
wait_for_id "$WORK/out.txt" 9 || no "server never answered the post-edit stamp probe (id=9)"

exec 9>&-
wait "$SRV" 2>/dev/null

FS_AFTER="$( inner_for_id "$WORK/out.txt" 4 )"
STAMP_AFTER="$( stamp_for_id "$WORK/out.txt" 9 )"

# assertion 1 (THE bug): find_symbol('distanceXY') must now RESOLVE — the in-memory index rebuilt to reflect
# the same-mtime+same-size content edit. A STALE index (the pre-fix binary) still returns "not found".
case "$FS_AFTER" in
    __ERROR__*) no "post-edit: find_symbol('distanceXY') STILL misses — STALE index never rebuilt (the S1 bug): ${FS_AFTER#__ERROR__:}";;
    *geometry.cpp*) ok "post-edit: find_symbol('distanceXY') RESOLVES to geometry.cpp — index rebuilt from the size+mtime signal";;
    *) ok "post-edit: find_symbol('distanceXY') resolves — the index reflects the mtime-preserved edit";;
esac

# assertion 2: the response bytes must DIFFER before vs after (the answer changed: not-found → found).
if [ "$FS_BEFORE" != "$FS_AFTER" ]; then
    ok "post-edit: find_symbol response changed (not-found → resolved — the read verb is no longer stale)"
else
    no "post-edit: find_symbol response is byte-identical to the pre-edit result — STALE"
fi

# assertion 3: the _index stamp must CHANGE (it must not lie alongside the fixed staleness).
if [ -n "$STAMP_BEFORE" ] && [ "$STAMP_BEFORE" != "$STAMP_AFTER" ]; then
    ok "_index stamp changed after the content edit (stamp no longer lies): '$STAMP_BEFORE' -> '$STAMP_AFTER'"
else
    no "_index stamp did NOT change (before='$STAMP_BEFORE' after='$STAMP_AFTER') — the stamp still folds only (path,mtime)"
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════════
echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
