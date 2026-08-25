#!/usr/bin/env bash
# nestedqualcheck.sh — C++ out-of-line, QUALIFIED nested class/struct definitions extract as symbols
# for their own bare name (candhead-ugrep lane, N11/N12, 2026-08-25).
#
#   test/nestedqualcheck.sh                          # uses build/ripwire on test/nestedqualfix
#   RIPWIRE_BIN=asan/ripwire test/nestedqualcheck.sh
#
# THE DEFECT THIS PINS (docs/EVALS.md, "N11/N12 — the ugrep extraction gap"; upstream: the anchor-body
# and def-over-decl lane reports, both disclaiming this as a separate, not-yet-touched extraction gap).
# The upstream C++ tags query captures a class/struct definition only when its OWN name is a bare
# type_identifier (`class Foo { ... };`). A nested type DEFINED OUT OF LINE with its qualifier written
# out — `class Outer::Inner : Base { ... };`, the Pimpl idiom rocksdb's own tree uses ~29 times
# (BlockBasedTable::IndexReaderCommon, AutoHyperClockTable::ChainRewriteLock, VersionBuilder::Rep, …) —
# writes its name as a qualified_identifier instead, so neither upstream pattern (class_specifier nor
# struct_specifier) matches: the class ITSELF is dropped at extraction. No symbol, no --skipped row, no
# floor. Its MEMBERS (a constructor, whose own name is unqualified inside the class body) already
# extracted fine and already scoped correctly to "Outer::Inner" — ingest.cpp's enclosingScopeOf walk is
# structural and reads the class_specifier's name field AS WRITTEN whether or not the tags query ever
# captured that node as a symbol. Only the class's OWN bare name resolved to nothing: measured on
# ugrep's reflex/input.h, `--for="dos_streambuf"` ranked a constructor and a same-named, wrongly-merged
# forward declaration but never `class BufferedInput::dos_streambuf : public std::streambuf { ... }`
# itself — absent, not merely low-ranked.
#
# THE FIX: queries/cpp/tags.scm gains `(class_specifier name: (qualified_identifier) @name body:(_))`
# and the struct_specifier twin, mirroring the out-of-line METHOD pattern already in that file. No new
# C++ code: ingest.cpp's cppDefNameReseat (descend to the innermost identifier for the bare NAME) and
# the canonical-scope rule (qualifierOf first, enclosingScopeOf only when that is empty, for the SCOPE)
# are both already generic over every C++ definition capture — kParserVer 72 -> 73.
#
# ARMS
#   (a) THE GOLD ITSELF — --for=Inner ranks a `cls` candidate whose id is exactly "Outer::Inner" (not
#       "Outer::Inner::Inner", the constructor; not "Inner::Inner", the bodyless in-class forward-decl
#       collision) at its real defining line.
#   (b) THE STRUCT TWIN — --for=SInner, same shape, for struct_specifier.
#   (c) THE BODY RIDES ALONG — the plain bundle's <bodies> now carries the class's own CDATA, not just
#       the constructor's.
#   (d) DECOY INVARIANCE — Decoy also forward-declares a nested "Inner" but never defines one out of
#       line anywhere in this fixture; no candidate's id may ever read "...Decoy::Inner" (scoped to
#       Decoy). A rule that merges same-named nested forward declarations across unrelated enclosing
#       types by construction, rather than reading the qualifier written at the DEFINITION site, goes
#       red here.
#   (e) MEMBER SCOPE INVARIANCE — the constructor's own id ("Outer::Inner::Inner") is BYTE-IDENTICAL
#       before and after: this fix adds a symbol, it does not touch how an already-correct member scopes.
#   (f) ROUTE SCOPE — --for=Inner takes the name-exact route (sanity: the arms above measure the
#       ranker this fix touches).
#   (g) SYMBOL-COUNT DELTA — exactly +2 symbols over the whole fixture (the two out-of-line
#       definitions; nothing else moves).
#   (h) determinism — two runs byte-identical.
#
# The fixture is copied to a tmp dir OUTSIDE any git repo and scanned via a RELATIVE path, so no churn
# or co-change attribute and no absolute path can reach the assertions.
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "nestedqualcheck: BIN=$BIN"

mkdir -p "$TMP/nestedqualfix"
cp "$ROOT"/test/nestedqualfix/*.hpp "$TMP/nestedqualfix/"
cd "$TMP"

# candidate ids, one per line, rank order: "<kind> <line> <id>"
cands(){ "$BIN" nestedqualfix --for="$1" --format=candidates --top-k="$2" 2>/dev/null \
    | tr '>' '\n' | sed -n 's/.*<cand r="[0-9]*" s="[^"]*" n="[^"]*" id="\([^"]*\)" k="\([^"]*\)" p="[^"]*" l="\([0-9]*\)".*/\2 \3 \1/p' \
    | sed 's#nestedqualfix/##'; }

# ── (a) THE GOLD ITSELF ───────────────────────────────────────────────────────────────────────────
G="$( cands Inner 10 )"
gold_line="$( printf '%s\n' "$G" | awk '$1=="cls" && $3=="defs.hpp::Outer::Inner" {print $2; exit}' )"
[ "$gold_line" = "20" ] \
    && ok "--for=Inner ranks a cls candidate id=defs.hpp::Outer::Inner at its real line (20)" \
    || no "no cls candidate with id=defs.hpp::Outer::Inner:20 in the --for=Inner candidate list — got:\n$G"

# constructor and collision-forward-decl rows must still both be present (this is an ADDITION, not a
# replacement of anything that already worked)
ctor_line="$( printf '%s\n' "$G" | awk '$1=="fn" && $3=="defs.hpp::Outer::Inner::Inner" {print $2; exit}' )"
[ "$ctor_line" = "23" ] \
    && ok "the constructor Outer::Inner::Inner is still ranked (line 23) — an addition, not a replacement" \
    || no "the constructor row moved or vanished — got ctor_line=$ctor_line"

# ── (b) THE STRUCT TWIN ───────────────────────────────────────────────────────────────────────────
S="$( cands SInner 10 )"
sgold_line="$( printf '%s\n' "$S" | awk '$1=="cls" && $3=="defs.hpp::SOuter::SInner" {print $2; exit}' )"
[ "$sgold_line" = "31" ] \
    && ok "--for=SInner ranks a cls candidate id=defs.hpp::SOuter::SInner at its real line (31)" \
    || no "no cls candidate with id=defs.hpp::SOuter::SInner:31 in the --for=SInner candidate list — got:\n$S"

# ── (c) THE BODY RIDES ALONG ──────────────────────────────────────────────────────────────────────
"$BIN" nestedqualfix --for=Inner >"$TMP/lens" 2>/dev/null
bodykinds="$( tr '>' '\n' <"$TMP/lens" | sed -n 's/.*<b t="\([^"]*\)" l="\([0-9]*\)" p="\([^"]*\)".*/\1:\2/p' | sort )"
printf '%s\n' "$bodykinds" | grep -qx "cls:20" \
    && ok "the class's own body (cls at line 20) rides in <bodies>, not just the constructor" \
    || no "<bodies> never carries the class's own definition — got:\n$bodykinds"

# ── (d) DECOY INVARIANCE ──────────────────────────────────────────────────────────────────────────
if printf '%s\n' "$G" | grep -q "Decoy::Inner"; then
    no "a candidate's id names Decoy::Inner — Decoy::Inner is never defined out of line anywhere in this fixture"
else
    ok "no candidate ever attributes a definition to Decoy::Inner (never defined out of line)"
fi

# ── (e) MEMBER SCOPE INVARIANCE ───────────────────────────────────────────────────────────────────
# Already checked structurally by (a)'s ctor_line assertion above (id="defs.hpp::Outer::Inner::Inner"
# unchanged); restated as its own arm because it is the registered invariance criterion, not incidental.
[ "$ctor_line" = "23" ] \
    && ok "member scope invariance: Outer::Inner::Inner is untouched by this fix (restated, see above)" \
    || no "member scope invariance failed (see the constructor assertion above)"

# ── (f) ROUTE SCOPE ────────────────────────────────────────────────────────────────────────────────
"$BIN" nestedqualfix --for=Inner 2>/dev/null | grep -q 'routed: name-exact' \
    && ok "--for=Inner takes the name-exact route (the route this fix's ranking arms measure)" \
    || no "--for=Inner no longer routes name-exact"

# ── (g) SYMBOL-COUNT DELTA ────────────────────────────────────────────────────────────────────────
symcount="$( "$BIN" nestedqualfix 2>/dev/null | grep -o 'symbols=[0-9]*' | head -1 | tr -dc 0-9 )"
[ "$symcount" = "12" ] \
    && ok "fixture symbol count is exactly 12 (10 pre-fix + the two out-of-line definitions)" \
    || no "fixture symbol count is $symcount, expected 12 — an extraction change touched more than the two golds"

# ── (h) determinism ───────────────────────────────────────────────────────────────────────────────
"$BIN" nestedqualfix --for=Inner >"$TMP/d1" 2>/dev/null
"$BIN" nestedqualfix --for=Inner >"$TMP/d2" 2>/dev/null
cmp -s "$TMP/d1" "$TMP/d2" \
    && ok "deterministic: two --for=Inner runs byte-identical" \
    || no "two --for=Inner runs differ"

[ "$fail" -eq 0 ] && echo "nestedqualcheck: ALL PASS" || echo "nestedqualcheck: FAILURES"
exit "$fail"
