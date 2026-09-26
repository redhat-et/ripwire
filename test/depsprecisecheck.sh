#!/usr/bin/env bash
# depsprecisecheck.sh — P3 gate: the FILE→FILE dependency graph (--deps/--arch/cycles/god-files) is
# PATH-PRECISE, not basename. graph.h::resolveIncludeAdj now resolves each quote `#include "x.h"` LEXICALLY
# relative-to-includer (resolve.h::buildPreciseIncludeAdj, the same sound machinery the call-graph
# SameInclude tier uses) instead of matching by basename. This closes the last silent-wrong-edge surface:
# a cross-directory basename collision could make --deps/--arch show a WRONG file→file edge.
#
# Fixture test/depsprecisefix has the exact collision the basename resolver could not tell apart:
#   dirA/x.h  and  dirB/x.h        BOTH exist, SAME basename `x.h`, DIFFERENT directories
#   consumer.cpp   #include "dirA/x.h"   (quote, by PATH)   → the ONE real dep
#   consumer.cpp   #include <dirB/x.h>   (angle, in-repo)   → external form → NO edge (never basename-matched)
#
# The old basename resolver reduced `dirA/x.h` to basename `x.h` and linked BOTH dirA/x.h and dirB/x.h
# (a phantom edge to the file the source never includes). Precise resolution:
#   - the edge lands on dirA/x.h ONLY  (afferent=1)                         ← path, not basename
#   - dirB/x.h gets NO incoming edge   (never appears as a resolved node)   ← the decoy is dropped
#   - the angle <dirB/x.h> contributes nothing                             ← angle → unresolved, honest
# MONOTONICITY: precise resolution can only REMOVE or REDIRECT a wrong edge, never MANUFACTURE one.
#
# Usage:  test/depsprecisecheck.sh   |   RIPWIRE_BIN=asan/ripwire test/depsprecisecheck.sh
# Exits non-zero on any failure. Does NOT edit test/regression.sh or test/golden.xml.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/depsprecisefix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "depsprecisecheck: BIN=$BIN  FIX=$FIX  TMP=$TMP"

# --deps: emit the file→file graph, one XML tag per line for grep-able node/edge assertions.
"$BIN" "$FIX" --deps --pack-top-n=1000 --no-cache 2>/dev/null | sed 's/</\n</g' >"$TMP/deps"

# ── the real dep resolves to dirA/x.h (afferent=1) — path, not basename ────────────────────────────
if grep -qE 'p="[^"]*dirA/x\.h"[^>]*afferent="1"' "$TMP/deps"; then
    ok "dirA/x.h has afferent=1 — the quote include \"dirA/x.h\" resolved by PATH to the right file"
else
    no "dirA/x.h afferent!=1 — the real edge was lost or mis-resolved"; grep -E 'dirA/x\.h' "$TMP/deps"
fi

# ── the decoy dirB/x.h gets NO incoming edge — it never appears as a RESOLVED node ─────────────────
# (a node line carries afferent="…"; an `<inc t="dirB/x.h">` DISPLAY line does not — assert on afferent).
if grep -qE 'p="[^"]*dirB/x\.h"[^>]*afferent="[1-9]' "$TMP/deps"; then
    no "dirB/x.h has a phantom incoming edge — basename collision leaked a WRONG file→file edge"
    grep -E 'dirB/x\.h' "$TMP/deps"
else
    ok "dirB/x.h has NO incoming edge — the same-basename decoy was NOT basename-matched (the fix)"
fi

# ── the angle include <dirB/x.h> of an in-repo file contributes NO edge (external form → unresolved) ─
# Proven by the above: consumer.cpp's ONLY quote include is dirA/x.h; the angle <dirB/x.h> is the only
# other route to dirB, and dirB has afferent 0 → the angle include added nothing. Assert it directly too:
# consumer.cpp's transitive cone is exactly 2 (self + dirA/x.h; Lakos counts self). Were the angle
# <dirB/x.h> resolved (basename-matched) it would be 3 — so transitive=2 proves the angle added no edge.
if grep -qE 'p="[^"]*consumer\.cpp"[^>]*transitive="2"' "$TMP/deps"; then
    ok "consumer.cpp cone=2 (self + dirA/x.h only) — angle <dirB/x.h> added NO edge (Lakos counts self)"
else
    no "consumer.cpp transitive cone != 2 — an angle include or decoy leaked an edge"
    grep -E 'consumer\.cpp' "$TMP/deps"
fi

# ── determinism: byte-identical run-to-run + warm == cold ─────────────────────────────────────────
"$BIN" "$FIX" --deps --no-cache >"$TMP/d1" 2>/dev/null
"$BIN" "$FIX" --deps --no-cache >"$TMP/d2" 2>/dev/null
if cmp -s "$TMP/d1" "$TMP/d2"; then ok "deterministic (two --deps --no-cache runs identical)"; else no "non-deterministic"; fi
"$BIN" "$FIX" --deps --cache="$TMP/c.bin" >"$TMP/cold" 2>/dev/null
"$BIN" "$FIX" --deps --cache="$TMP/c.bin" >"$TMP/warm" 2>/dev/null
if cmp -s "$TMP/cold" "$TMP/warm"; then ok "warm == cold (precise adjacency order-stable through cache)"; else no "warm != cold"; fi

# ── well-formed XML ───────────────────────────────────────────────────────────────────────────────
command -v xmllint >/dev/null 2>&1 \
  && { xmllint --noout "$TMP/d1" 2>/dev/null && ok "xml well-formed" || no "xml malformed"; } \
  || ok "xml well-formed (xmllint absent — skipped)"

# ── §P9.2: <f instab=> and <stabledeps gap=> must be the SAME Martin instability I=Ce/(Ca+Ce), so a ────
# `<stabledeps>` gap must equal (consumer's printed instab − provider's printed instab) within 0.01, from
# the document alone. Pre-fix, <f instab=> counted Ce over EVERY #include statement (system+third-party
# included) while <stabledeps gap=> counted Ce over the project-only resolved graph — two different numbers
# sharing one attribute name. Run against ripwire's OWN source (self-hosting): it is where the plan's
# worked example lives (src/mcp.h -> src/mcpverbs.h, claimed instab=0.52ish vs recomputed 0.25ish
# pre-fix) — the small depsprecisefix fixture has no stabledeps violations to check.
if command -v python3 >/dev/null 2>&1; then
    "$BIN" "$ROOT" --deps --pack-top-n=1000 --no-cache >"$TMP/deps_self.xml" 2>/dev/null
    if python3 - "$TMP/deps_self.xml" <<'PYEOF'
import re, sys
xml = open( sys.argv[1] ).read()
instab = {}
for m in re.finditer( r'<f p="([^"]*)"[^>]*\binstab="([0-9.]+)"', xml ):
    instab[ m.group(1) ] = float( m.group(2) )
checked, bad = 0, []
for m in re.finditer( r'<v from="([^"]*)" to="([^"]*)"[^>]*\bgap="([0-9.]+)"', xml ):
    frm, to, gap = m.group(1), m.group(2), float( m.group(3) )
    if frm not in instab or to not in instab:
        continue   # outside the --pack-top-n=1000 <f> window — not asserted, not a failure
    checked += 1
    recomputed = instab[to] - instab[frm]
    # tolerance is 0.01 (two independently-rounded %.2f values can compound to that much) + a tiny epsilon
    # so IEEE-754 binary representation of the decimal strings (e.g. 0.33-0.28 == 0.04999999999999999 in
    # float64) never fails a genuinely-reconciling row by 1e-16 of pure floating-point noise.
    if abs( recomputed - gap ) > 0.01 + 1e-9:
        bad.append( ( frm, to, gap, round( recomputed, 4 ) ) )
if checked == 0:
    print( "no <stabledeps> row had both endpoints in the <f> window — nothing checked" )
    sys.exit(1)
if bad:
    print( f"{len(bad)}/{checked} rows do NOT reconcile (from, to, printed_gap, recomputed_from_instab):" )
    for b in bad: print( "  ", b )
    sys.exit(1)
print( f"all {checked} <stabledeps> rows reconcile with printed <f instab=> within 0.01" )
PYEOF
    then ok "P9.2: every <stabledeps gap=> recomputes from printed <f instab=> within 0.01"
    else no "P9.2: <stabledeps gap=> does not reconcile with <f instab=> (two instability numbers under one name)"
    fi
else
    ok "P9.2 skipped (python3 absent)"
fi

# §A10.11: --deps emits three files=-family counts (root files=, <health files=>, <health dep_files=>)
# under one attribute name in two different places — the legend must name all three denominators, the
# same disclosure --owners already carries for its own files= DEPTH collision.
# L1 (2026-09-19): the CLI default legend is compact; this arm reads the FULL legend's prose, so it asks for it.
DOUT="$( "$BIN" "$FIX" --deps --no-cache --legend=full 2>/dev/null )"
printf '%s' "$DOUT" | grep -q 'health dep_files= = the dependency-CAPABLE subset' \
    && ok "--deps legend names all three files=-family denominators (§A10.11)" \
    || no "--deps legend does not disclose the three files=-family denominators"

# ── #220 part 1: a TS/JS import that names an IN-REPO alias or workspace package but drew no edge is COUNTED ──
# --deps resolves only relative TS/JS specifiers. An import through a tsconfig/jsconfig `paths` alias, a `baseUrl`-
# relative path or a workspace package name draws no edge, so a cycle spelled through one is missing and the absent
# <cycles> element read as "acyclic": a confident wrong zero. Part 1 does not resolve them; it counts them on the
# ROOT as imports_unresolved=N, on --deps, --arch, --impact (all three dialects and the MCP twin), and in --report's
# cycle line. Its READING is graph_partial="1" on --deps/--arch — measured over resolved edges, NOT counts_floor: a
# missing edge can merge two reported cycles into one and moves instab= either way, so "every count is a floor" was
# false there (arm J proves it); --impact keeps its own counts_floor="1" (importers= only rises). Absent at zero, so a tree with no such import is byte-
# identical. A bare package that matches none of the three (react, left-pad) is never counted. Fixtures are GENERATED
# here, never committed: this repository indexes itself, and a committed tsconfig would become live evidence.
mkts() {   # mkts DIR alias|relative|unbuilt — issue #220's matched pair: an npm-workspaces tree; `relative` respells three
    # specifiers; `unbuilt` keeps the alias spelling but points it at files that are not there (a generated `gen/` dir, an
    # unbuilt `dist/` entry with no outDir→rootDir map) — the in-repo imports part 2 still cannot resolve, so still counts.
    local D="$1" SP="$2" AB AA LIB TGT="src/*" MAIN="src/index.ts"
    rm -rf "$D"; mkdir -p "$D/packages/lib/src" "$D/packages/app/src"
    if [ "$SP" = relative ]; then AB="./b"; AA="./a"; LIB="../../lib/src/index"; else AB="@app/b"; AA="@app/a"; LIB="@acme/lib"; fi
    [ "$SP" = unbuilt ] && { TGT="gen/*"; MAIN="dist/index.js"; }
    printf '{ "name": "fixture-root", "private": true, "workspaces": ["packages/*"] }\n' >"$D/package.json"
    printf '{\n  // tsc accepts comments and trailing commas here\n  "compilerOptions": { "strict": true, },\n}\n' >"$D/tsconfig.base.json"
    printf '{ "name": "@acme/lib", "main": "%s" }\n' "$MAIN" >"$D/packages/lib/package.json"
    printf 'export function helper(): number { return 1; }\n' >"$D/packages/lib/src/index.ts"
    printf '{ "name": "@acme/app", "dependencies": { "@acme/lib": "*" } }\n' >"$D/packages/app/package.json"
    printf '{\n  "extends": "../../tsconfig.base.json",\n  "compilerOptions": { "baseUrl": ".", "paths": { "@app/*": ["%s"] } }\n}\n' "$TGT" >"$D/packages/app/tsconfig.json"
    printf "import { b } from '%s';\nimport { helper } from '%s';\nimport React from 'react';\nexport function a(): number { return b() + helper(); }\n" "$AB" "$LIB" >"$D/packages/app/src/a.ts"
    printf "import { a } from '%s';\nexport function b(): number { return typeof a === 'function' ? 1 : 0; }\n" "$AA" >"$D/packages/app/src/b.ts"
    printf "import { d } from './d';\nexport function c(): number { return d(); }\n" >"$D/packages/app/src/c.ts"
    printf "import { c } from './c';\nexport function d(): number { return typeof c === 'function' ? 1 : 0; }\n" >"$D/packages/app/src/d.ts"
}
root_of() { sed -n 's/.*\(<deps [^>]*>\).*/\1/p; s/.*\(<arch [^>]*>\).*/\1/p' "$1" | head -1; }
# partial_root N ROOT — the partial-graph pair, and NO counts_floor= (not every count on --deps/--arch is a floor)
partial_root() { case "$2" in *"imports_unresolved=\"$1\" graph_partial=\"1\""*) case "$2" in *counts_floor=*) return 1 ;; esac; return 0 ;; esac; return 1; }
# #220 part 2 resolves the `alias` spelling (its arms are below); the disclosure arms here run on the `unbuilt` one.
TA="$TMP/ts-alias"; TR="$TMP/ts-rel"; mkts "$TA" unbuilt; mkts "$TR" relative
"$BIN" "$TA" --deps --no-cache >"$TMP/ta.deps" 2>/dev/null
"$BIN" "$TR" --deps --no-cache >"$TMP/tr.deps" 2>/dev/null

# (220-A) the unbuilt alias tree: three in-repo specifiers unresolved (@app/b, @app/a through `paths` onto a missing gen/;
# @acme/lib a workspace member with an unbuilt entry), react NOT counted, and the partial-graph pair rides the root.
ROOTA="$( root_of "$TMP/ta.deps" )"
partial_root 3 "$ROOTA" && ok "#220 (A) alias tree: <deps imports_unresolved=\"3\" graph_partial=\"1\">, no counts_floor (react not counted)" \
    || no "#220 (A) alias tree root lacks imports_unresolved=\"3\" graph_partial=\"1\" or still claims counts_floor — got: $ROOTA"
# the missing cycle is the reason: only c<->d is found through the alias spelling, a<->b is not
[ "$( grep -o '<cycle ' "$TMP/ta.deps" | wc -l | tr -d ' ' )" = 1 ] \
    && ok "#220 (A) the unbuilt alias spelling finds 1 cycle (a<->b names no file) — disclosed, never guessed" \
    || no "#220 (A) cycle count on the unbuilt alias tree moved — an alias onto a missing file must not draw an edge"

# (220-B) the relative control: the same tree, relative specifiers — both cycles found EXACTLY, no count, no floor.
ROOTR="$( root_of "$TMP/tr.deps" )"
{ [ "$( grep -o '<cycle ' "$TMP/tr.deps" | wc -l | tr -d ' ' )" = 2 ] && ! grep -q 'imports_unresolved=\|counts_floor=\|graph_partial=' "$TMP/tr.deps"; } \
    && ok "#220 (B) relative control: 2 cycles, exact — no imports_unresolved=, graph_partial=, counts_floor=" \
    || no "#220 (B) relative control wrong — root: $ROOTR"

# (220-C) mutation: respell @acme/lib as left-pad (names nothing here) — the count drops by exactly one.
sed -i.bak "s#'@acme/lib'#'left-pad'#" "$TA/packages/app/src/a.ts" && rm -f "$TA/packages/app/src/a.ts.bak"
if grep -q "'left-pad'" "$TA/packages/app/src/a.ts"; then
    "$BIN" "$TA" --deps --no-cache 2>/dev/null >"$TMP/ta2.deps"
    partial_root 2 "$( root_of "$TMP/ta2.deps" )" && ok "#220 (C) mutation @acme/lib -> left-pad: 3 -> 2 (a bare package is never counted)" \
        || no "#220 (C) mutation did not drop the count to 2 — got: $( root_of "$TMP/ta2.deps" )"
else
    no "#220 (C) the mutation did not take (a.ts unchanged) — nothing measured"
fi
sed -i.bak "s#'left-pad'#'@acme/lib'#" "$TA/packages/app/src/a.ts" && rm -f "$TA/packages/app/src/a.ts.bak"

# (220-D) pure-external control: a tsconfig WITH paths and a catch-all "*" and baseUrl, and only react/lodash/node:fs
# imported — none matches a non-catch-all pattern, none exists under baseUrl or the catch-all's target: no count.
TX="$TMP/ts-ext"; mkdir -p "$TX/src"
printf '{ "compilerOptions": { "baseUrl": ".", "paths": { "@/*": ["src/*"], "*": ["types/*"] } } }\n' >"$TX/tsconfig.json"
printf "import React from 'react';\nimport { x } from 'lodash/fp';\nimport fs from 'node:fs';\nimport { y } from './y';\nexport function a(): number { return y(); }\n" >"$TX/src/a.ts"
printf "import { a } from './a';\nexport function y(): number { return typeof a === 'function' ? 1 : 0; }\n" >"$TX/src/y.ts"
"$BIN" "$TX" --deps --no-cache 2>/dev/null >"$TMP/tx.deps"
{ ! grep -q 'imports_unresolved=\|counts_floor=\|graph_partial=' "$TMP/tx.deps" && [ "$( grep -o '<cycle ' "$TMP/tx.deps" | wc -l | tr -d ' ' )" = 1 ]; } \
    && ok "#220 (D) external-only imports under paths/\"*\"/baseUrl: no count, no floor; the relative cycle exact" \
    || no "#220 (D) an external package was counted as in-repo — root: $( root_of "$TMP/tx.deps" )"

# (220-E) one rule per arm: a baseUrl-relative path that EXISTS resolves (part 2; part 1 counted it); a jsonc-COMMENTED
# paths block is never read; an alias inherited through a relative `extends` resolves; a pnpm-workspace.yaml member's
# name with an unbuilt entry counts.
TB="$TMP/ts-baseurl"; mkdir -p "$TB/src/lib"
printf '{ "compilerOptions": {\n    // "paths": { "@x/*": ["./*"] },\n    "baseUrl": "src" } }\n' >"$TB/tsconfig.json"
printf "import { u } from 'lib/util';\nimport { v } from '@x/lib/util';\nexport const a = u + v;\n" >"$TB/src/a.ts"
printf "export const u = 1;\n" >"$TB/src/lib/util.ts"
"$BIN" "$TB" --deps --no-cache 2>/dev/null >"$TMP/tb.deps"
{ grep -q '<f p="src/lib/util.ts" afferent="1"/>' "$TMP/tb.deps" && ! grep -q 'imports_unresolved=\|counts_floor=\|graph_partial=' "$TMP/tb.deps"; } \
    && ok "#220 (E1) baseUrl: 'lib/util' resolves to src/lib/util.ts (afferent=1, not partial); the commented-out paths key is not read" \
    || no "#220 (E1) baseUrl/jsonc arm wrong — got: $( root_of "$TMP/tb.deps" )"
# the jsonc arm is live: uncomment the key and @x/lib/util resolves too (assert the mutation took first)
sed -i.bak 's#// "paths"#"paths"#' "$TB/tsconfig.json" && rm -f "$TB/tsconfig.json.bak"
if grep -q '^    "paths"' "$TB/tsconfig.json"; then
    "$BIN" "$TB" --deps --no-cache 2>/dev/null | grep -q '<f p="src/lib/util.ts" afferent="2"/>' \
        && ok "#220 (E1) mutation: the same key UNcommented is read (afferent 1 -> 2), so the comment arm above is live" \
        || no "#220 (E1) mutation: the uncommented paths key was not read"
else
    no "#220 (E1) the uncomment mutation did not take — nothing measured"
fi
TE="$TMP/ts-extends"; mkdir -p "$TE/app/src"
printf '{ "compilerOptions": { "paths": { "#core/*": ["./app/src/*"] } } }\n' >"$TE/tsconfig.base.json"
printf '{ "extends": "../tsconfig.base", "compilerOptions": { "strict": true } }\n' >"$TE/app/tsconfig.json"
printf "import { b } from '#core/b';\nexport const a = b;\n" >"$TE/app/src/a.ts"
printf "import { a } from '#core/a';\nexport const b = a;\n" >"$TE/app/src/b.ts"
"$BIN" "$TE" --deps --no-cache 2>/dev/null >"$TMP/te.deps"
{ [ "$( grep -o '<cycle ' "$TMP/te.deps" | wc -l | tr -d ' ' )" = 1 ] && ! grep -q 'imports_unresolved=\|counts_floor=\|graph_partial=' "$TMP/te.deps"; } \
    && ok "#220 (E2) an alias inherited through a relative extends (no .json suffix) resolves: the a<->b cycle, not partial" \
    || no "#220 (E2) extends arm wrong — got: $( root_of "$TMP/te.deps" )"
TP="$TMP/ts-pnpm"; mkdir -p "$TP/packages/shared/src" "$TP/packages/app/src"
printf "packages:\n  - 'packages/*'\n" >"$TP/pnpm-workspace.yaml"
printf '{ "name": "@acme/shared", "main": "dist/index.js" }\n' >"$TP/packages/shared/package.json"
printf "export function helper(): number { return 1; }\n" >"$TP/packages/shared/src/index.ts"
printf "import { helper } from '@acme/shared';\nimport { h2 } from '@acme/shared/sub';\nimport { z } from '@acme/other';\nexport const a = helper() + h2 + z;\n" >"$TP/packages/app/src/a.ts"
"$BIN" "$TP" --deps --no-cache 2>/dev/null >"$TMP/tp.deps"
partial_root 2 "$( root_of "$TMP/tp.deps" )" && ok "#220 (E3) pnpm-workspace.yaml member @acme/shared (unbuilt dist/ entry) and its subpath count; @acme/other (no member) does not" \
    || no "#220 (E3) workspace arm wrong — got: $( root_of "$TMP/tp.deps" )"

# (220-F) --arch, the CI gate: the answer is partial on the alias tree — violations= can only rise, the <metrics> ratios
# move either way, so graph_partial="1" and no counts_floor (exit code unchanged — part 1 discloses; it does not change
# what a CI gate exits with). The relative control carries nothing.
printf 'layer app = packages/app\nlayer lib = packages/lib\ndeny app -> lib\n' >"$TMP/rules220.txt"
"$BIN" "$TA" --arch="$TMP/rules220.txt" --no-cache >"$TMP/ta.arch" 2>"$TMP/ta.arch.err"; RCA=$?
"$BIN" "$TR" --arch="$TMP/rules220.txt" --no-cache >"$TMP/tr.arch" 2>/dev/null
partial_root 3 "$( root_of "$TMP/ta.arch" )" && ok "#220 (F) --arch alias tree: <arch … imports_unresolved=\"3\" graph_partial=\"1\">, no counts_floor (rc=$RCA)" \
    || no "#220 (F) --arch root lacks the partial pair or still claims counts_floor — got: $( root_of "$TMP/ta.arch" )"
grep -q 'imports_unresolved=\|graph_partial=' "$TMP/tr.arch" && no "#220 (F) --arch relative control carries imports_unresolved=/graph_partial=" \
    || ok "#220 (F) --arch relative control: no count"
grep -q 'did not resolve' "$TMP/ta.arch.err" && ok "#220 (F) --arch says it on stderr too, where a CI log reads it" \
    || no "#220 (F) --arch stderr carries no floor note"

# (220-G) --report's cycle line is qualified as measured over the resolved edges (not a floor, not "acyclic") on the
# alias tree; unchanged on the control.
"$BIN" "$TA" --report --no-cache >"$TMP/ta.rep" 2>/dev/null
"$BIN" "$TR" --report --no-cache >"$TMP/tr.rep" 2>/dev/null
grep -q '^## Dependency cycles (showing 1 of 1; measured over resolved edges: 3 imports unresolved)$' "$TMP/ta.rep" \
    && ok "#220 (G) --report: '## Dependency cycles (showing 1 of 1; measured over resolved edges: 3 imports unresolved)'" \
    || no "#220 (G) --report cycle line is not qualified as partial — got: $( grep '^## Dependency cycles' "$TMP/ta.rep" )"
grep -q 'a floor' "$TMP/ta.rep" && no "#220 (G) --report still calls the cycle count a floor" \
    || ok "#220 (G) --report no longer calls the cycle count a floor"
grep -q '^## Dependency cycles (showing 2 of 2)$' "$TMP/tr.rep" \
    && ok "#220 (G) --report relative control unchanged: (showing 2 of 2)" \
    || no "#220 (G) --report relative control moved — got: $( grep '^## Dependency cycles' "$TMP/tr.rep" )"

# (220-H) --impact's import tier (importers= is a floor while imports are unresolved): XML, json, columnar, and the
# MCP twin all carry the same count.
IX="$( "$BIN" "$TA" --impact=packages/app/src/b.ts:b --no-cache 2>/dev/null )"
IJ="$( "$BIN" "$TA" --impact=packages/app/src/b.ts:b --json --no-cache 2>/dev/null )"
IC="$( "$BIN" "$TA" --impact=packages/app/src/b.ts:b --format=columnar --no-cache 2>/dev/null )"
printf '%s' "$IX" | grep -q 'importers="0" shown_importers="0" importers_capped="0" imports_unresolved="3"' \
    && ok "#220 (H) --impact XML: importers=\"0\" … imports_unresolved=\"3\"" || no "#220 (H) --impact XML lacks imports_unresolved=\"3\""
printf '%s' "$IJ" | grep -q '"imports_unresolved":3' \
    && ok "#220 (H) --impact json: \"imports_unresolved\":3" || no "#220 (H) --impact json lacks the key"
printf '%s' "$IC" | grep -q 'imports_unresolved="3"' \
    && ok "#220 (H) --impact columnar: imports_unresolved=\"3\"" || no "#220 (H) --impact columnar lacks it"
MCP220="$( printf '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{}}\n{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"impact","arguments":{"path":"%s","symbol":"packages/app/src/b.ts:b"}}}\n' "$TA" \
            | perl -e 'alarm 60; exec @ARGV' "$BIN" --mcp 2>/dev/null | tail -1 )"
printf '%s' "$MCP220" | grep -q 'imports_unresolved=\\"3\\"' \
    && ok "#220 (H) MCP impact twin: imports_unresolved=\"3\" (same count as the CLI)" \
    || no "#220 (H) MCP impact twin lacks imports_unresolved — got: $( printf '%s' "$MCP220" | head -c 300 )"
"$BIN" "$TR" --impact=packages/app/src/b.ts:b --no-cache 2>/dev/null | grep -q 'imports_unresolved=' \
    && no "#220 (H) --impact relative control carries imports_unresolved=" || ok "#220 (H) --impact relative control: no count"

# (220-I) the definitions ride the legend exactly when the attribute does — compact and full — and the answer is
# deterministic, warm == cold, well-formed.
# graph_partial='s reading is ONE sentence in all three legends (graphlegend.h/compactlegend.h say so and point here).
READ220='measured over resolved edges; unresolved imports could add, merge or remove cycles and change ratios'
"$BIN" "$TA" --deps --no-cache --legend=full 2>/dev/null >"$TMP/ta.full"
{ grep -q 'imports_unresolved=N graph_partial=1' "$TMP/ta.full" && grep -qF "$READ220" "$TMP/ta.full"; } \
    && ok "#220 (I) full --deps legend defines imports_unresolved=/graph_partial= in the partial-graph words" || no "#220 (I) full --deps legend lacks the partial-graph definition"
{ grep -q 'imports_unresolved=N' "$TMP/ta.deps" && grep -qF "graph_partial=1: $READ220" "$TMP/ta.deps"; } \
    && ok "#220 (I) compact --deps legend defines imports_unresolved= and graph_partial= (same words)" \
    || no "#220 (I) compact --deps legend lacks the definitions"
"$BIN" "$TA" --arch="$TMP/rules220.txt" --no-cache --legend=full 2>/dev/null | grep -qF "$READ220" \
    && ok "#220 (I) full --arch legend reads graph_partial= in the same words" || no "#220 (I) full --arch legend lacks the partial-graph words"
# the old wording is gone from every legend form: the numbers are no longer called floors
grep -q 'are floors over a partial graph\|graph counts are floors\|the metrics are floors' "$TMP/ta.full" "$TMP/ta.deps" "$TMP/ta.arch" \
    && no "#220 (I) a legend still calls the partial graph's numbers floors" || ok "#220 (I) no legend calls the partial graph's numbers floors"
"$BIN" "$TR" --deps --no-cache --legend=full 2>/dev/null | grep -q 'imports_unresolved' \
    && no "#220 (I) the full legend pays for imports_unresolved= on a tree without one" || ok "#220 (I) the legend clause is absent where the attribute is"
grep -q 'graph_partial' "$TMP/tr.deps" && no "#220 (I) the compact legend pays for graph_partial= on a tree without one" \
    || ok "#220 (I) the compact graph_partial= term is absent where the attribute is"
"$BIN" "$TA" --deps --cache="$TMP/c220.bin" >"$TMP/ta.cold" 2>/dev/null
"$BIN" "$TA" --deps --cache="$TMP/c220.bin" >"$TMP/ta.warm" 2>/dev/null
cmp -s "$TMP/ta.cold" "$TMP/ta.warm" && cmp -s "$TMP/ta.cold" "$TMP/ta.deps" \
    && ok "#220 (I) deterministic, warm == cold" || no "#220 (I) warm != cold or non-deterministic"

# (220-J) WHY it is not a floor — CodeRabbit on PR #336. Two cycles c<->d and e<->f; d imports e (relative, resolved)
# and f imports c. Spelled `./c` the graph is complete: ONE cycle {c,d,e,f}, c.ts instab=0.33. Spelled as the workspace
# package `@m/c` the f->c edge is missing: TWO cycles, c.ts instab=0.50 — both ABOVE the complete answer, so a
# counts_floor="1" on that root claimed a lower bound that is false. The root must say partial, and nothing floor.
# Part 2 resolves a plain alias, so the missing edge here is one it still cannot draw: the member's `exports` sends
# `import` to c.ts and `require` to c2.ts, and the directive's syntax (which would decide) is not in the record (P2-E).
mkmerge() {   # mkmerge DIR SPEC — SPEC is how f.ts spells its import of c.ts
    rm -rf "$1"; mkdir -p "$1/src"
    printf '{ "private": true, "workspaces": ["src"] }\n' >"$1/package.json"
    printf '{ "name": "@m/c", "exports": { ".": { "import": "./c.ts", "require": "./c2.ts" } } }\n' >"$1/src/package.json"
    printf "export const c2 = 2;\n" >"$1/src/c2.ts"
    printf "import { d } from './d';\nexport function c(): number { return d(); }\n" >"$1/src/c.ts"
    printf "import { c } from './c';\nimport { e } from './e';\nexport function d(): number { return typeof c === 'function' ? e() : 0; }\n" >"$1/src/d.ts"
    printf "import { f } from './f';\nexport function e(): number { return f(); }\n" >"$1/src/e.ts"
    printf "import { e } from './e';\nimport { c } from '%s';\nexport function f(): number { return typeof e === 'function' ? 1 : 0; }\n" "$2" >"$1/src/f.ts"
}
TMA="$TMP/ts-merge-alias"; TMR="$TMP/ts-merge-rel"; mkmerge "$TMA" '@m/c'; mkmerge "$TMR" './c'
"$BIN" "$TMA" --deps --no-cache >"$TMP/tma.deps" 2>/dev/null
"$BIN" "$TMR" --deps --no-cache >"$TMP/tmr.deps" 2>/dev/null
CYA="$( grep -o '<cycle ' "$TMP/tma.deps" | wc -l | tr -d ' ' )"; CYR="$( grep -o '<cycle ' "$TMP/tmr.deps" | wc -l | tr -d ' ' )"
IA="$( sed -n 's/.*<f p="src\/c.ts" [^>]*instab="\([0-9.]*\)".*/\1/p' "$TMP/tma.deps" )"
IR="$( sed -n 's/.*<f p="src\/c.ts" [^>]*instab="\([0-9.]*\)".*/\1/p' "$TMP/tmr.deps" )"
{ [ "$CYA" = 2 ] && [ "$CYR" = 1 ] && [ "$IA" = 0.50 ] && [ "$IR" = 0.33 ]; } \
    && ok "#220 (J) the missing edge MERGES: 2 cycles over resolved edges vs 1 complete; c.ts instab 0.50 vs 0.33 — neither a floor" \
    || no "#220 (J) merge fixture did not reproduce (cycles alias=$CYA rel=$CYR, instab alias=$IA rel=$IR) — nothing measured"
partial_root 1 "$( root_of "$TMP/tma.deps" )" \
    && ok "#220 (J) so its root says graph_partial=\"1\" and claims no counts_floor" \
    || no "#220 (J) merge tree root claims a floor it does not have — got: $( root_of "$TMP/tma.deps" )"
grep -q 'imports_unresolved=\|graph_partial=\|counts_floor=' "$TMP/tmr.deps" && no "#220 (J) the complete (relative) spelling carries a disclosure" \
    || ok "#220 (J) the complete (relative) spelling carries none"
command -v xmllint >/dev/null 2>&1 \
  && { xmllint --noout "$TMP/ta.deps" 2>/dev/null && xmllint --noout "$TMP/ta.arch" 2>/dev/null && ok "#220 (I) xml well-formed" || no "#220 (I) xml malformed"; } \
  || ok "#220 (I) xml well-formed (xmllint absent — skipped)"

# ── #220 part 2: those imports RESOLVE — the config says where, so they are edges ──────────────────────────────────────
# resolve.h tsimport::ImportResolver reads what tsc reads: `paths` (the one best key, targets in order, from baseUrl or
# the declaring config), `baseUrl`, and workspace packages (package.json `workspaces` array / {packages}, pnpm-workspace.yaml)
# through `exports` (the `.` entry and subpaths, `*` patterns, import/require/default conditions, `types` never taken,
# a null target not exported), else `module`/`main`, else `index`, mapping an emitted `dist/` entry back to its source
# through the package's own outDir→rootDir. A resolved import is an edge in every file-graph answer; what still cannot be
# resolved stays counted (the arms above). Every arm is RED on the part-1 binary (22a8b478): it counted these, drew none.
d220() { "$BIN" "$1" --deps --no-cache 2>/dev/null; }
ncyc() { grep -o '<cycle ' "$1" | wc -l | tr -d ' '; }
blk()  { sed -n "s/.*\(<$2[ >].*<\/$2>\).*/\1/p" "$1" | sed 's/<\/'"$2"'>.*/<\/'"$2"'>/'; }
mk220() {   # mk220 DIR alias|relative — issue #220's own reproduction, verbatim: pnpm, `@/*` paths, an `exports` map onto dist/
    local D="$1" AB="@/b" AA="@/a" SH="@acme/shared"
    [ "$2" = relative ] && { AB="./b"; AA="./a"; SH="../../shared/src/index"; }
    rm -rf "$D"; mkdir -p "$D/packages/shared/src" "$D/packages/app/src"
    printf "packages:\n  - 'packages/*'\n" >"$D/pnpm-workspace.yaml"
    printf '{ "name": "@acme/shared", "main": "dist/index.js",\n  "exports": { ".": { "types": "./dist/index.d.ts", "default": "./dist/index.js" } } }\n' >"$D/packages/shared/package.json"
    printf '{ "compilerOptions": { "rootDir": "src", "outDir": "dist", "module": "node20", "moduleResolution": "node16" } }\n' >"$D/packages/shared/tsconfig.json"
    printf "export { helper } from './helper';\n" >"$D/packages/shared/src/index.ts"
    printf "export function helper(): number { return 1; }\n" >"$D/packages/shared/src/helper.ts"
    printf '{ "name": "@acme/app", "dependencies": { "@acme/shared": "workspace:*" } }\n' >"$D/packages/app/package.json"
    printf '{ "compilerOptions": { "rootDir": "src", "outDir": "dist", "module": "node20", "moduleResolution": "node16",\n  "paths": { "@/*": ["./src/*"] } } }\n' >"$D/packages/app/tsconfig.json"
    printf "import { b } from '%s';  import { helper } from '%s';  export function a() { return b() + helper(); }\n" "$AB" "$SH" >"$D/packages/app/src/a.ts"
    printf "import { a } from '%s';  export function b() { return typeof a === 'function' ? 1 : 0; }\n" "$AA" >"$D/packages/app/src/b.ts"
    printf "import { d } from './d';  export function c() { return d(); }\n" >"$D/packages/app/src/c.ts"
    printf "import { c } from './c';  export function d() { return typeof c === 'function' ? 1 : 0; }\n" >"$D/packages/app/src/d.ts"
}
w220() { mkdir -p "$( dirname "$1" )"; printf '%b' "$2" >"$1"; }

# (P2-A) #220's own tree: the aliased a<->b cycle is FOUND — cycles exact (2), no count, no floor — and the cycle and god-file
# blocks are byte-identical to the relative spelling of the same tree (`@acme/shared` reaches src/index.ts through exports
# → dist/index.js → outDir→rootDir → src/index.js → .ts).
I2A="$TMP/p2-issue"; I2R="$TMP/p2-issue-rel"; mk220 "$I2A" alias; mk220 "$I2R" relative
d220 "$I2A" >"$TMP/p2a.deps"; d220 "$I2R" >"$TMP/p2r.deps"
{ [ "$( ncyc "$TMP/p2a.deps" )" = 2 ] && ! grep -q 'imports_unresolved=\|counts_floor=\|graph_partial=' "$TMP/p2a.deps"; } \
    && ok "#220 (P2-A) issue tree: cycles exact (2: a<->b through @/ and c<->d), no imports_unresolved=, no counts_floor=" \
    || no "#220 (P2-A) issue tree: $( ncyc "$TMP/p2a.deps" ) cycle(s), root $( root_of "$TMP/p2a.deps" )"
{ [ -n "$( blk "$TMP/p2a.deps" cycles )" ] && [ "$( blk "$TMP/p2a.deps" cycles )" = "$( blk "$TMP/p2r.deps" cycles )" ] \
  && [ "$( blk "$TMP/p2a.deps" godfiles )" = "$( blk "$TMP/p2r.deps" godfiles )" ]; } \
    && ok "#220 (P2-A) the alias and relative spellings give byte-identical <cycles> and <godfiles>" \
    || no "#220 (P2-A) alias vs relative spelling differ: $( blk "$TMP/p2a.deps" godfiles ) vs $( blk "$TMP/p2r.deps" godfiles )"
grep -q '<f p="packages/shared/src/index.ts" afferent="1"/>' "$TMP/p2a.deps" \
    && ok "#220 (P2-A) @acme/shared lands on packages/shared/src/index.ts (exports → dist → rootDir)" \
    || no "#220 (P2-A) @acme/shared did not reach packages/shared/src/index.ts"
# the same edges in the other file-graph answers: --report's cycle line, --impact's importer tier, --arch's judgement
"$BIN" "$I2A" --report --no-cache 2>/dev/null | grep -q '^## Dependency cycles (showing 2 of 2)$' \
    && ok "#220 (P2-A) --report: (showing 2 of 2), no floor" || no "#220 (P2-A) --report cycle line wrong"
"$BIN" "$I2A" --impact=packages/app/src/b.ts:b --no-cache 2>/dev/null | grep -q 'importers="1" shown_importers="1" importers_capped="0" radius' \
    && ok "#220 (P2-A) --impact importer tier: importers=\"1\" (a.ts through @/b), no imports_unresolved=" \
    || no "#220 (P2-A) --impact importer tier did not see the aliased importer"
printf 'layer app = packages/app\nlayer shared = packages/shared\ndeny app -> shared\n' >"$TMP/rules220b.txt"
"$BIN" "$I2A" --arch="$TMP/rules220b.txt" --no-cache >"$TMP/p2a.arch" 2>/dev/null; RC2A=$?
"$BIN" "$I2R" --arch="$TMP/rules220b.txt" --no-cache >/dev/null 2>&1; RC2R=$?
{ [ "$RC2A" = 2 ] && [ "$RC2R" = 2 ] && grep -q 'violations="1"' "$TMP/p2a.arch"; } \
    && ok "#220 (P2-A) --arch deny app -> shared: the workspace import is judged — exit 2 like the relative copy" \
    || no "#220 (P2-A) --arch exit alias=$RC2A relative=$RC2R (want 2/2)"

# (P2-B) paths: one key wins (exact before the longest-prefix wildcard), targets in ORDER — the first missing, the second
# answers; when both answer, the first wins; a `.js` specifier names its `.ts` source.
D="$TMP/p2-paths"
w220 "$D/tsconfig.json" '{ "compilerOptions": { "paths": { "@lib/*": ["gen/*", "src/lib/*"], "@both/*": ["src/one/*", "src/two/*"], "@/*": ["src/*"], "@/cfg": ["src/one/cfg"] } } }\n'
w220 "$D/src/lib/x.ts" "import { a } from '@/a.js';\nexport const x = a;\n"
w220 "$D/src/a.ts" "import { x } from '@lib/x';\nimport { y } from '@both/y';\nimport { c } from '@/cfg';\nexport const a = x + y + c;\n"
w220 "$D/src/one/y.ts" "export const y = 1;\n"; w220 "$D/src/two/y.ts" "export const y = 2;\n"; w220 "$D/src/one/cfg.ts" "export const c = 1;\n"; w220 "$D/src/cfg.ts" "export const c = 2;\n"
d220 "$D" >"$TMP/p2b.deps"
{ [ "$( ncyc "$TMP/p2b.deps" )" = 1 ] && grep -q '<f p="src/one/y.ts" afferent="1"/>' "$TMP/p2b.deps" && grep -q '<f p="src/one/cfg.ts" afferent="1"/>' "$TMP/p2b.deps" \
  && ! grep -q 'src/two/y.ts\|p="src/cfg.ts"' "$TMP/p2b.deps" && ! grep -q 'imports_unresolved=' "$TMP/p2b.deps"; } \
    && ok "#220 (P2-B) paths: 2nd target answers when the 1st is missing (a<->x cycle via @/a.js), 1st wins when both do, exact key beats @/*" \
    || no "#220 (P2-B) paths arm wrong — $( blk "$TMP/p2b.deps" godfiles )"

# (P2-C) baseUrl alone: a bare path under it is a file of this tree (tsc tries it before node_modules); react is not.
D="$TMP/p2-base"
w220 "$D/tsconfig.json" '{ "compilerOptions": { "baseUrl": "src" } }\n'
w220 "$D/src/lib/util.ts" "import { a } from 'app';\nexport const u = a;\n"; w220 "$D/src/app.ts" "import { u } from 'lib/util';\nimport React from 'react';\nexport const a = u;\n"
d220 "$D" >"$TMP/p2c.deps"
{ [ "$( ncyc "$TMP/p2c.deps" )" = 1 ] && ! grep -q 'imports_unresolved=\|counts_floor=\|graph_partial=' "$TMP/p2c.deps"; } \
    && ok "#220 (P2-C) baseUrl: lib/util <-> app is a cycle; react stays external (no count)" || no "#220 (P2-C) baseUrl arm — $( root_of "$TMP/p2c.deps" )"

# (P2-D) npm workspaces (array form) through `exports`: the `.` entry by condition (types skipped), a subpath, a `*` pattern;
# a subpath mapped to null is NOT exported, so it stays unresolved and is counted (1).
D="$TMP/p2-npm"
w220 "$D/package.json" '{ "name": "root", "private": true, "workspaces": ["packages/*"] }\n'
w220 "$D/packages/lib/package.json" '{ "name": "@acme/lib", "exports": { ".": { "types": "./src/index.d.ts", "import": "./src/index.ts", "require": "./src/index.ts" }, "./util": "./src/util.ts", "./feat/*": "./src/feat/*.ts", "./internal/*": null } }\n'
w220 "$D/packages/lib/src/index.ts" "import { app } from '@acme/app';\nexport const lib = app;\n"; w220 "$D/packages/lib/src/index.d.ts" "export declare const lib: number;\n"
w220 "$D/packages/lib/src/util.ts" "export const util = 1;\n"; w220 "$D/packages/lib/src/feat/f.ts" "export const f = 1;\n"; w220 "$D/packages/lib/src/internal/i.ts" "export const i = 1;\n"
w220 "$D/packages/app/package.json" '{ "name": "@acme/app", "main": "src/main.ts" }\n'
w220 "$D/packages/app/src/main.ts" "import { lib } from '@acme/lib';\nimport { util } from '@acme/lib/util';\nimport { f } from '@acme/lib/feat/f';\nimport { i } from '@acme/lib/internal/i';\nexport const app = lib + util + f + i;\n"
d220 "$D" >"$TMP/p2d.deps"
{ [ "$( ncyc "$TMP/p2d.deps" )" = 1 ] && grep -q 'imports_unresolved="1" graph_partial="1"' "$TMP/p2d.deps" \
  && grep -q '<f p="packages/lib/src/util.ts" afferent="1"/>' "$TMP/p2d.deps" && grep -q '<f p="packages/lib/src/feat/f.ts" afferent="1"/>' "$TMP/p2d.deps" \
  && ! grep -q 'internal/i.ts\|index.d.ts' "$TMP/p2d.deps"; } \
    && ok "#220 (P2-D) npm workspaces + exports: . (import, types skipped), ./util, ./feat/* resolve; ./internal/* is null → counted (1)" \
    || no "#220 (P2-D) npm/exports arm — $( root_of "$TMP/p2d.deps" ) $( blk "$TMP/p2d.deps" godfiles )"

# (P2-E) yarn's {packages} form with a `**` glob; entries that name EMITTED files map back through the package's own
# outDir→rootDir (`module` before `main`; exports import and require agreeing on one source).
D="$TMP/p2-yarn"
w220 "$D/package.json" '{ "private": true, "workspaces": { "packages": ["libs/**"] } }\n'
w220 "$D/libs/core/package.json" '{ "name": "core", "main": "dist/index.js", "module": "dist/index.mjs" }\n'
w220 "$D/libs/core/tsconfig.json" '{ "compilerOptions": { "outDir": "dist", "rootDir": "src" } }\n'
w220 "$D/libs/core/src/index.ts" "import { ui } from 'ui';\nexport const core = ui;\n"
w220 "$D/libs/nested/ui/package.json" '{ "name": "ui", "exports": { ".": { "import": "./dist/esm/index.js", "require": "./dist/esm/index.js" } } }\n'
w220 "$D/libs/nested/ui/tsconfig.json" '{ "compilerOptions": { "outDir": "dist/esm", "rootDir": "src" } }\n'
w220 "$D/libs/nested/ui/src/index.ts" "import { core } from 'core';\nexport const ui = core;\n"
d220 "$D" >"$TMP/p2e.deps"
{ [ "$( ncyc "$TMP/p2e.deps" )" = 1 ] && ! grep -q 'imports_unresolved=' "$TMP/p2e.deps"; } \
    && ok "#220 (P2-E) yarn {packages} + libs/**: core <-> ui through dist/ → src/ (main, exports) is a cycle" \
    || no "#220 (P2-E) yarn arm — $( root_of "$TMP/p2e.deps" )"
# exports import vs require naming two DIFFERENT sources: the directive's syntax would decide, the record does not keep it
w220 "$D/libs/nested/ui/package.json" '{ "name": "ui", "exports": { ".": { "import": "./src/index.ts", "require": "./src/other.ts" } } }\n'
w220 "$D/libs/nested/ui/src/other.ts" "export const other = 1;\n"
if grep -q 'other.ts' "$D/libs/nested/ui/package.json"; then
    d220 "$D" >"$TMP/p2e2.deps"
    { [ "$( ncyc "$TMP/p2e2.deps" )" = 0 ] && grep -q 'imports_unresolved="1" graph_partial="1"' "$TMP/p2e2.deps"; } \
        && ok "#220 (P2-E) exports import/require naming two files: ambiguous → no edge, counted (1)" \
        || no "#220 (P2-E) import/require disagreement guessed — $( root_of "$TMP/p2e2.deps" )"
else
    no "#220 (P2-E) the import/require mutation did not take — nothing measured"
fi

# (P2-F) pnpm-workspace.yaml (block list, both quote styles) with an `exports` string.
D="$TMP/p2-pnpm"
w220 "$D/pnpm-workspace.yaml" "packages:\n  - 'apps/*'\n  - \"pkgs/*\"\n"
w220 "$D/pkgs/shared/package.json" '{ "name": "@p/shared", "exports": "./index.ts" }\n'
w220 "$D/pkgs/shared/index.ts" "import { web } from '@p/web';\nexport const s = web;\n"
w220 "$D/apps/web/package.json" '{ "name": "@p/web" }\n'; w220 "$D/apps/web/index.ts" "import { s } from '@p/shared';\nexport const web = s;\n"
d220 "$D" >"$TMP/p2f.deps"
{ [ "$( ncyc "$TMP/p2f.deps" )" = 1 ] && ! grep -q 'imports_unresolved=' "$TMP/p2f.deps"; } \
    && ok "#220 (P2-F) pnpm workspace: exports string and the default index resolve (web <-> shared cycle)" || no "#220 (P2-F) pnpm arm — $( root_of "$TMP/p2f.deps" )"

# (P2-G) a PACKAGE-form extends read from the tree's node_modules (and its own relative extends): its `paths` under the
# child's baseUrl resolve. With node_modules absent the base is unread: tsconfig_unread="1" graph_partial="1", defined.
D="$TMP/p2-extpkg"
w220 "$D/tsconfig.json" '{ "extends": "@acme/tsconfig/base.json", "compilerOptions": { "baseUrl": "." } }\n'
w220 "$D/node_modules/@acme/tsconfig/base.json" '{ "extends": "./inner", "compilerOptions": { "strict": true } }\n'
w220 "$D/node_modules/@acme/tsconfig/inner.json" '{ "compilerOptions": { "paths": { "~/*": ["src/*"] } } }\n'
w220 "$D/src/a.ts" "import { b } from '~/b';\nexport const a = b;\n"; w220 "$D/src/b.ts" "import { a } from '~/a';\nexport const b = a;\n"
d220 "$D" >"$TMP/p2g.deps"
{ [ "$( ncyc "$TMP/p2g.deps" )" = 1 ] && ! grep -q 'tsconfig_unread=\|counts_floor=\|graph_partial=' "$TMP/p2g.deps"; } \
    && ok "#220 (P2-G) extends @acme/tsconfig/base.json → ./inner from node_modules: ~/a <-> ~/b is a cycle" || no "#220 (P2-G) package extends not followed — $( root_of "$TMP/p2g.deps" )"
rm -rf "$D/node_modules"
d220 "$D" >"$TMP/p2g2.deps"
{ [ "$( ncyc "$TMP/p2g2.deps" )" = 0 ] && grep -q 'tsconfig_unread="1" graph_partial="1"' "$TMP/p2g2.deps" && grep -q 'tsconfig_unread=N' "$TMP/p2g2.deps" \
  && "$BIN" "$D" --deps --no-cache --legend=full 2>/dev/null | grep -q 'tsconfig_unread=N graph_partial=1'; } \
    && ok "#220 (P2-G) the package not installed: tsconfig_unread=\"1\" graph_partial=\"1\", in the compact and full legends" \
    || no "#220 (P2-G) an unread extends base was not disclosed — $( root_of "$TMP/p2g2.deps" )"

# (P2-H) two workspace members declaring ONE name: never choose — no edge, counted.
D="$TMP/p2-dup"
w220 "$D/package.json" '{ "workspaces": ["a/*", "b/*"] }\n'
w220 "$D/a/one/package.json" '{ "name": "dup", "main": "index.ts" }\n'; w220 "$D/a/one/index.ts" "export const one = 1;\n"
w220 "$D/b/two/package.json" '{ "name": "dup", "main": "index.ts" }\n'; w220 "$D/b/two/index.ts" "export const two = 2;\n"
w220 "$D/a/app/package.json" '{ "name": "app" }\n'; w220 "$D/a/app/index.ts" "import { one } from 'dup';\nexport const x = one;\n"
d220 "$D" >"$TMP/p2h.deps"
{ grep -q 'imports_unresolved="1" graph_partial="1"' "$TMP/p2h.deps" && ! grep -q '<godfiles total=\|p="a/one/\|p="b/two/' "$TMP/p2h.deps"; } \
    && ok "#220 (P2-H) ambiguous name (two members named dup): unresolved, counted (1), no edge" || no "#220 (P2-H) ambiguous name arm — $( root_of "$TMP/p2h.deps" )"

# (P2-I) an external package never resolves by name coincidence: react beside an in-repo src/react/, lodash beside a
# package.json named lodash that no workspace glob admits, node:fs — no edge, no count. (./react is the control.)
D="$TMP/p2-ext"
w220 "$D/package.json" '{ "workspaces": ["packages/*"] }\n'
w220 "$D/tsconfig.json" '{ "compilerOptions": { "paths": { "@/*": ["src/*"] } } }\n'
w220 "$D/src/react/index.ts" "export const r = 1;\n"; w220 "$D/src/lodash.ts" "export const l = 1;\n"
w220 "$D/examples/lodash/package.json" '{ "name": "lodash", "main": "index.ts" }\n'; w220 "$D/examples/lodash/index.ts" "export const l = 2;\n"
w220 "$D/src/a.ts" "import React from 'react';\nimport _ from 'lodash';\nimport fs from 'node:fs';\nimport { r } from './react';\nexport const a = r;\n"
d220 "$D" >"$TMP/p2i.deps"
{ ! grep -q 'imports_unresolved=\|counts_floor=\|graph_partial=\|p="examples/\|p="src/lodash' "$TMP/p2i.deps" && grep -q '<f p="src/react/index.ts" afferent="1"/>' "$TMP/p2i.deps"; } \
    && ok "#220 (P2-I) react/lodash/node:fs: no edge, no count (only the relative ./react control resolves)" || no "#220 (P2-I) an external package resolved in-repo — $( blk "$TMP/p2i.deps" godfiles )"

# (P2-J) a declaration only when no source answers, and disclosed: @t/x → types/x.d.ts is imports_dts="1"; @s/y has both
# y.ts and y.d.ts and lands on the source.
D="$TMP/p2-dts"
w220 "$D/tsconfig.json" '{ "compilerOptions": { "paths": { "@t/*": ["types/*"], "@s/*": ["src/*"] } } }\n'
w220 "$D/types/x.d.ts" "export declare const x: number;\n"; w220 "$D/src/y.ts" "export const y = 1;\n"; w220 "$D/src/y.d.ts" "export declare const y: number;\n"
w220 "$D/src/a.ts" "import { x } from '@t/x';\nimport { y } from '@s/y';\nexport const a = x + y;\n"
d220 "$D" >"$TMP/p2j.deps"
{ grep -q 'imports_dts="1"' "$TMP/p2j.deps" && ! grep -q 'counts_floor=\|graph_partial=' "$TMP/p2j.deps" && grep -q '<f p="src/y.ts" afferent="1"/>' "$TMP/p2j.deps" \
  && grep -q 'imports_dts=N' "$TMP/p2j.deps"; } \
    && ok "#220 (P2-J) .d.ts fallback: imports_dts=\"1\" (no floor, defined); source beats its declaration" || no "#220 (P2-J) declaration arm — $( root_of "$TMP/p2j.deps" )"

# (P2-K) determinism: warm == cold == --no-cache on the issue tree; well-formed.
"$BIN" "$I2A" --deps --cache="$TMP/c220b.bin" >"$TMP/p2a.cold" 2>/dev/null
"$BIN" "$I2A" --deps --cache="$TMP/c220b.bin" >"$TMP/p2a.warm" 2>/dev/null
{ cmp -s "$TMP/p2a.cold" "$TMP/p2a.warm" && cmp -s "$TMP/p2a.cold" "$TMP/p2a.deps"; } && ok "#220 (P2-K) deterministic, warm == cold" || no "#220 (P2-K) warm != cold"
command -v xmllint >/dev/null 2>&1 \
  && { xmllint --noout "$TMP/p2a.deps" "$TMP/p2g2.deps" "$TMP/p2j.deps" 2>/dev/null && ok "#220 (P2-K) xml well-formed" || no "#220 (P2-K) xml malformed"; } \
  || ok "#220 (P2-K) xml well-formed (xmllint absent — skipped)"

# (P2-L) pnpm-workspace.yaml's FLOW list: `packages: [...]` on one line, and spanning lines (both quote styles, a
# trailing comma, a comment) — the same members as the block list in P2-F. An empty item admits nothing.
for FORM in one multi; do
    D="$TMP/p2-pnpmflow-$FORM"
    if [ "$FORM" = one ]; then w220 "$D/pnpm-workspace.yaml" "packages: ['apps/*', \"pkgs/*\"]  # flow\n"
    else w220 "$D/pnpm-workspace.yaml" "packages:\n  [\n    'apps/*', # web\n    \"pkgs/*\",\n    '',\n  ]\nonlyBuiltDependencies:\n  - esbuild\n"; fi
    w220 "$D/pkgs/shared/package.json" '{ "name": "@p/shared", "exports": "./index.ts" }\n'
    w220 "$D/pkgs/shared/index.ts" "import { web } from '@p/web';\nexport const s = web;\n"
    w220 "$D/apps/web/package.json" '{ "name": "@p/web" }\n'; w220 "$D/apps/web/index.ts" "import { s } from '@p/shared';\nexport const web = s;\n"
    d220 "$D" >"$TMP/p2l-$FORM.deps"
    { [ "$( ncyc "$TMP/p2l-$FORM.deps" )" = 1 ] && ! grep -q 'imports_unresolved=\|graph_partial=' "$TMP/p2l-$FORM.deps"; } \
        && ok "#220 (P2-L) pnpm flow list ($FORM line): web <-> shared cycle, nothing unresolved" \
        || no "#220 (P2-L) pnpm flow list ($FORM line) not read — $( root_of "$TMP/p2l-$FORM.deps" )"
done

# (P2-M) asset imports through an alias: a stylesheet, an image with a bundler `?query`, a missing stylesheet name no
# module of the import graph, so they are never counted; an indexed data file (`.json`) is an edge like a relative
# import's; a `.vue` component is code the crawl does not index, so it stays counted (disclosed, not dropped).
D="$TMP/p2-asset"
w220 "$D/tsconfig.json" '{ "compilerOptions": { "baseUrl": ".", "paths": { "@/*": ["src/*"] } } }\n'
w220 "$D/src/a.ts" "import '@/styles/globals.css';\nimport Logo from '@/logo.SVG?react';\nimport '@/gone.scss';\nimport data from '@/data.json';\nimport C from '@/Comp.vue';\nexport const a = data;\n"
w220 "$D/src/styles/globals.css" "body {}\n"; w220 "$D/src/logo.SVG" "<svg/>\n"; w220 "$D/src/data.json" '{ "a": 1 }\n'
w220 "$D/src/Comp.vue" "<template><div/></template>\n"
d220 "$D" >"$TMP/p2m.deps"
{ grep -q '<f p="src/data.json" afferent="1"/>' "$TMP/p2m.deps" && [ "$( root_of "$TMP/p2m.deps" | grep -o 'imports_unresolved="[0-9]*"' )" = 'imports_unresolved="1"' ]; } \
    && ok "#220 (P2-M) assets: css/svg?query/missing scss not counted, @/data.json an edge, the unindexed .vue counted (1)" \
    || no "#220 (P2-M) asset arm — $( root_of "$TMP/p2m.deps" ) $( blk "$TMP/p2m.deps" godfiles )"

# (P2-N) tsconfig `references`: create-vite's layout — tsconfig.json is `files: []` plus references to tsconfig.app.json
# (which holds `paths` and includes src/) and tsconfig.node.json (vite.config.ts only). src/ is owned by the app project,
# so @/a <-> @/b is a cycle; vite.config.ts is owned by the node project, which declares no alias, so its '@/a' is
# neither an edge nor counted (tsc would not resolve it there either).
mkvite() {   # mkvite DIR — the create-vite layout
    rm -rf "$1"
    w220 "$1/tsconfig.json" '{\n  "files": [],\n  "references": [ { "path": "./tsconfig.app.json" }, { "path": "./tsconfig.node.json" } ]\n}\n'
    w220 "$1/tsconfig.app.json" '{ "compilerOptions": { "baseUrl": ".", "paths": { "@/*": ["./src/*"] } }, "include": ["src"] }\n'
    w220 "$1/tsconfig.node.json" '{ "compilerOptions": { "strict": true }, "include": ["vite.config.ts"] }\n'
    w220 "$1/src/a.ts" "import { b } from '@/b';\nexport const a = b;\n"; w220 "$1/src/b.ts" "import { a } from '@/a';\nexport const b = a;\n"
    w220 "$1/vite.config.ts" "import { a } from '@/a';\nexport default a;\n"
}
D="$TMP/p2-vite"; mkvite "$D"
d220 "$D" >"$TMP/p2n.deps"
{ [ "$( ncyc "$TMP/p2n.deps" )" = 1 ] && ! grep -q 'imports_unresolved=\|graph_partial=\|tsconfig_unread=' "$TMP/p2n.deps" && grep -q '<f p="vite.config.ts" includes="1" afferent="0" instab="0.00" transitive="1">' "$TMP/p2n.deps"; } \
    && ok "#220 (P2-N) references (create-vite): src/ resolves under tsconfig.app.json (a <-> b cycle); vite.config.ts under the node project draws nothing" \
    || no "#220 (P2-N) references not followed — $( ncyc "$TMP/p2n.deps" ) cycle(s), $( root_of "$TMP/p2n.deps" )"
# two referenced projects hold src/ and disagree on @/*: never choose — no edge, counted
w220 "$D/tsconfig.test.json" '{ "compilerOptions": { "paths": { "@/*": ["./test/*"] } }, "include": ["src", "test"] }\n'
w220 "$D/test/a.ts" "export const a = 0;\n"; w220 "$D/test/b.ts" "export const b = 0;\n"
w220 "$D/tsconfig.json" '{ "files": [], "references": [ { "path": "./tsconfig.app.json" }, { "path": "./tsconfig.node.json" }, { "path": "./tsconfig.test.json" } ] }\n'
d220 "$D" >"$TMP/p2n2.deps"
{ [ "$( ncyc "$TMP/p2n2.deps" )" = 0 ] && grep -q 'imports_unresolved="2" graph_partial="1"' "$TMP/p2n2.deps"; } \
    && ok "#220 (P2-N) two projects hold src/ and resolve @/* apart: ambiguous, counted (2), no edge" \
    || no "#220 (P2-N) overlapping projects guessed — $( root_of "$TMP/p2n2.deps" )"
# a reference the crawl did not index could own the file: disclosed as tsconfig_unread, not guessed
mkvite "$D"; rm -f "$D/tsconfig.app.json"
d220 "$D" >"$TMP/p2n3.deps"
{ [ "$( ncyc "$TMP/p2n3.deps" )" = 0 ] && grep -q 'tsconfig_unread="1" graph_partial="1"' "$TMP/p2n3.deps"; } \
    && ok "#220 (P2-N) a referenced project not in the tree: tsconfig_unread=\"1\" graph_partial=\"1\"" \
    || no "#220 (P2-N) an unread reference was not disclosed — $( root_of "$TMP/p2n3.deps" )"
# the same disclosure on the other file-graph answers: --report's cycle line, --impact's importer tier (CLI XML/JSON)
"$BIN" "$D" --report --no-cache 2>/dev/null | grep -q '^## Dependency cycles (showing 0 of 0; measured over resolved edges: 0 imports unresolved, 1 tsconfig files unread)$' \
    && ok "#220 (P2-N) --report: the cycle line is qualified by the unread project (never '(acyclic)')" || no "#220 (P2-N) --report cycle line unqualified"
w220 "$D/src/b.ts" "import { a } from '@/a';\nexport function b() { return typeof a; }\n"
"$BIN" "$D" --impact=src/b.ts:b --no-cache >"$TMP/p2n3.imp" 2>/dev/null
{ grep -q 'importers="0" shown_importers="0" importers_capped="0" tsconfig_unread="1"' "$TMP/p2n3.imp" && grep -q 'counts_floor="1"' "$TMP/p2n3.imp" \
  && grep -q 'tsconfig_unread=N' "$TMP/p2n3.imp" && "$BIN" "$D" --impact=src/b.ts:b --no-cache --json 2>/dev/null | grep -q '"tsconfig_unread":1'; } \
    && ok "#220 (P2-N) --impact importer tier: tsconfig_unread=\"1\" beside counts_floor, defined; the JSON key too" \
    || no "#220 (P2-N) --impact did not disclose the unread project"

# (P2-O) RE-EXPORTS are imports (kParserVer 124): a barrel `index.ts` made of `export … from` lines. Relative: a.ts
# imports the barrel, the barrel re-exports b.ts, b.ts imports a.ts — one 3-file cycle, found only through the barrel.
# Aliased: the same through `@/` (paths) and `export *`/`export * as`/`export type` forms. Part 1 and the pre-124 part 2
# drew no edge out of a barrel, so both trees read acyclic, silently.
for SP in rel alias; do
    D="$TMP/p2-barrel-$SP"; P="./"; [ "$SP" = alias ] && P="@/"
    [ "$SP" = alias ] && w220 "$D/tsconfig.json" '{ "compilerOptions": { "paths": { "@/*": ["./src/*"] } } }\n'
    w220 "$D/src/index.ts" "export { b } from '${P}b';\nexport * from '${P}c';\nexport * as dns from '${P}d';\nexport type { T } from '${P}t';\nexport function local() { return 1; }\n"
    w220 "$D/src/a.ts" "import { b } from '${P}index';\nexport function a() { return b(); }\n"
    w220 "$D/src/b.ts" "import { a } from '${P}a';\nexport function b() { return typeof a; }\n"
    w220 "$D/src/c.ts" "export const c = 1;\n"; w220 "$D/src/d.ts" "export const d = 1;\n"; w220 "$D/src/t.ts" "export type T = number;\n"
    d220 "$D" >"$TMP/p2o-$SP.deps"
    { [ "$( ncyc "$TMP/p2o-$SP.deps" )" = 1 ] && grep -q '<cycle size="3"' "$TMP/p2o-$SP.deps" && grep -q '<f p="src/index.ts" includes="4" ' "$TMP/p2o-$SP.deps" \
      && ! grep -q 'imports_unresolved=\|graph_partial=' "$TMP/p2o-$SP.deps"; } \
        && ok "#220 (P2-O) re-exports ($SP): the barrel's 4 export…from lines are edges; a -> index -> b -> a is one 3-file cycle" \
        || no "#220 (P2-O) re-exports ($SP) drew no edge — $( ncyc "$TMP/p2o-$SP.deps" ) cycle(s), $( grep -o '<f p="src/index.ts"[^>]*>' "$TMP/p2o-$SP.deps" )"
done

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
