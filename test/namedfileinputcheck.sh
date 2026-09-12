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
# WHY THE SPLIT IS "CANNOT BE READ AS AN INDEX", NOT "IS NOT USABLE". A SCIP index that has bytes and fails to
# DECODE is a different fact: the file the caller named exists, and degrading to name-based (byte-identically,
# with the alert) is the robustness contract the fuzz arm of scipcheck.sh depends on. Arms A-D assert the open()
# failure — the case where nothing the caller named was ever read. scipcheck.sh arm 5 (corrupt index) still
# pins the degrade; its arm 5b (MISSING index) is re-pinned to the refusal in the same commit. OWNER DECISION
# 2026-09-12 moved the line one step: an EMPTY file, a DIRECTORY and any other path that is not a regular file (a
# FIFO, a device) hold nothing that could be read as an index at all, so each is the same caller mistake as a
# missing path and refuses too (arm F).
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
#   F  --scip only: a path that cannot be read as an index at all — an empty file, a directory, a FIFO, a
#      device — refuses: exit 1, the reason right after the flag and path ("is empty" / "is a directory" /
#      "is not a regular file"), nothing on stdout, no degrade log. Every F refusal run is bounded at 20 s: a
#      FIFO with no writer blocks a plain open() for ever, and a hang must FAIL as a hang rather than stall the
#      gate. Contrast: a 1-byte file (one byte from empty) is a corrupt index and still degrades at exit 0; a
#      valid index still overlays. F MECHANISM (structural): the probe closes its descriptor and scipReadFile opens
#      the path again, so that open is pinned on its own — one ::open carrying O_NONBLOCK, S_ISREG tested on an
#      ::fstat of that descriptor before any read, no fopen. A path swapped after the probe is a race no run here
#      can hold, so the pin is on the source.
#
# RED-FIRST (base binary ec5e3c3): A/B/C/D fail on --scip and --cache, C fails on --scan-skill and
# --scan-skills, D fails on --scan-skill.
# RED-FIRST for F (base binary 8c805661): both refusal rows failed all four checks — exit 0, the name-based map on
# stdout, "[math degraded] --scip: index missing or unreadable" and "cannot read index … proceeding name-based" on
# stderr. The presence guard and both contrasts passed there, as they must.
# RED-FIRST for the FIFO and device rows (base binary 1d9d1aa6): the FIFO run HUNG — the probe's fopen blocked waiting
# for a writer, killed at 20 s (exit 124 under GNU timeout, 142 under the perl-alarm fallback); /dev/null failed all four
# checks — exit 0, 2338 B of name-based map on stdout, "[math degraded] --scip: index missing or unreadable" on stderr.
# The empty-file, directory and contrast rows passed there.
# RED-FIRST for the F MECHANISM rows (source and both binaries at 58a33819): m1, m2 and m3 failed — scipReadFile opened
# the path with a plain std::fopen, with no ::open, no ::fstat and no S_ISREG; the extraction row passed. 66 PASS / 3 FAIL
# on the plain and the ASan binary alike.
#
# Usage:  bash test/namedfileinputcheck.sh [BIN]
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/fixture"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
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

# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== F: --scip=<empty file|directory|FIFO|device> refuses — none of them can be read as an index ==="
# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
# OWNER DECISION 2026-09-12. The empty file, the directory and the device pass A-D's open() probe, so they used to
# reach loadScipOverlay's "cannot read index … proceeding name-based" and serve the name-based map at exit 0 — the
# M7 defect one step later. The FIFO (no writer, ever) never got that far: a plain open() of it blocks for ever.
# The two rows after the refusals are the contrast: a ONE-byte file differs from the empty one by exactly one
# byte and is a corrupt index (degrade, exit 0), and a valid index still overlays.
SCIPFIX="$ROOT/test/scipfix"
: > "$TMP/empty.scip"
printf 'x' > "$TMP/onebyte.scip"
mkdir -p "$TMP/scipdir"
mkfifo "$TMP/pipe.scip"
[ -f "$TMP/empty.scip" ] && [ "$( wc -c <"$TMP/empty.scip" | tr -d ' ' )" -eq 0 ] && [ "$( wc -c <"$TMP/onebyte.scip" | tr -d ' ' )" -eq 1 ] \
  && [ -d "$TMP/scipdir" ] && [ -p "$TMP/pipe.scip" ] && [ -c /dev/null ] && [ -s "$SCIPFIX/index.scip" ] \
  && ok "F presence: a 0-byte file, a 1-byte file, a directory, a FIFO, the /dev/null character device and the scipfix index all exist" \
  || no "F presence: a fixture is missing — the F rows below would prove nothing"

# GNU timeout exits 124 when it kills the run; a runner without coreutils takes the house perl-alarm idiom, whose
# SIGALRM death is 142.
bounded_run(){ if command -v timeout >/dev/null 2>&1; then timeout 20 "$@"; else perl -e 'alarm 20; exec @ARGV' "$@"; fi; }

refuses_unreadable_scip(){ # $1 = label, $2 = the path, $3 = the reason the refusal must state right after the flag and path
    local label="$1" path="$2" reason="$3" rc
    bounded_run "$BIN" "$FIX" "--scip=$path" --no-cache >"$TMP/f.out" 2>"$TMP/f.err"; rc=$?
    if [ "$rc" -eq 124 ] || [ "$rc" -eq 142 ]; then
        # a killed run wrote nothing, so the stdout and degrade-log rows below would PASS on silence — report the hang alone
        no "F --scip=<$label>: HUNG — killed after 20 s (exit $rc), expected the refusal code 1"
        return
    fi
    if [ "$rc" -eq 1 ]; then ok "F --scip=<$label>: exit 1"; else no "F --scip=<$label>: exit $rc, expected the refusal code 1"; fi
    if grep -qF -- "--scip=$path: $reason" "$TMP/f.err"; then
        ok "F --scip=<$label>: the refusal names the flag, echoes the path and says it $reason"
    else
        no "F --scip=<$label>: stderr never says '--scip=<path>: $reason': $( cat "$TMP/f.err" )"
    fi
    if [ -s "$TMP/f.out" ]; then
        no "F --scip=<$label>: $( wc -c <"$TMP/f.out" | tr -d ' ' ) B on stdout — a refusal serves no map"
    else
        ok "F --scip=<$label>: stdout empty (no map served)"
    fi
    if grep -qF '[math degraded]' "$TMP/f.err"; then
        no "F --scip=<$label>: an internal degrade log in a refusal (nothing degraded — the run refused): $( cat "$TMP/f.err" )"
    else
        ok "F --scip=<$label>: no internal degrade log in a refusal"
    fi
}
refuses_unreadable_scip "empty file" "$TMP/empty.scip" "is empty"
refuses_unreadable_scip "directory"  "$TMP/scipdir"    "is a directory"
refuses_unreadable_scip "FIFO"       "$TMP/pipe.scip"  "is not a regular file"
refuses_unreadable_scip "device"     "/dev/null"       "is not a regular file"

"$BIN" "$FIX" --scip="$TMP/onebyte.scip" --no-cache >"$TMP/f1.out" 2>"$TMP/f1.err"; rc=$?
[ "$rc" -eq 0 ] && [ -s "$TMP/f1.out" ] && grep -qF 'corrupt or truncated index' "$TMP/f1.err" \
  && ok "F contrast: a 1-byte --scip file (one byte from empty) is a corrupt index — warns, serves the map, exit 0" \
  || no "F contrast: a 1-byte --scip file should degrade as corrupt at exit 0 with a map; got exit $rc, $( wc -c <"$TMP/f1.out" | tr -d ' ' ) B, stderr: $( cat "$TMP/f1.err" )"

"$BIN" "$SCIPFIX" --scip="$SCIPFIX/index.scip" --exclude=make_index.py --no-cache >"$TMP/fv.out" 2>"$TMP/fv.err"; rc=$?
[ "$rc" -eq 0 ] && grep -qF 'prov="scip"' "$TMP/fv.out" \
  && ok "F contrast: a valid index still overlays (exit 0, prov=\"scip\" on stdout)" \
  || no "F contrast: the valid scipfix index did not overlay: exit $rc, stderr: $( cat "$TMP/fv.err" )"

# ── F MECHANISM: the load's own open, which the probe cannot cover ─────────────────────────────────────────────────────────
# The probe above closes its descriptor, and loadScipOverlay's scipReadFile (src/scip.h) then opens the path a second time,
# so whatever is at the path by then reaches that open unprobed. With a plain fopen there, a FIFO put at the path after the
# probe blocked the run waiting for a writer. No user-reachable caller reaches scipReadFile without the probe (dispatchMain
# is loadScipOverlay's one caller, after the refusal), and the swap is a race across the whole crawl with no point a gate
# can hold it at, so no run here can reach that open deterministically. These rows pin the MECHANISM instead, as
# sidecarsymlinkcheck.sh (f) does, on scipReadFile's code with every // comment stripped: its one ::open carries O_NONBLOCK,
# S_ISREG is tested on an ::fstat of THAT descriptor before anything reads it, and fopen is gone from it.
scip_read_mechanism(){
    local code="$TMP/scipreadfile_code.txt" openLines fdVar regLine readLine
    awk '/^inline std::vector<std::uint8_t> scipReadFile\(/ { inFn = 1 } inFn { print } inFn && /^}/ { exit }' "$ROOT/src/scip.h" \
      | sed -E 's#//.*$##' >"$code"
    if ! grep -q 'scipReadFile(' "$code" || ! grep -q '^}' "$code"; then
        # an empty extraction would PASS the fopen row on silence — report the missing body alone
        no "F mechanism: scipReadFile's body could not be extracted from src/scip.h — the rows below would prove nothing"
        return
    fi
    ok "F mechanism: scipReadFile's body extracted from src/scip.h ($( grep -c '[^[:space:]]' "$code" | tr -d ' ' ) non-blank code lines)"

    openLines="$( grep -c '::open(' "$code" | tr -d ' ' )"
    if [ "$openLines" = "1" ] && grep '::open(' "$code" | grep -q 'O_NONBLOCK'; then
        ok "F mechanism (m1): scipReadFile opens the path once, with an ::open carrying O_NONBLOCK — a FIFO there returns at once"
    else
        no "F mechanism (m1): expected exactly one ::open carrying O_NONBLOCK in scipReadFile, found $openLines: $( grep -E 'open\(' "$code" | tr -s ' ' | head -c 200 )"
    fi

    fdVar="$( sed -n -E 's/.*[^A-Za-z0-9_]([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*::open\(.*/\1/p' "$code" | head -1 )"
    regLine="$( grep -n 'S_ISREG' "$code" | head -1 | cut -d: -f1 )"
    readLine="$( grep -n -E 'fdopen\(|fread\(|::read\(' "$code" | head -1 | cut -d: -f1 )"
    if [ -n "$fdVar" ] && grep -q -E "::fstat\([[:space:]]*$fdVar[[:space:]]*," "$code" \
       && [ -n "$regLine" ] && [ -n "$readLine" ] && [ "$regLine" -lt "$readLine" ]; then
        ok "F mechanism (m2): S_ISREG is tested on ::fstat( $fdVar, … ) — the opened descriptor — before anything reads it"
    else
        no "F mechanism (m2): expected S_ISREG on an ::fstat of the ::open's descriptor before the first read (descriptor '${fdVar:-none}', S_ISREG line ${regLine:-none}, first read line ${readLine:-none})"
    fi

    if grep -q 'fopen(' "$code"; then
        no "F mechanism (m3): scipReadFile still calls fopen, which blocks on a FIFO waiting for a writer: $( grep 'fopen(' "$code" | tr -s ' ' | head -c 160 )"
    else
        ok "F mechanism (m3): no fopen left in scipReadFile — the path is opened once, by the non-blocking ::open"
    fi
}
scip_read_mechanism

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
