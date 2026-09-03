#!/usr/bin/env bash
# freshnesscheck.sh — card A3: an answer served from a warm index must SAY whether it still describes
# the tree, on the answer itself, without the agent having to ask.
#
# WHAT THIS GATES. The `--mcp` server holds ONE in-memory index across every request in a session. It
# already re-validates that index on every request (mcpStale(): a watched-dir mtime sweep plus a per-file
# mtime+size loop, then a rebuild when either moves) — but until this round it never SAID SO. An agent
# reading a warm answer had `_index` (which index state answered) and `_reingest` (what a refresh cost),
# and no field that answers the question it actually has: *is this answer describing the tree I am editing
# right now?* The three fields gated here answer it:
#
#   _fresh          "ok"        — the re-validation ran this request and found nothing moved; the answer
#                                 was served from the index as it stood.
#                   "reindexed" — the re-validation ran, found the tree had moved, and the index was
#                                 rebuilt BEFORE the verb answered. Never a stale serve.
#   _stale_files    N           — how many INDEXED files diverged from their recorded (mtimeNs, sizeBytes).
#                                 Emitted only alongside "reindexed". An ADD is legitimately 0 here: no
#                                 indexed file moved, the containing directory did.
#   _changed_files  N           — how many files actually differ in CONTENT from the index that was
#                                 replaced (added + removed + byte-hash-changed). Emitted only alongside
#                                 "reindexed".
#
# WHY _changed_files EXISTS, AND WHY IT IS THE ARM THAT MATTERS (arm 4). A bare `touch` moves mtime with
# every byte untouched. A stat-keyed check is ENTITLED to re-validate on it — that is the check working —
# but reporting it the same way an edit is reported would be dishonest: nothing was stale. So the two
# facts are kept apart. On a pure touch the honest disclosure is `_stale_files:1` (yes, a recorded stat
# moved) with `_changed_files:0` (no, nothing in the tree's content had changed). An implementation that
# cannot tell arm 1 from arm 4 fails this gate, which is exactly the "must NOT report stale if the hash is
# unchanged, or must say why" clause of the registered band (docs/EVALS.md, card A3).
#
# THE TWO CONTROLS. The bands are two-sided on purpose, because each side kills a different wrong build:
#   • arm 0b (clean re-query) — a build that reports "reindexed" unconditionally goes RED here.
#   • arm 1  (edit) — a build that never re-stats between requests keeps serving the warm index, so it
#     reports "ok" AND its answer still names the pre-edit symbol. Both halves are asserted, so the
#     mutation control fails on the disclosure and on the answer independently.
#
# NOT COMPARED AGAINST A COLD RUN. Like `_reingest`, these three fields are PROCESS HISTORY — what this
# server had to do to answer — not tree state. A cold server rebuilds everything and reports differently
# for the same tree by design. mcpincrementalcheck.sh owns the warm==cold equivalence of the payload
# itself; this gate owns the disclosure. Neither field may ever reach a byte that must match a cold run.
#
# Usage:
#   test/freshnesscheck.sh
#   RIPWIRE_BIN=asan/ripwire test/freshnesscheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.
# NEVER edits test/fixture itself — every mutation happens on a scratch COPY in a mktemp dir.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
FIX="$ROOT/test/fixture"
TMP="$( mktemp -d )"
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for JSON assertions"; exit 2; }

echo "freshnesscheck: BIN=$BIN  FIX=$FIX"

# ─── a scratch COPY of the fixture ────────────────────────────────────────────────────────────────
WORK="$TMP/work"
mkdir -p "$WORK"
cp -R "$FIX/"* "$WORK/"
GEO="$WORK/geometry.cpp"

WARMTMP="$TMP/warmtmp"; mkdir -p "$WARMTMP"

# ─── JSON extraction (mcpincrementalcheck's shape) ────────────────────────────────────────────────
# Every reader prints "__ABSENT__" for a missing field, so "the field said 0" and "there was no field"
# can never be confused — the distinction arms 3 and 4 turn on.
field_for_id() {
    grep "\"id\":$2" "$1" | tail -1 | FLD="$3" python3 -c '
import sys, json, os
r = json.load(sys.stdin)
v = r.get("result",{}).get(os.environ["FLD"], None)
print("__ABSENT__" if v is None else str(v))
'
}
text_for_id() {
    grep "\"id\":$2" "$1" | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
if "error" in r:
    print("__ERROR__:" + r["error"].get("message",""))
else:
    print(json.dumps(r["result"]["content"][0]["text"]))
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

TASK="compute the area and perimeter of a shape"

# one `for` request against the SAME long-lived process → WTEXT / WFRESH / WSTALE / WCHANGED
warm_for() {
    local id="$1"
    printf '{"jsonrpc":"2.0","id":%s,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"%s"}}}\n' \
        "$id" "$WORK" "$TASK" >&9
    wait_for_id "$TMP/warm.out" "$id" || { no "warm server never answered id=$id"; WTEXT=""; WFRESH=""; WSTALE=""; WCHANGED=""; return 1; }
    WTEXT="$(    text_for_id  "$TMP/warm.out" "$id" )"
    WFRESH="$(   field_for_id "$TMP/warm.out" "$id" _fresh )"
    WSTALE="$(   field_for_id "$TMP/warm.out" "$id" _stale_files )"
    WCHANGED="$( field_for_id "$TMP/warm.out" "$id" _changed_files )"
}

# assert the three fields under one label. Pass __ABSENT__ for a field that must not be emitted.
expect() {
    local what="$1" efresh="$2" estale="$3" echanged="$4"
    [ "$WFRESH"   = "$efresh"   ] && ok "$what: _fresh=$WFRESH"                 || no "$what: _fresh=$WFRESH, expected $efresh"
    [ "$WSTALE"   = "$estale"   ] && ok "$what: _stale_files=$WSTALE"           || no "$what: _stale_files=$WSTALE, expected $estale"
    [ "$WCHANGED" = "$echanged" ] && ok "$what: _changed_files=$WCHANGED"       || no "$what: _changed_files=$WCHANGED, expected $echanged"
}

# ═══════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== arm 0a: the FIRST build — validated, and not a re-index of anything ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════
# There was no index to be stale, so the honest report is "ok" with no counts. Emitting counts here
# would leak a number that depends on whether a cache blob happened to exist (the _reingest lesson).
warm_for 10
[ -n "$WTEXT" ] && ok "arm 0a: server answered the ranked verb (index built)" \
                || no "arm 0a: server produced no ranked answer"
expect "arm 0a (first build)" ok __ABSENT__ __ABSENT__

# ═══════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== arm 0b (CONTROL): an untouched tree must NOT claim a re-index ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════
# The control that kills a build which reports "reindexed" unconditionally. Nothing moved between
# request 10 and request 11, so the re-validation ran and found the index still correct.
warm_for 11
expect "arm 0b (clean re-query)" ok __ABSENT__ __ABSENT__

# ═══════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== arm 1 (CONTROL): EDIT one file → reindexed, one stale, one changed ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════
python3 - "$GEO" <<'PY'
import sys
p = sys.argv[1]
b = open(p, "rb").read()
b2 = b.replace(b"double perimeter", b"double perimeterEdited")
assert b2 != b, "the edit must actually change the file"
open(p, "wb").write(b2)
PY
warm_for 12
expect "arm 1 (edit)" reindexed 1 1
# the second half of the mutation control: a build that never re-stats reports "ok" AND answers stale.
case "$WTEXT" in
    *perimeterEdited*) ok "arm 1: the answer itself reflects the edit (no stale serve behind an ok)";;
    *)                 no "arm 1: 'perimeterEdited' absent — the server answered from a stale index";;
esac

# ═══════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== arm 2: DELETE a file → reindexed, one stale, one changed ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════
# A deleted indexed file stats to (-1,-1), which diverges from its record — so unlike an ADD it IS a
# per-file staleness, and it is a content change (the file's bytes left the index).
VICTIM="$WORK/app.py"
if [ ! -f "$VICTIM" ]; then
    no "arm 2: the fixture no longer carries app.py — this arm needs a deletable file"
else
    rm -f "$VICTIM"
    warm_for 13
    expect "arm 2 (delete)" reindexed 1 1
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== arm 3: ADD a file → reindexed, ZERO stale, one changed ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════
# The asymmetry worth pinning: an addition moves no INDEXED file's stat — it moves the containing
# directory's mtime. `_stale_files:0` with `_changed_files:1` is therefore the correct pair, and it is a
# different sentence from arm 4's `1` / `0`. A build that folded the two counts into one cannot say
# either of them.
cat > "$WORK/addedlane.cpp" <<'CPP'
// added mid-session: the incremental pass must extract this file and nothing else.
double addedLaneArea( double w, double h )
{
    return w * h;
}
CPP
warm_for 14
expect "arm 3 (add)" reindexed 0 1
case "$WTEXT" in
    *addedLane*) ok "arm 3: the added file's symbols are visible to the SAME long-lived server";;
    *)           no "arm 3: 'addedLane*' absent — the added file was never extracted";;
esac

# ═══════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== arm 4 (THE DISCRIMINATOR): touch WITHOUT a content change → nothing was stale ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════
# The registered band's clause: a touch may re-validate, but must not claim anything was stale. The
# honest pair is `_stale_files:1` (a recorded stat moved — that is why the pass ran) with
# `_changed_files:0` (and no byte of the tree differs). An implementation that reports this arm the way
# it reports arm 1 fails the band.
BEFORE_TEXT="$WTEXT"
touch "$WORK/addedlane.cpp"
warm_for 15
expect "arm 4 (touch, content identical)" reindexed 1 0
if [ "$WTEXT" = "$BEFORE_TEXT" ]; then
    ok "arm 4: _changed_files=0 is corroborated — the ANSWER is byte-identical across the pass"
else
    no "arm 4: the answer moved across a content-identical pass, so _changed_files=0 cannot be right"
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== arm 5: every index-reading verb carries the field, not just the ranked one ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════
# The capability is "every answer served from the warm cache", so a single verb passing is not the
# claim. Three more verbs from three different families, on the settled tree: all must report ok.
armfive_fail=0
i=20
for V in '{"name":"find_symbol","arguments":{"path":"WORKDIR","symbol":"addedLaneArea"}}' \
         '{"name":"impact","arguments":{"path":"WORKDIR","symbol":"addedLaneArea"}}' \
         '{"name":"explore","arguments":{"path":"WORKDIR","task":"compute the area of a shape"}}'
do
    VV="${V//WORKDIR/$WORK}"
    printf '{"jsonrpc":"2.0","id":%s,"method":"tools/call","params":%s}\n' "$i" "$VV" >&9
    if wait_for_id "$TMP/warm.out" "$i"; then
        F="$( field_for_id "$TMP/warm.out" "$i" _fresh )"
        [ "$F" = "ok" ] || { no "arm 5: verb #$i reported _fresh=$F on a settled tree"; armfive_fail=1; }
    else
        no "arm 5: verb #$i never answered"; armfive_fail=1
    fi
    i=$(( i + 1 ))
done
[ "$armfive_fail" -eq 0 ] && ok "arm 5: find_symbol / impact / explore all carry _fresh=ok"

# ═══════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== arm 6: the CLI's own residual, made executable rather than asserted in prose ==="
# ═══════════════════════════════════════════════════════════════════════════════════════════════
# The stat-keyed check has one irreducible hole — a content edit that preserves BOTH the mtime and the
# exact byte length — and cachehashcheck.sh's header used to claim the CLI was immune to it ("the CLI path
# re-crawls and re-hashes bytes every invocation, so an equal mtime never masks a content change"). The
# A4-P7 stat-gate made that false: a warm run trusts a cached entry whose (size, mtime) still match and
# whose recorded mtime is strictly older than the cache blob's own, and then never reads the bytes. This
# arm reproduces it, so the limit is a thing the suite SHOWS rather than a sentence someone has to
# remember. Two halves, and only the first two assertions are contracts:
#   • HARD — `--no-cache` must be correct (the escape hatch has to work, or the limit is unbounded).
#   • HARD — a LENGTH-changing edit with the same restored mtime must be caught (the size discriminator is
#     the thing that makes the residual a corner rather than the common case).
#   • OBSERVED — whether the same-(mtime,size) edit is missed. Reported, never failed: closing it needs a
#     whole-tree re-read, which mcpStale's comment prices at ~13x the warm path. If a future round closes
#     it, this line says so instead of a gate going red for an improvement.
CLI="$TMP/cliresidual"; mkdir -p "$CLI/tree"
CLITMP="$TMP/clitmp"; mkdir -p "$CLITMP"
OLDSTAMP=202601011200.00
syms(){ TMPDIR="$CLITMP" "$BIN" "$CLI/tree" --top-k=20 "$@" 2>/dev/null | grep -o 'n="[A-Za-z]*"' | sort -u | tr '\n' ' '; }
printf 'int alphaaa( int x ) { return x + 1; }\nint caller( void ) { return alphaaa( 2 ); }\n' > "$CLI/tree/a.c"
touch -t "$OLDSTAMP" "$CLI/tree/a.c"
COLD="$( syms )"
case "$COLD" in *alphaaa*) ok "arm 6: cold run indexes the original symbol";; *) no "arm 6: cold run did not index alphaaa (got: $COLD)";; esac
# the attack: identical byte length, mtime restored to the pre-edit value
printf 'int betaaaa( int x ) { return x + 1; }\nint caller( void ) { return betaaaa( 2 ); }\n' > "$CLI/tree/a.c"
touch -t "$OLDSTAMP" "$CLI/tree/a.c"
WARM="$( syms )"
NOCACHE="$( syms --no-cache )"
case "$NOCACHE" in
    *betaaaa*) ok "arm 6 (HARD): --no-cache sees the new content — the escape hatch is intact";;
    *)         no "arm 6 (HARD): --no-cache served '$NOCACHE' — a cold parse must never be stale";;
esac
case "$WARM" in
    *betaaaa*) ok "arm 6 (OBSERVED): the same-(mtime,size) edit IS caught on this platform — the residual is narrower than documented";;
    *alphaaa*) ok "arm 6 (OBSERVED, not a defect): the warm CLI serves the pre-edit symbol — the documented same-(mtime,size) residual, reproduced";;
    *)         no "arm 6: the warm run named neither spelling (got: $WARM) — the arm did not stage";;
esac
# the size discriminator, which is what keeps the residual a corner case
printf 'int gammaaaLONGER( int x ) { return x + 1; }\nint caller( void ) { return gammaaaLONGER( 2 ); }\n' > "$CLI/tree/a.c"
touch -t "$OLDSTAMP" "$CLI/tree/a.c"
LEN="$( syms )"
case "$LEN" in
    *gammaaaLONGER*) ok "arm 6 (HARD): a LENGTH-changing edit under the same restored mtime is caught";;
    *)               no "arm 6 (HARD): a length-changing edit was missed (got: $LEN) — the size discriminator is blind";;
esac

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
else
    echo "FAILURES PRESENT"
fi
exit "$fail"
