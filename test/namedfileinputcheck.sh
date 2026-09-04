#!/usr/bin/env bash
# namedfileinputcheck.sh — M7 (capture-audit 2026-09-04, lens 6 F6/F20/F21): a file the USER NAMED that
# cannot be opened is a REFUSAL. Degrade-and-continue is reserved for the inputs the tool discovered itself.
#
# THE DEFECT, two members of one family:
#   --scip=nosuch.scip   → "[math degraded] … proceeding name-based" on stderr, the NAME-BASED map on stdout,
#                          exit 0. The caller asked for the PRECISION overlay by an explicit path and got the
#                          answer they were trying to improve on, under a warning no pipeline reads.
#   --cache=/nonexistent/dir/x.bin → the map is served, exit 0, and the named path is never written: every
#                          subsequent run pays a cold parse while believing it has a cache.
# Their eight siblings — --from-trace --batch --arch --plan-lint --lint-rules --with-profile --edit-plan
# --scan-skill(s) — all refuse the same shape of mistake. That is the asymmetry, not a policy.
#
# WHY THE SPLIT IS "CANNOT BE OPENED", NOT "IS NOT USABLE". A SCIP index that opens and fails to DECODE is a
# different fact: the file the caller named exists, and degrading to name-based (byte-identically, with the
# alert) is the robustness contract the fuzz arm of scipcheck.sh depends on. This gate asserts only the
# open() failure — the case where nothing the caller named was ever read. scipcheck.sh arm 5 (corrupt index)
# still pins the degrade; its arm 5b (MISSING index) is re-pinned to the refusal in the same commit.
#
# ARMS
#   A  every user-named FILE/DIR input, given an unopenable path, exits NON-ZERO
#   B  ... naming the flag and echoing the path
#   C  ... with the house refusal code 1 — EXCEPT for a verb whose low exit codes are VERDICTS. Lens 6 F20
#      filed --scan-skill / --scan-skills exiting 3 as an outlier to normalize; reading skillscan.h says
#      otherwise and the gate records the reading: those two return 0/1/2 for clean/warn/critical
#      (skillScanExitCode), so refusing with 1 would report "this skill has warnings" for a path that was
#      never opened. 3 is the correct code there precisely BECAUSE no verdict uses it. The family rule is
#      therefore "a refusal never collides with a verdict code", and the per-verb expectation is spelled
#      out below rather than flattened to a single number.
#   D  ... and WITHOUT an internal "[math degraded]" diagnostic line. That log is the marker of a path that
#      CONTINUED in a reduced mode; printing it immediately before a refusal tells the reader the opposite of
#      what happened, and it leaked on --scip, --scan-skill and --cache.
#   E  the negative: a readable file of the same kind still works.
#
# RED-FIRST (base binary ec5e3c3): A/B/C/D fail on --scip and --cache, C fails on --scan-skill and
# --scan-skills, D fails on --scan-skill.
#
# Usage:  bash test/namedfileinputcheck.sh [BIN]
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/fixture"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "namedfileinputcheck: BIN=$BIN  FIX=$FIX"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
MISS="$TMP/no/such/dir/absent_input.dat"

# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== A-D: an unopenable USER-NAMED input refuses — flag + path, no verdict-code collision, no degrade log ==="
# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
refuses_unopenable(){ # $1 = flag, $2 = expected exit code, $3 = the full "flag=value" token, $4.. = host verb
    local flag="$1" want="$2" token="$3"; shift 3
    local out rc
    out="$( "$BIN" "$FIX" "$token" "$@" --no-cache 2>&1 1>/dev/null )"; rc=$?
    if [ "$rc" -ne 0 ]; then ok "A $flag: exit $rc"; else no "A $flag: exit 0 — a file the caller NAMED was silently skipped"; fi
    if printf '%s' "$out" | grep -qF -- "$flag" && printf '%s' "$out" | grep -qF -- "$MISS"; then
        ok "B $flag: refusal names the flag and echoes the path"
    else
        no "B $flag: refusal names neither flag nor path: $out"
    fi
    if [ "$rc" -eq "$want" ]; then ok "C $flag: exit $rc (the refusal code that collides with no verdict)"; else no "C $flag: exit $rc, expected $want"; fi
    if printf '%s' "$out" | grep -qF '[math degraded]'; then
        no "D $flag: an internal degrade log precedes the refusal (nothing degraded — the run refused): $out"
    else
        ok "D $flag: no internal degrade log in a refusal"
    fi
}
refuses_unopenable --scip 1 "--scip=$MISS"
refuses_unopenable --cache 1 "--cache=$MISS"
refuses_unopenable --from-trace 1 "--from-trace=$MISS"
refuses_unopenable --batch 1 "--batch=$MISS"
refuses_unopenable --arch 1 "--arch=$MISS"
refuses_unopenable --plan-lint 1 "--plan-lint=$MISS"
refuses_unopenable --lint-rules 1 "--lint-rules=$MISS"
refuses_unopenable --with-profile 1 "--with-profile=$MISS" --lint
refuses_unopenable --edit-plan 1 "--edit-plan=$MISS" --dry-run
refuses_unopenable --scan-skill 3 "--scan-skill=$MISS"
refuses_unopenable --scan-skills 3 "--scan-skills=$MISS"

# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== E: the negative — a usable path of the same kind still works ==="
# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
"$BIN" "$FIX" "--cache=$TMP/warm.ripwirecache" >/dev/null 2>&1 \
  && [ -s "$TMP/warm.ripwirecache" ] \
  && ok "E --cache=<writable path> serves the map AND writes the cache" \
  || no "E --cache=<writable path> did not produce a cache at the named path"

# a SCIP index that opens but does not decode keeps the documented degrade (scipcheck.sh arm 5 owns the
# byte-identity half; this only asserts the two failures are still told apart).
printf 'not a scip index at all\n' > "$TMP/corrupt.scip"
"$BIN" "$FIX" --scip="$TMP/corrupt.scip" --no-cache >/dev/null 2>&1 \
  && ok "E --scip=<unparseable but readable> still degrades at exit 0 (a different fact from cannot-open)" \
  || no "E --scip=<unparseable but readable> refused — the corrupt-index degrade contract was widened too far"

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
