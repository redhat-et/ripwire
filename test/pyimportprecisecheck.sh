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
if grep -qa 'import\.names' "$BIN" && grep -qa 'import\.alias' "$BIN"; then
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
    'depth257.py', 'depth258.py'}, 'cut at 257; empty deep container also disclosed'
PY
then ok '#358: clean 255/256 imports kept, 257 cut, and empty 258 nesting still disclosed'
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
