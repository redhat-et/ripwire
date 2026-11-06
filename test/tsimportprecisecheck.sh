#!/usr/bin/env bash
# tsimportprecisecheck.sh — LEVER-B B2 gate: path-precise TS/JS import resolution.
#
# The precise SameInclude tier now has a TS/JS Step-A (resolve.h::resolveTsImport): a RELATIVE specifier
# `import {Z} from './x'` / `'../a/b'` resolves to the ONE repo file it names by PATH relative-to-includer,
# trying a FIXED extension list (.ts/.tsx/.js/.jsx/…) then index files, on a UNIQUE hit — else it degrades.
# A BARE specifier (`from 'react'` — node_modules/external) is left UNRESOLVED (the angle-include analogue).
# Same "unique-or-degrade" discipline as the C-family quote-include tier.
#
# Fixture test/tsimportprecisefix — the soundness cases:
#   caller.ts        import {helper} from './x'   → helper() binds x.ts::helper       (NOT the decoy other/x.ts)
#                    import {widget} from './a/b'  → widget() binds a/b.ts::widget      (NOT the decoy other/b.ts)
#                    import {idxfn} from './idx'   → idxfn() binds idx/index.ts::idxfn  (index-file resolution)
#                    import React from 'react'     → createElement() UNRESOLVED         (bare/external, no false edge)
#   other/caller2.ts import {helper} from './x'    → helper() binds other/x.ts::helper  (path, not basename)
#
# Also asserts B0 clean-specifier capture (--deps shows `./x`, not the clause), MONOTONICITY, determinism,
# warm==cold, and well-formed XML.
#
# Usage:  test/tsimportprecisecheck.sh   |   RIPWIRE_BIN=asan/ripwire test/tsimportprecisecheck.sh
# Exits non-zero on any failure. Does NOT edit test/regression.sh or test/golden.xml.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/tsimportprecisefix"
. "$ROOT/test/lib/headbinlib.sh"                       # shared sha-keyed cache of the HEAD comparison binary
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "tsimportprecisecheck: BIN=$BIN  FIX=$FIX  TMP=$TMP"

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

# ── B2 path-precise resolution ────────────────────────────────────────────────────────────────────
callee_binds useHelper      'x.ts:'         'other/x.ts'  ; callee_count useHelper 1
callee_binds useWidget      'a/b.ts:'       'other/b.ts'  ; callee_count useWidget 1
callee_binds useIdx         'idx/index.ts:' ''            ; callee_count useIdx 1
callee_binds useOtherHelper 'other/x.ts:'   ''            ; callee_count useOtherHelper 1

# bare `from 'react'` → NO false edge (createElement is not an in-repo def).
"$BIN" "$FIX" --callees=useReact --no-cache >"$TMP/useReact.out" 2>/dev/null
callee_count useReact 0

# ── B0 clean specifier: --deps carries the quoted-path stripped to `./x`, not the whole clause ────
"$BIN" "$FIX" --deps --no-cache >"$TMP/deps.out" 2>/dev/null
grep -q '<inc t="./x"' "$TMP/deps.out" \
  && ok 'B0: import {helper} from "./x" → clean specifier t="./x"' \
  || { no 'B0: ./x specifier not captured cleanly'; grep -oE '<inc t="[^"]*"' "$TMP/deps.out" | sort -u; }
grep -q '<inc t="react"' "$TMP/deps.out" \
  && ok 'B0: bare `react` captured (and left external at resolve time)' \
  || no 'B0: bare react specifier missing'

# ── RUNTIME-EXTENSION specifiers: `./x.js` names x.ts (node16/nodenext), `.mjs`→`.mts`, `.cjs`→`.cts`,
# `.jsx`→`.tsx`/`.ts`, and — second tier, source before declaration — `.js`/`.mjs`/`.cjs`→`.d.ts`/`.d.mts`/
# `.d.cts` when only the declaration exists ─────────────────────────────────────────────────────────────────
# One importer file per case, so each row's instab= answers for exactly one specifier: a resolved import is an
# efferent edge (instab="1.00"), an unresolved one is not (instab="0.00"). Built under $TMP so the committed
# fixture's own arms above keep their counts. The guards (dual, jd, both, idx) hold on every binary: a tree
# carrying BOTH dual.js and dual.ts, or BOTH jd.tsx and jd.ts for one `.jsx` specifier, stays unresolved
# (unique-or-degrade — a known, deliberate divergence from tsc's ordered tie-break, not new to this lane);
# `./lib.js` never lands on lib/index.ts (TypeScript resolves neither); and `./both.js` with BOTH both.ts and
# both.d.ts on disk resolves to the SOURCE, never touching the declaration tier. Every row here is
# tsc-live-verified: tsc 7.0.2 (`~/.npm` global install, `--traceResolution`), node16/nodenext/bundler
# identical results — see src/resolve.h's kJsRuntimeSourceExts comment for the exact trace.
RX="$TMP/runtimeext"
mkdir -p "$RX/other" "$RX/lib"
printf 'export function helper() { return 1; }\n'  >"$RX/x.ts"
printf 'export function helper() { return 99; }\n' >"$RX/other/x.ts"
printf 'export function widget() { return 2; }\n'  >"$RX/w.tsx"
printf 'export function modfn() { return 3; }\n'   >"$RX/m.mts"
printf 'export function cjsfn() { return 4; }\n'   >"$RX/c.cts"
printf 'export function dual() { return 5; }\n'    >"$RX/dual.ts"
printf 'export function dual() { return 6; }\n'    >"$RX/dual.js"
printf 'export function libfn() { return 7; }\n'   >"$RX/lib/index.ts"
printf "import { helper } from './x.js';\nexport function useJs() { return helper(); }\n"     >"$RX/usejs.ts"
printf "import { widget } from './w.js';\nexport function useTsx() { return widget(); }\n"    >"$RX/usetsx.ts"
printf "import { modfn } from './m.mjs';\nexport function useMjs() { return modfn(); }\n"     >"$RX/usemjs.ts"
printf "import { cjsfn } from './c.cjs';\nexport function useCjs() { return cjsfn(); }\n"     >"$RX/usecjs.ts"
printf "import { dual } from './dual.js';\nexport function useDual() { return dual(); }\n"    >"$RX/usedual.ts"
printf "import { libfn } from './lib.js';\nexport function useLib() { return libfn(); }\n"    >"$RX/uselib.ts"
# .jsx source rows — tsc live-verified (tsc 7.0.2 --traceResolution, node16/nodenext/bundler identical):
# `./jx.jsx` -> jx.tsx (only .tsx present), `./jts.jsx` -> jts.ts (only .ts present, tsx absent).
printf 'export function jxfn() { return 10; }\n'   >"$RX/jx.tsx"
printf 'export function jtsfn() { return 11; }\n'  >"$RX/jts.ts"
printf "import { jxfn } from './jx.jsx';\nexport function useJx() { return jxfn(); }\n"       >"$RX/usejx.ts"
printf "import { jtsfn } from './jts.jsx';\nexport function useJts() { return jtsfn(); }\n"   >"$RX/usejts.ts"
# .jsx decoy/clash — BOTH jd.tsx and jd.ts on disk for one `./jd.jsx` specifier. tsc breaks this tie
# (jd.tsx wins, ordered preference); this table keeps the SAME unique-or-degrade discipline the pre-existing
# `.js`->{ts,tsx} row already ships (the `dual` row above), so two real source candidates stay unresolved
# rather than guess — a known, deliberate divergence from tsc, not new to this change.
printf 'export function jdfn() { return 12; }\n'   >"$RX/jd.tsx"
printf 'export function jdfn() { return 13; }\n'   >"$RX/jd.ts"
printf "import { jdfn } from './jd.jsx';\nexport function useJd() { return jdfn(); }\n"       >"$RX/usejd.ts"
# declaration fallback rows (second tier, tried only when NO source alternate exists) — tsc live-verified:
# `./d.js` with only `d.d.ts` on disk -> d.d.ts; `./dm.mjs` with only `dm.d.mts` -> dm.d.mts; `./dc.cjs` with
# only `dc.d.cts` -> dc.d.cts. Declared with `declare function`, the ambient form (function_signature in the
# TS grammar) queries/typescript/tags.scm already captures as @definition.function.
printf 'declare function dfn(): number;\n'         >"$RX/d.d.ts"
printf 'declare function dmfn(): number;\n'        >"$RX/dm.d.mts"
printf 'declare function dcfn(): number;\n'        >"$RX/dc.d.cts"
printf "import { dfn } from './d.js';\nexport function useDecl() { return dfn(); }\n"         >"$RX/usedecl.ts"
printf "import { dmfn } from './dm.mjs';\nexport function useDm() { return dmfn(); }\n"       >"$RX/usedm.ts"
printf "import { dcfn } from './dc.cjs';\nexport function useDc() { return dcfn(); }\n"       >"$RX/usedc.ts"
# source-before-declaration precedence — tsc live-verified: `./both.js` with BOTH both.ts (source) and
# both.d.ts (declaration) on disk resolves to both.ts; the declaration tier is never even consulted.
printf 'export function bothfn() { return 14; }\n' >"$RX/both.ts"
printf 'declare function bothfn(): number;\n'      >"$RX/both.d.ts"
printf "import { bothfn } from './both.js';\nexport function useBoth() { return bothfn(); }\n" >"$RX/usebo.ts"
"$BIN" "$RX" --deps --no-cache >"$TMP/rx.deps" 2>/dev/null
rx_instab(){ grep -oE "<f p=\"$1\" [^>]*instab=\"[0-9.]+\"" "$TMP/rx.deps" | grep -oE 'instab="[0-9.]+"' | head -1; }
rx_expect(){  # $1 importer  $2 want instab  $3 what
  local got; got="$( rx_instab "$1" )"
  if [ "$got" = "instab=\"$2\"" ]; then ok "runtime-ext: $3 ($1 $got)"; else no "runtime-ext: $3 — $1 has '${got:-no row}', want instab=\"$2\""; fi
}
rx_expect usejs.ts   1.00 "./x.js resolves to x.ts"
rx_expect usetsx.ts  1.00 "./w.js resolves to w.tsx"
rx_expect usemjs.ts  1.00 "./m.mjs resolves to m.mts"
rx_expect usecjs.ts  1.00 "./c.cjs resolves to c.cts"
rx_expect usedual.ts 0.00 "./dual.js with BOTH dual.js and dual.ts stays unresolved"
rx_expect uselib.ts  0.00 "./lib.js does not resolve to lib/index.ts"
rx_expect usejx.ts   1.00 "./jx.jsx resolves to jx.tsx"
rx_expect usejts.ts  1.00 "./jts.jsx resolves to jts.ts (only .ts present)"
rx_expect usejd.ts   0.00 "./jd.jsx with BOTH jd.tsx and jd.ts stays unresolved (unique-or-degrade)"
rx_expect usedecl.ts 1.00 "./d.js resolves to d.d.ts (declaration fallback, no .ts/.tsx source)"
rx_expect usedm.ts   1.00 "./dm.mjs resolves to dm.d.mts (declaration fallback)"
rx_expect usedc.ts   1.00 "./dc.cjs resolves to dc.d.cts (declaration fallback)"
rx_expect usebo.ts   1.00 "./both.js with BOTH both.ts and both.d.ts resolves to both.ts (source before declaration)"
grep -qE '<f p="other/x.ts" afferent="[1-9]' "$TMP/rx.deps" \
  && no "runtime-ext: ./x.js bound the decoy other/x.ts" \
  || ok "runtime-ext: the decoy other/x.ts gains no importer"
grep -qE '<f p="both.d.ts" afferent="[1-9]' "$TMP/rx.deps" \
  && no "runtime-ext: ./both.js bound the declaration instead of the source" \
  || ok "runtime-ext: both.d.ts gains no importer when both.ts answers the specifier"

# ── the fixture resolves everything → ambiguous=0 ─────────────────────────────────────────────────
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

# ── MONOTONICITY: NEW.ambiguous <= pre-change.ambiguous on the fixture ────────────────────────────
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
        ok "monotonicity on fixture: ambiguous NEW=$an <= pre-change OLD=$ao (TS narrow only removes candidates)"
    else
        no "monotonicity VIOLATED: NEW=$an > OLD=$ao — a correct narrow was LOST (regression)"
    fi
}
monotonic_check

# ── LADDER-HOIST: a module alias is the CALL's fact, never a neighbour call's ────────────────────
# The by-name ladder reads each call's require() alias once (graph.h LadderRefFacts) and tests it per
# candidate. Three calls through three aliases in one tree, `run` defined in both modules: each call must
# be proven by its OWN alias (a fact kept across calls proves b.run() as lib/a.js's run). The third caller
# sits one directory down (`../lib/b`): the joined path is per caller directory, not per specifier.
# A fourth caller sits in sub/ and requires './b': a root-level b.js and sub/b.js both define `run`, so the call
# binds sub/b.js only if the join starts at the CALLER's directory (a join that starts at the root names b.js).
LH="$TMP/ladderhoist"; mkdir -p "$LH/lib" "$LH/sub"
printf 'function run() { return 1; }\nmodule.exports = { run };\n' >"$LH/lib/a.js"
printf 'function run() { return 2; }\nmodule.exports = { run };\n' >"$LH/lib/b.js"
printf "const a = require('./lib/a');\nconst b = require('./lib/b');\nfunction viaA() { return a.run(); }\nfunction viaB() { return b.run(); }\nmodule.exports = { viaA, viaB };\n" >"$LH/app.js"
printf "const b = require('../lib/b');\nfunction viaUp() { return b.run(); }\nmodule.exports = { viaUp };\n" >"$LH/sub/up.js"
printf 'function run() { return 3; }\nmodule.exports = { run };\n' >"$LH/b.js"
printf 'function run() { return 4; }\nmodule.exports = { run };\n' >"$LH/sub/b.js"
printf "const b = require('./b');\nfunction viaNear() { return b.run(); }\nmodule.exports = { viaNear };\n" >"$LH/sub/near.js"
lh_binds(){  # $1 caller  $2 the one callee path it must bind  $3 the decoy it must not
  local rc; "$BIN" "$LH" --callees="$1" --no-cache >"$TMP/lh.$1.out" 2>"$TMP/lh.$1.err"; rc=$?
  if [ "$rc" -ne 0 ]; then no "ladder-hoist $1: ripwire rc=$rc"; cat "$TMP/lh.$1.err"; return; fi
  if grep -q "p=\"$2\"" "$TMP/lh.$1.out" && ! grep -q "p=\"$3\"" "$TMP/lh.$1.out"; then
    ok "ladder-hoist $1 → $2 by its own alias (not $3)"
  else
    no "ladder-hoist $1 did not bind $2 alone"; cat "$TMP/lh.$1.out"
  fi
}
lh_binds viaA  'lib/a.js:1' 'lib/b.js:1'
lh_binds viaB  'lib/b.js:1' 'lib/a.js:1'
lh_binds viaUp 'lib/b.js:1' 'lib/a.js:1'
lh_binds viaNear 'sub/b.js:1' 'b.js:1'

# ── PATH-NORM: the per-build (directory, specifier) memo and the one-normalization probe list ─────
# resolve.h TsImportMemo answers a repeated (includer directory, specifier) pair from its first resolution, and
# SuffixProbe normalizes `dir/spec` once per probe list. Same specifier, two directories, two answers: a/ and b/
# each import './util' and each must land on its OWN util.ts (a memo keyed without the directory gives b/y.ts
# a/util.ts). A hit cached first must not make a later miss hit (a1/w.ts finds a1/missing.ts, b1/z.ts has none),
# and a miss cached first must not hide a later hit (a2/v.ts misses './only', b2/t.ts finds b2/only.ts). Two
# importers in one directory share an entry (a/x.ts, a/x2.ts). The specifiers whose last segment is not a plain
# name take the per-probe path: '..' (sub/q.ts → index.ts), './' and '.' (sub2/ → sub2/index.ts), and an escape
# above the root resolves to nothing. Read through --deps: transitive= counts the file plus what it reaches,
# godfiles' afferent= counts importers.
PN="$TMP/pathnorm"; mkdir -p "$PN/a" "$PN/b" "$PN/a1" "$PN/b1" "$PN/a2" "$PN/b2" "$PN/sub" "$PN/sub2"
printf 'export const u = 1;\n' >"$PN/a/util.ts"
printf "import { u } from './util';\nexport const x = u;\n" >"$PN/a/x.ts"
printf "import { u } from './util';\nexport const x2 = u;\n" >"$PN/a/x2.ts"
printf 'export const u = 2;\n' >"$PN/b/util.ts"
printf "import { u } from './util';\nexport const y = u;\n" >"$PN/b/y.ts"
printf 'export const m = 1;\n' >"$PN/a1/missing.ts"
printf "import { m } from './missing';\nexport const w = m;\n" >"$PN/a1/w.ts"
printf "import { m } from './missing';\nexport const z = m;\n" >"$PN/b1/z.ts"
printf "import { o } from './only';\nexport const v = o;\n" >"$PN/a2/v.ts"
printf 'export const o = 1;\n' >"$PN/b2/only.ts"
printf "import { o } from './only';\nexport const t = o;\n" >"$PN/b2/t.ts"
printf 'export const i = 1;\n' >"$PN/index.ts"
printf "import { i } from '..';\nexport const q = i;\n" >"$PN/sub/q.ts"
printf "import { e } from '../../../escape';\nexport const s = e;\n" >"$PN/sub/s.ts"
printf 'export const j = 1;\n' >"$PN/sub2/index.ts"
printf "import { j } from './';\nexport const r = j;\n" >"$PN/sub2/r.ts"
printf "import { j } from '.';\nexport const r2 = j;\n" >"$PN/sub2/r2.ts"
pn_rc=0; ( cd "$PN" && "$BIN" "$PN" --deps --no-cache ) >"$TMP/pn.out" 2>"$TMP/pn.err" || pn_rc=$?
if [ "$pn_rc" -ne 0 ] || ! grep -q '<deps ' "$TMP/pn.out"; then
  no "path-norm: ripwire --deps rc=$pn_rc or no <deps> root"; cat "$TMP/pn.err"
else
  pn_has(){  # $1 attribute fragment that must appear  $2 what it proves
    if grep -qF "$1" "$TMP/pn.out"; then ok "path-norm: $2"; else no "path-norm: $2 (missing $1)"; fi
  }
  pn_has '<f p="a/util.ts" afferent="2"/>'     "a/util.ts has its two importers (a/x.ts, a/x2.ts share one memo entry)"
  pn_has '<f p="b/util.ts" afferent="1"/>'     "b/y.ts's './util' lands on b/util.ts, not a/util.ts (the directory is in the key)"
  pn_has '<f p="b/y.ts" includes="1" afferent="0" instab="1.00" transitive="2">' "b/y.ts reaches one file"
  pn_has '<f p="a1/missing.ts" afferent="1"/>' "a1/w.ts's './missing' hits a1/missing.ts"
  pn_has '<f p="b1/z.ts" includes="1" afferent="0" instab="0.00" transitive="1">' "b1/z.ts's './missing' stays unresolved after a1/'s hit"
  pn_has '<f p="a2/v.ts" includes="1" afferent="0" instab="0.00" transitive="1">' "a2/v.ts's './only' misses"
  pn_has '<f p="b2/only.ts" afferent="1"/>'    "b2/t.ts's './only' still hits after a2/'s miss"
  pn_has '<f p="index.ts" afferent="1"/>'      "'..' from sub/ lands on index.ts (per-probe path)"
  pn_has '<f p="sub2/index.ts" afferent="2"/>' "'./' and '.' from sub2/ land on sub2/index.ts (per-probe path)"
  pn_has '<f p="sub/s.ts" includes="1" afferent="0" instab="0.00" transitive="1">' "an escape above the root resolves to nothing"
fi

bash "$ROOT/test/lib/jsimportalias.sh" "$BIN" || fail=1
bash "$ROOT/test/lib/jsimportfacts.sh" "$BIN" || fail=1
bash "$ROOT/test/lib/jsdefaultimport.sh" "$BIN" || fail=1

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
