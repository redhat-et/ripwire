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
# An aliased first clause records its bare module (#478 gap 2): these pins read `a as aa` / `a as local` / `a.b as c`
# until that fix, which moved them on purpose. The #478 gap 2 arms at the end of this gate say why.
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
want = ['a', 'a', 'pkg.mod', 'pkg.mod', '.', 'pkg', 'pkg.mod', 'os',
        'b', 'pkg.mod', 'a', 'b', 'a']
assert rows == {'main.py': want, 'typing.pyi': ['a', 'pkg.mod'], 'broken.py': ['a']}, rows
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

# readFileRecord/writeBind in ingest_cache.h, lean cache v51 (lane qd-constructs: 50 -> 51, the record head gains a ninth family count and the record ends with the construct-hit family, both taken below; lane clones-persist: 49 -> 50, a DEF record ends with a clone-key presence u8 (+ the u64 key), a record this lean fixture never holds, layout of the walked records unchanged; lane warm-direct: 48 -> 49, the record head gains the eight family counts after FileHealth, taken below; train 42b: 46 -> 48, lane alias-import's appended LocalBindKind::ReExport (its placeholder 47), a TS/JS record no Python fixture writes, layout unchanged; train 40: 44 -> 46 for lane js-def-naming, its PLACEHOLDER 45: appended LocalBindKind::JsObjectLiteral, a JS/TS record no Python fixture writes, layout unchanged; train 37b: 43 -> 44, lane rust-degraded: FileHealth gains useBoundsBlanked, a sixth u32 (the walker below skips 6 * 4); train 36: 40 -> 43, #155 appends a `trailingLambda` u8 to every RawRef after `forwarded`, taken below; train 34: 39 -> 40 appended LocalBindKind::JsRebind only, a JS/TS record no Python fixture writes; train 33: 38 -> 39 moved the number only, above every live 38; lane l6-iface fix round 1: 37 -> 38 appended LocalBindKind::ImplBlock only;
# lane l6-iface: 36 -> 37 appended LocalBindKind::DispatchType only, no
# record layout change; train renumbers) (train 30: 34 -> 36 moved the number only, above three lanes'
# 33/33/35; name-template-dispatch: 32 -> 35 appended RefRole::Pattern = 11 only; fcall-forward: a RawRef appends the `forwarded` u8 after memberFactory; call-result-typing: a bind record gains two u8 after isFromAssignment, resultIndex and unwrapDepth, which a
# Python bind leaves at 0xFF / 0 — asserted below; train 29: 33 -> 34 moved the number only; arity-min: 32 -> 33 appends
# paramsMin to the DEF record, which this lean fixture never holds; train 28: 31 -> 32 moved the number only). No heuristic
# string searches: walk the counted arrays and require complete file coverage, clean parse health and exact EOF.
blob = pathlib.Path(sys.argv[2]).read_bytes()
endian = '<' if sys.byteorder == 'little' else '>'
assert blob[:4] == b'CTPK' and struct.unpack_from(endian + 'I', blob, 4)[0] == 51, 'update the cache walker for a new layout'
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
    take(9 * 4)  # v49: the head copy of the family counts (each family's own count follows below); v51: nine, + construct hits
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
    take(number('I') * 9)  # v51: --quality-delta construct hits (startByte, line u32; tag u8), fixed size
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
    'dotted.py': ([include('a.b')], [bind('c', 'a.b', 'module')]),
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

# #478 gap 1: `from pkg import mod` depends on pkg/mod.py, not only on pkg/__init__.py. The from-import's ONE Include names the
# package (`pkg`, `.`, `..`, `.sub2`), so the edge to the submodule a member names was lost — and with it Ce/Ca, cycles and the
# importer tiers of every view on the file graph. The wide form (any `from pkg import mod`), with the bare `from . import x` as
# one case of it. Each member file below has exactly ONE importer shape, so its afferent= is that shape's edge alone, and every
# negative is a near miss: the alias's own name has a file (pkg/m.py), a class name has a case-folded namesake (pkg/someclass.py),
# a stdlib member has a root namesake (path.py), and a member that is both pkg/dup.py and pkg/dup/__init__.py is ambiguous.
PB="$TMP/pymember"; mkdir -p "$PB/pkg/sub" "$PB/pkg/dup" "$PB/rel/inner" "$PB/rel/sub2" "$PB/ns"
printf 'class SomeClass:\n    pass\n' >"$PB/pkg/__init__.py"
for m in mod aliased m ma someclass fn_mod dup; do printf 'def pym_%s():\n    return 1\n' "$m" >"$PB/pkg/$m.py"; done
printf 'def helper():\n    return 1\n' >>"$PB/pkg/mod.py"
printf 'def helper():\n    return 2\n' >>"$PB/pkg/ma.py"
: >"$PB/pkg/sub/__init__.py"; : >"$PB/pkg/dup/__init__.py"
: >"$PB/rel/__init__.py"; : >"$PB/rel/inner/__init__.py"; : >"$PB/rel/sub2/__init__.py"
for f in rel/sib rel/up rel/sub2/leaf ns/b path; do printf 'def pym_leaf():\n    return 1\n' >"$PB/$f.py"; done
printf 'from pkg import mod\n\n\ndef pym_use_wide():\n    return helper()\n' >"$PB/wide.py"
printf 'from pkg import aliased as m\n' >"$PB/aliasm.py"
printf 'from pkg import ma, sub\n' >"$PB/multi.py"
printf 'from pkg import SomeClass\n' >"$PB/klass.py"
printf 'from pkg import *\n' >"$PB/star.py"
printf 'from os import path\n' >"$PB/ext.py"
printf 'from pkg import dup\n' >"$PB/dupuser.py"
printf 'def pym_fn():\n    from pkg import fn_mod\n    return fn_mod\n' >"$PB/fnimp.py"
printf 'from . import sib\n' >"$PB/rel/user.py"
printf 'from .. import up\n' >"$PB/rel/inner/deep.py"
printf 'from .sub2 import leaf\n' >"$PB/rel/s2user.py"
printf 'from . import b\n' >"$PB/ns/a.py"
"$BIN" "$PB" --deps --no-cache >"$TMP/pb.deps" 2>/dev/null; rc=$?
if [ "$rc" -ne 0 ] || ! grep -q '<deps ' "$TMP/pb.deps"; then
    no "#478 gap 1: --deps on the member fixture did not run (rc=$rc)"
else
    if python3 - "$TMP/pb.deps" >"$TMP/pb.verdict" 2>&1 <<'PY'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
god = root.find('godfiles')
assert god is not None and god.get('capped') == '0', 'godfiles absent or capped: every afferent row must be visible'
aff = {f.get('p'): int(f.get('afferent')) for f in god.findall('f')}
# base edges: the seven `from pkg import …` statements hit pkg/__init__.py, the two relative ones rel/__init__.py, `.sub2` its own.
want = {'pkg/__init__.py': 7, 'rel/__init__.py': 2, 'rel/sub2/__init__.py': 1,
        'pkg/mod.py': 1, 'pkg/aliased.py': 1, 'pkg/ma.py': 1, 'pkg/sub/__init__.py': 1, 'pkg/fn_mod.py': 1,
        'rel/sib.py': 1, 'rel/up.py': 1, 'rel/sub2/leaf.py': 1, 'ns/b.py': 1}
assert aff == want, ('afferent', {k: (aff.get(k), want.get(k)) for k in sorted(set(aff) | set(want)) if aff.get(k) != want.get(k)})
cone = {f.get('p'): int(f.get('transitive')) for f in root.findall('f')}
for p, n in {'wide.py': 3, 'multi.py': 4, 'klass.py': 2, 'star.py': 2, 'ext.py': 1, 'dupuser.py': 2, 'ns/a.py': 2,
             'rel/user.py': 3, 'rel/inner/deep.py': 3, 'rel/s2user.py': 3, 'fnimp.py': 3, 'aliasm.py': 3}.items():
    assert cone.get(p) == n, ('transitive', p, cone.get(p), n)
PY
    then ok '#478 gap 1: member edges for wide, aliased (from:aliased, not m), multi-clause, subpackage, function-level, `.`, `..`, `.sub2` and namespace-package from-imports; none for a class, `*`, stdlib, or an ambiguous member'
    else no "#478 gap 1: member edges wrong: $( tail -1 "$TMP/pb.verdict" )"
    fi
fi
# A member edge is a DEPENDENCY, not import evidence for a bare call (the Include::isValueUse rule): `from pkg import mod` makes no
# name of mod visible bare, so wide.py's helper() — defined in both pkg/mod.py and pkg/ma.py — must stay declined, as on main.
"$BIN" "$PB" --callees=pym_use_wide --no-cache --legend=compact >"$TMP/pb.callees" 2>/dev/null; rc=$?
if [ "$rc" -eq 0 ] && grep -q '<callees [^>]*count="0"' "$TMP/pb.callees" && grep -q 'declined_calls="1"' "$TMP/pb.callees"; then
    ok '#478 gap 1 rule 3: a member edge does not bind a bare call (wide.py helper() stays declined)'
else
    no "#478 gap 1 rule 3: the member edge changed call binding or the run failed (rc=$rc): $( sed 's/<!--[^>]*-->//' "$TMP/pb.callees" )"
fi

# #533 review: the importer each member edge resolves TO, not only the counts — `--impact=FILE` lists a file's importers, so a
# swap of wide.py's pkg/mod.py edge with multi.py's pkg/ma.py edge (same afferent=, same cones) fails here.
# imp ROOT... FILE: one root, or several for a multi-root workspace (FILE is then root-labeled, rb/pkg/mod.py). A run that fails
# (rc != 0, or no <impact> answer) must never read as "no importers": an empty list is what the negative arms want. So it prints
# IMPERR(...) in place of the list, which no arm accepts, and logs the call to $TMP/imp.err, which fails the gate at the end
# (imp runs in a $( ) subshell, so it cannot set fail itself). #533 review (CodeRabbit, round 2).
imp(){
    local tgt="${!#}" out rc
    echo "$tgt" >>"$TMP/imp.calls"
    out="$( "$BIN" "${@:1:$#-1}" --impact="$tgt" --no-cache --legend=compact 2>/dev/null )"; rc=$?
    if [ "$rc" -ne 0 ] || ! grep -q '<impact ' <<<"$out"; then
        printf 'imp %s: rc=%s, impact answer %s\n' "$tgt" "$rc" "$( grep -q '<impact ' <<<"$out" && echo present || echo absent )" >>"$TMP/imp.err"
        printf 'IMPERR(rc=%s) ' "$rc"; return 0
    fi
    grep -oE '<f via="[^"]*" p="[^"]*"' <<<"$out" | sed 's/.*p="//; s/"$//' | sort | tr '\n' ' '
}
IW="$( imp "$PB" pkg/mod.py )"; IM="$( imp "$PB" pkg/ma.py )"
if [ "$IW" = "wide.py " ] && [ "$IM" = "multi.py " ]; then
    ok '#478 gap 1 targets: pkg/mod.py is imported by wide.py alone, pkg/ma.py by multi.py alone'
else no "#478 gap 1 targets: pkg/mod.py <- [$IW], pkg/ma.py <- [$IM]"; fi
# #533 review: the member lookup is confined to the package that resolved. Python reads `from pkg import m` as pkg's own m, so:
#   - pkg resolved to <D>/__init__.py → only <D>/m.py or <D>/m/__init__.py; a different root's pkg/m.py is never the member
#     (app/pkg/fromuser.py: `from pkg import helper` names app/pkg/__init__.py's def, NOT pkg/helper.py);
#   - pkg resolved to a plain module (util.py beside a util/ directory) → the module wins at import time: no member edge;
#   - the confined probe still finds the member it should (app/pkg/user2.py → app/pkg/real.py, with a pkg/real.py namesake).
# And two shapes the member edge must survive: an import under `if TYPE_CHECKING:` and one inside try/except ImportError.
PC="$TMP/pyconfine"; mkdir -p "$PC/app/pkg" "$PC/pkg" "$PC/util" "$PC/pkg2"
printf 'def helper():\n    return 1\n' >"$PC/app/pkg/__init__.py"
printf 'from pkg import helper\n' >"$PC/app/pkg/fromuser.py"
printf 'from pkg import real\n' >"$PC/app/pkg/user2.py"
: >"$PC/pkg/__init__.py"; : >"$PC/pkg2/__init__.py"
for f in app/pkg/real pkg/helper pkg/real util util/x pkg2/tcmod pkg2/trymod; do printf 'def pyc_leaf():\n    return 1\n' >"$PC/$f.py"; done
printf 'from util import x\n' >"$PC/utiluser.py"
printf 'from typing import TYPE_CHECKING\nif TYPE_CHECKING:\n    from pkg2 import tcmod\n' >"$PC/tc.py"
printf 'try:\n    from pkg2 import trymod\nexcept ImportError:\n    trymod = None\n' >"$PC/tryimp.py"
CH="$( imp "$PC" pkg/helper.py )"; CU="$( imp "$PC" util/x.py )"; CR="$( imp "$PC" app/pkg/real.py )"; CR2="$( imp "$PC" pkg/real.py )"
if [ "$CH" = "" ] && [ "$CU" = "" ]; then
    ok '#533 confine: no member edge from another root (pkg/helper.py) or through a plain module (util.py beside util/x.py)'
else no "#533 confine: pkg/helper.py <- [$CH], util/x.py <- [$CU] (both must be empty)"; fi
if [ "$CR" = "app/pkg/user2.py " ] && [ "$CR2" = "" ]; then
    ok '#533 confine twin: the resolved package'"'"'s own member is found (app/pkg/real.py), its other-root namesake is not'
else no "#533 confine twin: app/pkg/real.py <- [$CR], pkg/real.py <- [$CR2]"; fi
# #533 review (round 2): a name that is BOTH bound in pkg/__init__.py and a sibling pkg/<name>.py still draws the member edge, and
# the package edge stays. `from pkg3 import both` loads pkg3 (whose __init__ defines both()) and, in the usual case, that binding is
# the package re-exporting its own submodule, so the dependency on pkg3/both.py is real; the edge is drawn by design, not by accident.
mkdir -p "$PC/pkg3"
printf 'def both():\n    return 1\n' >"$PC/pkg3/__init__.py"
printf 'def pyc_both():\n    return 1\n' >"$PC/pkg3/both.py"
printf 'from pkg3 import both\n' >"$PC/bothuser.py"
CB="$( imp "$PC" pkg3/both.py )"; CBI="$( imp "$PC" pkg3/__init__.py )"
if [ "$CB" = "bothuser.py " ] && [ "$CBI" = "bothuser.py " ]; then
    ok '#533 init-and-sibling: a name both bound in pkg3/__init__.py and a file pkg3/both.py draws the member edge and keeps the package edge'
else no "#533 init-and-sibling: pkg3/both.py <- [$CB], pkg3/__init__.py <- [$CBI] (both must be bothuser.py)"; fi
CT="$( imp "$PC" pkg2/tcmod.py )"; CY="$( imp "$PC" pkg2/trymod.py )"
if [ "$CT" = "tc.py " ] && [ "$CY" = "tryimp.py " ]; then
    ok '#478 gap 1 shapes: a member import under `if TYPE_CHECKING:` and inside try/except ImportError keeps its edge'
else no "#478 gap 1 shapes: pkg2/tcmod.py <- [$CT], pkg2/trymod.py <- [$CY]"; fi

# #533 review (CodeRabbit, round 2): in a multi-root workspace the member probe is anchored at the PACKAGE's root, not the importer's.
# pkgDir is the package's labeled dir (rb/pkg), so probing it with the importer's identity rejected root rb's own rb/pkg/mod.py as a
# cross-root hit and fell back to the importer's disk directory, where root ra's same-path ra/rb/pkg/mod.py won: the real member
# edge was lost and a false one drawn. Premise: the package edge itself resolves across the roots (ra/user.py → rb/pkg/__init__.py).
MR="$TMP/pymultiroot"; mkdir -p "$MR/ra/rb/pkg" "$MR/rb/pkg"
printf 'from ..rb.pkg import mod\n' >"$MR/ra/user.py"
: >"$MR/rb/pkg/__init__.py"
printf 'def pymr_member():\n    return 1\n' >"$MR/rb/pkg/mod.py"
printf 'def pymr_decoy():\n    return 2\n' >"$MR/ra/rb/pkg/mod.py"
MP="$( imp "$MR/ra" "$MR/rb" rb/pkg/__init__.py )"; MM="$( imp "$MR/ra" "$MR/rb" rb/pkg/mod.py )"; MD="$( imp "$MR/ra" "$MR/rb" ra/rb/pkg/mod.py )"
if [ "$MP" != "ra/user.py " ]; then
    no "#533 multi-root premise: the package edge did not resolve across roots (rb/pkg/__init__.py <- [$MP]), so the member arm saw nothing"
elif [ "$MM" = "ra/user.py " ] && [ "$MD" = "" ]; then
    ok '#533 multi-root: the member edge lands in the package'"'"'s root (rb/pkg/mod.py), not on the importer root'"'"'s same-path ra/rb/pkg/mod.py'
else no "#533 multi-root: rb/pkg/mod.py <- [$MM] (want ra/user.py), ra/rb/pkg/mod.py <- [$MD] (want empty)"; fi

# #478 gap 2: an aliased plain import records the MODULE as its Include target. tree-sitter-python's import_statement
# carries name:(dotted_name|aliased_import), and the first-clause capture read the whole aliased_import span, so
# `import pkg.mod as pm` recorded `pkg.mod as pm`: no resolver finds that module, and the file lost its edge in --deps,
# --arch, cycles and the Rule 3 call narrow. Arms and fixture shapes ported from joyful-ii-V-I's pyaliasincludecheck
# (46bfa131, lane/py-alias-include-target, written against the pre-#382 walk); the multi-clause and one-segment rows
# are new. pkg/mod.py and other/mod.py both define pyai_helper, so a bare call to it binds only through the include.
PA="$TMP/pyalias"; mkdir -p "$PA/pkg" "$PA/other"
: >"$PA/pkg/__init__.py"; : >"$PA/other/__init__.py"
printf 'def pyai_helper():\n    return 1\n' >"$PA/pkg/mod.py"
printf 'def pyai_helper():\n    return 2\n' >"$PA/other/mod.py"
printf 'def pyai_single():\n    return 3\n' >"$PA/single.py"
printf 'import pkg.mod as pm\nimport os.path as osp\n\n\ndef pyai_caller_aliased():\n    return pyai_helper() + len( osp.sep )\n' >"$PA/aliased.py"
printf 'import pkg.mod\n\n\ndef pyai_caller_plain():\n    return pyai_helper()\n' >"$PA/plain.py"
printf 'from pkg.mod import pyai_helper as h\n\n\ndef pyai_caller_from():\n    return h()\n' >"$PA/fromimp.py"
printf 'import pkg.mod as pm, os.path\n' >"$PA/multi.py"
printf 'import single as s\n' >"$PA/onesegment.py"
printf 'import as_x\n' >"$PA/asname.py"
printf 'def as_x_fn():\n    return 4\n' >"$PA/as_x.py"
"$BIN" "$PA" --deps --no-cache >"$TMP/pa.deps" 2>/dev/null; rc=$?
if [ "$rc" -ne 0 ] || ! grep -q '<deps ' "$TMP/pa.deps"; then
    no "#478 gap 2: --deps on the alias fixture did not run (rc=$rc)"
else
    if python3 - "$TMP/pa.deps" <<'PY'
import sys, xml.etree.ElementTree as ET
rows = {f.get('p'): [i.get('t') for i in f.findall('inc')] for f in ET.parse(sys.argv[1]).getroot().findall('f')}
want = {'aliased.py': ['pkg.mod', 'os.path'], 'plain.py': ['pkg.mod'], 'fromimp.py': ['pkg.mod'],
        'multi.py': ['pkg.mod'], 'onesegment.py': ['single'], 'asname.py': ['as_x']}
got = {p: rows.get(p) for p in want}
assert got == want, got
assert not any(' as ' in t for ts in rows.values() for t in ts), rows
PY
    then ok '#478 gap 2: aliased, multi-clause and one-segment targets are the bare module; `import as_x` unchanged; no `… as …` row'
    else no "#478 gap 2: alias targets wrong: $( grep -oE '<inc t="[^"]*"' "$TMP/pa.deps" | sort | uniq -c | tr '\n' ' ' )"
    fi
    # afferent counts edge occurrences: plain + fromimp (controls) + aliased + multi (the fix) = 4.
    grep -q '<f p="pkg/mod.py" afferent="4"/>' "$TMP/pa.deps" \
        && ok '#478 gap 2: pkg/mod.py afferent="4" (plain + from-import + aliased + aliased-first multi-clause)' \
        || no "#478 gap 2: pkg/mod.py afferent wrong: $( grep -oE '<f p="pkg/mod.py"[^>]*>' "$TMP/pa.deps" )"
    grep -q '<f p="single.py" afferent="1"/>' "$TMP/pa.deps" \
        && ok '#478 gap 2: one-segment `import single as s` resolves (single.py afferent="1")' \
        || no "#478 gap 2: single.py afferent wrong: $( grep -oE '<f p="single.py"[^>]*>' "$TMP/pa.deps" )"
    # transitive= is the file's resolved cone: itself + pkg/mod.py = 2 (os.path is external). It read 1 while the
    # aliased target resolved to nothing.
    grep -oE '<f p="aliased.py"[^>]*>' "$TMP/pa.deps" | grep -q 'transitive="2"' \
        && ok '#478 gap 2: aliased.py transitive="2" (itself + pkg/mod.py; os.path is external)' \
        || no "#478 gap 2: aliased.py cone wrong: $( grep -oE '<f p="aliased.py"[^>]*>' "$TMP/pa.deps" )"
fi
"$BIN" "$PA" --callers=pkg/mod.py:pyai_helper --no-cache --legend=compact >"$TMP/pa.callers" 2>/dev/null; rc=$?
if [ "$rc" -ne 0 ] || ! grep -q '<callers ' "$TMP/pa.callers"; then
    no "#478 gap 2: --callers did not run (rc=$rc)"
else
    grep -q 'n="pyai_caller_aliased" p="aliased.py:5"' "$TMP/pa.callers" \
        && ok '#478 gap 2 rule 3: aliased.py:pyai_caller_aliased binds pkg/mod.py:pyai_helper through the include' \
        || no "#478 gap 2 rule 3: pyai_caller_aliased is not a caller of pkg/mod.py:pyai_helper: $( cat "$TMP/pa.callers" )"
    grep -q 'n="pyai_caller_plain" p="plain.py:4"' "$TMP/pa.callers" \
        && ok '#478 gap 2 rule 3 control: plain.py:pyai_caller_plain binds pkg/mod.py:pyai_helper' \
        || no "#478 gap 2 rule 3 control: pyai_caller_plain lost its edge: $( cat "$TMP/pa.callers" )"
fi
"$BIN" "$PA" --callers=other/mod.py:pyai_helper --no-cache --legend=compact >"$TMP/pa.other" 2>/dev/null; rc=$?
if [ "$rc" -eq 0 ] && grep -q '<callers [^>]*count="0"' "$TMP/pa.other"; then
    ok '#478 gap 2 rule 3 negative: the decoy other/mod.py:pyai_helper has no caller'
else
    no "#478 gap 2 rule 3 negative: decoy gained a caller or the run failed (rc=$rc): $( cat "$TMP/pa.other" )"
fi

# every imp call above ran and answered (see imp): one that did not is a FAIL even where its arm compared equal.
NIMP="$( wc -l <"$TMP/imp.calls" 2>/dev/null | tr -d ' ' )"
if [ "${NIMP:-0}" -eq 0 ]; then no "imp premise: no --impact call was counted (the importer arms saw nothing)"
elif [ -s "$TMP/imp.err" ]; then while IFS= read -r l; do no "imp: --impact did not answer: $l"; done <"$TMP/imp.err"
else ok "imp: all $NIMP --impact calls exited 0 with an <impact> answer"; fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
