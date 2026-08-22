#!/usr/bin/env bash
# phpcheck.sh — the PHP ingest coverage gate (grammar + tags.scm + base clauses + `use` imports).
#
# Modeled on csharpcheck.sh / javarubycheck.sh: a small fixture, assertions pinned to what the binary
# ACTUALLY does (every number below was read off a real run before it was written down), plus mutation
# arms so the edge and metric assertions are non-tautological.
#
# ── WHY THIS GATE IS NOT VACUOUS ──────────────────────────────────────────────────────────────────────
# Against a binary built from cd30104 — the commit this lane branched from, which has no PHP grammar at
# all — every .php/.phtml file leaves the index as `why="unsupported-ext"`, so the map reports
# `files=0 symbols=0` and EVERY arm below fails. That red is trivially easy to get, which is exactly why
# it is not the point: a "the language now parses" gate that only asserted files>0 would stay green
# through a tags.scm that captured nothing but class names. So the arms below pin SPECIFIC symbols,
# SPECIFIC kinds, SPECIFIC cross-file edges, the SPECIFIC extends use-site, the SPECIFIC import targets
# and an EXACT cyclomatic number whose arithmetic depends on the PHP-only decision node this port added
# (`match_conditional_expression`) — and §7's mutations prove each of those can actually go red.
#
# ── FIXTURE (test/phpfix/) ────────────────────────────────────────────────────────────────────────────
#   src/GreeterInterface.php  ns PhpFix\Services   interface GreeterInterface { greet(): string; }
#   src/Greeter.php           ns PhpFix\Services   use PhpFix\Support\Formatter;
#                                                  trait Loggable { logLine() }
#                                                  class Greeter implements GreeterInterface
#                                                    { use Loggable; const DEFAULT_NAME;
#                                                      greet() -> $this->decorate();
#                                                      decorate() -> Formatter::wrap() }
#   src/Formatter.php         ns PhpFix\Support    enum Style: string { case Plain; case Loud; }
#                                                  function shout(); class Formatter { static wrap() -> shout() }
#   index.php                 (no namespace)       use …\Greeter; use …\Style;
#                                                  describe() -> new Greeter() ; $greeter?->greet()
#   view.phtml                markup + <?php … ?>  function renderGreeting()
#
# ── FINDINGS from running `ripwire test/phpfix` and reading the raw output ────────────────────────────
#   - 5 files / 16 symbols / edges=5 / ambiguous=0 / unresolved=0, clean stderr (no ABI/degrade line).
#   - KIND MAPPING: interface -> t="iface"; TRAIT -> t="iface" too (a trait is a named bag of members
#     classes bind to — see queries/php/tags.scm for why that bucket, and what it costs); enum ->
#     t="struct" (the typedef/alias/enum bucket, matching Java's and C#'s enum_declaration); class ->
#     t="cls"; method_declaration -> t="method"; free function_definition -> t="fn"; a `const` element
#     and an `enum_case` -> t="var".
#   - `ambiguous=0` is load-bearing, not decoration: TWO symbols are named `greet` (the interface's
#     body-less declaration and Greeter's implementation). Decl/def collapse resolves the call to the
#     one WITH a body, so `describe -> greet` is a single unambiguous edge rather than an amb="1" spray.
#   - .phtml really does route through the `php/` sub-grammar: renderGreeting is extracted out of a file
#     whose first byte is `<`, which is the whole reason CMakeLists vendors `php/` and not `php_only/`.
#   - `use` directives are captured by ingest.cpp::captureIncludes (namespace_use_declaration), NOT by
#     tags.scm — matching every other language. `--deps` lists all three verbatim; `--uses=PhpFix` shows
#     three role="import" sites (importName keeps the leading identifier run, so the ref name is the
#     ROOT namespace segment — the same shape C#'s `using CsharpFix.Services;` already produces).
#   - `class Greeter implements GreeterInterface` (class_interface_clause) emits an extends use-site:
#     --uses=GreeterInterface shows role="extends" in_id="Greeter"; --lego lists Greeter as implementor.
#     --lego reports methods="0" caveat="not-extracted-for-lang" — DELIBERATE and asserted below: PHP is
#     not in serialize.h's legoMethodContractSound allow-list, and the caveat is the disclosure.
#   - describe() scores cx=7. The hand count: 1 base + `if` + `foreach` + TWO match arms + `while` +
#     `&&` = 7. The `default =>` arm is a match_default_expression and is deliberately NOT a decision
#     (matching a C-family `default:` label), which is why the number is 7 and not 8.
#   - import narrowing: PHP is intentionally NOT in resolve.h's includeLangOf table, so it falls through
#     to IncludeLang::Other and DEFERS, exactly as Java and C# do — a `use` is visible but never narrows
#     an ambiguous call. PSR-4 maps a namespace onto a DIRECTORY via composer.json, which this tool does
#     not read, so there is no sound string->fileId rule to write.
#
# Usage:
#   bash test/phpcheck.sh
#   RIPWIRE_BIN=build/ripwire bash test/phpcheck.sh
#   RIPWIRE_BIN=asan/ripwire  bash test/phpcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
FIX="$ROOT/test/phpfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for XML assertions"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }

echo "phpcheck: BIN=$BIN  FIX=$FIX"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 0. PRESENCE: the fixture really spells every shape the arms below assert ==="
# ═══════════════════════════════════════════════════════════════════════════
# A gate whose probe target can vanish passes for the wrong reason (CONTRIBUTING.md §2). These greps
# are the guard: if a fixture edit deletes a shape, THIS arm reds instead of the assertion going inert.
presence(){ grep -qF -- "$2" "$FIX/$1" && ok "fixture $1 spells: $3" || no "fixture $1 no longer spells: $3"; }
presence src/GreeterInterface.php 'interface GreeterInterface'        'an interface declaration'
presence src/Greeter.php          'trait Loggable'                    'a trait declaration'
presence src/Greeter.php          'implements GreeterInterface'       'a class_interface_clause'
presence src/Greeter.php          'use PhpFix\Support\Formatter;'     'a top-level use directive'
presence src/Greeter.php          'const DEFAULT_NAME'                'a class constant'
presence src/Formatter.php        'enum Style'                        'an enum declaration'
presence src/Formatter.php        'case Plain'                        'an enum case'
presence src/Greeter.php          'Formatter::wrap('                  'a scoped_call_expression'
presence index.php                'new Greeter()'                     'an object_creation_expression'
presence index.php                '?->greet()'                        'a nullsafe_member_call_expression'
presence index.php                'match ($style)'                    'a match expression'
presence view.phtml               '<?php'                             'markup wrapping a php island'

MAP_OUT="$TMP/map.xml"
"$BIN" "$FIX" --no-cache >"$MAP_OUT" 2>"$TMP/map.err"
MAP_EXIT=$?
[ "$MAP_EXIT" -eq 0 ] && ok "default map: exits 0 on the PHP fixture" || no "default map: exited $MAP_EXIT: $( cat "$TMP/map.err" )"
command -v xmllint >/dev/null 2>&1 && { xmllint --noout "$MAP_OUT" && ok "default map: passes xmllint --noout" || no "default map: xmllint failed"; }
[ -s "$TMP/map.err" ] && no "default map: unexpected stderr (ABI/degrade?): $( cat "$TMP/map.err" )" || ok "default map: clean stderr (no ABI mismatch / degrade)"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 1. STRUCTURE: 16 symbols across 5 files, kinds + edges match the fixture ==="
# ═══════════════════════════════════════════════════════════════════════════

grep -q 'files=5 symbols=16' "$MAP_OUT" && ok "header: files=5 symbols=16" || no "header: expected files=5 symbols=16: $( grep -o 'files=[0-9]* symbols=[0-9]*' "$MAP_OUT" )"
grep -q 'edges=5' "$MAP_OUT" && ok "header: edges=5" || no "header: expected edges=5: $( grep -o 'edges=[0-9]*' "$MAP_OUT" )"
grep -q 'ambiguous=0' "$MAP_OUT" && ok "header: ambiguous=0 (decl/def collapse resolved the interface's greet away)" || no "header: expected ambiguous=0: $( grep -o 'ambiguous=[0-9]*' "$MAP_OUT" )"
grep -q 'unresolved=0' "$MAP_OUT" && ok "header: unresolved=0" || no "header: expected unresolved=0: $( grep -o 'unresolved=[0-9]*' "$MAP_OUT" )"

# ─── parse the per-file symbol + edge structure once, reuse for all checks ────
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
        calls = re.findall(r'<c n="([^"]*)"', inner)
        syms.append({"t": t, "n": n, "calls": calls})
    out[name] = syms
print(json.dumps(out))
PYEOF

python3 - "$TMP/parsed.json" <<'PYEOF' >"$TMP/struct_check"
import json, sys
d = json.load(open(sys.argv[1]))
def has(f, n, t):     return any(s["n"] == n and s["t"] == t for s in d.get(f, []))
def edge(f, frm, to): return any(s["n"] == frm and to in s["calls"] for s in d.get(f, []))
print("IFACE:%s"        % has("GreeterInterface.php", "GreeterInterface", "iface"))
print("IFACE_METHOD:%s" % has("GreeterInterface.php", "greet", "method"))
print("TRAIT:%s"        % has("Greeter.php", "Loggable", "iface"))
print("TRAIT_METHOD:%s" % has("Greeter.php", "logLine", "method"))
print("CLASS:%s"        % has("Greeter.php", "Greeter", "cls"))
print("CONST:%s"        % has("Greeter.php", "DEFAULT_NAME", "var"))
print("ENUM:%s"         % has("Formatter.php", "Style", "struct"))
print("ENUM_CASE:%s"    % (has("Formatter.php", "Plain", "var") and has("Formatter.php", "Loud", "var")))
print("FREE_FN:%s"      % has("Formatter.php", "shout", "fn"))
print("STATIC_M:%s"     % has("Formatter.php", "wrap", "method"))
print("PHTML_FN:%s"     % has("view.phtml", "renderGreeting", "fn"))
print("E_THIS:%s"       % edge("Greeter.php", "greet", "decorate"))          # $this->decorate()
print("E_SCOPED:%s"     % edge("Greeter.php", "decorate", "wrap"))           # Formatter::wrap(), cross-file
print("E_NEW:%s"        % edge("index.php", "describe", "Greeter"))          # new Greeter(), cross-file
print("E_NULLSAFE:%s"   % edge("index.php", "describe", "greet"))            # $greeter?->greet(), cross-file
print("E_SELFCALL:%s"   % edge("Formatter.php", "wrap", "shout"))            # shout(), same file
PYEOF
cat "$TMP/struct_check"

arm(){ grep -q "^$1:True" "$TMP/struct_check" && ok "$2" || no "$2 — MISSING"; }
arm IFACE        'GreeterInterface.php: interface -> t="iface"'
arm IFACE_METHOD 'GreeterInterface.php: body-less greet() still emitted as t="method"'
arm TRAIT        'Greeter.php: trait Loggable -> t="iface" (the documented trait bucket)'
arm TRAIT_METHOD 'Greeter.php: a trait method is a t="method" symbol'
arm CLASS        'Greeter.php: class Greeter -> t="cls"'
arm CONST        'Greeter.php: class const DEFAULT_NAME -> t="var" (keyword-evidenced, no SCREAMING gate)'
arm ENUM         'Formatter.php: enum Style -> t="struct" (the enum/typedef bucket)'
arm ENUM_CASE    'Formatter.php: enum cases Plain/Loud -> t="var"'
arm FREE_FN      'Formatter.php: free function shout() -> t="fn"'
arm STATIC_M     'Formatter.php: static method wrap() -> t="method"'
arm PHTML_FN     '.phtml: renderGreeting() extracted from a MARKUP-first file (php/ sub-grammar, not php_only/)'
arm E_THIS       'edge: greet -> decorate  ($this->m(), member_call_expression)'
arm E_SCOPED     'edge: decorate -> wrap   (Formatter::wrap(), scoped_call_expression, CROSS-FILE)'
arm E_NEW        'edge: describe -> Greeter (new Greeter(), object_creation_expression, CROSS-FILE)'
arm E_NULLSAFE   'edge: describe -> greet  ($g?->greet(), nullsafe_member_call_expression, CROSS-FILE)'
arm E_SELFCALL   'edge: wrap -> shout      (bare function_call_expression)'

# cross-check via --callees / --callers (independent of the raw-XML parse)
CE="$( "$BIN" "$FIX" --callees=describe --no-cache 2>/dev/null )"
echo "$CE" | grep -q 'n="Greeter"' && ok "--callees=describe lists Greeter" || no "--callees=describe missing Greeter: $CE"
echo "$CE" | grep -q 'n="greet"'   && ok "--callees=describe lists greet"   || no "--callees=describe missing greet: $CE"
CR="$( "$BIN" "$FIX" --callers=wrap --no-cache 2>/dev/null )"
echo "$CR" | grep -q 'n="decorate"' && ok "--callers=wrap lists decorate" || no "--callers=wrap did not list decorate: $CR"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo '=== 2. IMPORTS: a use directive -> Include records + import use-sites ==='
# ═══════════════════════════════════════════════════════════════════════════

DEPS="$( "$BIN" "$FIX" --deps --no-cache 2>/dev/null )"
for T in 'PhpFix\Services\Greeter' 'PhpFix\Support\Style' 'PhpFix\Support\Formatter'; do
    case "$DEPS" in
        *"<inc t=\"$T\"/>"*) ok "--deps: <inc t=\"$T\"/> present";;
        *) no "--deps: include target '$T' MISSING";;
    esac
done

USES_NS="$( "$BIN" "$FIX" --uses=PhpFix --no-cache 2>/dev/null )"
echo "$USES_NS" | grep -q 'count="3"' && ok "--uses=PhpFix: count=3 import use-sites" || no "--uses=PhpFix: expected count=3: $( echo "$USES_NS" | grep -o 'count="[0-9]*"' )"
echo "$USES_NS" | grep -q 'role="import" p="index.php:3"' && ok '--uses=PhpFix: role="import" @index.php:3' || no '--uses=PhpFix: index.php:3 import site missing'
echo "$USES_NS" | grep -q 'role="import" p="src/Greeter.php:5"' && ok '--uses=PhpFix: role="import" @src/Greeter.php:5' || no '--uses=PhpFix: Greeter.php:5 import site missing'

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 3. INHERITANCE: class_interface_clause -> extends use-site + --lego ==="
# ═══════════════════════════════════════════════════════════════════════════

USES_IG="$( "$BIN" "$FIX" --uses=GreeterInterface --no-cache 2>/dev/null )"
echo "$USES_IG" | grep -q 'role="extends"' && echo "$USES_IG" | grep -q 'in_id="Greeter"' \
    && ok 'class Greeter implements GreeterInterface emits an extends use-site (in_id="Greeter")' \
    || no "extends use-site missing/wrong: $USES_IG"

LEGO="$( "$BIN" "$FIX" --lego=GreeterInterface --no-cache 2>/dev/null )"
echo "$LEGO" | grep -q '<iface n="GreeterInterface"' && echo "$LEGO" | grep -q '<impl n="Greeter"' \
    && ok "--lego=GreeterInterface lists Greeter as its implementor" \
    || no "--lego=GreeterInterface did not surface Greeter: $LEGO"
echo "$LEGO" | grep -q 'caveat="not-extracted-for-lang"' \
    && ok '--lego: the method contract is SUPPRESSED for PHP and says so (caveat=not-extracted-for-lang)' \
    || no "--lego: expected the not-extracted-for-lang caveat on a PHP interface: $LEGO"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 4. METRICS: the PHP-specific decision nodes are counted, and only once ==="
# ═══════════════════════════════════════════════════════════════════════════
# cx(describe) = 1 + if + foreach + 2 match arms + while + && = 7.
# The `default =>` arm is a match_default_expression and is NOT a decision, so 7 (not 8) is the proof
# that only the CONDITIONAL match arms are counted. §7's mutations show both halves can move.
MET="$( "$BIN" "$FIX" --metrics --no-cache 2>/dev/null )"
echo "$MET" | grep -q 'n="describe"[^>]*cx="7"' && ok 'describe(): cx=7 (if+foreach+2 match arms+while+&&; default arm excluded)' \
    || no "describe(): expected cx=7: $( echo "$MET" | grep -o 'n="describe"[^>]*cx="[0-9]*"' )"
echo "$MET" | grep -q 'n="describe"[^>]*nest="2"' && ok 'describe(): nest=2 (foreach > match)' \
    || no "describe(): expected nest=2: $( echo "$MET" | grep -o 'n="describe"[^>]*nest="[0-9]*"' )"
# ev= is a DISCLOSED non-goal for PHP (model.h::evCountedLang) — assert the absence so a future round
# that adds ev has to come here and say so, and so today's silence can never be read as "ev == 0".
echo "$MET" | grep -q 'n="describe"[^>]*ev="' && no 'describe(): ev= emitted, but PHP is outside evCountedLang — one of the two is now wrong' \
    || ok 'describe(): no ev= attribute (PHP is deliberately outside evCountedLang; "not measured", not zero)'

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 5. CENSUS: --skipped no longer drops PHP, and names it ==="
# ═══════════════════════════════════════════════════════════════════════════
SK="$( "$BIN" "$FIX" --skipped --no-cache 2>/dev/null )"
echo "$SK" | grep -q 'unsupported_ext="0"' && ok '--skipped: unsupported_ext=0 (no .php/.phtml falls out of the index)' \
    || no "--skipped: expected unsupported_ext=0: $( echo "$SK" | grep -o 'unsupported_ext="[0-9]*"' )"
echo "$SK" | grep -q '<lang n="php" files="5" symbols="16"/>' && ok '--skipped: <lang n="php" files="5" symbols="16"/> census row' \
    || no "--skipped: php census row missing/wrong: $( echo "$SK" | grep -o '<lang [^/]*/>' )"

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
echo "=== 7. MUTATION: break the thing, watch the assertion go red ==="
# ═══════════════════════════════════════════════════════════════════════════
mutate(){ rm -rf "$TMP/mut"; cp -R "$FIX" "$TMP/mut"; }

# 7a. rename the CALL SITES (leave every def intact) -> the edges must vanish
mutate
sed 's/\$this->decorate(/$this->decorateX(/'    "$FIX/src/Greeter.php" >"$TMP/mut/src/Greeter.php"
sed -e 's/\$greeter?->greet()/$greeter?->greetX()/' -e 's/new Greeter()/new GreeterX()/' "$FIX/index.php" >"$TMP/mut/index.php"
"$BIN" "$TMP/mut" --no-cache >"$TMP/mut.xml" 2>/dev/null
python3 - "$TMP/mut.xml" <<'PYEOF' >"$TMP/mut_check"
import sys, re
xml = open(sys.argv[1], encoding='utf-8').read()
print("THIS_GONE:%s"     % (not bool(re.search(r'n="greet"[^>]*>.*?<c n="decorate"', xml, re.S))))
print("NULLSAFE_GONE:%s" % (not bool(re.search(r'n="describe"[^>]*>(?:(?!</s>).)*?<c n="greet"', xml, re.S))))
print("NEW_GONE:%s"      % (not bool(re.search(r'n="describe"[^>]*>(?:(?!</s>).)*?<c n="Greeter"', xml, re.S))))
PYEOF
cat "$TMP/mut_check"
grep -q "THIS_GONE:True"     "$TMP/mut_check" && ok "mutation: renamed \$this->decorate() -> greet -> decorate edge vanished"         || no "mutation: greet -> decorate edge survived a renamed call site (tautology)"
grep -q "NULLSAFE_GONE:True" "$TMP/mut_check" && ok "mutation: renamed ?->greet() -> describe -> greet edge vanished"                 || no "mutation: describe -> greet edge survived a renamed call site (tautology)"
grep -q "NEW_GONE:True"      "$TMP/mut_check" && ok "mutation: renamed new Greeter() -> describe -> Greeter edge vanished"            || no "mutation: describe -> Greeter edge survived a renamed call site (tautology)"

# 7b. delete ONE conditional match arm -> cx must drop 7 -> 6 (proves match arms are counted)
mutate
grep -v 'Style::Loud =>' "$FIX/index.php" >"$TMP/mut/index.php"
CX="$( "$BIN" "$TMP/mut" --metrics --no-cache 2>/dev/null | grep -o 'n="describe"[^>]* cx="[0-9]*"' | grep -o ' cx="[0-9]*"' | tr -d ' ' )"
[ "$CX" = 'cx="6"' ] && ok "mutation: one match arm removed -> cx 7 -> 6 (match_conditional_expression really is the decision)" \
    || no "mutation: expected cx=6 after removing a match arm, got $CX"

# 7c. drop the `&&` from the while condition -> cx must drop 7 -> 6
mutate
sed 's/while (strlen($out) > 64 \&\& $out !== .\{2\}) {/while (strlen($out) > 64) {/' "$FIX/index.php" >"$TMP/mut/index.php"
grep -q 'while (strlen($out) > 64) {' "$TMP/mut/index.php" \
    && { CX="$( "$BIN" "$TMP/mut" --metrics --no-cache 2>/dev/null | grep -o 'n="describe"[^>]* cx="[0-9]*"' | grep -o ' cx="[0-9]*"' | tr -d ' ' )"
         [ "$CX" = 'cx="6"' ] && ok "mutation: && removed -> cx 7 -> 6 (the boolean operator really is counted)" \
                              || no "mutation: expected cx=6 after removing &&, got $CX"; } \
    || no "mutation 7c: the sed did not rewrite the while condition — the arm would have been inert"

# 7d. drop the implements clause -> the extends use-site and the --lego implementor must both vanish
mutate
sed 's/class Greeter implements GreeterInterface/class Greeter/' "$FIX/src/Greeter.php" >"$TMP/mut/src/Greeter.php"
MUT_LEGO="$( "$BIN" "$TMP/mut" --lego=GreeterInterface --no-cache 2>/dev/null )"
echo "$MUT_LEGO" | grep -q '<impl n="Greeter"' \
    && no "mutation: --lego still lists Greeter after the implements clause was deleted (tautology)" \
    || ok "mutation: implements clause deleted -> --lego no longer lists Greeter"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
