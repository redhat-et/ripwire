#!/usr/bin/env bash
# fnliteralcheck.sh — a name bound to a FUNCTION LITERAL owns that literal's body, in every language whose
# tags.scm captures the binding as a definition (JS, TS, Lua, Python).
#
# The defect (0.6.5): the @definition node of `const f = (x) => {…}` is the lexical_declaration, of
# `M.f = function(x) … end` the assignment_statement, of a class-body `f = lambda self, x: g(x)` the
# assignment — none of which owns a `body:` field. So bodyByte stayed 0, sigEndByte == endByte, and
# `--callees=f` answered bodyless_defs="1" for a function with a body: a FALSE claim, and every verb that
# skips bodyless symbols (quality panel, clones, naming, hotspots, biggest-first) silently skipped them.
#
# The fix (src/ingest_relations.h, kFnLiteralBinding + defBodyNodeOf): when the def node has no body, walk
# from the @name up to the def node looking for a value-carrying field (value:/right:, or the first value
# of a positional expression_list) whose value — through cast/paren wrappers — is a function literal, and
# adopt THAT literal's body. Metrics (params, cx, nest) read from the literal, not the declaration.
#
# Fixture (test/fnliteralfix/): arrows.ts, arrows.js, mod.lua, cls.py — each row's comment in the source
# says what it pins. Every expected value is counted by hand from the fixture.
#
# Usage:
#   test/fnliteralcheck.sh [BIN]
#   RIPWIRE_BIN=asan/ripwire test/fnliteralcheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/fnliteralfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no test/fnliteralfix directory"; exit 2; }
echo "fnliteralcheck: BIN=$BIN  FIX=$FIX"

# ---- 1. every literal-bound name is ONE definition WITH a body ------------------------------------------
echo "=== 1. --callees: literal-bound names are bodied definitions (bodyless_defs absent) ==="
header(){ ( cd "$FIX" && "$BIN" . --callees="$1" --no-cache --legend=compact 2>/dev/null ) | grep -oE '<callees [^>]*>' | head -1; }
for name in blockArrow conciseArrow bareParam fnExprConst exportedArrow castArrow satisfiesArrow firstOfTwo secondOfTwo handle \
            jsArrow jsConcise jsLegacyVar onPair jsField jsExported \
            luaAssigned luaLocal luaField luaField2 \
            py_lambda; do
    h="$( header "$name" )"
    if [ -z "$h" ]; then no "$name: no <callees> header"; continue; fi
    if ! printf '%s' "$h" | grep -q ' defs="1"'; then no "$name: expected defs=1 — got: $h"; continue; fi
    if printf '%s' "$h" | grep -q ' bodyless_defs='; then no "$name: still claims a bodyless def — $h"; else ok "$name: defs=1, bodied"; fi
    # every fixture binding calls its sink exactly once — the body's call must attribute to THIS symbol
    if printf '%s' "$h" | grep -q ' count="1"'; then ok "$name: its one call is its own (count=1)"; else no "$name: expected count=1 — got: $h"; fi
done

# ---- 2. real bodyless declarations stay bodyless ----------------------------------------------------------
echo "=== 2. declarations without a body stay bodyless ==="
h="$( header declaredOnly )"
if printf '%s' "$h" | grep -q ' defs="1".* bodyless_defs="1"'; then ok "declaredOnly: bodyless_defs=1"; else no "declaredOnly: expected bodyless — got: $h"; fi
h="$( header overloaded )"
if printf '%s' "$h" | grep -q ' defs="3".* bodyless_defs="2"'; then ok "overloaded: 2 signatures bodyless, 1 bodied"; else no "overloaded: expected defs=3 bodyless_defs=2 — got: $h"; fi
# `declare const f: (x) => void;` binds a TYPE, not a literal: it is not a function definition at all (the
# tags query needs a value:), so --callees refuses it — never a bodied def.
if ( cd "$FIX" && "$BIN" . --callees=declaredConst --no-cache --legend=compact 2>&1 >/dev/null ) | grep -q 'symbol not found: declaredConst'; then
    ok "declaredConst: not a function definition"
else
    no "declaredConst: became a definition — $( header declaredConst )"
fi

# ---- 3. metrics read from the literal ---------------------------------------------------------------------
echo "=== 3. --metrics: params / cx / nest / loc read from the literal ==="
( cd "$FIX" && "$BIN" . --metrics --no-cache --legend=compact 2>/dev/null ) | sed 's/></>\n</g' >"$TMP/m"
row(){ grep -E "<s t=\"[^\"]*\" n=\"$1\"" "$TMP/m" | head -1; }
attr(){ # name attr val why
    local r; r="$( row "$1" )"
    if [ -z "$r" ]; then no "$1: metrics row missing"; return; fi
    if printf '%s' "$r" | grep -q " $2=\"$3\""; then ok "$1: $2=$3 ($4)"; else no "$1: expected $2=$3 ($4) — got: $r"; fi
}
attr castArrow   params 1 "the arrow's one param, not the inline type annotation's three"
attr secondOfTwo params 2 "its own arrow, not the first declarator's"
attr firstOfTwo  loc    1 "its own declarator line, not the two-line declaration"
attr secondOfTwo loc    1 "its own declarator line, not the two-line declaration"
attr luaField    loc    1 "its own table field, not the whole four-line table"
attr blockArrow  params 2 "block-bodied arrow"
attr bareParam   params 1 "x => …: a lone parameter without a list"
attr blockArrow  cx     2 "one if"
attr luaAssigned params 2 "M.f = function(x, y)"
attr luaAssigned cx     2 "one if"
attr luaField2   params 2 "table-field literal"
attr py_lambda   params 2 "lambda self, x"
attr py_lambda   cx     1 "the lambda, read from the lambda"
# py_lambda's nest is deliberately NOT pinned: cc_isNestingOnly matches kind "lambda", which is ALSO the anonymous
# keyword token inside every Python lambda node, so any function containing a lambda reads one level too deep.
# That is a Python-wide metric defect (every function with a lambda moves), separate from this binding fix.

# ---- 4. a callback passed as an argument never becomes a definition ---------------------------------------
echo "=== 4. anonymous callbacks are not definitions ==="
n="$( grep -c '<s t=' "$TMP/m" )"
if [ "$n" = "37" ]; then ok "symbol rows = 37 (no anonymous callback minted a def)"; else no "expected 37 symbol rows — got $n"; fi
if grep -qE '<s t="[^"]*" n=""' "$TMP/m"; then no "an unnamed symbol row appeared"; else ok "no unnamed symbol rows"; fi

# ---- 5. determinism ---------------------------------------------------------------------------------------
( cd "$FIX" && "$BIN" . --no-cache >"$TMP/a" 2>/dev/null; "$BIN" . --no-cache >"$TMP/b" 2>/dev/null )
if diff -q "$TMP/a" "$TMP/b" >/dev/null; then ok "default map byte-identical run-to-run"; else no "non-deterministic default map"; fi

# ---- 6. edges: a FUNCTION-LOCAL def yields to what a call outside its function can name ----------------------------
# A name bound inside another function's body (a factory's `const start = () => …`, a nested `function done()`, a
# `const run` inside an it() callback) is reachable BY NAME only inside that function; outside it, only as a member of
# the value the function returns (src/graph.h reachableByName). Once such a def has a body it competes for calls, so
# the resolver must rank it below every candidate the call can name — without losing the returned-value edge.
# Fixtures: test/fnliteraledgefix/import (typed receiver + imported factories), .../shadow (a helper's PARAMETER), and
# .../php, .../lua (nested named functions the language binds globally), .../c (a top-level C++ function).
echo "=== 6. edges: function-local defs yield outside their function ==="
EDGE="$ROOT/test/fnliteraledgefix"
callees(){ ( cd "$EDGE/$1" && "$BIN" . --callees="$2" --no-cache --legend=compact 2>/dev/null ) | sed 's/></>\n</g'; }
edge(){ # dir caller callee-name callee-path why
    if callees "$1" "$2" | grep -qE "<s t=\"[^\"]*\" n=\"$3\" p=\"$4\""; then ok "$2 -> $3@$4 ($5)"; else no "$2: expected an edge to $3@$4 ($5) — got: $( callees "$1" "$2" | grep -E '^<callees |^<s t="' | tr '\n' ' ' )"; fi
}
noedge(){ # dir caller callee-name why
    if callees "$1" "$2" | grep -qE "<s t=\"[^\"]*\" n=\"$3\""; then no "$2: must not bind $3 ($4) — got: $( callees "$1" "$2" | grep -E '^<s t="' | tr '\n' ' ' )"; else ok "$2 binds no $3 ($4)"; fi
}
# (a) the typed-receiver shape: `tui.start()` / `tui.done()` on an imported Tui, beside two imported factories whose
#     local `start` (arrow const) and `done` (function declaration) are out of reach
edge import cmd/use.ts:declCaller  start ui/tui.ts:4 "the imported class's method, not a factory-local closure"
edge import cmd/use.ts:declCaller  done  ui/tui.ts:5 "function-declaration form of the same shape"
edge import cmd/use.ts:arrowCaller start ui/tui.ts:4 "an arrow-const caller, same answer"
h="$( callees import cmd/use.ts:declCaller | grep -oE '<callees [^>]*>' )"
if printf '%s' "$h" | grep -q 'declined_calls='; then no "declCaller: a call was declined — $h"; else ok "declCaller: no declined call"; fi
# (b) the returned-value shape stays bound: `createTracker().stop()` reaches the factory's `stop` through the imported
#     module, not the same-named method in a file the caller never imports
edge import cmd/use.ts:stopCaller stop agents/tracker.ts:5 "the returned member, reached through the imported factory"
# (c) inside its own function a local def is in reach: `stop` calls its sibling closure `start`
edge import agents/tracker.ts:stop start agents/tracker.ts:4 "a sibling closure in the same factory"
# (d) the shadow shape: `run` is captureStdout's own PARAMETER — neither the same file's it()-callback `const run`
#     nor a sibling test file's may answer it
noedge shadow tests/a.test.ts:captureStdout run "its own parameter; the it() callback's const is out of reach"
noedge shadow tests/b.test.ts:captureStdout run "its own parameter; another file's callback const is out of reach"
# (e) a nested named function the language binds GLOBALLY never yields (ingest_names.h kEscapingNestedBindings): PHP's
#     nested `function`, Lua's non-`local` nested `function` — a bare call from outside means it, never a same-named
#     method or table field of another file in the same directory (main binds these; a yielding local did not)
edge php a.php:use_helper php_helper a.php:4 "a PHP nested function is global once its outer function has run"
edge lua init.lua:run    lua_helper init.lua:4 "a non-local Lua nested function is a global"
# (f) a top-level C/C++ function is never "nested in itself": its captured name sits inside its own
#     function_definition, so the scope search must start from the definition, not the declarator
edge c a/x.cpp:use_helper helper a/x.cpp:3 "a same-file top-level C++ function, as on main"
# (g) the scope span rides the ingest cache: a WARM run (cache on, second pass) answers these arms exactly as --no-cache.
#     A blob from an older format (kCacheVersion 26 held wrong spans for the shapes above) is never read: the format is in
#     the blob's name and header, and cachefuzzcheck's version_decrement arm proves an N-1 blob is refused. The fingerprint
#     carries graph_unresolved= too: since FE-A the shadow shape's parameter call is unresolved (a call through the
#     parameter), no longer declined between two unrelated methods, so declined_calls= alone would leave it no witness.
CACHEHOME="$TMP/cachehome"; mkdir -p "$CACHEHOME/xdg" "$CACHEHOME/tmp"
for q in "c a/x.cpp:use_helper" "php a.php:use_helper" "lua init.lua:run" "import cmd/use.ts:declCaller" "shadow tests/a.test.ts:captureStdout"; do
    set -- $q
    cold="$( ( cd "$EDGE/$1" && "$BIN" . --callees="$2" --no-cache --legend=compact 2>/dev/null ) | grep -oE '<s t="[^>]*>|declined_calls="[0-9]+"|graph_unresolved="[0-9]+"' )"
    for pass in 1 2; do
        warm="$( ( cd "$EDGE/$1" && XDG_CACHE_HOME="$CACHEHOME/xdg" TMPDIR="$CACHEHOME/tmp" "$BIN" . --callees="$2" --legend=compact 2>/dev/null ) | grep -oE '<s t="[^>]*>|declined_calls="[0-9]+"|graph_unresolved="[0-9]+"' )"
    done
    if [ -n "$cold" ] && [ "$cold" = "$warm" ]; then ok "$2: warm cache answers as --no-cache"; else no "$2: warm cache differs from --no-cache — cold: $cold / warm: $warm"; fi
done
# ...while the call INSIDE that it() callback does reach it (a file-scope caller: the callback is anonymous)
if ( cd "$EDGE/shadow" && "$BIN" . --callers=tests/a.test.ts:run --no-cache --legend=compact 2>/dev/null ) | grep -q 'n="&lt;file-scope&gt;" p="tests/a.test.ts:1"'; then
    ok "tests/a.test.ts:run is called from inside its it() callback"
else
    no "tests/a.test.ts:run lost its in-scope caller"
fi

echo
if [ "$fail" = 0 ]; then echo "fnliteralcheck: ALL PASS"; else echo "fnliteralcheck: FAIL"; fi
exit "$fail"
