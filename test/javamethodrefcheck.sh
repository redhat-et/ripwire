#!/usr/bin/env bash
# javamethodrefcheck.sh — recall + precision gate for issue #74.
#
# The pinned grammar gives a simple type and a variable the same receiver node,
# so the resolver must prove the receiver is a repository type before minting a call.
#
# Maintainer (joyful-ii-V-I, 2026-09-10 on #74): land the two-method contrast as a
# test/*check.sh that is RED first, asserting that the lambda form and the reference
# form yield the *same* caller set — not just a bigger number.
#
# Fixture carries the issue's pair, verbatim:
#   lambda:           item -> Util.conv(item)     inside convLambda
#   method reference: Util::conv                  inside convMethodRef
# and the same contrast a second time on a type with four same-named defs
# (Widget.makeFn), which is what makes the TARGET assertions below possible.
#
# WHAT THIS GATE ASSERTS (and what it refuses to assert):
#   - the caller SET of conv is exactly {convLambda, convMethodRef}
#   - NOT "count went from 1 to 2" (a count-only arm stays green if a third
#     unrelated caller appears, or if both names vanish and something else
#     fills the quota)
#   - the lambda arm is asserted first, so an empty extraction cannot read as
#     "same set" (CONTRIBUTING.md §2 shape 3: empty equals agreement)
#   - the TARGET, not just the caller: --callers=Widget.java:makeFn and
#     --callers=Outer.java:makeFn name the def each reference resolved to.
#     `makeFn` has four defs, so a name-wide caller set cannot tell a correct
#     edge from one the bare-name ladder handed to the caller's own file
#   - both spellings are still WRITTEN in the fixture source (V5 presence
#     guard: deleting the method-ref line would otherwise satisfy an absence)
#   - a REFUSAL is not an empty set: every extraction helper below reports the
#     binary's exit status and any JSON parse failure as its own token, so an
#     arm expecting "" cannot pass on a binary that never ran
#
# MUTATION (CONTRIBUTING.md §2 rule 1–2): rewrite Util::conv → Util::convX in
# a scratch copy, assert the rewrite took, then re-extract --callers=conv.
# The caller set MUST change. On unmodified main it does not — the method-ref
# site was never an edge — so this arm is RED for the same hole, not green
# by vacuity.
#
# Registration owed on a real commit: add javamethodrefcheck to the alphabetical
# `for _g in` list in test/regression.sh (after javarubycheck). test/manifestcheck.sh
# fails a committed top-level *check.sh that is missing from that list. Re-derive
# the published gate count from the loop (docs/gatecount_build.py), never carry it.
#
# Usage:  RIPWIRE_BIN=/path/to/ripwire bash test/javamethodrefcheck.sh
# Exit:   0 = clean · 1 = an arm failed · 2 = usage / missing prerequisite

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/javamethodreffix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }
[ -f "$FIX/A.java" ] && [ -f "$FIX/Widget.java" ] && [ -f "$FIX/Outer.java" ] \
    && [ -f "$FIX/Util.java" ] && [ -f "$FIX/Builder.java" ] \
    || { echo "fixture files missing under $FIX"; exit 2; }

echo "javamethodrefcheck: BIN=$BIN  FIX=$FIX"

# ── fixture presence (source text, never tool output) ─────────────────────────
for spelling in \
    'item -> Widget.makeFn(item)' 'Widget::makeFn' 'Outer.Inner::makeFn' \
    'Widget::<Object>makeFn' 'com.example.Widget::pkgFn' \
    'widget::instanceFn' 'widget::makeFn' 'Widget::instanceFn' \
    'this::thisFn' 'this::makeFn' 'super::superFn' 'super::makeFn' 'Widget::new' \
    'Widget::localShadowFn' 'Widget::fieldShadowFn' \
    'Widget::afterLocalFn' 'Widget::siblingFn' \
    'Outer.Inner::nestedInnerFn' 'Outer.Inner::leadingShadowFn' \
    'Widget -> Widget::lambdaInfFn' '(Widget) -> Widget::lambdaParenFn' \
    'Widget::nestedInnerFn' 'item -> Util.conv(item)' 'Util::conv' \
    'catch (RuntimeException Widget)' 'Widget::catchShadowFn' 'Widget::catchAfterFn' \
    'for (RuntimeException Widget : errors)' 'Widget::forEachShadowFn' 'Widget::forEachAfterFn' \
    'try (AutoCloseable Widget = null)' 'Widget::resourceShadowFn' 'Widget::resourceAfterFn' \
    'b.name(name)'; do
    grep -qF "$spelling" "$FIX/A.java" \
        && ok "fixture still spells $spelling" \
        || no "fixture no longer spells $spelling — the matrix is vacuous"
done
grep -qF 'builderChain(Builder b, String name)' "$FIX/A.java" \
    && ok "fixture still declares a parameter named like Builder's method" \
    || no "fixture no longer shadows name at builderChain — the r9 arm is vacuous"
grep -qF 'Object Inner = null' "$FIX/A.java" \
    && ok "fixture still declares an unrelated local named Inner" \
    || no "fixture no longer declares local Inner — nested-segment shadow is vacuous"
grep -qF 'Outer Outer = null' "$FIX/A.java" \
    && ok "fixture still declares a leading-segment local named Outer" \
    || no "fixture no longer declares local Outer — leading-segment shadow is vacuous"

# ── extract caller / use-site sets ────────────────────────────────────────────
# JSON --callers: one name per callers[].n. SET comparison, never a count.
#
# THREE OUTCOMES, KEPT APART. "the symbol resolved and nothing calls it" is a different fact from
# "the binary refused" and from "the binary printed something that is not JSON", and this helper
# used to spell all three as the empty string: the pipeline's status was python's, python exited 2
# on a parse failure, and every call site swallowed that with `|| got=""`. Half the arms below
# expect exactly "", so the gate passed on a binary that could not run at all — and `widget`, a
# receiver identifier the fixture never defines, is an arm whose real answer IS a refusal. Each
# failure now carries its own token, which can never equal a caller set.
callers_set() {
    local out rc
    out="$( "$BIN" "$1" --no-cache --callers="$2" --json 2>/dev/null )"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        printf 'ERR:exit%s\n' "$rc"
        return 0
    fi
    # every failure prints a token of its own, the python process's included: a traceback prints
    # nothing on stdout, and an empty stdout is exactly what an expected-empty caller set reads as
    printf '%s' "$out" | python3 -c '
import json, sys
raw = sys.stdin.read()
try:
    obj = json.loads(raw)
except Exception:
    print("ERR:json"); sys.exit(0)
rows = obj.get("callers") if isinstance(obj, dict) else None
if not isinstance(rows, list) or not all(isinstance(row, dict) for row in rows):
    print("ERR:shape"); sys.exit(0)
names = sorted({ row["n"] for row in rows if isinstance(row.get("n"), str) and row["n"] })
print(" ".join(names))
' || printf 'ERR:python\n'
}

# --uses in_id values for role=call sites of a named symbol (default XML). Same taxonomy: a refusal
# or an unreadable document is a token of its own, never an empty id list.
uses_in_ids() {
    local out rc
    out="$( "$BIN" "$1" --no-cache --uses="$2" 2>/dev/null )"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        printf 'ERR:exit%s\n' "$rc"
        return 0
    fi
    # the document is PARSED before an id is read: a substring match accepted malformed XML whose text
    # merely contained `<uses ` and some in_id="…"
    printf '%s' "$out" | python3 -c '
import sys, xml.etree.ElementTree as ET
try:
    root = ET.fromstring(sys.stdin.read())
except ET.ParseError:
    print("ERR:xml"); sys.exit(0)
if root.tag != "uses":
    print("ERR:shape"); sys.exit(0)
ids = sorted({ e.get("in_id") for e in root.iter() if e.get("in_id") })
print(" ".join(ids))
' || printf 'ERR:python\n'
}

# MUTATION CONTROL for both helpers (CodeRabbit on #281): a stub binary answers with documents that parse but
# are the wrong shape, or do not parse at all. Each must come back as an ERR: token, never as an id or name list
# an expected-empty assertion could accept. The stub replaces $BIN only inside this block.
helper_controls() {
    local stub="$TMP/stubbin" realBin="$BIN" got
    for doc in '{"callers": 5}' '{"callers": [7]}' '[1, 2]'; do
        printf '#!/bin/sh\nprintf %%s %s\n' "'$doc'" >"$stub"; chmod +x "$stub"; BIN="$stub"
        got="$( callers_set "$FIX" makeFn )"
        case "$got" in ERR:*) ok "control: callers_set refuses $doc as [$got]" ;; *) no "control: callers_set accepted $doc as [$got]" ;; esac
    done
    for doc in '<uses in_id="typeMethod"' '<callers in_id="typeMethod"/>'; do
        printf '#!/bin/sh\nprintf %%s %s\n' "'$doc'" >"$stub"; chmod +x "$stub"; BIN="$stub"
        got="$( uses_in_ids "$FIX" makeFn )"
        case "$got" in ERR:*) ok "control: uses_in_ids refuses $doc as [$got]" ;; *) no "control: uses_in_ids accepted $doc as [$got]" ;; esac
    done
    BIN="$realBin"
}
helper_controls

contains_id() {
    case " $1 " in
        *" $2 "*) return 0 ;;
        *) return 1 ;;
    esac
}

expect_callers() {
    local symbol="$1" expected="$2" got
    got="$(callers_set "$FIX" "$symbol")"
    echo "callers_set($symbol) = [$got]"
    [ "$got" = "$expected" ] \
        && ok "$symbol caller set is exactly [$expected]" \
        || no "$symbol caller set expected [$expected], got [$got]"
}

# A name the corpus never DEFINES cannot have an empty caller set — the verb refuses it. Asserting
# "" for such a name is the failure mode item 5 names: the refusal and the empty answer read alike.
expect_refusal() {
    local symbol="$1" out rc
    out="$( "$BIN" "$FIX" --no-cache --callers="$symbol" --json 2>&1 )"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        no "--callers=$symbol exited 0 — a name with no definition must refuse, not answer"
        return 0
    fi
    case "$out" in
        *"not found"*) ok "--callers=$symbol refuses (exit $rc, 'not found'), which is not an empty set" ;;
        *)             no "--callers=$symbol exited $rc but said [$out] — expected a 'not found' refusal" ;;
    esac
}

# The issue's own pair, asserted first and on a name with ONE def, so the agreement
# between the two spellings is read before any target narrowing enters the picture.
expect_callers conv "convLambda convMethodRef"

# Recall: lambda and each statically typed method-reference form reach makeFn;
# same-name expression/this/super controls below must not enlarge this set.
expect_callers makeFn "genericTypeMethod lambdaForm nestedTypeMethod typeMethod"

# TARGETS, not just callers. `makeFn` has four definitions (A, Base, Widget, Outer.Inner), so the
# set above is satisfied by an edge pointing anywhere — and before the receiver-resolution fix every
# one of these references landed on the caller's own file's A.makeFn, via the bare-name ladder and
# the locality tie-break. Each reference must resolve to the member of the type it named.
# FE-B (test/receiverevidencecheck.sh): the lambda's INVOCATION `Widget.makeFn( item )` is a class-name receiver, so it
# resolves to Widget's member too — it used to land on A.makeFn by the same file-locality pin the references had.
expect_callers Widget.java:makeFn "genericTypeMethod lambdaForm typeMethod"
expect_callers Outer.java:makeFn "nestedTypeMethod"

# The r9 shadow pass is C++/ObjC evidence. A Java call never resolves to a local, so a parameter
# spelled like the method being called cannot delete the call — `b.name(name)` keeps its edge.
expect_callers name "builderChain"

# Package-qualified type receiver (grammar: field_access, last segment is the class).
expect_callers pkgFn "packageQualified"

# Nested type whose trailing segment is an unrelated local name: Inner is not the
# receiver. Leading Outer is the type, so the site must still resolve.
# This set is also the "member the proven type does not declare" assertion: typeMissingMember writes
# `Widget::nestedInnerFn`, Widget declares no such member, and a fall-back to the bare name would
# add typeMissingMember here — Outer.Inner's definition acquiring a caller by spelling alone.
expect_callers nestedInnerFn "nestedInnerLocal"

# A local named Outer *is* the leading receiver: expression Outer.Inner, not a type.
expect_callers leadingShadowFn ""

# Lexical shadowing: a local after the site, or in a sibling block, is not in
# scope at the method-reference. A local before the site, a parameter, a class
# field, and an inferred lambda parameter are.
expect_callers afterLocalFn "localDeclaredAfter"
expect_callers siblingFn "siblingBlockLocal"
expect_callers localShadowFn ""
expect_callers fieldShadowFn ""
expect_callers lambdaInfFn ""
expect_callers lambdaParenFn ""

# A catch parameter, an enhanced-for variable and a try-with-resources resource shadow the type inside
# their own clause, loop or statement, and only there (CodeRabbit on #281: none of the three emitted a
# declaration, so all three references resolved as the class). The references after each scope closes
# are the controls: a span widened to the enclosing block would empty those sets too.
expect_callers catchShadowFn ""
expect_callers forEachShadowFn ""
expect_callers resourceShadowFn ""
expect_callers catchAfterFn "catchShadowedTypeName"
expect_callers forEachAfterFn "enhancedForShadowedTypeName"
expect_callers resourceAfterFn "resourceShadowedTypeName"

# Precision: expression receivers and constructors mint no ordinary call edge.
expect_callers instanceFn ""
expect_callers thisFn ""
expect_callers superFn ""
expect_callers Widget ""

# The receiver identifier itself is not the call target — and `widget` is not a definition either,
# so the honest answer is a refusal, not an empty caller set.
expect_refusal widget

# ── mutation: rewrite the method-ref spelling; the caller set MUST move ───────
MUT="$TMP/mut"
mkdir -p "$MUT"
cp "$FIX/Widget.java" "$MUT/Widget.java"
cp "$FIX/Outer.java" "$MUT/Outer.java"
cp "$FIX/Util.java" "$MUT/Util.java"
cp "$FIX/Builder.java" "$MUT/Builder.java"
# leave the lambda site intact; only the Type::method spelling changes
sed 's/Widget::makeFn/Widget::missingFn/' "$FIX/A.java" >"$MUT/A.java"
grep -qF 'map(Widget::missingFn)' "$MUT/A.java" && ! grep -qF 'map(Widget::makeFn)' "$MUT/A.java" \
    && ok "mutation took: Widget::makeFn -> Widget::missingFn (lambda site untouched)" \
    || no "mutation did not take — refusing to trust the post-mutation extraction"
grep -qF 'item -> Widget.makeFn(item)' "$MUT/A.java" \
    && ok "mutation left the lambda spelling intact" \
    || no "mutation accidentally rewrote the lambda site"

S1="$( callers_set "$MUT" makeFn )"
echo "callers_set(makeFn) after mutation = [${S1}]"

[ "$S1" = "genericTypeMethod lambdaForm nestedTypeMethod" ] \
    && ok "mutating Widget::makeFn removes only typeMethod" \
    || no "mutation expected [genericTypeMethod lambdaForm nestedTypeMethod], got [$S1]"

# The target-level twin: Widget.makeFn keeps only the generic spelling, and `Widget::missingFn`
# names no definition anywhere, so it produces no edge rather than one to a plausible neighbour.
S2="$( callers_set "$MUT" Widget.java:makeFn )"
echo "callers_set(Widget.java:makeFn) after mutation = [${S2}]"
[ "$S2" = "genericTypeMethod lambdaForm" ] \
    && ok "mutation leaves Widget.java:makeFn with genericTypeMethod and the untouched lambda invocation (FE-B: a class-name receiver)" \
    || no "mutation expected Widget.java:makeFn = [genericTypeMethod lambdaForm], got [$S2]"
S3="$( callers_set "$MUT" Outer.java:makeFn )"
[ "$S3" = "nestedTypeMethod" ] \
    && ok "mutation leaves Outer.java:makeFn untouched (nestedTypeMethod)" \
    || no "mutation expected Outer.java:makeFn = [nestedTypeMethod], got [$S3]"

# An id list must be an id list. A "does NOT contain X" arm is satisfied by a refusal token just as
# well as by a correct extraction, so the taxonomy has to be checked before the arms that read it.
ids_readable() {
    case "$1" in
        ERR:*) no "$2 did not produce an id list: [$1]"; return 1 ;;
        *)     return 0 ;;
    esac
}

# --uses=makeFn must name the Type::method callers (not just well-formed XML).
U0="$( uses_in_ids "$FIX" makeFn )"
echo "uses_in_ids(makeFn) = [${U0}]"
if ids_readable "$U0" "--uses=makeFn"; then
    for id in typeMethod nestedTypeMethod genericTypeMethod lambdaForm; do
        contains_id "$U0" "$id" \
            && ok "--uses=makeFn includes $id" \
            || no "--uses=makeFn missing $id (got [$U0])"
    done
fi

# The r9 regression in use-site form: `b.name(name)` is a row of --uses=name, not a deleted site.
UN="$( uses_in_ids "$FIX" name )"
echo "uses_in_ids(name) = [${UN}]"
if ids_readable "$UN" "--uses=name"; then
    contains_id "$UN" builderChain \
        && ok "--uses=name includes builderChain (shadow suppression does not reach Java)" \
        || no "--uses=name missing builderChain (got [$UN])"
fi

U1="$( uses_in_ids "$MUT" makeFn )"
echo "uses_in_ids(makeFn) after mutation = [${U1}]"
if ids_readable "$U1" "--uses=makeFn (mutated)"; then
    contains_id "$U1" typeMethod \
        && no "mutation still lists typeMethod in --uses=makeFn (got [$U1])" \
        || ok "mutating Widget::makeFn drops typeMethod from --uses=makeFn"
    for id in nestedTypeMethod genericTypeMethod lambdaForm; do
        contains_id "$U1" "$id" \
            && ok "mutation kept $id in --uses=makeFn" \
            || no "mutation dropped $id from --uses=makeFn (got [$U1])"
    done
fi

# ── determinism on the unmodified fixture ─────────────────────────────────────
A="$( "$BIN" "$FIX" --no-cache --callers=makeFn --json 2>/dev/null || true )"
B="$( "$BIN" "$FIX" --no-cache --callers=makeFn --json 2>/dev/null || true )"
[ -n "$A" ] && [ "$A" = "$B" ] \
    && ok "determinism: --callers=makeFn --json byte-identical across two runs" \
    || no "determinism: --callers=makeFn --json differed or was empty"

if command -v xmllint >/dev/null 2>&1; then
    "$BIN" "$FIX" --no-cache --uses=makeFn 2>/dev/null | xmllint --noout - 2>/dev/null \
        && ok "xml well-formed: --uses=makeFn" \
        || no "xml malformed: --uses=makeFn"
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
