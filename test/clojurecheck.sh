#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir "$TMP/cache"
export XDG_CACHE_HOME="$TMP/cache"
cp -R "$ROOT/test/clojurefix" "$TMP/fix"

"$BIN" "$TMP/fix" --no-cache >"$TMP/cold.xml"
xmllint --noout "$TMP/cold.xml"
python3 - "$TMP/cold.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
t = ET.parse(sys.argv[1])
files = {f.get('p') for f in t.iter('f')}
assert files == {'core.clj', 'browser.cljs', 'shared.cljc', 'tasks.bb'}, files
rows = list(t.iter('s'))
names = {s.get('n').split('/')[0] for s in rows}
expected = {'sample.core', 'sample.browser', 'sample.shared', 'sample.tasks', 'answer', 'cached',
            'square', 'secret', 'unless', 'area', 'Greeter', 'Person', 'Counter', 'quoted', 'interop',
            'run', 'render', 'shared', 'task', 'quoted-holder'}
assert names == expected, (names, expected)
by = {s.get('n').split('/')[0]: s for s in rows}
for name, kind in {'answer':'var', 'cached':'var', 'square':'fn', 'unless':'macro',
                   'Greeter':'iface', 'Person':'cls', 'Counter':'cls'}.items():
    assert by[name].get('t') == kind, (name, by[name].attrib)
def calls(name):
    return {c.get('n').split('/')[0] for c in by[name].iter('c')}
assert 'square' in calls('secret'), calls('secret')
assert 'secret' in calls('run'), calls('run')
assert 'square' in calls('render'), calls('render')
assert 'render' in calls('task'), calls('task')
assert 'square' not in calls('quoted-holder'), calls('quoted-holder')
print('PASS Clojure definitions, kinds, calls, quote/discard negatives, and four extensions')
PY

"$BIN" "$TMP/fix" >"$TMP/warm-a.xml"
"$BIN" "$TMP/fix" >"$TMP/warm-b.xml"
cmp "$TMP/cold.xml" "$TMP/warm-a.xml"
cmp "$TMP/warm-a.xml" "$TMP/warm-b.xml"
( cd "$TMP" && "$BIN" fix --no-cache >"$TMP/relative.xml" )
python3 - "$TMP/cold.xml" "$TMP/relative.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
def facts(p):
    root = ET.parse(p).getroot()
    root.attrib.pop('root', None)
    root.attrib.pop('est_tokens', None)
    return ET.tostring(root)
assert facts(sys.argv[1]) == facts(sys.argv[2])
PY
"$BIN" "$TMP/fix" --skipped --no-cache >"$TMP/skipped.xml"
rg -q '<lang n="clj" files="4"' "$TMP/skipped.xml"
! rg -q 'degraded-parse' "$TMP/skipped.xml"
"$BIN" "$TMP/fix" --deps --no-cache >"$TMP/deps.xml"
! rg -q 'dep_langs="[^"]*clj' "$TMP/deps.xml"
"$BIN" "$TMP/fix" --nonlocal-state --no-cache >"$TMP/nonlocal.xml"
rg -q 'unanalyzed_langs="clojure"' "$TMP/nonlocal.xml"
rg -q 'unanalyzed_files="4"' "$TMP/nonlocal.xml"
python3 - "$TMP/fix/core.clj" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
old = '(defn run [x] (secret x))'
assert old in s
p.write_text(s.replace(old, '(defn run [x] (square x))'))
PY
"$BIN" "$TMP/fix" --no-cache >"$TMP/mutated.xml"
python3 - "$TMP/mutated.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
rows = [s for s in ET.parse(sys.argv[1]).iter('s') if s.get('n').split('/')[0] == 'run']
assert len(rows) == 1
calls = {c.get('n').split('/')[0] for c in rows[0].iter('c')}
assert 'square' in calls and 'secret' not in calls, calls
PY
PATH="$(cd "$(dirname "$BIN")" && pwd):$PATH" "$BIN" "$TMP/fix" --doctor >"$TMP/doctor.xml"
rg -q '<c n="grammars" ok="1" loaded="26" expected="26"' "$TMP/doctor.xml"
echo 'clojurecheck: ALL PASS'
