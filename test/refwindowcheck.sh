#!/usr/bin/env bash
# refwindowcheck.sh — LARGE-PARTIAL-1 item 3 (REF-WINDOW-COST) and the owner's warning rule (2026-11-14).
#
# THE DEFECT. #654 turned the sweep verbs' refusal past 512 branches into a disclosed window (refs_omitted=), but the cost
# stayed: one git process per ref (merge-base, then a diff per pair) made --stray-content 86 s and --abi 125 s at 602
# branches of a ONE-FILE repo, --plan 10-15 min. Now the merge bases come from one `git rev-list` walk and the diffs from
# batched `git diff-tree --stdin`, the window bounds work (512 refs for the sweeps; --whereis by tree entries), and the
# OWNER RULE: whenever a limit is reached, one stderr line tells the person what was cut, the limit and the flag that
# raises it (--detail), at most 5 per process then one collapse line; the answer's bytes never carry it.
#
# Fixture (generated here, git fast-import): a one-file repo, 520 local branches, each one commit off main.
#   T  the batched sweep answers in reasonable time (a loose 60 s bound per call: it took 86-125 s at 602 before)
#   W1 --stray-content past 512: stdout refs_omitted="8"; stderr has exactly one warning naming 512 and --detail
#   W2 --stray-content --abi: the same, for --abi
#   W3 --detail: every branch read (refs="520"), no refs_omitted=, no warning — the warning prints exactly when the limit fires
#   W4 a ref filter under the window: no refs_omitted=, no warning
#   W5 --whereis on the one-file tree: the site budget reads all 520 branches, no warning about refs
#   W6 no answer carries the warning text (stdout)
#   W7 MCP (one process, seven over-window calls): exactly 5 warning lines, then one collapse line, nothing after
#   E  the merge bases and diffs the batch computed match per-ref git: every ref's base= is main's commit, verdicts unmerged
# RED-FIRST (fade32332, measured): T (stray 171 s, abi 1003 s under load), W1b/W2 (no warning), W3 (no --detail lift), W5 (511 refs), W7 fail; W1a, W4, W6, E hold.
#
# Usage:  bash test/refwindowcheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
echo "refwindowcheck: BIN=$BIN"

FIX="$( mktemp -d )"; trap 'rm -rf "$FIX"' EXIT
export HOME="$FIX/home" TMPDIR="$FIX/tmp/"; mkdir -p "$HOME" "$FIX/tmp"
R="$FIX/repo"
git init -q -b main "$R"
python3 - "$R" <<'EOF' | git -C "$R" -c user.name=t -c user.email=t@t fast-import --quiet
import sys
base = 1700000000
def body(i):
    return (f"struct Widget {{ int a; int b{i}; }};\nint helper_{i}( struct Widget* w ) {{ return w->a; }}\n").encode()
out = sys.stdout.buffer
b0 = body(0)
out.write(b"commit refs/heads/main\nmark :1\ncommitter t <t@t> %d +0000\ndata 4\nbase\nM 100644 inline lib/widget.c\ndata %d\n" % (base, len(b0)) + b0 + b"\n")
for i in range(1, 521):
    bi = body(i)
    out.write(b"commit refs/heads/feat/b%05d\ncommitter t <t@t> %d +0000\ndata 3\nwip\nfrom :1\nM 100644 inline lib/widget.c\ndata %d\n" % (i, base + 60 * i, len(bi)) + bi + b"\n")
EOF
git -C "$R" checkout -q main
n=$( git -C "$R" for-each-ref refs/heads | wc -l | tr -d ' ' )
[ "$n" = 521 ] \
    && ok "P fixture: main + 520 branches" \
    || { no "P fixture holds $n refs, not 521"; exit 1; }

call(){ # call NAME ARGS... → $FIX/NAME.out / .err / .sec
    local name=$1; shift
    local t0; t0=$( date +%s )
    ( cd "$R" && "$BIN" . --no-cache "$@" >"$FIX/$name.out" 2>"$FIX/$name.err" )
    echo $(( $( date +%s ) - t0 )) >"$FIX/$name.sec"
}
warns(){ grep -c '^ripwire: warning:' "$FIX/$1.err"; }

call stray --stray-content
call abi --stray-content --abi
call strayd --stray-content --detail=1
call strayf --stray-content=feat/b001
call where --whereis=helper_0

for c in stray abi; do
    s=$( cat "$FIX/$c.sec" ); [ "$s" -le 60 ] \
        && ok "T $c answered in ${s} s" \
        || no "T $c took ${s} s"
done
grep -q 'refs_omitted="8"' "$FIX/stray.out" \
    && ok "W1a --stray-content refs_omitted=8" \
    || no "W1a no refs_omitted=8"
[ "$( warns stray )" = 1 ] && grep -q 'warning: --stray-content read the newest 512 of 520 .*limit: 512 refs.*--detail' "$FIX/stray.err" \
    && ok "W1b one stderr warning naming the window, the limit and --detail" \
    || no "W1b warnings: $( grep warning "$FIX/stray.err" )"
grep -q 'refs_omitted="8"' "$FIX/abi.out" && [ "$( warns abi )" = 1 ] && grep -q 'warning: --abi read the newest 512 of 520' "$FIX/abi.err" \
    && ok "W2 --abi: refs_omitted=8 and one warning" \
    || no "W2 --abi: $( grep -o 'refs_omitted="[0-9]*"' "$FIX/abi.out" ) $( grep warning "$FIX/abi.err" )"
grep -q ' refs="520"' "$FIX/strayd.out" && ! grep -q 'refs_omitted=' "$FIX/strayd.out" && [ "$( warns strayd )" = 0 ] \
    && ok "W3 --detail=1 reads all 520, no refs_omitted=, no warning" \
    || no "W3 --detail: $( grep -o ' refs="[0-9]*"' "$FIX/strayd.out" ) warnings=$( warns strayd )"
! grep -q 'refs_omitted=' "$FIX/strayf.out" && [ "$( warns strayf )" = 0 ] && grep -q ' refs="100"' "$FIX/strayf.out" \
    && ok "W4 a filter of 100 branches: no window, no warning" \
    || no "W4 filter: $( grep -o ' refs="[0-9]*"' "$FIX/strayf.out" ) warnings=$( warns strayf )"
grep -q 'refs_scanned="520"' "$FIX/where.out" && ! grep -q 'warning: --whereis read' "$FIX/where.err" \
    && ok "W5 --whereis reads all 520 branches of a one-file tree, no ref warning" \
    || no "W5 whereis: $( grep -o 'refs_scanned="[0-9]*"' "$FIX/where.out" )"
if grep -l 'ripwire: warning' "$FIX"/*.out >/dev/null 2>&1; then no "W6 a warning reached an answer's stdout"; else ok "W6 no answer carries the warning"; fi
bases=$( grep -o '<ref [^>]*base="[0-9a-f]*"' "$FIX/stray.out" | grep -o 'base="[0-9a-f]*"' | sort -u )
main9=$( git -C "$R" rev-parse --short=9 main )
um=$( grep -o '<ref [^>]* v="unmerged"' "$FIX/stray.out" | wc -l | tr -d ' ' )
[ "$bases" = "base=\"$main9\"" ] && [ "$um" -gt 0 ] \
    && ok "E every base= is main ($main9), $um rows unmerged" \
    || no "E bases: $bases unmerged=$um"

req='{"jsonrpc":"2.0","id":ID,"method":"tools/call","params":{"name":"stray_content","arguments":{"path":"'"$R"'"}}}'
{ printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}'; for i in 2 3 4 5 6 7 8; do printf '%s\n' "${req/ID/$i}"; done; } \
    | "$BIN" --mcp >"$FIX/mcp.out" 2>"$FIX/mcp.err"
w=$( grep -c '^ripwire: warning: --stray-content' "$FIX/mcp.err" ); c=$( grep -c '^ripwire: warning: more limits were reached' "$FIX/mcp.err" )
answers=$( grep -c 'refs_omitted' "$FIX/mcp.out" )
[ "$answers" -ge 7 ] && [ "$w" = 5 ] && [ "$c" = 1 ] && ok "W7 MCP: 7 cut answers, 5 warnings then one collapse line" \
    || no "W7 MCP: answers=$answers warnings=$w collapse=$c"

[ "$fail" = 0 ] && echo "refwindowcheck: PASS" || echo "refwindowcheck: FAILURES ABOVE"
exit $fail
