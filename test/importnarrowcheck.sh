#!/usr/bin/env bash
# importnarrowcheck.sh — gate for P2-D Rule 3 import/include-based FILE narrowing.
#
# The narrow: a call to an ambiguous name (K same-name DEFS across the repo) resolves to the ONE file the
# caller #includes / imports that defines it — dropping the rest — WITHOUT any type/receiver info, using only
# the include/import edges ctxpack already captures. It fires ONLY on an exactly-one-included-file match with
# NO same-file candidate; on 0 or ≥2 candidate files it degrades to the unchanged §2a ladder. The soundness
# discipline (resolve.h::rule3IncludeFile) is "a wrong narrow is worse than no narrow".
#
# Fixture test/importnarrowfix: a.h and b.h are SIBLING files that BOTH define helper(). Three callers, same
# bare `helper()` call shape, differ ONLY in their includes — the narrowed-vs-control contrast proves the
# narrow is REAL (include-driven), not a vacuously-unambiguous fixture:
#   caller.cpp   #includes ONLY a.h  → Rule 3 narrows helper() to a.h::helper  (POSITIVE — amb drops to 0)
#   neither.cpp  includes NEITHER    → Rule 3 can't fire → helper() stays AMBIGUOUS (negative control 1)
#   both.cpp     #includes BOTH       → ≥2 candidate files → Rule 3 bails → stays AMBIGUOUS (negative control 2)
#
# Usage:
#   CTXPACK_BIN=build/ctxpack bash test/importnarrowcheck.sh
#   CTXPACK_BIN=asan/ctxpack  bash test/importnarrowcheck.sh
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${CTXPACK_BIN:-$ROOT/build/ctxpack}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative CTXPACK_BIN
FIX="$ROOT/test/importnarrowfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no test/importnarrowfix dir — fixture missing"; exit 2; }
cd "$ROOT"

echo "importnarrowcheck: BIN=$BIN  CORPUS=test/importnarrowfix"

"$BIN" "$FIX" --no-cache >"$TMP/map" 2>/dev/null

# ── 1) headline: exactly TWO ambiguous calls remain — the two negative controls. The positive caller
#       (caller.cpp) narrowed away its ambiguity entirely via Rule 3. ─────────────────────────────────
amb="$( grep -o 'ambiguous=[0-9]*' "$TMP/map" | head -1 | grep -o '[0-9]*' )"
[ "$amb" = "2" ] && ok "exactly two ambiguous calls remain (ambiguous=2 — the two controls only)" \
                 || no "ambiguous=$amb (expected 2: the positive caller narrows, both controls stay split)"

# ── 2) POSITIVE — caller.cpp (#include a.h only) narrows: callIncludedOnly has EXACTLY ONE callee, pointing
#       at a.h::helper (a.h:3), NOT b.h::helper (b.h:3). This is Rule 3's core assertion. ───────────────────
ce="$( "$BIN" "$FIX" --callees=callIncludedOnly --no-cache 2>/dev/null )"
n="$( printf '%s' "$ce" | grep -o 'count="[0-9]*"' | grep -o '[0-9]*' )"
[ "$n" = "1" ] && ok "Rule 3: callIncludedOnly has exactly one callee edge (was 2)" \
              || { no "Rule 3: callIncludedOnly callee count = ${n:-?} (expected 1)"; printf '    %s\n' "$ce"; }
printf '%s' "$ce" | grep -q 'a.h:3' && ok "Rule 3: the edge points at the INCLUDED a.h::helper (a.h:3)" \
    || { no "Rule 3: edge does not point at a.h::helper (a.h:3)"; printf '    %s\n' "$ce"; }
printf '%s' "$ce" | grep -q 'b.h:3' && { no "Rule 3: a WRONG edge to the NON-included b.h::helper (b.h:3) survived"; printf '    %s\n' "$ce"; } \
    || ok "Rule 3: no wrong edge to the non-included b.h::helper (b.h:3)"

# ── 3) the positive caller carries NO amb= marker (its one call is pinned). ──────────────────────────────
if grep -oE 'n="callIncludedOnly"[^>]*' "$TMP/map" | grep -q 'amb='; then
    no "callIncludedOnly is still marked ambiguous (Rule 3 did not fire)"; grep -oE 'n="callIncludedOnly"[^>]*' "$TMP/map"
else
    ok "callIncludedOnly is NARROWED (no amb= — helper()→a.h::helper resolved 1:1)"
fi

# ── 4) NEGATIVE control 1 — neither.cpp (includes NEITHER) MUST stay ambiguous: no included file defines
#       helper, so Rule 3 cannot fire and the call honestly splits to BOTH defs (amb=1). ────────────────────
grep -q 'n="callNeither" amb="1"' "$TMP/map" \
    && ok "control callNeither() stays AMBIGUOUS (amb=1 — proves Rule 3 needs a real include)" \
    || { no "callNeither() is not amb=1 (negative control 1 failed — narrow may be spurious)"; grep -o 'n="callNeither"[^>]*' "$TMP/map" | head; }

# ── 5) NEGATIVE control 2 — both.cpp (#includes BOTH) MUST stay ambiguous: two distinct included files each
#       define helper, so the include set does NOT disambiguate → Rule 3 bails → stays split (amb=1). This is
#       the "never a wrong narrow on a tie" guarantee. ───────────────────────────────────────────────────────
grep -q 'n="callBoth" amb="1"' "$TMP/map" \
    && ok "control callBoth() stays AMBIGUOUS (amb=1 — ≥2 candidate files → Rule 3 correctly bails)" \
    || { no "callBoth() is not amb=1 (negative control 2 failed — Rule 3 wrongly narrowed a tie)"; grep -o 'n="callBoth"[^>]*' "$TMP/map" | head; }

# ── 6) under-link guard: the controls RESOLVE to BOTH distinct helper defs (a.h + b.h) — not dropped, not
#       cross-linked. Each stays split across exactly the two real defs. ──────────────────────────────────────
for c in callNeither callBoth; do
    cc="$( "$BIN" "$FIX" --callees=$c --no-cache 2>/dev/null )"
    nt="$( printf '%s' "$cc" | grep -o 'n="helper"[^>]*importnarrowfix/[ab].h:[0-9]*' | sort -u | wc -l | tr -d ' ' )"
    [ "$nt" = "2" ] && ok "control $c() keeps BOTH helper edges to distinct defs ($nt targets)" \
                    || { no "control $c() has $nt distinct helper targets (want 2: a.h + b.h)"; printf '%s\n' "$cc" | tr '>' '\n' | grep helper; }
done

# ── 7) determinism — the include-set build + narrow must be byte-stable run-to-run. ─────────────────────
"$BIN" "$FIX" --no-cache >"$TMP/map2" 2>/dev/null
diff -q "$TMP/map" "$TMP/map2" >/dev/null \
    && ok "deterministic (importnarrowfix map byte-identical across two runs)" \
    || { no "non-deterministic importnarrowfix map"; diff "$TMP/map" "$TMP/map2" | head -6; }

# ── 8) cache transparency — Rule 3 consumes include facts that survive the incremental cache: warm == cold. ──
rm -f "$TMP/nc"
"$BIN" "$FIX" --cache="$TMP/nc" >/dev/null 2>&1
"$BIN" "$FIX" --cache="$TMP/nc" >"$TMP/warm" 2>/dev/null
"$BIN" "$FIX" --no-cache        >"$TMP/cold" 2>/dev/null
diff -q "$TMP/warm" "$TMP/cold" >/dev/null \
    && ok "cache-transparent (includes round-trip: warm == cold)" \
    || { no "include cache changes output (warm != cold)"; diff "$TMP/cold" "$TMP/warm" | head -6; }

# ── 9) MUTATION test — flip caller.cpp's include from a.h to b.h and the narrow must FOLLOW the include (now
#       resolves to b.h::helper, still amb=0). Proves the narrow is DRIVEN by the include, not the filename or
#       symbol id order. Run on a throwaway copy so the committed fixture is untouched. ─────────────────────────
cp -R "$FIX" "$TMP/mut"
# rewrite the include line in the copy: #include "a.h"  →  #include "b.h"
perl -0pi -e 's/#include "a\.h"/#include "b.h"/' "$TMP/mut/caller.cpp"
mce="$( "$BIN" "$TMP/mut" --callees=callIncludedOnly --no-cache 2>/dev/null )"
mn="$( printf '%s' "$mce" | grep -o 'count="[0-9]*"' | grep -o '[0-9]*' )"
if [ "$mn" = "1" ] && printf '%s' "$mce" | grep -q 'b.h:3' && ! printf '%s' "$mce" | grep -q 'a.h:3'; then
    ok "mutation: flipping the include a.h→b.h re-targets the narrow to b.h::helper (include-driven, not name/id-driven)"
else
    no "mutation: after flipping to #include \"b.h\" the narrow did not follow (count=${mn:-?})"; printf '    %s\n' "$mce"
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
