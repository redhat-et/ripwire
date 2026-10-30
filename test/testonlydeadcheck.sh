#!/usr/bin/env bash
# testonlydeadcheck.sh — D1 TESTONLY-DEAD: --dead-code lists library functions whose EVERY indexed caller is test code
# as <to n= t= p= l=> rows (test-only=N on the root, absent at 0). Never in count=, never a <d> row.
# Arms: A1 Python private-module def called only by a test is listed; A2-A6 near misses stay off (a library caller,
# an ALIASED library import, no internal evidence, a method, a decorated def); A7 a C static called only by a test is
# listed; A8 a zero-caller Python private def is not a count= row; A9 a tree with none is byte-identical in shape
# (no test-only=, no clause); A10 rows only on the first page; A11 well-formed XML.
# Fix round 1 (review rv-testonly-dead): A12 a test-path helper (the candidate's own test-ness) is not listed; A13 a
# dunder module (__init__/__main__) public def is not listed; A14 `static` is a C-family fact only (a Python parameter, a
# TS string literal and a Rust 'static lifetime are not linkage, for <to> and for <d>); A15 a setup.cfg / pyproject
# entry-point target is live; A16 a def a package glob-re-exports is live; A17 a conftest.py def is test code; A18 a
# notebook that uses the name keeps it off; A19 the compact legend names the floor classes.
#   RIPWIRE_BIN=build/ripwire bash test/testonlydeadcheck.sh     # red on a pre-D1 binary (A1, A7)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
echo "testonlydeadcheck: BIN=$BIN"

F="$TMP/fx"; mkdir -p "$F/pkg" "$F/tests" "$F/src"
cat > "$F/pkg/_tools.py" <<'P'
def only_tested(x):
    return x + 1

def lib_used(x):
    return x * 2

def alias_used(x):
    return x - 1

def zero_callers(x):
    return x

@cache_it
def decorated_tested(x):
    return x

class Widget:
    def method_tested(self):
        return 1
P
cat > "$F/pkg/public.py" <<'P'
def public_tested(x):
    return x
P
cat > "$F/pkg/user.py" <<'P'
from pkg._tools import alias_used as renamed
from pkg._tools import lib_used

def run(v):
    return lib_used(v) + renamed(v)
P
cat > "$F/tests/test_tools.py" <<'P'
from pkg._tools import only_tested, lib_used, alias_used, decorated_tested, Widget
from pkg.public import public_tested

def test_all():
    assert only_tested(1) == 2
    assert lib_used(1) == 2
    assert alias_used(1) == 0
    assert decorated_tested(1) == 1
    assert Widget().method_tested() == 1
    assert public_tested(1) == 1
P
cat > "$F/src/core.c" <<'C'
static int c_only_tested(int x)
{
    return x + 1;
}
int core_entry(int x)
{
    return x;
}
C
cat > "$F/tests/test_core.c" <<'C'
int run_core_test(void)
{
    return c_only_tested(1);
}
C
runin(){ local dir="$1"; shift; ( cd "$dir" || exit 1; "$BIN" "$dir" --no-cache "$@" 2>/dev/null ); }
run(){ runin "$F" "$@"; }
# An absence arm reads a run only after the run is proven to have answered: rc 0 and a <dead-code root (a refused or
# empty run would pass every "is not listed" check vacuously). chk NAME DIR ARGS... sets CHK to the output.
CHK=""
chk(){ local name="$1" dir="$2"; shift 2; CHK="$( runin "$dir" "$@" )"; local rc=$?
       if [ "$rc" != 0 ] || ! printf '%s' "$CHK" | grep -q '<dead-code'; then no "$name: the run did not answer (rc=$rc, no <dead-code root)"; return 1; fi; return 0; }
chk "A1 main run" "$F" --dead-code && OUT="$CHK" || OUT=""
has(){ printf '%s' "$OUT" | grep -q "<to n=\"$1\""; }
if has only_tested; then ok "A1 private-module def called only by a test is a <to> row"; else no "A1 only_tested not listed"; fi
if printf '%s' "$OUT" | grep -q 'test-only="2"'; then ok "A1 root test-only=2"; else no "A1 test-only= is not 2: $( printf '%s' "$OUT" | grep -o 'test-only="[0-9]*"' )"; fi
if has lib_used; then no "A2 lib_used (a library caller) listed"; else ok "A2 a library caller keeps it off"; fi
if has alias_used; then no "A3 alias_used (an aliased library import) listed"; else ok "A3 an aliased library import keeps it off"; fi
if has public_tested; then no "A4 public_tested (no internal evidence) listed"; else ok "A4 a public module/name is not listed"; fi
if has method_tested; then no "A5 a method listed"; else ok "A5 methods are not listed"; fi
if has decorated_tested; then no "A6 a decorated def listed"; else ok "A6 a decorated def is not listed"; fi
if has c_only_tested; then ok "A7 a C static called only by a test is a <to> row"; else no "A7 c_only_tested not listed"; fi
if printf '%s' "$OUT" | grep -q '<d n="zero_callers"'; then no "A8 a zero-caller Python private def became a count= row"; else ok "A8 zero-caller Python private def is not a <d> row"; fi
if printf '%s' "$OUT" | grep -q '<dead-code [^>]*count="0"'; then ok "A8 count=0 (test-only rows are not in count=)"; else no "A8 count= is not 0"; fi
chk "A9 filtered run" "$F" --dead-code=pkg/public.py && NONE="$CHK" || NONE="<run failed>"
if [ "$NONE" = "<run failed>" ] || printf '%s' "$NONE" | grep -q 'test-only'; then no "A9 test-only text on an answer with no <to> row"; else ok "A9 no test-only=/clause when none (present-only)"; fi
if printf '%s' "$OUT" | grep -q 'test-only=N'; then ok "A9 the clause rides the answer that carries test-only="; else no "A9 clause missing"; fi
chk "A10 second-page run" "$F" --dead-code --limit=1 --offset=1 && P2="$CHK" || P2="<to n=\"run-failed\""
if printf '%s' "$P2" | grep -q '<to n="'; then no "A10 <to> rows repeated past the first page"; else ok "A10 <to> rows ride the first page only"; fi

# ── fix round 1 fixtures (tree G) ──────────────────────────────────────────────────────────────────────────────────────────
G="$TMP/gx"; mkdir -p "$G/pkg" "$G/pkg/pkg3" "$G/pkg/pkg4" "$G/pkg/sub" "$G/tests" "$G/src" "$G/web/src" "$G/web/test" "$G/notebooks" "$G/rs"
# A12/A13: the candidate's own test-ness, and the dunder modules
cat > "$G/tests/_helpers.py" <<'P'
def _fixture_value():
    return 3
P
cat > "$G/pkg/__init__.py" <<'P'
def api(x):
    return x
P
cat > "$G/pkg/__main__.py" <<'P'
def entry():
    return 0
P
# A14: `static` is a C-family fact. A Python parameter / string, a TS string literal, a Rust 'static lifetime are not linkage.
cat > "$G/pkg/serve.py" <<'P'
def serve(path, static=False):
    return path

def render(kind="static"):
    return kind

def serve_zero(path, static=False):
    return path
P
cat > "$G/web/package.json" <<'P'
{ "name": "modes", "main": "src/mode.ts" }
P
cat > "$G/web/src/mode.ts" <<'P'
export function pickMode(m: 'static' | 'dynamic'): number {
    return m.length;
}
export function pickModeZero(m: 'static' | 'dynamic'): number {
    return m.length;
}
P
cat > "$G/web/test/mode.test.ts" <<'P'
import { pickMode } from '../src/mode';
test('mode', () => { expect(pickMode('static')).toBe(6); });
P
cat > "$G/rs/lib.rs" <<'P'
fn leak_zero(s: &'static str) -> usize {
    s.len()
}
P
cat > "$G/src/dead.c" <<'C'
static int c_dead_zero(int x)
{
    return x + 7;
}
C
# A14b (CR 4396503844): `static` inside [ ] qualifies the array PARAMETER, it is no storage class: this function is external
cat > "$G/src/arrparam.c" <<'C'
int c_ext_arr(int v[static 1])
{
    return v[0];
}
C
cat > "$G/tests/test_arrparam.c" <<'C'
int run_arr_test(void)
{
    int a[1] = { 1 };
    return c_ext_arr(a);
}
C
# A15: entry points
cat > "$G/pkg/_cli.py" <<'P'
def cli_entry():
    return 0
P
cat > "$G/pkg/_cli2.py" <<'P'
def cli_entry2():
    return 0
P
cat > "$G/setup.cfg" <<'P'
[options.entry_points]
console_scripts =
    tool2 = pkg._cli:cli_entry
P
cat > "$G/pyproject.toml" <<'P'
[project.scripts]
tool3 = "pkg._cli2:cli_entry2"
P
# A16: package glob re-export
cat > "$G/pkg/pkg3/__init__.py" <<'P'
from ._impl import *
P
cat > "$G/pkg/pkg3/_impl.py" <<'P'
def compute(x):
    return x + 1
P
# A16b (CR 4396503848): a glob import with a run of spaces before `import` still names its module (`_impl2`, not `_impl2 `)
cat > "$G/pkg/pkg4/__init__.py" <<'P'
from ._impl2  import *
P
cat > "$G/pkg/pkg4/_impl2.py" <<'P'
def compute2(x):
    return x + 4
P
cat > "$G/pkg/pkg3/_solo.py" <<'P'
def solo_compute(x):
    return x + 2
P
cat > "$G/pkg/pkg3/_allx.py" <<'P'
__all__ = ["all_compute"]

def all_compute(x):
    return x + 3
P
# A17: conftest.py
cat > "$G/conftest.py" <<'P'
def _make_db():
    return {}
P
cat > "$G/pkg/sub/conftest.py" <<'P'
def _make_sub_db():
    return {}
P
# A18: notebook
cat > "$G/pkg/_tools.py" <<'P'
def nb_helper(x):
    return x

def nb_unused(x):
    return x
P
cat > "$G/notebooks/analysis.ipynb" <<'P'
{"cells":[{"cell_type":"code","metadata":{},"source":["from pkg._tools import nb_helper\n","def run_it(v):\n","    return nb_helper(v)\n"],"outputs":[],"execution_count":null}],"metadata":{},"nbformat":4,"nbformat_minor":5}
P
cat > "$G/tests/test_g.py" <<'P'
from conftest import _make_db
from pkg.sub.conftest import _make_sub_db
from tests._helpers import _fixture_value
from pkg import api
from pkg.__main__ import entry
from pkg.serve import serve, render, serve_zero
from pkg._cli import cli_entry
from pkg._cli2 import cli_entry2
from pkg.pkg3._impl import compute
from pkg.pkg3._solo import solo_compute
from pkg.pkg3._allx import all_compute
from pkg.pkg4._impl2 import compute2
from pkg._tools import nb_helper, nb_unused

def test_g():
    assert _make_db() == {} and _make_sub_db() == {} and _fixture_value() == 3
    assert api(1) == 1 and entry() == 0
    assert serve("x") == "x" and render() == "static"
    assert cli_entry() == 0 and cli_entry2() == 0
    assert compute(1) == 2 and solo_compute(1) == 3 and all_compute(1) == 4 and compute2(1) == 5
    assert nb_helper(1) == 1 and nb_unused(1) == 1
P
chk "A12-A18 tree G" "$G" --dead-code && GOUT="$CHK" || GOUT=""
gto(){ printf '%s' "$GOUT" | grep -q "<to n=\"$1\""; }
gd(){ printf '%s' "$GOUT" | grep -q "<d n=\"$1\""; }
if gto _fixture_value; then no "A12 a test-path helper (the candidate's own test-ness) was listed"; else ok "A12 a def in a test path is test code, not a <to> row"; fi
if gto api || gto entry; then no "A13 a dunder-module public def was listed (api/entry)"; else ok "A13 __init__.py / __main__.py defs are not privacy evidence"; fi
if gto serve || gto render || gto pickMode; then no "A14 a Python static= parameter / 'static' string / TS 'static' literal counted as linkage for <to>"; else ok "A14 <to>: static is not a keyword outside C/C++/ObjC"; fi
if gd serve_zero || gd pickModeZero || gd leak_zero; then no "A14 a Python parameter / TS literal / Rust 'static counted as linkage for <d>"; else ok "A14 <d>: static is not a keyword outside C/C++/ObjC"; fi
if gd c_dead_zero; then ok "A14 near miss: a C static zero-caller function is still a <d> row"; else no "A14 near miss: c_dead_zero lost its <d> row"; fi
if gto c_ext_arr; then no "A14b a C function with a static ARRAY-parameter bound (external linkage) was listed as test-only"; else ok "A14b int f(int v[static 1]) is external: not a <to> row"; fi
if gto compute2; then no "A16b a def a double-space glob import (from ._impl2  import *) re-exports was listed"; else ok "A16b a glob import with extra spaces before import still names its module"; fi
if gto cli_entry || gto cli_entry2; then no "A15 a setup.cfg / pyproject entry-point target was listed (cli_entry/cli_entry2)"; else ok "A15 a manifest entry-point target is live"; fi
if gto compute || gto all_compute; then no "A16 a package glob / __all__ re-exported def was listed (compute/all_compute)"; else ok "A16 a glob / __all__ re-exported def is live"; fi
if gto solo_compute; then ok "A16 near miss: a private module no package re-exports is still listed"; else no "A16 near miss: solo_compute lost its row (glob match too wide)"; fi
if gto _make_db || gto _make_sub_db; then no "A17 a conftest.py def was listed"; else ok "A17 conftest.py defs are test code, not <to> rows"; fi
if gto nb_helper; then no "A18 a def a notebook cell uses was listed"; else ok "A18 a notebook use keeps it off"; fi
if gto nb_unused; then ok "A18 near miss: a def no notebook names is still listed"; else no "A18 near miss: nb_unused lost its row"; fi
# A20 (CR 4396503875): a library file the index lists but vetting cannot read vets NOTHING, so no test-only row is claimed and stderr says so.
# The unreadable file is a cached one (the warm run lists it from the cache without opening it); it spells the candidate in a string only.
H="$TMP/hx"; mkdir -p "$H/src" "$H/tests"
printf 'static int h_only_tested(int x)\n{\n    return x + 1;\n}\n' > "$H/src/core.c"
printf 'int run_h_test(void)\n{\n    return h_only_tested(1);\n}\n' > "$H/tests/test_core.c"
printf 'const char *nm = "h_only_tested";\nint user_of(int x)\n{\n    return x * 2;\n}\n' > "$H/src/user.c"
HC="$TMP/h.cache"
if chk "A20 readable run (cold, caches)" "$H" --dead-code --cache="$HC"; then
    if printf '%s' "$CHK" | grep -q '<to n="h_only_tested"'; then no "A20 premise: a string spelling in a library file did not keep the row off"; else ok "A20 premise: the library file's spelling keeps h_only_tested off while readable"; fi
fi
chmod 000 "$H/src/user.c"
if [ "$( id -u )" != 0 ] && ! cat "$H/src/user.c" >/dev/null 2>&1; then
    HERR="$TMP/h.err"
    HOUT="$( cd "$H" && "$BIN" "$H" --cache="$HC" --dead-code 2>"$HERR" )"; hrc=$?
    if [ "$hrc" = 0 ] && printf '%s' "$HOUT" | grep -q '<dead-code' && ! printf '%s' "$HOUT" | grep -q '<to n="h_only_tested"' && grep -q 'cannot read src/user.c' "$HERR"
    then ok "A20 an unreadable library file: no test-only claim, and stderr names the file"
    else no "A20 unreadable library file: rc=$hrc, <to> row or stderr line wrong ($( grep -c . "$HERR" ) stderr lines)"; fi
else
    echo "  SKIP  A20 cannot make a file unreadable here (root or no chmod)"
fi
chmod 644 "$H/src/user.c"
# A19: the compact legend (the default) names the floor classes, present-only with the rows
if printf '%s' "$OUT" | grep -q 'test-only=N' && printf '%s' "$OUT" | grep -q 'run time'; then ok "A19 the compact clause names the floor classes"; else no "A19 the compact test-only clause does not name the floor classes"; fi
if command -v xmllint >/dev/null 2>&1; then
    if printf '%s' "$OUT" | xmllint --noout - 2>/dev/null; then ok "A11 well-formed"; else no "A11 not well-formed"; fi
    if run --dead-code --legend=full | xmllint --noout - 2>/dev/null; then ok "A11 full legend well-formed"; else no "A11 full legend not well-formed"; fi
else
    echo "  SKIP  A11 xmllint absent"
fi
[ "$fail" = 0 ] && echo "testonlydeadcheck: PASS" || echo "testonlydeadcheck: FAIL"
exit "$fail"
