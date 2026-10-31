#!/usr/bin/env bash
# fnslotcheck.sh — IX1-V2 (lane fn-slot): FN-VALUED SLOTS in Go — a function stored in a struct FIELD (a keyed composite-literal
# element, a field assignment, a parameter a registrar stores there) and the member call `x.F( … )` through that field; a method
# value of the method's own receiver stored in a variable. Rows: --callers <vr called_by= called_at= via=slot-name cands=>,
# --callees <vs through= slot= targets=>, --for slot_by= / slot_fields= on shown rows. Never a proven call: count= never moves.
#
# Arms tagged [P] were RED on the pre-change binary (train-39 3d03da53b); [G] arms are twins and near-miss negatives that hold on
# both binaries and must keep holding (PROCESS rule 4).
#   A1 [P] a registrar parameter: `RegisterReadWriteCommand( 1, declareKeysPut, Put )` stores Put via `Command{ EvalRW: impl }`
#   A2 [P] a direct keyed element `Command{ EvalRW: Direct }`;  A3 [P] a field assignment `c.EvalRW = Assigned`
#   A4 [P] the callees side lists the slot call and its 3 targets;  A5 [G] count= stays 0 (never a proven call)
#   B1 [P] a method value `f = b.opPlan` of the receiver, called through f in a closure: called_by=Operation
#   N1 [G] `f = other.opPlan` (a parameter, not the receiver) makes no row for Remote.opPlan
#   N2 [G] a field named like a Go METHOD (`h.Close()` beside `(*File).Close`) is no slot call
#   N3 [G] a map literal value is no field slot
#   N4 [G] two same-named registrars in two packages: the bare call `Reg( ambiguous )` binds its OWN package's registrar (fix1 F-1:
#          by-design change — this arm said "decide nothing" while registrars were keyed by the bare name; it now pins the
#          identity, and N4c below keeps the "decide nothing" premise on the shape that still has it)
#   N5 [G] a same-named struct in another package: batcheval.Command's slot_fields= never lists cobra.Command's RunE
#   F1 [P] --for: slot_fields= on the struct row (EvalRW=2: the `c.EvalRW =` store has no type, so it is not this struct's), slot_by= on the stored function, the clause rides;  F2 [G] the A/B handle
#   L1 [P] the compact legend defines cands= when it rides;  J1 [P] the JSON twin carries cands
# fix1 (review rv-fn-slot F-1..F-7; fixture test/fnslotfix2/, its own root so the arms above keep their rows):
#   N6 [P] a same-named function of another package that stores nothing (`other.Enlist( otherFn )`) never feeds the slot (F-1)
#   N6b [G] the twin: the registrar's own package's bare call `Enlist( realFn )` still lands in Task.Do
#   N7 [P] a METHOD registrar `(*Router).Mount` never feeds a bare call `Mount( zero, one )` of another package (F-1)
#   N4c [G] one registrar storing its parameter in two fields (`H{A: fn}`, `H{B: fn}`) decides nothing
#   K1 [P] x/types.Cmd and y/types.Cmd are two slots: K=1 on each struct row (F-2; the call side is name-only, so `@~`)
#   K2 [G] a QUALIFIED literal `enlist.Task{Do: litFn}` keys by the import's directory: Task Do=2 (realFn, litFn)
#   X1 [P] a Go member call never targets a C function-pointer field of the same name (F-3); X1b [P] nor does the C row count it
#   M1 [P] --for marks a field-name-only caller `~` (slot_by="~useA" on fb, A.F vs B.F) and the clause rides (F-4)
#   T1 [P] a named MAP type's keyed literal `Table{OpPut: putTab}` is no field slot (F-5); T1b [G] a struct's still is
#   N3b [G] an unnamed map literal `map[Op]func(){OpGet: getMap}` is no field slot (F-6; pins goValueSlot's ty.empty() guard)
#   Q1 [P] a slot_by= whose only store is in test code (`assertMatch( t, MatchV1 )`) is not printed on a non-test row (F-7)
# part 2 (lane fn-slot-2, Rust; fixture test/fnslotrust/, its own root; model.h kVrSlotLangs Rust row: ParenFieldCall, ModuleType):
#   R1 [P] a registrar path call `CallEval::new( 1, eval_block )` → `Self { stack, eval }` → `(self.eval)( … )` in CallEval::run:
#          called_by="run" via="slot" (typed: `Self` is the impl type on both sides), cands=4
#   R2 [P] a turbofish value `eval_block_generic::<u8>` is the function;  R3 [P] a struct expression `CallEval { eval: direct_eval }`
#   R4 [P] `Box::new( hook_target )` in `Hooks { eval: … }` lands in Hooks.eval (no Box::new argument row);  R4b [G] no row into Box::new
#   R5 [P] --callees: `(self.eval)( … )` prints the typed slot and its 4 targets
#   R6 [P] a path call to a METHOD `Reg::set( r, path_reg_target )` (self = position 0) feeds `self.h = h`, called in Reg::go
#   N8 [G] a local closure of a stored name (`let shadowed = |x| …; CallEval::new( 3, shadowed )`) is no function value: no row
#   N9 [P] a same-named struct of ANOTHER crate (crates/twin CallEval) is another slot: eval_block's cands stays 4, twin_run targets 1
#   N10 [G] (N10a [P]) an enum variant `Msg::Fire { eval: variant_target }` is no struct field slot: no called_by=
#   N11 [G] a method-call registrar `r.set( method_reg_target )` is a floor: no row
#   N12 [P] `x.cb = loose_target` and `(y.cb)( … )` (types not read) join by the field name only: via="slot-name", --for `@~`
#   N13 [P] a store in another file of the crate keys the crate's own CallEval (crate tier), typed: via="slot"
#   R7 [G] a registrar's owner type decides it: `Hooks::new` (stores into Hooks.eval) never feeds CallEval.eval, nor the reverse
#   X2 [G] a Go field of the same name (gox Box.eval) never joins a Rust slot (family guard), nor the reverse
#   F3 [P] --for: slot_fields= per struct (eval=4@CallEval::run, the twin's eval=1@CallEval::twin_run), slot_by= on eval_block
# fix round 1 (review rv-fn-slot-2 F-1..F-4; fixture test/fnslotrust2/, its own root: crates app, lib, qual):
#   E1 [P] `use extcrate::Hook; Hook { cb: f }` is an out-of-tree struct: never the in-tree Hook.cb (F-1)
#   E2 [P] `use tokio::spawn; spawn( f )` is an out-of-tree registrar: never the in-tree `spawn` that stores into Hook.cb (F-1)
#   E3 [P] `std::thread::spawn( f )` is std's: never the in-tree `spawn` (F-1);  E4 [G] the in-tree Hook keeps its own store
#   Q1 [P] `crate::a::Cfg { cb: f }` written in c.rs (which declares its own Cfg) is a.rs's Cfg: called_by="go" (F-2)
#   Q1b [G] the twin: c.rs's bare `Cfg { cb: f }` is its own Cfg (called_by="local_go")
#   Q2 [P] `crate::other::register( f )` beside a local storing `register` is other.rs's (stores nothing): no called_by= (F-2)
#   Q3 [P] `S::new( crate::other::target )` is other.rs's target, never here.rs's namesake (F-2);  Q3b [G] the bare twin
#          `register( local_t )` still lands in S.f
#   Q4 [P] `crate::p::Amb { f }` with two Amb in the crate is p.rs's (the path names the module file): called_by="go_p", typed
#   N14 [G] a BARE `Amb { f }` with two Amb in the crate (neither in the writing file) is never typed: via="slot-name" — kills
#          the source mutant "nearestOf guesses within an ambiguous tier" (review MG1)
#   N15 [G] `(self.inner.f)( … )` is never typed as Self's field: in_t keeps its caller, out_t (Outer.f) is never via="slot" —
#          kills the source mutant "slotCallAt types any self.… chain" (review MG2)
#   N16 [G] a bare CALLEE the enclosing function binds (`fn run( spawn: fn( fn() ) ) { spawn( worker ) }`, `let spawn = |f| f(); spawn( worker )`)
#          is never the in-tree registrar of that name: the argument row prints, no called_by= (CR 4408459928, harvest 463; RED on af8fc25a)
#   W1 [P] `std::sync::Arc::new( f )` is the wrapper by its LAST path segment: the value lands in Dyn.g (F-4)
# fix round 2 (second lens rv-fn-slot-2-lens L-1, L-2; fixture crates selfmod, ga, gx):
#   S1 [P] `use crate::workspace_settings_module::{self, Other}` (module path past SSO) binds the module: `workspace_settings_module::Ws { … }`
#          is that file's Ws, typed (L-1: the `self` branch kept a view into the string it then reassigned)
#   S2 [P] `use crate::{a::{self}}` binds `a`: `a::Sa { … }` is a.rs's Sa, never the writing file's own Sa (L-1 short module)
#   X1 [P] a bare `Gh { … }` in a file with an OUT-OF-TREE glob (`use extcrate::*`) is a guess among crate namesakes: via="slot-name",
#          never typed (L-2 tier 1)
#   X2 [P] a bare `Gw { … }` in a file that `use`s the defining crate by name AND has an out-of-tree glob: the same hedge (L-2 tier 2)
#   X3 [G] a local `Gm` shadows the glob (tier 0: typed);  X4 [G] no glob: the crate namesake stays typed;  X5 [G] an in-tree glob
#          (`use crate::hk::*`) and X6 [G] a glob led by an in-tree crate (`use ga::*`) are not out-of-tree: typed
#   X7 [G] a glob led by a `mod` the file declares, X8 [G] `use super::*`, X9 [G] `use self::Kind::*` are in-tree: typed;
#   X10 [G] tier 2 without a glob (`use ga::Gother` only) stays typed;  X11 [P] a glob inside a brace group
#          (`use extcrate::{Alpha, prelude::*}`) is an out-of-tree glob too: hedged
# FN-SLOT S2 (C/C++; fixture test/fnslotcpp/, its own root; model.h kVrSlotLangs Cpp row memberPointers, kVrSlotMacroCastMark):
#   C1 [P] ninja's ToolFunc table: `{ …, &NinjaMain::ToolBrowse }` in `static const Tool kTools[]` → `(ninja.*options.tool->func)( … )`
#          in real_main: called_by="real_main" via="slot" (typed: options is an Options, Options.tool a Tool), cands=2
#   C2 [P] --callees: the `.*` call prints the typed slot Tool.func and its 2 method targets
#   C3 [P] --for: slot_by="real_main" on NinjaMain::ToolBrowse, slot_fields="func=2@real_main" on Tool
#   C4 [P] a header DECLARATION and its definition: `&Hdr::Run` targets the definition (hdr.cc), never the class's prototype
#          (hdr.h);  C5 [P] a method only declared (`&Hdr::Stop`) targets its declaration
#   N20 [G] two classes named Twin (namespaces a, b; a symbol's scope has no namespace): `&a::Twin::Go` is no row (never a guess)
#   N21 [G] a member pointer in a plain variable `( ninja.*local )( … )` and `->*` (an ERROR node) are no slot calls
#   N22 [G] `&helpers::freeFn` (a namespace function, not a method) is no row (floor);  N23 [G] an inline member-pointer field
#          declarator `int ( Hdr2::*fn )( int )` (an ERROR node) makes no claim
#   X20 [G] a Go field of the same name (x.Hook.cb) never joins the C++ Hook2.cb (family guard), nor the reverse
#   H1 [P] htop's class tables: `.super = { .writeField = Linux_writeField }` nested in a ProcessClass literal keys the path
#          super.writeField (ProcessClass.super is a RowClass) and `As_Row( this )->writeField( … )` keys the macro's cast type:
#          called_by="Row_display" via="slot";  H2 [P] --callees prints the typed slot RowClass_.writeField, 1 target
#   H3 [G] a macro casting to ANOTHER type (As_Other → OtherClass) never targets RowClass's store
#   H4 [P] a macro of another shape (`Get_Klass( this )->writeField`) and H5 [P] a function call root (`row_class_of( this )->…`)
#          join by the field name only: via="slot-name"
# FN-SLOT S2 fix round 1 (reviews rv-fn-slot-s2 F-1..F-5, rv-fn-slot-s2-lens L-1; fixture test/fnslotcpp2/, its own root):
#   V1 [P] a pointer to a VIRTUAL method `&VBase::Act`: every override is a candidate (VDerived::Act, and VDeeper::Act two levels down)
#          gets called_by="dispatch_v";  V2 [P] a pure virtual's override gets it too;  V3 [P] the pure virtual's bodyless declaration
#          is never a target (5 targets: the three Act bodies, VDerived::Pure, VBase::Plain);  V4 [P] a method a derived class HIDES:
#          `&HBase::sh` lists both (a hedge);  V5 [G] `&HDer::sh` names HDer's own only;  V6 [P] a pure base method whose override is only
#          DECLARED in the tree: the candidate is the override's declaration, never the base's bodyless one
#   E1 [P] `&grpc::Server::start` (the header is not indexed) never binds the in-tree mine::Server (qualified spelling); E1b [P] nor
#          does a bare `&Server::start` under `using grpc::Server;`;  E1c [P] nor under `using namespace grpc;` (a bare Server
#          outside mine::);  E1d [P] nor `&other::inner::Deep::run` beside the in-tree outer::inner::Deep;  E1e [P] nor `&::Server::stop`
#          (the global-anchored spelling of a class that sits in mine::)
#   E1f [P] a namesake namespace that only ENDS with the qualifier's text (`&grpc::GServer::gstart` beside the in-tree mygrpc::GServer)
#          binds nothing (the :: boundary of the suffix match; fix round 2, rv-fss2-delta D-2)
#   E6 [P] (CR 4415276397) a CLASS-MEMBER using-declaration (`struct D : B { using B::B; };`, inheriting constructors) before a bare
#          `&B::m` does not decline it as an external class (it names a member, not a class reachable by a bare spelling)
#   I7 [P] a dependent base that is a template PARAMETER named like an in-tree class (`template <class DBase> struct Mixin : DBase`):
#          `&Mixin<DReal>::dfoo` names no DBase::dfoo (fix round 2, rv-fss2-delta D-1)
#   E4 [P] the in-tree class is GLOBAL (GSrv) and `using ext::GSrv;` makes the bare spelling the external one;  E4b [G] the same bare
#          spelling without the using stays typed;  E5 [G] `using namespace mine;` makes a bare `&Server::both` outside mine typed
#   E2 [G] `&mine::Server::stop`, the bare `&Server::stop` written inside `namespace mine`, an out-of-line `int mine::Server::both()`
#          writing `&Server::start`, `&::mine::Server::start` stay typed;  E3 [G] nested (`outer::inner::Deep`, the suffix `inner::Deep`),
#          C++17 nested (`c1::c2::Pair`, `c2::Pair`), an anonymous namespace (`Anon`) and an inline namespace (`v0::Ver`) stay typed
#   I1 [P] an INHERITED method `&ID::inh` (defined in IB) and I2 [P] a CRTP base method `&ICD::crt` (defined in ICB<ICD>) name the
#          base's definition;  I3 [G] two bases at one level declaring dup: no target;  I4 [G] a base outside the tree: no target (a floor);
#          I5 [G] an overloaded name lists every overload (targets= counts definitions);  I6 [G] the derived class's own method stays typed
#   N24 [G] a C++ METHOD call on a call result `f()->mr_write( … )` beside a function-pointer field of that name is no slot call
#          (kills the everyFieldCall mutant: the guard that keeps the macro-cast receiver to C)
#   L1 [P] a nested store the designator climb cannot type (6 deep) hides behind the typed tier: the site says slot_name_also="1" (XML
#          and --json);  L2 [G] --callers still says via="slot-name" for it;  L3 [G] a typed-only site prints no slot_name_also
#   F4 [P] --for slot_fields=: the cap of 4 cuts the least informative field, never the one a caller calls through (zzw=3@run_zzw)
#
# Usage: bash test/fnslotcheck.sh [BIN]   (BIN defaults to RIPWIRE_BIN, then build/ripwire)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "fnslotcheck: BIN=$BIN ($( "$BIN" --version 2>/dev/null | grep -o 'built_from=[^)]*' ))"
[ -x "$BIN" ] || { echo "  FAIL  no ripwire binary at $BIN"; exit 2; }
FIX="$ROOT/test/fnslotfix"
[ -d "$FIX" ] || { echo "  FAIL  fixture dir missing: $FIX"; exit 2; }
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
run(){
    local out rc
    out="$( cd "$FIX" && "$BIN" "$FIX" "$@" --no-cache 2>/dev/null )"; rc=$?
    if [ "$rc" -ne 0 ] || ! printf '%s' "$out" | grep -q -e '<callers ' -e '<callees ' -e '<ctx ' -e '"of":'; then
        printf 'RUNFAIL rc=%s' "$rc"; return 0
    fi
    printf '%s' "$out"
}
has(){ case "$2" in RUNFAIL*) no "$1 (the run failed: $2)"; return;; esac
       if printf '%s' "$2" | grep -qF -- "$3"; then ok "$1"; else no "$1 — missing: $3"; fi; }
hasnt(){ case "$2" in RUNFAIL*) no "$1 (the run failed: $2)"; return;; esac
         if printf '%s' "$2" | grep -qF -- "$3"; then no "$1 — unexpected: $3"; else ok "$1"; fi; }

o="$( run --callers=Put )"
has   "A1 a registrar parameter lands Put in Command.EvalRW, joined to the member call" "$o" 'into="RegisterReadWriteCommand#arg2" called_by="evaluateCommand" called_at="batcheval/evaluate.go:8" via="slot-name" cands="3"'
has   "A5 never a proven call: count stays 0" "$o" 'count="0"'
has   "L1 the compact legend defines cands= beside it" "$o" 'vr cands=K:'
o="$( run --callers=Direct )"
has   "A2 a keyed composite-literal element" "$o" 'into="direct.EvalRW" called_by="evaluateCommand"'
o="$( run --callers=Assigned )"
has   "A3 a field assignment" "$o" 'into="c.EvalRW" called_by="evaluateCommand"'
o="$( run --callees=evaluateCommand )"
has   "A4 the callees side: the slot call and its targets" "$o" '<vs l="8" through="cmd.EvalRW" slot=".EvalRW" via="slot-name" targets="3" shown="3"><t n="Assigned" p="batcheval/cmd_put.go:13"/><t n="Direct" p="batcheval/cmd_put.go:9"/><t n="Put" p="batcheval/cmd_put.go:7"/></vs>'
o="$( run --callers=local/backend.go:Local.opPlan )"
has   "B1 a method value of the receiver, called through the local in a closure" "$o" 'into="f" called_by="Operation"'
hasnt "N1b and no row binds it to the receiver's type either" "$o" 'bind="local/backend.go:19"'
o="$( run --callers=Remote.opPlan )"
hasnt "N1 a method value of a non-receiver parameter makes no row" "$o" '<vr '
o="$( run --callers=closeHook )"
has   "N2a the stored value still prints" "$o" 'into="hooks.Close"'
hasnt "N2 a field named like a Go method is no slot call" "$o" 'called_by='
o="$( run --callers=doneHook )"
hasnt "N3 a map literal value is no field slot" "$o" 'via="slot'
o="$( run --callers=ambiguous )"
has   "N4a the argument row prints" "$o" 'into="Reg#arg0"'
has   "N4 the bare call binds its own package's registrar (misc2.Reg → Hooks2.OnFail)" "$o" 'called_by="fire"'
hasnt "N4b never the other package's registrar's field" "$o" 'useHooks'
o="$( run '--for=how does evaluateCommand run the Command EvalRW of Put' )"
row(){ printf '%s' "$1" | grep -o "<d [^>]*n=\"$2\" p=\"$3\"[^>]*>" | head -1; }   # row ANSWER NAME PATH: that row's head
has   "F1a slot_fields= on batcheval.Command (the caller joins by the field name: @~)" "$( row "$o" Command batcheval/command.go )" 'slot_fields="DeclareKeys=1,EvalRW=2@~evaluateCommand"'
hasnt "N5 batcheval.Command never lists cobra.Command's field" "$( row "$o" Command batcheval/command.go )" 'RunE'
has   "F1b slot_by= on the stored function (field-name join: ~)" "$( row "$o" Put batcheval/cmd_put.go )" 'slot_by="~evaluateCommand"'
has   "F1c the clause rides beside the attributes" "$o" 'd slot_by= functions that MAY call this one'
o="$( RIPWIRE_NO_SLOT_JOIN_ROWS=1 run '--for=how does evaluateCommand run the Command EvalRW of Put' )"
hasnt "F2 the A/B handle turns the rows and the clause off" "$o" 'slot_by'
o="$( run --callers=Put --json )"
has   "J1 the JSON twin carries cands" "$o" '"cands":"3"'

FIX="$ROOT/test/fnslotfix2"
[ -d "$FIX" ] || { echo "  FAIL  fixture dir missing: $FIX"; exit 2; }
o="$( run --callers=otherFn )"
has   "N6a the argument row prints" "$o" 'into="Enlist#arg0"'
hasnt "N6 a same-named function of another package that stores nothing never feeds the slot" "$o" 'called_by='
o="$( run --callers=realFn )"
has   "N6b the registrar's own package's bare call still lands in Task.Do" "$o" 'into="Enlist#arg0" called_by="execTasks"'
o="$( run --callers=one )"
has   "N7a the argument row prints" "$o" 'into="Mount#arg1"'
hasnt "N7 a METHOD registrar never feeds a bare call of another package" "$o" 'called_by='
o="$( run --callers=amb )"
has   "N4c-a the argument row prints" "$o" 'into="Hold#arg0"'
hasnt "N4c one registrar storing its parameter in two fields decides nothing" "$o" 'called_by='
o="$( run '--for=how does execX run the Cmd Run of runX and runY' )"
has   "K1 x/types.Cmd holds one function" "$( row "$o" Cmd x/types/t.go )" 'slot_fields="Run=1@~execX"'
has   "K1b y/types.Cmd holds one function" "$( row "$o" Cmd y/types/t.go )" 'slot_fields="Run=1@'
o="$( run '--for=how does execTasks run the Task Do of realFn and litFn' )"
has   "K2 a qualified literal keys by its import's directory" "$( row "$o" Task enlist/reg.go )" 'slot_fields="Do=2@~execTasks"'
o="$( run --callees=goCall )"
has   "X1a the Go slot call prints" "$o" 'through="x.draw"'
hasnt "X1 a Go member call never targets a C function-pointer field" "$o" 'n="cdraw"'
o="$( run --callers=cdraw )"
has   "X1c the C row keeps its own typed caller" "$o" 'called_by="cfire" called_at="cx/ops.c:4" via="slot"'
hasnt "X1b the C row counts no Go caller" "$o" 'slot_name_also='
o="$( run '--for=how does useA call fa fb through field F of A and B' )"
has   "M1 a field-name-only caller is marked ~" "$( row "$o" fb p/p.go )" 'slot_by="~useA"'
has   "M1b the mark's clause rides" "$o" 'C matches the field name only'
o="$( run --callers=putTab )"
has   "T1a the stored value prints" "$o" 'into="t.OpPut"'
hasnt "T1 a named map type's keyed literal is no field slot" "$o" 'called_by='
o="$( run --callers=opsFn )"
has   "T1b a struct's keyed literal still is" "$o" 'into="o.OpPut" called_by="callOps"'
o="$( run --callers=getMap )"
has   "N3b-a the stored value prints" "$o" 'into="t.OpGet"'
hasnt "N3b an unnamed map literal is no field slot" "$o" 'called_by='
o="$( run '--for=how is MatchV1 scored and matched' )"
has   "Q1a the MatchV1 row is shown" "$o" 'n="MatchV1" p="fzt/algo.go"'
hasnt "Q1 a test-only store prints no slot_by=" "$( row "$o" MatchV1 fzt/algo.go )" 'slot_by='
# CR 4396503857 (train 40): a Go directory whose FIRST file is no .go file (enlist/README.md sorts before reg.go) keys its types all the same
if [ -f "$FIX/enlist/README.md" ]; then ok "K3a the fixture directory is led by a non-Go file"; else no "K3a enlist/README.md is missing: K3 would prove nothing"; fi
o="$( run '--for=how does execTasks run the Task Do of realFn and litFn' )"
has   "K3 a package directory led by README.md still keys enlist.Task: the qualified literal lands (Do=2, not the unknown-type drop)" "$( row "$o" Task enlist/reg.go )" 'slot_fields="Do=2@~execTasks"'
# CR 4396503829 (train 40): a caller whose NAME holds a `~` (C++ operator~) is not a field-name-only caller: no ~ clause rides
o="$( run '--for=how does tfire call tdrawImpl through tdraw' )"
has   "T2a the operator~ caller is printed" "$( row "$o" tdrawImpl tilde/t.cpp )" 'operator~'
hasnt "T2 a typed caller named operator~ never raises the field-name-only clause" "$o" 'matches the field name only'
hasnt "T2b nor the long form of it" "$o" 'a ~ before a slot_by= name'

FIX="$ROOT/test/fnslotrust"
[ -d "$FIX" ] || { echo "  FAIL  fixture dir missing: $FIX"; exit 2; }
o="$( run --callers=eval_block )"
has   "R1 a registrar path call lands in the typed slot its parameter is stored in" "$o" 'into="CallEval::new#arg1" called_by="run" called_at="src/engine/eval.rs:14" via="slot" cands="4"'
o="$( run --callers=eval_block_generic )"
has   "R2 a turbofish value is the function" "$o" 'into="CallEval::new#arg1" called_by="run"'
o="$( run --callers=direct_eval )"
has   "R3 a struct expression's field value" "$o" 'into="CallEval.eval" called_by="run" called_at="src/engine/eval.rs:14" via="slot"'
o="$( run --callers=hook_target )"
has   "R4 Box::new( f ) lands in the field" "$o" 'into="Hooks.eval" called_by="fire" called_at="src/other/hooks.rs:11" via="slot"'
hasnt "R4b no argument row into the Box::new wrapper" "$o" 'into="Box::new'
o="$( run --callees=CallEval::run )"
has   "R5 the (self.eval)( … ) call prints its typed slot and targets" "$o" 'through="self.eval" slot="CallEval.eval" via="slot" targets="4"'
o="$( run --callers=path_reg_target )"
has   "R6 a path call to a method counts self as position 0" "$o" 'into="Reg::set#arg1" called_by="go" called_at="crates/twin/src/lib.rs:60" via="slot"'
o="$( run --callers=shadowed )"
hasnt "N8 a local closure of a stored name is no function value" "$o" '<vr '
o="$( run --callers=twin_target )"
has   "N9 the twin crate's CallEval is its own slot" "$o" 'into="CallEval::new#arg0" called_by="twin_run" called_at="crates/twin/src/lib.rs:11" via="slot"'
hasnt "N9b the twin's value is not counted with the other crate's" "$o" 'cands='
o="$( run --callees=CallEval::twin_run )"
has   "N9c the twin's call targets its one function" "$o" 'slot="CallEval.eval" via="slot" targets="1"'
o="$( run --callers=variant_target )"
has   "N10a the variant store prints" "$o" 'into="Msg::Fire.eval"'
hasnt "N10 an enum variant field is no struct slot" "$o" 'called_by='
o="$( run --callers=method_reg_target )"
hasnt "N11 a method-call registrar is a floor" "$o" '<vr '
o="$( run --callers=loose_target )"
has   "N12 untyped receivers join by the field name only" "$o" 'into=".cb" called_by="call_loose" called_at="crates/twin/src/lib.rs:48" via="slot-name"'
o="$( run --callers=crate_tier_target )"
has   "N13 a store in another file of the crate keys the crate's struct" "$o" 'into="CallEval.eval" called_by="run" called_at="src/engine/eval.rs:14" via="slot"'
o="$( run --callees=Hooks::fire )"
has   "R7 Hooks.eval holds only its own store (Hooks::new feeds nothing else)" "$o" 'slot="Hooks.eval" via="slot" targets="1"'
o="$( run --callees=CallEval::run )"
has   "R7b CallEval.eval holds its four functions (crate tier included)" "$o" 'slot="CallEval.eval" via="slot" targets="4"'
o="$( run --callers=goTarget )"
has   "X2a the Go slot keeps its own call" "$o" 'called_by="fire" called_at="gox/g.go:11" via="slot-name"'
hasnt "X2 a Go value never counts a Rust slot's functions" "$o" 'cands='
o="$( run --callees=SnHold::fire )"
has   "L4 a Rust typed slot discloses the name-only store behind it (slot_name_also rides beyond C/C++)" "$o" 'slot="SnHold.snfn" via="slot" slot_name_also="1" targets="1" shown="1"'
o="$( run --callees=SnHold::fire --json )"
has   "L4j the --json twin carries it" "$o" '"slot_name_also":1'
o="$( run '--for=how CallEval runs eval_block' )"
has   "F3 slot_fields= on the crate's CallEval" "$( row "$o" CallEval src/engine/eval.rs )" 'slot_fields="eval=4@CallEval::run"'
has   "F3b slot_fields= on the twin crate's CallEval" "$( row "$o" CallEval crates/twin/src/lib.rs )" 'slot_fields="eval=1@CallEval::twin_run"'
has   "F3c slot_by= on the stored function (typed: no ~)" "$( row "$o" eval_block src/engine/eval.rs )" 'slot_by="CallEval::run"'
has   "X2b the Go struct row keeps its own name-tier caller" "$( row "$o" Box gox/g.go )" 'slot_fields="eval=1@~Box.fire"'
FIX="$ROOT/test/fnslotrust2"
[ -d "$FIX" ] || { echo "  FAIL  fixture dir missing: $FIX"; exit 2; }
o="$( run --callers=worker_ext_struct )"
has   "E1a the out-of-tree struct store still prints" "$o" 'into="Hook.cb"'
hasnt "E1 an out-of-tree struct is never the in-tree Hook" "$o" 'called_by='
o="$( run --callers=worker_bare_ext )"
has   "E2a the argument row still prints" "$o" 'into="spawn#arg0"'
hasnt "E2 a used out-of-tree registrar is never the in-tree spawn" "$o" 'called_by='
o="$( run --callers=worker_path_ext )"
hasnt "E3 std::thread::spawn is never the in-tree spawn" "$o" 'called_by='
o="$( run --callers=lib_target )"
has   "E4 the in-tree Hook keeps its own store" "$o" 'into="Hook.cb" called_by="fire" called_at="crates/lib/src/lib.rs:3" via="slot"'
o="$( run --callers=fc_qualified )"
has   "Q1 a crate:: path to a struct is the module file's struct" "$o" 'called_by="go" called_at="crates/qual/src/a.rs:3" via="slot"'
hasnt "Q1c never the writing file's own namesake" "$o" 'local_go'
o="$( run --callers=fc_local )"
has   "Q1b the bare twin is the file's own struct" "$o" 'called_by="local_go" called_at="crates/qual/src/c.rs:3" via="slot"'
o="$( run --callers=qual_t )"
has   "Q2a the argument row still prints" "$o" 'into="register#arg0"'
hasnt "Q2 a crate:: registrar path is never the local namesake" "$o" 'called_by='
o="$( run --callees=S::go )"
has   "Q3 a crate:: value path is the module file's function" "$o" '<t n="target" p="crates/qual/src/other.rs:1"/>'
hasnt "Q3c never the writing file's own namesake" "$o" '<t n="target" p="crates/qual/src/here.rs:3"/>'
has   "Q3b the bare registrar twin still lands in S.f" "$o" '<t n="local_t" p="crates/qual/src/here.rs:5"/>'
o="$( run --callers=amb_t )"
has   "Q4 crate::p::Amb is p.rs's Amb, typed" "$o" 'into="Amb.f" called_by="go_p" called_at="crates/qual/src/p.rs:2" via="slot"'
o="$( run --callers=amb_bare_t )"
has   "N14a the bare store joins by the field name" "$o" 'via="slot-name"'
hasnt "N14 an ambiguous crate tier is never typed" "$o" 'via="slot"'
o="$( run --callers=in_t )"
has   "N15a (self.inner.f)( … ) keeps Inner.f's caller" "$o" 'into="Inner.f" called_by="go_inner"'
o="$( run --callers=out_t )"
hasnt "N15 (self.inner.f)( … ) is never typed as Self's field" "$o" 'via="slot"'
o="$( run --callers=arc_t )"
has   "W1 std::sync::Arc::new( f ) hands the value to the field" "$o" 'into="Dyn.g" called_by="go" called_at="crates/qual/src/wrap.rs:2" via="slot"'
hasnt "W1b no argument row into the Arc::new wrapper" "$o" 'into="Arc::new'
o="$( run --callers=self_long_t )"
has   "S1 {self} of a long module path binds the module" "$o" 'into="Ws.scb" called_by="fire_ws" called_at="crates/selfmod/src/workspace_settings_module.rs:2" via="slot"'
hasnt "S1b never the writing file's own Ws" "$o" 'fire_ws_local'
o="$( run --callers=self_short_t )"
has   "S2 {self} of a short module path binds the module" "$o" 'into="Sa.acb" called_by="fire_sa" called_at="crates/selfmod/src/a.rs:2" via="slot"'
hasnt "S2b never the writing file's own Sa" "$o" 'fire_sa_local'
o="$( run --callers=glob_t1 )"
has   "X1a the store still prints, joined by the field name" "$o" 'into="Gh.hcb" called_by="fire_gh"'
has   "X1 an out-of-tree glob hedges the crate tier: slot-name" "$o" 'via="slot-name"'
hasnt "X1b never typed" "$o" 'via="slot"'
o="$( run --callers=glob_t2 )"
has   "X2a the store still prints, joined by the field name" "$o" 'into="Gw.wcb" called_by="fire_ga"'
has   "X2 an out-of-tree glob hedges the used-crate tier: slot-name" "$o" 'via="slot-name"'
hasnt "X2b never typed" "$o" 'via="slot"'
o="$( run --callers=glob_loc_t )"
has   "X3 a local struct shadows the glob: typed" "$o" 'into="Gm.mcb" called_by="fire_gm_local" called_at="crates/gx/src/g3.rs:3" via="slot"'
o="$( run --callers=plain_t )"
has   "X4 no glob: the crate namesake stays typed" "$o" 'into="Gh.hcb" called_by="fire_gh" called_at="crates/gx/src/hk.rs:2" via="slot"'
o="$( run --callers=intree_glob_t )"
has   "X5 an in-tree glob is no out-of-tree glob: typed" "$o" 'into="Gh.hcb" called_by="fire_gh" called_at="crates/gx/src/hk.rs:2" via="slot"'
o="$( run --callers=crate_glob_t )"
has   "X6 a glob led by an in-tree crate: typed" "$o" 'into="Gw.wcb" called_by="fire_ga" called_at="crates/ga/src/lib.rs:2" via="slot"'
o="$( run --callers=mod_glob_t )"
has   "X7 a glob led by a mod the file declares: typed" "$o" 'into="Gh.hcb" called_by="fire_gh" called_at="crates/gx/src/hk.rs:2" via="slot"'
o="$( run --callers=super_glob_t )"
has   "X8 use super::*: typed" "$o" 'into="Gh.hcb" called_by="fire_gh" called_at="crates/gx/src/hk.rs:2" via="slot"'
o="$( run --callers=self_glob_t )"
has   "X9 use self::Kind::*: typed" "$o" 'into="Gh.hcb" called_by="fire_gh" called_at="crates/gx/src/hk.rs:2" via="slot"'
o="$( run --callers=used_crate_t )"
has   "X10 tier 2 without a glob stays typed" "$o" 'into="Gw.wcb" called_by="fire_ga" called_at="crates/ga/src/lib.rs:2" via="slot"'
o="$( run --callers=nested_glob_t )"
has   "X11 a glob inside a brace group hedges: slot-name" "$o" 'into="Gh.hcb" called_by="fire_gh" called_at="crates/gx/src/hk.rs:2" via="slot-name"'
hasnt "X11b never typed" "$o" 'via="slot"'
o="$( run --callers=worker_param_callee )"
has   "N16a a parameter called with a function still prints the argument row" "$o" 'into="spawn#arg0"'
hasnt "N16 a parameter named like an in-tree registrar is never that registrar" "$o" 'called_by='
o="$( run --callers=worker_local_callee )"
has   "N16c a local closure called with a function still prints the argument row" "$o" 'into="spawn#arg0"'
hasnt "N16b a local closure named like an in-tree registrar is never that registrar" "$o" 'called_by='

FIX="$ROOT/test/fnslotcpp"
[ -d "$FIX" ] || { echo "  FAIL  fixture dir missing: $FIX"; exit 2; }
o="$( run --callers=ToolBrowse )"
has   "C1 &NinjaMain::ToolBrowse in the Tool table joins the .* call, typed" "$o" 'into="kTools[0][3]" called_by="real_main" called_at="src/tool.cc:33" via="slot" cands="2"'
o="$( run --callees=real_main )"
has   "C2 the .* call prints the typed slot and its 2 targets" "$o" 'through="(ninja.*options.tool-&gt;func)" slot="Tool.func" via="slot" targets="2" shown="2"><t n="NinjaMain.ToolBrowse" p="src/tool.cc:16"/><t n="NinjaMain.ToolClean" p="src/tool.cc:17"/>'
o="$( run '--for=how does real_main run the Tool func ToolBrowse' )"
has   "C3a slot_by= on the stored method" "$( row "$o" NinjaMain::ToolBrowse src/tool.cc )" 'slot_by="real_main"'
has   "C3b slot_fields= on the Tool struct" "$( printf '%s' "$o" | grep -o '<d [^>]*n="Tool" sc="Tool" p="src/tool.cc"[^>]*>' | head -1 )" 'slot_fields="func=2@real_main"'
o="$( run --callees=go_hdr )"
has   "C4 &Hdr::Run targets its definition" "$o" '<t n="Hdr.Run" p="src/hdr.cc:2"/>'
hasnt "C4b never the class's prototype of Run" "$o" '<t n="Hdr.Run" p="src/hdr.h:1"/>'
has   "C5 a method only declared targets its declaration" "$o" '<t n="Hdr.Stop" p="src/hdr.h:1"/>'
o="$( run --callers=Go )"
hasnt "N20 two classes named Twin: &a::Twin::Go is no row" "$o" '<vr '
o="$( run --callees=plain_var )"
hasnt "N21 a member pointer in a plain variable, and ->*, are no slot calls" "$o" '<vs '
o="$( run --callers=freeFn )"
hasnt "N22 &helpers::freeFn (a namespace function) is no row" "$o" '<vr '
o="$( run --callers=Walk )"
hasnt "N23 an inline member-pointer field declarator makes no claim" "$o" 'called_by='
o="$( run --callers=goTool )"
hasnt "X20 the Go Hook.cb never joins a C++ cb field" "$o" 'fire_h2'
o="$( run --callers=cpp_cb )"
has   "X20a the C++ store keeps its own typed caller" "$o" 'called_by="fire_h2" called_at="src/twin_b.cc:6" via="slot"'
hasnt "X20b nor does the Go call reach it" "$o" 'fireGo'
o="$( run --callers=Linux_writeField )"
has   "H1 a nested designated store meets the macro-cast call, typed" "$o" 'into="LinuxProcess_class.super.writeField" called_by="Row_display" called_at="c/row.c:2" via="slot"'
o="$( run --callees=Row_display )"
has   "H2 the macro-cast call prints the typed slot, 1 target" "$o" 'slot="RowClass_.writeField" via="slot" targets="1" shown="1"><t n="Linux_writeField" p="c/linux.c:2"/>'
o="$( run --callees=Other_display )"
hasnt "H3 a macro casting to another type never targets RowClass's store" "$o" 'Linux_writeField'
o="$( run --callees=Klass_display )"
has   "H4 a macro of another shape joins by the field name" "$o" 'slot=".writeField" via="slot-name"'
o="$( run --callees=Fn_display )"
has   "H5 a function call root joins by the field name" "$o" 'slot=".writeField" via="slot-name"'
# P: a --path whose TARGET is a slot target (train 41b, ninja `--path=real_main,ToolBrowse`, htop `--path=Row_display,LinuxProcess_rowWriteField`):
# the bridge row carries the slot hedge; the from= body would be a call through a field, no call to the target, so no route body rides (it
# printed without via=slot and cost 4-5 KB). The slot crossing in the MIDDLE of a route keeps its hedged body (hopbodycheck R9).
runp(){
    local out rc
    out="$( cd "$FIX" && "$BIN" "$FIX" "$@" --no-cache 2>/dev/null )"; rc=$?
    if [ "$rc" -ne 0 ] || ! printf '%s' "$out" | grep -q '<path '; then printf 'RUNFAIL rc=%s' "$rc"; return 0; fi
    printf '%s' "$out"
}
o="$( runp --path=real_main,ToolBrowse )"
has   "P1 ninja shape: the bridge names the slot crossing, hedged" "$o" 'n="ToolBrowse" p="src/tool.cc:16" via="slot" slot_callers="1" slot_fns="2"'
hasnt "P1b no route body for the caller of a slot into to=" "$o" '<bodies of="route"'
has   "P1c reachable=0 and the follow-up still names --callers" "$o" 'next="--callers=ToolBrowse"'
o="$( runp --path=Row_display,Linux_writeField )"
has   "P2 htop shape: the bridge names the slot crossing, hedged" "$o" 'n="Linux_writeField" p="c/linux.c:2" via="slot" slot_callers="1" slot_fns="1"'
hasnt "P2b no route body for the caller of a slot into to=" "$o" '<bodies of="route"'
o="$( runp --path=real_main,ToolBrowse --legend=full )"
hasnt "P3 the route-body legend clause is absent when no route body rides" "$o" 'bodies of=route proven=0'
FIX="$ROOT/test/fnslotcpp2"
[ -d "$FIX" ] || { echo "  FAIL  fixture dir missing: $FIX"; exit 2; }
o="$( run --callers=VDerived::Act )"
has   "V1 an override of a virtual method is a candidate of &VBase::Act" "$o" 'called_by="dispatch_v" called_at="virt.cc:26" via="slot"'
o="$( run --callers=VDeeper::Act )"
has   "V1b a two-level override too" "$o" 'called_by="dispatch_v"'
o="$( run --callers=VDerived::Pure )"
has   "V2 a pure virtual's override is the candidate of &VBase::Pure" "$o" 'called_by="dispatch_v"'
o="$( run --callees=dispatch_v )"
has   "V3 the candidate set: 3 Act bodies, VDerived::Pure, VBase::Plain" "$o" 'slot="VEnt.fn" via="slot" targets="5" shown="5"'
hasnt "V3b the pure virtual's bodyless declaration is never a target" "$o" '<t n="VBase.Pure"'
o="$( run --callees=go_hbase )"
has   "V4 a hidden non-virtual method: the base's pointer lists both (a hedge)" "$o" '<t n="HDer.sh" p="virt.cc:'
has   "V4b and the base's own" "$o" '<t n="HBase.sh" p="virt.cc:'
o="$( run --callees=go_hder )"
hasnt "V5 the derived class's pointer names its own only" "$o" '<t n="HBase.sh"'
o="$( run --callees=go_pv )"
has   "V6 a declared-only override is the candidate of a pure base method" "$o" '<t n="PD.pv"'
hasnt "V6b never the base's bodyless declaration" "$o" '<t n="PB.pv"'
o="$( run --callers=GSrv::gs_start )"
hasnt "E4 a using-declaration of an external class beside an in-tree global one of that name binds nothing" "$o" 'called_by="go_gdecl"'
has   "E4b the same bare spelling without the using stays typed" "$o" 'called_by="go_gok"'
o="$( run --callers=ICtor::ic_run )"
has   "E6 a class-member using-declaration (inheriting constructors) does not decline the bare &ICtor::ic_run" "$o" 'called_by="go_ictor"'
o="$( run --callers=Server::both )"
has   "E5 a using-directive of the class's own namespace keeps the bare spelling typed" "$o" 'called_by="go_dirin"'
o="$( run --callers=Server::start )"
hasnt "E1 an external &grpc::Server::start never binds the in-tree mine::Server" "$o" 'called_by="go_ext"'
hasnt "E1b nor a bare spelling under using grpc::Server" "$o" 'called_by="go_using"'
hasnt "E1c nor under using namespace grpc" "$o" 'called_by="go_dir"'
has   "E2c an out-of-line mine::Server::both writing the bare &Server::start stays typed" "$o" 'called_by="both"'
has   "E2d the global-anchored ::mine::Server stays typed" "$o" 'called_by="go_ofull"'
o="$( run --callers=Server::stop )"
has   "E2 &mine::Server::stop stays typed" "$o" 'called_by="go_mine"'
has   "E2b a bare &Server::stop written inside namespace mine stays typed" "$o" 'called_by="go_inside"'
hasnt "E1e &::Server::stop (a global class that does not exist in the tree) binds nothing" "$o" 'called_by="go_gwrong"'
o="$( run --callers=GServer::gstart )"
hasnt "E1f a namesake namespace that only ends with the qualifier's text on no :: boundary binds nothing" "$o" 'called_by="go_bnd"'
has   "E1f-b the in-tree spelling mygrpc::GServer stays typed" "$o" 'called_by="go_bok"'
o="$( run --callers=DBase::dfoo )"
hasnt "I7 a dependent base that is a template parameter named like an in-tree class is no DBase" "$o" 'called_by="dispatch_dep"'
has   "I7-b a plain pointer to the in-tree DBase::dfoo stays typed" "$o" 'called_by="go_dbok"'
o="$( run --callees=dispatch_dep )"
hasnt "I7b nor does the callee list pin DBase::dfoo" "$o" '<t n="DBase.dfoo"'
o="$( run --callers=Deep::run )"
has   "E3 the full nested spelling stays typed" "$o" 'called_by="go_nfull"'
has   "E3b a suffix of the nested path stays typed" "$o" 'called_by="go_nsuf"'
hasnt "E1d a namesake namespace that is not the in-tree one binds nothing" "$o" 'called_by="go_oext"'
o="$( run --callers=Anon::go )"
has   "E3c an anonymous namespace is transparent" "$o" 'called_by="go_anon"'
o="$( run --callers=Pair::f )"
has   "E3d C++17 nested c1::c2::Pair" "$o" 'called_by="go_pfull"'
has   "E3e and the suffix c2::Pair" "$o" 'called_by="go_psuf"'
o="$( run --callers=Ver::vf )"
has   "E3f an inline namespace is transparent" "$o" 'called_by="go_inl"'
o="$( run --callers=IB::inh )"
has   "I1 an inherited method names the base's definition" "$o" 'called_by="go_id"'
o="$( run --callers=ICB::crt )"
has   "I2 a CRTP base method names the base's definition" "$o" 'called_by="go_icd"'
o="$( run --callers=IM1::dup )"
hasnt "I3 two bases at one level: no target (IM1)" "$o" 'called_by='
o="$( run --callers=IM2::dup )"
hasnt "I3b (IM2)" "$o" 'called_by='
o="$( run --callees=go_ie )"
hasnt "I4 a base outside the tree: no target (a floor)" "$o" '<vs '
o="$( run --callees=go_io )"
has   "I5 an overloaded name lists every overload" "$o" 'slot="IOT.f" via="slot" targets="2" shown="2"'
o="$( run --callees=go_id2 )"
has   "I6 the derived class's own method stays typed" "$o" '<t n="ID.other"'
o="$( run --callers=ops_mr_write )"
hasnt "N24 f()->m() on a call result is no slot call (C++)" "$o" 'called_by="mr_paint"'
o="$( run --callees=mr_paint )"
hasnt "N24b and its callees list no slot" "$o" '<vs '
o="$( run --callees=deep_use )"
has   "L1 the typed tier discloses the name-tier store it hides" "$o" 'slot="L5_.cb" via="slot" slot_name_also="1" targets="1" shown="1"'
o="$( run --callees=deep_use --json )"
has   "L1j the --json twin carries it" "$o" '"slot_name_also":1'
o="$( run --callers=deepfn )"
has   "L2 --callers still says the name tier" "$o" 'called_by="deep_use"'
o="$( run --callees=go_mine )"
hasnt "L3 a typed-only site prints no slot_name_also" "$o" 'slot_name_also'
o="$( run '--for=how does run_zzw call the Cls zzw slot' )"
has   "F4 the cap keeps the field a caller calls through" "$( row "$o" Cls_ fields.c )" 'slot_fields="aaa=1,bbb=1,ccc=1,zzw=3@run_zzw" slot_fields_more="1"'
if [ "$fail" -eq 0 ]; then echo "fnslotcheck: PASS"; else echo "fnslotcheck: FAIL"; fi
exit "$fail"
