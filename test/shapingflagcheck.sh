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
# fnorm FILE — stdout with --run-trace's MEASURED duration_ms= masked (verbs_change.h "Determinism, honestly
# scoped"), the ONE documented non-determinism the (B) and (F) byte-identity arms may not blame on a knob.
# Defined HERE, above every caller: verify-wave1 I1 found it defined below the (B) loop, where bash's
# run-time resolution made both `$( fnorm … )` comparands expand EMPTY and the arm compare "" to "" — a
# permanently green byte-identity assertion (manifestcheck.sh's used-before-definition arm now pins this).
fnorm(){ sed -E 's/ duration_ms="[0-9]+"//g' "$1"; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
cd "$ROOT"
echo "shapingflagcheck: BIN=$BIN"
git status --porcelain 2>/dev/null | grep -vE '^\?\? (build|asan|tsan)' > "$TMP/status.before"

# ── (A) the SOURCE side: the read sites, re-derived ────────────────────────────────────────────────────
# cli.h is excluded because that is where the fields are DECLARED and where the guards read them to decide
# whether to speak; every other hit is a verb actually shaping with the value. The counts are pinned so a new
# read site cannot appear without a reader deciding which column of kShapingVerbs it belongs in — the same
# tripwire discipline as kTotalFlagArms. Re-derive with the commands printed below.
# V1 (2026-08-15): the exact-name --expand default (mapTopK=0 when a bare --expand=SYM resolves to exactly
# one match) added ONE new read site each — a single predicate line reading both cfg.topKExplicit and
# cfg.maxTokens to decide whether the auto-default applies. --expand already honours both flags in
# kShapingVerbs (the pre-existing M6 bundle-vs-whole-file logic already read them), so this is a re-pin, not
# a column change: 16->17 / 12->13. CLI recall's bounded default adds one more maxTokens policy read:
# 17->18; the verb already honored explicit --max-tokens, so its table column remains unchanged.
MAXSITES="$( grep -c 'cfg\.maxTokens\|c\.maxTokens' src/main.cpp src/verbs_*.h src/mcpserver.h 2>/dev/null | awk -F: '{s+=$2} END{print s+0}' )"
TOPSITES="$( grep -c 'cfg\.topK\|c\.topK'           src/main.cpp src/verbs_*.h src/mcpserver.h 2>/dev/null | awk -F: '{s+=$2} END{print s+0}' )"
[ "$MAXSITES" = 18 ] && ok "(A) --max-tokens has 18 read sites outside cli.h (grep 'cfg\\.maxTokens' src/main.cpp src/verbs_*.h src/mcpserver.h)" \
                     || no "(A) --max-tokens read sites moved 18 -> $MAXSITES: a verb gained or lost the budget, so kShapingVerbs' honorsMaxTokens column must be re-decided (and this number re-pinned)"
[ "$TOPSITES" = 13 ] && ok "(A) --top-k has 13 read sites outside cli.h" \
                     || no "(A) --top-k read sites moved 13 -> $TOPSITES: re-decide kShapingVerbs' honorsTopK column and re-pin this number"
# no OTHER file may read them: a third file would be a verb family this table has never heard of.
# 2026-08-29 main.cpp split: src/verbs_*.h are SECTIONS of main.cpp's own TU (RIPWIRE_MAIN_TU-guarded),
# so they count as main.cpp in this derivation — the counts above sweep them, the exclusion below too.
OTHER="$( grep -l 'cfg\.maxTokens\|cfg\.topK' src/*.h src/*.cpp 2>/dev/null | grep -vE 'src/(cli\.h|main\.cpp|mcpserver\.h|verbs_[a-z]+\.h)$' )"
[ -z "$OTHER" ] && ok "(A) only main.cpp (with its verbs_*.h sections) and mcpserver.h read the two fields" \
                || { no "(A) a NEW file reads --top-k/--max-tokens and is not in this gate's derivation:"; printf '%s\n' "$OTHER" | sed 's/^/        /'; }

# ── (B) the TABLE side: every kShapingVerbs row, parsed out of cli.h ───────────────────────────────────
python3 - "$ROOT" > "$TMP/rows.tsv" <<'PY'
import io, re, sys
src  = io.open( sys.argv[1] + "/src/cli.h", encoding = "utf-8" ).read()
body = src[ src.index( "inline constexpr ShapingVerb kShapingVerbs[] = {" ) : ]
body = re.sub( r'//[^\n]*', '', body[ : body.index( "\n};" ) ] )
for name, tail in re.findall( r'\{\s*"(--[a-z-]+)"\s*,([^}]*)\}', body ):
    cols = [ c.strip() for c in tail.split( "," ) ]
    # columns after the two selector slots are honorsTopK, honorsMaxTokens, honorsTokenBudget (defaulted false when absent)
    flags = ( [ c for c in cols[ 2: ] if c in ( "true", "false" ) ] + [ "false", "false", "false" ] )[ :3 ]
    print( "%s\t%s\t%s\t%s" % ( name, flags[ 0 ], flags[ 1 ], flags[ 2 ] ) )
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
        --slice)       printf '%s\0' --slice=parseArgs:c ;;
        # lane/at-seed: the seed LINE is the verb's own input, so it is DERIVED from a durable anchor
        # (the resolveFocus definition in graph.h) rather than pinned — the same corpus-coordinate
        # rule the --from-trace note below states.
        --at)          local atLine; atLine="$( grep -n 'inline NodeId resolveFocus' "$ROOT/src/graph.h" | head -1 | cut -d: -f1 )"
                       [ -n "$atLine" ] || atLine=1
                       printf '%s\0' --at=src/graph.h:$(( atLine + 2 )) ;;
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
        # capture-audit 2026-09-04 (H3): the two rows added with an honouring column. --html rides the map's
        # serialize path (a 58 KB document on this repo, so both knobs bite); --run-trace honours only
        # --token-budget, which this arm does not pair — its argv is here so the honouring-row rule above is
        # satisfied by a probe, and `true` is the command so nothing is built.
        --html)        printf '%s\0' --html ;;
        --run-trace)   printf '%s\0' --run-trace=true ;;
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

nNotice=0; nHonor=0; nDeferred=0
while IFS="$( printf '\t' )" read -r verb honorsTop honorsMax honorsBudget; do
    [ -n "$verb" ] || continue
    args=(); while IFS= read -r -d '' a; do args+=( "$a" ); done < <( argvFor "$verb" ) || true
    if [ "${#args[@]}" -eq 0 ]; then
        # capture-audit 2026-09-04 (H3): a notice-only row needs no hand-written probe here — arm (F) below
        # sweeps every flag in the universe and asserts the notice fires. An HONOURING row is different: its
        # column is a claim that the verb binds, and only a probe on a shape where the budget bites can prove
        # that, so it must have one.
        if [ "$honorsTop" = true ] || [ "$honorsMax" = true ] || [ "$honorsBudget" = true ]; then
            no "(B) $verb declares it honours a knob but has no probe argv in this gate — an honouring column must be PROVED on a binding shape, not declared"
        else
            nDeferred=$(( nDeferred + 1 ))
        fi
        continue
    fi

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
            if [ "$( fnorm "$TMP/plain" )" = "$( fnorm "$TMP/shaped" )" ]; then
                ok "(B) $verb ignores $flag and its stdout is byte-identical (the notice changes no output byte)"
            else
                # same rule as (F): a second plain run separates "the knob changed a byte" from "this verb's
                # stdout is not byte-stable" (--run-trace's duration_ms= is masked by fnorm; anything else that
                # flips is the verb's own defect). Disclosed, not asserted away.
                "$BIN" . "${args[@]}" >"$TMP/plain2" 2>/dev/null </dev/null
                [ "$( fnorm "$TMP/plain" )" = "$( fnorm "$TMP/plain2" )" ] \
                    && no "(B) $verb declares it ignores $flag but the output CHANGED (two plain runs agree) — the column is wrong" \
                    || ok "(B) $verb ignores $flag; its stdout is NOT byte-stable run-to-run (plain != plain), so byte-identity proves nothing here — the verb's own determinism defect, disclosed"
            fi
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

# ── (F) the UNIVERSE (capture-audit 2026-09-04, H3): every flag is in exactly ONE of three buckets ─────
#
# (B) proves the rows kShapingVerbs KNOWS about. The 18 verbs the lens caught (--verify --flags --layout
# --notes --doctor --skipped --field-affinity --naming-calibration --lint-catalog --dmm --plan-lint --affected
# --help-task --arch --mermaid --html --scan-skill --eval) were in NEITHER guard table, and neither (B) nor
# (C) could see them: 54 flag×verb combinations byte-identical at exit 0 with an empty stderr. The family had
# been closed twice (§B9, §B9.2) by enumerating members; this arm derives the members from src/cli.h
# (test/flaguniverse.py) so the verb added tomorrow is swept tomorrow.
#
# For every flag F and each of the three knobs K the outcome of `F K` must be exactly one of:
#     REFUSE   stderr carries the honorsPaging-family refusal ("narrows only --graph-query" / "is honored by")
#     NOTICE   stderr carries "is not read by" (the kShapingVerbs notice)
#     HONOUR   neither, and the output (or exit code) CHANGED — or the verb's kShapingVerbs row declares it
#              honours K, which (B) has already proved binds on a shape where the budget bites
# A fourth outcome — neither sentence and byte-identical output — is the silent class and FAILS by name; both
# sentences at once is two buckets and fails too. The knob values are tiny (--top-k=1 --max-tokens=10
# --token-budget=1) so any verb that reads the field binds even on this small corpus: the inert-probe trap the
# header describes is closed by making the budget bite everywhere, not by trusting bytes.
#
# The sweep runs in a THROWAWAY git copy of test/fixture, never in this tree: several verbs write when they
# run (--note-add, --quality-baseline, --quality-ack, --index-out, --cache, --html=FILE), and the "tree
# unmodified" arm at the bottom is what catches a probe this list forgot. A flag whose PLAIN run refuses as a
# lone modifier (the pairing dialect: "modifies … pass both") has no verb to shape and is counted, not
# asserted; a plain run that refuses for any OTHER reason is a broken probe and fails, so a silent verb cannot
# hide behind a bad argv. --mcp/--listen are servers (the knob is the pass-through for their sub-requests) and
# --help/--version print usage; those four are the only rows not probed, and they are named here.
FCORPUS="$TMP/fcorpus"
cp -R "$ROOT/test/fixture" "$FCORPUS"
( cd "$FCORPUS" && git init -q . && git add -A && git -c user.name=gate -c user.email=gate@gate commit -qm fixture ) >/dev/null 2>&1
printf 'layer test = /no-such-path-xyz/\ndeny test -> render\n' > "$TMP/arch.txt"
printf '#0 total_area at geometry.cpp:3\n' > "$TMP/ftrace.txt"
printf 'not a scip index\n' > "$TMP/fprobe.scip"   # M7 (capture-audit L5): an index that cannot be OPENED now refuses
                                                    # before the map — a readable-but-undecodable one still degrades to
                                                    # the name-based map, which is the verb the knobs shape
python3 "$ROOT/test/flaguniverse.py" "$ROOT/src/cli.h" > "$TMP/universe.tsv"
UROWS="$( grep -c . "$TMP/universe.tsv" )"
[ "$UROWS" -ge 190 ] && ok "(F) derived $UROWS flag rows from src/cli.h" \
                     || no "(F) only $UROWS rows derived — the scrape broke, so the sweep below asserts nothing"
fprobeFor()
{
    case "$1" in
        --query=)        printf '%s' '--query=area' ;;
        --recall=)       printf '%s' '--recall=notes' ;;
        --for=)          printf '%s' '--for=area' ;;
        --pack-task=)    printf '%s' '--pack-task=area' ;;
        --exemplar=)     printf '%s' '--exemplar=area' ;;
        --around=)       printf '%s' '--around=total_area' ;;
        --path=)         printf '%s' '--path=total_area,area_of_triangle' ;;
        --connect=)      printf '%s' '--connect=total_area,area_of_triangle' ;;
        --edit-check=)   printf '%s' '--edit-check=total_area' ;;
        --expand=)       printf '%s' '--expand=total_area' ;;
        --outline=)      printf '%s' '--outline=total_area' ;;
        --at=)           printf '%s' '--at=geometry.cpp:3' ;;
        --from-trace=)   printf '%s' "--from-trace=$TMP/ftrace.txt" ;;
        --cache=)        printf '%s' "--cache=$TMP/fprobe.cache" ;;
        --scip=)         printf '%s' "--scip=$TMP/fprobe.scip" ;;
        --index-out=)    printf '%s' "--index-out=$TMP/fprobe.idx" ;;
        --pin-census=)   printf '%s' "--pin-census=$TMP/fprobe.tsv" ;;
        --html=)         printf '%s' "--html=$TMP/fprobe.html" ;;
        --run-trace=)    printf '%s' '--run-trace=true' ;;
        --note-add=)     printf '%s' '--note-add=total_area: probe' ;;
        --scan-skill=)   printf '%s' "--scan-skill=$ROOT/skills/ripwire-orient/SKILL.md" ;;
        --plan-lint=)    printf '%s' "--plan-lint=$ROOT/CONTRIBUTING.md" ;;
        --arch=)         printf '%s' "--arch=$TMP/arch.txt" ;;
        --affected=)     printf '%s' '--affected=geometry.cpp' ;;
        --test-gate=)    printf '%s' '--test-gate=geometry.cpp' ;;
        --situ=)         printf '%s' '--situ=geometry.cpp' ;;
        --help-task=)    printf '%s' '--help-task=review' ;;
        --verify=)       printf '%s' '--verify=calls(total_area,area_of_triangle)' ;;
        --layout=)       printf '%s' '--layout=Point' ;;
        --field-affinity=) printf '%s' '--field-affinity=Point' ;;
        --lego=)         printf '%s' '--lego=Point' ;;
        --whereis=)      printf '%s' '--whereis=total_area' ;;
        --owners=)       printf '%s' '--owners=total_area' ;;
        --graph-query=)  printf '%s' '--graph-query=kind(all,fn)' ;;   # a multi-row set, so --top-k=1 has something to cut
        --callers=|--callees=|--uses=|--impact=|--mentions=|--safe-delete=) printf '%s' "${1}total_area" ;;
        --quality-ack=)  printf '%s' '--quality-ack=probe' ;;
        --order=)        printf '%s' '--order=stable' ;;
        --rank-by=)      printf '%s' '--rank-by=churn' ;;
        --format=)       printf '%s' '--format=columnar' ;;
        --color-by=)     printf '%s' '--color-by=lang' ;;
        --grep-scope=)   printf '%s' '--grep-scope=file' ;;
        --grep-in=)      printf '%s' '--grep-in=any' ;;
        --legend=)       printf '%s' '--legend=compact' ;;
        --slice-flow=)   printf '%s' '--slice-flow=back' ;;
        --agent=)        printf '%s' '--agent=codex' ;;
        --export=)       printf '%s' '--export=cc.json' ;;
        --quality-panel=) printf '%s' '--quality-panel=default' ;;
        --limit=)        printf '%s' '--limit=3' ;;
        --offset=)       printf '%s' '--offset=1' ;;
        --max-file-size=) printf '%s' '--max-file-size=1M' ;;
        --pack-budget-bytes=) printf '%s' '--pack-budget-bytes=1000' ;;
        --top-k=|--max-tokens=|--token-budget=) return 1 ;;   # the knobs themselves
        --mcp|--listen=|--help|--version) return 1 ;;         # servers and usage — named in the header
        *=)              printf '%s' "${1}zzqq9" ;;
        *)               printf '%s' "$1" ;;
    esac
}
# does the kShapingVerbs row for FLAG declare it honours KNOB? (rows.tsv: name, top, max, budget; a nested
# row such as "--stray-content --plan" is matched on its LAST token)
fdeclared()
{
    local flag="$1" knob="$2" col
    case "$knob" in --top-k=*) col=2 ;; --max-tokens=*) col=3 ;; *) col=4 ;; esac
    awk -F'\t' -v f="$flag" -v c="$col" '{ n = split( $1, t, " " ); if( $1 == f || t[ n ] == f ) { print $c; exit } }' "$TMP/rows.tsv"
}
# Two things stdout may legitimately vary on between two runs of the SAME argv, and how each is handled so
# the sweep can never blame a knob for them: (a) --run-trace's duration_ms= is a documented MEASUREMENT
# (verbs_change.h "Determinism, honestly scoped") — masked before comparing; (b) a verb's first run on a
# fresh corpus can leave state a second run reads (--doctor's cache-dir bytes=) — every probe is WARMED UP
# once and the second plain run is the one measured. Anything still flipping after both is disclosed by name
# through the tie-break in the notice branch, never asserted away and never counted as a knob read.
# (fnorm itself is defined beside ok/no at the top of this file — see I1 there.)
REFUSEPAT='narrows only --graph-query|--max-tokens is honored by|--token-budget is honored by'
NOTICEPAT='is not read by'
MODIFIERPAT='modif|pass both|pass it too|pass them|only applies|narrows|requires|needs|is read by|read only|honored only by|— pass|pass one|composes with|applies only|selects|re-serializes'
fRefuse=0; fNotice=0; fHonour=0; fModifier=0; fBad=0
while IFS="$( printf '\t' )" read -r flag kind example policy; do
    [ -n "$flag" ] || continue
    case "$kind" in int) probe="${flag}2" ;; *) probe="$( fprobeFor "$flag" )" || continue ;; esac
    case "$flag" in --top-k=|--max-tokens=|--token-budget=) continue ;; esac
    ( cd "$FCORPUS" && "$BIN" . $probe --no-cache >/dev/null 2>/dev/null </dev/null )   # warm-up: cold-vs-warm state is not a knob
    ( cd "$FCORPUS" && "$BIN" . $probe --no-cache >"$TMP/f.plain" 2>"$TMP/f.plain.err" </dev/null ); rcP=$?
    if [ "$rcP" -ne 0 ] && [ ! -s "$TMP/f.plain" ] && grep -qE "$MODIFIERPAT" "$TMP/f.plain.err"; then
        fModifier=$(( fModifier + 1 )); continue         # a lone modifier: no verb answered, nothing to shape
    fi
    # A plain run that refuses for the VERB'S OWN reason (a bogus value, a missing fixture) still goes through
    # the knob loop: both guards speak from validateConfig, BEFORE any handler, so the refusal or the notice
    # must be on stderr whether or not the verb then answered. A silent verb cannot hide behind a bad probe —
    # it lands in the fourth bucket below by name.
    for knob in --top-k=1 --max-tokens=10 --token-budget=1; do
        ( cd "$FCORPUS" && "$BIN" . $probe "$knob" --no-cache >"$TMP/f.knob" 2>"$TMP/f.knob.err" </dev/null ); rcK=$?
        isRefuse=0; isNotice=0
        grep -qE "$REFUSEPAT" "$TMP/f.knob.err" && isRefuse=1
        grep -qE "$NOTICEPAT" "$TMP/f.knob.err" && isNotice=1
        if [ "$isRefuse" = 1 ] && [ "$isNotice" = 1 ]; then
            fBad=$(( fBad + 1 )); no "(F) $probe $knob: BOTH the refusal and the notice fired — two buckets for one flag"
        elif [ "$isRefuse" = 1 ]; then
            fRefuse=$(( fRefuse + 1 ))
        elif [ "$isNotice" = 1 ]; then
            fNotice=$(( fNotice + 1 ))
            if [ "$( fnorm "$TMP/f.plain" )" != "$( fnorm "$TMP/f.knob" )" ]; then
                # a changed byte under a "not read" notice is a wrong column — UNLESS the verb's stdout is not
                # byte-stable to begin with even after the warm-up and the mask. A second plain run tells the
                # two apart; the nondeterminism is DISCLOSED by name, never asserted away, and is its own
                # defect for the determinism lane (M14), not evidence about the knob.
                ( cd "$FCORPUS" && "$BIN" . $probe --no-cache >"$TMP/f.plain2" 2>/dev/null </dev/null )
                if [ "$( fnorm "$TMP/f.plain" )" = "$( fnorm "$TMP/f.plain2" )" ]; then
                    fBad=$(( fBad + 1 )); no "(F) $probe $knob: the notice says the knob is not read, yet stdout CHANGED (and two plain runs agree, so the knob did it)"
                else
                    ok "(F) $probe $knob: notice fired; stdout is NOT byte-stable run-to-run on this verb (plain != plain), so byte-identity proves nothing here — a determinism defect of the verb, disclosed, not a knob read"
                fi
            fi
        elif [ "$rcK" -ne "$rcP" ] || [ "$( fnorm "$TMP/f.plain" )" != "$( fnorm "$TMP/f.knob" )" ]; then
            fHonour=$(( fHonour + 1 ))
        elif [ "$( fdeclared "${flag%%=*}" "$knob" )" = true ]; then
            fHonour=$(( fHonour + 1 ))                    # declared in kShapingVerbs and proved binding by (B)
        else
            fBad=$(( fBad + 1 )); no "(F) $probe $knob: SILENT — exit $rcK both ways, stdout byte-identical ($( wc -c <"$TMP/f.knob" | tr -d ' ' ) B), no refusal, no notice: accepted and ignored"
        fi
    done
done < "$TMP/universe.tsv"
[ "$fBad" -eq 0 ] && ok "(F) every flag×knob is in exactly one bucket: refuse=$fRefuse notice=$fNotice honour=$fHonour (lone modifiers skipped: $fModifier)" \
                  || no "(F) $fBad flag×knob combinations are outside the three buckets (refuse=$fRefuse notice=$fNotice honour=$fHonour modifiers=$fModifier)"
{ [ "$fRefuse" -ge 60 ] && [ "$fNotice" -ge 60 ] && [ "$fHonour" -ge 30 ]; } \
    && ok "(F) all three buckets are populated (the sweep measured something)" \
    || no "(F) a bucket is implausibly small (refuse=$fRefuse notice=$fNotice honour=$fHonour) — the sweep is not covering the universe"
[ "$nDeferred" -gt 0 ] && ok "(B) $nDeferred notice-only rows carry no hand-written probe and were asserted by (F) instead" || true

# ── the harness must not mutate the tree ───────────────────────────────────────────────────────────────
git status --porcelain 2>/dev/null | grep -vE '^\?\? (build|asan|tsan)' > "$TMP/status.after"
STRAY="$( comm -13 "$TMP/status.before" "$TMP/status.after" 2>/dev/null | head -5 )"
[ -z "$STRAY" ] && ok "gate left the tree unmodified" \
                || { no "gate MUTATED the tree:"; printf '%s\n' "$STRAY" | sed 's/^/        /'; }

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
