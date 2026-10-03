#!/usr/bin/env bash
# commenttokencheck.sh — a name written in a comment or a string is not code: it feeds no call edge and is no evidence
# for one.
#
#   test/commenttokencheck.sh                          # uses build/ripwire
#   RIPWIRE_BIN=asan/ripwire test/commenttokencheck.sh
#   test/commenttokencheck.sh build_base/ripwire       # the RED run (a pre-change binary)
#
# THE DEFECT. The builtin-method name gate (graph.h BuiltinMethodGate, test/builtinbindcheck.sh) admits a Python
# `x.get( k )` to a same-file `Pool.get` when the file names Pool beyond defining it — Python records no annotation as a
# binding, so `def f( p: Pool )` must count. The count was an identifier-token scan over the WHOLE file's bytes, so a
# `# Pool is the cache` comment, a `"""Feed :class:`Pool`"""` docstring or a `logging.info( 'Pool warm' )` message counted
# exactly like an annotation, and `data.get( "repos" )` on a json dict bound to Pool.get. The scan now runs over the
# house code scanner (clones.h scanCodeTokens: `#` comments and `"…"` strings dropped, and for this consumer `'…'`
# strings too), so only a token the parser would have read as code counts.
#
# ARMS (every fixture is built in $TMP; each Python file defines Pool.get and calls `data.get` on a json dict):
#   (A) a `# Pool` whole-line comment is no evidence: data.get is declined (count="0", declined_calls="1")  RED on base
#   (B) a docstring naming Pool is no evidence                                                              RED on base
#   (C) a single-quoted and a double-quoted string naming Pool are no evidence                              RED on base
#   (D) a triple-single-quoted string naming Pool is no evidence                                            RED on base
#   (E) a TRAILING comment (`x = 1  # Pool`) is no evidence                                                 RED on base
#   (F) NEAR MISS, must keep: `# don't` (an apostrophe in a comment) followed by a code line naming Pool — a scanner that
#       let the apostrophe open a string would swallow the code line and lose the edge
#   (G) NEAR MISS, must keep: `tag = "#"` then `kind = Pool` on the SAME line — a `#` inside a string is not a comment
#   (H) NEAR MISS, must keep: `s = "a\"b"` then `kind = Pool` — an escaped quote does not close the string early
#   (I) NEAR MISS, must keep: `s = 'it"s'` then `kind = Pool` — a `"` inside a `'…'` string opens nothing
#   (J) CONTROL, must keep: `def f( p: Pool )` in the same file (the annotation shape builtinbindcheck arm T pins)
#   (N) A STRING IN ANNOTATION OR SUBSCRIPT POSITION IS A TYPE EXPRESSION, must keep: `-> "Pool"`, `Optional["Pool"]`,
#       `x: "Pool" = …`, `Dict[str, "Pool"]`, `None | "Pool"`, `type["Pool"]` (N6: `type` is a scanner keyword, PEP 585 lower-case
#       generics are the modern spelling) — Python forward references are strings, and builtinbindcheck
#       arm T's `p: "PStr"` is the same shape (the first cut of this fix scanned every string as prose and lost that edge).
#       Disclosed floors, NOT gated: `cast("Pool", x)` and `TypeVar("T", bound="Pool")` are types only by their callee's
#       convention and read as call arguments (declined)
#   (O) ANY OTHER STRING IS PROSE, must decline: an `__all__` tuple entry, a list literal entry (`[` after `=` is no
#       subscript), `return "Pool"`, a call argument `print("Pool")`
#   (P) `//` IS FLOOR DIVISION IN PYTHON, must keep: `n = total // 2; kind = Pool` — the C-family `//`-to-EOL comment rule
#       does not apply to a `#`-comment language, so the rest of the line stays code
#   (Q) TRIPLE-QUOTED STRINGS RUN TO THEIR CLOSING TRIPLE, must keep: an apostrophe inside `'''…'''` (Q1) or a lone `"` inside
#       a `"""…"""` docstring (Q2) must not flip code and string for the rest of the file — the previous cut read `'''` as
#       `''` + `'` and LOST every later code mention (the drop direction the design forbids); Q3 even-quote control keeps;
#       Q4 a triple-quoted string naming the class is still prose, must decline
#   (R) F-STRING FIELDS ARE CODE: `f"{Pool}"` keeps (R1, Python compiles the field); the literal text `f"Pool {x}"` (R2) and an
#       escaped `f"{{Pool}}"` (R3) are prose, must decline
#   (K) INTERPOLATIONS ARE CODE: Python `f"{run()}"` and JS `${run()}` keep their call edge to run (tree-sitter reads
#       the interpolation as code; nothing here strips it)
#   (L) OTHER COMMENT FAMILIES make no call edge: C++ `//` and `/* */`, Lua `--` and `--[[ ]]`, Ruby `#` and
#       `=begin/=end`, JavaScript `//` and `/* */` — each beside a same-named real def and ONE real call; the callers
#       of the def are exactly the real caller (pins: tree-sitter never read a comment as a call)
#   (M) determinism x2 and xmllint on the Python tree; no degrade alert on stderr
#
# Exits non-zero on any failure.

set -u
export PYTHONDONTWRITEBYTECODE=1
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint required"; exit 2; }
echo "commenttokencheck: BIN=$BIN"

# ── helpers ───────────────────────────────────────────────────────────────────────────────────────────────────
root_tag(){ grep -oE "<$2( [^>]*)?>" "$1" | head -1; }
attr(){ printf '%s' "$1" | grep -oE " $2=\"[^\"]*\"" | head -1 | sed -E 's/^[^"]*"([^"]*)"$/\1/'; }
# the caller NAMES of a callers document, sorted, space-joined
names(){ grep -oE '<s [^>]*/>' "$1" | grep -oE ' n="[^"]*"' | sed -E 's/ n="([^"]*)"/\1/' | sort | tr '\n' ' ' | sed -E 's/ $//'; }
# callers_of DIR SELECTOR → $TMP/callers.xml; echoes "names|declined_calls" ("" when the attribute is absent)
callers_of(){
    ( cd "$1" && "$BIN" . --no-cache --callers="$2" ) >"$TMP/callers.xml" 2>"$TMP/callers.err"
    local R; R="$( root_tag "$TMP/callers.xml" callers )"
    [ -n "$R" ] || { printf 'NO-ROOT|'; return 0; }
    printf '%s|%s' "$( names "$TMP/callers.xml" )" "$( attr "$R" declined_calls )"
}
# One Python fixture per arm: $1 = arm dir name, stdin = the body written ABOVE the class (the probe text), so every
# arm shares the same `load` caller, the same json dict receiver and the same Pool.get target.
# Writes $TMP/py_<arm>/m.py (no command substitution around the heredoc: an apostrophe in the probe text must stay text).
pyfix(){
    local d="$TMP/py_$1"; mkdir -p "$d"
    { printf 'import json\nimport logging\n\n'; cat; printf '\n\ndef load(text):\n    data = json.loads(text)\n    return data.get("repos")\n\n\nclass Pool:\n    def get(self, key):\n        return key\n\n    def warm(self, key):\n        return self.get(key)\n'; } >"$d/m.py"
}
# the decline verdict: data.get is NOT a caller, self.get (warm) still is, and the decline is counted once
expect_declined(){   # label dir
    local got; got="$( callers_of "$2" m.py:get )"
    if [ "$got" = "warm|1" ]; then
        ok "$1: data.get declined, warm keeps its edge (names=[warm] declined_calls=1)"
    else
        no "$1: expected names=[warm] declined_calls=1, got [$got]"
    fi
}
# the keep verdict: data.get binds to Pool.get (the file names Pool in CODE), nothing declined
expect_kept(){       # label dir
    local got; got="$( callers_of "$2" m.py:get )"
    if [ "$got" = "load warm|" ]; then
        ok "$1: the code mention keeps data.get bound (names=[load warm], no declined_calls=)"
    else
        no "$1: expected names=[load warm] and no declined_calls=, got [$got]"
    fi
}

# ── (A)–(E) prose names the class: no evidence ─────────────────────────────────────────────────────────────────
echo "=== (A)-(E) a comment, docstring or string naming the class is no evidence for a same-file builtin-named call ==="
pyfix A <<'PY'
# Pool is the cache every loader shares
PY
A="$TMP/py_A"
grep -q '^# Pool' "$A/m.py" || no "(A) presence guard: the fixture lost its comment"
expect_declined "(A) whole-line comment" "$A"

pyfix B <<'PY'
def describe():
    """Feed :class:`Pool` from JSON; Pool.get serves it."""
    return None
PY
B="$TMP/py_B"
grep -q 'Pool.get serves' "$B/m.py" || no "(B) presence guard: the fixture lost its docstring"
expect_declined "(B) docstring" "$B"

pyfix C <<'PY'
def describe():
    logging.info('Pool warm')
    return "Pool"
PY
C="$TMP/py_C"
grep -q "'Pool warm'" "$C/m.py" || no "(C) presence guard: the fixture lost its single-quoted string"
expect_declined "(C) single- and double-quoted strings" "$C"

pyfix D <<'PY'
NOTE = '''Pool keeps the
connections; Pool.get hands one out.'''
PY
D="$TMP/py_D"
grep -q "^NOTE = '''Pool" "$D/m.py" || no "(D) presence guard: the fixture lost its triple-single-quoted string"
expect_declined "(D) triple-single-quoted string" "$D"

pyfix E <<'PY'
LIMIT = 1  # Pool
PY
E="$TMP/py_E"
grep -q '# Pool$' "$E/m.py" || no "(E) presence guard: the fixture lost its trailing comment"
expect_declined "(E) trailing comment" "$E"

# ── (F)–(J) near misses: a code mention next to prose, the edge must survive ────────────────────────────────────
echo "=== (F)-(J) near misses: the class named in CODE beside a comment or string keeps the edge ==="
pyfix F <<'PY'
# don't forget the kind
kind = Pool
PY
F="$TMP/py_F"
grep -q "^# don't" "$F/m.py" || no "(F) presence guard"
expect_kept "(F) apostrophe in a comment, code line after it" "$F"

pyfix G <<'PY'
tag = "#"; kind = Pool
PY
G="$TMP/py_G"
grep -q '^tag = "#"; kind = Pool' "$G/m.py" || no "(G) presence guard"
expect_kept "(G) a # inside a string, code after it on the line" "$G"

pyfix H <<'PY'
s = "a\"b"; kind = Pool
PY
H="$TMP/py_H"
grep -q 's = "a\\"b"; kind = Pool' "$H/m.py" || no "(H) presence guard"
expect_kept "(H) an escaped quote inside a string" "$H"

pyfix I <<'PY'
s = 'it"s'; kind = Pool
PY
I="$TMP/py_I"
grep -q "^s = 'it\"s'; kind = Pool" "$I/m.py" || no "(I) presence guard"
expect_kept "(I) a double quote inside a single-quoted string" "$I"

pyfix J <<'PY'
def typed(p: Pool):
    return p
PY
J="$TMP/py_J"
expect_kept "(J) control: an annotation names the class" "$J"

# ── (N)/(O) a string in annotation or subscript position is a type expression; any other string is prose ─────────
echo "=== (N) a string forward-reference annotation names the class in code: the edge survives ==="
pyfix N1 <<'PY'
def ret(make) -> "Pool":
    return make()
PY
expect_kept "(N1) -> \"Pool\" return annotation" "$TMP/py_N1"
pyfix N2 <<'PY'
from typing import Optional


def opt(p: Optional["Pool"]):
    return p
PY
expect_kept "(N2) Optional[\"Pool\"] subscript" "$TMP/py_N2"
pyfix N3 <<'PY'
def local(make):
    x: "Pool" = make()
    return x
PY
expect_kept "(N3) x: \"Pool\" = … annotated local" "$TMP/py_N3"
pyfix N4 <<'PY'
from typing import Dict


def mapped(d: Dict[str, "Pool"]):
    return d
PY
expect_kept "(N4) Dict[str, \"Pool\"] second subscript member" "$TMP/py_N4"
pyfix N5 <<'PY'
def union(p: None | "Pool"):
    return p
PY
expect_kept "(N5) None | \"Pool\" union member" "$TMP/py_N5"
pyfix N6 <<'PY'
def mk(cls: type["Pool"]):
    return cls()
PY
expect_kept "(N6) type[\"Pool\"] — a keyword as the subscript base" "$TMP/py_N6"

echo "=== (O) a string anywhere else stays prose: a tuple, a list, a return value, a call argument ==="
pyfix O1 <<'PY'
__all__ = ("Pool", "load")
PY
expect_declined "(O1) __all__ tuple entry" "$TMP/py_O1"
pyfix O2 <<'PY'
NAMES = ["Pool"]
PY
expect_declined "(O2) list literal entry (the [ follows =, no subscript)" "$TMP/py_O2"
pyfix O3 <<'PY'
def name():
    return "Pool"
PY
expect_declined "(O3) return \"Pool\"" "$TMP/py_O3"
pyfix O4 <<'PY'
def shout():
    print("Pool")
PY
expect_declined "(O4) call argument" "$TMP/py_O4"

echo "=== (P) Python's // is floor division, not a comment: the code after it on the line counts ==="
pyfix P <<'PY'
def half(total, make):
    n = total // 2; kind = Pool
    return make(n, kind)
PY
expect_kept "(P) n = total // 2; kind = Pool — the mention after // stays code" "$TMP/py_P"

echo "=== (Q) a triple-quoted string runs to its closing triple: an odd inner quote does not flip the scanner ==="
pyfix Q1 <<'PY'
NOTE = '''Don't forget the cache'''


def kind_of(make):
    kind = Pool
    return make(kind)
PY
expect_kept "(Q1) an apostrophe inside '''…''' then a code mention" "$TMP/py_Q1"
pyfix Q2 <<'PY'
def rod(make):
    """The 5" rod."""
    kind = Pool
    return make(kind)
PY
expect_kept "(Q2) a lone \" inside a \"\"\"docstring\"\"\" then a code mention" "$TMP/py_Q2"
pyfix Q3 <<'PY'
def quoted(make):
    """Says "hi" twice."""
    kind = Pool
    return make(kind)
PY
expect_kept "(Q3) control: an even number of inner quotes" "$TMP/py_Q3"
pyfix Q4 <<'PY'
NOTE = '''Pool's cache is warm'''
PY
expect_declined "(Q4) a triple-quoted string naming the class is prose" "$TMP/py_Q4"

echo "=== (R) an f-string's {…} fields are code, its literal text is prose ==="
pyfix R1 <<'PY'
def label():
    return f"{Pool}"
PY
expect_kept "(R1) f\"{Pool}\" — the field names the class in code" "$TMP/py_R1"
pyfix R2 <<'PY'
def label(x):
    return f"Pool {x}"
PY
expect_declined "(R2) f\"Pool {x}\" — the name is literal text" "$TMP/py_R2"
pyfix R3 <<'PY'
def label():
    return f"{{Pool}}"
PY
expect_declined "(R3) f\"{{Pool}}\" — escaped braces are literal text" "$TMP/py_R3"

# ── (K) interpolations are code ────────────────────────────────────────────────────────────────────────────────
echo "=== (K) a call inside an f-string / template-literal interpolation keeps its edge ==="
mkdir -p "$TMP/kpy" "$TMP/kjs"
cat >"$TMP/kpy/m.py" <<'PY'
def run():
    return 1


def show():
    return f"{run()}"
PY
cat >"$TMP/kjs/m.js" <<'JS'
function run() { return 1; }
function show() { return `${run()}`; }
JS
got="$( callers_of "$TMP/kpy" m.py:run )"
if [ "$got" = "show|" ]; then ok "(K) Python f\"{run()}\" keeps the edge show -> run"; else no "(K) Python f-string interpolation: expected [show|], got [$got]"; fi
got="$( callers_of "$TMP/kjs" m.js:run )"
if [ "$got" = "show|" ]; then ok "(K) JS \${run()} keeps the edge show -> run"; else no "(K) JS template interpolation: expected [show|], got [$got]"; fi

# ── (L) the other comment families make no edge ────────────────────────────────────────────────────────────────
echo "=== (L) a call spelled only inside a comment is no caller (C++, Lua, Ruby, JavaScript) ==="
mkdir -p "$TMP/lcpp" "$TMP/llua" "$TMP/lrb" "$TMP/ljs"
cat >"$TMP/lcpp/m.cpp" <<'CPP'
int helper( int x ) { return x + 1; }
// decoy_line(): helper( 1 ) is spelled here and nowhere near a call
int decoy_line( int x ) { return x; }
/* decoy_block(): helper( 2 ) again, inside a block comment */
int decoy_block( int x ) { return x; }
int real_caller( int x ) { return helper( x ); }
CPP
cat >"$TMP/llua/m.lua" <<'LUA'
local function helper(x) return x + 1 end
-- decoy_line: helper(1) is spelled here only
local function decoy_line(x) return x end
--[[ decoy_block: helper(2) inside a block comment ]]
local function decoy_block(x) return x end
local function real_caller(x) return helper(x) end
return real_caller
LUA
cat >"$TMP/lrb/m.rb" <<'RB'
def helper(x)
  x + 1
end

# decoy_line: helper(1) is spelled here only
def decoy_line(x)
  x
end

=begin
decoy_block: helper(2) inside a block comment
=end
def decoy_block(x)
  x
end

def real_caller(x)
  helper(x)
end
RB
cat >"$TMP/ljs/m.js" <<'JS'
function helper(x) { return x + 1; }
// decoy_line: helper(1) is spelled here only
function decoy_line(x) { return x; }
/* decoy_block: helper(2) inside a block comment */
function decoy_block(x) { return x; }
function real_caller(x) { return helper(x); }
JS
for fam in lcpp:m.cpp llua:m.lua lrb:m.rb ljs:m.js; do
    d="${fam%%:*}"; f="${fam#*:}"
    grep -c 'helper(' "$TMP/$d/$f" | grep -qE '^[3-9]$' || no "(L) presence guard: $f should spell helper( at least three times"
    got="$( callers_of "$TMP/$d" "$f:helper" )"
    if [ "$got" = "real_caller|" ]; then ok "(L) $f: callers of helper are exactly [real_caller]"; else no "(L) $f: expected [real_caller|], got [$got]"; fi
done

# ── (M) determinism, well-formedness, stderr ───────────────────────────────────────────────────────────────────
echo "=== (M) determinism x2, xmllint, no degrade alert ==="
( cd "$A" && "$BIN" . --no-cache ) >"$TMP/m1.xml" 2>"$TMP/m1.err"
( cd "$A" && "$BIN" . --no-cache ) >"$TMP/m2.xml" 2>/dev/null
if cmp -s "$TMP/m1.xml" "$TMP/m2.xml"; then ok "(M) the default map is byte-identical across two runs"; else no "(M) two runs differ"; fi
if xmllint --noout "$TMP/m1.xml" 2>/dev/null; then ok "(M) the map is well-formed XML"; else no "(M) xmllint rejected the map"; fi
if ( cd "$A" && "$BIN" . --no-cache --callers=m.py:get ) 2>&1 >/dev/null | grep -qiE 'degrade|ALERT'; then no "(M) a degrade alert on stderr"; else ok "(M) no degrade alert on stderr"; fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
