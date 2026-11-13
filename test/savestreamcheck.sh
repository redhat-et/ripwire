#!/usr/bin/env bash
# savestreamcheck.sh — SAVE-STREAM (card C1, reports/mem-audit-fable-1111 + mem-per-verb-1112): saveCache streams the blob
# into its temp file through a 4 MiB window (ByteW::flushWindow) instead of building the whole blob in one growing
# std::string. The window flushes only between records, so every offset the table records is a FILE offset (ByteW::pos)
# and every record checksum is taken over bytes still in the window; the header's entry count, settled only after the
# carry-over records, is patched into the file after the last flush. Any of those wrong and the next run reparses (the
# blob is refused or its records fail their checksums), which no answer shows: these arms read the blob and its reuse.
#
# Arms (fixture: 160 C++ files x 40 functions x 20 calls, a blob of several windows; a 3-file tree whose blob fits one):
#   P  premise: the big fixture's blob is larger than two windows (8 MiB), so the streamed path ran; the small one's is
#      under one window, so the in-memory path ran. Fails when either size does not hold (the arms below would be blind).
#   F  frame: for both blobs, the header's entry count (u32 at 21) equals the trailer's (u32 at size-16) and is not 0, and
#      size == tableOffset + entryCount*32 + 24 (red with the post-flush header patch removed: header count 0).
#   W  warm reuse: a second run over the same tree answers byte-identically and does not rewrite the blob (same inode and
#      mtime: every record loaded and verified, nothing dirty). Red with buffer-relative record offsets (ByteW::b.size()
#      in place of pos()): the records past the first window fail their checksums, the files reparse, the blob is rewritten.
#   C  carry-over through the window: a run that excludes half the tree and edits one kept file saves a blob whose excluded
#      half is copied verbatim out of the previous blob (appendCarryRecord); the full tree after it is warm (no rewrite) and
#      answers byte-identically to a --no-cache run of the same tree.
#
# Usage: bash test/savestreamcheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
case "$BIN" in /*) ;; *) BIN="$PWD/$BIN" ;; esac
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ fail=1; printf '  FAIL  %s\n' "$*"; return 0; }

if ! "$BIN" --version 2>/dev/null | grep -q '^ripwire '; then
    echo "  FAIL  $BIN does not run"; echo "FAIL savestreamcheck"; exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo "  SKIP  python3 not found (the fixture generator and the blob reader)"; echo "PASS savestreamcheck"; exit 0
fi

BIG="$TMP/big"; SMALL="$TMP/small"; mkdir -p "$BIG/a" "$BIG/b" "$SMALL"
python3 - "$BIG" "$SMALL" <<'PY'
import sys, os
big, small = sys.argv[1], sys.argv[2]
for f in range( 160 ):
    half = "a" if f % 2 == 0 else "b"
    out = []
    for fn in range( 40 ):
        calls = "\n".join( f"    helper_{f}_{( fn + c ) % 40}( {c} );" for c in range( 20 ) )
        out.append( f"int helper_{f}_{fn}( int v );\nint fn_{f}_{fn}()\n{{\n{calls}\n    return {fn};\n}}" )
    open( os.path.join( big, half, f"unit{f}.cpp" ), "w" ).write( "\n".join( out ) + "\n" )
for f in range( 3 ):
    open( os.path.join( small, f"s{f}.cpp" ), "w" ).write( f"int s{f}() {{ return {f}; }}\nint t{f}() {{ return s{f}(); }}\n" )
PY

HOMEDIR="$TMP/home"; mkdir -p "$HOMEDIR"
run(){   # tree cachefile out [extra args...]
    local tree="$1" cache="$2" out="$3"; shift 3
    ( cd "$tree" && env HOME="$HOMEDIR" TMPDIR="$TMP/" "$BIN" "$tree" --cache="$cache" --deps "$@" > "$out" 2> "$out.err" )
}
frame(){   # blob -> "size hdrCount trailerCount tableOffset"
    python3 - "$1" <<'PY'
import struct, sys, os
p = sys.argv[1]; b = open( p, "rb" ).read()
hdr = struct.unpack_from( "<I", b, 21 )[ 0 ]
off, cnt = struct.unpack_from( "<QI", b, len( b ) - 24 )
print( len( b ), hdr, cnt, off )
PY
}
stamp(){ python3 -c 'import os,sys; s=os.stat(sys.argv[1]); print(s.st_ino, s.st_mtime_ns)' "$1"; }

# ---- cold runs ----
run "$BIG" "$TMP/big.blob" "$TMP/big1.out"; rc1=$?
run "$SMALL" "$TMP/small.blob" "$TMP/small1.out"; rc2=$?
if [ "$rc1" -ne 0 ] || [ "$rc2" -ne 0 ] || [ ! -s "$TMP/big.blob" ] || [ ! -s "$TMP/small.blob" ]; then
    no "P: the cold runs failed or wrote no blob (big rc=$rc1, small rc=$rc2)"; echo "FAIL savestreamcheck"; exit 1
fi

# ---- P ----
read -r bsz bhdr bcnt boff <<<"$( frame "$TMP/big.blob" )"
read -r ssz shdr scnt soff <<<"$( frame "$TMP/small.blob" )"
win=$(( 4 * 1024 * 1024 ))
if [ "${bsz:-0}" -gt $(( 2 * win )) ] && [ "${ssz:-0}" -gt 0 ] && [ "${ssz:-0}" -lt "$win" ]; then
    ok "P: the big blob is $bsz B (more than two 4 MiB windows: streamed); the small one $ssz B (one window, in memory)"
else
    no "P: blob sizes do not exercise both paths: big $bsz B (want > $(( 2 * win ))), small $ssz B (want < $win)"
fi

# ---- F ----
for which in big small; do
    if [ "$which" = big ]; then sz=$bsz h=$bhdr c=$bcnt o=$boff; else sz=$ssz h=$shdr c=$scnt o=$soff; fi
    if [ "${h:-0}" -gt 0 ] && [ "$h" = "$c" ] && [ "$sz" -eq $(( o + c * 32 + 24 )) ]; then
        ok "F: $which blob frame holds: header count $h = trailer count $c, size $sz = table at $o + $c x 32 + 24"
    else
        no "F: $which blob frame broken: header count $h, trailer count $c, size $sz, table at $o"
    fi
done

# ---- W ----
before="$( stamp "$TMP/big.blob" )"
run "$BIG" "$TMP/big.blob" "$TMP/big2.out"; rcw=$?
after="$( stamp "$TMP/big.blob" )"
if [ "$rcw" -eq 0 ] && cmp -s "$TMP/big1.out" "$TMP/big2.out" && [ "$before" = "$after" ]; then
    ok "W: the warm run answers byte-identically and leaves the streamed blob unrewritten (every record reused)"
else
    no "W: warm rc=$rcw, answer identical=$( cmp -s "$TMP/big1.out" "$TMP/big2.out" && echo yes || echo no ), blob stamp $before -> $after (a rewrite means records were refused)"
fi

# ---- C ----
printf 'int carry_probe_fn() { return 7; }\n' >> "$BIG/a/unit0.cpp"
run "$BIG" "$TMP/big.blob" "$TMP/big3.out" --exclude=b/; rcx=$?
read -r xsz xhdr xcnt xoff <<<"$( frame "$TMP/big.blob" )"
mid="$( stamp "$TMP/big.blob" )"
run "$BIG" "$TMP/big.blob" "$TMP/big4.out"; rcf=$?
end="$( stamp "$TMP/big.blob" )"
probe="$( grep -c 'carry_probe_fn' "$TMP/big4.out" )"
if [ "$rcx" -ne 0 ] || [ "$rcf" -ne 0 ]; then
    no "C: the excluded or the full run failed (rc $rcx / $rcf)"
elif [ "$mid" = "$after" ]; then
    no "C: premise: the excluded run with an edited file did not save a blob, so no carry-over was written"
elif [ "${xhdr:-0}" != "$bcnt" ] || [ "$xhdr" != "$xcnt" ] || [ "$xsz" -ne $(( xoff + xcnt * 32 + 24 )) ]; then
    no "C: the carry-over blob's frame: header count $xhdr, trailer $xcnt (want $bcnt: 80 fresh + 80 carried), size $xsz, table at $xoff"
elif [ "$mid" != "$end" ]; then
    no "C: the full run after the carry-over rewrote the blob: carried records were refused"
else
    ok "C: the carry-over blob ($xhdr entries) serves the full tree warm, no rewrite (the edited file answered: $probe probe rows in --deps, which lists no functions)"
fi
if [ "$rcf" -eq 0 ] && [ "$rcw" -eq 0 ]; then
    if ( cd "$BIG" && env HOME="$HOMEDIR" TMPDIR="$TMP/" "$BIN" "$BIG" --no-cache --deps > "$TMP/big5.out" 2>/dev/null ) && cmp -s "$TMP/big4.out" "$TMP/big5.out"; then
        ok "C: the full run over the carried blob answers byte-identically to a --no-cache run of the same tree"
    else
        no "C: the full run over the carried blob differs from a --no-cache run of the same tree"
    fi
fi

if [ "$fail" -eq 0 ]; then echo "PASS savestreamcheck"; exit 0; fi
echo "FAIL savestreamcheck"; exit 1
