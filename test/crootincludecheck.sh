#!/usr/bin/env bash
# crootincludecheck.sh — C-ROOT-INCLUDE: a C/C++ quote include that misses the includer's directory is probed at the
# include roots a build passes as -I, with no build file read (resolve.h resolveCIncludeRoots): the repo root, an
# `include/` beside the includer's directory or an ancestor, and the root `src/`. Unique across those roots or no edge,
# and a name two roots both hold is counted in imports_unresolved= graph_partial="1" on --deps and --arch.
#
# The fixture is written at runtime (never a .gitignored path). Every edge is read from --arch with one deny-all rule,
# which prints each resolved file edge as a violation row.
#   R1 root          sub/deep/a.c   "core/x.h"        → core/x.h            (Envoy, htop, tmux: -I<root>)
#   R2 include/      app/src/b.cpp  "util/y.hpp"      → app/include/util/y.hpp  (waybar, cpython _hacl: -Iinclude)
#   R3 root src/     misc/f.cc      "z.h"             → src/z.h             (ninja's fuzzer build: -Isrc)
#   R4 own dir wins  d/a.c          "x.h"             → d/x.h, never the root x.h
#   R5 ambiguous     t/a.c          "w.h"             → no edge: root w.h AND include/w.h; counted imports_unresolved=1
#   R6 angle         sub/s.c        <string.h>, <core/x.h> → no edge on a single root (a sibling string.h never binds)
#   R7 unproven      t/q.c          "q.h"             → no edge: only source/q.h and lib/q.h hold it
#   R8 escape        sub/e.c        "../../out.h"     → no edge above the crawl root, though a root out.h exists (a missing
#                    sub/include/ must not turn the escape into `out.h`)
#   R9 decoupled     sub/deep/main.c calls helper(): "core/x.h" and "alt/x.h" both define it, main.c includes only
#                    core/x.h by its root path. The FILE graph has the edge main.c → core/x.h, and the call graph is
#                    main's: --callers=helper still declines the call between the two namesakes (count="0",
#                    via="declined"). The call narrow keeps the includer-directory resolution until CPP-EXTQUAL-VETO
#                    lands (resolve.h kCallNarrowReadsCIncludeRoots); this arm goes red if the root probe leaks into it,
#                    and is the arm to retarget (bound to core/x.h alone) when the two are re-coupled.
#   R10 non-C        a Python file importing `core.x` is untouched (the rule is the C-family branch only)
#   R11 no suffix    t/u.c          "y.hpp"           → no edge: only app/include/util/y.hpp ends with it (unique-suffix
#                    matching is not this rule; card C-SUFFIX-INCLUDE)
#   R12 proof        fx4: other/impl.c includes "core/api.h" by its root path and defines work: --defs=core/api.h:work
#                    widens to it (defs="2") and --callers=core/api.h:work finds main.c (count="1")
#   R13 proof = file graph  the declaration-to-definition proof reads the file graph's rule over the whole corpus, not
#                    the declaration files only: fx1 (other/impl.c's own other/api.h wins) and fx2 (api.h is held by
#                    the root and include/, so ambiguous) both keep --defs=api.h:work at defs="1" unproven_defs="1"
#   R14 phantom base fx5: p/q/r.c "../a.h" with no include/ or src/ in the tree draws no edge to the root a.h
#   R15 one root twice  lib/deep/m.c "../include/dd.h": include/ and src/ both normalize onto include/dd.h, which is
#                    one file, not two roots, so the edge stands
#   R16 C-family only a Bash `source util/v.sh` never probes the C include roots (include/util/v.sh exists)
#   R17 --impact     a symbol in w.h (R5's ambiguous name) carries imports_unresolved="1": importers= is a floor
#
# Usage:  test/crootincludecheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire test/crootincludecheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "crootincludecheck: BIN=$BIN TMP=$TMP"

FIX="$TMP/fix"
mk(){ mkdir -p "$( dirname "$FIX/$1" )"; printf '%s\n' "$2" > "$FIX/$1"; }
mk core/x.h                '#pragma once
int helper(int a) { return a + 1; }'
mk alt/x.h                 '#pragma once
int helper(int a) { return a + 2; }'
mk sub/deep/a.c            '#include "core/x.h"
int a_fn(void) { return 1; }'
mk sub/deep/main.c         '#include "core/x.h"
int main_fn(void) { return helper(3); }'
mk app/include/util/y.hpp  '#pragma once
inline int y_fn() { return 2; }'
mk app/src/b.cpp           '#include "util/y.hpp"
int b_fn() { return y_fn(); }'
mk src/z.h                 '#pragma once
int z_fn(void);'
mk misc/f.cc               '#include "z.h"
int f_fn() { return 3; }'
mk x.h                     'int root_x(void);'
mk d/x.h                   'int own_x(void);'
mk d/a.c                   '#include "x.h"
int d_fn(void) { return 4; }'
mk w.h                     'int w_root(void);'
mk include/w.h             'int w_inc(void);'
mk t/a.c                   '#include "w.h"
int t_fn(void) { return 5; }'
mk sub/string.h            'int not_libc(void);'
mk sub/s.c                 '#include <string.h>
#include <core/x.h>
int s_fn(void) { return 6; }'
mk source/q.h              'int q_src(void);'
mk lib/q.h                 'int q_lib(void);'
mk t/q.c                   '#include "q.h"
int q_fn(void) { return 7; }'
mk out.h                   'int out_root(void);'
mk sub/e.c                 '#include "../../out.h"
int e_fn(void) { return 8; }'
mk t/u.c                   '#include "y.hpp"
int u_fn(void) { return 9; }'
mk include/dd.h            'int dd(void);'
mk lib/deep/m.c            '#include "../include/dd.h"
int m_fn(void) { return 10; }'
mk include/util/v.sh       'v() { echo 1; }'
mk sh/run.sh               'source util/v.sh
r() { echo 1; }'
mk core/x.py               'def helper(): return 1'
mk py/use.py               'import core.x
def use(): return core.x.helper()'
printf 'deny path .* -> .*\n' > "$TMP/all.rules"

( cd "$FIX" && "$BIN" "$FIX" --no-cache --arch="$TMP/all.rules" ) > "$TMP/arch.out" 2>"$TMP/arch.err"
( cd "$FIX" && "$BIN" "$FIX" --no-cache --deps ) > "$TMP/deps.out" 2>"$TMP/deps.err"
( cd "$FIX" && "$BIN" "$FIX" --no-cache --callers=helper --legend=compact ) > "$TMP/callers.out" 2>"$TMP/callers.err"
( cd "$FIX" && "$BIN" "$FIX" --no-cache --impact=w.h:w_root ) > "$TMP/impact.out" 2>"$TMP/impact.err"

# R12-R14: one small tree each (the review fixtures of #524), so no root above can take part.
mkx(){ mkdir -p "$( dirname "$TMP/$1" )"; printf '%s\n' "$2" > "$TMP/$1"; }
mkx fx4/core/api.h  'int work(void);'
mkx fx4/main.c      '#include "core/api.h"
int go(void) { return work(); }'
mkx fx4/other/impl.c '#include "core/api.h"
int work(void) { return 1; }'
for d in fx1 fx2; do
  mkx $d/api.h      'int work(void);'
  mkx $d/main.c     '#include "api.h"
int go(void) { return work(); }'
  mkx $d/other/impl.c '#include "api.h"
int work(void) { return 1; }'
done
mkx fx1/other/api.h   'int unrelated(void);'
mkx fx2/include/api.h 'int unrelated(void);'
mkx fx5/a.h         'int ra(void);'
mkx fx5/p/q/r.c     '#include "../a.h"
int r(void) { return 1; }'
( cd "$TMP/fx4" && "$BIN" . --no-cache --defs=core/api.h:work ) > "$TMP/fx4.defs" 2>&1
( cd "$TMP/fx4" && "$BIN" . --no-cache --callers=core/api.h:work ) > "$TMP/fx4.callers" 2>&1
( cd "$TMP/fx1" && "$BIN" . --no-cache --defs=api.h:work ) > "$TMP/fx1.defs" 2>&1
( cd "$TMP/fx2" && "$BIN" . --no-cache --defs=api.h:work ) > "$TMP/fx2.defs" 2>&1
( cd "$TMP/fx5" && "$BIN" "$TMP/fx5" --no-cache --arch="$TMP/all.rules" ) > "$TMP/fx5.arch" 2>&1
[ -s "$TMP/arch.out" ] || { no "--arch produced no output"; cat "$TMP/arch.err"; echo "SOME CHECKS FAILED"; exit 1; }

edge(){ grep -q "from=\"$FIX/$1\" fromLayer=\"[^\"]*\" to=\"$FIX/$2\"" "$TMP/arch.out"; }
noedge_from(){ ! grep -q "from=\"$FIX/$1\"" "$TMP/arch.out"; }

if edge sub/deep/a.c core/x.h; then ok "R1 root: sub/deep/a.c \"core/x.h\" → core/x.h"; else no "R1 root edge missing"; fi
if edge app/src/b.cpp app/include/util/y.hpp; then ok "R2 include/: app/src/b.cpp \"util/y.hpp\" → app/include/util/y.hpp"; else no "R2 include/ edge missing"; fi
if edge misc/f.cc src/z.h; then ok "R3 root src/: misc/f.cc \"z.h\" → src/z.h"; else no "R3 root src/ edge missing"; fi
if edge d/a.c d/x.h && ! edge d/a.c x.h; then ok "R4 the includer's own directory wins: d/a.c → d/x.h only"; else no "R4 d/a.c must bind d/x.h and never the root x.h"; fi
if noedge_from t/a.c; then ok "R5 ambiguous: t/a.c \"w.h\" (root w.h and include/w.h) draws no edge"; else no "R5 ambiguous include drew an edge"; fi
if grep -q 'imports_unresolved="1"' "$TMP/arch.out"; then ok "R5 --arch discloses it: imports_unresolved=\"1\""; else no "R5 --arch lacks imports_unresolved=\"1\""; fi
if grep -q 'imports_unresolved="1"' "$TMP/deps.out" && grep -q 'graph_partial="1"' "$TMP/deps.out"; then
  ok "R5 --deps discloses it: imports_unresolved=\"1\" graph_partial=\"1\""
else no "R5 --deps lacks the disclosure"; fi
if noedge_from sub/s.c; then ok "R6 angle <string.h> and <core/x.h> stay unresolved on a single root"; else no "R6 an angle include bound a file"; fi
if noedge_from t/q.c; then ok "R7 unproven roots: source/q.h and lib/q.h never bind \"q.h\""; else no "R7 an unproven root bound"; fi
if noedge_from sub/e.c; then ok "R8 a ../ escape above the crawl root stays unresolved"; else no "R8 escape bound a file"; fi
if edge sub/deep/main.c core/x.h; then ok "R9 file graph: sub/deep/main.c → core/x.h (the root include)"; else no "R9 file edge main.c → core/x.h missing"; fi
if grep -q '<callers schema="ripwire.callers/v1" of="helper" defs="3" count="0" ' "$TMP/callers.out" \
   && grep -qE '<dc in="main_fn" p="sub/deep/main.c:2" cands="2" via="declined"' "$TMP/callers.out" \
   && ! grep -qE '<s t="fn" n="main_fn"' "$TMP/callers.out"; then
  ok "R9 call graph unchanged from main: main.c's helper() is declined between the two namesakes (root edges stay out of the call narrow)"
else no "R9 the root include reached the call narrow: main.c's helper() is no longer declined"; sed -n '1,20p' "$TMP/callers.out" | sed 's/<!--.*-->//' | head -c 1200; echo; fi
if edge py/use.py core/x.py; then ok "R10 Python import core.x unchanged (resolves by its own rule)"; else no "R10 Python import edge changed"; fi

if noedge_from t/u.c; then ok "R11 a unique suffix (\"y.hpp\" → app/include/util/y.hpp) draws no edge"; else no "R11 a suffix match bound a file"; fi

defs_of(){ sed 's/<!--.*-->//' "$1" | grep -o '<name q="[^"]*" [^>]*>'; }
if defs_of "$TMP/fx4.defs" | grep -q 'defs="2">' && grep -q '<callers schema="ripwire.callers/v1" of="core/api.h:work" defs="2" count="1" ' "$TMP/fx4.callers"; then
  ok "R12 proof: other/impl.c includes \"core/api.h\" by its root path, so --defs=core/api.h:work widens to it (defs=2) and --callers counts main.c"
else no "R12 the root include did not prove other/impl.c's work: $( defs_of "$TMP/fx4.defs" )"; fi
for d in fx1 fx2; do
  if defs_of "$TMP/$d.defs" | grep -q 'defs="1" unproven_defs="1">'; then
    ok "R13 $d: --defs=api.h:work stays defs=1 unproven_defs=1 (the proof follows the file graph's rule)"
  else no "R13 $d: the proof bound other/impl.c where the file graph draws no edge: $( defs_of "$TMP/$d.defs" )"; fi
done
if [ -s "$TMP/fx5.arch" ] && ! grep -q 'from="[^"]*p/q/r.c"' "$TMP/fx5.arch"; then
  ok "R14 a missing include/ or src/ is never a base: fx5 p/q/r.c \"../a.h\" draws no edge"
else no "R14 a phantom base bound p/q/r.c \"../a.h\""; grep -o 'from="[^"]*" fromLayer="[^"]*" to="[^"]*"' "$TMP/fx5.arch" | head -3; fi
if edge lib/deep/m.c include/dd.h; then ok "R15 include/ and src/ normalizing onto one file are one root: lib/deep/m.c → include/dd.h"
else no "R15 lib/deep/m.c \"../include/dd.h\" lost its edge (one file reached through two bases counted as ambiguous)"; fi
if noedge_from sh/run.sh; then ok "R16 a Bash source never probes the C include roots (include/util/v.sh stays unbound)"
else no "R16 a non-C directive reached the C include roots"; fi
if grep -q '<impact schema="ripwire.impact/v1" of="w.h:w_root" [^>]*imports_unresolved="1"' "$TMP/impact.out"; then
  ok "R17 --impact=w.h:w_root discloses the ambiguous root include: imports_unresolved=\"1\""
else no "R17 --impact on a C symbol hides the ambiguous root include"; sed 's/<!--.*-->//' "$TMP/impact.out" | head -c 600; echo; fi

if [ "$fail" -eq 0 ]; then echo "ALL PASS"; else echo "SOME CHECKS FAILED"; exit 1; fi
