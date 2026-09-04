#!/usr/bin/env bash
# externalvetocheck.sh — the EXTERNAL-NAME VETO (docs/EVALS.md "Phase 5", mechanism 1): a call whose name
# or receiver is provably bound OUTSIDE the indexed tree is refused instead of sprayed, counted in the
# header `external=N` (absent when 0), and recorded as a `C external` census row with no target.
#
#   test/externalvetocheck.sh                    # uses build/ripwire on test/extvetofix
#   RIPWIRE_BIN=asan/ripwire test/externalvetocheck.sh
#
# WHY THIS GATE EXISTS. On astropy-14365, 17 of the 24 disconfirmed S6-C locality pins were sites SCIP
# resolved to a builtin or another package: a bare `sum(…)` pinned to the caller's own `sum` METHOD (a
# target Python's name lookup can never reach), `np.dtype(…)` pinned to `Column::dtype` (the receiver is
# `import numpy as np`), `OrderedDict.__getitem__(…)` pinned to `Table::__getitem__`. A tie-break cannot
# decline to pin; the veto can, on three kinds of evidence — an import binding (a NEW ingest fact), the
# committed builtin/stdlib table in src/externalnames.h, and the absence of any definition evidence a bare
# call could legally reach (a module-level def, a nested def, an in-repo import, a local, or — C-family — a
# FREE symbol in the caller's file or its transitive includes).
#
# THE FIXTURE (test/extvetofix/): ext.py + own.py (Python), ext.cpp + ext.h + decl.cpp (C++). Arms:
#   (A) Rep.norm  -> bare `sum(…)`          builtin, no evidence          -> vetoed (was an S6-C pin, lpin="1")
#   (B) Rep.conv  -> `np.dtype(…)`          external import receiver      -> vetoed (was an S6-C pin)
#   (C) Rep.get   -> `OrderedDict.__getitem__(…)`  name from a stdlib module -> vetoed (was an S6-C pin)
#   (D) Rep.use   -> `helper(1)`            in-repo import evidence       -> edge to own.py::helper stays
#   (E) K.go      -> `sum([1])`             same-file module-level def    -> edge to own.py::sum stays
#   (F) free_fn   -> `find( 3 )`            C++ table, no free-symbol evidence -> vetoed (was a split)
#   (G) uses_decl -> `clamp( 1 )`           declared in the included ext.h -> edge to decl.cpp::clamp stays
#   (H) header `external=5` exactly, legend-defined; ABSENT on a veto-free corpus (test/lpinfix)
#   (I) --json carries "external":5
#   (J) determinism x2, xmllint
#
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
CORPUS="$ROOT/test/extvetofix"
CLEAN="$ROOT/test/lpinfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$CORPUS" ] || { echo "fixture missing: $CORPUS"; exit 2; }

echo "externalvetocheck: BIN=$BIN  CORPUS=$CORPUS"

"$BIN" "$CORPUS" --pin-census="$TMP/c.tsv" --no-cache >"$TMP/map.xml" 2>"$TMP/err" || { no "the map run exited non-zero"; sed 's/^/          /' "$TMP/err"; }
MAP="$( cat "$TMP/map.xml" )"
row(){ printf '%s' "$MAP" | tr '<' '\n' | grep "id=\"$1\"" | head -1; }
# the census C row for a (caller, callee): "<mech> <targets>"
crow(){ awk -F'\t' -v c="$1" -v n="$2" '$1=="C" && index($6, c"#")==1 && $7==n {print $2 "\t" $8; exit}' "$TMP/c.tsv"; }
# every census C row for a (caller, callee), mechanism column only
cmechs(){ awk -F'\t' -v c="$1" -v n="$2" '$1=="C" && index($6, c"#")==1 && $7==n {print $2}' "$TMP/c.tsv" | sort -u | tr '\n' ' '; }

vetoed(){ # $1 caller id prefix, $2 callee, $3 arm label
    local R; R="$( crow "$1" "$2" )"
    printf '%s' "$R" | grep -q '^external	' && ok "$3 $1 -> $2 is a C external row: '$R'" \
        || no "$3 $1 -> $2 is not an external row: '${R:-no row}'"
    [ "$( cmechs "$1" "$2" )" = "external " ] && ok "$3 no other mechanism row for $1 -> $2" \
        || no "$3 other rows exist for $1 -> $2: $( cmechs "$1" "$2" )"
    printf '%s' "$R" | awk -F'\t' '{ exit ($2 == "" ? 0 : 1) }' && ok "$3 the external row names NO target" \
        || no "$3 the external row still names a target: '$R'"
}

# ── (A) a bare builtin call to a name the file's classes also define ─────────────────────────────
vetoed 'ext.py::Rep::norm' sum '(A)'
printf '%s' "$( row 'ext.py::Rep::norm' )" | grep -q 'lpin=' && no "(A) Rep::norm still carries lpin= — the S6-C pin was not refused" \
    || ok "(A) no lpin= on Rep::norm"

# ── (B) a named-receiver call through an EXTERNAL import binding ─────────────────────────────────
vetoed 'ext.py::Rep::conv' dtype '(B)'

# ── (C) a class-name receiver imported from a stdlib module ──────────────────────────────────────
vetoed 'ext.py::Rep::get' __getitem__ '(C)'

# ── (D) control: an IN-REPO import binding is evidence ───────────────────────────────────────────
R="$( crow 'ext.py::Rep::use' helper )"
printf '%s' "$R" | grep -q 'own.py::helper' && ! printf '%s' "$R" | grep -q '^external	' \
    && ok "(D) Rep::use -> helper keeps its edge to own.py::helper: '$R'" \
    || no "(D) Rep::use -> helper lost its edge or was vetoed: '${R:-no row}'"

# ── (E) control: a same-file MODULE-LEVEL def of a builtin name is evidence ──────────────────────
R="$( crow 'own.py::K::go' sum )"
printf '%s' "$R" | grep -q 'own.py::sum' && ! printf '%s' "$R" | grep -q '^external	' \
    && ok "(E) K::go -> sum keeps its edge to the module-level own.py::sum: '$R'" \
    || no "(E) K::go -> sum lost its edge or was vetoed: '${R:-no row}'"

# ── (F) C++: a bare std-name call from a free function, the only same-name symbols are methods ───
vetoed 'ext.cpp::free_fn' find '(F)'
# free_fn is unscoped, so its row carries no id= (emitted only when it disambiguates) — match on n= instead.
printf '%s' "$MAP" | tr '<' '\n' | grep 'n="free_fn"' | head -1 | grep -q 'amb=' && no "(F) free_fn still carries amb= — the split was not refused" \
    || ok "(F) no amb= on free_fn"

# ── (G) control: a FREE declaration in an included header is evidence ────────────────────────────
R="$( crow 'ext.cpp::uses_decl' clamp )"
printf '%s' "$R" | grep -q 'decl.cpp::clamp' && ! printf '%s' "$R" | grep -q '^external	' \
    && ok "(G) uses_decl -> clamp keeps its edge to decl.cpp::clamp: '$R'" \
    || no "(G) uses_decl -> clamp lost its edge or was vetoed: '${R:-no row}'"

# ── (H) the header counter is exact, legend-defined, and absent when zero ────────────────────────
HDR="$( printf '%s' "$MAP" | grep -o '<!-- files=[^>]*-->' | head -1 )"
printf '%s' "$HDR" | grep -q ' external=5 ' && ok "(H) header external=5 (A, B, C, F + mrowalkcheck's L)" \
    || no "(H) header external= is not 5: $( printf '%s' "$HDR" | grep -o 'external=[0-9]*' || echo absent )"
printf '%s' "$MAP" | head -1 | grep -q 'hdr:external=' && ok "(H) the legend defines hdr:external=" \
    || no "(H) the legend does not define hdr:external="
"$BIN" "$CLEAN" --no-cache >"$TMP/clean.xml" 2>/dev/null
# the STATS comment only — the legend line defines `hdr:external=` on every map, so a whole-map grep would false-positive
grep -o '<!-- files=[^>]*-->' "$TMP/clean.xml" | head -1 | grep -q ' external=' && no "(H) external= present on a veto-free corpus ($CLEAN) — must be absent when 0" \
    || ok "(H) external= absent on a veto-free corpus"

# ── (I) the JSON twin ────────────────────────────────────────────────────────────────────────────
"$BIN" "$CORPUS" --json --no-cache >"$TMP/map.json" 2>/dev/null
grep -q '"external":5,' "$TMP/map.json" && ok '(I) --json carries "external":5' \
    || no "(I) --json external gauge missing/wrong: $( grep -o '"external":[0-9]*' "$TMP/map.json" || echo absent )"
"$BIN" "$CLEAN" --json --no-cache >"$TMP/clean.json" 2>/dev/null
grep -q '"external"' "$TMP/clean.json" && no '(I) "external" present in --json on a veto-free corpus' \
    || ok '(I) "external" absent from --json on a veto-free corpus'

# ── (J) determinism + well-formedness ────────────────────────────────────────────────────────────
"$BIN" "$CORPUS" --pin-census="$TMP/c2.tsv" --no-cache >"$TMP/map2.xml" 2>/dev/null
cmp -s "$TMP/map.xml" "$TMP/map2.xml" && cmp -s "$TMP/c.tsv" "$TMP/c2.tsv" && ok "(J) map + census byte-identical across two runs" \
    || no "(J) map or census differs between two runs"
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/map.xml" 2>/dev/null && ok "(J) xmllint clean" || no "(J) xmllint rejected the map"
fi

[ "$fail" = 0 ] && echo "externalvetocheck: PASS" || echo "externalvetocheck: FAIL"
exit "$fail"
