#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
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
            'square', 'cube', 'doto', 'secret', 'unless', 'area', 'Greeter', 'Person', 'Counter', 'quoted', 'interop',
            'run', 'render', 'shared', 'task', 'quoted-holder', 'route', 'spaced', 'commented',
            'gap-call', 'comment-call', 'comment-holder', 'join', 'qualified-join', 'documented',
            'nested-quote', 'nested-discard', 'nested-comment', 'comment-not-head', 'comment-x',
            'comment-x-holder', 'before-discard', 'after-discard', 'quoted-macro', 'a', 'b',
            'syntax-quote-hole', 'live-hole-control', 'plain-call', 'meta-call', 'tag-call', 'stacked-meta-call',
            'quoted-meta', 'special-form-metadata', 'metadata-not-call', 'fn-literal', 'fn-literal-two-arg',
            'meta-fn-literal', 'quoted-fn-literal', 'special-form-literal', 'param-head-literal'}
assert names == expected, (names, expected)
by = {s.get('n').split('/')[0]: s for s in rows}
for name, kind in {'answer':'var', 'cached':'var', 'square':'fn', 'unless':'macro',
                   'Greeter':'iface', 'Person':'cls', 'Counter':'cls'}.items():
    assert by[name].get('t') == kind, (name, by[name].attrib)
# Review N1: a defmacro's signature includes its name. The grammar names every list child `value:`, and the C
# `#define` fallback once read that field as the macro body, so the span ended before the name and every
# defmacro row carried extent_suspect="name". Near misses: a defn, and a macro with a docstring and attr-map.
for name in ('unless', 'documented', 'square', 'secret'):
    assert by[name].get('extent_suspect') is None, (name, by[name].attrib)
assert by['documented'].get('t') == 'macro', by['documented'].attrib
print('PASS defmacro and defn rows carry no extent_suspect (signature includes the name)')
def calls(name):
    return {c.get('n').split('/')[0] for c in by[name].iter('c')}
assert 'square' in calls('secret'), calls('secret')
assert 'secret' in calls('run'), calls('run')
assert 'square' in calls('render'), calls('render')
assert 'render' in calls('task'), calls('task')
for name in ('spaced', 'commented', 'gap-call', 'comment-call'):
    assert 'square' in calls(name), (name, calls(name))
assert 'square' not in calls('quoted-holder'), calls('quoted-holder')
assert 'square' not in calls('comment-holder'), calls('comment-holder')
# Arm 1 (#548): metadata before a list head does not hide the call; a quoted metadata call stays
# inert, metadata on a non-call records nothing, and a metadata-prefixed special form stays excluded.
# `doto` has an in-tree def (core.clj), so a special form leaking past the gate would resolve and fail here;
# mutant check 2026-11-21 (lane land-715): with the specialForms test removed this arm goes red on ('doto').
for name in ('plain-call', 'meta-call', 'tag-call', 'stacked-meta-call'):
    assert calls(name) == {'square'}, (name, calls(name))
assert calls('quoted-meta') == set(), calls('quoted-meta')
assert calls('special-form-metadata') == set(), calls('special-form-metadata')
assert calls('metadata-not-call') == set(), calls('metadata-not-call')
print('PASS metadata-prefixed calls extracted; quoted metadata and special forms stay inert')
# Arm 2 (#548): an anonymous function literal whose head is a symbol records that call (`#(cube %)` is
# `(fn* [x] (cube x))`), also under metadata. Near misses: a call nested in the literal already worked and
# stays as it was; a quoted literal stays inert; a special-form head (`if`, and `doto`, which has an in-tree
# def, so a leak past the special-form gate would resolve and fail here) records nothing; a parameter head
# (`#(%)`, `#(%1 %2)`) names no definition and is never guessed into one.
for name in ('fn-literal', 'meta-fn-literal'):
    assert calls(name) == {'cube'}, (name, calls(name))
assert calls('fn-literal-two-arg') == {'square'}, calls('fn-literal-two-arg')
assert calls('quoted-fn-literal') == set(), calls('quoted-fn-literal')
assert calls('special-form-literal') == set(), calls('special-form-literal')
assert calls('param-head-literal') == set(), calls('param-head-literal')
print('PASS fn-literal heads extracted; quoted literals, special forms and parameter heads stay out')
# Slice 8a: nested inert forms drop their calls; a live sibling proves the holder is still captured.
for name in ('nested-quote', 'nested-discard', 'nested-comment', 'quoted-macro'):
    assert calls(name) == {'secret'}, (name, calls(name))
assert by['quoted-macro'].get('t') == 'macro', by['quoted-macro'].attrib
print('PASS nested quote/discard/comment and quote inside defmacro keep only the live sibling')
# Only the exact list head comment is inert: a later symbol and comment-x leave square live.
assert calls('comment-not-head') == {'square'}, calls('comment-not-head')
assert calls('comment-x-holder') == {'comment-x', 'square'}, calls('comment-x-holder')
for name in ('before-discard', 'after-discard'):
    assert calls(name) == {'square'}, (name, calls(name))
assert 'discarded-value' not in names, names
print('PASS comment head near misses and discard of one def preserve neighbouring captures')
# KNOWN GAP (#449 follow-up: Clojure syntax-quote live holes, separate from slice 8a).
# In `(a ~(b)), b should be a call, but today's filter makes the whole syntax-quote inert.
# A future unquoting_lit / unquote_splicing_lit Live arm flips this assertion to {'b'};
# retain a as inert, and retain this fixture and arm when the gap moves. This migration does not fix it.
assert calls('live-hole-control') == {'b'}, calls('live-hole-control')
assert calls('syntax-quote-hole') == set(), ('known gap moved: flip this arm to {"b"}', calls('syntax-quote-hole'))
print('PASS known syntax-quote/unquote gap: b is currently inert; future live-hole follow-up flips this arm')
# KNOWN GAP (shared resolver, not Clojure): a qualifier that names no definition still reaches the
# bare-name ladder, so str/join binds the in-tree join. The maintainers' shared refusal flips this arm.
# When it goes red, assert 'join' not in these calls; retain the fixture and the arm.
assert 'join' in calls('qualified-join'), ('known gap moved: flip this arm to "not in"', calls('qualified-join'))
print('PASS known shared resolver gap: str/join currently binds the in-tree join')
print('PASS Clojure definitions, kinds, calls, quote/discard negatives, and four extensions')
PY

"$BIN" "$TMP/fix" --callers=square --no-cache >"$TMP/callers-square.xml"
python3 - "$TMP/callers-square.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
names = {s.get('n').split('/')[0] for s in ET.parse(sys.argv[1]).iter('s')}
for name in ('plain-call', 'meta-call', 'tag-call', 'stacked-meta-call'):
    assert name in names, (name, names)
for name in ('quoted-meta', 'special-form-metadata'):
    assert name not in names, (name, names)
print('PASS --callers=square names the metadata-prefixed callers and not the inert forms')
PY

"$BIN" "$TMP/fix" --callers=cube --no-cache >"$TMP/callers-cube.xml"
python3 - "$TMP/callers-cube.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
names = {s.get('n').split('/')[0] for s in ET.parse(sys.argv[1]).iter('s')}
for name in ('fn-literal', 'meta-fn-literal'):
    assert name in names, (name, names)
for name in ('quoted-meta', 'quoted-fn-literal', 'param-head-literal'):
    assert name not in names, (name, names)
print('PASS --callers=cube names the fn-literal callers and not the quoted or parameter-head forms')
PY

"$BIN" "$TMP/fix" --metrics --no-cache >"$TMP/metrics.xml"
python3 - "$TMP/metrics.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
rows = [s for s in ET.parse(sys.argv[1]).iter('s') if s.get('n') == 'route']
assert len(rows) == 1, rows
assert rows[0].get('params') == '1', rows[0].attrib
PY

mkdir "$TMP/rules"
printf '%s\n' '- id: clojure-symbol' '  language: clj' '  severity: warn' \
    '  message: symbol found' '  query: |' '    (sym_lit name: (sym_name) @hit)' >"$TMP/rules/clj.yml"
"$BIN" "$TMP/fix" --lint-rules="$TMP/rules" --no-cache >"$TMP/lint.xml"
rg -q 'rule="clojure-symbol"' "$TMP/lint.xml"

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
if rg -q 'degraded-parse' "$TMP/skipped.xml"; then
    echo 'Unexpected degraded Clojure parse' >&2
    exit 1
fi
"$BIN" "$TMP/fix" --deps --no-cache >"$TMP/deps.xml"
if rg -q 'dep_langs="[^"]*clj' "$TMP/deps.xml"; then
    echo 'Unexpected Clojure dependency capability' >&2
    exit 1
fi
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
rg -q '<c n="grammars" ok="1" loaded="27" expected="27"' "$TMP/doctor.xml"
echo 'clojurecheck: ALL PASS'
