#!/usr/bin/env bash
# pyimportprecisecheck.sh — LEVER-B B1 gate: path-precise PYTHON import resolution.
#
# The precise SameInclude tier now has a Python Step-A (resolve.h::resolvePythonImport): an
# `import a` / `import pkg.mod` / `from pkg.mod import Z` / `from .rel import Z` resolves to the ONE
# repo file it names (`a.py`, `pkg/mod.py`, `pkg/__init__.py`) by PATH — relative-to-file AND
# relative-to-repo-root — on a UNIQUE hit, else it degrades (no edge, no guess). Same "unique-or-degrade"
# discipline as the C-family quote-include tier.
#
# Fixture test/pyimportprecisefix — the soundness cases:
#   caller.py       import a                    → widget() binds a.py::widget       (NOT the decoy other/a.py)
#                   from pkg.mod import gadget   → gadget() binds pkg/mod.py::gadget  (NOT the decoy other/mod.py)
#                   import pkg                   → pkginit() binds pkg/__init__.py    (package __init__ resolution)
#                   import os (stdlib) + getcwd()→ UNRESOLVED (no false edge)
#   other/caller2.py import other.a             → widget() binds other/a.py::widget  (path, not basename)
#   rel/relcaller.py from .sibling import sib    → sib() binds rel/sibling.py::sib    (relative import)
#
# Also asserts B0 clean-specifier capture (--deps shows `pkg.mod`, not the sliced clause), MONOTONICITY
# (ambiguous can only DECREASE vs the pre-change binary), determinism, warm==cold, and well-formed XML.
#
# Usage:  test/pyimportprecisecheck.sh   |   RIPWIRE_BIN=asan/ripwire test/pyimportprecisecheck.sh
# Exits non-zero on any failure. Does NOT edit test/regression.sh or test/golden.xml.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/pyimportprecisefix"
. "$ROOT/test/lib/headbinlib.sh"                       # shared sha-keyed cache of the HEAD comparison binary
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "pyimportprecisecheck: BIN=$BIN  FIX=$FIX  TMP=$TMP"

# a callee edge of $1 resolving to file $2 (and to NO other .py holding the same-name def).
callee_binds(){  # $1 caller  $2 expected-path-substr  $3 must-NOT-contain-substr (decoy)
  "$BIN" "$FIX" --callees="$1" --no-cache >"$TMP/$1.out" 2>/dev/null
  if grep -q "$2" "$TMP/$1.out" && { [ -z "${3:-}" ] || ! grep -q "$3" "$TMP/$1.out"; }; then
    ok "$1 → $2 (unique, precise${3:+; not $3})"
  else
    no "$1 did not bind $2 alone"; cat "$TMP/$1.out"
  fi
}
callee_count(){  # $1 caller  $2 expected count=
  local c; c="$( grep -oE 'count="[0-9]+"' "$TMP/$1.out" | head -1 )"
  if [ "$c" = "count=\"$2\"" ]; then ok "$1 has $c callee(s)"; else no "$1 callee count wrong (got $c, want count=\"$2\")"; fi
}

# ── B1 path-precise resolution ────────────────────────────────────────────────────────────────────
callee_binds use_a        'a.py:'            'other/a.py'      ; callee_count use_a 1
callee_binds use_pkgmod   'pkg/mod.py:'      'other/mod.py'    ; callee_count use_pkgmod 1
callee_binds use_pkginit  'pkg/__init__.py:' ''               ; callee_count use_pkginit 1
callee_binds use_other_a  'other/a.py:'      ''               ; callee_count use_other_a 1   # NB: distinct from root a.py by PATH
callee_binds use_rel      'rel/sibling.py:'  ''               ; callee_count use_rel 1

# stdlib import → NO false edge (getcwd is not an in-repo def; `import os` must not manufacture one).
"$BIN" "$FIX" --callees=use_stdlib --no-cache >"$TMP/use_stdlib.out" 2>/dev/null
callee_count use_stdlib 0

# ── B0 clean specifier: --deps carries the module path, not the sliced clause ─────────────────────
"$BIN" "$FIX" --deps --no-cache >"$TMP/deps.out" 2>/dev/null
grep -q '<inc t="pkg.mod"' "$TMP/deps.out" \
  && ok 'B0: from pkg.mod import gadget → clean specifier t="pkg.mod"' \
  || { no 'B0: pkg.mod specifier not captured cleanly'; grep -oE '<inc t="[^"]*"' "$TMP/deps.out" | sort -u; }

# ── the fixture resolves everything → ambiguous=0 (a precise narrow never MANUFACTURES ambiguity) ─
famb="$( "$BIN" "$FIX" --no-cache 2>/dev/null | grep -oE 'ambiguous=[0-9]+' | head -1 )"
if [ "$famb" = "ambiguous=0" ]; then ok "fixture $famb"; else no "fixture $famb (expected 0)"; fi

# ── determinism + warm==cold ──────────────────────────────────────────────────────────────────────
"$BIN" "$FIX" --no-cache >"$TMP/d1" 2>/dev/null
"$BIN" "$FIX" --no-cache >"$TMP/d2" 2>/dev/null
if cmp -s "$TMP/d1" "$TMP/d2"; then ok "deterministic (two --no-cache runs identical)"; else no "non-deterministic"; fi
"$BIN" "$FIX" --cache="$TMP/c.bin" >"$TMP/cold" 2>/dev/null
"$BIN" "$FIX" --cache="$TMP/c.bin" >"$TMP/warm" 2>/dev/null
if cmp -s "$TMP/cold" "$TMP/warm"; then ok "warm == cold (resolver order-stable through cache)"; else no "warm != cold"; fi

# ── well-formed XML ───────────────────────────────────────────────────────────────────────────────
command -v xmllint >/dev/null 2>&1 \
  && { xmllint --noout "$TMP/d1" 2>/dev/null && ok "xml well-formed" || no "xml malformed"; } \
  || ok "xml well-formed (xmllint absent — skipped)"

# ── MONOTONICITY: NEW.ambiguous <= pre-change.ambiguous on the fixture (narrow only removes candidates)
# Build a pre-change binary from git HEAD (resolve.h + ingest.cpp changed), run BOTH on the fixture.
monotonic_check()
{
    command -v git   >/dev/null 2>&1 || { skip "monotonicity: git absent"; return; }
    command -v cmake >/dev/null 2>&1 || { skip "monotonicity: cmake absent"; return; }
    ( cd "$ROOT" && git rev-parse --verify HEAD >/dev/null 2>&1 ) || { skip "monotonicity: not a git repo"; return; }

    # pre-change binary from the shared sha-keyed cache (test/lib/headbinlib.sh): built at most once per
    # HEAD sha, then reused by all four monotonicity gates and every rerun until HEAD moves.
    local OLDBIN
    OLDBIN="$( ripwire_head_binary "$ROOT" "$TMP" )" \
        || { headbin_refusal $? "monotonicity"; return; }

    local ao an
    ao="$( "$OLDBIN" "$FIX" --no-cache 2>/dev/null | grep -oE 'ambiguous=[0-9]+' | head -1 | grep -oE '[0-9]+' )"
    an="$( "$BIN"    "$FIX" --no-cache 2>/dev/null | grep -oE 'ambiguous=[0-9]+' | head -1 | grep -oE '[0-9]+' )"
    if [ -n "$ao" ] && [ -n "$an" ] && [ "$an" -le "$ao" ]; then
        ok "monotonicity on fixture: ambiguous NEW=$an <= pre-change OLD=$ao (Python narrow only removes candidates)"
    else
        no "monotonicity VIOLATED: NEW=$an > OLD=$ao — a correct narrow was LOST (regression)"
    fi
}
monotonic_check

# #358 Python capture slice. Expectations below were read from pristine main, not from the new
# query: ONE Include per statement (first clause), but bindings for EVERY named/aliased clause.
# Aliased plain imports keep their whole written clause in --deps; cleaning it is a separate change.
PC="$TMP/captures"; mkdir -p "$PC/pkg"
cat >"$PC/main.py" <<'PY'
import a, b
import a as aa, b as bb
import pkg.mod
from pkg.mod import run, spare as renamed
from . import a
from pkg import *
from pkg.mod import (run as f, spare,)
import os
if TYPE_CHECKING:
    import b
try:
    from pkg.mod import run as rr
except ImportError:
    import a
class C:
    import b
    def method(self):
        import a as local
        return local.run()
def plain():
    return bb.run()
PY
printf 'def run():\n    return 1\n' >"$PC/a.py"
printf 'def run():\n    return 2\n' >"$PC/b.py"
printf 'def init():\n    return 1\n' >"$PC/pkg/__init__.py"
printf 'def run():\n    return 2\ndef spare():\n    return 3\n' >"$PC/pkg/mod.py"
printf 'import a as aa\nfrom pkg.mod import run as r\n' >"$PC/typing.pyi"
printf 'x = (import unreachable)\ndef okay():\n    import a\n' >"$PC/broken.py"

# This inspects the EMBEDDED vocabulary; --match alone also matches on a pre-change binary.
# The needles are the PYTHON PATTERNS themselves, not the bare capture names: v0.6.7's binary already
# carries `@import.names` and `@import.alias` in the Go tags.scm comment that explains their absence there,
# so a bare-name grep passed on a binary without the Python captures (review N2 on #382). Measured: both
# needles are absent from the v0.6.7 main binary (0e0f67c7) and the v0.6.5 release asset; present here.
if grep -qaF 'name: (dotted_name) @import.names' "$BIN" && grep -qaF 'alias: (identifier) @import.alias' "$BIN"; then
    ok '#358: Python import.names and import.alias vocabulary is compiled in'
else
    no '#358: Python import.names/import.alias vocabulary is absent from this binary'
fi
# Historical comments may retain the old name; check definitions, not prose.
if grep -rEq '^[[:space:]]*(inline[[:space:]]+)?void[[:space:]]+capturePythonImportBinds[[:space:]]*\(' "$ROOT/src"; then
    no '#358: replaced Python import binding extractor still exists in src/'
else
    ok '#358: replaced Python import binding extractor removed'
fi
"$BIN" "$PC" --deps --no-cache >"$TMP/pc.deps" 2>"$TMP/pc.err"
if python3 - "$TMP/pc.deps" <<'PY'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
rows = {f.get('p'): [i.get('t') for i in f.findall('inc')] for f in root.findall('f')}
want = ['a', 'a as aa', 'pkg.mod', 'pkg.mod', '.', 'pkg', 'pkg.mod', 'os',
        'b', 'pkg.mod', 'a', 'b', 'a as local']
assert rows == {'main.py': want, 'typing.pyi': ['a as aa', 'pkg.mod'], 'broken.py': ['a']}, rows
PY
then ok '#358: exact first-clause, alias, from, relative, wildcard, nested and .pyi targets; ERROR import stays out'
else no '#358: Python target set/order differs from pristine main'
fi
"$BIN" "$PC" --callees=plain --no-cache >"$TMP/pc.plain" 2>/dev/null
if grep -q '<callees [^>]*count="1"' "$TMP/pc.plain" && grep -q 'p="b.py:1"' "$TMP/pc.plain"; then
    ok '#358: the SECOND comma-separated module alias binds bb.run to b.py only'
else
    no '#358: binding for the second module alias was lost or widened'
fi

# Maintainer negatives and alias forms (#382). Keep these files free of definitions/assignments:
# then the lean cache exposes EVERY Include/RawBind, including bindings invisible in --deps.
PN="$TMP/pynegative"; mkdir -p "$PN"
printf 'from __future__ import annotations\n' >"$PN/future.py"
printf '__import__("x")\n' >"$PN/builtin_call.py"
printf 'import importlib\nimportlib.import_module("x")\n' >"$PN/importlib_call.py"
printf 'import a.b as c\n' >"$PN/dotted.py"
printf 'from . import a as b\n' >"$PN/relative.py"
"$BIN" "$PN" --deps --no-cache >"$TMP/pn.fresh" 2>"$TMP/pn.err" \
    || no '#382: fresh negative/alias fixture extraction failed'
"$BIN" "$PN" --deps --cache="$TMP/pn.bin" >"$TMP/pn.cold" 2>>"$TMP/pn.err" \
    || no '#382: cold negative/alias fixture extraction failed'
cp "$TMP/pn.bin" "$TMP/pn.copy"
"$BIN" "$PN" --deps --cache="$TMP/pn.bin" >"$TMP/pn.warm" 2>>"$TMP/pn.err" \
    || no '#382: warm negative/alias fixture extraction failed'
"$BIN" "$PN" --deps --no-cache >"$TMP/pn.repeat" 2>>"$TMP/pn.err" \
    || no '#382: repeated negative/alias fixture extraction failed'
if cmp -s "$TMP/pn.fresh" "$TMP/pn.cold" && cmp -s "$TMP/pn.cold" "$TMP/pn.warm" \
    && cmp -s "$TMP/pn.fresh" "$TMP/pn.repeat" && cmp -s "$TMP/pn.bin" "$TMP/pn.copy"; then
    ok '#382: negative/alias deps deterministic, fresh == cold == warm, cache not rewritten'
else
    no '#382: negative/alias deps or warm cache identity changed'
fi
if python3 - "$TMP/pn.fresh" "$TMP/pn.bin" "$ROOT" <<'PY'
import copy, pathlib, re, struct, sys, xml.etree.ElementTree as ET
from collections import Counter

# readFileRecord/writeBind in ingest_cache.h, lean cache v46 (train 40: 44 -> 46 for lane js-def-naming, its PLACEHOLDER 45: appended LocalBindKind::JsObjectLiteral, a JS/TS record no Python fixture writes, layout unchanged; train 37b: 43 -> 44, lane rust-degraded: FileHealth gains useBoundsBlanked, a sixth u32 (the walker below skips 6 * 4); train 36: 40 -> 43, #155 appends a `trailingLambda` u8 to every RawRef after `forwarded`, taken below; train 34: 39 -> 40 appended LocalBindKind::JsRebind only, a JS/TS record no Python fixture writes; train 33: 38 -> 39 moved the number only, above every live 38; lane l6-iface fix round 1: 37 -> 38 appended LocalBindKind::ImplBlock only;
# lane l6-iface: 36 -> 37 appended LocalBindKind::DispatchType only, no
# record layout change; train renumbers) (train 30: 34 -> 36 moved the number only, above three lanes'
# 33/33/35; name-template-dispatch: 32 -> 35 appended RefRole::Pattern = 11 only; fcall-forward: a RawRef appends the `forwarded` u8 after memberFactory; call-result-typing: a bind record gains two u8 after isFromAssignment, resultIndex and unwrapDepth, which a
# Python bind leaves at 0xFF / 0 — asserted below; train 29: 33 -> 34 moved the number only; arity-min: 32 -> 33 appends
# paramsMin to the DEF record, which this lean fixture never holds; train 28: 31 -> 32 moved the number only). No heuristic
# string searches: walk the counted arrays and require complete file coverage, clean parse health and exact EOF.
blob = pathlib.Path(sys.argv[2]).read_bytes()
endian = '<' if sys.byteorder == 'little' else '>'
assert blob[:4] == b'CTPK' and struct.unpack_from(endian + 'I', blob, 4)[0] == 46, 'update the cache walker for a new layout'
table, count = struct.unpack_from(endian + 'QI', blob, len(blob) - 24)
assert count == 5 == struct.unpack_from(endian + 'I', blob, 21)[0], 'all five fixtures must be cached'
assert table + count * 32 == len(blob) - 24, 'cache table bounds'
facts = {}
for i in range(count):
    off = table + i * 32
    pos = struct.unpack_from(endian + 'Q', blob, off + 8)[0]
    end = pos + struct.unpack_from(endian + 'I', blob, off + 24)[0]
    assert 25 <= pos <= end <= table, 'cache record bounds'
    def take(n):
        global pos
        assert n >= 0 and pos + n <= end, 'truncated cache record'
        data = blob[pos:pos + n]; pos += n
        return data
    def number(fmt):
        return struct.unpack(endian + fmt, take(struct.calcsize(fmt)))[0]
    def string():
        return take(number('I')).decode('utf-8')
    path = string()
    assert path not in facts, 'duplicate file record'
    take(4 * 8)  # content hash and size/mtime/ctime
    health = struct.unpack(endian + '6I', take(6 * 4))   # v44: + useBoundsBlanked (0: no Python file is re-parsed)
    assert health[0] == health[1] == health[5] == 0 and health[2] > 0, (path, 'fixture must parse cleanly', health)
    assert number('I') == 0, 'lean fixture must contain no definitions/dictionary'
    for _ in range(number('I')):  # RawRef: only its variable-length strings affect the walk
        take(5); string(); inherit = take(2)[0]; string(); take(1); string(); take(1)
        string(); string(); take(13)  # argCount is serialized u32, narrowed by u16Of32 on read
        for _ in range(4):
            string()  # memberRoot/memberPath/memberCtor/memberVia
        take(3)  # memberFactory, forwarded (fcall-forward), trailingLambda (#155)
        if inherit:
            take(4)  # baseBind
    incs = []
    for _ in range(number('I')):
        flags = tuple(take(3)); byte = number('I'); value_use = number('B')
        incs.append((string(), byte, flags, value_use))
    binds = []
    for _ in range(number('I')):
        byte = number('I'); lang = number('B'); kind = number('B'); assignment = number('B')
        assert (number('B'), number('B')) == (0xFF, 0), (path, 'a Python bind carries no call-result position / unwrap depth')
        spans = (number('I'), number('I'))
        binds.append((string(), string(), string(), byte, lang, kind, assignment, spans))
    for _ in range(4):  # FFI aliases, route defs/uses, const-opens: absent in this Python fixture
        assert number('I') == 0, 'unexpected auxiliary fact'
    assert pos == end, (path, 'cache walker desynchronised')
    facts[path] = (incs, binds)

# Derive enum values from their declarations; do not mistake a Type/VarDecl for an Import.
model = re.sub(r'//[^\n]*', '', pathlib.Path(sys.argv[3], 'src/model.h').read_text())
def enum_value(enum, name):
    body = re.search(r'enum class ' + enum + r'\s*:\s*std::uint8_t\s*\{([^}]+)\}', model).group(1)
    names = [s.strip() for s in body.split(',') if s.strip()]
    return names.index(name)
py = enum_value('Lang', 'Python'); imp = enum_value('LocalBindKind', 'Import')
name_alias = enum_value('LocalBindKind', 'NameAlias')
def include(target):
    return (target, 0, (0, 0, 0), 0)
def bind(var, target, marker):
    return (var, target, marker, 0, py, imp, 0, (0, 0))
want = {
    'future.py': ([], []),
    'builtin_call.py': ([], []),
    'importlib_call.py': ([include('importlib')], [bind('importlib', 'importlib', 'module')]),
    'dotted.py': ([include('a.b as c')], [bind('c', 'a.b', 'module')]),
    # HISTORY (lane ind4b, fix 5 -> fix 6): the Import RawBind of an ALIASED from-import used to carry importedName '' (no marker); fix 5
    # records the member's own name for it, 'from:a' (kPythonFromMemberMark + a), so `from . import a as b` + `b.Base` can be read as the
    # submodule a. The change is on purpose, not erosion: the pin still asserts the exact value (a wrong or missing marker fails, see the
    # wrong_marker control below), and only a plain `from m import x` or a module-form import keeps ''/'module'.
    # The receiver-evidence pass also writes this NameAlias. Pin all its fields and count;
    # its position relative to the Import bind is an implementation detail of the two passes.
    'relative.py': ([include('.')], [('b', 'a', '', 14, py, name_alias, 0, (0, 0)), bind('b', '.', 'from:a')]),
}
def check(actual):
    assert actual.keys() == want.keys() and all(
        incs == want[path][0] and Counter(binds) == Counter(want[path][1])
        for path, (incs, binds) in actual.items()), ('Include/RawBind mismatch', actual, want)
check(facts)
rows = {f.get('p'): [inc.get('t') for inc in f.findall('inc')]
        for f in ET.parse(sys.argv[1]).getroot().findall('f')}
assert rows == {p: [inc[0] for inc in incs] for p, (incs, _) in want.items() if incs}, rows

# Test the SAME predicate with deliberately wrong extracted facts. Each control must fail;
# unrelated fields are left intact, so loss of coverage cannot hide behind another assertion.
for path in ('future.py', 'builtin_call.py', 'importlib_call.py'):
    for channel, extra in ((0, include('x')), (1, bind('x', 'x', 'module'))):
        bad = copy.deepcopy(facts); bad[path][channel].append(extra)
        try: check(bad)
        except AssertionError: pass
        else: raise AssertionError((path, channel, 'extra fact escaped the negative assertion'))
for path in ('dotted.py', 'relative.py'):
    for field, wrong in ((0, 'wrong_alias'), (1, 'wrong.target'), (2, 'wrong_marker')):
        bad = copy.deepcopy(facts); idx = next(i for i, row in enumerate(bad[path][1]) if row[5] == imp)
        row = list(bad[path][1][idx]); row[field] = wrong
        bad[path][1][idx] = tuple(row)
        try: check(bad)
        except AssertionError: pass
        else: raise AssertionError((path, field, 'wrong binding escaped the alias assertion'))
    for channel in (0, 1):
        bad = copy.deepcopy(facts)
        if channel == 0:
            bad[path][channel].clear()
        else:
            bad[path][channel][:] = [row for row in bad[path][channel] if row[5] != imp]
        try: check(bad)
        except AssertionError: pass
        else: raise AssertionError((path, channel, 'missing fact escaped the alias assertion'))
print('  PASS  #382: 16 corrupt-fact controls rejected by the exact Include/RawBind predicate')
PY
then ok '#382: future/dynamic negatives; c -> a.b with module marker; relative Include . and b -> . with the member marker from:a'
else no '#382: negative/alias extraction or assertion controls failed'
fi

# One-space indentation avoids the vendored scanner's 8-bit serialized indent overflow. Each if
# spends two containers; an else arm spends three. These parse cleanly at exactly 255/256/257.
BD="$TMP/pybound"; mkdir -p "$BD"
if python3 - "$BD" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
for depth in (255, 256, 257, 258):
    if depth % 2:
        n = (depth - 3) // 2
        s = ''.join(' ' * i + 'if flag:\n' for i in range(n))
        s += ' ' * n + 'if flag:\n' + ' ' * (n + 1) + 'pass\n'
        s += ' ' * n + 'else:\n' + ' ' * (n + 1) + 'import a\n'
    else:
        n = depth // 2
        s = ''.join(' ' * i + 'if flag:\n' for i in range(n))
        s += ' ' * n + ('pass\n' if depth == 258 else 'import a\n')
    (p / f'depth{depth}.py').write_text(s)
PY
then :; else no '#358: could not generate Python nesting fixture'; fi
"$BIN" "$BD" --deps --no-cache >"$TMP/pb.deps" 2>/dev/null
"$BIN" "$BD" --skipped --no-cache >"$TMP/pb.skipped" 2>/dev/null
if python3 - "$TMP/pb.deps" "$TMP/pb.skipped" <<'PY'
import sys, xml.etree.ElementTree as ET
rows = ET.parse(sys.argv[1]).getroot().findall('f')
assert {f.get('p'): [i.get('t') for i in f.findall('inc')] for f in rows} == {
    'depth255.py': ['a'], 'depth256.py': ['a']}
skipped = ET.parse(sys.argv[2]).getroot().find('skipped')
assert skipped is not None
assert not skipped.findall('h'), 'nesting fixture must parse without recovery'
assert {f.get('p') for f in skipped.findall('f') if f.get('why') == 'extract-partial'} == {
    'depth257.py'}, 'cut at 257 is disclosed; import-free deep container has nothing cut'
PY
then ok '#358: clean 255/256 imports kept, 257 cut/disclosed, and import-free 258 not disclosed'
else no '#358: Python reach/depth/disclosure differs from pristine main'
fi

# Negative control: changing a non-first clause changes its BINDING while the first-clause Include
# is unchanged. The mutation must take, and the identical callee extraction must see it.
printf 'def run():\n    return 3\n' >"$PC/c.py"
cp "$PC/main.py" "$TMP/pc.source"
sed 's/a as aa, b as bb/a as aa, c as bb/' "$TMP/pc.source" >"$PC/main.py"
if cmp -s "$PC/main.py" "$TMP/pc.source"; then no '#358: second-clause mutation did not take'; fi
"$BIN" "$PC" --callees=plain --no-cache >"$TMP/pc.changed" 2>/dev/null
if grep -q '<callees [^>]*count="1"' "$TMP/pc.changed" && grep -q 'p="c.py:1"' "$TMP/pc.changed" && ! cmp -s "$TMP/pc.plain" "$TMP/pc.changed"; then
    ok '#358: second-clause mutation moves the alias edge (binding control is live)'
else
    no '#358: second-clause mutation did not move the alias edge'
fi
cp "$TMP/pc.source" "$PC/main.py"
rm -f "$PC/c.py"

"$BIN" "$PC" --deps --cache="$TMP/pc.bin" >"$TMP/pc.cold" 2>/dev/null
"$BIN" "$PC" --deps --cache="$TMP/pc.bin" >"$TMP/pc.warm" 2>/dev/null
if cmp -s "$TMP/pc.deps" "$TMP/pc.cold" && cmp -s "$TMP/pc.cold" "$TMP/pc.warm"; then
    ok '#358: Python dependency output identical through fresh and warm caches'
else
    no '#358: Python dependency output differs through cache'
fi
BASE_BIN="${RIPWIRE_BASE_BIN:-}"
if [ -n "$BASE_BIN" ] && [ -x "$BASE_BIN" ]; then
    "$BASE_BIN" "$PC" --deps --cache="$TMP/pc.base.bin" >"$TMP/pc.base" 2>/dev/null
    cp "$TMP/pc.base.bin" "$TMP/pc.base.copy"
    "$BIN" "$PC" --deps --cache="$TMP/pc.base.bin" >"$TMP/pc.prewarm" 2>/dev/null
    if cmp -s "$TMP/pc.base" "$TMP/pc.deps" && cmp -s "$TMP/pc.prewarm" "$TMP/pc.deps" && cmp -s "$TMP/pc.base.bin" "$TMP/pc.base.copy"; then
        ok '#358: pristine-main Python cache accepted without rewrite; fresh output byte-identical'
    else
        no '#358: pristine-main Python cache/output differs; parser-version parity not established'
    fi
else
    skip '#358: pristine-main cache compatibility (set RIPWIRE_BASE_BIN)'
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
