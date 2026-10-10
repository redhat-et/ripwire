#!/usr/bin/env bash
# importcapcheck.sh — the gate for the shared import-capture vocabulary (issue #358), C-family and Go slices.
#
# WHAT THIS PINS. `#include` / `#import` for c, cpp, objc (and the .h/.hpp/.cu/.cuh/.metal extensions
# that ride those grammars) no longer come from a per-language extractor in src/ingest_relations.h. They
# come from ONE capture name — `@import.path`, declared in queries/{c,cpp,objc}/tags.scm — normalised by
# the ONE DepDialect::CFamily specifier normaliser in src/ingest_importcap.h. This gate pins that the
# EMITTED dependency edges are exactly the ones the extractor emitted, for every shape the round touches:
#
#   1  the vocabulary is COMPILED IN — the capture name is in the binary's EMBEDDED tags.scm, which a
#                                    --match probe cannot show (it feeds its own query to the astQuery
#                                    engine, so it matched even on a pre-change binary); and the two
#                                    extractor functions this replaces name nothing in src/ any more
#   2  quote vs angle              — the isAngle bit, from the delimiter. Resolution leaves <x.h> alone.
#   3  #import under BOTH spellings — the C and C++ grammars have no #import rule (it parses as a generic
#                                    preproc_call, argument-gated in C++); the ObjC grammar HAS one.
#   4  the C++ gate on directive TEXT — `#pragma once` / `#error` / `#warning` are captured by the same
#                                    pattern and MUST NOT become edges. This is the arm a query predicate
#                                    would have written and the tags pass cannot evaluate.
#   5  a macro include              — `#include HEADER` carries no delimiter; the target stays the bare
#                                    macro name (a disclosed floor, unchanged by the round).
#   6  an include inside a guard    — `#if`/`#else`/`#elif`/`#ifdef`, the union-over-arms posture.
#   7  a DEAD arm                   — `#if 0` / `#elif 0` includes must be DROPPED. This is the arm the
#                                    round could most easily have broken: captureTagsFacts never ran
#                                    dropPreprocDead over `includes` before, and a query cannot know an
#                                    arm is dead. Measured without the filter: dep_dead_if.h and
#                                    dep_elif.h both come back as edges.
#   8  the use-site half            — every Include has its ABS-3 import-role use-site ref, so --uses
#                                    still reports the include site of a header by its importable name.
#   9  cache round-trip on --deps   — cold == warm byte-identically, and warm == --no-cache, on the view
#                                    that actually reads Include records (the map view does not carry them)
#  10  determinism                  — two independent cold runs byte-identical
#  11  the cuda/metal grammars      — `.cu`/`.cuh` ride the vendored tree-sitter-cuda grammar on
#                                    queries/cpp/tags.scm; a pattern that fails to COMPILE makes every
#                                    file of that language disclose extract-partial instead of erroring
#  12  THE REACH GATE               — an unanchored query must NOT widen the graph: extern "C" { #include },
#                                    namespace ns { #include }, an #include in a function body, and an
#                                    include under an ERROR node all stay OUT, exactly as the walk left them
#  13  no kParserVer bump is owed    — a cache written by a PRE-CHANGE binary is accepted and reads
#                                    identically, which is the evidence the records did not change
#                                    (RIPWIRE_BASE_BIN, the house name; SKIPs when unset, as on CI)
#
#
# THE GO SLICE (arms 14-19, below the C-family arms). Go's `import_declaration` — single and grouped, aliased,
# dot, blank, cgo `import "C"` — is captured as `@import.path` in queries/go/tags.scm and read by the ONE
# DepDialect::Go normaliser in src/ingest_importcap.h; the walk in captureIncludes no longer runs for Go.
#  14  the Go capture is COMPILED IN — `(import_declaration) @import.path` is in the binary's embedded tags.scm
#  15  every Go form, exact rows — single/aliased/dot/blank/group/cgo/tab/semicolon/raw-string/UTF-8 cut/error
#                                    recovery, pinned as the byte-for-byte rows the extractor emitted
#  16  no widening                  — an import_declaration the grammar never makes a child of the file root
#                                    (inside a function body) stays out, exactly as the walk left it
#  17  resolution through imports   — a go.mod `replace` still maps an import onto a sibling root's package
#                                    (single, aliased and grouped), and a bogus replace target removes the edge
#  18  the use-site half            — `--uses=<last path element>` reports role="import" for a Go import
#  19  Go cache + determinism       — warm == cold == --no-cache on --deps over the Go fixture
#
# Usage:  test/importcapcheck.sh
#         RIPWIRE_BIN=asan/ripwire test/importcapcheck.sh
# Exits non-zero on any failure. Does NOT edit test/regression.sh or test/golden.xml.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
skip(){ printf '  SKIP  %s\n' "$*"; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "importcapcheck: BIN=$BIN  TMP=$TMP"

WORK="$TMP/proj"
mkdir -p "$WORK"

# The fixture: one C++ file carrying every C-family spelling, one plain-C file, one ObjC file. The ten
# headers are one-line stubs — the round is about the EDGE, and an edge resolves to a real file, so every
# spelled target must exist on disk or the row would vanish for the wrong reason.
for h in dep_quoted dep_angle dep_imported dep_imported_angle dep_if dep_else dep_ifdef dep_elif \
         dep_dead_if dep_dead_ifdef; do
    printf 'int %s_helper( void );\n' "$h" > "$WORK/$h.h"
done
printf 'int HEADER_MACRO_PATH_helper( void );\n' > "$WORK/HEADER_MACRO_PATH.h"

cat > "$WORK/main.cpp" <<'CPP'
#include "dep_quoted.h"
#include <dep_angle.h>
#import "dep_imported.h"
#import <dep_imported_angle.h>
#include HEADER_MACRO_PATH
#pragma once
#error "not an include at all"
#define GUARD 1
#if defined(GUARD)
#include "dep_if.h"
#else
#include "dep_else.h"
#endif
#ifdef GUARD
#include "dep_ifdef.h"
#elif 0
#include "dep_elif.h"
#endif
#if 0
#include "dep_dead_if.h"
#endif
#ifdef DEAD
#include "dep_dead_ifdef.h"
#endif
int use( void ) { return dep_quoted_helper(); }
CPP

cat > "$WORK/main.c" <<'C'
#include "dep_quoted.h"
#include <dep_angle.h>
#import "dep_imported.h"
int c_use( void ){ return dep_quoted_helper(); }
C

cat > "$WORK/thing.m" <<'M'
#import "dep_imported.h"
#import <dep_imported_angle.h>
@interface Thing : NSObject
@end
M

deps() { "$BIN" "$1" --deps 2>/dev/null; }

# ── the captured edge set ───────────────────────────────────────────────────────────────────────────
OUT="$TMP/deps.xml"
deps "$WORK" > "$OUT"

# arm 1 + 3 + 5 + 6 + 7: the exact fourteen rows, in the exact spelling. (Counted, not estimated: the
# list below has 14 entries — 9 from main.cpp, 3 from main.c, 2 from thing.m — and every label that
# quotes a number quotes THIS one. CodeRabbit caught 13 and 15 here; the assertion itself was always
# right because it compares against the list, never against the number in the message.)
want='dep_quoted.h
dep_angle.h
dep_imported.h
dep_imported_angle.h
HEADER_MACRO_PATH
dep_if.h
dep_else.h
dep_ifdef.h
dep_dead_ifdef.h
dep_quoted.h
dep_angle.h
dep_imported.h
dep_imported.h
dep_imported_angle.h'
got=$(grep -o '<inc t="[^"]*"' "$OUT" | sed 's/<inc t="//; s/"$//')
if [ "$got" = "$want" ]; then
    ok "14 Include rows, exact set and order (three #import spellings, macro include, guarded arms)"
else
    no "Include rows differ from the expected 14"
    printf '    expected:\n%s\n' "$(printf '%s\n' "$want" | sed 's/^/      /')"
    printf '    got:\n%s\n'      "$(printf '%s\n' "$got"   | sed 's/^/      /')"
fi

# arm 7 on its own, named: the dead arms must be ABSENT, not merely balanced by the total above.
for dead in dep_dead_if.h dep_elif.h; do
    if grep -q "<inc t=\"$dead\"" "$OUT"; then
        no "dead arm leaked an edge: $dead (dropPreprocDead no longer covers the includes window)"
    else
        ok "dead arm dropped: $dead"
    fi
done

# arm 4 on its own, named: the non-import preproc_calls. These are in the SAME query pattern as #import,
# and the fixture deliberately carries a `#pragma once` and an `#error` so the arm is not vacuous.
grep -q 't="once"' "$OUT" && no "#pragma once became a dependency" || ok "#pragma once is not a dependency"
grep -q 't="not an include at all"' "$OUT" && no "#error became a dependency" || ok "#error is not a dependency"

# ── arm 11: the extension families the C-family grammar table covers but a normal corpus does not ──────
# `.cu`/`.cuh` ride the VENDORED tree-sitter-cuda grammar on queries/cpp/tags.scm, and `.metal` rides cpp.
# A query that fails to COMPILE against a grammar does not error — every file of that language discloses
# extract-partial instead — so this arm is not redundant with the three above: it is the only place the
# cuda grammar's spelling of these patterns is exercised at all.
CT="$TMP/cuda"; mkdir -p "$CT"
printf 'int cu_helper();\n'   > "$CT/cu_helper.cuh"
printf 'int metal_helper();\n' > "$CT/metal_helper.h"
cat > "$CT/k.cu" <<'CU'
#include "cu_helper.cuh"
#include <vector>
#import "cu_helper.cuh"
#if 1
#include "cu_helper.cuh"
#endif
__global__ void k() {}
CU
printf '#include "metal_helper.h"\n#import "metal_helper.h"\n' > "$CT/s.metal"
"$BIN" "$CT" --deps --no-cache > "$TMP/cu.xml" 2> "$TMP/cu.err"
CU_EDGES=$(grep -o '<inc ' "$TMP/cu.xml" | wc -l)
if [ "$CU_EDGES" -eq 6 ] && ! grep -q 'extract-partial' "$TMP/cu.err"; then
    ok "cuda + metal: 6 edges, no extract-partial (the patterns compile against tree-sitter-cuda too)"
else
    no "cuda + metal: got ${CU_EDGES:-0} edges (want 6), stderr=[$(head -c 160 "$TMP/cu.err")]"
fi

# ── arm 2: the quote-vs-angle discriminator, asserted where it is actually OBSERVABLE ─────────────────
# `Include::isAngle` is invisible in the row list above. Both spellings normalise to the same bare path
# and both appear as an `<inc t=...>` directive row, so counting spellings proves nothing about the bit —
# a label that claimed otherwise would be a gate arm that cannot fail, which this repo's own
# .coderabbit.yaml path_instructions name as a defect. The bit IS observable one level up, in whether the
# target RESOLVES: a quoted include is resolved relative to the includer and the header earns its own
# `<f>` row, while an angle include is left unresolved (no build system to search) and earns none.
# Measured on exactly this fixture: quoted.h -> afferent="1"; angled.h -> no row at all.
AT="$TMP/angle"; mkdir -p "$AT"
printf 'int quoted_helper( void );\n' > "$AT/quoted.h"
printf 'int angled_helper( void );\n'  > "$AT/angled.h"
printf '#include "quoted.h"\n#include <angled.h>\nint use( void ){ return quoted_helper(); }\n' > "$AT/a.cpp"
"$BIN" "$AT" --deps --no-cache > "$TMP/angle.xml" 2>/dev/null
A_CAPTURED=$(grep -o '<inc t="\(quoted\|angled\)\.h"' "$TMP/angle.xml" | wc -l)
A_QUOTED=$(grep -c '<f p="quoted\.h"' "$TMP/angle.xml" || true)
A_ANGLED=$(grep -c '<f p="angled\.h"' "$TMP/angle.xml" || true)
if [ "$A_CAPTURED" -eq 2 ] && [ "$A_QUOTED" -ge 1 ] && [ "$A_ANGLED" -eq 0 ]; then
    ok "quote-vs-angle: both spellings captured, and only the quoted one resolves (2 directives, 1 resolved, 0 for angle)"
else
    no "quote-vs-angle: captured=$A_CAPTURED quoted_rows=$A_QUOTED angled_rows=$A_ANGLED (want 2 / >=1 / 0)"
fi
# parses as a generic preproc_call and is gated on the directive TEXT in C++ — while the ObjC grammar has
# an #import rule and routes it through the preproc_include pattern instead. Three rows, three routes.
# The quoted form with its closing delimiter, so `dep_imported_angle.h` cannot ride in on the prefix.
if [ "$(grep -o 't="dep_imported\.h"' "$OUT" | wc -l)" -eq 3 ]; then
    ok "#import captured under all three grammars (c/cpp preproc_call + text gate, objc preproc_include)"
else
    no "#import rows missing for one of the three grammars (got $(grep -o 't="dep_imported\.h"' "$OUT" | wc -l), want 3)"
fi

# ── arm 1: the vocabulary is COMPILED IN, and the extractors it replaces are GONE ─────────────────────
# The earlier version of this arm ran `--match=(preproc_include path: (_) @import.path)` on the command
# line, which was VACUOUS: --match feeds the query to the astQuery engine, so it matched on ANY binary
# including a pre-change one, and the whole gate passed 15/15 against main. It proved the grammar parses,
# not that the tags.scm carries the capture. The capture lives in the tags.scm EMBEDDED IN THE BINARY, so
# that is where it is looked for: the literal `import.path` is in the emitted image on this branch and
# absent from a pre-change one (measured: 5 hits vs 0), which is a red-on-main reason that means
# something. The --match probe is kept as a second, weaker statement about the grammar, not the gate.
if grep -qa 'import\.path' "$BIN"; then
    ok "@import.path is present in the binary's embedded tags.scm (absent from a pre-change build)"
else
    no "@import.path is nowhere in this binary — the capture is not compiled in"
fi
MHITS=$("$BIN" "$WORK" --no-cache '--match=(preproc_include path: (_) @import.path)' 2>/dev/null \
        | grep -o 'hits="[0-9]*"' | head -1 | grep -o '[0-9]*')
if [ -n "$MHITS" ] && [ "$MHITS" -ge 3 ]; then
    ok "the @import.path pattern matches $MHITS sites on a real parse (grammar shape, not the wiring)"
else
    no "@import.path matched ${MHITS:-0} sites; expected >= 3"
fi
for gone in preprocIncludeTarget preprocImportTarget; do
    if grep -rq "$gone" "$ROOT/src"; then
        no "extractor $gone still exists in src/ — it should have been removed with this language"
    else
        ok "extractor $gone removed from src/"
    fi
done

# ── arm 8: the use-site half ─────────────────────────────────────────────────────────────────────────
# importName() strips the extension and the directory, so the selector is the HEADER'S importable name
# (`dep_quoted`), not the symbol it declares — the same selector `--uses=geometry` uses for geometry.h.
USES="$("$BIN" "$WORK" --uses=dep_quoted --no-cache 2>/dev/null)"
if printf '%s' "$USES" | grep -q 'role="import"'; then
    ok "--uses reports the include site with role=\"import\" (the ABS-3 half survived the move)"
else
    no "--uses lost the import-role use-site ref for an included header"
fi

# ── arm 12: THE REACH GATE — an unanchored query must not widen the C-family graph ─────────────────────
# This is the round's load-bearing negative. `(preproc_include path: (_) @import.path)` is unanchored, so
# it matches at ANY depth, while the walk this replaces entered only `isImportContainer` nodes and started
# from root's direct children. Left unchecked the round WIDENED the graph by 10 edges on the maintainer's
# probe tree (main 17, this 27): `extern "C" { #include }` in .cpp/.mm/.cu, `namespace ns { #include }`,
# an `#include` inside a function body (the X-macro `.def` pattern) in .c/.cpp/.metal/.cu, and an include
# under an ERROR node in a header whose guard arm failed to parse.
#
# All of those are real dependencies, so capturing them is arguably a FIX — which is exactly why it must
# not ride along here: #358's rule is that each slice is byte-identical, and the widening is its own PR.
# Each shape below is asserted to produce NO edge; only the file-scope include survives.
# The fixture carries NINE includes. Main captures THREE of them — the two file-scope `fn_body.h` and the
# `d.inc` under `#ifdef GUARD`, because a preproc conditional IS a container the walk entered. Main's set
# is the specification: #358 requires this slice byte-identical, so the arm asserts main's exact set rather
# than a count I reasoned out. The six main does NOT capture, and neither does this:
#   extern "C" { #include "n.h" }   x3  (.cpp / .mm / .cu) — the standard C-header idiom
#   namespace ns { #include "d.inc" }    — a wrapper the walk never entered
#   an #include inside a function body   x2  (the X-macro `.def` pattern)
WR="$TMP/reach"; mkdir -p "$WR"
for h in fn_body macro_hdr; do printf 'int %s_helper( void );\n' "$h" > "$WR/$h.h"; done
printf 'extern "C" {\n#include "n.h"\n}\n'                                        > "$WR/extc.cpp"
printf 'extern "C" {\n#import "n.h"\n}\n'                                        > "$WR/extc.mm"
printf 'extern "C" {\n#include "n.h"\n}\n__global__ void k(){}\n'                 > "$WR/extc.cu"
printf 'namespace ns {\n#include "d.inc"\n}\n'                                     > "$WR/ns.cpp"
printf '#include "fn_body.h"\nvoid f( void ){\n#include "macro_hdr.h"\n}\n'        > "$WR/body.c"
printf '#include "fn_body.h"\nvoid f( void ){\n#include "macro_hdr.h"\n}\n'        > "$WR/body.metal"
printf '#ifdef GUARD\n#include "d.inc"\nthis is not valid C at all ((( \n#endif\n'  > "$WR/broken.h"
"$BIN" "$WR" --deps --no-cache > "$TMP/reach.xml" 2>/dev/null
R_FNBODY=$(grep -o '<inc t="fn_body\.h"'  "$TMP/reach.xml" | wc -l)
R_DINC=$(grep -o '<inc t="d\.inc"'         "$TMP/reach.xml" | wc -l)
R_NH=$(grep -o '<inc t="n\.h"'             "$TMP/reach.xml" | wc -l)
R_MACRO=$(grep -o '<inc t="macro_hdr\.h"' "$TMP/reach.xml" | wc -l)
R_TOTAL=$(grep -o '<inc ' "$TMP/reach.xml" | wc -l)
if [ "$R_TOTAL" -eq 3 ] && [ "$R_FNBODY" -eq 2 ] && [ "$R_DINC" -eq 1 ] && [ "$R_NH" -eq 0 ] && [ "$R_MACRO" -eq 0 ]; then
    ok "reach gate: exactly main's 3 of 9 — file-scope x2 and the guarded one kept; extern\"C\", namespace and function-body all out"
else
    no "reach gate: total=$R_TOTAL fn_body=$R_FNBODY d.inc=$R_DINC n.h=$R_NH macro_hdr=$R_MACRO (want 3/2/1/0/0) — an unanchored query is widening the graph"
    sed 's/></>\n</g' "$TMP/reach.xml" | grep -o '<inc t="[^"]*"' | sed 's/^/              /'
fi

# ── arm 12b: the DEPTH BOUND's last three rows — 255, 256, 257 ─────────────────────────────────────────
# The one-character boundary at the nesting bound, which was wrong until the maintainer measured it.
# importContainerReach counts the containers ABOVE the directive; the walk it replaces counted from the
# other end. Main pushes a frame at `frame.depth + 1` and refuses to descend a container whose OWN depth
# has reached kMaxImportContainerDepth — so main captures a directive under exactly 256 containers and
# the cut starts at 257. Testing that count with `>=` against the same constant cuts at 256 instead and
# silently drops that one edge. Both halves moved together: the loop's break and emitCapturedImport's
# disclose test.
#
# Why no other arm caught it: test/preproccondcheck.sh's 600-deep arm is past the boundary on BOTH sides,
# so it passes either way, and a 256-deep file is not a shape a human writes. The maintainer's
# #elif-chain probe reaches it without hand-written nesting at all, which is the argument for pinning the
# boundary directly instead of trusting a deeper probe to cover it.
#
# These are the SPECIFICATION, read off main's own descend condition rather than reasoned out here: kept
# at 255 and 256, cut and disclosed at 257. The 256 row is the one that fails on the old comparison.
BD="$TMP/bound"
bd_shape(){ # $1=depth -> a dir holding one include under $1 nested containers, target inside it
    mkdir -p "$BD/$1"; printf 'int helper;\n' > "$BD/$1/deep.h"
    local i=0
    while [ "$i" -lt "$1" ]; do printf '#ifdef G%s\n' "$i" >> "$BD/$1/a.c"; i=$((i + 1)); done
    printf '#include "deep.h"\n' >> "$BD/$1/a.c"
    i=0; while [ "$i" -lt "$1" ]; do printf '#endif\n' >> "$BD/$1/a.c"; i=$((i + 1)); done
}
BD_BAD=0
for d in 255 256 257; do
    bd_shape "$d"
    "$BIN" "$BD/$d" --deps    --no-cache > "$TMP/bd$d.dep"  2>/dev/null
    "$BIN" "$BD/$d" --skipped --no-cache > "$TMP/bd$d.skip" 2>/dev/null
    # `wc -l` PADS ITS OUTPUT on BSD: on macOS `echo x | wc -l` prints "       1", on GNU it prints
    # "1". Comparing that as a STRING reported `edge= 1 ... (want 1/0)` as a FAIL — the values were
    # equal and the arm failed anyway, on 8 of the 24 release legs and nowhere else. Every other
    # wc -l in this gate is compared with -eq, which evaluates in an arithmetic context and strips the
    # padding for free; this one was the only string comparison, which is exactly why it was the only
    # one that broke. Normalised here, and compared with -eq like its siblings.
    e=$(grep -o '<inc ' "$TMP/bd$d.dep" | wc -l | tr -d '[:space:]')
    f=$(grep -c 'why="extract-partial"' "$TMP/bd$d.skip" | tr -d '[:space:]' || true)
    # 255 and 256: the edge survives and nothing is announced. 257: the edge is gone AND announced.
    if [ "$d" -le 256 ]; then want_e=1; want_f=0; else want_e=0; want_f=1; fi
    if [ "$e" -ne "$want_e" ] || [ "$f" -ne "$want_f" ]; then
        BD_BAD=1
        no "depth bound at $d: edge=$e extract-partial=$f (want $want_e/$want_f) — the nesting bound is off by one against main"
    fi
done
[ "$BD_BAD" -eq 0 ] \
    && ok "depth bound matches main exactly: kept at 255 and 256 containers, cut AND disclosed at 257" \
    || true

# ── arm 12c: the two DISCLOSURE differences from main, pinned in BOTH directions ───────────────────────
# Re-deriving the bound from ancestry cannot reproduce main's disclosure on two shapes, because main's
# answer comes from a walk that never made the trip this round makes. The maintainer reviewed both and
# asked for OUR behaviour to be kept and documented, not reverted — matching main here would need an
# unbounded parent walk, which is the very thing the bound exists to prevent. So these two rows are
# DELIBERATE, and this arm exists so that a later change to either direction is caught rather than
# discovered: one row pins where this round is QUIETER than main, one where it is LOUDER.
DS="$TMP/disc"
# (i) QUIETER, and the more accurate answer: no import was actually dropped, so there is nothing to
#     announce. Main flags these because its walk entered a too-deep container on the way to a file that
#     turned out to hold no import at all.
mkdir -p "$DS/quiet"
{ i=0; while [ "$i" -lt 300 ]; do printf '#ifdef G%s\n' "$i" >> "$DS/quiet/a.c"; i=$((i + 1)); done
  printf 'int y;\n' >> "$DS/quiet/a.c"
  i=0; while [ "$i" -lt 300 ]; do printf '#endif\n' >> "$DS/quiet/a.c"; i=$((i + 1)); done
} >/dev/null 2>&1
printf 'int x;\n' > "$DS/quiet/x.c"
# (ii) LOUDER, and the safe direction: the include sits inside a function body whose OWN 260 nested
#      conditionals put it past the bound, so the depth test fires before the reach test can conclude
#      the walk would never have entered the function anyway.
mkdir -p "$DS/loud"; printf 'int x;\n' > "$DS/loud/deep.h"
{ printf 'void f( void ){\n'
  i=0; while [ "$i" -lt 260 ]; do printf '#ifdef G%s\n' "$i" >> "$DS/loud/a.c"; i=$((i + 1)); done
  printf '#include "deep.h"\n' >> "$DS/loud/a.c"
  i=0; while [ "$i" -lt 260 ]; do printf '#endif\n' >> "$DS/loud/a.c"; i=$((i + 1)); done
  printf '}\n'
} >/dev/null 2>&1
"$BIN" "$DS/quiet" --skipped --no-cache > "$TMP/dq.xml" 2>/dev/null
"$BIN" "$DS/loud"  --skipped --no-cache > "$TMP/dl.xml" 2>/dev/null
Q=$(grep -c 'why="extract-partial"' "$TMP/dq.xml" || true)
L=$(grep -c 'why="extract-partial"' "$TMP/dl.xml" || true)
if [ "$Q" -eq 0 ] && [ "$L" -eq 1 ]; then
    ok "the two deliberate disclosure differences hold: silent when nothing was dropped, loud when the bound cut an import"
else
    no "disclosure differences moved: no-include-under-300-nesting extract-partial=$Q (want 0), import-in-fn-under-260 extract-partial=$L (want 1)"
fi

# ── arm 9: cache round-trip, on --deps — where the include edges actually show ────────────────────────
# The map view does not carry Include rows, so the earlier version of this arm compared two documents in
# which the cached records are invisible. --deps is the view that reads them.
CACHE="$TMP/c.bin"
"$BIN" "$WORK" --cache="$CACHE" --deps > "$TMP/cold.xml" 2>/dev/null      # populate
"$BIN" "$WORK" --cache="$CACHE" --deps > "$TMP/warm.xml" 2>/dev/null
"$BIN" "$WORK" --no-cache   --deps > "$TMP/nocache.xml" 2>/dev/null
cmp -s "$TMP/cold.xml" "$TMP/warm.xml" \
    && ok "warm == cold on --deps (the Include round-trip, incl. isAngle, is byte-identical)" \
    || no "warm != cold on --deps — the Include cache round-trip changed"
cmp -s "$TMP/cold.xml" "$TMP/nocache.xml" \
    && ok "cache path == no-cache path on --deps" \
    || no "cache vs no-cache diverged on --deps"

# ── arm 13: a cache written by a PRE-CHANGE binary is still correct for this one ──────────────────────
# kParserVer is bumped "on any grammar/.scm/extraction change" (src/ingest_cache.h), and this round
# changed both a .scm and the extraction path — yet it needs NO bump, because the records are identical and
# a stale cache therefore still holds the truth. This arm is the evidence for that claim: a cache written
# by the pre-change binary is ACCEPTED (not rejected), and reading it must equal --no-cache exactly. If a
# future change makes the two disagree, this arm is what says a bump is owed.
# It SKIPs unless RIPWIRE_BASE_BIN names one — which is every CI run, because CI has no pre-change
# binary to hand, so that path must be safe with the variable UNSET. It was not, once: an earlier draft
# expanded `$RIPWIRE_PRECHANGE_BIN` bare inside this very message, and `set -u` killed the gate mid-run
# with NO output — the shape pargates reports as "the gate died before its own reporting", which cost a
# 12-job CI cycle to find. A gate that can die silently is worse than one that fails.
#
# The name and the shape are the house convention, not a new one: test/recallbudgetcheck.sh and
# test/selectorchaincheck.sh take the same optional reference binary, read it the same way
# (`BASE="${RIPWIRE_BASE_BIN:-}"`), and SKIP when it is absent.
BASE_BIN="${RIPWIRE_BASE_BIN:-}"
if [ -n "$BASE_BIN" ] && [ -x "$BASE_BIN" ]; then
    PCACHE="$TMP/pre.bin"
    rm -f "$PCACHE"
    "$BASE_BIN" "$WORK" --cache="$PCACHE" --deps >/dev/null 2>&1
    # A copy, not a checksum: `sha256sum` is absent on stock macOS and `shasum -a 256` is absent on
    # some Linux images, and 8 of the 24 release legs are macOS. cmp against a copy is the portable
    # spelling of "these bytes did not change".
    cp "$PCACHE" "$TMP/pre.bin.copy"
    "$BIN" "$WORK" --cache="$PCACHE" --deps > "$TMP/prewarm.xml" 2>/dev/null
    if cmp -s "$TMP/prewarm.xml" "$TMP/nocache.xml"; then
        ok "a pre-change binary's cache is accepted and reads identically — no kParserVer bump is owed"
    else
        no "a pre-change cache reads DIFFERENTLY from --no-cache — extraction output changed, so kParserVer must be bumped"
    fi
    # Reading identically is NOT the same as being accepted: a binary that silently rejected the cache
    # and rebuilt it from source would produce the same document and sail the arm above. Acceptance is
    # the stronger claim — kParserVer accepted the pre-change stamp AND the bytes on disk came back
    # untouched — so it gets its own assertion.
    if cmp -s "$PCACHE" "$TMP/pre.bin.copy"; then
        ok "the pre-change cache file is byte-for-byte UNCHANGED after this binary read it — accepted, not silently rebuilt"
    else
        no "the pre-change cache file was REWRITTEN — this binary rebuilt it rather than accepting the pre-change stamp"
    fi
else
    skip "pre-change-cache arm (set RIPWIRE_BASE_BIN=<path to a pre-change ripwire> to run it)"
fi

# ── arm 10: determinism ───────────────────────────────────────────────────────────────────────────────
"$BIN" "$WORK" --no-cache > "$TMP/d1.xml" 2>/dev/null
"$BIN" "$WORK" --no-cache > "$TMP/d2.xml" 2>/dev/null
if cmp -s "$TMP/d1.xml" "$TMP/d2.xml"; then
    ok "deterministic (two --no-cache runs identical)"
else
    no "non-deterministic output"
fi

# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# JS/TS SLICE (DepDialect::Web) — TypeScript, TSX, JavaScript and the .astro frontmatter.
#
# WHAT THIS PINS. `import … from 'x'`, the re-exports (`export * from`, `export { a as b } from`,
# `export type { T } from`), and the CommonJS / dynamic `require('x')` / `import('x')` no longer come from
# captureIncludes' walk (directiveTargetOf's import_statement-source / export_statement / call_expression
# branches). They come from the same `@import.path` name, three patterns per queries/{typescript,tsx,
# javascript}/tags.scm, normalised by the DepDialect::Web arm of src/ingest_importcap.h. The EMITTED edges
# are exactly the ones the walk emitted, for every spelling — and for every spelling the walk did NOT emit:
#
#   J1  the Web patterns are COMPILED IN, and the walk's TS/JS branches are GONE from src/
#   J2  exact edge list, in source order, for .ts .js .tsx .mjs .cjs .jsx and the .astro frontmatter —
#       ES default/named/namespace/side-effect/type imports, three re-export spellings, CommonJS in every
#       container shape the walk entered (declaration, assignment, export, callback, await, if/try/for…)
#   J3  THE NEGATIVES — the query matches ANY `x('s')` call at ANY depth; every `neg_*` specifier below is
#       a shape the walk never turned into an edge (member callee, `.foo` chained on the call, ternary,
#       array, two arguments, a comment before the string, template literal, computed, `require.resolve`,
#       a `new` argument, TS `import x = require()`, a `declare module` body, a class method) and none may
#       become one. The leading text gate (callee is `require`/`import`) and the reach rule are what hold.
#   J4  the LAZY bit — a require()/import() written inside a function body is lazy="1" on --impact's import
#       tier; a top-level one is lazy="0"; one file required both ways is lazy="0" (the pair rule)
#   J5  the use-site half — --uses reports the import-role ref of a named import
#   J6  the DEPTH BOUND on blocks — kept at 255 and 256 containers, cut AND announced at 257, as the walk did
#   J7  the DELIBERATE disclosure differences (the two of the C-family arm 12c, same reason, plus a non-import under a too-deep nest)
#   J8  cache round-trip, a pre-change binary's cache accepted (no kParserVer bump), determinism
#
# The expected lists are the SPECIFICATION and were read off the pre-change binary, never reasoned out: this
# slice is a refactor, so main's set is the contract. The `neg_*` / `lazy_*` / `cjs_*` names say what each
# edge (or non-edge) is, so a diff reads without opening the fixture.

web_fixture_ts() { local W="$1"
    cat > "$W/main.ts" <<'TS'
import def from "./es_default";
import { named1, named2 as alias2 } from "./es_named";
import * as ns from "./es_namespace";
import "./es_sideeffect";
import type { T } from "./es_type_named";
import type DefT from "./es_type_default";
import { type U, V } from "./es_inline_type";
import dflt, { n1 } from "./es_default_and_named";
import json from "./es_import_attributes" with { type: "json" };
export * from "./re_star";
export { default } from "./re_default";
export { default as D } from './re_default_as_single_quote';
export * as hns from "./re_star_as";
export { x as y } from "./re_named_as";
export type { Z } from "./re_type";
import eq = require("./neg_import_equals");
import type eq2 = require("./neg_import_equals_type");
export = ns;
const r1 = require("./cjs_const");
const { q1, q2 } = require("./cjs_destructured");
var r2 = require('./cjs_var_single');
require("./cjs_bare");
module.exports = require("./cjs_module_exports");
const dyn = await import("./dyn_await");
const opt = require?.("./cjs_optional_call");
const memb = require("./neg_member").foo;
const tern = cond ? require("./neg_ternary") : null;
const arr = [require("./neg_array")];
const two = require("./neg_two_args", "./neg_second");
const cm = require(/*c*/ "./neg_comment");
const tpl = require(`./neg_template`);
const nonlit = require(neg_variable);
const other = foo.require("./neg_foo_require");
const cat = require("./neg_concat" + sfx);
const res = require.resolve("./neg_resolve");
const nw = new Foo(require("./neg_new_arg"));
const nest = foo(bar(require("./fn_arg_nested")));
const th = import("./neg_dynamic_then").then(( m ) => m);
const bang = !require("./neg_unary");
function f() { return require("./lazy_function"); }
const g2 = () => import("./lazy_arrow");
class K { m() { return require("./neg_class_method"); } }
const o = { get G() { return require("./lazy_getter"); } };
if (x) { require("./if_then"); } else { require("./if_else"); }
try { require("./try_body"); } catch (e) { require("./catch_body"); }
for (;;) { require("./for_body"); }
switch (x) { case 1: require("./switch_case"); }
export default require("./export_default_require");
export const ex = require("./export_const_require");
export function ef() { return import("./export_fn_dynamic"); }
foo(function () { require("./callback_fn"); });
foo(() => require("./callback_arrow"), require("./callback_second"));
const pe = (require("./paren_require"));
const aw = await require("./await_require");
label: require("./labeled");
TS
}
web_fixture_js() { local W="$1"
    cat > "$W/main.js" <<'JS'
import def from "./es_default";
import { named1, named2 as alias2 } from "./es_named";
import * as ns from "./es_namespace";
import "./es_sideeffect";
export * from "./re_star";
export * as hns from "./re_star_as";
export { x as y } from "./re_named_as";
const r1 = require("./cjs_const");
const { q1, q2 } = require("./cjs_destructured");
require("./cjs_bare");
module.exports = require("./cjs_module_exports");
const dyn = await import("./dyn_await");
const memb = require("./neg_member").foo;
const arr = [require("./neg_array")];
const two = require("./neg_two_args", "./neg_second");
const cm = require(/*c*/ "./neg_comment");
const nonlit = require(neg_variable);
function f() { return require("./lazy_function"); }
const g2 = () => import("./lazy_arrow");
class K { m() { return require("./neg_class_method"); } }
exports.run = function () { return require("./lazy_exports_fn"); };
JS
}
web_fixture_small() { local W="$1"   # .tsx .mjs .cjs .jsx and the .astro frontmatter
    cat > "$W/neg.ts" <<'NEG'
declare module "amb" { import q from "./neg_ambient"; }
namespace NS { import w = require("./neg_ns_equals"); const z2 = require("./neg_ns_const"); }
NEG
    cat > "$W/comp.tsx" <<'TSX'
import React from "react";
import { Button } from "./tsx_button";
export { Card } from "./tsx_card";
export const View = () => <Button onClick={() => import("./tsx_lazy")}>{require("./neg_tsx_jsx_child")}</Button>;
const side = require("./tsx_cjs");
TSX
    printf 'import m from "./mjs_import";\nexport * from "./mjs_reexport";\nconst c = require("./mjs_cjs");\n' > "$W/mod.mjs"
    printf 'const a = require("./cjs_file");\nmodule.exports = { get b() { return require("./cjs_lazy"); } };\n' > "$W/mod.cjs"
    printf 'import J from "./jsx_import";\nconst V = () => <J/>;\n' > "$W/view.jsx"
    printf '%s\n' '---' 'import A from "./astro_import";' 'const m = require("./astro_require");' 'export * from "./astro_reexport";' '---' '<div>{A}</div>' > "$W/page.astro"
}
web_fixture_stubs() { local W="$1"
    # every specifier above names a real file, so each edge RESOLVES and the lazy bit and --uses are observable
    local spec
    for spec in $(cat "$W"/main.ts "$W"/neg.ts "$W"/main.js "$W"/comp.tsx "$W"/mod.mjs "$W"/mod.cjs "$W"/view.jsx "$W"/page.astro \
                  | grep -o '"\./[A-Za-z_0-9]*"\|'"'"'\./[A-Za-z_0-9]*'"'" | tr -d "\"'" | sort -u); do
        printf 'export const %s = 1;\n' "${spec#./}" > "$W/${spec#./}.js"
    done
}
web_fixture() {   # $1 = an empty directory
    mkdir -p "$1"
    web_fixture_ts "$1"; web_fixture_js "$1"; web_fixture_small "$1"; web_fixture_stubs "$1"
}

# The expected Include targets per file, in source order, as one space-separated line each — read off the
# PRE-CHANGE binary on exactly this fixture. 40 / 15 / 4 / 3 / 2 / 1 / 3 edges.
W_MAIN_TS='./es_default ./es_named ./es_namespace ./es_sideeffect ./es_type_named ./es_type_default ./es_inline_type ./es_default_and_named ./es_import_attributes ./re_star ./re_default ./re_default_as_single_quote ./re_star_as ./re_named_as ./re_type ./cjs_const ./cjs_destructured ./cjs_var_single ./cjs_bare ./cjs_module_exports ./dyn_await ./cjs_optional_call ./fn_arg_nested ./lazy_function ./lazy_arrow ./lazy_getter ./if_then ./if_else ./try_body ./catch_body ./for_body ./export_default_require ./export_const_require ./export_fn_dynamic ./callback_fn ./callback_arrow ./callback_second ./paren_require ./await_require ./labeled'
W_MAIN_JS='./es_default ./es_named ./es_namespace ./es_sideeffect ./re_star ./re_star_as ./re_named_as ./cjs_const ./cjs_destructured ./cjs_bare ./cjs_module_exports ./dyn_await ./lazy_function ./lazy_arrow ./lazy_exports_fn'
W_COMP_TSX='react ./tsx_button ./tsx_card ./tsx_cjs'
W_MOD_MJS='./mjs_import ./mjs_reexport ./mjs_cjs'
W_MOD_CJS='./cjs_file ./cjs_lazy'
W_VIEW_JSX='./jsx_import'
W_PAGE_ASTRO='./astro_import ./astro_require ./astro_reexport'

WEB="$TMP/web"; web_fixture "$WEB"
"$BIN" "$WEB" --deps --no-cache > "$TMP/web.deps.xml" 2> "$TMP/web.deps.err"
web_incs(){ sed 's/<f /\n<f /g' "$TMP/web.deps.xml" | grep "^<f p=\"$1\"" | grep -o '<inc t="[^"]*"' | sed 's/<inc t="//; s/"$//' | tr '\n' ' ' | sed 's/ $//'; }

# ── J1: the Web patterns are COMPILED IN, and the walk's TS/JS branches are gone ───────────────────────
# `source: (string) @import.path` is the line two of the three patterns share (import_statement and
# export_statement) in each of the three embedded query files; a pre-change binary carries none (measured: 0
# vs 6). The C-family patterns never contain it, so unlike the C-family arm 1 this one is RED on a binary
# without the JS/TS slice.
WEB_PATTERNS=$(grep -ao 'source: (string) @import\.path' "$BIN" | wc -l | tr -d '[:space:]')
if [ -n "$WEB_PATTERNS" ] && [ "$WEB_PATTERNS" -ge 6 ]; then
    ok "J1: the JS/TS import patterns are in the binary's embedded tags.scm ($WEB_PATTERNS occurrences; 0 on a pre-change build)"
else
    no "J1: expected >= 6 occurrences of the JS/TS @import.path patterns in the binary, got '${WEB_PATTERNS:-none}'"
fi
for gone in 'kindIs( t, "export_statement" )' 'target = jsModuleLoadTarget( n, src );'; do
    if grep -rqF "$gone" "$ROOT/src"; then
        no "J1: the walk's TS/JS branch \`$gone\` is still in src/ — it should have been removed with this language"
    else
        ok "J1: the walk's TS/JS branch is gone from src/ ($gone)"
    fi
done

# ── J2 + J3: exact edge list per file, which also pins every negative ──────────────────────────────────
WEB_BAD=0
for pair in "main.ts:$W_MAIN_TS" "main.js:$W_MAIN_JS" "comp.tsx:$W_COMP_TSX" "mod.mjs:$W_MOD_MJS" \
            "mod.cjs:$W_MOD_CJS" "view.jsx:$W_VIEW_JSX" "page.astro:$W_PAGE_ASTRO"; do
    f=${pair%%:*}; want=${pair#*:}
    got=$(web_incs "$f")
    if [ -z "$got" ] || [ "$got" != "$want" ]; then
        WEB_BAD=1
        no "J2: $f Include targets differ from the pre-change set"
        printf '    expected: %s\n    got:      %s\n' "$want" "${got:-<none>}"
    fi
done
[ "$WEB_BAD" -eq 0 ] && ok "J2: exact Include set and order for .ts .js .tsx .mjs .cjs .jsx and the .astro frontmatter (68 edges)"
NEG=$(grep -o '<inc t="[^"]*neg_[^"]*"' "$TMP/web.deps.xml" | wc -l | tr -d '[:space:]')
EDGES=$(grep -o '<inc t=' "$TMP/web.deps.xml" | wc -l | tr -d '[:space:]')
if [ "$NEG" = "0" ] && [ "${EDGES:-0}" -eq 68 ]; then
    ok "J3: no neg_* specifier became an edge (the query is broader than a module load; the text gate and the reach rule hold)"
else
    no "J3: neg_* edges=${NEG:-?} (want 0), total edges=${EDGES:-?} (want 68)"
fi

# ── J4: the LAZY bit, re-derived from ancestry ────────────────────────────────────────────────────────
# Include::isLazy came from captureIncludes' sticky `insideFn`; the tags pass has no walk frame, so
# importContainerReach recomputes it from the captured call's ancestors. Observable one level up: --impact's
# import tier prints lazy= per importer edge.
LZ="$TMP/lz"; mkdir -p "$LZ"
printf 'const eager = require("./eager");\nfunction later() { return require("./lazy_only"); }\nfunction both() { return require("./both"); }\nconst b2 = require("./both");\nmodule.exports = { later, both, eager, b2 };\n' > "$LZ/entry.js"
for n in eager lazy_only both; do printf 'function %s_fn() { return 1; }\nmodule.exports = %s_fn;\n' "$n" "$n" > "$LZ/$n.js"; done
LZ_BAD=0
for pair in eager_fn:0 lazy_only_fn:1 both_fn:0; do
    s=${pair%%:*}; want=${pair#*:}
    got=$("$BIN" "$LZ" --impact="$s" --no-cache 2>/dev/null | grep -o '<f via="import" p="entry\.js" lazy="[01]"' | grep -o 'lazy="[01]"' | head -1)
    if [ "$got" != "lazy=\"$want\"" ]; then LZ_BAD=1; no "J4: --impact=$s importer edge is ${got:-absent}, want lazy=\"$want\""; fi
done
[ "$LZ_BAD" -eq 0 ] && ok "J4: lazy bit — top-level require lazy=0, function-body require lazy=1, a file required both ways lazy=0"

# ── J5: the use-site half ────────────────────────────────────────────────────────────────────────────
WU=$("$BIN" "$WEB" --uses=es_named --no-cache 2>/dev/null | grep -o '<u role="import" p="main\.\(ts\|js\):2"' | wc -l | tr -d '[:space:]')
if [ "${WU:-0}" -eq 2 ]; then
    ok "J5: --uses reports the import-role ref of a named import in both main.ts:2 and main.js:2"
else
    no "J5: --uses=es_named import-role rows = ${WU:-?} (want 2)"
fi

# ── J6: the DEPTH BOUND, on nested blocks ───────────────────────────────────────────────────────────
# `{ { … require('./deep') … } }` — each block is a statement_block, and the statement is an
# expression_statement, so n blocks put the call under n+1 containers. The walk captured a directive under
# exactly 256 containers and cut at 257; importContainerReach must agree. n = 254, 255 are kept; 256 is
# cut and announced.
WB="$TMP/wbound"
web_bound(){ # $1=blocks
    mkdir -p "$WB/$1"; printf 'export const deep = 1;\n' > "$WB/$1/deep.js"
    local i=0
    { while [ "$i" -lt "$1" ]; do printf '{'; i=$((i + 1)); done
      printf ' require("./deep"); '
      i=0; while [ "$i" -lt "$1" ]; do printf '}'; i=$((i + 1)); done; printf '\n'; } > "$WB/$1/a.js"
}
WB_BAD=0
for n in 254 255 256; do
    web_bound "$n"
    e=$("$BIN" "$WB/$n" --deps    --no-cache 2>/dev/null | grep -o '<inc ' | wc -l | tr -d '[:space:]')
    f=$("$BIN" "$WB/$n" --skipped --no-cache 2>/dev/null | grep -c 'why="extract-partial"' | tr -d '[:space:]' || true)
    if [ "$n" -le 255 ]; then want_e=1; want_f=0; else want_e=0; want_f=1; fi
    if [ "$e" != "$want_e" ] || [ "$f" != "$want_f" ]; then
        WB_BAD=1
        no "J6: $n nested blocks: edge=$e extract-partial=$f (want $want_e/$want_f)"
    fi
done
[ "$WB_BAD" -eq 0 ] && ok "J6: depth bound — kept under 255 and 256 containers, cut AND announced under 257 (edges identical to the walk's)"

# ── J7: the DELIBERATE disclosure differences, in both directions (the C-family arm 12c, for JS) ────
# (i) QUIETER: `require('./deep')` is ITSELF a container, so the walk refused to descend into it from depth
#     256 and announced, although the edge was kept and nothing was dropped. n=255 above is that shape: edge
#     kept, and this binary says nothing because nothing was lost (the walk said extract-partial).
# (ii) LOUDER: 300 blocks inside a class METHOD. The walk never entered the class (class_declaration is not
#     an import container) so it said nothing; the ancestor loop reaches the bound first and announces. The
#     safe direction — a floor that says so — and the same trade the C-family slice accepted.
WL="$TMP/wloud"; mkdir -p "$WL"; printf 'export const deep = 1;\n' > "$WL/deep.js"
{ printf 'class K { m() { '; i=0; while [ "$i" -lt 300 ]; do printf '{'; i=$((i + 1)); done
  printf ' require("./deep"); '; i=0; while [ "$i" -lt 300 ]; do printf '}'; i=$((i + 1)); done; printf ' } }\n'; } > "$WL/a.js"
LE=$("$BIN" "$WL" --deps    --no-cache 2>/dev/null | grep -o '<inc ' | wc -l | tr -d '[:space:]')
LF=$("$BIN" "$WL" --skipped --no-cache 2>/dev/null | grep -c 'why="extract-partial"' | tr -d '[:space:]' || true)
QF=$("$BIN" "$WB/255" --skipped --no-cache 2>/dev/null | grep -c 'why="extract-partial"' | tr -d '[:space:]' || true)
if [ "$LE" = "0" ] && [ "$LF" = "1" ] && [ "$QF" = "0" ]; then
    ok "J7: disclosure differences hold — silent when the edge was kept (255 blocks), loud when the bound cut an unreachable import (class method)"
else
    no "J7: class-method-under-300: edges=$LE partial=$LF (want 0/1); 255-blocks partial=$QF (want 0)"
fi

# (iii) QUIETER, and no import in the file at all: 300 nested blocks around `foo( "x" )` (a call the Web pattern
#     captures and the text gate drops), and 300 nested #ifdef around `#pragma once` (captured by the C/C++
#     preproc_call pattern, dropped by the #import gate). The walk announced on any too-deep CONTAINER, and the
#     first version of this arm announced because the bound test ran before the text gate; both said "an import
#     was cut" when nothing import-shaped existed. The text gate now runs first, so neither does.
WQ="$TMP/wquiet"; mkdir -p "$WQ/js" "$WQ/c"
{ i=0; while [ "$i" -lt 300 ]; do printf '{'; i=$((i + 1)); done
  printf ' foo("x"); '; i=0; while [ "$i" -lt 300 ]; do printf '}'; i=$((i + 1)); done; printf '\n'; } > "$WQ/js/a.js"
{ i=0; while [ "$i" -lt 300 ]; do printf '#ifdef G%s\n' "$i"; i=$((i + 1)); done
  printf '#pragma once\n'; i=0; while [ "$i" -lt 300 ]; do printf '#endif\n'; i=$((i + 1)); done; } > "$WQ/c/a.c"
QJ=$("$BIN" "$WQ/js" --skipped --no-cache 2>/dev/null | grep -c 'why="extract-partial"' | tr -d '[:space:]' || true)
QC=$("$BIN" "$WQ/c"  --skipped --no-cache 2>/dev/null | grep -c 'why="extract-partial"' | tr -d '[:space:]' || true)
if [ "$QJ" = "0" ] && [ "$QC" = "0" ]; then
    ok "J7: no announcement when nothing import-shaped was cut (foo( \"x\" ) under 300 blocks, #pragma once under 300 #ifdef)"
else
    no "J7: non-import under a too-deep nest announced an import cut: js=$QJ c=$QC (want 0/0)"
fi

# ── J8: cache round-trip and a pre-change cache ─────────────────────────────────────────────────────
WC="$TMP/web.cache.bin"
"$BIN" "$WEB" --cache="$WC" --deps > "$TMP/web.cold.xml" 2>/dev/null
"$BIN" "$WEB" --cache="$WC" --deps > "$TMP/web.warm.xml" 2>/dev/null
if cmp -s "$TMP/web.cold.xml" "$TMP/web.warm.xml" && cmp -s "$TMP/web.cold.xml" "$TMP/web.deps.xml"; then
    ok "J8: warm == cold == --no-cache on --deps for the JS/TS fixture (isLazy round-trips)"
else
    no "J8: JS/TS --deps differs between cold, warm and --no-cache"
fi
if [ -n "$BASE_BIN" ] && [ -x "$BASE_BIN" ]; then
    WP="$TMP/web.pre.bin"; rm -f "$WP"
    "$BASE_BIN" "$WEB" --cache="$WP" --deps >/dev/null 2>&1
    cp "$WP" "$TMP/web.pre.bin.copy"
    "$BIN" "$WEB" --cache="$WP" --deps > "$TMP/web.prewarm.xml" 2>/dev/null
    if cmp -s "$TMP/web.prewarm.xml" "$TMP/web.deps.xml" && cmp -s "$WP" "$TMP/web.pre.bin.copy"; then
        ok "J8: a pre-change binary's JS/TS cache is accepted unchanged and reads identically — no kParserVer bump is owed"
    else
        no "J8: a pre-change JS/TS cache reads differently or was rewritten — extraction output changed, kParserVer must be bumped"
    fi
else
    skip "J8: pre-change-cache arm for JS/TS (set RIPWIRE_BASE_BIN=<path to a pre-change ripwire> to run it)"
fi
"$BIN" "$WEB" --no-cache --deps > "$TMP/web.d2.xml" 2>/dev/null
if cmp -s "$TMP/web.deps.xml" "$TMP/web.d2.xml"; then
    ok "J8: deterministic (two --no-cache JS/TS runs identical)"
else
    no "J8: non-deterministic JS/TS output"
fi

# THE GO SLICE (arms 14-19). Go's import_declaration rides `(import_declaration) @import.path` and the
# DepDialect::Go normaliser; the Include target is the declaration CLAUSE, exactly as the removed walk branch
# built it, so every row below is the byte-for-byte row the extractor emitted (read off the pre-change binary,
# not predicted). A GROUPED import is ONE row whose text is the whole group cut at 96 bytes — resolve.h's
# resolveGoImport documents that — and splitting it per spec would ADD rows, which is exactly what arm 15
# would show as a diff.
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
GO="$TMP/go"; mkdir -p "$GO/cmd" "$GO/pkg/util" "$GO/replaced"
printf 'module example.com/app\n\ngo 1.21\n\nrequire example.com/ext v0.0.0\n\nreplace example.com/ext => ./replaced\n' > "$GO/go.mod"
printf 'package ext\n\nfunc Ext() int { return 1 }\n'     > "$GO/replaced/ext.go"
printf 'package util\n\nfunc Helper() int { return 2 }\n' > "$GO/pkg/util/util.go"
cat > "$GO/main.go" <<'GOSRC'
package main

import "fmt"
import f2 "os"
import . "strings"
import _ "embed"
import (
	"example.com/app/pkg/util"
	alias "example.com/ext"
	. "math"
	_ "net/http/pprof"
	"strconv" // trailing comment
)

import "C"

func main() {
	fmt.Println(util.Helper(), alias.Ext(), f2.Args, strconv.Itoa(1), ToUpper("x"), Abs(1))
}
GOSRC
# a TAB after the keyword keeps the word `import` (the keyword is dropped at a SPACE); two spaces leave one
# leading space; a trailing `;` is trimmed; a raw-string path keeps its backticks.
printf 'package main\n\nimport\t"os"\nimport  "io";\nimport `raw/path`\n\nfunc t() { _ = os.Args }\n' > "$GO/cmd/tab.go"
cat > "$GO/cmd/long.go" <<'GOSRC'
package main

import (
	"github.com/very/long/module/path/that/goes/on/and/on/and/on/forever/and/ever/amen/pkg1"
	"github.com/very/long/module/path/that/goes/on/and/on/and/on/forever/and/ever/amen/pkg2"
)

func l() {}
GOSRC
# error recovery: a bare `import` swallowing the next lines is still ONE import_declaration, and a broken
# function header does not stop the next import being recovered.
printf 'package main\n\nimport\nfunc b( {\nimport "after/error"\n' > "$GO/cmd/broken.go"
printf 'package main\n\nfunc f( {\nimport "x"\n}\n' > "$GO/cmd/err.go"
# the 96-byte cut lands mid multibyte sequence on purpose: the pre-change bytes are kept, not "fixed".
printf 'package main\nimport "é世界/pkg"; import "z"\nimport ("é世界/pkg/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"\n)\n' > "$GO/cmd/utf.go"
# a definition named like the last path element of utf.go's first import: --uses keys on an INDEXED name, so
# arm 18 needs one (`fmt`, `os` have no definition in the tree and answer found=0).
printf 'package main\n\nfunc pkg() {}\n' > "$GO/cmd/pkgdef.go"
# arm 16's negative: an import inside a function body is not a file-scope declaration and was never an edge.
printf 'package main\n\nfunc a() {\n\timport "inbody"\n}\n' > "$GO/cmd/nested.go"

"$BIN" "$GO" --deps --no-cache > "$TMP/go.xml" 2>/dev/null
grep -o '<f p="[^"]*"\|<inc t="[^"]*"' "$TMP/go.xml" > "$TMP/go.rows"
cat > "$TMP/go.want" <<'GOWANT'
<f p="cmd/broken.go"
<inc t="b( {&#10;import &quot;after/error&quot;"
<f p="cmd/err.go"
<inc t="&quot;x&quot;"
<f p="cmd/long.go"
<inc t="(&#10;&#9;&quot;github.com/very/long/module/path/that/goes/on/and/on/and/on/forever/and/ever/amen/pkg1&quot;&#10;&#9;&quot;gi"
<f p="cmd/tab.go"
<inc t="import&#9;&quot;os&quot;"
<inc t=" &quot;io&quot;"
<inc t="`raw/path`"
<f p="cmd/utf.go"
<inc t="&quot;é世界/pkg&quot;"
<inc t="&quot;z&quot;"
<inc t="(&quot;é世界/pkg/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
<f p="main.go"
<inc t="&quot;fmt&quot;"
<inc t="f2 &quot;os&quot;"
<inc t=". &quot;strings&quot;"
<inc t="_ &quot;embed&quot;"
<inc t="(&#10;&#9;&quot;example.com/app/pkg/util&quot;&#10;&#9;alias &quot;example.com/ext&quot;&#10;&#9;. &quot;math&quot;&#10;&#9;_ &quot;net/http/pprof&quot;&#10;&#9;&quot;strconv&quot;"
<inc t="&quot;C&quot;"
GOWANT

# ── arm 14: the Go capture is COMPILED IN ─────────────────────────────────────────────────────────────
# Same reasoning as arm 1: a --match probe feeds its own query to the astQuery engine and passes on a
# pre-change binary, so the capture is looked for where it lives — the tags.scm embedded in the image. The
# C-family arm above already finds the literal `import.path`; THIS literal is Go's own pattern, absent from
# a build whose Go imports still come from the walk.
if grep -qa '(import_declaration) @import\.path' "$BIN"; then
    ok "Go: (import_declaration) @import.path is in the binary's embedded tags.scm"
else
    no "Go: the import_declaration capture is not compiled into this binary — Go imports are not on the shared vocabulary"
fi

# ── arm 15: every Go form, exact rows ─────────────────────────────────────────────────────────────────
if cmp -s "$TMP/go.rows" "$TMP/go.want"; then
    ok "Go: 21 rows byte-exact — single, aliased, dot, blank, group (cut at 96 bytes), cgo \"C\", tab, semicolon, raw string, UTF-8 cut, error recovery"
else
    no "Go: Include rows differ from the pre-change extractor's (diff expected vs got below)"
    diff "$TMP/go.want" "$TMP/go.rows" | sed 's/^/      /' | head -30
fi
# each form NAMED, so a red arm says which spelling a regression lost rather than "rows differ".
for form in 'fmt&quot;' 'f2 &quot;os&quot;' '\. &quot;strings&quot;' '_ &quot;embed&quot;' '&quot;C&quot;' 'alias &quot;example\.com/ext&quot;'; do
    grep -q "<inc t=\"[^\"]*$form" "$TMP/go.xml" || no "Go: the form [$form] has no Include row"
done
# the group is ONE row: three spec lines of main.go's block must not each become a row of their own.
if [ "$(grep -c '<inc t="(&#10;&#9;&quot;example' "$TMP/go.xml")" -eq 1 ] \
   && ! grep -q '<inc t="&quot;strconv&quot;"' "$TMP/go.xml" \
   && ! grep -q '<inc t="&quot;example.com/app/pkg/util&quot;"' "$TMP/go.xml"; then
    ok "Go: a grouped import block is ONE Include (its specs are not split into rows)"
else
    no "Go: a grouped import block was split into per-spec rows — that ADDS edges, a behaviour change"
fi

# ── arm 16: no widening ───────────────────────────────────────────────────────────────────────────────
if grep -q 'inbody' "$TMP/go.xml"; then
    no "Go: an import inside a function body became an edge (the capture is wider than the walk it replaced)"
else
    ok "Go: an import inside a function body stays out (reach re-derived from ancestry, as for C-family)"
fi
if ! grep -q 'cmd/nested.go' "$TMP/go.xml"; then
    ok "Go: the function-body file carries no Include row at all"
else
    no "Go: cmd/nested.go gained an Include row"
fi

# ── arm 17: resolution through imports — go.mod `replace` onto a sibling root ─────────────────────────
# The module-path resolution the Include feeds (resolve.h resolveGoImport) reads the FIRST QUOTED TOKEN of the
# clause, so a single, an aliased and a GROUPED import of the same package all resolve to its one file. Two
# importing roots, one providing root; svc/pkg/handle.go must have afferent=2.
WS="$TMP/gows"; mkdir -p "$WS/svc/pkg" "$WS/cli" "$WS/cli2" "$WS/clibogus"
printf 'package pkg\n\nfunc GoHandle() int { return 1 }\n' > "$WS/svc/pkg/handle.go"
printf 'module example.com/svc\n\ngo 1.21\n'               > "$WS/svc/go.mod"
printf 'module example.com/cli\n\ngo 1.21\n\nreplace example.com/svc => ../svc\n'   > "$WS/cli/go.mod"
printf 'package main\n\nimport svc "example.com/svc/pkg"\n\nfunc runGoMain() int { return svc.GoHandle() }\n' > "$WS/cli/main.go"
printf 'module example.com/cli2\n\ngo 1.21\n\nreplace example.com/svc => ../svc\n'  > "$WS/cli2/go.mod"
printf 'package main\n\nimport (\n\tsvc "example.com/svc/pkg"\n\t"fmt"\n)\n\nfunc runGrouped() int { fmt.Println(); return svc.GoHandle() }\n' > "$WS/cli2/main.go"
printf 'module example.com/clibogus\n\ngo 1.21\n\nreplace example.com/svc => ../svc/NONEXISTENT\n' > "$WS/clibogus/go.mod"
printf 'package main\n\nimport svc "example.com/svc/pkg"\n\nfunc runBogus() int { return svc.GoHandle() }\n' > "$WS/clibogus/main.go"
"$BIN" "$WS/svc" "$WS/cli" "$WS/cli2" --deps --no-cache > "$TMP/gows.xml" 2>/dev/null
if grep -q '<f p="svc/pkg/handle.go" afferent="2"' "$TMP/gows.xml"; then
    ok "Go: a go.mod replace resolves a single/aliased import AND a grouped one onto the sibling root's package (afferent=2)"
else
    no "Go: replace-based resolution changed — svc/pkg/handle.go afferent != 2: $(grep -o '<f p="svc/pkg/handle.go"[^>]*' "$TMP/gows.xml")"
fi
# the evidence-driven negative: the same import under a replace whose target does not exist resolves to nothing.
"$BIN" "$WS/svc" "$WS/clibogus" --deps --no-cache > "$TMP/gobogus.xml" 2>/dev/null
if grep -q '<inc t="svc &quot;example.com/svc/pkg&quot;"' "$TMP/gobogus.xml" && ! grep -q '<f p="svc/pkg/handle.go" afferent="[1-9]' "$TMP/gobogus.xml"; then
    ok "Go: a replace to a missing directory leaves the import captured but UNRESOLVED (evidence-driven, not name-driven)"
else
    no "Go: bogus replace — the import is not captured, or it resolved: $(grep -o '<f p="svc/pkg/handle.go"[^>]*' "$TMP/gobogus.xml")"
fi

# ── arm 18: the use-site half ─────────────────────────────────────────────────────────────────────────
GUSES="$("$BIN" "$GO" --uses=pkg --no-cache 2>/dev/null)"
if printf '%s' "$GUSES" | grep -q '<u role="import" p="cmd/utf.go:2"'; then
    ok "Go: --uses=pkg reports the import site cmd/utf.go:2 with role=\"import\" (the ABS-3 half survived the move)"
else
    no "Go: --uses lost the import-role use-site ref for a Go import: $(printf '%s' "$GUSES" | grep -o '<u [^>]*' | head -3)"
fi

# ── arm 19: Go cache round-trip + determinism ────────────────────────────────────────────────────────
GCACHE="$TMP/go.cache"
"$BIN" "$GO" --cache="$GCACHE" --deps > "$TMP/gocold.xml" 2>/dev/null
"$BIN" "$GO" --cache="$GCACHE" --deps > "$TMP/gowarm.xml" 2>/dev/null
if cmp -s "$TMP/gocold.xml" "$TMP/gowarm.xml" && cmp -s "$TMP/gocold.xml" "$TMP/go.xml"; then
    ok "Go: warm == cold == --no-cache on --deps (the Go Include round-trip is byte-identical)"
else
    no "Go: --deps differs between cold, warm and --no-cache"
fi
if [ -n "${BASE_BIN:-}" ] && [ -x "${BASE_BIN:-}" ]; then
    "$BASE_BIN" "$GO" --deps --no-cache > "$TMP/gobase.xml" 2>/dev/null
    if cmp -s "$TMP/gobase.xml" "$TMP/go.xml"; then
        ok "Go: --deps over the fixture is byte-identical to the pre-change binary's"
    else
        no "Go: --deps differs from the pre-change binary — dependency output changed"
    fi
    # and the Go half of arm 13: a cache written by the pre-change binary over the Go fixture is ACCEPTED
    # (file untouched) and reads identically, so no kParserVer bump is owed for the Go records either.
    GPRE="$TMP/gopre.bin"; rm -f "$GPRE"
    "$BASE_BIN" "$GO" --cache="$GPRE" --deps >/dev/null 2>&1
    cp "$GPRE" "$TMP/gopre.bin.copy"
    "$BIN" "$GO" --cache="$GPRE" --deps > "$TMP/gopre.xml" 2>/dev/null
    if cmp -s "$TMP/gopre.xml" "$TMP/go.xml" && cmp -s "$GPRE" "$TMP/gopre.bin.copy"; then
        ok "Go: a pre-change binary's cache over the Go fixture is accepted untouched and reads identically — no kParserVer bump owed"
    else
        no "Go: a pre-change cache reads differently or was rewritten — extraction output changed, kParserVer must be bumped"
    fi
else
    skip "Go: pre-change comparison (set RIPWIRE_BASE_BIN=<pre-change ripwire> to run it)"
fi

# ── well-formed XML ───────────────────────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/cold.xml" 2>/dev/null; then ok "xml well-formed"; else no "xml malformed"; fi
else
    skip "xml well-formed (xmllint absent)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
