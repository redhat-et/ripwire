#!/usr/bin/env bash
# tspathsalias.sh — #711 (reported by SStonkSS1): a named import through a tsconfig `paths` alias that points inside the
# root (`@/*` → `./src/*`, the Next.js default) pins the call as a relative import does, through the SAME project-config
# resolution the file edge reads (resolve.h resolveBareTsSpecifier). Before, the binder asked only the path resolver,
# the call fell to the name ladder, and a same-named method on any class declined it (`<dc ... cands="2">`).
#
# Every root below holds src/mod.ts::listItems, a decoy `Repo.listItems` method, and src/app/route.ts whose GET calls
# the imported `listItems`. POSITIVES (red before #711, green after): `paths` only; `baseUrl` + `paths`; an alias to a
# directory's index.ts; `paths` read through an `extends` chain; `@/mod.ts` spelled with its extension.
# NEGATIVES (as before #711; each counts the answer it read and the arm FAILS on none): an alias whose target is outside
# the root; a bare package import; a relative import; an alias whose target file is missing (declined, cands=2); a
# workspace root's nested tsconfig alias into a SIBLING root — the file edge's same-root rule (an answer in another
# root is not evidence) holds for the binder too, so the call stays declined. That last arm is the one a guard-off
# build turns red (drop the fileRoot check in resolveBareTsSpecifier: the call pins to b/src/mod.ts). N4 and N5 import
# no Repo: with `r: Repo` in the file and no file edge to src/mod.ts, the ladder binds the bare call to Repo.listItems on
# every binary (a pre-#711 edge this gate does not pin).
# Usage: test/lib/tspathsalias.sh BIN   (run by test/tsimportprecisecheck.sh)
set -u
ROOT="$( cd "$( dirname "$0" )/../.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0 negSeen=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
echo "tspathsalias (#711): BIN=$BIN"

P='{"compilerOptions":{"moduleResolution":"bundler","paths":{"@/*":["./src/*"]}}}'
mkroot(){  # $1 root  $2 tsconfig json (empty: none)  $3 the specifier route.ts imports listItems from  [$4 the module file]  [$5 noRepo]
  local r="$1" m="${4:-src/mod.ts}" repo='import { Repo } from "../repo";\n' param='r: Repo'
  [ -n "${5:-}" ] && { repo=''; param=''; }
  mkdir -p "$r/src/app" "$r/$( dirname "$m" )"
  [ -n "$2" ] && printf '%s\n' "$2" >"$r/tsconfig.json"
  printf 'export async function listItems(a: number) { return a; }\n' >"$r/$m"
  printf 'export class Repo {\n  async listItems(a: number) { return a; }\n}\n' >"$r/src/repo.ts"
  printf "import { listItems } from \"%s\";\n${repo}export async function GET(${param}) { return listItems(1); }\n" "$3" >"$r/src/app/route.ts"
}
callers(){ "$BIN" "$@" --no-cache 2>/dev/null | grep -o '<callers .*'; }
pinned(){  # $1 arm  $2 root  $3 module file: GET is the one caller, nothing declined
  local out; out="$( callers "$2" --callers="$3:listItems" )"
  case "$out" in
    *' count="1"'*'<s t="fn" n="GET" p="src/app/route.ts:3"'*) [[ "$out" != *declined* ]] && { ok "$1: GET → $3 pinned"; return; } ;;
  esac
  no "$1: GET → $3 not pinned"; printf '        %s\n' "$out"
}
neg(){  # $1 arm  $2 the callers element  $3 a substring it must hold  $4 one it must not
  [ -z "$2" ] && { no "$1: no <callers> answer read (vacuous)"; return; }
  negSeen=$(( negSeen + 1 ))
  if [[ "$2" == *"$3"* && "$2" != *"$4"* ]]; then ok "$1: as before"; else no "$1: changed"; printf '        %s\n' "$2"; fi
}

mkroot "$TMP/p1" "$P" "@/mod";                                                 pinned "P1 paths only" "$TMP/p1" src/mod.ts
mkroot "$TMP/p2" '{"compilerOptions":{"baseUrl":".","paths":{"@/*":["src/*"]}}}' "@/mod"; pinned "P2 baseUrl + paths" "$TMP/p2" src/mod.ts
mkroot "$TMP/p3" "$P" "@/lib" src/lib/index.ts;                                pinned "P3 directory index.ts" "$TMP/p3" src/lib/index.ts
mkroot "$TMP/p4" '{"extends":"./tsconfig.base.json"}' "@/mod"; printf '%s\n' "$P" >"$TMP/p4/tsconfig.base.json"
pinned "P4 paths through extends" "$TMP/p4" src/mod.ts
mkroot "$TMP/p5" "$P" "@/mod.ts";                                              pinned "P5 @/mod.ts" "$TMP/p5" src/mod.ts

mkroot "$TMP/n1/proj" '{"compilerOptions":{"paths":{"@ext/*":["../outside/*"]}}}' "@ext/mod"
mkdir -p "$TMP/n1/outside"; printf 'export async function listItems(a: number) { return a; }\n' >"$TMP/n1/outside/mod.ts"
neg "N1 alias outside the root" "$( callers "$TMP/n1/proj" --callers=src/mod.ts:listItems )" ' count="0"' '<s '
mkroot "$TMP/n2" "$P" "some-pkg"
neg "N2 bare package"           "$( callers "$TMP/n2" --callers=src/mod.ts:listItems )" ' count="0"' '<s '
mkroot "$TMP/n3" "$P" "../mod"
neg "N3 relative import"        "$( callers "$TMP/n3" --callers=src/mod.ts:listItems )" '<s t="fn" n="GET" p="src/app/route.ts:3"' 'declined'
mkroot "$TMP/n4" "$P" "@/missing/mod" src/mod.ts noRepo
neg "N4 missing alias target"   "$( callers "$TMP/n4" --callers=src/mod.ts:listItems )" '<dc in="GET" p="src/app/route.ts:2" cands="2" via="declined"' '<s '
W="$TMP/n5"; mkroot "$W/a" "" "@b/mod" src/mod.ts noRepo; printf '{"compilerOptions":{"paths":{"@b/*":["../../b/src/*"]}}}\n' >"$W/a/src/tsconfig.json"
mkdir -p "$W/b/src"; printf 'export async function listItems(a: number) { return a; }\n' >"$W/b/src/mod.ts"
neg "N5 workspace alias into a sibling root" "$( callers "$W/a" "$W/b" --callers=listItems )" '<dc in="GET" p="a/src/app/route.ts:2" cands="2" via="declined"' '<s '
[ "$negSeen" -eq 5 ] || no "negative arms read $negSeen of 5 answers"

[ "$fail" -eq 0 ] && echo "tspathsalias: ALL PASS" || { echo "tspathsalias: SOME CHECKS FAILED"; exit 1; }
