#!/usr/bin/env bash
# objcsniffcheck.sh — the .h language-routing sniff must read CODE, not comments (kParserVer 74).
#
# looksObjC() decides whether a .h uses the objc grammar instead of C++ by peeking the first 8 KB for
# @interface/@protocol/@implementation. Pre-74 that peek was a raw substring search, so a C++ header
# whose DOC COMMENTS mention those keywords was rerouted wholesale to the objc grammar — which cannot
# parse namespaces/lambdas/noexcept — and every C++ symbol in the file vanished at EXTRACTION: no
# symbol row, no --skipped row, no floor, and --grep hits inside the file lost their in= enclosing
# symbol. Measured live on src/ingest_model.h (2026-08-30): its collapseObjCDeclDefs doc comment says
# "@interface"/"@implementation", and `struct DefSweep` + its `find` method (anonymous namespace, in
# a header) were unindexed while the SAME code had been indexed from src/ingest.cpp on the pre-split
# tree — the sniff only fires on .h, which is exactly why the decomposition surfaced it.
#
# RED-FIRST (recorded 2026-08-30, pre-fix build/ripwire on the repo itself, both repro forms):
#   `--edit-check=src/ingest_model.h:find`         → "symbol not found"
#   `--grep="nextSpanIndex = fileStart"`           → the hit row carried NO in= attribute
# post-fix the same calls resolve to DefSweep::find / in="DefSweep::find".
#
# Fixture test/objcsnifffix/:
#   cpp_mentions_objc.h — the victim shape: header + anonymous namespace + struct method, with the
#                         sniff keywords present in comments, a string literal, AND a raw string
#                         (all three must be masked), plus a 1'000'000 digit separator (a naive
#                         char-literal masker would swallow the rest of the file from it).
#   objc_real.h         — control: a REAL @interface in live code must still route to objc.
#
# Usage:  test/objcsniffcheck.sh   |   RIPWIRE_BIN=asan/ripwire test/objcsniffcheck.sh
# Exits non-zero on any failure. Does NOT edit test/regression.sh or test/golden.xml.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/objcsnifffix"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "objcsniffcheck: BIN=$BIN  FIX=$FIX"

MAP="$( "$BIN" "$FIX" --no-cache 2>/dev/null )"

# ── (a) the victim class of symbol: a struct METHOD in an anonymous namespace in a HEADER ───────────
printf '%s' "$MAP" | grep -q 'id="cpp_mentions_objc.h::SniffVictim::sniffVictimMethod"' \
    && ok "(a) sniffVictimMethod indexed with its SniffVictim scope (the symbol class that vanished pre-74)" \
    || { no "(a) sniffVictimMethod missing or unscoped — the comment-mention header is misrouted again"; printf '%s\n' "$MAP" | tr '>' '>\n' | grep 'cpp_mentions_objc' | head -6; }

printf '%s' "$MAP" | grep -q '<s t="cls" n="SniffVictim"' \
    && ok "(a) the enclosing struct itself is a cls row" \
    || no "(a) struct SniffVictim not indexed"

# ── (b) the no-enclosing-symbol symptom: a body grep must carry in= ─────────────────────────────────
GREPOUT="$( "$BIN" "$FIX" --no-cache --grep="return x + cursorState" 2>/dev/null )"
printf '%s' "$GREPOUT" | grep -q 'in="SniffVictim::sniffVictimMethod"' \
    && ok "(b) --grep inside the method body reports in=\"SniffVictim::sniffVictimMethod\"" \
    || { no "(b) the body grep lost its in= enclosing symbol (the original repro's symptom)"; printf '%s\n' "$GREPOUT" | tail -2; }

# ── (c) control: a REAL ObjC header still routes to the objc grammar ────────────────────────────────
printf '%s' "$MAP" | grep -q 'n="RealObjCThing"' \
    && ok "(c) real @interface still routes to objc (RealObjCThing extracted)" \
    || no "(c) RealObjCThing missing — the narrowed sniff went blind to live ObjC code"
printf '%s' "$MAP" | grep -q 'n="doRealThing"' \
    && ok "(c) the ObjC method doRealThing extracted" \
    || no "(c) doRealThing missing — objc routing degraded"

exit $fail
