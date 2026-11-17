#!/usr/bin/env bash
# protoindexcheck.sh — PROTO-INDEX: .proto definitions in the index, and generated names linked to them by name.
#
# A Protocol Buffers schema defines the messages, enums, oneofs, services and rpcs that Rust (prost), Go
# (protoc-gen-go), C++, Python and TypeScript code uses through GENERATED modules, which are usually not in the
# tree. Before this lane ripwire did not read .proto at all, so `--for=ExprType` on a tree whose code writes
# `use x_pb::expr::expr_node::Type as ExprType;` could name no definition.
#
# Arms (the fixture is written at runtime, never under a .gitignored path):
#   A  --defs finds each definition kind with its kind and line: message, nested message, enum, enum value,
#      oneof, service, rpc; a member's scope is its owner (ExprService.Evaluate, Type.ADD); a nested type prints bare
#      (the house rule for owner kinds) and its owner rides the gen rung in D (ExprNode.Type).
#   B  keywords inside comments and string options never become definitions (positive twin: the real ones exist).
#   C  --whereis and --for name the definition (kind and line).
#   D  a Rust `use … as Alias` and the Go spelling `Outer_Leaf` link to the .proto definition through the
#      shortkey gen rung (a Go `type Alias = pb.Outer_Leaf` is a definition, served name-exact), hedged: via="name", exact="0"; never a proven edge (--callers of the proto def is empty).
#   E  a same-named Rust struct that is not generated keeps its own proven caller; the proto def gains none (the fixture
#      defines a proto Datum too, so the collision is real).
#   F  absence arm with a positive twin: a Rust alias whose leaf no .proto defines links nothing (kept="0").
#   G  a tree with no .proto file prints no gen rung (byte-identical ladder shape).
#   I  an alias path must END its statement: `let X = pkg::Leaf (arg)` (a call after a space) and `pkg::Leaf [0]` link nothing;
#      `pkg::Leaf ;` and `pkg::Leaf; // note` still link (CodeRabbit #571).
#   J  key= and path= come from the same path: a first path that names nothing never lends its leaf to a later match.
#   K  a cut gen list says so: 7 same-named schema definitions print kept="7" shown="6" and 6 rows; twin: one definition
#      prints shown="1". (The leaf rung's cut is stated by its of= total and the legend's "6 shown".)
#   L  --compress reaches the gen rung's body (a comment line dropped) and the block says compress="1"; twin: no flag, no
#      compress= and the comment kept.
#   M  a SCIP index that resolves a Go call to a .proto definition commits no caller edge; twin: the same index's Go-to-Go
#      call is pinned (prov=scip).
#   H  RANK-PROTO: 60 copies of a generic schema name (message Config) take no --for ranked row and displace no code
#      definition (a .proto def is no lexical document, model.h kRankFlagNotLexRanked); twin: --defs binds all 60.
# Every command whose output an arm reads has its exit code checked; an empty output is a FAIL, never a pass.
#
# Usage: test/protoindexcheck.sh [BIN]   (default build/ripwire). Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "protoindexcheck: BIN=$BIN"

FIX="$TMP/repo"; mkdir -p "$FIX/proto" "$FIX/src" "$FIX/go"
cat > "$FIX/proto/expr.proto" <<'EOF'
syntax = "proto3";
package demo.expr;
import "data.proto";
option java_package = "com.demo.message enum service";
// message CommentedMsg { enum CommentedEnum {} }
/* service HiddenSvc { rpc HiddenRpc(A) returns (B); } */
message ExprNode {
  message NowRexNode {}
  enum Type {
    UNSPECIFIED = 0;
    ADD = 1;
  }
  Type function_type = 1;
  oneof rex_node {
    uint32 input_ref = 4;
    string label = 5 [(validate.rules).string = {pattern: "message StringMsg"}];
  }
}
service ExprService {
  rpc Evaluate(ExprNode) returns (data.Datum);
  rpc Stream(stream ExprNode) returns (stream data.Datum) {}
}
message Datum {}
EOF
cat > "$FIX/src/lib.rs" <<'EOF'
use demo_pb::expr::expr_node::Type as ExprType;
use demo_pb::expr::{ExprNode as Node, missing_mod::Nowhere as GhostKind};

pub struct Datum { pub v: i64 }
impl Datum { pub fn new( v: i64 ) -> Datum { Datum { v } } }

pub fn kind_of( t: ExprType ) -> ExprType { t }
pub fn build() -> Datum { Datum::new( 1 ) }
use demo_pb::expr::ExprNode as Missing;
pub fn aliases() -> i32 {
    let CallKind = demo_pb::expr::ExprNode (1);
    let IdxKind = demo_pb::expr::ExprNode [0];
    let SpacedKind = demo_pb::expr::ExprNode ;
    let CmtKind = demo_pb::expr::ExprNode; // the node
    0
}
EOF
cat > "$FIX/go/expr.go" <<'EOF'
package expr

import pb "example.com/demo/expr"

type GoExprType = pb.ExprNode_Type

func Kind( t GoExprType ) GoExprType { return t }
EOF
# --whereis searches git refs: the fixture is a one-commit repository
( cd "$FIX" && git init -q && git add -A && git -c user.name=t -c user.email=t@example.invalid commit -qm fixture ) || { echo "protoindexcheck: fixture git init failed"; exit 2; }
CACHE="$TMP/cache"
run(){ ( cd "$FIX" || exit 1; "$BIN" "$FIX" --cache="$CACHE" "$@" ) 2>"$TMP/err"; }

echo "=== A: definitions, kinds, lines, scopes ==="
want_def(){   # name expected-n expected-t expected-line
    out="$( run --defs="$1" )"; rc=$?
    [ "$rc" = 0 ] || { no "A $1: --defs exited $rc"; return; }
    [ -n "$out" ] || { no "A $1: --defs printed nothing"; return; }
    if printf '%s' "$out" | grep -q "<d n=\"$2\" t=\"$3\" p=\"proto/expr.proto:$4\"[^>]* lang=\"proto\""; then ok "A $1 -> $2 t=$3 l=$4"
    else no "A $1: want n=$2 t=$3 l=$4, got: $( printf '%s' "$out" | grep -o '<d [^>]*>' | head -3 )"; fi
}
want_def ExprNode   ExprNode            cls    7
# a nested message, enum or oneof prints bare n= like every language's nested type (memberowner.h: an owner-kind row is
# never qualified); its owner scope is checked in D, where the gen rung prints it (ExprNode.Type)
want_def NowRexNode NowRexNode          cls    8
want_def Type       Type                cls    9
want_def ADD        Type.ADD            var    11
want_def rex_node   rex_node            cls    14
want_def ExprService ExprService        iface  19
want_def Evaluate   ExprService.Evaluate method 20
want_def Datum      Datum               cls    23
out="$( run --defs=ExprNode )"; rc=$?
if [ "$rc" != 0 ] || ! printf '%s' "$out" | grep -q '<d n="ExprNode" t="cls"'; then no "A ExprNode body arm: no definition row (rc=$rc)"
elif printf '%s' "$out" | grep -q 'decl_only="1"'; then no "A ExprNode reads as a bodyless declaration"
else ok "A a message has a body (no decl_only)"; fi

echo "=== B: comment and string keywords are not definitions (twin: A) ==="
for n in CommentedMsg CommentedEnum HiddenSvc HiddenRpc StringMsg; do
    out="$( run --defs="$n" )"; rc=$?
    # a name with no definition exits 1 with its found="0" answer (the not-found contract); any other status is a failure
    [ "$rc" = 1 ] && [ -n "$out" ] || { no "B $n: --defs exited $rc (want 1, the not-found exit) or printed nothing"; continue; }
    if printf '%s' "$out" | grep -q 'found="0"'; then ok "B $n is not a definition"; else no "B $n became a definition"; fi
done

echo "=== C: --whereis and --for name the definition ==="
out="$( run --whereis=NowRexNode )"; rc=$?
if [ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'proto/expr.proto'; then ok "C --whereis names proto/expr.proto"; else no "C --whereis (rc=$rc): $( printf '%s' "$out" | head -c 300 )"; fi
out="$( run --for=ExprService )"; rc=$?
if [ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'p="proto/expr.proto"'; then ok "C --for=ExprService serves the proto def"; else no "C --for=ExprService (rc=$rc): $( printf '%s' "$out" | head -c 300 )"; fi

echo "=== D: generated names link by name, hedged ==="
out="$( run --for=ExprType )"; rc=$?
[ "$rc" = 0 ] || no "D --for=ExprType exited $rc"
gen="$( printf '%s' "$out" | grep -o '<rung n="gen"[^>]*>.*</rung>' | head -1 )"
[ -n "$gen" ] || no "D Rust: no gen rung for --for=ExprType (rc=$rc): $( printf '%s' "$out" | grep -o '<shortkey[^>]*>' )"
if printf '%s' "$gen" | grep -q 'via="name"' && printf '%s' "$gen" | grep -q 'exact="0"'; then ok "D Rust gen rung is hedged (via=name, exact=0)"; else no "D Rust gen rung not hedged: $gen"; fi
if printf '%s' "$gen" | grep -q 'path="demo_pb::expr::expr_node::Type"' && printf '%s' "$gen" | grep -q '<d n="ExprNode.Type" t="cls" p="proto/expr.proto" l="9"/>'; then ok "D Rust use-as links ExprNode.Type"; else no "D Rust use-as: $gen"; fi
if printf '%s' "$out" | grep -q 'shortkey gen:'; then ok "D the gen legend rides the answer"; else no "D gen legend missing"; fi
# A Go `type GoExprType = pb.ExprNode_Type` is itself a definition: --for serves it name-exact (its line shows the generated
# path) and the gen rung, a not-found ladder rung, does not run. Disclosed limitation (report ## Follow-ons: GEN-USES).
out="$( run --for=GoExprType )"; rc=$?
if [ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'n="GoExprType" p="go/expr.go"'; then ok "D Go alias GoExprType serves its own def (pb.ExprNode_Type on its line)"; else no "D Go alias (rc=$rc): $( printf '%s' "$out" | head -c 400 )"; fi
out="$( run --for=ExprNode_Type )"; rc=$?
if [ "$rc" = 0 ] && printf '%s' "$out" | grep -o '<rung n="gen"[^>]*>.*</rung>' | grep -q 'ExprNode.Type'; then ok "D the Go spelling asked directly links ExprNode.Type"; else no "D ExprNode_Type (rc=$rc)"; fi
out="$( run --callers=Type )"; rc=$?
if [ "$rc" != 0 ] || ! printf '%s' "$out" | grep -q '<callers [^>]*of="Type" defs="1"'; then no "D --callers=Type did not resolve the proto enum (rc=$rc)"
elif printf '%s' "$out" | grep -q 'kind_of\|Kind'; then no "D a by-name gen link became a proven caller edge"
else ok "D --callers of the proto enum lists no Rust/Go caller"; fi

echo "=== E: a same-named Rust struct keeps its own proven edges ==="
out="$( run --callers=Datum::new )"; rc=$?
if [ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'build'; then ok "E Rust Datum::new keeps its caller build"; else no "E Datum::new callers (rc=$rc): $( printf '%s' "$out" | head -c 300 )"; fi

echo "=== F: absence with a positive twin ==="
# GhostKind is code-shaped: a name-exact route, so the not-found ladder runs
out="$( run --for=GhostKind )"; rc=$?
[ "$rc" = 0 ] || no "F --for=GhostKind exited $rc"
g="$( printf '%s' "$out" | grep -o '<rung n="gen"[^>]*>' )"
[ -n "$g" ] || no "F GhostKind: no gen rung at all (rc=$rc) — the absence must be a printed kept=0, not silence"
if printf '%s' "$g" | grep -q 'kept="0"'; then ok "F an alias no .proto defines links nothing (kept=0); twin = D"; else no "F GhostKind: $g"; fi

echo "=== I: an alias path ends its statement ==="
for q in CallKind IdxKind; do
    out="$( run --for="$q" )"; rc=$?
    g="$( printf '%s' "$out" | grep -o '<rung n="gen"[^>]*>.*</rung>' | head -1 )"
    # the ladder ran (its literal rung shows the line), and no path was read from it: no gen rung, or one that kept nothing
    if [ "$rc" != 0 ] || ! printf '%s' "$out" | grep -q '<rung n="literal"[^>]*total="1"'; then no "I $q: no ladder with the literal row (rc=$rc)"
    elif [ -z "$g" ] || { printf '%s' "$g" | grep -q 'kept="0"' && ! printf '%s' "$g" | grep -q '<d '; }; then ok "I $q: an expression after the path links nothing"
    else no "I $q linked a definition: $g"; fi
done
for q in SpacedKind CmtKind; do
    out="$( run --for="$q" )"; rc=$?
    [ "$rc" = 0 ] || no "I $q: --for exited $rc"
    g="$( printf '%s' "$out" | grep -o '<rung n="gen"[^>]*>.*</rung>' | head -1 )"
    if printf '%s' "$g" | grep -q 'path="demo_pb::expr::ExprNode"' && printf '%s' "$g" | grep -q '<d n="ExprNode" t="cls" p="proto/expr.proto" l="7"/>'; then ok "I $q: a path that ends the statement links ExprNode"
    else no "I $q: $g"; fi
done

echo "=== J: key= is the matched path's leaf ==="
out="$( run --for=demo_pb::Missing )"; rc=$?
g="$( printf '%s' "$out" | grep -o '<rung n="gen"[^>]*>' )"
if [ "$rc" != 0 ] || [ -z "$g" ]; then no "J --for=demo_pb::Missing: no gen rung (rc=$rc)"
elif printf '%s' "$g" | grep -q 'key="ExprNode" path="demo_pb::expr::ExprNode" paths="2"'; then ok "J key= and path= name the same path (the first path, demo_pb::Missing, named nothing)"
else no "J key/path disagree: $g"; fi

echo "=== G: no .proto in the tree, no gen rung ==="
rm -f "$FIX/proto/expr.proto"
out="$( ( cd "$FIX" || exit 1; "$BIN" "$FIX" --cache="$TMP/cache2" --for=ExprType ) 2>/dev/null )"; rc=$?
if [ "$rc" != 0 ] || ! printf '%s' "$out" | grep -q '<shortkey'; then no "G no shortkey at all (rc=$rc): the twin arm needs the ladder"
elif printf '%s' "$out" | grep -q 'n="gen"'; then no "G a gen rung printed with no .proto in the tree"
else ok "G no .proto: the ladder has no gen rung"; fi

echo "=== K: a cut list says so (shown=) ==="
KFIX="$TMP/krepo"; mkdir -p "$KFIX/proto" "$KFIX/src"
i=1
while [ "$i" -le 7 ]; do
    printf 'syntax = "proto3";\npackage w%s;\nmessage Widget {\n  string n = 1;\n}\n' "$i" > "$KFIX/proto/w$i.proto"
    i=$(( i + 1 ))
done
printf 'syntax = "proto3";\npackage g;\nmessage Gadget {\n  // a comment line the compressed body drops\n  string n = 1;\n}\n' > "$KFIX/proto/gadget.proto"
cat > "$KFIX/src/lib.rs" <<'RSEOF'
use demo::Widget as WidgetAlias;
use demo::Gadget as GadgetAlias;
pub fn f( w: WidgetAlias, g: GadgetAlias ) -> i32 { 0 }
RSEOF
( cd "$KFIX" && git init -q && git add -A && git -c user.name=t -c user.email=t@example.invalid commit -qm fixture ) || no "K fixture git init failed"
krun(){ ( cd "$KFIX" || exit 1; "$BIN" "$KFIX" --cache="$TMP/kcache" "$@" ) 2>"$TMP/kerr"; }
out="$( krun --for=nowhere::Widget )"; rc=$?
gen="$( printf '%s' "$out" | grep -o '<rung n="gen"[^>]*>' )"
if [ "$rc" != 0 ] || [ -z "$gen" ]; then no "K --for=nowhere::Widget: rc=$rc gen=[$gen]"
elif printf '%s' "$gen" | grep -q 'kept="7"' && printf '%s' "$gen" | grep -q 'shown="6"' && [ "$( printf '%s' "$out" | grep -o '<rung n="gen".*</rung>' | grep -o '<d ' | wc -l | tr -d ' ' )" = 6 ]; then ok "K gen rung: kept=7 shown=6, 6 rows"
else no "K gen rung: $gen"; fi
out="$( krun --for=GadgetAlias )"; rc=$?
gen="$( printf '%s' "$out" | grep -o '<rung n="gen"[^>]*>' )"
if [ "$rc" = 0 ] && printf '%s' "$gen" | grep -q 'kept="1"' && printf '%s' "$gen" | grep -q 'shown="1"'; then ok "K twin: one definition, shown=1"
else no "K twin GadgetAlias (rc=$rc): $gen"; fi

echo "=== L: --compress reaches the gen body ==="
plain="$( krun --for=GadgetAlias )"; rc1=$?
comp="$( krun --for=GadgetAlias --compress )"; rc2=$?
if [ "$rc1" != 0 ] || [ "$rc2" != 0 ]; then no "L --for=GadgetAlias exited $rc1 / $rc2"
else
    if printf '%s' "$plain" | grep -q 'a comment line the compressed body drops' && ! printf '%s' "$plain" | grep -q 'compress='; then ok "L twin: without the flag the body keeps its comment and no compress= prints"
    else no "L plain body: $( printf '%s' "$plain" | grep -o '<shortkey[^>]*>' )"; fi
    if printf '%s' "$comp" | grep -q '<b t="cls"[^>]*n="Gadget"' && ! printf '%s' "$comp" | grep -q 'a comment line the compressed body drops'; then ok "L --compress drops the comment from the gen body"
    else no "L the compressed gen body kept its comment (or printed no body)"; fi
    if printf '%s' "$comp" | grep -q '<shortkey [^>]*compress="1"' && printf '%s' "$comp" | grep -q 'shortkey compress=1:'; then ok "L the block discloses compress=1 and its legend line rides along"
    else no "L no compress disclosure: $( printf '%s' "$comp" | grep -o '<shortkey[^>]*>' )"; fi
fi

echo "=== M: a SCIP index pins no call edge to a .proto definition ==="
MFIX="$TMP/mrepo"; mkdir -p "$MFIX/proto" "$MFIX/go"
printf 'syntax = "proto3";\nmessage Payload {}\n' > "$MFIX/proto/s.proto"
printf 'package use\n\nfunc Build() { Payload() }\nfunc Helper() {}\nfunc Run() { Helper() }\n' > "$MFIX/go/use.go"
python3 - "$ROOT/test/scipfix/make_index.py" "$TMP/m.scip" <<'PYEOF' || no "M could not write the SCIP index"
import importlib.util, sys
spec = importlib.util.spec_from_file_location( "w", sys.argv[ 1 ] ); w = importlib.util.module_from_spec( spec ); spec.loader.exec_module( w )
P = "scip-go gomod demo 1 "
def occ( line1, col, n, sym, roles ):
    return w.occurrence( [ line1 - 1, col, col + n ], P + sym, roles )
go = [ occ( 3, 5, 5, "use/Build().", 1 ), occ( 3, 15, 7, "s/Payload#", 0 ), occ( 4, 5, 6, "use/Helper().", 1 ),
       occ( 5, 5, 3, "use/Run().", 1 ), occ( 5, 13, 6, "use/Helper().", 0 ) ]
pr = [ occ( 2, 8, 7, "s/Payload#", 1 ) ]
docs = [ w.document( "go/use.go", go, [ w.symbol_information( P + s, s ) for s in ( "use/Build().", "use/Helper().", "use/Run()." ) ] ),
         w.document( "proto/s.proto", pr, [ w.symbol_information( P + "s/Payload#", "Payload" ) ] ) ]
open( sys.argv[ 2 ], "wb" ).write( w.index( docs ) )
PYEOF
mrun(){ ( cd "$MFIX" || exit 1; "$BIN" "$MFIX" --no-cache --scip="$TMP/m.scip" "$@" ) 2>"$TMP/merr"; }
out="$( mrun --callers=Helper )"; rc=$?
if [ "$rc" = 0 ] && printf '%s' "$out" | grep -q 'Run'; then ok "M twin: the index's Go-to-Go call is an edge (Run -> Helper)"
else no "M twin --callers=Helper (rc=$rc): $( printf '%s' "$out" | head -c 300 ) $( head -c 300 "$TMP/merr" )"; fi
out="$( mrun --callers=Payload )"; rc=$?
if [ "$rc" != 0 ] || ! printf '%s' "$out" | grep -q '<callers [^>]*of="Payload"'; then no "M --callers=Payload did not resolve the proto message (rc=$rc)"
elif printf '%s' "$out" | grep -q 'Build'; then no "M a SCIP-resolved call to a .proto definition became a caller edge"
else ok "M the .proto definition gains no SCIP caller edge"; fi

echo "=== H: a generic proto name does not displace code from --for (RANK-PROTO) ==="
# 60 schema copies of `message Config` (the envoy/terraform shape: one short generic name in many files) against three code
# functions. A .proto definition is no --for lexical document (model.h kRankFlagNotLexRanked): before RANK-PROTO the 60
# Config rows filled the ranked rows and config_defaults fell to a tail <t> name.
HFIX="$TMP/hrepo"; mkdir -p "$HFIX/proto" "$HFIX/src"
i=1
while [ "$i" -le 60 ]; do
    printf 'syntax = "proto3";\npackage p%s;\nmessage Config {\n  string name = 1;\n}\n' "$i" > "$HFIX/proto/svc$i.proto"
    i=$(( i + 1 ))
done
cat > "$HFIX/src/loader.py" <<'PYEOF'
def load_listener_config(path):
    """Read the listener config file."""
    return open(path).read()

def apply_listener_config(cfg):
    return cfg

def unrelated_helper(x):
    return x + 1

def config_defaults():
    return {}
PYEOF
( cd "$HFIX" && git init -q && git add -A && git -c user.name=t -c user.email=t@example.invalid commit -qm fixture ) || { no "H fixture git init failed"; }
hrun(){ ( cd "$HFIX" || exit 1; "$BIN" "$HFIX" --cache="$TMP/hcache" "$@" ) 2>"$TMP/herr"; }
out="$( hrun --for="where is the listener config loaded" )"; rc=$?
rows="$( printf '%s' "$out" | grep -o '<d [^>]*>' )"
if [ "$rc" != 0 ] || [ -z "$rows" ]; then no "H --for printed no ranked row (rc=$rc)"
else
    if printf '%s' "$rows" | grep -q 'n="config_defaults" p="src/loader.py"'; then ok "H config_defaults keeps a ranked row"
    else no "H config_defaults displaced from the ranked rows: $( printf '%s' "$rows" | grep -o 'n="[^"]*" p="[^"]*"' | head -5 | tr '\n' ' ' )"; fi
    if printf '%s' "$rows" | grep -q 'p="proto/'; then no "H a proto Config competes in --for ranking: $( printf '%s' "$rows" | grep -c 'p="proto/' ) rows"
    else ok "H no proto definition takes a --for ranked row"; fi
fi
# positive twin: the schema definitions stay definitions (--defs counts all 60); --for reaches a schema name through the
# name route and the not-found ladder's gen rung (arms C and D), not through subtoken ranking
out="$( hrun --defs=Config )"; rc=$?
if [ "$rc" = 0 ] && printf '%s' "$out" | grep -q '<name q="Config" defs="60"' && printf '%s' "$out" | grep -q '<d n="Config" t="cls" p="proto/svc'; then ok "H --defs=Config binds the 60 proto definitions"
else no "H --defs=Config (rc=$rc): $( printf '%s' "$out" | grep -o '<name [^>]*>' )"; fi

[ "$fail" = 0 ] && echo "protoindexcheck: ALL PASS" || echo "protoindexcheck: FAIL"
exit "$fail"
