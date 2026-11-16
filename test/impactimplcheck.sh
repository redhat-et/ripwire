#!/usr/bin/env bash
# impactimplcheck.sh — IMPL-TIER: --impact on an interface, trait, abstract or virtual member names its
# IMPLEMENTORS, because those are what a signature change breaks.
#
# --impact walks the transitive CALLERS of the definitions it matched. When the selector resolves to a
# bodyless or virtual member, the implementors are not callers and so were absent from the radius: on the
# 2026-11-15 file-grain gold set, --impact recovered 24.2 % of the required files on dispatch-through-
# indirection targets against 94.0 % on concrete ones (docs/EVALS.md, "the implementor tier").
#
# The tier is METHOD-scoped and OWNER-scoped, and the fixture is built to catch both mistakes:
#   (A) CommandRunner::StartCommand (pure virtual, 2 implementors in runners.cc) names them, labelled.
#   (B) Hollow::hollowRun is pure virtual with NO implementor of Hollow, while Unrelated and Unrelated2
#       define their own hollowRun. A join by bare NAME pulls those two in; the tier must name NEITHER.
#   (C) DryRunCommandRunner also declares StartCommand( Edge*, int ) — an overload. The tier names the
#       implementing method, and the arity-mismatched overload is not a second claim about the same edge.
#   (D) SoloBase::soloRun has exactly one implementor: the one-implementor case still labels its row.
#   (E) a concrete free function's answer is BYTE-IDENTICAL: the tier is absent, not empty.
#   (F) the JSON dialect carries the same count as the XML one (no dialect can disagree about what was
#       measured — ImpactView is one computation, three renderings).
#
# RED-FIRST: every arm except (E) and the premise arms FAILS on main 0217049f2, where --impact has no
# implementor tier at all. (E) passes there and must keep passing.
#
# Usage: test/impactimplcheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "impactimplcheck: BIN=$BIN"
CPP="$ROOT/test/ifacedispatchfix/cpp"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

imp(){ "$BIN" "$CPP" --impact="$1" --no-cache --legend=compact 2>&1; }

# ── premise: the fixture is the one these arms describe (it fails if the fixture changes under them) ──
pv=0
grep -q "virtual bool StartCommand( Edge\* edge ) = 0;" "$CPP/runner.h" || { no "(P1) the fixture's StartCommand is no longer pure virtual"; pv=1; }
[ "$( grep -c 'StartCommand( Edge\* edge ) override' "$CPP/runners.cc" )" = 2 ] || { no "(P2) the fixture no longer has exactly 2 StartCommand implementors"; pv=1; }
grep -q "struct Unrelated$" "$CPP/runners.cc" && grep -q "int hollowRun() { return 1; }" "$CPP/runners.cc" \
    || { no "(P3) the fixture's unrelated hollowRun collision is gone — arm (B) would pass vacuously"; pv=1; }
[ "$pv" = 0 ] && ok "(P) the fixture states the premise every arm below reads"

# ── (A) the implementors of a pure virtual are named, and labelled ───────────────────────────────────
A="$( imp CommandRunner.StartCommand )"
printf '%s' "$A" | grep -q 'via="implementor"' \
    && ok "(A1) --impact on a pure virtual carries labelled implementor rows" \
    || no "(A1) --impact=CommandRunner.StartCommand has no via=\"implementor\" row"
printf '%s' "$A" | grep -q 'runners.cc' \
    && ok "(A2) the implementors' file is named" \
    || no "(A2) runners.cc (both StartCommand implementors) is not named at all"
printf '%s' "$A" | grep -qE 'implementors="[1-9]' \
    && ok "(A3) the header discloses how many implementors the tier names" \
    || no "(A3) no implementors= count on the root — the tier must be counted, not silent"
# the rows are a DIFFERENT relation from the reach set: an implementor row is never an <s> row
printf '%s' "$A" | grep -oE '<s [^>]*via="implementor"[^>]*>' | grep -q . \
    && no "(A4) an implementor is rendered as an <s> reach row — it is not a caller" \
    || ok "(A4) implementor rows are not mixed into the <s> reach set"

# ── (B) the name-collision adversary: Hollow has no implementor, two unrelated classes share the name ─
B="$( imp Hollow.hollowRun )"
printf '%s' "$B" | grep -q 'Unrelated' \
    && no "(B1) Unrelated/Unrelated2 named for Hollow.hollowRun — the join read the NAME, not the implementors" \
    || ok "(B1) a same-named method on an unrelated class is not an implementor"
printf '%s' "$B" | grep -qE 'implementors="[1-9]' \
    && no "(B2) implementors= is non-zero for a pure virtual nothing implements" \
    || ok "(B2) no implementor count where nothing implements the owner"

# ── (C)/(D) one implementor, and an overload is not a second claim ───────────────────────────────────
D="$( imp SoloBase.soloRun )"
printf '%s' "$D" | grep -q 'via="implementor"' && printf '%s' "$D" | grep -q 'runners.cc' \
    && ok "(D1) the single-implementor case is labelled and named" \
    || no "(D1) SoloBase.soloRun names no labelled implementor"

# ── (C) an OVERLOAD is not an override, and a declaration+definition pair is ONE method ──────────────
# DryRunCommandRunner declares StartCommand( Edge* ) and StartCommand( Edge*, int ); RealCommandRunner
# declares StartCommand at runners.cc:5 and defines it at :9. The honest answer to "what breaks if I
# change StartCommand( Edge* )" is two methods, not four: the arity-mismatched overload is a different
# contract, and a decl/def pair is one thing to change.
ac="$( printf '%s' "$A" | grep -oE 'implementors="[0-9]+"' | head -1 | tr -dc '0-9' )"
[ "$ac" = 2 ] \
    && ok "(C1) implementors=2 — the overload and the decl/def duplicate are both excluded" \
    || no "(C1) implementors=$ac, expected 2: an arity-mismatched overload or a decl/def pair is being counted"
printf '%s' "$A" | grep -q '<impl [^>]*p="runners.cc:9"' \
    && ok "(C2) the pair collapses to the BODIED definition (runners.cc:9)" \
    || no "(C2) runners.cc:9, the bodied definition, is not the row kept for that implementor"
printf '%s' "$A" | grep -q '<impl [^>]*p="runners.cc:5"' \
    && no "(C3) runners.cc:5, the declaration of a method defined at :9, is counted as its own implementor" \
    || ok "(C3) the declaration half of a decl/def pair is not a second row"
printf '%s' "$A" | grep -q '<impl [^>]*p="runners.cc:18"' \
    && no "(C4) StartCommand( Edge*, int ) is named — an overload is not an override" \
    || ok "(C4) the arity-mismatched overload is not an implementor of this contract"

# ── (E) a concrete free function: the tier is ABSENT, and the answer is byte-identical to no-tier ─────
E="$( imp byPointer )"
printf '%s' "$E" | grep -q 'via="implementor"\|implementors=' \
    && no "(E1) a concrete free function's answer grew an implementor tier" \
    || ok "(E1) no implementor tier where the selector names no bodyless member"

# ── (F) dialect parity: XML and JSON agree on the count ──────────────────────────────────────────────
xc="$( printf '%s' "$A" | grep -oE 'implementors="[0-9]+"' | head -1 | tr -dc '0-9' )"
jc="$( "$BIN" "$CPP" --impact=CommandRunner.StartCommand --json --no-cache 2>/dev/null | grep -oE '"implementors":[0-9]+' | head -1 | tr -dc '0-9' )"
[ -n "$xc" ] && [ "$xc" = "$jc" ] \
    && ok "(F1) XML and JSON report the same implementor count ($xc)" \
    || no "(F1) implementor count disagrees across dialects — XML '$xc', JSON '$jc'"

[ "$fail" = 0 ] && echo "impactimplcheck: ALL PASS" || echo "impactimplcheck: FAILURES"
exit "$fail"
