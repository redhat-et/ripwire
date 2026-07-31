#!/usr/bin/env bash
# selectorrefusecheck.sh — §B4 gate (PLAN_outputAudit3_2026-07-29.md): the two selector-refusal defects.
#
# §B4.1 [BROKEN] — `--edit-check`'s ambiguity refusal predicted a SIBLING VERB's output from the wrong
#   number. `editCheckAmbiguousMessage` printed `groups.size()` (the per-(file,scope) COLLAPSED contract
#   count) in BOTH slots, so it said "it matches 53 definitions … (--callers may … disclose defs=\"53\")"
#   while --callers/--uses/--impact all disclosed defs="58". The two counts diverge exactly when one file
#   holds two same-named defs, which is why nothing caught it: the repo's own bare names mostly don't. A
#   refusal that makes a CHECKABLE FALSE CLAIM about another verb is the worst kind of wrong — an agent can
#   act on it without re-running anything.
#
# §B4.2 [MISLEADING] — a `file:name` selector whose FILE half is the fault. --uses said what was actually
#   wrong ("that file defines no 'X' — defined in …/graph.h — e.g. --uses=…"); --edit-check / --callers /
#   --callees / --impact / --around / --lego said only "symbol not found" about a symbol that plainly
#   EXISTS, sending the reader after a rename that never happened. One enrichment, one arm — the "one
#   shared guard, N arms" class. Fixed by lifting the message to src/selectorrefuse.h, which all six call.
#
# RED-FIRST: every arm below fails on build_base/ctxpack (the pre-wave binary) and passes on the fixed one.
#
# Usage:  bash test/selectorrefusecheck.sh [BIN]   |   CTXPACK_BIN=build_base/ctxpack bash test/…
# Exits non-zero on any failure. Does NOT edit regression.sh (test/pargates.py auto-discovers *check.sh).

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${CTXPACK_BIN:-$ROOT/build/ctxpack}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first"; exit 2; }
echo "selectorrefusecheck: BIN=$BIN"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
# §B4.1 — a fixture where the two counts DIVERGE by construction.
#
#   one.h   two overloads of `helper` at file scope  → ONE contract group, TWO definitions
#   two.h   one `helper`                             → ONE contract group, ONE definition
#
# So the ambiguity refusal must say "3 definitions in 2 distinct contracts", and the defs= it predicts for
# --callers must be 3 — which is what --callers/--uses/--impact actually print. A binary that reuses the
# group count says "2 … defs=\"2\"" and disagrees with all three siblings.
# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
R="$TMP/repo"; mkdir -p "$R"
printf 'int helper( int q ) { return q; }\nint helper( int q, int r ) { return q + r; }\n' > "$R/one.h"
printf 'int helper( double q ) { return int( q ); }\n'                                    > "$R/two.h"
printf '#include "one.h"\n#include "two.h"\nint use() { return helper( 1 ) + helper( 1, 2 ) + helper( 1.0 ); }\n' > "$R/use.cpp"

EC_RC=0; "$BIN" "$R" --edit-check=helper --no-cache >/dev/null 2>"$TMP/ecerr" || EC_RC=$?
EC="$( cat "$TMP/ecerr" )"
[ "$EC_RC" = 1 ] \
    && ok "§B4.1: an ambiguous bare name still refuses (exit 1)" \
    || no "§B4.1: --edit-check=helper exited $EC_RC (want 1) — $EC"

# the defs= the refusal PREDICTS, and what the three siblings actually DISCLOSE. Set-compare, not a literal:
# the fixture pins the shape (2 groups, 3 defs), the binary supplies the numbers.
PREDICTED="$( printf '%s' "$EC" | grep -oE 'defs=\\?"[0-9]+' | grep -oE '[0-9]+' | head -1 )"
defs_of(){ "$BIN" "$R" "$1"=helper --no-cache 2>/dev/null | grep -oE 'defs="[0-9]+"' | head -1 | grep -oE '[0-9]+'; }
C_DEFS="$( defs_of --callers )"; U_DEFS="$( defs_of --uses )"; I_DEFS="$( defs_of --impact )"
{ [ -n "$C_DEFS" ] && [ "$C_DEFS" = "$U_DEFS" ] && [ "$C_DEFS" = "$I_DEFS" ]; } \
    && ok "§B4.1 guard: the three siblings agree with each other on defs= ($C_DEFS)" \
    || no "§B4.1 guard: siblings disagree — callers=$C_DEFS uses=$U_DEFS impact=$I_DEFS (fixture broken?)"
{ [ -n "$PREDICTED" ] && [ "$PREDICTED" = "$C_DEFS" ]; } \
    && ok "§B4.1: the refusal's predicted defs=\"$PREDICTED\" == what --callers/--uses/--impact disclose ($C_DEFS)" \
    || no "§B4.1: refusal predicts defs=\"$PREDICTED\" but the siblings disclose defs=\"$C_DEFS\" — a false claim about a sibling verb"

# the fixture's whole point: the two numbers must actually DIFFER here, or the arm above is vacuous.
CONTRACTS="$( printf '%s' "$EC" | grep -oE 'in [0-9]+ distinct contracts' | grep -oE '[0-9]+' | head -1 )"
{ [ -n "$CONTRACTS" ] && [ "$CONTRACTS" -lt "$PREDICTED" ]; } \
    && ok "§B4.1: the refusal reports BOTH quantities and they differ here ($PREDICTED definitions in $CONTRACTS contracts)" \
    || no "§B4.1: the refusal does not separate definitions from contracts (defs=$PREDICTED contracts=$CONTRACTS) — $EC"

# each number carries its own noun (the collapsed count was narrated as "definitions", which it is not).
printf '%s' "$EC" | grep -qE "matches $PREDICTED definitions in $CONTRACTS distinct contracts" \
    && ok "§B4.1: each number carries the right NOUN (definitions vs contracts)" \
    || no "§B4.1: the two numbers are not each named — $EC"

# GUARD: an unambiguous selector is untouched by any of this.
"$BIN" "$R" --edit-check=one.h:helper --no-cache >/dev/null 2>&1 \
    && ok "GUARD §B4.1: a qualified, unambiguous selector still answers (exit 0)" \
    || no "GUARD §B4.1: --edit-check=one.h:helper no longer answers"

# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
# §B4.2 — the non-defining `file:name` qualifier, on ALL SIX arms.
#
# `two.h:notHere` is not the case (the NAME is unknown too — that must still get a plain not-found). The
# case is `two.h:helper`: the name exists, in one.h, and the file half is the mistake. Asserted as MEANING
# halves, never as a sentence: (1) the refusal NAMES the file that does define it, (2) it hands back a
# retry that is runnable AS TYPED for that same verb.
# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
printf 'int lonely( int q ) { return q; }\n' > "$R/one_only.h"

for arm in callers callees impact around lego uses edit-check; do
    ARC=0; "$BIN" "$R" --$arm=two.h:lonely --no-cache >/dev/null 2>"$TMP/e" || ARC=$?
    E="$( cat "$TMP/e" )"
    [ "$ARC" = 1 ] \
        && ok "§B4.2 (--$arm): a non-defining file:name REFUSES (exit 1)" \
        || no "§B4.2 (--$arm): exited $ARC (want 1) — $E"
    printf '%s' "$E" | grep -q 'one_only.h' \
        && ok "§B4.2 (--$arm): the refusal NAMES the file that does define 'lonely'" \
        || no "§B4.2 (--$arm): refusal does not name the defining file — $E"
    RETRY="$( printf '%s' "$E" | grep -oE -- "--$arm=[^ )]+" | tail -1 )"
    if [ -z "$RETRY" ]; then
        no "§B4.2 (--$arm): refusal offers no runnable retry — $E"
    else
        RRC=0; "$BIN" "$R" "$RETRY" --no-cache >/dev/null 2>&1 || RRC=$?
        [ "$RRC" = 0 ] \
            && ok "§B4.2 (--$arm): the offered retry '$RETRY' RUNS (exit 0) exactly as printed" \
            || no "§B4.2 (--$arm): the offered retry '$RETRY' exited $RRC — the example is not runnable"
    fi
done

# GUARD: a genuinely unknown NAME must NOT get the file-half story — it gets the historic not-found + a
# near-miss. The enrichment must be a fact about the selector, never a guess dressed as one.
for arm in callers impact around lego uses edit-check; do
    "$BIN" "$R" --$arm=two.h:zzqqwibble --no-cache >/dev/null 2>"$TMP/e2" || true
    E2="$( cat "$TMP/e2" )"
    printf '%s' "$E2" | grep -q 'that file defines no' \
        && no "GUARD §B4.2 (--$arm): an unknown NAME wrongly gets the file-half explanation — $E2" \
        || ok "GUARD §B4.2 (--$arm): an unknown name still gets the plain not-found (no invented file story)"
done

# GUARD: the bare-name path is untouched — no colon, no file half, no enrichment.
"$BIN" "$R" --callers=zzqqwibble --no-cache >/dev/null 2>"$TMP/e3" || true
grep -q 'symbol not found: zzqqwibble' "$TMP/e3" \
    && ok "GUARD §B4.2: a bare unknown name keeps the historic 'symbol not found: NAME' wording" \
    || no "GUARD §B4.2: bare-name refusal wording changed — $( cat "$TMP/e3" )"

# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
# §B11.1 — THE TWO ARMS §B4.2's SWEEP MISSED.
#
# The §B4.2 fix reached nine SYM-taking verbs. `--owners=` and `--mentions=` take the same `SYM` and were
# still resolving with the BARE-NAME resolver and refusing in the pre-§B4.2 dialect — four words about a
# symbol that plainly exists — so a `file:name` spelling was rejected outright. That is trap #6 exactly: a
# ruling that produces a shared helper sweeps the arms someone remembered, not the surface. This block runs
# the SAME three assertions the loop above runs, on its own git fixture (--owners is mined from git, so its
# retry has to have a repository to run in), plus the guards.
#
# Deliberately parameterised over a LIST rather than written twice: a tenth verb joins by being named here.
# ══════════════════════════════════════════════════════════════════════════════════════════════════════════
if command -v git >/dev/null 2>&1; then
    R2="$TMP/repo2"; mkdir -p "$R2"
    printf 'int lonely( int q ) { return q; }\n'                       > "$R2/one_only.h"
    printf 'int neighbour( int q ) { return lonely( q ); }\n'          > "$R2/two.h"
    ( cd "$R2" && git init -q && git config user.email t@t && git config user.name t \
      && git config commit.gpgsign false && git add -A && git commit -qm init ) >/dev/null 2>&1

    for arm in owners mentions; do
        ARC=0; "$BIN" "$R2" --$arm=two.h:lonely --no-cache >/dev/null 2>"$TMP/b11e" || ARC=$?
        E="$( cat "$TMP/b11e" )"
        [ "$ARC" = 1 ] \
            && ok "§B11.1 (--$arm): a non-defining file:name REFUSES (exit 1)" \
            || no "§B11.1 (--$arm): exited $ARC (want 1) — $E"
        printf '%s' "$E" | grep -q 'one_only.h' \
            && ok "§B11.1 (--$arm): the refusal NAMES the file that does define 'lonely'" \
            || no "§B11.1 (--$arm): still the bare pre-§B4.2 not-found — $E"
        RETRY="$( printf '%s' "$E" | grep -oE -- "--$arm=[^ )]+" | tail -1 )"
        if [ -z "$RETRY" ]; then
            no "§B11.1 (--$arm): refusal offers no runnable retry — $E"
        else
            RRC=0; "$BIN" "$R2" "$RETRY" --no-cache >/dev/null 2>&1 || RRC=$?
            [ "$RRC" = 0 ] \
                && ok "§B11.1 (--$arm): the offered retry '$RETRY' RUNS (exit 0) exactly as printed" \
                || no "§B11.1 (--$arm): the offered retry '$RETRY' exited $RRC — the example is not runnable"
        fi

        # the OTHER half of the gap: a VALID qualified spelling must now be ANSWERED, not refused. Before,
        # both verbs resolved bare-name-only, so `one_only.h:lonely` — a spelling that names a real
        # definition in the file that really holds it — came back "symbol not found".
        VRC=0; "$BIN" "$R2" --$arm=one_only.h:lonely --no-cache >/dev/null 2>"$TMP/b11v" || VRC=$?
        [ "$VRC" = 0 ] \
            && ok "§B11.1 (--$arm): a VALID file:name spelling is answered, not refused" \
            || no "§B11.1 (--$arm): a valid qualified spelling exited $VRC — $( cat "$TMP/b11v" )"

        # GUARDS: an unknown NAME gets no invented file story, and the bare-name path is byte-unchanged.
        "$BIN" "$R2" --$arm=two.h:zzqqwibble --no-cache >/dev/null 2>"$TMP/b11g" || true
        grep -q 'that file defines no' "$TMP/b11g" \
            && no "GUARD §B11.1 (--$arm): an unknown NAME wrongly gets the file-half explanation — $( cat "$TMP/b11g" )" \
            || ok "GUARD §B11.1 (--$arm): an unknown name still gets the plain not-found"
        "$BIN" "$R2" --$arm=zzqqwibble --no-cache >/dev/null 2>"$TMP/b11b" || true
        grep -q "$arm symbol not found: zzqqwibble" "$TMP/b11b" \
            && ok "GUARD §B11.1 (--$arm): a bare unknown name keeps the historic wording" \
            || no "GUARD §B11.1 (--$arm): bare-name refusal wording changed — $( cat "$TMP/b11b" )"
    done

    # ── the MCP twins. The same `symbol` field, the same bare-name resolver, and V2-1's ruling for this
    # surface is REFUSE (qualified selectors are CLI-only here) — which `uses` had and these two did not.
    # All FOUR dispatch sites are probed: the server's tools/call arm and the batch arm, per verb, because
    # V2-1's own header records that its first landing guarded one of two.
    if command -v python3 >/dev/null 2>&1; then
        mcp_err(){ printf '%s\n' "$1" | "$BIN" --mcp 2>/dev/null | python3 -c 'import sys,json
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    try: d=json.loads(line)
    except Exception: continue
    if "error" in d: print(d["error"].get("message",""))
    else:
        c=d.get("result",{}).get("content")
        if c: print(c[0].get("text",""))'; }
        for arm in owners mentions; do
            M1="$( mcp_err '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"'"$arm"'","arguments":{"path":"'"$R2"'","symbol":"two.h:lonely"}}}' )"
            printf '%s' "$M1" | grep -q 'qualified file:name selectors are CLI-only' \
                && ok "§B11.1 MCP $arm (tools/call): refuses a qualified spelling in the shared V2-1 sentence" \
                || { no "§B11.1 MCP $arm (tools/call): did not inherit the V2-1 guard"; printf '   %s\n' "$M1"; }
            M2="$( mcp_err '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"batch","arguments":{"path":"'"$R2"'","queries":[{"verb":"'"$arm"'","symbol":"two.h:lonely"}]}}}' )"
            printf '%s' "$M2" | grep -q 'qualified file:name selectors are CLI-only' \
                && ok "§B11.1 MCP $arm (batch arm): refuses identically — no clone-seam drift" \
                || { no "§B11.1 MCP $arm (batch arm): the two dispatch sites disagree"; printf '   %s\n' "$M2"; }
            M3="$( mcp_err '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"'"$arm"'","arguments":{"path":"'"$R2"'","symbol":"lonely"}}}' )"
            printf '%s' "$M3" | grep -q 'qualified file:name selectors are CLI-only' \
                && no "GUARD §B11.1 MCP $arm: the guard fired on a BARE name" \
                || ok "GUARD §B11.1 MCP $arm: a bare name is answered exactly as before"
        done
        # REGRESSION: `uses` shares the hoisted sentence — its own wording must not have moved.
        MU="$( mcp_err '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"uses","arguments":{"path":"'"$R2"'","symbol":"two.h:lonely"}}}' )"
        printf '%s' "$MU" | grep -q 'ctxpack <dir> --uses=two.h:lonely' \
            && ok "§B11.1 the hoist left MCP uses' own retry example intact" \
            || { no "§B11.1 hoisting the sentence changed MCP uses' message"; printf '   %s\n' "$MU"; }
    else
        printf '  SKIP  §B11.1 MCP twins (no python3)\n'
    fi
else
    printf '  SKIP  §B11.1 (git unavailable — --owners needs a repository)\n'
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
