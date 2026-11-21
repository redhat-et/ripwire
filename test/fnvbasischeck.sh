#!/usr/bin/env bash
# fnvbasischeck.sh — FNV-1a 64 has ONE home for its seeds: src/infra/hashutil.h.
#
# THE DEFECT (FNV-SEED-ONE, 2026-11-19). The FNV-1a 64 offset basis was typed out 24 times under src/ with TWO values:
# 14695981039346656037 (the published basis, 13 sites) and 1469598103934665603 (the same digits with the last one
# dropped, 11 sites). The short one keys stored formats (cache blob names, the cache-root key, file-content hashes,
# persisted lexical statistics, the clone sketch, edit-lock and remote-clone names), so it cannot be corrected in place
# (quality.h kCacheRootKeySeed's comment measures why); three build-local hashes had copied it from a neighbour.
# hashutil.h now names both — kFnv1aOffset64 and kFnv1aLegacySeed64 — and holds the one fnv1a64 loop.
#
#   (a) no FNV-1a 64 basis literal, in either spelling, decimal or hex (both seeds), on a code line of any src/ file except
#       src/infra/hashutil.h. Red on the base: 24 sites. A comment may quote the digits (quality.h's history does).
#   (b) hashutil.h's kFnv1aOffset64 is the published basis and kFnv1aLegacySeed64 the 17-digit stored seed, digit for
#       digit, and the static_assert test vectors in it are the values a reference FNV-1a 64 (computed here) gives.
#   (c) the static_asserts bite: hashutil.h compiles as shipped, and FAILS to compile with kFnv1aOffset64 set to the
#       17-digit value. Skipped with a NOTE when no C++23 compiler is on PATH (the build legs compile it anyway).
#   (n) non-vacuity: the scanner fires on a probe tree holding each spelling, stays silent on its named twin, and
#       read a src/ population large enough to be the real tree.
#
# Usage:  bash test/fnvbasischeck.sh [BIN]     (BIN is unused: every arm reads the source)
#         RIPWIRE_FNV_SRC=<base>/src bash test/fnvbasischeck.sh    — the red-first run against a base checkout
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
SRC="${RIPWIRE_FNV_SRC:-$ROOT/src}"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
note(){ printf '  NOTE  %s\n' "$*"; }

command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "fnvbasischeck: SRC=$SRC"

cat > "$TMP/scan.py" <<'SCANPY'
# python3 scan.py TREE → one "path:line: text" row per FNV basis literal on a code line, then "files=N" on stderr.
import os, re, sys
tree = sys.argv[1]
lit = re.compile( r'(?<![0-9A-Za-z_])(?:14695981039346656037|1469598103934665603|0[xX]cbf29ce484222325|0[xX]14650fb0739d0383)(?:[uUlL]*)(?![0-9A-Za-z_])', re.I )
files = 0
for dp, dns, fns in os.walk( tree ):
    dns.sort()
    for fn in sorted( fns ):
        if not fn.endswith( ( '.h', '.hpp', '.cpp', '.cc', '.c' ) ):
            continue
        path = os.path.join( dp, fn )
        rel = os.path.relpath( path, tree ).replace( os.sep, '/' )
        if rel == 'infra/hashutil.h':
            continue
        files += 1
        with open( path, encoding='utf-8', errors='replace' ) as f:
            for n, line in enumerate( f, 1 ):
                code = line.split( '//', 1 )[0]
                if code.lstrip().startswith( '*' ):
                    continue
                if lit.search( code ):
                    print( '%s:%d: %s' % ( rel, n, line.strip() ) )
print( 'files=%d' % files, file=sys.stderr )
SCANPY

echo
echo "=== (a) no FNV basis literal outside infra/hashutil.h ==="
python3 "$TMP/scan.py" "$SRC" > "$TMP/hits.txt" 2> "$TMP/scan.err"; rc=$?
files="$( sed -n 's/^files=//p' "$TMP/scan.err" )"
hits="$( wc -l < "$TMP/hits.txt" | tr -d ' ' )"
if [ "$rc" -ne 0 ]; then no "(a) the scanner exited $rc"; cat "$TMP/scan.err"
elif [ "$hits" -eq 0 ]; then ok "(a) 0 basis literals on code lines across $files src files — every site names hashutil's constant"
else no "(a) $hits basis literal(s) outside infra/hashutil.h — use hashutil::kFnv1aOffset64 (or kFnv1aLegacySeed64 for a stored key):"; sed 's/^/        /' "$TMP/hits.txt"
fi

echo
echo "=== (n) non-vacuity ==="
if [ "${files:-0}" -ge 250 ]; then ok "(n) the scan read $files src files (the real tree)"; else no "(n) the scan read only ${files:-0} src files — not the real tree"; fi
mkdir -p "$TMP/probe/infra"
cat > "$TMP/probe/bad.h" <<'EOF'
std::uint64_t a = 14695981039346656037ull;
std::uint64_t b = 1469598103934665603ULL;
std::uint64_t c = 0xcbf29ce484222325ull;
    lane = { 1469598103934665603, 1 };
std::uint64_t d = 0x14650FB0739D0383ULL;
EOF
cat > "$TMP/probe/good.h" <<'EOF'
std::uint64_t a = hashutil::kFnv1aOffset64;            // was 14695981039346656037ull
std::uint64_t b = hashutil::kFnv1aLegacySeed64;
std::uint64_t c = 146959810393466560371ull;   // a longer number is not the basis
 * the doc block may quote 1469598103934665603 too
EOF
cp "$SRC/infra/hashutil.h" "$TMP/probe/infra/hashutil.h"
python3 "$TMP/scan.py" "$TMP/probe" > "$TMP/probe.txt" 2>/dev/null
pb="$( grep -c '^bad.h:' "$TMP/probe.txt" )"; pg="$( grep -c '^good.h:' "$TMP/probe.txt" )"; ph="$( grep -c '^infra/hashutil.h:' "$TMP/probe.txt" )"
if [ "$pb" -eq 5 ]; then ok "(n) all 5 spellings in the probe fire (decimal 20- and 17-digit, either suffix case, hex of both, unsuffixed)"
else no "(n) the probe's 5 literals gave $pb hits"; cat "$TMP/probe.txt"; fi
if [ "$pg" -eq 0 ]; then ok "(n) the named twin, a comment quote and a longer number stay silent"
else no "(n) the compliant twin fired $pg time(s)"; cat "$TMP/probe.txt"; fi
if [ "$ph" -eq 0 ]; then ok "(n) infra/hashutil.h — the one home — is exempt"; else no "(n) the home file was scanned"; fi

echo
echo "=== (b) the two constants and the test vectors, digit for digit ==="
H="$SRC/infra/hashutil.h"
python3 - "$H" > "$TMP/b.txt" <<'PY'
import re, sys
s = open( sys.argv[1], encoding='utf-8' ).read()
def const( name ):
    m = re.search( r'constexpr\s+std::uint64_t\s+' + name + r'\s*=\s*([0-9]+)ull\s*;', s )
    return int( m.group( 1 ) ) if m else None
def fnv( b, h ):
    for c in b:
        h = ( ( h ^ c ) * 1099511628211 ) & 0xFFFFFFFFFFFFFFFF
    return h
off, leg = const( 'kFnv1aOffset64' ), const( 'kFnv1aLegacySeed64' )
print( 'offset', 'ok' if off == 14695981039346656037 else 'BAD %r' % off )
print( 'legacy', 'ok' if leg == 1469598103934665603 else 'BAD %r' % leg )
vec = re.findall( r'static_assert\(\s*fnv1a64\(\s*"((?:[^"\\]|\\.)*)"\s*\)\s*==\s*0x([0-9a-fA-F]+)ull', s )
print( 'vectors', len( vec ) )
for text, hexv in vec:
    want = fnv( text.encode(), 14695981039346656037 )
    print( 'vector', repr( text ), 'ok' if want == int( hexv, 16 ) else 'BAD want %016x' % want )
PY
if grep -q '^offset ok$' "$TMP/b.txt"; then ok "(b) kFnv1aOffset64 = 14695981039346656037, the published FNV-1a 64 basis"
else no "(b) kFnv1aOffset64 is not the published basis"; cat "$TMP/b.txt"; fi
if grep -q '^legacy ok$' "$TMP/b.txt"; then ok "(b) kFnv1aLegacySeed64 = 1469598103934665603, the stored seed every on-disk key was written with"
else no "(b) kFnv1aLegacySeed64 moved — every stored key would be orphaned"; cat "$TMP/b.txt"; fi
nv="$( sed -n 's/^vectors //p' "$TMP/b.txt" )"
if [ "${nv:-0}" -ge 3 ] && ! grep -q '^vector .* BAD' "$TMP/b.txt"; then ok "(b) $nv static_assert test vectors match a reference FNV-1a 64"
else no "(b) static_assert vectors: ${nv:-0} found (want >= 3) or one disagrees with the reference"; cat "$TMP/b.txt"; fi

echo
echo "=== (c) the static_asserts bite ==="
CXX="${CXX:-}"
if [ -z "$CXX" ]; then for c in c++ clang++ g++; do command -v "$c" >/dev/null 2>&1 && { CXX="$c"; break; }; done; fi
if [ -z "$CXX" ]; then
    note "(c) no C++ compiler on PATH — skipped (every build leg compiles hashutil.h's static_asserts)"
else
    mkdir -p "$TMP/cc/infra"
    printf '#include "infra/hashutil.h"\nint main() { return 0; }\n' > "$TMP/cc/tu.cpp"
    cc(){ "$CXX" -std=c++23 -fsyntax-only -I"$TMP/cc" -I"$SRC/infra" -I"$SRC" -I"$ROOT/third_party" "$TMP/cc/tu.cpp" 2> "$TMP/cc/err.txt"; }
    cp "$H" "$TMP/cc/infra/hashutil.h"
    printf '#include <cstdint>\n#include <print>\nint main() { return 0; }\n' > "$TMP/cc/probe23.cpp"
    if ! "$CXX" -std=c++23 -fsyntax-only "$TMP/cc/probe23.cpp" 2> "$TMP/cc/probe23.err"; then
        note "(c) $CXX cannot compile a minimal C++23 unit here — skipped; the build legs compile hashutil.h's static_asserts:"; head -3 "$TMP/cc/probe23.err"
    elif cc; then
        ok "(c) hashutil.h compiles as shipped ($CXX)"
        sed 's/kFnv1aOffset64 = 14695981039346656037ull/kFnv1aOffset64 = 1469598103934665603ull/' "$H" > "$TMP/cc/infra/hashutil.h"
        if cmp -s "$H" "$TMP/cc/infra/hashutil.h"; then no "(c) could not plant the 17-digit basis (the definition's spelling moved)"
        elif cc; then no "(c) hashutil.h still compiles with the 17-digit basis — the test vectors do not pin it"
        elif grep -q 'published offset basis' "$TMP/cc/err.txt"; then ok "(c) with the 17-digit basis planted, the static_assert stops the build"
        else no "(c) the planted build failed, but not on the basis static_assert:"; head -5 "$TMP/cc/err.txt"; fi
    else
        no "(c) hashutil.h as shipped does not compile standalone with $CXX (a minimal C++23 unit does):"; head -5 "$TMP/cc/err.txt"
    fi
fi

echo
if [ "$fail" -eq 0 ]; then echo "fnvbasischeck: PASS"; exit 0; fi
echo "fnvbasischeck: FAIL"; exit 1
