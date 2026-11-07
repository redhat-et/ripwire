#!/usr/bin/env bash
# forstampprefetchcheck.sh — FOR-TRANSIENTS: --for's at= stamp is prefetched beside the graph build (gitstamp.h
# startStampPrefetch, HEAD + shallow probe folded into one git child) and findClones reads/normalizes files on workers.
# Both are speed changes; this gate pins that neither moves a byte:
#   (A) clean / tracked edit / untracked file / shallow clone / unborn HEAD: --for's at= equals --doctor's (the
#       un-prefetched stampAt) and the expected value (SHA9, +dirty, +shallow, omitted).
#   (B) a cache file the ingest writes INSIDE the tree still makes --for's stamp +dirty (the prefetch starts after
#       the ingest; a prefetch started before it reads the tree clean — the stale-stamp mutant).
#   (C) a failing git (every call exits 1) and a stalling git (each call waits, then answers): --for exits 0, the
#       stamp is omitted / identical to the unstalled one.
#   (D) the MCP server never prefetches: in ONE session, a commit between two calls moves the stamp.
#   (E) findClones' fan-out keeps the serial member order: --clones lists a 3-file clone group in file order, and
#       a 40-file fixture's --clones output is identical across runs and to its single-file-at-a-time twin order.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "forstampprefetchcheck: SKIP all arms — git unavailable"; exit 0; }
REALGIT="$( command -v git )"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "forstampprefetchcheck: BIN=$BIN"

export GIT_AUTHOR_NAME=ripwire GIT_AUTHOR_EMAIL=ripwire@example.invalid
export GIT_COMMITTER_NAME=ripwire GIT_COMMITTER_EMAIL=ripwire@example.invalid
export GIT_CONFIG_NOSYSTEM=1

# at= value of the root element of a document ("" when omitted). Exit status of the run is checked by the caller.
atOf(){ printf '%s' "$1" | head -c 4000 | grep -o ' at="[^"]*"' | head -1 | sed 's/^ at="//; s/"$//'; }

mkrepo(){   # mkrepo DIR — one commit holding a small C++ file
    mkdir -p "$1/src"
    cat > "$1/src/code.cpp" <<'EOF'
int classify( int a )
{
    if( a > 0 ) { return 1; }
    else if( a < 0 ) { return -1; }
    return 0;
}
int caller( int b ) { return classify( b ); }
EOF
    git -C "$1" init -q -b main && git -C "$1" config commit.gpgsign false && git -C "$1" add -A && git -C "$1" commit -q -m base
}

# runFor DIR [extra args]: --for on DIR, cwd = DIR, private cache dir; sets OUT and RC
runFor(){ local d="$1"; shift; OUT="$( cd "$d" && "$BIN" "$d" --for=classify --cache="$TMP/c.$RANDOM" "$@" 2>"$TMP/err" )"; RC=$?; }
doctorAt(){ local o; o="$( cd "$1" && "$BIN" "$1" --doctor --no-cache 2>/dev/null )"; atOf "$o"; }

# ── (A) the stamp's shapes, --for vs --doctor ───────────────────────────────────────────────────────────
R="$TMP/repo"; mkrepo "$R"
SHA9="$( git -C "$R" rev-parse --short=9 HEAD )"
[ "${#SHA9}" = 9 ] || { echo "forstampprefetchcheck: could not derive a 9-char sha"; exit 2; }
checkShape(){   # checkShape DESC DIR EXPECTED
    runFor "$2"
    [ "$RC" -eq 0 ] || { no "$1: --for exited $RC"; return; }
    [ -n "$OUT" ] || { no "$1: --for printed nothing"; return; }
    local got doc; got="$( atOf "$OUT" )"; doc="$( doctorAt "$2" )"
    if [ "$got" = "$3" ] && [ "$got" = "$doc" ]; then ok "$1: --for at=\"$got\" (= --doctor's)"; else no "$1: --for at=\"$got\", --doctor at=\"$doc\", expected \"$3\""; fi
}
checkShape "clean tree" "$R" "$SHA9"
echo "// edit" >> "$R/src/code.cpp"
checkShape "tracked edit" "$R" "$SHA9+dirty"
git -C "$R" checkout -q -- src/code.cpp
echo "x" > "$R/untracked.txt"
checkShape "untracked file" "$R" "$SHA9+dirty"
rm -f "$R/untracked.txt"
checkShape "clean again" "$R" "$SHA9"

SH="$TMP/shallow"; git clone -q --depth=1 "file://$R" "$SH" 2>/dev/null
echo "// two" >> "$R/src/code.cpp"; git -C "$R" commit -q -am two
SH2="$TMP/shallow2"; git clone -q --depth=1 "file://$R" "$SH2" 2>/dev/null
if [ -f "$SH2/.git/shallow" ]; then
    checkShape "shallow clone" "$SH2" "$( git -C "$SH2" rev-parse --short=9 HEAD )+shallow"
else
    no "shallow clone fixture: git clone --depth=1 made no .git/shallow"
fi
UB="$TMP/unborn"; mkdir -p "$UB/src"; cp "$R/src/code.cpp" "$UB/src/"; git -C "$UB" init -q -b main
checkShape "unborn HEAD (stamp omitted)" "$UB" ""

# ── (B) a cache file the ingest writes inside the tree ──────────────────────────────────────────────────
C="$TMP/cacherepo"; mkrepo "$C"; CSHA9="$( git -C "$C" rev-parse --short=9 HEAD )"
OUT="$( cd "$C" && "$BIN" "$C" --for=classify --cache="$C/.rwcache" 2>/dev/null )"; RC=$?
if [ "$RC" -eq 0 ] && [ -f "$C/.rwcache" ] && [ "$( atOf "$OUT" )" = "$CSHA9+dirty" ]; then
    ok "cold --for with an in-tree cache: the file the ingest wrote counts (at=\"$CSHA9+dirty\")"
else
    no "cold --for with an in-tree cache: rc=$RC cache=$( [ -f "$C/.rwcache" ] && echo written || echo absent ) at=\"$( atOf "$OUT" )\", expected \"$CSHA9+dirty\" (a stamp read before the ingest is stale)"
fi

# ── (C) a failing git and a stalling git ────────────────────────────────────────────────────────────────
FB="$TMP/failbin"; mkdir -p "$FB"
printf '#!/bin/sh\nexit 1\n' > "$FB/git"; chmod +x "$FB/git"
OUT="$( cd "$R" && PATH="$FB:$PATH" "$BIN" "$R" --for=classify --no-cache 2>/dev/null )"; RC=$?
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'n="classify"' && [ -z "$( atOf "$OUT" )" ]; then
    ok "failing git: --for answers, stamp omitted"
else
    no "failing git: rc=$RC at=\"$( atOf "$OUT" )\" (expected rc 0, the symbol, no at=)"
fi
SB="$TMP/stallbin"; mkdir -p "$SB"
printf '#!/bin/sh\nsleep 1\nexec "%s" "$@"\n' "$REALGIT" > "$SB/git"; chmod +x "$SB/git"
runFor "$R" --no-cache; FAST="$OUT"
OUT="$( cd "$R" && PATH="$SB:$PATH" "$BIN" "$R" --for=classify --no-cache 2>/dev/null )"; RC=$?
if [ "$RC" -eq 0 ] && [ -n "$OUT" ] && [ "$OUT" = "$FAST" ] && [ -n "$( atOf "$OUT" )" ]; then
    ok "stalling git: --for answer byte-identical to the unstalled one (at=\"$( atOf "$OUT" )\")"
else
    no "stalling git: rc=$RC, answer differs from the unstalled one or has no at="
fi

# ── (D) MCP never prefetches: a commit between two calls in one session moves the stamp ────────────────
if command -v python3 >/dev/null 2>&1; then
    M="$TMP/mcprepo"; mkrepo "$M"
    MCP_OUT="$( python3 - "$BIN" "$M" <<'PYEOF'
import json, subprocess, sys
binPath, root = sys.argv[1], sys.argv[2]
p = subprocess.Popen( [ binPath, "--mcp" ], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, cwd=root )
def call( method, params ):
    p.stdin.write( json.dumps( { "jsonrpc": "2.0", "id": 1, "method": method, "params": params } ).encode() + b"\n" ); p.stdin.flush()
    return json.loads( p.stdout.readline().decode() )
def at( r ):
    try:
        t = r[ "result" ][ "content" ][ 0 ][ "text" ]
    except Exception:
        return "ERR"
    i = t.find( '"at":"' )
    return t[ i + 6 : t.find( '"', i + 6 ) ] if i >= 0 else "NONE"
call( "initialize", {} )
a = at( call( "tools/call", { "name": "situational_awareness", "arguments": { "path": root } } ) )
call( "tools/call", { "name": "for", "arguments": { "path": root, "task": "classify" } } )
subprocess.run( [ "git", "-C", root, "commit", "-q", "--allow-empty", "-m", "next" ], check=True )
b = at( call( "tools/call", { "name": "situational_awareness", "arguments": { "path": root } } ) )
p.stdin.close(); p.wait()
print( "A=%s B=%s" % ( a, b ) )
PYEOF
)"
    A1="${MCP_OUT#A=}"; A1="${A1%% *}"; B1="${MCP_OUT##*B=}"
    if [ "${#A1}" -ge 9 ] && [ "${#B1}" -ge 9 ] && [ "$A1" != "ERR" ] && [ "$B1" != "ERR" ] && [ "$A1" != "NONE" ] && [ "$A1" != "$B1" ]; then
        ok "MCP: a commit mid-session moves the stamp ($A1 -> $B1)"
    else
        no "MCP: stamp did not move across a mid-session commit ($MCP_OUT)"
    fi
else
    echo "  SKIP  MCP arm — python3 unavailable"
fi

# ── (E) findClones' fan-out keeps the serial member order ──────────────────────────────────────────────
K="$TMP/clones"; mkdir -p "$K"
body='{ int total = 0; for( int i = 0; i < n; ++i ) { if( i % 3 == 0 ) { total += i * 2; } else { total -= i; } } if( total > 100 ) { total = 100; } return total + n * 7 - 1; }'
for f in a b c; do printf 'int sum_%s( int n )\n%s\n' "$f" "$body" > "$K/$f.cpp"; done
for i in $( seq 10 49 ); do printf 'int other_%s( int n )\n{ int v = n; while( v > %s ) { v -= 3; if( v == 7 ) { return v * 2; } } return v + %s * n - 5 + n / 2 + n %% 5 + 11 * v; }\n' "$i" "$i" "$i" > "$K/f$i.cpp"; done
O1="$( "$BIN" "$K" --clones --no-cache 2>/dev/null )"; RC=$?
order="$( printf '%s' "$O1" | grep -o 'sum_[abc]' | tr '\n' ' ' )"
if [ "$RC" -eq 0 ] && [ "$order" = "sum_a sum_b sum_c " ]; then
    ok "--clones: the 3-file group lists its members in file order ($order)"
else
    no "--clones: rc=$RC member order \"$order\", expected \"sum_a sum_b sum_c \""
fi
n40="$( printf '%s' "$O1" | grep -o 'other_[0-9]*' | wc -l | tr -d ' ' )"
seq40="$( printf '%s' "$O1" | grep -o 'other_[0-9]*' | tr '\n' ' ' )"
want40="$( for i in $( seq 10 49 ); do printf 'other_%s ' "$i"; done )"
if [ "$n40" -eq 40 ] && [ "$seq40" = "$want40" ]; then
    ok "--clones: the 40-file group lists all 40 members in file order"
else
    no "--clones: 40-file group has $n40 members, order differs from file order"
fi
O2="$( "$BIN" "$K" --clones --no-cache 2>/dev/null )"
[ -n "$O1" ] && [ "$O1" = "$O2" ] && ok "--clones: two runs byte-identical" || no "--clones: two runs differ (or printed nothing)"

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "FAILURES ABOVE"; exit 1; }
