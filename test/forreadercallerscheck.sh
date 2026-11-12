#!/usr/bin/env bash
# forreadercallerscheck.sh — READER-CALLERS (src/forreadercallers.h) and its two triggers in src/forliteral.h: WHOLE-TOKEN (a bare kebab
# option name) and MSG-VERBATIM (a cue-less task that is a message verbatim). ORCH reports/ideas-opus-1111.md C1, ideas-fable-1111.md
# LIT-READER-UP, C8 THROW-SITE; rule frozen in ORCH tmp/reader-callers/RULE.md.
#
# Fixture generated at test time (three tiny repos: py, c, ts). Arms tagged [P] are RED on main c2ad05de7; [G] hold on both;
# [F] are RED on 2dd66bafb (the CodeRabbit fix round) and green after.
#   R1 [P] reader callers: --for=WIDGET_DISABLE_ALL prints <lc d="1" of="get_widgets" n="make_validator"> (the reader's one caller)
#   R2 [P] single-caller extra hop: d="2" rows of="make_validator" for build_model and build_adapter, and nothing at d=3
#          (premise: --callers=build_model lists run_all, so d=3 existed to print)
#   R3 [G/P] negatives with premise counts: the test caller (tests/test_loader.py, which --callers lists) is no <lc> row; a
#          literal with no reader function (a module-level dict entry, WIDGET_TABLE_ONLY) prints its <lit> and no <lc>; the
#          unproven caller of a two-definition name (run_flags -> load_flags) is no row while --callers names it via="name"
#   R4 [P] fan-in gate: a reader with 7 callers lists none: <lcn of="hub_reader" n="7" next="--callers=hub_reader"/>
#   R5 [F] reader limit (CR 4540061421): 5 readers, each with a caller; the first 3 are walked and <lcn readers_more="2"/> says the
#          other 2 were not (premise: --callers=rd_3 lists use_rd_3, so a dropped reader had a caller)
#   R5b [F] (CR 4550333670): a caller cut by the 12-row cap is not printed, so a 4th reader whose only caller it is counts in
#          readers_more=1 (premise: --callers=rd_d lists shared_x, rd_d is an ls row, 12 lc rows)
#   R6 [F] constructor hub (CR 4540061415): a constructor whose class is built in 7 places is a hub; its lcn carries next= (the
#          constructor's own callers) and class_next="--callers=Hubby" (the construction sites; premise: that command lists all 7,
#          the next= one lists none of them)
#   K1 [P] kebab trigger: --for="widget-time option" fires <lit s="widget-time" shape="flag"> with lc rows keys_callback, read_callback
#   K1b [G] a reader with two callers takes no d=2 hop (premise: --callers=keys_callback lists main_loop)
#   K2 [G] near misses: "widget-time" with no option word, and "wide-spread option" (9 quoted sites) print no flag <lit>
#   T1 [P] raise site: --for="Widget can't resolve parts of the" fires <lit shape="message"> (no cue word), its reader's caller is the
#          exception constructor (ctor="1") and d=2 is the throw site Injector::lookup
#   T2 [G] near misses: a 3-word cue-less task, and a cue-less text with 4 string sites, print no message <lit>
#   T3 [F] unclassified site (CR 4540061404): a cue-less text whose one site the span tier did not classify (an .astro file with no
#          frontmatter: k="?") prints no message <lit> (premise: the same text with a message cue word lists that k="?" row)
#   O1 [G] RIPWIRE_NO_READER_CALLERS=1: the same <lit> with no <lc>/<lcn> and no callers legend
#   X1 [G] determinism; X2 [G] xmllint well-formed; X3 [P] the callers legend once, no "--" inside it
#
# Usage: bash test/forreadercallerscheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
unset RIPWIRE_NO_READER_CALLERS   # CR 4540061440: an inherited off switch would empty every ordinary arm (O1 sets it per command)
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "forreadercallerscheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
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
# R5: five readers of one literal, each with one caller
w( "py/widgets/many.py", "import os\n" + "".join( f'''
def rd_{i}():
    return os.getenv('WIDGET_MANY')

def use_rd_{i}():
    return rd_{i}()
''' for i in range( 5 ) ) )
# R5b (CR 4550333670): rd_a and rd_b take 6 callers each (the 12-row cap), rd_c's one caller shared_x is past the cap, and
# shared_x is the 4th reader rd_d's only caller
w( "py/widgets/capped.py", "import os\n" + "".join( f'''
def rd_{r}():
    return os.getenv('WIDGET_CAPPED')
''' for r in "abcd" ) + "".join( f'''
def c{r}_{i}():
    return rd_{r}()
''' for r in "ab" for i in range( 6 ) ) + '''
def shared_x():
    rd_c()
    return rd_d()
''' )
# R6: a constructor reader whose class is constructed in 7 places
w( "py/widgets/hubctor.py", '''import os

class Hubby:
    def __init__(self):
        self.v = os.getenv('WIDGET_CTOR_VALUE')
''' + "".join( f'''
def make_hubby_{i}():
    return Hubby()
''' for i in range( 7 ) ) )
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
w( "ts/src/banner.astro", '''<div>Gizmo can't resolve parts of the page</div>
''' )
w( "ts/src/spread.ts", "".join( f'''export function spreadMsg{i}(): string {{ return "gadget parts are often spread"; }}
''' for i in range( 4 ) ) )
PY

run(){ local repo="$1"; shift; ( cd "$TMP/$repo" && "$BIN" . --no-cache "$@" ) 2>/dev/null; }
has(){ grep -qF -- "$2" "$1"; }
count(){ grep -oF -- "$2" "$1" | wc -l | tr -d ' '; }

# R1-R3
run py --for=WIDGET_DISABLE_ALL >"$TMP/r1"
if has "$TMP/r1" '<lc d="1" of="get_widgets" n="make_validator" t="fn" p="widgets/validator.py:3"'; then ok "R1 reader caller row"; else no "R1 no d=1 row for get_widgets <- make_validator"; fi
if has "$TMP/r1" '<lc d="2" of="make_validator" n="build_adapter"' && has "$TMP/r1" '<lc d="2" of="make_validator" n="build_model"'; then ok "R2 single-caller extra hop (d=2 build_adapter, build_model)"; else no "R2 d=2 rows missing"; fi
run py --callers=build_model >"$TMP/r2c"
if has "$TMP/r2c" 'n="run_all"'; then
    if has "$TMP/r1" 'n="run_all"'; then no "R2 a d=3 row (run_all) printed"; else ok "R2 no d=3 row (premise: --callers=build_model lists run_all)"; fi
else no "R2 premise: --callers=build_model does not list run_all"; fi
run py --callers=get_widgets >"$TMP/r3c"
if has "$TMP/r3c" 'test_get_widgets_disabled'; then
    if has "$TMP/r1" 'n="test_get_widgets_disabled"'; then no "R3 a test caller is a row"; else ok "R3 test caller not a row (premise: --callers lists it)"; fi
else no "R3 premise: --callers=get_widgets does not list the test caller"; fi
n=$( count "$TMP/r1" '<lc ' ); if [ "$n" = 3 ]; then ok "R3 exactly 3 lc rows ($n)"; else no "R3 expected 3 lc rows, saw $n"; fi
run py --for=WIDGET_TABLE_ONLY >"$TMP/r3t"
if has "$TMP/r3t" '<lit s="WIDGET_TABLE_ONLY"'; then
    if has "$TMP/r3t" '<lc'; then no "R3 a literal with no reader function prints callers"; else ok "R3 no-reader literal: <lit> printed, no <lc (premise: 1 lit)"; fi
else no "R3 premise: WIDGET_TABLE_ONLY printed no <lit>"; fi
run py --for=WIDGET_FLAG_MODE >"$TMP/r3u"
run py --callers=load_flags >"$TMP/r3uc"
if has "$TMP/r3uc" 'n="run_flags" p="widgets/flags_run.py:1" via="name"' && has "$TMP/r3u" '<lit s="WIDGET_FLAG_MODE"'; then
    if has "$TMP/r3u" 'n="run_flags"'; then no "R3 unproven caller run_flags printed"; else ok "R3 unproven caller (two load_flags defs) not a row (premise: --callers lists it)"; fi
else no "R3 premise: --callers=load_flags lists no run_flags or no <lit> fired"; fi
# R4
run py --for=WIDGET_HUB_VALUE >"$TMP/r4"
if has "$TMP/r4" '<lcn of="hub_reader" n="7" next="--callers=hub_reader"/>' && [ "$( count "$TMP/r4" '<lc ' )" = 0 ]; then ok "R4 fan-in gate: lcn n=7, no rows"; else no "R4 fan-in gate row missing or rows listed"; fi
# R5
run py --for=WIDGET_MANY >"$TMP/r5"; run py --callers=rd_3 >"$TMP/r5c"
if has "$TMP/r5c" 'n="use_rd_3"' && has "$TMP/r5" 'in="rd_3"'; then
    if has "$TMP/r5" '<lcn readers_more="2"/>' && [ "$( count "$TMP/r5" '<lc ' )" = 3 ] && ! has "$TMP/r5" 'n="use_rd_3"'; then ok "R5 reader limit: 3 readers walked, readers_more=2 (premise: rd_3 is an ls row and has a caller)"
    else no "R5 readers past the limit dropped without readers_more=2 (or rows changed)"; fi
else no "R5 premise: rd_3 is no ls row or --callers=rd_3 lists no use_rd_3"; fi
n=$( count "$TMP/r1" ' readers_more="' ); m=$( count "$TMP/r1" '<lc ' )
if [ "$m" -gt 0 ]; then if [ "$n" = 0 ]; then ok "R5 one reader: no readers_more= (premise: $m lc rows printed)"; else no "R5 readers_more= on a one-reader lit"; fi
else no "R5 premise: the one-reader lit printed no lc rows"; fi
# R5b: a caller omitted by the row cap is no printed caller, so the reader it alone calls counts in readers_more=
run py --for=WIDGET_CAPPED >"$TMP/r5b"; run py --callers=rd_d >"$TMP/r5bc"
if has "$TMP/r5bc" 'n="shared_x"' && has "$TMP/r5b" 'in="rd_d"' && [ "$( count "$TMP/r5b" '<lc ' )" = 12 ]; then
    if has "$TMP/r5b" '<lcn more="1" readers_more="1"/>' && ! has "$TMP/r5b" 'n="shared_x"'; then ok "R5b a row-capped caller still counts for readers_more=1 (premise: rd_d is an ls row, its one caller shared_x, 12 lc rows)"
    else no "R5b readers_more= missed rd_d, whose only caller was cut by the row cap: $( grep -o '<lcn [^>]*>' "$TMP/r5b" | tr '\n' ' ' )"; fi
else no "R5b premise: rd_d no ls row, --callers=rd_d lists no shared_x, or not 12 lc rows ($( count "$TMP/r5b" '<lc ' ))"; fi
# R6
run py --for=WIDGET_CTOR_VALUE >"$TMP/r6"; run py --callers=Hubby >"$TMP/r6k"; run py --callers=Hubby.__init__ >"$TMP/r6i"
nk=$( count "$TMP/r6k" 'n="make_hubby_' ); ni=$( count "$TMP/r6i" 'n="make_hubby_' )
if [ "$nk" = 7 ] && [ "$ni" = 0 ]; then
    if has "$TMP/r6" '<lcn of="Hubby::__init__" n="7" next="--callers=Hubby.__init__" class_next="--callers=Hubby"/>'; then ok "R6 ctor hub: class_next covers the 7 construction sites (premise: class lists $nk, next= lists $ni)"
    else no "R6 ctor hub lcn carries no class_next=--callers=Hubby"; fi
else no "R6 premise: --callers=Hubby lists $nk make_hubby (want 7), --callers=Hubby.__init__ lists $ni (want 0)"; fi
if has "$TMP/r4" '<lcn of="hub_reader" n="7"'; then
    if has "$TMP/r4" ' class_next="'; then no "R6 class_next= on a plain function hub"; else ok "R6 plain-function hub: no class_next= (premise: its lcn printed)"; fi
else no "R6 premise: the hub_reader lcn is missing"; fi
# K1-K2
run c "--for=widget-time option" >"$TMP/k1"
if has "$TMP/k1" '<lit s="widget-time" shape="flag"' && has "$TMP/k1" '<lc d="1" of="keys_next" n="keys_callback"' && has "$TMP/k1" '<lc d="1" of="keys_next" n="read_callback"'; then ok "K1 bare kebab + option word fires shape=flag with reader callers"; else no "K1 kebab trigger or its lc rows missing"; fi
run c --callers=keys_callback >"$TMP/k1c"
if has "$TMP/k1c" 'n="main_loop"'; then
    if has "$TMP/k1" '<lc d="2"'; then no "K1b a d=2 row above a two-caller reader"; else ok "K1b two callers: no d=2 hop (premise: --callers=keys_callback lists main_loop)"; fi
else no "K1b premise: --callers=keys_callback does not list main_loop"; fi
run c "--for=widget-time" >"$TMP/k2a"; run c "--for=wide-spread option" >"$TMP/k2b"
run c --grep=wide-spread >"$TMP/k2g"
if has "$TMP/k2a" '<lit '; then no "K2 no cue word still fired a lit"; else ok "K2 no option word: no <lit"; fi
if [ "$( count "$TMP/k2g" '<hit ' )" -ge 9 ]; then
    if has "$TMP/k2b" '<lit s="wide-spread"'; then no "K2 a 9-site kebab fired"; else ok "K2 9 quoted sites: no flag <lit (premise: grep sees 9)"; fi
else no "K2 premise: --grep sees fewer than 9 wide-spread sites"; fi
# T1-T2
run ts "--for=Widget can't resolve parts of the" >"$TMP/t1"
if has "$TMP/t1" 'shape="message"' && has "$TMP/t1" 'n="UnknownWidgetException::constructor" t="method"' && has "$TMP/t1" 'ctor="1"' && has "$TMP/t1" '<lc d="2" of="UnknownWidgetException::constructor" n="Injector::lookup"'; then ok "T1 cue-less verbatim message fires; ctor hop reaches the throw site"; else no "T1 verbatim trigger or the raise-site hop missing"; fi
run ts "--for=resolve parts of" >"$TMP/t2a"; run ts "--for=gadget parts are often spread" >"$TMP/t2b"
if has "$TMP/t2a" 'shape="message"'; then no "T2 3-word task fired"; else ok "T2 3-word cue-less task: no message <lit"; fi
run ts "--grep=gadget parts are often spread" >"$TMP/t2g"
if [ "$( count "$TMP/t2g" '<hit ' )" -ge 4 ]; then
    if has "$TMP/t2b" 'shape="message"'; then no "T2 a 4-site cue-less text fired"; else ok "T2 4 string sites: no message <lit (premise: grep sees 4)"; fi
else no "T2 premise: --grep sees fewer than 4 sites"; fi
# T3
run ts "--for=Gizmo can't resolve parts of the" >"$TMP/t3"; run ts "--for=error Gizmo can't resolve parts of the" >"$TMP/t3c"
if has "$TMP/t3c" '<ls p="src/banner.astro" l="1" k="?"'; then
    if has "$TMP/t3" 'shape="message"'; then no "T3 a cue-less text with only an unclassified site fired a message <lit"; else ok "T3 unclassified-only site: no message <lit (premise: the cued task lists the k=? row)"; fi
else no "T3 premise: the cued task lists no k=? banner.astro row"; fi
# O1
RIPWIRE_NO_READER_CALLERS=1 run py --for=WIDGET_DISABLE_ALL >"$TMP/o1"
if has "$TMP/o1" '<lit s="WIDGET_DISABLE_ALL"' && ! has "$TMP/o1" '<lc' && ! has "$TMP/o1" 'for lit callers'; then ok "O1 off switch: lit kept, no callers"; else no "O1 off switch"; fi
# X1-X3
run py --for=WIDGET_DISABLE_ALL >"$TMP/x1"; if cmp -s "$TMP/r1" "$TMP/x1"; then ok "X1 deterministic"; else no "X1 two runs differ"; fi
if command -v xmllint >/dev/null 2>&1; then
    bad=0; for f in r1 r4 r5 r6 k1 t1; do xmllint --noout "$TMP/$f" 2>/dev/null || bad=1; done
    if [ $bad = 0 ]; then ok "X2 well formed"; else no "X2 xmllint failed"; fi
else ok "X2 skipped (no xmllint)"; fi
leg=$( grep -o '<!-- ripwire for lit callers.*-->' "$TMP/r1" | head -1 | sed 's/-->.*/-->/' )
if [ "$( count "$TMP/r1" 'ripwire for lit callers' )" = 1 ] && [ -n "$leg" ] && ! printf '%s' "${leg:4:${#leg}-7}" | grep -q -- '--'; then ok "X3 callers legend once, no -- inside"; else no "X3 callers legend"; fi

[ $fail = 0 ] && echo "forreadercallerscheck: ALL PASS" || echo "forreadercallerscheck: FAIL"
exit $fail
