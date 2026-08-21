#!/usr/bin/env bash
# metalcheck.sh — the gate for Metal Shading Language (.metal) + dual-compile-header coverage.
#
#   test/metalcheck.sh
#   RIPWIRE_BIN=asan/ripwire test/metalcheck.sh
#
# THE FAILURE THIS PINS: `--callers=ml_styleFor` returned 0 on a real Metal repo — every .metal shader
# was outside the crawl, so the GPU half of a dual-compile codebase was invisible to the call graph and
# the agent fell back to grep. `.metal` is now indexed with the C++ grammar and the C++ tags.scm (MSL is
# a C++14 dialect); no Metal grammar and no Metal tags.scm exist, deliberately (see kLangTable's comment
# in src/ingest.cpp for the measurements that decided it).
#
# The fixture test/metalfix/ is the smallest thing that carries every construct the C++ grammar has no
# keyword for, so this gate fails the day tree-sitter's error recovery stops localising them:
#   GalleryShaders.metal — `kernel`/`vertex`/`fragment` function qualifiers, `constant`/`device`/
#                          `threadgroup` address spaces, `[[buffer(0)]]`-style attribute bindings,
#                          `texture2d<float, access::write>` template types, and the `#import` spelling
#                          of `#include` (10 of the 45 real shaders in the measured reference tree do).
#   AAPLSharedTypes.h    — the DUAL-COMPILE header: `#if __METAL_VERSION__` guards, an MSL `constant`
#                          module-scope table, and ml_styleFor, the symbol both halves call.
#   galleryHost.cpp      — the CPU half, calling that same ml_styleFor.
#
# Exit 0 = ALL PASS, non-zero = SOME FAILED.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/metalfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no fixture at $FIX"; exit 2; }

echo "metalcheck: BIN=$BIN  FIX=$FIX"

"$BIN" "$FIX" --no-cache >"$TMP/map" 2>/dev/null
MAP="$( cat "$TMP/map" )"

# ── 1) the .metal file is crawled at all (the whole premise) ──────────────────────────────────────────
printf '%s' "$MAP" | grep -q 'f p="[^"]*GalleryShaders\.metal"' \
    && ok ".metal is crawled and indexed (it was skipped entirely before)" \
    || { no ".metal file absent from the map — the extension is not registered"; printf '%s\n' "$MAP" | head -c 800; }

# ── 2) each MSL function-qualifier flavour survives error recovery as a real definition ───────────────
#     `kernel void f()` / `vertex Out f()` / `fragment float4 f()` put the return type inside an ERROR
#     node under the C++ grammar; the enclosing function_definition must still yield the def.
for sym in gallery_prefilter gallery_vertexSphere gallery_fragmentSphere gallery_falloff; do
    printf '%s' "$MAP" | grep -q "n=\"$sym\"" \
        && ok "MSL definition extracted: $sym" \
        || no "MSL definition MISSING: $sym (qualifier recovery regressed)"
done

# ── 3) NO garbage symbols: an MSL-only keyword must never become a symbol name ─────────────────────────
junk=0
for kw in kernel vertex fragment constant device threadgroup texture2d access half4 float4; do
    printf '%s' "$MAP" | grep -q "n=\"$kw\"" && { no "keyword leaked in as a symbol name: $kw"; junk=1; }
done
[ $junk -eq 0 ] && ok "no MSL keyword leaked in as a symbol name (kernel/vertex/fragment/constant/device/threadgroup/…)"

# ── 4) NO phantom scope: `vertex Out f()` recovers as a qualified_identifier with a MISSING `::`, which
#      would publish the RETURN TYPE as a class scope (`Out::f`). qualifierOf rejects a missing separator.
printf '%s' "$MAP" | grep -q 'GalleryVertexOut::gallery_vertexSphere' \
    && { no "phantom scope published: gallery_vertexSphere claims to be a member of its return type"; } \
    || ok "no phantom scope on a qualifier-prefixed entry point (return type is not published as a class)"

# ── 5) THE ACCEPTANCE CASE: a dual-compile header's symbol is reachable from BOTH halves ───────────────
"$BIN" "$FIX" --no-cache --callers=ml_styleFor >"$TMP/callers" 2>/dev/null
C="$( cat "$TMP/callers" )"
printf '%s' "$C" | grep -q 'GalleryShaders\.metal' \
    && ok "--callers=ml_styleFor names a .metal caller (was count=0 before Metal was indexed)" \
    || { no "--callers=ml_styleFor has no .metal caller"; printf '%s\n' "$C"; }
printf '%s' "$C" | grep -q 'galleryHost\.cpp' \
    && ok "--callers=ml_styleFor still names the C++ host caller (both graphs reach the shared header)" \
    || { no "--callers=ml_styleFor lost the C++ caller"; printf '%s\n' "$C"; }
CN="$( printf '%s' "$C" | sed -n 's/.*<callers [^>]*count="\([0-9]*\)".*/\1/p' )"
[ "${CN:-0}" -ge 4 ] \
    && ok "--callers=ml_styleFor count=$CN (2 shader + 2 host)" \
    || no "--callers=ml_styleFor count=${CN:-?} (want >= 4)"

# ── 6) --uses surfaces the .metal use-sites with a call role and file:line ────────────────────────────
"$BIN" "$FIX" --no-cache --uses=ml_styleFor >"$TMP/uses" 2>/dev/null
grep -q 'role="call" p="[^"]*GalleryShaders\.metal:[0-9]' "$TMP/uses" \
    && ok "--uses=ml_styleFor reports the .metal use-sites (role=call, file:line)" \
    || { no "--uses=ml_styleFor missing .metal use-sites"; head -c 700 "$TMP/uses"; }
UN="$( sed -n 's/.*<uses [^>]*count="\([0-9]*\)".*/\1/p' "$TMP/uses" )"
[ "${UN:-0}" -ge 4 ] && ok "--uses=ml_styleFor count=$UN" || no "--uses=ml_styleFor count=${UN:-?} (want >= 4)"

# ── 7) shader-internal call edges resolve (not just the cross-half one) ───────────────────────────────
"$BIN" "$FIX" --no-cache --callers=gallery_falloff >"$TMP/gf" 2>/dev/null
grep -q 'gallery_fragmentSphere' "$TMP/gf" && grep -q 'gallery_prefilter' "$TMP/gf" \
    && ok "shader-internal call edges resolve (gallery_falloff <- fragment + kernel)" \
    || { no "shader-internal call edges missing"; cat "$TMP/gf"; }

# ── 8) `#import` is an include edge. The C/C++ grammar has NO #import rule (the objc grammar does), so
#      it arrives as a generic preproc_call and must still be captured — this is what physically links a
#      shader to its FX headers. `#pragma`/`#error` share that node type and must NOT become edges.
"$BIN" "$FIX" --no-cache --deps >"$TMP/deps" 2>/dev/null
tr '<' '\n' < "$TMP/deps" | grep -A3 'GalleryShaders\.metal' | grep -q 'inc t="AAPLSharedTypes\.h"' \
    && ok '#import "AAPLSharedTypes.h" became an include edge from the .metal' \
    || { no '#import did not produce an include edge'; cat "$TMP/deps"; }
printf 'int probeFn( void ) { return 1; }\n' > "$TMP/np.cpp"
mkdir -p "$TMP/np"; mv "$TMP/np.cpp" "$TMP/np/np.cpp"
printf '#pragma once\n#error nope\n#warning meh\nint probeHdr( void );\n' > "$TMP/np/np.h"
"$BIN" "$TMP/np" --no-cache --deps 2>/dev/null | grep -q '<inc ' \
    && { no "a non-#import preproc_call (#pragma/#error/#warning) leaked in as an include edge"; } \
    || ok "#pragma / #error / #warning do NOT become include edges (only #import does)"

# ── 9) bodies are the VERBATIM source: no pre-parse scrub rewrote the shader text ─────────────────────
"$BIN" "$FIX" --no-cache --expand=gallery_prefilter >"$TMP/exp" 2>/dev/null
grep -q 'kernel void gallery_prefilter' "$TMP/exp" \
    && ok "--expand returns the verbatim MSL body (the qualifier is not blanked out)" \
    || { no "--expand body text was rewritten"; head -c 600 "$TMP/exp"; }

# ── 10) determinism + G4 well-formedness + minification ───────────────────────────────────────────────
"$BIN" "$FIX" --no-cache >"$TMP/a" 2>/dev/null
"$BIN" "$FIX" --no-cache >"$TMP/b" 2>/dev/null
cmp -s "$TMP/a" "$TMP/b" && ok "determinism (two cold runs byte-identical)" || no "non-deterministic on a .metal corpus"
"$BIN" "$FIX" >"$TMP/w1" 2>/dev/null; "$BIN" "$FIX" >"$TMP/w2" 2>/dev/null
cmp -s "$TMP/w1" "$TMP/w2" && ok "determinism (warm/cached runs byte-identical)" || no "warm run differs from itself"
cmp -s "$TMP/a" "$TMP/w2" && ok "warm run matches the cold run (cache carries .metal facts correctly)" \
                          || no "warm .metal run differs from cold — cache/parserVer mismatch"
# The same warm/cold identity on the CANONICAL-ID surface specifically. The per-def `scope` field is
# CACHED, so the phantom-scope guard is an extraction change: a blob written before it was added serves
# the old `Out::f` ids warm while a cold run says `f`. That really happened mid-development (kParserVer
# 29 → 30) — pin it on the verb that shows canonical ids, not just on the map.
"$BIN" "$FIX" --no-cache --uses=ml_styleFor >"$TMP/uc" 2>/dev/null
"$BIN" "$FIX"            --uses=ml_styleFor >"$TMP/uw" 2>/dev/null
cmp -s "$TMP/uc" "$TMP/uw" && ok "warm == cold on canonical ids (--uses; the cached scope field is not stale)" \
                           || { no "warm/cold canonical-id mismatch — a cached extraction field changed without a kParserVer bump"; diff "$TMP/uc" "$TMP/uw" | head -4; }
if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$TMP/a" 2>/dev/null && ok "G4: .metal map XML well-formed" || no "G4: malformed XML on a .metal corpus"
else
    ok "xmllint unavailable — G4 skipped"
fi
[ "$( grep -c '' "$TMP/a" )" -le 1 ] && ok "output is minified (no stray newlines)" || no "newlines outside CDATA"

# ── 11) the user-visible language list names Metal (doc/binary agreement) ─────────────────────────────
"$BIN" --help 2>&1 | grep -qi 'Metal' \
    && ok "--help advertises Metal" || no "--help does not mention Metal"
grep -qi 'Metal' "$ROOT/README.md" \
    && ok "README advertises Metal" || no "README does not mention Metal"

[ $fail -eq 0 ] && echo "metalcheck: ALL PASS" || echo "metalcheck: FAILURES"
exit $fail
