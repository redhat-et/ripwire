#!/usr/bin/env bash
# printffmtparitycheck.sh — the byte-parity fence for any printf-family -> std::format/std::print
# conversion.
#
# THE PROPERTY THIS GATE PROVES, AND WHY IT IS THE WHOLE SAFETY STORY FOR THAT MIGRATION: the codebase
# is printf-family by deliberate choice (0 std::cout, 1529 fprintf/printf/snprintf/sprintf call sites
# across ~60 files) and every one of those bytes feeds G4 (minified XML), the determinism contract,
# docs/EVALS.md's recorded numbers, and showcasecapturecheck's/docscommandscheck's stored captures.
# A conversion to std::format is safe ONLY if it changes NOTHING about stdout/stderr bytes for any verb —
# std::format's default float formatting (shortest-roundtrip) is NOT the same as printf's (`%g` = 6
# significant digits: 0.1+0.2 prints "0.3" under %g, "0.30000000000000004" under std::format's `{}`),
# so a naive per-specifier swap is a silent, gate-invisible byte change unless something asserts
# byte-identity directly. This script is that assertion: it is the reviewer, not the model doing the
# conversion — a cheap model can be trusted with the mechanical rule set in the lane report PRECISELY
# BECAUSE this gate reverts any file whose conversion moves one byte.
#
# WHAT IT DOES: runs a fixed corpus of verb invocations (chosen to touch several of the densest
# printf-family files — verbs_lint.h, verbs_navigate.h, cli.h, verbs_report.h's --hotspots/--clones
# paths, main.cpp's dispatch) against the binary under test, hashes stdout and stderr separately per
# verb (SHA-256, so a 176 KB --help capture costs one line, not a checked-in blob), and compares against
# the committed manifest test/printf_parity.manifest. Any mismatch — hash OR exit code — is a FAIL naming
# exactly which verb and which stream changed.
#
# Deliberately EXCLUDED from the corpus: --for, --hotspots and --owners, whose output is derived from GIT
# HISTORY (churn, blame). The manifest is necessarily pinned BEFORE the commit that carries it, and making
# that commit changes churn and ownership — so those three can never hold a pin: the gate would be red on
# the very commit that pinned it, every time. They are covered by their own gates; printf parity does not
# need them. Also excluded: --doctor (self_mtime/self_size/cache blobs= are documented
# VOLATILE fields — doctor's own legend says a determinism comparison must strip them, so a naive
# byte-hash here would false-positive on every rebuild regardless of any printf change); --quality-delta
# (a state-writing verb per the lane brief's rule 9 — out of scope for a read-only parity fence); and
# --version (embeds `built_from=<sha>[+dirty]` — the dirty suffix flips the moment ANY file in the tree
# is edited, which is true of every commit in a printf-family conversion BEFORE it lands, so this verb
# false-positives on the gate's own normal use and would falsely blame the conversion for a byte change
# that is really "you have uncommitted changes"; confirmed live during the R8 pilot conversion).
#
# MAINTENANCE COST, stated so nobody mistakes it for a defect: this manifest pins ABSOLUTE output hashes,
# so ANY change to any verb's bytes reds it — a legitimate disclosure added by an unrelated lane just as
# surely as a bad printf conversion. That is the same contract test/golden.xml and the showcase capture
# carry, and the same remedy applies: re-pin with UPDATE_GOLDEN=1 and REVIEW THE DIFF, confirming every
# moved verb is explained by a change you meant. It is a fence around a conversion batch, not a claim that
# output is frozen forever.
#
# Usage:
#   bash test/printffmtparitycheck.sh                    # compare against the committed manifest
#   RIPWIRE_BIN=asan/ripwire bash test/printffmtparitycheck.sh
#   UPDATE_GOLDEN=1 bash test/printffmtparitycheck.sh     # regenerate the manifest (review the diff!)
#
# Exits non-zero on any mismatch; prints PASS/FAIL per verb/stream; prints ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
CORPUS="$ROOT/test/fixture"
MANIFEST="$ROOT/test/printf_parity.manifest"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

hashfile(){
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
    else sha256sum "$1" | cut -d' ' -f1
    fi
}

# ── the verb corpus ──────────────────────────────────────────────────────────────────────────────────
# Each label names a verb invocation. `argvFor` fills the global ARGV array — an ARRAY, not a
# word-split string, because a fence that cannot express an argument containing a space cannot cover
# --pattern/--exemplar/--pack-task, and the previous string form needed a hand-written special case per
# such label (it carried two: match and pattern). Widening the fence is the whole point of the corpus,
# so the corpus must not be the thing that resists widening.
#
# WIDENED 2026-09-09 (12 -> 27 labels) for the printf-family -> std::print conversion. The rule the
# widening follows: a verb may be converted only if a label covers it, so the labels come FIRST and the
# conversion follows them. Coverage added, by the file whose call sites it fences:
#   src/verbs_navigate.h (113 sites)  expand callees around uses path connect  (+ callers/impact, held)
#   src/verbs_grep.h      (41 sites)  grep                                     (+ match/pattern, held)
#   src/serialize.h       (84 sites)  pack_signatures pack_task                (+ flagless, held)
#   src/verbs_report.h   (147 sites)  arch seams skipped                       (+ clones, held)
#   src/recall.h/exemplar/lego/notes  recall exemplar lego notes
#   src/cli.h            (101 sites)  bad_flag — the refusal path, which is a STDERR fence: cli.h's
#                                     diagnostics are printf sites too and no other label reaches them
#
# `arch` earns its place twice over: its output carries the only FLOATS in the fenced corpus
# (propagation_cost="0.375", I=/A=/D="0.00"), and float rendering is precisely the trap this gate's
# header warns about — %g is 6 significant digits, {} is shortest-roundtrip. It reads
# test/parity_arch_rules.txt, which sits OUTSIDE test/fixture on purpose (a file inside the crawl root
# would move every other label's hash) and is written to produce one real violation, so the label
# fences the violation-row emitter and the exit-2 path rather than only the <metrics> block.
#
# STILL EXCLUDED, and each for a reason that has been tested rather than assumed — see the git-sensitivity
# and dirty-tree probes recorded in the lane report: --for/--hotspots/--owners (git history: churn and
# blame move when the commit carrying the manifest is made, so the pin is red on the commit that sets
# it), --doctor (documented VOLATILE fields), --quality-delta (state-writing), --version (+dirty stamp).
# --pack-task is INCLUDED but routes through --for's ranker; it was probed across a commit before being
# admitted, and if it ever flakes it is the first label to suspect and drop.
# Both --help TIERS are pinned, and so is one addressed entry. `help` is the budgeted first screen;
# `help_all` is the complete catalog every gate and docs/docs_commands_build.py reads; `help_one` proves
# the per-flag address still serves a whole entry. Pinning only one of them would let a change move the
# other silently, which is exactly the split this fence is guarding.
# label -> (needsCorpus 0|1, argv...). needsCorpus=1 verbs get "$CORPUS --no-cache" prepended; 0 verbs
# (--version/--help) are global and take no positional path at all.
LABELS="flagless lint lint_sarif lint_select lint_naming lint_catalog match pattern callers impact clones help expand callees around uses path connect grep pack_signatures pack_task arch seams skipped recall exemplar lego notes bad_flag callers_json callees_json impact_json uses_json grep_json expand_missing callers_missing safe_delete verify_layer graph_query callers_limit help_all help_one"

# needsCorpus: 1 = prepend "test/fixture --no-cache"; 0 = a global verb that takes no positional path.
needsCorpusFor(){
    case "$1" in
        help|help_all|help_one|bad_flag) return 1;;
        *)             return 0;;
    esac
}

argvFor(){
    case "$1" in
        flagless)        ARGV=();;
        lint)            ARGV=( --lint );;
        lint_sarif)      ARGV=( --lint --sarif );;
        lint_select)     ARGV=( --lint --lint-select=cache );;
        lint_naming)     ARGV=( --lint --naming-locals );;
        lint_catalog)    ARGV=( --lint-catalog );;
        match)           ARGV=( '--match=(function_definition) @m' );;
        pattern)         ARGV=( '--pattern=distance($A, $B)' );;
        callers)         ARGV=( --callers=distance );;
        impact)          ARGV=( --impact=perimeter );;
        clones)          ARGV=( --clones );;
        help)            ARGV=( --help );;
        help_all)        ARGV=( --help=all );;
        help_one)        ARGV=( --help=--uses );;
        expand)          ARGV=( --expand=distance );;
        callees)         ARGV=( --callees=distance );;
        around)          ARGV=( --around=distance );;
        uses)            ARGV=( --uses=distance );;
        path)            ARGV=( --path=distance,perimeter );;
        connect)         ARGV=( --connect=distance,perimeter );;
        grep)            ARGV=( --grep=distance );;
        pack_signatures) ARGV=( --pack-signatures );;
        pack_task)       ARGV=( '--pack-task=compute the distance between points' );;
        arch)            ARGV=( --arch=test/parity_arch_rules.txt );;
        seams)           ARGV=( --seams );;
        skipped)         ARGV=( --skipped );;
        recall)          ARGV=( --recall=geometry );;
        exemplar)        ARGV=( '--exemplar=compute a distance' );;
        lego)            ARGV=( --lego=Point );;
        notes)           ARGV=( --notes );;
        # --json is a SECOND output path through the same file, and the brace-dense one: JSON emitters
        # are where {{ }} escaping matters most, and a coverage run showed the XML labels never reach
        # them. These two are the highest-value rows in the corpus per byte.
        callers_json)    ARGV=( --callers=distance --json );;
        callees_json)    ARGV=( --callees=distance --json );;
        impact_json)     ARGV=( --impact=perimeter --json );;
        # --json refusals: verbs that do not implement it must keep refusing in the same bytes.
        uses_json)       ARGV=( --uses=distance --json );;
        grep_json)       ARGV=( --grep=distance --json );;
        # not-found refusals — the selectorNotFoundMessage path, 35 cold stderr sites' front door.
        expand_missing)  ARGV=( --expand=nosuchsym );;
        callers_missing) ARGV=( --callers=nosuchsym );;
        # whole verbs in verbs_navigate.h that no other label reaches at all. (--slice was tried here
        # too and REFUSED by the stamp screen below: it prints at="<sha>". The screen caught it on the
        # very next widening after it was written, which is the argument for having it.)
        safe_delete)     ARGV=( --safe-delete=distance );;
        # verify_layer fences the one site in this conversion that was edited BY HAND (the converter
        # emitted a double-wrapped string_view there and it was simplified back to the bare view).
        verify_layer)    ARGV=( '--verify=reaches(distance,perimeter)' );;
        graph_query)     ARGV=( --graph-query=kind:fn );;
        callers_limit)   ARGV=( --callers=distance --limit=1 );;
        # the refusal path: an unknown flag must keep emitting the same stderr bytes and the same rc.
        bad_flag)        ARGV=( --no-such-flag-parity-probe );;
        *)               echo "printffmtparitycheck: unknown label '$1'" >&2; exit 2;;
    esac
}

# ${ARGV[@]+"${ARGV[@]}"}, not "${ARGV[@]}": under `set -u`, bash 3.2 — which is what macOS ships and
# therefore what every developer here runs — treats "${A[@]}" on an EMPTY array as an unbound variable and
# aborts. The `flagless` label is exactly that empty array. bash 5 on the CI legs does NOT abort, so the
# naive spelling yields a gate that is green in CI and broken on the machine doing the conversion; caught
# here by running the widened corpus against the UNCHANGED manifest, where flagless turned rc=0 into rc=1.
runVerb(){
    # $1 = label, writes stdout to $TMP/out, stderr to $TMP/err, returns the process rc via $?
    argvFor "$1"
    if needsCorpusFor "$1"; then
        # RELATIVE corpus path, run from $ROOT, and the reason is the whole reason this manifest is
        # portable: ripwire ECHOES the root it was given (root="..."), and the length of that string
        # also moves est_tokens. An absolute path therefore bakes the checkout's own location into
        # every hash, so a manifest pinned in one directory can never pass in another — not in CI, not
        # in a second worktree, not in a fresh clone. Measured: the same binary on the same corpus gave
        # est_tokens=909 under .../ripwire-wt-integrate and 935 under a /private/tmp clone.
        # test/parity_arch_rules.txt is likewise repo-relative, for the same portability reason.
        ( cd "$ROOT" && "$BIN" test/fixture --no-cache ${ARGV[@]+"${ARGV[@]}"} ) >"$TMP/out" 2>"$TMP/err"
    else
        ( cd "$ROOT" && "$BIN" ${ARGV[@]+"${ARGV[@]}"} ) >"$TMP/out" 2>"$TMP/err"
    fi
    return $?
}
# ── the stamp screen (pin time) ──────────────────────────────────────────────────────────────────────
# A verb that embeds the git stamp can NEVER hold a pin, and the reason is structural rather than a
# quirk of any one verb: `at="<sha>"` moves on the very commit that carries the manifest, and the
# `+dirty` suffix moves the moment anyone edits a file in the tree. --version was excluded from this
# corpus for exactly that, and the reasoning generalises — so it is enforced MECHANICALLY here instead
# of being left to whoever widens the corpus next to remember.
#
# Measured 2026-09-09 while widening 12 -> 29: --html and --test-gate both stamp `at=`, and BOTH passed
# THREE consecutive byte-identical runs before this screen caught them. Repeat-run stability does not
# detect this class at all — only committing and re-running does, which is not something a widener would
# think to try. That is the whole argument for screening at pin time.
#
# To admit a stamped verb later, normalise the stamp out of the captured stream before hashing (the
# technique --doctor's own legend already prescribes for its VOLATILE fields) rather than deleting this
# screen. Doing so would unlock htmlexport.h (53 sites) and verbs_quality.h (67), which are otherwise
# unfenced and therefore unconvertible.
gitStamp(){ ( cd "$ROOT" && git rev-parse --short=9 HEAD 2>/dev/null ); }

screenStamp(){
    # $1 = label. Fails the PIN if the verb's own output embeds this checkout's HEAD sha.
    local stamp; stamp="$( gitStamp )"
    [ -n "$stamp" ] || return 0            # no git (tarball build): nothing to screen against
    if grep -q "$stamp" "$TMP/out" "$TMP/err" 2>/dev/null; then
        printf 'REFUSED  %s: output embeds the git stamp (%s) — this verb cannot hold a pin.\n' "$1" "$stamp"
        printf '         The sha moves on the commit that carries this manifest and +dirty moves on any edit.\n'
        printf '         Drop the label, or normalise the stamp out before hashing. See the stamp screen above.\n'
        return 1
    fi
    return 0
}

# ── re-pinning, and why a WIDER fence makes a blind re-pin MORE dangerous ────────────────────────────
# UPDATE_GOLDEN rewrites EVERY label, not the one you meant to move. At 12 labels that was survivable by
# reading the diff; at 40 it is a real footgun, and the failure it invites is precise: an unrelated drift
# gets absorbed under someone else's justification, and the manifest then certifies a bug as intended.
# That is the same shape as a blind re-pin of test/qschemetrip.hash, one file over — except here it would
# defeat the exact guarantee this gate exists to provide.
#
# So a re-pin REPORTS ITSELF. Before writing, the previous manifest is read; afterwards every label whose
# hash or exit code moved is named with its old and new value, and the count of unchanged labels is stated
# beside it. Set UPDATE_GOLDEN_EXPECT to the space-separated labels you INTEND to move and the gate exits 4
# if the moved set differs — the cheap way to make "exactly one line, help, and nothing else" a check
# rather than a promise.
#
# THE ORDER THAT MATTERS: run the gate FIRST and read which labels are red. Only then re-pin. A red you
# have not explained is not a manifest that needs updating; for a printf-family conversion it is a revert
# of the converting file, because the whole claim is that the bytes did not move.
if [ "${UPDATE_GOLDEN:-0}" = "1" ]; then
    prevManifest=""
    [ -f "$MANIFEST" ] && prevManifest="$( cat "$MANIFEST" )"
    : >"$MANIFEST"
    screenFail=0
    for label in $LABELS; do
        runVerb "$label"; rc=$?
        screenStamp "$label" || screenFail=1
        printf '%s %s %s %s\n' "$label" "$rc" "$( hashfile "$TMP/out" )" "$( hashfile "$TMP/err" )" >>"$MANIFEST"
    done
    if [ "$screenFail" != 0 ]; then
        echo "printffmtparitycheck: REFUSING to pin — one or more labels embed the git stamp (see above)."
        echo "  $MANIFEST was written anyway so you can see the damage, but DO NOT COMMIT IT."
        exit 3
    fi
    moved=""; unchanged=0
    if [ -n "$prevManifest" ]; then
        while read -r pl prc pout perr; do
            [ -n "$pl" ] || continue
            newline="$( grep "^$pl " "$MANIFEST" | head -1 )"
            if [ -z "$newline" ]; then
                printf '  DROPPED %s (was in the previous manifest, not in LABELS any more)\n' "$pl"
                moved="$moved $pl"
                continue
            fi
            set -- $newline
            if [ "$2" != "$prc" ] || [ "$3" != "$pout" ] || [ "$4" != "$perr" ]; then
                moved="$moved $pl"
                [ "$3" != "$pout" ] && printf '  MOVED %-16s STDOUT %s -> %s\n' "$pl" "$( printf %.8s "$pout" )" "$( printf %.8s "$3" )"
                [ "$4" != "$perr" ] && printf '  MOVED %-16s STDERR %s -> %s\n' "$pl" "$( printf %.8s "$perr" )" "$( printf %.8s "$4" )"
                [ "$2" != "$prc" ]  && printf '  MOVED %-16s exit   %s -> %s\n' "$pl" "$prc" "$2"
            else
                unchanged=$(( unchanged + 1 ))
            fi
        done <<EOF
$prevManifest
EOF
    fi
    moved="$( printf '%s' "$moved" | sed 's/^ *//' )"
    echo "UPDATE_GOLDEN: wrote $MANIFEST ($( wc -l <"$MANIFEST" | tr -d ' ' ) verbs); moved={${moved:-none}}, $unchanged unchanged"
    echo "  Read that list. It must be EXACTLY the labels you meant to move; anything else is a real change"
    echo "  being absorbed under your justification."
    if [ -n "${UPDATE_GOLDEN_EXPECT+x}" ]; then
        want="$( printf '%s' "$UPDATE_GOLDEN_EXPECT" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ *$//' )"
        got="$(  printf '%s' "$moved"                | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ *$//' )"
        if [ "$want" != "$got" ]; then
            echo "printffmtparitycheck: MOVED SET MISMATCH — expected {$want}, got {$got}. The manifest was written;"
            echo "  DO NOT COMMIT IT until the difference is explained."
            exit 4
        fi
        echo "  UPDATE_GOLDEN_EXPECT matched: {$got}"
    fi
    exit 0
fi

[ -f "$MANIFEST" ] || { echo "printffmtparitycheck: no manifest at $MANIFEST — run with UPDATE_GOLDEN=1 first"; exit 2; }

while read -r label wantRc wantOutHash wantErrHash; do
    [ -n "$label" ] || continue
    runVerb "$label"; rc=$?
    gotOutHash="$( hashfile "$TMP/out" )"
    gotErrHash="$( hashfile "$TMP/err" )"
    if [ "$rc" != "$wantRc" ]; then
        no "$label: exit code changed ($wantRc -> $rc)"
    elif [ "$gotOutHash" != "$wantOutHash" ]; then
        no "$label: STDOUT bytes changed (sha256 $wantOutHash -> $gotOutHash) — a printf-family conversion altered output"
    elif [ "$gotErrHash" != "$wantErrHash" ]; then
        no "$label: STDERR bytes changed (sha256 $wantErrHash -> $gotErrHash) — a printf-family conversion altered a refusal/diagnostic message"
    else
        ok "$label (rc=$rc, out=$gotOutHash, err=$gotErrHash)"
    fi
done <"$MANIFEST"

if [ "$fail" = 0 ]; then
    echo "ALL PASS — printf-family byte parity holds over $( wc -l <"$MANIFEST" | tr -d ' ' ) verbs"
else
    echo "printffmtparitycheck: FAIL — see above. Any file whose conversion moved these bytes must be reverted."
fi
exit $fail
