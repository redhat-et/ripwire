#!/usr/bin/env bash
# Named import resolution: real targets, false-edge decoys, and scoped shadows.
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
python3 - "$BIN" <<'PY'
import pathlib, subprocess, sys, tempfile, xml.etree.ElementTree as ET
binary = str(pathlib.Path(sys.argv[1]).resolve())
failures = []
with tempfile.TemporaryDirectory(prefix='rw-import-alias-') as directory:
    for ext in ('ts', 'tsx', 'mts', 'cts', 'js', 'jsx', 'mjs', 'cjs'):
        root = pathlib.Path(directory) / ext
        root.mkdir()
        spec = {'ts': 'js', 'tsx': 'js', 'mts': 'mjs', 'cts': 'cjs'}.get(ext, ext)
        (root / ('owner.' + ext)).write_text('export function target() { return 1; }\nexport const arrow = () => 2;\nfunction privateFn() { return 3; }\n')
        (root / ('decoy.' + ext)).write_text('export function alias() { return 9; }\nexport function target() { return 8; }\nexport function missing() { return 7; }\n')
        consumer = root / ('consumer.' + ext)
        consumer.write_text(f'''import {{ target as alias, arrow, privateFn as hidden }} from './owner.{spec}';
import {{ missing as external }} from 'absent-package';
import {{ missing as absent }} from './absent.{spec}';
export function caller() {{ return alias(); }}
export function direct() {{ return arrow(); }}
export function param(alias) {{ return alias(); }}
export function local() {{ const alias = () => 4; return alias(); }}
export function nested() {{ {{ let alias; alias(); }} return alias(); }}
export function closure(alias) {{ return () => alias(); }}
export function destructured({{ fn: alias }}) {{ return alias(); }}
export function loop(callbacks) {{ for (const alias of callbacks) alias(); }}
export const selfNamed = function alias() {{ return alias(); }};
export function classNamed() {{ const C = class alias {{ method() {{ return new alias(); }} }}; return C; }}
export function defaultParam(cb = () => alias()) {{ var alias; return cb(); }}
export function missingCaller() {{ external(); absent(); hidden(); }}
''')
        def run(symbol, cache='--no-cache'):
            result = subprocess.run([binary, str(root), '--callees=' + symbol, cache], capture_output=True, text=True, check=True)
            return result.stdout, ET.fromstring(result.stdout)
        def edges(symbol):
            _, tree = run(symbol)
            if int(tree.attrib['defs']) != 1:
                raise AssertionError(f'{ext}: missing/duplicate probe {symbol}: {tree.attrib}')
            return [(s.attrib['n'], s.attrib['p'].split(':')[0]) for s in tree.findall('s')]
        for symbol, expected in [('caller', [('target', 'owner.' + ext)]), ('direct', [('arrow', 'owner.' + ext)]),
                                 ('param', []), ('destructured', []), ('missingCaller', [])]:
            got = edges(symbol)
            if got != expected:
                failures.append(f'{ext}/{symbol}: expected {expected}, got {got}')
        # A local function may be modelled or omitted, but must never become the import target/decoy.
        for symbol in ('local', 'closure', 'loop', 'selfNamed', 'classNamed'):
            if any(path != 'consumer.' + ext for _, path in edges(symbol)):
                failures.append(f'{ext}/{symbol}: shadow escaped its file')
        if edges('defaultParam') != [('target', 'owner.' + ext)]:
            failures.append(f'{ext}/defaultParam: body var hid the import in parameter scope')
        if edges('nested') != [('target', 'owner.' + ext)]:
            failures.append(f'{ext}/nested: block shadow swallowed the later import call')
        if ext in ('ts', 'tsx', 'mts', 'cts'):
            with consumer.open('a') as out:
                out.write('\nimport type { target as typeAlias } from \'./owner.' + spec + '\';\nexport function typeCaller(){ return typeAlias(); }\n')
                out.write('export function abstractCaller(){ abstract class alias {} return new alias(); }\n')
            if edges('typeCaller') or any(path != 'consumer.' + ext for _, path in edges('abstractCaller')):
                failures.append(f'{ext}: type-only import or abstract class minted a false edge')
        collision = root / ('collision.' + ext)
        collision.write_text('export const target = null; { function target() { return 9; } }\n')
        with consumer.open('a') as out:
            out.write(f"import {{ target as collisionAlias }} from './collision.{ext}';\nexport function collisionCaller(){{ return collisionAlias(); }}\n")
        if edges('collisionCaller'):
            failures.append(f'{ext}: export name matched a non-exported declaration')
        collision.write_text('export const {target} = function target() {};\n')
        if edges('collisionCaller'):
            failures.append(f'{ext}: destructured property became its initializer function')
        if ext in ('ts', 'tsx', 'mts', 'cts'):
            runtime = root / ('owner.' + spec)
            runtime.write_text('export function target(){ return 0; }\n')
            assert runtime.exists()
            if edges('caller'):
                failures.append(f'{ext}: competing source/runtime files picked a winner')
            runtime.unlink()
        cold, _ = run('caller')
        cache = '--cache=' + str(root / 'test.cache')
        first, _ = run('caller', cache)
        warm, _ = run('caller', cache)
        if cold != first or first != warm:
            failures.append(f'{ext}: cold/warm mismatch')
        # Mutate the actual import and run the same extraction: no alias target remains.
        before = consumer.read_text()
        after = before.replace(f"from './owner.{spec}'", "from 'missing-owner'")
        assert before != after
        consumer.write_text(after)
        assert consumer.read_text() == after
        if edges('caller'):
            failures.append(f'{ext}: changed import still produced an edge')
if failures:
    print('\n'.join('  FAIL  ' + failure for failure in failures))
    sys.exit(1)
print('  PASS  named imports resolve by module/export; shadows, missing targets and caches are bounded')
PY
