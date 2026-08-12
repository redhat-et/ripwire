#!/usr/bin/env bash
# mcpincrementalcheck.sh — P1-15: the MCP server's INCREMENTAL reingest must be (a) byte-equivalent to a
# cold full reingest of the same tree state, and (b) HONEST about how many files it actually re-extracted.
#
# WHAT IS ALREADY TRUE (this gate pins it against regression). getIndex() detects staleness with a
# mtime+size stat sweep and then rebuilds through ingest()'s content-hash cache — the A4-P7 stat-gate means
# an unchanged file is neither READ nor PARSED, only changed/added/removed files are re-extracted, and the
# graph + PageRank passes re-run globally over cached-per-file facts + fresh facts. NodeIds are reassigned
# every run (never cached), which is exactly why a warm incremental answer can be byte-identical to a cold
# one. Nothing here asserts a NEW mechanism for that; arms 1-3 are the executable proof that the mechanism
# holds under edit / delete / add, because "the ranking still looks right" is indistinguishable from
# "the ranking is right" by eye, and PageRank is GLOBAL — one changed edge moves every score, so a splice
# that reused one stale cached fact would show up here and nowhere else.
#
# WHAT IS NEW (the red arm). Nothing disclosed how much work an incremental pass did. `reingest_files=N` is
# now emitted as the `_reingest` envelope field on any response whose handling triggered a rebuild, and it
# is a COUNT, never a guess: 0 means "the pass ran and re-extracted nothing", which is a different fact
# from "no pass ran" (the field is then absent). Arm 4 is the pre-fix reproducer — a stat-changed but
# content-identical tree must report 0, and on the pre-fix binary there is no field at all.
#
# THE EQUIVALENCE INSTRUMENT. For each tree state, the same verb is asked of TWO servers:
#   • the WARM one — a single long-lived process that has been carrying its in-memory index across every
#     mutation in this script, so it can only answer incrementally;
#   • a COLD one — a fresh process under a FRESH TMPDIR, so quality::cacheDirLadder() resolves to an empty
#     cache dir and ingest() has no blob to stat-gate against: a full parse of every file.
# Both run against the SAME directory (paths appear verbatim in verb output, so a copied tree would differ
# for an uninteresting reason). The compared surface is the verb's `text` payload AND the `_index` stamp —
# the two things that are a pure function of tree state. `_reingest` is deliberately NOT compared: it
# discloses what THIS PROCESS did, not what the tree contains, so it differs by design (cold re-extracts
# every file) — the same category as the RIPWIRE_MCP_TIMINGS stderr line.
#
# The verb is `for`, not `find_symbol`: it returns a RANKED set, so its bytes depend on every PageRank
# score in the tree. A splice that got one edge wrong reorders it; find_symbol would still resolve.
#
# Usage:
#   test/mcpincrementalcheck.sh
#   RIPWIRE_BIN=asan/ripwire test/mcpincrementalcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.
# NEVER edits test/fixture itself — every mutation happens on a scratch COPY in a mktemp dir.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
FIX="$ROOT/test/fixture"
TMP="$( mktemp -d )"
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for JSON assertions"; exit 2; }

echo "mcpincrementalcheck: BIN=$BIN  FIX=$FIX"

# ─── a scratch git repo COPY of the fixture ───────────────────────────────────────────────────────
WORK="$TMP/work"
mkdir -p "$WORK"
cp -R "$FIX/"* "$WORK/"
git -C "$WORK" init -q 2>/dev/null
git -C "$WORK" config user.email "incr@x.com" 2>/dev/null
git -C "$WORK" config user.name  "Incr" 2>/dev/null
git -C "$WORK" add -A 2>/dev/null
git -C "$WORK" commit -q -m init 2>/dev/null
GEO="$WORK/geometry.cpp"

# the WARM server's cache home — one TMPDIR for the whole session, so its blob survives every mutation.
WARMTMP="$TMP/warmtmp"; mkdir -p "$WARMTMP"

# ─── JSON extraction helpers (mcpstalecheck's shape) ──────────────────────────────────────────────
inner_for_id() {
    grep "\"id\":$2" "$1" | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
if "error" in r:
    print("__ERROR__:" + r["error"].get("message",""))
else:
    print(json.dumps(r["result"]["content"][0]["text"]))
'
}
stamp_for_id() {
    grep "\"id\":$2" "$1" | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
print(r.get("result",{}).get("_index",""))
'
}
# the NEW disclosure field. Prints "__ABSENT__" when the response carries none — so "the pass reingested
# zero files" and "no field was emitted" can never be confused for one another (the whole point of arm 4).
reingest_for_id() {
    grep "\"id\":$2" "$1" | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
v = r.get("result",{}).get("_reingest", None)
print("__ABSENT__" if v is None else str(v))
'
}
wait_for_id() {
    local i
    for i in $( seq 1 400 ); do
        grep -q "\"id\":$2" "$1" 2>/dev/null && return 0
        sleep 0.05
    done
    return 1
}

# ─── the long-lived WARM server ───────────────────────────────────────────────────────────────────
FIFO="$WORK/in.fifo"; mkfifo "$FIFO"
TMPDIR="$WARMTMP" "$BIN" --mcp <"$FIFO" >"$TMP/warm.out" 2>/dev/null &
SRV=$!
exec 9>"$FIFO"
trap 'exec 9>&- 2>/dev/null; kill "$SRV" 2>/dev/null; rm -rf "$TMP"' EXIT
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' >&9

# ask the WARM server for verb `for` with task $2, response id $1 → sets WTEXT / WSTAMP / WREINGEST.
warm_for() {
    local id="$1" task="$2"
    printf '{"jsonrpc":"2.0","id":%s,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"%s"}}}\n' \
        "$id" "$WORK" "$task" >&9
    wait_for_id "$TMP/warm.out" "$id" || { no "warm server never answered id=$id"; WTEXT=""; WSTAMP=""; WREINGEST=""; return 1; }
    WTEXT="$( inner_for_id "$TMP/warm.out" "$id" )"
    WSTAMP="$( stamp_for_id "$TMP/warm.out" "$id" )"
    WREINGEST="$( reingest_for_id "$TMP/warm.out" "$id" )"
}

# ask a FRESH server (fresh TMPDIR ⇒ no cache blob ⇒ genuine COLD full reingest) → CTEXT / CSTAMP.
cold_for() {
    local task="$1"
    local ct; ct="$( mktemp -d "$TMP/cold.XXXXXX" )"
    printf '%s\n{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"%s"}}}\n' \
        '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$WORK" "$task" \
        | TMPDIR="$ct" "$BIN" --mcp >"$ct/out" 2>/dev/null
    CTEXT="$( inner_for_id "$ct/out" 7 )"
    CSTAMP="$( stamp_for_id "$ct/out" 7 )"
}

# compare the two tree-state surfaces (text + stamp) and report under $1.
equiv() {
    local what="$1"
    if [ -z "$WTEXT" ] || [ -z "$CTEXT" ]; then
        no "$what: one of the two responses was empty (warm=${#WTEXT}B cold=${#CTEXT}B)"
        return
    fi
    if [ "$WTEXT" = "$CTEXT" ]; then
        ok "$what: incremental verb text is BYTE-IDENTICAL to a cold full reingest ($(( ${#WTEXT} )) B)"
    else
        no "$what: incremental verb text DIFFERS from a cold full reingest"
        diff <( printf '%s\n' "$WTEXT" ) <( printf '%s\n' "$CTEXT" ) | head -20
    fi
    if [ "$WSTAMP" = "$CSTAMP" ]; then
        ok "$what: _index stamp matches cold ('$WSTAMP')"
    else
        no "$what: _index stamp differs — warm='$WSTAMP' cold='$CSTAMP'"
    fi
}

TASK="compute the area and perimeter of a shape"

# ═══════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== warm-up: the long-lived server builds its index once ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════
warm_for 10 "$TASK"
[ -n "$WTEXT" ] && ok "warm-up: server answered the ranked verb (index built)" \
                || no "warm-up: server produced no ranked answer"
# The first build is NOT an incremental pass — there was no index to bring up to date — so the field must be
# ABSENT here. This is a cache-transparency assertion, not a cosmetic one: the first build's re-extraction
# count is the only number in this family that depends on whether a cache blob happened to exist on disk
# (the whole corpus if cold, zero if warm), and emitting it would make two runs of the same request differ.
case "$WREINGEST" in
    __ABSENT__) ok "warm-up: no _reingest on the FIRST build — an initial build is not an incremental pass";;
    *)          no "warm-up: first build emitted _reingest=$WREINGEST — a blob-dependent number leaked into the response";;
esac

# ═══════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== arm 1: EDIT one file → reflected in the next query AND equal to a cold rebuild ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════
python3 - "$GEO" <<'PY'
import sys
p = sys.argv[1]
b = open(p, "rb").read()
b2 = b.replace(b"double perimeter", b"double perimeterEdited")
assert b2 != b, "the edit must actually change the file"
open(p, "wb").write(b2)
PY
warm_for 11 "$TASK"
case "$WTEXT" in
    *perimeterEdited*) ok "arm 1: the edited symbol name is visible to the SAME long-lived server";;
    *)                 no "arm 1: 'perimeterEdited' absent — the incremental pass did not pick the edit up";;
esac
case "$WREINGEST" in
    1) ok "arm 1: _reingest=1 — exactly the one changed file was re-extracted (cost is proportional to drift)";;
    __ABSENT__) no "arm 1: no _reingest disclosure after a real edit";;
    *) no "arm 1: _reingest=$WREINGEST after a ONE-file edit — the incremental pass re-extracted more than the drift";;
esac
cold_for "$TASK"
equiv "arm 1 (edit)"

# ═══════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== arm 2: DELETE a file → its symbols are gone, and the result equals a cold rebuild ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════
# app.py is the fixture's only file whose symbols nothing else defines, so its disappearance is
# unambiguous: any surviving mention of `shape_report` after the delete is a symbol the incremental pass
# failed to drop. Deleting a file is the case a naive per-file splice gets wrong most often — nothing
# arrives to overwrite the stale entry, so it has to be actively removed AND every edge into it re-resolved.
VICTIM="$WORK/app.py"
if [ ! -f "$VICTIM" ]; then
    no "arm 2: the fixture no longer carries app.py — this arm needs a deletable file with unique symbols"
else
    GONE_SYM="$( grep -oE '^def [a-z_]+' "$VICTIM" | head -1 | sed 's/^def //' )"
    [ -n "$GONE_SYM" ] || GONE_SYM="app.py"
    rm -f "$VICTIM"
    warm_for 12 "$TASK"
    case "$WTEXT" in
        *"$GONE_SYM"*) no "arm 2: '$GONE_SYM' still appears after app.py was deleted — the removal was not spliced out";;
        *)             ok "arm 2: '$GONE_SYM' is gone from the index after its file was deleted";;
    esac
    case "$WREINGEST" in
        0) ok "arm 2: _reingest=0 — a pure DELETE re-extracts nothing (the work is re-resolution, not parsing)";;
        __ABSENT__) no "arm 2: no _reingest disclosure after a delete";;
        *) no "arm 2: _reingest=$WREINGEST after a pure delete — no file's content changed, so nothing should re-extract";;
    esac
    cold_for "$TASK"
    equiv "arm 2 (delete)"
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== arm 3: ADD a file → present, and the result equals a cold rebuild ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════
cat > "$WORK/addedlane.cpp" <<'CPP'
// added mid-session: the incremental pass must extract this file and nothing else.
double addedLaneArea( double w, double h )
{
    return w * h;
}
double addedLanePerimeter( double w, double h )
{
    return 2.0 * ( w + h );
}
CPP
warm_for 13 "$TASK"
case "$WTEXT" in
    *addedLane*) ok "arm 3: the added file's symbols are visible to the SAME long-lived server";;
    *)           no "arm 3: 'addedLane*' absent — the added file was never extracted";;
esac
case "$WREINGEST" in
    1) ok "arm 3: _reingest=1 — only the new file was extracted";;
    __ABSENT__) no "arm 3: no _reingest disclosure after an add";;
    *) no "arm 3: _reingest=$WREINGEST after adding ONE file";;
esac
cold_for "$TASK"
equiv "arm 3 (add)"

# ═══════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== arm 4 (THE RED ARM): a pass over an untouched tree reingests ZERO files, and says so ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════
# A pure `touch` moves mtime with the bytes untouched. mcpStale() sees the mtime move and forces a pass —
# so a pass genuinely RUNS — but ingest()'s content hash matches the cached one for every file, so the
# correct disclosure is exactly 0. "0" and "absent" are different facts and the helper keeps them apart.
BEFORE_TEXT="$WTEXT"; BEFORE_STAMP="$WSTAMP"
touch "$WORK/addedlane.cpp"
warm_for 14 "$TASK"
case "$WREINGEST" in
    0)          ok "arm 4: the pass ran and discloses _reingest=0 — none changed, stated as a count";;
    __ABSENT__) no "arm 4: the pass ran but disclosed NOTHING — 'how much work did that cost' is unanswerable";;
    *)          no "arm 4: _reingest=$WREINGEST on a content-identical tree — a no-op pass re-extracted files";;
esac
if [ "$WTEXT" = "$BEFORE_TEXT" ]; then
    ok "arm 4: a zero-reingest pass left the ANSWER byte-identical (a touch cannot move one output byte)"
else
    no "arm 4: a content-identical tree produced a DIFFERENT answer across the pass"
fi
# The `_index` stamp is a different assertion and is deliberately NOT required to hold still here. It folds
# (path, mtime, byteHash) by design (the S1 content-fold), so a pure `touch` moves it while the answer stays
# put. That is over-conservative, not dishonest — the stamp's contract is "different stamp ⇒ do not assume
# the same index", never "same tree ⇒ same stamp" — and the value a COLD server computes for this same tree
# state moves identically, which is what the equivalence check below actually pins. Recording the
# observation here rather than silently comparing something weaker: an agent diffing two stamps across an
# editor's save-without-change will see a change that no answer reflects.
[ "$WSTAMP" != "$BEFORE_STAMP" ] \
    && ok "arm 4: (observed, not a defect) the stamp moved on a pure touch — mtime is folded into it by design" \
    || ok "arm 4: the stamp also held still across the touch"
cold_for "$TASK"
equiv "arm 4 (no-op pass)"

# ═══════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== arm 5: the mtime-race trap — a second edit inside one mtime granule is not missed ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════
# racymtimecheck's lesson, inherited rather than re-invented: ingest()'s stat-gate refuses to trust a cached
# entry whose mtime is NOT STRICTLY OLDER than the cache blob's own on-disk mtime, so a write landing in the
# same coarse granule as the cache write is force-re-hashed. This arm reproduces that shape at the MCP layer:
# edit, let the server rebuild (which rewrites the blob), then edit AGAIN and force BOTH the file's and the
# blob's mtime to the SAME whole second — what a coarse filesystem reports for free. The second edit changes
# the byte LENGTH too, so mcpStale's size discriminator is a second independent detector; both must hold for
# the answer to be fresh, and this arm fails if EITHER is blind.
python3 - "$GEO" <<'PY'
import sys
p = sys.argv[1]
b = open(p, "rb").read()
open(p, "wb").write(b.replace(b"perimeterEdited", b"perimeterRaceA"))
PY
warm_for 15 "$TASK"      # forces a rebuild → rewrites the cache blob under $WARMTMP
BLOB="$( find "$WARMTMP" -name 'ripwire-mcp-*.cache' 2>/dev/null | sort | head -1 )"
python3 - "$GEO" <<'PY'
import sys
p = sys.argv[1]
b = open(p, "rb").read()
open(p, "wb").write(b.replace(b"perimeterRaceA", b"perimeterRaceBB"))   # +1 byte: length changes too
PY
if [ -n "$BLOB" ]; then
    # force file AND blob into the SAME whole second — the coarse-FS shape racymtimecheck fakes.
    touch -t 202601011200.00 "$GEO"
    touch -t 202601011200.00 "$BLOB"
    ok "arm 5: file and cache blob forced into one mtime granule (blob=$( basename "$BLOB" ))"
else
    no "arm 5: no MCP cache blob found under the warm TMPDIR — the race shape could not be staged"
fi
warm_for 16 "$TASK"
case "$WTEXT" in
    *perimeterRaceBB*) ok "arm 5: the same-granule second edit IS reflected — the racy-mtime defense is inherited";;
    *perimeterRaceA*)  no "arm 5: STALE — the second edit inside one mtime granule was missed (racy rule lost)";;
    *)                 no "arm 5: neither race spelling present — the arm did not stage as intended";;
esac
cold_for "$TASK"
equiv "arm 5 (same-granule edit)"

# ═══════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== arm 6: torn-read defense — a file that changes DURING a pass is not left half-indexed ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════
# tornreadcheck's lesson: what makes a mid-flight write safe is not locking, it is that the pass hashes the
# BYTES IT ACTUALLY READ. Whatever snapshot a pass consumed, its recorded hash describes that snapshot, so a
# write that lands mid-pass leaves (mtime,size) disagreeing with the cache and the NEXT pass re-extracts —
# the index converges on the final bytes and never freezes on a torn one. Staged by starting a writer that
# rewrites the file repeatedly while the verb is in flight, then quiescing and asking once more: the settled
# answer must equal a cold reingest of the settled tree, with no leftover intermediate spelling.
( for i in 1 2 3 4 5 6 7 8; do
      python3 - "$GEO" "$i" <<'PY' 2>/dev/null
import sys
p, i = sys.argv[1], sys.argv[2]
b = open(p, "rb").read()
open(p, "wb").write(b.replace(b"perimeterRaceBB", b"perimeterTorn" + i.encode()).replace(
    b"perimeterTorn" + str(int(i)-1).encode(), b"perimeterTorn" + i.encode()))
PY
  done ) &
WRITER=$!
warm_for 17 "$TASK"                        # in flight while the writer churns — must not crash or wedge
wait "$WRITER" 2>/dev/null
python3 - "$GEO" <<'PY'
import sys, re
p = sys.argv[1]
b = open(p, "rb").read().decode("utf-8", "replace")
b = re.sub(r"perimeter(RaceBB|Torn\d)", "perimeterSettled", b)
open(p, "w").write(b)
PY
warm_for 18 "$TASK"                        # quiesced: the settled tree
case "$WTEXT" in
    *perimeterSettled*) ok "arm 6: after the writer quiesced the index converged on the FINAL bytes";;
    *)                  no "arm 6: the index did not converge on the settled content";;
esac
cold_for "$TASK"
equiv "arm 6 (post-torn-read settle)"

# ═══════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== arm 7: the disclosure must not cost cache transparency ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════
# The standing MCP contract (mcpverbscheck / mcprobustcheck / mcpclidiffcheck) is that two runs of the same
# request return byte-identical responses whether or not a cache blob exists on disk. `_reingest` is the
# first envelope field whose value could depend on that blob, so this arm pins the exact scenario that made
# it not: two consecutive fresh processes sharing ONE cache home — the first writes the blob, the second
# stat-gates against it and re-extracts nothing. Their FULL response lines (not just the payload) must
# match. This is the arm that fails if the disclosure is ever re-gated on "a rebuild happened" instead of
# "an index we already held was refreshed".
SHARED="$( mktemp -d "$TMP/shared.XXXXXX" )"
one_shot() {
    printf '%s\n{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"%s"}}}\n' \
        '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$WORK" "$TASK" \
        | TMPDIR="$SHARED" "$BIN" --mcp 2>/dev/null | grep '"id":7' | tail -1
}
R1="$( one_shot )"
R2="$( one_shot )"
if [ -z "$R1" ]; then
    no "arm 7: the one-shot server produced no response"
elif [ "$R1" = "$R2" ]; then
    ok "arm 7: cold-blob and warm-blob runs of the same request are BYTE-IDENTICAL (cache stays transparent)"
else
    no "arm 7: the same request answered differently with a cold vs a warm cache blob"
    diff <( printf '%s\n' "$R1" ) <( printf '%s\n' "$R2" ) | head -10
fi
case "$R1" in
    *_reingest*) no "arm 7: a single-request server emitted _reingest — it never held a prior index to refresh";;
    *)           ok "arm 7: a single-request server emits no _reingest (nothing was brought up to date)";;
esac

# ═══════════════════════════════════════════════════════════════════════════════════════════════
exec 9>&-
wait "$SRV" 2>/dev/null

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
