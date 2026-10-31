#!/usr/bin/env bash
# pyimportlayoutcheck.sh — #478 (reported by @jflowers, who built the ground truth on pip): three Python file-graph gaps.
#   gap 4       an absolute `import logging` inside a package never names the sibling logging.py (Python 3 has no implicit
#               relative import). Near miss: a plain script directory keeps its sibling, it is sys.path[0]. Neither the file
#               graph (resolvePythonImport) nor the call graph (resolvePythonModuleSuffix) binds it.
#   src layout  an absolute import may be rooted at `src` beside the includer or an ancestor, or at the source root of the
#               includer's own package chain. Two such roots naming one module degrade to no edge. Outside both shapes: no edge.
#   gap 3       every directory the crawl denylist prunes is rowed in --skipped; a real package (a build-output name with its own
#               __init__.py) is why=pruned-package and is named by --arch and --deps. Vendored junk never is.
# Fixtures are built at runtime. usage: bash test/pyimportlayoutcheck.sh [BIN]   (BIN falls back to RIPWIRE_BIN, then build/ripwire)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
BIN=${1:-${RIPWIRE_BIN:-$HERE/../build/ripwire}}
case "$BIN" in /*) ;; *) BIN=$PWD/$BIN ;; esac
echo "pyimportlayoutcheck: BIN=$BIN"
[ -x "$BIN" ] || { echo "pyimportlayoutcheck: no binary at $BIN"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "pyimportlayoutcheck: python3 required"; exit 2; }
T=$(mktemp -d "${TMPDIR:-/tmp}/pyimportlayoutcheck.XXXXXX")
trap 'rm -rf "$T"' EXIT
fail=0
ok() { echo "PASS $1"; }
no() { echo "FAIL $1"; fail=1; }
w() { mkdir -p "$(dirname "$1")"; printf '%b' "$2" > "$1"; }
printf 'deny path (.*) -> (.*)\n' > "$T/all.rules"
# edges ROOT...: one `from -> to` line per file edge, root-relative. A failed run (no <arch>) is a hard failure, never "no edge".
edges() {
    local out="$T/out.$$.$RANDOM"
    ( cd "$1" && "$BIN" "$@" --no-cache --arch="$T/all.rules" ) > "$out" 2>/dev/null
    grep -q '<arch ' "$out" || { echo "pyimportlayoutcheck: --arch produced no <arch> on $1"; exit 2; }
    python3 -I -c 'import re,sys
root=sys.argv[2]
for a,b in sorted(set(re.findall(r"<v from=\"([^\"]*)\"[^>]*? to=\"([^\"]*)\"", open(sys.argv[1]).read()))):
    print(a.replace(root+"/","")+" -> "+b.replace(root+"/",""))' "$out" "$1"
}
has()  { grep -qxF "$2" <<<"$1"; }
want() { if has "$2" "$3"; then ok "$1: $3"; else no "$1: missing $3"; printf '%s\n' "$2" | sed 's/^/    /'; fi; }
deny() { if has "$2" "$3"; then no "$1: false edge $3"; else ok "$1: no edge $3"; fi; }

# ── gap 4 ────────────────────────────────────────────────────────────────────
G=$T/gap4
w "$G/pkg/__init__.py" ''; w "$G/pkg/utils/__init__.py" ''
w "$G/pkg/utils/worker.py" 'import logging\nimport json\nfrom .helper import h\ndef w():\n    logging.info("x")\n    return h()\n'
w "$G/pkg/utils/logging.py" 'def info(m):\n    return m\n'
w "$G/pkg/utils/json.py" 'def loads(m):\n    return m\n'
w "$G/pkg/utils/helper.py" 'def h():\n    return 1\n'
w "$G/scripts/run.py" 'import helper2\nhelper2.h2()\n'
w "$G/scripts/helper2.py" 'def h2():\n    return 1\n'
E=$(edges "$G")
deny G4.1 "$E" 'pkg/utils/worker.py -> pkg/utils/logging.py'
deny G4.2 "$E" 'pkg/utils/worker.py -> pkg/utils/json.py'
want G4.3-relative-still-binds "$E" 'pkg/utils/worker.py -> pkg/utils/helper.py'
want G4.4-script-dir-near-miss "$E" 'scripts/run.py -> scripts/helper2.py'
C=$( cd "$G" && "$BIN" "$G" --no-cache --callers=info 2>/dev/null )
if grep -q 'count="0"' <<<"$C"; then ok "G4.5 call graph: logging.info() has no caller edge to the sibling"; else no "G4.5 call edge bound to the sibling: $C"; fi
C=$( cd "$G" && "$BIN" "$G" --no-cache --callers=h2 2>/dev/null )
if grep -q 'count="1"' <<<"$C"; then ok "G4.6 script-dir sibling keeps its call edge"; else no "G4.6: $C"; fi

# ── src layout ───────────────────────────────────────────────────────────────
S=$T/srcl
w "$S/src/mypkg/__init__.py" ''; w "$S/src/mypkg/a.py" 'from mypkg.b import fb\nimport logging\n'
w "$S/src/mypkg/b.py" 'def fb():\n    return 1\n'; w "$S/src/mypkg/logging.py" 'x = 1\n'
w "$S/tests/test_a.py" 'import mypkg.a\nfrom mypkg import b\nimport notinrepo.mod\n'
E=$(edges "$S")
want S1.1-in-package "$E" 'src/mypkg/a.py -> src/mypkg/b.py'
want S1.2-tests-into-src "$E" 'tests/test_a.py -> src/mypkg/a.py'
want S1.3-package-init "$E" 'tests/test_a.py -> src/mypkg/__init__.py'
deny S1.4-gap4-under-src "$E" 'src/mypkg/a.py -> src/mypkg/logging.py'

M=$T/mono
w "$M/members/a/src/foo/__init__.py" ''; w "$M/members/a/src/foo/x.py" 'import foo.y\n'; w "$M/members/a/src/foo/y.py" ''
w "$M/members/a/tests/t.py" 'import foo.y\n'
w "$M/members/b/src/foo/__init__.py" ''; w "$M/members/b/src/foo/y.py" ''
w "$M/members/b/tests/t.py" 'import foo.y\n'
E=$(edges "$M")
want S2.1-member-src "$E" 'members/a/tests/t.py -> members/a/src/foo/y.py'
want S2.2-other-member "$E" 'members/b/tests/t.py -> members/b/src/foo/y.py'
deny S2.3-no-cross-member "$E" 'members/a/tests/t.py -> members/b/src/foo/y.py'

N=$T/nonstd
w "$N/lib/mypkg/__init__.py" ''; w "$N/lib/mypkg/a.py" 'import mypkg.b\nimport logging\n'; w "$N/lib/mypkg/b.py" ''
w "$N/lib/mypkg/sub/__init__.py" ''; w "$N/lib/mypkg/sub/c.py" 'from mypkg import a\nimport mypkg.b\n'
w "$N/tests/t.py" 'import mypkg.b\n'
w "$N/examples/logging.py" ''
E=$(edges "$N")
want S3.1-source-root "$E" 'lib/mypkg/a.py -> lib/mypkg/b.py'
want S3.2-deep-chain "$E" 'lib/mypkg/sub/c.py -> lib/mypkg/b.py'
deny S3.3-outside-shape-stays-unresolved "$E" 'tests/t.py -> lib/mypkg/b.py'
deny S3.4-unrelated-namesake "$E" 'lib/mypkg/a.py -> examples/logging.py'

B=$T/both
w "$B/x.py" ''; w "$B/src/x.py" ''; w "$B/src/pkg/__init__.py" ''; w "$B/src/pkg/a.py" 'import x\n'; w "$B/only.py" ''; w "$B/src/pkg/c.py" 'import only\n'
E=$(edges "$B")
deny S4.1-two-roots-degrade "$E" 'src/pkg/a.py -> x.py'
deny S4.2-two-roots-degrade "$E" 'src/pkg/a.py -> src/x.py'
want S4.3-root-alone-still-binds "$E" 'src/pkg/c.py -> only.py'

# two labeled roots with the same shape: an import stays in its own root (checklist 13a)
R1=$T/r/one; R2=$T/r/two
w "$R1/src/p/__init__.py" ''; w "$R1/src/p/m.py" ''; w "$R1/tests/t.py" 'import p.m\n'
w "$R2/src/p/__init__.py" ''; w "$R2/src/p/m.py" ''; w "$R2/tests/t.py" 'import p.m\n'
O=$( cd "$T/r" && "$BIN" "$R1" "$R2" --no-cache --arch="$T/all.rules" 2>/dev/null )
grep -q '<arch ' <<<"$O" || no "S5 multi-root run produced no <arch>"
E=$(python3 -I -c 'import re,sys
for a,b in sorted(set(re.findall(r"<v from=\"([^\"]*)\"[^>]*? to=\"([^\"]*)\"", sys.stdin.read()))): print(a+" -> "+b)' <<<"$O")
if grep -qE 'one/tests/t\.py -> .*one/src/p/m\.py' <<<"$E" && grep -qE 'two/tests/t\.py -> .*two/src/p/m\.py' <<<"$E"; then ok "S5.1 each root binds its own src"; else no "S5.1 multi-root: $E"; fi
if grep -qE 'one/tests/t\.py -> .*two/|two/tests/t\.py -> .*one/' <<<"$E"; then no "S5.2 cross-root edge: $E"; else ok "S5.2 no cross-root edge"; fi

# ── gap 3 ────────────────────────────────────────────────────────────────────
P=$T/gap3
w "$P/pkg/__init__.py" ''; w "$P/pkg/operations/__init__.py" ''; w "$P/pkg/operations/run.py" 'from pkg.operations.build import wheel\n'
w "$P/pkg/operations/build/__init__.py" ''; w "$P/pkg/operations/build/wheel.py" 'def bw():\n    return 1\n'
w "$P/vendor/__init__.py" ''; w "$P/vendor/junk/j.py" ''
w "$P/build/lib/pkg/__init__.py" ''
skipped() { ( cd "$1" && "$BIN" "$1" --no-cache --skipped 2>/dev/null ); }
O=$(skipped "$P")
grep -q 'pruned_dirs="3"' <<<"$O" && ok "P1.0 pruned_dirs=3" || no "P1.0: $(grep -o 'pruned_dirs="[^"]*"' <<<"$O")"
grep -q '<f p="pkg/operations/build" why="pruned-package" bytes="0"' <<<"$O" && ok "P1.1 real package rowed" || no "P1.1"
grep -q '<f p="vendor" why="pruned-dir"' <<<"$O" && ok "P1.2 vendored dir with __init__.py is pruned-dir" || no "P1.2"
grep -q '<f p="build" why="pruned-dir"' <<<"$O" && ok "P1.3 build output (no __init__.py at its top) is pruned-dir" || no "P1.3"
grep -q 'rows_capped' <<<"$O" && no "P1.4 rows_capped on a complete listing" || ok "P1.4 no rows_capped"
for verb in "--deps" "--arch=$T/all.rules"; do
    O=$( cd "$P" && "$BIN" "$P" --no-cache "$verb" 2>/dev/null )
    grep -q '<pruned_packages count="1" shown="1" next="--skipped"[^>]*><p path="pkg/operations/build"/></pruned_packages>' <<<"$O" && ok "P2 ${verb%%=*} names the package" || no "P2 ${verb%%=*}: $(grep -o '<pruned_packages.*</pruned_packages>' <<<"$O")"
    grep -q 'path="vendor"\|path="build"' <<<"$O" && no "P2 ${verb%%=*} names junk" || ok "P2 ${verb%%=*} names no junk"
    if command -v xmllint >/dev/null 2>&1; then
        printf '<r>%s</r>' "$(grep -o '<pruned_packages.*</pruned_packages>' <<<"$O")" | xmllint --noout - 2>/dev/null && ok "P2 ${verb%%=*} block well-formed" || no "P2 ${verb%%=*} malformed"
    fi
done
J=$T/junkonly
w "$J/a.py" ''; w "$J/vendor/__init__.py" ''; w "$J/node_modules/x/__init__.py" ''
O=$( cd "$J" && "$BIN" "$J" --no-cache --deps 2>/dev/null )
grep -q '<deps ' <<<"$O" && ! grep -q 'pruned_packages' <<<"$O" && ok "P3 vendored junk alone: no block" || no "P3"
# the name allowlist cuts one side only: a build-output name without __init__.py
K=$T/many
for i in 1 2 3 4 5 6 7 8 9 10; do w "$K/p$i/__init__.py" ''; w "$K/p$i/build/__init__.py" ''; done
O=$( cd "$K" && "$BIN" "$K" --no-cache --deps 2>/dev/null )
grep -q '<pruned_packages count="10" shown="8" next="--skipped"' <<<"$O" && ok "P4.1 shown cap disclosed by count= shown= next=" || no "P4.1 $(grep -o '<pruned_packages [^>]*' <<<"$O")"
[ "$(grep -o '<p path="' <<<"$O" | wc -l | tr -d ' ')" = 8 ] && ok "P4.2 8 rows" || no "P4.2"
O=$(skipped "$K")
[ "$(grep -o 'why="pruned-package"' <<<"$O" | wc -l | tr -d ' ')" = 10 ] && ok "P4.3 --skipped holds all 10" || no "P4.3"
# the row cap: 501 pruned dirs is disclosed, not silent
Z=$T/rowcap
w "$Z/a.py" ''
python3 -I -c 'import os,sys
for i in range(501): os.makedirs(f"{sys.argv[1]}/d{i:03d}/vendor")' "$Z"
O=$(skipped "$Z")
grep -q 'pruned_dirs="501"' <<<"$O" && grep -q 'rows_capped="1"' <<<"$O" && [ "$(grep -o 'why="pruned-dir"' <<<"$O" | wc -l | tr -d ' ')" = 500 ] && ok "P5 row cap: count exact, rows_capped=1, 500 rows" || no "P5 $(grep -o 'pruned_dirs="[^"]*"\|rows_capped="[^"]*"' <<<"$O" | tr '\n' ' ')"
# a warm cache must not lose the rows
CC=$T/cc
( cd "$P" && "$BIN" "$P" --cache="$CC" --skipped >/dev/null 2>&1 )
O=$( cd "$P" && "$BIN" "$P" --cache="$CC" --skipped 2>/dev/null )
grep -q 'why="pruned-package"' <<<"$O" && ok "P6 warm cache keeps the rows" || no "P6 warm cache lost the rows"
O=$( cd "$P" && "$BIN" "$P" --cache="$CC" --deps 2>/dev/null )
grep -q '<pruned_packages count="1"' <<<"$O" && ok "P6.1 warm cache keeps the --deps block" || no "P6.1"

[ "$fail" = 0 ] && { echo "pyimportlayoutcheck: PASS"; exit 0; }
echo "pyimportlayoutcheck: FAIL"; exit 1
