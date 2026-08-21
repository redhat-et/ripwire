#!/usr/bin/env bash
# luacheck.sh — the Lua ingest coverage gate (grammar + tags.scm + the Lua-only control-flow carve-outs).
#
# Modeled on csharpcheck.sh / phpcheck.sh: a small fixture, assertions pinned to what the binary ACTUALLY
# does (every number below was read off a real run before it was written down), plus mutation arms so the
# edge and metric assertions are non-tautological.
#
# ── WHY THIS GATE IS NOT VACUOUS ──────────────────────────────────────────────────────────────────────
# Against a binary built from cd30104 — the commit this lane branched from, which has no Lua grammar at
# all — every .lua file leaves the index as `why="unsupported-ext"`, so the map reports
# `files=0 symbols=0` and every arm fails. That is the trivial red and it is NOT what this gate is for.
# Lua has no `function`-keyword monopoly on defining a function: FIVE different spellings define one, and
# a tags.scm that captured only the first would still turn a naive `files>0` gate green. So §1 pins each
# of the five shapes by name and kind, and §4 pins EXACT cyclomatic numbers whose arithmetic depends on
# the two Lua-specific corrections this port had to make — `do … end` is a bare scope block and must NOT
# count as a decision (the C family's `do` is a loop, Swift's is a try), while `repeat … until` and the
# WORD operators `and`/`or` must. §7 mutates each of those three independently and shows the number move.
#
# ── FIXTURE (test/luafix/) ────────────────────────────────────────────────────────────────────────────
#   util.lua      local M = {}                             -- the module-table idiom
#                 function M.trim(s)                        -- shape 2: dot_index function_declaration
#                 function M.shout(s)   -> M.trim(s)        -- a same-file dotted call
#                 M.pad = function(s)                       -- shape 4: assignment_statement
#                 return M
#   greeter.lua   local util = require("util")              -- NOT an import: an ordinary call
#                 function Greeter.new(name) -> setmetatable(...)
#                 function Greeter:greet()  -> util.shout() -- shape 3: colon method, CROSS-FILE call
#                 local function fallback(n)                -- shape 1, with an if/elseif chain
#                 return { new = Greeter.new, fallback = fallback }
#   main.lua      handlers = { run = function(name) … }     -- shape 5: table_constructor field
#                 local function countdown(n)               -- do-block + for + repeat + while + `and`
#
# ── FINDINGS from running `ripwire test/luafix` and reading the raw output ────────────────────────────
#   - 3 files / 8 symbols / edges=3 / ambiguous=0 / unresolved=0, clean stderr (no ABI/degrade line).
#   - KIND MAPPING: every function spelling lands as t="fn" EXCEPT the colon form `function Greeter:greet()`,
#     which is t="method" — the colon is Lua's only syntactic evidence of an implicit `self`, and it is the
#     one place the language distinguishes a method from a function, so the extractor does too.
#   - `new = Greeter.new` inside the returned table is deliberately NOT a second definition of `new`: the
#     table field's value is a dot_index_expression, not a function_definition, so the table-constructor
#     pattern correctly declines it. That is what keeps symbols=8 rather than 9, and it is asserted.
#   - `require("util")`, `setmetatable(...)` and `string.upper(...)` ARE captured as call references; they
#     resolve to nothing in-corpus and drop, which is why unresolved=0 and edges=3 rather than more.
#   - cx(countdown) = 5: 1 base + for + repeat + while + `and`. The `do … end` block contributes NOTHING.
#   - cx(fallback) = 3: 1 base + if + elseif. (Lua's elseif_statement is a SIBLING of the if_statement in
#     this grammar, not a child clause, so cc_walk's C-family else-if flattening never sees it — it has to
#     be counted in isDecisionType, and this number is the proof that it is.)
#   - NO INHERITANCE EDGES, by design and disclosed: greeter.lua really does spell
#     `setmetatable({...}, Greeter)` and `Greeter.__index = Greeter`, which IS Lua inheritance — and it is
#     an ordinary runtime call over an ordinary table, with no syntax to read. §5 asserts the absence so
#     the silence can never be mistaken for "measured, found none".
#
# Usage:
#   bash test/luacheck.sh
#   RIPWIRE_BIN=build/ripwire bash test/luacheck.sh
#   RIPWIRE_BIN=asan/ripwire  bash test/luacheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
FIX="$ROOT/test/luafix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
cxof(){ "$1" "$2" --metrics --no-cache 2>/dev/null | grep -o "n=\"$3\"[^>]* cx=\"[0-9]*\"" | grep -o ' cx="[0-9]*"' | tr -d ' '; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for XML assertions"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }

echo "luacheck: BIN=$BIN  FIX=$FIX"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 0. PRESENCE: the fixture really spells every shape the arms below assert ==="
# ═══════════════════════════════════════════════════════════════════════════
# A gate whose probe target can vanish passes for the wrong reason (CONTRIBUTING.md §2). These greps are
# the guard: if a fixture edit deletes a shape, THIS arm reds instead of the assertion going inert.
presence(){ grep -qF -- "$2" "$FIX/$1" && ok "fixture $1 spells: $3" || no "fixture $1 no longer spells: $3"; }
presence greeter.lua 'local function fallback'   'shape 1 — a plain local function_declaration'
presence util.lua    'function M.trim(s)'        'shape 2 — a dot_index function_declaration'
presence greeter.lua 'function Greeter:greet()'  'shape 3 — a colon (method) function_declaration'
presence util.lua    'M.pad = function(s)'       'shape 4 — the assignment_statement spelling'
presence main.lua    'run = function(name)'      'shape 5 — the table_constructor spelling'
presence main.lua    '  do'                      'a bare do … end scope block'
presence main.lua    '  repeat'                  'a repeat … until loop'
presence main.lua    'total < 0 and n > 0'       'the WORD boolean operator `and`'
presence greeter.lua 'elseif n == ""'            'an elseif arm'
presence greeter.lua 'setmetatable('             'the metatable idiom the inheritance floor is about'
presence greeter.lua 'require("util")'           'a require call (NOT an import directive)'

MAP_OUT="$TMP/map.xml"
"$BIN" "$FIX" --no-cache >"$MAP_OUT" 2>"$TMP/map.err"
MAP_EXIT=$?
[ "$MAP_EXIT" -eq 0 ] && ok "default map: exits 0 on the Lua fixture" || no "default map: exited $MAP_EXIT: $( cat "$TMP/map.err" )"
command -v xmllint >/dev/null 2>&1 && { xmllint --noout "$MAP_OUT" && ok "default map: passes xmllint --noout" || no "default map: xmllint failed"; }
[ -s "$TMP/map.err" ] && no "default map: unexpected stderr (ABI/degrade?): $( cat "$TMP/map.err" )" || ok "default map: clean stderr (no ABI mismatch / degrade)"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 1. STRUCTURE: all FIVE definition spellings, 8 symbols across 3 files ==="
# ═══════════════════════════════════════════════════════════════════════════

grep -q 'files=3 symbols=8' "$MAP_OUT" && ok "header: files=3 symbols=8" || no "header: expected files=3 symbols=8: $( grep -o 'files=[0-9]* symbols=[0-9]*' "$MAP_OUT" )"
grep -q 'edges=3' "$MAP_OUT" && ok "header: edges=3" || no "header: expected edges=3: $( grep -o 'edges=[0-9]*' "$MAP_OUT" )"
grep -q 'ambiguous=0' "$MAP_OUT" && ok "header: ambiguous=0" || no "header: expected ambiguous=0: $( grep -o 'ambiguous=[0-9]*' "$MAP_OUT" )"
grep -q 'unresolved=0' "$MAP_OUT" && ok "header: unresolved=0" || no "header: expected unresolved=0: $( grep -o 'unresolved=[0-9]*' "$MAP_OUT" )"

python3 - "$MAP_OUT" <<'PYEOF' >"$TMP/parsed.json"
import sys, re, json
xml = open(sys.argv[1], encoding='utf-8').read()
files = re.findall(r'<f p="([^"]+)"[^>]*>(.*?)</f>', xml, re.S)
out = {}
for path, body in files:
    name = path.split('/')[-1]
    syms = []
    for sm in re.finditer(r'<s t="(\w+)" n="([^"]*)"[^>]*>(.*?)</s>|<s t="(\w+)" n="([^"]*)"[^>]*/>', body, re.S):
        if sm.group(1) is not None:
            t, n, inner = sm.group(1), sm.group(2), sm.group(3)
        else:
            t, n, inner = sm.group(4), sm.group(5), ""
        syms.append({"t": t, "n": n, "calls": re.findall(r'<c n="([^"]*)"', inner)})
    out[name] = syms
print(json.dumps(out))
PYEOF

python3 - "$TMP/parsed.json" <<'PYEOF' >"$TMP/struct_check"
import json, sys
d = json.load(open(sys.argv[1]))
def has(f, n, t):     return any(s["n"] == n and s["t"] == t for s in d.get(f, []))
def count(f, n):      return sum(1 for s in d.get(f, []) if s["n"] == n)
def edge(f, frm, to): return any(s["n"] == frm and to in s["calls"] for s in d.get(f, []))
print("S1_LOCALFN:%s"   % has("greeter.lua", "fallback", "fn"))
print("S2_DOTINDEX:%s"  % has("util.lua", "trim", "fn"))
print("S3_COLON:%s"     % has("greeter.lua", "greet", "method"))
print("S4_ASSIGN:%s"    % has("util.lua", "pad", "fn"))
print("S5_TABLE:%s"     % has("main.lua", "run", "fn"))
print("NEW_ONCE:%s"     % (count("greeter.lua", "new") == 1))   # `new = Greeter.new` is NOT a 2nd def
print("E_DOTCALL:%s"    % edge("util.lua", "shout", "trim"))      # M.trim(s), same file
print("E_XFILE:%s"      % edge("greeter.lua", "greet", "shout"))  # util.shout(), CROSS-FILE
print("E_TABLEFN:%s"    % edge("main.lua", "run", "fallback"))    # greeter.fallback(), CROSS-FILE
PYEOF
cat "$TMP/struct_check"

arm(){ grep -q "^$1:True" "$TMP/struct_check" && ok "$2" || no "$2 — MISSING"; }
arm S1_LOCALFN  'shape 1: `local function fallback(n)` -> t="fn"'
arm S2_DOTINDEX 'shape 2: `function M.trim(s)` -> t="fn" named by the FIELD, not by M'
arm S3_COLON    'shape 3: `function Greeter:greet()` -> t="method" (the colon IS the method evidence)'
arm S4_ASSIGN   'shape 4: `M.pad = function(s)` -> t="fn"'
arm S5_TABLE    'shape 5: `{ run = function(name) … }` -> t="fn"'
arm NEW_ONCE    'negative: `new = Greeter.new` in a table is NOT a second definition of new'
arm E_DOTCALL   'edge: shout -> trim (M.trim(s), dot_index call)'
arm E_XFILE     'edge: greet -> shout (util.shout(), CROSS-FILE)'
arm E_TABLEFN   'edge: run -> fallback (greeter.fallback(), CROSS-FILE, from inside a table field)'

CR="$( "$BIN" "$FIX" --callers=trim --no-cache 2>/dev/null )"
echo "$CR" | grep -q 'n="shout"' && ok "--callers=trim lists shout" || no "--callers=trim did not list shout: $CR"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 2. IMPORTS: Lua has none, and that is a POSITIVE assertion ==="
# ═══════════════════════════════════════════════════════════════════════════
# `require "mod"` is an ordinary global function call, not an import directive — so Lua is absent from
# lintrules.h's dependencyCapable set and a .lua file is never a node in the dependency graph. The
# fixture spells three requires (guarded in §0), so a `<deps files="0">` here is a real measurement.
DEPS="$( "$BIN" "$FIX" --deps --no-cache 2>/dev/null )"
echo "$DEPS" | grep -q '<deps files="0"' && ok '--deps: files="0" — require() is a call, never an Include record' \
    || no "--deps: expected files=0 on a Lua corpus: $( echo "$DEPS" | grep -o '<deps [^>]*>' )"
echo "$DEPS" | grep -q 'dep_files="0"' && ok '--deps health: dep_files="0" — Lua is not dependency-capable' \
    || no "--deps health: expected dep_files=0: $( echo "$DEPS" | grep -o '<health [^/]*/>' )"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 3. CENSUS: --skipped no longer drops Lua, and names it ==="
# ═══════════════════════════════════════════════════════════════════════════
SK="$( "$BIN" "$FIX" --skipped --no-cache 2>/dev/null )"
echo "$SK" | grep -q 'unsupported_ext="0"' && ok '--skipped: unsupported_ext=0 (no .lua falls out of the index)' \
    || no "--skipped: expected unsupported_ext=0: $( echo "$SK" | grep -o 'unsupported_ext="[0-9]*"' )"
echo "$SK" | grep -q '<lang n="lua" files="3" symbols="8"/>' && ok '--skipped: <lang n="lua" files="3" symbols="8"/> census row' \
    || no "--skipped: lua census row missing/wrong: $( echo "$SK" | grep -o '<lang [^/]*/>' )"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 4. METRICS: the Lua control-flow carve-outs, by exact number ==="
# ═══════════════════════════════════════════════════════════════════════════
CX="$( cxof "$BIN" "$FIX" countdown )"
[ "$CX" = 'cx="5"' ] && ok 'countdown(): cx=5 (for + repeat + while + `and`; the do … end block counts for NOTHING)' \
    || no "countdown(): expected cx=5, got $CX"
CX="$( cxof "$BIN" "$FIX" fallback )"
[ "$CX" = 'cx="3"' ] && ok 'fallback(): cx=3 (if + elseif — Lua elseif is a sibling, counted in isDecisionType)' \
    || no "fallback(): expected cx=3, got $CX"
MET="$( "$BIN" "$FIX" --metrics --no-cache 2>/dev/null )"
echo "$MET" | grep -q 'n="countdown"[^>]*nest="1"' && ok 'countdown(): nest=1 (the do-block does not deepen nesting either)' \
    || no "countdown(): expected nest=1: $( echo "$MET" | grep -o 'n="countdown"[^>]*nest="[0-9]*"' )"
# ev= is a DISCLOSED non-goal for Lua (model.h::evCountedLang) — assert the absence, so today's silence
# can never be read as "ev == 0" and a future round that adds ev has to come here and say so.
echo "$MET" | grep -q 'n="countdown"[^>]*ev="' && no 'countdown(): ev= emitted, but Lua is outside evCountedLang — one of the two is now wrong' \
    || ok 'countdown(): no ev= attribute (Lua is deliberately outside evCountedLang; "not measured", not zero)'

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 5. THE DISCLOSED FLOOR: no inheritance edges on a metatable corpus ==="
# ═══════════════════════════════════════════════════════════════════════════
# greeter.lua really does inherit via setmetatable (guarded in §0). ripwire reports NOTHING for it, on
# purpose — there is no syntax to read. This arm exists so that absence is a recorded decision rather
# than an accident somebody later "fixes" by inventing an edge.
USES_G="$( "$BIN" "$FIX" --uses=Greeter --no-cache 2>/dev/null )"
echo "$USES_G" | grep -q 'role="extends"' \
    && no 'an extends use-site appeared on a Lua corpus — Lua has no inheritance SYNTAX, so this edge was invented' \
    || ok 'no role="extends" use-site (the metatable floor holds; queries/lua/tags.scm states it)'
LEGO="$( "$BIN" "$FIX" --lego=Greeter --no-cache 2>/dev/null )"
echo "$LEGO" | grep -q '<impl ' \
    && no "--lego=Greeter listed an implementor on a Lua corpus: $LEGO" \
    || ok '--lego=Greeter lists no implementors (same floor, second surface)'

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 6. DETERMINISM: default map thrice, byte-identical ==="
# ═══════════════════════════════════════════════════════════════════════════
"$BIN" "$FIX" --no-cache >"$TMP/det_a.xml" 2>/dev/null
"$BIN" "$FIX" --no-cache >"$TMP/det_b.xml" 2>/dev/null
"$BIN" "$FIX" --no-cache >"$TMP/det_c.xml" 2>/dev/null
diff -q "$TMP/det_a.xml" "$TMP/det_b.xml" >/dev/null && diff -q "$TMP/det_b.xml" "$TMP/det_c.xml" >/dev/null \
    && ok "determinism: default map byte-identical across three runs" \
    || no "determinism: default map differs across runs"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 7. MUTATION: each carve-out moved independently ==="
# ═══════════════════════════════════════════════════════════════════════════
mutate(){ rm -rf "$TMP/mut"; cp -R "$FIX" "$TMP/mut"; }
pyedit(){ python3 -c '
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
if old not in s:
    sys.exit("mutation target not present: " + old)
open(p, "w").write(s.replace(old, new, 1))
' "$@"; }

# 7a. DELETE the do … end block -> cx must STAY 5. This is the arm that proves the carve-out is real:
#     on a build that counts Lua's do_statement as a decision, the unmutated cx is 6 and this is 5.
mutate
pyedit "$TMP/mut/main.lua" '  do
    total = total + 1
  end
' '' && { CX="$( cxof "$BIN" "$TMP/mut" countdown )"
          [ "$CX" = 'cx="5"' ] && ok "mutation: do … end deleted -> cx STAYS 5 (the block was never a decision)" \
                               || no "mutation: expected cx=5 after deleting the do-block, got $CX"; } \
      || no "mutation 7a: the do-block edit did not apply — the arm would have been inert"

# 7b. DELETE the repeat … until loop -> cx must drop 5 -> 4
mutate
pyedit "$TMP/mut/main.lua" '  repeat
    total = total - 1
  until total <= 0
' '' && { CX="$( cxof "$BIN" "$TMP/mut" countdown )"
          [ "$CX" = 'cx="4"' ] && ok "mutation: repeat … until deleted -> cx 5 -> 4 (repeat_statement really is a loop)" \
                               || no "mutation: expected cx=4 after deleting the repeat loop, got $CX"; } \
      || no "mutation 7b: the repeat edit did not apply — the arm would have been inert"

# 7c. DROP the `and` from the while condition -> cx must drop 5 -> 4
mutate
pyedit "$TMP/mut/main.lua" 'while total < 0 and n > 0 do' 'while total < 0 do' \
    && { CX="$( cxof "$BIN" "$TMP/mut" countdown )"
         [ "$CX" = 'cx="4"' ] && ok "mutation: \`and\` dropped -> cx 5 -> 4 (the WORD boolean operator really is counted)" \
                              || no "mutation: expected cx=4 after dropping \`and\`, got $CX"; } \
    || no "mutation 7c: the and-edit did not apply — the arm would have been inert"

# 7d. DELETE the elseif arm -> cx(fallback) must drop 3 -> 2
mutate
pyedit "$TMP/mut/greeter.lua" '  elseif n == "" then
    return "world"
' '' && { CX="$( cxof "$BIN" "$TMP/mut" fallback )"
          [ "$CX" = 'cx="2"' ] && ok "mutation: elseif deleted -> cx 3 -> 2 (elseif_statement really is a decision)" \
                               || no "mutation: expected cx=2 after deleting the elseif, got $CX"; } \
      || no "mutation 7d: the elseif edit did not apply — the arm would have been inert"

# 7e. rename the CROSS-FILE call site (leave the def intact) -> the edge must vanish
mutate
pyedit "$TMP/mut/greeter.lua" 'util.shout(self.name)' 'util.shoutX(self.name)' \
    && { "$BIN" "$TMP/mut" --no-cache >"$TMP/mut.xml" 2>/dev/null
         grep -q '<c n="shout"/>' "$TMP/mut.xml" \
             && no "mutation: greet -> shout edge survived a renamed call site (tautology)" \
             || ok "mutation: renamed util.shout() call site -> greet -> shout edge vanished"; } \
    || no "mutation 7e: the call-site rename did not apply — the arm would have been inert"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
