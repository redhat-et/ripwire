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
#   R8 escape        sub/e.c        "../../out.h"     → no edge above the crawl root
#   R9 decoupled     sub/deep/main.c calls helper(): "core/x.h" and "alt/x.h" both define it, main.c includes only
#                    core/x.h by its root path. The FILE graph has the edge main.c → core/x.h, and the call graph is
#                    main's: --callers=helper still declines the call between the two namesakes (count="0",
#                    via="declined"). The call narrow keeps the includer-directory resolution until CPP-EXTQUAL-VETO
#                    lands (resolve.h kCallNarrowReadsCIncludeRoots); this arm goes red if the root probe leaks into it,
#                    and is the arm to retarget (bound to core/x.h alone) when the two are re-coupled.
#   R10 non-C        a Python file importing `core.x` is untouched (the rule is the C-family branch only)
#   R11 no suffix    t/u.c          "y.hpp"           → no edge: only app/include/util/y.hpp ends with it (unique-suffix
#                    matching is not this rule; card C-SUFFIX-INCLUDE)
#
# Usage:  test/crootincludecheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire test/crootincludecheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
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
mk sub/e.c                 '#include "../../out.h"
int e_fn(void) { return 8; }'
mk t/u.c                   '#include "y.hpp"
int u_fn(void) { return 9; }'
mk core/x.py               'def helper(): return 1'
mk py/use.py               'import core.x
def use(): return core.x.helper()'
printf 'deny path .* -> .*\n' > "$TMP/all.rules"

( cd "$FIX" && "$BIN" "$FIX" --no-cache --arch="$TMP/all.rules" ) > "$TMP/arch.out" 2>"$TMP/arch.err"
( cd "$FIX" && "$BIN" "$FIX" --no-cache --deps ) > "$TMP/deps.out" 2>"$TMP/deps.err"
( cd "$FIX" && "$BIN" "$FIX" --no-cache --callers=helper --legend=compact ) > "$TMP/callers.out" 2>"$TMP/callers.err"
[ -s "$TMP/arch.out" ] || { no "--arch produced no output"; cat "$TMP/arch.err"; echo "SOME CHECKS FAILED"; exit 1; }

edge(){ grep -q "from=\"$FIX/$1\" fromLayer=\"[^\"]*\" to=\"$FIX/$2\"" "$TMP/arch.out"; }
noedge_from(){ ! grep -q "from=\"$FIX/$1\"" "$TMP/arch.out"; }

edge sub/deep/a.c core/x.h && ok "R1 root: sub/deep/a.c \"core/x.h\" → core/x.h" || no "R1 root edge missing"
edge app/src/b.cpp app/include/util/y.hpp && ok "R2 include/: app/src/b.cpp \"util/y.hpp\" → app/include/util/y.hpp" || no "R2 include/ edge missing"
edge misc/f.cc src/z.h && ok "R3 root src/: misc/f.cc \"z.h\" → src/z.h" || no "R3 root src/ edge missing"
if edge d/a.c d/x.h && ! edge d/a.c x.h; then ok "R4 the includer's own directory wins: d/a.c → d/x.h only"; else no "R4 d/a.c must bind d/x.h and never the root x.h"; fi
noedge_from t/a.c && ok "R5 ambiguous: t/a.c \"w.h\" (root w.h and include/w.h) draws no edge" || no "R5 ambiguous include drew an edge"
grep -q 'imports_unresolved="1"' "$TMP/arch.out" && ok "R5 --arch discloses it: imports_unresolved=\"1\"" || no "R5 --arch lacks imports_unresolved=\"1\""
grep -q 'imports_unresolved="1"' "$TMP/deps.out" && grep -q 'graph_partial="1"' "$TMP/deps.out" \
  && ok "R5 --deps discloses it: imports_unresolved=\"1\" graph_partial=\"1\"" || no "R5 --deps lacks the disclosure"
noedge_from sub/s.c && ok "R6 angle <string.h> and <core/x.h> stay unresolved on a single root" || no "R6 an angle include bound a file"
noedge_from t/q.c && ok "R7 unproven roots: source/q.h and lib/q.h never bind \"q.h\"" || no "R7 an unproven root bound"
noedge_from sub/e.c && ok "R8 a ../ escape above the crawl root stays unresolved" || no "R8 escape bound a file"
edge sub/deep/main.c core/x.h && ok "R9 file graph: sub/deep/main.c → core/x.h (the root include)" || no "R9 file edge main.c → core/x.h missing"
if grep -q '<callers schema="ripwire.callers/v1" of="helper" defs="3" count="0" ' "$TMP/callers.out" \
   && grep -qE '<dc in="main_fn" p="sub/deep/main.c:2" cands="2" via="declined"' "$TMP/callers.out" \
   && ! grep -qE '<s t="fn" n="main_fn"' "$TMP/callers.out"; then
  ok "R9 call graph unchanged from main: main.c's helper() is declined between the two namesakes (root edges stay out of the call narrow)"
else no "R9 the root include reached the call narrow: main.c's helper() is no longer declined"; sed -n '1,20p' "$TMP/callers.out" | sed 's/<!--.*-->//' | head -c 1200; echo; fi
edge py/use.py core/x.py && ok "R10 Python import core.x unchanged (resolves by its own rule)" || no "R10 Python import edge changed"

noedge_from t/u.c && ok "R11 a unique suffix (\"y.hpp\" → app/include/util/y.hpp) draws no edge" || no "R11 a suffix match bound a file"

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
