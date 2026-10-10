#!/usr/bin/env bash
# rootspellingcheck.sh — #228: an ANSWER must not depend on how the crawl root was TYPED.
#
# `ripwire .`, `ripwire ./`, `ripwire "$PWD"`, `ripwire "$PWD/"`, `ripwire <a symlink to the tree>` and
# `ripwire ../<tree>` name one tree. Before #228 the crawl stored every path with the root exactly as typed,
# and the index builders and path predicates read that spelling raw, so three families of answer moved with it:
#   * RESOLUTION — Python's root-relative import probe joined onto an EMPTY base, which is the crawl root only
#     when the root was typed `.`. Under "$PWD" (every MCP session, and the --quality-delta HEAD side, which
#     always ingests at an absolute temp root) `from pkg.store import load` stopped resolving and the name
#     ladder bound the same-directory `load` instead. A root typed `../tree` was worse: lexicalNormalize
#     refuses a path that starts above its base, so every include/import key came out empty in EVERY language.
#   * PATH PREDICATES — isTestPath / isFixturePath / builtinLayer walked the directories ABOVE the root, so a
#     checkout that merely lives under tests/ or fixtures/ had every file called a test (layer="test", dead-code
#     exempt, --affected seeds) under an absolute root and none under `.`.
#   * --quality-delta compared a working tree ingested as typed with a HEAD tree ingested absolute, so an
#     unchanged four-file tree gated (exit 2) under `.` and passed under "$PWD" (the reporter's repro).
# The fix is one seam, model.h::rootRelPath: the root ingest() recorded, stripped lexically. This gate is the
# claim stated as measurements, over the committed four-file fixture and every language import fixture.
#
# Arms:
#   (1) SPELLING INVARIANCE — per fixture, map / --deps / --callers / --impact / --affected / --quality-delta
#       (plus --dead-code / --for / --pack-task on the four-file tree, whose route anchors and callee rows printed
#       the typed root) stdout and exit status are byte-identical across six spellings once ONLY the printed root
#       is normalised (root="…", and est_tokens=, which prices the root= bytes).
#   (2) POSITIVE CONTROLS — resolution actually happened under every spelling: named edges exist, the resolver
#       gauge sits where it should, --quality-delta exits 0 on the root element with zero regressions. Without
#       these, (1) would pass on six empty documents (CONTRIBUTING §2 shape 3).
#   (3) SENSITIVITY — a real edit that CHANGES which `load` the import binds must gate (exit 2) under `.` and
#       under the absolute spelling alike: the zero in (2) is a verdict the arm can reach, not a constant.
#   (4) A DIRECTORY ABOVE THE ROOT DECIDES NOTHING — the four-file tree staged under tests/fixtures/…/ answers
#       exactly as the neutrally-staged copy does, under `.` and under the absolute spelling.
#   (5) THE QSNAP SCHEME BUMP (opt-in, RIPWIRE_PREFIX_BIN=<a pre-#228 build>) — the pre-fix binary writes its
#       HEAD Snapshot into a shared cache; the fixed binary must not serve it.
#   (6) A SELECTOR SPELLED FROM THE CWD — `<root as typed>/pkg/store.py:load` and the absolute `/…/pkg/store.py:load`
#       answer like the root-relative `pkg/store.py:load` under every spelling, on --edit-check, --callers, --at and
#       --affected (one shared matcher, graph.h filePathContainsRootRel). A1's first version matched root-relative
#       ONLY, so every such selector refused a file 0.6.1 found (#281's CI: xmlwellformed's --edit-check).
#
# Fixtures are STAGED under this gate's own mktemp dir with neutral names (a copy beside the sources would
# perturb the crawl, and an in-tree test/<x>fix location is itself a fixture component), git-committed with a
# private identity and no hooks; TMPDIR and XDG_CACHE_HOME are this gate's, so no cache outlives it.
#
# Usage:  test/rootspellingcheck.sh   |   RIPWIRE_BIN=asan/ripwire test/rootspellingcheck.sh
# Exit:   0 = clean · 1 = an arm failed · 2 = usage / missing prerequisite

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/rootspellfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
TMP="$( cd "$TMP" && pwd -P )"            # macOS /tmp is a symlink; stage under the physical spelling
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no test/rootspellfix — fixture missing"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }
echo "rootspellingcheck: BIN=$BIN  FIX=$FIX"

mkdir -p "$TMP/tmp" "$TMP/xdg" "$TMP/w" "$TMP/ln" "$TMP/out"
export TMPDIR="$TMP/tmp" XDG_CACHE_HOME="$TMP/xdg"
G=( -c user.name=fx -c user.email=fx@example.invalid -c core.hooksPath=/dev/null -c commit.gpgsign=false )
SPELLINGS="dot dotslash abs trail link dotdot"

# stage SRC DEST — copy a fixture, commit it, and give it a symlink twin and a sibling directory to climb from.
stage()
{
    local src="$1" dest="$2"
    mkdir -p "$( dirname "$dest" )" "$( dirname "$dest" )/_sib"
    cp -R "$src" "$dest"
    ( cd "$dest" && git init -q . && git add -A && git "${G[@]}" commit -qm fixture ) >/dev/null 2>&1
    ln -s "$dest" "$TMP/ln/$( basename "$dest" )" 2>/dev/null
}

# spell SPELLING DIR OUTBASE ARGS... — one run under one spelling of DIR's root, cwd chosen so the spelling names DIR.
spell()
{
    local sp="$1" d="$2" out="$3"; shift 3
    local name; name="$( basename "$d" )"
    case "$sp" in
        dot)      ( cd "$d" && "$BIN" .                  --no-cache "$@" ) ;;
        dotslash) ( cd "$d" && "$BIN" ./                 --no-cache "$@" ) ;;
        abs)      ( cd "$TMP" && "$BIN" "$d"             --no-cache "$@" ) ;;
        trail)    ( cd "$TMP" && "$BIN" "$d/"            --no-cache "$@" ) ;;
        link)     ( cd "$TMP" && "$BIN" "$TMP/ln/$name"  --no-cache "$@" ) ;;
        dotdot)   ( cd "$( dirname "$d" )/_sib" && "$BIN" "../$name" --no-cache "$@" ) ;;
    esac >"$out.xml" 2>"$out.err"
    echo "$?" >"$out.rc"
    # ONLY the printed root is normalised: the root= attribute, and est_tokens=, which prices those bytes.
    sed -E 's/ root="[^"]*"/ root="ROOT"/g; s/est_tokens="?[0-9]+"?/est_tokens=N/g' "$out.xml" >"$out.norm"
}

# invariant LABEL DIR VERB-ARGS... — every spelling's normalised stdout AND exit status equal the absolute run's.
invariant()
{
    local label="$1" d="$2"; shift 2
    local key; key="$( printf '%s' "$label" | tr -c 'A-Za-z0-9' '_' )"
    local sp diverged=""
    for sp in $SPELLINGS; do
        spell "$sp" "$d" "$TMP/out/$key.$sp" "$@"
    done
    if [ ! -s "$TMP/out/$key.abs.xml" ]; then
        no "$label: the absolute run printed nothing (rc=$( cat "$TMP/out/$key.abs.rc" )) — nothing to compare"
        return
    fi
    for sp in $SPELLINGS; do
        [ "$sp" = abs ] && continue
        if ! cmp -s "$TMP/out/$key.abs.norm" "$TMP/out/$key.$sp.norm" || ! cmp -s "$TMP/out/$key.abs.rc" "$TMP/out/$key.$sp.rc"; then
            diverged="$diverged $sp"
        fi
    done
    if [ -z "$diverged" ]; then
        ok "$label: identical under . ./ \$PWD \$PWD/ symlink ../name"
    else
        no "$label: differs from the absolute spelling under:$diverged"
        local first; first="$( printf '%s' "$diverged" | awk '{print $1}' )"
        diff <( tr '>' '\n' <"$TMP/out/$key.abs.norm" | grep -v '^<!--' ) <( tr '>' '\n' <"$TMP/out/$key.$first.norm" | grep -v '^<!--' ) | head -6 | cut -c1-220
    fi
}

# every_spelling LABEL KEY PATTERN — PATTERN (fixed string) appears in the stdout of EVERY spelling of that run.
every_spelling()
{
    local label="$1" key="$2" pat="$3" sp missing=""
    key="$( printf '%s' "$key" | tr -c 'A-Za-z0-9' '_' )"
    for sp in $SPELLINGS; do
        grep -qF -- "$pat" "$TMP/out/$key.$sp.xml" 2>/dev/null || missing="$missing $sp"
    done
    if [ -z "$missing" ]; then ok "$label"; else no "$label — missing under:$missing"; fi
}

# refuses_uniformly LABEL DIR VERB-ARGS... — every spelling's exit code is 1 (a uniform refusal). Some
# CORRECT answers are "refuses, no document at all" (stdout empty, the diagnosis on stderr), which
# invariant()'s "diff the abs run's stdout" guard has nothing to compare — this asserts the exit code
# vector instead.
refuses_uniformly()
{
    local label="$1" d="$2"; shift 2
    local key; key="$( printf '%s' "$label" | tr -c 'A-Za-z0-9' '_' )"
    local sp rcs="" want=""
    for sp in $SPELLINGS; do
        spell "$sp" "$d" "$TMP/out/$key.$sp" "$@"
        rcs="$rcs$( cat "$TMP/out/$key.$sp.rc" )"
        want="${want}1"
    done
    [ "$rcs" = "$want" ] && ok "$label: refuses (rc=1) identically under every spelling" \
                         || no "$label: exit codes per spelling ($SPELLINGS) = $rcs, want $want"
}

# ── (1)+(2) the four-file Python tree (the #228 repro) ───────────────────────────────────────────────
PY="$TMP/w/pyfour"
stage "$FIX" "$PY"
invariant "pyfour map"                "$PY"
invariant "pyfour --deps"             "$PY" --deps
invariant "pyfour --callers=store"    "$PY" --callers=pkg/store.py:load
invariant "pyfour --callers=local"    "$PY" --callers=app/local.py:load
invariant "pyfour --impact=store"     "$PY" --impact=pkg/store.py:load
invariant "pyfour --affected"         "$PY" --affected=pkg/store.py
invariant "pyfour --dead-code"        "$PY" --dead-code
invariant "pyfour --for"              "$PY" --for=handler              # route anchors printed /.../views.py under an absolute root
invariant "pyfour --pack-task"        "$PY" --pack-task=handler        # its callee rows kept the whole path under "$PWD/"
invariant "pyfour --quality-delta"    "$PY" --quality-delta

every_spelling 'control: app/views.py resolves `from pkg.store import load` (pkg/store.py afferent="1")' \
    "pyfour --deps" '<f p="pkg/store.py" afferent="1"/>'
every_spelling 'control: handler is the one caller of pkg/store.py:load (the import bound it)' \
    "pyfour --callers=store" '<s t="fn" n="handler" p="app/views.py:4"/>'
every_spelling 'control: the same-directory app/local.py:load has count="0" callers (the name ladder did not bind it)' \
    "pyfour --callers=local" 'count="0"'
every_spelling 'control: --impact names app/views.py as the importer of pkg/store.py (importers="1")' \
    "pyfour --impact=store" '<f via="import" p="app/views.py" lazy="0"/>'
every_spelling 'control: the resolver gauge reads graph_ambiguous="0"' \
    "pyfour --callers=store" 'graph_ambiguous="0"'
every_spelling 'control: --quality-delta on the unchanged tree reports regressions="0" on its root element' \
    "pyfour --quality-delta" 'regressions="0"'
qrc=""
for sp in $SPELLINGS; do qrc="$qrc$( cat "$TMP/out/pyfour___quality_delta.$sp.rc" )"; done
[ "$qrc" = "000000" ] && ok "control: --quality-delta exits 0 on the unchanged tree under all six spellings" \
                      || no "control: --quality-delta exit codes per spelling ($SPELLINGS) = $qrc, want 000000"

# ── (6) a selector spelled from the cwd (#281) ───────────────────────────────────────────────────────────────
# selector_prefix SPELLING DIR FORM — what a user in that spelling's cwd types before a root-relative path:
#   FORM=typed  the root exactly as that spelling typed it, then '/' (`./`, "$PWD/", the symlink, `../name/`);
#   FORM=abs    the absolute root (physical — $TMP is staged under `pwd -P`, so the symlink spelling reaches it
#               through the root's realpath, not through the link text);
#   FORM=cwdrel the root's path RELATIVE TO THAT SPELLING'S CWD, whatever the root was typed as — xmlwellformed's own
#               shape: `ripwire "$ROOT/test/fixture" --edit-check=test/fixture/geometry.cpp:distance` from $ROOT.
selector_prefix()
{
    local sp="$1" d="$2" form="$3" name; name="$( basename "$d" )"
    if [ "$form" = abs ]; then printf '%s/' "$d"; return; fi
    if [ "$form" = cwdrel ]; then
        case "$sp" in
            dot|dotslash)    printf './' ;;
            abs|trail|link)  printf '%s/' "${d#"$TMP"/}" ;;   # these spellings run from $TMP
            dotdot)          printf '../%s/' "$name" ;;
        esac
        return
    fi
    case "$sp" in
        dot|dotslash) printf './' ;;
        abs|trail)    printf '%s/' "$d" ;;
        link)         printf '%s/' "$TMP/ln/$name" ;;
        dotdot)       printf '../%s/' "$name" ;;
    esac
}

# cwd_selector LABEL DIR FORM FLAG REL PATTERN... — under every spelling, FLAG=<prefix><REL> exits 0 and its stdout
# holds every PATTERN (fixed strings). The patterns are the root-relative selector's own answer rows, so a refusal,
# an empty document, or a different file cannot pass; the selector's echo (of=, changed=) is never asserted.
cwd_selector()
{
    local label="$1" d="$2" form="$3" flag="$4" rel="$5"; shift 5
    local key sp pat pre rc wrong=""
    key="$( printf '%s' "$label" | tr -c 'A-Za-z0-9' '_' )"
    for sp in $SPELLINGS; do
        pre="$( selector_prefix "$sp" "$d" "$form" )"
        spell "$sp" "$d" "$TMP/out/$key.$sp" "$flag=$pre$rel"
        rc="$( cat "$TMP/out/$key.$sp.rc" )"
        if [ "$rc" != 0 ]; then wrong="$wrong $sp(rc=$rc)"; continue; fi
        for pat in "$@"; do
            grep -qF -- "$pat" "$TMP/out/$key.$sp.xml" || { wrong="$wrong $sp(missing $pat)"; break; }
        done
    done
    [ -z "$wrong" ] && ok "$label: answers like the root-relative selector under . ./ \$PWD \$PWD/ symlink ../name" \
                    || no "$label — wrong under:$wrong"
}

for form in typed abs cwdrel; do
    # lane lean-trio (idea #11): an unchanged, unflagged contract is its verdict line (no <c> rows), so the resolved
    # definition and its one caller are read off the root: p= is the definition the selector named, callers="1" its caller.
    cwd_selector "(6) --edit-check=<$form root>/pkg/store.py:load" "$PY" "$form" --edit-check pkg/store.py:load 'sym="load"' 'p="pkg/store.py:1"' 'callers="1"'
    cwd_selector "(6) --callers=<$form root>/pkg/store.py:load"    "$PY" "$form" --callers    pkg/store.py:load 'count="1"' '<s t="fn" n="handler" p="app/views.py:4"/>'
    cwd_selector "(6) --at=<$form root>/pkg/store.py:2"            "$PY" "$form" --at         pkg/store.py:2    'sym="load"'
    cwd_selector "(6) --affected=<$form root>/pkg/store.py"        "$PY" "$form" --affected   pkg/store.py      'seeds="1"' 'reached="1"'
done
# the control: a cwd-spelled path that names no indexed file still refuses under every spelling, in both forms (the
# second reading adds a spelling of the same file, it does not loosen the match)
for form in typed abs cwdrel; do
    nrc=""
    for sp in $SPELLINGS; do
        spell "$sp" "$PY" "$TMP/out/nosuch_$form.$sp" "--callers=$( selector_prefix "$sp" "$PY" "$form" )pkg/nosuch.py:load"
        nrc="$nrc$( cat "$TMP/out/nosuch_$form.$sp.rc" )"
    done
    [ "$nrc" = "111111" ] && ok "(6) control: --callers=<$form root>/pkg/nosuch.py:load refuses (rc=1) under every spelling" \
                          || no "(6) control: --callers=<$form root>/pkg/nosuch.py:load exit codes per spelling ($SPELLINGS) = $nrc, want 111111"
done

# ── (1)+(2) A1 residual (found-items 2026-09-17, reports/pr-253.md R1/R2): SELECTOR PATH PATTERNS and
# --exclude= must match the ROOT-RELATIVE path, not the typed one. testmap.h::resolveAffectedSeeds/
# resolveExerciseSeeds and ingest_crawl.h's --exclude matcher used to filePathContains() the RAW stored
# path, so a marker that exists only in the CHECKOUT location above the crawl root — never inside any
# file's own tree-relative path — decided the answer: `--affected=<marker>` matched every file (seeds
# nonzero) and `--exclude=<marker>` dropped every file, under an absolute or trailing-slash root spelling,
# while `.`/`./`/symlink/`..`-spelled runs correctly saw no match at all.
MARK="$TMP/w/zzzmarker9/pyfour"
stage "$FIX" "$MARK"
refuses_uniformly "A1 --affected=<above-root marker>" "$MARK" --affected=zzzmarker9
invariant "A1 --exclude=<above-root marker> excludes nothing under every spelling" "$MARK" --exclude=zzzmarker9

# review round (2026-09-17): --affected/--exclude were not the only raw filePathContains consumers.
# graph.h's resolveAtSeed (--at=FILE:LINE) and resolveAllByNameQualified (the file:name qualifier every
# --callers/--impact/--uses/--edit-check/--around/--lego selector shares), selectorrefuse.h's
# indexHasFileMatching (the refusal diagnosis those same verbs print — reused by name below, since a
# wrong-file refusal is silent success from the caller's POV), and verbs_navigate.h's --verify FILE
# argument all matched the RAW stored path. All four now route through graph.h's shared
# filePathContainsRootRel; mcpedit.h's editHintMatches (the MCP write verbs' `file` disambiguation hint)
# is the fifth site and is MCP-only — covered in test/mcpeditcheck.sh instead, where the MCP call harness
# already lives (arm (14), below its own root-spelling fixture).
refuses_uniformly "A1 --verify contains(<above-root marker>) FILE half" "$MARK" --verify='contains(zzzmarker9,"x")'
# --at needs a CONTENT check, not just an exit-code one: a marker that matches several files under an
# absolute spelling refuses as FileAmbiguous ("'zzzmarker9' matches N indexed files") instead of
# FileUnmatched ("no indexed file matches 'zzzmarker9'") — a DIFFERENT, wrong reason at the SAME rc=1, so
# refuses_uniformly's exit-code vector cannot see it (confirmed: this arm passed on the pre-fix binary
# under a bare rc check and only reds once the reason is compared).
atReason=""
for sp in $SPELLINGS; do
    spell "$sp" "$MARK" "$TMP/out/a1at.$sp" --at=zzzmarker9:1
    grep -qF "no indexed file matches 'zzzmarker9'" "$TMP/out/a1at.$sp.err" || atReason="$atReason $sp"
done
[ -z "$atReason" ] && ok "A1 --at=<above-root marker>:1 (resolveAtSeed): every spelling refuses for the SAME reason (no indexed file matches)" \
                    || no "A1 --at=<above-root marker>:1: refusal reason differs under:$atReason (a marker matching several files there reads FileAmbiguous, not FileUnmatched)"
# --callers=<marker>:load exercises BOTH resolveAllByNameQualified (graph.h) and the refusal diagnosis
# indexHasFileMatching (selectorrefuse.h) prints when the file half matches nothing — one arm, two sites.
refuses_uniformly "A1 --callers=<above-root marker>:load (resolveAllByNameQualified + refusal diagnosis)" "$MARK" --callers=zzzmarker9:load

# ── (3) sensitivity: an edit that moves the import's target MUST gate, under `.` and absolute alike ─────
printf 'from app.local import load\n\n\ndef handler():\n    return load(1)\n' >"$PY/app/views.py"
for sp in dot abs; do
    spell "$sp" "$PY" "$TMP/out/sens.$sp" --quality-delta
    src="$( cat "$TMP/out/sens.$sp.rc" )"
    if [ "$src" = 2 ] && grep -q 'kind="dead-code" sym="load" p="pkg/store.py' "$TMP/out/sens.$sp.xml"; then
        ok "sensitivity ($sp): re-pointing the import at app.local gates (exit 2) with pkg/store.py load newly dead"
    else
        no "sensitivity ($sp): the re-pointed import did not gate (rc=$src): $( grep -oE '<r [^>]*>' "$TMP/out/sens.$sp.xml" | head -2 | tr '\n' ' ' )"
    fi
done
( cd "$PY" && git checkout -q -- app/views.py )

# ── (1)+(2) a C++ header selector: the declaration file answers through an include PROOF ──────────────
# `--callers=include/Store.h:putObject` widens to the defining .cpp only when that .cpp's own #include resolves to
# the header. The proof builds its own path index (graph.h markCandidateFilesIncludingDecl), a second place the
# includer spelling and the index keys must agree — an earlier cut of this fix keyed the index root-relative and
# resolved the includer as typed, and the header answered count="0" under every spelling but `.`.
CH="$TMP/w/cpphdr"
mkdir -p "$TMP/cpphdr.src/include" "$TMP/cpphdr.src/src" "$TMP/cpphdr.src/app"
printf '#pragma once\nclass Store\n{\npublic:\n    int putObject( const char* key );\n};\n' >"$TMP/cpphdr.src/include/Store.h"
printf '#include "../include/Store.h"\nint Store::putObject( const char* key )\n{\n    return key ? 1 : 0;\n}\n' >"$TMP/cpphdr.src/src/Store.cpp"
printf '#include "../include/Store.h"\nint driveTheStore( Store& s )\n{\n    return s.putObject( "k" );\n}\n' >"$TMP/cpphdr.src/app/Caller.cpp"
stage "$TMP/cpphdr.src" "$CH"
invariant "cpphdr --callers=include/Store.h:putObject" "$CH" --callers=include/Store.h:putObject
every_spelling 'control: the header selector reaches the caller through the include proof (driveTheStore)' \
    "cpphdr --callers=include/Store.h:putObject" 'n="driveTheStore" p="app/Caller.cpp:2"'

# ── (1)+(2) every language with a path-resolved import tier ─────────────────────────────────────────
# fixture | symbol | a file whose change reaches it | an --deps row that proves an edge resolved
while IFS='|' read -r fx sym file edge; do
    [ -n "$fx" ] || continue
    [ -d "$ROOT/test/$fx" ] || { no "language fixture test/$fx is missing"; continue; }
    D="$TMP/w/$fx"
    stage "$ROOT/test/$fx" "$D"
    invariant "$fx map"               "$D"
    invariant "$fx --deps"            "$D" --deps
    invariant "$fx --callers=$sym"    "$D" "--callers=$sym"
    invariant "$fx --impact=$sym"     "$D" "--impact=$sym"
    invariant "$fx --affected"        "$D" "--affected=$file"
    invariant "$fx --quality-delta"   "$D" --quality-delta
    every_spelling "control: $fx resolves an edge under every spelling ($edge)" "$fx --deps" "$edge"
done <<'EOF'
pyimportprecisefix|gadget|pkg/mod.py|<f p="pkg/mod.py" afferent="1"
tsimportprecisefix|widget|a/b.ts|<f p="a/b.ts" afferent="1"
rustimportprecisefix|helper|src/geo/mod.rs|<f p="src/geo/mod.rs" afferent="2"
bashsourcefix|helper_fn|lib/helper.sh|<f p="lib/helper.sh" afferent="3"
rubyrequirefix|helper_go|lib/helper.rb|<f p="lib/helper.rb" afferent="3"
luarequirefix|go|a/b.lua|<f p="a/b.lua" afferent="3"
includeprecisefix|right_fn|diamond/right.h|<f p="diamond/shared.h" afferent="2"
eliximportfix|run|lib/my_app/foo.ex|<f p="lib/my_app/foo.ex" afferent="3"
EOF

# ── (4) a directory ABOVE the root decides nothing ──────────────────────────────────────────────────
# The same tree staged under tests/fixtures/bench/: every file there sits below a `tests` and a `fixtures`
# component, but those components are the CHECKOUT's location, not the tree's content.
HOST="$TMP/tests/fixtures/bench/pyfour"
stage "$FIX" "$HOST"
for verb in map --affected=pkg/store.py --callers=pkg/store.py:load; do
    for sp in dot abs; do
        spell "$sp" "$PY"   "$TMP/out/place.neutral.$sp" ${verb#map}
        spell "$sp" "$HOST" "$TMP/out/place.hostile.$sp" ${verb#map}
        if [ -s "$TMP/out/place.neutral.$sp.xml" ] && cmp -s "$TMP/out/place.neutral.$sp.norm" "$TMP/out/place.hostile.$sp.norm"; then
            ok "placement ($sp, $verb): staged under tests/fixtures/bench/ the tree answers exactly as it does staged neutrally"
        else
            no "placement ($sp, $verb): a directory above the root changed the answer (or the neutral run printed nothing)"
            diff <( tr '>' '\n' <"$TMP/out/place.neutral.$sp.norm" | grep -v '^<!--' ) <( tr '>' '\n' <"$TMP/out/place.hostile.$sp.norm" | grep -v '^<!--' ) | head -4 | cut -c1-220
        fi
    done
done
spell abs "$HOST" "$TMP/out/place.layer"
if ! grep -q '<f p="pkg/store.py"' "$TMP/out/place.layer.xml"; then
    no 'placement: the hostile-staged map printed no pkg/store.py row — nothing was compared'
elif grep -q 'layer="test"' "$TMP/out/place.layer.xml"; then
    no 'placement: the hostile-staged map tags a file layer="test" from a directory above the root'
else
    ok 'placement: the hostile-staged map carries no layer="test" (and is not empty)'
fi
# the dead-code kind's fixture exemption must not swallow a real finding just because of where the checkout lives
printf 'from app.local import load\n\n\ndef handler():\n    return load(1)\n' >"$HOST/app/views.py"
for sp in dot abs; do
    spell "$sp" "$HOST" "$TMP/out/place.sens.$sp" --quality-delta
    prc="$( cat "$TMP/out/place.sens.$sp.rc" )"
    if [ "$prc" = 2 ] && grep -q 'kind="dead-code" sym="load" p="pkg/store.py' "$TMP/out/place.sens.$sp.xml"; then
        ok "placement ($sp): under tests/fixtures/ the re-pointed import still gates (exit 2) — no fixture exemption from above the root"
    else
        no "placement ($sp): under tests/fixtures/ the re-pointed import did not gate (rc=$prc) — a directory above the root exempted it"
    fi
done

# ── (5) the qsnap scheme bump: a pre-#228 HEAD Snapshot is never served ─────────────────────────────
if [ -n "${RIPWIRE_PREFIX_BIN:-}" ] && [ -x "${RIPWIRE_PREFIX_BIN:-}" ]; then
    # Both binaries get ONE private cache ladder (TMPDIR wins over XDG_CACHE_HOME in cacheDirLadder), so the
    # pre-fix HEAD Snapshot is sitting exactly where the fixed binary looks — unless the scheme bump renamed it.
    UP="$TMP/w/upgrade"; UPC="$TMP/upcache"
    stage "$FIX" "$UP"
    mkdir -p "$UPC"
    ( cd "$TMP" && env TMPDIR="$UPC" XDG_CACHE_HOME="$UPC" "$RIPWIRE_PREFIX_BIN" "$UP" --quality-delta >/dev/null 2>&1 )
    nblob="$( find "$UPC" -name 'ripwire-qsnap-*.bin' 2>/dev/null | wc -l | tr -d ' ' )"
    [ "$nblob" -ge 1 ] && ok "upgrade: the pre-#228 binary wrote $nblob qsnap blob(s) into the shared cache ladder" \
                       || no "upgrade: the pre-#228 binary wrote no qsnap blob under $UPC — the arm has nothing to refuse"
    ( cd "$UP" && env TMPDIR="$UPC" XDG_CACHE_HOME="$UPC" "$BIN" . --quality-delta >"$TMP/out/up.xml" 2>/dev/null ); urc=$?
    if [ "$urc" = 0 ] && grep -q 'regressions="0"' "$TMP/out/up.xml"; then
        ok "upgrade: with that ladder warm, the fixed binary under \`.\` exits 0 with regressions=\"0\" (the pre-#228 Snapshot was not served)"
    else
        no "upgrade: the fixed binary served the pre-#228 HEAD Snapshot (rc=$urc): $( grep -oE '<r [^>]*>' "$TMP/out/up.xml" | head -1 )"
    fi
else
    printf '  SKIP  (5) upgrade arm: set RIPWIRE_PREFIX_BIN to a build from before #228 to run it\n'
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
