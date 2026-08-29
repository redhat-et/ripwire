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
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
cd "$ROOT"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
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
git status --porcelain 2>/dev/null | grep -vE '^\?\? (build|asan|tsan)' > "$TMP/status.before"

CORPUS="test/fixture"

# ── the argv matrix ───────────────────────────────────────────────────────────────────────────────────
# Four independent sources, so a vector set that drifts in one place is still covered by the others.
VEC="$TMP/vectors.txt"; : > "$VEC"

# (1) every long flag --help advertises, alone (bare and =1), against a real corpus.
#     Server entry points are excluded: --mcp reads stdin to EOF and --listen binds a socket.
#
# The matrix is the INTERSECTION of both binaries' advertised surfaces, and that is not a convenience: this
# gate's question is "did anything PRE-EXISTING change?". A flag the new binary added does not exist in the
# base at all, so probing it compares "unknown flag" against real output and reports a diff on every genuinely
# ADDITIVE change — the exact result that makes a differential gate get ignored. New flags are counted and
# NAMED below (never silently dropped) and are covered by their own dedicated gate; the pre-existing surface
# is what must stay byte-identical, and every one of it is still probed.
"$BIN"  --help 2>&1 | grep -oE '\-\-[a-z][a-z0-9-]+' | sort -u > "$TMP/flags.new.txt"
"$BASE" --help 2>&1 | grep -oE '\-\-[a-z][a-z0-9-]+' | sort -u > "$TMP/flags.base.txt"
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
while read -r f; do
    case "$SKIP" in *" $f "*) continue ;; esac
    printf '%s %s\n'    "$CORPUS" "$f"    >> "$VEC"
    printf '%s %s=1\n'  "$CORPUS" "$f"    >> "$VEC"
done < "$TMP/flags.txt"

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
    harvested="$( grep -oE '^## `\./build/ripwire [^`]*' "$SHOWCASE" 2>/dev/null \
        | sed 's|^## `\./build/ripwire ||' \
        | grep -vE '\-\-mcp|\-\-listen|\-\-note-add|\-\-quality-ack|\-\-quality-baseline|\-\-baseline|\-\-index-out|\-\-html|\-\-export|\-\-cache=|\-\-eval-skills=|\-\-eval-stray=|\-\-from-trace=|\-\-batch=|\-\-scan-skill|\-\-arch=|\-\-lint-rules=|\-\-scip=|wrap ' \
        | head -60 )"
    hcount="$( printf '%s\n' "$harvested" | grep -c . )"
    if [ "$hcount" -ge 20 ]; then
        printf '%s\n' "$harvested" >> "$VEC"
        ok "harvested $hcount real-shape vectors from $SHOWCASE"
    else
        no "harvest produced only $hcount vector(s) from $SHOWCASE (want >=20) — format drift, fix the regex"
    fi
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
# STRICTER assertion for that case — BASE's help must survive VERBATIM inside BIN's, line for line — which
# catches a reworded or deleted row that byte-identity would have caught and a plain skip would not.
if [ -s "$TMP/flags.added.txt" ]; then
    grep -vE '(^|[[:space:]])(--help|-h)([[:space:]]|$)' "$VEC" > "$TMP/vec.trimmed" && mv "$TMP/vec.trimmed" "$VEC"
    "$BASE" --help 2>&1 > "$TMP/help.base"
    "$BIN"  --help 2>&1 > "$TMP/help.new"
    missing="$( grep -Fxv -f "$TMP/help.new" "$TMP/help.base" | head -3 )"
    [ -z "$missing" ] && ok "help is ADDITIVE: every line of BASE's --help survives verbatim in BIN's" \
                      || { no "BASE --help line(s) reworded or removed — not additive:"; printf '%s\n' "$missing" | sed 's/^/        /'; }
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
    # shellcheck disable=SC2086
    "$BASE" $v >"$TMP/o.base" 2>"$TMP/e.base" </dev/null; rcb=$?
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
git status --porcelain 2>/dev/null | grep -vE '^\?\? (build|asan|tsan)' > "$TMP/status.after"
STRAY="$( comm -13 "$TMP/status.before" "$TMP/status.after" 2>/dev/null | head -5 )"
if [ -z "$STRAY" ]; then ok "harness left the tree unmodified (no new changes vs the pre-run status)"
else no "harness MUTATED the tree:"; printf '%s\n' "$STRAY" | sed 's/^/        /'; fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
