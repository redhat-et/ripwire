#!/usr/bin/env bash
# Gleam grammar, definitions, local/qualified calls, pipes, test scope, and deterministic cache round trips.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir "$TMP/cache"
export XDG_CACHE_HOME="$TMP/cache"
cp -R "$ROOT/test/gleamfix" "$TMP/fix"

"$BIN" "$TMP/fix" --no-cache > "$TMP/map.xml"
python3 - "$TMP/map.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
rows = list(ET.parse(sys.argv[1]).iter('s'))
syms = {s.get('n'): s for s in rows}
expected = {'Color', 'Point', 'Meters', 'native', 'add', 'increment', 'pipeline', 'announce', 'add_test'}
assert set(syms) == expected, (set(syms), expected)
for name in {'Color', 'Point', 'Meters'}:
    assert syms[name].get('t') == 'struct', (name, syms[name].attrib)
for name in expected - {'Color', 'Point', 'Meters'}:
    assert syms[name].get('t') == 'fn', (name, syms[name].attrib)
def calls(name): return {c.get('n') for c in syms[name].iter('c')}
assert calls('increment') == {'add'}
assert {'increment', 'add'} <= calls('pipeline')
assert calls('add_test') == {'add'}
test_files = [f for f in ET.parse(sys.argv[1]).iter('f') if any(s.get('n') == 'add_test' for s in f.iter('s'))]
assert len(test_files) == 1 and 'test' in test_files[0].get('p', ''), [f.attrib for f in test_files]
print('  PASS Gleam definitions, calls, pipes and test scope')
PY

for call in map debug; do
  "$BIN" "$TMP/fix" --no-cache --uses="$call" --legend=compact > "$TMP/uses-$call.xml"
  python3 - "$TMP/uses-$call.xml" "$call" <<'PY'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
rows = list(root.iter('u'))
assert root.get('external') == '1', root.attrib
assert any(row.get('role') == 'call' and row.get('in_id') == 'announce' for row in rows), rows
PY
done
echo '  PASS qualified piped external calls'

"$BIN" "$TMP/fix" --deps --no-cache --legend=compact > "$TMP/deps.xml"
python3 - "$TMP/deps.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
files = {row.get('p'): row for row in root.iter('f')}
assert files['math.gleam'].get('afferent') == '1', files['math.gleam'].attrib
assert root.find('health').get('dep_langs').split(',')[-1] == 'gleam'
assert any(row.get('t') == 'math' for row in files['math_test.gleam'].iter('inc'))
print('  PASS Gleam import capture and exact module-path resolution')
PY

"$BIN" "$TMP/fix" --callees=add_test --no-cache --legend=compact > "$TMP/callees.xml"
python3 - "$TMP/callees.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
rows = list(root.iter('s'))
assert root.get('graph_ambiguous') == '0', root.attrib
assert len(rows) == 1 and rows[0].get('p', '').startswith('math.gleam:'), [r.attrib for r in rows]
print('  PASS imported module narrows a duplicate function name')
PY

for n in a b c; do "$BIN" "$TMP/fix" > "$TMP/$n.xml"; done
cmp "$TMP/map.xml" "$TMP/a.xml"
cmp "$TMP/a.xml" "$TMP/b.xml"
cmp "$TMP/b.xml" "$TMP/c.xml"
xmllint --noout "$TMP/c.xml"
echo '  PASS cold/warm determinism and XML'

python3 - "$TMP/fix/math.gleam" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert 'add(value, 1)' in s
p.write_text(s.replace('add(value, 1)', 'missing_add(value, 1)'))
PY
"$BIN" "$TMP/fix" --no-cache > "$TMP/mut.xml"
python3 - "$TMP/mut.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
syms = {s.get('n'): s for s in ET.parse(sys.argv[1]).iter('s')}
assert 'add' not in {c.get('n') for c in syms['increment'].iter('c')}
print('  PASS call-site mutation removes the edge')
PY
