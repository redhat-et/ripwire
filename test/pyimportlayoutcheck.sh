#!/usr/bin/env bash
# pyimportlayoutcheck.sh — #478 (reported by @jflowers, who built the ground truth on pip): three Python file-graph gaps.
#   gap 4       an absolute `import logging` inside a package never names the sibling logging.py (Python 3 has no implicit
#               relative import). Near miss: a plain script directory keeps its sibling, it is sys.path[0]. Neither the file
#               graph (resolvePythonImport) nor the call graph (resolvePythonModuleSuffix) binds it.
#   src layout  an absolute import may be rooted at `src` beside the includer or an ancestor, or at the source root of the
#               includer's own package chain, as a FALLBACK: the repo root and a plain script directory are probed first and win
#               over a layout root's namesake; two layout roots naming one module degrade to no edge. Outside both shapes: no
#               edge. A `src` that is a package, or sits inside one, is not a root. A stdlib-named first segment does not bind
#               through a layout root (pythonstdlib.h), except at a root that holds the stdlib itself (cpython Lib/). The call
#               graph reads the same rules and keeps a root labelled `src` from binding another root.
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
# callkind ROOT SYM PATH-PREFIX [ROOT...]: how --callers=SYM reports its caller row under PATH-PREFIX: firm (no via=), name (via="name"), none.
callkind() {
    local o row r=$1 sym=$2 pre=$3; shift 3
    [ $# -gt 0 ] || set -- "$r"
    o=$( cd "$r" && "$BIN" "$@" --no-cache --callers="$sym" 2>/dev/null )
    row=$(grep -o "<s [^>]*p=\"[^\"]*$pre[^\"]*\"[^>]*>" <<<"$o" | head -1)
    if [ -z "$row" ]; then echo none; elif grep -q 'via="name"' <<<"$row"; then echo name; else echo firm; fi
}
wantkind() { local got; got=$(callkind "$2" "$3" "$4" "${@:6}"); if [ "$got" = "$5" ]; then ok "$1: $3 caller under $4 is $5"; else no "$1: $3 caller under $4 is $got, want $5"; fi; }
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
want S4.1-root-module-wins-over-src-namesake "$E" 'src/pkg/a.py -> x.py'
deny S4.2-src-namesake-loses "$E" 'src/pkg/a.py -> src/x.py'
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

# ── fix round 1: the layout roots are a FALLBACK, and a package `src` is not a root ───────────────────────────────────────
LG='def info(m):\n    return m\n'
# F1: a `src` holding __init__.py is a package. Non-stdlib names (utils) so the stdlib guard cannot be what answers.
KP=$T/srcpkg
w "$KP/src/__init__.py" ''; w "$KP/src/utils.py" 'def uu():\n    return 1\n'; w "$KP/src/logging.py" "$LG"
w "$KP/src/train.py" 'import utils\nimport logging\ndef tr():\n    utils.uu()\n'
w "$KP/scripts/run.py" 'from utils import uu\nimport logging\ndef r():\n    uu()\n'; w "$KP/tests/test_a.py" 'import utils\nimport logging\n'
w "$KP/run.py" 'from src.train import tr\n'
w "$KP/mypkg/__init__.py" ''; w "$KP/mypkg/src/__init__.py" ''; w "$KP/mypkg/src/utils2.py" ''; w "$KP/mypkg/a.py" 'import utils2\n'
w "$KP/mypkg/sub/__init__.py" ''; w "$KP/mypkg/sub/b.py" 'import utils2\n'
w "$KP/pk2/__init__.py" ''; w "$KP/pk2/src/utils3.py" ''; w "$KP/pk2/a.py" 'import utils3\n'
E=$(edges "$KP")
deny K1.1-script-not-through-package-src "$E" 'scripts/run.py -> src/utils.py'
deny K1.2-test-not-through-package-src "$E" 'tests/test_a.py -> src/utils.py'
deny K1.3-stdlib-name-too "$E" 'tests/test_a.py -> src/logging.py'
deny K1.4-gap4-inside-package-src "$E" 'src/train.py -> src/utils.py'
deny K1.5-gap4-inside-package-src-stdlib "$E" 'src/train.py -> src/logging.py'
want K1.6-dotted-import-of-package-src-still-binds "$E" 'run.py -> src/train.py'
deny K1.7-src-inside-a-package "$E" 'mypkg/a.py -> mypkg/src/utils2.py'
deny K1.8-src-inside-a-package-deeper "$E" 'mypkg/sub/b.py -> mypkg/src/utils2.py'
deny K1.8b-plain-src-inside-a-package "$E" 'pk2/a.py -> pk2/src/utils3.py'
wantkind K1.9-call-graph "$KP" uu scripts/run.py name
KN=$T/srcplain
w "$KN/src/utils.py" 'def uu():\n    return 1\n'; w "$KN/scripts/run.py" 'from utils import uu\ndef r():\n    uu()\n'; w "$KN/tests/test_a.py" 'import utils\n'
w "$KN/src/train.py" 'import utils\n'
E=$(edges "$KN")
want K1.10-near-miss-plain-src-is-a-root "$E" 'tests/test_a.py -> src/utils.py'
want K1.11-near-miss-plain-src-is-a-root "$E" 'scripts/run.py -> src/utils.py'
want K1.12-near-miss-plain-src-sibling "$E" 'src/train.py -> src/utils.py'
wantkind K1.13-near-miss-call-graph "$KN" uu scripts/run.py firm

# F3: probe the layout roots only when the repo root and a plain script directory found nothing
KF=$T/fallback
w "$KF/tests/helpers.py" 'def hh():\n    return 1\n'; w "$KF/src/helpers.py" 'def hh():\n    return 2\n'; w "$KF/tests/test_a.py" 'from helpers import hh\ndef t():\n    hh()\n'
w "$KF/scripts/helpers.py" 'def hh():\n    return 3\n'; w "$KF/scripts/run.py" 'import helpers\nhelpers.hh()\n'
w "$KF/tools/cfg.py" ''; w "$KF/src/cfg.py" ''; w "$KF/tools/run.py" 'import cfg\n'
w "$KF/x.py" ''; w "$KF/src/x.py" ''; w "$KF/main.py" 'import x\n'; w "$KF/tests/t.py" 'import x\n'
w "$KF/src/only.py" ''; w "$KF/tests/test_b.py" 'import only\n'
E=$(edges "$KF")
want F3.1-test-sibling-wins "$E" 'tests/test_a.py -> tests/helpers.py'
deny F3.2-test-sibling-wins "$E" 'tests/test_a.py -> src/helpers.py'
want F3.3-script-sibling-wins "$E" 'scripts/run.py -> scripts/helpers.py'
want F3.4-tools-sibling-wins "$E" 'tools/run.py -> tools/cfg.py'
want F3.5-root-module-wins-for-root-script "$E" 'main.py -> x.py'
want F3.6-root-module-wins-for-test "$E" 'tests/t.py -> x.py'
deny F3.7-no-src-namesake "$E" 'main.py -> src/x.py'
want F3.8-near-miss-fallback-still-binds "$E" 'tests/test_b.py -> src/only.py'
wantkind F3.9-call-graph "$KF" hh tests/test_a.py firm
wantkind F3.10-call-graph-script "$KF" hh scripts/run.py firm

# F2: a stdlib-named FIRST segment never binds through a layout root
ST=$T/stdlibname
w "$ST/src/logging.py" "$LG"; w "$ST/src/app.py" 'import logging\n'
w "$ST/pkg/__init__.py" ''; w "$ST/pkg/a.py" 'import logging\nimport json.decoder\n'; w "$ST/src/json/__init__.py" ''; w "$ST/src/json/decoder.py" ''
w "$ST/tests/test_a.py" 'import logging\n'; w "$ST/tools/gen.py" 'import logging\n'
w "$ST/scripts/logging.py" "$LG"; w "$ST/scripts/run.py" 'import logging\n'
w "$ST/src/mylib/__init__.py" ''; w "$ST/src/mylib/logging.py" "$LG"; w "$ST/tests/test_m.py" 'from mylib.logging import info\n'
w "$ST/src/dataclasses.py" 'def field():\n    return 1\n'; w "$ST/other/o.py" 'from dataclasses import field\ndef g():\n    return field()\n'
E=$(edges "$ST")
deny F2.1-pkg-stdlib-name "$E" 'pkg/a.py -> src/logging.py'
deny F2.2-test-stdlib-name "$E" 'tests/test_a.py -> src/logging.py'
deny F2.3-tool-stdlib-name "$E" 'tools/gen.py -> src/logging.py'
deny F2.4-first-segment-only "$E" 'pkg/a.py -> src/json/decoder.py'
want F2.6-near-miss-plain-dir-sibling "$E" 'src/app.py -> src/logging.py'
want F2.7-near-miss-script-dir-shadow "$E" 'scripts/run.py -> scripts/logging.py'
want F2.8-near-miss-stdlib-name-not-first "$E" 'tests/test_m.py -> src/mylib/logging.py'
wantkind F2.10-call-graph "$ST" field other/o.py name
SR=$T/stdlibchain
w "$SR/lib/mypkg/__init__.py" ''; w "$SR/lib/mypkg/a.py" 'import logging\nimport mypkg.b\n'; w "$SR/lib/mypkg/b.py" ''; w "$SR/lib/logging.py" "$LG"
E=$(edges "$SR")
deny F2.5-chain-root-stdlib-name "$E" 'lib/mypkg/a.py -> lib/logging.py'
want F2.9-near-miss-chain-root-non-stdlib "$E" 'lib/mypkg/a.py -> lib/mypkg/b.py'
CP=$T/stdlibroot
w "$CP/Lib/os.py" ''; w "$CP/Lib/importlib/__init__.py" ''; w "$CP/Lib/re/__init__.py" ''; w "$CP/Lib/json/__init__.py" ''
w "$CP/Lib/json/decoder.py" 'import re\nimport importlib\n'; w "$CP/Lib/test/__init__.py" ''; w "$CP/Lib/test/test_x.py" 'import os\n'
w "$CP/lib2/os.py" ''; w "$CP/lib2/mypkg/__init__.py" ''; w "$CP/lib2/mypkg/a.py" 'import os\n'
E=$(edges "$CP")
want F2.11-stdlib-root-exempt "$E" 'Lib/json/decoder.py -> Lib/re/__init__.py'
want F2.12-stdlib-root-exempt "$E" 'Lib/json/decoder.py -> Lib/importlib/__init__.py'
want F2.13-stdlib-root-exempt "$E" 'Lib/test/test_x.py -> Lib/os.py'
deny F2.14-near-miss-os-alone-is-not-the-stdlib "$E" 'lib2/mypkg/a.py -> lib2/os.py'

# F4: a root LABELLED `src` is not reachable from another root in the call graph (the file graph already refuses it)
MR=$T/labelsrc
w "$MR/a/src/helperlib.py" 'def hl():\n    return 1\n'; w "$MR/a/src/lp/__init__.py" ''; w "$MR/a/src/lp/m.py" 'def lm():\n    return 1\n'
w "$MR/b/tools/t.py" 'import helperlib\nfrom lp.m import lm\ndef w():\n    helperlib.hl()\n    lm()\n'
wantkind F4.1-no-cross-root-call-edge "$MR" hl tools/t.py none "$MR/a/src" "$MR/b/tools"
w "$MR/a/src/own.py" 'from lp.m import lm\ndef o():\n    lm()\n'
wantkind F4.3-near-miss-own-root-still-binds "$MR" lm own.py firm "$MR/a/src" "$MR/b/tools"
# D1: a package importing ITSELF is decided at its own chain root: no stdlib guard, no repo-root namesake in the way. A non-self importer stays
# unresolved (its run mode is unknowable). Stdlib-named (email) and non-stdlib-named (foo, mytool) packages.
DE=$T/selfemail
w "$DE/src/email/__init__.py" ''; w "$DE/src/email/templates.py" 'def tp():\n    return 1\n'
w "$DE/src/email/sender.py" 'from email.templates import tp\nimport email.utils\ndef send():\n    tp()\n'
w "$DE/src/api/__init__.py" ''; w "$DE/src/api/routes.py" 'from email.sender import send\nimport logging\n'; w "$DE/src/logging.py" "$LG"
w "$DE/tests/test_e.py" 'from email.sender import send\n'
E=$(edges "$DE")
want D1.1-stdlib-named-package-imports-itself "$E" 'src/email/sender.py -> src/email/templates.py'
deny D1.2-non-self-importer-stays-dropped "$E" 'src/api/routes.py -> src/email/sender.py'
deny D1.3-test-importer-stays-dropped "$E" 'tests/test_e.py -> src/email/sender.py'
deny D1.4-near-miss-other-stdlib-name-stays-guarded "$E" 'src/api/routes.py -> src/logging.py'
wantkind D1.5-call-graph-self-import "$DE" tp src/email/sender.py firm
DR=$T/selfroot
w "$DR/foo/__init__.py" ''; w "$DR/foo/a.py" 'def fa():\n    return 1\n'; w "$DR/foo/b.py" 'from foo.a import fa\n'
w "$DR/src/foo/__init__.py" ''; w "$DR/src/foo/a.py" 'def fa():\n    return 2\n'; w "$DR/src/foo/b.py" 'from foo.a import fa\n'
w "$DR/tests/t.py" 'import foo.a\n'; w "$DR/src/foo/sub/__init__.py" ''; w "$DR/src/foo/sub/d.py" 'import foo.a\n'
w "$DR/mytool.py" 'from mytool.cli import main\n'; w "$DR/src/mytool/__init__.py" ''; w "$DR/src/mytool/cli.py" 'def main():\n    return 1\n'
w "$DR/src/mytool/core.py" 'import mytool\nfrom mytool import cli\n'
w "$DR/bar/bar.py" ''; w "$DR/src/bar/__init__.py" ''; w "$DR/src/bar/bar.py" ''; w "$DR/src/bar/c.py" 'import bar.bar\n'
E=$(edges "$DR")
want D1.6-self-beats-root-namesake "$E" 'src/foo/b.py -> src/foo/a.py'
deny D1.7-self-beats-root-namesake "$E" 'src/foo/b.py -> foo/a.py'
want D1.7b-nested-module-names-its-top-package "$E" 'src/foo/sub/d.py -> src/foo/a.py'
want D1.8-near-miss-root-package-still-binds-itself "$E" 'foo/b.py -> foo/a.py'
want D1.9-near-miss-test-keeps-root-tier "$E" 'tests/t.py -> foo/a.py'
want D1.10-self-beats-root-script-namesake "$E" 'src/mytool/core.py -> src/mytool/__init__.py'
want D1.11-near-miss-root-script-keeps-its-fallback "$E" 'mytool.py -> src/mytool/cli.py'
want D1.12-self-beats-root-namespace-portion "$E" 'src/bar/c.py -> src/bar/bar.py'
deny D1.13-self-beats-root-namespace-portion "$E" 'src/bar/c.py -> bar/bar.py'
# D2: `__main__` is in no path (it is the running program), so it is guarded like a stdlib name; a plain script sibling still binds
DM=$T/dunder
w "$DM/src/__main__.py" ''; w "$DM/src/pk/__init__.py" ''; w "$DM/src/pk/a.py" 'import __main__\n'; w "$DM/tests/t.py" 'import __main__\n'
w "$DM/scripts/__main__.py" ''; w "$DM/scripts/run.py" 'import __main__\n'
E=$(edges "$DM")
deny D2.1-main-not-through-layout-root "$E" 'tests/t.py -> src/__main__.py'
deny D2.2-main-not-through-chain-root "$E" 'src/pk/a.py -> src/__main__.py'
want D2.3-near-miss-script-sibling "$E" 'scripts/run.py -> scripts/__main__.py'
# D5: the stdlib-root marker is os.py AND importlib/__init__.py; a backport holding only importlib/ is not the stdlib
DB=$T/importlibbackport
w "$DB/src/importlib/__init__.py" ''; w "$DB/src/logging.py" "$LG"; w "$DB/pkg/__init__.py" ''; w "$DB/pkg/a.py" 'import logging\n'
E=$(edges "$DB")
deny D5.1-importlib-alone-is-not-the-stdlib "$E" 'pkg/a.py -> src/logging.py'
# call-graph twins of the src-layout arms (S1, S3, S5 read --arch only)
SC=$T/callsrc
w "$SC/src/mypkg/__init__.py" ''; w "$SC/src/mypkg/m.py" 'def fm():\n    return 1\n'; w "$SC/tests/test_m.py" 'from mypkg.m import fm\ndef t():\n    fm()\n'
w "$SC/lib/lp/__init__.py" ''; w "$SC/lib/lp/b.py" 'def fb():\n    return 1\n'; w "$SC/lib/lp/sub/__init__.py" ''; w "$SC/lib/lp/sub/c.py" 'from lp.b import fb\ndef c():\n    fb()\n'
wantkind S1.5-call-graph-tests-into-src "$SC" fm tests/test_m.py firm
wantkind S3.5-call-graph-chain-root "$SC" fb lib/lp/sub/c.py firm
R3=$T/r3/one; R4=$T/r3/two
for r in "$R3" "$R4"; do w "$r/src/p/__init__.py" ''; w "$r/src/p/m.py" 'def pm():\n    return 1\n'; w "$r/tests/t.py" 'from p.m import pm\ndef t():\n    pm()\n'; done
wantkind S5.3-call-graph-own-root-one "$T/r3" pm one/tests/t.py firm "$R3" "$R4"
wantkind S5.4-call-graph-own-root-two "$T/r3" pm two/tests/t.py firm "$R3" "$R4"

# ── gap 3 ────────────────────────────────────────────────────────────────────
P=$T/gap3
w "$P/pkg/__init__.py" ''; w "$P/pkg/operations/__init__.py" ''; w "$P/pkg/operations/run.py" 'from pkg.operations.build import wheel\n'
w "$P/pkg/operations/build/__init__.py" ''; w "$P/pkg/operations/build/wheel.py" 'def bw():\n    return 1\n'
w "$P/vendor/__init__.py" ''; w "$P/vendor/junk/j.py" ''
w "$P/build/lib/pkg/__init__.py" ''
skipped() { ( cd "$1" && "$BIN" "$1" --no-cache --skipped 2>/dev/null ); }
O=$(skipped "$P")
if grep -q 'pruned_dirs="3"' <<<"$O"; then ok "P1.0 pruned_dirs=3"; else no "P1.0: $(grep -o 'pruned_dirs="[^"]*"' <<<"$O")"; fi
if grep -q '<f p="pkg/operations/build" why="pruned-package" bytes="0"' <<<"$O"; then ok "P1.1 real package rowed"; else no "P1.1"; fi
if grep -q '<f p="vendor" why="pruned-dir"' <<<"$O"; then ok "P1.2 vendored dir with __init__.py is pruned-dir"; else no "P1.2"; fi
if grep -q '<f p="build" why="pruned-dir"' <<<"$O"; then ok "P1.3 build output (no __init__.py at its top) is pruned-dir"; else no "P1.3"; fi
if grep -q 'rows_capped' <<<"$O"; then no "P1.4 rows_capped on a complete listing"; else ok "P1.4 no rows_capped"; fi
for verb in "--deps" "--arch=$T/all.rules"; do
    O=$( cd "$P" && "$BIN" "$P" --no-cache "$verb" 2>/dev/null )
    if grep -q '<pruned_packages count="1" shown="1" next="--skipped"[^>]*><p path="pkg/operations/build"/></pruned_packages>' <<<"$O"; then ok "P2 ${verb%%=*} names the package"; else no "P2 ${verb%%=*}: $(grep -o '<pruned_packages.*</pruned_packages>' <<<"$O")"; fi
    if grep -q 'path="vendor"\|path="build"' <<<"$O"; then no "P2 ${verb%%=*} names junk"; else ok "P2 ${verb%%=*} names no junk"; fi
    # the block is defined where it is read: a compact row keyed by count= on the element, a clause in the full legend
    if grep -q 'pruned_packages count=N: real packages' <<<"$O"; then ok "P2 ${verb%%=*} compact legend defines the block"; else no "P2 ${verb%%=*} compact legend: no pruned_packages definition"; fi
    OF=$( cd "$P" && "$BIN" "$P" --no-cache "$verb" --legend=full 2>/dev/null )
    if grep -q '<pruned_packages count=N shown=M next= note=>' <<<"$OF"; then ok "P2 ${verb%%=*} full legend defines the block"; else no "P2 ${verb%%=*} full legend: no pruned_packages clause"; fi
    if command -v xmllint >/dev/null 2>&1; then
        if printf '<r>%s</r>' "$(grep -o '<pruned_packages.*</pruned_packages>' <<<"$O")" | xmllint --noout - 2>/dev/null; then ok "P2 ${verb%%=*} block well-formed"; else no "P2 ${verb%%=*} malformed"; fi
    fi
done
J=$T/junkonly
w "$J/a.py" ''; w "$J/vendor/__init__.py" ''; w "$J/node_modules/x/__init__.py" ''
O=$( cd "$J" && "$BIN" "$J" --no-cache --deps 2>/dev/null )
if grep -q '<deps ' <<<"$O" && ! grep -q 'pruned_packages' <<<"$O"; then ok "P3 vendored junk alone: no block"; else no "P3"; fi
OF=$( cd "$J" && "$BIN" "$J" --no-cache --deps --legend=full 2>/dev/null )
if ! grep -q 'pruned_packages' <<<"$OF"; then ok "P3.1 vendored junk alone: no clause either"; else no "P3.1"; fi
if "$BIN" --help=skipped 2>&1 | grep -q 'why=pruned-package'; then ok "P3.2 --skipped help names why=pruned-package"; else no "P3.2 help lacks the new why"; fi
# the name allowlist cuts one side only: a build-output name without __init__.py
K=$T/many
for i in 1 2 3 4 5 6 7 8 9 10; do w "$K/p$i/__init__.py" ''; w "$K/p$i/build/__init__.py" ''; done
O=$( cd "$K" && "$BIN" "$K" --no-cache --deps 2>/dev/null )
if grep -q '<pruned_packages count="10" shown="8" next="--skipped"' <<<"$O"; then ok "P4.1 shown cap disclosed by count= shown= next="; else no "P4.1 $(grep -o '<pruned_packages [^>]*' <<<"$O")"; fi
if [ "$(grep -o '<p path="' <<<"$O" | wc -l | tr -d ' ')" = 8 ]; then ok "P4.2 8 rows"; else no "P4.2"; fi
O=$(skipped "$K")
if [ "$(grep -o 'why="pruned-package"' <<<"$O" | wc -l | tr -d ' ')" = 10 ]; then ok "P4.3 --skipped holds all 10"; else no "P4.3"; fi
# the row cap: 501 pruned dirs is disclosed, not silent
Z=$T/rowcap
w "$Z/a.py" ''
python3 -I -c 'import os,sys
for i in range(501): os.makedirs(f"{sys.argv[1]}/d{i:03d}/vendor")' "$Z"
O=$(skipped "$Z")
if grep -q 'pruned_dirs="501"' <<<"$O" && grep -q 'rows_capped="1"' <<<"$O" && [ "$(grep -o 'why="pruned-dir"' <<<"$O" | wc -l | tr -d ' ')" = 500 ]; then ok "P5 row cap: count exact, rows_capped=1, 500 rows"; else no "P5 $(grep -o 'pruned_dirs="[^"]*"\|rows_capped="[^"]*"' <<<"$O" | tr '\n' ' ')"; fi
# a warm cache must not lose the rows
CC=$T/cc
( cd "$P" && "$BIN" "$P" --cache="$CC" --skipped >/dev/null 2>&1 )
O=$( cd "$P" && "$BIN" "$P" --cache="$CC" --skipped 2>/dev/null )
if grep -q 'why="pruned-package"' <<<"$O"; then ok "P6 warm cache keeps the rows"; else no "P6 warm cache lost the rows"; fi
O=$( cd "$P" && "$BIN" "$P" --cache="$CC" --deps 2>/dev/null )
if grep -q '<pruned_packages count="1"' <<<"$O"; then ok "P6.1 warm cache keeps the --deps block"; else no "P6.1"; fi

if [ "$fail" = 0 ]; then echo "pyimportlayoutcheck: PASS"; exit 0; fi
echo "pyimportlayoutcheck: FAIL"; exit 1
