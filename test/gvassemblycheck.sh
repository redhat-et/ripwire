#!/usr/bin/env bash
# gvassemblycheck.sh — GV-ASSEMBLY (src/forgraphverb.h sourceOnlyPickSpelling / metBridgePlan, src/verbs_for.h appendSubjectGraphVerbBlock):
# a --for task spelled as a graph question prints what the path search already proved.
#   M1 ESRC: a task endpoint refused because several definitions fit it binds the ONE left once the test-path and bodyless ones go.
#   (e1) `path from ApplicationRef.tick to refreshView`: three definitions fit (source, a bodyless .d.ts, a tests/ copy) → the
#        graph block runs `--path=src/app/application_ref.ts:tick,refreshView`, narrowed="ApplicationRef.tick", reachable="1", the
#        chain holds tickImpl, and the block equals the bare --path call with that spelling
#   (e2) `callers of ApplicationRef.tick`: the same narrowing on the callers form (verb=--callers=src/app/application_ref.ts:tick)
#   (e3) NEGATIVE: two bodied source definitions left (a second src/ copy) → refused as before: no graph block, no narrowed=
#   M3 MET-BRIDGE: an unreached path whose search reached a caller of to= prints the proven prefix and the one crossing.
#   (b1) onFileEvent -> ConnectionManagerImpl::onData (a virtual `filter->onData( 1 )` the graph declines): <met_bridge reachable="0"
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
verb="$( gvattr e1 verb )"; nar="$( gvattr e1 narrowed )"; body="$( gvbody e1 )"; bare="$( cat "$TMP/e1v.xml" )"
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

# (e3) negative: two bodied source definitions left → still refused, no graph block
run "$F1N" e3 --for="path from ApplicationRef.tick to refreshView"
run "$F1N" e3v --path=ApplicationRef.tick,refreshView
if [ "$( rc e3 )" = 0 ] && [ "$( count e3 '<graph_verb ' )" = 0 ] && [ "$( count e3 'narrowed=' )" = 0 ] && grep -q 'refused="' "$TMP/e3v.xml" \
   && grep -q '<ctx ' "$TMP/e3.xml"; then
    ok "(e3) two source definitions left: no bind, no graph block (the bare --path still refuses)"
else no "(e3) rc=$( rc e3 ) graph_verb=$( count e3 '<graph_verb ' ) narrowed=$( count e3 'narrowed=' )"; fi

# (b1) met bridge across a declined virtual call
RIPWIRE_NO_HOP_BODY=1 run "$F3" b1 --for="path from ConnectionImpl::onFileEvent to ConnectionManagerImpl::onData"
RIPWIRE_NO_HOP_BODY=1 run "$F3" b1v --path=ConnectionImpl::onFileEvent,src/filter_manager.cc:onContinueReading
facts="$( python3 - "$TMP/b1.xml" "$TMP/b1v.xml" <<'PY'
import re, sys
s = open( sys.argv[1], encoding="utf8", errors="replace" ).read()
bare = open( sys.argv[2], encoding="utf8", errors="replace" ).read()
gv = re.search( r'<graph_verb [^>]*>(.*)</graph_verb>', s, re.S )
inner = gv.group( 1 ) if gv else ''
leg = re.search( r'<!-- ripwire for met_bridge:(.*?)-->', inner, re.S )
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
   && [ "$facts" = "n=1 after_gap=1 reach0=1 in=onContinueReading via=declined prefix_reached=1 hop=1 cross_n=onData cross_in=onContinueReading prefix_eq=1 legdash=0" ] \
   && xmlok "$TMP/b1.xml"; then
    ok "(b1) met bridge: proven prefix to the reached caller + one declined crossing ($facts)"
else no "(b1) rc=$( rc b1 )/$( rc b1v ) facts='$facts'"; fi

# (b2) negative, envoy-03: from= names two `main` definitions; the reached one calls an out-of-tree same-named run
run "$F3N" b2 --for="path from main to InstanceBase::run"
if [ "$( rc b2 )" = 0 ] && [ "$( count b2 '<graph_verb ' )" = 1 ] && grep -q 'met="1"' "$TMP/b2.xml" && [ "$( count b2 '<met_bridge' )" = 0 ]; then
    ok "(b2) from= binds two definitions: the near_sink met=1 row stays, no met_bridge"
else no "(b2) rc=$( rc b2 ) graph_verb=$( count b2 '<graph_verb ' ) met_bridge=$( count b2 '<met_bridge' )"; fi

# (b3) negative: a reached path prints no bridge
run "$F3" b3 --for="path from ConnectionImpl::onFileEvent to FilterManagerImpl::onContinueReading"
if [ "$( rc b3 )" = 0 ] && grep -q 'reachable="1"' "$TMP/b3.xml" && [ "$( count b3 '<met_bridge' )" = 0 ]; then
    ok "(b3) reachable path: no met_bridge"
else no "(b3) rc=$( rc b3 ) met_bridge=$( count b3 '<met_bridge' )"; fi

[ "$fail" = 0 ] && echo "gvassemblycheck: PASS" || echo "gvassemblycheck: FAIL"
exit "$fail"
