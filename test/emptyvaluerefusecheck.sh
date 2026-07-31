#!/usr/bin/env bash
# emptyvaluerefusecheck.sh — §B5 gate: EVERY value-taking table flag refuses an EMPTY value.
#
# §A9 V1-4 made `--flag=` (usually a shell variable that expanded to nothing) a REFUSAL rather than a
# request for the whole ranked map, and expressed that refusal ONCE in kViewFlags' needs=/example= columns.
# Nine of the then-33 rows were left with needs=nullptr, so the refusal they inherit was "none":
#
#     ripwire test/fixture --since=        →  exit 0, the default 6000-symbol map, stderr EMPTY   (before)
#     ripwire test/fixture --since=zzqq9   →  a loud refusal                                      (one keystroke apart)
#
# The audit's sharpest case is the question-shaped `--eval-*=` / `--since=`: an agent whose $FILE is unset
# gets an atlas where it asked a question, at exit 0, with nothing on stderr to read. OWNER RULING
# (PLAN_outputAudit3_2026-07-29.md §B5, 2026-07-29): refuse-all — all nine rows carry needs=/example=,
# including the five config-passthrough flags, and an empty value refuses uniformly.
#
# The gate asserts the CONTRACT, not the sentence: exit 1, the flag NAMED, the real problem stated, a
# RUNNABLE example — plus that the refusal is byte-identical under --json (the table machinery prints to
# stderr before any serializer is chosen, and that has to stay true), and that a NON-empty value for the
# same flag is untouched (a flag-triggered refusal would be a far worse bug than the one being fixed).
#
#   bash test/emptyvaluerefusecheck.sh                                     # build/ripwire
#   bash test/emptyvaluerefusecheck.sh build_base/ripwire                  # must FAIL (pre-fix binary)
#   RIPWIRE_BIN=asan/ripwire bash test/emptyvaluerefusecheck.sh

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
echo "emptyvaluerefusecheck: BIN=$BIN"
git status --porcelain 2>/dev/null | grep -vE '^\?\? (build|asan|tsan)' > "$TMP/status.before"

# ── the nine §B5 flags, plus three of the 24 already-compliant rows as the reference dialect ───────────
# The compliant rows are in the SAME list on purpose: they are what "fixed" looks like, so a change that
# waters the shared refusal down cannot go green by lowering the bar for the nine.
B5_FLAGS="--mcp-token --eval-mined --eval-skills --cache --index-out --since --scip --lint-rules --eval-stray"
REF_FLAGS="--grep --impact --for"

refuseCase()
{
    local flag="$1" label="$2"
    "$BIN" test/fixture "$flag=" >"$TMP/out" 2>"$TMP/err"; local rc=$?

    [ "$rc" -eq 1 ] && ok "$label $flag= exits 1" \
                    || no "$label $flag= exits $rc (expected 1) — an empty value is a mistyped verb, not a request for the map"
    # the map must not be emitted: exit 1 with 200 KB of atlas on stdout is the same false answer
    [ -s "$TMP/out" ] && no "$label $flag= still wrote $( wc -c <"$TMP/out" | tr -d ' ' ) bytes to stdout" \
                      || ok "$label $flag= wrote nothing to stdout"
    grep -q -- "$flag" "$TMP/err" && ok "$label $flag= refusal NAMES the flag" \
                                  || no "$label $flag= refusal does not name the flag: [$( head -c 200 "$TMP/err" )]"
    grep -q "is empty" "$TMP/err" && ok "$label $flag= refusal states the real problem (empty value)" \
                                  || no "$label $flag= refusal does not state the problem: [$( head -c 200 "$TMP/err" )]"
    grep -q "e\.g\. $flag" "$TMP/err" && ok "$label $flag= refusal shows a runnable $flag example" \
                                      || no "$label $flag= refusal carries no runnable example: [$( head -c 200 "$TMP/err" )]"
}

for f in $B5_FLAGS;  do refuseCase "$f" "§B5"; done
for f in $REF_FLAGS; do refuseCase "$f" "ref"; done

# ── the refusal must not depend on the OUTPUT MODE: it is printed before a serializer is chosen ────────
for f in --since --cache --eval-mined; do
    "$BIN" test/fixture "$f=" >/dev/null 2>"$TMP/err.xml";  rcx=$?
    "$BIN" test/fixture "$f=" --json >/dev/null 2>"$TMP/err.json"; rcj=$?
    # rcx must be 1 as well: two IDENTICAL non-refusals also compare equal, and a mode-parity assertion
    # that passes on a binary which refuses in neither mode is measuring nothing.
    if [ "$rcx" = 1 ] && [ "$rcx" = "$rcj" ] && [ -s "$TMP/err.xml" ] && cmp -s "$TMP/err.xml" "$TMP/err.json"; then
        ok "$f= refusal is byte-identical under --json (exit $rcx)"
    else
        no "$f= refusal differs under --json (exit $rcx vs $rcj): [$( head -c 160 "$TMP/err.json" )]"
    fi
done

# ── the refusal is triggered by the VALUE, not by the flag ─────────────────────────────────────────────
# A non-empty value must reach the member exactly as before. These values are deliberately nonsense: the
# point is that the run gets PAST the parser (whatever the verb then decides), never that it succeeds.
# Two of them WRITE when they reach their handler (--cache= a cache, --index-out= two index artifacts), so
# their nonsense value is a path under $TMP: a gate that leaves state in the tree it tests is a liability
# (an early run of this one left three zzqq9* files in the repo root).
value(){ case "$1" in --cache|--index-out) printf '%s' "$TMP/zzqq9nosuchvalue" ;; *) printf 'zzqq9nosuchvalue' ;; esac; }
for f in $B5_FLAGS; do
    "$BIN" test/fixture "$f=$( value "$f" )" >/dev/null 2>"$TMP/err"
    grep -q "is empty" "$TMP/err" \
        && no "$f=<non-empty> was refused as EMPTY — the guard is testing the flag, not the value" \
        || ok "$f=<non-empty> is not caught by the empty-value guard"
done

# ── §B5 (capture-audit-4): the sweep is DERIVED FROM THE TABLE, not from a list in this file ───────────
#
# The named list above is a HAND-PICKED sample and that is exactly how §B5 happened: last round's refuse-all
# ruling swept the 33 kViewFlags rows, this gate pinned nine of them by name, and the 40 hand-written arms in
# parseArgs — never in any list — went on silently accepting an empty value. Four of them did
# (`--listen=` became a live stdio MCP server at exit 0; `--owners=`/`--outline=`/`--ack-only=` emitted a
# report or the default map). Trap-ledger #6: "a ruling that produces a table sweeps the table, not the
# surface."
#
# So the arms below are read OUT OF src/cli.h at run time, one probe per row, and the expected exit code
# comes from the row's own EmptyValue column:
#     Refuse         → exit 1, empty stdout, a refusal naming the flag
#     HandlerRefuses → exit 1 (the verb's own sentence; this gate does not pin its wording, only the code)
#     Meaningful     → exit 0 (`--situ=` IS `--situ`) — the ONE outcome that must not be assumed silently
# A row that is added without a policy cannot compile (cli.h's consteval floor), and a row whose policy
# disagrees with the binary fails here. Neither half alone is enough: the floor checks the DECLARATION, this
# checks the BEHAVIOUR.
if command -v python3 >/dev/null 2>&1; then
    python3 - "$ROOT" > "$TMP/rows.tsv" <<'PY'
import io, re, sys
src = io.open( sys.argv[1] + "/src/cli.h", encoding = "utf-8" ).read()
start = src.index( "inline constexpr ViewFlag kViewFlags[] =" )
end   = src.index( "\n};", start )
body  = re.sub( r'//[^\n]*', '', src[ start:end ] )         # a row comment must never be read as a row
for prefix, policy in re.findall( r'\{\s*"(--[^"]+)"\s*,\s*&Config::\w+\s*,\s*EmptyValue::(\w+)', body ):
    print( "%s\t%s" % ( prefix, policy ) )
PY
    ROWCOUNT="$( wc -l < "$TMP/rows.tsv" | tr -d ' ' )"
    [ "$ROWCOUNT" -ge 50 ] && ok "derived $ROWCOUNT kViewFlags rows (prefix + EmptyValue) from src/cli.h" \
                           || no "only $ROWCOUNT rows parsed out of src/cli.h — the scrape broke, so the sweep below asserts nothing"

    # A WRITE-PRONE row is probed against a THROWAWAY git corpus, never test/fixture — trap #14: a gate whose
    # own vectors write into the tree under test is a liability, and this sweep found that out by leaving a
    # .ripwire_quality_acks behind on its first run (`--quality-ack=` is EmptyValue::Meaningful, so the sweep
    # runs it, and running it is what writes the acks file). The copy is git-initialised because several
    # Meaningful rows need a repo — probing them in a bare directory would make them exit 1 for a reason that
    # has nothing to do with the empty value, which is a gate passing (or failing) for the wrong reason.
    #
    # The list below is NOT load-bearing: it is a convenience, and the "gate left the tree unmodified" arm at
    # the very bottom is the machine check. A future write-prone row that is missing from this list fails
    # there, loudly, instead of silently dirtying the fixture.
    WRITECORPUS="$TMP/writecorpus"
    cp -R test/fixture "$WRITECORPUS"
    ( cd "$WRITECORPUS" && git init -q . && git add -A \
      && git -c user.name=gate -c user.email=gate@gate commit -qm fixture ) >/dev/null 2>&1
    WRITE_PRONE=" --quality-ack= "

    nRefuse=0; nHandler=0; nMeaning=0; nBad=0
    while IFS="$( printf '\t' )" read -r prefix policy; do
        [ -n "$prefix" ] || continue
        corpus="test/fixture"
        case "$WRITE_PRONE" in *" $prefix "*) corpus="$WRITECORPUS" ;; esac
        # --listen= would BIND A SOCKET on a non-empty value; the empty probe is the whole point here and it
        # refuses before any transport is chosen, so the probe is safe. stdin is closed for every probe so a
        # server-shaped verb cannot hang the gate.
        "$BIN" "$corpus" "$prefix" >"$TMP/out" 2>"$TMP/err" </dev/null; rc=$?
        case "$policy" in
            Refuse)
                if [ "$rc" -eq 1 ] && [ ! -s "$TMP/out" ] && grep -q -- "${prefix%=}" "$TMP/err"; then
                    nRefuse=$(( nRefuse + 1 ))
                else
                    nBad=$(( nBad + 1 ))
                    no "table sweep: $prefix is EmptyValue::Refuse but exited $rc with $( wc -c <"$TMP/out" | tr -d ' ' ) stdout bytes: [$( head -c 120 "$TMP/err" )]"
                fi ;;
            HandlerRefuses)
                if [ "$rc" -eq 1 ] && [ ! -s "$TMP/out" ]; then
                    nHandler=$(( nHandler + 1 ))
                else
                    nBad=$(( nBad + 1 ))
                    no "table sweep: $prefix is EmptyValue::HandlerRefuses but its handler exited $rc with $( wc -c <"$TMP/out" | tr -d ' ' ) stdout bytes"
                fi ;;
            Meaningful)
                if [ "$rc" -eq 0 ]; then
                    nMeaning=$(( nMeaning + 1 ))
                else
                    nBad=$(( nBad + 1 ))
                    no "table sweep: $prefix is EmptyValue::Meaningful (\"\" is a real value) but exited $rc: [$( head -c 120 "$TMP/err" )]"
                fi ;;
            *)  nBad=$(( nBad + 1 )); no "table sweep: $prefix carries an EmptyValue this gate does not know: '$policy'" ;;
        esac
    done < "$TMP/rows.tsv"

    [ "$nBad" -eq 0 ] && ok "table sweep: all $ROWCOUNT rows behave as their EmptyValue column declares ($nRefuse Refuse, $nHandler HandlerRefuses, $nMeaning Meaningful)" \
                      || no "table sweep: $nBad of $ROWCOUNT rows disagree with their own EmptyValue column"
    # the three policies must all be POPULATED. A sweep that is 56/56 Refuse would pass every arm above while
    # having quietly deleted the distinction the column exists to record.
    { [ "$nRefuse" -gt 0 ] && [ "$nHandler" -gt 0 ] && [ "$nMeaning" -gt 0 ]; } \
        && ok "table sweep: all three EmptyValue policies are in use — the column is a decision, not a formality" \
        || no "table sweep: a policy is unused (Refuse=$nRefuse HandlerRefuses=$nHandler Meaningful=$nMeaning)"
else
    no "python3 is required for the §B5 table-derived sweep — the gate does not skip"
fi

# ── §B5: the arms a table CANNOT hold still refuse, and they are enumerated here on purpose ────────────
# --expand=/--outline= split a comma list into a vector<string>, so they will never be kViewFlags rows and
# the derived sweep above can never see them. --outline= was the fourth §B5 arm (it had the split and not
# the refusal). Naming them here is the honest cost of the residue: 17 arms stay hand-written, and the
# value-taking ones among them each need a pin somewhere.
for f in --expand --outline; do refuseCase "$f" "§B5-hand"; done

# ── a control: the guard is not vacuous ────────────────────────────────────────────────────────────────
# If `--since=` refuses, the same corpus with NO flag at all must still produce a map at exit 0, or the
# assertions above would pass on a binary that refuses everything.
"$BIN" test/fixture >"$TMP/plain" 2>/dev/null; rc=$?
[ "$rc" -eq 0 ] && [ -s "$TMP/plain" ] \
    && ok "control: the plain default map still exits 0 with $( wc -c <"$TMP/plain" | tr -d ' ' ) bytes" \
    || no "control: the plain default map exits $rc — this gate is passing for the wrong reason"

# ── the harness must not mutate the tree it tests ──────────────────────────────────────────────────────
# Compared against the status captured at the top of the run, not against a clean checkout: this gate is
# normally run mid-change with the tree already dirty.
git status --porcelain 2>/dev/null | grep -vE '^\?\? (build|asan|tsan)' > "$TMP/status.after"
STRAY="$( comm -13 "$TMP/status.before" "$TMP/status.after" 2>/dev/null | head -5 )"
[ -z "$STRAY" ] && ok "gate left the tree unmodified" \
                || { no "gate MUTATED the tree:"; printf '%s\n' "$STRAY" | sed 's/^/        /'; }

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
