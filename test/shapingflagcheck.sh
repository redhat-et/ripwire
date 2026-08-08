#!/usr/bin/env bash
# shapingflagcheck.sh — §B9.2 (capture-audit-4): --top-k / --max-tokens on verbs OUTSIDE the report/paging
# family are DISCLOSED, and the disclosure agrees with which verbs actually read the fields.
#
# §B9's wave-2 guards close the family they can see: honorsPaging()'s 22 members refuse both flags. The
# wave-2 verifier then found 14 verbs OUTSIDE that family taking them at exit 0 with byte-identical output,
# 11 disclosed nowhere at all. cli.h's kShapingVerbs table is the ledger of that outside; this gate is what
# stops it from becoming another kPagingHonoringVerbs-style prose list that outgrows the code.
#
# THE CAVEAT THIS GATE IS BUILT AROUND (the verifier's own false start): "byte-identical output" does NOT
# mean "the flag was ignored". Its first --connect and --pr-context probes were INERT — a 705-byte subgraph
# has nothing for a 200-token ceiling to trim — and reading that as an ignore would have written --connect
# and --pr-context into the wrong column. So every HONOURING row below is probed on a shape where the budget
# demonstrably BINDS, and that is ASSERTED, not assumed: the un-budgeted run must exceed the flag's own byte
# allowance (tokens x kMinBytesPerToken), or nothing could have been trimmed and the row proves nothing.
#
# WHAT THE HONOURING ARM ASSERTS, and why it is not "the output shrinks" (CA4-F5.F7). This header used to
# claim "the probe asserts the output really shrinks" while the code asserted only `! cmp -s` — any
# difference. Live, that arm printed `PASS (B) --pr-context honours --max-tokens=200: 3509 B -> 3538 B`:
# 29 bytes LARGER. The verb was not lying — it really dropped every nested <caller>/<partner>/<author> list
# and said so (`trim_level="4" truncated="...;budget-floor-exceeded"`) — but on a document whose irreducible
# structure is already far past a 472 B allowance, the ~130 B disclosure outweighs what the trim saved. That
# is this round's trap #8 ("a disclosure has BYTES") landing on the gate that measures it, and a strict
# `shaped < plain` would therefore RED on an HONEST verb whenever HEAD~1's diff happens to be small.
#
# So the property is EVIDENCE OF TRIMMING, and the arm takes it in either of the two forms it can arrive in:
# strictly fewer bytes, or an explicit trim disclosure naming what was dropped. A changed output that is
# neither smaller nor accompanied by a disclosure FAILS — that is noise, and it is exactly what the old
# `! cmp -s` accepted. The byte delta is printed either way, and the disclosure-outweighs-the-saving case is
# NAMED in the pass line rather than reported as a shrink that did not happen.
#
#   bash test/shapingflagcheck.sh                        # build/ripwire
#   bash test/shapingflagcheck.sh <scratch>/base_w3      # red-first: the notices are absent there
#   RIPWIRE_BIN=asan/ripwire bash test/shapingflagcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
cd "$ROOT"
echo "shapingflagcheck: BIN=$BIN"
git status --porcelain 2>/dev/null | grep -vE '^\?\? (build|asan|tsan)' > "$TMP/status.before"

# ── (A) the SOURCE side: the read sites, re-derived ────────────────────────────────────────────────────
# cli.h is excluded because that is where the fields are DECLARED and where the guards read them to decide
# whether to speak; every other hit is a verb actually shaping with the value. The counts are pinned so a new
# read site cannot appear without a reader deciding which column of kShapingVerbs it belongs in — the same
# tripwire discipline as kTotalFlagArms. Re-derive with the commands printed below.
MAXSITES="$( grep -c 'cfg\.maxTokens\|c\.maxTokens' src/main.cpp src/mcpserver.h 2>/dev/null | awk -F: '{s+=$2} END{print s+0}' )"
TOPSITES="$( grep -c 'cfg\.topK\|c\.topK'           src/main.cpp src/mcpserver.h 2>/dev/null | awk -F: '{s+=$2} END{print s+0}' )"
[ "$MAXSITES" = 16 ] && ok "(A) --max-tokens has 16 read sites outside cli.h (grep 'cfg\\.maxTokens' src/main.cpp src/mcpserver.h)" \
                     || no "(A) --max-tokens read sites moved 16 -> $MAXSITES: a verb gained or lost the budget, so kShapingVerbs' honorsMaxTokens column must be re-decided (and this number re-pinned)"
[ "$TOPSITES" = 12 ] && ok "(A) --top-k has 12 read sites outside cli.h" \
                     || no "(A) --top-k read sites moved 12 -> $TOPSITES: re-decide kShapingVerbs' honorsTopK column and re-pin this number"
# no OTHER file may read them: a third file would be a verb family this table has never heard of
OTHER="$( grep -l 'cfg\.maxTokens\|cfg\.topK' src/*.h src/*.cpp 2>/dev/null | grep -vE 'src/(cli\.h|main\.cpp|mcpserver\.h)$' )"
[ -z "$OTHER" ] && ok "(A) only main.cpp and mcpserver.h read the two fields" \
                || { no "(A) a NEW file reads --top-k/--max-tokens and is not in this gate's derivation:"; printf '%s\n' "$OTHER" | sed 's/^/        /'; }

# ── (B) the TABLE side: every kShapingVerbs row, parsed out of cli.h ───────────────────────────────────
python3 - "$ROOT" > "$TMP/rows.tsv" <<'PY'
import io, re, sys
src  = io.open( sys.argv[1] + "/src/cli.h", encoding = "utf-8" ).read()
body = src[ src.index( "inline constexpr ShapingVerb kShapingVerbs[] = {" ) : ]
body = re.sub( r'//[^\n]*', '', body[ : body.index( "\n};" ) ] )
for name, tail in re.findall( r'\{\s*"(--[a-z-]+)"\s*,([^}]*)\}', body ):
    cols = [ c.strip() for c in tail.split( "," ) ]
    # columns after the two selector slots are honorsTopK, honorsMaxTokens (defaulted false when absent)
    flags = [ c for c in cols[ 2: ] if c in ( "true", "false" ) ]
    print( "%s\t%s\t%s" % ( name, ( flags + [ "false", "false" ] )[ 0 ], ( flags + [ "false", "false" ] )[ 1 ] ) )
PY
ROWS="$( grep -c . "$TMP/rows.tsv" )"
[ "$ROWS" -ge 12 ] && ok "(B) parsed $ROWS kShapingVerbs rows out of src/cli.h" \
                   || { no "(B) only $ROWS rows parsed — the scrape broke, so nothing below asserts anything"; echo "FAILURES ABOVE"; exit 1; }

# the argv each row is exercised with. Chosen so the verb produces a REAL, sizeable result on this repo:
# a row probed on a shape it answers in 80 bytes cannot tell honouring from inert (see the header).
argvFor()
{
    case "$1" in
        --for)         printf '%s\0' --for=add retry to the http client ;;
        --pack-task)   printf '%s\0' --pack-task=add retry to the http client ;;
        --exemplar)    printf '%s\0' --exemplar=a JSON writer ;;
        --around)      printf '%s\0' --around=parseArgs ;;
        --path)        printf '%s\0' --path=parseArgs,serialize ;;
        --lego)        printf '%s\0' --lego=Config ;;
        --report)      printf '%s\0' --report ;;
        --edit-check)  printf '%s\0' --edit-check=parseArgs ;;
        --situ)        printf '%s\0' --situ ;;
        --handoff)     printf '%s\0' --handoff ;;
        --scan-skills) printf '%s\0' --scan-skills ;;
        --merge-scout) printf '%s\0' --merge-scout=HEAD,HEAD~1 ;;
        --connect)     printf '%s\0' --connect=parseArgs,serialize,rankGraph ;;
        # H4 close-out: HEAD~1 made this probe INERT whenever the newest commit is docs-only — a
        # crawl-skipped diff has no symbol rows, nothing trims, and the honours column reads false
        # (third instance of the live-diff-dependence class this round; the est under-charge,
        # residual #6, is what lets the budget believe an untrimmable 4.5 KB document "fits").
        # Anchor the base at the parent of the last SOURCE-touching commit so the diff always
        # carries indexed symbols. src/ always has commits in this repo; the guard keeps a
        # hand-rolled checkout without git from silently probing an empty range.
        --pr-context)  local srcTip; srcTip="$( git -C "$ROOT" log -1 --format=%H -- src/ 2>/dev/null )"
                       [ -n "$srcTip" ] || srcTip=HEAD
                       printf '%s\0' --pr-context="${srcTip}~1" ;;
        --from-trace)  printf '%s\0' --from-trace="$TMP/trace.txt" ;;
        *)             return 1 ;;
    esac
}
# The innermost frame is DERIVED, never pinned. An absolute line number inside a probe is a CORPUS
# COORDINATE, not a fact about the verb: this file used to write "src/cli.h:2100", and one wave's worth of
# new --help text pushed that line off validateShapingFlagsHonored — a ~40-line body carrying a 3-call list,
# and the ONLY part of this document a byte budget can cut — onto a three-line neighbour. The budget then had
# nothing left to trim, the shaped run came back byte-identical, and the gate reported an entirely HONEST
# --from-trace as broken. That is the THIRD instance of the inert-probe class this header already documents
# twice above (--connect/--pr-context, then --pr-context's HEAD~1), and the (B-binds) precondition cannot see
# it: (B-binds) weighs the WHOLE document against the allowance, and the ~2.9 KB legend keeps that true long
# after the trimmable part has gone. So anchor on the NAME and let the probe follow the code, and let
# (B-anchor) below assert that it landed rather than assume it.
TRACE_FN=validateShapingFlagsHonored
TRACE_LINE="$( grep -n "^inline void ${TRACE_FN}(" "$ROOT/src/cli.h" | head -1 | cut -d: -f1 )"
[ -n "$TRACE_LINE" ] || { echo "shapingflagcheck: cannot locate ${TRACE_FN} in src/cli.h — the --from-trace probe has no anchor to derive"; exit 2; }
printf '#0 parseArgs at src/cli.h:%s\n#1 serialize at src/serialize.h:900\n#2 main at src/main.cpp:7600\n' "$TRACE_LINE" > "$TMP/trace.txt"

# the trim vocabulary the honouring arm accepts as evidence when a budgeted run does not get SMALLER. Kept
# narrow on purpose: each of these is a statement the verb makes about a cut it performed, not a count that
# an untrimmed document also carries (`capped="1"` is deliberately NOT here — it appears on ordinary paged
# output and would let an unrelated difference pass as a trim).
TRIMMARK='trim_level=|truncated=|budget-floor-exceeded|over_ceiling'

nNotice=0; nHonor=0
while IFS="$( printf '\t' )" read -r verb honorsTop honorsMax; do
    [ -n "$verb" ] || continue
    args=(); while IFS= read -r -d '' a; do args+=( "$a" ); done < <( argvFor "$verb" ) || true
    [ "${#args[@]}" -gt 0 ] || { no "(B) $verb has no probe argv in this gate — a row was added without one"; continue; }

    for pair in "--top-k=3|$honorsTop" "--max-tokens=200|$honorsMax"; do
        flag="${pair%%|*}"; honors="${pair#*|}"
        "$BIN" . "${args[@]}"        >"$TMP/plain" 2>"$TMP/plain.err" </dev/null; rcP=$?
        "$BIN" . "${args[@]}" "$flag" >"$TMP/shaped" 2>"$TMP/shaped.err" </dev/null; rcS=$?
        [ "$rcP" = "$rcS" ] || { no "(B) $verb $flag changed the EXIT code ($rcP -> $rcS) — this is a notice, never a refusal"; continue; }

        if [ "$honors" = true ]; then
            # honouring: the flag must actually BIND on this shape, and no note may claim otherwise
            pB="$( wc -c <"$TMP/plain"  | tr -d ' ' )"; sB="$( wc -c <"$TMP/shaped" | tr -d ' ' )"
            # (B-binds) the precondition the header claims — for a BYTE budget, the un-budgeted run must be
            # over the allowance the flag sets (tokens x kMinBytesPerToken = 2.36), or nothing could bind and
            # the row would be proving inertness. --top-k carries no byte allowance, so it is exempt by shape.
            case "$flag" in
                --max-tokens=*)
                    allow="$( awk "BEGIN{printf \"%d\", ${flag#--max-tokens=} * 2.36}" )"
                    if [ "$pB" -le "$allow" ]; then
                        no "(B-binds) $verb $flag: the un-budgeted run is $pB B, already inside the ${allow} B allowance — this probe is INERT and the honouring row it feeds proves nothing (widen the probe argv, do not move the column)"
                    else
                        ok "(B-binds) $verb $flag binds on this shape: $pB B un-budgeted vs a ${allow} B allowance"
                    fi ;;
            esac
            if cmp -s "$TMP/plain" "$TMP/shaped"; then
                no "(B) $verb declares it honours $flag but the output did not change ($pB B) — either the column is wrong or this probe is INERT"
            elif [ "$sB" -lt "$pB" ]; then
                nHonor=$(( nHonor + 1 ))
                ok "(B) $verb honours $flag and the output SHRINKS: $pB B -> $sB B ($(( sB - pB )) B)"
            # the disclosure must have APPEARED because of the flag: present in the shaped run and ABSENT from
            # the un-shaped one. A marker present in both says nothing about what this flag did.
            elif grep -qE "$TRIMMARK" "$TMP/shaped" && ! grep -qE "$TRIMMARK" "$TMP/plain"; then
                # trap #8: the trim is real and disclosed; the disclosure just costs more than it saved here.
                nHonor=$(( nHonor + 1 ))
                ok "(B) $verb honours $flag — it TRIMS and discloses what it dropped, and on this shape the disclosure outweighs the saving: $pB B -> $sB B (+$(( sB - pB )) B, trap #8). The trim is the evidence; the byte total is not."
            else
                no "(B) $verb $flag changed the output ($pB B -> $sB B) but it neither shrank nor disclosed a trim — that is noise, not evidence of honouring, and it is what a bare 'the bytes differ' assertion accepts"
            fi
            grep -q "is not read by $verb" "$TMP/shaped.err" \
                && no "(B) $verb is DISCLOSED as ignoring $flag while it demonstrably shapes with it — the note is false"
        else
            cmp -s "$TMP/plain" "$TMP/shaped" \
                && ok "(B) $verb ignores $flag and its stdout is byte-identical (the notice changes no output byte)" \
                || no "(B) $verb declares it ignores $flag but the output CHANGED — the column is wrong"
            if grep -q "is not read by $verb" "$TMP/shaped.err"; then
                nNotice=$(( nNotice + 1 ))
                ok "(B) $verb DISCLOSES that $flag is not read"
            else
                no "(B) $verb takes $flag silently — accepted and ignored, with no way to tell a no-op from a typo"
            fi
            grep -q "is not read by $verb" "$TMP/plain.err" \
                && no "(B) $verb prints the $flag notice even when the flag was never passed"
        fi
    done
done < "$TMP/rows.tsv"
# (B-anchor) the derived probe must actually LAND on the anchor. A rename or a refactor that moves the
# frame onto some other symbol makes the honouring row above inert again — silently, and with a failure
# message that blames the binary. This arm names the drift instead.
"$BIN" . --from-trace="$TMP/trace.txt" >"$TMP/anchor.out" 2>/dev/null </dev/null
innerFrame="$( grep -o '<frame [^>]*>' "$TMP/anchor.out" | grep 'innermost="1"' | head -1 )"
case "$innerFrame" in
    *"n=\"${TRACE_FN}\""*) ok "(B-anchor) the derived --from-trace frame resolved to ${TRACE_FN} (src/cli.h:${TRACE_LINE}) — the probe sits on a trimmable body, not on whatever now occupies a pinned line" ;;
    *)                     no "(B-anchor) the derived --from-trace frame did NOT resolve to ${TRACE_FN} — it landed on: ${innerFrame:-<no innermost frame at all>}. The honouring row it feeds proves nothing until the anchor is fixed" ;;
esac

[ "$nNotice" -ge 20 ] && ok "(B) $nNotice ignore-disclosures fired across the table" || no "(B) only $nNotice ignore-disclosures fired (want >=20)"
[ "$nHonor"  -ge 3  ] && ok "(B) $nHonor honouring rows proved to actually bind (not merely inert)" || no "(B) only $nHonor honouring rows bound"

# ── (C) the two families must not BOTH speak ───────────────────────────────────────────────────────────
# honorsPaging()'s members REFUSE these flags (exit 1). A verb there must get the refusal and NOT the notice,
# or a caller gets two contradictory sentences about one flag.
"$BIN" . --hotspots --top-k=3 >/dev/null 2>"$TMP/hot.err"; rcH=$?
{ [ "$rcH" -eq 1 ] && grep -q 'honored only by\|narrows only' "$TMP/hot.err" && ! grep -q 'is not read by' "$TMP/hot.err"; } \
    && ok "(C) a report/paging verb still REFUSES --top-k and does not also emit the notice" \
    || no "(C) --hotspots --top-k=3 exited $rcH with: [$( head -c 200 "$TMP/hot.err" )]"

# ── (D) the default map and its riders honour both and must stay silent ────────────────────────────────
for probe in "--top-k=3" "--max-tokens=200"; do
    "$BIN" . "$probe" >"$TMP/d.out" 2>"$TMP/d.err"; rcD=$?
    { [ "$rcD" -eq 0 ] && [ ! -s "$TMP/d.out" ] && false; } 2>/dev/null
    if [ "$rcD" -eq 0 ] && ! grep -q 'is not read by' "$TMP/d.err"; then
        ok "(D) the default map takes $probe silently (it honours it)"
    else
        no "(D) the default map exited $rcD or was told $probe is unread: [$( head -c 160 "$TMP/d.err" )]"
    fi
done
# the --for --detail carve-out: --for ignores --max-tokens bare and HONOURS it under --detail=N, so the note
# must disappear in the second shape. A table column cannot state that; this is the arm that pins it.
"$BIN" . --for="add retry to the http client" --detail=3 --max-tokens=200 >"$TMP/fd.out" 2>"$TMP/fd.err"
grep -q 'is not read by --for' "$TMP/fd.err" \
    && no "(D) --for --detail=N is told --max-tokens is unread — it bounds the bodies, so the note is false" \
    || ok "(D) --for --detail=N gets NO --max-tokens notice (the carve-out holds)"
"$BIN" . --for="add retry to the http client" --detail=3 >"$TMP/fp.out" 2>/dev/null
cmp -s "$TMP/fp.out" "$TMP/fd.out" \
    && no "(D) --for --detail=3 --max-tokens=200 produced identical bytes — the carve-out is claiming a budget that does not bind" \
    || ok "(D) --for --detail=N really does shrink under --max-tokens ($( wc -c <"$TMP/fp.out" | tr -d ' ' ) B -> $( wc -c <"$TMP/fd.out" | tr -d ' ' ) B)"

# ── (E) --help must state --from-trace's budget ────────────────────────────────────────────────────────
# The named §B9.2 gap: --from-trace DOES honour --max-tokens and --help never said so.
"$BIN" --help 2>&1 | tr '\n' ' ' | grep -q -- '--from-trace' && HELPOK=1 || HELPOK=0
[ "$HELPOK" = 1 ] || no "(E) --help does not mention --from-trace at all"
"$BIN" --help 2>&1 | sed -n '/--from-trace=FILE/,/--note-add/p' | grep -q -- '--max-tokens' \
    && ok "(E) --help's --from-trace paragraph states that it honors --max-tokens" \
    || no "(E) --help's --from-trace paragraph still never mentions --max-tokens"

# ── the harness must not mutate the tree ───────────────────────────────────────────────────────────────
git status --porcelain 2>/dev/null | grep -vE '^\?\? (build|asan|tsan)' > "$TMP/status.after"
STRAY="$( comm -13 "$TMP/status.before" "$TMP/status.after" 2>/dev/null | head -5 )"
[ -z "$STRAY" ] && ok "gate left the tree unmodified" \
                || { no "gate MUTATED the tree:"; printf '%s\n' "$STRAY" | sed 's/^/        /'; }

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
