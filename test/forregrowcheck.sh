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
nomiss 'where is get_states used' 'N3a [G] no cue word: byte-identical'
nomiss 'what does get_states get' 'N3b [G] get without to: byte-identical'
nomiss 'get_states turned off' 'N3c [G] turned without into: byte-identical'
nomiss 'where is closed_anchor handled' 'N4 [G] a registration call closed on an earlier line holds no later anchor'
nomiss 'where is no_such_key_here defined' 'N5 [G] an identifier the index lacks, with no site: no block, no claim'
nomiss 'where is generated_only_key defined' 'N6 [G] an identifier the index lacks whose only site is no row: no block'
# X1 [G]
A1="$( call '--for=Where is barrier_interval_ms defined and what reads it?' )"; A2="$( call '--for=Where is barrier_interval_ms defined and what reads it?' )"
if [ -n "$A1" ] && [ "$A1" = "$A2" ]; then ok "X1a determinism"; else no "X1a two runs differ or empty"; fi
if command -v xmllint >/dev/null 2>&1; then if printf '%s' "$A1" | xmllint --noout - 2>/dev/null; then ok "X1b xmllint well-formed"; else no "X1b not well-formed"; fi; else echo "  SKIP  X1b xmllint not installed"; fi

[ "$fail" -eq 0 ] && echo "forregrowcheck: OK" || echo "forregrowcheck: FAILED"
exit "$fail"
