#!/usr/bin/env bash
# gvassemblycheck.sh — GV-ASSEMBLY (src/forgraphverb.h sourceOnlyPickSpelling / metBridgePlan, src/verbs_for.h appendSubjectGraphVerbBlock):
# a --for task spelled as a graph question prints what the path search already proved.
#   M1 ESRC: a task endpoint refused because several definitions fit it binds the ONE left once the test-path and bodyless ones go.
#   (e1) `path from ApplicationRef.tick to refreshView`: three definitions fit (source, a bodyless .d.ts, a tests/ copy) → the
#        graph block runs `--path=src/app/application_ref.ts:tick,refreshView`, narrowed="ApplicationRef.tick", reachable="1", the
#        chain holds tickImpl, and the block equals the bare --path call with that spelling
#   (e2) `callers of ApplicationRef.tick`: the same narrowing on the callers form (verb=--callers=src/app/application_ref.ts:tick)
#   (e3) NEGATIVE: two bodied source definitions left (a second src/ copy) → no M1 bind: no graph block, no narrowed=; the bare
#       --path binds all four fitting definitions instead of refusing (PATH-AMBIG-VERDICT (b), src/graph.h ownerSpellingFittedDefs)
#   GV-PATH-BIND: the same frozen rule on the DIRECT verbs (src/forgraphverb.h narrowRefusedSpelling, src/verbs_navigate.h):
#   (d1) `--path=ApplicationRef.tick,refreshView` binds the one source definition: rc 0, from="src/app/application_ref.ts:tick",
#        narrowed="ApplicationRef.tick" on <path>, its reading in the legend (compact and full), and the answer == the explicit
#        `--path=src/app/application_ref.ts:tick,refreshView` answer apart from that disclosure
#   (d2) `--connect=ApplicationRef.tick,refreshView`: the same on <connect> (est_tokens= masked: it charges the disclosure)
#   (d3) the callers form `--callers=ApplicationRef.tick`: the same on <callers>, bootApp listed
#   (d4) NEGATIVE: two bodied source definitions left → no narrowed= anywhere; --callers still refuses (rc 1), --path binds the four
#       fitting definitions (rc 0, from_defs=4: it lists pairs and picks none, so qualifying never refuses there), and --connect binds
#       them too (PATH-AMBIG-VC, the same src/graph.h ownerSpellingFittedDefs: rc 0, the tick terminal searched defs="4" and moved onto
#       the definition that joins, as for any many-definition name)
#   (d5) CALLERS-TWO-COPY: MCP find_referencing_symbols binds through the same callHierarchyRowsNarrowed: the d3 answer
#       (narrowed, bootApp), and the d4 fixture still refuses
#   CALLERS-TWO-COPY-BIND (owner 11-17 "bind source, disclose"; src/forgraphverb.h sourceCopyPick): when M1 leaves two bodied
#   definitions and all but ONE are COPIES (a CI/tool dot dir, a vendoring dir, the demo/generated tier, or a file opening with a
#   generated/copied banner), --callers binds the source one and names the copies
#   (d6) a copied-banner twin (the vscode extensions/copilot/src/util/vs shape): --callers=ApplicationRef.tick rc 0, of= the source
#       definition, narrowed=, copy_p= the copy's p:line, copy_next= the callers call on the copy (which itself binds the copy alone),
#       bootApp listed, the readings in the compact and full legends, and the answer == the explicit call's apart from that disclosure
#   (d7) NEGATIVE: neither definition left is source (a banner copy + a .github copy, no src/ one) -> still refused (rc 1), no copy_p=;
#       the d4 two-source refusal carries no copy_p= either
#   (d8) MCP find_referencing_symbols answers the same copy as the CLI: the bound file, narrowed, copy_p, copy_next equal the CLI --json
#       root's, and the MCP answer carries copy_note
#   (d9) a space-bearing copy path (.github/work flow.ts): copy_next= keeps nextFlag's shell quotes raw (nextAttrXml), pastes to
#       the copy alone, and the CLI --json / MCP copy_next carry the same value
#   (e4) --for is not reached: `callers of ApplicationRef.tick` on the d6 tree appends no graph block (the M1 rule alone binds there)
#   M3 MET-BRIDGE: an unreached path whose search reached a caller of to= prints the proven prefix and the one crossing.
#   (b1) onFileEvent -> ConnectionManagerImpl::onData (a virtual `filter->onData( 1 )` the graph declines): AF2 E1 puts the bridge AHEAD
#        of <path_gap> (after_gap=0); <met_bridge reachable="0"
#        in="onContinueReading" via="declined"> holding the path verb's reachable="1" answer onFileEvent -> onContinueReading (its
#        FilterManagerImpl::onRead hop included), then <s via="declined" n="onData" in="onContinueReading">; inside the graph block,
#        after path_gap, once; well-formed, legend without `--`; the prefix equals the bare --path call to in='s spelling
#   (b2) NEGATIVE (envoy-03): `path from main to InstanceBase::run` where main has two definitions and the reached `main` calls an
#        out-of-tree ClangTool's same-named `run` (the declined list holds InstanceBase::run by name only) → no met_bridge
#   (b3) NEGATIVE: a reachable path → no met_bridge
#   (c1) a crashing / silent binary turns the arms red (every arm reads rc and requires its positive text)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "gvassemblycheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
xmlok(){ if command -v xmllint >/dev/null 2>&1; then xmllint --noout "$1" 2>/dev/null; else return 0; fi; }
command -v xmllint >/dev/null 2>&1 || echo "  SKIP  xmllint not installed: the well-formedness half of (b1) is not checked"

# ── M1 fixture: one source definition, a bodyless declaration, a tests/ copy ──
F1="$TMP/fx1"; mkdir -p "$F1/src/app" "$F1/src/render" "$F1/src/types" "$F1/test/mocks"
cat > "$F1/src/app/application_ref.ts" <<'T'
import { refreshView } from '../render/change';
export class ApplicationRef {
  tick(): void { this.tickImpl(); }
  tickImpl(): void { refreshView(); }
}
export function bootApp( app: ApplicationRef ): void { app.tick(); }
T
cat > "$F1/src/render/change.ts" <<'T'
export function refreshView(): void { markDone(); }
export function markDone(): void {}
T
cat > "$F1/src/types/core.d.ts" <<'T'
export declare class ApplicationRef {
  tick(): void;
}
T
cat > "$F1/test/mocks/application_ref_mock.ts" <<'T'
export class ApplicationRef {
  tick(): void { fakeTick(); }
}
function fakeTick(): void {}
T
# the negative twin: the same tree plus a second bodied source definition
F1N="$TMP/fx1n"; cp -R "$F1" "$F1N"; mkdir -p "$F1N/src/legacy"
cat > "$F1N/src/legacy/application_ref_v1.ts" <<'T'
export class ApplicationRef {
  tick(): void { oldTick(); }
}
function oldTick(): void {}
T

# CALLERS-TWO-COPY-BIND: the F1 tree plus a copied-banner twin of the source class (the vscode copilot shape)
F1V="$TMP/fx1v"; cp -R "$F1" "$F1V"; mkdir -p "$F1V/extensions/copilot/src/util/vs/app"
cat > "$F1V/extensions/copilot/src/util/vs/app/application_ref.ts" <<'T'
//!!! DO NOT modify, this file was COPIED from 'upstream/src/app'
export class ApplicationRef {
  tick(): void { copyTick(); }
}
function copyTick(): void {}
T
# the neither-source twin: the banner copy and a .github copy, no src/ definition left
F1X="$TMP/fx1x"; cp -R "$F1V" "$F1X"; rm -f "$F1X/src/app/application_ref.ts"; mkdir -p "$F1X/.github/actions/app"
cat > "$F1X/.github/actions/app/application_ref.ts" <<'T'
export class ApplicationRef {
  tick(): void { ghTick(); }
}
function ghTick(): void {}
T
# (d9) the space-bearing copy: a .github copy whose path has a space, so copy_next='s selector is shell-quoted
F1S="$TMP/fx1s"; cp -R "$F1" "$F1S"; mkdir -p "$F1S/.github"
cat > "$F1S/.github/work flow.ts" <<'T'
export class ApplicationRef {
  tick(): void { wfTick(); }
}
function wfTick(): void {}
T

# ── M3 fixtures ──
F3="$TMP/fx3"; mkdir -p "$F3/src"
cat > "$F3/src/filter.h" <<'C'
struct ReadFilter { virtual void onData( int n ) = 0; virtual ~ReadFilter() {} };
C
cat > "$F3/src/conn_manager.cc" <<'C'
#include "filter.h"
struct ConnectionManagerImpl : ReadFilter { void onData( int n ) override { decodeData( n ); } void decodeData( int ) {} };
C
cat > "$F3/src/echo.cc" <<'C'
#include "filter.h"
struct EchoFilter : ReadFilter { void onData( int ) override {} };
C
cat > "$F3/src/filter_manager.cc" <<'C'
#include "filter.h"
struct FilterManagerImpl { ReadFilter* filter; void onContinueReading() { filter->onData( 1 ); } void onRead() { onContinueReading(); } };
C
cat > "$F3/src/connection.cc" <<'C'
#include "filter.h"
struct FilterManagerImpl;
struct ConnectionImpl { FilterManagerImpl* fm; void onRead(); void onReadReady() { onRead(); } void onFileEvent() { onReadReady(); } };
C
cat > "$F3/src/connection_impl.cc" <<'C'
struct FilterManagerImpl { void onRead(); };
struct ConnectionImpl { FilterManagerImpl* fm; void onRead(); };
void ConnectionImpl::onRead() { fm->onRead(); }
C
F3N="$TMP/fx3n"; mkdir -p "$F3N/source/server" "$F3N/source/exe" "$F3N/compat/prefixer"
cat > "$F3N/source/server/server.cc" <<'C'
struct InstanceBase { void run(); void loop() {} };
void InstanceBase::run() { loop(); }
struct Worker { void run() {} };
C
cat > "$F3N/source/exe/main_common.cc" <<'C'
struct MainCommon { void start() {} };
int main() { MainCommon m; m.start(); return 0; }
C
cat > "$F3N/compat/prefixer/prefixer.cpp" <<'C'
#include <clang/Tooling/Tooling.h>
int main( int argc, char** argv ) { clang::tooling::ClangTool tool( argc, argv ); int ret = tool.run( nullptr ); return ret; }
C

# rc-checked run in fixture $1: stdout to $TMP/<name>.xml, rc kept in $TMP/<name>.rc
run(){ local fx="$1" name="$2"; shift 2; ( cd "$fx" || exit 1; "$BIN" "$fx" --no-cache --legend=compact "$@" 2>/dev/null ) >"$TMP/$name.xml"; echo $? >"$TMP/$name.rc"; }
rc(){ cat "$TMP/$1.rc"; }
# the <graph_verb> open tag's attribute, or '-'
gvattr(){ python3 - "$TMP/$1.xml" "$2" <<'PY'
import re, sys
s = open( sys.argv[1], encoding="utf8", errors="replace" ).read()
m = re.search( r'<graph_verb ([^>]*)>', s )
a = re.search( r'\b' + sys.argv[2] + r'="([^"]*)"', m.group( 1 ) ) if m else None
print( a.group( 1 ) if a else '-' )
PY
}
# the bytes between the <graph_verb …> open tag and the first </path> / </callers…> root close — the verb's own answer
gvbody(){ python3 - "$TMP/$1.xml" <<'PY'
import re, sys
s = open( sys.argv[1], encoding="utf8", errors="replace" ).read()
m = re.search( r'<graph_verb [^>]*>(.*?)(<!-- ripwire for (?:path_gap|met_bridge):|</graph_verb>)', s, re.S )
print( m.group( 1 ) if m else '', end='' )
PY
}
count(){ python3 -c 'import sys; print(open(sys.argv[1], encoding="utf8", errors="replace").read().count(sys.argv[2]))' "$TMP/$1.xml" "$2"; }

# (e1) path form narrowed to the one source definition
RIPWIRE_NO_HOP_BODY=1 run "$F1" e1 --for="path from ApplicationRef.tick to refreshView"
RIPWIRE_NO_HOP_BODY=1 run "$F1" e1v --path=src/app/application_ref.ts:tick,refreshView
# AF2 A (2026-11-18, results/AF2_FIRST12K_1118 §SPEC): a comment that is a direct child of <graph_verb> joins the document legend
# in the answer-first --for answer, so the embedded verb answer equals the bare one with its comments out (they are in the
# answer's legend, once — foranswerfirstcheck (R1)/(R2) pin that no comment is lost or duplicated).
nocomment(){ python3 -c 'import re,sys; print(re.sub(r"<!--.*?-->", "", sys.stdin.read(), flags=re.S), end="")'; }
verb="$( gvattr e1 verb )"; nar="$( gvattr e1 narrowed )"; body="$( gvbody e1 | nocomment )"; bare="$( nocomment <"$TMP/e1v.xml" )"
if [ "$( rc e1 )" = 0 ] && [ "$( rc e1v )" = 0 ] && [ "$verb" = "--path=src/app/application_ref.ts:tick,refreshView" ] && [ "$nar" = "ApplicationRef.tick" ] \
   && printf '%s' "$body" | grep -q 'reachable="1"' && printf '%s' "$body" | grep -q 'n="ApplicationRef.tickImpl"' && [ -n "$bare" ] && [ "$body" = "$bare" ] \
   && grep -q 'narrowed= names the task spellings' "$TMP/e1.xml"; then
    ok "(e1) path endpoint refused over 3 definitions binds the one source definition: verb=$verb narrowed=$nar, block == bare --path"
else no "(e1) rc=$( rc e1 )/$( rc e1v ) verb='$verb' narrowed='$nar' body_eq=$( [ "$body" = "$bare" ] && echo 1 || echo 0 )"; fi

# (e2) callers form, same narrowing
run "$F1" e2 --for="callers of ApplicationRef.tick"
verb="$( gvattr e2 verb )"; nar="$( gvattr e2 narrowed )"
if [ "$( rc e2 )" = 0 ] && [ "$verb" = "--callers=src/app/application_ref.ts:tick" ] && [ "$nar" = "ApplicationRef.tick" ] && gvbody e2 | grep -q 'bootApp'; then
    ok "(e2) callers form narrowed: verb=$verb, bootApp listed"
else no "(e2) rc=$( rc e2 ) verb='$verb' narrowed='$nar'"; fi

# (e3) negative: two bodied source definitions left → no M1 bind, no graph block; the bare --path binds every fitting definition
run "$F1N" e3 --for="path from ApplicationRef.tick to refreshView"
run "$F1N" e3v --path=ApplicationRef.tick,refreshView
if [ "$( rc e3 )" = 0 ] && [ "$( count e3 '<graph_verb ' )" = 0 ] && [ "$( count e3 'narrowed=' )" = 0 ] && [ "$( rc e3v )" = 0 ] \
   && grep -q 'from_defs="4"' "$TMP/e3v.xml" && [ "$( count e3v 'narrowed=' )" = 0 ] && grep -q '<ctx ' "$TMP/e3.xml"; then
    ok "(e3) two source definitions left: no M1 bind, no graph block; the bare --path binds the 4 fitting definitions, no narrowed="
else no "(e3) rc=$( rc e3 )/$( rc e3v ) graph_verb=$( count e3 '<graph_verb ' ) narrowed=$( count e3 'narrowed=' ) e3v_from_defs4=$( count e3v 'from_defs=\"4\"' )"; fi

# ── GV-PATH-BIND: the direct verbs ──
# $1 the narrowed answer, $2 the explicit-spelling answer: "eq=1" when they are byte-equal once the narrowed= attribute, its one
# legend reading and est_tokens= are taken out; then how many narrowed= attributes / readings the narrowed answer carried
direq(){ python3 - "$TMP/$1.xml" "$TMP/$2.xml" <<'PY'
import re, sys
a = open( sys.argv[1], encoding="utf8", errors="replace" ).read()
b = open( sys.argv[2], encoding="utf8", errors="replace" ).read()
attrs = len( re.findall( r' narrowed="[^"]*"', a ) )
reads = len( re.findall( r'narrowed=: [^.]*\. ?', a ) )
mask = lambda s: re.sub( r' est_tokens="\d+"', '', s )
cut = mask( re.sub( r'narrowed=: [^.]*\. ?', '', re.sub( r' narrowed="[^"]*"', '', a ) ) )
print( "eq=%d attrs=%d reads=%d" % ( int( cut == mask( b ) and b != '' ), attrs, reads ) )
PY
}
# the root element <$2 …>'s attribute $3 (comments skipped), or '-'
rootattr(){ python3 - "$TMP/$1.xml" "$2" "$3" <<'PY'
import re, sys
s = re.sub( r'<!--.*?-->', '', open( sys.argv[1], encoding="utf8", errors="replace" ).read(), flags=re.S )
m = re.search( r'<' + sys.argv[2] + r' ([^>]*)>', s )
a = re.search( r'\b' + sys.argv[3] + r'="([^"]*)"', m.group( 1 ) ) if m else None
print( a.group( 1 ) if a else '-' )
PY
}

# (d1) direct --path, narrowed
RIPWIRE_NO_HOP_BODY=1 run "$F1" d1 --path=ApplicationRef.tick,refreshView
RIPWIRE_NO_HOP_BODY=1 run "$F1" d1f --path=ApplicationRef.tick,refreshView --legend=full
d1eq="$( direq d1 e1v )"; d1nar="$( rootattr d1 path narrowed )"; d1from="$( rootattr d1 path from )"
if [ "$( rc d1 )" = 0 ] && [ "$( rc d1f )" = 0 ] && [ "$d1eq" = "eq=1 attrs=1 reads=1" ] && [ "$d1nar" = "ApplicationRef.tick" ] \
   && [ "$d1from" = "src/app/application_ref.ts:tick" ] && grep -q 'reachable="1"' "$TMP/d1.xml" && grep -q 'narrowed=: ' "$TMP/d1f.xml" \
   && grep -q ' narrowed="ApplicationRef.tick"' "$TMP/d1f.xml"; then
    ok "(d1) direct --path endpoint refused over 3 definitions binds the one source definition: from=$d1from narrowed=$d1nar, == the explicit call ($d1eq)"
else no "(d1) rc=$( rc d1 )/$( rc d1f ) narrowed='$d1nar' from='$d1from' $d1eq"; fi

# (d2) direct --connect, narrowed
run "$F1" d2 --connect=ApplicationRef.tick,refreshView
run "$F1" d2v --connect=src/app/application_ref.ts:tick,refreshView
d2eq="$( direq d2 d2v )"; d2nar="$( rootattr d2 connect narrowed )"
if [ "$( rc d2 )" = 0 ] && [ "$( rc d2v )" = 0 ] && [ "$d2eq" = "eq=1 attrs=1 reads=1" ] && [ "$d2nar" = "ApplicationRef.tick" ] && grep -q 'tickImpl' "$TMP/d2.xml"; then
    ok "(d2) direct --connect terminal narrowed: narrowed=$d2nar, == the explicit call ($d2eq)"
else no "(d2) rc=$( rc d2 )/$( rc d2v ) narrowed='$d2nar' $d2eq"; fi

# (d3) direct --callers, narrowed
run "$F1" d3 --callers=ApplicationRef.tick
run "$F1" d3v --callers=src/app/application_ref.ts:tick
d3eq="$( direq d3 d3v )"; d3nar="$( rootattr d3 callers narrowed )"; d3of="$( rootattr d3 callers of )"
if [ "$( rc d3 )" = 0 ] && [ "$( rc d3v )" = 0 ] && [ "$d3eq" = "eq=1 attrs=1 reads=1" ] && [ "$d3nar" = "ApplicationRef.tick" ] \
   && [ "$d3of" = "src/app/application_ref.ts:tick" ] && grep -q 'n="bootApp"' "$TMP/d3.xml"; then
    ok "(d3) direct --callers narrowed: of=$d3of narrowed=$d3nar, bootApp listed, == the explicit call ($d3eq)"
else no "(d3) rc=$( rc d3 )/$( rc d3v ) narrowed='$d3nar' of='$d3of' $d3eq"; fi

# (d4) negative: two bodied source definitions left → no M1 narrowing; --callers refuses, --path and --connect bind the four fitting
run "$F1N" d4p --path=ApplicationRef.tick,refreshView
run "$F1N" d4c --connect=ApplicationRef.tick,refreshView
run "$F1N" d4k --callers=ApplicationRef.tick
d4n=$(( $( count d4p 'narrowed' ) + $( count d4c 'narrowed' ) + $( count d4k 'narrowed' ) ))
if [ "$( rc d4p )" = 0 ] && [ "$( rc d4c )" = 0 ] && [ "$( rc d4k )" = 1 ] && [ "$d4n" = 0 ] && grep -q 'from_defs="4"' "$TMP/d4p.xml" \
   && grep -q 'found="0" refused="4"' "$TMP/d4k.xml" && grep -qE '<t n="tick"[^>]* defs="4"' "$TMP/d4c.xml"; then
    ok "(d4) two source definitions left: --callers still refuses (rc 1, refused=4), --path (from_defs=4) and --connect (t defs=4) bind the 4, no narrowed="
else no "(d4) rc=$( rc d4p )/$( rc d4c )/$( rc d4k ) narrowed=$d4n"; fi

# (d5) CALLERS-TWO-COPY: MCP find_referencing_symbols / callers bind through the CLI's own binder (forgraphverb.h
#      callHierarchyRowsNarrowed), so ApplicationRef.tick narrows to the one source definition there too ("narrowed", its
#      note, bootApp in calledBy), where MCP called callHierarchyRows directly and refused it. NEGATIVE: the two-source
#      fixture still refuses on MCP, as --callers does (d4). RED on the base binary (MCP answered -32602 / not found).
mcpq(){ python3 - "$BIN" "$1" "$2" ${3:+"$3"} <<'PY'
import json, subprocess, sys
binp, root, verb = sys.argv[1], sys.argv[2], sys.argv[3]
reqs = [ { "jsonrpc": "2.0", "id": 0, "method": "initialize", "params": { "protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": { "name": "g", "version": "1" } } },
         { "jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": { "name": verb, "arguments": { "path": root, "symbol": "ApplicationRef.tick" } } } ]
p = subprocess.run( [ binp, "--mcp" ], input = "".join( json.dumps( r ) + "\n" for r in reqs ), capture_output = True, text = True, timeout = 300 )
for line in p.stdout.splitlines():
    try:
        o = json.loads( line )
    except ValueError:
        continue
    if o.get( "id" ) != 1:
        continue
    r = o.get( "result", {} )
    text = "".join( c.get( "text", "" ) for c in r.get( "content", [] ) )
    try:
        # SEP-1303 (lane mcp-metadata): a found=0 answer carries its refusal sentence as a second block, so the
        # JSON document is content[0] alone
        j = json.loads( r[ "content" ][ 0 ].get( "text", "" ) if r.get( "content" ) else text )
    except ValueError:
        print( "err", ( json.dumps( o.get( "error" ) ) if "error" in o else text ).replace( "\n", " " )[:300] ); break
    # SEP-1303 (lane mcp-metadata): a not-found is a plain result now, the found=0 document in content[0] and the
    # refusal sentence in content[1] (it was a -32602 error); "notfound" + that sentence keeps (d5)'s refusal arm exact
    if j.get( "found" ) == 0 and len( r.get( "content", [] ) ) > 1:
        print( "notfound", r[ "content" ][ 1 ].get( "text", "" ).replace( "\n", " " )[:300] ); break
    names = [ e.get( "name" ) for e in j.get( "calledBy", [] ) ]
    print( "ok", "narrowed=" + str( j.get( "narrowed", "-" ) ), "note=" + ( "1" if "narrowed_note" in j else "0" ),
           "defs=" + str( j.get( "defs" ) ), "calledBy=" + ",".join( n for n in names if n ) )
    if len( sys.argv ) > 4:   # (d8): the fields the CLI --json root carries, for the twin comparison
        sym = j.get( "symbol" ) if isinstance( j.get( "symbol" ), dict ) else {}
        print( "file=%s narrowed=%s copy_p=%s copy_next=%s copy_note=%d" % ( str( sym.get( "p", sym.get( "file", "-" ) ) ).split( ":" )[0], j.get( "narrowed", "-" ), j.get( "copy_p", "-" ),
                                                                          j.get( "copy_next", "-" ), int( "copy_note" in j ) ) )
    break
else:
    print( "err no response" )
PY
}
d5a="$( mcpq "$F1" find_referencing_symbols )"; d5b="$( mcpq "$F1N" find_referencing_symbols )"
if [ "$( rc d3 )" = 0 ] && [ "$d5a" = "ok narrowed=ApplicationRef.tick note=1 defs=1 calledBy=bootApp" ]; then
    ok "(d5) MCP find_referencing_symbols narrows like --callers (d3): $d5a"
else no "(d5) MCP find_referencing_symbols ApplicationRef.tick: want the CLI's narrowed answer, got [$d5a]"; fi
# The refusal must be THE refusal: the symbol-not-found answer for the selector (a found=0 result carrying the refusal
# sentence; a -32602 error before SEP-1303). "err no response" (the subprocess died or
# hung up), a malformed result, or any other error is a FAIL, not a pass by default.
case "$d5b" in
    'notfound symbol not found: '"'ApplicationRef.tick'"*)
        ok "(d5) negative: two source definitions left, MCP still refuses like --callers: [$d5b]" ;;
    ok\ *) no "(d5) negative: two source definitions left, MCP must still refuse like --callers (d4): [$d5b]" ;;
    *)     no "(d5) negative: want the symbol-not-found answer for ApplicationRef.tick, got [$d5b]" ;;
esac

# ── CALLERS-TWO-COPY-BIND ──
# (d6) the copied-banner twin: --callers binds the source definition and names the copy
run "$F1V" d6 --callers=ApplicationRef.tick
run "$F1V" d6f --callers=ApplicationRef.tick --legend=full
run "$F1V" d6v --callers=src/app/application_ref.ts:tick
d6of="$( rootattr d6 callers of )"; d6nar="$( rootattr d6 callers narrowed )"; d6cp="$( rootattr d6 callers copy_p )"; d6cn="$( rootattr d6 callers copy_next )"
# "eq=1" when the bound answer equals the explicit call's once narrowed=/copy_p=/copy_next= and their compact readings are taken out
d6eq="$( python3 - "$TMP/d6.xml" "$TMP/d6v.xml" <<'PY'
import re, sys
a = open( sys.argv[1], encoding="utf8", errors="replace" ).read()
b = open( sys.argv[2], encoding="utf8", errors="replace" ).read()
reads = len( re.findall( r'copy_p=: ', a ) ) + len( re.findall( r'copy_next=: ', a ) )
cut = re.sub( r' (narrowed|copy_p|copy_next)="[^"]*"', '', a )
cut = re.sub( r'(narrowed|copy_p|copy_next)=: [^.]*\. ?', '', cut )
mask = lambda s: re.sub( r' est_tokens="\d+"', '', s )
print( "eq=%d reads=%d" % ( int( mask( cut ) == mask( b ) and b != '' ), reads ) )
PY
)"
cp_sel="${d6cn#--callers=}"
run "$F1V" d6c "--callers=$cp_sel"
if [ "$( rc d6 )" = 0 ] && [ "$( rc d6f )" = 0 ] && [ "$( rc d6v )" = 0 ] && [ "$d6of" = "src/app/application_ref.ts:tick" ] && [ "$d6nar" = "ApplicationRef.tick" ] \
   && [ "$d6cp" = "extensions/copilot/src/util/vs/app/application_ref.ts:3" ] && [ "$d6cn" = "--callers=extensions/copilot/src/util/vs/app/application_ref.ts:tick" ] \
   && grep -q 'n="bootApp"' "$TMP/d6.xml" && [ "$d6eq" = "eq=1 reads=2" ] && grep -q 'copy_p=: beside narrowed=' "$TMP/d6f.xml" \
   && [ "$( rc d6c )" = 0 ] && [ "$( rootattr d6c callers defs )" = 1 ] && [ "$( rootattr d6c callers copy_p )" = "-" ]; then
    ok "(d6) banner copy: --callers binds of=$d6of (narrowed=$d6nar), copy_p=$d6cp, copy_next= binds the copy alone, == the explicit call ($d6eq)"
else no "(d6) rc=$( rc d6 )/$( rc d6f )/$( rc d6v )/$( rc d6c ) of='$d6of' narrowed='$d6nar' copy_p='$d6cp' copy_next='$d6cn' $d6eq"; fi

# (d7) negative: no source definition left (a banner copy + a .github copy) -> still refused, no disclosure; nor on d4's refusal
run "$F1X" d7 --callers=ApplicationRef.tick
if [ "$( rc d7 )" = 1 ] && grep -q 'found="0" refused=' "$TMP/d7.xml" && [ "$( count d7 'copy_p' )" = 0 ] && [ "$( count d7 'narrowed' )" = 0 ] \
   && [ "$( count d4k 'copy_p' )" = 0 ]; then
    ok "(d7) neither definition is source: --callers still refuses (rc 1), no copy_p=/narrowed=; the two-source refusal (d4) has no copy_p= either"
else no "(d7) rc=$( rc d7 ) copy_p=$( count d7 'copy_p' )/$( count d4k 'copy_p' ) narrowed=$( count d7 'narrowed' )"; fi

# (d8) MCP answers the same copy as the CLI
run "$F1V" d8j --callers=ApplicationRef.tick --json --legend=full   # (--legend=compact is XML-only and refuses with --json)
d8cli="$( python3 - "$TMP/d8j.xml" <<'PY'
import json, sys
try:
    j = json.loads( open( sys.argv[1], encoding="utf8" ).read() )
except ValueError:
    print( "unparsable" ); sys.exit()
print( "file=%s narrowed=%s copy_p=%s copy_next=%s copy_note=1" % ( j.get( "of", "-" ).split( ":" )[0], j.get( "narrowed", "-" ), j.get( "copy_p", "-" ), j.get( "copy_next", "-" ) ) )
PY
)"
d8mcp="$( mcpq "$F1V" find_referencing_symbols twin | sed -n 2p )"
if [ "$( rc d8j )" = 0 ] && [ -n "$d8mcp" ] && [ "$d8mcp" = "$d8cli" ] && [ "${d8cli#*copy_p=extensions/}" != "$d8cli" ]; then
    ok "(d8) MCP find_referencing_symbols == CLI --json on the two-copy bind: $d8mcp"
else no "(d8) CLI [$d8cli] vs MCP [$d8mcp]"; fi

# (d9) a space-bearing copy path: copy_next= is the nextFlag-quoted call with its apostrophes RAW (nextAttrXml, the one next=
#      escaper), not escapeXml's &apos; -- pasted out of the raw answer it binds the copy alone; the CLI --json and MCP spell the same
#      value. RED before the fix (copy_next="--callers=&apos;.github/work flow.ts:tick&apos;").
want9="--callers='.github/work flow.ts:tick'"
run "$F1S" d9 --callers=ApplicationRef.tick
run "$F1S" d9j --callers=ApplicationRef.tick --json --legend=full
d9raw="$( python3 -c 'import re,sys; m=re.search(r" copy_next=\"([^\"]*)\"", open(sys.argv[1], encoding="utf8", errors="replace").read()); print(m.group(1) if m else "-")' "$TMP/d9.xml" )"
d9js="$( python3 -c 'import json,sys
try: print(json.loads(open(sys.argv[1], encoding="utf8").read()).get("copy_next","-"))
except ValueError: print("unparsable")' "$TMP/d9j.xml" )"
d9mcp="$( mcpq "$F1S" find_referencing_symbols twin | sed -n 2p )"
d9paste="$( cd "$F1S" && eval "\"\$BIN\" \"\$F1S\" --no-cache --legend=compact $d9raw" 2>/dev/null )"; d9prc=$?
d9pof="$( printf '%s' "$d9paste" | python3 -c 'import re,sys; m=re.search(r"<callers [^>]*\bof=\"([^\"]*)\"", sys.stdin.read()); print(m.group(1) if m else "-")' )"
if [ "$( rc d9 )" = 0 ] && [ "$d9raw" = "$want9" ] && [ "$( count d9 '&apos;' )" = 0 ] && [ "$( rc d9j )" = 0 ] && [ "$d9js" = "$want9" ] \
   && [ "${d9mcp#*copy_next="$want9" copy_note=1}" != "$d9mcp" ] && [ "$d9prc" = 0 ] && [ "$d9pof" = ".github/work flow.ts:tick" ]; then
    ok "(d9) space-bearing copy: copy_next=$d9raw raw (no &apos;), pastes to of=$d9pof; --json and MCP spell it the same"
else no "(d9) rc=$( rc d9 )/$( rc d9j ) copy_next xml=[$d9raw] json=[$d9js] mcp=[$d9mcp] paste rc=$d9prc of=[$d9pof]"; fi

# (e4) --for is not reached by the two-copy bind
run "$F1V" e4 --for="callers of ApplicationRef.tick"
if [ "$( rc e4 )" = 0 ] && [ "$( count e4 '<graph_verb ' )" = 0 ] && [ "$( count e4 'copy_p' )" = 0 ]; then
    ok "(e4) --for callers of a two-copy name: no graph block, no copy_p= (the bind is --callers / MCP only)"
else no "(e4) rc=$( rc e4 ) graph_verb=$( count e4 '<graph_verb ' ) copy_p=$( count e4 'copy_p' )"; fi

# (b1) met bridge across a declined virtual call
RIPWIRE_NO_HOP_BODY=1 run "$F3" b1 --for="path from ConnectionImpl::onFileEvent to ConnectionManagerImpl::onData"
RIPWIRE_NO_HOP_BODY=1 run "$F3" b1v --path=ConnectionImpl::onFileEvent,src/filter_manager.cc:onContinueReading
facts="$( python3 - "$TMP/b1.xml" "$TMP/b1v.xml" <<'PY'
import re, sys
s = open( sys.argv[1], encoding="utf8", errors="replace" ).read()
bare = open( sys.argv[2], encoding="utf8", errors="replace" ).read()
gv = re.search( r'<graph_verb [^>]*>(.*)</graph_verb>', s, re.S )
inner = gv.group( 1 ) if gv else ''
leg = re.search( r'<!-- ripwire for met_bridge:(.*?)-->', s, re.S )   # AF2 A: the bridge legend joins the document legend
mb = re.search( r'<met_bridge ([^>]*)>(.*)</met_bridge>', inner, re.S )
a = mb.group( 1 ) if mb else ''
body = mb.group( 2 ) if mb else ''
cross = re.search( r'<s via="declined" [^>]*/>$', body )
pre = body[: cross.start()] if cross else ''
c = cross.group( 0 ) if cross else ''
print( "n=%d after_gap=%d reach0=%d in=%s via=%s prefix_reached=%d hop=%d cross_n=%s cross_in=%s prefix_eq=%d legdash=%d" % (
    s.count( '<met_bridge ' ), int( inner.find( '</path_gap>' ) < inner.find( '<met_bridge ' ) ), int( 'reachable="0"' in a ),
    ( re.search( r'\bin="([^"]*)"', a ) or [0, '-'] )[1], ( re.search( r'\bvia="([^"]*)"', a ) or [0, '-'] )[1],
    int( 'reachable="1"' in pre ), int( 'FilterManagerImpl::onRead"' in pre ),
    ( re.search( r'\bn="([^"]*)"', c ) or [0, '-'] )[1], ( re.search( r'\bin="([^"]*)"', c ) or [0, '-'] )[1],
    int( pre == bare and pre != '' ), int( '--' in leg.group( 1 ) ) if leg else 9 ) )
PY
)"
if [ "$( rc b1 )" = 0 ] && [ "$( rc b1v )" = 0 ] \
   && [ "$facts" = "n=1 after_gap=0 reach0=1 in=onContinueReading via=declined prefix_reached=1 hop=1 cross_n=onData cross_in=onContinueReading prefix_eq=1 legdash=0" ] \
   && xmlok "$TMP/b1.xml"; then
    ok "(b1) met bridge: proven prefix to the reached caller + one declined crossing ($facts)"
else no "(b1) rc=$( rc b1 )/$( rc b1v ) facts='$facts'"; fi

# (b2) negative, envoy-03: from= names two `main` definitions; the reached one calls an out-of-tree same-named run
run "$F3N" b2 --for="path from main to InstanceBase::run"
if [ "$( rc b2 )" = 0 ] && [ "$( count b2 '<graph_verb ' )" = 1 ] && grep -Eq '<near_sink [^>]*>(<ns [^>]*/>)*<ns [^>]*met="1"' "$TMP/b2.xml" && [ "$( count b2 '<met_bridge' )" = 0 ]; then
    ok "(b2) from= binds two definitions: the near_sink met=1 row stays, no met_bridge"
else no "(b2) rc=$( rc b2 ) graph_verb=$( count b2 '<graph_verb ' ) met_bridge=$( count b2 '<met_bridge' )"; fi

# (b3) negative: a reached path prints no bridge
run "$F3" b3 --for="path from ConnectionImpl::onFileEvent to FilterManagerImpl::onContinueReading"
if [ "$( rc b3 )" = 0 ] && grep -q 'reachable="1"' "$TMP/b3.xml" && [ "$( count b3 '<met_bridge' )" = 0 ]; then
    ok "(b3) reachable path: no met_bridge"
else no "(b3) rc=$( rc b3 ) met_bridge=$( count b3 '<met_bridge' )"; fi

[ "$fail" = 0 ] && echo "gvassemblycheck: PASS" || echo "gvassemblycheck: FAIL"
exit "$fail"
