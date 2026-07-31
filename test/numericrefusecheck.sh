#!/usr/bin/env bash
# numericrefusecheck.sh — §B8 gate: the numeric flag arms refuse in the SAME dialect as everything else,
# and --connect-radius refuses its two out-of-range directions SYMMETRICALLY.
#
# §B8.2 (PLAN_outputAudit3_2026-07-29.md): ten hand-written numeric arms answered EVERY bad value with one
# fixed sentence — no echo of what was actually passed, no example — while refusePageValue (one function
# away) and the 24 compliant kViewFlags rows do both:
#
#     ripwire … --zoom=          →  "ripwire: --zoom needs a positive integer depth"     (before)
#     ripwire … --zoom=zzq       →  "ripwire: --zoom needs a positive integer depth"     (byte-identical)
#     ripwire … --limit=zzq      →  "ripwire: --limit needs a positive integer — got 'zzq', e.g. --limit=100"
#
# Two dialects for one error class: the caller of the first cannot tell an unset shell variable from a typo
# without re-reading its own command line. §B8.1: `--connect-radius=0` refused loudly while `=13/999999`
# SILENTLY clamped to 12 at exit 0 — the out-of-range direction the user is more likely to hit was the
# invisible one, and the low-side refusal's "(clamped to 1..12)" parenthetical described the accept-side
# behaviour it was not attached to.
#
# §B8.2 verifier finding N4 (W2FIX-CLI, 2026-07-29): the first pass migrated nine arms and left six behind
# on the SAME --help screen — --around-depth=/--around-fanout=/--partition=/--plan-lanes= (now kIntFlags
# rows) and --token-budget=/--max-file-size= (kept hand-written because their member is a std::size_t BYTE
# COUNT with a N[K|M|G] suffix grammar an `int Config::*` table row cannot hold without narrowing it — same
# reasoning as --pack-budget-bytes — but routed through the shared refuseFlagValue() so the SENTENCE, not
# the accept grammar, joined the dialect). All fifteen numeric arms are covered below.
#
# What this gate pins is the CONTRACT (the wording is free to improve): every arm echoes the offending
# value, names its domain, shows a runnable example, and answers empty and garbage DIFFERENTLY — plus both
# ends of --connect-radius' range refuse, the in-range ends still work, and the two byte-size arms still
# accept their K/M/G suffix forms untouched.
#
#   bash test/numericrefusecheck.sh                                     # build/ripwire
#   bash test/numericrefusecheck.sh build_base/ripwire                  # must FAIL (pre-fix binary)
#   RIPWIRE_BIN=asan/ripwire bash test/numericrefusecheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative binary
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
cd "$ROOT"
[ -d test/fixture ] || { echo "no test/fixture corpus — this gate cannot run"; exit 2; }
echo "numericrefusecheck: BIN=$BIN"

# ── the plain-positive-int §B8.2 numeric arms (thirteen of fifteen) ───────────────────────────────────
# --connect-radius carries the --connect= it modifies so the run reaches the verb it belongs to; every
# other arm stands alone. GARBAGE is 'zzq' (never a number in any base) and EMPTY is the unset-variable
# shape the class was found through. The refusal path runs at parse time, before validateConfig's
# cross-flag guards, so none of the four W2FIX-CLI arrivals (--around-depth/--around-fanout/--partition/
# --plan-lanes) need a companion flag to REACH their refusal — only their ACCEPT-side spot check below does.
NUMERIC="--zoom --connect-radius --max-tokens --top-k --pack-top-n --pack-budget-bytes --detail --grep-before --grep-after --grep-context --around-depth --around-fanout --partition --plan-lanes"

extra(){ case "$1" in --connect-radius) printf '%s' "--connect=perimeter,distance" ;; *) printf '' ;; esac; }

for f in $NUMERIC; do
    X="$( extra "$f" )"
    # shellcheck disable=SC2086
    "$BIN" test/fixture "$f=" $X >"$TMP/o.empty" 2>"$TMP/e.empty"; rce=$?
    # shellcheck disable=SC2086
    "$BIN" test/fixture "$f=zzq" $X >"$TMP/o.garb" 2>"$TMP/e.garb"; rcg=$?

    [ "$rce" -eq 1 ] && ok "$f= (empty) exits 1"     || no "$f= (empty) exits $rce (expected 1)"
    [ "$rcg" -eq 1 ] && ok "$f=zzq (garbage) exits 1" || no "$f=zzq (garbage) exits $rcg (expected 1)"

    grep -q "got ''"    "$TMP/e.empty" && ok "$f= echoes the empty value it got" \
                                       || no "$f= does not echo got '': [$( head -c 160 "$TMP/e.empty" )]"
    grep -q "got 'zzq'" "$TMP/e.garb"  && ok "$f=zzq echoes the offending value" \
                                       || no "$f=zzq does not echo got 'zzq': [$( head -c 160 "$TMP/e.garb" )]"
    grep -q "e\.g\. $f=" "$TMP/e.garb" && ok "$f refusal shows a runnable $f= example" \
                                       || no "$f refusal carries no runnable example: [$( head -c 160 "$TMP/e.garb" )]"
    cmp -s "$TMP/e.empty" "$TMP/e.garb" \
        && no "$f: empty and garbage produce a BYTE-IDENTICAL refusal — the caller cannot tell them apart" \
        || ok "$f: empty and garbage refusals differ (the value is in the message)"
done

# ── the two BYTE-SIZE arms (fourteenth and fifteenth of fifteen) ──────────────────────────────────────
# --token-budget and --max-file-size parse a std::size_t via parseByteSize's "N[K|M|G]" grammar, not
# parsePosInt — an int-typed kIntFlags row would silently narrow the accepted range, so both stay
# hand-written (§B8.2, same reasoning as --pack-budget-bytes) and only their REFUSAL sentence was routed
# through the shared refuseFlagValue(); the wanted-text must say "suffix", not "integer", or it would lie
# about its own grammar.
for f in --token-budget --max-file-size; do
    "$BIN" test/fixture "$f=" >"$TMP/o.empty" 2>"$TMP/e.empty"; rce=$?
    "$BIN" test/fixture "$f=zzq" >"$TMP/o.garb" 2>"$TMP/e.garb"; rcg=$?

    [ "$rce" -eq 1 ] && ok "$f= (empty) exits 1"     || no "$f= (empty) exits $rce (expected 1)"
    [ "$rcg" -eq 1 ] && ok "$f=zzq (garbage) exits 1" || no "$f=zzq (garbage) exits $rcg (expected 1)"

    grep -q "got ''"    "$TMP/e.empty" && ok "$f= echoes the empty value it got" \
                                       || no "$f= does not echo got '': [$( head -c 160 "$TMP/e.empty" )]"
    grep -q "got 'zzq'" "$TMP/e.garb"  && ok "$f=zzq echoes the offending value" \
                                       || no "$f=zzq does not echo got 'zzq': [$( head -c 160 "$TMP/e.garb" )]"
    grep -q "e\.g\. $f=" "$TMP/e.garb" && ok "$f refusal shows a runnable $f= example" \
                                       || no "$f refusal carries no runnable example: [$( head -c 160 "$TMP/e.garb" )]"
    grep -qi "suffix" "$TMP/e.garb"    && ok "$f wanted-text names the K/M/G suffix grammar, not a bare integer" \
                                       || no "$f wanted-text does not mention the suffix grammar it actually accepts: [$( head -c 160 "$TMP/e.garb" )]"
    cmp -s "$TMP/e.empty" "$TMP/e.garb" \
        && no "$f: empty and garbage produce a BYTE-IDENTICAL refusal — the caller cannot tell them apart" \
        || ok "$f: empty and garbage refusals differ (the value is in the message)"
done
# accept-side control: the suffix grammar itself must be untouched by the refusal-only change
"$BIN" test/fixture --token-budget=16000 --pack-task=t >/dev/null 2>"$TMP/e.tbp"
[ $? -eq 0 ] && ok "--token-budget=16000 (plain) still accepted" || no "--token-budget=16000 was refused: [$( head -c 160 "$TMP/e.tbp" )]"
"$BIN" test/fixture --token-budget=16K --pack-task=t >/dev/null 2>"$TMP/e.tbk"
[ $? -eq 0 ] && ok "--token-budget=16K (suffix) still accepted" || no "--token-budget=16K was refused: [$( head -c 160 "$TMP/e.tbk" )]"
"$BIN" test/fixture --max-file-size=4194304 >/dev/null 2>"$TMP/e.mfp"
[ $? -eq 0 ] && ok "--max-file-size=4194304 (plain) still accepted" || no "--max-file-size=4194304 was refused: [$( head -c 160 "$TMP/e.mfp" )]"
"$BIN" test/fixture --max-file-size=10MB >/dev/null 2>"$TMP/e.mfm"
[ $? -eq 0 ] && ok "--max-file-size=10MB (suffix) still accepted" || no "--max-file-size=10MB was refused: [$( head -c 160 "$TMP/e.mfm" )]"

# ── --path=SRC,DST' bare-arg-count path (the same class, one file over in main.cpp) ────────────────────
"$BIN" test/fixture --path=zzq >/dev/null 2>"$TMP/e.path"; rc=$?
[ "$rc" -eq 1 ] && ok "--path=zzq exits 1" || no "--path=zzq exits $rc (expected 1)"
grep -q "got 'zzq'" "$TMP/e.path" && ok "--path=zzq echoes the offending value" \
                                  || no "--path=zzq does not echo got 'zzq': [$( head -c 160 "$TMP/e.path" )]"
grep -q "e\.g\. --path=" "$TMP/e.path" && ok "--path=zzq refusal shows a runnable example" \
                                       || no "--path=zzq refusal carries no runnable example: [$( head -c 160 "$TMP/e.path" )]"
# its EMPTY form is the kViewFlags empty-value refusal (a different, already-compliant sentence): the two
# must still differ, which is the whole point of echoing the value.
"$BIN" test/fixture --path= >/dev/null 2>"$TMP/e.pathempty"; rc=$?
[ "$rc" -eq 1 ] && ok "--path= (empty) exits 1" || no "--path= (empty) exits $rc (expected 1)"
cmp -s "$TMP/e.path" "$TMP/e.pathempty" \
    && no "--path=: empty and garbage produce a BYTE-IDENTICAL refusal" \
    || ok "--path=: empty and garbage refusals differ"

# ── §B8.1 — --connect-radius refuses BOTH out-of-range directions, and says which range ─────────────────
for v in 0 -1 13 100 999999; do
    "$BIN" test/fixture "--connect-radius=$v" --connect=perimeter,distance >"$TMP/o.r" 2>"$TMP/e.r"; rc=$?
    [ "$rc" -eq 1 ] && ok "--connect-radius=$v refuses (exit 1)" \
                    || no "--connect-radius=$v exits $rc — an out-of-range radius that silently clamps is invisible in the output"
    [ -s "$TMP/o.r" ] && no "--connect-radius=$v still wrote a <connect> payload to stdout" \
                      || ok "--connect-radius=$v wrote nothing to stdout"
    grep -q "1\.\.12" "$TMP/e.r" && ok "--connect-radius=$v names the accepted range 1..12" \
                                 || no "--connect-radius=$v does not name the accepted range: [$( head -c 160 "$TMP/e.r" )]"
    grep -q "got '$v'" "$TMP/e.r" && ok "--connect-radius=$v echoes the value it got" \
                                  || no "--connect-radius=$v does not echo got '$v': [$( head -c 160 "$TMP/e.r" )]"
done
# the low-side message must stop describing the accept-side clamp it is not attached to
"$BIN" test/fixture --connect-radius=0 --connect=perimeter,distance >/dev/null 2>"$TMP/e.low"
grep -qi "clamped" "$TMP/e.low" \
    && no "--connect-radius=0 refusal still says 'clamped' — it describes behaviour that no longer happens" \
    || ok "--connect-radius=0 refusal no longer claims a clamp"
# and the two directions must read as ONE rule, not two policies
"$BIN" test/fixture --connect-radius=13 --connect=perimeter,distance >/dev/null 2>"$TMP/e.high"
lowtxt="$(  sed "s/'0'/'V'/"  "$TMP/e.low"  )"
hightxt="$( sed "s/'13'/'V'/" "$TMP/e.high" )"
[ "$lowtxt" = "$hightxt" ] && ok "--connect-radius: low and high refusals are the same sentence modulo the echoed value" \
                           || no "--connect-radius: low and high refusals are different sentences: [$lowtxt] vs [$hightxt]"

# ── the ACCEPT side is untouched: both ends of the range still run ─────────────────────────────────────
for v in 1 6 12; do
    "$BIN" test/fixture "--connect-radius=$v" --connect=perimeter,distance >"$TMP/o.acc" 2>"$TMP/e.acc"; rc=$?
    if [ "$rc" -eq 0 ] && grep -q "radius=\"$v\"" "$TMP/o.acc"; then
        ok "--connect-radius=$v is accepted and searched at radius=\"$v\""
    else
        no "--connect-radius=$v exits $rc without radius=\"$v\" — an in-range value was broken: [$( head -c 160 "$TMP/e.acc" )]"
    fi
done
# a sample of the other arms' accept side, so a refusal that swallowed every value cannot pass this gate
# --top-k=0 needs a payload verb to be a legal COMBINATION (validateConfig, unrelated to value parsing);
# pairing it with --pack-signatures keeps this assertion about the numeric arm and nothing else.
"$BIN" test/fixture --top-k=0 --pack-signatures >/dev/null 2>&1 && ok "--top-k=0 still accepted (0 = payload-only)" || no "--top-k=0 was refused"
"$BIN" test/fixture --detail=0 >/dev/null 2>&1 && ok "--detail=0 still accepted (0 = off)"        || no "--detail=0 was refused"
"$BIN" test/fixture --zoom=2   >/dev/null 2>&1 && ok "--zoom=2 still accepted"                    || no "--zoom=2 was refused"
"$BIN" test/fixture --grep=double --grep-context=2 >/dev/null 2>&1 && ok "--grep-context=2 still accepted" || no "--grep-context=2 was refused"
# the four W2FIX-CLI arrivals' accept side (each needs the companion flag its own guard requires)
"$BIN" test/fixture --around=perimeter --around-depth=3 --around-fanout=50 >/dev/null 2>&1 && ok "--around-depth=3/--around-fanout=50 still accepted" || no "--around-depth=3/--around-fanout=50 was refused"
"$BIN" test/fixture --pack-task=t --partition=4 >/dev/null 2>&1 && ok "--partition=4 still accepted" || no "--partition=4 was refused"
"$BIN" test/fixture --plan-lanes=3 --task="paint the tile" >/dev/null 2>&1 && ok "--plan-lanes=3 still accepted" || no "--plan-lanes=3 was refused"

# ── the reference dialect: --limit/--offset already do all of this (unchanged) ─────────────────────────
"$BIN" test/fixture --deps --limit=zzq >/dev/null 2>"$TMP/e.lim"
grep -q "got 'zzq'" "$TMP/e.lim" && grep -q "e\.g\. --limit=" "$TMP/e.lim" \
    && ok "reference: --limit=zzq still echoes the value and shows an example" \
    || no "reference: --limit=zzq lost its echo/example — the shared helper regressed: [$( head -c 160 "$TMP/e.lim" )]"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
