#!/usr/bin/env bash
# verifycheck.sh — G4 VERIFY-A-CLAIM: `--verify="CLAIM"` answers a structured claim about the code with
# EVIDENCE plus a verdict the agent can trust, in ONE call — the collapse of the manual verification
# grep-chain (the month-scale mine's biggest verb-less intent).
#
# THE VERDICT GRAMMAR IS THE CONTRACT, and it is three-valued because the index cannot support a bare
# yes/no everywhere:
#   confirmed        — a witness exists and is printed inline (a path, use-sites, hits, a definition).
#   refuted          — ONLY where the underlying scan can claim completeness: a literal-scan absence
#                      (contains / the defines literal check) carries complete="1"; an absence-claim
#                      (unused) is refuted by printed witness sites. Never by a graph/reference zero.
#   not-established  — the absence is real WITHIN THE MODEL but the model is a floor; limit= names the
#                      limiting factor (call-graph floor, reference floor, collection ceiling, scan
#                      degrade, extraction floor). NEVER means "false".
# calls()/reaches() can NEVER refute (name-based call edges: dynamic dispatch contributes no edge), and
# unused() can NEVER confirm (the reference index is a floor). A false completeness claim is the worst
# bug this tool can ship, so the arms below include MUTATION arms asserting what must NOT appear.
#
# Fixture: test/verifyfix — chain.cpp (entry_caller -> mid_hop -> leaf_target), registry.cpp
# (zz_registry_handler invoked ONLY via a string literal = the dynamic-dispatch shape the floor
# vocabulary exists for).
#
# Usage:  test/verifycheck.sh              # uses build/ripwire
#         RIPWIRE_BIN=asan/ripwire test/verifycheck.sh
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
cd "$ROOT"
echo "verifycheck: BIN=$BIN"

FIX=test/verifyfix

# the root START-TAG only — the legend COMMENT also spells the attribute names (it defines them), so
# every presence/absence assertion must parse the element, never grep the stream (completecheck's rule).
root_of(){ grep -o '<verify [^>]*>' | head -1; }

# ── 0) presence guards — the fixture must hold what the arms probe (CONTRIBUTING §2) ───────────────────
"$BIN" "$FIX" --no-cache >"$TMP/map.xml" 2>/dev/null
for s in entry_caller mid_hop leaf_target zz_registry_handler; do
    grep -q "n=\"$s\"" "$TMP/map.xml" \
        && ok "presence: $s is indexed" \
        || no "presence: $s missing from the fixture map — every arm below is void"
done
grep -q '"zz_registry_handler"' "$FIX/registry.cpp" \
    && ok "presence: the dynamic-dispatch string literal exists in the fixture" \
    || no "presence: registry.cpp lost its string-keyed call site — the unused() mutation arm is void"
grep -q 'mid_hop' "$FIX/registry.cpp" \
    && ok "presence: registry.cpp mentions mid_hop (extraction-floor arm's occurrence)" \
    || no "presence: registry.cpp no longer mentions mid_hop — the extraction-floor arm is void"
grep -q 'entry_caller' "$FIX/registry.cpp" \
    && no "presence: registry.cpp mentions entry_caller — the defines() REFUTED arm would be void" \
    || ok "presence: entry_caller absent from registry.cpp (the defines() complete-refutation target)"

# ── 1) calls() TRUE — verdict confirmed, with the path as inline evidence ──────────────────────────────
"$BIN" "$FIX" --no-cache --verify='calls(entry_caller, leaf_target)' >"$TMP/c1.xml" 2>"$TMP/c1.err"; rc=$?
R="$( root_of <"$TMP/c1.xml" )"
{ [ $rc -eq 0 ] && printf '%s' "$R" | grep -q 'verdict="confirmed"'; } \
    && ok 'calls true: verdict is confirmed at exit 0' \
    || { no "calls true: expected confirmed/exit 0 (rc=$rc)"; printf '%s\n' "$R"; head -2 "$TMP/c1.err"; }
grep -q 'n="mid_hop"' "$TMP/c1.xml" \
    && ok 'calls true: the path evidence names the intermediate hop inline' \
    || no 'calls true: no inline path evidence (mid_hop missing from the rows)'
printf '%s' "$R" | grep -q 'shape="calls"' \
    && ok 'calls true: the root names the claim shape' \
    || no 'calls true: shape= missing from the root'

# ── 2) calls() reverse — NOT-ESTABLISHED, never refuted (the call graph is a floor) ────────────────────
"$BIN" "$FIX" --no-cache --verify='calls(leaf_target, entry_caller)' >"$TMP/c2.xml" 2>/dev/null; rc=$?
R="$( root_of <"$TMP/c2.xml" )"
{ [ $rc -eq 0 ] && printf '%s' "$R" | grep -q 'verdict="not-established"'; } \
    && ok 'calls reverse: verdict is not-established at exit 0' \
    || { no "calls reverse: expected not-established (rc=$rc)"; printf '%s\n' "$R"; }
printf '%s' "$R" | grep -q 'verdict="refuted"' \
    && no 'calls MUTATION: a graph absence claimed refuted — the floor vocabulary forbids this' \
    || ok 'calls MUTATION: the graph absence did NOT claim refuted'
printf '%s' "$R" | grep -q 'limit="call-graph-floor"' \
    && ok 'calls reverse: limit= names the call-graph floor' \
    || no 'calls reverse: the limiting factor is not named'
printf '%s' "$R" | grep -q 'complete="1"' \
    && no 'calls MUTATION: a floor-bounded answer wore complete= — worst-bug class' \
    || ok 'calls MUTATION: no completeness claim on a floor-bounded answer'

# ── 3) contains() REFUTED — the complete literal-scan no ───────────────────────────────────────────────
"$BIN" "$FIX" --no-cache --verify='contains(chain.cpp, "zqzq_absent_token")' >"$TMP/n1.xml" 2>/dev/null; rc=$?
R="$( root_of <"$TMP/n1.xml" )"
{ [ $rc -eq 0 ] && printf '%s' "$R" | grep -q 'verdict="refuted"' && printf '%s' "$R" | grep -q 'complete="1"'; } \
    && ok 'contains refuted: a clean literal scan claims the complete no' \
    || { no "contains refuted: expected refuted + the completeness claim (rc=$rc)"; printf '%s\n' "$R"; }
printf '%s' "$R" | grep -q 'counts_floor' \
    && no 'contains MUTATION: complete= and counts_floor= co-occur on one root — mutually exclusive by doctrine' \
    || ok 'contains MUTATION: no floor marker beside the completeness claim'

# ── 4) contains() CONFIRMED — hits inline, still complete when every hit printed ───────────────────────
"$BIN" "$FIX" --no-cache --verify='contains(chain.cpp, "mid_hop")' >"$TMP/n2.xml" 2>/dev/null; rc=$?
R="$( root_of <"$TMP/n2.xml" )"
{ [ $rc -eq 0 ] && printf '%s' "$R" | grep -q 'verdict="confirmed"'; } \
    && ok 'contains confirmed: the literal is found' \
    || { no "contains confirmed: expected confirmed (rc=$rc)"; printf '%s\n' "$R"; }
grep -q '<hit p="test/verifyfix/chain.cpp:' "$TMP/n2.xml" \
    && ok 'contains confirmed: hit rows carry file:line evidence inline' \
    || no 'contains confirmed: no inline hit evidence'
# a comma INSIDE the quoted literal must parse (the quote scan owns the argument split)
"$BIN" "$FIX" --no-cache --verify='contains(chain.cpp, "mid_hop(), then")' >"$TMP/n3.xml" 2>/dev/null; rc=$?
R="$( root_of <"$TMP/n3.xml" )"
{ [ $rc -eq 0 ] && printf '%s' "$R" | grep -q 'verdict="refuted"'; } \
    && ok 'contains parse: a comma inside the quoted literal splits nothing' \
    || { no "contains parse: quoted-comma literal mishandled (rc=$rc)"; printf '%s\n' "$R"; }

# ── 5) unused() — the mutation arm the verdict grammar exists for ──────────────────────────────────────
# zz_registry_handler IS invoked (string-keyed registry), but the identifier-based reference index sees
# zero sites. The verdict must be NOT-ESTABLISHED: never refuted, and NEVER confirmed.
"$BIN" "$FIX" --no-cache --verify='unused(zz_registry_handler)' >"$TMP/u1.xml" 2>/dev/null; rc=$?
R="$( root_of <"$TMP/u1.xml" )"
{ [ $rc -eq 0 ] && printf '%s' "$R" | grep -q 'verdict="not-established"'; } \
    && ok 'unused dynamic-dispatch: verdict is not-established' \
    || { no "unused dynamic-dispatch: expected not-established (rc=$rc)"; printf '%s\n' "$R"; }
printf '%s' "$R" | grep -q 'verdict="confirmed"' \
    && no 'unused MUTATION: a reference-floor zero claimed confirmed — beyond the floor' \
    || ok 'unused MUTATION: the zero did NOT confirm the claim'
printf '%s' "$R" | grep -q 'limit="reference-floor"' \
    && ok 'unused dynamic-dispatch: limit= names the reference floor' \
    || no 'unused dynamic-dispatch: the limiting factor is not named'

# ── 6) unused() REFUTED by witness — one printed site is the whole proof ───────────────────────────────
"$BIN" "$FIX" --no-cache --verify='unused(leaf_target)' >"$TMP/u2.xml" 2>/dev/null; rc=$?
R="$( root_of <"$TMP/u2.xml" )"
{ [ $rc -eq 0 ] && printf '%s' "$R" | grep -q 'verdict="refuted"'; } \
    && ok 'unused refuted: a witness site refutes the absence claim' \
    || { no "unused refuted: expected refuted (rc=$rc)"; printf '%s\n' "$R"; }
grep -q '<u role="call" p="test/verifyfix/chain.cpp:' "$TMP/u2.xml" \
    && ok 'unused refuted: the witness use-site is inline' \
    || no 'unused refuted: no inline witness'

# ── 7) uses() CONFIRMED ────────────────────────────────────────────────────────────────────────────────
"$BIN" "$FIX" --no-cache --verify='uses(leaf_target)' >"$TMP/u3.xml" 2>/dev/null; rc=$?
R="$( root_of <"$TMP/u3.xml" )"
{ [ $rc -eq 0 ] && printf '%s' "$R" | grep -q 'verdict="confirmed"'; } \
    && ok 'uses confirmed: reference sites exist and confirm' \
    || { no "uses confirmed: expected confirmed (rc=$rc)"; printf '%s\n' "$R"; }

# ── 8) defines(): confirmed / complete-refuted / extraction-floor ──────────────────────────────────────
"$BIN" "$FIX" --no-cache --verify='defines(chain.cpp, mid_hop)' >"$TMP/d1.xml" 2>/dev/null; rc=$?
R="$( root_of <"$TMP/d1.xml" )"
{ [ $rc -eq 0 ] && printf '%s' "$R" | grep -q 'verdict="confirmed"'; } \
    && ok 'defines confirmed: the definition row is the witness' \
    || { no "defines confirmed: expected confirmed (rc=$rc)"; printf '%s\n' "$R"; }
"$BIN" "$FIX" --no-cache --verify='defines(registry.cpp, entry_caller)' >"$TMP/d2.xml" 2>/dev/null; rc=$?
R="$( root_of <"$TMP/d2.xml" )"
{ [ $rc -eq 0 ] && printf '%s' "$R" | grep -q 'verdict="refuted"' && printf '%s' "$R" | grep -q 'complete="1"'; } \
    && ok 'defines refuted: the name token never occurs in FILE — a complete literal no' \
    || { no "defines refuted: expected refuted + completeness (rc=$rc)"; printf '%s\n' "$R"; }
# mid_hop occurs in registry.cpp (a comment) but has no extracted definition there → the verdict may not
# lean either way: NOT-ESTABLISHED with the extraction floor named.
"$BIN" "$FIX" --no-cache --verify='defines(registry.cpp, mid_hop)' >"$TMP/d3.xml" 2>/dev/null; rc=$?
R="$( root_of <"$TMP/d3.xml" )"
{ [ $rc -eq 0 ] && printf '%s' "$R" | grep -q 'verdict="not-established"' && printf '%s' "$R" | grep -q 'limit="extraction-floor"'; } \
    && ok 'defines extraction-floor: occurrence without a def stays not-established' \
    || { no "defines extraction-floor: expected not-established + extraction-floor (rc=$rc)"; printf '%s\n' "$R"; }
printf '%s' "$R" | grep -q 'verdict="refuted"' \
    && no 'defines MUTATION: an occurrence-bearing file claimed refuted' \
    || ok 'defines MUTATION: no refutation while the name occurs in the file'

# ── 9) reaches(): file target confirmed / layer target confirmed / floor absence ───────────────────────
"$BIN" "$FIX" --no-cache --verify='reaches(leaf_target, "chain.cpp")' >"$TMP/r1.xml" 2>/dev/null; rc=$?
R="$( root_of <"$TMP/r1.xml" )"
{ [ $rc -eq 0 ] && printf '%s' "$R" | grep -q 'verdict="confirmed"'; } \
    && ok 'reaches file: code in chain.cpp reaches leaf_target — confirmed' \
    || { no "reaches file: expected confirmed (rc=$rc)"; printf '%s\n' "$R"; }
grep -q 'n="leaf_target"' "$TMP/r1.xml" \
    && ok 'reaches file: the witness path lands on the target inline' \
    || no 'reaches file: no inline path evidence'
"$BIN" "$FIX" --no-cache --verify='reaches(leaf_target, test)' >"$TMP/r2.xml" 2>/dev/null; rc=$?
R="$( root_of <"$TMP/r2.xml" )"
{ [ $rc -eq 0 ] && printf '%s' "$R" | grep -q 'verdict="confirmed"'; } \
    && ok 'reaches layer: the built-in layer vocabulary resolves (test)' \
    || { no "reaches layer: expected confirmed (rc=$rc)"; printf '%s\n' "$R"; }
"$BIN" "$FIX" --no-cache --verify='reaches(entry_caller, "registry.cpp")' >"$TMP/r3.xml" 2>/dev/null; rc=$?
R="$( root_of <"$TMP/r3.xml" )"
{ [ $rc -eq 0 ] && printf '%s' "$R" | grep -q 'verdict="not-established"' && printf '%s' "$R" | grep -q 'limit="call-graph-floor"'; } \
    && ok 'reaches absence: not-established with the call-graph floor named' \
    || { no "reaches absence: expected not-established (rc=$rc)"; printf '%s\n' "$R"; }

# ── 10) refusals — unknown shape lists the WHOLE vocabulary; a typo is a user error, not a measurement ──
"$BIN" "$FIX" --no-cache --verify='frobnicates(a, b)' >"$TMP/x1.out" 2>"$TMP/x1.err"; rc=$?
[ $rc -ne 0 ] && [ ! -s "$TMP/x1.out" ] \
    && ok 'refusal: unknown shape exits non-zero with no output element' \
    || no "refusal: unknown shape did not refuse (rc=$rc)"
for shape in 'calls(' 'uses(' 'unused(' 'contains(' 'defines(' 'reaches('; do
    grep -qF "$shape" "$TMP/x1.err" \
        && ok "refusal: the vocabulary names $shape" \
        || no "refusal: $shape missing from the refusal vocabulary"
done
"$BIN" "$FIX" --no-cache --verify='calls' >/dev/null 2>"$TMP/x2.err"; rc=$?
[ $rc -ne 0 ] && grep -qF 'contains(' "$TMP/x2.err" \
    && ok 'refusal: a shapeless claim refuses with the vocabulary' \
    || no "refusal: shapeless claim did not refuse with the vocabulary (rc=$rc)"
"$BIN" "$FIX" --no-cache --verify='uses(zz_no_such_symbol_qq)' >/dev/null 2>"$TMP/x3.err"; rc=$?
[ $rc -ne 0 ] && grep -q 'not found' "$TMP/x3.err" \
    && ok 'refusal: an unresolvable symbol refuses (a typo is not a measurement)' \
    || no "refusal: unknown symbol did not refuse (rc=$rc)"
"$BIN" "$FIX" --no-cache --verify='contains(zz_no_such_file.cpp, "x")' >/dev/null 2>"$TMP/x4.err"; rc=$?
[ $rc -ne 0 ] \
    && ok 'refusal: a file matching nothing indexed refuses' \
    || no "refusal: unindexed file did not refuse (rc=$rc)"

# ── 11) determinism ×3 (byte identity) and well-formedness across every verdict class ──────────────────
det=1
for i in 1 2 3; do
    "$BIN" "$FIX" --no-cache --verify='calls(entry_caller, leaf_target)' >"$TMP/det.$i" 2>/dev/null
done
cmp -s "$TMP/det.1" "$TMP/det.2" && cmp -s "$TMP/det.2" "$TMP/det.3" || det=0
[ $det -eq 1 ] && ok 'determinism: three runs are byte-identical' || no 'determinism: runs differ'
xml_ok=1
for f in c1 c2 n1 n2 n3 u1 u2 u3 d1 d2 d3 r1 r2 r3; do
    xmllint --noout "$TMP/$f.xml" 2>/dev/null || { xml_ok=0; no "xmllint: $f.xml is not well-formed"; }
done
[ $xml_ok -eq 1 ] && ok 'xmllint: every verdict class is well-formed XML'

# ── 12) the honesty invariant, swept across every captured root ────────────────────────────────────────
both=0
for f in c1 c2 n1 n2 n3 u1 u2 u3 d1 d2 d3 r1 r2 r3; do
    RT="$( root_of <"$TMP/$f.xml" )"
    if printf '%s' "$RT" | grep -q 'complete="1"' && printf '%s' "$RT" | grep -q 'counts_floor'; then both=1; no "honesty: $f.xml carries complete= AND counts_floor= on one root"; fi
done
[ $both -eq 0 ] && ok 'honesty: complete= and counts_floor= never co-occur on a verify root'

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
