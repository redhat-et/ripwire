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

"$BIN" "$TMP/fix" --doctor > "$TMP/doctor.xml"
python3 - "$TMP/doctor.xml" <<'PYDOC'
import sys, xml.etree.ElementTree as ET
rows = [c for c in ET.parse(sys.argv[1]).iter('c') if c.get('n') == 'grammars']
assert len(rows) == 1
assert rows[0].get('loaded') == rows[0].get('expected') == '22', rows[0].attrib
print('  PASS doctor loads all 22 grammars and queries')
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
assert len([s for s in rows if s.get('n') == 'render']) == 1
assert {'Boundary', 'render', 'seed', 'wrap', 'run', 'guarded', 'pattern', 'invoke'} == set(syms), set(syms)
assert {c.get('n') for c in syms['invoke'].iter('c')} == {'render'}
assert {c.get('n') for c in syms['run'].iter('c')} == {'wrap', 'seed'}
assert 'seed' in {c.get('n') for c in syms['guarded'].iter('c')}
assert not list(syms['pattern'].iter('c'))
assert not list(syms['Boundary'].iter('c')), 'implementation calls leaked into enclosing module'
print('  PASS implementation isolation and executable defaults without declaration-head edges')
PYBOUND
