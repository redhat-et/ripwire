#!/usr/bin/env bash
# build.sh DIR — writes the three fixtures affectedfoldcheck.sh reads, deterministically, under DIR:
#   big/    a python + typescript tree whose --affected answer lists 50+ test files in nested directories at two hop
#           depths (the fold fires), one path with a space (a quoted-command hold-out, single row);
#   small/  three sibling tests (the fold is below the document bar: the answer must not move);
#   odd/    names that stress the writer: an XML-escaped directory (a&b), a file whose whole name is another's suffix
#           (x.py beside x.y.py and sub/x.py), a directory and a file sharing a stem (sub/ and sub.py), a deep chain;
#   brace/  big's shape with one directory literally named {{tpl}} at hops=2 (that row keeps p=, the others fold).
# The goldens under golden/ were captured from the binary BEFORE the fold (994f0021f) on exactly these bytes.
set -eu
D="$1"
py_test(){ # file  import-module  callee  name
    mkdir -p "$( dirname "$1" )"
    printf 'from %s import %s\n\n\ndef test_%s():\n    assert %s(1) is not None\n' "$2" "$3" "$4" "$3" > "$1"
}
py_lib(){ # root
    mkdir -p "$1/pkg"
    printf 'def core_value(x):\n    return x + 1\n' > "$1/pkg/core.py"
    printf 'from pkg.core import core_value\n\n\ndef mid_value(x):\n    return core_value(x) * 2\n' > "$1/pkg/mid.py"
}
# ── big (a pytest project: its python rows carry run_each="pytest {p}", its typescript rows run_unknown)
py_lib "$D/big"; printf "[pytest]\n" > "$D/big/pytest.ini"
for i in 01 02 03 04 05 06 07 08 09 10; do py_test "$D/big/tests/unit/alpha/test_a$i.py" pkg.core core_value "a$i"; done
for i in 01 02 03 04 05 06 07 08;       do py_test "$D/big/tests/unit/beta/test_b$i.py"  pkg.core core_value "b$i"; done
for i in 1 2 3;                         do py_test "$D/big/tests/unit/test_top$i.py"     pkg.core core_value "top$i"; done
py_test "$D/big/tests/unit/my dir/test_sp1.py" pkg.core core_value sp1
for i in 01 02 03 04 05 06;             do py_test "$D/big/tests/integration/api/test_api$i.py" pkg.mid mid_value "api$i"; done
for i in 1 2 3 4;                       do py_test "$D/big/tests/integration/test_flow$i.py"    pkg.mid mid_value "flow$i"; done
py_test "$D/big/tests/zeta_only.py" pkg.mid mid_value zeta
mkdir -p "$D/big/web/__tests__/deep"
printf 'export function webValue( x: number ): number\n{\n    return x + 1;\n}\n' > "$D/big/web/lib.ts"
for i in 1 2 3 4 5 6 7 8; do
    printf "import { webValue } from '../lib';\n\nexport function checkX%s(): number\n{\n    return webValue( %s );\n}\n" "$i" "$i" > "$D/big/web/__tests__/x$i.test.ts"
done
for i in 1 2 3 4; do
    printf "import { webValue } from '../../lib';\n\nexport function checkY%s(): number\n{\n    return webValue( %s );\n}\n" "$i" "$i" > "$D/big/web/__tests__/deep/y$i.spec.ts"
done
# ── small
py_lib "$D/small"
for i in 1 2 3; do py_test "$D/small/tests/test_s$i.py" pkg.core core_value "s$i"; done
# ── brace
py_lib "$D/brace"
for i in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16; do py_test "$D/brace/tests/unit/alpha/test_a$i.py" pkg.core core_value "a$i"; done
for i in 01 02 03 04 05 06 07 08;                         do py_test "$D/brace/tests/unit/beta/test_b$i.py"  pkg.core core_value "b$i"; done
for i in 1 2 3 4 5 6; do py_test "$D/brace/{{tpl}}/tests/test_t$i.py" pkg.mid mid_value "t$i"; done
# ── odd
py_lib "$D/odd"
L="tests/a_rather_long_directory_name_so_the_fold_pays"
for n in x x.y x.y.z sub; do py_test "$D/odd/$L/$n.py" pkg.core core_value "o1"; done
for n in x w.y; do py_test "$D/odd/$L/sub/$n.py" pkg.core core_value "o2"; done
for i in 1 2 3; do py_test "$D/odd/$L/a&b/test_$i.spec.py" pkg.core core_value "o3$i"; done
for i in 1 2; do py_test "$D/odd/$L/deep/er/still/test_d$i.py" pkg.core core_value "o4$i"; done
py_test "$D/odd/$L/deep/er/other.py" pkg.core core_value o5
for i in 1 2 3 4; do py_test "$D/odd/tests_flat_$i/only.py" pkg.core core_value "o6$i"; done
