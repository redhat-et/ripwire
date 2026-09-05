#!/usr/bin/env bash
# substrfiltercheck.sh — H7 (capture-audit 2026-09-04, lens 6 F9, lens 7 F-DYM-1): a SCOPING FILTER that
# selects nothing refuses; it never reports the empty selection as a measurement of the repo.
#
# THE DEFECT. `--flags=zzzznosuch` answered `<flags gates="0" dark_gates="0" … files="1550">` at exit 0, and
# `--stray-content=zzzznosuchref` answered `<stray-content refs="0" … unknown="0">` at exit 0. Both zeros
# read identically to the true and interesting facts "this repo has no dark gates" and "no branch carries
# stray work" — which is exactly the reading an agent takes, because the root even carries the scan
# denominator (files="1550", 189 refs scanned) to prove the sweep really ran. Two of their siblings had
# already been fixed and carry the wording this gate pins:
#
#   --dead-code=nosuchdir → "matches no indexed path — a zero here would be a failure, not a measurement"
#   --doc-drift=zzz       → "matches no document — an exit 0 under a filter that owns nothing is a failure"
#   --scope=zzz/**        → "matches no indexed path — an exit 0 under a scope that owns nothing is a failure"
#
# THE FAMILY. A `--verb=SUBSTR` scoping filter is a verb whose argument NARROWS what the verb would
# otherwise sweep repo-wide (the bare spelling runs everything). Enumerated from the flag table: --dead-code,
# --doc-drift, --scope, --flags, --stray-content. All five are asserted here; --dead-code / --doc-drift /
# --scope pass before and after, and are in the gate because the property is the family's, not the two
# broken members'.
#
# NOT in the family, deliberately, and each for a stated reason:
#   --grep=STR / --regex   a literal text scan over file bytes IS the measurement; hits="0" is its answer.
#   --for / --recall       ranked queries whose every name resolved; they disclose reason="no_candidates".
#   --exclude=GLOB         a SUBTRACTIVE filter — matching nothing is a no-op, not an empty selection.
#
# ARM D covers the same standing rule on the text-selector side (lens 6 F5): `--whereis=<one-edit typo>`
# answered hits="0" with no did-you-mean while every other symbol verb one keystroke away offers one, and
# `--whereis=@src/graph.h:999999` searched the literal string "@src/graph.h:999999" across every blob
# instead of resolving the documented @FILE:LINE seed grammar the sibling selectors resolve.
#
# RED-FIRST (base binary ec5e3c3): A/B fail on --flags and --stray-content, D fails on both whereis arms.
#
# Usage:  bash test/substrfiltercheck.sh [BIN]   |   RIPWIRE_BIN=build_base/ripwire bash test/…
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "substrfiltercheck: BIN=$BIN  CORPUS=$ROOT"

MISS="zzzznosuchfilterxyz"

# R3 (verify-wave1): the --stray-content probes run against a THROWAWAY repo with a known `lane/probe` ref
# (test/lib/strayfixture.sh), never against this checkout — `lives --stray-content lane` on the operator's own
# branches was green only where a lane/* head happened to exist. refuses_empty/lives take the corpus from
# $CORPUS, which defaults to this repo and is pointed at the fixture for that one flag.
. "$ROOT/test/lib/strayfixture.sh"
SFIX="$( mktemp -d )"; trap 'rm -rf "$SFIX"' EXIT
mkStrayFixture "$SFIX"
strayFixtureHasRef "$SFIX" \
    && ok "fixture: throwaway repo carries a lane/* ref for --stray-content=lane to select" \
    || { no "fixture: no lane/* ref in the throwaway repo — the --stray-content arms below would prove nothing"; echo "FAILURES ABOVE"; exit 1; }
CORPUS="$ROOT"

# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== A/B: a scoping filter that owns nothing REFUSES, naming the flag and the value ==="
# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
refuses_empty(){ # $1 = flag, $2 = value, $3.. = the host verb, when the filter is a modifier rather than a verb
    local flag="$1" val="$2"; shift 2
    local out rc
    out="$( "$BIN" "$CORPUS" "$flag=$val" "$@" --no-cache 2>&1 1>/dev/null )"; rc=$?
    if [ "$rc" -ne 0 ]; then
        ok "A $flag=$val → exit $rc"
    else
        no "A $flag=$val → exit 0 — an empty SELECTION was reported as a measurement of the repo"
    fi
    if printf '%s' "$out" | grep -qF -- "$flag" && printf '%s' "$out" | grep -qF -- "$val"; then
        ok "B $flag: refusal names the flag and echoes the value"
    else
        no "B $flag: refusal names neither flag nor value: $out"
    fi
    if printf '%s' "$out" | grep -qiE "not a (measurement|clean tree)|is a failure"; then
        ok "C $flag: says WHY a zero would not have been an answer"
    else
        no "C $flag: no 'a zero here would be a failure' clause (the wording --dead-code/--doc-drift set): $out"
    fi
}
refuses_empty --dead-code     "$MISS"
refuses_empty --doc-drift     "$MISS"
refuses_empty --scope         "$MISS/**" --quality-delta   # a MODIFIER, so it is probed on its host verb
refuses_empty --flags         "$MISS"
CORPUS="$SFIX" refuses_empty --stray-content "$MISS"
# wave-3 close (2026-09-05): --stray-content=SUBSTR is also the FILTER of two host verbs, --plan and --abi. Both
# already refused a no-match filter (exit 1) but with the WRONG sentence — "more than 512 refs match — narrow it"
# for a filter that matched ZERO refs (the zero-hit case fell into the else of a two-way ok/nonGitRoot split;
# only the bare verb had H7's branch). Found by the close regen: `--stray-content=r27 --plan` on a tree with no
# r27 ref. RED on 41d831b: B (the value is not echoed) and C (no "not a measurement" clause) for both hosts.
CORPUS="$SFIX" refuses_empty --stray-content "$MISS" --plan
CORPUS="$SFIX" refuses_empty --stray-content "$MISS" --abi

# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== the negative: a filter that DOES own something still answers ==="
# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
lives(){ # $1 = flag, $2 = value, $3.. = host verb / expected-exit override
    local flag="$1" val="$2"; shift 2
    local rc
    "$BIN" "$CORPUS" "$flag=$val" "$@" --no-cache >/dev/null 2>&1; rc=$?
    # --quality-delta's own exit code is its gate (2 = gating findings), so only the REFUSAL code is a failure
    if [ "$rc" -eq 0 ] || [ "$rc" -eq 2 ]; then
        ok "$flag=$val → exit $rc (a real selection still answers)"
    else
        no "$flag=$val → exit $rc; the refusal swallowed a working filter"
    fi
}
lives --dead-code     src
lives --doc-drift     README
lives --scope         'src/**' --quality-delta
lives --flags         RIPWIRE
CORPUS="$SFIX" lives --stray-content lane
CORPUS="$SFIX" lives --stray-content lane --plan
CORPUS="$SFIX" lives --stray-content lane --abi

# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== D: --whereis is a SYM selector — near-miss suggestion + @FILE:LINE seed resolution ==="
# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
# --whereis scans every ref's TREE, so it would find this script's own text if the probes ran against this
# repo: the typo below is a literal in this file, and the repo IS the corpus. A throwaway git fixture keeps
# the arm about the verb instead of about the gate.
WFIX="$( mktemp -d )"
printf 'int helperOne( int x ) { return x + 1; }\nint sturdyTeleport( int x ) { return helperOne( x ); }\nint tailer( int x ) { return sturdyTeleport( x ); }\n' > "$WFIX/one.cpp"
( cd "$WFIX" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm init ) >/dev/null 2>&1

# (a) a one-edit typo of an indexed symbol names it. The lexical tree scan is a legitimate measurement for a
#     name this repo never had, so the ZERO stays an answer — but the index knows the near-miss and every
#     other SYM verb says so, and a hits="0" the reader cannot distinguish from a typo is worth one clause.
OUT="$( "$BIN" "$WFIX" --whereis=sturdyTeleporr --no-cache 2>&1 )"
if printf '%s' "$OUT" | grep -qE "did you mean 'sturdyTeleport'|retry=\"sturdyTeleport\""; then
    ok "D --whereis=<one-edit typo> names the near-miss sturdyTeleport"
else
    no "D --whereis=<one-edit typo>: hits=0 with no did-you-mean, and the index knows the name: $( printf '%s' "$OUT" | grep -o '<whereis [^>]*>' )"
fi

# (b) the documented @FILE:LINE seed grammar is RESOLVED, not searched as a literal. A bad line refuses with
#     the shared seed message (--owners/--mentions/--edit-check already do); it must never come back as a
#     true-but-useless hits="0" over every blob.
OUT="$( "$BIN" "$WFIX" '--whereis=@one.cpp:999999' --no-cache 2>&1 1>/dev/null )"; RC=$?
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -qF "one.cpp"; then
    ok "D --whereis=@one.cpp:999999 refuses on the bad line, naming the file"
else
    no "D --whereis=@one.cpp:999999 → exit $RC; the seed was searched as a literal string instead of resolved: $OUT"
fi

# (c) a REAL @FILE:LINE seed resolves to the enclosing definition and is answered under that name.
OUT="$( "$BIN" "$WFIX" '--whereis=@one.cpp:2' --no-cache 2>/dev/null )"
if printf '%s' "$OUT" | grep -qF 'sym="sturdyTeleport"'; then
    ok "D --whereis=@one.cpp:2 resolves to sym=\"sturdyTeleport\""
else
    no "D --whereis=@one.cpp:2 did not resolve the seed: $( printf '%s' "$OUT" | grep -o '<whereis [^>]*>' )"
fi
rm -rf "$WFIX"

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
