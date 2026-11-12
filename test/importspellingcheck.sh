#!/usr/bin/env bash
# importspellingcheck.sh — lane import-spelling (B29; Opus ideas C2 IMPORT-SPELLING / REEXPORT-SPEC, Fable IMPORT-SPEC-TRACE): a --for
# task that SPELLS an import (`NAME imported from @scope/pkg/sub`, `NAME from pkg/sub`, `from a.b import NAME`, a dotted `a.b.NAME`)
# gets the chain FROM the spelling inside <reexports> (src/forimportspec.h, src/forreexport.h renderImportSpecBlock): the spec
# resolved to its entry file through the in-tree package.json `name` + `exports` (Python: the module file), then each statement
# that hands NAME on, followed to the definition.
#
# Before the lane: the parse took the cue word (`imported`) as the name, the package was the spec's LAST segment as a directory
# (`@acme/core/internal` -> an `internal/` directory), and the definition-side walk stopped silently where `./di` names both
# `di.ts` and `di/` (tsc reads the file). An external spelling whose last segment matched an in-tree directory printed that tree's
# chain (a guess).
#
# The fixture is generated at test time. Arms:
#   S1  `inject imported from @acme/core`: spec row (package.json, entry index.ts), the def, and the five hops index.ts ->
#       public_api.ts -> src/core.ts (`./di` = di.ts, not di/index.ts) -> src/di.ts -> src/di/index.ts, in import order.
#   S2  `Widget type imported from @acme/core/internal`: the subpath's exports key line, entry internal.ts, the interface two hops
#       away; the same-named decorator (src/widget.decorator.ts) is not in the block.
#   S3  `signToken from hx/jwt`: exports target ./dist/middleware/jwt/index.js mapped to src/middleware/jwt/index.ts; the aliased
#       re-export `sign as signToken` is a row as="signToken" and the def is `sign`.
#   S6  VALUE-HOP (increment 2): `verify from hv/jwt` where middleware/jwt/jwt.ts does `export const verify = Jwt.verify` and
#       utils/jwt/index.ts `export const Jwt = { sign, verify }` over `import { sign, verify } from './jwt'`: two val= rows, then
#       the function in utils/jwt/jwt.ts.
#   S4  card (c) on the definition-side walk: `where injectAll is defined` reaches src/core.ts, public_api.ts and index.ts.
#   S5  Python: `where acme.pkg.Thing is defined` -> `lazy from .impl import Thing` in acme/pkg/__init__.py; `Thing2 imported from
#       acme.pkg` -> the parenthesised `Other as Thing2` (as="Thing2", def Other).
#   S5c a `#` comment inside a parenthesised Python list (CodeRabbit 4550333639): `Thing3`, the name after a commented line,
#       and `Thing4`, the name after a comment holding `)`, each reach their def. Premise, counted: the list has 2 comment lines.
#   N1  external: `inject from lodash/fp` (no in-tree package.json declares lodash and no segment names an in-tree directory or
#       file: graph.h jsModuleIsForeign): external="1" and no rx/def rows. Premise: the fixture defines inject (counted) and the spec
#       row printed. (A spelling that no package.json declares but whose segment names the tree, `@fix/m` for a directory m/, keeps
#       the definition-side rule of test/reexportcheck.sh P1.)
#   N2  ambiguous: `Gadget from @acme/dup` (two package.json files declare @acme/dup, two Gadget defs): cands="2", no def/rx row.
#   N3  RIPWIRE_NO_IMPORT_SPEC=1 prints no spec row; a task with no spelled import is byte-identical with and without it.
#   N4  every answer is well-formed XML (xmllint, when present).
#   N5  an unreadable manifest is no verdict (CodeRabbit 4542271940): `gizmo imported from @acme/unread` where the one package.json
#       that declares @acme/unread is chmod 000 prints no external="1" and no spec row (the definition-side chains answer, as before).
#       Premise, counted: the same task resolves (p=packages/u/package.json) while the file is readable, and after the chmod the
#       file really is unreadable (SKIP when it is not, e.g. as root).
#   N6  the depth cap discloses (CodeRabbit 4542271958): a 14-statement `export *` chain past kImportSpecDepth (12) prints
#       found="0" WITH capped="1". Premise, counted: a 6-statement chain of the same shape reaches its def (no capped=).
#   N7  a cut the walk can no longer use is no hedge (CodeRabbit 4550333655): a def found at depth 12 beside a sibling that still
#       hands the name on, and a def found at depth 1 beside 300 depth-2 statements past kImportSpecMaxStates, print no capped=.
#       Premise, counted: the depth-12 sibling hop and the 300 statements exist.
#
# Usage: bash test/importspellingcheck.sh [BIN]     (default build/ripwire; exits non-zero on any failure)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
FIX="$TMP/fx"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "FAIL: no binary at $BIN"; exit 1; }
echo "importspellingcheck: $( "$BIN" --version 2>/dev/null )"

mkdir -p "$FIX"
w(){ mkdir -p "$FIX/$( dirname "$1" )"; printf '%s\n' "$2" > "$FIX/$1"; }
w package.json '{ "name": "acme-root", "private": true }'
# a scoped package: the root entry walks index -> public_api -> src/core -> ./di (file beside a directory) -> di/index -> def
w packages/core/package.json '{
  "name": "@acme/core",
  "exports": {
    ".": "./index.js",
    "./internal": "./internal.js"
  }
}'
w packages/core/index.ts "export * from './public_api';"
w packages/core/public_api.ts "export * from './src/core';"
w packages/core/src/core.ts "export * from './di';
export * from './widget.decorator';"
w packages/core/src/di.ts "export * from './di/index';"
w packages/core/src/di/index.ts "export {inject, injectAll} from './injector_compatibility';"
w packages/core/src/di/injector_compatibility.ts "export function inject(token: string): string {
  return token;
}
export function injectAll(token: string): string[] {
  return [token];
}"
# the subpath entry: a type re-export two hops from the interface; a same-named decorator is the decoy
w packages/core/internal.ts "export type { Widget } from './interfaces/index.js';"
w packages/core/interfaces/index.ts "export * from './widget.interface.js';"
w packages/core/interfaces/widget.interface.ts "export interface Widget {
  id: string;
}"
w packages/core/src/widget.decorator.ts "export function Widget(): string {
  return 'widget';
}"
w packages/app/src/module.ts "import type { Widget } from '@acme/core/internal';
import { inject } from '@acme/core';
export const made: string = inject('x');
export type W = Widget;"
# a root-named package whose exports name the build output, and an aliased re-export
w packages/hx/package.json '{
  "name": "hx",
  "exports": {
    "./jwt": {
      "types": "./dist/types/middleware/jwt/index.d.ts",
      "import": "./dist/middleware/jwt/index.js"
    }
  }
}'
w packages/hx/src/middleware/jwt/index.ts "export { verify, sign as signToken } from './jwt';"
w packages/hx/src/middleware/jwt/jwt.ts "export function verify(token: string): boolean {
  return token.length > 0;
}
export function sign(payload: string): string {
  return payload + '.sig';
}"
# VALUE-HOP: the subpath's name is a value built from an import (`export const verify = Jwt.verify`, `Jwt = { sign, verify }`)
w packages/hv/package.json '{ "name": "hv", "exports": { "./jwt": "./dist/middleware/jwt/index.js" } }'
w packages/hv/src/middleware/jwt/index.ts "export { verify } from './jwt';"
w packages/hv/src/middleware/jwt/jwt.ts "import { Jwt } from '../../utils/jwt';
export const verify = Jwt.verify;"
w packages/hv/src/utils/jwt/index.ts "import { sign, verify } from './jwt';
export const Jwt = { sign, verify };"
w packages/hv/src/utils/jwt/jwt.ts "export function verify(token: string): boolean {
  return token.length > 1;
}
export function sign(payload: string): string {
  return payload + '.hv';
}"
# two manifests that spell one package name: ambiguous, disclosed
w packages/dup-a/package.json '{ "name": "@acme/dup", "exports": { ".": "./index.js" } }'
w packages/dup-a/index.ts "export function Gadget(): number {
  return 1;
}"
w packages/dup-b/package.json '{ "name": "@acme/dup", "exports": { ".": "./index.js" } }'
w packages/dup-b/index.ts "export function Gadget(): number {
  return 2;
}"
# (no fixture for the external spec: `lodash/fp` names no in-tree package, directory or file)
# Python: a package __init__ that hands names on (PEP 810 lazy, a parenthesised list with a rename)
w py/acme/__init__.py ""
w py/acme/pkg/__init__.py "from .base import (Base,
                   Other as Thing2)
lazy from .impl import Thing"
w py/acme/pkg/impl.py "class Thing:
    pass"
# S5c (CodeRabbit 4550333639): a `#` comment inside the parenthesised list, one plain and one holding a `)`
w py/acme/cmt/__init__.py "from .parts import (
    Plain,  # the plain one
    Hidden as Thing3,  # see f()
    Last as Thing4,
)"
w py/acme/cmt/parts.py "class Plain:
    pass


class Hidden:
    pass


class Last:
    pass"
w py/acme/pkg/base.py "class Base:
    pass


class Other:
    pass"

ask(){ ( cd "$FIX" || exit 1; HOME="$TMP" "$BIN" "$FIX" --no-cache "$@" </dev/null 2>/dev/null ); }
block(){ grep -o '<reexports>.*</reexports>' "$1"; }
has(){ if block "$1" | grep -qF -- "$3"; then ok "$2"; else no "$2 (missing: $3)"; fi; }
hasnt(){ if block "$1" | grep -qF -- "$3"; then no "$2 (present: $3)"; else ok "$2"; fi; }
count(){ block "$1" | grep -oF -- "$2" | wc -l | tr -d ' '; }

ask "--for=where inject imported from @acme/core is defined" >"$TMP/s1.xml"
has "$TMP/s1.xml" "S1 spec row: package.json + entry" '<spec m="@acme/core" n="inject" p="packages/core/package.json" l="4" entry="packages/core/index.ts"/>'
has "$TMP/s1.xml" "S1 the definition the walk reached" '<def n="inject" p="packages/core/src/di/injector_compatibility.ts" l="1" total="5"/>'
has "$TMP/s1.xml" "S1 hops in import order, ./di = di.ts" '<rx p="packages/core/index.ts" l="1" from="./public_api" glob="1"/><rx p="packages/core/public_api.ts" l="1" from="./src/core" glob="1"/><rx p="packages/core/src/core.ts" l="1" from="./di" glob="1"/><rx p="packages/core/src/di.ts" l="1" from="./di/index" glob="1"/><rx p="packages/core/src/di/index.ts" l="1" from="./injector_compatibility"/>'

ask "--for=Widget type imported from @acme/core/internal in packages/app/src/module.ts" >"$TMP/s2.xml"
has "$TMP/s2.xml" "S2 subpath: the exports key line, entry internal.ts" '<spec m="@acme/core/internal" n="Widget" p="packages/core/package.json" l="5" entry="packages/core/internal.ts"/>'
has "$TMP/s2.xml" "S2 the interface, two hops" '<def n="Widget" p="packages/core/interfaces/widget.interface.ts" l="1" total="2"/><rx p="packages/core/internal.ts" l="1" from="./interfaces/index.js"/><rx p="packages/core/interfaces/index.ts" l="1" from="./widget.interface.js" glob="1"/>'
hasnt "$TMP/s2.xml" "S2 the same-named decorator is not in the block" 'widget.decorator.ts'

ask "--for=signToken from hx/jwt" >"$TMP/s3.xml"
has "$TMP/s3.xml" "S3 dist target mapped to its source" 'entry="packages/hx/src/middleware/jwt/index.ts"'
has "$TMP/s3.xml" "S3 the aliased re-export is a row, def sign" '<def n="sign" p="packages/hx/src/middleware/jwt/jwt.ts" l="4" total="1"/><rx p="packages/hx/src/middleware/jwt/index.ts" l="1" from="./jwt" as="signToken"/>'

ask "--for=verify from hv/jwt" >"$TMP/s6.xml"
has "$TMP/s6.xml" "S6 value hops: Jwt.verify, then the object member, to the function" '<def n="verify" p="packages/hv/src/utils/jwt/jwt.ts" l="1" total="3"/><rx p="packages/hv/src/middleware/jwt/index.ts" l="1" from="./jwt"/><rx p="packages/hv/src/middleware/jwt/jwt.ts" l="2" from="../../utils/jwt" val="Jwt.verify"/><rx p="packages/hv/src/utils/jwt/index.ts" l="2" from="./jwt" val="{ verify }"/>'

ask "--for=where injectAll is defined" >"$TMP/s4.xml"
has "$TMP/s4.xml" "S4 definition-side walk passes ./di (file before index)" '<rx p="packages/core/src/core.ts" l="1" from="./di" glob="1"/>'
has "$TMP/s4.xml" "S4 ... and reaches the package entry" '<rx p="packages/core/index.ts" l="1" from="./public_api" glob="1"/>'

ask "--for=where acme.pkg.Thing is defined" >"$TMP/s5.xml"
has "$TMP/s5.xml" "S5 Python lazy from hop" '<spec m="acme.pkg" n="Thing" p="py/acme/pkg/__init__.py" entry="py/acme/pkg/__init__.py"/><def n="Thing" p="py/acme/pkg/impl.py" l="1" total="1"/><rx p="py/acme/pkg/__init__.py" l="3" from=".impl"/>'
ask "--for=Thing2 imported from acme.pkg" >"$TMP/s5b.xml"
has "$TMP/s5b.xml" "S5 Python parenthesised rename" '<def n="Other" p="py/acme/pkg/base.py" l="5" total="1"/><rx p="py/acme/pkg/__init__.py" l="1" from=".base" as="Thing2"/>'
cmts=$( grep -c '^ .*#' "$FIX/py/acme/cmt/__init__.py" )
ask "--for=Thing3 imported from acme.cmt" >"$TMP/s5c.xml"
ask "--for=Thing4 imported from acme.cmt" >"$TMP/s5d.xml"
if [ "$cmts" = 2 ]; then
    has "$TMP/s5c.xml" "S5c a comment in the list does not swallow the next name" '<def n="Hidden" p="py/acme/cmt/parts.py" l="5" total="1"/><rx p="py/acme/cmt/__init__.py" l="1" from=".parts" as="Thing3"/>'
    has "$TMP/s5d.xml" "S5c a \`)\` in a comment does not end the list" '<def n="Last" p="py/acme/cmt/parts.py" l="9" total="1"/><rx p="py/acme/cmt/__init__.py" l="1" from=".parts" as="Thing4"/>'
    hasnt "$TMP/s5c.xml" "S5c no found=0 for the commented list" 'found="0"'
    hasnt "$TMP/s5d.xml" "S5c no found=0 past the commented \`)\`" 'found="0"'
else no "S5c premise: the fixture list carries $cmts comment lines (want 2)"; fi

ask "--for=inject from lodash/fp" >"$TMP/n1.xml"
defs=$( grep -rl 'export function inject(' "$FIX/packages" | wc -l | tr -d ' ' )
spec=$( count "$TMP/n1.xml" '<spec m="lodash/fp" n="inject" external="1"/>' )
rows=$(( $( count "$TMP/n1.xml" '<rx ' ) + $( count "$TMP/n1.xml" '<def ' ) ))
if [ "$defs" -ge 1 ] && [ "$spec" = 1 ] && [ "$rows" = 0 ]; then ok "N1 external spec: external=1, 0 in-tree rows (premise: $defs inject defs, spec row seen)"
else no "N1 external spec: defs=$defs spec=$spec rows=$rows (want >=1 / 1 / 0)"; fi

ask "--for=Gadget from @acme/dup" >"$TMP/n2.xml"
pj=$( grep -rl '"name": "@acme/dup"' "$FIX" --include=package.json | wc -l | tr -d ' ' )
spec=$( count "$TMP/n2.xml" '<spec m="@acme/dup" n="Gadget" cands="2"/>' )
rows=$(( $( count "$TMP/n2.xml" '<rx ' ) + $( count "$TMP/n2.xml" '<def ' ) ))
if [ "$pj" = 2 ] && [ "$spec" = 1 ] && [ "$rows" = 0 ]; then ok "N2 ambiguous spec disclosed (cands=2), nothing guessed (premise: $pj manifests)"
else no "N2 ambiguous spec: manifests=$pj spec=$spec rows=$rows (want 2 / 1 / 0)"; fi

( cd "$FIX" && RIPWIRE_NO_IMPORT_SPEC=1 HOME="$TMP" "$BIN" "$FIX" --no-cache "--for=where inject imported from @acme/core is defined" </dev/null >"$TMP/n3.xml" 2>/dev/null )
if grep -q '<spec ' "$TMP/n3.xml"; then no "N3 RIPWIRE_NO_IMPORT_SPEC=1 still prints a spec row"; else ok "N3 RIPWIRE_NO_IMPORT_SPEC=1 prints no spec row"; fi
ask "--for=where Base is defined" >"$TMP/n3a.xml"
( cd "$FIX" && RIPWIRE_NO_IMPORT_SPEC=1 HOME="$TMP" "$BIN" "$FIX" --no-cache "--for=where Base is defined" </dev/null >"$TMP/n3b.xml" 2>/dev/null )
if [ -s "$TMP/n3a.xml" ] && cmp -s "$TMP/n3a.xml" "$TMP/n3b.xml"; then ok "N3 a task with no spelled import is byte-identical with the switch"; else no "N3 a task with no spelled import differs with RIPWIRE_NO_IMPORT_SPEC=1"; fi

# ---- N5 / N6: their own fixtures (generated here), so the arms above read the tree they always read ----
askin(){ local d="$1"; shift; ( cd "$d" || exit 1; HOME="$TMP" "$BIN" "$d" --no-cache "$@" </dev/null 2>/dev/null ); }
U="$TMP/fxu"; mkdir -p "$U/packages/u" "$U/app"
printf '{ "name": "acme-root", "private": true }\n' >"$U/package.json"
printf '{\n  "name": "@acme/unread",\n  "exports": { ".": "./index.js" }\n}\n' >"$U/packages/u/package.json"
printf 'export function gizmo() { return 1; }\n' >"$U/packages/u/index.ts"
printf "import { gizmo } from '@acme/unread';\nexport function main() { return gizmo(); }\n" >"$U/app/main.ts"
askin "$U" "--for=where gizmo imported from @acme/unread is defined" >"$TMP/n5a.xml"
pre=$( count "$TMP/n5a.xml" '<spec m="@acme/unread" n="gizmo" p="packages/u/package.json"' )
chmod 000 "$U/packages/u/package.json"
if cat "$U/packages/u/package.json" >/dev/null 2>&1; then
    echo "  SKIP  N5 chmod 000 leaves the manifest readable here (root?): the unreadable shape cannot be staged"
else
    askin "$U" "--for=where gizmo imported from @acme/unread is defined" >"$TMP/n5.xml"
    ext=$( grep -c 'external="1"' "$TMP/n5.xml" ); spec=$( grep -c '<spec ' "$TMP/n5.xml" )
    if [ "$pre" = 1 ] && [ -s "$TMP/n5.xml" ] && [ "$ext" = 0 ] && [ "$spec" = 0 ]; then ok "N5 an unreadable manifest: no external=1, no spec row (premise: resolved while readable)"
    else no "N5 unreadable manifest: premise=$pre external=$ext spec=$spec (want 1 / 0 / 0)"; fi
fi
chmod 644 "$U/packages/u/package.json"
chain(){ # chain DIR N: @acme/deep's entry re-exports through N statements to the def of deepThing
    local d="$1" n="$2" i; mkdir -p "$d/packages/deep"
    printf '{ "name": "acme-root", "private": true }\n' >"$d/package.json"
    printf '{\n  "name": "@acme/deep",\n  "exports": { ".": "./index.js" }\n}\n' >"$d/packages/deep/package.json"
    printf "export * from './h1';\n" >"$d/packages/deep/index.ts"
    for i in $( seq 1 $(( n - 1 )) ); do printf "export * from './h%d';\n" $(( i + 1 )) >"$d/packages/deep/h$i.ts"; done
    printf 'export function deepThing() { return 1; }\n' >"$d/packages/deep/h$n.ts"
}
chain "$TMP/fxd6" 6; chain "$TMP/fxd14" 14
askin "$TMP/fxd6" "--for=where deepThing imported from @acme/deep is defined" >"$TMP/n6a.xml"
askin "$TMP/fxd14" "--for=where deepThing imported from @acme/deep is defined" >"$TMP/n6.xml"
short=$( count "$TMP/n6a.xml" '<def n="deepThing" p="packages/deep/h6.ts"' ); shortcap=$( count "$TMP/n6a.xml" 'capped="1"' )
deep=$( block "$TMP/n6.xml" | grep -oE '<spec m="@acme/deep"[^>]*>' | head -1 )
case "$deep" in
    *'capped="1"'*'found="0"'*) [ "$short" = 1 ] && [ "$shortcap" = 0 ] && ok "N6 past the depth cap: $deep (premise: the 6-chain reaches its def)" \
                                    || no "N6 premise: the 6-chain def=$short capped=$shortcap (want 1 / 0)" ;;
    *) no "N6 past the depth cap: ${deep:-<no spec row>} (want found=\"0\" with capped=\"1\")" ;;
esac

# N7 (CodeRabbit 4550333655): a cut the walk can no longer use does not hedge a found answer with capped=1.
#   (a) depth: a12.ts defines deepThing 12 statements from the entry (kImportSpecDepth) while b12.ts, at the same depth, still
#       hands it on; (b) states: a.ts defines it one statement in while ten siblings each re-export 30 files (300 depth-2 states
#       past kImportSpecMaxStates, 256). Premise, counted: the b-branch hop at depth 12 and the 300 depth-2 statements exist.
fork(){ # fork DIR: the entry hands deepThing to a 12-chain ending in its def and to a 12-chain that keeps going
    local d="$1" i b; mkdir -p "$d/packages/deep"
    printf '{ "name": "acme-root", "private": true }\n' >"$d/package.json"
    printf '{\n  "name": "@acme/deep",\n  "exports": { ".": "./index.js" }\n}\n' >"$d/packages/deep/package.json"
    printf "export * from './a1';\nexport * from './b1';\n" >"$d/packages/deep/index.ts"
    for b in a b; do for i in $( seq 1 11 ); do printf "export * from './%s%d';\n" "$b" $(( i + 1 )) >"$d/packages/deep/$b$i.ts"; done; done
    printf 'export function deepThing() { return 1; }\n' >"$d/packages/deep/a12.ts"
    printf "export * from './b13';\n" >"$d/packages/deep/b12.ts"
    printf 'export const other = 1;\n' >"$d/packages/deep/b13.ts"
}
fan(){ # fan DIR: the entry hands deepThing to a.ts (its def) and to s1..s10, each re-exporting 30 files
    local d="$1" i j; mkdir -p "$d/packages/deep"
    printf '{ "name": "acme-root", "private": true }\n' >"$d/package.json"
    printf '{\n  "name": "@acme/deep",\n  "exports": { ".": "./index.js" }\n}\n' >"$d/packages/deep/package.json"
    { printf "export * from './a';\n"; for i in $( seq 1 10 ); do printf "export * from './s%d';\n" "$i"; done; } >"$d/packages/deep/index.ts"
    printf 'export function deepThing() { return 1; }\n' >"$d/packages/deep/a.ts"
    for i in $( seq 1 10 ); do
        for j in $( seq 1 30 ); do printf "export * from './t%d_%d';\n" "$i" "$j"; printf 'export const v%d_%d = 1;\n' "$i" "$j" >"$d/packages/deep/t${i}_$j.ts"; done >"$d/packages/deep/s$i.ts"
    done
}
fork "$TMP/fxf"; fan "$TMP/fxn"
askin "$TMP/fxf" "--for=where deepThing imported from @acme/deep is defined" >"$TMP/n7a.xml"
askin "$TMP/fxn" "--for=where deepThing imported from @acme/deep is defined" >"$TMP/n7b.xml"
bhop=$( grep -c "export \* from './b13'" "$TMP/fxf/packages/deep/b12.ts" ); fanrx=$( cat "$TMP/fxn/packages/deep"/s*.ts | grep -c '^export \* from' )
for arm in "a:$TMP/n7a.xml:a12.ts:depth" "b:$TMP/n7b.xml:a.ts:states"; do
    IFS=: read -r tag xml def what <<<"$arm"
    row=$( block "$xml" | grep -oE '<spec m="@acme/deep"[^>]*>' | head -1 ); got=$( count "$xml" "<def n=\"deepThing\" p=\"packages/deep/$def\"" )
    if [ "$bhop" = 1 ] && [ "$fanrx" = 300 ] && [ "$got" = 1 ] && [ -n "$row" ] && [ "${row#*capped=}" = "$row" ]; then ok "N7$tag a found def is not capped by the $what cut: $row (premise: b12 hop $bhop, depth-2 statements $fanrx)"
    else no "N7$tag $what cut after the def: ${row:-<no spec row>} def=$got (premise: b12 hop $bhop want 1, depth-2 statements $fanrx want 300; want no capped=)"; fi
done

if command -v xmllint >/dev/null 2>&1; then
    bad=0; n=0
    for f in "$TMP"/*.xml; do n=$(( n + 1 )); xmllint --noout "$f" 2>/dev/null || { bad=1; no "N4 malformed XML: $( basename "$f" )"; }; done
    [ "$bad" = 0 ] && [ "$n" -ge 9 ] && ok "N4 $n answers well-formed"
fi

[ "$fail" = 0 ] && echo "importspellingcheck: OK" || echo "importspellingcheck: FAILED"
exit "$fail"
