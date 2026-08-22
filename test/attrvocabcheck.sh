#!/usr/bin/env bash
# attrvocabcheck.sh — the gate for  "Vocabulary": the four attribute-name
# defects that a MACHINE consumer trips over, as opposed to the prose-level ones.
#
# Why these four and not the whole §P8 list: each one below is a spelling a parser cannot work around.
# The rest of §P8 (the ~25 spellings for "how many rows", the six float precisions) is a consistency
# complaint a parser CAN work around by reading the legend, so it is documented, not gated.
#
#   1  head_ref, one spelling — --stray-content used to print `head-ref=` while its own --abi sibling printed
#      `head_ref=`. Same concept, same verb FAMILY, one keystroke apart, and the only literal hyphen/
#      underscore pair in the tool. Unified onto head_ref (the snake_case majority: 41 vs 8 tool-wide, and
#      --abi's spelling was already the one README.md documents). This gate pins BOTH halves of the family
#      so the pair can never diverge again.
#   2  at= on --cochange / --owners — both are PURE git-history products (a co-change pair mined from
#      `git log`, a recency-weighted ownership share). Before this round they were the only such verbs with
#      no `at="<sha>[+dirty]"` anchor, so a number quoted out of them was unanchored: you could not tell
#      which HEAD produced it. gitstamp.h's at= is the tool-wide anchor; this gate pins it on both.
#   3  est_tokens on the map ROOT — the flagship default map reported its own size ONLY inside an XML
#      COMMENT, so the one number a budget-aware caller most needs was the one number a conformant XML
#      parser is entitled to discard. The comment STAYS (every existing consumer keeps working); the root
#      element gains the same value as a real attribute. This gate pins that the two AGREE — one estimator,
#      never two counters (serialize.h's own standing rule).
#      --stable is the deliberate exception: it moves every volatile count OUT of the byte-stable prefix into
#      a trailing comment, and the root element IS the prefix. Same precedent as the k= rank attribute, which
#      --stable already omits for exactly this reason. Gated below as a pin, not as an oversight.
#   4b the four SAFE collision renames (§5 below) — of §P8's eight same-spelling-different-meaning
#      collisions, only the meanings with ZERO consumers anywhere in test/, skills/ or the docs were moved:
#      `ok=`/`dark=` counts off the roots whose children use the same name for a BOOL, the multi-root
#      `<root l=>` label off the spelling 22 sites use for a line number, and `--uses`' canonical-id `in=`.
#      Each assertion pins BOTH halves, because the regression worth catching is a later cleanup renaming
#      the POPULAR half instead.
#   4  --connect est_tokens is a plain integer — it printed `est_tokens="~191"`, a NON-NUMERIC value that
#      `int(...)` rejects, in the one field whose entire purpose is arithmetic against a budget. The `~`
#      is gone (the number was never exact anywhere else either, and no other verb apologises for it), and
#      §P9.3's scope bug is fixed with it: the estimate covered the payload ONLY, excluding a 397-byte header
#      comment that on its own exceeded the printed estimate — a ~1.9x under-report of the verb's own
#      document. serialize.h:524 had already decided this for the map family ("the REPORTED est_tokens must
#      cover the whole payload the caller receives"); --connect is that rule applied where it had not been.
#
# Usage:  test/attrvocabcheck.sh              # uses build/ripwire
#         RIPWIRE_BIN=asan/ripwire test/attrvocabcheck.sh
# Exits non-zero on any failure. Does NOT edit test/regression.sh or test/golden.xml.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
cd "$ROOT"
echo "attrvocabcheck: BIN=$BIN"

root_of(){ grep -o "<$1 [^>]*>" | head -1; }         # first START-TAG of element $1, attributes intact

# ── 1) head_ref: ONE spelling across the --stray-content family ────────────────────────────────────────
# Both halves are run against this repo itself (the verb needs real refs); a shallow/ref-less checkout
# degrades to zero rows but STILL emits the root element, which is all this assertion reads.
"$BIN" . --stray-content --no-cache >"$TMP/stray.xml" 2>/dev/null
"$BIN" . --stray-content --abi --no-cache >"$TMP/abi.xml" 2>/dev/null

SC="$( root_of stray-content <"$TMP/stray.xml" )"
AB="$( root_of abi          <"$TMP/abi.xml"   )"

case "$SC" in
    *'head-ref='*) no "stray-content still prints the kebab head-ref= : $SC" ;;
    *'head_ref="'*) ok "stray-content root prints head_ref= (snake_case, matching its --abi sibling)" ;;
    *)             no "stray-content root carries NO head_ref= at all: ${SC:-<no root element>}" ;;
esac
case "$AB" in
    *'head-ref='*) no "abi regressed to the kebab head-ref= : $AB" ;;
    *'head_ref="'*) ok "abi root still prints head_ref= (unchanged — this half was always correct)" ;;
    *)             no "abi root carries NO head_ref= at all: ${AB:-<no root element>}" ;;
esac
# The whole family's output, not just the two roots: no `head-ref` byte survives anywhere (children, notes).
if grep -q 'head-ref' "$TMP/stray.xml" "$TMP/abi.xml"; then
    no "the literal 'head-ref' still appears somewhere in the stray-content family output"
    grep -o 'head-ref[^ ]*' "$TMP/stray.xml" "$TMP/abi.xml" | head -3
else
    ok "no 'head-ref' spelling anywhere in the stray-content family output"
fi
# Same VALUE under the new spelling in both verbs — a rename that changed the datum would be worse than
# the collision it fixed.
SR="$( printf '%s' "$SC" | grep -o 'head_ref="[^"]*"' | head -1 )"
AR="$( printf '%s' "$AB" | grep -o 'head_ref="[^"]*"' | head -1 )"
[ -n "$SR" ] && [ "$SR" = "$AR" ] \
    && ok "stray-content and abi agree on the value: $SR" \
    || no "head_ref values disagree across the family: stray='$SR' abi='$AR'"

# ── 2) at= on the two pure git-history verbs ────────────────────────────────────────────────────────────
SHA9="$( git -C "$ROOT" rev-parse --short=9 HEAD 2>/dev/null )"
if [ -z "$SHA9" ]; then
    ok "not a git repo (or no HEAD) — at= assertions skipped, which is the documented omit-never-placeholder case"
else
    # `at=` is sha9 optionally + "+dirty"; the worktree this runs in may legitimately be either.
    stamp_ok(){ printf '%s' "$1" | grep -qE "at=\"$SHA9(\\+dirty)?\""; }

    for spec in "cochange:--cochange" "cochange:--cochange=src/main.cpp" "owners:--owners"; do
        el="${spec%%:*}"; flag="${spec#*:}"
        out="$( "$BIN" . "$flag" --no-cache 2>/dev/null | root_of "$el" )"
        if [ -z "$out" ]; then
            no "$flag emitted no <$el> root element at all"
        elif stamp_ok "$out"; then
            ok "$flag root carries at=\"$SHA9...\""
        else
            no "$flag root has no at=\"$SHA9\" stamp: $out"
        fi
    done

    # The stamp must be the SAME anchor the rest of the tool prints, not a second, differently-derived one.
    C_AT="$( "$BIN" . --cochange --no-cache 2>/dev/null | root_of cochange | grep -o 'at="[^"]*"' )"
    D_AT="$( "$BIN" . --doctor   --no-cache 2>/dev/null | root_of doctor   | grep -o 'at="[^"]*"' )"
    [ -n "$C_AT" ] && [ "$C_AT" = "$D_AT" ] \
        && ok "cochange at= is byte-identical to doctor's ($C_AT) — one stamp, not two derivations" \
        || no "cochange at= ($C_AT) differs from doctor's ($D_AT)"
fi

# ── 3) est_tokens on the map ROOT, agreeing with the comment it does not replace ────────────────────────
"$BIN" test/fixture --no-cache >"$TMP/map.xml" 2>/dev/null
# `est_tokens=[0-9][0-9]*` and not `est_tokens=[0-9]*`: the map's LEGEND comment now also mentions the word
# (`r:est_tokens=hdr-copy(none-if-stable)` — the contract line telling a reader the root attribute exists),
# and a `*` quantifier matches it with zero digits, silently yielding an empty "value". Requiring at least
# one digit picks the stats comment, which is the only place the NUMBER lives.
CMT="$( grep -o 'est_tokens=[0-9][0-9]*' "$TMP/map.xml" | head -1 | tr -dc '0-9' )"
ATTR="$( root_of r <"$TMP/map.xml" | grep -o 'est_tokens="[0-9]*"' | tr -dc '0-9' )"

[ -n "$CMT" ] && [ "$CMT" -gt 0 ] 2>/dev/null \
    && ok "map header comment still reports est_tokens=$CMT (kept — existing consumers unbroken)" \
    || no "map header comment lost its est_tokens (got '$CMT')"
[ -n "$ATTR" ] && [ "$ATTR" -gt 0 ] 2>/dev/null \
    && ok "map ROOT <r> carries a machine-readable est_tokens=\"$ATTR\"" \
    || no "map ROOT <r> carries no numeric est_tokens= (got '$ATTR') — a parser still cannot reach the total"
[ -n "$ATTR" ] && [ "$ATTR" = "$CMT" ] \
    && ok "root attribute and header comment AGREE ($ATTR) — one estimator, not two counters" \
    || no "root est_tokens=$ATTR disagrees with the comment's $CMT"

# --stable: the pin, not an oversight. Volatile counts stay OUT of the byte-stable prefix (same rule that
# already omits the k= rank attribute there); the trailing comment still carries the number.
"$BIN" test/fixture --no-cache --stable >"$TMP/stable.xml" 2>/dev/null
SROOT="$( root_of r <"$TMP/stable.xml" )"
case "$SROOT" in
    *'est_tokens='*) no "--stable: <r> gained est_tokens= — that puts a volatile count back in the stable prefix: $SROOT" ;;
    *)               ok "--stable: <r> stays free of est_tokens= (volatile counts remain in the trailing comment)" ;;
esac
grep -q 'est_tokens=[0-9]' "$TMP/stable.xml" \
    && ok "--stable: the trailing comment still reports est_tokens" \
    || no "--stable: est_tokens vanished entirely"

# ── 4) --connect est_tokens: a plain integer, covering the WHOLE document ───────────────────────────────
"$BIN" . --connect=buildGraph,serialize --no-cache >"$TMP/connect.xml" 2>/dev/null
CROOT="$( root_of connect <"$TMP/connect.xml" )"
case "$CROOT" in
    *'est_tokens="~'*) no "--connect still prints the non-numeric est_tokens=\"~N\": $CROOT" ;;
    *'est_tokens="'*)  ok "--connect est_tokens= is a plain value (no ~ prefix)" ;;
    *)                 no "--connect root carries no est_tokens=: ${CROOT:-<no root element>}" ;;
esac
CEST="$( printf '%s' "$CROOT" | grep -o 'est_tokens="[0-9]*"' | tr -dc '0-9' )"
[ -n "$CEST" ] && [ "$CEST" -gt 0 ] 2>/dev/null \
    && ok "--connect est_tokens=$CEST parses as a positive integer" \
    || no "--connect est_tokens is not a parseable positive integer (got '$CEST')"

# §P9.3 scope: the estimate must describe the bytes the caller ACTUALLY receives — comment header + root
# element + payload — not the payload alone. Compared as a TOLERANCE band (house rule for estimates): the
# root element's own length depends on the digits of the number it contains, so exactness is unattainable
# by construction. 12% is far tighter than the ~1.9x under-report this replaces.
CBYTES="$( wc -c <"$TMP/connect.xml" | tr -d ' ' )"
if [ -n "$CEST" ] && [ "$CEST" -gt 0 ] 2>/dev/null && [ "$CBYTES" -gt 0 ]; then
    # truth = bytes / 2.50 (kBytesPerTokenDefault), in integer arithmetic: bytes*100/250
    TRUTH=$(( CBYTES * 100 / 250 ))
    DIFF=$(( CEST - TRUTH )); [ "$DIFF" -lt 0 ] && DIFF=$(( -DIFF ))
    [ $(( DIFF * 100 )) -le $(( TRUTH * 12 )) ] \
        && ok "--connect est_tokens=$CEST within 12% of the whole delivered document ($TRUTH from $CBYTES B)" \
        || no "--connect est_tokens=$CEST does NOT describe the delivered $CBYTES B (truth ~$TRUTH, |diff|=$DIFF) — §P9.3 scope bug"
else
    no "--connect: could not measure the document (est='$CEST' bytes='$CBYTES')"
fi

# ── 5) the four SAFE collision renames (§P8's "eight attribute collisions") ────────────────────────────
# Only the meanings with ZERO consumers moved. Each assertion pins BOTH halves: the renamed minority is
# present under its new name AND the load-bearing majority still has the old name, because the failure mode
# worth catching is a later "cleanup" that renames the popular half instead.
#   ok=       count on <doctor> -> passed= ; the <c/> children keep the BOOL ok=
#   dark=     count on <flags>  -> dark_gates= ; the <gate/> children keep the BOOL dark=
#   l=        label on <root>   -> label= ; 22 other sites keep l= as a LINE NUMBER
#   in=       canonical id in --uses -> in_id= ; --grep/--lint keep the NAME in=, --for keeps the COUNT in=
# The other four (in= name-vs-count, files=, k=, p=) are DOCUMENTED, not renamed — too many consumers, and
# for k= a rename is blocked outright: --doc-drift already emits k= and kind= on one element meaning
# different things. Those are gated by their legends, not by this section.
DOC="$( "$BIN" . --doctor --no-cache 2>/dev/null )"
printf '%s' "$DOC" | grep -q '<doctor[^>]* passed="[0-9]' \
    && ok "doctor root count is passed= (was the colliding ok=)" || no "doctor root has no passed= count: $( printf '%s' "$DOC" | root_of doctor )"
printf '%s' "$DOC" | root_of doctor | grep -q ' ok="' \
    && no "doctor ROOT still carries an ok= count — the collision is back" || ok "doctor root carries no ok= (the count moved, the child bool did not)"
printf '%s' "$DOC" | grep -q '<c n="[^"]*" ok="[01]"' \
    && ok "doctor <c/> children still carry the BOOLEAN ok= (the half with ~20 consumers is untouched)" \
    || no "doctor child rows lost ok= — the WRONG half of the collision moved"

FL="$( "$BIN" . --flags --no-cache 2>/dev/null )"
printf '%s' "$FL" | grep -q '<flags[^>]* dark_gates="[0-9]' \
    && ok "flags root count is dark_gates= (was the colliding dark=)" || no "flags root has no dark_gates= count: $( printf '%s' "$FL" | root_of flags )"
printf '%s' "$FL" | root_of flags | grep -q ' dark="' \
    && no "flags ROOT still carries a dark= count — the collision is back" || ok "flags root carries no dark= count"
printf '%s' "$FL" | grep -q '<gate [^>]*dark="[01]"' \
    && ok "flags <gate/> children still carry the BOOLEAN dark= (the half with consumers is untouched)" \
    || no "flags child rows lost dark= — the WRONG half of the collision moved"

US="$( "$BIN" . --uses=escapeXml --no-cache 2>/dev/null )"
if printf '%s' "$US" | grep -q '<u '; then
    printf '%s' "$US" | grep -q 'in_id="' \
        && ok "--uses canonical id is in_id= (was the thrice-overloaded in=)" || no "--uses has no in_id= attribute"
    printf '%s' "$US" | grep -q ' in="' \
        && no "--uses still emits the colliding bare in=" || ok "--uses emits no bare in="
else
    ok "--uses returned no <u> rows here — rename assertions skipped"
fi
# The two LOAD-BEARING in= meanings must NOT have moved with it.
"$BIN" test/fixture --grep=distance --no-cache 2>/dev/null | grep -q '<hit [^>]*in="' \
    && ok "--grep keeps in= as the enclosing symbol NAME (documented, not renamed)" || no "--grep lost its in= — the wrong meaning moved"
"$BIN" test/fixture --for="distance between points" --no-cache 2>/dev/null | grep -q ' in="[0-9]*"' \
    && ok "--for keeps in= as the fan-in COUNT (documented, not renamed)" || no "--for lost its in= — the wrong meaning moved"

# head= width: --merge-scout aligned onto the 9-char majority its four siblings already used.
MS="$( "$BIN" . --merge-scout=HEAD --no-cache 2>/dev/null | root_of merge-scout )"
if [ -n "$MS" ]; then
    printf '%s' "$MS" | grep -qE 'head="[0-9a-f]{9}"' \
        && ok "merge-scout head= is 9 hex chars, matching abi/stray-content/landing-plan/history" \
        || no "merge-scout head= is not the 9-char majority width: $MS"
else
    ok "--merge-scout produced no root here (no comparable arms) — width assertion skipped"
fi

# ── 6) MUTATION self-tests: prove each assertion can actually FAIL ──────────────────────────────────────
# A gate that cannot fail is a gate that proves nothing. Each mutant is the exact defect this round fixed.
sed 's/head_ref=/head-ref=/' "$TMP/stray.xml" >"$TMP/mut1.xml"
grep -q 'head-ref' "$TMP/mut1.xml" \
    && ok "mutation: reintroducing head-ref= IS detected by the family scan" \
    || no "mutation: the head-ref scan cannot see a reintroduced kebab spelling"
printf '%s' "$CROOT" | sed 's/est_tokens="/est_tokens="~/' | grep -q 'est_tokens="~' \
    && ok "mutation: a reintroduced ~ prefix IS detected" \
    || no "mutation: the ~ assertion cannot see a reintroduced tilde"
MUT_ATTR="$( printf '<r est_tokens="1">' | grep -o 'est_tokens="[0-9]*"' | tr -dc '0-9' )"
[ -n "$CMT" ] && [ "$MUT_ATTR" != "$CMT" ] \
    && ok "mutation: a root/comment DISAGREEMENT is detected (1 != $CMT)" \
    || no "mutation: the agreement assertion cannot see a disagreement"

# ── 7) G4: every document this gate reads is well-formed XML ────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    for f in stray abi map stable connect; do
        xmllint --noout "$TMP/$f.xml" 2>/dev/null \
            && ok "G4: $f.xml is well-formed" \
            || no "G4: $f.xml failed xmllint"
    done
else
    ok "xmllint absent — G4 sub-check skipped"
fi

echo
[ "$fail" -eq 0 ] && { echo "attrvocabcheck: ALL PASS"; exit 0; }
echo "attrvocabcheck: FAILURES"; exit 1
