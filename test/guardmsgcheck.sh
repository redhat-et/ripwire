#!/usr/bin/env bash
# guardmsgcheck.sh — the 20 COMBINATION GUARDS at the tail of parseArgs, pinned by MESSAGE, not exit code.
#
# The gap this closes (PLAN_dispatchRefactor_2026-07-27.md §3.3 / §6.1 step 3): parseArgs ends in ~165 lines
# of combination validation ("--gateability needs --doc-drift", "--partition needs --pack-task", …) emitting
# 19 distinct messages plus one usage() dump. NOT ONE of those strings appeared verbatim anywhere in test/.
# Coverage was `[ $? -ne 0 ]` plus a fuzzy `grep -qi 'anchor'` — which cannot tell "refused for the right
# reason" from "refused for a different reason", and cannot see a guard silently swapped for its neighbour.
# Three of them rode on a single loose assertion each (--listen, --no-mention-boost, --no-doc-mention).
#
# That is exactly the failure mode an extraction of the guard block invites: cut 165 lines into
# validateConfig(), drop or reorder one guard, and every existing gate still passes because SOME nonzero
# exit still happens. This gate asserts the SPECIFIC refusal, so a swapped, dropped or merged guard is red.
#
# It also pins the one statement in that block that is NOT a guard — `--mcp` implying `--stable` — because
# a default that travels with the guards changes meaning without changing any exit code.
#
# Deliberately cheap: every probe runs against a NONEXISTENT root. Argument validation runs before root
# validation, so each guard answers in ~4 ms without parsing a corpus, spawning git, or walking history.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
cd "$ROOT"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN"; exit 2; }

echo "guardmsgcheck: BIN=$BIN"

NOROOT="$TMP/definitely-not-a-root"
checked=0

# guard NAME | EXPECTED-SUBSTRING | argv…   — asserts exit != 0 AND stderr contains the substring.
# The substring is a distinctive slice of the guard's OWN message: long enough that no other guard in the
# block matches it, short enough to survive a reworded example.
guard()
{
    local name="$1" want="$2"; shift 2
    checked=$(( checked + 1 ))
    "$BIN" "$@" >"$TMP/out" 2>"$TMP/err" </dev/null; local rc=$?
    if [ "$rc" = 0 ]; then
        no "$name: exited 0 — the guard did not fire at all"
        return
    fi
    if grep -qF -- "$want" "$TMP/err"; then
        ok "$name"
    else
        no "$name: refused (exit $rc) but with the WRONG message"
        printf '            want: %s\n' "$want"
        printf '            got : %s\n' "$( head -1 "$TMP/err" )"
    fi
}

# ── the 20 guards, in source order ────────────────────────────────────────────────────────────────────
# 1. no root at all → usage() dump (the only guard with no ripwire: prefix)
guard "no-root prints usage"        'ripgrep of AI context'

# 2. --listen serves one fixed workspace, so it needs a root (bare --mcp does not)
guard "--listen without a root"     'serves ONE workspace fixed at startup'  --listen=127.0.0.1:8765

# 3/4. --anchor and --cochange-boost are RIPWIRE_DEV-gated negative-result experiments. The unset matters:
#      a developer running the suite with RIPWIRE_DEV exported must still see this gate assert the dev refusal.
unset RIPWIRE_DEV
guard "--anchor needs RIPWIRE_DEV"            '--anchor is experimental'          "$NOROOT" --anchor
guard "--cochange-boost needs RIPWIRE_DEV"    '--cochange-boost is experimental'  "$NOROOT" --cochange-boost

# 5/6. …and past the dev gate, both are --for lens modifiers that must not silently no-op.
export RIPWIRE_DEV=1
guard "--anchor alone"              '--anchor modifies --for=TASK'          "$NOROOT" --anchor
guard "--cochange-boost alone"      '--cochange-boost modifies --for=TASK'  "$NOROOT" --cochange-boost
unset RIPWIRE_DEV

# 7-11. the remaining lens modifiers — each refuses alone rather than doing nothing
guard "--no-route alone"            '--no-route modifies --for=TASK or --query=TERMS'         "$NOROOT" --no-route
guard "--adaptive alone"            '--adaptive modifies --for=TASK or --query=TERMS'         "$NOROOT" --adaptive
guard "--no-mention-boost alone"    '--no-mention-boost modifies --for=TASK'                  "$NOROOT" --no-mention-boost
guard "--no-doc-mention alone"      '--no-doc-mention modifies --for=TASK'                    "$NOROOT" --no-doc-mention
guard "--detail alone"              '--detail=N modifies --for=TASK'                          "$NOROOT" --detail=2

# 12/13. --partition: needs --pack-task, and N is bounded 2..16
guard "--partition without --pack-task"  '--partition=N splits a --pack-task bundle'  "$NOROOT" --partition=3
guard "--partition out of range"         'must be 2..16'                              "$NOROOT" --pack-task=t --partition=99

# 14/15. --flip: needs the --flags table, and needs a gate NAME
guard "--flip without --flags"      '--flip=NAME reports one gate from the --flags table'  "$NOROOT" --flip=NOPE
guard "--flip with no gate name"    '--flip needs a gate name'                             "$NOROOT" --flags --flip

# 16-18. the cross-branch composers — each rides on another verb's sweep
guard "--plan without --stray-content"        "--plan composes with --stray-content's sweep"  "$NOROOT" --plan
guard "--abi without --stray-content"         '--abi reports the cross-branch ABI-break gate' "$NOROOT" --abi
guard "--gateability without --doc-drift"     "--gateability reports over --doc-drift's own scan" "$NOROOT" --gateability

# 19/20. the two output-shape guards
guard "--format=candidates alone"   '--format=candidates exports a --for=TASK or --query=TERMS result'  "$NOROOT" --format=candidates
guard "--top-k=0 without a payload" 'payload only'                                                      "$NOROOT" --top-k=0

[ "$checked" -ge 20 ] && ok "pinned $checked guard messages (20 distinct guards)" \
                      || no "only $checked guards probed — a guard was dropped from this gate, not from the parser"

# ── the statement in that block that is NOT a guard ───────────────────────────────────────────────────
# `if( c.mcp && !c.noStable ) c.stable = true;` sits among the guards but is a DEFAULT: --mcp turns --stable
# on so MCP callers get a KV-cache-friendly prefix without remembering the flag. Nothing pinned it, so an
# extraction that carried it off with the guards — or reordered it past one — would change output ordering
# with every exit code unchanged.
#
# The observable: stable order SUPPRESSES the volatile stats header, so `order=important-first` appears
# exactly once in a non-stable map and never in a stable one. That is a byte in stdout, not a mode flag.
stableorder()
{
    local name="$1" want="$2"; shift 2   # want = STABLE | UNSTABLE
    local got mode
    got="$( "$BIN" "$@" </dev/null 2>/dev/null | grep -c 'order=important-first' )"
    [ "$got" = 0 ] && mode=STABLE || mode=UNSTABLE
    [ "$mode" = "$want" ] && ok "$name" || no "$name (map came out $mode, want $want)"
}
stableorder "plain run is NOT stable-ordered"         UNSTABLE  test/fixture
stableorder "--order=stable IS stable-ordered"        STABLE    test/fixture --order=stable
stableorder "--no-stable alone changes nothing"       UNSTABLE  test/fixture --no-stable
stableorder "--order=stable --no-stable stays stable" STABLE    test/fixture --order=stable --no-stable

# The --mcp side of the same default, without starting a server: stdio MCP reads one request per line, so a
# single request on stdin exercises the flag combination and exits. The map arrives JSON-escaped inside the
# response, but `order=important-first` carries no quotes so the same marker works.
stablemcp()
{
    local name="$1" want="$2"; shift 2
    local got mode
    got="$( printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"analyze","arguments":{"path":"test/fixture"}}}\n' \
            | "$BIN" "$@" 2>/dev/null | grep -c 'order=important-first' )"
    [ "$got" = 0 ] && mode=STABLE || mode=UNSTABLE
    [ "$mode" = "$want" ] && ok "$name" || no "$name (map came out $mode, want $want)"
}
stablemcp "--mcp implies --stable"           STABLE    --mcp
stablemcp "--mcp --no-stable opts back out"  UNSTABLE  --mcp --no-stable

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
