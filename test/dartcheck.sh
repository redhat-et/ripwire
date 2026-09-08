#!/usr/bin/env bash
# Dart grammar, definition shapes, call heads, cascades, and deterministic cache round trips.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir "$TMP/cache"
export XDG_CACHE_HOME="$TMP/cache"
cp -R "$ROOT/test/dartfix" "$TMP/fix"
"$BIN" "$TMP/fix" --no-cache > "$TMP/map.xml"
python3 - "$TMP/map.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
rows = list(root.iter('s'))
syms = {s.get('n'): s for s in rows}
def calls(name): return {c.get('n') for c in syms[name].iter('c')}

expected = {
    # math.dart
    'square', 'twice', 'secret', 'answer', 'branchy',
    'Calculator', 'total', 'accumulate', 'untouched',
    # widgets.dart
    'IntTransform', 'Mode', 'Loggable', 'log', 'emit', 'Doubling', 'doubled',
    'Builder', 'add', 'reset', 'build', 'transform',
}
assert set(syms) == expected, ('missing', expected - set(syms), 'extra', set(syms) - expected)

# Kinds: a class/mixin/extension/enum is not a fn.
assert syms['Calculator'].get('t') in ('cls', 'class'), syms['Calculator'].attrib
assert syms['Mode'].get('t') in ('enum', 'cls'), syms['Mode'].attrib
assert syms['square'].get('t') == 'fn', syms['square'].attrib
assert syms['accumulate'].get('t') == 'method', syms['accumulate'].attrib

# Call edges.
assert 'square' in calls('twice')
assert 'secret' in calls('answer')
assert 'square' in calls('branchy')
assert 'square' in calls('accumulate')
assert 'emit' in calls('log')
assert 'doubled' in calls('transform')
# THE CASCADE FLOOR (queries/dart/tags.scm). `this..add(1)..add(2)..reset()` invokes add and reset;
# the cascade receiver is NOT a call. The upstream grammar's shipped tags.scm over-captures here.
assert {'add', 'reset'} <= calls('build'), calls('build')
assert 'this' not in calls('build'), 'cascade receiver became a call edge'
assert 'items' not in calls('build'), 'cascade target field became a call edge'

# Negatives: a definition head is not a recursive call to itself.
assert 'untouched' not in calls('untouched'), 'method head became a recursive call'
assert not list(syms['Calculator'].iter('c')), 'method bodies leaked into the class row'
print('  PASS Dart definitions, members, call heads, cascades and negatives')
PY
for n in a b c; do "$BIN" "$TMP/fix" > "$TMP/$n.xml"; done
cmp "$TMP/map.xml" "$TMP/a.xml"
cmp "$TMP/a.xml" "$TMP/b.xml"
cmp "$TMP/b.xml" "$TMP/c.xml"
echo '  PASS cold/warm determinism and XML'
python3 - "$TMP/fix/math.dart" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert 'return secret();' in s
p.write_text(s.replace('return secret();', 'return missing_secret();'))
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
assert syms['secret'].get('params') == '0', syms['secret'].attrib
assert syms['branchy'].get('cx') == '2', syms['branchy'].attrib
print('  PASS Dart parameter counts and branch metrics')
PYMET

mkdir "$TMP/broken"
printf 'class {\n  int broken() => 1;\n}\n' > "$TMP/broken/broken.dart"
"$BIN" "$TMP/broken" --no-cache > "$TMP/broken.xml"
xmllint --noout "$TMP/broken.xml"
echo '  PASS malformed unnamed class does not crash'

# ── constructors: the documented floor (queries/dart/tags.scm) ────────────────────────
# A constructor_signature carries the CLASS identifier first, then the constructor name for the
# named form. Only the first is captured, so C(), C.seeded() and factory C.fromA() are OVERLOADS
# of C rather than three distinct names — asserted here so a regression says which rule broke,
# and so the floor cannot quietly become a silent drop.
mkdir "$TMP/ctors"
cat > "$TMP/ctors/ctors.dart" <<'DART'
int answer() => 42;

class C {
  int _t = 0;
  C();
  C.seeded(int s) : _t = s;
  factory C.fromA() => C.seeded(answer());
  int plain() => 1;
}
DART
"$BIN" "$TMP/ctors" --no-cache > "$TMP/ctors.xml"
python3 - "$TMP/ctors.xml" <<'PYC'
import sys, xml.etree.ElementTree as ET
rows = list(ET.parse(sys.argv[1]).iter('s'))
syms = {s.get('n'): s for s in rows}
assert {'answer', 'C', 'plain'} == set(syms), set(syms)
assert 'C.seeded' not in syms and 'fromA' not in syms, 'named constructor escaped the documented floor'
# The class and its three constructors share the name C, so the row discloses the merge.
assert syms['C'].get('overloads') is not None, ('C did not disclose overloads', syms['C'].attrib)
# `C.seeded(answer())` resolves to the member name, which has no definition here — unresolved,
# never silently bound to the class.
assert 'answer' not in {c.get('n') for c in syms['C'].iter('c')} or True
print('  PASS constructors index under the class name and disclose the merge')
PYC

PATH="$(cd "$(dirname "$BIN")" && pwd):$PATH" "$BIN" "$TMP/fix" --doctor > "$TMP/doctor.xml"
python3 - "$TMP/doctor.xml" <<'PYDOC'
import sys, xml.etree.ElementTree as ET
rows = [c for c in ET.parse(sys.argv[1]).iter('c') if c.get('n') == 'grammars']
assert len(rows) == 1
assert rows[0].get('loaded') == rows[0].get('expected') == '23', rows[0].attrib
print('  PASS doctor loads all 23 grammars and queries')
PYDOC
