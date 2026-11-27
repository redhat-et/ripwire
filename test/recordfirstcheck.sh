#!/usr/bin/env bash
# recordfirstcheck.sh — RECORD-FIRST (#729 stage 2, warm snapshot kVersion 12): the run that PARSES records the warm
# snapshot, so the SECOND call is served, after an edit as after the first run (#794 made a cold first run record; a run
# after an edit still stored nothing, and the third call was the first served one); the snapshot is SECTIONED, each section checked by its own digest the first time a run reads it; the file
# is mapped, not read into memory; and it is written as a stream, section by section.
#
# The observable is one stderr line under RIPWIRE_SNAPSHOT_STATS=1 (src/main.cpp finishWarmSnapshot):
#   ripwire: snapshot-stats tree=walked|replayed model=built|loaded graph=built|loaded why= model_why= graph_why= saved=0|1
# A build without the snapshot prints no such line, so every "served" check below FAILS on a missing line.
#
# The corpus is every test/*fix directory copied into one tree plus a two-file Go module (so the resolver reads go.mod
# outside the crawl), back-dated past the racy window so a first run may record its crawl. The auto-cache is redirected
# into this gate's TMP (TMPDIR outranks XDG_CACHE_HOME in quality::cacheDirLadder), one fresh directory per arm group.
#
# ARMS (every negative arm counts what it saw and FAILs on zero)
#   R1  RECORD-FIRST, both orders: map x3 then --for x3, and --for x3 then map x3, each in a fresh cache directory. Call 1
#       of each verb records (saved=1); call 2 and call 3 are served (model=loaded graph=loaded); the three answers are
#       cmp-equal to each other and to --no-cache. The verb after the other one re-parses nothing (ONE-PARSE).
#   R2  kill switches: RIPWIRE_NO_RECORD_FIRST=1 — a cold call 1 still records (#794), but after an EDIT the parsing
#       run holds its model and graph back (unsaved_why=reparsed), call 2 is built, call 3 served, answers equal;
#       RIPWIRE_NO_WARMSNAP=1 — nothing is served, answers equal.
#   R3  invalidation, each from a served state, each with its why= and the answer == --no-cache, then served again on the
#       NEXT call (the record-first promise after an edit): edit / touch / add / remove / rename a file (why=tree-moved);
#       --exclude, --max-file-size, --ignore-tests, --no-ignore and one RIPWIRE_NO_* variable (another name: why=absent);
#       go.mod changed (graph_why=dep); the snapshot's version field (why=version); its producer field with the header
#       digest re-stamped (why=producer); in a git checkout, a commit that changes no file (why=git-moved, the graph
#       still served) and a git config change (why=git-moved).
#   R4  corruption, one byte flipped in the middle of each section in turn: only that section is refused
#       (TREE: why=checksum and the crawl walked; MODEL: model_why=checksum; GRAPH: graph_why=checksum), the others are
#       still used where the load order allows, and the answer == --no-cache; a byte in the header refuses the file.
#   R5  truncation: a snapshot cut inside its last section is refused whole (why=checksum), answer == --no-cache.
#
# Usage: bash test/recordfirstcheck.sh [BIN]
# Exits non-zero on any failure; prints PASS/FAIL per check; prints ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )" && [ -n "$TMP" ] && [ -d "$TMP" ] || { echo "recordfirstcheck: mktemp -d failed"; exit 2; }
trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required (the snapshot header)"; exit 2; }
echo "recordfirstcheck: BIN=$BIN  TMP=$TMP"
FOR='distance between two points'

# ── the corpus ──────────────────────────────────────────────────────────────────────────────────────
mkcorpus()
{
    local dst="$1"; mkdir -p "$dst"
    for d in "$ROOT"/test/*fix; do cp -R "$d" "$dst/" 2>/dev/null; done
    mkdir -p "$dst/gomod/lib"
    printf 'module example.com/snap\n\ngo 1.21\n' >"$dst/gomod/go.mod"
    printf 'package main\n\nimport "example.com/snap/lib"\n\nfunc main() {\n\tlib.Hello()\n}\n' >"$dst/gomod/main.go"
    printf 'package lib\n\nfunc Hello() int {\n\treturn 1\n}\n' >"$dst/gomod/lib/lib.go"
    age "$dst"
}
# Out of the racy window (warmsnap.h kRacySlackNs): mtimes back-dated, and two seconds for the ctimes a copy or an edit
# just set, which no touch can back-date. A run inside the window records the MODEL and GRAPH (keyed on content) but
# not the crawl's signatures, and the model is loaded only behind a replayed crawl, so the next call is served from
# the graph alone; the arms below measure the case past the window.
age(){ find "$1" -exec touch -h -t 202001010000 {} + 2>/dev/null; sleep 2.2; }

# A cache directory of its own per arm group: `use DIR` points TMPDIR (the ladder's first rung) at it.
use(){ CD="$TMP/cache/$1"; mkdir -p "$CD"; }
# run ROOT OUT [args...] — one auto-cached run in $CD; stdout OUT, stderr OUT.err, the stats line OUT.stats
run()
{
    local root="$1" out="$2"; shift 2
    ( cd "$root" && env TMPDIR="$CD/" RIPWIRE_CACHE_STATS=1 RIPWIRE_SNAPSHOT_STATS=1 ${RUNENV:-} "$BIN" . "$@" >"$out" 2>"$out.err" </dev/null ) || no "run ${out##*/}: exit $?"
    grep '^ripwire: snapshot-stats ' "$out.err" >"$out.stats" || : >"$out.stats"
}
# full ROOT OUT [args...] — the reference: no cache, every stage built
full(){ local root="$1" out="$2"; shift 2; ( cd "$root" && env ${RUNENV:-} "$BIN" . --no-cache "$@" >"$out" 2>/dev/null </dev/null ) || no "full ${out##*/}: exit $?"; }
has(){ grep -q -- "$2" "$1.stats"; }
served(){ has "$1" 'model=loaded' && has "$1" 'graph=loaded'; }
st(){ sed 's/^ripwire: snapshot-stats //' "$1.stats" 2>/dev/null; [ -s "$1.stats" ] || printf 'no snapshot-stats line'; }
same()
{
    if [ ! -s "$3" ]; then no "$1 — the reference run printed nothing"; return; fi
    if cmp -s "$2" "$3"; then ok "$1"; else no "$1 — differs from --no-cache ($( cmp "$2" "$3" 2>&1 | head -1 ))"; fi
}
# expect LABEL OUT PATTERN — the stats line carries PATTERN
expect(){ if has "$2" "$3"; then ok "$1 ($( st "$2" ))"; else no "$1 — expected '$3': $( st "$2" )"; fi; }
snaps(){ find "$CD" -type f -name 'ripwire-warmsnap-*.bin' 2>/dev/null; }
onesnap(){ local n; n="$( snaps | wc -l | tr -d ' ' )"; [ "$n" = 1 ] && snaps || { echo ""; }; }

# hdr FILE CMD [ARG] — the v12 header, read and patched from outside (no format code is shared with the binary):
#   span I        -> "offset length" of section I (0 TREE, 1 MODEL, 2 GRAPH)
#   flip OFFSET   -> flip one byte at OFFSET, in place
#   setu32 OFF V  -> write u32 V at OFF, re-stamping the header digest (depwatch::digest64 over the first 128 bytes)
#   setu64 OFF V  -> the same for a u64
hdr()
{
    python3 -I - "$@" <<'PYHDR'
import struct, sys
M = ( 1 << 64 ) - 1
A, B = 0x9e3779b97f4a7c15, 0xc2b2ae3d27d4eb4f
def mix( h, w ):
    h ^= ( w * B ) & M
    r = ( ( ( h & ( M >> 31 ) ) << 31 ) | ( h >> 33 ) ) & M
    return ( r * A ) & M
def digest64( b ):
    lane = [ 0x243753c19f0a1b63, 0x8f1bbcdcca62c1d6, 0x5be0cd19137e2179, 0x1f83d9abfb41bd6b ]
    p, n = 0, len( b )
    while n >= 32:
        for i in range( 4 ): lane[ i ] = mix( lane[ i ], struct.unpack_from( '<Q', b, p + 8 * i )[ 0 ] )
        p += 32; n -= 32
    h = ( len( b ) * A ) & M
    for i in range( 4 ): h = mix( h, lane[ i ] )
    while n >= 8:
        h = mix( h, struct.unpack_from( '<Q', b, p )[ 0 ] ); p += 8; n -= 8
    tail = 0
    for i in range( n ): tail |= b[ p + i ] << ( 8 * i )
    h = mix( h, tail ^ ( n << 56 ) )
    h ^= h >> 29; h = ( h * B ) & M; h ^= h >> 32
    return h
path, cmd = sys.argv[ 1 ], sys.argv[ 2 ]
b = bytearray( open( path, 'rb' ).read() )
HEAD = 56 + 3 * 24
if cmd == 'span':
    i = int( sys.argv[ 3 ] ); o, n = struct.unpack_from( '<QQ', b, 56 + 24 * i ); print( o, n ); raise SystemExit( 0 )
if cmd == 'flip':
    at = int( sys.argv[ 3 ] ); b[ at ] = ( b[ at ] + 1 ) % 256
elif cmd in ( 'setu32', 'setu64' ):
    off, v = int( sys.argv[ 3 ] ), int( sys.argv[ 4 ], 0 )
    struct.pack_into( '<I' if cmd == 'setu32' else '<Q', b, off, v )
    struct.pack_into( '<Q', b, HEAD, digest64( bytes( b[ : HEAD ] ) ) )
open( path, 'wb' ).write( b )
PYHDR
}

W="$TMP/w"; mkcorpus "$W"
full "$W" "$TMP/map.full"; full "$W" "$TMP/for.full" --for="$FOR"

# ── R1: record-first, both orders ───────────────────────────────────────────────────────────────────
servedCalls=0
order()
{
    local tag="$1" first="$2" second="$3"
    use "r1$tag"
    for v in "$first" "$second"; do
        local a=(); [ "$v" = for ] && a=( --for="$FOR" )
        for k in 1 2 3; do run "$W" "$TMP/r1$tag.$v.$k" ${a[@]+"${a[@]}"}; done
        if has "$TMP/r1$tag.$v.1" 'saved=1'; then ok "R1 ($tag) $v call 1 recorded the snapshot ($( st "$TMP/r1$tag.$v.1" ))"
        else no "R1 ($tag) $v call 1 did not record: $( st "$TMP/r1$tag.$v.1" )"; fi
        for k in 2 3; do
            if served "$TMP/r1$tag.$v.$k"; then servedCalls=$(( servedCalls + 1 )); ok "R1 ($tag) $v call $k served ($( st "$TMP/r1$tag.$v.$k" ))"
            else no "R1 ($tag) $v call $k was not served: $( st "$TMP/r1$tag.$v.$k" )"; fi
            same "R1 ($tag) $v call $k == call 1" "$TMP/r1$tag.$v.$k" "$TMP/r1$tag.$v.1"
        done
        same "R1 ($tag) $v call 1 == --no-cache" "$TMP/r1$tag.$v.1" "$TMP/$v.full"
    done
    if grep -q 'cache-stats reparsed=0 ' "$TMP/r1$tag.$second.1.err"; then ok "R1 ($tag) $second after $first re-parsed nothing (one parse blob)"
    else no "R1 ($tag) $second after $first re-parsed: $( grep -o 'cache-stats reparsed=[0-9]*' "$TMP/r1$tag.$second.1.err" )"; fi
}
order a map for
order b for map
if [ "$servedCalls" -ge 8 ]; then
    ok "R1 premise: $servedCalls of 8 second/third calls were served"
else
    no "R1 premise: only $servedCalls of 8 second/third calls were served"
fi

# ── R2: the kill switches ───────────────────────────────────────────────────────────────────────────
use r2a
W2="$TMP/w2"; mkcorpus "$W2"
for k in 1 2; do RUNENV=RIPWIRE_NO_RECORD_FIRST=1 run "$W2" "$TMP/r2a.p$k"; done   # a cold call 1 records under either rule (#794)
if served "$TMP/r2a.p2"; then ok "R2 RIPWIRE_NO_RECORD_FIRST=1 premise: after a cold call 1, call 2 is served (#794's rule) ($( st "$TMP/r2a.p2" ))"
else no "R2 RIPWIRE_NO_RECORD_FIRST=1 premise: call 2 after a cold call 1 was not served: $( st "$TMP/r2a.p2" )"; fi
printf 'package lib\n\nfunc Hello() int {\n\treturn 7\n}\n' >"$W2/gomod/lib/lib.go"
sleep 2.2                                          # past the racy window, so only the edit rule can hold a section back
for k in 1 2 3; do RUNENV=RIPWIRE_NO_RECORD_FIRST=1 run "$W2" "$TMP/r2a.$k"; done
RUNENV=RIPWIRE_NO_RECORD_FIRST=1 full "$W2" "$TMP/r2a.full"
if grep -q 'cache-stats reparsed=[1-9]' "$TMP/r2a.1.err" && has "$TMP/r2a.1" 'unsaved_why=reparsed'; then ok "R2 RIPWIRE_NO_RECORD_FIRST=1: the run after the edit re-parsed and held its model and graph back ($( st "$TMP/r2a.1" ))"
else no "R2 RIPWIRE_NO_RECORD_FIRST=1: the run after the edit did not re-parse or did not hold back: $( grep -o 'cache-stats reparsed=[0-9]*' "$TMP/r2a.1.err" ) $( st "$TMP/r2a.1" )"; fi
if ! served "$TMP/r2a.2" && [ -s "$TMP/r2a.2.stats" ]; then ok "R2 RIPWIRE_NO_RECORD_FIRST=1: call 2 after the edit is built, as before ($( st "$TMP/r2a.2" ))"
else no "R2 RIPWIRE_NO_RECORD_FIRST=1: call 2 after the edit was served or printed no line: $( st "$TMP/r2a.2" )"; fi
if served "$TMP/r2a.3"; then ok "R2 RIPWIRE_NO_RECORD_FIRST=1: call 3 after the edit is served ($( st "$TMP/r2a.3" ))"; else no "R2 RIPWIRE_NO_RECORD_FIRST=1: call 3 not served: $( st "$TMP/r2a.3" )"; fi
for k in 1 2 3; do same "R2 RIPWIRE_NO_RECORD_FIRST=1 call $k after the edit == --no-cache" "$TMP/r2a.$k" "$TMP/r2a.full"; done
use r2b
for k in 1 2; do RUNENV=RIPWIRE_NO_WARMSNAP=1 run "$W" "$TMP/r2b.$k"; done
if ! grep -q -E 'model=loaded|graph=loaded' "$TMP/r2b.2.stats"; then ok "R2 RIPWIRE_NO_WARMSNAP=1: nothing served ($( st "$TMP/r2b.2" ))"; else no "R2 RIPWIRE_NO_WARMSNAP=1 served: $( st "$TMP/r2b.2" )"; fi
for k in 1 2; do same "R2 RIPWIRE_NO_WARMSNAP=1 call $k == --no-cache" "$TMP/r2b.$k" "$TMP/map.full"; done

# ── R3: invalidation ────────────────────────────────────────────────────────────────────────────────
# arm LABEL WHY ROOT [args...] — from a served state of ROOT under the same args: the caller has already changed one
# input; the next run must show WHY, answer == --no-cache, and the run after it must be served again.
arm()
{
    local label="$1" why="$2" root="$3"; shift 3
    local o="$TMP/r3.$( printf '%s' "$label" | tr -c 'a-z0-9' '_' )"
    sleep 2.2                                     # the change's ctime leaves the racy window (age, above)
    run "$root" "$o.1" "$@"; full "$root" "$o.full" "$@"
    expect "R3 $label: $why" "$o.1" "$why"
    same   "R3 $label: the answer == --no-cache" "$o.1" "$o.full"
    run "$root" "$o.2" "$@"
    if served "$o.2"; then ok "R3 $label: the NEXT call is served ($( st "$o.2" ))"; else no "R3 $label: the next call was not served: $( st "$o.2" )"; fi
    same   "R3 $label: the served answer == --no-cache" "$o.2" "$o.full"
}
prime(){ run "$1" "$TMP/prime.1" "${@:2}"; run "$1" "$TMP/prime.2" "${@:2}"; served "$TMP/prime.2" || no "R3 VACUOUS: the tree was not served before the change ($( st "$TMP/prime.2" ))"; }
W3="$TMP/w3"; mkcorpus "$W3"; use r3
prime "$W3"
printf 'package lib\n\nfunc Hello() int {\n\treturn 2\n}\n' >"$W3/gomod/lib/lib.go"
arm "edit one file" 'why=tree-moved' "$W3"
touch "$W3/gomod/main.go"
arm "touch one file (no content change)" 'why=tree-moved' "$W3"
printf 'package lib\n\nfunc Added() int {\n\treturn 3\n}\n' >"$W3/gomod/lib/added.go"
arm "add a file" 'why=tree-moved' "$W3"
rm -f "$W3/gomod/lib/added.go"
arm "remove a file" 'why=tree-moved' "$W3"
mv "$W3/gomod/lib/lib.go" "$W3/gomod/lib/lib2.go"
arm "rename a file" 'why=tree-moved' "$W3"
use r3f; prime "$W3"
for flag in --exclude=gomod --max-file-size=2000 --ignore-tests --no-ignore; do arm "flag $flag" 'why=absent' "$W3" "$flag"; done
RUNENV=RIPWIRE_NO_DOC_MENTION=1 arm "env RIPWIRE_NO_DOC_MENTION=1" 'why=absent' "$W3"
use r3d; prime "$W3"
printf 'module example.com/snap\n\ngo 1.22\n' >"$W3/gomod/go.mod"
arm "go.mod changed (a read outside the crawl)" 'graph_why=dep' "$W3"
use r3v; prime "$W3"
S="$( onesnap )"
if [ -n "$S" ]; then hdr "$S" setu32 8 6; arm "a version-6 snapshot (old format)" 'why=version' "$W3"
else no "R3 version: VACUOUS — not exactly one snapshot in $CD"; fi
use r3p; prime "$W3"
S="$( onesnap )"
if [ -n "$S" ]; then hdr "$S" setu64 16 0x1234; arm "another producer (header digest re-stamped)" 'why=producer' "$W3"
else no "R3 producer: VACUOUS — not exactly one snapshot in $CD"; fi
# a git checkout: the crawl asks git which paths are ignored, so the TREE section keeps git's inputs
G="$TMP/g"; mkcorpus "$G"; use r3git
if ( cd "$G" && git init -q && git add -A && git -c user.name=t -c user.email=t@t commit -q -m one ) 2>/dev/null; then
    age "$G"; prime "$G"
    ( cd "$G" && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m two )
    # git's inputs moved (HEAD and its log), so the crawl is walked again; the model and graph are keyed on content and
    # the graph is still served. A git-keyed section of its own (STAMP) is a later stage of #729.
    arm "git commit, no file changed" 'why=git-moved' "$G"
    expect "R3 git commit, no file changed: the graph is still served" "$TMP/r3.git_commit__no_file_changed.1" 'graph=loaded'
    ( cd "$G" && git config core.excludesFile "$TMP/none.ignore" )
    arm "git config changed" 'why=git-moved' "$G"
else
    no "R3 git: could not make a git checkout to test"
fi

# ── R4: corruption, one section at a time ───────────────────────────────────────────────────────────
W4="$TMP/w4"; mkcorpus "$W4"
names=( TREE MODEL GRAPH ); wants=( 'why=checksum' 'model_why=checksum' 'graph_why=checksum' )
for i in 0 1 2; do
    use "r4$i"; prime "$W4"
    S="$( onesnap )"
    [ -n "$S" ] || { no "R4 ${names[$i]}: VACUOUS — not exactly one snapshot"; continue; }
    read -r off len <<<"$( hdr "$S" span $i )"
    if [ "${len:-0}" -gt 0 ]; then
        hdr "$S" flip $(( off + len / 2 ))
        run "$W4" "$TMP/r4.$i"
        expect "R4 a byte flipped in ${names[$i]}: ${wants[$i]}" "$TMP/r4.$i" "${wants[$i]}"
        same   "R4 a byte flipped in ${names[$i]}: the answer == --no-cache" "$TMP/r4.$i" "$TMP/map.full"
        case $i in
            0) expect "R4 ...TREE refused: the crawl walked" "$TMP/r4.$i" 'tree=walked'
               expect "R4 ...and the intact GRAPH was still served" "$TMP/r4.$i" 'graph=loaded' ;;
            1) expect "R4 ...MODEL refused: the crawl was still replayed" "$TMP/r4.$i" 'tree=replayed'
               expect "R4 ...and the intact GRAPH was still served" "$TMP/r4.$i" 'graph=loaded' ;;
            2) expect "R4 ...GRAPH refused: the intact MODEL was still served" "$TMP/r4.$i" 'model=loaded' ;;
        esac
        run "$W4" "$TMP/r4.$i.next"
        if served "$TMP/r4.$i.next"; then ok "R4 ${names[$i]}: the next call is served again"; else no "R4 ${names[$i]}: not healed: $( st "$TMP/r4.$i.next" )"; fi
    else
        no "R4 ${names[$i]}: VACUOUS — the section is empty"
    fi
done
use r4h; prime "$W4"; S="$( onesnap )"
if [ -n "$S" ]; then
    hdr "$S" flip 44
    run "$W4" "$TMP/r4.h"
    expect "R4 a byte flipped in the header refuses the file: why=checksum" "$TMP/r4.h" 'why=checksum'
    same   "R4 header: the answer == --no-cache" "$TMP/r4.h" "$TMP/map.full"
else no "R4 header: VACUOUS — not exactly one snapshot"; fi

# ── R5: truncation ──────────────────────────────────────────────────────────────────────────────────
use r5; prime "$W4"; S="$( onesnap )"
if [ -n "$S" ]; then
    read -r off len <<<"$( hdr "$S" span 2 )"
    python3 -I -c 'import sys; p = sys.argv[ 1 ]; b = open( p, "rb" ).read(); open( p, "wb" ).write( b[ : int( sys.argv[ 2 ] ) ] )' "$S" $(( off + len / 2 ))
    run "$W4" "$TMP/r5"
    expect "R5 a snapshot cut inside GRAPH is refused whole: why=checksum" "$TMP/r5" 'why=checksum'
    expect "R5 ...nothing of it is used: the crawl walked" "$TMP/r5" 'tree=walked'
    same   "R5 the answer == --no-cache" "$TMP/r5" "$TMP/map.full"
else no "R5: VACUOUS — not exactly one snapshot"; fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
