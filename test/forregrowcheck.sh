#!/usr/bin/env bash
# forregrowcheck.sh — REGISTRAR-2 (src/forliteral.h, the TABLE-CONST V2 block; src/regindex.h reg_detail::isRegistrationCallee): a --for task
# about where a registered thing is defined, built or handled reaches its registration rows. Fixture built at runtime.
#
# THE CONTRACT THIS PINS (arms tagged [P] are RED on base 292a26dec; [G] arms are twins and near misses that hold on both binaries):
#   R1 [P] Rust top-level macro row, cue `build ... for`: `impl_body!(HashJoin(HashJoinNode) => ...)`, tbl="item"
#   R2 [P] Rust macro-table brace row, cue `defined`: `{ barrier_interval_ms, u32, ...`, tbl="for_all_params! {"
#   R3 [P] Python decorator dict, cue `handled`: `@decorators.websocket_command({"type": "get_states"})`, reg= the decorator up to its paren
#   R4 [P] Python register call over three lines inside a function, cue `get to`: the quoted "async_turn_on" argument line, reg= the call's line
#   R5 [P] a hit inside a longer name is a row only as a registration call's argument: `async_reg(hass, handle_get_states)`; the same longer
#          name in a plain call, or as a callee inside a registration (`async_reg(hass, async_get_states_trigger(hass))`), stays counted
#          in longer=, never a row; a registration row says reg=, never tbl= (no table opener)
#   R6 [P] TypeScript register call, cue `turned into`: `commands.registerCommand("open_panel", open_panel)`
#   R7 [P] a generated file's registration ranks after the source's (zz_generated sorts first by path)
#   R8 [P] a dotted anchor that prints nothing (`vpkg.ValidationError`) is tried by its tail after the task's own anchors: `'ValidationError': (...)`
#   R9 [P] an identifier-shaped word with no index symbol (`ProtoOnlyNode`, a generated type) anchors under a row-only cue, after the indexed ones
#   N5 [G] / N6 [G] such a word with no site, or whose only site is no row: no block, byte-identical
#   N1 [G] a definition named like a handler (`func NewHandlerRunner(recorder EventRecorder)`) is no registration call: no block, the
#          answer byte-identical to RIPWIRE_NO_LITERAL_ANCHOR=1 (the kubernetes-01 shape)
#   N2 [G] a call not named for a registration (`aggregate(agg_target)`, `regex_compile(agg_target)`): no block
#   N3 [G] no cue word (`where is get_states used`): byte-identical; `get` without `to`, `turned` without `into`: byte-identical
#   N4 [G] a registration call closed on an earlier line: the anchor after it is no argument, no block
#   X1 [G] determinism and xmllint on a REGISTRAR-2 answer; every positive arm checks the exit code and a non-empty answer
#   REG2-FIX1 (rv-reg2 F1-F3 and CodeRabbit on #539; [P] = red on c984839a3, the REGISTRAR-2 head before the fix round):
#   N7 [P] F1 a C++ constructor declaration, a member-initializer list, a TypeScript interface member are no call; N7c [G] a GNU-style definition is none
#   N8 [P] F1 a Rust enum tuple variant is no call; R10 [G] its twin `reg.register(X);` is a reg= row
#   N9 [P] F1 a statement in a JS arrow body or a Go func literal body is no argument of the call around it; N9c a JS method shorthand is its own
#          signature; R11 [G] an object-literal argument stays an argument
#   N10 [P] F2 handler(, get_handler(, logging.FileHandler(, run_command(, write_reg(, ParseCommandLine(, reg_write(, is_registered(, get_registry(
#          are no registration; R12 add_route(, @app.route(, _register_handler(, `register_handler (` are
#   R13-R15 [P] CodeRabbit: a same-line receiver hit, a CRLF line start, a `::` callee chain; N13 [G] a call opened past the 4-line read-back is no row;
#          N14 [P] a paren in a string opens nothing
#   N11 [P] F3 a dotted anchor's common tail with only an unquoted table row prints no block; R16 [G] the quoted-key tail (koa-02) prints; R17 [P] one tail once
#   N12 [P] `is not defined` / `was not declared` (error messages) are no cue; R18 [G] the same word without the negation anchors
#   L1 [P] legend: F5 (no tbl= or reg= is no claim), the 4-line and 512-byte reach; L2 [P] D4: no vocabulary list, rank sentence or tail= sentence without tail=
#   G-STORED-B (forliteral-3 commit 1; [P] = red on 2562d9931): a task with NO cue word lists strong rows only. S1-S6 [P] a bare subject reaches a Rust
#   top-level macro row (and the unindexed late try), a Python register call, a Go and a TS call registration, a Rust macro-table row; S7 [P] a weak dict
#   row beside a strong one is counted in weak=, not listed; S8 [P] the legend clause (compact and full). N16-N21 [G] weak-only rows (TS object key,
#   Python dict, __all__, #define X-macro), no-call shapes (C++ init list, Rust enum variant, a call not named for a registration), no identifier
#   word: byte-identical. N3 moved to a weak-only anchor (get_states now has strong rows). D1a-d [P] useRouter(, addCommandLineOption(, reg_value(,
#   reg_field( are no registration; D1e-f [G] addEventHandler(, reg_handler( stay.
#   N22 [G] a no-cue task with more anchors than the scan cap and no strong row adds no <lit_capped> note (the answer is unchanged).
#
# Usage:  bash test/forregrowcheck.sh [BIN]   (BIN is $1, else RIPWIRE_BIN, else build/ripwire). Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
unset RIPWIRE_NO_LITERAL_ANCHOR
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "forregrowcheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { no "binary not executable: $BIN"; exit 1; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" TMPDIR="$TMP/"; mkdir -p "$HOME"
RF="$TMP/regfix"
mkdir -p "$RF/src/stream" "$RF/src/common" "$RF/homeassistant/components/websocket_api" "$RF/homeassistant/components/light" \
         "$RF/homeassistant/helpers" "$RF/ext/src" "$RF/aaa/gen" "$RF/pkg/logs" "$RF/pkg/events" "$RF/lib/agg"
cat > "$RF/src/stream/hash_join.rs" <<'RS'
pub struct HashJoinNode;
pub struct HashJoinExecutorBuilder;
impl_body!(HashJoin(HashJoinNode) => HashJoinExecutorBuilder);
impl_body!(Probe(ProtoOnlyNode) => ProbeBuilder);
pub fn new_boxed_executor() -> u32 { 1 }
RS
cat > "$RF/src/common/system_param.rs" <<'RS'
macro_rules! for_all_params {
    ($macro:ident) => {
        $macro! {
            { barrier_interval_ms, u32, Some(1000_u32), true },
            { checkpoint_frequency, u64, Some(1_u64), true },
        }
    };
}
pub fn barrier_interval_ms() -> u32 { 1 }
RS
cat > "$RF/homeassistant/components/websocket_api/commands.py" <<'PY'
from . import decorators


def async_register_commands(hass, async_reg):
    async_reg(hass, async_get_states_trigger(hass))
    async_reg(hass, handle_subscribe)
    async_reg(hass, handle_get_states)


@decorators.websocket_command({"type": "get_states"})
def handle_get_states(hass, connection, msg):
    return get_states(hass)


def get_states(hass):
    return list(hass.states)


def handle_subscribe(hass, connection, msg):
    return None
PY
cat > "$RF/homeassistant/components/websocket_api/decorators.py" <<'PY'
def websocket_command(schema):
    def wrap(f):
        return f
    return wrap
PY
cat > "$RF/homeassistant/components/light/services.py" <<'PY'
SERVICE_TURN_ON = "turn_on"


def async_setup_services(component):
    component.async_register_entity_service(
        SERVICE_TURN_ON, None, "async_turn_on"
    )
PY
cat > "$RF/homeassistant/components/light/light.py" <<'PY'
class Light:
    async def async_turn_on(self, **kwargs):
        return None
PY
cat > "$RF/homeassistant/helpers/plain.py" <<'PY'
def show(x):
    print_states(handle_get_states)
PY
cat > "$RF/ext/src/extension.ts" <<'TS'
export function open_panel(): void {}
export function activate(commands: any): void {
    commands.registerCommand("open_panel", open_panel);
}
TS
cat > "$RF/aaa/gen/zz_generated.register.go" <<'GO'
package gen

func init() {
	RegisterHandler("pods_log_route", generatedLog)
}
GO
cat > "$RF/pkg/logs/routes.go" <<'GO'
package logs

func pods_log_route() {}

func install(r Router) {
	r.RegisterHandler("pods_log_route", pods_log_route)
}
GO
cat > "$RF/pkg/events/runner.go" <<'GO'
package events

type EventRecorder interface {
	Event()
}

func NewHandlerRunner(recorder EventRecorder) int {
	return 1
}
GO
cat > "$RF/lib/agg/agg.py" <<'PY'
def agg_target():
    return 1


def run():
    aggregate(agg_target)
    regex_compile(agg_target)


def closed():
    register_thing(1)
    x = closed_anchor
    return x


def closed_anchor():
    return 2


def uses():
    return lookup("generated_only_key")
PY
mkdir -p "$RF/vpkg"
cat > "$RF/vpkg/__init__.py" <<'PY'
"""The vpkg.ValidationError is raised on bad input."""
_dynamic_imports = {
    'ValidationError': ('vpkg_core', '.'),
    'Other': ('vpkg_core', '.'),
}
PY
cat > "$RF/vpkg/core.py" <<'PY'
class ValidationError(ValueError):
    pass


class Other:
    pass
PY
# REG2-FIX1 fixtures: shapes that are NOT a call argument (F1), names that are NOT registrations (F2), a dotted tail that is no key (F3), and the
# neighbours rv-reg2 did not name (lesson 16): a GNU-style out-of-class definition, a TypeScript interface method, a Go func literal
mkdir -p "$RF/f1" "$RF/f3"
cat > "$RF/f1/runner.h" <<'CC'
struct RunnerConfig { int parallelism; };
struct CommandRunner {
  CommandRunner(const RunnerConfig& cfg_decl_marker);
};
CC
cat > "$RF/f1/runner.cc" <<'CC'
#include "runner.h"
CommandRunner::CommandRunner(const RunnerConfig& cfg)
    : cfg_(cfg),
      register_hook_(init_marker_a) {}
void
Registry::RegisterHandler(Handler gnu_marker_a)
{
}
void wire()
{
    registry::register_handler(cxx_call_marker);
}
CC
cat > "$RF/f1/proto.rs" <<'RS'
pub enum Request {
    RegisterCapability(VariantOptsMarker),
    Command(HoverMarker),
}
pub fn init(reg: &mut Registry) {
    reg.register(CallMarkerA);
}
RS
cat > "$RF/f1/iface.ts" <<'TS'
export interface Commands {
  registerCommand(id: string, iface_marker_a: Handler): void
}
TS
cat > "$RF/f1/app.js" <<'JS'
app.registerCommand('sync', () => {
  audit_log(closure_marker_a)
})
app.registerCommand('plain', {
  run: obj_marker_a
})
class Hub {
  registerHandler(method_marker_a) {
    return method_marker_a
  }
}
JS
cat > "$RF/f1/srv.go" <<'GO'
package srv

func wire(mux *Mux) {
	mux.RegisterHandler("/x", func(w W, r R) {
		audit(go_closure_marker)
	})
}
GO
cat > "$RF/f1/vocab.py" <<'PY'
def f(a_hnd_marker, b_get_marker, c_log_marker, d_run_marker, e_wr_marker, f_parse_marker, g_rw_marker, h_isreg_marker, i_getreg_marker):
    handler(a_hnd_marker)
    get_handler(b_get_marker)
    logging.FileHandler(c_log_marker)
    run_command(d_run_marker)
    write_reg(e_wr_marker, 0)
    ParseCommandLine(f_parse_marker)
    reg_write(g_rw_marker, 0)
    is_registered(h_isreg_marker)
    get_registry(i_getreg_marker)


def g(app):
    app.add_route(path_marker_a, ep_marker_b)
    _register_handler(under_marker_a)
    register_handler (blank_marker_a)
    event_handler.register_handler(event_handler)


@app.route(deco_marker_a)
def h():
    pass


def k():
    return register_handler(ret_marker_a)
PY
printf 'async_reg(\r\n    handle_crlf_marker,\r\n)\r\n' > "$RF/f1/crlf.py"
cat > "$RF/f1/reach.py" <<'PY'
def far(r):
    r.register_thing(
        a_one(1),
        b_two(2),
        c_three(3),
        d_four(4),
        e_five(5),
        deep_marker_a,
    )
PY
cat > "$RF/f1/strparen.py" <<'PY'
def quirky(r):
    r.register_thing("a(", 1)
    other(strparen_marker_a)
PY
cat > "$RF/f3/table.ts" <<'TS'
export const defaults = {
  mode: 1,
  other: 2,
}
export class Editor { mode = 0 }
TS
cat > "$RF/f3/koa.js" <<'JS'
delegate(proto, 'response')
  .method('attachment')
  .method('redirect')
  .method('flushHeaders')
proto.redirect = function () {}
JS
cat > "$RF/f3/keys.py" <<'PY'
_dynamic_imports = {
    'shared_handler_key': ('core', '.'),
    'other_key': ('core', '.'),
}
PY
cat > "$RF/f3/limits.ts" <<'TS'
export const limits = {
  max_part_size_marker: 1,
  other_limit: 2,
}
TS
# G-STORED-B fixtures: a bare subject (no cue word) beside strong and weak rows, and the D1 vocabulary neighbours (rv-reg2-delta)
mkdir -p "$RF/gsb"
cat > "$RF/gsb/mixed.py" <<'PY'
MIXED = {
    "mixed_anchor_fn": 1,
    "other_mixed": 2,
}


def setup(r):
    r.register(mixed_anchor_fn)


def mixed_anchor_fn():
    return 1
PY
cat > "$RF/gsb/exports.py" <<'PY'
__all__ = [
    "exported_weak_fn",
    "other_export",
]


def exported_weak_fn():
    return 1
PY
cat > "$RF/gsb/opcodes.h" <<'CC'
#define OPCODE_LIST(X) \
    X(op_weak_marker, 1) \
    X(op_other_marker, 2)
int op_weak_marker(void);
CC
cat > "$RF/gsb/vocab.js" <<'JS'
useRouter(ur_marker_a)
parser.addCommandLineOption(acl_marker_a)
emitter.addEventHandler(aeh_marker_a)
JS
cat > "$RF/gsb/vocab2.py" <<'PY'
def regs(dev):
    reg_value(rv_marker_a)
    reg_field(rf_marker_a, 3)
    reg_handler(rh_marker_a)
PY
call(){ ( cd "$RF" || exit 1; "$BIN" "$RF" --no-cache "$@" </dev/null 2>/dev/null ); }
offc(){ ( cd "$RF" || exit 1; RIPWIRE_NO_LITERAL_ANCHOR=1 "$BIN" "$RF" --no-cache "$@" </dev/null 2>/dev/null ); }
lits(){ python3 -I -c 'import sys,re;s=sys.stdin.read();print("".join(re.findall(r"<lit [^>]*>.*?</lit>",s,re.S)))'; }
has(){ grep -qF -- "$2" <<<"$1"; }
lsrows(){ python3 -I -c 'import sys,re;print("\n".join(re.findall(r"<ls [^>]*>.*?</ls>",sys.stdin.read(),re.S)))'; }
# a positive arm: the call exits 0 and prints an answer, else it is red whatever the text holds
A=""; RC=0
ask(){ A="$( call "--for=$1" )"; RC=$?; [ "$RC" -eq 0 ] && [ -n "$A" ]; }

# R1 [P]
if ask 'How does new_boxed_executor build an executor for HashJoinNode?'; then L="$( lits <<<"$A" )"
    if has "$L" 's="HashJoinNode" shape="table"' && has "$L" 'tbl="item"' && has "$L" 'impl_body!(HashJoin(HashJoinNode)'; then ok "R1 [P] build ... for: the Rust top-level macro row"
    else no "R1 macro row: ${L:0:400}"; fi
else no "R1 call failed rc=$RC"; fi
# R2 [P]
if ask 'Where is barrier_interval_ms defined and what reads it?'; then L="$( lits <<<"$A" )"
    if has "$L" 's="barrier_interval_ms" shape="table"' && has "$L" '{ barrier_interval_ms, u32' && has "$L" 'tbl="$macro! {"'; then ok "R2 [P] defined: the macro-table brace row"
    else no "R2 brace row: ${L:0:400}"; fi
else no "R2 call failed rc=$RC"; fi
# R3 [P] + R5 [P]
if ask 'I need to change what get_states returns over the websocket; where is it handled?'; then L="$( lits <<<"$A" )"
    if has "$L" 's="get_states" shape="table"' && has "$L" 'reg="@decorators.websocket_command("' && ! has "$L" 'tbl="@' && has "$L" '"type": "get_states"'; then ok "R3 [P] handled: the Python decorator dict row, tbl= the decorator"
    else no "R3 decorator row: ${L:0:500}"; fi
    if has "$L" 'async_reg(hass, handle_get_states)' && has "$L" 'reg="async_reg("' && ! has "$L" 'print_states(' && ! has "$( lsrows <<<"$L" )" 'async_get_states_trigger' && has "$L" 'longer="'; then ok "R5 [P] a longer name is a row as a registration argument only; the plain call stays in longer="
    else no "R5 longer name: ${L:0:1400}"; fi
else no "R3/R5 call failed rc=$RC"; fi
# R4 [P]
if ask 'how does the light service get to async_turn_on?'; then L="$( lits <<<"$A" )"
    if has "$L" 's="async_turn_on" shape="table"' && has "$L" 'p="homeassistant/components/light/services.py" l="6"' && has "$L" 'reg="component.async_register_entity_service("'; then ok "R4 [P] get to: a register call over three lines in a function body"
    else no "R4 register call: ${L:0:500}"; fi
else no "R4 call failed rc=$RC"; fi
# R6 [P]
if ask 'where is open_panel turned into a command?'; then L="$( lits <<<"$A" )"
    if has "$L" 's="open_panel" shape="table"' && has "$L" 'reg="commands.registerCommand("'; then ok "R6 [P] turned into: the TypeScript register call"
    else no "R6 TS register: ${L:0:400}"; fi
else no "R6 call failed rc=$RC"; fi
# R7 [P]
if ask 'which handler is pods_log_route built from?'; then L="$( lits <<<"$A" )"
    FIRST="$( grep -o '<ls p="[^"]*"' <<<"$L" | sed -n 1p )"
    if [ "$FIRST" = '<ls p="pkg/logs/routes.go"' ] && has "$L" 'zz_generated.register.go'; then ok "R7 [P] the source registration first, the generated one after it"
    else no "R7 order: $FIRST ${L:0:300}"; fi
else no "R7 call failed rc=$RC"; fi
# R9 [P] an identifier the index holds no symbol of (a generated type) anchors under a row-only cue, its macro row printed
if ask 'where is ProtoOnlyNode built into an executor?'; then L="$( lits <<<"$A" )"
    if has "$L" 's="ProtoOnlyNode" shape="table"' && has "$L" 'impl_body!(Probe(ProtoOnlyNode)' && has "$L" 'tbl="item"'; then ok "R9 [P] an unindexed generated name: its macro row"
    else no "R9 unindexed: ${L:0:400}"; fi
else no "R9 call failed rc=$RC"; fi
# R8 [P] a dotted anchor with no row is tried by its last segment: the re-export map's quoted key row
if ask 'where vpkg.ValidationError is defined'; then L="$( lits <<<"$A" )"
    if has "$L" 's="ValidationError" shape="table"' && has "$L" "'ValidationError': ('vpkg_core', '.')" && has "$L" 'tbl="_dynamic_imports = {"' && ! has "$L" 's="vpkg.ValidationError"'; then ok "R8 [P] defined + a dotted anchor: its tail's re-export map row"
    else no "R8 dotted tail: ${L:0:400}"; fi
else no "R8 call failed rc=$RC"; fi
# near misses [G]: an answer, no table block, byte-identical to the switch off
nomiss(){ local X; X="$( call "--for=$1" )"; local rc=$?
    if [ "$rc" -eq 0 ] && [ -n "$X" ] && ! has "$( lits <<<"$X" )" 'shape="table"' && [ "$X" = "$( offc "--for=$1" )" ]; then ok "$2"; else no "$2: rc=$rc ${#X} B $( lits <<<"$X" | cut -c1-300 )"; fi; }
nomiss 'Where is EventRecorder defined and who implements it?' 'N1 [G] a definition named like a handler is no registration call (kubernetes-01 shape)'
nomiss 'where is agg_target handled' 'N2 [G] a call not named for a registration (aggregate, regex_compile): no row'
# N3 (G-STORED-B): a task with no cue now prints STRONG rows only; max_part_size_marker has a weak row (a TS object key) alone, which a row-only cue prints
nomiss 'where is max_part_size_marker used' 'N3a [G] no cue word, only a weak row: byte-identical'
nomiss 'what does max_part_size_marker get' 'N3b [G] get without to is no cue: the weak row stays silent, byte-identical'
nomiss 'max_part_size_marker turned off' 'N3c [G] turned without into is no cue: byte-identical'
nomiss 'where is closed_anchor handled' 'N4 [G] a registration call closed on an earlier line holds no later anchor'
nomiss 'where is no_such_key_here defined' 'N5 [G] an identifier the index lacks, with no site: no block, no claim'
nomiss 'where is generated_only_key defined' 'N6 [G] an identifier the index lacks whose only site is no row: no block'
nomiss 'how do agg_target closed_anchor max_part_size_marker init_marker_a cfg_decl_marker EventRecorder relate' 'N22 [G] no cue word, more anchors than the scan cap, no strong row: no lit_capped note, byte-identical (koa-13 shape; red before the fix)'
# ── REG2-FIX1 (rv-reg2 F1-F3, CodeRabbit on #539) ────────────────────────────────────────────────────────────────────────────────────────
# a task with a quoted anchor: `Where is `X` defined?` (the cue prints only beside a row)
q(){ ask "Where is \`$1\` defined?"; }
rowsof(){ lits <<<"$A"; }
# N7 [P] F1(a)(c): a C++ constructor declaration, a member-initializer list, and (neighbour) a GNU-style out-of-class definition: no call, no block
nomiss 'Where is `cfg_decl_marker` defined?' 'N7a [P] a C++ constructor declaration is no registration call'
nomiss 'Where is `init_marker_a` defined?' 'N7b [P] a C++ member-initializer list is no registration call'
nomiss 'Where is `gnu_marker_a` defined?' 'N7c [G] a GNU-style definition `Registry::RegisterHandler(` is the signature of its own symbol, no call'
nomiss 'Where is `iface_marker_a` defined?' 'N7d [P] a TypeScript interface method signature is no registration call (neighbour)'
# N8 [P] F1(b): Rust enum tuple variants
nomiss 'Where is `VariantOptsMarker` defined?' 'N8a [P] a Rust enum tuple variant named for a registration is no call'
nomiss 'Where is `HoverMarker` defined?' 'N8b [P] a Rust enum tuple variant named for a command is no call'
if q CallMarkerA; then L="$( rowsof )"; if has "$L" 'reg="reg.register("'; then ok "R10 [G] the Rust twin: reg.register(CallMarkerA); stays a reg= row"; else no "R10 Rust call: ${L:0:300}"; fi; else no "R10 call failed rc=$RC"; fi
# N9 [P] F1(d): a closure body is no argument of the call that holds it (JS arrow, and the neighbour: a Go func literal)
nomiss 'Where is `closure_marker_a` defined?' 'N9a [P] a statement in a JS arrow-function body is no argument of the call around it'
nomiss 'Where is `go_closure_marker` defined?' 'N9b [P] a statement in a Go func literal body is no argument of the call around it (neighbour)'
if q obj_marker_a; then L="$( rowsof )"; if has "$L" "reg=\"app.registerCommand(\""; then ok "R11 [G] an object-literal argument stays an argument"; else no "R11 object literal: ${L:0:300}"; fi; else no "R11 call failed rc=$RC"; fi
nomiss 'Where is `method_marker_a` defined?' 'N9c [P] a JS class method shorthand `registerHandler(x) {` is the signature of its own symbol (neighbour)'
nomiss 'Where is `ret_marker_a` defined?' 'N15 [G] a registration call that does not open its line (`return register_handler(x)`) is no row: the opens-its-line rule'
# N10 [P] F2: a name must say it registers: verb + noun, `register`, `reg` (no access word), or a decorator's noun
for m in a_hnd_marker:'handler(' b_get_marker:'get_handler(' c_log_marker:'logging.FileHandler(' d_run_marker:'run_command(' e_wr_marker:'write_reg(' \
         f_parse_marker:'ParseCommandLine(' g_rw_marker:'reg_write(' h_isreg_marker:'is_registered(' i_getreg_marker:'get_registry('; do
    nomiss "Where is \`${m%%:*}\` defined?" "N10 [P] ${m#*:}...) calls or looks something up; it registers nothing"
done
for m in path_marker_a:'app.add_route(' deco_marker_a:'@app.route(' under_marker_a:'_register_handler(' blank_marker_a:'register_handler (' ; do
    if q "${m%%:*}"; then L="$( rowsof )"; if has "$L" "reg=\"${m#*:}\""; then ok "R12 [P/G] ${m#*:} is a registration call: reg= (add_route, @app.route: green on base too; _name( and name ( red there)"; else no "R12 ${m#*:}: ${L:0:300}"; fi; else no "R12 ${m#*:} call failed rc=$RC"; fi
done
# CodeRabbit on #539: a same-line receiver hit, a CRLF file, `::` in the callee chain
if q event_handler; then L="$( rowsof )"; if has "$L" 'reg="event_handler.register_handler("'; then ok "R13 [P] a same-line receiver hit does not hide the argument hit"; else no "R13 same line: ${L:0:300}"; fi; else no "R13 call failed rc=$RC"; fi
if q crlf_marker; then L="$( rowsof )"; if has "$L" 'reg="async_reg("'; then ok "R14 [P] a longer name at the start of a CRLF line is an argument"; else no "R14 CRLF: ${L:0:300}"; fi; else no "R14 call failed rc=$RC"; fi
if q cxx_call_marker; then L="$( rowsof )"; if has "$L" 'reg="registry::register_handler("'; then ok "R15 [P] a C++ qualified callee registry::register_handler( is read whole"; else no "R15 qualified callee: ${L:0:300}"; fi; else no "R15 call failed rc=$RC"; fi
# a registration call opened beyond the read-back, and a paren in a string: no row, the legend says how far it reads
nomiss 'Where is `deep_marker_a` defined?' 'N13 [G] a registration call opened 7 lines above the site is past the 4-line read-back: no row (a floor, said in the legend)'
nomiss 'Where is `strparen_marker_a` defined?' 'N14 [P] an open paren inside a string does not make a later call an argument of the registration call'
# N11 [P] F3: the tail of a dotted anchor is read for quoted keys only
if ask 'where is `editor.mode` defined'; then L="$( lits <<<"$A" )"
    if ! has "$L" 's="mode"'; then ok "N11 [P] a common tail with only an unquoted table row prints no block"; else no "N11 dotted tail mode: ${L:0:300}"; fi
else no "N11 call failed rc=$RC"; fi
if ask 'where is `ctx.redirect` registered'; then L="$( lits <<<"$A" )"
    if has "$L" 's="redirect" shape="table"' && has "$L" ".method('redirect')" && ! has "$L" ".method('attachment')" && has "$L" 'tail="'; then ok "R16 [G] koa-02 twin: the tail as a quoted key prints its row, tail= says how many sites it leaves out"; else no "R16 koa twin: ${L:0:400}"; fi
else no "R16 call failed rc=$RC"; fi
if ask 'where are `alpha.shared_handler_key` and `beta.shared_handler_key` defined'; then L="$( lits <<<"$A" )"
    if [ "$( grep -o 's="shared_handler_key"' <<<"$L" | wc -l | tr -d ' ' )" = 1 ]; then ok "R17 [P] two dotted anchors with one tail print it once"; else no "R17 duplicate tail: ${L:0:400}"; fi
else no "R17 call failed rc=$RC"; fi
# N12 [P] the cue `defined`/`declared` after a negation is an error message, not a question about a definition
nomiss 'Fix NameError: name max_part_size_marker is not defined in the parser' 'N12a [P] `is not defined` (an error message) is no cue'
nomiss 'error: max_part_size_marker was not declared in this scope' 'N12b [P] `was not declared` (a compiler message) is no cue (neighbour)'
if ask 'where is max_part_size_marker defined'; then L="$( rowsof )"; if has "$L" 'max_part_size_marker: 1'; then ok "R18 [G] the same word without the negation still anchors"; else no "R18 defined: ${L:0:300}"; fi; else no "R18 call failed rc=$RC"; fi
# the legend: F4 (rank wording), F5 (no tbl= or reg= is no claim), the read-back reach, tail=
if ask 'Where is barrier_interval_ms defined and what reads it?'; then
    if has "$A" 'no tbl= or reg= is no claim' && ! has "$A" 'rank last' && has "$A" '4 lines' && has "$A" '512 bytes'; then ok "L1 [P] the table legend: no tbl= or reg= is no claim, the 4-line and 512-byte reach"; else no "L1 legend wording"; fi
    # D4 (rv-reg2-delta): no vocabulary list, no ranking sentence, the tail= sentence only beside a tail= (this answer prints none)
    if ! has "$A" 'bind with route' && ! has "$A" 'Generated and JSON files' && ! has "$A" 'tail=N'; then ok "L2 [P] D4: the table legend carries no vocabulary list, no rank sentence, no tail= sentence without a tail="; else no "L2 extraneous legend bytes"; fi
else no "L1 call failed rc=$RC"; fi
# ── G-STORED-B (reports/os5-g-stored-s0.md): a bare subject with no cue word prints STRONG rows only ─────────────────────────────────────────
# strong = a registration call (reg=), a top-level macro or call row (tbl="item"), a macro-table brace row (tbl= a `name! {` or `$macro! {` opener)
strong(){ if ask "$1"; then L="$( lits <<<"$A" )"; local want; local okk=1
    for want in "${@:3}"; do has "$L" "$want" || okk=0; done
    if [ "$okk" = 1 ]; then ok "$2"; else no "$2: ${L:0:500}"; fi; else no "$2: call failed rc=$RC"; fi; }
strong 'new_boxed_executor for HashJoinNode' 'S1 [P] Rust bare subject: the top-level macro row (rw-03 stored shape)' 's="HashJoinNode" shape="table"' 'tbl="item"' 'impl_body!(HashJoin(HashJoinNode)'
strong 'ProtoOnlyNode executor' 'S2 [P] Rust bare subject, a name the index lacks: its macro row (the late unindexed try)' 's="ProtoOnlyNode" shape="table"' 'impl_body!(Probe(ProtoOnlyNode)'
strong 'light.turn_on hue async_turn_on' 'S3 [P] Python bare subject: the register call over three lines (ha-03 stored shape)' 's="async_turn_on" shape="table"' 'reg="component.async_register_entity_service("'
strong 'pods_log_route kubelet' 'S4 [P] Go bare subject: a call registration' 's="pods_log_route" shape="table"' 'reg="r.RegisterHandler("'
strong 'open_panel extension' 'S5 [P] TypeScript bare subject: registerCommand' 's="open_panel" shape="table"' 'reg="commands.registerCommand("'
strong 'barrier_interval_ms system param' 'S6 [P] Rust bare subject: the macro-table brace row' 's="barrier_interval_ms" shape="table"' 'tbl="$macro! {"'
# fix round 1 (rv-forliteral-3 section 2): a no-cue task scans a compound name, never a plain lower-case word (a dotted name's tail `plainword`);
# a registration call's argument is strong only when it is a DIRECT argument (nothing nested in an inner call or an index)
mkdir -p "$RF/gsb2"
cat > "$RF/gsb2/plain.py" <<'PY'
class PlainBox:
    def plainword(self):
        return 1

    def plain_word(self):
        return 2


def setup_plain(r):
    r.register("plainword", PlainBox)
    r.register("plain_word", PlainBox)


def nested_marker_fn():
    return 1


def direct_marker_fn():
    return 2


def idx_marker_fn():
    return 3


def setup_nested(r, table):
    r.register(wrap(nested_marker_fn))
    r.register(table[idx_marker_fn])
    r.register(direct_marker_fn)
PY
nested(){ if ask "$1"; then L="$( lits <<<"$A" )"; if ! has "$L" 'shape="table"' && [ "$A" = "$( offc "--for=$1" )" ]; then ok "$2"; else no "$2: ${L:0:400}"; fi; else no "$2: call failed rc=$RC"; fi; }
nested 'lowest common caller of PlainBox.plainword and Gadget.thing' 'N23a [P] a no-cue dotted name whose tail is one lower-case word (plainword): the tail is not scanned, byte-identical (nest-08 shape)'
strong 'lowest common caller of PlainBox.plain_word and Gadget.thing' 'N23b [G] twin: the tail with an underscore (plain_word) is a compound name: its registration row prints' 's="plain_word" shape="table"' 'reg="r.register("'
nested 'nested_marker_fn setup_nested' 'N24a [P] a site nested in an inner call (register(wrap(x))) is no direct argument: no strong row, byte-identical (vscode-03 shape)'
nested 'idx_marker_fn setup_nested' 'N24b [P] a site inside an index (register(table[x])) is no direct argument: byte-identical'
strong 'direct_marker_fn setup_nested' 'N24c [G] twin: a direct argument of the same call stays strong' 's="direct_marker_fn" shape="table"' 'reg="r.register("'
# S7 [P]: one anchor with a strong and a weak row: the registration prints, the dict row does not, weak= counts it
if ask 'mixed_anchor_fn setup'; then L="$( lits <<<"$A" )"
    if has "$L" 'reg="r.register("' && ! has "$L" 'tbl="MIXED = {"' && has "$L" 'weak="2"' && has "$A" 'weak='; then ok "S7 [P] strong rows only: the registration prints, the dict row and the def line are counted in weak="; else no "S7 mixed: ${L:0:500}"; fi
else no "S7 call failed rc=$RC"; fi
# S8 [P]: the legend says why only those rows print, beside the block that prints them (compact and full)
if ask 'mixed_anchor_fn setup'; then if has "$A" 'no table or registration word'; then ok "S8a [P] compact answer: the no-cue clause is in the legend"; else no "S8a no-cue legend missing"; fi; else no "S8a call failed rc=$RC"; fi
FULL="$( call '--for=mixed_anchor_fn setup' --legend=full )"
if [ -n "$FULL" ] && has "$FULL" 'no table or registration word' && has "$FULL" 'weak='; then ok "S8b [P] full legend: the no-cue clause and weak="; else no "S8b full legend: ${#FULL} B"; fi
# N16-N20 [G]: a bare subject whose only rows are weak, or that are no row at all: no block, byte-identical to the switch off
nomiss 'max_part_size_marker limits' 'N16 [G] bare subject, only a TS object key row (weak): byte-identical'
nomiss 'shared_handler_key core' 'N17 [G] bare subject, only a Python dict row (weak): byte-identical'
nomiss 'exported_weak_fn exports' 'N18 [G] bare subject, only an __all__ list row (weak): byte-identical'
nomiss 'op_weak_marker opcode' 'N19 [G] bare subject, only a #define X-macro row (weak): byte-identical'
nomiss 'init_marker_a runner' 'N20a [G] bare subject in a C++ member-initializer list (no call): byte-identical'
nomiss 'VariantOptsMarker request' 'N20b [G] bare subject in a Rust enum tuple variant (no call): byte-identical'
nomiss 'agg_target aggregation' 'N20c [G] bare subject in calls not named for a registration: byte-identical'
nomiss 'how does the light turn on' 'N21 [G] no identifier-shaped word: byte-identical, nothing scanned'
# D1 (rv-reg2-delta): the vocabulary. `use` is a hook prefix, not an adding verb; the noun of an adding verb is the name's last word; `reg` is a verb
# only as the last word or right before a noun (`async_reg`, `reg_handler`), never `reg_value`. Twins stay rows.
nomiss 'Where is `ur_marker_a` defined?' 'D1a [P] useRouter( is a React hook call, no registration'
nomiss 'Where is `acl_marker_a` defined?' 'D1b [P] addCommandLineOption( adds an option: the noun is not the last word'
nomiss 'Where is `rv_marker_a` defined?' 'D1c [P] reg_value( reads a hardware register: reg as a noun'
nomiss 'Where is `rf_marker_a` defined?' 'D1d [P] reg_field( : reg as a noun'
if q aeh_marker_a; then L="$( rowsof )"; if has "$L" 'reg="emitter.addEventHandler("'; then ok "D1e [G] addEventHandler( (noun last) stays a registration"; else no "D1e addEventHandler: ${L:0:300}"; fi; else no "D1e call failed rc=$RC"; fi
if q rh_marker_a; then L="$( rowsof )"; if has "$L" 'reg="reg_handler("'; then ok "D1f [G] reg_handler( (reg before a noun) stays a registration"; else no "D1f reg_handler: ${L:0:300}"; fi; else no "D1f call failed rc=$RC"; fi
# X1 [G]
A1="$( call '--for=Where is barrier_interval_ms defined and what reads it?' )"; A2="$( call '--for=Where is barrier_interval_ms defined and what reads it?' )"
if [ -n "$A1" ] && [ "$A1" = "$A2" ]; then ok "X1a determinism"; else no "X1a two runs differ or empty"; fi
if command -v xmllint >/dev/null 2>&1; then if printf '%s' "$A1" | xmllint --noout - 2>/dev/null; then ok "X1b xmllint well-formed"; else no "X1b not well-formed"; fi; else echo "  SKIP  X1b xmllint not installed"; fi

[ "$fail" -eq 0 ] && echo "forregrowcheck: OK" || echo "forregrowcheck: FAILED"
exit "$fail"
