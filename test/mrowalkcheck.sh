#!/usr/bin/env bash
# mrowalkcheck.sh — the receiver MRO WALK (docs/EVALS.md "Phase 5", mechanism 2): Rule 1 generalised to
# the enclosing class's bases, and the new `super()` receiver kind that resolves through the bases ONLY
# (a miss is a veto — the MRO left the indexed tree).
#
#   test/mrowalkcheck.sh                    # uses build/ripwire on test/extvetofix
#   RIPWIRE_BIN=asan/ripwire test/mrowalkcheck.sh
#
# WHY THIS GATE EXISTS. Ingest classified a `super()` receiver `RecvKind::None`, so `super().m()` reached
# the ladder as a BARE call and the S6-C prior handed it to the caller's OWN class — the one class `super()`
# by definition skips (astropy: `super().__new__` in `MaskedNDArray` pinned to `MaskedNDArray::__new__`,
# SCIP `Masked::__new__`; four `super().__init__`-shaped sites whose bases are stdlib/numpy pinned to the
# caller's class, SCIP `@external`). And Rule 1's bare C-family `m()` stopped at the enclosing class, so a
# method inherited from a base fell into the same-name spray.
#
# THE FIXTURE (test/extvetofix/, shared with externalvetocheck.sh). Arms:
#   (K) Leaf.run  -> `super().run()`, Leaf(Mid), Mid(Base), only Base defines run -> Base::run, receiver-rule
#                  (was NO edge: the pin landed the caller's own Leaf::run, a self-loop, dropped)
#   (L) Ext.reset -> `super().__init__()` in Ext(dict)  -> vetoed, C external (was a unique edge to Other::__init__)
#   (M) Grid::go  -> bare `size()` in Grid : Buf         -> Buf::size, receiver-rule (was a split, amb="1")
#   (N) Ext.reset -> `self.keys()`                       -> no row before or after (the walk never invents)
#   (O) determinism x2
#
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
CORPUS="$ROOT/test/extvetofix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$CORPUS" ] || { echo "fixture missing: $CORPUS"; exit 2; }

echo "mrowalkcheck: BIN=$BIN  CORPUS=$CORPUS"

"$BIN" "$CORPUS" --pin-census="$TMP/c.tsv" --no-cache >"$TMP/map.xml" 2>"$TMP/err" || { no "the map run exited non-zero"; sed 's/^/          /' "$TMP/err"; }
MAP="$( cat "$TMP/map.xml" )"
row(){ printf '%s' "$MAP" | tr '<' '\n' | grep "id=\"$1\"" | head -1; }
crow(){ awk -F'\t' -v c="$1" -v n="$2" '$1=="C" && index($6, c"#")==1 && $7==n {print $2 "\t" $8; exit}' "$TMP/c.tsv"; }
cmechs(){ awk -F'\t' -v c="$1" -v n="$2" '$1=="C" && index($6, c"#")==1 && $7==n {print $2}' "$TMP/c.tsv" | sort -u | tr '\n' ' '; }

# ── (K) `super().run()` walks Leaf -> Mid -> Base ────────────────────────────────────────────────
R="$( crow 'ext.py::Leaf::run' run )"
printf '%s' "$R" | grep -q '^receiver-rule	' && ok "(K) Leaf::run -> super().run() is receiver-rule: '$R'" \
    || no "(K) Leaf::run -> run is not receiver-rule: '${R:-no row}'"
printf '%s' "$R" | grep -q 'ext.py::Base::run' && ! printf '%s' "$R" | grep -q 'ext.py::Leaf::run' \
    && ok "(K) the target is Base::run alone (never the caller's own Leaf::run)" \
    || no "(K) targets are not exactly Base::run: '${R:-no row}'"

# ── (L) `super().__init__()` with no in-repo base defining it is a VETO, not a pin ───────────────
R="$( crow 'ext.py::Ext::reset' __init__ )"
printf '%s' "$R" | grep -q '^external	' && ok "(L) Ext::reset -> super().__init__() is a C external row: '$R'" \
    || no "(L) Ext::reset -> __init__ is not an external row: '${R:-no row}'"
[ "$( cmechs 'ext.py::Ext::reset' __init__ )" = "external " ] && ok "(L) no other mechanism row for Ext::reset -> __init__" \
    || no "(L) other rows exist for Ext::reset -> __init__: $( cmechs 'ext.py::Ext::reset' __init__ )"
grep -F 'ext.py::Ext::reset' "$TMP/c.tsv" | grep -q 'ext.py::Other::__init__' && no "(L) Ext::reset still reaches Other::__init__" \
    || ok "(L) Ext::reset never reaches the unrelated Other::__init__"

# ── (M) C++: a bare call inside a method walks to the base's definition ──────────────────────────
R="$( crow 'ext.cpp::Grid::go' size )"
printf '%s' "$R" | grep -q '^receiver-rule	' && ok "(M) Grid::go -> size() is receiver-rule: '$R'" \
    || no "(M) Grid::go -> size is not receiver-rule: '${R:-no row}'"
printf '%s' "$R" | grep -q 'ext.cpp::Buf::size' && ! printf '%s' "$R" | grep -q 'ext.cpp::Other2::size' \
    && ok "(M) the target is Buf::size alone" \
    || no "(M) targets are not exactly Buf::size: '${R:-no row}'"
printf '%s' "$( row 'ext.cpp::Grid::go' )" | grep -q 'amb=' && no "(M) Grid::go still carries amb=" \
    || ok "(M) no amb= on Grid::go"

# ── (N) control: the walk never invents a target ─────────────────────────────────────────────────
[ -z "$( crow 'ext.py::Ext::reset' keys )" ] && ok "(N) no row for Ext::reset -> keys (no in-repo def anywhere)" \
    || no "(N) a row appeared for Ext::reset -> keys: '$( crow 'ext.py::Ext::reset' keys )'"

# ── (O) determinism ──────────────────────────────────────────────────────────────────────────────
"$BIN" "$CORPUS" --pin-census="$TMP/c2.tsv" --no-cache >"$TMP/map2.xml" 2>/dev/null
cmp -s "$TMP/map.xml" "$TMP/map2.xml" && cmp -s "$TMP/c.tsv" "$TMP/c2.tsv" && ok "(O) map + census byte-identical across two runs" \
    || no "(O) map or census differs between two runs"

[ "$fail" = 0 ] && echo "mrowalkcheck: PASS" || echo "mrowalkcheck: FAIL"
exit "$fail"
