#!/usr/bin/env bash
# headerstaticadjcheck.sh — the header-static visibility question resolves C-family #includes, not the whole corpus
# (lane PF1, 2026-11-21).
#
# The incident: BX1 FIX 3 (valuerefindex.h headerStaticVisibleFrom: a C `static` in a header is visible to the files
# that #include it) answers its first question by building the WHOLE-corpus include adjacency
# (resolve.h buildPreciseIncludeAdj): every Python import, TS specifier, Rust use tree and Ruby constant in the tree is
# resolved to answer a question only #include chains can decide. Measured on cpython (4,663 files, C beside Python), warm
# `--for`: 54 header questions cost 911M of 16.5G instructions (5.8%), almost all of it Python import resolution.
# graph.h's decl-to-def COST note had already ruled that whole-corpus resolve out for a per-selector path.
#
# The rule now: the adjacency for this question holds the edges of C-family and unclassified includers only. A chain
# ref.c -> ... -> header can leave that set only through an edge INTO a file of another include dialect, so when the
# narrowed build draws one such edge the whole-corpus adjacency is built instead (the answer is the same either way;
# only the work differs). RIPWIRE_STATS=1 prints the work as one deterministic stderr line:
#     [stats] header_static_adj scope=<cfamily|all> directives=<include directives resolved> of=<directives in the corpus>
#
# Arm classes: [P] positive — RED on the parent binary (integration/070-1121-local 5000f06af: it prints no such line);
# [C] control — holds on every binary (the answers are pinned from the parent); [N] near miss.
#   (A) ANSWER  [C] the F3 binds (test/verbfixcheck.sh [F3]) hold in a tree that also holds Python imports.
#   (B) COUNT   [P] the question resolved the 6 C directives of the fixture, of 9 in the corpus (3 are Python imports).
#   (C) ESCAPE  [P] a C file that #includes a file of another dialect (`#include "gen.py"`) widens the build to scope=all,
#               [C] and the answer there is the parent's, byte for byte (pinned below).
#   (D) REACH   [N] a tree whose only static is in a .c file asks no header question: no line at all (the adjacency is
#               still built on first use, never eagerly).
# This is a WORK-COUNT gate, not a timing gate: every number is a pure function of the fixture.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
DIR="$( mktemp -d )"; trap 'rm -rf "$DIR"' EXIT
fail=0
# every verdict is an if/else: a failed write of a PASS line must never print FAIL for an arm that passed (gateexitcheck G2)
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
has(){ if printf '%s' "$1" | grep -qF -- "$2"; then ok "$3"; else no "$3 — missing: $2"; fi; }
hasnt(){ if printf '%s' "$1" | grep -qF -- "$2"; then no "$3 — present: $2"; else ok "$3"; fi; }
body(){ printf '%s' "$1" | sed 's/^.*-->//'; }

echo "headerstaticadjcheck: BIN=$BIN"
[ -x "$BIN" ] || { echo "  FAIL  no ripwire binary at $BIN"; exit 1; }

# the F3 corpus of verbfixcheck.sh (written here; no file of this tree is read as a fixture), plus a Python package
mk_c(){
    mkdir -p "$1"
    cat >"$1/row.h" <<'C'
#ifndef ROW_H
#define ROW_H
static inline int row_cmp(const void *a, const void *b) { return a == b; }
#endif
C
    printf 'int vec_index(void *v, void *x, int (*cmp)(const void *, const void *));\n' >"$1/vec.h"
    printf '#include "row.h"\n' >"$1/table.h"
    printf '#include "row.h"\n#include "vec.h"\nint t1(void *v, void *x) { return vec_index(v, x, row_cmp); }\n' >"$1/t1.c"
    printf '#include "table.h"\n#include "vec.h"\nint t2(void *v, void *x) { return vec_index(v, x, row_cmp); }\n' >"$1/t2.c"
    printf '#include "vec.h"\nint t4(void *v, void *x) { return vec_index(v, x, row_cmp); }\n' >"$1/lone.c"
}
mk_py(){
    mkdir -p "$1/pkg"
    : >"$1/pkg/__init__.py"
    printf 'def base():\n    return 1\n' >"$1/pkg/b.py"
    printf 'from pkg import b\nimport pkg.b\n\ndef top():\n    return b.base()\n' >"$1/pkg/a.py"
    printf 'from pkg.a import top\n\ndef main():\n    return top()\n' >"$1/run.py"
}
mk_c "$DIR/mix"; mk_py "$DIR/mix"
mk_c "$DIR/esc"; mk_py "$DIR/esc"
printf '#include "run.py"\n#include "row.h"\n#include "vec.h"\nint t5(void *v, void *x) { return vec_index(v, x, row_cmp); }\n' >"$DIR/esc/gen.c"
mkdir -p "$DIR/src"
printf 'int vec_index(void *v, void *x, int (*cmp)(const void *, const void *));\n' >"$DIR/src/vec.h"
printf '#include "vec.h"\nstatic int row_cmp(const void *a, const void *b) { return 0; }\nint t3(void *v, void *x) { return vec_index(v, x, row_cmp); }\n' >"$DIR/src/other.c"
printf '#include "vec.h"\nint t4(void *v, void *x) { return vec_index(v, x, row_cmp); }\n' >"$DIR/src/lone.c"

# one run per tree: stdout is the answer, stderr carries the RIPWIRE_STATS line
run(){ ( cd "$DIR/$1" && RIPWIRE_STATS=1 "$BIN" . --no-cache --uses=row_cmp >"$DIR/$1.out" 2>"$DIR/$1.err" ); }
line(){ grep -F '[stats] header_static_adj' "$DIR/$1.err" || true; }

echo "[A] the answer in a tree that also holds Python imports"
run mix
a="$( body "$( cat "$DIR/mix.out" )" )"
has "$a" '<u role="value" p="t1.c:3"' "(A1) [C] a direct includer's value use binds the header static"
has "$a" '<u role="value" p="t2.c:3"' "(A2) [C] a transitive includer (t2.c -> table.h -> row.h) binds it too"
hasnt "$a" 'p="lone.c:' "(A3) [C] a file that includes no row.h binds nothing"

echo "[B] the work: C-family directives only"
l="$( line mix )"
has "$l" 'scope=cfamily' "(B1) [P] the question was answered from the C-family includers' adjacency"
has "$l" 'directives=6 of=9' "(B2) [P] 6 #include directives resolved, of the corpus's 9 (the 3 Python imports are not)"
if [ "$( printf '%s\n' "$l" | grep -c . )" = 1 ]; then ok "(B3) [P] exactly one line: the adjacency is built once per index"; else no "(B3) expected exactly one header_static_adj line, got: $l"; fi

echo "[C] an edge into another dialect widens the build"
run esc
l="$( line esc )"
has "$l" 'scope=all' "(C1) [P] gen.c's #include \"run.py\" leaves the C-family set: the whole-corpus adjacency answers"
a="$( body "$( cat "$DIR/esc.out" )" )"
has "$a" '<u role="value" p="gen.c:4"' "(C2) [C] gen.c binds the header static"
has "$a" '<u role="value" p="t2.c:3"' "(C3) [C] ... and so does the transitive includer"
hasnt "$a" 'p="lone.c:' "(C4) [C] ... and lone.c still does not"

echo "[D] no header static, no adjacency"
run src
l="$( line src )"
if [ -z "$l" ]; then ok "(D1) [N] a .c static asks no header question: no adjacency is built"; else no "(D1) a tree with no header static built the adjacency: $l"; fi
has "$( body "$( cat "$DIR/src.out" )" )" '<u role="value" p="other.c:3"' "(D2) [C] other.c's own static still binds its own use"

if xmllint --noout "$DIR/mix.out" 2>/dev/null && xmllint --noout "$DIR/esc.out" 2>/dev/null; then ok "(X) [C] well-formed XML"; else no "(X) xmllint rejects an answer"; fi

if [ "$fail" = 0 ]; then echo "headerstaticadjcheck: ALL PASS"; else echo "headerstaticadjcheck: FAIL"; fi
exit "$fail"
