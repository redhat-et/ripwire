#!/usr/bin/env bash
# matchgrammarcheck.sh — §L3 gate: a --match query that compiles for SOME grammars but zero of them are
# present in the corpus must not report a bare hits="0" — that is indistinguishable from "this pattern does
# not occur" (the honesty contract §3 in CLAUDE.md: a zero means "none found", never "none exists").
#
#   `(interface_declaration) @m` against a Python-only fixture returned <match hits="0" ...> with nothing
#   saying the query never had a Java/C#/TS file to run against. The compile loop already tries every
#   grammar to decide whether to refuse outright (the existing "compiled for no grammar" message) — this
#   gate is about the query that DID compile (for grammars the corpus doesn't hold), which is the gap that
#   message does not cover.
#
# Fix shape: additive attributes on the <match> root —
#   grammars="csv"        the grammar names the query compiled against (kLangTable order, deterministic,
#                          independent of what the corpus actually holds)
#   eligible_files="N"    corpus files whose language is among those grammars
#   of_files="M"          total indexed files (N and M make a floor-vs-total honest even at N=0)
#
#   RIPWIRE_BIN=build/ripwire      bash test/matchgrammarcheck.sh
#   RIPWIRE_BIN=build_base/ripwire bash test/matchgrammarcheck.sh   # must FAIL (pre-fix binary)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "matchgrammarcheck: BIN=$BIN  ROOT=$ROOT"

# A corpus that holds exactly ONE language: Python. No .java/.cs/.ts file anywhere in it.
PYFIX="$TMP/pyonly"
mkdir -p "$PYFIX"
cat > "$PYFIX/sample.py" <<'EOF'
def foo():
    pass


class Bar:
    def method(self):
        return 1
EOF

# Scoped to the <match ...> TAG itself, never the whole line — the legend comment that precedes it is
# human prose and happens to contain literal `eligible_files="0"` / `hits="0"` as WORDED EXAMPLES, which a
# whole-line grep would find first (single-line minified output, no newline between comment and tag).
attrOf(){ grep -oE '<match [^>]*>' "$1" | grep -oE " $2=\"[^\"]*\"" | head -1 | sed -E "s/^ $2=\"([^\"]*)\"/\1/"; }

# ── arm 1: a query that compiles for OTHER grammars (java/csharp/typescript all have interface_declaration)
#    but the corpus is Python-only — zero of those grammars are present here.
"$BIN" "$PYFIX" --match='(interface_declaration) @m' >"$TMP/arm1.out" 2>"$TMP/arm1.err"; rc1=$?
[ "$rc1" -eq 0 ] && ok "arm1: exit 0 (query compiled for SOME grammar, not refused)" \
                 || no "arm1: exit $rc1 (expected 0): $( cat "$TMP/arm1.err" )"

grammars1="$( attrOf "$TMP/arm1.out" grammars )"
[ -n "$grammars1" ] && ok "arm1: grammars=\"$grammars1\" present and non-empty" \
                    || no "arm1: grammars= missing or empty — a query compiling for other grammars must say which"

elig1="$( attrOf "$TMP/arm1.out" eligible_files )"
[ "$elig1" = "0" ] && ok "arm1: eligible_files=\"0\" (Python-only corpus has no java/csharp/ts file)" \
                   || no "arm1: eligible_files=\"${elig1:-<missing>}\" (expected \"0\")"

of1="$( attrOf "$TMP/arm1.out" of_files )"
[ "$of1" = "1" ] && ok "arm1: of_files=\"1\" (the corpus's one indexed file)" \
                 || no "arm1: of_files=\"${of1:-<missing>}\" (expected \"1\")"

hits1="$( attrOf "$TMP/arm1.out" hits )"
[ "$hits1" = "0" ] && ok "arm1: hits=\"0\" (correct — but now disclosed as measured, not guessed)" \
                   || no "arm1: hits=\"${hits1:-<missing>}\" (expected \"0\")"

# ── arm 2: a query that compiles for the fixture's OWN language — eligible_files must be > 0.
"$BIN" "$PYFIX" --match='(function_definition) @f' >"$TMP/arm2.out" 2>"$TMP/arm2.err"; rc2=$?
[ "$rc2" -eq 0 ] && ok "arm2: exit 0" || no "arm2: exit $rc2 (expected 0): $( cat "$TMP/arm2.err" )"

grammars2="$( attrOf "$TMP/arm2.out" grammars )"
case ",$grammars2," in
    *,python,*) ok "arm2: grammars=\"$grammars2\" includes python" ;;
    *)          no "arm2: grammars=\"${grammars2:-<missing>}\" does not include python" ;;
esac

elig2="$( attrOf "$TMP/arm2.out" eligible_files )"
[ "${elig2:-0}" -gt 0 ] 2>/dev/null && ok "arm2: eligible_files=\"$elig2\" > 0 (the fixture's own language matched)" \
                                    || no "arm2: eligible_files=\"${elig2:-<missing>}\" (expected > 0)"

of2="$( attrOf "$TMP/arm2.out" of_files )"
[ "$of2" = "1" ] && ok "arm2: of_files=\"1\"" || no "arm2: of_files=\"${of2:-<missing>}\" (expected \"1\")"

hits2="$( attrOf "$TMP/arm2.out" hits )"
[ "$hits2" = "2" ] && ok "arm2: hits=\"2\" (def foo + def method)" \
                   || no "arm2: hits=\"${hits2:-<missing>}\" (expected \"2\")"

# ── arm 3: regression guard — a query that compiles for NO grammar at all must still be refused outright,
#    exactly as before (no <match> element, exit 1, the existing add-@name-adjacent refusal message).
"$BIN" "$PYFIX" --match='(this_is_not_a_node)' >"$TMP/arm3.out" 2>"$TMP/arm3.err"; rc3=$?
[ "$rc3" -eq 1 ] && ok "arm3: exit 1 (uncompilable query still refused)" \
                 || no "arm3: exit $rc3 (expected 1)"
grep -q '<match' "$TMP/arm3.out" && no "arm3: a <match> element was printed on the refusal path" \
                                 || ok "arm3: no <match> element on the refusal path"
grep -q 'compiled for no grammar' "$TMP/arm3.err" && ok "arm3: refusal message unchanged" \
                                                   || no "arm3: refusal message missing/changed: $( cat "$TMP/arm3.err" )"

# ── arm 4 (octocode F3): a NEAR-MISS node-kind typo — `call_expresion` is one deleted 's' away from the
#    real `call_expression` (a genuine cpp node kind; see third_party/deps/cpp/src/parser.c's
#    ts_symbol_names table) — must be refused with a `nearest_kind=` hint naming the real kind, plus the
#    grammar it belongs to. This is the query text auto-captured to `(call_expresion) @m`, which still
#    compiles for NO grammar (arm3's regression path), so the hint rides the SAME refusal, not a new one.
"$BIN" "$PYFIX" --match='(call_expresion)' >"$TMP/arm4.out" 2>"$TMP/arm4.err"; rc4=$?
[ "$rc4" -eq 1 ] && ok "arm4: exit 1 (still an uncompilable-query refusal)" \
                 || no "arm4: exit $rc4 (expected 1)"
grep -q '<match' "$TMP/arm4.out" && no "arm4: a <match> element was printed on the refusal path" \
                                 || ok "arm4: no <match> element on the refusal path"
nk4="$( grep -oE 'nearest_kind="[^"]*"' "$TMP/arm4.err" | head -1 )"
[ "$nk4" = 'nearest_kind="call_expression"' ] && ok "arm4: $nk4" \
                                              || no "arm4: nearest_kind missing/wrong (got '${nk4:-<none>}', expected nearest_kind=\"call_expression\"): $( cat "$TMP/arm4.err" )"
gr4="$( grep -oE 'grammar="[^"]*"' "$TMP/arm4.err" | head -1 )"
[ "$gr4" = 'grammar="cpp"' ] && ok "arm4: $gr4 (call_expression is a cpp node kind)" \
                             || no "arm4: grammar missing/wrong (got '${gr4:-<none>}', expected grammar=\"cpp\"): $( cat "$TMP/arm4.err" )"

# ── arm 5 (octocode F3): TOTAL garbage — no real node kind is within the edit-distance cutoff of
#    `zzqqxx` in ANY linked grammar's vocabulary. Design choice, asserted explicitly: the refusal stays
#    exactly as it was pre-fix (no hint at all) rather than forcing a distant, useless guess — the same
#    "no plausible near-miss" contract didyoumean.h's didYouMean() already uses for symbol names.
"$BIN" "$PYFIX" --match='(zzqqxx)' >"$TMP/arm5.out" 2>"$TMP/arm5.err"; rc5=$?
[ "$rc5" -eq 1 ] && ok "arm5: exit 1 (uncompilable garbage query still refused)" \
                 || no "arm5: exit $rc5 (expected 1)"
grep -q '<match' "$TMP/arm5.out" && no "arm5: a <match> element was printed on the refusal path" \
                                 || ok "arm5: no <match> element on the refusal path"
grep -q 'nearest_kind=' "$TMP/arm5.err" && no "arm5: a nearest_kind hint was emitted for garbage with no close kind: $( cat "$TMP/arm5.err" )" \
                                        || ok "arm5: no nearest_kind hint (no candidate was close enough — honest silence, not a guess)"
grep -q 'compiled for no grammar' "$TMP/arm5.err" && ok "arm5: refusal message present, unchanged shape" \
                                                   || no "arm5: refusal message missing/changed: $( cat "$TMP/arm5.err" )"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
