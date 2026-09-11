#!/usr/bin/env bash
# jsimportfacts.sh — the DISCLOSURE half of ES named-import resolution, and the export FORMS the
# binding table has to see before it may refuse anything.
#
# test/lib/jsimportalias.sh next door asserts that a named import lands on the right definition. This
# file asserts the three things that verb cannot see, each of which is a way for the same feature to be
# silently WRONG rather than merely incomplete:
#
#   (A) An import whose MODULE is outside the indexed tree (`node:child_process`, a bare package) is a
#       refusal the tool can prove — it belongs in the header's `external=` gauge, whose legend already
#       names "external-import" as one of its three sources. Counting it into `unresolved=` instead
#       claims the opposite: unresolved= means "an in-repo definition of this name exists and we could
#       not use it" (src/graph.h, Graph::unresolvedOut). One number over-states a MISS; the other
#       states a refusal. A JS corpus is mostly node/npm imports, so this is not a corner.
#   (B/C/D) The export FORMS. A binding table that records only `export function f(){}` sees no
#       `export { f }`, no `export { f as g }`, and no `export { f } from './m.js'` — and then refuses
#       the very call sites the plain name ladder used to resolve correctly. A refusal that DELETES a
#       previously-correct edge is strictly worse than the fallback it replaced, so the rule is: refuse
#       only on positive contrary evidence, otherwise degrade to the ladder.
#   (E/F) The provenance. An import-resolved edge is NOT "uniquely-resolved-name-based", which is what
#       an ABSENT prov= means in the map legend; and a refused external import must leave a census row,
#       or the veto's own precision cannot be measured. Both are the A4-R5 FFI path's rules, applied to
#       the mechanism that now sits beside it.
#
# Every arm carries a MUTATION CONTROL: a source edit that must flip the measured quantity. An arm that
# cannot be made to fail measured nothing. Run against the pre-fix binary, (A) (B) (D) (E) and (F) all
# report FAIL — that liveness is the point of the file.
set -eu
ROOT="$( cd "$( dirname "$0" )/../.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
python3 - "$BIN" <<'PY'
import pathlib, re, subprocess, sys, tempfile, xml.etree.ElementTree as ET

binary = str(pathlib.Path(sys.argv[1]).resolve())
failures = []

def run(root, *args):
    result = subprocess.run([binary, str(root), '--no-cache', *args], capture_output=True, text=True, check=True)
    return result.stdout

def edgesOf(out, symbol):
    """(callee, prov) for one symbol's <c> children, off any map text."""
    tree = ET.fromstring(re.sub(r'<!--.*?-->', '', out, flags=re.S))
    for s in tree.iter('s'):
        if s.attrib.get('n') == symbol:
            return sorted((c.attrib.get('n'), c.attrib.get('prov', '')) for c in s.findall('c'))
    return []

def runRoots(roots, *args):
    result = subprocess.run([binary, *[str(x) for x in roots], '--no-cache', *args], capture_output=True, text=True, check=True)
    return result.stdout

def stats(root, *args):
    """the header's own gauge comment, as a dict — the numbers the map publishes about itself."""
    out = run(root, *args)
    hit = re.search(r'<!-- files=([^>]*?) -->', out)
    if hit is None:
        raise AssertionError('no stats comment in the map')
    fields = {}
    for token in ('files=' + hit.group(1)).split():
        if '=' in token:
            key, _, value = token.partition('=')
            fields[key] = value
    return fields

def callees(root, symbol):
    """(callee name, callee file) pairs — the identity the map's <c n=""> child cannot carry."""
    out = run(root, '--callees=' + symbol)
    tree = ET.fromstring(out)
    if int(tree.attrib['defs']) != 1:
        raise AssertionError('missing/duplicate probe {}: {}'.format(symbol, tree.attrib))
    return sorted((s.attrib['n'], s.attrib['p'].split(':')[0]) for s in tree.findall('s'))

def provOf(root, symbol, callee):
    """the prov= the map stamps on ONE <c> child of ONE <s> — '' when the attribute is absent."""
    out = run(root)
    tree = ET.fromstring(re.sub(r'<!--.*?-->', '', out, flags=re.S))
    for s in tree.iter('s'):
        if s.attrib.get('n') != symbol:
            continue
        for c in s.findall('c'):
            if c.attrib.get('n') == callee:
                return c.attrib.get('prov', '')
    return None

def census(root):
    """the --pin-census C rows as (mech, callee, targets) triples."""
    with tempfile.NamedTemporaryFile(prefix='rw-jsfacts-census-', suffix='.tsv', delete=False) as handle:
        path = handle.name
    run(root, '--pin-census=' + path)
    rows = []
    for line in pathlib.Path(path).read_text().splitlines():
        if not line.startswith('C\t'):
            continue
        parts = line.split('\t')   # C mech pre post flags caller_id callee targets line
        if len(parts) >= 8:
            rows.append((parts[1], parts[6], parts[7]))
    pathlib.Path(path).unlink()
    return rows

def check(label, got, want):
    if got != want:
        failures.append('{}: expected {!r}, got {!r}'.format(label, want, got))
        return False
    return True

def control(label, got, want):
    """a MUTATION CONTROL: the arm above measured nothing unless this flipped value shows up."""
    if got != want:
        failures.append('{} [MUTATION CONTROL INERT]: expected {!r} after the edit, got {!r}'.format(label, want, got))

with tempfile.TemporaryDirectory(prefix='rw-jsimport-facts-') as directory:
    base = pathlib.Path(directory)

    # ── (A) an out-of-tree module is a REFUSAL (external=), never a MISS (unresolved=) ───────────────
    # Three imports: a node: builtin, a bare npm package, and one in-tree relative module. Only the
    # third can produce an edge; the first two are refusals the module specifier PROVES (a bare
    # specifier never names a relative file, and neither names anything in this tree).
    ext = base / 'ext'
    ext.mkdir()
    (ext / 'local.js').write_text('export function helper() { return 1; }\n')
    (ext / 'consumer.js').write_text(
        "import { execFileSync } from 'node:child_process';\n"
        "import { pack } from 'some-npm-package';\n"
        "import { helper } from './local.js';\n"
        'export function run() { return execFileSync("ls"); }\n'
        'export function bundle() { return pack(1); }\n'
        'export function use() { return helper(); }\n')
    s = stats(ext)
    check('(A) out-of-tree imports counted as external=', s.get('external'), '2')
    check('(A) out-of-tree imports NOT counted as unresolved=', s.get('unresolved'), '0')
    check('(A) the in-tree import still resolves', callees(ext, 'use'), [('helper', 'local.js')])
    # MUTATION CONTROL: give the npm specifier an in-tree relative spelling. One refusal must vanish.
    src = (ext / 'consumer.js').read_text()
    (ext / 'consumer.js').write_text(src.replace("{ pack } from 'some-npm-package'", "{ helper as pack } from './local.js'"))
    control('(A) external= tracks the module specifier', stats(ext).get('external'), '1')
    (ext / 'consumer.js').write_text(src)

    # ── (B) `export { x }` — a clause export, resolved against a same-named DECOY ────────────────────
    # Both modules define `pick` at module scope, so the plain name ladder is ambiguous by construction
    # and any correct answer here came from the import binding, not from a lucky unique name.
    clause = base / 'clause'
    clause.mkdir()
    (clause / 'owner.js').write_text('function pick() { return 1; }\nexport { pick };\n')
    (clause / 'decoy.js').write_text('function pick() { return 2; }\nexport { pick };\n')
    (clause / 'consumer.js').write_text(
        "import { pick } from './owner.js';\n"
        'export function callPick() { return pick(); }\n')
    check('(B) export { x } resolves to the imported module', callees(clause, 'callPick'), [('pick', 'owner.js')])
    # MUTATION CONTROL: repoint the import; the edge must FOLLOW the specifier, not sit on a name.
    (clause / 'consumer.js').write_text(
        "import { pick } from './decoy.js';\n"
        'export function callPick() { return pick(); }\n')
    control('(B) the clause-export edge follows the module', callees(clause, 'callPick'), [('pick', 'decoy.js')])

    # ── (C) `export { x as y }` — the exported NAME and the local declaration differ ─────────────────
    rename = base / 'rename'
    rename.mkdir()
    (rename / 'ren.js').write_text('function inner() { return 3; }\nexport { inner as outer };\n')
    (rename / 'consumer.js').write_text(
        "import { outer } from './ren.js';\n"
        'export function callOuter() { return outer(); }\n')
    check('(C) export { x as y } resolves to the LOCAL declaration', callees(rename, 'callOuter'), [('inner', 'ren.js')])
    # MUTATION CONTROL: export it under a different name. The module no longer exports `outer`, no
    # in-tree definition is named `outer`, and the ladder has nothing to fall back to → no edge.
    (rename / 'ren.js').write_text('function inner() { return 3; }\nexport { inner as elsewhere };\n')
    control('(C) the rename edge tracks the export name', callees(rename, 'callOuter'), [])

    # ── (D) a barrel re-export must DEGRADE to the ladder, never refuse ──────────────────────────────
    # `export { b } from './b.js'` is a name this table cannot pin: the definition is in a third file.
    # The pre-import ladder resolved this call correctly by name, so a refusal here DELETES a correct
    # edge. Absence of evidence is not evidence of absence — fall back.
    barrel = base / 'barrel'
    barrel.mkdir()
    (barrel / 'b.js').write_text('export function bfn() { return 2; }\n')
    (barrel / 'barrel.js').write_text("export { bfn } from './b.js';\n")
    (barrel / 'consumer.js').write_text(
        "import { bfn } from './barrel.js';\n"
        'export function callBarrel() { return bfn(); }\n')
    check('(D) a barrel re-export keeps the ladder edge', callees(barrel, 'callBarrel'), [('bfn', 'b.js')])
    # MUTATION CONTROL: rename the import locally. The local spelling is now private to this file, so a
    # same-name ladder hit would be a coincidence, not a resolution — the fallback must NOT fire.
    (barrel / 'consumer.js').write_text(
        "import { bfn as alias } from './barrel.js';\n"
        'export function callBarrel() { return alias(); }\n')
    control('(D) a RENAMED unlisted import refuses instead of guessing', callees(barrel, 'callBarrel'), [])

    # ── (E) provenance: an import-resolved edge is not "uniquely-resolved-name-based" ────────────────
    # The map legend defines an ABSENT prov= as exactly that. This edge came from a binding table, so
    # it must say so — the same rule the FFI path follows with prov="binding".
    prov = base / 'prov'
    prov.mkdir()
    (prov / 'owner.js').write_text('function pick() { return 1; }\nexport { pick };\n')
    (prov / 'decoy.js').write_text('function pick() { return 2; }\nexport { pick };\n')
    (prov / 'consumer.js').write_text(
        "import { pick } from './owner.js';\n"
        'export function callPick() { return pick(); }\n')
    check('(E) an import-resolved edge carries prov="import"', provOf(prov, 'callPick', 'pick'), 'import')
    legend = run(prov).split('-->')[0]
    if 'prov=' not in legend or 'import(' not in legend:
        failures.append('(E) the legend does not define the prov= value the map just emitted: ' + legend[-220:])
    mechs = [row for row in census(prov) if row[1] == 'pick']
    check('(E) the census names the deciding mechanism', [row[0] for row in mechs], ['import'])
    # MUTATION CONTROL: send the module out of the tree. Nothing is pinned, so nothing is stamped.
    (prov / 'consumer.js').write_text(
        "import { pick } from 'some-npm-package';\n"
        'export function callPick() { return pick(); }\n')
    control('(E) prov="import" tracks the resolution', provOf(prov, 'callPick', 'pick'), None)

    # ── (F) a refused external import leaves a census row ────────────────────────────────────────────
    # The veto's whole contract (src/pincensus.h, PinMech::External) is "no edge, one header count, one
    # census row with no target" — the row is how the refusal's own precision gets scored later. A
    # `continue` that skips the census makes the refusal unauditable.
    rows = census(ext)
    externals = sorted(row[1] for row in rows if row[0] == 'external')
    check('(F) each external-import refusal leaves a census row', externals, ['execFileSync', 'pack'])
    check('(F) a refusal row carries no target', [row[2] for row in rows if row[0] == 'external'], ['', ''])
    # MUTATION CONTROL: bring one module in-tree; its refusal row must disappear.
    (ext / 'consumer.js').write_text(src.replace("{ pack } from 'some-npm-package'", "{ helper as pack } from './local.js'"))
    control('(F) the refusal rows track the module specifiers',
            sorted(row[1] for row in census(ext) if row[0] == 'external'), ['execFileSync'])

    # ── (G) a TS file importing a .js module: the MODULE SYSTEM decides, not the language tag ───────
    # Every other admission site in the resolve loop filters candidates through langCompatible, which
    # calls TypeScript and JavaScript INCOMPATIBLE. The import path deliberately does not: `import { f }
    # from './lib.js'` inside a .ts file is a real, spec-defined resolution, and the path resolver already
    # probes the .ts/.tsx source alternatives for exactly this reason. The exemption is narrow — it applies
    # only where a module specifier named the file — and it is asserted here so it cannot be dropped or
    # widened without a gate saying so.
    tsjs = base / 'tsjs'
    tsjs.mkdir()
    (tsjs / 'lib.js').write_text('export function jsHelper() { return 1; }\n')
    (tsjs / 'app.ts').write_text(
        "import { jsHelper } from './lib.js';\n"
        'export function useJs() { return jsHelper(); }\n')
    check('(G) a TS->JS import edge survives the lang filter', callees(tsjs, 'useJs'), [('jsHelper', 'lib.js')])
    # MUTATION CONTROL: the module stops exporting that name. Nothing in the tree is called jsHelper, so
    # the ladder this degrades to has nothing to offer either.
    (tsjs / 'lib.js').write_text('export function otherHelper() { return 1; }\n')
    control('(G) the TS->JS edge is the import, not the language pair', callees(tsjs, 'useJs'), [])

    # ── (H) two roots: a PATH-RESOLVED import may cross, a bare name still may not ───────────────────
    # §3.1's cross-root rule is "evidence only, never a bare-name guess". A module specifier that resolves
    # to an indexed file IS that evidence, so the edge is admitted and — because it came from the binding
    # table rather than the name ladder — it says prov="import". Asserted because the import path does not
    # re-apply the sameRoot() filter its neighbours do, and a silent cross-root edge is precisely the thing
    # §3.1 exists to keep out.
    cli, svc = base / 'cli', base / 'svc'
    cli.mkdir(); svc.mkdir()
    (svc / 'api.ts').write_text('export function svcApi() { return 1; }\n')
    (cli / 'app.ts').write_text(
        "import { svcApi } from '../svc/api.js';\n"
        'export function runApp() { return svcApi(); }\n')
    check('(H) a path-resolved import crosses roots, and says so',
          edgesOf(runRoots([cli, svc], '--top-k=400'), 'runApp'), [('svcApi', 'import')])
    # MUTATION CONTROL: point the specifier at a same-root file that does not exist. The name is then
    # unlisted, the ladder takes over — and the ladder does NOT cross roots on a name alone.
    (cli / 'app.ts').write_text(
        "import { svcApi } from './missing.js';\n"
        'export function runApp() { return svcApi(); }\n')
    control('(H) a bare NAME still does not cross roots',
            edgesOf(runRoots([cli, svc], '--top-k=400'), 'runApp'), [])

if failures:
    print('\n'.join('  FAIL  ' + failure for failure in failures))
    sys.exit(1)
print('  PASS  ES import disclosure: external= vs unresolved=, clause/rename/barrel exports, prov= and the census')
PY
