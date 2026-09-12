#!/usr/bin/env bash
# argvdiffcheck.sh — DIFFERENTIAL proof that a parser/dispatch refactor changed nothing observable.
#
# parseArgs and the run* handlers are pure with respect to argv, so the strongest available proof that a
# refactor is behaviour-preserving is not a hand-written assertion — it is running the OLD binary and the
# NEW binary over a large argv matrix and diffing stdout, stderr AND exit code for every vector.
#
# Why this gate exists (§6.1): `--affected=src/cli.h` returns
# tests="0" — the 200+ gates are shell scripts the call graph cannot see — so the tool cannot tell you what
# to run when you touch the argument parser. 139 of 146 parse arms are covered only INCIDENTALLY, by gates
# that happen to pass the flag while testing something else, and the 20 combination guards are pinned by
# exit code but not by message. A silent parse regression is therefore the single most likely way to break
# this repo without any gate going red.
#
# USAGE — set RIPWIRE_BASE to the reference binary:
#     RIPWIRE_BASE=build_base/ripwire RIPWIRE_BIN=build/ripwire bash test/argvdiffcheck.sh
# With no RIPWIRE_BASE this SKIPS and exits 0: in normal CI there is no "previous" binary to compare
# against, and a gate that cannot run must say so rather than pretend to pass.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
BASE="${RIPWIRE_BASE:-}"
[ -n "$BASE" ] && [ "${BASE#/}" = "$BASE" ] && BASE="$ROOT/$BASE"
TMP="$( mktemp -d )"
# The argv matrix is word-split on purpose (a vector IS an argv line), and vectors now embed a scratch
# path, so a $TMPDIR with whitespace would silently re-split them into different arguments. Refuse instead.
case "$TMP" in *[[:space:]]*) echo "argvdiffcheck: refusing — TMPDIR contains whitespace ($TMP), the argv matrix is word-split"; exit 2 ;; esac
# The scratch destination every PATH-valued vector is pointed at (see the value-typing block below), and
# the one file the mutation CONTROL creates in the tree on purpose. The trap owns BOTH, so a killed run
# cannot leave behind the very stray the last arm exists to catch.
ARGVOUT="$TMP/argvout"
CTRL="$ROOT/argvdiffcheck_mutation_control"
trap 'rm -rf "$TMP"; rm -f "$CTRL"' EXIT
cd "$ROOT"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
# SORTED, and that is load-bearing: the mutation arm at the bottom diffs two snapshots with comm, and comm
# on unsorted input drops lines without saying so. git prints staged entries BEFORE untracked ones, so a
# real tree can emit "M  zoo.c" ahead of "?? a.txt" — out of byte order, and a stray hides in the disorder.
treestatus(){ git status --porcelain 2>/dev/null | grep -vE '^\?\? (build|asan|tsan)' | sort; }
# The sanctioned skip is decided BEFORE the binary guard: with no RIPWIRE_BASE the gate cannot run at all,
# so a missing build/ripwire in that state is irrelevant — exit 2 there turned the skip into a failure in
# any tree without a build dir (gateexitcheck arm D asserts this skip is exit 0).
if [ -z "$BASE" ] || [ ! -x "$BASE" ]; then
    echo "argvdiffcheck: SKIP — no RIPWIRE_BASE reference binary"
    echo "  (set RIPWIRE_BASE=build_base/ripwire after building the pre-change source to activate)"
    exit 0
fi
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN"; exit 2; }
echo "argvdiffcheck: BASE=$BASE"
echo "argvdiffcheck: BIN =$BIN"
treestatus > "$TMP/status.before"

CORPUS="test/fixture"

# ── the argv matrix ───────────────────────────────────────────────────────────────────────────────────
# Four independent sources, so a vector set that drifts in one place is still covered by the others.
VEC="$TMP/vectors.txt"; : > "$VEC"

# (1) every long flag --help advertises, alone (bare and with a synthesized value), against a real corpus.
#     Server entry points are excluded: --mcp reads stdin to EOF and --listen binds a socket. The value is
#     TYPED from the flag's own --help placeholder — see the block above the loop for why `=1` is not safe
#     for every flag.
#
# The matrix is the INTERSECTION of both binaries' advertised surfaces, and that is not a convenience: this
# gate's question is "did anything PRE-EXISTING change?". A flag the new binary added does not exist in the
# base at all, so probing it compares "unknown flag" against real output and reports a diff on every genuinely
# ADDITIVE change — the exact result that makes a differential gate get ignored. New flags are counted and
# NAMED below (never silently dropped) and are covered by their own dedicated gate; the pre-existing surface
# is what must stay byte-identical, and every one of it is still probed.
"$BIN"  --help=all 2>&1 | grep -oE '\-\-[a-z][a-z0-9-]+' | sort -u > "$TMP/flags.new.txt"
"$BASE" --help=all 2>&1 | grep -oE '\-\-[a-z][a-z0-9-]+' | sort -u > "$TMP/flags.base.txt"
comm -12 "$TMP/flags.new.txt" "$TMP/flags.base.txt" > "$TMP/flags.txt"
comm -23 "$TMP/flags.new.txt" "$TMP/flags.base.txt" > "$TMP/flags.added.txt"
if [ -s "$TMP/flags.added.txt" ]; then
    printf '  NOTE  %s flag(s) exist only in BIN (additive, not comparable):%s\n' \
           "$( grep -c . "$TMP/flags.added.txt" )" "$( tr '\n' ' ' < "$TMP/flags.added.txt" | sed 's/ $//;s/^/ /' )"
fi
# A REMOVAL is not additive, and dropping it from the matrix would hide exactly the regression this gate is
# for — so the disappearance itself is the failure, checked before any vector runs.
comm -13 "$TMP/flags.new.txt" "$TMP/flags.base.txt" > "$TMP/flags.removed.txt"
[ -s "$TMP/flags.removed.txt" ] \
    && no "flag(s) advertised by BASE but GONE from BIN (a removal is not additive):$( tr '\n' ' ' < "$TMP/flags.removed.txt" )" \
    || ok "no advertised flag was removed ($( grep -c . "$TMP/flags.txt" ) shared with BASE, probed below)"
# --html is probed ONLY with unopenable paths above (it degrades without writing).
# --doctor is excluded because --help itself declares it "DIAGNOSTIC, not deterministic (env-dependent by
# design)": it reports the binary's own path and staleness, so two build dirs MUST disagree. Excluding a
# deliberately env-dependent verb is not the same as excluding an inconvenient one — every other exclusion
# here is a server entry point or a verb that writes a file.
# STATE-WRITING flags are excluded too, and this is not optional: a gate that mutates the tree is a
# liability, and --quality-ack/--quality-baseline/--note-add against $CORPUS write sidecars INTO the
# fixture the golden snapshot is computed from. (Caught the hard way: an early run of this harness left
# test/fixture/.ripwire_quality_acks behind.) The verbs are covered by their own dedicated gates.
SKIP=" --mcp --listen --mcp-token --allow-remote-edits --refetch --doctor \
       --index-out --html --export --note-add --quality-ack --quality-baseline --baseline --baseline-update --scan-skills --cache "
# The synthesized VALUE has to fit the flag's advertised TYPE. `1` is the right shape for a count, a name,
# a symbol or a mode, and the wrong shape for the two families where a value is not merely READ:
#
#   PATH-valued (--help spells the placeholder FILE / DIR / PATH / BASE / TESTFILE) — `--pin-census=1` made
#     the binary write its census to a file literally named `1` in the CWD, which is the REPO ROOT. The
#     mutation arm at the bottom caught the damage ("harness MUTATED the tree: ?? 1") but nothing prevented
#     it, and CI never saw it because CI sets no RIPWIRE_BASE and this gate skips. These now get a path
#     inside the scratch dir, so a writer writes THERE — and the write path is still exercised, which
#     `--flag=1` only ever did by accident, in the wrong place.
#   CMD-valued (placeholder CMD) — --run-trace EXECUTES its value under `sh -c`, so the generator was
#     handing a synthesized string to a shell, and reports a MEASURED duration_ms that its own legend calls
#     "not deterministic". Two byte-identical binaries DIFF on it (observed: 26 ms vs 25 ms), which fails
#     this gate's headline assertion for no reason. It is excluded on exactly the grounds --doctor is:
#     env-dependent BY DESIGN, not by accident. test/runtracecheck.sh is its dedicated gate. Only the VALUE
#     form is dropped — bare `--run-trace` (unknown flag) and `--run-trace=` (the §B5 empty-value refusal
#     below) are deterministic, and both stay in the matrix.
#
# Both sets are read out of --help rather than hand-listed, so a flag added later is classified by the row
# deckcheck.sh already forces its author to write in the same commit. The UNION of the two binaries'
# answers is used, because the two error directions are not symmetric: over-classifying only swaps one
# nonsense value for another, under-classifying puts a file back in the repo root.
placeholders(){ "$1" --help=all 2>&1 | grep -oE '^ +--[a-z][a-z0-9-]*\[?="?[A-Za-z][^ ]*' | sed 's/^ *//;s/"//g' | sed -E 's/\[?=/ /'; }
{ placeholders "$BIN"; placeholders "$BASE"; } > "$TMP/placeholders.txt"
PATHFLAGS=" $( awk '$2 ~ /^(FILE|DIR|PATH|BASE|TESTFILE|FILE\|-)\]?$/ {print $1}' "$TMP/placeholders.txt" | sort -u | tr '\n' ' ' )"
CMDFLAGS=" $(  awk '$2 ~ /^CMD\]?$/                                  {print $1}' "$TMP/placeholders.txt" | sort -u | tr '\n' ' ' )"
mkdir -p "$ARGVOUT"
npath=0; ncmd=0
while read -r f; do
    case "$SKIP" in *" $f "*) continue ;; esac
    printf '%s %s\n'    "$CORPUS" "$f"    >> "$VEC"
    case "$CMDFLAGS"  in *" $f "*) ncmd=$(( ncmd + 1 )); continue ;; esac
    case "$PATHFLAGS" in
        *" $f "*) npath=$(( npath + 1 )); printf '%s %s=%s\n' "$CORPUS" "$f" "$ARGVOUT/out" >> "$VEC" ;;
        *)                               printf '%s %s=1\n'   "$CORPUS" "$f"                >> "$VEC" ;;
    esac
done < "$TMP/flags.txt"
[ "$npath" -gt 0 ] \
    && ok "values typed from --help: $npath path-valued flag(s) aimed at the scratch dir, $ncmd cmd-valued value-form(s) dropped" \
    || no "values typed from --help: ZERO path-valued flags found — the --help row format drifted, fix the placeholder regex"

# (1b) §B5 (capture-audit-4): the EMPTY value, `--flag=`, for every shared advertised flag.
#
# Source (1) probes `--flag` and `--flag=1` and has never probed `--flag=`. That is precisely the shape §B5
# is about — a shell variable that expanded to nothing — and it means the four arms that silently accepted it
# (`--listen=` became a live stdio MCP server at exit 0; `--owners=`/`--outline=`/`--ack-only=` emitted a
# report or the whole default map) were invisible to the one gate whose job is "did anything change".
# 356/356 byte-identical was true and did not cover the question.
#
# --listen IS probed here, unlike in source (1): it is excluded there because a non-empty spec BINDS A
# SOCKET, and the empty form is the one that must not. Every vector runs with stdin closed, so the pre-fix
# binary's stdio server reads EOF and exits rather than hanging the gate.
#
# EMPTY_SKIP is narrower than SKIP and carries only flags whose empty form WRITES INTO THE CORPUS (trap #14:
# argvdiffcheck's own vectors mutating the tree under test is how a stale run inflates the diff count).
EMPTY_SKIP=" --mcp --refetch --doctor --quality-ack --quality-baseline --baseline-update "
while read -r f; do
    case "$EMPTY_SKIP" in *" $f "*) continue ;; esac
    printf '%s %s=\n' "$CORPUS" "$f" >> "$VEC"
done < "$TMP/flags.txt"

# (2) the combination guards — vectors chosen to TRIP validation, where a misplaced default silently
#     changes meaning (the cli.h:1170-1171 class the plan flagged).
#
# Two of these exist for a coverage hole rather than a validation edge. Source (1) probes every advertised
# flag bare and as `--flag=1`, and for a SYM-taking verb both of those REFUSE — `--edit-check` and
# `--edit-check=1` are both "symbol not found" on this corpus — so the verb's actual document, a ~3.8 KB
# bundle with the largest legend in the tree, was never emitted by any vector in the matrix. A 589-byte
# rewrite of that legend produced ZERO diffs here while changing every --edit-check run in the tree. Both
# resolving spellings are probed (bare name and file:name) because they take different resolver paths.
# The same hole shape is worth checking for any other verb whose only vectors are refusals.
cat >> "$VEC" <<EOF
$CORPUS --gateability
$CORPUS --plan
$CORPUS --abi
$CORPUS --partition=3
$CORPUS --flip=NOPE
$CORPUS --detail=2
$CORPUS --baseline
$CORPUS --with-graph
$CORPUS --json --hotspots
$CORPUS --json --detail=1
$CORPUS --format=columnar --for=cache
$CORPUS --format=candidates --for=cache
$CORPUS --top-k=0
$CORPUS --top-k=0 --expand=bigFunction
$CORPUS --token-budget=0
$CORPUS --token-budget=100
$CORPUS --max-tokens=500 --token-budget=16K
$CORPUS --order=stable
$CORPUS --order=important-last
$CORPUS --rank-by=churn
$CORPUS --rank-by=bogus
$CORPUS --format=bogus
$CORPUS --order=bogus
$CORPUS --limit=3 --offset=1 --deps
$CORPUS --exclude=geometry --exclude=related
$CORPUS --ignore-tests --metrics
$CORPUS --edit-check=total_area
$CORPUS --edit-check=test/fixture/app.py:total_area
$CORPUS --no-cache --no-stable --no-route
$CORPUS --adaptive --for=geometry
$CORPUS --no-mention-boost --for=geometry
$CORPUS --no-doc-mention --for=geometry
$CORPUS --compress --expand=bigFunction
$CORPUS --outline=bigFunction:3-5
$CORPUS --expand=bigFunction:6-8
$CORPUS --expand=nosuchsymbolzz
$CORPUS --callers=nosuchsymbolzz
$CORPUS --uses=nosuchsymbolzz
$CORPUS --lego=nosuchtypezz
$CORPUS --graph-query=bogus(
$CORPUS --connect=a
$CORPUS --connect-radius=99 --connect=perimeter,distance
$CORPUS --max-file-size=1
$CORPUS --scan-skill=/nonexistent
$CORPUS --arch=/nonexistent
$CORPUS --lint-rules=/nonexistent
$CORPUS --scip=/nonexistent
$CORPUS --from-trace=/nonexistent
$CORPUS --batch=/nonexistent
$CORPUS --eval-skills=/nonexistent
$CORPUS --eval-stray=/nonexistent
/nonexistent-root --hotspots
--help
--version
$CORPUS --html=/
$CORPUS --html=/nonexistent-dir/x.html
$CORPUS --export=cc.json:/nonexistent-dir/x.json
$CORPUS --lint-rules=/dev/null
EOF

# (3) real multi-flag invocations, harvested from the captured showcase — these are the shapes a user
#     actually types, not the ones a gate author imagines.
# The source is the NEWEST capture under docs/captures/. Its absence is a FAILURE, not a skip — and so is a
# zero-vector harvest: this block once pointed at a stale filename behind a silent `if [ -f ]` AND carried a
# regex the capture format had outgrown (commands are `## \`./build/ripwire …\`` headings, not line-start),
# so it contributed nothing for a round while every count still looked green (trap ledger #7, twice over).
SHOWCASE="$( ls docs/captures/COMMANDS_showcase_*.md 2>/dev/null | sort | tail -1 )"
if [ -z "$SHOWCASE" ]; then
    no "harvest source missing: no docs/captures/COMMANDS_showcase_*.md — the real-shape vectors are gone"
else
    # The harvest inherits source (1)'s bug in a different shape. These are REAL command lines, so their
    # values are REAL paths, and a harvested line that writes lands in the repo root exactly the way
    # `--pin-census=1` did. The hand-written exclusion list below is the historical filter — server entry
    # points, `wrap `, and the verbs that write sidecars into the corpus — and it is kept, because it also
    # covers spellings the placeholder types cannot see (`--scip=index.scip`). It is not SUFFICIENT: it misses
    # `--with-profile=`, `--pin-census=`, `--plan-lint=` and `--edit-payload=`, every one of which the
    # current capture contains. So a second, DERIVED stage drops any line carrying a path-valued or
    # cmd-valued flag in its VALUE form — reusing the same --help typing the vector generator uses above —
    # plus the verbs that write into the CORPUS rather than into a flag-given path (the symbol edits, and
    # --edit-plan --apply, which commits them).
    #
    # What makes this urgent rather than theoretical: `. --lint --with-profile=report.txt` sits at position
    # 62 of the filtered list and the cap is `head -60`. TWO lines of margin are the only thing that has
    # ever kept report.txt out of the repo root — and the ordering is decided by a GENERATED file that is
    # regenerated every round. Dropping unsafe lines BEFORE the cap costs no coverage: the survivors below
    # shift up into the 60, so the count holds and only the shape changes.
    UNSAFE_RE="$( { printf '%s\n' $PATHFLAGS $CMDFLAGS | sed 's/^--/\\-\\-/; s/$/=/'
                    printf '\\-\\-%s\n' replace-symbol-body insert-after-symbol insert-before-symbol edit-plan apply
                  } | grep . | sort -u | tr '\n' '|' | sed 's/|$//' )"
    raw="$( grep -oE '^## `\./build/ripwire [^`]*' "$SHOWCASE" 2>/dev/null \
        | sed 's|^## `\./build/ripwire ||' \
        | grep -vE '\-\-mcp|\-\-listen|\-\-run-trace|\-\-note-add|\-\-quality-ack|\-\-quality-baseline|\-\-baseline|\-\-index-out|\-\-html|\-\-export|\-\-cache=|\-\-eval-skills=|\-\-eval-stray=|\-\-from-trace=|\-\-batch=|\-\-scan-skill|\-\-arch=|\-\-lint-rules=|\-\-scip=|wrap ' )"
    safe="$( printf '%s\n' "$raw" | grep -vE "$UNSAFE_RE" )"
    ndropped=$(( $( printf '%s\n' "$raw" | grep -c . ) - $( printf '%s\n' "$safe" | grep -c . ) ))
    harvested="$( printf '%s\n' "$safe" | head -60 )"
    hcount="$( printf '%s\n' "$harvested" | grep -c . )"
    if [ "$hcount" -ge 20 ]; then
        printf '%s\n' "$harvested" >> "$VEC"
        ok "harvested $hcount real-shape vectors from $SHOWCASE ($ndropped tree-writing shape(s) dropped before the cap)"
    else
        no "harvest produced only $hcount vector(s) from $SHOWCASE (want >=20) — format drift, fix the regex"
    fi
    # ...and the control, because a filter that drops nothing looks exactly like a filter that works. The
    # probe is not synthetic: this line IS in the capture today, at the position the cap only just excludes.
    printf '%s\n' '. --lint --with-profile=report.txt' | grep -qE "$UNSAFE_RE" \
        && ok "control: the harvest's unsafe-shape stage drops a known tree-writing line (--with-profile=report.txt)" \
        || no "control: the harvest did NOT drop '. --lint --with-profile=report.txt' — the unsafe-shape stage is inert"
fi

# (4) verb pairs on the navigate/quality dispatch paths that a handler split could reorder.
cat >> "$VEC" <<EOF
$CORPUS --callers=perimeter --format=columnar
$CORPUS --callees=perimeter
$CORPUS --impact=distance
$CORPUS --around=perimeter --around-depth=2 --around-fanout=3
$CORPUS --path=perimeter,distance
$CORPUS --grep=double --grep-context=2
$CORPUS --regex=doub.e
$CORPUS --match=(function_definition)
$CORPUS --tree
$CORPUS --report
$CORPUS --metrics --deps
$CORPUS --communities
$CORPUS --zoom
$CORPUS --seams
$CORPUS --dead-code
$CORPUS --external-surface
$CORPUS --lint
$CORPUS --clones
$CORPUS --hotspots
$CORPUS --pack-signatures
$CORPUS --pack-top-n=3
$CORPUS --for=geometry --detail=1
$CORPUS --pack-task=compute the perimeter
$CORPUS --recall=geometry
$CORPUS --exemplar=compute a distance
$CORPUS --query=perimeter
EOF

# --help is the ONE pre-existing vector an additive flag is REQUIRED to change: deckcheck.sh fails unless a
# new flag's rows land in --help in the same commit. So when BIN advertises a flag BASE does not, the two help
# texts must differ, and byte-identity there would mean the rows were never written. It is replaced by a
# stricter assertion for that case: every flag BASE DOCUMENTS must still have a row in BIN's catalog.
#
# TWO THINGS CHANGED HERE ON 2026-09-09, and both are worth stating rather than discovering later.
#
# (1) THE SPELLING IS ASYMMETRIC ON PURPOSE. BASE is a PREVIOUS RELEASE, and `--help=all` did not exist
#     before the two-tier split — asking an old binary for it yields an unknown-flag refusal and an EMPTY
#     capture, which this arm would then read as "nothing missing" and pass. That is the empty-equals-
#     agreement shape (CONTRIBUTING §2, row 3): the arm would stay in the file and leave the conjunction.
#     So BASE is asked with `--help` (its full catalog) and BIN with `--help=all` (its full catalog), and
#     the presence guard below makes an empty BASE capture a FAILURE rather than a pass.
#
# (2) THE ASSERTION IS NOW ABOUT ROWS, NOT LINES. It used to require BASE's help to survive VERBATIM inside
#     BIN's, line for line. The two-tier split deliberately reworded 133 opening lines and moved the old
#     prose down one row, so line-verbatim now fails on a change that deleted nothing — and it would have
#     failed the same way on any honest rewording, which this project does routinely. Rows are the property
#     the arm was really protecting: a flag whose documentation silently DISAPPEARS between releases. A
#     reworded row still has to be there. test/helpbudgetcheck.sh holds the within-release half of this
#     (every row advertised in tier 1 is retrievable from tier 2).
if [ -s "$TMP/flags.added.txt" ]; then
    grep -vE '(^|[[:space:]])(--help|-h)([[:space:]]|$)' "$VEC" > "$TMP/vec.trimmed" && mv "$TMP/vec.trimmed" "$VEC"
    "$BASE" --help     >"$TMP/help.base" 2>/dev/null
    "$BIN"  --help=all >"$TMP/help.new"  2>/dev/null
    helprows(){ grep -E '^    (--[^ ]+|[^ ]+  +[^ ])' "$1" | sed -E 's/^    ([^ ]+) .*/\1/' | sort -u; }
    helprows "$TMP/help.base" >"$TMP/rows.base"
    helprows "$TMP/help.new"  >"$TMP/rows.new"
    nbase="$( grep -c . "$TMP/rows.base" )"
    if [ "$nbase" -lt 50 ]; then
        no "only $nbase rows read out of BASE's --help — the capture broke, so the additive check proves nothing"
    else
        missing="$( comm -23 "$TMP/rows.base" "$TMP/rows.new" | head -3 )"
        [ -z "$missing" ] && ok "help is ADDITIVE: all $nbase rows BASE documents still have a row in BIN's catalog" \
                          || { no "row(s) BASE documents are gone from BIN's --help — not additive:"; printf '%s\n' "$missing" | sed 's/^/        /'; }
    fi
fi

TOTAL="$( grep -c . "$VEC" )"
[ "$TOTAL" -ge 250 ] && ok "argv matrix: $TOTAL vectors from 5 independent sources" \
                     || no "argv matrix only $TOTAL vectors (want >=250) — the harvest broke"

# ── run both binaries over every vector, diff stdout + stderr + exit code ──────────────────────────────
diffs=0; ran=0
while IFS= read -r v; do
    [ -n "$v" ] || continue
    ran=$(( ran + 1 ))
    # word-split deliberately: the vector IS an argv line
    # A PATH-valued vector WRITES into $ARGVOUT, so both binaries have to start from the same empty dir:
    # a writer that found its own output already there from the BASE run could refuse, and diff for that
    # alone. Reset between the two runs, not once per vector.
    rm -rf "$ARGVOUT"; mkdir -p "$ARGVOUT"
    # shellcheck disable=SC2086
    "$BASE" $v >"$TMP/o.base" 2>"$TMP/e.base" </dev/null; rcb=$?
    rm -rf "$ARGVOUT"; mkdir -p "$ARGVOUT"
    # shellcheck disable=SC2086
    "$BIN"  $v >"$TMP/o.new"  2>"$TMP/e.new"  </dev/null; rcn=$?
    # DEGRADED_PATH_ALERT prints __LINE__, so ANY refactor that moves code shifts every alert below it
    # (an adversarial pass found 7 of 11 sites in main.cpp shifted when it grew 118 lines). That is a
    # position artifact, not a behaviour change — the alert's MESSAGE and the function it names are the
    # signal, so normalise the ":NNNN" and keep everything else byte-exact. Without this the harness
    # reports a false positive on every future extraction and gets ignored, which is worse than noisy.
    # 2026-08-29 main.cpp split: the verb families moved into src/verbs_*.h SECTIONS of main.cpp's own
    # TU, so an alert in moved code changed its __FILE__ spelling from main.cpp to its section — the
    # same position-artifact class as the line shift. Fold the ONE TU's spellings (main.cpp and its
    # RIPWIRE_MAIN_TU-guarded verbs_*.h sections) to a common token before the line normalisation;
    # every other file's name stays byte-exact, so a message genuinely moving to a different subsystem
    # still diffs.
    sed -E 's/\((main\.cpp|verbs_[a-z]+\.h):[0-9]+,/(MAINTU:LINE,/g; s/\.(cpp|h):[0-9]+,/.\1:LINE,/g' "$TMP/e.base" > "$TMP/e.base.n"
    sed -E 's/\((main\.cpp|verbs_[a-z]+\.h):[0-9]+,/(MAINTU:LINE,/g; s/\.(cpp|h):[0-9]+,/.\1:LINE,/g' "$TMP/e.new"  > "$TMP/e.new.n"
    if [ "$rcb" != "$rcn" ] || ! cmp -s "$TMP/o.base" "$TMP/o.new" || ! cmp -s "$TMP/e.base.n" "$TMP/e.new.n"; then
        diffs=$(( diffs + 1 ))
        # The default 5 keeps a normal run terse. A FIX ROUND must classify EVERY diff, and capping the list
        # at 5 previously forced an agent to make a throwaway copy of this gate in test/ just to read its own
        # output — friction that argues for the knob, not the copy. ARGVDIFF_SHOW=999 prints all of them.
        if [ "$diffs" -le "${ARGVDIFF_SHOW:-5}" ]; then
            printf '        DIFF  ripwire %s\n' "$v"
            [ "$rcb" != "$rcn" ] && printf '              exit %s -> %s\n' "$rcb" "$rcn"
            cmp -s "$TMP/o.base" "$TMP/o.new" || printf '              stdout differs (%s -> %s bytes)\n' "$(wc -c <"$TMP/o.base"|tr -d ' ')" "$(wc -c <"$TMP/o.new"|tr -d ' ')"
            cmp -s "$TMP/e.base.n" "$TMP/e.new.n" || { printf '              stderr differs:\n'; diff "$TMP/e.base.n" "$TMP/e.new.n" | head -4 | sed 's/^/                /'; }
        fi
    fi
done < "$VEC"

[ "$diffs" = 0 ] && ok "all $ran vectors byte-identical across both binaries (stdout+stderr+exit)" \
                 || no "$diffs of $ran vectors DIFFER — the refactor is not behaviour-preserving"

# a self-test: the harness must be able to SEE a difference, or it proves nothing.
if [ "$BASE" != "$BIN" ]; then
    "$BASE" "$CORPUS" --top-k=1 >"$TMP/x1" 2>/dev/null
    "$BIN"  "$CORPUS" --top-k=2 >"$TMP/x2" 2>/dev/null
    cmp -s "$TMP/x1" "$TMP/x2" && no "control: two KNOWN-different invocations compared equal — the differ is broken" \
                               || ok "control: the differ does detect a real difference"
fi

# ── the harness must not mutate the tree it tests ─────────────────────────────────────────────────────
# A differential gate that leaves state behind can corrupt the corpus the golden is computed from, which
# would then fail somewhere else entirely and look like a code bug.
# Compared against the status captured BEFORE the run, not against a clean tree: this gate is normally run
# mid-change with the working tree already dirty (that IS the moment a differential proof is wanted), and a
# check that only passes on a pristine checkout would be turned off rather than obeyed.
treestatus > "$TMP/status.after"
STRAY="$( comm -13 "$TMP/status.before" "$TMP/status.after" 2>/dev/null | head -5 )"
if [ -z "$STRAY" ]; then ok "harness left the tree unmodified (no new changes vs the pre-run status)"
else no "harness MUTATED the tree:"; printf '%s\n' "$STRAY" | sed 's/^/        /'; fi

# ...and a CONTROL for that arm, on the same argument as the differ's control above: an assertion nobody
# has ever seen fail is indistinguishable from one that cannot fail. This arm is what caught --pin-census=1
# writing a file named `1` into the repo root, and now that the value-typing block prevents that class it is
# the ONLY thing standing between a future path-valued flag and the same stray — so it has to be exercised,
# not merely present. Create one stray on purpose, run the SAME comparison, require it to be SEEN, then
# remove it and require the tree to be clean again: a control that leaves its own litter behind is not one.
: > "$CTRL"
treestatus > "$TMP/status.ctrl"
seen="$( comm -13 "$TMP/status.after" "$TMP/status.ctrl" 2>/dev/null )"
rm -f "$CTRL"
treestatus > "$TMP/status.restored"
case "$seen" in
    *"argvdiffcheck_mutation_control"*) ok "control: the tree-mutation arm does detect a deliberate stray file" ;;
    *) no "control: a deliberate stray file went UNDETECTED — the tree-mutation arm above proves nothing" ;;
esac
cmp -s "$TMP/status.after" "$TMP/status.restored" \
    || no "control: the deliberate stray outlived its own removal — the control littered the tree"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
