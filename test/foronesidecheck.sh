#!/usr/bin/env bash
# foronesidecheck.sh — ONE-SIDE-REACH (src/foronesidereach.h): on a --for task that names exactly two endpoints, a printed <sigs> <d>,
# <callers> <s> or <syms> <y> row that reaches only one of them within 3 calls, and is on no shortest path between them, prints in its
# place as a tail pointer <t p= sym= r=/>; the rule is OFF unless some printed row reaches both endpoints.
#
# ONE TypeScript tree, four files:
#   chain.ts  a root/sink chain alpha_start -> alpha_beta_bridge -> beta_finish, a wrapper above the root (alpha_start_wrapper) and a
#             direct caller of the sink (beta_finish_direct)
#   sinks.ts  two sinks with a common caller (sink_left_right_driver), a one-sided caller of the left sink and that caller's caller
#   gamma.ts  two endpoints nothing reaches both of, each with a caller of its own
#   delta.ts  two sinks whose common caller and whose one-sided decoy are each an overload set (two declarations + the implementation,
#             the calls on the implementation only)
# ARMS
#   (a)  root/sink: the answer equals the RIPWIRE_NO_ONE_SIDE_REACH=1 answer with exactly alpha_start_wrapper rewritten as a pointer and
#        the legend comment before it (est_tokens= aside); the chain and the direct caller of the sink stay rows
#   (a2) two sinks: sink_left_only_caller and sink_left_only_outer (2 calls from the left sink) are pointers, the driver a row; the prose
#        wording "How do A and B connect?" demotes the same rows
#   (b)  nothing reaches both endpoints: the rule is off, the answer byte-identical to the rule disabled
#   (c)  overloads: every row of the common caller's overload set (its declarations too) stays a row — the set is on the path; every row
#        of the decoy's overload set is a pointer, its declarations included (a row stands for its implementation)
#   (d)  a single-endpoint task (bare, and as a question) is byte-identical to the rule disabled
#   (e)  est_tokens= is re-priced by the signed byte change (within one token; on this tiny tree the legend outweighs the one row, so it goes up); (w) well formed; (l) one legend comment, no "--" in it
#   (t)  --token-budget leaves the answer as shaped: no pointer, no legend
#   (x)  MCP `for` (one renderer): its answer equals its RIPWIRE_NO_ONE_SIDE_REACH=1 twin with the same rows as pointers, and they are the
#        CLI's pointers
# A SECOND tree (paths.ts, many.ts, same.cpp), so its rows do not move the first tree's answers:
#   (f)  root/sink with TWO shortest 6-call paths: no row of either path is a pointer (path_b4, 4 calls from the root and 2 from the sink
#        on the path shortestPathAny did not pick, was one before), so the answer is byte-identical to the rule disabled
#   (g)  two sinks with 10 common callers (more than the 8 whose paths were once kept): no caller's middle row is a pointer, byte-identical
#   (h)  two C++ members named run on ONE line (SameQ::run reaches the left sink only, SameP::run both): SameQ::run is a pointer and
#        SameP::run a row — each row's scope comes from its own n= qualifier, not from the first `run` at the line
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
# SIBLING-DEMOTE (forsiblingdemote.h) runs after this pass and demotes deep same-file <d> rows past <d> rank 10; the pointers this
# pass prints move those ranks, so its on/off twins would differ in rows that are not this rule's. This gate pins ONE-SIDE-REACH alone;
# SIBLING-DEMOTE's rule is pinned in forsiblingdemotecheck.
export RIPWIRE_NO_SIBLING_DEMOTE=1
export RIPWIRE_NO_DECL_TWIN=1   # DECL-TWIN (fordecltwin.h) runs after it; pinned in fordecltwincheck
unset RIPWIRE_NO_ONE_SIDE_REACH # an inherited value (even 0) would turn the rule off in both twins
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "foronesidecheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME" "$TMP/ts"

cat >"$TMP/ts/chain.ts" <<'EOF'
export function alpha_start(n: number): number {
    return alpha_beta_bridge(n + 1);
}
export function alpha_beta_bridge(n: number): number {
    return beta_finish(n * 2);
}
export function beta_finish(n: number): number {
    return n;
}
export function alpha_start_wrapper(n: number): number {
    return alpha_start(n);
}
export function beta_finish_direct(n: number): number {
    return beta_finish(n);
}
EOF
cat >"$TMP/ts/sinks.ts" <<'EOF'
export function sink_left_value(n: number): number {
    return n;
}
export function sink_right_value(n: number): number {
    return n + 1;
}
export function sink_left_right_driver(n: number): number {
    return sink_left_value(n) + sink_right_value(n);
}
export function sink_left_only_caller(n: number): number {
    return sink_left_value(n);
}
export function sink_left_only_outer(n: number): number {
    return sink_left_only_caller(n);
}
EOF
cat >"$TMP/ts/gamma.ts" <<'EOF'
export function gamma_one_value(n: number): number {
    return n;
}
export function gamma_two_value(n: number): number {
    return n;
}
export function gamma_one_caller(n: number): number {
    return gamma_one_value(n);
}
export function gamma_two_caller(n: number): number {
    return gamma_two_value(n);
}
EOF
cat >"$TMP/ts/delta.ts" <<'EOF'
export function delta_left_value(n: number): number {
    return n;
}
export function delta_right_value(n: number): number {
    return n + 2;
}
export function delta_left_right_driver(n: string): number;
export function delta_left_right_driver(n: number): number;
export function delta_left_right_driver(n: any): number {
    return delta_left_value(n) + delta_right_value(n);
}
export function delta_left_only_caller(n: string): number;
export function delta_left_only_caller(n: number): number;
export function delta_left_only_caller(n: any): number {
    return delta_left_value(n);
}
EOF

# check.py OFF ON NAMES -> PASS/FAIL: ON is OFF with every <d>/<s>/<y> row named in NAMES (in <sigs>/<callers>/<syms>) a pointer, the
# legend before the first, est_tokens= aside; then `ptr`/`rows` lines (the pointer names and the row names of ON, in order).
cat >"$TMP/check.py" <<'PY'
import re, sys
LEG = ( "<!-- one-side: a <t> among sigs, callers or syms rows is one-sided within 3 calls (it reaches only one of the two named endpoints, or "
        "it reaches the sink and the root does not reach it) and is on no shortest path between them, a pointer (p= file, sym= name, r= rank), "
        "not the answer -->" )
ATTR = re.compile( r'([\w:-]+)="([^"]*)"' )
def mask( t ): return re.sub( r"<!--.*?-->|<!\[CDATA\[.*?\]\]>", lambda m: " " * len( m.group( 0 ) ), t, flags = re.S )
def rows( t ):
    m = mask( t ); out = []
    for blk, tag in ( ( "sigs", "d" ), ( "callers", "s" ), ( "syms", "y" ) ):
        for b in re.finditer( r"<%s[ >](.*?)</%s>" % ( blk, blk ), m, re.S ):
            for x in re.finditer( r"<%s ([^>]*?)(/?)>" % tag, m[b.start():b.end()] ):
                s = b.start() + x.start(); e = b.start() + x.end()
                if tag == "d" and not x.group( 2 ): e = m.find( "</d>", e ) + 4
                out.append( ( s, e, dict( ATTR.findall( x.group( 1 ) ) ) ) )
    return sorted( out, key = lambda r: r[0] )
off, on, names = open( sys.argv[1] ).read(), open( sys.argv[2] ).read(), set( sys.argv[3].split( "," ) )
exp, at, first = [], 0, True
for s, e, a in rows( off ):
    if a.get( "n" ) not in names: continue
    p = a.get( "p", "" ); p = p.rsplit( ":", 1 )[0] if ":" in p and p.rsplit( ":", 1 )[1].isdigit() else p
    exp += [ off[at:s], LEG if first else "", '<t p="%s" sym="%s"%s/>' % ( p, a["n"], ' r="%s"' % a["r"] if "r" in a else "" ) ]; at = e; first = False
exp = "".join( exp ) + off[at:]
est = lambda s: re.sub( r' est_tokens="\d+"', "", s, count = 1 )
print( ( "PASS" if not first and est( exp ) == est( on ) else "FAIL" ) + " expected-rewrite" )
t = mask( on )
print( "ptr " + ",".join( re.findall( r'<t p="[^"]*" sym="([^",]*)"(?: r="\d+")?/>', t ) ) )
print( "rows " + ",".join( a.get( "n", "" ) for _, _, a in rows( on ) ) )
PY

TREE=ts
run(){ ( cd "$TMP/$TREE" && "$BIN" . --no-cache "$@" ); }
estof(){ grep -o '^<ctx [^>]*' "$1" | grep -o ' est_tokens="[0-9]*"' | grep -o '[0-9]*'; }
names(){ ptr="$( sed -n 's/^ptr //p' "$1" ),"; rws="$( sed -n 's/^rows //p' "$1" ),"; }
isptr(){ case ",$ptr" in *",$1,"*) return 0;; esac; return 1; }
isrow(){ case ",$rws" in *",$1,"*) return 0;; esac; return 1; }
arm(){ # arm ID want(row|ptr) NAME WHAT
  if { [ "$2" = row ] && isrow "$3" && ! isptr "$3"; } || { [ "$2" = ptr ] && isptr "$3" && ! isrow "$3"; }; then ok "($1) $3 is a $2: $4"; else no "($1) $3 is not a $2 ($4): ptr=$ptr rows=$rws"; fi
}
twin(){ # twin ID TASK NAMES: run on/off, check the expected rewrite, load the names
  run "--for=$2" >"$TMP/$1.on"; rc1=$?
  RIPWIRE_NO_ONE_SIDE_REACH=1 run "--for=$2" >"$TMP/$1.off"; rc2=$?
  [ "$rc1" = 0 ] && [ "$rc2" = 0 ] || no "($1) runs exited $rc1 / $rc2"
  python3 "$TMP/check.py" "$TMP/$1.off" "$TMP/$1.on" "$3" >"$TMP/$1.res" 2>&1
  if grep -q '^PASS expected-rewrite' "$TMP/$1.res"; then ok "($1) '$2': the off answer with exactly $3 as pointers"; else no "($1) '$2': not the off answer with $3 as pointers: $( head -c 400 "$TMP/$1.res" )"; fi
  names "$TMP/$1.res"
}
ident(){ # ident ID TASK: rule off, byte-identical
  run "--for=$2" >"$TMP/$1.on"; RIPWIRE_NO_ONE_SIDE_REACH=1 run "--for=$2" >"$TMP/$1.off"
  if [ -s "$TMP/$1.on" ] && cmp -s "$TMP/$1.on" "$TMP/$1.off" && ! grep -q '<!-- one-side:' "$TMP/$1.on"; then ok "($1) '$2': byte-identical to the rule disabled"; else no "($1) '$2': differs from the rule disabled"; fi
}

twin a 'alpha_start + beta_finish' alpha_start_wrapper
arm a ptr alpha_start_wrapper "calls the root: it reaches the sink, the root does not reach it"
arm a row alpha_start "an endpoint"
arm a row alpha_beta_bridge "on the root -> sink path"
arm a row beta_finish "an endpoint"
arm a row beta_finish_direct "a direct caller of the sink"
eon="$( estof "$TMP/a.on" )"; eoff="$( estof "$TMP/a.off" )"
gone="$(( $( wc -c <"$TMP/a.off" ) - $( wc -c <"$TMP/a.on" ) + ${#eon} - ${#eoff} ))"
want="$( python3 -c "import sys; print( int( sys.argv[1] ) - int( int( sys.argv[2] ) / 2.5 + 0.5 ) )" "$eoff" "$gone" )"
if [ -n "$eon" ] && [ "$eon" != "$eoff" ] && [ "$(( eon - want ))" -le 1 ] && [ "$(( want - eon ))" -le 1 ]; then ok "(e) est_tokens re-priced on the rewritten bytes: $eoff -> $eon (expected ~$want, $gone B removed; negative: the legend outweighs one short row)"; else no "(e) est_tokens off=$eoff on=$eon expected ~$want ($gone B removed)"; fi
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/a.on" 2>"$TMP/w.err"; then ok "(w) well formed"; else no "(w) $( head -c 300 "$TMP/w.err" )"; fi
fi
nl="$( python3 -c 'import sys; print( open( sys.argv[1] ).read().count( "<!-- one-side:" ) )' "$TMP/a.on" )"
lc="$( python3 -c 'import sys; t = open( sys.argv[1] ).read(); a = t.find( "<!-- one-side:" ) + 4; print( t[a:t.find( "-->", a )] )' "$TMP/a.on" )"
if [ "$nl" = 1 ] && [ "${lc#*--}" = "$lc" ]; then ok "(l) one legend comment, no double hyphen inside"; else no "(l) legend comments=$nl"; fi

twin a2 'sink_left_value + sink_right_value' sink_left_only_caller,sink_left_only_outer
arm a2 ptr sink_left_only_caller "reaches the left sink only"
arm a2 ptr sink_left_only_outer "reaches the left sink only, 2 calls away"
arm a2 row sink_left_right_driver "the common caller reaches both"
twin a2p 'How do sink_left_value and sink_right_value connect?' sink_left_only_caller,sink_left_only_outer

ident b 'gamma_one_value + gamma_two_value'

twin c 'delta_left_value + delta_right_value' delta_left_only_caller
arm c ptr delta_left_only_caller "every row of the one-sided overload set, declarations included"
arm c row delta_left_right_driver "the common caller's overload set"
nd="$( grep -o '<d [^>]*n="delta_left_right_driver"' "$TMP/c.on" | wc -l | tr -d ' ' )"
nt="$( grep -o '<t p="delta.ts" sym="delta_left_only_caller"' "$TMP/c.on" | wc -l | tr -d ' ' )"
if [ "$nd" = 3 ] && [ "$nt" = 3 ]; then ok "(c) the driver's 3 overload rows stay rows, the decoy's 3 are pointers"; else no "(c) driver rows=$nd (want 3), decoy pointers=$nt (want 3)"; fi

ident d 'alpha_start'
ident d2 'What does alpha_start do?'

run "--for=sink_left_value + sink_right_value" --token-budget=4000 >"$TMP/t.on"
if [ -s "$TMP/t.on" ] && ! grep -q '<!-- one-side:' "$TMP/t.on" && ! grep -q 'sym="sink_left_only_caller" r=' "$TMP/t.on"; then ok "(t) --token-budget: no pointer, no legend"; else no "(t) a budgeted answer was demoted"; fi

mcp(){ printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"%s"}}}\n' "$TMP/ts" "$1" \
  | ( cd "$TMP/ts" || exit 1; "$BIN" --mcp 2>/dev/null ) | python3 -c '
import json, sys
for line in sys.stdin:
    d = json.loads( line )
    if d.get( "id" ) == 1:
        print( d["result"]["content"][0]["text"], end="" )
'; }
TREE=t2; mkdir -p "$TMP/t2"
{ printf 'export function path_root_go(n: number): number { return path_a1(n) + path_b1(n); }\n'
  for side in a b; do for k in 1 2 3 4; do printf 'export function path_%s%s(n: number): number { return path_%s%s(n); }\n' "$side" "$k" "$side" "$(( k + 1 ))"; done
    printf 'export function path_%s5(n: number): number { return path_sink_end(n); }\n' "$side"; done
  printf 'export function path_sink_end(n: number): number { return n; }\n'; } >"$TMP/t2/paths.ts"
{ printf 'export function many_left_value(n: number): number { return n; }\nexport function many_right_value(n: number): number { return n + 4; }\n'
  for k in 1 2 3 4 5 6 7 8 9 10; do
    printf 'export function many_mid_%s(n: number): number { return many_left_value(n); }\n' "$k"
    printf 'export function many_driver_%s(n: number): number { return many_mid_%s(n) + many_right_value(n); }\n' "$k" "$k"; done; } >"$TMP/t2/many.ts"
cat >"$TMP/t2/same.cpp" <<'EOF'
int same_left_value( int n ) { return n; }
int same_right_value( int n ) { return n + 3; }
int same_left_right_driver( int n ) { return same_left_value( n ) + same_right_value( n ); }
struct SameQ { int run( int n ) { return same_left_value( n ); } }; struct SameP { int run( int n ) { return same_left_value( n ) + same_right_value( n ); } };
EOF
ident f 'path_root_go + path_sink_end'
if grep -q 'n="path_b4"' "$TMP/f.on"; then ok "(f) path_b4 (on the shortest path not picked) is a row"; else no "(f) path_b4 is not a row"; fi
ident g 'many_left_value + many_right_value'
if grep -q 'n="many_mid_10"' "$TMP/g.on"; then ok "(g) many_mid_10 (the 10th common caller's path) is a row"; else no "(g) many_mid_10 is not a row"; fi
twin h 'same_left_value + same_right_value' SameQ::run
arm h ptr SameQ::run "reaches the left sink only; its scope from its own qualifier"
arm h row SameP::run "reaches both, on the same line as SameQ::run"
TREE=ts

for arm in a a2; do
    task='alpha_start + beta_finish'; want=alpha_start_wrapper
    [ "$arm" = a2 ] && { task='sink_left_value + sink_right_value'; want=sink_left_only_caller,sink_left_only_outer; }
    mcp "$task" >"$TMP/x.on"; RIPWIRE_NO_ONE_SIDE_REACH=1 mcp "$task" >"$TMP/x.off"
    python3 "$TMP/check.py" "$TMP/x.off" "$TMP/x.on" "$want" >"$TMP/x.res" 2>&1
    cli="$( sed -n 's/^ptr //p' "$TMP/$arm.res" )"; mcpptr="$( sed -n 's/^ptr //p' "$TMP/x.res" )"
    if [ -s "$TMP/x.on" ] && grep -q '^PASS expected-rewrite' "$TMP/x.res" && [ "$cli" = "$mcpptr" ]; then ok "(x) MCP for '$task': the same pointers as the CLI ($mcpptr)"
    else no "(x) MCP for '$task': mcp ptr=$mcpptr cli ptr=$cli $( head -c 300 "$TMP/x.res" )"; fi
done
[ "$fail" = 0 ] && echo "foronesidecheck: PASS" || echo "foronesidecheck: FAIL"
exit "$fail"
