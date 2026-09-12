#!/usr/bin/env bash
# lintrulescheck.sh — Wave 4 #2 gate: user-extensible lint rules (--lint-rules=DIR, ast-grep style).
# Asserts, on test/lintrulesfix/:
#   1. determinism — --lint-rules run twice is byte-identical (the sort/load-order contract)
#   2. the GOOD rule fires with rule=/sev=/message honored on the fixture printf() call
#   3. a rule with a BAD tree-sitter query alerts + is skipped WITHOUT killing the run (exit 0)
#   4. a MALFORMED yaml file alerts (file+line) + is skipped WITHOUT killing the run (exit 0)
#   5. xmllint-clean output
#   6. built-ins STILL fire when --lint is given alongside --lint-rules
#   7. exit 1 (with a clear message) when the flag is given but zero rules load
#   8. PHASE-2 combinators (inside / not-inside / not-matches) — pure span algebra over the SAME
#      astQuery engine. On test/lintrulesfix/combinators/ each combinator has a POSITIVE case (a hit
#      kept) and a NEGATIVE case (a hit filtered), asserted by BOTH the finding count and the exact
#      line the surviving hit lands on. Plus: repeated `inside` keys AND-combine; a malformed
#      combinator block (empty '|') alerts + skips the file whole; combinators are deterministic.
# Does NOT edit test/regression.sh (the orchestrator wires it).
#
#   RIPWIRE_BIN=build/ripwire bash test/lintrulescheck.sh
#   RIPWIRE_BIN=asan/ripwire  bash test/lintrulescheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
CORPUS="$ROOT/test/lintrulesfix"
RULES="$CORPUS/rules"
LINTFIX="$ROOT/test/lintfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ]    || { echo "no ripwire binary at $BIN — build first"; exit 2; }
[ -d "$CORPUS" ] || { echo "no test/lintrulesfix dir — fixture missing"; exit 2; }
[ -d "$RULES" ]  || { echo "no test/lintrulesfix/rules dir — fixture missing"; exit 2; }

echo "lintrulescheck: BIN=$BIN  CORPUS=$CORPUS"

# 1. determinism — run twice, byte-identical (stderr suppressed; alerts are non-deterministic in TIMING only)
"$BIN" "$CORPUS" --lint-rules="$RULES" --no-cache >"$TMP/out1" 2>/dev/null
"$BIN" "$CORPUS" --lint-rules="$RULES" --no-cache >"$TMP/out2" 2>/dev/null
diff -q "$TMP/out1" "$TMP/out2" >/dev/null && ok "deterministic (byte-identical run-to-run)" \
    || { no "non-deterministic output"; diff "$TMP/out1" "$TMP/out2" | head -8; }

OUT="$TMP/out1"

# 2. the good rule fires with its id, severity, and message honored
if grep -q 'rule="no-printf"' "$OUT"; then ok "good rule fires (rule=\"no-printf\")"; else no "good rule no-printf NOT found"; fi
if grep -q 'sev="warn"'       "$OUT"; then ok "severity honored (sev=\"warn\")"; else no "sev=\"warn\" NOT emitted"; fi
if grep -q 'use LOG() instead of printf' "$OUT"; then ok "message honored (element text)"; else no "rule message NOT emitted"; fi
# it must fire on the printf call site (sample.cpp), inside the enclosing fn
if grep -q 'rule="no-printf"[^>]*p="[^"]*sample.cpp' "$OUT"; then ok "good rule located at the fixture printf"; else no "good rule not located at sample.cpp"; fi
# exactly one finding for the good rule (the @hit/@fn two-capture collapse worked — not two)
CNT="$( grep -o 'rule="no-printf"' "$OUT" | wc -l | tr -d ' ' )"
if [ "$CNT" = "1" ]; then ok "single finding per match (capture collapse: got 1)"; else no "expected 1 no-printf finding, got $CNT"; fi

# 3 + 4. bad query and malformed yaml alert + skip, but the run still exits 0
"$BIN" "$CORPUS" --lint-rules="$RULES" --no-cache >/dev/null 2>"$TMP/err"; rc=$?
if [ "$rc" -eq 0 ]; then ok "--lint-rules exits 0 despite a bad query + a malformed file"; else no "--lint-rules exit $rc (expected 0)"; fi
if grep -qi 'did not compile' "$TMP/err"; then ok "bad tree-sitter query alerted (astQuery)"; else no "no alert for the bad query"; fi
if grep -qi 'malformed.yaml'  "$TMP/err"; then ok "malformed yaml file alerted (file named)"; else no "no alert naming the malformed file"; fi
if grep -Eq 'malformed.yaml:[0-9]+' "$TMP/err"; then ok "malformed alert names a line number"; else no "malformed alert has no line number"; fi
# broken-query / bad-shape must NOT have produced findings
grep -q 'rule="broken-query"' <(grep '<f ' "$OUT") && no "broken-query wrongly produced a finding" || ok "bad query produced no findings (skipped)"
grep -q 'rule="bad-shape"'    "$OUT"               && no "malformed file's rule wrongly loaded"      || ok "malformed file skipped whole (bad-shape absent)"

# §L10: a compile-FAILED query's tally row must not read like a well-formed query that legitimately found
# nothing — before this fix count="0" was the ONLY signal, indistinguishable from no-printf run on a tree
# with no printf() call, with the compile failure disclosed on stderr alone. compiled="0" makes it part of
# the row a machine reader of stdout actually sees; the well-formed rows must NOT carry it.
BROKEN_ROW="$( grep -o '<rule name="broken-query"[^/]*/>' "$OUT" )"
printf '%s' "$BROKEN_ROW" | grep -q 'compiled="0"' \
    && ok "L10: broken-query's tally row carries compiled=\"0\" (count=\"0\" is now distinguishable from a real zero)" \
    || { no "L10: broken-query's tally row has no compiled=\"0\" marker"; printf '%s\n' "$BROKEN_ROW"; }
grep -o '<rule name="no-printf"[^/]*/>' "$OUT" | grep -q 'compiled="0"' \
    && no "L10: the WELL-FORMED no-printf rule wrongly carries compiled=\"0\"" \
    || ok "L10: a well-formed rule's row carries no compiled= at all (absent = compiled)"

# 5. xmllint-clean
"$BIN" "$CORPUS" --lint-rules="$RULES" --no-cache 2>/dev/null | xmllint --noout - 2>/dev/null \
    && ok "xmllint clean" || no "xmllint reported malformed XML"

# 6. built-ins still fire when --lint is also given (on the built-in lint fixture)
"$BIN" "$LINTFIX" --lint --lint-rules="$RULES" --no-cache >"$TMP/both" 2>/dev/null; rc=$?
if [ "$rc" -eq 0 ]; then ok "--lint + --lint-rules exits 0"; else no "--lint + --lint-rules exit $rc"; fi
if grep -q 'rule="magic-number"'      "$TMP/both"; then ok "built-in rule still fires with --lint-rules present"; else no "built-in magic-number missing when combined"; fi
if grep -q 'rule="typedef-over-using"' "$TMP/both"; then ok "built-in typedef-over-using still fires"; else no "built-in typedef-over-using missing when combined"; fi

# 7. flag given but zero rules load → exit 1 with a clear message
EMPTY="$TMP/emptyrules"; mkdir -p "$EMPTY"
"$BIN" "$CORPUS" --lint-rules="$EMPTY" --no-cache >/dev/null 2>"$TMP/e2"; rc=$?
if [ "$rc" -eq 1 ]; then ok "empty rules dir → exit 1"; else no "empty rules dir exit $rc (expected 1)"; fi
if grep -qi 'no rules loaded' "$TMP/e2"; then ok "empty rules dir → clear stderr message"; else no "no 'no rules loaded' message"; fi

# ── 8. phase-2 combinators: inside / not-inside / not-matches ─────────────────────────────────────
# Fixture: test/lintrulesfix/combinators/{combo.cpp, rules/}. Each combinator has a kept case AND a
# filtered case; we assert by count AND by the exact line the surviving hit sits on. `l()` extracts the
# combo.cpp line numbers of a given rule's findings, in order, space-joined — the exact-line oracle.
COMBO="$CORPUS/combinators"
CRULES="$COMBO/rules"
if [ ! -d "$COMBO" ] || [ ! -d "$CRULES" ]; then
    no "combinators fixture missing ($COMBO)"
else
    "$BIN" "$COMBO" --lint-rules="$CRULES" --no-cache >"$TMP/c1" 2>/dev/null
    "$BIN" "$COMBO" --lint-rules="$CRULES" --no-cache >"$TMP/c2" 2>/dev/null
    diff -q "$TMP/c1" "$TMP/c2" >/dev/null && ok "combinators deterministic (byte-identical)" \
        || { no "combinators non-deterministic"; diff "$TMP/c1" "$TMP/c2" | head -8; }
    COUT="$TMP/c1"
    # count findings for a rule id; and list the combo.cpp lines (in emit order) for a rule id
    cnt(){ grep -oE "rule=\"$1\"" "$COUT" | wc -l | tr -d ' '; }
    lns(){ grep -oE "rule=\"$1\" [^>]*p=\"[^\"]*combo.cpp:[0-9]+" "$COUT" | grep -oE 'combo.cpp:[0-9]+' | grep -oE '[0-9]+$' | paste -sd' ' - ; }

    # inside: KEEP L19 (new inside makesWidget) + L25 (new inside makesPool); DROP L15 (namespace-scope new)
    if [ "$( cnt new-inside-fn )" = "2" ]; then ok "inside: 2 kept (function-scoped new)"; else no "inside: expected 2 findings, got $( cnt new-inside-fn )"; fi
    if [ "$( lns new-inside-fn )" = "19 25" ]; then ok "inside: kept exactly L19,L25 (L15 dropped)"; else no "inside: expected lines '19 25', got '$( lns new-inside-fn )'"; fi

    # not-inside: KEEP L33 (log in normalCaller); DROP L38 (log in skipMe — scope name ^skip)
    if [ "$( cnt log-not-in-skip )" = "1" ]; then ok "not-inside: 1 kept (log outside skip*)"; else no "not-inside: expected 1 finding, got $( cnt log-not-in-skip )"; fi
    if [ "$( lns log-not-in-skip )" = "33" ]; then ok "not-inside: kept exactly L33 (L38 dropped)"; else no "not-inside: expected line '33', got '$( lns log-not-in-skip )'"; fi

    # not-matches: KEEP L15 + L19 (new Widget); DROP L25 (new Pool<int> — type ^Pool)
    if [ "$( cnt new-not-pool )" = "2" ]; then ok "not-matches: 2 kept (non-Pool new)"; else no "not-matches: expected 2 findings, got $( cnt new-not-pool )"; fi
    if [ "$( lns new-not-pool )" = "15 19" ]; then ok "not-matches: kept exactly L15,L19 (L25 dropped)"; else no "not-matches: expected lines '15 19', got '$( lns new-not-pool )'"; fi

    # combinators output stays xmllint-clean
    "$BIN" "$COMBO" --lint-rules="$CRULES" --no-cache 2>/dev/null | xmllint --noout - 2>/dev/null \
        && ok "combinators xmllint clean" || no "combinators output malformed XML"

    # repeated `inside` keys AND-combine: candidate must be inside a function_definition AND a
    # compound_statement → only the two in-body news survive (L19,L25); the namespace-scope new (L15) drops.
    AND="$TMP/andrules"; mkdir -p "$AND"
    cat > "$AND/and.yml" <<YAML
- id: new-and
  language: cpp
  severity: warn
  message: new inside fn AND compound
  query: |
    (new_expression) @hit
  inside: |
    (function_definition) @a
  inside: |
    (compound_statement) @b
YAML
    "$BIN" "$COMBO" --lint-rules="$AND" --no-cache >"$TMP/cand" 2>/dev/null
    AND_LNS="$( grep -oE 'rule="new-and" [^>]*p="[^"]*combo.cpp:[0-9]+' "$TMP/cand" | grep -oE 'combo.cpp:[0-9]+' | grep -oE '[0-9]+$' | paste -sd' ' - )"
    if [ "$AND_LNS" = "19 25" ]; then ok "inside AND (repeated key): kept exactly L19,L25"; else no "inside-AND expected '19 25', got '$AND_LNS'"; fi

    # a malformed combinator block (empty '|' body) alerts + skips the file WHOLE, run still exits 0
    BADC="$TMP/badcombo"; mkdir -p "$BADC"
    printf -- '- id: empty-inside\n  language: cpp\n  query: |\n    (new_expression) @hit\n  inside: |\n' > "$BADC/empty.yml"
    # add a sound rule too so the dir isn't empty (empty dir → exit 1 is a DIFFERENT check)
    cp "$CRULES/inside.yml" "$BADC/sound.yml"
    "$BIN" "$COMBO" --lint-rules="$BADC" --no-cache >"$TMP/bc" 2>"$TMP/bcerr"; rc=$?
    if [ "$rc" -eq 0 ]; then ok "malformed combinator block → run still exits 0"; else no "malformed combinator exit $rc (expected 0)"; fi
    if grep -qi "empty 'inside' query" "$TMP/bcerr"; then ok "malformed combinator alerted (empty 'inside' named)"; else no "no alert for empty combinator block"; fi
    grep -q 'rule="empty-inside"' "$TMP/bc" && no "malformed combinator file wrongly loaded (empty-inside present)" || ok "malformed combinator file skipped whole (empty-inside absent)"
    if grep -q 'rule="new-inside-fn"' "$TMP/bc"; then ok "the sound sibling rule still loaded"; else no "sound sibling rule missing after skip"; fi
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
