#!/usr/bin/env bash
# didyoumeancheck.sh — gate for A3-F16a/b:
#
#   (a) every SYM-taking verb's "not found" stderr message ("ripwire: --X symbol not found: Y") now
#       appends a nearest-name suggestion ("(did you mean 'Z'?)") when a plausible near-miss exists in
#       the corpus. Covers --callers/--callees/--around/--expand/--lego/--path/--impact/--mentions/--owners.
#   (b) --graph-query parse errors append a one-line grammar reminder + worked example ("grammar: ...")
#       exactly once per error (not once per token consumed during the recursive-descent unwind).
#
# Reuses test/queryfix (functions d1..d4, hot/caller_a/caller_b/rec, struct Gadget — already hand-verified
# by querycheck.sh) so no new fixture is needed. Near-miss typos below are single/double-character edits
# of real symbol names in that fixture.
#
# Usage:
#   test/didyoumeancheck.sh
#   RIPWIRE_BIN=asan/ripwire test/didyoumeancheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/queryfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no test/queryfix dir — fixture missing"; exit 2; }

echo "didyoumeancheck: BIN=$BIN  CORPUS=$FIX"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== A3-F16a: nearest-name suggestion on SYM-verb 'not found' errors ==="
# ═══════════════════════════════════════════════════════════════════════════

check_dym(){
    # $1 = human label, $2.. = ripwire args (after FIX); asserts stderr has "did you mean 'EXPECT'" where
    # EXPECT is $3 (the 3rd positional after label/expect is passed as the rest of the args array)
    local label="$1" expect="$2"; shift 2
    local out
    out="$( "$BIN" "$FIX" "$@" --no-cache 2>&1 1>/dev/null )"
    if printf '%s' "$out" | grep -qF "did you mean '$expect'"; then
        ok "$label: suggests '$expect' ($out)"
    else
        no "$label: no plausible 'did you mean $expect' in: $out"
    fi
}

# one-character-off typos of real fixture symbols, each on the not-found path of a different verb.
check_dym "--callers"  "hot"       --callers=hott
check_dym "--callees"  "d1"        --callees=d11
check_dym "--around"   "caller_a"  --around=caller_A
check_dym "--expand"   "rec"       --expand=recc
check_dym "--lego"     "Gadget"    --lego=Gadgett
check_dym "--path"     "d4"        --path=d44,d1
check_dym "--impact"   "caller_b"  --impact=caller_B
check_dym "--mentions" "hot"       --mentions=hott
check_dym "--owners"   "d2"        --owners=d22

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== A3-F16b: --graph-query parse errors carry a grammar reminder ==="
# ═══════════════════════════════════════════════════════════════════════════

check_grammar(){
    local label="$1" expr="$2"
    local out
    out="$( "$BIN" "$FIX" --graph-query="$expr" --no-cache 2>&1 1>/dev/null )"
    if printf '%s' "$out" | grep -q 'grammar:'; then
        ok "$label: error carries a 'grammar:' reminder"
    else
        no "$label: missing 'grammar:' reminder in: $out"
    fi
    # exactly one "grammar:" line — not one per token during the recursive-descent unwind
    local n
    n="$( printf '%s' "$out" | grep -c 'grammar:' )"
    [ "$n" = 1 ] \
        && ok "$label: exactly one 'grammar:' line (not per-token)" \
        || no "$label: expected exactly 1 'grammar:' line, got $n"
    # the worked example is present too
    printf '%s' "$out" | grep -qF 'and(callers(name(' \
        && ok "$label: worked example present" \
        || no "$label: worked example missing"
}

check_grammar "unclosed-paren"  'callers(name("x")'
check_grammar "unknown-op"      'frobnicate(all)'
check_grammar "bad-kind"        'kind(all,bogus)'
check_grammar "nested-unclosed" 'and(callers(name("hot"),2),kind(all,fn)'

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== §P12.1: true edit-distance suggester (self-corpus — needs a real decoy in-prefix) ==="
# ═══════════════════════════════════════════════════════════════════════════
# test/queryfix is too small to exercise the old bug (shared-prefix*4 - |lenDelta|): it needs a corpus with
# an unrelated symbol that shares a long prefix with the typo. ripwire's own src/ has exactly that —
# src/search.h's parseAlt() shares "pars"/"pare" with a typo'd parseArgs and used to outscore it. Run
# against ROOT itself so parseArgs/buildGraph/runEval (real ripwire symbols) are in the pool.
check_dym_self(){
    local label="$1" expect="$2"; shift 2
    local out
    out="$( "$BIN" "$ROOT" "$@" --no-cache 2>&1 1>/dev/null )"
    if printf '%s' "$out" | grep -qF "did you mean '$expect'"; then
        ok "$label: suggests '$expect' ($out)"
    else
        no "$label: no plausible 'did you mean $expect' in: $out"
    fi
}

check_dym_self "--callers=parsArgs (1-edit; parseAlt is the old false winner)"  "parseArgs"  --callers=parsArgs
check_dym_self "--callers=pareArgs (1-edit; parseAlt is the old false winner)"  "parseArgs"  --callers=pareArgs
check_dym_self "--callers=buildGrap (1-edit insert)"                           "buildGraph" --callers=buildGrap
check_dym_self "--callers=runEva (1-edit insert)"                              "runEval"    --callers=runEva

# §P10.2-era regression: a src/-prefixed unqualified typo on --uses must resolve to the REAL symbol, not
# the constant nonsense suggestion "srcmut_sigchange" (the old "file:" prefix poisoning the suggester bug).
out="$( "$BIN" "$ROOT" --uses=src/graph.h:buildGrap --no-cache 2>&1 1>/dev/null )"
if printf '%s' "$out" | grep -q 'srcmut_sigchange'; then
    no "src/-prefixed typo: constant nonsense suggestion srcmut_sigchange is back: $out"
else
    ok "src/-prefixed typo: no constant nonsense suggestion"
fi
printf '%s' "$out" | grep -qF "did you mean 'buildGraph'" \
    && ok "src/-prefixed typo: suggests real symbol 'buildGraph'" \
    || no "src/-prefixed typo: expected 'did you mean buildGraph' in: $out"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== sanity: a genuinely-missing symbol with NO plausible near-miss doesn't fabricate one ==="
# ═══════════════════════════════════════════════════════════════════════════

# a wildly different name should either get no suggestion or a low-quality one — we only assert the
# command still exits non-zero and prints the base "not found" message (never crashes/hangs).
out="$( perl -e 'alarm 8; exec @ARGV' "$BIN" "$FIX" --callers=zzzzzzzzzzzzzzzzzzzz --no-cache 2>&1 1>/dev/null )"
rc=$?
{ [ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'symbol not found'; } \
    && ok "wildly-unmatched name: still exits 1 with a 'not found' message (no crash/hang)" \
    || no "wildly-unmatched name: unexpected exit/output ($rc: $out)"

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== X9(e): did-you-mean must NEVER offer a markdown Section title for a code-symbol typo ==="
# ═══════════════════════════════════════════════════════════════════════════
# Isolated copy of queryfix + a markdown doc whose H1 heading ("hottt") scores HIGHER against the query
# "hott" than the real code symbol "hot" does under didYouMean's prefix+length-delta scoring: "hottt" vs
# "hott" = prefix 4, lenDelta 1 -> score 15; "hot" vs "hott" = prefix 3, lenDelta 1 -> score 11. "hottt" is
# deliberately NOT an exact match for the query (that would resolve as a real hit, never reaching
# did-you-mean at all) — it only needs to OUTSCORE "hot" in the candidate pool. Before the X9(e) fix,
# didYouMean's shared pool included Section symbols, so the suggestion would be the markdown heading
# "hottt", not the code symbol "hot": a nonsensical suggestion for a --callers/--impact/--around/etc.
# typo. The fix excludes SymKind::Section from the pool.
SECFIX="$TMP/secfix"; mkdir -p "$SECFIX/src"
cp "$FIX"/src/*.cpp "$SECFIX/src/" 2>/dev/null
cat > "$SECFIX/docs.md" <<'EOF'
# hottt

Unrelated documentation content — a markdown Section symbol whose title outscores the code symbol "hot"
against the query typo "hott" below, under the plain prefix+length-delta metric.
EOF

secout="$( "$BIN" "$SECFIX" --callers=hott --no-cache 2>&1 1>/dev/null )"
secrc=$?
[ "$secrc" = 1 ] || no "X9(e) setup: --callers=hott should still exit 1 (got $secrc)"
printf '%s' "$secout" | grep -q "did you mean 'hottt'" \
    && no "X9(e): did-you-mean suggested the markdown Section title 'hottt' (should be excluded)" \
    || ok "X9(e): markdown Section title 'hottt' NOT suggested"
printf '%s' "$secout" | grep -q "did you mean 'hot'" \
    && ok "X9(e): correctly falls back to the real code symbol 'hot' instead" \
    || { no "X9(e): expected a fallback suggestion of 'hot', got: $secout"; }

# ═══════════════════════════════════════════════════════════════════════════
echo
echo "=== M9: the EDIT verbs share the read verbs' near-miss policy (one suggester, not two) ==="
# ═══════════════════════════════════════════════════════════════════════════
# capture-audit 2026-09-04, lens 6 F8. The three edit verbs had their OWN candidate ranker — a
# case-folded shared-prefix score minus length delta — so they answered:
#     --replace-symbol-body=DoesNotExist  → "nearest: do_snake_one, do_snake_two, docDriftText, …"
#     --insert-before-symbol=<one-edit typo> → the right name, but buried in four prefix neighbours
# Prefix neighbours of a name that has no near-miss are noise dressed as help: an agent that acts on
# `do_snake_one` for `DoesNotExist` edits the wrong function. The read verbs' didYouMean has said for a
# long time that no plausible candidate is an honest answer. The property below is CONSISTENCY, not
# "always suggest something": on the SAME input, the read and edit surfaces agree.
#
# The other two halves of F8: the refusal names the FLAG (all three verbs said "ripwire edit:", so a log
# could not tell them apart), and a `--edit-target-file` that matches no indexed file blames the PATH half
# instead of the symbol ("'size' not found under path 'svectr.h'" for a path that was never indexed).
EDITFIX="$TMP/editfix"; mkdir -p "$EDITFIX"
printf 'int rankGraphTeleport( int x ) { return x + 1; }\nint helperTwo( int y ) { return y; }\n' > "$EDITFIX/one.cpp"
printf 'payload\n' > "$TMP/payload.txt"

for verb in --replace-symbol-body --insert-before-symbol --insert-after-symbol; do
    # (a) a one-edit typo names the SAME candidate the read verbs name
    out="$( "$BIN" "$EDITFIX" "$verb=rankGraphTeleporr" --edit-payload="$TMP/payload.txt" --no-cache 2>&1 1>/dev/null )"
    printf '%s' "$out" | grep -qF "rankGraphTeleport" \
        && ok "M9 $verb: a one-edit typo names rankGraphTeleport" \
        || no "M9 $verb: no near-miss for a one-edit typo: $out"
    # (b) a name with NO plausible near-miss gets NO candidate list (the read verbs' contract)
    out="$( "$BIN" "$EDITFIX" "$verb=DoesNotExist" --edit-payload="$TMP/payload.txt" --no-cache 2>&1 1>/dev/null )"
    printf '%s' "$out" | grep -qF "nearest:" \
        && no "M9 $verb=DoesNotExist: invented a candidate list from prefix neighbours: $out" \
        || ok "M9 $verb=DoesNotExist: no fabricated candidates (nothing is within edit distance)"
    # (c) the refusal names the verb's own flag
    printf '%s' "$out" | grep -qF -- "$verb" \
        && ok "M9 $verb: the refusal names the flag" \
        || no "M9 $verb: refusal does not name the flag (three verbs, one indistinguishable prefix): $out"
done

# (d) a --edit-target-file matching no indexed file diagnoses the PATH half
out="$( "$BIN" "$EDITFIX" --replace-symbol-body=rankGraphTeleport --edit-target-file=nosuchfile.h \
        --edit-payload="$TMP/payload.txt" --no-cache 2>&1 1>/dev/null )"
printf '%s' "$out" | grep -qiE "no indexed file|PATH half" \
    && ok "M9 --edit-target-file=<unindexed>: the PATH half is named as the fault" \
    || no "M9 --edit-target-file=<unindexed>: the refusal blames the symbol for a path fault: $out"

# (e) the read verbs are unchanged on the same two inputs (the consistency this arm is really pinning)
out="$( "$BIN" "$EDITFIX" --callers=DoesNotExist --no-cache 2>&1 1>/dev/null )"
printf '%s' "$out" | grep -qF "did you mean" \
    && no "M9 --callers=DoesNotExist: the read verb fabricated a candidate too" \
    || ok "M9 --callers=DoesNotExist: no candidate — the same answer the edit verbs now give"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
