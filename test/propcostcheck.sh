#!/usr/bin/env bash
# propcostcheck.sh — gate for Q5b: DSM propagation cost on --arch's <metrics> element.
#
# propagation_cost = density of the transitive closure of the file→file dependency graph
#   = ( Σ_i |reachable(i)| ) / N²   (reachable INCLUDES i itself — MacCormack's unit-diagonal visibility
#     matrix), the fraction of the system reachable from an average file. A VALIDATED coupling form.
#     Reported number on --arch, NEVER a gate (the arch exit code is owned
#     by the layer/path-rule violations, unaffected by this attribute).
#
# HAND-COMPUTED on test/archmetricsfix/ (9 files; resolveIncludeAdj resolves includes by unique basename):
#   file→file edges (adj[src] = files src includes):
#     app.cpp  → math.h, shape.h        math.cpp → math.h
#     a.cpp    → a.h, b.h               b.cpp    → b.h, a.h
#     (math.h, shape.h, util.cpp, a.h, b.h include nothing)
#   reachable-set sizes (incl. self):
#     app.cpp=3  math.cpp=2  math.h=1  shape.h=1  util.cpp=1  a.cpp=3  a.h=1  b.cpp=3  b.h=1
#   Σ = 16 ,  N=9 ,  N²=81  →  16/81 = 0.197531… → "0.198" at the serializer's fixed 3-decimal precision.
#   (Note: a.h/b.h include nothing, so the file graph is ACYCLIC even though the DIRECTORY projection has
#    the ringA↔ringB module cycle — propagation cost is a FILE-level closure, hence 0.198 not higher.)
#
# The fixed 3dp formatting makes the emitted string byte-identical run-to-run (a report value, not a rank
# input → no tolerance band; the det-gate holds on the exact string).
#
# Degenerate: N≤1 → the sole file reaches only itself → Σ=1, N²=1 → 1.000 (documented unit-diagonal).
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/propcostcheck.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow repo-relative RIPWIRE_BIN
FIX="$ROOT/test/archmetricsfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
[ -d "$FIX" ] || { echo "no test/archmetricsfix dir — fixture missing"; exit 2; }
[ -f "$FIX/sibling.arch" ] || { echo "no test/archmetricsfix/sibling.arch — fixture config missing"; exit 2; }
cd "$ROOT"

echo "propcostcheck: BIN=$BIN  CORPUS=test/archmetricsfix"

# full --arch output; extract the propagation_cost attribute value from <metrics …>
arch(){ perl -e 'alarm 20; exec @ARGV' "$BIN" "$1" --arch="$2" --no-cache 2>/dev/null; }
pc(){ printf '%s' "$1" | tr '>' '\n' | grep '<metrics ' | grep -oE 'propagation_cost="[^"]*"' | head -1 | sed -E 's/.*"([^"]*)".*/\1/'; }

OUT="$( arch "$FIX" "$FIX/sibling.arch" )"
GOT="$( pc "$OUT" )"

# ── 1) hand-computed value: Σ|reachable(i)|/N² = 16/81 = 0.198 (3dp) ──────────────────────────────────
# To MUTATION-TEST this assertion, change EXPECT below to any other value (e.g. 0.199) → this check FAILS.
EXPECT="0.198"
[ "$GOT" = "$EXPECT" ] \
    && ok "propagation_cost = $EXPECT (hand-computed 16/81 transitive-closure density on archmetricsfix)" \
    || no "propagation_cost expected $EXPECT, got '$GOT' (closure density / formatting wrong)"

# ── 2) the attribute is PRESENT and well-formed (an emitted number, never a gate) ────────────────────
printf '%s' "$OUT" | grep -q 'propagation_cost="[0-9]\.[0-9][0-9][0-9]"' \
    && ok "propagation_cost present with fixed 3-decimal formatting" \
    || no "propagation_cost missing or not 3-decimal formatted"

# ── 3) determinism — the emitted value is byte-identical across two runs ──────────────────────────────
GOT2="$( pc "$( arch "$FIX" "$FIX/sibling.arch" )" )"
[ "$GOT" = "$GOT2" ] \
    && ok "deterministic (propagation_cost byte-identical across two runs)" \
    || no "non-deterministic propagation_cost ('$GOT' vs '$GOT2')"

# ── 4) N≤1 degenerate case → 1.000 (sole file reaches only itself; no divide-by-zero) ─────────────────
mkdir -p "$TMP/solo"
printf 'int main(){ return 0; }\n' > "$TMP/solo/only.cpp"
printf 'deny path nope -> nope\n' > "$TMP/degen.arch"
DGOT="$( pc "$( arch "$TMP/solo" "$TMP/degen.arch" )" )"
[ "$DGOT" = "1.000" ] \
    && ok "N==1 degenerate → propagation_cost=1.000 (unit-diagonal; no divide-by-zero)" \
    || no "N==1 case expected 1.000, got '$DGOT'"

# ── 5) it is NOT a gate: the arch exit code is owned by violations, not by this number ────────────────
# archmetricsfix + sibling.arch has 4 real violations → exit 2 regardless of propagation_cost.
perl -e 'alarm 20; exec @ARGV' "$BIN" "$FIX" --arch="$FIX/sibling.arch" --no-cache >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] \
    && ok "propagation_cost is descriptive only (arch exit still driven by violations: exit $rc)" \
    || no "unexpected arch exit $rc (propagation_cost must not affect the exit code)"

# ── 6) XML well-formed (G4) — the <metrics> element carrying the new attribute ────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$OUT" | xmllint --noout - 2>/dev/null && ok "xml well-formed (arch + metrics + propagation_cost)" || no "xml malformed"
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

# ── §P9.4: files that CANNOT participate in the #include/import graph (.md/.json — no import syntax at ──
# all) must not dilute --deps <health>'s nccd/acd nor --arch's propagation_cost. Both must be computed
# over dependency-capable files only, with the SAME denominator.
# archmetricsfix (9 C-family files) has a hand-computed propagation_cost = 16/81 = 0.198 (see the header
# comment above) and a hand-computed CCD; copy it and add TWO non-capable files with no edges (a .md and a
# .json) — if they leaked into N, both numbers would be diluted toward a LARGER N (0.198 * 81/121 = 0.132,
# CCD/N would drop too). They must not move at all: excluding non-capable files means N stays 9.
#
# The .sh that used to be one of these two MOVED at kParserVer 81 — Bash `source`/`.` is now a captured
# directive and .sh is dependency-capable — so it is no longer a valid negative control and has become the
# POSITIVE one below. .md is still excluded on purpose (it mints doc→doc link edges but a README that
# links twelve designs is not twelve files of change amplification — see lintrules.h::dependencyCapable);
# .json has no file-level import at all.
DCAP="$TMP/depcap"
cp -R "$FIX" "$DCAP"
printf '# notes\n\nnothing to see here\n'  > "$DCAP/README.md"
printf '{ "note": "not a dependency" }\n'  > "$DCAP/data.json"

DEPS_DCAP="$( "$BIN" "$DCAP" --deps --no-cache 2>/dev/null )"
printf '%s' "$DEPS_DCAP" | grep -qE '<health files="11"[^>]*\bdep_files="9"' \
    && ok "P9.4: <health> discloses BOTH files=11 (corpus, incl. .md/.json) and dep_files=9 (denominator)" \
    || no "P9.4: <health> files=/dep_files= wrong or missing: $( printf '%s' "$DEPS_DCAP" | grep -o '<health[^/]*/>' )"
printf '%s' "$DEPS_DCAP" | grep -qE '<health[^>]*\bnccd="0\.66"' \
    && ok "P9.4: --deps nccd unmoved by the two non-capable files (still computed over dep_files=9)" \
    || no "P9.4: --deps nccd shifted — non-capable files leaked into the denominator: $( printf '%s' "$DEPS_DCAP" | grep -o '<health[^/]*/>' )"

ARCH_DCAP="$( "$BIN" "$DCAP" --arch="$DCAP/sibling.arch" --no-cache 2>/dev/null )"
DCAP_PC="$( pc "$ARCH_DCAP" )"
[ "$DCAP_PC" = "$EXPECT" ] \
    && ok "P9.4: --arch propagation_cost unmoved by the two non-capable files (still $EXPECT, same N as --deps)" \
    || no "P9.4: --arch propagation_cost shifted to '$DCAP_PC' (expected unchanged $EXPECT) — denominators disagree"

# ── POSITIVE CONTROL for the same denominator (kParserVer 81) — without it, the three assertions above
# pass just as well on a build where dependencyCapable() returned false for EVERYTHING. Add ONE .sh with
# no edges to the same 9-file fixture: it must now COUNT, so dep_files goes 9 -> 10 and propagation_cost
# becomes 17/100 = 0.170 (the .sh seeds a root that reaches only itself: +1 numerator, +19 denominator).
# Both numbers moving together is the "same N" claim proven in the direction that can actually fail.
DCAPSH="$TMP/depcapsh"
cp -R "$FIX" "$DCAPSH"
printf '#!/usr/bin/env bash\necho hi\n' > "$DCAPSH/deploy.sh"

DEPS_SH="$( "$BIN" "$DCAPSH" --deps --no-cache 2>/dev/null )"
printf '%s' "$DEPS_SH" | grep -qE '<health files="10"[^>]*\bdep_files="10"' \
    && ok "P9.4 positive: a .sh is dependency-CAPABLE at parser version 81 — dep_files=10 of files=10" \
    || no "P9.4 positive: the .sh did not join the denominator: $( printf '%s' "$DEPS_SH" | grep -o '<health[^/]*/>' )"
SH_PC="$( pc "$( "$BIN" "$DCAPSH" --arch="$DCAPSH/sibling.arch" --no-cache 2>/dev/null )" )"
[ "$SH_PC" = "0.170" ] \
    && ok "P9.4 positive: --arch propagation_cost moved with it (17/100 = 0.170, same N as --deps)" \
    || no "P9.4 positive: propagation_cost is '$SH_PC', expected 0.170 — the two denominators disagree"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
