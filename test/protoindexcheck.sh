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
#      oneof, service, rpc; the scope is the owner (ExprNode.Type, ExprService.Evaluate, Type.ADD).
#   B  keywords inside comments and string options never become definitions (positive twin: the real ones exist).
#   C  --whereis and --for name the definition (kind and line).
#   D  a Rust `use … as Alias` and a Go `type Alias = pb.Outer_Leaf` link to the .proto definition through the
#      shortkey gen rung, hedged: via="name", exact="0"; never a proven edge (--callers of the proto def is empty).
#   E  a same-named Rust struct that is not generated keeps its own proven caller; the proto def gains none.
#   F  absence arm with a positive twin: a Rust alias whose leaf no .proto defines links nothing (kept="0").
#   G  a tree with no .proto file prints no gen rung (byte-identical ladder shape).
# Every command whose output an arm reads has its exit code checked; an empty output is a FAIL, never a pass.
#
# Usage: test/protoindexcheck.sh [BIN]   (default build/ripwire). Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
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
EOF
cat > "$FIX/src/lib.rs" <<'EOF'
use demo_pb::expr::expr_node::Type as ExprType;
use demo_pb::expr::{ExprNode as Node, missing_mod::Nowhere as Ghost};

pub struct Datum { pub v: i64 }
impl Datum { pub fn new( v: i64 ) -> Datum { Datum { v } } }

pub fn kind_of( t: ExprType ) -> ExprType { t }
pub fn build() -> Datum { Datum::new( 1 ) }
pub fn ghost( g: Ghost ) -> Ghost { g }
EOF
cat > "$FIX/go/expr.go" <<'EOF'
package expr

import pb "example.com/demo/expr"

type GoExprType = pb.ExprNode_Type

func Kind( t GoExprType ) GoExprType { return t }
EOF
CACHE="$TMP/cache"
run(){ ( cd "$FIX" || exit 1; "$BIN" "$FIX" --cache="$CACHE" "$@" ) 2>"$TMP/err"; }

echo "=== A: definitions, kinds, lines, scopes ==="
want_def(){   # name expected-n expected-t expected-line
    out="$( run --defs="$1" )"; rc=$?
    [ -n "$out" ] || { no "A $1: --defs printed nothing (rc=$rc)"; return; }
    if printf '%s' "$out" | grep -q "<d n=\"$2\" t=\"$3\" p=\"proto/expr.proto:$4\"[^>]* lang=\"proto\""; then ok "A $1 -> $2 t=$3 l=$4"
    else no "A $1: want n=$2 t=$3 l=$4, got: $( printf '%s' "$out" | grep -o '<d [^>]*>' | head -3 )"; fi
}
want_def ExprNode   ExprNode            cls    7
want_def NowRexNode ExprNode.NowRexNode cls    8
want_def Type       ExprNode.Type       cls    9
want_def ADD        Type.ADD            var    11
want_def rex_node   ExprNode.rex_node   cls    14
want_def ExprService ExprService        iface  19
want_def Evaluate   ExprService.Evaluate method 20
out="$( run --defs=ExprNode )"
printf '%s' "$out" | grep -q 'decl_only="1"' && no "A ExprNode reads as a bodyless declaration" || ok "A a message has a body (no decl_only)"

echo "=== B: comment and string keywords are not definitions (twin: A) ==="
for n in CommentedMsg CommentedEnum HiddenSvc HiddenRpc StringMsg; do
    out="$( run --defs="$n" )"; rc=$?
    [ -n "$out" ] || { no "B $n: --defs printed nothing (rc=$rc)"; continue; }
    printf '%s' "$out" | grep -q 'found="0"' && ok "B $n is not a definition" || no "B $n became a definition"
done

echo "=== C: --whereis and --for name the definition ==="
out="$( run --whereis=NowRexNode )"; rc=$?
printf '%s' "$out" | grep -q 'proto/expr.proto' && ok "C --whereis names proto/expr.proto" || no "C --whereis (rc=$rc): $( printf '%s' "$out" | head -c 300 )"
out="$( run --for=ExprService )"; rc=$?
printf '%s' "$out" | grep -q 'p="proto/expr.proto"' && ok "C --for=ExprService serves the proto def" || no "C --for=ExprService (rc=$rc): $( printf '%s' "$out" | head -c 300 )"

echo "=== D: generated names link by name, hedged ==="
out="$( run --for=ExprType )"; rc=$?
gen="$( printf '%s' "$out" | grep -o '<rung n="gen"[^>]*>.*</rung>' | head -1 )"
[ -n "$gen" ] || no "D Rust: no gen rung for --for=ExprType (rc=$rc): $( printf '%s' "$out" | grep -o '<shortkey[^>]*>' )"
printf '%s' "$gen" | grep -q 'via="name"' && printf '%s' "$gen" | grep -q 'exact="0"' && ok "D Rust gen rung is hedged (via=name, exact=0)" || no "D Rust gen rung not hedged: $gen"
printf '%s' "$gen" | grep -q '<d n="ExprNode.Type" t="cls" p="proto/expr.proto" l="9"/>' && ok "D Rust use-as links ExprNode.Type" || no "D Rust use-as: $gen"
printf '%s' "$out" | grep -q 'shortkey gen:' && ok "D the gen legend rides the answer" || no "D gen legend missing"
out="$( run --for=GoExprType )"; rc=$?
printf '%s' "$out" | grep -o '<rung n="gen"[^>]*>.*</rung>' | grep -q 'ExprNode.Type' && ok "D Go alias pb.ExprNode_Type links ExprNode.Type" || no "D Go alias (rc=$rc): $( printf '%s' "$out" | grep -o '<shortkey.*</shortkey>' | head -c 400 )"
out="$( run --for=ExprNode_Type )"; rc=$?
printf '%s' "$out" | grep -o '<rung n="gen"[^>]*>.*</rung>' | grep -q 'ExprNode.Type' && ok "D the Go spelling asked directly links ExprNode.Type" || no "D ExprNode_Type (rc=$rc)"
out="$( run --callers=Type )"; rc=$?
printf '%s' "$out" | grep -q 'kind_of\|Kind' && no "D a by-name gen link became a proven caller edge" || ok "D --callers of the proto enum lists no Rust/Go caller (rc=$rc)"

echo "=== E: a same-named Rust struct keeps its own proven edges ==="
out="$( run --callers=Datum::new )"; rc=$?
printf '%s' "$out" | grep -q 'build' && ok "E Rust Datum::new keeps its caller build" || no "E Datum::new callers (rc=$rc): $( printf '%s' "$out" | head -c 300 )"

echo "=== F: absence with a positive twin ==="
out="$( run --for=Ghost )"; rc=$?
g="$( printf '%s' "$out" | grep -o '<rung n="gen"[^>]*>' )"
[ -n "$g" ] || no "F Ghost: no gen rung at all (rc=$rc) — the absence must be a printed kept=0, not silence"
printf '%s' "$g" | grep -q 'kept="0"' && ok "F an alias no .proto defines links nothing (kept=0); twin = D" || no "F Ghost: $g"

echo "=== G: no .proto in the tree, no gen rung ==="
rm -f "$FIX/proto/expr.proto"
out="$( ( cd "$FIX" || exit 1; "$BIN" "$FIX" --cache="$TMP/cache2" --for=ExprType ) 2>/dev/null )"; rc=$?
printf '%s' "$out" | grep -q '<shortkey' || no "G no shortkey at all (rc=$rc): the twin arm needs the ladder"
printf '%s' "$out" | grep -q 'n="gen"' && no "G a gen rung printed with no .proto in the tree" || ok "G no .proto: the ladder has no gen rung"

[ "$fail" = 0 ] && echo "protoindexcheck: ALL PASS" || echo "protoindexcheck: FAIL"
exit "$fail"
