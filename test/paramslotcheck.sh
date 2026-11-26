#!/usr/bin/env bash
# paramslotcheck.sh — BX2 FIX 8: a function passed as an ARGUMENT, whose callee stores that parameter into a struct field,
# MAY be called by every call through that field (ingest_valuerefs.h paramSlotFact, valuerefindex.h ParamSlots; lane BS1's
# tmux-02 shape, results/BS1_BLINDSPOT_1118).
#
#   test/paramslotcheck.sh [BIN]        # BIN defaults to $RIPWIRE_BIN, then build/ripwire
#
# tmux registers client_signal with `proc_set_signals( client_proc, client_signal )`; proc_set_signals stores the parameter
# (`tp->signalcb = signalcb;`) and proc_signal_cb calls the field (`tp->signalcb( signo );`). The value row landed in
# proc_set_signals#arg1 and stopped: no called_by=. Go and Rust already joined a registrar's stored parameter to its slot
# (IX1-V2); the C family recorded no fact. It now does, typed the way a C field store is (the object's declared struct
# type through the typedef facts), so the <vr> row names the slot's callers: called_by= called_at= via="slot" — a MAY-call,
# never an edge (count= and --impact do not move).
#
# Arm classes: [P] positive — RED on the parent binary; [N] near miss — must not join; [C] control.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
DIR="$( mktemp -d )"; trap 'rm -rf "$DIR"' EXIT
fail=0
# every verdict is an if/else: a failed write of a PASS line must never print FAIL for an arm that passed (gateexitcheck G2)
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
has(){ if printf '%s' "$1" | grep -qF -- "$2"; then ok "$3"; else no "$3 — missing: $2"; fi; }
hasnt(){ if printf '%s' "$1" | grep -qF -- "$2"; then no "$3 — present: $2"; else ok "$3"; fi; }
body(){ printf '%s' "$1" | sed 's/^.*-->//'; }

echo "paramslotcheck: BIN=$BIN"
[ -x "$BIN" ] || { echo "  FAIL  no ripwire binary at $BIN"; exit 1; }

# ── the corpus, written here ─────────────────────────────────────────────────────────────────────────────────────────
# proc.c   the tmux shape: proc_set stores its parameter cb into tp->sigcb; proc_fire calls tp->sigcb( s ).
# other.c  a DIFFERENT struct with a field of the same name: other_set stores into o->sigcb, other_fire calls it.
# keep.c   keep_local stores its parameter in a local (no field); keep_two stores it into two different fields (decides nothing).
# client.c on_signal -> proc_set, on_other -> other_set, on_local -> keep_local, on_two -> keep_two.
mkdir -p "$DIR/src"
cat >"$DIR/src/p.h" <<'C'
struct proc { void (*sigcb)( int ); };
struct other { void (*sigcb)( int ); };
struct two { void (*a)( int ); void (*b)( int ); };
void proc_set( struct proc *tp, void (*cb)( int ) );
void other_set( struct other *o, void (*cb)( int ) );
void keep_local( void (*cb)( int ) );
void keep_two( struct two *t, void (*cb)( int ) );
C
cat >"$DIR/src/proc.c" <<'C'
#include "p.h"
void proc_set( struct proc *tp, void (*cb)( int ) )
{
    tp->sigcb = cb;
}
void proc_fire( struct proc *tp, int s )
{
    tp->sigcb( s );
}
C
cat >"$DIR/src/other.c" <<'C'
#include "p.h"
void other_set( struct other *o, void (*cb)( int ) )
{
    o->sigcb = cb;
}
void other_fire( struct other *o, int s )
{
    o->sigcb( s );
}
C
cat >"$DIR/src/keep.c" <<'C'
#include "p.h"
void keep_local( void (*cb)( int ) )
{
    void (*held)( int ) = cb;
    (void)held;
}
void keep_two( struct two *t, void (*cb)( int ) )
{
    t->a = cb;
    t->b = cb;
}
void two_fire( struct two *t, int s )
{
    t->a( s );
}
C
cat >"$DIR/src/client.c" <<'C'
#include "p.h"
static void on_signal( int s ) { (void)s; }
static void on_other( int s ) { (void)s; }
static void on_local( int s ) { (void)s; }
static void on_two( int s ) { (void)s; }
void client_main( struct proc *p, struct other *o, struct two *t )
{
    proc_set( p, on_signal );
    other_set( o, on_other );
    keep_local( on_local );
    keep_two( t, on_two );
}
C
cd "$DIR" || exit 1
export TMPDIR="$DIR/tmp"; mkdir -p "$TMPDIR"
rw(){ "$BIN" "$@" 2>/dev/null; }

echo "[P] a stored parameter joins its field's callers"
a="$( body "$( rw . --callers=on_signal )" )"
has "$a" 'called_by="proc_fire"' "[P1] --callers=on_signal: the <vr> row names proc_fire, which calls the field proc_set stores it in"
has "$a" 'called_at="src/proc.c:8"' "[P2] ... at the call through the field (proc.c:8)"
has "$a" 'via="slot"' "[P3] ... on the same-type tier (struct proc on both sides)"
hasnt "$a" 'other_fire' "[N1] a same-named field of ANOTHER struct type does not join"
a="$( body "$( rw . --callers=on_other )" )"
has "$a" 'called_by="other_fire"' "[P4] --callers=on_other names other_fire"
hasnt "$a" 'proc_fire' "[N2] ... never proc_fire"
a="$( body "$( rw . --impact=on_signal )" )"
has "$a" 'called_by="proc_fire"' "[P5] --impact=on_signal carries the same slot callers"
q='{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"find_referencing_symbols","arguments":{"path":"'"$DIR"'","symbol":"on_signal"}}}'
a="$( printf '%s\n%s\n' '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{}}' "$q" | "$BIN" --mcp 2>/dev/null )"
has "$a" 'called_by\":\"proc_fire' "[P6] MCP find_referencing_symbols carries them too"

echo "[N] what must not join"
a="$( body "$( rw . --callers=on_local )" )"
hasnt "$a" 'called_by=' "[N3] a parameter kept in a local joins nothing"
a="$( body "$( rw . --callers=on_two )" )"
hasnt "$a" 'two_fire' "[N4] a parameter stored into two different fields decides nothing"

echo "[C] the call graph is unchanged"
a="$( body "$( rw . --callers=on_signal )" )"
has "$a" 'count="0"' "[C1] count= stays 0: a may-call through a slot is never an edge"
if [ "$( rw . --callers=on_signal )" = "$( rw . --callers=on_signal )" ]; then ok "[C2] two runs byte-identical"; else no "[C2] two runs differ"; fi

if [ "$fail" -eq 0 ]; then echo "paramslotcheck: ALL PASS"; else echo "paramslotcheck: FAIL"; fi
exit "$fail"
