#!/usr/bin/env bash
# expandtopk0check.sh — V1 gate (ugrep routing note RN2, 2026-08-15 harvest): --expand=SYMBOL for an
# EXACT-NAME request (one token, one unambiguous match) now DEFAULTS its own ranked map to top-k=0 — the
# caller already named the exact target, so the ~200-row orientation map is pure overhead in front of the
# one body it exists to summarize. "Cheapest complete answer in one call."
#
# THE CONTRACT:
#   - one token, ONE match, no explicit --top-k: NO <r> map rows, and the root discloses the default with
#     topk_default="0" (self-describing — the change can be seen without reading source).
#   - one token, MULTIPLE matches (a genuinely ambiguous name): the caller's ORDINARY default still
#     applies — the ranked map rides along (there IS something to disambiguate) and the pre-existing
#     "ranked top-N map rides along" stderr note still fires. NO topk_default= on this shape.
#   - an EXPLICIT --top-k=N (0 included) always overrides the new default and keeps the classic shape —
#     no topk_default= attribute either way, since the caller made the choice, not the tool.
#   - the default composes with M6's bundle-vs-whole-file auto-serving (test/expandmodecheck.sh): whichever
#     mode M6 picks, topk_default="0" still rides on the root when the exact-name default applied.
#
# Fixtures: test/expandtopk0fix/unique.c (uniqueTarget, one def) + dupA.c/dupB.c (dupTarget, two defs, the
# ambiguous control) — both tiny, so M6 serves whole-file; test/expandmodefix/big.c (bigProbe007, one def
# in a file too large for whole-file) exercises the SAME default composed with mode="bundle".
#
# Usage:  RIPWIRE_BIN=build/ripwire bash test/expandtopk0check.sh   |   RIPWIRE_BIN=asan/ripwire bash …
# Exits non-zero on any failure; prints PASS/FAIL per check, ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/expandtopk0fix"
MODEFIX="$ROOT/test/expandmodefix"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ]     || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ]     || { echo "no test/expandtopk0fix directory"; exit 2; }
[ -d "$MODEFIX" ] || { echo "no test/expandmodefix directory"; exit 2; }
cd "$ROOT"
echo "expandtopk0check: BIN=$BIN  FIX=$FIX"

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

# ── (A) exact-name, no --top-k: topk_default="0", NO ranked map, NO ride-along stderr note ──────────────
"$BIN" "$FIX" --expand=uniqueTarget --no-cache >"$TMP/uniq.xml" 2>"$TMP/uniq.err"
grep -q 'topk_default="0"' "$TMP/uniq.xml" \
    && ok "(A) exact-name --expand discloses topk_default=\"0\" on the root" \
    || no "(A) exact-name --expand carries no topk_default= disclosure"
if grep -q '<r ' "$TMP/uniq.xml"; then
    no "(A) exact-name --expand still shipped the ranked map"
else
    ok "(A) exact-name --expand emits NO ranked map rows"
fi
grep -q 'uniqueTarget' "$TMP/uniq.xml" \
    && ok "(A) the one body is still present" || no "(A) the body itself is missing"
if grep -qi 'rides along' "$TMP/uniq.err"; then
    no "(A) the ride-along stderr note fired even though no map rides (mapTopK==0 guard missing)"
else
    ok "(A) no ride-along stderr note (nothing is riding along to warn about)"
fi

# ── (B) ambiguous name (2 defs), the ORDINARY default where the lean default does not apply ────────────────
# expand-lean-k64 (2026-10-08): a multi-definition name whose definitions are ALL served now drops the map too — see (H)
# below. This TWIN pins the path that stays: wherever the lean default is excluded the caller's ordinary default applies, the
# ranked map rides along and the pre-existing "ranked top-N map rides along" stderr note still fires, with NO topk_default=.
# --max-tokens=3000 is such a shape (it sizes the map, so the exact-name/lean defaults both stand aside); the explicit
# --top-k=5 twin right below pins the other half (the caller asked for the map).
"$BIN" "$FIX" --expand=dupTarget --top-k=5 --no-cache >"$TMP/dup5.xml" 2>/dev/null
grep -q '<r ' "$TMP/dup5.xml" \
    && ok "(B) --top-k=5 sanity: dupTarget's map is reachable at all" \
    || no "(B) --top-k=5 sanity failed — fixture cannot exercise this arm"
if grep -qE 'topk_default=|map_next=' "$TMP/dup5.xml"; then
    no "(B) explicit --top-k=5 on a multi-def name carries lean-default decoration — the caller chose, not the tool"
else
    ok "(B) explicit --top-k=5 on a multi-def name keeps the classic shape (no topk_default=, no map_next=)"
fi
"$BIN" "$FIX" --expand=dupTarget --max-tokens=3000 --pack-budget-bytes=10 --no-cache >"$TMP/dup.xml" 2>"$TMP/dup.err"
grep -q '<r ' "$TMP/dup.xml" \
    && ok "(B) sanity: --max-tokens=3000 keeps the ordinary ride-along map on a multi-def name" \
    || no "(B) sanity failed: --max-tokens=3000 shipped no map — arm proves nothing"
if grep -qE 'topk_default=|map_next=' "$TMP/dup.xml"; then
    no "(B) a --max-tokens-sized multi-def --expand wrongly got the lean default"
else
    ok "(B) --max-tokens multi-def --expand carries NO topk_default=/map_next= — the ordinary path is untouched"
fi
grep -qi 'rides along' "$TMP/dup.err" \
    && ok "(B) the pre-existing ride-along stderr note still fires on the ordinary multi-def shape" \
    || no "(B) ride-along note missing on the ordinary multi-def shape (V1 regression)"

# ── (C) explicit --top-k=5 on the exact-name target: overrides the default, classic undecorated shape ───
"$BIN" "$FIX" --expand=uniqueTarget --top-k=5 --no-cache >"$TMP/tk5.xml" 2>/dev/null
grep -q '<r ' "$TMP/tk5.xml" \
    && ok "(C) explicit --top-k=5 forces the map back even on an exact-name match" \
    || no "(C) explicit --top-k=5 lost the map"
if grep -q 'topk_default=' "$TMP/tk5.xml"; then
    no "(C) explicit --top-k=5 still carries topk_default= — override must keep the caller's plain shape"
else
    ok "(C) explicit --top-k=5 carries no topk_default= (the caller chose, not the tool)"
fi

# ── (D) explicit --top-k=0: the pre-existing legacy undecorated lean form, unchanged ─────────────────────
"$BIN" "$FIX" --expand=uniqueTarget --top-k=0 --no-cache >"$TMP/tk0.xml" 2>/dev/null
if grep -qE '<r |topk_default=|mode="' "$TMP/tk0.xml"; then
    no "(D) explicit --top-k=0 picked up new decoration — must stay the pre-existing byte shape"
else
    ok "(D) explicit --top-k=0 stays the pre-existing undecorated lean form"
fi

# ── (E) composes with M6 bundle mode: bigProbe007 (large file, exact match) — mode="bundle" AND
#        topk_default="0" AND no <r> map, all at once (test/expandmodecheck.sh arm 2 pins the mode= side;
#        this arm is the topk_default= side of the SAME document). ───────────────────────────────────────
"$BIN" "$MODEFIX" --expand=bigProbe007 --no-cache >"$TMP/big.xml" 2>/dev/null
grep -q 'mode="bundle"' "$TMP/big.xml" && grep -q 'topk_default="0"' "$TMP/big.xml" \
    && ok "(E) bundle mode AND the exact-name default compose on one root" \
    || no "(E) bundle mode / topk_default= did not compose: $( grep -oE '<ctx[^>]*>' "$TMP/big.xml" )"
if grep -q '<r ' "$TMP/big.xml"; then
    no "(E) bundle mode still shipped the ranked map"
else
    ok "(E) bundle mode ships no ranked map either"
fi

# ── (G) V1 fix regression guard (verifier finding 1, 2026-08-15) — the shape (B) and (E) both
#        structurally could not exercise. (B) forces bundle mode via --pack-budget-bytes=10, so the
#        estimator's own value never gets compared against a real whole-file candidate. (E)'s
#        bigProbe007 fixture is tiny and hand-built, so even a wildly wrong bundle estimate happens not
#        to flip the mode there. Neither arm runs at the DEFAULT budget on a REAL, non-trivial repo — the
#        one place the defect actually manifested: measureEmittedMapBytes(mapTopK, …) was called
#        UNGUARDED for the bundle-size estimate, and mapTopK==0 means UNLIMITED inside serialize() (not
#        "no map"), so the estimator priced a ~1 MB whole-repo map that the emitter never intended to
#        print. chooseExpandServe then compared that phantom bundle against the real whole-file candidate
#        and picked mode="whole-file" — serving the ENTIRE 48 KB src/darkflags.h in place of the ~1 KB
#        body the exact-name default promises. RED on the pre-fix binary
#        (reason="file 48222B &lt; bundle 1054283B", mode="whole-file"); GREEN once the estimator is
#        guarded exactly like its two siblings at the ceiling verdict and the topK>0 emission gate
#        (`mapTopK > 0 ? measureEmittedMapBytes(...) : 0`).
# L1 (2026-09-19): the CLI default legend is compact. (G-b)'s identity — reason='s bundle price IS the served byte count —
# is priced by chooseExpandServe in the FULL dialect (expandmodecheck (4) states why); under the compact default the
# reason= numbers stay the full-dialect candidate prices, a found item in the L1 lane report. Both runs ask for full.
# PROBE MOVED 2026-09-30 (train 22): src/darkflags.h grew past the 64 KiB pack budget (66,556 B, the --flags
# JavaScript/TypeScript env reader), so --expand=endsWithView now serves bundle for a different reason ("whole-file
# 66556B over pack-budget 65536B") and never prices the bundle against the file — the comparison this arm exists for.
# The probe is now lspPercentDecode (src/lsp.h, ~50 KB, one definition): a small body in a real file under the budget,
# the same shape darkflags.h had when V1 was found. Pick another such symbol if lsp.h crosses the budget too.
PROBE=lspPercentDecode
"$BIN" "$ROOT" --expand=$PROBE --no-cache --legend=full >"$TMP/real_default.xml" 2>"$TMP/real_default.err"
"$BIN" "$ROOT" --expand=$PROBE --no-cache --top-k=0 --legend=full >"$TMP/real_tk0.xml" 2>/dev/null
realTk0Bytes=$( wc -c < "$TMP/real_tk0.xml" | tr -d ' ' )

if grep -q 'mode="whole-file"' "$TMP/real_default.xml"; then
    no "(G) default --expand=$PROBE on the real repo wrongly served whole-file: $( grep -oE '<ctx[^>]*>' "$TMP/real_default.xml" )"
else
    ok "(G) default --expand=$PROBE on the real repo correctly stays in bundle mode"
fi

# (G-a) the SERVED BODY (everything but the <ctx ...> opening tag's own mode=/reason= decoration, which
#       composing with M6 is the documented, (E)-gated contract) must be byte-identical to explicit
#       --top-k=0's — proving the estimator and the emitter now agree on what mapTopK==0 means.
sed 's/<ctx[^>]*>//' "$TMP/real_default.xml" > "$TMP/real_default_body.xml"
sed 's/<ctx[^>]*>//' "$TMP/real_tk0.xml"      > "$TMP/real_tk0_body.xml"
diff -q "$TMP/real_default_body.xml" "$TMP/real_tk0_body.xml" >/dev/null \
    && ok "(G-a) default's served body is byte-identical to explicit --top-k=0's" \
    || no "(G-a) default's served body diverges from explicit --top-k=0's — the estimator or the emitter disagree on what mapTopK==0 means"

# (G-b) when topk_default="0" is in effect and a reason= fires, the bundle byte count it PRICES must be the
#       REAL served size, never a phantom map-inclusive estimate. This is the precise, load-bearing number
#       the V1 defect corrupted.
#
#       WHAT THE COMPARISON IS, and why it moved (CodeRabbit, PR #215). It used to read the priced number
#       against EXPLICIT --top-k=0's byte count. Those two documents carry the same payload but not the same
#       root: the auto form is decorated with topk_default= and the mode=/reason= disclosure, the explicit
#       override is deliberately undecorated ((G-a) strips the opener for exactly that reason). The old
#       equality held only because the price omitted that decoration too — two omissions cancelling, which is
#       how the file candidate came to be compared against the bundle on different accounting in the first
#       place. Both candidates are now priced as the complete document they would serve, so the identity is
#       the stronger and more direct one: the priced bundle IS the bundle document. The anti-phantom property
#       the arm exists for is unweakened — (G-a) already proves this document's payload is byte-identical to
#       explicit --top-k=0's, and a phantom whole-repo map would blow the identity here by ~1 MB.
pricedBundle=$( grep -oE 'reason="bundle [0-9]+B' "$TMP/real_default.xml" | grep -oE '[0-9]+' )
realDefaultBytes=$( wc -c < "$TMP/real_default.xml" | tr -d ' ' )
if [ -n "$pricedBundle" ]; then
    if [ "$pricedBundle" = "$realDefaultBytes" ]; then
        ok "(G-b) reason= prices the bundle at exactly the bytes it serves (${pricedBundle}B; explicit --top-k=0 serves the same payload under an undecorated root, ${realTk0Bytes}B) — no phantom map"
    else
        no "(G-b) reason= priced the bundle at ${pricedBundle}B but the document it served is ${realDefaultBytes}B — the whole-file candidate is being compared against a bundle price that is not the bundle document"
    fi
else
    no "(G-b) no reason=\"bundle NNNB ...\" clause found on the real-repo default root — unexpected mode, see (G) above: $( grep -oE '<ctx[^>]*>' "$TMP/real_default.xml" )"
fi

# ── (H) expand-lean-k64: a multi-definition name, EVERY definition served — no ride-along map ─────────────────────────
# `subtokens` has three definitions (one C++ header, two Python fixtures) and the default budget serves all of them in
# bundle mode (the header is far over the pack budget as a whole file). The root discloses the default (topk_default="0"),
# carries the recoverable pointer to the map it did not ship (map_next=), the bodies keep p= l= for each def, and no <r>/<f>
# rows ride. (The tiny dupTarget fixture serves whole-file instead — (J2) pins that.)
"$BIN" "$ROOT" --expand=subtokens --no-cache --legend=full >"$TMP/mdef.xml" 2>"$TMP/mdef.err"
grep -q 'topk_default="0"' "$TMP/mdef.xml" && grep -q 'map_next="ripwire ' "$TMP/mdef.xml" \
    && ok "(H) multi-def, all served: root carries topk_default=\"0\" and map_next=" \
    || no "(H) multi-def default lacks topk_default=/map_next=: $( grep -oE '<ctx[^>]*>' "$TMP/mdef.xml" )"
if grep -qE '<r |<f p=' "$TMP/mdef.xml"; then
    no "(H) multi-def, all served: the ranked map still rides along"
else
    ok "(H) multi-def, all served: NO ranked map rows"
fi
if grep -qi 'rides along' "$TMP/mdef.err"; then
    no "(H) the ride-along stderr note fired though no map rides"
else
    ok "(H) no ride-along stderr note (no map rides)"
fi
if grep -q 'unserved_' "$TMP/mdef.xml"; then
    no "(H) unserved_* named on an answer that served every definition"
else
    ok "(H) all served: no unserved_* attributes (negative)"
fi

# ── (H2) the pointer is real, and the payload is the one the explicit-top-k twin serves ─────────────────────────────
mapNext=$( grep -oE 'map_next="[^"]*"' "$TMP/mdef.xml" | head -1 | sed 's/^map_next="//;s/"$//' )
case "$mapNext" in
    "ripwire "*) mapRoot="${mapNext#ripwire }"
                 "$BIN" "$mapRoot" --no-cache --top-k=3 >"$TMP/mapnext.xml" 2>/dev/null
                 grep -q '<r ' "$TMP/mapnext.xml" \
                     && ok "(H2) map_next's root prints a ranked map (the pointer is recoverable)" \
                     || no "(H2) map_next=\"$mapNext\" does not print a map" ;;
    *) no "(H2) map_next= missing or not a ripwire call: '$mapNext'" ;;
esac
"$BIN" "$ROOT" --expand=subtokens --top-k=3 --no-cache --legend=full >"$TMP/mdef_tk.xml" 2>/dev/null
bodiesOf(){ perl -0777 -ne 'print $1 if /(<bodies shown="[0-9]+" total=.*?<\/bodies>)/s' "$1"; }
[ -n "$( bodiesOf "$TMP/mdef.xml" )" ] && [ "$( bodiesOf "$TMP/mdef.xml" )" = "$( bodiesOf "$TMP/mdef_tk.xml" )" ] \
    && ok "(H2) the lean answer's <bodies> are byte-identical to the explicit --top-k=3 twin's" \
    || no "(H2) the lean answer's <bodies> differ from the explicit twin's (every body must still be served)"
nb=$( grep -oE '<b t="[a-z]+" l="[0-9]+" p="[^"]*" n="subtokens"' "$TMP/mdef.xml" | wc -l | tr -d ' ' )
[ "$nb" -ge 3 ] && grep -q '<bodies shown="'"$nb"'" total="'"$nb"'"' "$TMP/mdef.xml" \
    && ok "(H2) all $nb definitions are served and located (p= l= on each <b>, shown==total)" \
    || no "(H2) the lean answer serves $nb located <b>, expected >= 3 with shown==total"

# ── (I) bodies CUT: a symbol-scoped aid (the unserved defs), never the generic map ─────────────────────────────────
"$BIN" "$FIX" --expand=dupTarget --pack-budget-bytes=10 --no-cache >"$TMP/cut.xml" 2>/dev/null
if grep -qE '<r |<f p=' "$TMP/cut.xml"; then
    no "(I) a cut multi-def answer shipped the generic ranked map"
else
    ok "(I) a cut multi-def answer ships no generic ranked map"
fi
grep -q 'unserved_total="1"' "$TMP/cut.xml" \
    && ok "(I) the root counts the unserved defs (unserved_total=\"1\")" \
    || no "(I) unserved_total=\"1\" missing: $( grep -oE '<ctx[^>]*>' "$TMP/cut.xml" )"
unNext=$( grep -oE 'unserved_next="[^"]*"' "$TMP/cut.xml" | head -1 | sed 's/^unserved_next="//;s/"$//' )
case "$unNext" in
    --expand=*dupB.c:*:dupTarget)
        if grep -q 'dupB.c:2:dupTarget' <<<"$unNext"; then
            "$BIN" "$FIX" "$unNext" --no-cache >"$TMP/cut2.xml" 2>/dev/null
            grep -q 'return 2' "$TMP/cut2.xml" \
                && ok "(I) unserved_next serves exactly the cut definition (dupB.c's body)" \
                || no "(I) unserved_next did not serve dupB.c's body"
            grep -q 'return 1' "$TMP/cut2.xml" \
                && no "(I) unserved_next re-served the definition that was already served" \
                || ok "(I) unserved_next names only the unserved def (dupA.c's body is not re-served)"
        else
            no "(I) unserved_next names the wrong line: $unNext"
        fi ;;
    *) no "(I) unserved_next missing or names the wrong def: '$unNext'" ;;
esac
grep -q '<b [^>]*p="dupA.c"' "$TMP/cut.xml" \
    && ok "(I) the served def (dupA.c) is still in the cut answer" || no "(I) the first def is missing from the cut answer"

# ── (J) the whole-file comparison prices the PAYLOAD, not a map ─────────────────────────────────────────────────────
# (J1) real repo: emitTo (2 overloads, one file) used to serve the whole 24 KB file because the bundle was priced with the
#      ~19 KB map. Now bundle mode, the priced bundle is the served document, and the document is far under the file.
"$BIN" "$ROOT" --expand=emitTo --no-cache --legend=full >"$TMP/emit.xml" 2>/dev/null
if grep -q 'mode="bundle"' "$TMP/emit.xml"; then
    pb=$( grep -oE 'reason="bundle [0-9]+B' "$TMP/emit.xml" | grep -oE '[0-9]+' )
    sz=$( wc -c < "$TMP/emit.xml" | tr -d ' ' )
    [ -n "$pb" ] && [ "$pb" = "$sz" ] && [ "$sz" -lt 12000 ] \
        && ok "(J1) emitTo: bundle mode, priced bundle ${pb}B == served ${sz}B (< 12000B; was the whole 24788B file)" \
        || no "(J1) emitTo bundle priced '${pb}' vs served ${sz}B"
else
    no "(J1) emitTo is not in bundle mode: $( grep -oE '<ctx[^>]*>' "$TMP/emit.xml" )"
fi
# (J2) near-miss: where the file really is cheaper (tiny fixture) whole-file STILL wins, with the lean disclosure intact
"$BIN" "$FIX" --expand=dupTarget --no-cache --legend=full >"$TMP/small.xml" 2>/dev/null
grep -q 'mode="whole-file"' "$TMP/small.xml" && grep -q 'topk_default="0"' "$TMP/small.xml" && ! grep -q '<r ' "$TMP/small.xml" \
    && ok "(J2) a file cheaper than the payload bundle is still served whole-file (no map, lean disclosure intact)" \
    || no "(J2) tiny-fixture default is not whole-file+lean: $( grep -oE '<ctx[^>]*>' "$TMP/small.xml" )"
if grep -q 'unserved_' "$TMP/small.xml"; then
    no "(J2) whole-file serving names unserved defs though the file carries every one"
else
    ok "(J2) whole-file serving carries no unserved_* (the file has every definition)"
fi

# ── (K) --outline follows the same rule ──────────────────────────────────────────────────────────────────────────────
"$BIN" "$FIX" --outline=dupTarget --no-cache >"$TMP/ol.xml" 2>/dev/null
if grep -qE '<r |<f p=' "$TMP/ol.xml"; then no "(K) --outline of all-served defs still ships the map"; else ok "(K) --outline of all-served defs ships no map"; fi
grep -q 'topk_default="0"' "$TMP/ol.xml" && grep -q 'map_next="ripwire ' "$TMP/ol.xml" \
    && ok "(K) --outline root carries topk_default=\"0\" and map_next=" || no "(K) --outline lean root decoration missing"
"$BIN" "$FIX" --outline=dupTarget --top-k=5 --no-cache >"$TMP/ol5.xml" 2>/dev/null
grep -q '<r ' "$TMP/ol5.xml" && ! grep -qE 'topk_default=|map_next=' "$TMP/ol5.xml" \
    && ok "(K) --outline with an explicit --top-k=5 keeps the classic map shape" || no "(K) explicit --top-k=5 --outline lost the map or gained the lean decoration"
"$BIN" "$FIX" --outline=dupTarget --pack-budget-bytes=1 --no-cache >"$TMP/olcut.xml" 2>/dev/null
grep -q 'unserved_total=' "$TMP/olcut.xml" && grep -q 'unserved_next="--outline=' "$TMP/olcut.xml" && ! grep -q '<r ' "$TMP/olcut.xml" \
    && ok "(K) a cut --outline names its unserved defs (unserved_next=--outline=…), no generic map" \
    || no "(K) cut --outline: $( grep -oE '<ctx[^>]*>' "$TMP/olcut.xml" )"

# ── (L) near-miss negatives: the lean default must NOT apply where the caller or a composed verb owns the map ─────────
"$BIN" "$FIX" --expand=dupTarget --top-k=0 --no-cache >"$TMP/mtk0.xml" 2>/dev/null
if grep -qE 'topk_default=|map_next=|mode="' "$TMP/mtk0.xml"; then
    no "(L) explicit --top-k=0 on a multi-def name picked up lean decoration — must stay the undecorated lean form"
else
    ok "(L) explicit --top-k=0 on a multi-def name stays undecorated"
fi
"$BIN" "$FIX" --expand=dupTarget --pack-top-n=1 --no-cache >"$TMP/mpack.xml" 2>/dev/null
if grep -qE 'topk_default=|map_next=' "$TMP/mpack.xml"; then
    no "(L) --expand composed with --pack-top-n wrongly got the lean default (the composed verb owns the map)"
else
    ok "(L) --expand composed with --pack-top-n keeps its own shape (no lean decoration)"
fi
"$BIN" "$FIX" --expand=uniqueTarget,dupTarget --pack-budget-bytes=1000000 --no-cache >"$TMP/mtok.xml" 2>/dev/null
if grep -q '<r ' "$TMP/mtok.xml" || ! grep -q 'map_next=' "$TMP/mtok.xml"; then
    no "(L) a multi-token --expand with every def served should be lean: $( grep -oE '<ctx[^>]*>' "$TMP/mtok.xml" )"
else
    ok "(L) a multi-token --expand with every def served is lean too"
fi
"$BIN" "$FIX" --expand=uniqueTarget --no-cache >"$TMP/u1.xml" 2>/dev/null
if grep -q 'map_next=' "$TMP/u1.xml"; then
    no "(L) the single-definition exact-name answer changed shape (map_next= appeared)"
else
    ok "(L) the single-definition exact-name answer is unchanged (topk_default only, no map_next=)"
fi

# ── (M) fix round 1: map_next= replays EVERY root and the crawl-scope flags, shell-quoted (nextFlag) ─────────────────
# A multi-root call's map is the map of all its roots; the pointer used to fall back to "ripwire ." (the parent tree), and
# it dropped --ignore-tests/--exclude, so pasting it printed a map of a different corpus. Exact pointers, then pasted.
xmlUnesc(){ sed -e 's/&apos;/'"'"'/g' -e 's/&quot;/"/g' -e 's/&lt;/</g' -e 's/&gt;/>/g' -e 's/&amp;/\&/g'; }
attrOf(){ grep -oE "$1=\"[^\"]*\"" "$2" | head -1 | sed "s/^$1=\"//;s/\"\$//"; }
MR="$TMP/mr"; mkdir -p "$MR/r1" "$MR/r2"
printf 'int multiWork(void) { return 1; }\n' >"$MR/r1/w.c"
printf 'int multiWork(void) { return 2; }\n' >"$MR/r2/w.c"
( cd "$MR" && "$BIN" r1 r2 --expand=multiWork --no-cache ) >"$TMP/mroot.xml" 2>/dev/null
mrNext="$( attrOf map_next "$TMP/mroot.xml" )"
[ "$mrNext" = "ripwire r1 r2" ] \
    && ok "(M) multi-root: map_next names BOTH roots (\"$mrNext\")" \
    || no "(M) multi-root: map_next='$mrNext', want 'ripwire r1 r2': $( grep -oE '<ctx[^>]*>' "$TMP/mroot.xml" | head -1 )"
grep -q 'return 1' "$TMP/mroot.xml" && grep -q 'return 2' "$TMP/mroot.xml" \
    && ok "(M) multi-root: both definitions are served (premise of the lean answer)" \
    || no "(M) multi-root: the two definitions are not both served"
( cd "$MR" && "$BIN" r1 r2 --no-cache --top-k=3 ) >"$TMP/mroot_map.xml" 2>/dev/null
( cd "$MR" && eval "\"\$BIN\" ${mrNext#ripwire } --no-cache --top-k=3" ) >"$TMP/mroot_paste.xml" 2>/dev/null
grep -q '<r ' "$TMP/mroot_paste.xml" && cmp -s "$TMP/mroot_map.xml" "$TMP/mroot_paste.xml" \
    && ok "(M) multi-root: the pasted map_next prints the two-root map byte for byte" \
    || no "(M) multi-root: the pasted map_next does not print the two-root map"
# The scope tree holds a tests/ file, so --ignore-tests really changes the map the pointer must reproduce.
SC="$TMP/sc"; mkdir -p "$SC"; cp -R "$FIX" "$SC/fix"; mkdir -p "$SC/fix/tests"
printf 'int testOnlyHelper(void) { return dupTarget(); }\nint testOnlyCaller(void) { return testOnlyHelper(); }\n' >"$SC/fix/tests/test_dup.c"
( cd "$SC" && "$BIN" fix --expand=dupTarget --ignore-tests '--exclude=nomatch*' --no-cache ) >"$TMP/scope.xml" 2>/dev/null
scNext="$( attrOf map_next "$TMP/scope.xml" )"
[ "$scNext" = "ripwire fix --exclude=&apos;nomatch*&apos; --ignore-tests" ] \
    && ok "(M) crawl scope: map_next replays --exclude (quoted) and --ignore-tests" \
    || no "(M) crawl scope: map_next='$scNext', want the root plus --exclude='nomatch*' --ignore-tests"
scShell="$( printf '%s' "$scNext" | xmlUnesc )"
( cd "$SC" && eval "\"\$BIN\" ${scShell#ripwire } --no-cache --top-k=50" ) >"$TMP/scope_paste.xml" 2>/dev/null
( cd "$SC" && "$BIN" fix --ignore-tests '--exclude=nomatch*' --no-cache --top-k=50 ) >"$TMP/scope_map.xml" 2>/dev/null
( cd "$SC" && "$BIN" fix --no-cache --top-k=50 ) >"$TMP/scope_wide.xml" 2>/dev/null
cmp -s "$TMP/scope_map.xml" "$TMP/scope_wide.xml" \
    && no "(M) crawl scope premise: --ignore-tests does not change this tree's map — the paste arm would prove nothing" \
    || ok "(M) crawl scope premise: --ignore-tests changes this tree's map"
grep -q '<r ' "$TMP/scope_paste.xml" && cmp -s "$TMP/scope_map.xml" "$TMP/scope_paste.xml" \
    && ok "(M) crawl scope: the pasted map_next prints the same-scope map byte for byte" \
    || no "(M) crawl scope: the pasted map_next does not print the same-scope map"
"$BIN" test/expandtopk0fix --expand=dupTarget --no-cache >"$TMP/plainptr.xml" 2>/dev/null
[ "$( attrOf map_next "$TMP/plainptr.xml" )" = "ripwire test/expandtopk0fix" ] \
    && ok "(M) negative: with no crawl-scope flag map_next is just the root" \
    || no "(M) negative: plain map_next='$( attrOf map_next "$TMP/plainptr.xml" )', want 'ripwire test/expandtopk0fix'"

# ── (N) fix round 1: unserved_next= is shell-quoted, and past 16 cut definitions it says how many it lists ──────────
# Each file under "sub dir/" holds a 62-line (~2.8 KB) `def work`; a 3500 B pack budget serves one. With 4 files the 3 cut ones are
# all listed (no unserved_listed=); with 20 files the 19 cut ones exceed the 16-selector guard: unserved_listed="16", the
# paste (default budget: 16 bodies fit) serves exactly those 16, and the same call with a larger budget serves all 20 (the
# legend's "the rest"). Served = <b> rows in bundle mode or <src sym=> blocks in whole-file mode, whichever the call picks.
rootOf(){ grep -oE '<ctx[^>]*>' "$1" | head -1; }
mkwork(){ local d="$1" n="$2" i j; mkdir -p "$d/sub dir"
    for i in $( seq -w 1 "$n" ); do
        { echo "def work():"; for j in $( seq 1 61 ); do echo "    value_$j = 'padding to about forty-five bytes $j'"; done; } >"$d/sub dir/m$i.py"
    done; }
selectorsOf(){ printf '%s' "$1" | xmlUnesc | sed -e "s/^--expand=//" -e "s/^'//" -e "s/'\$//" | tr ',' '\n' | sort; }
servedOf(){ grep -oE '<b t="[a-z]+" l="[0-9]+" p="[^"]*" n="work"' "$1" | sed -E 's/.* l="([0-9]+)" p="([^"]*)".*/\2:\1:work/' | sort; }
servedAnyOf(){ { servedOf "$1"; grep -oE '<src p="[^"]*" sym="work:[0-9]+"' "$1" | sed -E 's/<src p="([^"]*)" sym="work:([0-9]+)"/\1:\2:work/'; } | sort -u; }   # bundle or whole-file
SP4="$TMP/sp4"; mkwork "$SP4" 4
( cd "$SP4" && "$BIN" . --expand=work --pack-budget-bytes=3500 --no-cache ) >"$TMP/sp4.xml" 2>/dev/null
un4="$( attrOf unserved_next "$TMP/sp4.xml" )"
grep -q 'unserved_total="3"' "$TMP/sp4.xml" && case "$un4" in "--expand=&apos;sub dir/"*) true ;; *) false ;; esac \
    && ok "(N) space path: unserved_total=\"3\" and unserved_next is single-quoted for the shell" \
    || no "(N) space path: $( grep -oE '<ctx[^>]*>' "$TMP/sp4.xml" | head -1 )"
rootOf "$TMP/sp4.xml" | grep -q 'unserved_listed=' \
    && no "(N) negative: unserved_listed= appeared though all 3 cut definitions are listed" \
    || ok "(N) negative: no unserved_listed= when every cut definition is listed"
( cd "$SP4" && eval "\"\$BIN\" . --no-cache $( printf '%s' "$un4" | xmlUnesc )" ) >"$TMP/sp4_paste.xml" 2>/dev/null
[ "$( selectorsOf "$un4" | wc -l | tr -d ' ' )" = 3 ] && [ "$( servedAnyOf "$TMP/sp4_paste.xml" )" = "$( selectorsOf "$un4" )" ] \
    && ok "(N) space path: the pasted unserved_next serves exactly the 3 cut definitions" \
    || no "(N) space path: pasted unserved_next served [$( servedAnyOf "$TMP/sp4_paste.xml" | tr '\n' ' ' )], listed [$( selectorsOf "$un4" | tr '\n' ' ' )]"
SP20="$TMP/sp20"; mkwork "$SP20" 20
( cd "$SP20" && "$BIN" . --expand=work --pack-budget-bytes=3500 --no-cache ) >"$TMP/sp20.xml" 2>/dev/null
tot20="$( attrOf unserved_total "$TMP/sp20.xml" )"; un20="$( attrOf unserved_next "$TMP/sp20.xml" )"
served20="$( servedOf "$TMP/sp20.xml" | wc -l | tr -d ' ' )"
[ -n "$tot20" ] && [ "$tot20" -gt 16 ] && [ "$(( tot20 + served20 ))" = 20 ] && rootOf "$TMP/sp20.xml" | grep -q 'unserved_listed="16"' \
    && ok "(N) >16 cut: unserved_total=\"$tot20\" (+$served20 served = 20) and unserved_listed=\"16\"" \
    || no "(N) >16 cut: total='$tot20' served=$served20: $( grep -oE '<ctx[^>]*>' "$TMP/sp20.xml" | head -1 | cut -c1-300 )"
( cd "$SP20" && eval "\"\$BIN\" . --no-cache $( printf '%s' "$un20" | xmlUnesc )" ) >"$TMP/sp20_paste.xml" 2>/dev/null
[ "$( selectorsOf "$un20" | wc -l | tr -d ' ' )" = 16 ] && [ "$( servedAnyOf "$TMP/sp20_paste.xml" )" = "$( selectorsOf "$un20" )" ] \
    && rootOf "$TMP/sp20_paste.xml" | grep -q 'schema=' && ! rootOf "$TMP/sp20_paste.xml" | grep -q 'unserved_' \
    && ok "(N) >16 cut: the pasted unserved_next serves exactly the 16 it lists, and nothing is cut in that answer" \
    || no "(N) >16 cut: pasted unserved_next served $( servedAnyOf "$TMP/sp20_paste.xml" | wc -l | tr -d ' ' ): $( rootOf "$TMP/sp20_paste.xml" | cut -c1-200 )"
( cd "$SP20" && "$BIN" . --expand=work --pack-budget-bytes=1000000 --no-cache ) >"$TMP/sp20_all.xml" 2>/dev/null   # (deprecated knob, still the one that cut)
[ "$( servedAnyOf "$TMP/sp20_all.xml" | wc -l | tr -d ' ' )" = 20 ] && rootOf "$TMP/sp20_all.xml" | grep -q 'schema=' && ! rootOf "$TMP/sp20_all.xml" | grep -q 'unserved_' \
    && [ -z "$( comm -23 <( servedOf "$TMP/sp20_paste.xml" ) <( servedAnyOf "$TMP/sp20_all.xml" ) )" ] \
    && ok "(N) >16 cut: the rest are recoverable — a larger --pack-budget-bytes serves all 20, no unserved_*" \
    || no "(N) >16 cut: the larger-budget call did not serve all 20: $( grep -oE '<ctx[^>]*>' "$TMP/sp20_all.xml" | head -1 | cut -c1-200 )"

# ── (O) fix round 1 (review N1): several --outline tokens keep the ordinary map (the lean rule is for ONE token) ─────
"$BIN" "$FIX" --outline=uniqueTarget,dupTarget --no-cache >"$TMP/ol2.xml" 2>/dev/null
grep -q '<r ' "$TMP/ol2.xml" && ! grep -qE 'topk_default=|map_next=|unserved_' "$TMP/ol2.xml" \
    && ok "(O) multi-token --outline keeps the ordinary map, no lean decoration" \
    || no "(O) multi-token --outline went lean or lost its map: $( grep -oE '<ctx[^>]*>' "$TMP/ol2.xml" | head -1 )"

# ── (F) well-formedness + determinism ─────────────────────────────────────────────────────────────────
if command -v xmllint >/dev/null 2>&1; then
    for f in uniq dup5 dup tk5 tk0 big real_default real_tk0 mdef cut ol olcut emit mroot scope sp4 sp20 sp20_paste ol2; do
        if xmllint --noout "$TMP/$f.xml" 2>/dev/null; then ok "(F) $f.xml well-formed"; else no "(F) $f.xml fails xmllint"; fi
    done
else
    printf '  SKIP  xmllint not installed\n'
fi
"$BIN" "$FIX" --expand=uniqueTarget --no-cache >"$TMP/uniq2.xml" 2>/dev/null
diff -q "$TMP/uniq.xml" "$TMP/uniq2.xml" >/dev/null \
    && ok "(F) exact-name default output byte-identical across two runs" \
    || no "(F) exact-name default output non-deterministic"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
