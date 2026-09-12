#!/usr/bin/env bash
# kotlincheck.sh — the Kotlin ingest coverage gate (grammar + tags.scm + the Kotlin<->Java JVM bridge).
#
# Modeled on luacheck.sh/elixircheck.sh: a small fixture, assertions pinned to what the binary
# ACTUALLY does (every number below was read off a real run before it was written down), plus
# mutation arms so the edge assertions are non-tautological.
#
# ── WHY THIS GATE IS NOT VACUOUS ──────────────────────────────────────────────────────────────────
# Against a pre-Kotlin binary, every .kt file in this fixture leaves the index as
# `why="unsupported-ext"` — the map reports files=1 (the lone .java) and every Kotlin-side arm fails.
# That trivial red is not what this gate is for. The two things worth pinning by exact number are the
# things a naive port gets wrong silently, not loudly: (a) whether a class/object/companion-object
# member gets its ENCLOSING SCOPE in its canonical id= (kotlinEnclosingScopeOf, ingest_names.h) — a
# scope-less id is exactly what makes a same-name collision across classes invisible — and (b) the
# JVM bridge itself (graph.h langCompatible + keepOwnJvmLanguageCandidates), in BOTH directions, plus the
# collision it resolves by rule: a same-name Kotlin/Java pair binds the caller's OWN language (§5), in a
# one-directory tree and a split one alike (§14) — never both (an ambiguity that only a flat fixture could
# show) and never neither (what a split tree silently did before the rule).
#
# ── FIXTURE (test/kotlinfix/) ─────────────────────────────────────────────────────────────────────
#   Util.kt        fun square(n: Int): Int                  -- top-level function, cross-file callee
#                   class Formatter { fun format(n: Int) }    -- a plain member function
#                   object Extra { fun helper(n: Int) }       -- one half of the collision pair
#                   enum class Mode { ON, OFF }               -- the enum_class_body collision pair (§8)
#                   interface Labeled { fun label(): String } -- captureBases DIRECT shape (§9, bare, no call)
#                   open class Shape { open fun area(): Int }
#                   class Square(...) : Shape(), Labeled       -- captureBases WRAPPED shape (§9, Shape()) + DIRECT (Labeled)
#                   fun describe(name, age = 0, vararg tags)   -- countParams fixture (§10): 3 real params, not 5
#   Greeter.kt      class Greeter(name: String) {
#                     companion object { fun of(name): Greeter } -- companion-object factory function
#                     fun greet(): String -> square(2)          -- member function, CROSS-FILE call
#                   }
#                   fun Int.doubled(): Int                    -- extension function
#                   fun useJavaHelper(): Int -> JavaBridge.helper(5)  -- Kotlin -> ???, QUALIFIED on a name both define (§5 trade-off)
#                   fun useJavaOnly(): Int -> JavaBridge.javaOnly(3)  -- Kotlin -> Java, qualified, a name only Java defines (§3)
#                   fun ambiguousCall(): Int -> helper(5)      -- Kotlin -> ???, BARE (the collision probe)
#                   fun runAll(): Int -> of, greet, doubled, useJavaHelper, useJavaOnly, ambiguousCall
#   JavaBridge.java class JavaBridge {
#                     static int helper(int n)                 -- the OTHER half of the collision pair
#                     static int javaOnly(int n)               -- the Java-only bridge target (§3)
#                     int callGreeter() -> Greeter.of(...), .greet()  -- Java -> Kotlin, BOTH bridge uses
#                   }
#                   class Mode { void run() }                 -- the OTHER half of the §8 collision pair
#
# ── FINDINGS from running `ripwire test/kotlinfix` and reading the raw output ───────────────────────
#   - files=3 symbols=31 edges=14 ambiguous=0 unresolved=0, clean stderr (no ABI/degrade line).
#   - id="Greeter.kt::Greeter::of" / id="Greeter.kt::Greeter::greet" / id="Util.kt::Formatter::format"
#     / id="Util.kt::Extra::helper" — every class/object/companion-object member carries its enclosing
#     scope; a top-level function (square, doubled, useJavaHelper, runAll, ambiguousCall) carries none
#     (scope-less, by contract — id= is absent, not empty, at file scope).
#   - JVM BRIDGE, Java -> Kotlin: --callers=Greeter.kt:of and --callers=Greeter.kt:greet BOTH report
#     count=2 — runAll (same-language) AND JavaBridge.java's callGreeter (cross-language), in the flat
#     fixture and split across three directories alike (§14a).
#   - JVM BRIDGE, Kotlin -> Java: useJavaOnly's `JavaBridge.javaOnly(3)` reaches the Java method — a
#     name only Java defines, which is the case the bridge exists for (§3).
#   - THE COLLISION, by rule: `helper` is defined in both languages, so both Kotlin sites — the BARE
#     ambiguousCall() and the QUALIFIED useJavaHelper() — bind Kotlin's Extra.helper: the bridge admits
#     the other JVM language only when the caller's own defines no candidate (graph.h
#     keepOwnJvmLanguageCandidates). The qualified site is the disclosed trade-off: Kotlin receivers do
#     not narrow candidates yet (ingest_binds.h). What this replaced reported both helpers at
#     ambiguous=2 in this flat fixture — and silently bound NEITHER once the files sat in different
#     directories, the same tier-3 drop that deleted Java edges on square/retrofit (§14).
#   - A same-name Kotlin/Java pair of TYPES is kept as two definitions even when one side has no body
#     (model.h isDefinitionNotDeclaration, §11 and §13); the positional body fallback in ingest_sidecap.h is what
#     gives a bodied Kotlin definition its body span.
#   - --deps: one Include record (`com.example.util.square`, Greeter.kt's import) — Kotlin's
#     IncludeLang is Other/deferred (resolve.h, same posture as Java), so it is captured for
#     disclosure but never file-resolved; dep_langs= names "kt" in the capable set regardless
#     (dependencyCapable() is about the language, not about how far the resolver currently reaches).
#   - --skipped: <lang n="kt" files="2" symbols="23"/> and <lang n="java" files="1" symbols="8"/>.
#   - CAPTUREBASES DELEGATION_SPECIFIER (§9, a review-round coverage gap, not part of the original
#     port): no prior fixture had a Kotlin class with a base clause at all, so captureBases's Kotlin
#     arm (src/ingest_relations.h) — both the WRAPPED shape (`Shape()`, delegation_specifier ->
#     constructor_invocation -> user_type) and the DIRECT shape (`Labeled`, bare interface, no call,
#     user_type right under delegation_specifier) — ran with zero test coverage. `class Square(...) :
#     Shape(), Labeled` exercises both in one header: --uses=Shape shows role="call" (the constructor
#     delegation is ALSO a real call, via tags.scm's constructor_invocation capture) AND role="extends"
#     at the same site; --uses=Labeled shows role="extends" only (no call — Labeled is never invoked).
#   - COUNTPARAMS (§10, a review-round coverage gap): no prior Kotlin fixture had a function with more
#     than one parameter, so the fix for function_value_parameters counting `parameter` children ONLY
#     (a parameter's own `vararg` modifier and default-value expression are SIBLINGS in this grammar,
#     not nested — the generic "every named child" rule misreads 3 real params as 5) had nothing
#     pinning it. `describe(name: String, age: Int = 0, vararg tags: String)` --metrics reports
#     params="3", not 5.
#   - ENUM CLASS BODY (§8, a second-opinion review finding, not part of the original port): Util.kt's
#     `enum class Mode` and JavaBridge.java's package-private `class Mode` are unrelated same-name
#     types. `class_declaration`'s enum-class form nests its members under `enum_class_body`, a
#     DIFFERENT positional child than a plain class's `class_body` — the ObjC/Kotlin body-fallback
#     (ingest_sidecap.h) originally recognized only `class_body`, so the Kotlin enum read as bodyless
#     and graph.h's decl/def collapse deleted it whenever the Java Mode existed, the same silent-drop
#     §5 exists to catch for `helper`. Fixed by adding `enum_class_body` to that fallback.
#
# Usage:
#   bash test/kotlincheck.sh
#   RIPWIRE_BIN=build/ripwire bash test/kotlincheck.sh
#   RIPWIRE_BIN=asan/ripwire  bash test/kotlincheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
FIX="$ROOT/test/kotlinfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for XML assertions"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }

echo "kotlincheck: BIN=$BIN  FIX=$FIX"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 0. PRESENCE: the fixture really spells every shape the arms below assert ==="
# ═══════════════════════════════════════════════════════════════════════════
presence(){ if grep -qF -- "$2" "$FIX/$1"; then ok "fixture $1 spells: $3"; else no "fixture $1 no longer spells: $3"; fi; }
presence Util.kt        'fun square(n: Int)'          'a top-level function, cross-file callee'
presence Util.kt        'class Formatter'             'a plain class with a member function'
presence Util.kt        'object Extra'                'the Kotlin half of the collision pair'
presence Greeter.kt     'companion object'             'a companion-object factory function'
presence Greeter.kt     'fun Int.doubled()'            'an extension function'
presence Greeter.kt     'JavaBridge.helper(5)'         'a qualified Kotlin -> Java call'
presence Greeter.kt     '= helper(5)'                  'the BARE Kotlin -> ??? call (the collision probe; `= ` keeps this from matching the qualified call above)'
presence JavaBridge.java 'static int helper(int n)'    'the Java half of the collision pair'
presence JavaBridge.java 'Greeter.of('                 'a Java -> Kotlin companion-object call'
presence JavaBridge.java 'g.greet()'                   'a Java -> Kotlin member call'
presence Greeter.kt     'JavaBridge.javaOnly(3)'       'a qualified Kotlin -> Java call on a name only Java defines'
presence JavaBridge.java 'static int javaOnly(int n)'  'the Java-only bridge target'

MAP_OUT="$TMP/map.xml"
"$BIN" "$FIX" --no-cache >"$MAP_OUT" 2>"$TMP/map.err"
MAP_EXIT=$?
if [ "$MAP_EXIT" -eq 0 ]; then ok "default map: exits 0 on the Kotlin fixture"; else no "default map: exited $MAP_EXIT: $( cat "$TMP/map.err" )"; fi
command -v xmllint >/dev/null 2>&1 && { if xmllint --noout "$MAP_OUT"; then ok "default map: passes xmllint --noout"; else no "default map: xmllint failed"; fi; }
[ -s "$TMP/map.err" ] && no "default map: unexpected stderr (ABI/degrade?): $( cat "$TMP/map.err" )" || ok "default map: clean stderr (no ABI mismatch / degrade)"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 1. STRUCTURE: 3 files / 31 symbols / 14 edges, and no ambiguity left ==="
# ═══════════════════════════════════════════════════════════════════════════
# symbols=31: the original port's 26, §11's bodyless Taggable collision pair (Kotlin's interface, Java's class and its one
# method: 3, and no call edges, since neither is constructed or invoked), and §3's Java-only bridge pair (useJavaOnly, javaOnly). edges=14: the helper
# collision now costs ONE edge per call site instead of two — both bind Kotlin's Extra.helper (§5), which is -2 — and §3's
# pair adds two (runAll -> useJavaOnly, useJavaOnly -> javaOnly). ambiguous=0: helper's two sites were the only ambiguous
# calls in the fixture. The rest is the original port's accounting: §8's enum_class_body pair (Mode/Mode) adds 3
# definitions and no call edges; §9's Labeled/Shape/Square/describe adds 8 definitions, and Square's `Shape()` delegation
# is one real call edge (tags.scm's constructor_invocation capture), like any other call expression.
if grep -q 'files=3 symbols=31 ' "$MAP_OUT"; then ok "header: files=3 symbols=31"; else no "header: expected files=3 symbols=31: $( grep -o 'files=[0-9]* symbols=[0-9]*' "$MAP_OUT" )"; fi
if grep -q ' edges=14 ' "$MAP_OUT"; then ok "header: edges=14"; else no "header: expected edges=14: $( grep -o 'edges=[0-9]*' "$MAP_OUT" )"; fi
if grep -q ' ambiguous=0 ' "$MAP_OUT"; then ok "header: ambiguous=0"; else no "header: expected ambiguous=0: $( grep -o 'ambiguous=[0-9]*' "$MAP_OUT" )"; fi
if grep -q 'unresolved=0' "$MAP_OUT"; then ok "header: unresolved=0"; else no "header: expected unresolved=0: $( grep -o 'unresolved=[0-9]*' "$MAP_OUT" )"; fi

grep -q 'id="Greeter.kt::Greeter::of"' "$MAP_OUT" && ok 'scope: companion-object factory carries id=Greeter.kt::Greeter::of' \
    || no "scope: Greeter::of id missing — kotlinEnclosingScopeOf regressed: $( grep -o 'n="of"[^>]*' "$MAP_OUT" )"
grep -q 'id="Greeter.kt::Greeter::greet"' "$MAP_OUT" && ok 'scope: member function carries id=Greeter.kt::Greeter::greet' \
    || no "scope: Greeter::greet id missing: $( grep -o 'n="greet"[^>]*' "$MAP_OUT" )"
grep -q 'id="Util.kt::Formatter::format"' "$MAP_OUT" && ok 'scope: plain class member carries id=Util.kt::Formatter::format' \
    || no "scope: Formatter::format id missing: $( grep -o 'n="format"[^>]*' "$MAP_OUT" )"
grep -q 'id="Util.kt::Extra::helper"' "$MAP_OUT" && ok 'scope: object member carries id=Util.kt::Extra::helper' \
    || no "scope: Extra::helper id missing: $( grep -o 'n="helper"[^>]*' "$MAP_OUT" )"
# Negative: a TOP-LEVEL function must NOT pick up a spurious scope (kotlinEnclosingScopeOf's own
# self-exclusion / walk-through-anonymous-companion logic must not over-fire).
echo "$( grep -o '<s t="fn" n="doubled"[^>]*>' "$MAP_OUT" )" | grep -q 'id=' \
    && no "scope: top-level extension function doubled() got a spurious id= (should be scope-less)" \
    || ok "scope: top-level extension function doubled() is correctly scope-less"

CR="$( "$BIN" "$FIX" --callers=square --no-cache 2>/dev/null )"
echo "$CR" | grep -q 'n="greet"' && ok "--callers=square lists greet (Greeter.kt -> Util.kt, cross-file)" \
    || no "--callers=square did not list greet: $CR"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 2. JVM BRIDGE, Java -> Kotlin (graph.h langCompatible) ==="
# ═══════════════════════════════════════════════════════════════════════════
# callGreeter() is the ONLY cross-language caller each has; runAll() is the same-language caller.
# count=2 (not 1) on each is the proof both edges are live, not just one.
OF_CALLERS="$( "$BIN" "$FIX" --callers="Greeter.kt:of" --no-cache 2>/dev/null )"
echo "$OF_CALLERS" | grep -q 'count="2"' && ok "--callers=Greeter.kt:of -> count=2 (runAll + Java's callGreeter)" \
    || no "--callers=Greeter.kt:of: expected count=2: $( echo "$OF_CALLERS" | grep -o '<callers [^>]*>' )"
# defs="1", not graph_ambiguous= (that attribute is the WHOLE GRAPH's gauge, not this symbol's own —
# it will read "2" here too once §5's collision exists elsewhere in the same file, correctly). `of`
# has exactly one definition — no same-name collision on THIS symbol, unlike helper's.
echo "$OF_CALLERS" | grep -q 'defs="1"' && ok "--callers=Greeter.kt:of -> defs=1 (no same-name collision on this symbol)" \
    || no "--callers=Greeter.kt:of: expected defs=1: $( echo "$OF_CALLERS" | grep -o '<callers [^>]*>' )"

GREET_CALLERS="$( "$BIN" "$FIX" --callers="Greeter.kt:greet" --no-cache 2>/dev/null )"
echo "$GREET_CALLERS" | grep -q 'count="2"' && ok "--callers=Greeter.kt:greet -> count=2 (runAll + Java's callGreeter)" \
    || no "--callers=Greeter.kt:greet: expected count=2: $( echo "$GREET_CALLERS" | grep -o '<callers [^>]*>' )"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 3. JVM BRIDGE, Kotlin -> Java, QUALIFIED, on a name only Java defines (useJavaOnly -> JavaBridge.javaOnly) ==="
# ═══════════════════════════════════════════════════════════════════════════
# The bridge's own job: a Kotlin call into a name its own language does not define. useJavaHelper's `JavaBridge.helper(5)`
# used to stand in for this arm, but `helper` is defined in BOTH languages, so it never isolated the bridge — it measured
# the collision (§5), and with the files split across directories it bound nothing at all (§14a).
JAVAONLY_CALLERS="$( "$BIN" "$FIX" --callers="JavaBridge.java:javaOnly" --no-cache 2>/dev/null )"
echo "$JAVAONLY_CALLERS" | grep -q 'n="useJavaOnly"' && ok "--callers=JavaBridge.java:javaOnly lists useJavaOnly (Kotlin -> Java, qualified)" \
    || no "--callers=JavaBridge.java:javaOnly did not list useJavaOnly: $JAVAONLY_CALLERS"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 4. IMPORTS + CENSUS ==="
# ═══════════════════════════════════════════════════════════════════════════
DEPS="$( "$BIN" "$FIX" --deps --no-cache 2>/dev/null )"
echo "$DEPS" | grep -q '<inc t="com.example.util.square"/>' && ok '--deps: Greeter.kt import captured as t="com.example.util.square" (whole dotted specifier)' \
    || no "--deps: import specifier not captured cleanly: $( echo "$DEPS" | grep -oE '<inc t="[^"]*"' )"
echo "$DEPS" | grep -qE 'dep_langs="[^"]*,kt[,"]' && ok '--deps health: dep_langs= names kt in the disclosed capable set' \
    || no "--deps health: dep_langs= does not list kt: $( echo "$DEPS" | grep -o 'dep_langs="[^"]*"' )"
# NOT ',kt"' alone — that only matches when kt is the LAST token, which is only true because Kotlin is
# currently the last-appended Lang (model.h). This diff's own eliximportcheck.sh fix (`,ex[,"]`) exists
# for the exact same reason: the next language appended after Kotlin would otherwise make THIS assertion
# fail for a reason unrelated to what it tests.

SK="$( "$BIN" "$FIX" --skipped --no-cache 2>/dev/null )"
echo "$SK" | grep -q 'unsupported_ext="0"' && ok '--skipped: unsupported_ext=0 (no .kt/.java falls out of the index)' \
    || no "--skipped: expected unsupported_ext=0: $( echo "$SK" | grep -o 'unsupported_ext="[0-9]*"' )"
echo "$SK" | grep -q '<lang n="kt" files="2" symbols="23"/>' && ok '--skipped: <lang n="kt" files="2" symbols="23"/> census row' \
    || no "--skipped: kotlin census row missing/wrong: $( echo "$SK" | grep -o '<lang n="kt"[^/]*/>' )"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 5. THE COLLISION: a same-name Kotlin/Java pair binds the caller's OWN language — and the trade-off that costs ==="
# ═══════════════════════════════════════════════════════════════════════════
# helper is defined in both languages (Util.kt's Extra.helper, JavaBridge.java's helper). The bridge admits the other JVM
# language only when the caller's own defines no candidate of the name (graph.h keepOwnJvmLanguageCandidates), so BOTH
# Kotlin call sites — the bare ambiguousCall() and the QUALIFIED useJavaHelper()'s `JavaBridge.helper(5)` — bind Kotlin's
# Extra.helper. The qualified one is the disclosed trade-off, pinned so it cannot move silently: Kotlin receivers do not
# narrow candidates yet (ingest_binds.h), so `JavaBridge.` is evidence this resolver cannot read. What this replaced: both
# sites bound BOTH helpers at ambiguous=2 — but only because this fixture is one directory; split across three they
# reached NEITHER, with no amb= and no unresolved= (§14a runs that split layout).
USES_HELPER="$( "$BIN" "$FIX" --uses=helper --no-cache 2>/dev/null )"
echo "$USES_HELPER" | grep -q 'defs="2"' && ok '--uses=helper: defs="2" — both definitions are still indexed (Extra.helper, JavaBridge.helper)' \
    || no "--uses=helper: expected defs=2: $( echo "$USES_HELPER" | grep -o '<uses [^>]*>' )"
UTIL_HELPER_CALLERS="$( "$BIN" "$FIX" --callers="Util.kt:helper" --no-cache 2>/dev/null )"
HELPER_CALLERS="$( "$BIN" "$FIX" --callers="JavaBridge.java:helper" --no-cache 2>/dev/null )"
echo "$UTIL_HELPER_CALLERS" | grep -q 'count="2"' && echo "$UTIL_HELPER_CALLERS" | grep -q 'n="useJavaHelper"' && echo "$UTIL_HELPER_CALLERS" | grep -q 'n="ambiguousCall"' \
    && ok "--callers=Util.kt:helper: count=2 — the bare ambiguousCall AND the qualified useJavaHelper both bind Kotlin's Extra.helper" \
    || no "--callers=Util.kt:helper: expected both Kotlin call sites: $( echo "$UTIL_HELPER_CALLERS" | grep -o '<callers [^>]*>' )"
echo "$HELPER_CALLERS" | grep -q 'count="0"' \
    && ok "--callers=JavaBridge.java:helper: count=0 — no Kotlin site reaches Java's helper while Kotlin defines one (the trade-off)" \
    || no "--callers=JavaBridge.java:helper: expected count=0 — a Kotlin site reached Java's helper although Kotlin defines one: $( echo "$HELPER_CALLERS" | grep -o '<callers [^>]*>' )"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 8. ENUM CLASS BODY: enum_class_body is a DIFFERENT positional child than class_body ==="
# ═══════════════════════════════════════════════════════════════════════════
# Util.kt's `enum class Mode` and JavaBridge.java's package-private `class Mode` are the same shape
# of collision §5 pins for `helper` — a same-name pair with no other evidence, both must stay real
# candidates. The difference is WHERE the bug lived: class_declaration's enum-class form nests its
# members under enum_class_body, not class_body, so the ObjC/Kotlin positional body-fallback missed
# it until a second-opinion review caught the gap. Verified via a raw parse of
# `enum class Status { READY, DONE }`: (class_declaration (type_identifier) (enum_class_body ...)).
USES_MODE="$( "$BIN" "$FIX" --uses=Mode --no-cache 2>/dev/null )"
echo "$USES_MODE" | grep -q 'defs="2"' && ok '--uses=Mode: defs="2" — BOTH candidates are visible (Kotlin enum class, Java class)' \
    || no "--uses=Mode: expected defs=2: $( echo "$USES_MODE" | grep -o '<uses [^>]*>' )"
# What this arm can and cannot see, stated rather than implied: --uses defs= counts every same-named definition BEFORE the
# decl/def collapse, and no call reaches Mode, so "2" would print even if the enum class were collapsed away. The
# graph_ambiguous="2" this section used to pin beside it was helper's collision (§5) — a whole-graph gauge, never Mode's.
# The arm that reads the collapse's OUTPUT for a Kotlin type is §13, through --callees target files.

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 9. CAPTUREBASES: Kotlin delegation_specifier, both shapes (WRAPPED call + DIRECT bare) ==="
# ═══════════════════════════════════════════════════════════════════════════
# No prior fixture had a Kotlin class with a base clause at all, so captureBases's Kotlin arm
# (src/ingest_relations.h) ran with zero test coverage — a copy-paste slip in its isClause/
# isBaseTypeNode tables, or a grammar-shape change on a future tree-sitter-kotlin bump, could have
# silently zeroed out every Kotlin inherit edge with nothing here to notice. `class Square(...) :
# Shape(), Labeled` exercises both shapes in one header: `Shape()` is WRAPPED (delegation_specifier ->
# constructor_invocation -> user_type — and a real CALL too, via tags.scm's own constructor_invocation
# capture, so it carries BOTH role="call" and role="extends" at the same site); `Labeled` is DIRECT
# (bare interface, no call — user_type sits right under delegation_specifier, so it is role="extends"
# only).
#     Assertions grep only the <u .../> rows (not the whole output) — the verb's own legend prose
#     ITSELF contains the literal substrings 'role="call"'/'role="extends"' as worked examples, so a
#     naive whole-output grep would pass vacuously (matching the legend, not the data).
USES_SHAPE="$( "$BIN" "$FIX" --uses=Shape --no-cache 2>/dev/null | grep -o '<u role="[a-z]*"[^/]*/>' )"
echo "$USES_SHAPE" | grep -q 'role="call"' && echo "$USES_SHAPE" | grep -q 'role="extends"' && echo "$USES_SHAPE" | grep -q 'in_id="Square"' \
    && ok '--uses=Shape: Square gets BOTH role="call" and role="extends" at the Shape() delegation site' \
    || no "--uses=Shape: expected both call and extends roles for Square: $USES_SHAPE"

USES_LABELED="$( "$BIN" "$FIX" --uses=Labeled --no-cache 2>/dev/null | grep -o '<u role="[a-z]*"[^/]*/>' )"
echo "$USES_LABELED" | grep -q 'role="extends"' && echo "$USES_LABELED" | grep -q 'in_id="Square"' \
    && ok '--uses=Labeled: Square gets role="extends" (DIRECT — bare interface, no call)' \
    || no "--uses=Labeled: expected role=extends for Square: $USES_LABELED"
echo "$USES_LABELED" | grep -q 'role="call"' \
    && no "--uses=Labeled: got a spurious role=\"call\" — Labeled is never invoked, only implemented" \
    || ok "--uses=Labeled: correctly carries no role=\"call\" (a bare interface is never a call site)"

LEGO_LABELED="$( "$BIN" "$FIX" --lego=Labeled --no-cache 2>/dev/null )"
echo "$LEGO_LABELED" | grep -q 'implementors="1"' && echo "$LEGO_LABELED" | grep -q '<impl n="Square"' \
    && ok '--lego=Labeled: Square is the one implementor' \
    || no "--lego=Labeled: expected Square as the sole implementor: $LEGO_LABELED"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 10. COUNTPARAMS: Kotlin function_value_parameters counts \`parameter\` children only ==="
# ═══════════════════════════════════════════════════════════════════════════
# No prior Kotlin fixture had a function with more than one parameter, so the fix for
# function_value_parameters (src/ingest_metrics.h) — count `parameter` children ONLY, since a
# parameter's own `vararg` modifier and default-value expression are SIBLINGS in this grammar, not
# nested — had nothing pinning it. The generic "every named child" rule would misread these 3 real
# params (name, age, tags) as 5 (the extra siblings: age's `= 0` default-value expression, tags'
# `vararg` modifier).
DESCRIBE_METRICS="$( "$BIN" "$FIX" --metrics --no-cache 2>/dev/null )"
echo "$DESCRIBE_METRICS" | grep -o '<s t="fn" n="describe"[^>]*>' | grep -q 'params="3"' \
    && ok 'describe(name, age = 0, vararg tags): params="3" (not 5 — the sibling modifiers/defaults are correctly excluded)' \
    || no "describe(): expected params=3: $( echo "$DESCRIBE_METRICS" | grep -o '<s t=\"fn\" n=\"describe\"[^>]*>' )"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 11. TRULY BODYLESS: a Kotlin interface with NO braces at all is still a definition ==="
# ═══════════════════════════════════════════════════════════════════════════
# §8's enum-class Mode and §9's Labeled interface both HAVE a body (enum_class_body / class_body) and
# so already exercise ingest_sidecap.h's positional-body fallback. `interface Taggable` (no braces —
# not even an empty `{}`) has NO such child for that fallback to find AT ALL, because Kotlin has no
# forward-declaration syntax for types: this bodyless spelling is the type's sole, complete
# definition, same as `Labeled`/`Mode` are once bodied. Before graph.h's decl/def collapse gained the
# Kotlin-class exception (since read through model.h isDefinitionNotDeclaration; §13 pins the wider shapes), a bodyless
# type read exactly like a forward declaration and was silently deleted whenever a same-name Java
# class existed (JavaBridge.java's Taggable, below) — the same silent-drop shape §5/§8 exist to catch,
# but for a definition that was never going to grow a body-fallback child to find. Found in review,
# not in the original port (a post-PR-review coderabbit finding).
USES_TAGGABLE="$( "$BIN" "$FIX" --uses=Taggable --no-cache 2>/dev/null )"
echo "$USES_TAGGABLE" | grep -q 'defs="2"' \
    && ok '--uses=Taggable: defs="2" — the bodyless Kotlin interface survives alongside the Java class' \
    || no "--uses=Taggable: expected defs=2: $USES_TAGGABLE"
# The graph_ambiguous="2" this section first pinned beside defs= was helper's collision (§5): graph_ambiguous= is the WHOLE
# GRAPH's gauge, not Taggable's own, and Taggable is never called, so it can make nothing ambiguous. §14's own-language
# rule took helper's ambiguity to 0 (the same reason §8 dropped its copy). defs="2" above and mutation 7g pin this pair.

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 6. DETERMINISM: default map thrice, byte-identical ==="
# ═══════════════════════════════════════════════════════════════════════════
# $MAP_OUT (line ~119) is already one run of this exact invocation — reused here as the first of the
# three rather than re-running it, so this gate costs two subprocess runs, not three.
"$BIN" "$FIX" --no-cache >"$TMP/det_b.xml" 2>/dev/null
"$BIN" "$FIX" --no-cache >"$TMP/det_c.xml" 2>/dev/null
diff -q "$MAP_OUT" "$TMP/det_b.xml" >/dev/null && diff -q "$TMP/det_b.xml" "$TMP/det_c.xml" >/dev/null \
    && ok "determinism: default map byte-identical across three runs" \
    || no "determinism: default map differs across runs"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 7. MUTATION: the cross-file and bridge edges move independently ==="
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

# 7a. rename the cross-file call target (greet -> square) — the edge must vanish, proving §1's
#     --callers=square assertion is not a tautology.
mutate
pyedit "$TMP/mut/Greeter.kt" 'val doubled = square(2)' 'val doubled = squareX(2)' \
    && { "$BIN" "$TMP/mut" --no-cache >"$TMP/mut.xml" 2>/dev/null; MUT_RC=$?
         if [ "$MUT_RC" -ne 0 ]; then
             no "mutation 7a: binary exited $MUT_RC on the mutated fixture — absent output means a crash, not proof the edge vanished"
         elif grep -q '<c n="square"/>' "$TMP/mut.xml"; then
             no "mutation: greet -> square edge survived a renamed call site (tautology)"
         else
             ok "mutation: renamed square() call site -> greet -> square edge vanished"
         fi; } \
    || no "mutation 7a: the call-site rename did not apply — the arm would have been inert"

# 7b. rename the Java -> Kotlin bridge call (callGreeter's Greeter.of -> a nonexistent name) — the
#     bridge edge must vanish, proving §2's count="2" assertion is not a tautology.
mutate
pyedit "$TMP/mut/JavaBridge.java" 'Greeter g = Greeter.of("java");' 'Greeter g = Greeter.ofX("java");' \
    && { OF_CALLERS_MUT="$( "$BIN" "$TMP/mut" --callers="Greeter.kt:of" --no-cache 2>/dev/null )"
         echo "$OF_CALLERS_MUT" | grep -q 'count="1"' \
             && ok "mutation: renamed Java -> Kotlin bridge call -> Greeter.kt:of callers drops 2 -> 1" \
             || no "mutation: expected count=1 after renaming the bridge call, got: $( echo "$OF_CALLERS_MUT" | grep -o '<callers [^>]*>' )"; } \
    || no "mutation 7b: the bridge call-site rename did not apply — the arm would have been inert"

# 7c. rename the Kotlin -> Java qualified bridge call (JavaBridge.javaOnly -> a nonexistent name) — the bridge edge must
#     vanish, proving §3's assertion is not a tautology. (This renamed the helper call while helper was §3's target; once
#     the bridge prefers Kotlin, useJavaHelper is never a caller of Java's helper, so that rename would prove nothing.)
mutate
pyedit "$TMP/mut/Greeter.kt" 'fun useJavaOnly(): Int = JavaBridge.javaOnly(3)' 'fun useJavaOnly(): Int = JavaBridge.javaOnlyX(3)' \
    && { JAVAONLY_CALLERS_MUT="$( "$BIN" "$TMP/mut" --callers="JavaBridge.java:javaOnly" --no-cache 2>/dev/null )"; MUT_RC=$?
         if [ "$MUT_RC" -ne 0 ]; then
             no "mutation 7c: binary exited $MUT_RC on the mutated fixture — absent output means a crash, not proof useJavaOnly dropped out"
         elif ! echo "$JAVAONLY_CALLERS_MUT" | grep -q '<callers '; then
             no "mutation 7c: --callers printed no <callers> report on the mutated fixture — nothing was asserted"
         elif echo "$JAVAONLY_CALLERS_MUT" | grep -q 'n="useJavaOnly"'; then
             no "mutation: useJavaOnly survived as a caller of javaOnly() after its call site was renamed (tautology)"
         else
             ok "mutation: renamed Kotlin -> Java qualified call -> useJavaOnly no longer a caller of javaOnly()"
         fi; } \
    || no "mutation 7c: the qualified bridge call-site rename did not apply — the arm would have been inert"

# 7d. rename the Kotlin enum class out of collision (Mode -> ModeKt) — §8's defs="2" must drop to
#     defs="1" (only Java's Mode left), proving that assertion is not a tautology either.
mutate
pyedit "$TMP/mut/Util.kt" 'enum class Mode { ON, OFF }' 'enum class ModeKt { ON, OFF }' \
    && { USES_MODE_MUT="$( "$BIN" "$TMP/mut" --uses=Mode --no-cache 2>/dev/null )"
         echo "$USES_MODE_MUT" | grep -q 'defs="1"' \
             && ok "mutation: renamed Kotlin enum out of collision -> --uses=Mode defs 2 -> 1" \
             || no "mutation 7d: expected defs=1 after removing the Kotlin side of the collision, got: $( echo "$USES_MODE_MUT" | grep -o '<uses [^>]*>' )"; } \
    || no "mutation 7d: the enum class rename did not apply — the arm would have been inert"

# 7e. drop Labeled from Square's base list (`: Shape(), Labeled` -> `: Shape()`) — --uses=Labeled must
#     drop to count="0", proving §9's DIRECT-shape assertion is not a tautology.
mutate
pyedit "$TMP/mut/Util.kt" 'class Square(private val side: Int) : Shape(), Labeled {' 'class Square(private val side: Int) : Shape() {' \
    && { USES_LABELED_MUT="$( "$BIN" "$TMP/mut" --uses=Labeled --no-cache 2>/dev/null )"
         echo "$USES_LABELED_MUT" | grep -q 'count="0"' \
             && ok "mutation: dropped Labeled from Square's base list -> --uses=Labeled count 1 -> 0" \
             || no "mutation 7e: expected count=0 after dropping the DIRECT base, got: $( echo "$USES_LABELED_MUT" | grep -o '<uses [^>]*>' )"; } \
    || no "mutation 7e: the base-list edit did not apply — the arm would have been inert"

# 7f. drop describe()'s vararg parameter — params must fall 3 -> 2, proving §10's countParams
#     assertion tracks real source changes rather than reporting a hardcoded value.
mutate
pyedit "$TMP/mut/Util.kt" 'fun describe(name: String, age: Int = 0, vararg tags: String): String = "$name/$age/${tags.size}"' 'fun describe(name: String, age: Int = 0): String = "$name/$age"' \
    && { DESCRIBE_MUT="$( "$BIN" "$TMP/mut" --metrics --no-cache 2>/dev/null | grep -o '<s t="fn" n="describe"[^>]*>' )"
         echo "$DESCRIBE_MUT" | grep -q 'params="2"' \
             && ok "mutation: dropped describe()'s vararg parameter -> params 3 -> 2" \
             || no "mutation 7f: expected params=2 after dropping the vararg parameter, got: $DESCRIBE_MUT"; } \
    || no "mutation 7f: the parameter-list edit did not apply — the arm would have been inert"

# 7g. rename the bodyless Kotlin interface out of collision (Taggable -> TaggableKt) — §11's defs="2"
#     must drop to defs="1" (only Java's Taggable left), proving that assertion is not a tautology.
mutate
pyedit "$TMP/mut/Util.kt" 'interface Taggable' 'interface TaggableKt' \
    && { USES_TAGGABLE_MUT="$( "$BIN" "$TMP/mut" --uses=Taggable --no-cache 2>/dev/null )"
         echo "$USES_TAGGABLE_MUT" | grep -q 'defs="1"' \
             && ok "mutation: renamed bodyless Kotlin interface out of collision -> --uses=Taggable defs 2 -> 1" \
             || no "mutation 7g: expected defs=1 after removing the Kotlin side of the collision, got: $( echo "$USES_TAGGABLE_MUT" | grep -o '<uses [^>]*>' )"; } \
    || no "mutation 7g: the interface rename did not apply — the arm would have been inert"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 12. HOSTILE NESTING: 600 nested string templates are refused before the parse, never a process abort ==="
# ═══════════════════════════════════════════════════════════════════════════
# tree-sitter-kotlin's external scanner keeps one stack entry per OPEN string, and upstream abort()ed when the next push
# would overrun the 1024-byte serialization buffer: on the first Kotlin binary ONE such file ended the run for its whole
# tree at rc=134 with no output — the map, --skipped, --grep, --match, every verb. Two independent layers now, and this
# section is the runtime arm for the FIRST: ingest's kotlinStringsNestTooDeep prescan (ingest.h
# kMaxKotlinStringNestDepth = 128) refuses the FILE before any parse, names it on stderr (plus DEGRADED_PATH_ALERT on a
# non-NDEBUG build) and rows it in --skipped as why="nest-refused". The SECOND layer, the vendored scanner refusing the
# push instead of aborting, is vendorpatchcheck arm J. The ceiling is pinned from BOTH sides (128 indexed, 129 refused)
# and the siblings must stay indexed, so a guard that refuses the whole tree and a guard that refuses nothing are both red.
NEST="$TMP/nest"; mkdir -p "$NEST"
python3 - "$NEST" <<'PYEOF'
import os, sys
root = sys.argv[1]
def nested(depth):   # `depth` simultaneously-open strings: "a${"a${ … "leaf" … }"}"
    return '"a${' * (depth - 1) + '"leaf"' + '}"' * (depth - 1)
def write(name, fn, depth):
    with open(os.path.join(root, name), "w") as f:
        f.write("package nest\n\nfun %s(): Int = 1\n\nval v_%s = %s\n" % (fn, fn, nested(depth)))
write("Deep.kt", "deepFn", 600)
write("OverCeiling.kt", "overCeilingFn", 129)
write("AtCeiling.kt", "atCeilingFn", 128)
with open(os.path.join(root, "Sibling.kt"), "w") as f:
    f.write('package nest\n\nfun siblingFn(name: String): String = "hi ${name.uppercase()} ${"x${name}"}"\n\nfun callsSibling(): String = siblingFn("k")\n')
PYEOF
nestOpeners(){ grep -o '"a\${' "$1" | wc -l | tr -d ' '; }   # open strings = openers + 1 (the "leaf")
[ "$( nestOpeners "$NEST/Deep.kt" )" = 599 ] && [ "$( nestOpeners "$NEST/OverCeiling.kt" )" = 128 ] && [ "$( nestOpeners "$NEST/AtCeiling.kt" )" = 127 ] \
    && ok "presence: Deep.kt nests 600 open strings, OverCeiling.kt 129, AtCeiling.kt 128" \
    || no "presence: fixture depths are not 600/129/128 — every arm below would assert on the wrong input"

"$BIN" "$NEST" --no-cache >"$TMP/nest.xml" 2>"$TMP/nest.err"; NEST_RC=$?
[ "$NEST_RC" -eq 0 ] && ok "hostile nesting: the map exits 0 (the first Kotlin binary died here at rc=134, the scanner's abort)" \
    || no "hostile nesting: the map exited $NEST_RC — 134 is the scanner's abort(): $( head -3 "$TMP/nest.err" )"
# Every arm below reads the map, so it is evaluated ONLY on a clean exit: a crashed run prints nothing, and "no deepFn in
# an empty file" would otherwise pass for the very defect this section exists to catch.
if [ "$NEST_RC" -eq 0 ]; then
    command -v xmllint >/dev/null 2>&1 && { if xmllint --noout "$TMP/nest.xml" 2>/dev/null; then ok "hostile nesting: the map is well-formed"; else no "hostile nesting: the map fails xmllint"; fi; }
    grep -q 'n="siblingFn"' "$TMP/nest.xml" && grep -q 'n="callsSibling"' "$TMP/nest.xml" \
        && ok "hostile nesting: Sibling.kt stays indexed (siblingFn, callsSibling) — the refusal is per file, not per tree" \
        || no "hostile nesting: Sibling.kt's symbols are missing — the guard took the tree down with the file"
    grep -q 'n="atCeilingFn"' "$TMP/nest.xml" \
        && ok "hostile nesting: AtCeiling.kt (128 open strings) is indexed — the ceiling is inclusive" \
        || no "hostile nesting: AtCeiling.kt (128 deep) was refused — the prescan over-counts at the ceiling"
    grep -q 'n="deepFn"' "$TMP/nest.xml" || grep -q 'n="overCeilingFn"' "$TMP/nest.xml" \
        && no "hostile nesting: Deep.kt or OverCeiling.kt contributed symbols — the prescan did not refuse them before the parse" \
        || ok "hostile nesting: Deep.kt (600) and OverCeiling.kt (129) contribute no symbols — refused before the parse"
    grep -q 'Deep.kt: kotlin string-template nesting > 128 levels' "$TMP/nest.err" && grep -q 'OverCeiling.kt: kotlin string-template nesting > 128 levels' "$TMP/nest.err" \
        && ok "hostile nesting: both refusals are named on stderr (the json/yaml house skip style)" \
        || no "hostile nesting: stderr does not name both refusals: $( head -5 "$TMP/nest.err" )"
    # DEGRADED_PATH_ALERT prints only where NDEBUG is undefined (the plain dev build, the asan build); Release compiles it
    # out. The flavour is read from --version's build-type token, the reading estchargecheck and versioncheck share, so
    # this arm neither goes red on a Release leg nor passes blind on the plain build.
    NEST_FLAVOUR="$( "$BIN" --version 2>/dev/null | sed -nE 's/^[^(]*\(([^,)]*).*/\1/p' )"
    case "$NEST_FLAVOUR" in
        Release|RelWithDebInfo|MinSizeRel)
            ok "hostile nesting: $NEST_FLAVOUR build defines NDEBUG — DEGRADED_PATH_ALERT is compiled out, nothing to assert" ;;
        *)
            grep -q 'math degraded.*kMaxKotlinStringNestDepth' "$TMP/nest.err" \
                && ok "hostile nesting: DEGRADED_PATH_ALERT names the refusal on this '${NEST_FLAVOUR:-unknown}' (non-NDEBUG) build" \
                || no "hostile nesting: '${NEST_FLAVOUR:-unknown}' is a non-NDEBUG build, yet the Kotlin refusal raised no DEGRADED_PATH_ALERT" ;;
    esac
else
    no "hostile nesting: the symbol, stderr and degrade-alert arms were NOT evaluated — the map did not exit 0"
fi

SKN="$( "$BIN" "$NEST" --skipped --no-cache 2>/dev/null )"; SKN_RC=$?
deepBytes="$( wc -c < "$NEST/Deep.kt" | tr -d ' ' )"; overBytes="$( wc -c < "$NEST/OverCeiling.kt" | tr -d ' ' )"
if [ "$SKN_RC" -eq 0 ] && echo "$SKN" | grep -q '<skipped '; then
    ok "--skipped exits 0 over the hostile tree with a <skipped> report"
    echo "$SKN" | grep -q "<f p=\"Deep.kt\" why=\"nest-refused\" bytes=\"$deepBytes\" ext=\".kt\"/>" \
        && ok "--skipped itemizes Deep.kt: why=\"nest-refused\" bytes=\"$deepBytes\" ext=\".kt\"" \
        || no "--skipped has no exact nest-refused row for Deep.kt: $( echo "$SKN" | grep -o '<f p="[^"]*" why="[^"]*"[^/]*/>' | head -5 )"
    echo "$SKN" | grep -q "<f p=\"OverCeiling.kt\" why=\"nest-refused\" bytes=\"$overBytes\" ext=\".kt\"/>" \
        && ok "--skipped itemizes OverCeiling.kt" || no "--skipped has no exact nest-refused row for OverCeiling.kt"
    # why="nest-refused" specifically: AtCeiling.kt is one long whitespace-poor line, so it legitimately earns a
    # minified-suspect <h> health row — an indexed file flagged, which is exactly what it is.
    echo "$SKN" | grep -q 'p="AtCeiling.kt" why="nest-refused"' && no "--skipped rows AtCeiling.kt as nest-refused, but it was indexed" \
        || ok "--skipped does not row AtCeiling.kt as nest-refused (indexed, not refused)"
    echo "$SKN" | grep -q 'nest_refused="2"' && ok '--skipped header: nest_refused="2"' \
        || no "--skipped header: expected nest_refused=\"2\": $( echo "$SKN" | grep -o '<skipped [^>]*>' )"
    echo "$SKN" | grep -q '<!-- nest_refused= counts' && ok "--skipped defines nest_refused= in the legend of the document that carries the rows" \
        || no "--skipped: nest-refused rows with no legend clause defining them"
    "$BIN" "$NEST" --skipped --no-cache 2>/dev/null | cmp -s - <( echo "$SKN" ) && ok "--skipped over the hostile tree: two runs byte-identical" \
        || no "--skipped over the hostile tree differs between two runs"
else
    no "--skipped over the hostile tree exited $SKN_RC or printed no <skipped> report — its row, header and legend arms were NOT evaluated"
fi
SK_CLEAN="$( "$BIN" "$FIX" --skipped --no-cache 2>/dev/null )"
if echo "$SK_CLEAN" | grep -q '<skipped '; then
    echo "$SK_CLEAN" | grep -q 'nest_refused\|nest-refused' \
        && no "--skipped on the clean kotlinfix mentions nest_refused — absent-means-nothing-happened is broken" \
        || ok "--skipped on the clean kotlinfix: no nest_refused attribute, row or legend clause"
else
    no "--skipped on the clean kotlinfix printed no <skipped> report — the absent-when-zero arm would pass on nothing"
fi

# warm: a refused file yields no facts, so it is never cached — a cached re-run must re-read and re-refuse it, not lose it.
"$BIN" "$NEST" --cache="$TMP/nest.cache" >/dev/null 2>&1
if ls "$TMP"/nest.cache* >/dev/null 2>&1; then
    SKW="$( "$BIN" "$NEST" --skipped --cache="$TMP/nest.cache" 2>/dev/null )"
    echo "$SKW" | grep -q 'nest_refused="2"' && echo "$SKW" | grep -q '<f p="Deep.kt" why="nest-refused"' \
        && ok "warm: the cached re-run still refuses and rows both files" \
        || no "warm: the cached re-run lost the refusal: $( echo "$SKW" | grep -o '<skipped [^>]*>' )"
else
    no "warm: presence — the first run wrote no cache under $TMP/nest.cache* (the warm arm would have run cold)"
fi

# multi-root: the row relabels like every other skipped row, and the count sums across roots.
mkdir -p "$TMP/other"; printf 'package other\n\nfun otherFn(): Int = 2\n' > "$TMP/other/Other.kt"
SKM="$( cd "$TMP" && "$BIN" nest other --skipped --no-cache 2>/dev/null )"
echo "$SKM" | grep -q '<f p="nest/Deep.kt" why="nest-refused"' && echo "$SKM" | grep -q 'nest_refused="2"' \
    && ok "multi-root: the refusal row keeps its <label>/<rel> spelling (nest/Deep.kt) and nest_refused merges to 2" \
    || no "multi-root: expected <f p=\"nest/Deep.kt\" why=\"nest-refused\" and nest_refused=\"2\": $( echo "$SKM" | grep -o '<f p="[^"]*" why="nest-refused"[^/]*/>' )"

# multi-root row cap: does a merge put a cut list under rows_capped="0"? Each root caps its own nest-refused rows at
# kMaxSkipRowsPerClass, and mergeCrawlDisclosures concatenates them exactly as it concatenates every sibling row class
# (excluded, unsupported-ext, ignored, ignored-dir): none of them takes a second, workspace-level cut. rows_capped= compares
# the MERGED rows to the merged exact count, so it is absent only when every refused file has its row. Pinned from both sides,
# with unsupported-ext twins in the same roots so this class keeps its siblings' merge shape: two roots of 501 cut the rows
# and say rows_capped="1"; two roots of 300 give 600 rows, past one root's ceiling with none missing, and no rows_capped.
# The real open tag is matched as `<skipped indexed=`, because the legend's own prose spells rows_capped="1".
CAPT="$TMP/nestcap"; mkdir -p "$CAPT"
python3 - "$CAPT" <<'PYEOF'
import os, sys
top = sys.argv[1]
hostile = 'package cap\n\nval v = ' + '"a${' * 128 + '"leaf"' + '}"' * 128 + '\n'   # 129 open strings: refused
for root, n in (("capA", 501), ("capB", 501), ("fullA", 300), ("fullB", 300)):
    d = os.path.join(top, root); os.makedirs(d)
    for k in range(n):
        open(os.path.join(d, "N%04d.kt" % k), "w").write(hostile)
        open(os.path.join(d, "U%04d.xyz" % k), "w").write("x\n")
PYEOF
capTag(){ grep -o '<skipped indexed=[^>]*>' "$1"; }
capRows(){ grep -o "<f p=\"[^\"]*\" why=\"$2\"" "$1" | wc -l | tr -d ' '; }
capAttr(){ capTag "$1" | grep -oE " $2=\"[0-9]*\"" | grep -oE '[0-9]+'; }
( cd "$CAPT" && "$BIN" capA capB --skipped --no-cache >"$TMP/nestcap_over.xml" 2>/dev/null ) \
    && ( cd "$CAPT" && "$BIN" fullA fullB --skipped --no-cache >"$TMP/nestcap_full.xml" 2>/dev/null ); CAP_RC=$?
if [ "$CAP_RC" -eq 0 ] && [ "$( ls "$CAPT/capA" | wc -l | tr -d ' ' )" = 1002 ] && [ "$( ls "$CAPT/fullB" | wc -l | tr -d ' ' )" = 600 ]; then
    oN="$( capRows "$TMP/nestcap_over.xml" nest-refused )"; oU="$( capRows "$TMP/nestcap_over.xml" unsupported-ext )"
    oNC="$( capAttr "$TMP/nestcap_over.xml" nest_refused )"; oUC="$( capAttr "$TMP/nestcap_over.xml" unsupported_ext )"
    [ "${oNC:-}" = 1002 ] && [ "${oUC:-}" = 1002 ] && [ "$oN" -lt 1002 ] && capTag "$TMP/nestcap_over.xml" | grep -q ' rows_capped="1"' \
        && ok "multi-root cap: two roots of 501 -> $oN nest-refused rows beside nest_refused=\"1002\", rows_capped=\"1\" (a disclosed sample)" \
        || no "multi-root cap: two roots of 501 want counts 1002/1002, rows short of them and rows_capped=\"1\"; got rows=$oN/$oU counts=${oNC:-?}/${oUC:-?} tag: $( capTag "$TMP/nestcap_over.xml" | grep -oE 'rows_capped="[0-9]*"' )"
    [ "$oN" = "$oU" ] && ok "multi-root cap: nest-refused merges in its siblings' shape ($oN rows beside unsupported-ext's $oU, same two roots)" \
        || no "multi-root cap: nest-refused rows ($oN) and unsupported-ext rows ($oU) merged differently over the same two roots"
    fN="$( capRows "$TMP/nestcap_full.xml" nest-refused )"; fU="$( capRows "$TMP/nestcap_full.xml" unsupported-ext )"
    [ "$( capAttr "$TMP/nestcap_full.xml" nest_refused )" = 600 ] && [ "$fN" = 600 ] && [ "$fU" = 600 ] && ! capTag "$TMP/nestcap_full.xml" | grep -q 'rows_capped=' \
        && ok "multi-root cap: two roots of 300 -> all 600 rows of each class and no rows_capped (past one root's ceiling, nothing missing)" \
        || no "multi-root cap: two roots of 300 want 600 rows of each class and no rows_capped; got nest=$fN unsupported=$fU tag: $( capTag "$TMP/nestcap_full.xml" | grep -oE '(nest_refused|rows_capped)="[0-9]*"' | tr '\n' ' ' )"
else
    no "multi-root cap: the two --skipped runs (rc=$CAP_RC) or the generated roots (want 1002 and 600 entries) failed — its arms were NOT evaluated"
fi

# Mutation: take ONE level off OverCeiling.kt (129 -> 128). The identical extraction must now index it and the count must
# drop to 1 — so the ceiling arms above track DEPTH, not a file name or a size.
rm -rf "$TMP/nestmut"; cp -R "$NEST" "$TMP/nestmut"
python3 - "$TMP/nestmut/OverCeiling.kt" <<'PYEOF'
import sys
p = sys.argv[1]; s = open(p).read()
t = s.replace('"a${', '', 1).replace('}"', '', 1)
if t == s:
    sys.exit("mutation target not present")
open(p, "w").write(t)
PYEOF
if [ "$( nestOpeners "$TMP/nestmut/OverCeiling.kt" )" = 127 ]; then
    "$BIN" "$TMP/nestmut" --no-cache >"$TMP/nestmut.xml" 2>/dev/null
    SKMUT="$( "$BIN" "$TMP/nestmut" --skipped --no-cache 2>/dev/null )"
    grep -q 'n="overCeilingFn"' "$TMP/nestmut.xml" && echo "$SKMUT" | grep -q 'nest_refused="1"' \
        && ok "mutation: one level off OverCeiling.kt (129 -> 128) -> indexed, nest_refused 2 -> 1" \
        || no "mutation: 128-deep OverCeiling.kt is still refused, or the count did not move: $( echo "$SKMUT" | grep -o '<skipped [^>]*>' )"
else
    no "mutation 12: OverCeiling.kt did not lose exactly one level — the arm would have been inert"
fi

# ESCAPES: the prescan must count what the VENDORED scanner holds, escape by escape, not what Kotlin means. Two readings of
# scan_string_content's `\$` branch, each pinned from the side that would break it. (a) `"\$${ … }"` is ONE open string at a
# time: after `\$` and a byte that is not a quote the loop falls through to its bottom advance, so the scanner consumes three
# bytes and `{ … }` is string content — a prescan resuming at the second `$` would count 200 levels and refuse a file the
# scanner parses one string deep. (b) `"""\$"${ … }"""` is one string PER LEVEL: vendored patch 002 leaves the quote after
# `\$` to the triple-quote close test, and the prescan used to close the string at that quote instead (upstream's unpatched
# reading), fall back into code and never count past one — so 129 levels, plain or `$$`-prefixed, went to the parse. The
# ceiling is pinned inclusive here too (128 levels indexed). Each file stands alone in its own tree, so the counts above
# stay exactly the section's.
NESC="$TMP/nestesc"; mkdir -p "$NESC"
python3 - "$NESC" <<'PYEOF'
import os, sys
root, B = sys.argv[1], '\\'
def write(name, fn, depth, opener, closer, leaf):   # `depth` levels as the scanner reads them: opener^(depth-1) leaf closer^(depth-1)
    with open(os.path.join(root, name), "w") as f:
        f.write("package nestesc\n\nfun %s(): Int = 1\n\nval v_%s = %s\n" % (fn, fn, opener * (depth - 1) + leaf + closer * (depth - 1)))
write("TripleEscape.kt",       "tripleEscapeFn",   129, '"""' + B + '$"${',    '}"""', '"""leaf"""')
write("TripleEscapeAt.kt",     "tripleEscapeAtFn", 128, '"""' + B + '$"${',    '}"""', '"""leaf"""')
write("DollarTripleEscape.kt", "dollarTripleFn",   129, '$$"""' + B + '$"$${', '}"""', '"""leaf"""')
write("EscapedDollarRun.kt",   "escapedDollarFn",  200, '"' + B + '$${',       '}"',   '"leaf"')
PYEOF
[ "$( grep -oF '"""\$"${' "$NESC/TripleEscape.kt" | wc -l | tr -d ' ' )" = 128 ] && [ "$( grep -oF '"""\$"${' "$NESC/TripleEscapeAt.kt" | wc -l | tr -d ' ' )" = 127 ] \
    && [ "$( grep -oF '$$"""\$"$${' "$NESC/DollarTripleEscape.kt" | wc -l | tr -d ' ' )" = 128 ] && [ "$( grep -oF '"\$${' "$NESC/EscapedDollarRun.kt" | wc -l | tr -d ' ' )" = 199 ] \
    && ok "escapes presence: TripleEscape.kt 129 levels, TripleEscapeAt.kt 128, DollarTripleEscape.kt 129, EscapedDollarRun.kt 200" \
    || no "escapes presence: the escape fixtures do not spell the depths the arms below assert"
grep -qF 'RIPWIRE_VENDOR_PATCH(kotlin/002-triple-dollar-escape)' "$ROOT/third_party/deps/kotlin/src/scanner.c" \
    && ok "escapes presence: the vendored scanner still carries patch 002, the scanner reading (b) mirrors" \
    || no "escapes presence: patch 002 is gone from the vendored scanner — reading (b) no longer describes it; re-derive the arm"
"$BIN" "$NESC" --no-cache >"$TMP/nestesc.xml" 2>/dev/null; NESC_RC=$?
SKE="$( "$BIN" "$NESC" --skipped --no-cache 2>/dev/null )"; SKE_RC=$?
if [ "$NESC_RC" -eq 0 ] && [ "$SKE_RC" -eq 0 ] && echo "$SKE" | grep -q '<skipped '; then
    echo "$SKE" | grep -q '<f p="TripleEscape.kt" why="nest-refused"' && echo "$SKE" | grep -q '<f p="DollarTripleEscape.kt" why="nest-refused"' \
        && ok "escapes (b): 129 levels of \"\"\"\\\$\"\${ … }\"\"\" are refused, plain and \$\$-prefixed — the prescan follows patch 002's triple-quote close" \
        || no "escapes (b): TripleEscape.kt / DollarTripleEscape.kt hold 129 open strings in the scanner but were not refused: $( echo "$SKE" | grep -o '<f p="[^"]*" why="nest-refused"' | tr '\n' ' ' )"
    grep -q 'n="tripleEscapeFn"' "$TMP/nestesc.xml" || grep -q 'n="dollarTripleFn"' "$TMP/nestesc.xml" \
        && no "escapes (b): a 129-level triple-quoted escape file contributed symbols — it reached the parse" \
        || ok "escapes (b): neither 129-level triple-quoted escape file contributed a symbol"
    grep -q 'n="tripleEscapeAtFn"' "$TMP/nestesc.xml" && ! echo "$SKE" | grep -q 'p="TripleEscapeAt.kt" why="nest-refused"' \
        && ok "escapes (b): 128 levels of the same shape are indexed — the ceiling stays inclusive" \
        || no "escapes (b): TripleEscapeAt.kt (128 levels) was refused — the prescan over-counts the triple-quoted escape"
    grep -q 'n="escapedDollarFn"' "$TMP/nestesc.xml" && ! echo "$SKE" | grep -q 'p="EscapedDollarRun.kt" why="nest-refused"' \
        && ok "escapes (a): 200 levels of \"\\\$\${ … }\" stay indexed — the scanner reads \\\$\$ as three bytes and holds one string" \
        || no "escapes (a): EscapedDollarRun.kt was refused — the prescan counted Kotlin's nesting, not the scanner's"
    echo "$SKE" | grep -q 'nest_refused="2"' && ok 'escapes: nest_refused="2" over the escape tree' \
        || no "escapes: expected nest_refused=\"2\": $( echo "$SKE" | grep -o '<skipped [^>]*>' )"
else
    no "escapes: the map (rc=$NESC_RC) or --skipped (rc=$SKE_RC) over the escape tree failed — its arms were NOT evaluated"
fi

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 13. BODYLESS KOTLIN TYPES ARE DEFINITIONS, and the decl/def collapse never crosses the Kotlin/Java line ==="
# ═══════════════════════════════════════════════════════════════════════════
# graph.h's decl/def collapse deletes a name's bodyless rows whenever one bodied row exists, reading a bodyless row as the
# prototype of that body. Kotlin has no forward declarations, so `data class User(val name: String)`, `class Token` and
# `interface Marker` are complete definitions that own no class_body — and on the first Kotlin binary each was deleted
# the moment a same-named Java type existed ANYWHERE: makeUser's `User("a")` bound java/User.java at ambiguous=0, and
# --lego=Models.kt:Marker answered with the Java interface (split tree) or with no implementor at all (flat tree). PR #126's
# own Kotlin-class clause (§11) closed that half before this section merged, so those arms are pins. The
# collapse also ran ACROSS the language line: Kotlin's KPong.pong() body evicted Java's interface-only JSvc.pong()
# declaration, so a Java call sitting in the declaration's own file bound Kotlin code. What must NOT change is the one
# bodyless shape that really is a declaration: a Kotlin interface member still collapses into its Kotlin override.
# Every arm reads the bound TARGET (--callees p=, --lego's <iface p=>). Not --uses defs=, which counts every same-named
# symbol before the collapse and reads 2 with or without the bug, and not a --callers selector, which widens a bodyless
# selection to same-scope bodies and lists the Java caller under both Users. The layout control runs every arm in a split
# tree (kt/ beside zjava/, named so the Kotlin files sort first — see the interface arm) and a flat one: the collapse is
# layout-blind, so a fix that only holds when the tier ladder happens to prefer a directory fails one of the two.
BL="$TMP/bodyless"; mkdir -p "$BL/split/kt" "$BL/split/zjava" "$BL/flat"
cat > "$BL/split/kt/Models.kt" <<'KT'
package com.example.kt

data class User(val name: String)

class Token

interface Marker

object Empty

fun makeUser(): User = User("a")

fun makeToken(): Token = Token()

class Tagged : Marker
KT
cat > "$BL/split/kt/Pinger.kt" <<'KT'
package com.example.kt

interface Pinger {
    fun ping(): String
}
KT
cat > "$BL/split/kt/KPinger.kt" <<'KT'
package com.example.kt

class KPinger : Pinger {
    override fun ping(): String = "k"
}

fun usePinger(p: Pinger): String = p.ping()
KT
cat > "$BL/split/kt/Pong.kt" <<'KT'
package com.example.kt

class KPong {
    fun pong(): String = "kp"
}
KT
cat > "$BL/split/zjava/User.java" <<'JAVA'
package com.example.java;

public class User {
    private String name;
    public String getName() { return name; }
}

class Token {
    void spin() { }
}

interface Marker {
    void mark();
}

class Empty {
    void nothing() { }
}
JAVA
cat > "$BL/split/zjava/JSvc.java" <<'JAVA'
package com.example.java;

interface JSvc {
    String pong();
}

class JCaller {
    String call(JSvc s) { return s.pong(); }
}
JAVA
cp "$BL"/split/kt/*.kt "$BL"/split/zjava/*.java "$BL/flat/"
# calleeFiles ROOT CALLER CALLEE — the file(s) CALLER's call to CALLEE is bound to, as --callees reports them (p=, no :line)
calleeFiles(){ "$BIN" "$1" --callees="$2" --no-cache 2>/dev/null | grep -o "<s t=\"[a-z]*\" n=\"$3\" p=\"[^\"]*\"" | sed -E 's/.* p="([^":]*).*/\1/' | sort -u | tr '\n' ' ' | sed 's/ $//'; }
for L in split flat; do
    if [ "$L" = split ]; then K="kt/"; J="zjava/"; else K=""; J=""; fi
    [ -f "$BL/$L/${K}Models.kt" ] && [ -f "$BL/$L/${J}User.java" ] && grep -q '^data class User(val name: String)$' "$BL/$L/${K}Models.kt" \
        && ok "$L: presence — a bodyless Kotlin data class, class and interface beside same-named Java types" \
        || no "$L: presence — the bodyless-type fixture is missing or no longer spells a bodyless data class"
    got="$( calleeFiles "$BL/$L" Models.kt:makeUser User )"
    [ "$got" = "${K}Models.kt" ] && ok "$L: makeUser's User(\"a\") binds the bodyless Kotlin data class, not java User" \
        || no "$L: makeUser's User(\"a\") binds [${got:-nothing}], expected ${K}Models.kt — the Kotlin type was collapsed as a declaration"
    got="$( calleeFiles "$BL/$L" Models.kt:makeToken Token )"
    [ "$got" = "${K}Models.kt" ] && ok "$L: makeToken's Token() binds the bodyless Kotlin class, not java Token" \
        || no "$L: makeToken's Token() binds [${got:-nothing}], expected ${K}Models.kt"
    # The interface arm reads --lego, the one verb that reports which base an `extends` bound, and --lego answers with the
    # LOWEST-id definition of a name: the Kotlin grammar tags `interface` as a class, so lego's interface selector cannot
    # address it by file and falls back to the name. kt/ sorts before zjava/ (and Models.kt before User.java), so the Kotlin
    # interface IS the lowest id in both trees — asserted FIRST, so a reordered fixture fails loudly instead of quietly
    # reading the Java interface. Implementors of that definition are the read: collapsed as a declaration, it had none.
    LEGO="$( "$BIN" "$BL/$L" --lego=Marker --no-cache 2>/dev/null )"
    if echo "$LEGO" | grep -q "<iface n=\"Marker\" p=\"${K}Models.kt\""; then
        echo "$LEGO" | grep -q "<impl n=\"Tagged\" p=\"${K}Models.kt\"" \
            && ok "$L: the bodyless Kotlin interface Marker survives the collapse, and Tagged implements it" \
            || no "$L: the bodyless Kotlin interface Marker has no Tagged implementor — it was collapsed as a declaration: $( echo "$LEGO" | grep -oE '<(iface|impl) [^>]*>' | tr '\n' ' ' )"
    else
        no "$L: presence — --lego=Marker no longer answers with the Kotlin interface (${K}Models.kt), so the implementor arm would read the Java one: $( echo "$LEGO" | grep -oE '<iface [^>]*>' )"
    fi
    got="$( calleeFiles "$BL/$L" JSvc.java:call pong )"
    [ "$got" = "${J}JSvc.java" ] && ok "$L: Java's s.pong() keeps its own interface declaration — Kotlin's KPong.pong body does not evict it" \
        || no "$L: Java's s.pong() binds [${got:-nothing}], expected ${J}JSvc.java — the collapse crossed the Kotlin/Java line"
    got="$( calleeFiles "$BL/$L" KPinger.kt:usePinger ping )"
    [ "$got" = "${K}KPinger.kt" ] && ok "$L: a bodyless Kotlin FUNCTION is still a declaration — p.ping() binds KPinger's override, not Pinger's member" \
        || no "$L: p.ping() binds [${got:-nothing}], expected ${K}KPinger.kt — the interface member stopped collapsing into its Kotlin body"
done

# Mutation: delete the Kotlin data class. With no Kotlin User left, the same extraction must bind makeUser's call to
# zjava/User.java — the JVM bridge doing exactly its job — so the arm above tracks the Kotlin row, not a pinned file name.
rm -rf "$BL/mut"; cp -R "$BL/split" "$BL/mut"
pyedit "$BL/mut/kt/Models.kt" 'data class User(val name: String)' '// data class User removed by mutation 13' \
    && { got="$( calleeFiles "$BL/mut" Models.kt:makeUser User )"
         [ "$got" = "zjava/User.java" ] && ok "mutation: Kotlin User deleted -> makeUser's User(\"a\") binds zjava/User.java (the bridge, once Kotlin has none)" \
             || no "mutation 13: expected zjava/User.java once the Kotlin User is gone, got [${got:-nothing}]"; } \
    || no "mutation 13: the data-class deletion did not apply — the arm would have been inert"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== 14. JVM BRIDGE, OWN LANGUAGE FIRST: Kotlin files never move a Java edge, in any directory layout ==="
# ═══════════════════════════════════════════════════════════════════════════
# langCompatible admits a Kotlin/Java pair by bare NAME, and the tier ladder DROPS a bare call whose candidates sit in two
# or more directories other than the caller's — no edge, no amb=, no unresolved=. So the first bridge deleted Java edges
# wherever an unrelated same-named Kotlin definition existed: on square/retrofit the test-only Kotlin body() functions (five
# spelled in two test directories, three with bodies) took Response.java's body from 279 callers to 5. §5's "honestly ambiguous" helper collision only ever held because
# test/kotlinfix is ONE directory; split across three, the same two calls reached neither helper. The rule now (graph.h
# keepOwnJvmLanguageCandidates): a Java or Kotlin reference reaches the other JVM language only when its own offers no
# candidate of that name — for call edges, and for base classes in the inheritance overlay.
callersCount(){ "$BIN" "$1" --callers="$2" --no-cache 2>/dev/null | grep -o '<callers [^>]*>' | grep -o 'count="[0-9]*"' | head -1; }
callerRows(){ "$BIN" "$1" --callers="$2" --no-cache 2>/dev/null | grep -oE '<s t="[a-z]*" n="[^"]*" p="[^"]*"' | LC_ALL=C sort | tr '\n' ' '; }

# 14a. test/kotlinfix split across three directories must give the flat layout's answers.
SPLIT="$TMP/kotlinsplit"; mkdir -p "$SPLIT/a" "$SPLIT/b" "$SPLIT/c"
cp "$FIX/Util.kt" "$SPLIT/a/"; cp "$FIX/Greeter.kt" "$SPLIT/b/"; cp "$FIX/JavaBridge.java" "$SPLIT/c/"
for L in flat split; do
    ROOTL="$FIX"; [ "$L" = split ] && ROOTL="$SPLIT"
    [ "$( callersCount "$ROOTL" Greeter.kt:of )" = 'count="2"' ] && [ "$( callersCount "$ROOTL" Greeter.kt:greet )" = 'count="2"' ] \
        && ok "$L: Java -> Kotlin — Greeter.of and greet each keep both callers (runAll, and Java's callGreeter)" \
        || no "$L: Java -> Kotlin bridge lost a caller: of $( callersCount "$ROOTL" Greeter.kt:of ), greet $( callersCount "$ROOTL" Greeter.kt:greet )"
    callerRows "$ROOTL" JavaBridge.java:javaOnly | grep -q 'n="useJavaOnly"' \
        && ok "$L: Kotlin -> Java — useJavaOnly reaches JavaBridge.javaOnly, a name only Java defines" \
        || no "$L: Kotlin -> Java — useJavaOnly does not reach JavaBridge.javaOnly"
    [ "$( callersCount "$ROOTL" Util.kt:helper )" = 'count="2"' ] && [ "$( callersCount "$ROOTL" JavaBridge.java:helper )" = 'count="0"' ] \
        && ok "$L: both Kotlin helper(5) calls bind Kotlin's Extra.helper and none reaches Java's (own language first)" \
        || no "$L: helper — Util.kt:helper $( callersCount "$ROOTL" Util.kt:helper ), JavaBridge.java:helper $( callersCount "$ROOTL" JavaBridge.java:helper ); expected count=2 and count=0"
done

# 14b. Response.body beside an unrelated Kotlin body() in another directory. The Java callers must equal the same tree's
#      callers with the .kt files removed — computed, not pinned — and that baseline must really hold both callers.
RB="$TMP/respbody"; mkdir -p "$RB/lib/src/main/java/r" "$RB/lib/src/test/java/r" "$RB/kt/src/test/java/r"
cat > "$RB/lib/src/main/java/r/Response.java" <<'JAVA'
package r;

public final class Response<T> {
    private final T body;
    Response(T body) { this.body = body; }
    public T body() { return body; }
    public int code() { return 200; }
}
JAVA
cat > "$RB/lib/src/test/java/r/CallTest.java" <<'JAVA'
package r;

public class CallTest {
    public void bodySuccess() {
        Response<String> response = new Response<>("x");
        String b = response.body();
    }
    public void bodyFailure() {
        Response<String> response = new Response<>(null);
        Object o = response.body();
    }
}
JAVA
cat > "$RB/kt/src/test/java/r/KotlinTest.kt" <<'KT'
package r

class KotlinTest {
    fun body() {
        val x = 1
    }
}
KT
cat > "$RB/kt/src/test/java/r/Service.kt" <<'KT'
package r

interface Service {
    suspend fun body(): String
}
KT
rm -rf "$TMP/respbody_nokt"; cp -R "$RB" "$TMP/respbody_nokt"; rm -rf "$TMP/respbody_nokt/kt"
withKt="$( callerRows "$RB" Response.java:body )"; noKt="$( callerRows "$TMP/respbody_nokt" Response.java:body )"
if echo "$noKt" | grep -q 'n="bodySuccess"' && echo "$noKt" | grep -q 'n="bodyFailure"'; then
    [ "$withKt" = "$noKt" ] && ok "Response.body keeps exactly its Java-only callers with an unrelated Kotlin body() two directories away" \
        || no "Response.body's callers moved when .kt files were added — without: [$noKt] with: [${withKt:-none}]"
else
    no "presence: without the .kt files Response.body has no bodySuccess/bodyFailure callers — the comparison would be empty against empty"
fi
# Mutation: rename Java's body() DEFINITION only; the calls stay body(). Java now defines no candidate of that name, so the
# identical extraction must bridge both calls to Kotlin's KotlinTest.body — the filter defers to its own language only when
# that language has a candidate; it does not switch the bridge off.
rm -rf "$TMP/respbody_mut"; cp -R "$RB" "$TMP/respbody_mut"
pyedit "$TMP/respbody_mut/lib/src/main/java/r/Response.java" 'public T body() { return body; }' 'public T bodyJ() { return body; }' \
    && { rows="$( callerRows "$TMP/respbody_mut" KotlinTest.kt:body )"
         echo "$rows" | grep -q 'n="bodySuccess"' && echo "$rows" | grep -q 'n="bodyFailure"' \
             && ok "mutation: Java's body() definition renamed -> both Java calls bridge to Kotlin's KotlinTest.body" \
             || no "mutation 14b: with no Java body left, the Java calls did not bridge to KotlinTest.body: [${rows:-none}]"; } \
    || no "mutation 14b: the Response.body rename did not apply — the arm would have been inert"

# 14c. THE INVARIANT, over several shapes at once: a Java-only tree, then the same tree plus a k/ directory of Kotlin
#      definitions spelling the SAME names (bodied and bodyless types, a free function, a class hierarchy, an interface
#      with an implementor). For six Java definitions the --callers rows, and the Java interface's --lego implementors,
#      must be exactly what the Java-only tree produced, and every Java symbol's call edges, prov= and amb= in the full
#      map must be unchanged. The shapes: a unique cross-directory global reached through a typed receiver
#      (Response.body/code), an interface-only declaration (Svc.pong), a same-file inherited call (Base.run), a Java-Java
#      collision the ladder already drops (dup, defined in two other directories — it must STAY dropped, not turn into a
#      Kotlin edge), and an interface implemented from the other language (Marker).
INV="$TMP/jvminv"; rm -rf "$INV"; mkdir -p "$INV/a" "$INV/b" "$INV/c" "$INV/d" "$INV/e"
cat > "$INV/a/Response.java" <<'JAVA'
package a;

public class Response {
    public String body() { return "b"; }
    public int code() { return 1; }
}
JAVA
cat > "$INV/b/Caller.java" <<'JAVA'
package b;

class Caller {
    String go(a.Response r) {
        r.code();
        return r.body();
    }
    int twice() { return dup() + dup(); }
}
JAVA
cat > "$INV/c/Svc.java" <<'JAVA'
package c;

interface Svc {
    String pong();
}

interface Marker {
    void mark();
}

class SvcUser implements Marker {
    String use(Svc s) { return s.pong(); }
    public void mark() { }
}
JAVA
cat > "$INV/d/Base.java" <<'JAVA'
package d;

class Base {
    void run() { }
    static int dup() { return 1; }
}

class Derived extends Base {
    void go() { run(); }
}
JAVA
cat > "$INV/e/Dup.java" <<'JAVA'
package e;

class Dup {
    static int dup() { return 2; }
}
JAVA
rm -rf "$TMP/jvminv_kt"; cp -R "$INV" "$TMP/jvminv_kt"; mkdir -p "$TMP/jvminv_kt/k"
cat > "$TMP/jvminv_kt/k/Kt.kt" <<'KT'
package k

class Response {
    fun body(): String = "k"
    fun code(): Int = 2
}

interface Svc {
    fun pong(): String
}

class KPong {
    fun pong(): String = "kp"
}

open class Base {
    open fun run() { }
}

fun dup(): Int = 3

interface Marker

class Tagged : Marker
KT
markerImpls(){ "$BIN" "$1" --lego=Svc.java:Marker --no-cache 2>/dev/null | grep -oE '<impl [^>]*>' | LC_ALL=C sort | tr '\n' ' '; }
if [ -n "$( callerRows "$INV" Response.java:body )" ] && [ -n "$( callerRows "$INV" Svc.java:pong )" ] \
   && [ -n "$( callerRows "$INV" Base.java:run )" ] && [ -n "$( markerImpls "$INV" )" ]; then
    invDiff=""
    for target in Response.java:body Response.java:code Svc.java:pong Base.java:run Base.java:dup Dup.java:dup; do
        [ "$( callerRows "$INV" "$target" )" = "$( callerRows "$TMP/jvminv_kt" "$target" )" ] || invDiff="$invDiff $target"
    done
    [ "$( markerImpls "$INV" )" = "$( markerImpls "$TMP/jvminv_kt" )" ] || invDiff="$invDiff lego:Marker"
    "$BIN" "$INV" --top-k=100000 --no-cache > "$TMP/inv_j.xml" 2>/dev/null
    "$BIN" "$TMP/jvminv_kt" --top-k=100000 --no-cache > "$TMP/inv_jk.xml" 2>/dev/null
    read -r javaRows javaMoved <<< "$( python3 - "$TMP/inv_j.xml" "$TMP/inv_jk.xml" <<'PYEOF'
import sys, xml.etree.ElementTree as ET
def java_rows(path):
    raw = open(path, encoding="utf-8", errors="replace").read()
    root = ET.fromstring(raw[raw.find("<r "):])
    rows = set()
    for f in root.iter("f"):
        if not f.get("p", "").endswith(".java"):
            continue
        for s in f.iter("s"):
            key = (f.get("p"), s.get("t"), s.get("n"), s.get("id") or "")
            rows.add(key + ("amb", s.get("amb") or ""))
            for c in s.iter("c"):
                rows.add(key + ("c", c.get("n"), c.get("prov") or ""))
    return rows
a, b = java_rows(sys.argv[1]), java_rows(sys.argv[2])
print(len(a), len(a ^ b))
PYEOF
)"
    [ "${javaRows:-0}" -gt 0 ] && [ "${javaMoved:-x}" = 0 ] || invDiff="$invDiff map(${javaMoved:-?} of ${javaRows:-?} Java rows)"
    [ -z "$invDiff" ] && ok "invariant: adding k/Kt.kt moved NO Java edge — --callers of 6 Java definitions, the Java Marker's implementors, and $javaRows Java map rows (edges, prov=, amb=) are identical" \
        || no "invariant: adding k/Kt.kt moved Java edges at:$invDiff"
else
    no "invariant presence: the Java-only tree has no callers for body/pong/run, or no Marker implementor — the comparison would be empty against empty"
fi
# Mutation: delete the Kotlin interface Marker. Kotlin now defines no Marker, so the identical extraction must hand Tagged to
# the Java interface — the inheritance overlay, like the call filter, defers to its own language only when it has a candidate.
rm -rf "$TMP/jvminv_mut"; cp -R "$TMP/jvminv_kt" "$TMP/jvminv_mut"
pyedit "$TMP/jvminv_mut/k/Kt.kt" 'interface Marker' '// interface Marker removed by mutation 14c' \
    && { markerImpls "$TMP/jvminv_mut" | grep -q '<impl n="Tagged"' \
             && ok "mutation: Kotlin Marker deleted -> Tagged implements the Java Marker (the bridge, once Kotlin has none)" \
             || no "mutation 14c: with no Kotlin Marker, Tagged did not become the Java Marker's implementor: [$( markerImpls "$TMP/jvminv_mut" )]"; } \
    || no "mutation 14c: the Marker deletion did not apply — the arm would have been inert"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
