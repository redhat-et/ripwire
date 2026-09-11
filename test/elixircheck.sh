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
syms = {s.get('n'): s for s in root.iter('s')}
expected = {'Sample.Math', 'Sample.Run', 'square', 'twice', 'secret', 'answer', 'literal', 'positive', 'pipeline', 'untouched', 'run', 'build', 'quoted', 'branchy', 'Sample.MathTest', 'test squares'}
assert set(syms) == expected, (set(syms), expected)
for name in expected - {'Sample.Math', 'Sample.Run', 'Sample.MathTest'}:
    assert syms[name].get('t') == 'fn', (name, syms[name].attrib)
def calls(name): return {c.get('n') for c in syms[name].iter('c')}
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
syms = {s.get('n'): s for s in ET.parse(sys.argv[1]).iter('s')}
assert 'secret' in syms
assert 'secret' not in {c.get('n') for c in syms['answer'].iter('c')}
print('  PASS call-site mutation removes the edge')
PY

"$BIN" "$TMP/fix" --metrics --no-cache > "$TMP/metrics.xml"
python3 - "$TMP/metrics.xml" <<'PYMET'
import sys, xml.etree.ElementTree as ET
syms = {s.get('n'): s for s in ET.parse(sys.argv[1]).iter('s')}
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
rows = [d for d in ET.parse(sys.argv[1]).iter('d') if d.get('n') == 'tabbed']
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
assert rows[0].get('loaded') == rows[0].get('expected') == '23', rows[0].attrib
print('  PASS doctor loads all 23 grammars and queries')
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
rows = list(ET.parse(sys.argv[1]).iter('s'))
syms = {s.get('n'): s for s in rows}
byid = {s.get('id'): s for s in rows if s.get('id')}
def calls(node): return {c.get('n') for c in node.iter('c')}
# `defimpl P, for: T` defines the module Elixir itself generates, `P.T`, and its clauses are ordinary
# executable functions. They are indexed under that scope, so a name the enclosing module also defines
# (render) yields TWO rows with DISTINCT canonical ids rather than one row or a silent drop.
assert {'Boundary', 'render', 'seed', 'wrap', 'run', 'guarded', 'pattern', 'invoke',
        'hidden', 'outside_impl', 'Inspect.Any', 'Inspect.Atom'} == set(syms), set(syms)
assert len([s for s in rows if s.get('n') == 'render']) == 2, 'defimpl render lost or merged'
assert 'boundaries.ex::Boundary::render' in byid and 'boundaries.ex::Inspect.Any::render' in byid, sorted(byid)
# A defimpl module name is ABSOLUTE: nesting inside `defmodule Boundary` does not make it Boundary.Inspect.Any.
assert byid['boundaries.ex::Inspect.Any::hidden'] is not None
assert calls(byid['boundaries.ex::Inspect.Any::render']) == {'hidden'}, 'impl-local call escaped its impl'
assert calls(byid['boundaries.ex::Inspect.Any::hidden']) == {'seed'}
assert calls(byid['boundaries.ex::Inspect.Atom::outside_impl']) == {'seed'}
assert calls(syms['invoke']) == {'render'}
assert calls(syms['run']) == {'wrap', 'seed'}
assert 'seed' in calls(syms['guarded'])
assert not list(syms['pattern'].iter('c'))
assert not list(syms['Boundary'].iter('c')), 'implementation calls leaked into enclosing module'
print('  PASS defimpl clauses indexed under P.For, isolated, with executable defaults')
PYBOUND
