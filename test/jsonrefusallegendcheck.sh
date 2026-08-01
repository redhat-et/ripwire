#!/usr/bin/env bash
# jsonrefusallegendcheck.sh — §B1.4 + §B1.5 gates, two SELF-DESCRIPTION defects that
# share one fixture set.
#
# §B1.4 — the `--json`-unsupported refusal:
#   * named a flag the user NEVER TYPED: `--regex=PAT` sets both c.grep and c.grepRegex, the --grep arm
#     matched first, and the refusal told a --regex caller that "--grep" was unsupported;
#   * carried NO runnable example, while its closest sibling (the --format=columnar refusal) has one;
#   * called the output-SHAPE modifiers (--format=columnar, --format=candidates, --detail, --scip) "verbs",
#     which sends the reader looking for a verb to drop instead of an encoding to pick.
#
# §B1.5 — columnar output shipped the XML ROW legend describing `p=file:line` / `t=` / `n=` attributes it
#   never emits, and had NO legend of its own: the path-table/parallel-array zip contract, the n= alignment
#   rule, the empty-page shape and the `&#44;` comma escape lived only in source comments (columnar.h).
#   --help's --format one-liner also named the wrong field list for --uses (it emits path,line,role,in_id,
#   not path,name,line,kind).
#
# Assertions are on MEANING (a flag is named / an example is runnable / a contract clause is present), never
# on whole sentences.
#
# Usage: bash test/jsonrefusallegendcheck.sh [path/to/ripwire]
# Exits non-zero on any failure; DOES NOT touch regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"   # house convention: the suite passes the binary via RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

echo "jsonrefusallegendcheck: BIN=$BIN"
[ -x "$BIN" ] || { no "binary not executable: $BIN"; echo "FAILURES ABOVE"; exit 1; }
command -v xmllint >/dev/null 2>&1 || { no "xmllint is REQUIRED by this gate — not found"; echo "FAILURES ABOVE"; exit 1; }

SBX="$TMP/sbx"; mkdir -p "$SBX"
cat > "$SBX/a.py" <<'PY'
def alpha():
    return beta()

def beta():
    return 1
PY

# ─────────────────────────── §B1.4: the --json refusal ───────────────────────────────────────────────────
"$BIN" "$SBX" --regex="bet.*" --json > "$TMP/regex.out" 2>"$TMP/regex.err"; RC=$?
[ $RC -eq 1 ] && ok "--regex --json refuses with exit 1" || no "--regex --json exited $RC, want 1"
[ -s "$TMP/regex.err" ] || { no "the refusal wrote nothing to stderr"; echo "FAILURES ABOVE"; exit 1; }
MSG="$( cat "$TMP/regex.err" )"

# (1) the flag the user ACTUALLY typed
case "$MSG" in *--regex*) ok "the refusal names --regex, the flag the user typed" ;;
               *)         no "the refusal does not name --regex: $MSG" ;; esac
case "$MSG" in *--grep*)  no "the refusal still names --grep, a flag the user never typed: $MSG" ;;
               *)         ok "the refusal no longer names --grep" ;; esac

# (2) a RUNNABLE example — and it must actually run
EG="$( printf '%s' "$MSG" | grep -oE 'ripwire <dir> --[a-z-]+=[A-Za-z_]+ --json' | head -1 )"
if [ -n "$EG" ]; then
    ok "the refusal carries an example ($EG)"
    EGFLAG="$( printf '%s' "$EG" | grep -oE '\-\-[a-z-]+=[A-Za-z_]+' | head -1 | sed 's/=.*//' )"
    "$BIN" "$SBX" "${EGFLAG}=beta" --json >/dev/null 2>&1 \
        && ok "the example's flag ($EGFLAG) really is --json-supported" \
        || no "the example names $EGFLAG, which itself refuses under --json"
else
    no "the refusal carries NO runnable example (its --format=columnar sibling has one): $MSG"
fi

# (3) a SHAPE MODIFIER must not be described as a verb
"$BIN" "$SBX" --callers=beta --format=columnar --json > /dev/null 2>"$TMP/shape.err"; RC=$?
[ $RC -eq 1 ] && ok "--callers --format=columnar --json refuses with exit 1" || no "--callers --format=columnar --json exited $RC, want 1"
SHAPE="$( cat "$TMP/shape.err" )"
case "$SHAPE" in *--format=columnar*) ok "the shape-modifier refusal names --format=columnar" ;;
                 *)                   no "the shape-modifier refusal does not name --format=columnar: $SHAPE" ;; esac
if printf '%s' "$SHAPE" | grep -qiE 'supported verbs?: *(the default map|--)'; then
    no "--format=columnar is still presented as a 'verb' (the refusal enumerates it against 'supported verbs'): $SHAPE"
else
    ok "--format=columnar is not presented as a verb"
fi
# 'format' alone would match the flag spelling itself — the word must be a CATEGORY the reader can act on
printf '%s' "$SHAPE" | grep -qiE 'shape|encoding' \
    && ok "the shape-modifier refusal says WHAT KIND of flag it refused" \
    || no "the shape-modifier refusal gives the reader no category for the flag: $SHAPE"

# the verb arm keeps naming the supported set (nothing regressed)
printf '%s' "$MSG" | grep -q -- '--pack-task' \
    && ok "the verb refusal still enumerates the supported set" \
    || no "the verb refusal lost its supported-set enumeration: $MSG"

# ─────────────────────────── §B1.5: the columnar legend ──────────────────────────────────────────────────
for verb in "--callers=beta" "--callees=alpha" "--uses=beta" "--impact=beta"; do
    OUT="$( "$BIN" "$SBX" "$verb" --format=columnar 2>/dev/null )"
    [ -n "$OUT" ] || { no "$verb --format=columnar produced no output"; continue; }
    # extract the columnar legend by delimiter, not by a `[^>]*` class: the legend legitimately NAMES the
    # elements it describes (<paths>, <cols>), and --uses ships its own verb legend ahead of it
    LEG=""
    REST="${OUT#*<!-- format=columnar}"
    [ "$REST" != "$OUT" ] && LEG="format=columnar${REST%%-->*}"
    if [ -z "$LEG" ]; then
        no "$verb: NO columnar legend — the encoding contract (zip-by-index, n=, &#44;) is source-comment-only"
        continue
    fi
    ok "$verb: carries a columnar legend"
    for clause in 'paths' 'n=' '&#44;' 'fields='; do
        case "$LEG" in *"$clause"*) ok "$verb legend states '$clause'" ;;
                       *)           no "$verb legend never mentions '$clause'" ;; esac
    done
    # the legend must DEFUSE the row-attribute description it ships next to, not repeat it
    printf '%s' "$LEG" | grep -qiE 'not emitted|no per-row|instead of' \
        && ok "$verb legend says the per-row attributes are NOT emitted in this form" \
        || no "$verb legend does not correct the row-attribute claim it ships beside: $LEG"
    printf '%s\n' "$OUT" | xmllint --noout - 2>/dev/null \
        && ok "$verb columnar output still well-formed XML with the legend" \
        || no "$verb columnar output is not well-formed XML"
done

# the empty-page shape the legend promises must be the shape actually emitted
EMPTY="$( "$BIN" "$SBX" --callers=beta --format=columnar --limit=1 --offset=99 2>/dev/null )"
case "$EMPTY" in *'n="0"'*) ok "an out-of-range page really does emit n=\"0\" (the legend's empty-page clause)" ;;
                 *)         no "an out-of-range page does not emit n=\"0\": $( printf '%s' "$EMPTY" | tail -c 200 )" ;; esac

# ── --help's --format one-liner must name --uses' REAL columns ───────────────────────────────────────────
HELP="$( "$BIN" --help 2>&1 )"
[ -n "$HELP" ] || { no "--help produced nothing"; echo "FAILURES ABOVE"; exit 1; }
FMTLINE="$( printf '%s\n' "$HELP" | grep -A 6 -- '--format=xml|columnar' )"
[ -n "$FMTLINE" ] || { no "could not locate the --format one-liner in --help"; echo "FAILURES ABOVE"; exit 1; }
# --uses emits path,line,role,in_id — a help text that names only name/line/kind mis-describes it
printf '%s' "$FMTLINE" | grep -q 'role' \
    && ok "--help's --format text accounts for --uses' role/in_id columns" \
    || no "--help's --format text still names only the symbol-row columns, mis-describing --uses"
# and the claim must be TRUE of the binary
USESCOLS="$( "$BIN" "$SBX" --uses=beta --format=columnar 2>/dev/null | grep -o 'fields="[^"]*"' | head -1 )"
[ "$USESCOLS" = 'fields="path,line,role,in_id"' ] \
    && ok "--uses columnar really emits $USESCOLS" \
    || no "--uses columnar emits $USESCOLS — update the help text to match the binary, not the other way round"

# ─────────────────────────── §B1.1 (capture-audit-4, 2026-07-30): the eight forgotten arms ────────────────
# jsonUnsupportedVerb() had no arm at all for these eight verb surfaces, so they fell through to
# `return nullptr` and dispatched normally — XML at exit 0 under --json. dir/args are chosen so the verb
# actually REACHES a successful dispatch pre-fix (found symbol, real git repo, valid id) rather than
# tripping some UNRELATED refusal of its own (not-a-git-repo / file-not-indexed / id-out-of-range /
# struct-not-found) that would happen to also name the flag and produce a false red-first pass — five of
# the eight (whereis/stray-content/abi/exercises/community) do have such an unrelated refusal, and $SBX (no
# git history, one untracked file, no modules) trips every one of them; only doc-drift/flags/layout are
# shaped so ANY root reaches real dispatch. $ROOT (this checkout) and its own test/fixture supply real git
# history / an indexed symbol / a real module id / a real struct for the other five.
check_json_refuses()
{
    local desc="$1"; shift
    local dir="$1";  shift
    local want="$1"; shift
    OUT="$( "$BIN" "$dir" "$@" --json 2>"$TMP/arm.err" )"; RC=$?
    ERRTXT="$( cat "$TMP/arm.err" )"
    [ "$RC" -eq 1 ] && ok "$desc: --json exits 1" || no "$desc: --json exited $RC (want 1): $ERRTXT"
    case "$ERRTXT" in *"$want"*) ok "$desc: refusal names $want" ;;
                      *)         no "$desc: refusal does not name $want: $ERRTXT" ;; esac
    [ -z "$OUT" ] && ok "$desc: stdout stayed empty (no XML leaked before the refusal)" \
                  || no "$desc: stdout was NOT empty under a refusal: $( printf '%s' "$OUT" | head -c 120 )"
}
check_json_refuses "--whereis"                 "$ROOT"                "--whereis"       --whereis=main
check_json_refuses "--stray-content"           "$ROOT"                "--stray-content" --stray-content
check_json_refuses "--stray-content --abi"     "$ROOT"                "--abi"           --stray-content --abi
check_json_refuses "--exercises"               "$ROOT/test/fixture"   "--exercises"     --exercises=notes.md
check_json_refuses "--community=ID"            "$ROOT"                "--community"     --community=1
check_json_refuses "--doc-drift"               "$SBX"                 "--doc-drift"     --doc-drift
check_json_refuses "--flags"                   "$SBX"                 "--flags"         --flags
check_json_refuses "--layout"                  "$ROOT"                "--layout"        --layout=Config

# §B1.2: the supported-set sentence must now mention --metrics, and --metrics itself must still WORK under
# --json (it was never actually refused — the gap was purely that the refusal never told a caller it existed).
"$BIN" "$SBX" --tree --json >/dev/null 2>"$TMP/metrics.err"
case "$( cat "$TMP/metrics.err" )" in *--metrics*) ok "the supported-set sentence now names --metrics" ;;
                                      *)           no "the supported-set sentence still omits --metrics: $( cat "$TMP/metrics.err" )" ;; esac
"$BIN" "$SBX" --metrics --json >/dev/null 2>"$TMP/metrics2.err"; RC=$?
[ "$RC" -eq 0 ] && ok "--metrics --json (bare) really is supported (exits 0)" \
                || no "--metrics --json exited $RC — the sentence now claims support it doesn't have"

# ── §B1.5 (capture-audit-4, wave 3): the FIVE self-eval verbs ────────────────────────────────────────────
#
# The wave-2 verifier's 96-flag sweep concluded only --eval-stray still emitted XML at exit 0 under --json.
# True, and not the whole class: --eval / --eval-retrieval / --eval-mined / --eval-skills emit PLAIN TEXT
# tables, so an XML-shaped probe cannot see them while they accept and ignore --json just as silently.
#
# CRITICAL, and the reason each probe below is given real inputs: on a corpus where a verb refuses for an
# UNRELATED reason (no doc-commented symbols, a missing labels file) the flag never binds, and a probe that
# reads the resulting exit 1 as "it refuses --json" passes on the pre-fix binary. That is the §B9 inert-vs-
# ignoring caveat applied here. So the fixtures are ones where each verb SUCCEEDS, and every arm asserts the
# refusal SENTENCE, not merely a non-zero exit.
mkdir -p "$SBX/sub"
cat > "$SBX/sub/lib.py" <<'PY'
def gamma( x ):
    """Compute the gamma adjustment for a sample value."""
    return delta( x ) + 1


def delta( x ):
    """Return the delta baseline used by gamma."""
    return x * 2
PY
printf '{"query":"gamma delta adjustment","gold_files":[{"path":"a.py"},{"path":"sub/lib.py"}]}\n' > "$TMP/mined.jsonl"

# --eval-stray scores a CLASSIFIER against labelled branch verdicts. On this repo the labelled branches do
# not exist, so it runs, emits its report and exits 3 ("scored below threshold") — which is a verb that RAN.
# okCodes exists for exactly that: the control asks "did the flag get a chance to bind", not "did the eval
# pass". Collapsing the two would make the fixture's own accuracy a silent precondition of a --json gate.
printf 'feat-unmerged\tunmerged\nfeat-merged\tmerged\n' > "$TMP/strayfixture.tsv"

check_eval_refuses()
{
    local desc="$1" root="$2" want="$3" okCodes="$4"; shift 4
    # the CONTROL first: without --json this shape must actually RUN, or the refusal arm below is measuring a
    # verb that was refusing anyway (the §B9 inert-vs-ignoring caveat, applied to a --json probe).
    "$BIN" "$root" "$@" >"$TMP/ev.plain.out" 2>"$TMP/ev.plain.err" </dev/null; local rcPlain=$?
    case " $okCodes " in
        *" $rcPlain "*)
            [ -s "$TMP/ev.plain.out" ] \
                && ok "§B1.5 $desc: the fixture EXERCISES the verb without --json (exit $rcPlain, $( wc -c <"$TMP/ev.plain.out" | tr -d ' ' ) bytes)" \
                || no "§B1.5 $desc: exit $rcPlain but EMPTY stdout — the verb did not run" ;;
        *)  no "§B1.5 $desc: the fixture does not exercise the verb (exit $rcPlain, want one of [$okCodes]) — the refusal arm below would pass for the wrong reason: $( head -c 140 "$TMP/ev.plain.err" )" ;;
    esac

    "$BIN" "$root" "$@" --json >"$TMP/ev.out" 2>"$TMP/ev.err" </dev/null; local rc=$?
    [ "$rc" -eq 1 ] && ok "§B1.5 $desc --json refuses with exit 1" \
                    || no "§B1.5 $desc --json exited $rc, want 1 — accepted and ignored"
    grep -qF -- "$want" "$TMP/ev.err" && ok "§B1.5 $desc --json refusal names $want" \
                                      || no "§B1.5 $desc --json refusal does not name $want: [$( head -c 160 "$TMP/ev.err" )]"
    [ ! -s "$TMP/ev.out" ] && ok "§B1.5 $desc --json wrote nothing to stdout" \
                           || no "§B1.5 $desc --json still emitted $( wc -c <"$TMP/ev.out" | tr -d ' ' ) bytes"
}
check_eval_refuses "--eval"           "$ROOT/src"    "--eval"           "0"   --eval
check_eval_refuses "--eval-retrieval" "$ROOT/src"    "--eval-retrieval" "0"   --eval-retrieval
check_eval_refuses "--eval-mined"     "$SBX"         "--eval-mined"     "0"   "--eval-mined=$TMP/mined.jsonl"
check_eval_refuses "--eval-skills"    "$ROOT/skills" "--eval-skills"    "0"   "--eval-skills=$ROOT/test/skillevalfix/prompts.tsv" --no-cache
check_eval_refuses "--eval-stray"     "$ROOT"        "--eval-stray"     "0 3" "--eval-stray=$TMP/strayfixture.tsv"

# ── §B1.5: --plan-lanes is the INERT case and gets a DIFFERENT answer ────────────────────────────────────
# It emits JSON natively, so --json changes no byte. Refusing would turn away the caller who asked for the
# one dialect it speaks; staying silent is the accept-and-ignore class. It is accepted AND disclosed, and
# both halves are asserted — a disclosure that came with a changed byte would be a worse bug than the gap.
printf 'lane one\nlane two\n' > "$TMP/brief.txt"
"$BIN" "$SBX" --plan-lanes --brief="$TMP/brief.txt" --json >"$TMP/pl.json.out" 2>"$TMP/pl.json.err"; RCJ=$?
"$BIN" "$SBX" --plan-lanes --brief="$TMP/brief.txt"        >"$TMP/pl.out"      2>"$TMP/pl.err";      RCP=$?
{ [ "$RCJ" -eq 0 ] && [ "$RCP" -eq 0 ]; } && ok "§B1.5 --plan-lanes exits 0 with and without --json" \
                                          || no "§B1.5 --plan-lanes exited $RCP / $RCJ (want 0 / 0)"
cmp -s "$TMP/pl.out" "$TMP/pl.json.out" && ok "§B1.5 --plan-lanes stdout is byte-identical with --json (inert, not ignored)" \
                                        || no "§B1.5 --plan-lanes stdout CHANGED under --json — the disclosure claims it does not"
grep -q 'redundant' "$TMP/pl.json.err" && ok "§B1.5 --plan-lanes DISCLOSES that --json is redundant" \
                                       || no "§B1.5 --plan-lanes accepts --json silently: [$( head -c 160 "$TMP/pl.json.err" )]"
grep -q 'redundant' "$TMP/pl.err" && no "§B1.5 the --json redundancy note fires without --json" \
                                  || ok "§B1.5 the redundancy note fires ONLY under --json"
head -c 1 "$TMP/pl.out" | grep -q '{' && ok "§B1.5 control: --plan-lanes really is JSON-native (its stdout opens with '{')" \
                                      || no "§B1.5 control: --plan-lanes stdout does not open with '{' — the whole rationale is wrong"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
