#!/usr/bin/env bash
# Default bindings must follow the exported function, never a same-spelled decoy.
set -eu
ROOT="$( cd "$( dirname "$0" )/../.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
python3 - "$BIN" <<'PY'
import pathlib, subprocess, sys, tempfile, xml.etree.ElementTree as ET

binary = str(pathlib.Path(sys.argv[1]).resolve())
failures = []
with tempfile.TemporaryDirectory(prefix='rw-default-import-') as directory:
    for ext in ('ts', 'tsx', 'mts', 'cts', 'js', 'jsx', 'mjs', 'cjs'):
        root = pathlib.Path(directory) / ext
        root.mkdir()
        spec = {'ts': 'js', 'tsx': 'js', 'mts': 'mjs', 'cts': 'cjs'}.get(ext, ext)
        owner = root / ('owner.' + ext)
        owner.write_text('export default function actual() { return 1; }\n')
        (root / ('decoy.' + ext)).write_text('export function save() { return 2; }\n')
        consumer = root / ('consumer.' + ext)
        consumer.write_text(f'''import save from './owner.{spec}';
export function caller() {{ return save(); }}
export function construct() {{ return new save(); }}
export function shadow(save) {{ return save(); }}
export function closure(save) {{ return () => save(); }}
export function nested() {{ {{ let save; save(); }} return save(); }}
''')

        def run(symbol, cache='--no-cache'):
            result = subprocess.run([binary, str(root), '--callees=' + symbol, cache],
                                    capture_output=True, text=True, check=True)
            tree = ET.fromstring(result.stdout)
            assert int(tree.attrib['defs']) == 1, (symbol, tree.attrib)
            return result.stdout, [(s.attrib['n'], s.attrib['p'].split(':')[0]) for s in tree.findall('s')]

        def check(label, symbol, expected):
            got = run(symbol)[1]
            if got != expected:
                failures.append(f'{ext}/{label}: expected {expected}, got {got}')

        expected = [('actual', 'owner.' + ext)]
        check('declaration', 'caller', expected)
        check('parameter shadow', 'shadow', [])
        check('closure shadow', 'closure', [])
        check('block shadow ends', 'nested', expected)
        for source in ('function actual() { return 1; }\nexport default actual;\n',
                       'const actual = () => 1;\nexport default actual;\n',
                       'function actual() { return 1; }\nexport { actual as default };\n'):
            owner.write_text(source)
            check('local export ' + source.splitlines()[-1], 'caller', expected)
        previous = owner.read_text()
        owner.write_text('export default class actual {}\n')
        check('named default class', 'construct', expected)
        owner.write_text(previous)
        cache = '--cache=' + str(root / 'facts.cache')
        cold = run('caller')[0]
        first = run('caller', cache)[0]
        assert (root / 'facts.cache').is_file(), 'warm arm requires a real cache'
        warm = run('caller', cache)[0]
        if cold != first or first != warm:
            failures.append(f'{ext}: cold/warm mismatch')
        # Real source mutations must remove the edge, including through a previously populated cache.
        for source in ('export default 1;\n', 'export default function() { return 1; }\n',
                       'export default function actual() {}\nexport default 1;\n',
                       'function actual() {}\nexport default actual;\nexport default actual;\n',
                       'function actual() {}\nconst actual = 1;\nexport default actual;\n',
                       'function actual() {}\nconst actual = 1;\nexport { actual as default };\n',
                       'function actual() {}\nfunction actual() {}\nexport default actual;\n'):
            before = owner.read_text()
            assert before != source
            owner.write_text(source)
            assert owner.read_text() == source
            check('unsupported/ambiguous export', 'caller', [])
            if run('caller', cache)[1]:
                failures.append(f'{ext}: warm cache kept a removed/ambiguous default target')
        owner.write_text('export default function actual() { return 1; }\n')
        if ext in ('ts', 'tsx', 'mts', 'cts'):
            runtime = root / ('owner.' + spec)
            runtime.write_text('export default function other() {}\n')
            check('ambiguous module', 'caller', [])
            runtime.unlink()
            consumer.write_text(f"import type save from './owner.{spec}';\nexport function caller() {{ return save(); }}\n")
            check('type-only default', 'caller', [])
        consumer.write_text("import save from 'missing-package';\nexport function caller() { return save(); }\n")
        check('external default', 'caller', [])
if failures:
    print('\n'.join('  FAIL  ' + failure for failure in failures))
    sys.exit(1)
print('  PASS  default imports: exported identity, decoys, shadows, ambiguity and cold/warm caches')
PY
