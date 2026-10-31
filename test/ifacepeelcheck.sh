#!/usr/bin/env bash
# ifacepeelcheck.sh — receiver typing that hands an interface-typed call to the dispatch tier (lane iface-peel, D1 of the
# dispatch-register design): a C++ member written as a smart-pointer ALIAS, and a Rust local initialised by a call whose
# one proven callee returns a trait object.
#
#   test/ifacepeelcheck.sh [BIN]        # BIN defaults to $RIPWIRE_BIN, then build/ripwire
#
# THE GAP. `using FilterSharedPtr = std::shared_ptr<Filter>; FilterSharedPtr handle_; handle_->decodeHeaders()` and
# `let d = state.get_decl( id ); d.run()` (`-> &dyn Command`) were matched by NAME: every in-tree `decodeHeaders` / `run`,
# an inherent namesake (`CallEval::run`, which a `dyn Command` call never reaches) included, as via="name" rows.
#
# THE CONTRACT.
#   * C++ (LangFacts::aliasPeelsSmartPointer): a member written as an alias of std::shared_ptr<I> / std::unique_ptr<I> —
#     `using`, `typedef`, or a plain alias of such an alias (the chain holds at most kAliasPeelDepth = 4 alias DECLARATIONS: the
#     smart alias plus 3 plain ones) — is I through `->`, exactly like a member written `std::shared_ptr<I>`: an interface I
#     declines `gate="iface"` with its implementors counted; a concrete I with no derived class is a typed edge.
#     The alias must be IN SCOPE at the member (resolve.h SmartAliasPeel: the lexical chain, or the written qualifier).
#     Refused (base reading kept): a std pointee, two same-scope aliases that disagree, an alias name that is also a class, a
#     template parameter of that name, a concrete I with derived classes (an override must stay a candidate).
#   * Rust (LangFacts::returnTypedDispatchLet): `let x = r.m( … )` whose call commits ONE proven edge to a callee declared
#     `-> &dyn T` / `-> Box<dyn T>` / `-> impl T` types x as some implementor of T (the dispatch tier then declines or proves).
#     A by-name or declined callee types nothing; a generic `-> R` (R: T) is never read.
#
# ARMS (fixture test/ifacepeelfix: cpp/ rs/). [P] red on a binary without the lane; [N] near misses / controls.
#   P1 C++ using-alias / typedef / alias-of-alias field → <dc gate="iface" cands="2">, no via="name"
#   P2 Rust `let d = s.get_decl( id ); d.run()` and `Box<dyn T>` result → <dc gate="iface">, CallEval::run ABSENT
#   N1 C++ alias of a CONCRETE class → the typed edge to Codec::encodeFrame, never the namesake Other::encodeFrame
#   N2 Rust: the inherent namesake CallEval::run is never a candidate (P2's absence check)
#   N3 Rust: a by-name callee (`s.get_decl` on a generic S) types nothing — base by-name rows unchanged, no iface row
#   N4 C++ `.` on the alias member reaches the smart pointer, never the pointee (`handle_.reset()` with an I::reset: no iface row)
#   N5 C++ alias of std::shared_ptr<std::string> types nothing (an in-tree text::string keeps its base by-name row)
#   N6 Rust: a generic `-> R` (R: Command) is never read as a trait object (no iface row)
#   fix round 1 (B1, scope.h): an alias is read only where it is IN SCOPE at the member (lexical chain: its own class, the
#   enclosing namespaces; a using-directive is NOT followed; or the written qualifier names the alias's namespace)
#   B1a a template PARAMETER named like an alias (another namespace; the same namespace; a concrete pointee) keeps the base reading
#   B1b an alias name that is not visible there (another namespace, a wrong qualifier) keeps the base reading
#   B1c an external using-declaration `using extlib::SpinPtr;` of the name keeps the base reading
#   B1d [P] the same namespace, an enclosing namespace and a written qualifier still peel; a using-directive is NOT followed (floor)
#   S1a the chain cap: an alias reached through 3 plain aliases still peels (ch::V3), 4 do not (ch::V4: the base hedge) — a cap lowered to 2 fails V3
#   S1b the real-class refusal: an alias name that is also an in-tree class (e2::Tank beside f2::Tank) is never peeled
#   S1c the disagreement refusal: two same-scope aliases of one name with different pointees (dis::QPtr) are never peeled
#   S1e a member alias a base class declares (Hz1::HP) is never replaced by a global alias of the same name (Hz2 inherits Hz1)
#   S1d a raw-pointer typedef of the alias's name in another namespace (rp2::Ptr beside rp1::Ptr) is never peeled
#   N1b an alias of a CONCRETE class that has a virtual method derived classes override is no typed pin: the override set stays
#   D1 [fix round 2] "the class is an interface" counts a contract only: a bodyless member that is no constructor / destructor and has
#      no out-of-line definition. A concrete base keeps its override set as hedged candidates (never one typed Base::act pin):
#      D1a methods defined in the .cc, D1b a declared constructor only, D1c a declared destructor only; D1d a pure-virtual interface
#      still declines gate="iface". S1b and L-1 also assert a POSITIVE row (a crash or empty output cannot pass them).
#   L-1 a C member written with the name of a C++ smart alias is a C pointer: the peel is gated on the member's language (lang.c)
#   B1e [P] class-scoped aliases of one name: each member reads its OWN class's (HoldX → iface, HoldY → the typed KyC::kick)
#   R1 [train 42b T-1, rv-iface-delta2 R1] a deleted / defaulted / friend / member-template declaration is no contract: a concrete base whose one bodyless
#      member is `operator= … = delete`, `operator== … = default`, a `friend` declaration or a member-template declaration (its only
#      definition a specialization) keeps its override as a candidate, never one typed Base::act pin (runtime fixture). Twins: a pure
#      virtual written `= 0` and one written through a macro (`#define PURE = 0`, the Envoy spelling) still decline gate="iface".
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$PWD/$BIN"
echo "ifacepeelcheck: BIN=$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
FIX="$ROOT/test/ifacepeelfix"
[ -d "$FIX" ] || { echo "fixture missing: test/ifacepeelfix"; exit 2; }
SCR="$( mktemp -d )"; trap 'rm -rf "$SCR"' EXIT
export HOME="$SCR" TMPDIR="$SCR/"
fail=0
npass=0; nfail=0
say() { if [ "$1" != 1 ]; then fail=1; echo "  FAIL  $2"; nfail=$((nfail+1)); else echo "  PASS  $2"; npass=$((npass+1)); fi; }
callees() { ( cd "$1" && "$BIN" "$1" --no-cache "--callees=$2" </dev/null 2>/dev/null | sed 's/^<!--.*-->//' ); }
has()  { case "$1" in *"$2"*) echo 1;; *) echo 0;; esac; }
hasnt(){ case "$1" in *"$2"*) echo 0;; *) echo 1;; esac; }

CPP="$FIX/cpp"; RS="$FIX/rs"
for f in viaAlias viaTypedef viaChain; do
  o="$( callees "$CPP" "filter.h::ActiveStreamDecoderFilter::$f" )"
  say "$( has "$o" 'n="decodeHeaders"' )" "P1 $f: an iface <dc> row for decodeHeaders"
  case "$o" in *'<dc n="decodeHeaders"'*'cands="2" via="declined" gate="iface"'*) say 1 "P1 $f: cands=2 gate=iface";; *) say 0 "P1 $f: cands=2 gate=iface";; esac
  say "$( hasnt "$o" 'via="name"' )" "P1 $f: no via=name guess"
done
o="$( callees "$CPP" "filter.h::ActiveStreamDecoderFilter::viaConcrete" )"
say "$( has "$o" '<s t="method" n="Codec::encodeFrame" p="filter.h:19"/>' )" "N1 alias of a concrete class: a typed (not by-name) edge to Codec::encodeFrame"
say "$( hasnt "$o" 'Other::encodeFrame' )" "N1 the namesake Other::encodeFrame is gone"
o="$( callees "$CPP" "filter.h::ActiveStreamDecoderFilter::viaDot" )"
say "$( has "$o" 'defs="1"' )" "N4 viaDot resolves to one definition (the negative below cannot pass on an empty answer)"
say "$( hasnt "$o" 'gate="iface"' )" "N4 '.' on the alias member (handle_.reset(): the smart pointer's own) never types it as the pointee (no iface row)"

for f in eval_call eval_boxed; do
  o="$( callees "$RS" "src/lib.rs:$f" )"
  case "$o" in *'<dc n="run"'*'cands="2" via="declined" gate="iface"'*) say 1 "P2 $f: d.run declines gate=iface cands=2";; *) say 0 "P2 $f: d.run declines gate=iface cands=2";; esac
  say "$( hasnt "$o" 'CallEval::run' )" "N2 $f: the inherent namesake CallEval::run is absent"
  say "$( hasnt "$o" 'via="name"' )" "P2 $f: no via=name guess"
done
o="$( callees "$RS" "src/lib.rs:eval_unknown" )"
say "$( hasnt "$o" 'gate="iface"' )" "N3 a by-name callee types nothing (no iface row)"
say "$( has "$o" 'n="Ls::run"' )" "N3 base by-name rows unchanged"
o="$( callees "$CPP" "filter.h:nameLen" )"
say "$( has "$o" '<s t="method" n="string::size" p="filter.h:22" via="name"/>' )" "N5 an alias of shared_ptr<std::string> types nothing: the in-tree namesake text::string stays a by-name row (base reading)"
o="$( callees "$RS" "src/lib.rs:eval_generic" )"
say "$( has "$o" 'defs="1"' )" "N6 eval_generic resolves to one definition"
say "$( hasnt "$o" 'gate="iface"' )" "N6 a generic -> R result is not read as a trait object"
# ---- fix round 1, B1 (scope.h): the alias must be in scope where the member is written ----
isiface() { case "$1" in *'<dc n="'*'cands="2" via="declined" gate="iface"'*) echo 1;; *) echo 0;; esac; }
hedge()   { case "$1" in *'gate="iface"'*) echo 0;; *'via="name"'*) echo 1;; *) echo 0;; esac; }
o="$( callees "$CPP" "scope.h::TmplIface::go" )"
say "$( hedge "$o" )" "B1a a template parameter named like an alias of another namespace keeps the by-name rows (no iface row)"
o="$( callees "$CPP" "scope.h::TmplSame::go" )"
say "$( hedge "$o" )" "B1a a template parameter named like an alias of the SAME namespace keeps the by-name rows"
o="$( callees "$CPP" "scope.h::TmplConc::go" )"
say "$( has "$o" 'Wheel::turn' )" "B1a a template parameter named like a CONCRETE-pointee alias is no typed Motor::turn pin (the namesake Wheel::turn stays)"
o="$( callees "$CPP" "scope.h::NotInScope::go" )"
say "$( hedge "$o" )" "B1b an alias of another namespace is not visible by its bare name"
o="$( callees "$CPP" "scope.h::WrongQual::go" )"
say "$( hedge "$o" )" "B1b a written qualifier that names no scope of the alias keeps the by-name rows"
o="$( callees "$CPP" "scope.h::ExtUser::go" )"
say "$( hedge "$o" )" "B1c an external using-declaration of the name keeps the by-name rows"
for f in SameNs InnerNs GlobalQ; do
  o="$( callees "$CPP" "scope.h::$f::go" )"
  say "$( isiface "$o" )" "B1d $f: the alias in scope still declines gate=iface cands=2"
done
o="$( callees "$CPP" "scope.h::ViaDirective::go" )"
say "$( hedge "$o" )" "B1d a using-directive is not followed (a stated floor): the base by-name rows, never a wrong typed row"
o="$( callees "$CPP" "scope.h::HoldX::goX" )"
say "$( isiface "$o" )" "B1e HoldX: its own class's Ptr (shared_ptr<KxI>) declines gate=iface"
o="$( callees "$CPP" "scope.h::HoldY::goY" )"
say "$( has "$o" 'n="KyC::kick"' )" "B1e HoldY: its own class's Ptr (unique_ptr<KyC>) is the typed KyC::kick"
say "$( hasnt "$o" 'via="name"' )" "B1e HoldY: no by-name guess beside the typed row"
say "$( hasnt "$o" 'KxI1::kick' )" "B1e HoldY: HoldX's pointee never reaches it"
# ---- train 42b CodeRabbit harvest (crharvest.h): a pointer to the alias and an alias of a template parameter keep the base reading ----
o="$( callees "$CPP" "crharvest.h::Ctl::go" )"
say "$( isiface "$o" )" "CR0 control: a member written as the alias still declines gate=iface cands=2"
o="$( callees "$CPP" "crharvest.h::PtrUser::go" )"
say "$( has "$o" 'defs="1"' )" "CR1 PtrUser::go resolves to one definition"
say "$( hasnt "$o" 'gate="iface"' )" "CR1 a POINTER to the smart-pointer alias (RunPtr* p_; p_->peek()) is no pointee typing (no iface row)"
say "$( has "$o" 'via="name"' )" "CR1 the base by-name rows stay"
o="$( callees "$CPP" "crharvest.h::TplHolder::go" )"
say "$( has "$o" 'defs="1"' )" "CR2 TplHolder::go resolves to one definition"
say "$( hasnt "$o" 'gate="iface"' )" "CR2 an alias of shared_ptr<T> where T is the enclosing template PARAMETER named like an in-tree class types nothing"
say "$( has "$o" 'via="name"' )" "CR2 the base by-name rows stay"
# ---- fix round 1, S1 (scope2.h): the guards the contract names each have an arm ----
o="$( callees "$CPP" "scope2.h::Pipe::d0" )"
say "$( isiface "$o" )" "S1a a smart alias itself declines gate=iface"
o="$( callees "$CPP" "scope2.h::Pipe::d3" )"
say "$( isiface "$o" )" "S1a an alias behind 3 plain aliases declines gate=iface (the cap is 4 alias declarations)"
o="$( callees "$CPP" "scope2.h::Pipe::d4" )"
say "$( hedge "$o" )" "S1a an alias behind 4 plain aliases is past the cap: the base by-name rows"
o="$( callees "$CPP" "scope2.h::Rig::go" )"
say "$( hasnt "$o" 'gate="iface"' )" "S1b an alias name that is also a real class (f2::Tank) is never peeled"
say "$( has "$o" '<s t="method" n="Tank::flow" p="scope2.h:29"/>' )" "S1b ... the class's own Tank::flow is the row (positive: a crash or empty output fails)"
o="$( callees "$CPP" "scope2.h::DisUser::go" )"
say "$( hedge "$o" )" "S1c two same-scope aliases with different pointees are never peeled"
o="$( callees "$CPP" "scope2.h::Holder::go" )"
say "$( hedge "$o" )" "S1d a raw-pointer typedef of the alias's name in another namespace is never peeled"
# ---- fix round 1, N1: a concrete pointee whose virtual a derived class overrides keeps the override set ----
o="$( callees "$CPP" "scope2.h::UsesBase2::go" )"
say "$( has "$o" 'Der1::act' )" "N1b an alias of a concrete class with overridden virtuals keeps Der1::act as a candidate (no single typed Base2::act)"
say "$( has "$o" 'Der2::act' )" "N1b ... and Der2::act"
# ---- fix round 1, L-1: the member reader is language-gated like the ingest ----
o="$( callees "$CPP" "lang.c:cgo" )"
say "$( hasnt "$o" 'gate="iface"' )" "L-1 a C struct member named like a C++ smart alias is never read as its pointee (no iface row)"
say "$( has "$o" 'defs="1"' )" "L-1 ... and cgo is found (positive: a crash or an unmatched selector fails)"
o="$( callees "$CPP" "scope2.h::Hz2::go" )"
say "$( hedge "$o" )" "S1e a member of a derived class never takes a global alias when a base class may declare the name"
# ---- fix round 2, D1: only a CONTRACT makes a class an interface (not a ctor, a dtor or a member defined out of line) ----
o="$( callees "$CPP" "scope3.cc:UsesOol::go" )"
say "$( has "$o" 'OolA::act' )" "D1a methods declared in the .h and defined in the .cc: OolA::act stays a candidate (no single typed BaseOol::act)"
say "$( has "$o" 'OolB::act' )" "D1a ... and OolB::act"
o="$( callees "$CPP" "scope3.h::UsesCtor::go" )"
say "$( has "$o" 'CtorA::act' )" "D1b a declared constructor does not make the class an interface: CtorA::act stays"
say "$( has "$o" 'CtorB::act' )" "D1b ... and CtorB::act"
o="$( callees "$CPP" "scope3.h::UsesDtor::go" )"
say "$( has "$o" 'DtorA::act' )" "D1c a declared destructor does not make the class an interface: DtorA::act stays"
say "$( has "$o" 'DtorB::act' )" "D1c ... and DtorB::act"
o="$( callees "$CPP" "scope3.h::UsesPure::go" )"
say "$( isiface "$o" )" "D1d a pure-virtual interface still declines gate=iface cands=2"
say "$( hasnt "$o" 'via="name"' )" "D1d ... with no by-name guess"
# ---- train 42b T-1 (rv-iface-delta2 R1): a bodyless member that is not `= 0` is no contract ----
R1="$SCR/r1"; mkdir -p "$R1"
cat >"$R1/a.h" <<'CPPEOF'
#include <memory>
namespace q {
class BDel { public: BDel& operator=( const BDel& ) = delete; virtual int act( int x ) { return x; } };
class DelA : public BDel { public: int act( int x ) override { return x + 1; } };
class BDef { public: bool operator==( const BDef& ) const = default; virtual int act( int x ) { return x; } };
class DefA : public BDef { public: int act( int x ) override { return x + 1; } };
class BFr { public: friend int peek( const BFr& ); virtual int act( int x ) { return x; } };
class FrA : public BFr { public: int act( int x ) override { return x + 1; } };
class BTm { public: template <typename T> int get( T t ); virtual int act( int x ) { return x; } };
class TmA : public BTm { public: int act( int x ) override { return x + 1; } };
#define PURE = 0
class BPu { public: virtual int act( int x ) = 0; };
class BMa { public: virtual int act( int x ) PURE; };
class MaA : public BMa { public: int act( int x ) override { return x + 1; } };
class MaB : public BMa { public: int act( int x ) override { return x + 2; } };
class PuA : public BPu { public: int act( int x ) override { return x + 1; } };
class PuB : public BPu { public: int act( int x ) override { return x + 2; } };
using BDelPtr = std::shared_ptr<BDel>;
using BDefPtr = std::shared_ptr<BDef>;
using BFrPtr = std::shared_ptr<BFr>;
using BTmPtr = std::shared_ptr<BTm>;
using BPuPtr = std::shared_ptr<BPu>;
using BMaPtr = std::shared_ptr<BMa>;
class UDel { public: int go( int x ) { return b_->act( x ); } BDelPtr b_; };
class UDef { public: int go( int x ) { return b_->act( x ); } BDefPtr b_; };
class UFr { public: int go( int x ) { return b_->act( x ); } BFrPtr b_; };
class UTm { public: int go( int x ) { return b_->act( x ); } BTmPtr b_; };
class UPu { public: int go( int x ) { return b_->act( x ); } BPuPtr b_; };
class UMa { public: int go( int x ) { return b_->act( x ); } BMaPtr b_; };
}
CPPEOF
cat >"$R1/b.cc" <<'CPPEOF'
#include "a.h"
namespace q {
int peek( const BFr& ) { return 0; }
template <> int BTm::get<int>( int t ) { return t; }
}
CPPEOF
o="$( callees "$R1" "a.h::UDel::go" )"
say "$( has "$o" 'DelA::act' )" "R1 an \`= delete\` operator is no contract: DelA::act stays a candidate (no single typed BDel::act)"
o="$( callees "$R1" "a.h::UDef::go" )"
say "$( has "$o" 'DefA::act' )" "R1 an \`= default\` operator is no contract: DefA::act stays"
o="$( callees "$R1" "a.h::UFr::go" )"
say "$( has "$o" 'FrA::act' )" "R1 a friend declaration is no contract: FrA::act stays"
o="$( callees "$R1" "a.h::UTm::go" )"
say "$( has "$o" 'TmA::act' )" "R1 a member-template declaration defined only by a specialization is no contract: TmA::act stays"
o="$( callees "$R1" "a.h::UPu::go" )"
say "$( isiface "$o" )" "R1 twin: a pure-virtual (\`= 0\`) base in the same tree still declines gate=iface"
o="$( callees "$R1" "a.h::UMa::go" )"
say "$( isiface "$o" )" "R1 twin: a pure virtual spelled through a macro (\`PURE\`, Envoy) still declines gate=iface"
echo "ifacepeelcheck: $npass passed, $nfail failed"
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
