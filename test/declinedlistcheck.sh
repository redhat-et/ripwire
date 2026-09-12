#!/usr/bin/env bash
# declinedlistcheck.sh — declined_calls= stays exact when the resolver SHARES the declined calls' candidate lists.
#
#   test/declinedlistcheck.sh                          # uses build/ripwire on a fixture written to a temp dir
#   RIPWIRE_BIN=asan/ripwire test/declinedlistcheck.sh
#   test/declinedlistcheck.sh build_base/ripwire       # any other binary, positional
#
# THE STRUCTURE. A tier-3 decline (test/declinecheck.sh) records the candidate definitions the call could equally have
# meant, and declinedCallsNaming (src/graph.h) counts, for one callers or impact answer, the declined CALLS whose candidates
# include one of the answer's symbols. One stored list per call grew super-linearly with the tree: 27.9 M entries for
# 715,735 declined calls on a sparse llvm-project tree that holds only 9,879 DISTINCT lists. So each distinct list is stored
# once (src/graph.h internDeclinedList), beside the number of calls that named it.
#
# WHAT THIS GATE PINS: the sharing key is the list's CONTENT, never the called NAME. One name routinely owns several distinct
# lists — the language filter splits `size` into its C++ and its Python definitions, the root filter splits `foo` per
# workspace root — and a by-name share hands one list's calls to the other list's definitions. Each (A) and (C) definition
# row reads a value a by-name share gets wrong; the bare-name rows are controls both designs get right.
#   (A) one root: `size` twice in C++ (a/, b/) and twice in Python (c/, d/), one declining C++ caller (e/) and one
#       declining Python caller (f/). --impact and --callers on each definition read declined_calls="1" — a by-name share
#       reads 2 on the first-seen list's definitions and nothing on the other's; the bare name (defs="4") reads 2 either
#       way; --json and the MCP twins (impact, find_referencing_symbols) carry the same count
#   (B) one list, two calls: `twin` in a/ and b/, called from g/ and h/ — declined_calls="2" on each definition, so a list
#       keeps its CALL count (counting lists instead of calls reads 1)
#   (C) two roots, each defining `foo` twice with one declining caller: --callers=r1/x.cpp:foo reads 1 (a by-name share
#       reads 2), r2's definition reads 1, the bare name reads 2
#   (D) the predicate rejects the by-name reading
#   (E) determinism x2, xmllint, no degrade alert on stderr
#
# RED FIRST. main was already exact (one list per call), so the red run is a MUTATION: keying internDeclinedList by the
# called name instead of the list content turns the (A) and (C) definition rows red while the bare-name controls stay green.
#
# Exits non-zero on any failure.

set -u
export PYTHONDONTWRITEBYTECODE=1
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative binary
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "declinedlistcheck: BIN=$BIN"

# ── the fixture ───────────────────────────────────────────────────────────────────────────────────────────────
ONE="$TMP/one"; WS="$TMP/ws"
mkdir -p "$ONE"/a "$ONE"/b "$ONE"/c "$ONE"/d "$ONE"/e "$ONE"/f "$ONE"/g "$ONE"/h "$WS"/r1/y "$WS"/r1/z "$WS"/r2/y "$WS"/r2/z || exit 2
cfn(){ printf 'int %s()\n{\n    return %s;\n}\n' "$1" "$2"; }                  # a C++ function returning $2
pyfn(){ printf 'def %s():\n    return %s\n' "$1" "$2"; }                       # the Python twin
cfn size 1 >"$ONE/a/size.cpp";   cfn size 2 >"$ONE/b/size.cpp"
pyfn size 3 >"$ONE/c/size.py";   pyfn size 4 >"$ONE/d/size.py"
cfn e_call 'size()' >"$ONE/e/caller.cpp"
pyfn f_call 'size()' >"$ONE/f/caller.py"
cfn twin 1 >"$ONE/a/twin.cpp";   cfn twin 2 >"$ONE/b/twin.cpp"
cfn g_call 'twin()' >"$ONE/g/caller.cpp"
cfn h_call 'twin()' >"$ONE/h/caller.cpp"
for r in r1 r2; do
    cfn foo 1 >"$WS/$r/x.cpp";   cfn foo 2 >"$WS/$r/y/foo.cpp"
    cfn "${r}_call" 'foo()' >"$WS/$r/z/caller.cpp"
done

# ── helpers ───────────────────────────────────────────────────────────────────────────────────────────────────
root_tag(){ grep -oE "<$2( [^>]*)?>" "$1" | head -1; }                               # first <TAG …> start tag
attr(){ printf '%s' "$1" | grep -oE " $2=\"[^\"]*\"" | head -1 | sed -E 's/^[^"]*"([^"]*)"$/\1/'; }
stats(){ grep -oE '<!-- files=[^>]*-->' "$1" | head -1; }                             # the map's STATS comment only
gauge(){ printf '%s' "$1" | grep -oE " $2=[0-9]+" | head -1 | grep -oE '[0-9]+$'; }   # "" when absent
# the answer predicate every row uses: the root's declined_calls= equals the expected count ("" = the key is absent)
declined_is(){ [ "$( attr "$1" declined_calls )" = "$2" ]; }
mcp_text(){
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$1" \
        | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c '
import sys, json
r = json.load( sys.stdin )
print( "__ERROR__:" + r[ "error" ].get( "message", "" ) if "error" in r else r[ "result" ][ "content" ][ 0 ][ "text" ] )
'
}
call(){ printf '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"%s","arguments":%s}}' "$1" "$2"; }

cd "$ONE" || exit 2                                   # every file:name selector in (A) and (B) is relative to the root `.`
rw(){ "$BIN" . --no-cache "$@" 2>>"$TMP/err"; }
rw >"$TMP/map.xml" || no "the map run exited non-zero"
HDR="$( stats "$TMP/map.xml" )"
[ "$( gauge "$HDR" declined )" = 4 ] && [ "$( gauge "$HDR" edges )" = 0 ] \
    && ok "premise: header declined=4 edges=0 — the two size calls and the two twin calls all decline" \
    || no "premise: the fixture no longer declines exactly its four calls, so the rows below prove nothing: ${HDR:-no stats comment}"

# ── (A) one name, two distinct lists ──────────────────────────────────────────────────────────────────────────
echo "=== (A) one name, two distinct candidate lists: each definition counts only its own list's calls ==="
# verb | selector | declined_calls | what a by-name share reads
while IFS='|' read -r verb sel want wrong; do
    [ -z "$verb" ] && continue
    rw --"$verb"="$sel" >"$TMP/a.xml"
    R="$( root_tag "$TMP/a.xml" "$verb" )"
    [ -n "$R" ] && declined_is "$R" "$want" \
        && ok "(A) --$verb=$sel declined_calls=\"$want\" (a by-name share reads ${wrong:-nothing})" \
        || no "(A) --$verb=$sel should read declined_calls=\"$want\": ${R:-no <$verb> root}"
done <<'EOF'
impact|a/size.cpp:size|1|2
impact|b/size.cpp:size|1|2
impact|c/size.py:size|1|
impact|d/size.py:size|1|
callers|a/size.cpp:size|1|2
callers|c/size.py:size|1|
callers|size|2|2
EOF
R="$( rw --callers=size >"$TMP/bare.xml"; root_tag "$TMP/bare.xml" callers )"
[ "$( attr "$R" defs )" = 4 ] && ok "(A) control premise: --callers=size unions all four definitions (defs=\"4\")" \
    || no "(A) control premise: --callers=size should read defs=\"4\": ${R:-no <callers> root}"
rw --impact=a/size.cpp:size --json >"$TMP/a.json"
grep -q '"declined_calls":1[,}]' "$TMP/a.json" && ok "(A) --impact=a/size.cpp:size --json carries \"declined_calls\":1" \
    || no "(A) --impact=a/size.cpp:size --json: $( head -c 240 "$TMP/a.json" )"
rw --callers=c/size.py:size --json >"$TMP/c.json"
grep -q '"declined_calls":1[,}]' "$TMP/c.json" && ok "(A) --callers=c/size.py:size --json carries \"declined_calls\":1" \
    || no "(A) --callers=c/size.py:size --json: $( head -c 240 "$TMP/c.json" )"
M="$( mcp_text "$( call impact '{"path":"'"$ONE"'","symbol":"a/size.cpp:size","legend":"full"}' )" )"
printf '%s' "$M" | grep -oE '<impact [^>]*>' | head -1 | grep -q ' declined_calls="1"' \
    && ok "(A) MCP impact a/size.cpp:size root declined_calls=\"1\"" \
    || no "(A) MCP impact a/size.cpp:size: $( printf '%s' "$M" | grep -oE '<impact [^>]*>' | head -1 || echo no root )"
M="$( mcp_text "$( call find_referencing_symbols '{"path":"'"$ONE"'","symbol":"c/size.py:size"}' )" )"
printf '%s' "$M" | grep -q '"declined_calls":1[,}]' && ok "(A) MCP find_referencing_symbols c/size.py:size carries \"declined_calls\":1" \
    || no "(A) MCP find_referencing_symbols c/size.py:size: $( printf '%s' "$M" | head -c 240 )"

# ── (B) one list, two calls ───────────────────────────────────────────────────────────────────────────────────
echo "=== (B) one distinct list named by two calls keeps its call count ==="
for sel in a/twin.cpp:twin b/twin.cpp:twin; do
    for verb in callers impact; do
        rw --"$verb"="$sel" >"$TMP/b.xml"
        R="$( root_tag "$TMP/b.xml" "$verb" )"
        [ -n "$R" ] && declined_is "$R" 2 \
            && ok "(B) --$verb=$sel declined_calls=\"2\" — two calls, one shared list" \
            || no "(B) --$verb=$sel should read declined_calls=\"2\" (1 counts lists, not calls): ${R:-no <$verb> root}"
    done
done

# ── (C) two roots ─────────────────────────────────────────────────────────────────────────────────────────────
echo "=== (C) two roots: the root filter splits one name into one list per root ==="
cd "$WS" || exit 2
"$BIN" r1 r2 --no-cache >"$TMP/ws.xml" 2>>"$TMP/err"
WHDR="$( stats "$TMP/ws.xml" )"
[ "$( gauge "$WHDR" declined )" = 2 ] && [ "$( gauge "$WHDR" roots )" = 2 ] \
    && ok "(C) premise: two roots, header declined=2" \
    || no "(C) premise: the two-root run should read roots=2 declined=2: ${WHDR:-no stats comment}"
# selector | declined_calls | what a by-name share reads
while IFS='|' read -r sel want wrong; do
    [ -z "$sel" ] && continue
    "$BIN" r1 r2 --no-cache --callers="$sel" >"$TMP/w.xml" 2>>"$TMP/err"
    R="$( root_tag "$TMP/w.xml" callers )"
    [ -n "$R" ] && declined_is "$R" "$want" \
        && ok "(C) --callers=$sel declined_calls=\"$want\" (a by-name share reads ${wrong:-nothing})" \
        || no "(C) --callers=$sel should read declined_calls=\"$want\": ${R:-no <callers> root}"
done <<'EOF'
r1/x.cpp:foo|1|2
r2/x.cpp:foo|1|
foo|2|2
EOF
cd "$ONE" || exit 2

# ── (D) the predicate can fail ────────────────────────────────────────────────────────────────────────────────
echo "=== (D) mutation — the answer predicate rejects the by-name reading ==="
R='<impact of="a/size.cpp:size" defs="1" reaches="0" declined_calls="2" root="." counts_floor="1">'
declined_is "$R" 1 && no "(D) the predicate accepts declined_calls=\"2\" where 1 is expected" \
    || ok "(D) a by-name declined_calls=\"2\" IS rejected"
R='<callers of="c/size.py:size" defs="1" count="0" root="." counts_floor="1">'
declined_is "$R" 1 && no "(D) the predicate accepts an answer with no declined_calls= at all" \
    || ok "(D) a by-name answer that lost its declined_calls= IS rejected"

# ── (E) determinism, well-formedness, no degrade alert ────────────────────────────────────────────────────────
echo "=== (E) determinism + well-formedness ==="
rw >"$TMP/map2.xml"
rw --impact=a/size.cpp:size >"$TMP/i1.xml"; rw --impact=a/size.cpp:size >"$TMP/i2.xml"
cmp -s "$TMP/map.xml" "$TMP/map2.xml" && cmp -s "$TMP/i1.xml" "$TMP/i2.xml" && ok "(E) map + impact answer byte-identical across two runs" \
    || no "(E) map or impact answer differs between two runs"
if command -v xmllint >/dev/null 2>&1; then
    for f in map.xml i1.xml ws.xml w.xml b.xml; do
        if xmllint --noout "$TMP/$f" 2>/dev/null; then ok "(E) xmllint clean: $f"; else no "(E) xmllint rejected $f"; fi
    done
fi
grep -qi 'degrad' "$TMP/err" && no "(E) a run raised a degrade alert: $( grep -i 'degrad' "$TMP/err" | head -1 )" \
    || ok "(E) no degrade alert on stderr"

[ "$fail" = 0 ] && echo "declinedlistcheck: PASS" || echo "declinedlistcheck: FAIL"
exit "$fail"
