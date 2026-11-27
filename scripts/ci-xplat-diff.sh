#!/usr/bin/env bash
# ci-xplat-diff.sh — Windows vs Linux: the same verbs on the same fixture must print the same bytes.
#
# Reads two directories written by scripts/ci-xplat-outputs.sh (Linux: the ubuntu-24.04 Release clang leg; Windows:
# the packaged, UNZIPPED windows-x64 release binary) and applies exactly these rules — nothing is normalised away:
#   R1 identity   every output the Linux side wrote (*.xml, *.rc, *.json, *.txt; *.err is platform notes and is
#                 skipped) exists on the Windows side and is byte-identical. No path-separator, line-ending or
#                 case folding is applied: '/' is the only separator either platform may print, and "\n" the only
#                 line ending (stdout is binary on Windows, os::init_process).
#   R2 separator  the Windows-only bslash-map.xml (root typed as test\fixture) is byte-identical to Linux's
#                 repo-map.xml: a root typed with '\' enters the program as '/' (os::normalize_path_arg), and root=
#                 and every p= print it that way.
#   R3 CRLF       on EACH side, crlf-{map,for,callers,impact} equal tree-{map,for,callers,impact}: CRLF line endings
#                 change no symbol, rank, edge, line number or count. crlf-expand is narrowed, not exempt: on EACH
#                 side, crlf-expand must equal tree-expand once CR bytes and the reason=/est_tokens= attributes are
#                 dropped — so a CRLF-only line-number (l=) or symbol-list bug in --expand is still caught even when
#                 the two platforms happen to agree. It is also still under R1, so both platforms must print the
#                 SAME CRLF bytes.
#                 crlf-for is strict OUTSIDE its <fold kind="bodies"> element (train 31 body-fold): the fold carries whole source
#                 bodies, as --expand does, so on EACH side crlf-for must equal tree-for byte for byte once est_tokens= (which
#                 prices those bodies) is masked and, INSIDE the fold only, the CR bytes and a skip's bytes= (the source span's
#                 size) are dropped — the same narrowing crlf-expand gets, applied to the same body text and nowhere else.
#                 The same holds for the <doc_body> element (FOR-DOC-BODY, 2026-11-06): it serves a doc file's best sections as
#                 verbatim source text, so a CRLF copy carries the CR bytes in the sections and in its bytes= count; inside
#                 <doc_body> only, those two are dropped, and everything outside it stays strict.
#   R0 rc floor   every Linux-side *.rc must be 0. A verb that fails the same way on both platforms (rc != 0 on
#                 both, same error bytes) would otherwise pass R1 vacuously.
# Usage: bash scripts/ci-xplat-diff.sh <linux outputs dir> <windows outputs dir>
set -u
LIN="${1:?usage: ci-xplat-diff.sh <linux dir> <windows dir>}"
WIN="${2:?usage: ci-xplat-diff.sh <linux dir> <windows dir>}"
fail=0
# verdict PASS|FAIL MESSAGE — a FAIL marks both the run and the rule being checked
verdict() { printf '  %s  %s\n' "$1" "$2"; if [ "$1" = FAIL ]; then fail=1; rulefail=1; fi; }
show() { # first differing bytes, readable
    diff <( tr '>' '\n' <"$1" ) <( tr '>' '\n' <"$2" ) | head -12 | sed 's/^/        /'
}

for f in "$LIN"/*.rc; do
    [ -e "$f" ] || continue
    [ "$( cat "$f" )" = 0 ] || verdict FAIL "R0 ${f##*/}: the Linux reference itself exited $( cat "$f" ) — a shared failure would pass R1"
done

n=0; rulefail=0
for f in "$LIN"/*.xml "$LIN"/*.rc "$LIN"/*.json "$LIN"/*.txt; do
    [ -e "$f" ] || continue
    b="${f##*/}"; n=$(( n + 1 ))
    if [ ! -e "$WIN/$b" ]; then
        verdict FAIL "R1 $b: written on Linux, missing on Windows"
    elif cmp -s "$f" "$WIN/$b"; then
        :
    else
        verdict FAIL "R1 $b differs (Linux $( wc -c <"$f" | tr -d ' ' ) B, Windows $( wc -c <"$WIN/$b" | tr -d ' ' ) B):"; show "$f" "$WIN/$b"
    fi
done
# 5 verbs x 3 copies + their 15 rc files + 3 MCP files. A short list means an output step silently wrote nothing.
if [ "$n" -lt 33 ]; then
    verdict FAIL "R1 only $n Linux outputs found in $LIN (expected >= 33): nothing meaningful was compared"
else
    [ "$rulefail" -eq 0 ] && verdict PASS "R1 all $n Linux outputs are byte-identical on Windows"
fi

if [ ! -e "$WIN/bslash-map.xml" ]; then
    verdict FAIL "R2 Windows side has no bslash-map.xml (run ci-xplat-outputs.sh with --windows)"
elif cmp -s "$LIN/repo-map.xml" "$WIN/bslash-map.xml" && [ "$( cat "$WIN/bslash-map.rc" 2>/dev/null )" = 0 ]; then
    verdict PASS "R2 a root typed test\\fixture on Windows maps byte-identically to test/fixture on Linux"
else
    verdict FAIL "R2 bslash-map.xml (rc=$( cat "$WIN/bslash-map.rc" 2>/dev/null )) differs from Linux repo-map.xml:"; show "$LIN/repo-map.xml" "$WIN/bslash-map.xml"
fi

rulefail=0
for side in "$LIN" "$WIN"; do
    for v in map callers impact; do
        if cmp -s "$side/tree-$v.xml" "$side/crlf-$v.xml"; then
            :
        else
            verdict FAIL "R3 ${side##*/}: crlf-$v.xml differs from tree-$v.xml — CRLF line endings changed a structural answer:"; show "$side/tree-$v.xml" "$side/crlf-$v.xml"
        fi
    done
done
nx() { tr -d '\r' <"$1" | sed -E 's/ (reason|est_tokens)="[^"]*"//g'; }
# the --for answer: est_tokens= masked everywhere; inside <fold>…</fold> and <doc_body>…</doc_body> only, CR bytes and bytes= dropped
nf() { python3 -c 'import re, sys
t = open( sys.argv[1], "rb" ).read().decode( "utf-8", "replace" )
t = re.sub( r" est_tokens=\"[^\"]*\"", "", t )
fold = lambda m: re.sub( r" bytes=\"[^\"]*\"", "", m.group( 0 ).replace( "\r", "" ) )
sys.stdout.write( re.sub( r"<(fold|doc_body) .*?</\1>", fold, t, flags = re.S ) )' "$1"; }
# normalise for|expand FILE -> the file through nf or nx; fails on a missing or empty input
normalise() {
    [ -s "$2" ] || return 1
    case "$1" in
        for )    nf "$2" ;;
        expand ) nx "$2" ;;
        * )      return 1 ;;
    esac
}
# normeq for|expand A B -> 0 equal, 1 differ, 2 unusable: an input that is missing or empty, or a normaliser that fails or
# prints nothing, is never compared (two empty streams would compare equal and pass R3 vacuously)
normeq() {
    local a b r; a="$( mktemp )"; b="$( mktemp )"
    if normalise "$1" "$2" >"$a" && normalise "$1" "$3" >"$b" && [ -s "$a" ] && [ -s "$b" ]; then
        cmp -s "$a" "$b"; r=$?; [ "$r" -le 1 ] || r=2
    else
        r=2
    fi
    rm -f "$a" "$b"; return "$r"
}
for side in "$LIN" "$WIN"; do
    normeq for "$side/tree-for.xml" "$side/crlf-for.xml"; r=$?
    if [ "$r" -eq 2 ]; then
        verdict FAIL "R3 ${side##*/}: tree-for.xml / crlf-for.xml missing, empty, or unreadable by the normaliser (python3) — nothing was compared"
    elif [ "$r" -ne 0 ]; then
        verdict FAIL "R3 ${side##*/}: crlf-for differs from tree-for beyond est_tokens= and its fold's CR bytes and skip bytes=:"; show "$side/tree-for.xml" "$side/crlf-for.xml"
    fi
done
for side in "$LIN" "$WIN"; do
    normeq expand "$side/tree-expand.xml" "$side/crlf-expand.xml"; r=$?
    if [ "$r" -eq 2 ]; then
        verdict FAIL "R3 ${side##*/}: tree-expand.xml / crlf-expand.xml missing, empty, or unreadable by the normaliser — nothing was compared"
    elif [ "$r" -ne 0 ]; then
        verdict FAIL "R3 ${side##*/}: crlf-expand differs from tree-expand beyond its CR bytes and reason=/est_tokens="
    fi
done
[ "$rulefail" -eq 0 ] && verdict PASS "R3 CRLF copies give the same map/--callers/--impact as LF on both sides, crlf-for the same outside its fold CR bytes/bytes= and est_tokens=, and crlf-expand agrees with tree-expand modulo CR bytes and reason=/est_tokens="

if [ "$fail" -ne 0 ]; then
    echo "SOME CHECKS FAILED"; exit 1
fi
echo "ALL PASS"
