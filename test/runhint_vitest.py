#!/usr/bin/env python3
# Issue #323: evidence-backed Vitest hints, unknown cases, and unchanged test-gate exit.
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

binary = sys.argv[1]

def write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)

def report(root, changed, json_mode=False):
    args = [binary, str(root), f'--test-gate={changed}', '--no-cache']
    if json_mode:
        args.append('--json')
    else:
        args.append('--legend=compact')
    result = subprocess.run(args, capture_output=True, text=True, check=False, timeout=30)
    assert result.returncode == 4, (result.returncode, result.stderr, result.stdout)
    if json_mode:
        return json.loads(result.stdout)
    return ET.fromstring(result.stdout.split('-->', 1)[1])

def make_case(root, package, test_path='src/lib.test.ts'):
    write(root / 'package.json', json.dumps(package))
    write(root / 'src/lib.ts', 'export function add(a: number, b: number) { return a + b; }\n')
    write(root / test_path, 'import { add } from "./lib";\nexport function check() { return add(1, 2); }\n')

vitest = {'scripts': {'test': 'vitest run'}, 'devDependencies': {'vitest': '^3.2.0'}}
with tempfile.TemporaryDirectory() as temp:
    root = Path(temp) / 'repo'
    root.mkdir()
    make_case(root, vitest)
    row = report(root, 'src/lib.ts').find('t')
    assert row is not None and row.attrib['p'] == 'src/lib.test.ts', row
    assert row.attrib.get('run') == 'npm --prefix . run test -- src/lib.test.ts', row.attrib
    assert 'run_unknown' not in row.attrib, row.attrib
    j = report(root, 'src/lib.ts', True)
    assert j['tests_to_run'][0]['run'] == row.attrib['run'], j
    assert 'run_unknown' not in j['tests_to_run'][0], j
    print('PASS Vitest script and declared dependency produce the same XML/JSON command; gate remains exit 4')

    # The nearest package decides the runner. The package path and test argument are shell arguments.
    nested = root / 'packages/web app'
    write(nested / 'package.json', json.dumps(vitest))
    write(nested / 'src/lib.ts', 'export function add(a: number, b: number) { return a + b; }\n')
    write(nested / 'src/lib.test.ts', 'import { add } from "./lib";\nexport function check() { return add(1, 2); }\n')
    nested_row = report(root, 'packages/web app/src/lib.ts').find('t')
    assert nested_row is not None and nested_row.attrib.get('run') == "npm --prefix 'packages/web app' run test -- src/lib.test.ts", nested_row.attrib if nested_row is not None else None
    if shutil.which('npm'):
        trace = Path(temp) / 'vitest-argv'
        fake = nested / 'node_modules/.bin/vitest'
        write(fake, '#!/bin/sh\nprintf "%s|%s\\n" "$PWD" "$*" > "$RIPWIRE_VITEST_TRACE"\n')
        fake.chmod(0o755)
        env = dict(os.environ, RIPWIRE_VITEST_TRACE=str(trace))
        subprocess.run(nested_row.attrib['run'], shell=True, cwd=root, env=env, capture_output=True, text=True, check=True, timeout=30)
        assert trace.read_text().strip() == f'{nested.resolve()}|run src/lib.test.ts', trace.read_text()
        print('PASS emitted npm command executes the scoped test from the nearest package')
    print('PASS nearest package and shell quoting in a monorepo')

    # A nearer package with no Vitest evidence must not borrow the parent package's script.
    write(nested / 'package.json', json.dumps({'scripts': {'test': 'jest'}}))
    unknown = report(root, 'packages/web app/src/lib.ts').find('t')
    assert unknown is not None and unknown.attrib.get('run_unknown') == '1' and 'run' not in unknown.attrib, unknown.attrib if unknown is not None else None
    print('PASS nearest package without evidence keeps run_unknown')

    # The crawler can skip an oversized manifest; its presence still blocks an ancestor's runner.
    write(nested / 'package.json', json.dumps({'padding': 'x' * 270000}))
    unknown = report(root, 'packages/web app/src/lib.ts').find('t')
    assert unknown is not None and unknown.attrib.get('run_unknown') == '1' and 'run' not in unknown.attrib, unknown.attrib if unknown is not None else None
    print('PASS unindexed nearer package blocks ancestor runner')

    for label, package in (
        ('missing dependency', {'scripts': {'test': 'vitest run'}}),
        ('unsupported script', {'scripts': {'test': 'vitest watch'}, 'devDependencies': {'vitest': '^3.2.0'}}),
        ('unsupported package manager', {'packageManager': 'pnpm@9.0.0', **vitest}),
    ):
        write(root / 'package.json', json.dumps(package))
        row = report(root, 'src/lib.ts').find('t')
        assert row is not None and row.attrib.get('run_unknown') == '1' and 'run' not in row.attrib, (label, row.attrib if row is not None else None)
        print('PASS', label, 'keeps run_unknown')

    write(root / 'package.json', '{"scripts":{"test":"vitest run"},"devDependencies":{"vitest":"^3"}')
    row = report(root, 'src/lib.ts').find('t')
    assert row is not None and row.attrib.get('run_unknown') == '1', row.attrib if row is not None else None
    print('PASS malformed package.json keeps run_unknown')

    # A corpus path is shell input. Pasting the hint must keep it one argument and never run its suffix.
    write(root / 'package.json', json.dumps(vitest))
    hostile = 'src/odd;touch PWNED.test.ts'
    write(root / hostile, 'export function check() { return 1; }\n')
    row = report(root, hostile).find('t')
    assert row is not None and row.attrib.get('run') == "npm --prefix . run test -- 'src/odd;touch PWNED.test.ts'", row.attrib if row is not None else None
    fake_dir = Path(temp) / 'fake-bin'
    fake_dir.mkdir()
    fake_npm = fake_dir / 'npm'
    trace = Path(temp) / 'npm-argv'
    write(fake_npm, '#!/bin/sh\nprintf "%s\\n" "$@" > "$RIPWIRE_NPM_TRACE"\n')
    fake_npm.chmod(0o755)
    env = dict(os.environ, PATH=f'{fake_dir}:{os.environ.get("PATH", "")}', RIPWIRE_NPM_TRACE=str(trace))
    subprocess.run(row.attrib['run'], shell=True, cwd=root, env=env, capture_output=True, text=True, check=True, timeout=30)
    assert trace.read_text().splitlines() == ['--prefix', '.', 'run', 'test', '--', hostile], trace.read_text()
    assert not (root / 'PWNED.test.ts').exists()
    print('PASS hostile test path stays one argument with no shell side effect')

    js_root = Path(temp) / 'js-repo'
    js_root.mkdir()
    write(js_root / 'package.json', json.dumps(vitest))
    write(js_root / 'src/lib.js', 'export function add(a, b) { return a + b; }\n')
    write(js_root / 'src/lib.test.js', 'import { add } from "./lib";\nexport function check() { return add(1, 2); }\n')
    js_row = report(js_root, 'src/lib.js').find('t')
    assert js_row is not None and js_row.attrib.get('run') == 'npm --prefix . run test -- src/lib.test.js', js_row.attrib if js_row is not None else None
    print('PASS JavaScript test file receives the same scoped Vitest command')

    (js_root / 'package.json').unlink()
    unknown = report(js_root, 'src/lib.js').find('t')
    assert unknown is not None and unknown.attrib.get('run_unknown') == '1', unknown.attrib if unknown is not None else None
    print('PASS no package.json keeps run_unknown')

    # Vitest 3.2's default include is **/*.{test,spec}.?(c|m)[jt]s?(x). No vitest.config is read.
    shape = Path(temp) / 'shape'
    shape.mkdir()
    write(shape / 'package.json', json.dumps(vitest))

    def gate_name(rel):
        write(shape / rel, 'export function check() { return 1; }\n')
        xml = report(shape, rel)
        row = next((item for item in xml.iter('t') if item.attrib.get('p') == rel), None)
        js = next((item for item in report(shape, rel, True)['tests_to_run'] if item.get('p') == rel), None)
        return row, js

    for rel in (
        'src/lib.test.ts',
        'src/lib.spec.ts',
        'src/lib.test.js',
        'src/lib.test.tsx',
        'src/lib.spec.mts',
        'src/lib.test.cts',
        'test/helpers.test.ts',
    ):
        row, js = gate_name(rel)
        expect = f'npm --prefix . run test -- {rel}'
        assert row is not None and row.attrib.get('run') == expect and 'run_unknown' not in row.attrib, (rel, None if row is None else row.attrib)
        assert js is not None and js.get('run') == expect and 'run_unknown' not in js, (rel, js)
        print('PASS', rel, 'matches Vitest default include; XML and JSON agree')

    for rel in (
        'test/helpers.ts',
        'tests/setup.js',
        'src/test_helper.ts',
        'src/helper_test.ts',
        'src/lib.test.helper.ts',
    ):
        row, js = gate_name(rel)
        assert row is not None and row.attrib.get('run_unknown') == '1' and 'run' not in row.attrib, (rel, None if row is None else row.attrib)
        assert js is not None and js.get('run_unknown') is True and 'run' not in js, (rel, js)
        print('PASS', rel, 'keeps run_unknown; XML and JSON agree')
