#!/usr/bin/env bash
# forreadercallerscheck.sh — READER-CALLERS (src/forreadercallers.h) and its two triggers in src/forliteral.h: WHOLE-TOKEN (a bare kebab
# option name) and MSG-VERBATIM (a cue-less task that is a message verbatim). ORCH reports/ideas-opus-1111.md C1, ideas-fable-1111.md
# LIT-READER-UP, C8 THROW-SITE; rule frozen in ORCH tmp/reader-callers/RULE.md.
#
# Fixture generated at test time (three tiny repos: py, c, ts). Arms tagged [P] are RED on main c2ad05de7; [G] hold on both.
#   R1 [P] reader callers: --for=WIDGET_DISABLE_ALL prints <lc d="1" of="get_widgets" n="make_validator"> (the reader's one caller)
#   R2 [P] single-caller extra hop: d="2" rows of="make_validator" for build_model and build_adapter, and nothing at d=3
#          (premise: --callers=build_model lists run_all, so d=3 existed to print)
#   R3 [G/P] negatives with premise counts: the test caller (tests/test_loader.py, which --callers lists) is no <lc> row; a
#          literal with no reader function (a module-level dict entry, WIDGET_TABLE_ONLY) prints its <lit> and no <lc>; the
#          unproven caller of a two-definition name (run_flags -> load_flags) is no row while --callers names it via="name"
#   R4 [P] fan-in gate: a reader with 7 callers lists none: <lcn of="hub_reader" n="7" next="--callers=hub_reader"/>
#   K1 [P] kebab trigger: --for="widget-time option" fires <lit s="widget-time" shape="flag"> with lc rows keys_callback, read_callback
#   K1b [G] a reader with two callers takes no d=2 hop (premise: --callers=keys_callback lists main_loop)
#   K2 [G] near misses: "widget-time" with no option word, and "wide-spread option" (9 quoted sites) print no flag <lit>
#   T1 [P] raise site: --for="Widget can't resolve parts of the" fires <lit shape="message"> (no cue word), its reader's caller is the
#          exception constructor (ctor="1") and d=2 is the throw site Injector::lookup
#   T2 [G] near misses: a 3-word cue-less task, and a cue-less text with 4 string sites, print no message <lit>
#   O1 [G] RIPWIRE_NO_READER_CALLERS=1: the same <lit> with no <lc>/<lcn> and no callers legend
#   X1 [G] determinism; X2 [G] xmllint well-formed; X3 [P] the callers legend once, no "--" inside it
#
# Usage: bash test/forreadercallerscheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "forreadercallerscheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"

python3 - "$TMP" <<'PY' || { echo "fixture generator failed"; exit 2; }
import os, sys
d = sys.argv[1]
def w( p, s ):
    p = os.path.join( d, p ); os.makedirs( os.path.dirname( p ), exist_ok = True ); open( p, "w" ).write( s )
# ── py: a reader with one caller (funnel), its two callers, a test caller, a hub reader, a module-level-only literal, an ambiguous name
w( "py/widgets/loader.py", '''import os

def get_widgets():
    disabled = os.getenv('WIDGET_DISABLE_ALL')
    if disabled in ('1', 'true'):
        return ()
    return ('a', 'b')
''' )
w( "py/widgets/validator.py", '''from widgets.loader import get_widgets

def make_validator(schema):
    plugins = get_widgets()
    return (schema, plugins)
''' )
w( "py/widgets/model.py", '''from widgets.validator import make_validator

def build_model(cls):
    return make_validator(cls)

def build_adapter(tp):
    return make_validator(tp)

def run_all():
    build_model(1)
    return build_adapter(2)
''' )
w( "py/tests/test_loader.py", '''from widgets.loader import get_widgets

def test_get_widgets_disabled():
    assert get_widgets() == ('a', 'b')
''' )
w( "py/widgets/table.py", '''SETTINGS = {
    'WIDGET_TABLE_ONLY': 1,
    'other': 2,
}
''' )
w( "py/widgets/hub.py", '''import os

def hub_reader():
    return os.getenv('WIDGET_HUB_VALUE')
''' + "".join( f'''
def hub_user_{i}():
    return hub_reader()
''' for i in range( 7 ) ) )
w( "py/widgets/flags_a.py", '''import os

def load_flags():
    return os.getenv('WIDGET_FLAG_MODE')
''' )
w( "py/widgets/flags_b.py", '''def load_flags():
    return 2
''' )
w( "py/widgets/flags_run.py", '''def run_flags(x):
    return load_flags()
''' )
# ── c: a tmux-like option table and its reader
w( "c/options-table.c", '''struct options_table_entry { const char *name; int type; };
const struct options_table_entry options_table[] = {
	{ .name = "widget-time", .type = 1 },
	{ .name = "other-time", .type = 2 },
};
''' )
w( "c/keys.c", '''extern int options_get_number(void *oo, const char *name);
extern void *global_options;
int keys_next(int c)
{
	int delay;
	delay = options_get_number(global_options, "widget-time");
	if (delay == 0)
		delay = 1;
	return delay + c;
}
int keys_callback(int fd)
{
	return keys_next(fd);
}
int main_loop(int fd)
{
	return keys_callback(fd);
}
''' )
w( "c/tty.c", '''extern int keys_next(int c);
int read_callback(int fd)
{
	while (keys_next(fd) != 0)
		;
	return 0;
}
''' )
w( "c/spread.c", "".join( f'''int spread_{i}(void) {{ return lookup("wide-spread"); }}
''' for i in range( 9 ) ) )
# ── ts: a message built in a const arrow, raised from an exception constructor, thrown by a method
w( "ts/src/messages.ts", '''export const UNKNOWN_WIDGET_MESSAGE = (name: string) => {
  let message = `Widget can't resolve parts of the ${name}`;
  return message;
};
''' )
w( "ts/src/unknown-widget.exception.ts", '''import { UNKNOWN_WIDGET_MESSAGE } from './messages';
export class UnknownWidgetException extends Error {
  constructor(name: string) {
    super(UNKNOWN_WIDGET_MESSAGE(name));
  }
}
''' )
w( "ts/src/injector.ts", '''import { UnknownWidgetException } from './unknown-widget.exception';
export class Injector {
  lookup(name: string): void {
    throw new UnknownWidgetException(name);
  }
}
''' )
w( "ts/src/spread.ts", "".join( f'''export function spreadMsg{i}(): string {{ return "gadget parts are often spread"; }}
''' for i in range( 4 ) ) )
PY

run(){ local repo="$1"; shift; ( cd "$TMP/$repo" && "$BIN" . --no-cache "$@" ) 2>/dev/null; }
has(){ grep -qF -- "$2" "$1"; }
count(){ grep -oF -- "$2" "$1" | wc -l | tr -d ' '; }

# R1-R3
run py --for=WIDGET_DISABLE_ALL >"$TMP/r1"
has "$TMP/r1" '<lc d="1" of="get_widgets" n="make_validator" t="fn" p="widgets/validator.py:3"' && ok "R1 reader caller row" || no "R1 no d=1 row for get_widgets <- make_validator"
has "$TMP/r1" '<lc d="2" of="make_validator" n="build_adapter"' && has "$TMP/r1" '<lc d="2" of="make_validator" n="build_model"' \
    && ok "R2 single-caller extra hop (d=2 build_adapter, build_model)" || no "R2 d=2 rows missing"
run py --callers=build_model >"$TMP/r2c"
if has "$TMP/r2c" 'n="run_all"'; then
    has "$TMP/r1" 'n="run_all"' && no "R2 a d=3 row (run_all) printed" || ok "R2 no d=3 row (premise: --callers=build_model lists run_all)"
else no "R2 premise: --callers=build_model does not list run_all"; fi
run py --callers=get_widgets >"$TMP/r3c"
if has "$TMP/r3c" 'test_get_widgets_disabled'; then
    has "$TMP/r1" 'n="test_get_widgets_disabled"' && no "R3 a test caller is a row" || ok "R3 test caller not a row (premise: --callers lists it)"
else no "R3 premise: --callers=get_widgets does not list the test caller"; fi
n=$( count "$TMP/r1" '<lc ' ); [ "$n" = 3 ] && ok "R3 exactly 3 lc rows ($n)" || no "R3 expected 3 lc rows, saw $n"
run py --for=WIDGET_TABLE_ONLY >"$TMP/r3t"
if has "$TMP/r3t" '<lit s="WIDGET_TABLE_ONLY"'; then
    has "$TMP/r3t" '<lc' && no "R3 a literal with no reader function prints callers" || ok "R3 no-reader literal: <lit> printed, no <lc (premise: 1 lit)"
else no "R3 premise: WIDGET_TABLE_ONLY printed no <lit>"; fi
run py --for=WIDGET_FLAG_MODE >"$TMP/r3u"
run py --callers=load_flags >"$TMP/r3uc"
if has "$TMP/r3uc" 'n="run_flags" p="widgets/flags_run.py:1" via="name"' && has "$TMP/r3u" '<lit s="WIDGET_FLAG_MODE"'; then
    has "$TMP/r3u" 'n="run_flags"' && no "R3 unproven caller run_flags printed" || ok "R3 unproven caller (two load_flags defs) not a row (premise: --callers lists it)"
else no "R3 premise: --callers=load_flags lists no run_flags or no <lit> fired"; fi
# R4
run py --for=WIDGET_HUB_VALUE >"$TMP/r4"
has "$TMP/r4" '<lcn of="hub_reader" n="7" next="--callers=hub_reader"/>' && [ "$( count "$TMP/r4" '<lc ' )" = 0 ] \
    && ok "R4 fan-in gate: lcn n=7, no rows" || no "R4 fan-in gate row missing or rows listed"
# K1-K2
run c "--for=widget-time option" >"$TMP/k1"
has "$TMP/k1" '<lit s="widget-time" shape="flag"' && has "$TMP/k1" '<lc d="1" of="keys_next" n="keys_callback"' && has "$TMP/k1" '<lc d="1" of="keys_next" n="read_callback"' \
    && ok "K1 bare kebab + option word fires shape=flag with reader callers" || no "K1 kebab trigger or its lc rows missing"
run c --callers=keys_callback >"$TMP/k1c"
if has "$TMP/k1c" 'n="main_loop"'; then
    has "$TMP/k1" '<lc d="2"' && no "K1b a d=2 row above a two-caller reader" || ok "K1b two callers: no d=2 hop (premise: --callers=keys_callback lists main_loop)"
else no "K1b premise: --callers=keys_callback does not list main_loop"; fi
run c "--for=widget-time" >"$TMP/k2a"; run c "--for=wide-spread option" >"$TMP/k2b"
run c --grep=wide-spread >"$TMP/k2g"
has "$TMP/k2a" '<lit ' && no "K2 no cue word still fired a lit" || ok "K2 no option word: no <lit"
if [ "$( count "$TMP/k2g" '<hit ' )" -ge 9 ]; then
    has "$TMP/k2b" '<lit s="wide-spread"' && no "K2 a 9-site kebab fired" || ok "K2 9 quoted sites: no flag <lit (premise: grep sees 9)"
else no "K2 premise: --grep sees fewer than 9 wide-spread sites"; fi
# T1-T2
run ts "--for=Widget can't resolve parts of the" >"$TMP/t1"
has "$TMP/t1" 'shape="message"' && has "$TMP/t1" 'n="UnknownWidgetException::constructor" t="method"' && has "$TMP/t1" 'ctor="1"' \
    && has "$TMP/t1" '<lc d="2" of="UnknownWidgetException::constructor" n="Injector::lookup"' \
    && ok "T1 cue-less verbatim message fires; ctor hop reaches the throw site" || no "T1 verbatim trigger or the raise-site hop missing"
run ts "--for=resolve parts of" >"$TMP/t2a"; run ts "--for=gadget parts are often spread" >"$TMP/t2b"
has "$TMP/t2a" 'shape="message"' && no "T2 3-word task fired" || ok "T2 3-word cue-less task: no message <lit"
run ts "--grep=gadget parts are often spread" >"$TMP/t2g"
if [ "$( count "$TMP/t2g" '<hit ' )" -ge 4 ]; then
    has "$TMP/t2b" 'shape="message"' && no "T2 a 4-site cue-less text fired" || ok "T2 4 string sites: no message <lit (premise: grep sees 4)"
else no "T2 premise: --grep sees fewer than 4 sites"; fi
# O1
RIPWIRE_NO_READER_CALLERS=1 run py --for=WIDGET_DISABLE_ALL >"$TMP/o1"
has "$TMP/o1" '<lit s="WIDGET_DISABLE_ALL"' && ! has "$TMP/o1" '<lc' && ! has "$TMP/o1" 'for lit callers' && ok "O1 off switch: lit kept, no callers" || no "O1 off switch"
# X1-X3
run py --for=WIDGET_DISABLE_ALL >"$TMP/x1"; cmp -s "$TMP/r1" "$TMP/x1" && ok "X1 deterministic" || no "X1 two runs differ"
if command -v xmllint >/dev/null 2>&1; then
    bad=0; for f in r1 r4 k1 t1; do xmllint --noout "$TMP/$f" 2>/dev/null || bad=1; done
    [ $bad = 0 ] && ok "X2 well formed" || no "X2 xmllint failed"
else ok "X2 skipped (no xmllint)"; fi
leg=$( grep -o '<!-- ripwire for lit callers.*-->' "$TMP/r1" | head -1 | sed 's/-->.*/-->/' )
[ "$( count "$TMP/r1" 'ripwire for lit callers' )" = 1 ] && [ -n "$leg" ] && ! printf '%s' "${leg:4:${#leg}-7}" | grep -q -- '--' \
    && ok "X3 callers legend once, no -- inside" || no "X3 callers legend"

[ $fail = 0 ] && echo "forreadercallerscheck: ALL PASS" || echo "forreadercallerscheck: FAIL"
exit $fail
