#!/usr/bin/env bash
# regexrefusecheck.sh — §P0.4 gate: an invalid --regex must REFUSE, never report a confident zero.
#
#   --regex='(fnv1a'    -> hits="0", exit 0, stderr EMPTY      (before)
#   --regex='fnv1a\w+'  -> a non-degenerate hit count, asserted as >= the narrower 'fnv1a64' probe
#
# An unbalanced paren or unterminated class was byte-identical to a true negative on every channel —
# stdout, exit code and stderr — which is the worst shape a false zero can take. The refusal must fire
# ahead of the trigram prefilter so that --no-prefilter refuses identically (the prefilter's own parse is
# allowed to degrade; only the VERIFIER's compile means "the user's pattern is invalid").
#
#   CTXPACK_BIN=build/ctxpack      bash test/regexrefusecheck.sh
#   CTXPACK_BIN=build_base/ctxpack bash test/regexrefusecheck.sh   # must FAIL (pre-fix binary)

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first"; exit 2; }
echo "regexrefusecheck: BIN=$BIN  ROOT=$ROOT"

# refuseCase <label> <extra flags…> -- the last argument is the pattern
refuseCase(){
    local label="$1"; shift
    "$BIN" "$ROOT" "$@" >"$TMP/out" 2>"$TMP/err"; local rc=$?
    [ "$rc" -eq 1 ] && ok "$label: exit 1" || no "$label: exit $rc (expected 1)"
    [ -s "$TMP/err" ] && ok "$label: stderr is not empty" || no "$label: stderr EMPTY (a silent refusal is still a false zero)"
    grep -q 'hits=' "$TMP/out" && no "$label: still printed a hits= element on stdout" || ok "$label: no hits= element on stdout"
}

refuseCase "--regex='(fnv1a'"                 --regex='(fnv1a'
refuseCase "--regex='fnv1a['"                 --regex='fnv1a['
refuseCase "--no-prefilter --regex='(fnv1a'"  --no-prefilter --regex='(fnv1a'

# the refusal must name the offending pattern, not just complain
"$BIN" "$ROOT" --regex='(fnv1a' >/dev/null 2>"$TMP/err"
grep -q '(fnv1a' "$TMP/err" && ok "refusal names the pattern" || no "refusal does not name the pattern: $( head -c 200 "$TMP/err" )"

# ── a VALID pattern is untouched: still scans, still exits 0, still finds what it found before
"$BIN" "$ROOT" --regex='fnv1a\w+' >"$TMP/ok" 2>/dev/null; rc=$?
HITS="$( grep -oE ' hits="[0-9]+"' "$TMP/ok" | head -1 | grep -oE '[0-9]+' )"
[ "$rc" -eq 0 ] && ok "valid --regex exits 0" || no "valid --regex exits $rc (expected 0)"

# "Still finds what it found before" was pinned as `hits > 100`, a literal count of THIS tree. That made
# the arm a corpus assertion wearing a scanner assertion's clothes: prune a few documents that happen to
# mention the stem and the gate reddens while the scanner is perfectly healthy. What the arm actually
# wants to prove is that the valid path really scans at repo scale and is not silently swallowed by the
# refusal path. Assert that as an INVARIANT instead: a widened pattern must find at least as much as the
# strictly narrower one it contains, and the narrow one must be non-degenerate.
"$BIN" "$ROOT" --regex='fnv1a64' >"$TMP/narrow" 2>/dev/null
NARROW="$( grep -oE ' hits="[0-9]+"' "$TMP/narrow" | head -1 | grep -oE '[0-9]+' )"
if [ "${NARROW:-0}" -lt 5 ]; then
    no "valid --regex: the narrow probe 'fnv1a64' found hits=${NARROW:-<none>} (<5) — the scan is degenerate, not merely small"
elif [ "${HITS:-0}" -lt "${NARROW:-0}" ]; then
    no "valid --regex: widened 'fnv1a\\w+' found hits=${HITS:-<none>} < narrow 'fnv1a64' hits=$NARROW — a superset pattern cannot find less"
else
    ok "valid --regex scans at repo scale: 'fnv1a\\w+' hits=$HITS >= narrower 'fnv1a64' hits=$NARROW (>=5)"
fi

# A valid pattern that genuinely matches nothing is a MEASUREMENT — exit 0, hits="0". The [q] class keeps
# this very script from being its own hit: the file holds `q[q]q…`, the pattern demands `qqq…`.
"$BIN" "$ROOT" --regex='q[q]qnosuchtokenqqq\w*' >"$TMP/zero" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] && grep -q 'hits="0"' "$TMP/zero" \
    && ok 'valid pattern matching nothing still reports hits="0" at exit 0 (a measurement)' \
    || no "valid non-matching pattern: exit $rc without hits=\"0\""

# ── a literal --grep is not a regex and must not be compile-checked
"$BIN" "$ROOT" --grep='(fnv1a' >"$TMP/lit" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] && grep -q 'hits=' "$TMP/lit" \
    && ok "--grep='(fnv1a' (literal) still scans and exits 0" \
    || no "--grep='(fnv1a' exits $rc — the literal path must not be regex-compiled"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
