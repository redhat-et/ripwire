#!/usr/bin/env bash
# fcallforwardcheck.sh — JS/TS call forwarders: `f.call( … )` / `f.apply( … )` on a PROVEN function binding is a call of f,
# and `f.bind( … )` is a value reference to f, never a call (lane fcall-forward, train 30). "Proven function" means the
# bare call `f( … )` binds at a PROVEN tier (no via="name") to a function or method definition.
#
#   test/fcallforwardcheck.sh                          # uses build/ripwire on test/fcallforwardfix
#   RIPWIRE_BIN=asan/ripwire test/fcallforwardcheck.sh
#   test/fcallforwardcheck.sh build_base/ripwire       # the RED run (a pre-change binary)
#
# THE DEFECT. `handleRequest.call( request.server, null, request, reply )` was recorded only as a member call named `call`
# on the receiver handleRequest: no edge to handleRequest, not even a gap. On a real JS framework the request pipeline
# (route handler → pre-parsing → request handler → … ) was unreachable through --path (reachable=0) and the handler was
# missing from --callees of the function that runs it.
#
# THE FIX (model.h kCallForwarders, read by ingest_valuerefs.h). A family-owned data row per language names the builtin
# forwarders: JS/TS call/apply (kind Call) and bind (kind Value). The value-reference walk, which already tracks
# parameters and locals lexically, queues `f.call( … )` / `f.apply( … )` when f is a bare identifier no enclosing
# parameter or local declares; at file end it keeps the site only when the FILE proves f names a function — a function
# declaration of the file (no file-scope variable rebinding the name) or a file-scope import from a RELATIVE module.
# The kept site is a FORWARDED call reference to f — the bare call `f( … )` — decided by the ordinary resolution tiers,
# and then kept only where they PROVE a function or method (graph.h buildGraph): a by-name-only result, an imported object,
# const or class adds nothing, because an import proves a binding, never that the binding is a function (fix round 1, B1).
# `f.bind( … )` lands f, as a value, in the slot the whole call fills. The original member reference (`call`) is unchanged.
#
# FLOORS (disclosed, shared with the bare call `f()` on the pre-change binary): a function-local `var f` / `let f` declared
# AFTER the site does not shadow (scope declarations are harvested on scope entry), and a re-assignment `f = …` is not
# followed — the forward binds as the bare call does. The declaration proof is file + name (any depth); a declaration only
# in a SIBLING scope binds the bare call by name alone, so its forward is dropped (N10).
#
# ARMS (fixture test/fcallforwardfix/js and /ts):
#   (P1) `.call` on a relative require: --callees=runPreParsing has handleRequest, proven (no via=)       RED on base
#   (P2) `.apply` on a function declared BELOW the site (hoisting): viaApply → localDecl                  RED on base
#   (P3) `.call` on a destructured relative require: helperUser → helperA                                RED on base
#   (R)  --path=routeHandler,preHandlerInner reachable=1 hops=3 (the fastify-14 chain shape)            RED on base
#   (N1) a parameter shadows: nearParam's `cb.call` never reaches other.js:cb
#   (N2) a method-valued member `obj.method.call` never reaches other.js:method
#   (N3) a file-scope NON-function binding `notFn.call` never reaches other.js:notFn
#   (N4) a non-relative import `vendor.call` never reaches other.js:vendor
#   (N5) a loop variable `hook.call` never reaches other.js:hook
#   (N6) `Reflect.apply( target, … )` and `Object.prototype.toString.call` add no call
#   (H)  `dup` is declared only inside two sibling functions: the bare `dup()` binds by name alone (hedged rows), so
#        `dup.call` adds NOTHING (fix round 1: a forward is kept only at a proven tier)
#   (N7) an imported module OBJECT with methods named call / apply (`rpc.call`, `patch.apply`): no call  RED on 52d773b3
#   (N8) an imported CLASS `Klass.call`: no call to klass.js:Klass; (P8) its twin makeKlass.call → makeKlass  N8 RED on 52d773b3
#   (N11) an ESM import of a const object `notAFn.call`: no call; (P11) its twin realFn.call → realFn    N11 RED on 52d773b3
#   (N9) a file-scope `var fv` rebinding a declared function: no call (pins the rebinding guard)
#   (N10) a function declared only in a sibling scope (`nestedOnly`): no call                             RED on 52d773b3
#   (U1) --uses lists no call site for a dropped forward; (U2) it lists a kept one (Graph::keptForwards)    U1 RED on 52d773b3
#   (T7) TS `import { type typeOnlyFn }`: an inline type specifier binds no value — no call
#   (M4) the type guard itself (ingest_valuerefs.h: a type-only specifier is never forwarded): --safe-delete=lib.ts:typeOnlyFn
#        has no callers_floor= and graph_unresolved="0" (train 30, nit N3: RED with the guard removed; T7 alone is not)
#   (S1) a forward buildGraph DROPPED (`fwdNested.call` on a name only a sibling scope declares) is no call site: --callers and
#        --safe-delete of nested.js:fwdNested say sites_at="caller.js:3" — the bare call's line, as --uses lists (nit N1)
#   (S2) a dropped forward of an imported CLASS (`FwdK.call`) and (S3) of a name the module does not export (`notThere.call`)
#        raise no callers_floor= on a same-named function elsewhere (countfloor.h reads model.h forwardCounts; nit N1)
#   (K)  the member reference itself is unchanged: runPreParsing keeps its `call` row via="name" (the fixture's
#        object-literal method named call), as on the pre-change binary
#   (V1) `.bind` handed on as an argument is not a call site: handleRequest's caller sites are the `.call` line only
#   (V2) `onlyBound.bind( this )` as an argument: no caller row, a value row into="emitter.on#arg1"     RED on base
#   (T1) TS `.call` on an aliased named import, (T2) `.apply` on a default import: tsUser → target, defaultFn  RED on base
#   (T3) a namespace member `ns.target.call`, (T4) a typed parameter `handler.call`, (T5) `.bind` into a local,
#   (T6) a local arrow `run.call` (a disclosed floor): none adds a call
set -u
export PYTHONDONTWRITEBYTECODE=1
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/fcallforwardfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$CORPUS/js" ] && [ -d "$CORPUS/ts" ] || { echo "fixture missing: $CORPUS"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "fcallforwardcheck: BIN=$BIN  CORPUS=$CORPUS"

# run( dir, args… ): the answer, or the literal ERROR rc=N so an empty or failed run can never satisfy a check
run(){
    local d="$1"; shift
    local out rc
    out="$( cd "$CORPUS/$d" && "$BIN" . --no-cache "$@" 2>/dev/null )"; rc=$?
    if [ "$rc" -ne 0 ] || [ -z "$out" ]; then printf 'ERROR rc=%s' "$rc"; else printf '%s' "$out"; fi
}
root_tag(){ printf '%s' "$1" | grep -oE "<$2 [^>]*>" | head -1; }
attr(){ printf '%s' "$1" | grep -oE " $2=\"[^\"]*\"" | head -1 | sed -E 's/^[^"]*"([^"]*)"$/\1/'; }
# rows( doc ): the <s> rows as sorted "file:name[~name]" words (p= without its line; ~name marks via="name")
rows(){ printf '%s' "$1" | python3 -c '
import re, sys
t = re.sub( r"<!--.*?-->", "", sys.stdin.read(), flags = re.S )
out = []
for m in re.finditer( r"<s ([^>]*?)/?>", t ):
    a = dict( re.findall( r"(\w+)=\"([^\"]*)\"", m.group( 1 ) ) )
    if "n" in a and "p" in a:
        out.append( a[ "p" ].rsplit( ":", 1 )[ 0 ] + ":" + a[ "n" ] + ( "~name" if a.get( "via" ) == "name" else "" ) )
print( " ".join( sorted( out ) ) )'; }
# has_root( doc, tag ): the answer RAN and produced its root element (an absence is read only off such a run)
has_root(){ [ -n "$( root_tag "$1" "$2" )" ]; }

# ── JS ───────────────────────────────────────────────────────────────────────────────────────────────────────
D="$( run js --callees=runPreParsing )"; R="$( rows "$D" )"
if has_root "$D" callees; then
    case " $R " in *" handle-request.js:handleRequest "*) ok "(P1) runPreParsing → handleRequest, proven (rows: $R)";;
        *) no "(P1) runPreParsing should call handle-request.js:handleRequest without via=: [$R]";; esac
    case " $R " in *" route.js:call~name "*) ok "(K) the member reference is unchanged: the via=name \`call\` row stays";;
        *) no "(K) the original member reference changed: [$R]";; esac
else no "(P1) --callees=runPreParsing did not run: $D"; fi

D="$( run js --callees=viaApply )"; R="$( rows "$D" | tr ' ' '\n' | grep -vE ':(call|apply)~name$' | tr '\n' ' ' | sed 's/ $//' )"
if has_root "$D" callees && [ "$R" = "route.js:localDecl" ]; then ok "(P2) viaApply → localDecl (a declaration below the site)"; else no "(P2) viaApply should call exactly route.js:localDecl: [$R] ${D:0:120}"; fi

D="$( run js --callees=helperUser )"; R="$( rows "$D" )"
case " $R " in *" helpers.js:helperA "*) ok "(P3) helperUser → helperA (destructured relative require)";;
    *) no "(P3) helperUser should call helpers.js:helperA: [$R] ${D:0:120}";; esac

D="$( run js --path=routeHandler,preHandlerInner )"; P="$( root_tag "$D" path )"
if [ "$( attr "$P" reachable )" = 1 ] && [ "$( attr "$P" hops )" = 3 ]; then ok "(R) --path=routeHandler,preHandlerInner reachable=1 hops=3"; else no "(R) --path should be reachable=1 hops=3: ${P:-$D}"; fi

# the near-misses: no answer may reach a namesake in other.js (each would be a FALSE edge)
for pair in N1:nearParam N2:nearMember N3:nearNonFunc N4:nearExternal N5:nearLoop N6:nearGlobal; do
    arm="${pair%%:*}"; fn="${pair#*:}"
    D="$( run js --callees="$fn" )"; R="$( rows "$D" )"
    if ! has_root "$D" callees; then no "($arm) --callees=$fn did not run: $D"; continue; fi
    case " $R " in *" other.js:"*|*":target"*) no "($arm) $fn reaches a namesake it cannot call: [$R]";;
        *) ok "($arm) $fn adds no forwarded call (rows: ${R:-none})";; esac
done
for nm in cb hook notFn method vendor target; do
    D="$( run js --callers=other.js:"$nm" )"; C="$( root_tag "$D" callers )"
    if [ -n "$C" ] && [ "$( attr "$C" count )" = 0 ]; then ok "(N) other.js:$nm has no caller"; else no "(N) other.js:$nm should have count=0: ${C:-$D}"; fi
done

DF="$( run js --callees=dupForwarded )"; DB="$( run js --callees=dupBare )"
RF="$( rows "$DF" | tr ' ' '\n' | grep -v ':call~name$' | tr '\n' ' ' | sed 's/ $//' )"; RB="$( rows "$DB" )"
if has_root "$DF" callees && has_root "$DB" callees && [ -z "$RF" ] && [ -n "$RB" ] && ! printf ' %s ' "$RB" | grep -qE ' [^ ]*:dup '; then
    ok "(H) dup.call on a name only nested scopes declare adds nothing; the bare dup() stays hedged: [$RB]"
else no "(H) dup.call should add no row (got [$RF]) while the bare dup() keeps only via=name rows (got [$RB])"; fi

# B1: an import proves a BINDING, not a function — a forward is kept only when the bare call binds, proven, to a function
for pair in N7:nearObjImport N9:nearRebound N10:nearNested; do
    arm="${pair%%:*}"; fn="${pair#*:}"
    D="$( run js --callees="$fn" )"; R="$( rows "$D" )"
    if ! has_root "$D" callees; then no "($arm) --callees=$fn did not run: $D"; continue; fi
    case " $R " in *" other.js:"*|*" route.js:fv "*|*":nestedOnly"*) no "($arm) $fn gains a forwarded call it does not make: [$R]";;
        *) ok "($arm) $fn adds no forwarded call (rows: ${R:-none})";; esac
done
D="$( run js --callees=nearClassImport )"; R="$( rows "$D" )"
if has_root "$D" callees; then
    case " $R " in *" klass.js:Klass"*) no "(N8) an imported class is no function: nearClassImport reaches klass.js:Klass [$R]";;
        *) ok "(N8) Klass.call adds no call to the imported class";; esac
    case " $R " in *" klass.js:makeKlass "*) ok "(P8) makeKlass.call → klass.js:makeKlass, proven (the function imported beside the class)";;
        *) no "(P8) nearClassImport should call klass.js:makeKlass without via=: [$R]";; esac
else no "(N8) --callees=nearClassImport did not run: $D"; fi
D="$( run js --callees=esmUser )"; R="$( rows "$D" )"
if has_root "$D" callees; then
    case " $R " in *":notAFn"*) no "(N11) an ESM import of a const object is no function: esmUser reaches notAFn [$R]";;
        *) ok "(N11) notAFn.call (an imported const object) adds no call";; esac
    case " $R " in *" consts.js:realFn "*) ok "(P11) realFn.call → consts.js:realFn, proven (an ESM import of a function)";;
        *) no "(P11) esmUser should call consts.js:realFn without via=: [$R]";; esac
else no "(N11) --callees=esmUser did not run: $D"; fi
for nm in rpc patch notAFn nestedOnly fv; do
    D="$( run js --callers=other.js:"$nm" )"; C="$( root_tag "$D" callers )"
    if [ -n "$C" ] && [ "$( attr "$C" count )" = 0 ]; then ok "(N) other.js:$nm has no caller"; else no "(N) other.js:$nm should have count=0: ${C:-$D}"; fi
done

# U: the use-site index follows the resolver — a dropped forward is no call site, a kept one is
for nm in rpc patch Klass nestedOnly dup; do
    D="$( run js --uses="$nm" )"
    if has_root "$D" uses && ! printf '%s' "$D" | grep -qE '<u role="call" p="route.js:[0-9]+" in_id="(nearObjImport|nearClassImport|nearNested|dupForwarded)"'; then ok "(U1) --uses=$nm lists no call site for its dropped forward"; else no "(U1) --uses=$nm lists a dropped forward as a call site: ${D:0:300}"; fi
done
LAPPLY="$( grep -n 'localDecl.apply(' "$CORPUS/js/route.js" | head -1 | cut -d: -f1 )"
D="$( run js --uses=localDecl )"
if printf '%s' "$D" | grep -qF "<u role=\"call\" p=\"route.js:$LAPPLY\" in_id=\"viaApply\"/>"; then ok "(U2) --uses=localDecl lists the kept forward localDecl.apply as a call site"; else no "(U2) --uses=localDecl should list route.js:$LAPPLY as a call site: ${D:0:300}"; fi
LCALL="$( grep -n 'handleRequest.call(' "$CORPUS/js/route.js" | head -1 | cut -d: -f1 )"
LBIND="$( grep -n 'onlyBound.bind(' "$CORPUS/js/route.js" | head -1 | cut -d: -f1 )"
D="$( run js --callers=handleRequest )"; C="$( root_tag "$D" callers )"
SITES="$( printf '%s' "$D" | grep -oE 'sites_at="[^"]*"' | head -1 )"
if [ -n "$C" ] && [ "$( attr "$C" count )" = 1 ] && [ "$SITES" = "sites_at=\"$LCALL\"" ] && printf '%s' "$D" | grep -qE "<s [^>]*p=\"route\.js:[0-9]+\"[^>]* sites_at=\"$LCALL\""; then ok "(V1) handleRequest's one caller site is the .call line, not the .bind line"; else no "(V1) handleRequest callers should be count=1 with sites_at=$LCALL on a p=route.js row: ${C:-$D} $SITES"; fi

D="$( run js --callers=onlyBound )"; C="$( root_tag "$D" callers )"
if [ -n "$C" ] && [ "$( attr "$C" count )" = 0 ] && printf '%s' "$D" | grep -qF "<vr in_id=\"binder\" bind=\"route.js:$LBIND\" into=\"emitter.on#arg1\"/>"; then ok "(V2) onlyBound.bind( this ) is a value row into emitter.on#arg1, not a caller"; else no "(V2) onlyBound should have count=0 and a value row into emitter.on#arg1: ${D:0:400}"; fi
D="$( run js --callees=binder )"; R="$( rows "$D" )"
if has_root "$D" callees && [ -z "$R" ]; then ok "(V2) binder calls nothing (the bind is no call)"; else no "(V2) binder should have no callee row: [$R]"; fi

# ── TS ───────────────────────────────────────────────────────────────────────────────────────────────────────
D="$( run ts --callees=tsUser )"; R="$( rows "$D" )"
if has_root "$D" callees && [ "$R" = "lib.ts:target lib2.ts:defaultFn" ]; then ok "(T1/T2) tsUser → target (aliased named import) and defaultFn (default import), proven"; else no "(T1/T2) tsUser should call exactly lib.ts:target lib2.ts:defaultFn: [$R] ${D:0:120}"; fi
for pair in T3:tsNs T4:tsParam T6:tsLocalArrow T7:tsTypeSpec; do
    arm="${pair%%:*}"; fn="${pair#*:}"
    D="$( run ts --callees="$fn" )"; R="$( rows "$D" )"
    if has_root "$D" callees && [ -z "$R" ]; then ok "($arm) $fn adds no call"; else no "($arm) $fn should have no callee row: [$R] ${D:0:120}"; fi
done
D="$( run ts --callers=defaultFn )"; R="$( rows "$D" )"
if [ "$R" = "user.ts:tsUser" ]; then ok "(T5) defaultFn.bind into a local is no call: its only caller is tsUser"; else no "(T5) defaultFn's callers should be exactly user.ts:tsUser: [$R]"; fi
for nm in other.ts:handler other.ts:run other.ts:typeOnlyFn lib.ts:typeOnlyFn; do
    D="$( run ts --callers="$nm" )"; C="$( root_tag "$D" callers )"
    if [ -n "$C" ] && [ "$( attr "$C" count )" = 0 ]; then ok "(T4/T6/T7) $nm has no caller"; else no "(T4/T6/T7) $nm should have count=0: ${C:-$D}"; fi
done

# ── train 30: the fcall-forward train nits (N1 one shared kept-forward rule, N3 the type guard's own arm) ──────────────
D="$( run ts --safe-delete=lib.ts:typeOnlyFn )"; C="$( root_tag "$D" safe-delete )"
if [ -n "$C" ] && [ "$( attr "$C" graph_unresolved )" = 0 ] && [ -z "$( attr "$C" callers_floor )" ]; then ok "(M4) a type-only specifier is never forwarded: no callers_floor=, graph_unresolved=\"0\""
else no "(M4) --safe-delete=lib.ts:typeOnlyFn should carry graph_unresolved=\"0\" and no callers_floor=: ${C:-$D}"; fi
for v in callers safe-delete; do
    D="$( run sites --$v=nested.js:fwdNested )"; C="$( root_tag "$D" "$v" )"
    S="$( printf '%s' "$D" | grep -oE 'sites_at="[^"]*"' | head -1 )"
    if [ -n "$C" ] && [ "$S" = 'sites_at="3"' ] && printf '%s' "$D" | grep -qE '<[sc] [^>]*p="caller\.js:[0-9]+"[^>]* sites_at="3"'; then ok "(S1) --$v: the dropped fwdNested.call is no call site ($S)"
    else no "(S1) --$v=nested.js:fwdNested should say sites_at=\"3\" only, on a p=caller.js row: ${S:-no sites_at} ${C:-$D}"; fi
done
D="$( run sites --uses=fwdNested )"
if has_root "$D" uses && [ "$( printf '%s' "$D" | grep -oE '<u role="call" p="[^"]*"' | tr '\n' ' ' )" = '<u role="call" p="caller.js:3" ' ]; then ok "(S1) --uses agrees: the one call site is caller.js:3"
else no "(S1) --uses=fwdNested should list exactly the call site caller.js:3: ${D:0:300}"; fi
for pair in S2:kfn.js:FwdK S3:gname.js:notThere; do
    arm="${pair%%:*}"; sel="${pair#*:}"
    D="$( run sites --safe-delete="$sel" )"; C="$( root_tag "$D" safe-delete )"
    if [ -n "$C" ] && [ -z "$( attr "$C" callers_floor )" ]; then ok "($arm) $sel: the dropped forward raises no callers_floor="
    else no "($arm) --safe-delete=$sel should carry no callers_floor=: ${C:-$D}"; fi
done

# (S4) train 30 CR pre-pass A1: MCP `uses` reads the same kept-forward rule — the dropped forwards of S1-S3 are no use-site there
MU="$( cd "$CORPUS/sites" && python3 -c '
import json, subprocess, sys
reqs = [ { "jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {} } ]
for i, s in enumerate( ( "fwdNested", "FwdK", "notThere" ) ):
    reqs.append( { "jsonrpc": "2.0", "id": i + 2, "method": "tools/call", "params": { "name": "uses", "arguments": { "path": ".", "symbol": s } } } )
p = subprocess.run( [ sys.argv[ 1 ], "--mcp", "--mcp-legend=inline" ], input = "".join( json.dumps( r ) + "\n" for r in reqs ), capture_output = True, text = True, timeout = 120 )
for line in p.stdout.splitlines():
    try: r = json.loads( line )
    except ValueError: continue
    if r.get( "id", 0 ) >= 2:
        print( r[ "id" ], json.dumps( r.get( "result", r.get( "error" ) ) ) )
' "$BIN" 2>/dev/null )"
if [ "$( printf '%s\n' "$MU" | grep -c '^[234] ' )" = 3 ] && ! printf '%s' "$MU" | grep -qE 'caller\.js:4|kuser\.js:2|gfwd\.js:2'; then ok "(S4) MCP uses lists none of the dropped forwards (caller.js:4, kuser.js:2, gfwd.js:2)"
else no "(S4) MCP uses should answer 3 calls and list no dropped forward: ${MU:0:600}"; fi

# (S5) train 30 CodeRabbit (outside the diff, src/lsp.h lspReferences): LSP textDocument/references reads the same kept-forward
#     rule as --uses and the hover — the kept forward localDecl.apply (route.js:28) is a reference of localDecl. RED on ad8af71e
#     (no graph reached the references provider, so every forwarded reference stayed out). Near miss: the --uses answer agrees.
#     The LSP index runs on a copy (it may cache under its root; the fixture stays untouched).
LW="$( cd "$( mktemp -d )" && pwd -P )"; cp -R "$CORPUS/js" "$LW/js"   # pwd -P: the uri must name the path the server indexes
LDEF="$( grep -n '^function localDecl ' "$LW/js/route.js" | head -1 | cut -d: -f1 )"
LR="$( python3 - "$BIN" "$LW/js" "$(( LDEF - 1 ))" <<'PY'
import json, subprocess, sys
binp, root, line = sys.argv[ 1 ], sys.argv[ 2 ], int( sys.argv[ 3 ] )
def frame( o ):
    b = json.dumps( o ).encode()
    return b"Content-Length: %d\r\n\r\n" % len( b ) + b
uri = "file://" + root + "/route.js"
msgs = [ { "jsonrpc": "2.0", "id": 1, "method": "initialize", "params": { "rootUri": "file://" + root, "capabilities": {} } },
         { "jsonrpc": "2.0", "method": "initialized", "params": {} },
         { "jsonrpc": "2.0", "id": 2, "method": "textDocument/references", "params": { "textDocument": { "uri": uri },
           "position": { "line": line, "character": 10 }, "context": { "includeDeclaration": False } } },
         { "jsonrpc": "2.0", "id": 99, "method": "shutdown" }, { "jsonrpc": "2.0", "method": "exit" } ]
p = subprocess.run( [ binp, "--lsp" ], input = b"".join( frame( m ) for m in msgs ), capture_output = True, timeout = 120 )
data, i = p.stdout, 0
while i < len( data ):
    j = data.find( b"\r\n\r\n", i )
    if j < 0: break
    cl = int( [ l for l in data[ i:j ].decode().split( "\r\n" ) if l.lower().startswith( "content-length:" ) ][ 0 ].split( ":" )[ 1 ] )
    r = json.loads( data[ j + 4 : j + 4 + cl ] ); i = j + 4 + cl
    if r.get( "id" ) == 2:
        res = r.get( "result" )
        print( "ERR " + json.dumps( r ) if not isinstance( res, list ) else "EMPTY" if not res else " ".join( sorted( "%s:%d" % ( x[ "uri" ].rsplit( "/", 1 )[ -1 ], x[ "range" ][ "start" ][ "line" ] + 1 ) for x in res ) ) )
PY
)"
rm -rf "$LW"
case " $LR " in
    *" route.js:$LAPPLY "*) ok "(S5) LSP references of localDecl list the kept forward route.js:$LAPPLY ($LR)" ;;
    *) no "(S5) LSP textDocument/references of localDecl should list the kept forward route.js:$LAPPLY: [${LR:-no answer}]" ;;
esac

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
