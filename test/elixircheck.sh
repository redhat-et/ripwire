#!/usr/bin/env bash
# Elixir grammar, definition filtering, call heads, pipes, and deterministic cache round trips.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir "$TMP/cache"
export XDG_CACHE_HOME="$TMP/cache"
cp -R "$ROOT/test/elixirfix" "$TMP/fix"
"$BIN" "$TMP/fix" --no-cache > "$TMP/map.xml"
python3 - "$TMP/map.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
syms = {s.get('n').split('/')[0]: s for s in root.iter('s')}
expected = {'Sample.Math', 'Sample.Run', 'square', 'twice', 'secret', 'answer', 'literal', 'positive', 'pipeline', 'untouched', 'run', 'build', 'quoted', 'branchy', 'Sample.MathTest', 'test squares'}
assert set(syms) == expected, (set(syms), expected)
for name in expected - {'Sample.Math', 'Sample.Run', 'Sample.MathTest'}:
    assert syms[name].get('t') == 'fn', (name, syms[name].attrib)
def calls(name): return {c.get('n').split('/')[0] for c in syms[name].iter('c')}
assert not calls('Sample.Math'), 'typespec became a module call edge'
assert 'square' in calls('twice')
assert 'secret' in calls('answer')
assert {'square', 'twice'} <= calls('pipeline')
assert 'square' in calls('run')
assert 'square' in calls('test squares')
assert 'untouched' in calls('build')
assert 'untouched' not in calls('untouched'), 'function head became a recursive call'
# The documented extraction floor (queries/elixir/tags.scm, docs/ARCHITECTURE.md#elixir-extraction):
# macro-generated code inside `quote do` is NOT indexed, so run.exs's `def phantom` must be absent and
# its `nonexistent(x)` must not become an edge. Asserted by name so a regression says which rule broke.
assert 'phantom' not in syms, 'quoted definition became an indexed symbol'
assert 'nonexistent' not in calls('quoted'), 'quoted call site became a call edge'
print('  PASS Elixir definitions, guards, macros, local/remote calls, pipes and negatives')
PY

# Live-hole arguments execute even when the enclosing quoted syntax is a
# declaration head or metadata. Outer declaration/pattern filters must stop here.
mkdir "$TMP/head-holes"
cat > "$TMP/head-holes/heads.ex" <<'EXHEADHOLES'
defmodule HeadHole do
  def bar(x), do: x
  def seed(), do: :generated
  defmacro generated(x) do
    quote do
      def unquote(bar(x))(arg), do: arg
    end
  end
  defmacro typed(x) do
    quote do
      @spec unquote(bar(x))
    end
  end
  defmacro bare() do
    quote do
      def unquote(seed)(arg), do: arg
    end
  end
  defmacro bound_name(seed) do
    quote do
      def unquote(seed)(arg), do: arg
    end
  end
  defmacro disabled(x) do
    quote unquote: false do
      def unquote(bar(x))(arg), do: arg
    end
  end
end
EXHEADHOLES
"$BIN" "$TMP/head-holes" --no-cache > "$TMP/head-holes.xml"
python3 - "$TMP/head-holes.xml" <<'PYHEADHOLES'
import sys, xml.etree.ElementTree as ET
syms = {s.get('n'): s for s in ET.parse(sys.argv[1]).iter('s')}
def calls(name): return {c.get('n') for c in syms[name].iter('c')}
assert calls('generated/1') == {'bar/1'}, 'quoted declaration head dropped the live-hole call'
assert calls('typed/1') == {'bar/1'}, 'quoted metadata dropped the live-hole call'
assert calls('bare/0') == {'seed/0'}, 'quoted declaration head mistook a live bare call for a pattern'
assert not calls('bound_name/1'), 'bound live-hole variable became a zero-arity call'
assert not calls('disabled/1'), 'disabled declaration-head hole became live'
print('  PASS live holes in quoted declaration heads/metadata, bare calls and variable negatives')
PYHEADHOLES

# Issue #357: quoted syntax is inert, but unquote expressions are evaluated while
# constructing it. Keep this fixture separate from the golden corpus so the gate
# contrasts the call sites and the declined count directly.
mkdir "$TMP/inert"
cat > "$TMP/inert/quoted.ex" <<'EXINERT'
defmodule InertFixture do
  def inert(x), do: x
  def bar(x), do: x
  def splice(x), do: [x]
  def after_call(x), do: x
  def quote(x), do: x
  def comment(x), do: x

  def run(x) do
    quote do
      inert(x)
      foo(unquote(bar(x)))
      [unquote_splicing(splice(x))]
    end
    after_call(x)
    InertFixture.quote(x)
    InertFixture.comment(x)
  end

  def options(x) do
    quote bind_quoted: [item: bar(x)] do
      inert(item)
    end
  end

  def nested(x) do
    quote do
      unquote(quote do
        inert(x)
        unquote(bar(x))
      end)
    end
  end
end
EXINERT
"$BIN" "$TMP/inert" --no-cache > "$TMP/inert.xml"
python3 - "$TMP/inert.xml" <<'PYINERT'
import re, sys, xml.etree.ElementTree as ET
data = open(sys.argv[1]).read()
syms = {s.get('n'): s for s in ET.fromstring(data).iter('s')}
def calls(name): return {c.get('n') for c in syms[name].iter('c')}
assert 'inert/1' not in calls('run/1'), 'ordinary quoted call became an edge'
assert 'bar/1' in calls('run/1'), 'unquote(bar(x)) lost its live call edge'
assert 'splice/1' in calls('run/1'), 'unquote_splicing(splice(x)) lost its live call edge'
assert 'after_call/1' in calls('run/1'), 'call after quote was suppressed'
assert {'quote/1', 'comment/1'} <= calls('run/1'), 'ordinary named functions were treated as special forms'
assert 'bar/1' in calls('options/1'), 'bind_quoted option expression was suppressed'
assert 'inert/1' not in calls('options/1'), 'bind_quoted quote body became live'
assert 'bar/1' in calls('nested/1'), 'inner unquote in nested quote lost its live call edge'
assert 'inert/1' not in calls('nested/1'), 'nested quote body became live'
match = re.search(r'\bdeclined=(\d+)\b', data)
assert match and int(match.group(1)) >= 3, 'inert-region calls vanished from declined accounting'
print('  PASS inert quote bodies, live holes, near misses, boundaries, and declined count')
PYINERT
mkdir "$TMP/inert-control"
python3 - "$TMP/inert/quoted.ex" "$TMP/inert-control/quoted.ex" <<'PYINERTCONTROL'
import pathlib, sys
original = pathlib.Path(sys.argv[1]).read_text()
lines = original.splitlines(keepends=True)
mutated = 0
for i, line in enumerate(lines):
    if line.strip() in {'inert(x)', 'inert(item)'}:
        lines[i] = line[:len(line) - len(line.lstrip())] + 'x\n'
        mutated += 1
    elif line.strip() == 'foo(unquote(bar(x)))':
        lines[i] = line.replace('foo(unquote(bar(x)))', 'unquote(bar(x))')
        mutated += 1
assert mutated == 4, f'control did not remove all four inert call sites: {mutated}'
pathlib.Path(sys.argv[2]).write_text(''.join(lines))
PYINERTCONTROL
"$BIN" "$TMP/inert-control" --no-cache > "$TMP/inert-control.xml"
python3 - "$TMP/inert.xml" "$TMP/inert-control.xml" <<'PYINERTCOUNT'
import re, sys
def declined(path):
    match = re.search(r'\bdeclined=(\d+)\b', open(path).read())
    return int(match.group(1)) if match else 0
assert declined(sys.argv[1]) >= declined(sys.argv[2]) + 4, (declined(sys.argv[1]), declined(sys.argv[2]))
print('  PASS four inert call sites move declined accounting by four')
PYINERTCOUNT
"$BIN" "$TMP/inert" --callees=run/1 --no-cache > "$TMP/inert-callees.xml"
"$BIN" "$TMP/inert" --callers=inert/1 --no-cache > "$TMP/inert-callers.xml"
python3 - "$TMP/inert.xml" "$TMP/inert-callees.xml" "$TMP/inert-callers.xml" <<'PYINERTVERBS'
import sys, xml.etree.ElementTree as ET
map_text, callees_text, callers_text = [open(p).read() for p in sys.argv[1:]]
assert 'including inert Elixir quote sites' in map_text, 'compact map misdescribes declined sites'
callees = ET.fromstring(callees_text)
assert callees.get('declined_calls') == '2', callees.attrib
assert 'including inert Elixir quote sites' in callees_text, 'compact callees misdescribes declined sites'
callers = ET.fromstring(callers_text)
assert callers.get('count') == '0', callers.attrib
assert 'declined_calls' not in callers.attrib, 'inert sites became possible callers'
print('  PASS declined map/callees accounting, compact readings, and no possible callers')
PYINERTVERBS

# A non-Elixir body may quote our legend markers as source text. Only real
# comments outside CDATA may select the inert-decline reading.
mkdir -p "$TMP/marker/src" "$TMP/marker/a" "$TMP/marker/b"
cat > "$TMP/marker/src/run.cpp" <<'CPPMARKER'
int run() {
  const char* marker = R"marker(<!-- hdr:declined=also-counts-ordinary-Elixir-call-sites-inside-inert-quote-AST-after-unquote/unquote_splicing-re-entry;no-edge;not-a-possible-callee -->)marker";
  const char* clause = "ordinary Elixir call candidates in inert quote AST";
  return duplicate();
}
CPPMARKER
printf 'int duplicate() { return 1; }\n' > "$TMP/marker/a/a.cpp"
printf 'int duplicate() { return 2; }\n' > "$TMP/marker/b/b.cpp"
"$BIN" "$TMP/marker" --pack-top-n=3 --no-cache > "$TMP/marker.xml"
python3 - "$TMP/marker.xml" <<'PYMARKER'
import sys, xml.etree.ElementTree as ET
text = open(sys.argv[1]).read()
ET.fromstring(text)
assert 'declined=1' in text and '<![CDATA[' in text, 'marker control is vacuous'
assert 'including inert Elixir quote sites' not in text, 'C++ source text changed the compact declined reading'
print('  PASS non-Elixir CDATA markers cannot select the inert-decline reading')
PYMARKER

# quote options control whether unquote is a live hole (Kernel.SpecialForms.quote/2).
mkdir "$TMP/quote-options"
cat > "$TMP/quote-options/options.ex" <<'EXOPTIONS'
defmodule QuoteOptions do
  def bar(x), do: x
  def splice(x), do: [x]
  def bound(x) do
    quote bind_quoted: [x: x] do
      unquote(bar(x))
      [unquote_splicing(splice(x))]
    end
  end
  def disabled(x) do
    quote unquote: false, do: unquote(bar(x))
  end
  def enabled(x) do
    quote bind_quoted: [x: x], unquote: true do
      unquote(bar(x))
    end
  end
  def nested_inert(x) do
    quote do
      quote do
        unquote(bar(x))
      end
    end
  end
  def nested_disabled(x) do
    quote unquote: false do
      unquote(quote do
        unquote(bar(x))
      end)
    end
  end
end
EXOPTIONS
"$BIN" "$TMP/quote-options" --no-cache > "$TMP/options.xml"
python3 - "$TMP/options.xml" <<'PYOPTIONS'
import sys, xml.etree.ElementTree as ET
syms = {s.get('n'): s for s in ET.parse(sys.argv[1]).iter('s')}
def calls(name): return {c.get('n') for c in syms[name].iter('c')}
assert not calls('bound/1'), 'bind_quoted incorrectly activates unquote/splicing'
assert not calls('disabled/1'), 'unquote: false incorrectly activates unquote'
assert calls('enabled/1') == {'bar/1'}, 'explicit unquote: true failed to restore the live hole'
assert not calls('nested_inert/1'), 'unquote in an inert nested quote became live'
assert not calls('nested_disabled/1'), 'disabled outer hole evaluated its nested quote'
print('  PASS disabled unquote, bind_quoted default, and explicit re-enable')
PYOPTIONS
for n in a b c; do "$BIN" "$TMP/inert" > "$TMP/inert-$n.xml"; done
cmp "$TMP/inert.xml" "$TMP/inert-a.xml"
cmp "$TMP/inert-a.xml" "$TMP/inert-b.xml"
cmp "$TMP/inert-b.xml" "$TMP/inert-c.xml"
echo '  PASS inert count and live edges survive cold/warm round trips'
for n in a b c; do "$BIN" "$TMP/fix" > "$TMP/$n.xml"; done
cmp "$TMP/map.xml" "$TMP/a.xml"
cmp "$TMP/a.xml" "$TMP/b.xml"
cmp "$TMP/b.xml" "$TMP/c.xml"
echo '  PASS cold/warm determinism and XML'
python3 - "$TMP/fix/math.ex" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert 'do: secret()' in s
p.write_text(s.replace('do: secret()', 'do: missing_secret()'))
PY
"$BIN" "$TMP/fix" --no-cache > "$TMP/mut.xml"
python3 - "$TMP/mut.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
syms = {s.get('n').split('/')[0]: s for s in ET.parse(sys.argv[1]).iter('s')}
assert 'secret' in syms
assert 'secret' not in {c.get('n').split('/')[0] for c in syms['answer'].iter('c')}
print('  PASS call-site mutation removes the edge')
PY

"$BIN" "$TMP/fix" --metrics --no-cache > "$TMP/metrics.xml"
python3 - "$TMP/metrics.xml" <<'PYMET'
import sys, xml.etree.ElementTree as ET
syms = {s.get('n').split('/')[0]: s for s in ET.parse(sys.argv[1]).iter('s')}
assert syms['square'].get('params') == '1', syms['square'].attrib
assert syms['answer'].get('params') == '0', syms['answer'].attrib
assert syms['branchy'].get('cx') == '2', syms['branchy'].attrib
assert syms['branchy'].get('nest') == '1', syms['branchy'].attrib
print('  PASS Elixir parameter counts and branch metrics')
PYMET

mkdir "$TMP/broken" "$TMP/tabbed"
printf 'defmodule do\n def broken(), do: 1\nend\n' > "$TMP/broken/broken.ex"
"$BIN" "$TMP/broken" --no-cache > "$TMP/broken.xml"
xmllint --noout "$TMP/broken.xml"
echo '  PASS malformed unnamed module does not crash'
printf 'defmodule Tab do\n def tabbed(), do:\t123456789\nend\n' > "$TMP/tabbed/tab.ex"
"$BIN" "$TMP/tabbed" --no-cache --pack-signatures > "$TMP/tabbed.xml"
python3 - "$TMP/tabbed.xml" <<'PYBODY'
import sys, xml.etree.ElementTree as ET
rows = [d for d in ET.parse(sys.argv[1]).iter('d') if d.get('n') == 'tabbed/0']
assert len(rows) == 1
assert '123456789' not in ''.join(rows[0].itertext()), rows[0].text
print('  PASS tab-separated keyword body is elided from signatures')
PYBODY

# --doctor's binary-path row compares this binary against the `ripwire` on PATH, so a dev tree with a
# stale install (or none) reds the row and, under set -e, the whole gate. test/doctorcheck.sh — which
# owns doctor's exit contract — prepends the binary's own directory for this reason; do the same here.
PATH="$(cd "$(dirname "$BIN")" && pwd):$PATH" "$BIN" "$TMP/fix" --doctor > "$TMP/doctor.xml"
python3 - "$TMP/doctor.xml" <<'PYDOC'
import sys, xml.etree.ElementTree as ET
rows = [c for c in ET.parse(sys.argv[1]).iter('c') if c.get('n') == 'grammars']
assert len(rows) == 1
assert rows[0].get('loaded') == rows[0].get('expected') == '25', rows[0].attrib
print('  PASS doctor loads all 25 grammars and queries')
PYDOC

mkdir "$TMP/boundaries"
cat > "$TMP/boundaries/boundaries.ex" <<'EX'
defmodule Boundary do
  def render(x), do: x
  def seed(), do: 1
  def wrap(x), do: x
  def run(x \\ wrap(seed())), do: x
  def guarded(x \\ seed()) when is_integer(x), do: x
  def pattern(%Unknown{value: x}), do: x
  def invoke(), do: Boundary.render(1)
  defimpl Inspect, for: Any do
    def render(x), do: hidden(x)
    def hidden(x), do: Boundary.seed()
  end
end
defimpl Inspect, for: Atom do
  def outside_impl(x), do: Boundary.seed()
end
EX
"$BIN" "$TMP/boundaries" --no-cache > "$TMP/boundaries.xml"
python3 - "$TMP/boundaries.xml" <<'PYBOUND'
import sys, xml.etree.ElementTree as ET
tree = ET.parse(sys.argv[1])
rows = list(tree.iter('s'))
syms = {s.get('n').split('/')[0]: s for s in rows}
# row 6 (2026-09-12): the row prints sc= (the scope); its canonical id composes as <f p=>::sc::n
byid = {f.get('p') + '::' + s.get('sc') + '::' + s.get('n'): s for f in tree.iter('f') for s in f.iter('s') if s.get('sc')}
def calls(node): return {c.get('n').split('/')[0] for c in node.iter('c')}
# `defimpl P, for: T` defines the module Elixir itself generates, `P.T`, and its clauses are ordinary
# executable functions. They are indexed under that scope, so a name the enclosing module also defines
# (render) yields TWO rows with DISTINCT canonical ids rather than one row or a silent drop.
assert {'Boundary', 'render', 'seed', 'wrap', 'run', 'guarded', 'pattern', 'invoke',
        'hidden', 'outside_impl', 'Inspect.Any', 'Inspect.Atom'} == set(syms), set(syms)
assert len([s for s in rows if s.get('n') == 'render/1']) == 2, 'defimpl render lost or merged'
assert 'boundaries.ex::Boundary::render/1' in byid and 'boundaries.ex::Inspect.Any::render/1' in byid, sorted(byid)
# A defimpl module name is ABSOLUTE: nesting inside `defmodule Boundary` does not make it Boundary.Inspect.Any.
assert byid['boundaries.ex::Inspect.Any::hidden/1'] is not None
assert calls(byid['boundaries.ex::Inspect.Any::render/1']) == {'hidden'}, 'impl-local call escaped its impl'
assert calls(byid['boundaries.ex::Inspect.Any::hidden/1']) == {'seed'}
assert calls(byid['boundaries.ex::Inspect.Atom::outside_impl/1']) == {'seed'}
assert calls(syms['invoke']) == {'render'}
assert calls(syms['run']) == {'wrap', 'seed'}
assert 'seed' in calls(syms['guarded'])
assert not list(syms['pattern'].iter('c'))
assert not list(syms['Boundary'].iter('c')), 'implementation calls leaked into enclosing module'
print('  PASS defimpl clauses indexed under P.For, isolated, with executable defaults')
PYBOUND
