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
#   S4  card (c) on the definition-side walk: `where injectAll is defined` reaches src/core.ts, public_api.ts and index.ts.
#   S5  Python: `where acme.pkg.Thing is defined` -> `lazy from .impl import Thing` in acme/pkg/__init__.py; `Thing2 imported from
#       acme.pkg` -> the parenthesised `Other as Thing2` (as="Thing2", def Other).
#   N1  external: `inject from lodash/fp` (no in-tree package.json declares lodash and no segment names an in-tree directory or
#       file: graph.h jsModuleIsForeign): external="1" and no rx/def rows. Premise: the fixture defines inject (counted) and the spec
#       row printed. (A spelling that no package.json declares but whose segment names the tree, `@fix/m` for a directory m/, keeps
#       the definition-side rule of test/reexportcheck.sh P1.)
#   N2  ambiguous: `Gadget from @acme/dup` (two package.json files declare @acme/dup, two Gadget defs): cands="2", no def/rx row.
#   N3  RIPWIRE_NO_IMPORT_SPEC=1 prints no spec row; a task with no spelled import is byte-identical with and without it.
#   N4  every answer is well-formed XML (xmllint, when present).
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
ok(){ printf '  PASS  %s\n' "$*"; }
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

ask "--for=where injectAll is defined" >"$TMP/s4.xml"
has "$TMP/s4.xml" "S4 definition-side walk passes ./di (file before index)" '<rx p="packages/core/src/core.ts" l="1" from="./di" glob="1"/>'
has "$TMP/s4.xml" "S4 ... and reaches the package entry" '<rx p="packages/core/index.ts" l="1" from="./public_api" glob="1"/>'

ask "--for=where acme.pkg.Thing is defined" >"$TMP/s5.xml"
has "$TMP/s5.xml" "S5 Python lazy from hop" '<spec m="acme.pkg" n="Thing" p="py/acme/pkg/__init__.py" entry="py/acme/pkg/__init__.py"/><def n="Thing" p="py/acme/pkg/impl.py" l="1" total="1"/><rx p="py/acme/pkg/__init__.py" l="3" from=".impl"/>'
ask "--for=Thing2 imported from acme.pkg" >"$TMP/s5b.xml"
has "$TMP/s5b.xml" "S5 Python parenthesised rename" '<def n="Other" p="py/acme/pkg/base.py" l="5" total="1"/><rx p="py/acme/pkg/__init__.py" l="1" from=".base" as="Thing2"/>'

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

if command -v xmllint >/dev/null 2>&1; then
    bad=0; n=0
    for f in "$TMP"/*.xml; do n=$(( n + 1 )); xmllint --noout "$f" 2>/dev/null || { bad=1; no "N4 malformed XML: $( basename "$f" )"; }; done
    [ "$bad" = 0 ] && [ "$n" -ge 9 ] && ok "N4 $n answers well-formed"
fi

[ "$fail" = 0 ] && echo "importspellingcheck: OK" || echo "importspellingcheck: FAILED"
exit "$fail"
