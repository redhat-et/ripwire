#!/usr/bin/env bash
# GDScript grammar, definition kinds, call heads, the decoy, and the two DISCLOSED grammar blind
# spots. Written RED against a binary without the GDScript change (which indexes no .gd at all and
# so extracts zero symbols from this fixture) before the change landed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir "$TMP/cache"
export XDG_CACHE_HOME="$TMP/cache"
cp -R "$ROOT/test/gdscriptfix" "$TMP/fix"
"$BIN" "$TMP/fix" --no-cache > "$TMP/map.xml"

python3 - "$TMP/map.xml" <<'PY'
import sys, collections, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
byfile = {f.get('p'): {s.get('n'): s for s in f.iter('s')} for f in root.iter('f')}
allsyms = collections.defaultdict(list)
for p, d in byfile.items():
    for n, s in d.items():
        allsyms[n].append((p, s))

hero = byfile['hero.gd']
# --- kinds: the whole definition surface queries/gdscript/tags.scm claims ---
assert hero['Hero'].get('t') == 'cls', hero['Hero'].attrib          # class_name -> the file's global class
assert hero['Loadout'].get('t') == 'cls'                            # inner class
assert hero['describe'].get('t') == 'method', hero['describe'].attrib  # func inside class_body
for fn in ('take_damage', '_apply', 'notify_died'):
    assert hero[fn].get('t') == 'fn', (fn, hero[fn].attrib)         # file-scope func
assert hero['State'].get('t') == 'struct', hero['State'].attrib     # enum -> definition.type, as Java/C#/TS
for v in ('MAX_HP', 'lowercase_const', 'IDLE', 'RUN', 'FALL',
          'hp', 'sprite', 'velocity', 'spawned', 'weapon_id'):
    assert hero[v].get('t') == 'var', (v, hero[v].attrib)
# `const lowercase_const` proves GDScript is NOT on the SCREAMING_SNAKE constant gate: the `const`
# keyword is the evidence, not the case (constCaptureNeedsScreamingGate returns false for GDScript).
# A signal is a declared member with no SymKind of its own — DISCLOSED as t="var", not dropped.
assert hero['died'].get('t') == 'var', hero['died'].attrib
# @export/@onready parse as plain variable_statement + annotations in Godot 4 — one pattern covers all
# three spellings, so the annotated vars above must be present exactly like the bare one.
print('  PASS GDScript definition kinds (class/inner class/method/fn/enum/const/var/signal)')

# --- case: `hero` the var must not collapse into `Hero` the class ---
assert hero['hero'].get('t') == 'var', hero['hero'].attrib
assert hero['Hero'].get('t') == 'cls'
print('  PASS case-distinct symbols (hero var vs Hero class) stay separate')

# --- decoy: same names in two files must stay two defs, one per file ---
for dup in ('take_damage', '_apply'):
    files = sorted(p for p, _ in allsyms[dup])
    assert files == ['hero.gd', 'villain.gd'], (dup, files)
assert sorted(p for p, _ in allsyms['only_here']) == ['villain.gd']
print('  PASS decoy: duplicated names keep one def per file')

# --- call edges ---
def calls(p, n): return {c.get('n') for c in byfile[p][n].iter('c')}
assert {'_apply', 'notify_died'} <= calls('hero.gd', 'take_damage'), calls('hero.gd', 'take_damage')
assert '_apply' in calls('villain.gd', 'take_damage')
# `sprite.set_modulate(...)` names no in-repo def — it must NOT mint an edge.
assert 'set_modulate' not in calls('hero.gd', 'take_damage'), 'external Godot API call became an edge'
print('  PASS local + attribute call edges, and no edge for an external Godot API call')

# --- DISCLOSED blind spots (queries/gdscript/tags.scm; STEP 0 measured 98.88% over 2938 files) ---
# blindspots.gd holds BOTH upstream grammar gaps: `$%SceneUnique` (the `%` scene-unique-name inside a
# `$` path — 70% of all real-world parse failures measured) and `remote = {}` (a Godot 3 RPC keyword
# still reserved by the grammar, unusable in statement position). Both produce ERROR nodes. The
# CONTRACT asserted here is that tree-sitter's recovery is LOCAL: every definition and every call
# edge in the file survives, and only the erroring sub-expression is lost. If a future grammar bump
# fixes these upstream, this arm still passes — it asserts survival, not failure.
b = byfile['blindspots.gd']
assert b['Blind'].get('t') == 'cls'
assert b['uniq'].get('t') == 'var', 'a var whose initialiser holds the $% blind spot was lost'
for fn in ('keyword_reassign', 'survives_after_blind_spot', 'helper_fn'):
    assert b[fn].get('t') == 'fn', (fn, b[fn].attrib)
assert 'helper_fn' in calls('blindspots.gd', 'keyword_reassign'), 'call edge lost after the keyword blind spot'
print('  PASS disclosed blind spots degrade LOCALLY: defs and edges survive')
PY

# --- determinism + cache round trip (a contract, not a nicety) ---
for n in a b c; do "$BIN" "$TMP/fix" > "$TMP/$n.xml"; done
cmp "$TMP/map.xml" "$TMP/a.xml"
cmp "$TMP/a.xml" "$TMP/b.xml"
cmp "$TMP/b.xml" "$TMP/c.xml"
echo '  PASS cold/warm determinism and XML'

# --- a relative and an absolute crawl root resolve identically ---
( cd "$TMP" && "$BIN" ./fix --no-cache > "$TMP/rel.xml" )
"$BIN" "$TMP/fix" --no-cache > "$TMP/abs.xml"
python3 - "$TMP/rel.xml" "$TMP/abs.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
def shape(p):
    # Compare by BASENAME: a relative crawl root keeps its own root segment in p= (./fix -> "fix/x.gd")
    # while an absolute one does not ("x.gd"). That is pre-existing ripwire behaviour shared by every
    # language — verified against test/elixirfix on the same binary — not a GDScript property, so the
    # claim under test here is that the SYMBOL SET is root-spelling independent.
    r = ET.parse(p).getroot()
    return sorted((f.get('p').rsplit('/', 1)[-1], s.get('n'), s.get('t'))
                  for f in r.iter('f') for s in f.iter('s'))
assert shape(sys.argv[1]) == shape(sys.argv[2]), 'relative and absolute crawl roots disagree'
print('  PASS relative and absolute crawl roots agree')
PY

# --- langOfPath knows .gd (lintrules.h kExt), not just the crawl table ---
# REGRESSION ARM. kExt is a fixed-size std::array: bumping its bound without adding the row
# leaves the tail zero-filled to { "", Lang::Cpp } and compiles clean, so langOfPath("x.gd")
# silently returns Unknown while ingest_crawl.h still indexes the file. That shipped once here
# and the whole suite stayed green — a rule row's applicable="0" beside its own count>0 is the
# cheapest observable that contradicts it (the shape test/dartcheck.sh uses for Dart).
mkdir "$TMP/lintgd"
cat > "$TMP/lintgd/n.gd" <<'GD'
class_name Widget

func mixed_caseName() -> int:
	return 1
GD
"$BIN" "$TMP/lintgd" --lint --no-cache > "$TMP/lintgd.xml"
python3 - "$TMP/lintgd.xml" <<'PYLINT'
import sys, xml.etree.ElementTree as ET
rules = {r.get('name'): r for r in ET.parse(sys.argv[1]).iter('rule')}
fired = [n for n, r in rules.items() if n.startswith('naming-') and int(r.get('count', '0')) > 0]
assert fired, ('no naming rule fired on the GDScript fixture — the arm cannot reach a verdict', sorted(rules))
for n in fired:
    assert rules[n].get('applicable') != '0', (
        'rule %s reports count=%s yet applicable="0" — langOfPath does not know .gd is GDScript '
        '(lintrules.h kExt row missing?)' % (n, rules[n].get('count')))
print('  PASS langOfPath resolves .gd (the lint catalog knows a GDScript corpus)')
PYLINT

# --- each enum member owns its own span, not the enclosing enumerator_list ---
mkdir "$TMP/enumspan"
{ echo "class_name Big"; echo "extends Node"; echo; echo "enum State {"
  i=1; while [ $i -le 40 ]; do echo "	MEMBER_$i,"; i=$((i+1)); done; echo "}"; echo
  i=1; while [ $i -le 60 ]; do echo "func pad_$i() -> void:"; echo "	pass"; echo; i=$((i+1)); done; } > "$TMP/enumspan/b.gd"
"$BIN" "$TMP/enumspan" --no-cache --expand=b.gd:MEMBER_2  > "$TMP/em2.xml"
"$BIN" "$TMP/enumspan" --no-cache --expand=b.gd:MEMBER_39 > "$TMP/em39.xml"
python3 - "$TMP/em2.xml" "$TMP/em39.xml" <<'PYENUM'
import sys, re
def body(p):
    t = open(p, encoding='utf-8').read()
    # Strip the XML comment legend FIRST: it contains its own CDATA-shaped prose, so a naive
    # first-match regex reads the legend instead of the body and every assertion below is then
    # testing the legend text. (Observed while writing this arm.)
    t = re.sub(r'<!--.*?-->', '', t, flags=re.S)
    m = re.search(r'<!\[CDATA\[(.*?)\]\]>', t, re.S)
    return m.group(1) if m else ''
b2, b39 = body(sys.argv[1]), body(sys.argv[2])
assert b2 and b39, 'expand produced no body — the arm is inert'
# Capturing the enclosing enumerator_list gives every member the SAME span, so both expands
# return the whole 40-member list. Each enumerator must own its own.
assert b2 != b39, 'MEMBER_2 and MEMBER_39 expand to an identical body — the enum span is shared'
assert 'MEMBER_39' not in b2, 'MEMBER_2 expanded to a body containing MEMBER_39 — span covers the whole list'
print('  PASS each enum member owns its own definition span')
PYENUM

# --- the extension is really registered, not just parsed by accident ---
"$BIN" "$TMP/fix" --skipped > "$TMP/skipped.xml"
if grep -q 'x=".gd"' "$TMP/skipped.xml"; then
    echo '  FAIL .gd still reported as skipped/unsupported-ext'; exit 1
fi
echo '  PASS .gd is indexed, not skipped as unsupported-ext'
