#!/usr/bin/env bash
# testrowruncheck.sh — the FAMILY gate for "a tests_to_run row says how to run it".
#
# capture-audit 2026-09-04, finding M21(b) (lens 0 M0-3, lens 2 L2, lens 8 §(2)).
#
# THE DEFECT. Seven verbs answer "which tests must I run" and they did not agree on whether the answer is a
# COMMAND or a PATH. --test-gate — the verb that EXITS 4 calling its rows "the obligations" — printed
# `<t p="./test/verify_radix.cpp"/>`: the agent is told a test must run and not how. --handoff printed the
# same rows with no run= at all while --situ/--pr-context/--affected beside it carried
# `run="bash test/…check.sh"` for the same file. testmap.h's rule was "absent run= means NOT DERIVABLE", and
# that rule is right — a guessed command is worse than none — but an ABSENCE is not a disclosure: a reader
# cannot tell "no runner exists for this harness" from "this emitter forgot to ask". The honesty contract
# (a zero means none FOUND, every gap stated where it is consumed) wants the not-derivable case SAID.
#
# THE PROPERTY, asserted over the family and not over one verb: every tests_to_run row, in every dialect,
# carries EITHER a real `run=` / `"run":` / `(run: …)` recipe OR the explicit `run_unknown="1"` /
# `"run_unknown":true` / `(run: not derivable)` disclosure — never neither. Plus M21(b)'s second half: the
# untested blast-radius `<u>` rows carry `l=`, the line their sibling --flags --flip rows have always had.
#
# E1 / A4-2 (2026-09-12, owner call): runner-less rows that share their per-row attributes are served as ONE
# `<g … n= p="a,b,c" run_unknown="1"/>` row (JSON `{"p":[…],…,"n":N,"run_unknown":true}`, text
# `[hops=N] (n): a, b, c   (run: not derivable)`), so the disclosure is said once per GROUP. The rule keeps
# its meaning — "a <t> or <g> row carries one or the other, never neither" — and arm 12 proves what the
# grouping must never change: the MULTISET of paths (every path verbatim, each exactly once, across every
# dialect), on a fixture with three hop groups and a runner row in the middle of one of them.
#
# ARM 0 is the DERIVATION arm: it enumerates the row emitters out of src/ and fails when a site appears that
# the arms below do not drive. That is what makes this a family gate rather than seven instance gates — a
# NEW verb that grows a tests_to_run row is a FAILURE here until it is driven and disclosed. Since E1 every
# emitter renders its rows through testmap.h's ONE seam (testRowsRendered), so the census is its call sites.
#
# Usage:  test/testrowruncheck.sh              # uses build/ripwire
#         RIPWIRE_BIN=asan/ripwire test/testrowruncheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }

echo "testrowruncheck: BIN=$BIN"

# ── ARM 0 — the emitter census, derived from src/ ──────────────────────────────────────────────────────
# Every site that prints a tests_to_run row. The list is the CONTRACT: a site added to src/ and not added
# here fails, which is the only way a family gate stays a family gate. forpage.h (forbudget-soft round C) renders the --for
# answer's FILE tail rows (`<t p=… sym=…/>`, moved there from serialize.h, already excluded): file rows, not tests_to_run.
EXPECTED_SITES="src/verbs_change.h src/situ.h src/prcontext.h src/packtask.h src/handoff.h src/flipimpact.h src/mcpverbs.h src/mcpedit.h"
FOUND_SITES="$( cd "$ROOT" && grep -lE 'testRows(Rendered|Joined|List)\(|"<(t|test) p=\\"|\{\\"test\\":|\{\\"p\\":\\"%s\\"%s\}' src/*.h src/*.cpp 2>/dev/null \
                | grep -vE 'src/(serialize|testmap|forpage)\.h' | sort | tr '\n' ' ' | sed 's/ $//' )"
WANT_SITES="$( printf '%s\n' $EXPECTED_SITES | sort | tr '\n' ' ' | sed 's/ $//' )"
[ "$FOUND_SITES" = "$WANT_SITES" ] \
    && ok "(0) the tests_to_run row emitters are exactly the census this gate drives" \
    || no "(0) emitter census drifted: src/ has [$FOUND_SITES], gate drives [$WANT_SITES] — drive the new one or explain it here"

# ── the fixture ────────────────────────────────────────────────────────────────────────────────────────
# Two harnesses on purpose, because the property has TWO sides and a fixture that exercises one of them
# proves nothing about the other:
#   test/covered.cpp   — a shell runner shares its STEM (test/covered.sh) ⇒ run= IS derivable
#   test/lonely.cpp    — nothing names it anywhere              ⇒ run= is NOT derivable ⇒ run_unknown
WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/src" "$WORK/test"
cat > "$WORK/src/app.cpp" <<'EOF'
int compute( int x )
{
    return x + 1;
}

int wrapper( int x )
{
    return compute( x );
}
EOF
cat > "$WORK/test/covered.cpp" <<'EOF'
int compute( int x );
int test_covered( void )
{
    return compute( 1 );
}
EOF
cat > "$WORK/test/lonely.cpp" <<'EOF'
int wrapper( int x );
int test_lonely( void )
{
    return wrapper( 2 );
}
EOF
# a second source file whose CALLER no test reaches — that is what makes the untested blast radius (the
# <u> rows arm 10 asserts) non-empty. --test-gate's untested set is the transitive-caller reach of the
# CHANGED symbols minus the changed symbols themselves, minus anything a test reaches: so the fixture needs
# a changed callee (helper_core, dirtied below) with an unchanged, untested caller (nobody_tests_me).
cat > "$WORK/src/util.cpp" <<'EOF'
int helper_core( int x )
{
    return x + 0;
}
EOF
# the caller lives in its OWN file: the changed-symbol set is FILE-granular, so a caller sharing util.cpp
# would be "changed" too and the untested radius would come back empty (measured: impacted="0").
cat > "$WORK/src/consumer.cpp" <<'EOF'
int helper_core( int x );

int nobody_tests_me( int x )
{
    return helper_core( x );
}
EOF
cat > "$WORK/test/covered.sh" <<'EOF'
#!/usr/bin/env bash
echo covered
EOF
chmod +x "$WORK/test/covered.sh"
# a DARK gate whose guarded region sits in a file the tests reach, so --flags --flip has a report to make
# with <t> rows in it (arm 7 skipped on every fixture for a release — it also read the wrong row element).
printf 'cmake_minimum_required( VERSION 3.20 )\nproject( trr )\noption( FEATURE_WRAP "the dark one" OFF )\n' > "$WORK/CMakeLists.txt"
# INSIDE wrapper's body, not beside it: a flip's tests are the tests that reach the gate's HOSTS, and a
# host that is itself dark is reached by nothing — the region has to sit in a function a test already calls.
cat > "$WORK/src/app.cpp" <<'APPEOF'
int compute( int x )
{
    return x * 2;
}

int wrapper( int x )
{
#ifdef FEATURE_WRAP
    if( x > 100 )
    {
        return compute( x + 1 );
    }
#endif
    return compute( x );
}
APPEOF
( cd "$WORK" && git init -q && git config user.email t@t && git config user.name t \
  && git add -A && git commit -qm init >/dev/null 2>&1 )
# a second commit so the ref-taking verbs (--pr-context, --handoff) have a base to diff against, and a
# dirty working tree so the diff-seeded verbs (--test-gate, --situ) have a change set at all.
printf 'int extra( int x ) { return x - 1; }\n' >> "$WORK/src/app.cpp"
( cd "$WORK" && git add -A && git commit -qm second >/dev/null 2>&1 )
# RE-PINNED (2026-09-27, the symbol-granular change set): the uncommitted app.cpp edit is a MODULE-LEVEL
# append, not a never-called function. --test-gate/--handoff now narrow to the symbols the hunks locate
# (situ.h computeSymbolChangeSet; test/situhunkcheck.sh), and an appended uncalled function would leave
# app.cpp's tests (they reach compute/wrapper, not the new symbol) out of every row — the arms below would
# assert over an empty document. The module-scope line is the documented unlocated-hunk fallback, so
# app.cpp's change set stays file-granular and every pinned row/multiset holds. util.cpp's body-only sed
# needs no such help: it LOCATES in helper_core, its only symbol — narrowed == file-granular there.
printf 'int extra2_state = 2;\n' >> "$WORK/src/app.cpp"
# dirty helper_core's BODY only, so nobody_tests_me stays unchanged and lands in the untested blast radius.
sed -i.bak 's/return x + 0;/return x + 7;/' "$WORK/src/util.cpp" && rm -f "$WORK/src/util.cpp.bak"

rw(){ ( cd "$WORK" && "$BIN" . "$@" --no-cache 2>/dev/null ); }

# ── the two assertions every arm shares ────────────────────────────────────────────────────────────────
# $1 = a label, $2 = the document, $3 = the row regex, $4 = the "has a recipe" regex,
# $5 = the "says it has none" regex.
rows_disclosed(){
    local label="$1" doc="$2" rowre="$3" hasre="$4" unkre="$5"
    local rows n bad
    rows="$( printf '%s' "$doc" | grep -oE "$rowre" )"
    n="$( printf '%s' "$rows" | grep -c . )"
    if [ "${n:-0}" -eq 0 ]; then
        no "$label: fixture produced no tests_to_run rows — the arm cannot bite"; printf '%s\n' "$doc" | head -c 800; echo
        return
    fi
    bad="$( printf '%s\n' "$rows" | grep -vE "$hasre" | grep -vE "$unkre" )"
    if [ -n "$bad" ]; then
        no "$label: $( printf '%s\n' "$bad" | grep -c . ) of $n row(s) carry neither a run recipe nor the not-derivable disclosure"
        printf '%s\n' "$bad" | head -5
    else
        ok "$label: all $n tests_to_run row(s) carry a run recipe or run_unknown"
    fi
    # non-vacuity: the fixture must produce BOTH shapes wherever the verb lists both harnesses, so a gate
    # that only ever sees run= cannot pass an emitter that never learned to say run_unknown.
    printf '%s\n' "$rows" | grep -qE "$unkre" \
        || printf '        NOTE  %s listed no not-derivable row (verb reached only the covered harness)\n' "$label"
}

# E1: a <g …> group row is a tests_to_run row too (its p= lists several paths); the JSON twin's "p"/"test"
# is then an ARRAY. Both shapes must carry the disclosure like any single row.
XROW='<(t|test) p="[^"]*"[^>]*/>|<g [^>]*/>'
XHAS=' run="'
XUNK=' run_unknown="1"'
JROW='\{"(p|test)":("[^"]*"|\[[^]]*\])[^}]*\}'
JHAS='"run":"'
JUNK='"run_unknown":true'
# the JSON dialects embed the tests_to_run LIST inside a document that also carries file rows keyed "p";
# slice the list first so the arm asks its question of the row family it is about and no other.
#
# Review of #214: this slicer was `grep -oE '"tests_to_run":\[[^]]*\]'`, which stops at the first ']' — and
# since E1 the first ']' is the end of the FIRST GROUP's path array, not of the list. Arms 3, 5 and 9 were
# asserting over two and a half rows and passing vacuously. The slice is now taken by BRACKET DEPTH, in
# test/testrowpaths.py, which is also the reader every other gate in the tree uses for these rows.
ROWPATHS="$ROOT/test/testrowpaths.py"
json_tests(){ printf '%s' "$1" | sed 's/\\"/"/g' | python3 "$ROWPATHS" jsonlist; }
# the FILES a document names, in emitted order, in any dialect — singles and <g>/array groups alike
row_paths(){ printf '%s' "$2" | python3 "$ROWPATHS" paths "$1"; }

# ── ARM 1 — --affected (verbs_change.h) ────────────────────────────────────────────────────────────────
rows_disclosed "(1) --affected"  "$( rw --affected=compute,wrapper )" "$XROW" "$XHAS" "$XUNK"
# ── ARM 2 — --exercises seed rows (verbs_change.h) ─────────────────────────────────────────────────────
rows_disclosed "(2) --exercises" "$( rw --exercises=test/lonely.cpp )" "$XROW" "$XHAS" "$XUNK"
# ── ARM 3 — --test-gate, both dialects (situ.h) ────────────────────────────────────────────────────────
TG="$( rw --test-gate )"
rows_disclosed "(3) --test-gate xml"  "$TG"                     "$XROW" "$XHAS" "$XUNK"
rows_disclosed "(3) --test-gate json" "$( json_tests "$( rw --test-gate --json )" )" "$JROW" "$JHAS" "$JUNK"
# ── ARM 4 — --pr-context (prcontext.h) ─────────────────────────────────────────────────────────────────
rows_disclosed "(4) --pr-context" "$( rw --pr-context )" "$XROW" "$XHAS" "$XUNK"
# ── ARM 5 — --pack-task, both dialects (packtask.h) ────────────────────────────────────────────────────
rows_disclosed "(5) --pack-task xml"  "$( rw --pack-task="change compute and wrapper" )"        "$XROW" "$XHAS" "$XUNK"
rows_disclosed "(5) --pack-task json" "$( json_tests "$( rw --pack-task="change compute and wrapper" --json )" )" "$JROW" "$JHAS" "$JUNK"
# ── ARM 6 — --handoff (handoff.h) — the row family lens 2 L2 found carrying NO run= at all ─────────────
rows_disclosed "(6) --handoff" "$( rw --handoff )" "$XROW" "$XHAS" "$XUNK"
# ── ARM 7 — --flags --flip (flipimpact.h) ──────────────────────────────────────────────────────────────
# the gate row is `<gate name="…" kind=…>`; this arm read `<g n="…"` for a release, which matches nothing
# --flags emits, so it skipped on every fixture including one that HAS a gate (review of #214).
FLIPNAME="$( rw --flags | grep -oE '<gate name="[^"]+"' | head -1 | sed -E 's/^<gate name="([^"]*)"$/\1/' )"
FLIPOUT=""
[ -n "$FLIPNAME" ] && FLIPOUT="$( rw --flags --flip="$FLIPNAME" )"
if printf '%s' "$FLIPOUT" | grep -qE '<(t|test) p="'; then
    rows_disclosed "(7) --flags --flip" "$FLIPOUT" "$XROW" "$XHAS" "$XUNK"
else
    # NOT a silent pass: the flip verb's own <t> emitter is in the arm-0 census, so when the fixture cannot
    # reach it the gate says so out loud rather than letting the census claim coverage it did not get.
    printf '  SKIP  (7) --flags --flip emitted no test row on this fixture (gate=%s) — arm 0 pins the emitter, and test/flipcheck.sh coverage arm pins the row shape on a fixture that has a dark gate\n' "${FLIPNAME:-none}"
fi
# ── ARM 8 — --situ's TEXT dialect (situ.h) ─────────────────────────────────────────────────────────────
SITU="$( rw --situ )"
# A5 (2026-09-13): the section's closing script-gate disclosure is now the attribute line
# `script_gates_unmodelled=N — …` rather than a parenthesised sentence, so "starts with (" no longer
# excludes it.
#
# Review of #219: the discriminator used to be "a path never contains '='", which is FALSE — `test=smoke.sh`
# is a legal filename. Any row whose path carried '=' was filed as an attribute line and dropped, so arm 8
# skipped its `(run: …)` validation entirely and could pass while that row shipped a broken recipe. Same
# species as everything else this round: an arm passing over a row it silently discarded. The filter now
# names the ONE disclosure line this section emits, so a row can never be mistaken for it — and arm 8b
# below feeds this same function a '='-bearing path to prove it.
# Second review of #219: `script_gates_unmodelled=` alone is still a PREFIX, and isTestPath accepts
# `*_test.*`, so a legal row for a file literally named `script_gates_unmodelled=123 — …` would match it and
# be dropped — the same over-broad-filter defect one notch narrower. The filter now matches the disclosure's
# COMPLETE fixed text anchored to end of line, so only the disclosure can satisfy it.
situRowsOf()   # $1 = a --situ text report; prints the tests-to-run ROWS only
{
    printf '%s\n' "$1" | sed -n '/tests to run/,/^  \[3\]/p' | grep -E '^        [^ (]' \
        | grep -vE '^        script_gates_unmodelled=[0-9]+ — test/\*\.sh gates never appear above: script-to-binary edges are not call edges \(a path count\)$'
}
SITU_ROWS="$( situRowsOf "$SITU" )"
if [ -z "$SITU_ROWS" ]; then
    no "(8) --situ: fixture produced no 'tests to run' rows — the arm cannot bite"; printf '%s\n' "$SITU" | head -30
else
    SITU_BAD="$( printf '%s\n' "$SITU_ROWS" | grep -v '(run: ' )"
    [ -z "$SITU_BAD" ] \
        && ok "(8) --situ text: all $( printf '%s\n' "$SITU_ROWS" | grep -c . ) test line(s) carry a (run: …) recipe or its not-derivable form" \
        || { no "(8) --situ text: a tests-to-run line carries no run recipe and no disclosure"; printf '%s\n' "$SITU_BAD"; }
fi
# ── ARM 8b — the row/disclosure DISCRIMINATOR itself, on a path arm 8 would have dropped ───────────────
# Fed to situRowsOf above, not to a copy of its expression, so the two cannot drift. A synthetic block
# rather than a fixture: the defect is in the filter, and a filename with '=' in a crawled corpus would be
# testing the crawl instead. Both directions are asserted — the '='-bearing ROW survives AND the
# disclosure line is still removed — because a filter that kept everything would pass the first alone.
# The disclosure line here is the emitter's COMPLETE text, taken from a live run rather than abbreviated:
# an abbreviated copy would be excluded by a prefix filter and kept by the anchored one, so a truncated
# fixture would test the fixture instead of the filter. The third row is the ADVERSARY the second review
# named — a legal filename that BEGINS with the disclosure's key, which the prefix form dropped and the
# anchored form must keep.
SYNTH_SITU="$( printf '%s\n' \
    '  [2] tests to run (3):' \
    '        test=smoke.sh (run: bash test=smoke.sh)' \
    '        test/plaincheck.sh (run: bash test/plaincheck.sh)' \
    '        script_gates_unmodelled=9_test.sh (run: bash script_gates_unmodelled=9_test.sh)' \
    '        script_gates_unmodelled=672 — test/*.sh gates never appear above: script-to-binary edges are not call edges (a path count)' \
    '  [3] co-change' )"
SYNTH_ROWS="$( situRowsOf "$SYNTH_SITU" )"
printf '%s\n' "$SYNTH_ROWS" | grep -q 'test=smoke.sh' \
    && ok "(8b) a tests-to-run row whose PATH contains '=' is kept, not filed as an attribute line" \
    || no "(8b) a '='-bearing path row was dropped by the row filter — arm 8 would skip validating its (run: …)"
printf '%s\n' "$SYNTH_ROWS" | grep -q 'script_gates_unmodelled=9_test.sh' \
    && ok "(8b) a legal path that BEGINS with 'script_gates_unmodelled=' is kept — the filter matches the disclosure's whole text, not its prefix" \
    || no "(8b) a path beginning with the disclosure's key was dropped — the filter is still a prefix match"
printf '%s\n' "$SYNTH_ROWS" | grep -q 'are not call edges (a path count)$' \
    && no "(8b) the script_gates_unmodelled= disclosure leaked into the ROW set — arm 8 would demand a run recipe from a disclosure" \
    || ok "(8b) the script_gates_unmodelled= disclosure is still excluded from the row set"
[ "$( printf '%s\n' "$SYNTH_ROWS" | grep -c . )" = 3 ] \
    && ok "(8b) exactly the 3 synthetic rows survive the filter" \
    || no "(8b) filter kept $( printf '%s\n' "$SYNTH_ROWS" | grep -c . ) line(s), expected 3: $( printf '[%s]' "$SYNTH_ROWS" )"
# ── ARM 9 — MCP situational_awareness (mcpverbs.h) ─────────────────────────────────────────────────────
MCPOUT="$( printf '%s\n%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"situational_awareness","arguments":{"path":"'"$WORK"'"}}}' \
  | ( cd "$WORK" && "$BIN" --mcp 2>/dev/null ) )"
rows_disclosed "(9) mcp situational_awareness" "$( json_tests "$MCPOUT" )" "$JROW" "$JHAS" "$JUNK"

# ── ARM 10 — M21(b) second half: the untested blast-radius <u> rows carry a LINE ───────────────────────
# `<u sym="dispatchMcpLine" p="./src/mcp.h" ccx="439"/>` names a symbol to test and a file to open, and
# leaves the reader to find it. Its own sibling --flags --flip has printed `<u sym= p= l= ccx=>` since it
# was written; this is that attribute applied where the plan says it was missing. Both dialects.
UROWS="$( printf '%s' "$TG" | grep -oE '<u [^>]*/>' )"
if [ -z "$UROWS" ]; then
    no "(10) --test-gate produced no <u> untested rows — the arm cannot bite"; printf '%s\n' "$TG" | tail -c 600
else
    printf '%s\n' "$UROWS" | grep -vqE ' l="[0-9]+"' \
        && { no "(10) an untested <u> row carries no l= line"; printf '%s\n' "$UROWS" | grep -vE ' l="[0-9]+"' | head -3; } \
        || ok "(10) every --test-gate untested <u> row carries l= ($( printf '%s\n' "$UROWS" | grep -c . ) rows)"
fi
UJSON="$( rw --test-gate --json | grep -oE '\{"sym":"[^"]*"[^}]*\}' )"
if [ -z "$UJSON" ]; then
    no "(10) --test-gate --json produced no untested rows — the arm cannot bite"
else
    printf '%s\n' "$UJSON" | grep -vqE '"l":[0-9]+' \
        && { no "(10) a JSON untested row carries no \"l\""; printf '%s\n' "$UJSON" | head -3; } \
        || ok "(10) every --test-gate --json untested row carries \"l\" (the XML twin's l=)"
fi

# ── ARM 11 — the disclosure is DEFINED where it is emitted ─────────────────────────────────────────────
# legendcoveragecheck.sh owns this rule tool-wide; pinned here too because run_unknown= is the attribute
# this gate exists for, and an undefined attribute is a fact the reader cannot use.
# The legend is everything BEFORE the root element's start tag (the document is one line, so a greedy
# regex over <!--…--> would capture only the last comment — that mistake made this arm read as red while
# the definition was present).
TG_LEGEND="${TG%%<test-gate *}"
if printf '%s' "$TG" | grep -q 'run_unknown'; then
    printf '%s' "$TG_LEGEND" | grep -q 'run_unknown' \
        && ok "(11) run_unknown= is defined in the legend of the document that emits it" \
        || { no "(11) run_unknown= emitted with no legend definition"; }
else
    printf '  SKIP  (11) this document emitted no run_unknown row\n'
fi

# ── ARM 12 — E1: grouping never changes the MULTISET of paths NOR THEIR ORDER, in any dialect ─────────
# A fixture with THREE hop groups (tests reaching the changed symbol at depth 1, 2 and 3) and a runner row
# in the MIDDLE of the depth-1 group (t_leaf_b.sh stem-matches t_leaf_b.cpp; path order a < b < c < d), so
# the arm sees: a runner-less run interrupted by a single run= row, groups at three distinct hops=, and the
# same eight paths in --affected, --test-gate (XML and JSON) and --situ's text. What it proves: every path
# appears exactly once (verbatim — a reader's grep for a file name must still hit), the run= row stays a
# single row, at least three <g> rows exist with distinct hops=, the root's tests= count is the number of
# FILES, not rows, and — review of #214, the A,B,A shape — the ORDER is preserved: the paths read off the
# rows in emitted order are exactly the order the single rows had, so a group only ever covers a CONTIGUOUS
# run and a runner row never has a later sibling hoisted in front of it. Red on the pre-E1 binary (no <g>
# row at all) and, for the order half, on 7ab0956a (which grouped a, c, d across b: a,c,d,b).
#
# The paths are read by test/testrowpaths.py — THE shared reader, so this arm and the eight other gates that
# assert over these rows cannot disagree about what a row is.
command -v python3 >/dev/null 2>&1 || no "(12) python3 missing — the multiset arm cannot run"
W2="$( mktemp -d )"; trap 'rm -rf "$WORK" "$W2"' EXIT
mkdir -p "$W2/src" "$W2/test"
printf 'int leaf( int x )\n{\n    return x + 1;\n}\n' > "$W2/src/leaf.cpp"
printf 'int leaf( int x );\nint mid( int x )\n{\n    return leaf( x );\n}\n' > "$W2/src/mid.cpp"
printf 'int mid( int x );\nint top( int x )\n{\n    return mid( x );\n}\n' > "$W2/src/top.cpp"
for n in leaf_a leaf_b leaf_c leaf_d; do printf 'int leaf( int x );\nint test_%s( void )\n{\n    return leaf( 1 );\n}\n' "$n" > "$W2/test/t_$n.cpp"; done
for n in mid_a mid_b; do printf 'int mid( int x );\nint test_%s( void )\n{\n    return mid( 1 );\n}\n' "$n" > "$W2/test/t_$n.cpp"; done
for n in top_a top_b; do printf 'int top( int x );\nint test_%s( void )\n{\n    return top( 1 );\n}\n' "$n" > "$W2/test/t_$n.cpp"; done
printf '#!/usr/bin/env bash\necho leaf_b\n' > "$W2/test/t_leaf_b.sh"; chmod +x "$W2/test/t_leaf_b.sh"
( cd "$W2" && git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -qm init >/dev/null 2>&1 )
# a second commit and a dirty tree, so the DIFF-seeded verbs (--pr-context, --handoff) have a change set to
# answer about: without one they report files="0" and name no test at all, and arm 12's group-shape half
# (and arm 14's positive control) would be asserting over an empty document.
printf 'int leaf_extra( int x )\n{\n    return x + 2;\n}\n' >> "$W2/src/leaf.cpp"
( cd "$W2" && git add -A && git commit -qm second >/dev/null 2>&1 )
# RE-PINNED (2026-09-27, the symbol-granular change set): module-level append, as in WORK above — the
# selector arms here (--test-gate=src/leaf.cpp, --situ=src/leaf.cpp, --handoff) must keep seeing leaf.cpp's
# WHOLE symbol set so the eight pinned paths at three hops survive; a never-called appended function would
# narrow the seeds to itself and empty every row (situ.h computeSymbolChangeSet's located-hunk rule).
printf 'int leaf_extra2_state = 3;\n' >> "$W2/src/leaf.cpp"
rw2(){ ( cd "$W2" && "$BIN" . "$@" --no-cache 2>/dev/null ); }
A12="$( rw2 --affected=src/leaf.cpp )"
G12="$( rw2 --test-gate=src/leaf.cpp )"
J12="$( rw2 --test-gate=src/leaf.cpp --json )"
S12="$( rw2 --situ=src/leaf.cpp )"
P12="$( rw2 --pr-context )"
H12="$( rw2 --handoff )"
K12="$( rw2 --pack-task="change leaf" )"
KJ12="$( rw2 --pack-task="change leaf" --json )"
ROOT="$ROOT" python3 - "$A12" "$G12" "$J12" "$S12" "$P12" "$H12" "$K12" "$KJ12" <<'PY12'
import sys, os, re
sys.path.insert( 0, os.path.join( os.environ[ "ROOT" ], "test" ) )
import testrowpaths as trp                      # THE shared reader — singles and <g>/array groups, any dialect
aff, tg, tgj, situ, prc, hoff, pt, ptj = sys.argv[1:9]
ORDER  = [ "test/t_%s.cpp" % n for n in ( "leaf_a", "leaf_b", "leaf_c", "leaf_d", "mid_a", "mid_b", "top_a", "top_b" ) ]   # evidence order: hops asc, then path
EXPECT = sorted( ORDER )
fails = []

# (a) the four dialects that serve the WHOLE list: same paths, same order, through the shared reader.
for label, doc, dialect in ( ( "--affected", aff, "xml" ), ( "--test-gate", tg, "xml" ),
                             ( "--test-gate --json", tgj, "json" ), ( "--situ text", situ, "text" ) ):
    paths = trp.xml_paths( doc ) if dialect == "xml" else ( trp.json_paths( doc ) if dialect == "json" else trp.text_paths( doc ) )
    if sorted( paths ) != EXPECT:
        fails.append( "%s multiset %r != %r" % ( label, sorted( paths ), EXPECT ) )
    if paths != ORDER:
        fails.append( "%s ORDER changed by grouping: %r != %r (a group must cover a contiguous run only)" % ( label, paths, ORDER ) )

# (b) the group shape itself EXISTS, at three distinct hops=, and the run= row stayed a single row.
for label, doc in ( ( "--affected", aff ), ( "--test-gate", tg ) ):
    body = trp.strip_comments( doc )
    hops = re.findall( r'<g [^>]*?\bhops="(\d+)"', body )
    if len( set( hops ) ) < 3:
        fails.append( "%s: expected >=3 <g> rows at distinct hops=, got hops=%r" % ( label, hops ) )
    runs = [ m.group( 0 ) for m in re.finditer( r'<(?:t|test|g)\b[^>]*?\brun="[^"]*"[^>]*/>', body ) ]
    if len( runs ) != 1 or runs[0].startswith( "<g " ):
        fails.append( "%s: the runner row is not exactly one SINGLE row: %r" % ( label, runs ) )
    tests = re.findall( r'\btests="(\d+)"', body )
    if tests and tests[0] != str( len( EXPECT ) ):
        fails.append( "%s: tests=%s counts rows, not FILES (expected %d)" % ( label, tests[0], len( EXPECT ) ) )

# (c) review of #214: the <g> shapes of the OTHER emitters were produced by no arm at all. This fixture
#     forms a group, so every one of them must show one — and every group row must carry the disclosure.
for label, doc, dialect in ( ( "--pr-context", prc, "xml" ), ( "--handoff", hoff, "xml" ),
                             ( "--pack-task", pt, "xml" ), ( "--pack-task --json", ptj, "json" ) ):
    if dialect == "xml":
        body   = trp.strip_comments( doc )
        groups = re.findall( r"<g [^>]*/>", body )
        if not groups:
            fails.append( "%s renders no <g> group row on a fixture that forms one" % label )
        for grow in groups:
            if 'run_unknown="1"' not in grow:
                fails.append( "%s group row carries no disclosure: %r" % ( label, grow ) )
            if not re.search( r'\bn="\d+"', grow ):
                fails.append( "%s group row carries no n=: %r" % ( label, grow ) )
    else:
        import json as _json
        sl = trp.json_list_slice( doc )
        rows = _json.loads( sl ) if sl else []
        arrays = [ r for r in rows if isinstance( r.get( "p", r.get( "test" ) ), list ) ]
        if not arrays:
            fails.append( "%s renders no array (group) row on a fixture that forms one: %r" % ( label, rows ) )
        for r in arrays:
            if r.get( "run_unknown" ) is not True or "n" not in r:
                fails.append( "%s group row missing n= or the disclosure: %r" % ( label, r ) )
    # and the files a group names are files this fixture has
    got = trp.xml_paths( doc ) if dialect == "xml" else trp.json_paths( doc )
    if not got:
        fails.append( "%s named no test file at all" % label )
    for g in got:
        if not g.endswith( tuple( os.path.basename( e ) for e in EXPECT ) ):
            fails.append( "%s named a path this fixture does not have: %r" % ( label, g ) )

if fails:
    print( "\n".join( fails ) ); sys.exit( 1 )
print( "OK %d paths in order, groups present in 8 dialect/verb combinations" % len( EXPECT ) )
PY12
r12=$?
[ "$r12" -eq 0 ] \
    && ok "(12) E1: grouping keeps the path multiset AND order in every dialect, and every emitter renders the <g> shape (8 paths, >=3 hop groups, the run= row single in place, tests= counts files)" \
    || no "(12) E1: the grouped rows do not carry the same paths, order or shape as the single rows did (details above)"

# ── ARM 13 — E1: a path that ESCAPES WIDER than it reads never costs the section its rows ─────────────
# --pack-task's <tests> section is byte-budgeted. It used to GROUP first and hand the group rows to the
# generic list cutter under a per-row byte cap whose estimate was `attrs + 48 + Σ(path+1)` over UNESCAPED
# paths — so a corpus whose test paths hold '&' (or '<', or '"') rendered wider than the cap admitted, the
# cutter broke at the first over-budget entry, and the whole TAIL of the section went with it, run= singles
# included. The section now cuts over its own grouped, ESCAPED rendering (packTaskTestsSection).
#
# A true matched pair: the same ten test files, the same path LENGTHS, differing in exactly one byte per
# name — '&' in one fixture, '_' in the other — plus one harness with a runner so a run= single is in play.
# The property: at every budget the '&' fixture names at least one file whenever the control does (it may
# name fewer — escaped paths really are wider — but it must never collapse to nothing), and neither fixture
# ever goes backwards as the budget grows. Red on ff8d77a1: at --token-budget=1440 the control serves 5
# files and the '&' fixture serves 0.
A13="$( mktemp -d )"; C13="$( mktemp -d )"; trap 'rm -rf "$WORK" "$W2" "$A13" "$C13"' EXIT
mk13(){ d="$1"; sep="$2"; mkdir -p "$d/src" "$d/test"
    printf 'int compute_value( int x )\n{\n    return x + 1;\n}\n' > "$d/src/core.cpp"
    for n in a b c d e f x y z w; do printf 'int compute_value( int x );\nint test_%s( void )\n{\n    return compute_value( 1 );\n}\n' "$n" > "$d/test/${n}${sep}t.cpp"; done
    printf 'int compute_value( int x );\nint test_run( void )\n{\n    return compute_value( 1 );\n}\n' > "$d/test/runme_t.cpp"
    printf '#!/usr/bin/env bash\necho runme\n' > "$d/test/runme_t.sh"; chmod +x "$d/test/runme_t.sh"
    ( cd "$d" && git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -qm init >/dev/null 2>&1 ); }
mk13 "$A13" '&'
mk13 "$C13" '_'
named13(){ ( cd "$1" && "$BIN" . --no-cache --pack-task="compute_value" --token-budget="$2" 2>/dev/null ) | python3 "$ROWPATHS" paths xml | grep -c . ; }
bad13=""; prevA=0; prevC=0; sawA=0
for b in 1440 1500 1560 1620 1680 1740 1800 1860; do
    na="$( named13 "$A13" $b )"; nc="$( named13 "$C13" $b )"
    [ "$na" -gt 0 ] && sawA=1
    [ "$nc" -gt 0 ] && [ "$na" -eq 0 ] && bad13="$bad13 budget=$b: control names $nc file(s), the '&' fixture names NONE"
    [ "$na" -lt "$prevA" ] && bad13="$bad13 budget=$b: the '&' fixture went backwards ($prevA -> $na)"
    [ "$nc" -lt "$prevC" ] && bad13="$bad13 budget=$b: the control went backwards ($prevC -> $nc)"
    prevA=$na; prevC=$nc
done
if [ "$sawA" -ne 1 ] || [ "$prevC" -eq 0 ]; then
    no "(13) neither fixture named a test file anywhere in 1440..1860 — the arm cannot bite"
elif [ -n "$bad13" ]; then
    no "(13) a '&' in a test path costs the <tests> section its rows:$bad13"
else
    ok "(13) E1: a path that escapes wider than it reads never drops the <tests> section (10 tests, '&' vs '_', budgets 1440..1860; both monotone, neither empty where the other is not)"
fi

# ── ARM 14 — the run-hint clause is gated on ROWS at every site that splices it ───────────────────────
# The clause is a rule ABOUT rows (~180 B). Review of #214: --handoff and --flags --flip spliced it
# unconditionally — and --handoff is BYTE-BUDGETED with heuristic rows dropped tail-first, so a packet with
# <tests n="0"> could evict a real row to pay for a rule about rows it has none of. Both now ask
# testmap.h's ONE gate (runHintClauseIfRows) with the count the seam returned.
# Fixture: a corpus with NO test file at all, so every verb below renders zero rows. Red on ff8d77a1 for
# --handoff; --flags --flip is asserted on the same corpus for the same reason.
N14="$( mktemp -d )"; trap 'rm -rf "$WORK" "$W2" "$A13" "$C13" "$N14"' EXIT
mkdir -p "$N14/src"
printf 'int alpha( int x )\n{\n    return x + 1;\n}\n' > "$N14/src/a.cpp"
# a DARK preprocessor gate, so --flags --flip has something to report on this corpus too: its legend splices
# the same clause and, review of #214, spliced it unconditionally.
cat > "$N14/src/b.cpp" <<'B14'
int alpha( int x );

int beta( int x )
{
    return alpha( x ) + 2;
}

#ifdef FEATURE_ZETA
int zeta_only( int x )
{
    return alpha( x ) * 3;
}
#endif
B14
# the gate itself is a CMake option() — the shape --flags reports as kind="cmake" default="OFF" dark="1"
printf 'cmake_minimum_required( VERSION 3.20 )\nproject( n14 )\noption( FEATURE_ZETA "the dark one" OFF )\n' > "$N14/CMakeLists.txt"
( cd "$N14" && git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -qm init >/dev/null 2>&1 )
printf 'int gamma_fn( int x ) { return x - 1; }\n' >> "$N14/src/b.cpp"
# L1 (2026-09-19): the CLI default legend is compact; (14) reads the FULL legend's run-hint clause (both the must-carry and
# the must-not-carry halves), so every probed document asks for the full legend.
CLAUSE='run= is the command that discharges a test row'
bad14=""
for v in --handoff --pr-context --test-gate --affected=src/a.cpp; do
    o="$( cd "$N14" && "$BIN" . $v --no-cache --legend=full 2>/dev/null )"
    rows="$( printf '%s' "$o" | python3 "$ROWPATHS" paths xml | grep -c . )"
    has="$( printf '%s' "$o" | grep -c "$CLAUSE" )"
    [ "$rows" -eq 0 ] && [ "$has" -ne 0 ] && bad14="$bad14 $v(0 rows, clause present)"
    [ "$rows" -gt 0 ] && [ "$has" -eq 0 ] && bad14="$bad14 $v($rows rows, clause MISSING)"
done
# --flags --flip on the same no-test corpus: zero <t> rows, so no clause either
FN14="$( ( cd "$N14" && "$BIN" . --flags --no-cache 2>/dev/null ) | grep -oE '<gate name="[^"]+"' | head -1 | sed -E 's/^<gate name="([^"]*)"$/\1/' )"
if [ -n "$FN14" ]; then
    o="$( cd "$N14" && "$BIN" . --flags --flip="$FN14" --no-cache --legend=full 2>/dev/null )"
    rows="$( printf '%s' "$o" | python3 "$ROWPATHS" paths xml | grep -c . )"
    has="$( printf '%s' "$o" | grep -c "$CLAUSE" )"
    [ "$rows" -eq 0 ] && [ "$has" -ne 0 ] && bad14="$bad14 --flags --flip=$FN14(0 rows, clause present)"
    [ "$rows" -gt 0 ] && [ "$has" -eq 0 ] && bad14="$bad14 --flags --flip=$FN14($rows rows, clause MISSING)"
else
    bad14="$bad14 --flags found no gate on the fixture (the flip half of this arm cannot bite)"
fi

# the positive control: the grouping fixture from arm 12 DOES carry rows, so the same verbs must carry it
for v in --handoff --pr-context; do
    o="$( rw2 $v --legend=full )"
    rows="$( printf '%s' "$o" | python3 "$ROWPATHS" paths xml | grep -c . )"
    has="$( printf '%s' "$o" | grep -c "$CLAUSE" )"
    [ "$rows" -gt 0 ] && [ "$has" -eq 0 ] && bad14="$bad14 control:$v($rows rows, clause MISSING)"
    [ "$rows" -eq 0 ] && bad14="$bad14 control:$v named no row — the positive control cannot bite"
done
[ -z "$bad14" ] \
    && ok "(14) the run-hint clause rides exactly the documents that render a row (5 verbs on a no-test corpus, 2 positive controls)" \
    || no "(14) the run-hint clause is not rows-gated:$bad14"

# ── ARM 15 — the partitioned bundle gates its outer clause on a COUNT, never on rendered bytes ────────
# partition.h asked `xml.find( "<tests " )` of each slice's RENDERED output. A bundle whose <bodies> CDATA
# quotes the literal text `<tests ` — any source file that WRITES that element does — answered yes with
# zero rows, and the outer legend paid ~180 B for a rule about rows the document has none of. Each bundle
# now REPORTS its kept count (packTaskBundleText's testsKeptOut) and the counts are summed.
# Fixture: a corpus with NO test file whose one body prints `<tests n="%d">`. Red on ff8d77a1.
Q15="$( mktemp -d )"; trap 'rm -rf "$WORK" "$W2" "$A13" "$C13" "$N14" "$Q15"' EXIT
mkdir -p "$Q15/src"
cat > "$Q15/src/emitter.cpp" <<'EOF'
#include <cstdio>

void write_report( FILE* out, int n )
{
    std::fprintf( out, "<tests n=\"%d\">", n );
    std::fprintf( out, "</tests>" );
}

void caller_one( FILE* out )
{
    write_report( out, 1 );
}

void caller_two( FILE* out )
{
    write_report( out, 2 );
}
EOF
printf 'void unrelated_helper( int x )\n{\n    (void)x;\n}\n' > "$Q15/src/other.cpp"
( cd "$Q15" && git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -qm init >/dev/null 2>&1 )
O15="$( cd "$Q15" && "$BIN" . --no-cache --pack-task="write_report" --partition=2 2>/dev/null )"
lit15="$( printf '%s' "$O15" | grep -c '<tests ' )"
sec15="$( printf '%s' "$O15" | grep -c '<tests shown=' )"
cls15="$( printf '%s' "$O15" | grep -c "$CLAUSE" )"
if [ "$lit15" -eq 0 ]; then
    no "(15) the fixture's body does not carry the literal '<tests ' — the arm cannot bite"
elif [ "$sec15" -ne 0 ]; then
    no "(15) the fixture produced a real <tests> section — it was meant to have no test file at all"
elif [ "$cls15" -ne 0 ]; then
    no "(15) the partitioned bundle charges the run-hint clause for a body that merely QUOTES '<tests ' (zero rows)"
else
    ok "(15) the partitioned bundle's outer clause follows the slices' kept COUNTS, not a grep over their bytes"
fi


# ── ARM 16 — THE SHARED READER'S OWN TWO SILENCES (CodeRabbit on #214) ────────────────────────────────
# test/testrowpaths.py exists because eight private readers went quiet instead of failing. Two of its own
# did the same, and neither had a control until now.
#
# (a) A TRUNCATED JSON document. json_list_slice returned None both when the field is ABSENT and when its
#     array never closes, and json_paths turned None into [] with exit 0 — so a document cut mid-array
#     asserted over zero rows and PASSED. The two are different claims and now answer differently: no field
#     is an answer (0 paths, exit 0); a field whose list never closes is exit 2 with a named reason.
# (b) A PATH WITH A SPACE in the text dialect. The single-row reader took `(\S+)`, which stops at the first
#     space, so such a path was reported TRUNCATED — a path that does not exist, produced silently. The
#     reader now cuts the run suffix and the renderer's own attribute tail ([changed] [partner] [hops=N], in
#     that order) and keeps everything else verbatim.
#
# Both arms are RED on the reader as it stood at 6621370f (a: 0 paths, rc=0; b: "test/with" for
# "test/with space.cpp") and are pure reader tests — no binary, so they cost nothing.
r16bad=""
# (a) absent field: an answer. Truncated list: an error. Balanced list with a group: the rows.
a16="$( printf '%s' '{"blast_radius":[]}' | python3 "$ROWPATHS" paths json 2>/dev/null )"; a16rc=$?
[ "$a16rc" -eq 0 ] && [ -z "$a16" ] || r16bad="$r16bad [absent tests_to_run should be 0 paths at rc=0, got rc=$a16rc paths=$( printf '%s' "$a16" | tr '\n' ' ' )]"
t16="$( printf '%s' '{"tests_to_run":[{"p":["a","b"],"n":2},{"p":"c"}' | python3 "$ROWPATHS" paths json 2>/dev/null )"; t16rc=$?
[ "$t16rc" -eq 2 ] && [ -z "$t16" ] || r16bad="$r16bad [an unterminated tests_to_run array must be exit 2 with no rows, got rc=$t16rc paths=$( printf '%s' "$t16" | tr '\n' ' ' )]"
l16="$( printf '%s' '{"tests_to_run":[{"p":["a","b"],"n":2},{"p":"c"}]}' | python3 "$ROWPATHS" jsonlist 2>/dev/null )"; l16rc=$?
[ "$l16rc" -eq 0 ] && [ -n "$l16" ] || r16bad="$r16bad [the balanced control no longer slices: rc=$l16rc]"
j16="$( printf '%s' '{"tests_to_run":[{"p":["a","b"],"n":2},{"p":"c"}' | python3 "$ROWPATHS" jsonlist 2>/dev/null )"; j16rc=$?
[ "$j16rc" -eq 2 ] || r16bad="$r16bad [jsonlist swallows the same truncation: rc=$j16rc]"
# (b) the text dialect, in the renderer's own spelling (testmap.h: path, then [changed] [partner] [hops=N],
#     then three spaces and the run suffix). Every path here holds a space; one holds all three attributes.
T16="$( printf '%s\n' \
    '        test/with space.cpp   (run: not derivable)' \
    '        test/two words.cpp [hops=2]   (run: ctest -R two)' \
    '        test/a b c.cpp [changed] [partner] [hops=1]   (run: ctest -R abc)' \
    '        [hops=3] (2): test/g one.cpp, test/g two.cpp   (run: not derivable)' )"
p16="$( printf '%s' "$T16" | python3 "$ROWPATHS" paths text 2>/dev/null | tr '\n' '|' )"
e16='test/with space.cpp|test/two words.cpp|test/a b c.cpp|test/g one.cpp|test/g two.cpp|'
[ "$p16" = "$e16" ] || r16bad="$r16bad [text single rows truncate a path at its first space: got '$p16' want '$e16']"
[ -z "$r16bad" ] \
    && ok "(16) the shared reader fails LOUDLY on a truncated tests_to_run array (exit 2, absent field still 0 rows) and keeps a text path's spaces" \
    || no "(16) the shared reader is still silent where it should fail:$r16bad"


# ── ARM 17 — THE THIRD SILENCE: "tests_to_run" PRESENT BUT NOT A LIST (review of #214) ────────────────
# json_list_slice found the key and then ran `doc.find( "[", i )` — an UNBOUNDED forward scan. So a document
# spelling `"tests_to_run":null` was not read as "the field is not a list"; the scan walked PAST the value,
# found the NEXT '[' anywhere in the document, and sliced THAT. Measured on the reader as it stood at
# c9d6d4e8: `{"tests_to_run":null,"other":[{"p":"ghost.cpp"}]}` returned ghost.cpp at rc=0 — a foreign
# field's paths served as the tests_to_run answer, which is the same species of defect arm 16 closed and one
# step worse, because the caller is handed rows rather than silence. The docstring already promised the
# raise ("is followed by no '[' — not a list at all"); only the code disagreed.
#
# The fix reads the value ADJACENTLY: past the key, a ':', optional whitespace, and then the very next
# character must be '['. Every non-array value is exit 2; a well-formed array still parses, which is what
# the controls below hold.
r17bad=""
# (a) every non-array value raises — and the decoy '[' that used to be sliced names a path that would be
#     served as a test row. null, a number, a string and an OBJECT all take this leg.
for d17 in '{"tests_to_run":null,"other":[]}' \
           '{"tests_to_run":null,"other":[{"p":"ghost.cpp"}]}' \
           '{"tests_to_run":7,"other":[{"p":"ghost.cpp"}]}' \
           '{"tests_to_run":"nope","other":[{"p":"ghost.cpp"}]}' \
           '{"tests_to_run":{"a":[{"p":"ghost.cpp"}]}}'; do
    o17="$( printf '%s' "$d17" | python3 "$ROWPATHS" paths json 2>/dev/null )"; o17rc=$?
    { [ "$o17rc" -eq 2 ] && [ -z "$o17" ]; } \
        || r17bad="$r17bad [$d17 -> rc=$o17rc paths='$( printf '%s' "$o17" | tr '\n' ' ' )', want rc=2 and no rows]"
    # the jsonlist mode shares the slicer, so it owes the same answer
    printf '%s' "$d17" | python3 "$ROWPATHS" jsonlist >/dev/null 2>&1
    [ $? -eq 2 ] || r17bad="$r17bad [jsonlist swallows the same non-list value: $d17]"
done
# (b) the CONTROLS: a well-formed array still parses, whitespace between ':' and '[' is legal JSON, and a
#     group row's nested array is still sliced by depth rather than by the first ']'.
c17="$( printf '%s' '{"tests_to_run":[{"p":"ok.cpp"}]}' | python3 "$ROWPATHS" paths json 2>/dev/null )"; c17rc=$?
{ [ "$c17rc" -eq 0 ] && [ "$c17" = "ok.cpp" ]; } \
    || r17bad="$r17bad [the well-formed control no longer parses: rc=$c17rc paths='$c17']"
w17="$( printf '%s' '{"tests_to_run"  :  [{"p":["a","b"],"n":2},{"p":"c"}]}' | python3 "$ROWPATHS" paths json 2>/dev/null | tr '\n' '|' )"; w17rc=$?
{ [ "$w17rc" -eq 0 ] && [ "$w17" = "a|b|c|" ]; } \
    || r17bad="$r17bad [whitespace around the ':' must stay legal: rc=$w17rc paths='$w17']"
[ -z "$r17bad" ] \
    && ok "(17) a present-but-not-a-list tests_to_run is exit 2, never a slice of the NEXT field's array — the value is read adjacently" \
    || no "(17) the slicer still scans past its own field:$r17bad"


[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit "$fail"
