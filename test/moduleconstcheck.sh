#!/usr/bin/env bash
# moduleconstcheck.sh — const-qualified module-constant extraction gate (the kParserVer family).
#
# WHY (2026-08-12 history mine, 114 914 tool calls): 613 of 2 870 symbol-name lookups (21.4%) are
# constant-shaped, and the repo's own version-pinning constants were unfindable by its own tool —
# `--for=kParserVer` and `--for=kIngestParserVerMirror` returned weak="1" with `.codex-plugin/
# plugin.json` at rank 1, and `--uses` on those names reported defs="0". Mechanism: r3 q10's
# @definition.constant patterns capture every initialized module-scope C/C++ binding but the
# SCREAMING_SNAKE gate drops every non-SCREAMING name — and `constexpr`/`const`-qualified constants
# in this tree are k-camel by house convention. The same recon hole was independently flagged by the
# headroom competitor round ("module-constant indexing gap").
#
# THE FIX THIS GATE PINS: in the C family (Lang::Cpp + Lang::C) a const/constexpr/constinit
# type_qualifier on an INITIALIZED module-scope declaration is keyword evidence — the Rust
# const_item rationale, already applied to CUDA `__constant__` — so those keep CASE-BLIND. Mutable
# globals stay behind the SCREAMING gate. Class-static const/constexpr members with an in-class
# initializer (a new field_declaration capture; no pattern existed at ALL pre-fix, even SCREAMING)
# keep under a static+const ingest gate. Probed-and-DEFERRED, pinned absent below: enumerators
# (>=5000 capture-cap hits on a 2 377-file private validation tree — a corpus blow-up needing its own round) and TS/JS
# non-SCREAMING top-level consts (r3 q10 pinned policy — constcheck arm 3 asserts retryBudget stays
# unindexed; relaxing it is a measured behavior change, not a rider). Python/Rust/Go were probed
# case-blind already (2026-08-12 probe table) — no gap, pinned unchanged here.
#
# RED-BEFORE-FIX: arms tagged [RED] below fail against the pre-fix binary (verified at b74783e).
#
# Usage:
#   test/moduleconstcheck.sh
#   RIPWIRE_BIN=asan/ripwire test/moduleconstcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/moduleconstfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }

echo "moduleconstcheck: BIN=$BIN  FIX=$FIX"

MAP="$TMP/map.xml"
$BIN "$FIX" --no-cache >"$MAP" 2>"$TMP/map.err" || { no "default map exited non-zero: $( cat "$TMP/map.err" )"; exit 1; }

command -v xmllint >/dev/null 2>&1 && { xmllint --noout "$MAP" && ok "map passes xmllint --noout" || no "map fails xmllint"; }

# presence guard (CONTRIBUTING §2: assert the probe target exists before asserting the property)
grep -q 'n="mcConsumeAll"' "$MAP" || { no "presence guard: fixture parse produced no mcConsumeAll fn — gate cannot observe its subject"; exit 1; }

has_var(){ grep -q "t=\"var\" n=\"$1\"" "$MAP"; }
has_any(){ grep -q "n=\"$1\"" "$MAP"; }

# ── 1. [RED] C++ module-scope const-qualified camel constants become t="var" ───────────────────
for sym in kMcTuConstexpr kMcTuConstPtr kMcTuStaticConst \
           kMcNsConstexpr kMcNsInlineConstexpr kMcNsPlainConst kMcNsConstinit; do
    has_var "$sym" && ok "extracted t=\"var\": $sym" || no "MISSING t=\"var\" def: $sym"
done

# ── 2. [RED] class-static const/constexpr members with in-class initializers ───────────────────
for sym in kMcClassConstexpr MC_CLASS_SCREAM kMcClassConstInt; do
    has_var "$sym" && ok "extracted class-static: $sym" || no "MISSING class-static def: $sym"
done

# ── 3. [RED] C file-scope const-qualified camel constants ──────────────────────────────────────
for sym in k_mc_file_buf_bytes k_mc_file_default_name; do
    has_var "$sym" && ok "extracted C const: $sym" || no "MISSING C const def: $sym"
done

# ── 4. scope negatives: the fix must not index mutables, locals, or per-instance fields ────────
for sym in mcMutableCamelGlobal mc_file_mutable kMcLocalConstexpr mcMemberDefaultInit mcMemberConstField; do
    has_any "$sym" && no "over-capture: '$sym' must stay unindexed" || ok "unindexed as required: $sym"
done

# ── 5. deferred families stay honestly absent (each deferral is a recorded probe verdict) ──────
for sym in kMcEnumRed kMcEnumGreen MC_ENUM_SCREAM kMcTsCamel kMcJsCamel; do
    has_any "$sym" && no "deferred family leaked into the index: '$sym'" || ok "deferred stays absent: $sym"
done

# ── 6. no-gap languages pinned unchanged (probed case-blind pre-fix) ───────────────────────────
for sym in MC_PY_UPPER mc_py_lower MC_RS_SCREAM kMcRsCamel McGoCamel MC_TS_SCREAM MC_JS_SCREAM; do
    has_var "$sym" && ok "existing behavior pinned: $sym" || no "regressed existing capture: $sym"
done

# ── 7. [RED] decoy separation: same name, two files, two symbols (pathQualifiedKey era) ────────
decoyCount="$( grep -o 'n="kMcSameDecoy"' "$MAP" | wc -l | tr -d ' ' )"
[ "$decoyCount" = "2" ] \
    && ok "kMcSameDecoy defined in two files stays two symbols" \
    || no "kMcSameDecoy decoy count is $decoyCount, want 2 (cross-file fold or miss)"

# ── 8. [RED] --for on a camel constant: rank 1, non-weak ───────────────────────────────────────
FOR_OUT="$TMP/for.xml"
$BIN "$FIX" --no-cache --for="kMcNsConstexpr" >"$FOR_OUT" 2>/dev/null
grep -q 'weak="1"' "$FOR_OUT" && no "--for=kMcNsConstexpr still weak=\"1\"" || ok "--for=kMcNsConstexpr not weak"
firstRanked="$( grep -o '<d [^>]*' "$FOR_OUT" | head -1 | grep -o ' n="[^"]*"' | head -1 | sed 's/ n="\(.*\)"/\1/' )"
[ "$firstRanked" = "kMcNsConstexpr" ] \
    && ok "--for=kMcNsConstexpr lands the constant at rank 1" \
    || no "--for=kMcNsConstexpr rank 1 is '${firstRanked:-<none>}', want kMcNsConstexpr"

# ── 9. [RED] --uses on a camel constant: the def exists and the read site is found ─────────────
USES_OUT="$TMP/uses.xml"
$BIN "$FIX" --no-cache --uses=kMcTuConstexpr >"$USES_OUT" 2>/dev/null
grep -q 'defs="1"' "$USES_OUT" && ok "--uses=kMcTuConstexpr sees the def (defs=\"1\")" || no "--uses=kMcTuConstexpr defs != 1"
grep -q 'role="read" p="[^"]*cfg\.cpp:' "$USES_OUT" \
    && ok "--uses=kMcTuConstexpr finds the cfg.cpp read site" \
    || no "--uses=kMcTuConstexpr finds no read site in cfg.cpp"

# ── 10. [RED] the live repro, pinned: the repo's own version constants resolve on src/ ─────────
SRC_USES="$TMP/src_uses.xml"
$BIN "$ROOT/src" --no-cache --uses=kParserVer >"$SRC_USES" 2>/dev/null
grep -q 'defs="1"' "$SRC_USES" && ok "src/: --uses=kParserVer sees the ingest_cache.h def" || no "src/: --uses=kParserVer defs != 1 (the live gap)"
$BIN "$ROOT/src" --no-cache --uses=kIngestParserVerMirror >"$TMP/src_uses2.xml" 2>/dev/null
grep -q 'defs="1"' "$TMP/src_uses2.xml" && ok "src/: --uses=kIngestParserVerMirror sees the quality.h def" || no "src/: --uses=kIngestParserVerMirror defs != 1"
$BIN "$ROOT/src" --no-cache --for="kParserVer" >"$TMP/src_for.xml" 2>/dev/null
if grep -q 'weak="1"' "$TMP/src_for.xml"; then
    no "src/: --for=kParserVer still weak=\"1\" — the 2026-08-12 census repro"
else
    grep -q 'n="kParserVer"' "$TMP/src_for.xml" && ok "src/: --for=kParserVer resolves non-weak to the constant" || no "src/: --for=kParserVer non-weak but constant missing"
fi

# ── 11. determinism on this fixture ────────────────────────────────────────────────────────────
$BIN "$FIX" --no-cache >"$TMP/map2.xml" 2>/dev/null
diff -q "$MAP" "$TMP/map2.xml" >/dev/null && ok "two runs byte-identical" || no "determinism drift on moduleconstfix"

echo
[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
