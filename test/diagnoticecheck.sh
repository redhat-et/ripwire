#!/usr/bin/env bash
# diagnoticecheck.sh — every Diagnostics notice (src/infra/diagnostics.cpp) leaves the process in ONE write, with
# exactly the bytes it always had, so a concurrent writer can never tear it across lines.
#
# WHY THIS GATE EXISTS. kotlincheck §12 "hostile nesting" went red on CI eight times (three on main) with "yet the
# Kotlin refusal raised no DISCLOSE". The alert was on stderr every time, whole, just not on one line.
# ConsoleLog::handleDegraded built its notice from nine `std::cerr <<` insertions; with stdio sync on, each
# insertion is its own fwrite on an unbuffered stderr, so its own write(2). §12's fixture refuses two files at
# once, the second parse worker's one-write refusal line landed between two of those insertions, and the notice
# was split across lines. Measured locally at f8e6087c: 18 gate failures in 5,700 runs of the arm, and the notice
# torn in 32-73% of runs depending on load (the gate's single-line grep only sees a tear at one of the eight
# boundaries, which is why the rate it caught was so much lower). A probe that formatted the notice first and
# wrote it once: 0 failures and 0 tears in 3,800 runs, 2,300 of them paired against the old code under one load.
# The assert, panic and thread-violation reporters had the same many-insertion shape.
#
# ARMS
#   (S)  STATIC. Every `ConsoleLog::handle*` definition in diagnostics.cpp — the population is derived from the
#        file, and must include the four known reporters — calls the notice writer `writeNotice` exactly once and
#        makes no stream call of its own; `writeNotice` is defined once and makes exactly one stream call.
#        Comments and string literals are blanked before counting, so prose cannot satisfy or break the arm.
#   (S') CONTROL for (S), per CONTRIBUTING §2: the REAL file is mutated twice (the writer's stream call
#        duplicated; a stream call injected into handleDegraded), each mutation is asserted to have taken, and
#        the identical extraction must see both.
#   (W)  WRITES, dynamic and timing-free. test/diagnotice_harness.cpp runs each reporter in a forked child whose
#        fd 2 is an AF_UNIX SOCK_DGRAM socket: a datagram socket keeps write boundaries, so the parent counts the
#        write(2) calls a notice took. Every case must be writes=1, byte-exact against text the harness spells
#        out independently, and end the way the reporter must (degraded returns, assert and thread-violation
#        trap, panic aborts). Ten cases: the seven text branches, including the empty and null Notes rows, plus
#        three `2>&1` ORDERING cases (degraded, assert, panic) where stdout holds unflushed text when the reporter
#        runs. std::cerr is tied to std::cout, so the old reporters flushed stdout first; that text must still
#        arrive first, whole, as the first of exactly two writes, or a trap or an abort would lose it.
#   (W') CONTROL for (W): the harness rebuilt against (S')'s duplicated-writer mutation must see writes=2.
#   (L)  LONG. A notice past the writer's fixed buffer still arrives as one line and stays valid UTF-8 (the cut
#        backs off a multi-byte sequence). Its marker "kept K of N bytes" must be honest — K the length of the
#        text in front of it, N the full notice — and those K bytes must be the notice's own first K.
#   (T)  STRESS, end to end. fd 2 is a regular file; 4 threads raise 3,000 notices each while 2 threads write one
#        line per stdio call and 2 more one line per raw write(2). Every line of the file must be a whole notice
#        or a whole competitor line, and every count must be exact.
#   (A)  ALLOC. A reporter may run under memory exhaustion, so it must not allocate. Measured with the house
#        instrument, src/alloccount.cpp, as a delta between two otherwise identical runs: 110 extra reporter
#        calls (55 over-long) must leave the allocation count and bytes unchanged. The baseline must count at
#        least one allocation, or the instrument is not live. What it counts is global operator new ONLY; a
#        malloc inside the C library is invisible to it (by reading, neither glibc nor the BSD libc allocates on
#        an fputs to an unbuffered stderr). The harness's own output in this mode must cost the same in both
#        runs: an emitTo report line one byte past libstdc++'s 15-byte small-string buffer made this arm red on
#        every g++ leg of #245's first CI run, and libc++'s 22-byte buffer hid it on macOS.
#   (A') CONTROL for (A): the real file with the writer's rw::emitRaw rerouted through rw::emitTo (a std::string
#        per notice) must show a larger count on the same measurement.
#   (Z)  SANITIZED. (W), (L) and (T) again with the harness and diagnostics.cpp under ASan+UBSan. A toolchain
#        that cannot build it prints SKIP with the reason, never a WARN a runner would count as a pass.
#
# The header line names the harness compiler and the emit.h arm it compiled (rw::kEmitterName): the gate builds with
# $CXX, not with the leg's product compiler, and the arm decides what the harness's own output allocates.
#
# RED, MEASURED against the multi-insertion reporters (f8e6087c's diagnostics.cpp, AppleClang 21): (S) red on all
# four reporters; (W) red on all seven cases — writes=9 for the degraded notice and 15 to 21 for the banners — while
# every exact= stayed 1, which is also the byte-identity evidence for the rewrite (the same seven cases, reassembled
# from both builds, are byte-identical); (L) red, no marker; (T) red in 200 of 200 standalone harness runs, and
# 2,201 and 11,417 torn lines in two runs of this gate. (A) is green on the old reporters as well: it guards the
# rewrite's no-allocation property and does not detect the tear, which is why (A') exists. 27 FAIL, 2 PASS in all.
#
# Binds no ripwire binary: its subject is the reporters' source and a harness built from it.
# Usage:  bash test/diagnoticecheck.sh            CXX=clang++ bash test/diagnoticecheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
CXX="${CXX:-c++}"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

. "$ROOT/scripts/cxxstd.sh"
CXXSTD="$( ripwire_cxx_std_flag "$CXX" )"
DIAG="$ROOT/src/infra/diagnostics.cpp"
HARNESS="$ROOT/test/diagnotice_harness.cpp"
. "$ROOT/scripts/gatebound.sh"
WORK="$( mktemp -d )"; trap 'gate_bounded_reap; rm -rf "$WORK"' EXIT; gate_bounded_arm

echo "diagnoticecheck: CXX=$CXX"

if ! command -v python3 >/dev/null 2>&1; then
    no "python3 is required by arm (S)"
    echo "diagnoticecheck: FAIL"
    exit "$fail"
fi

# ── (S) + (S') static: one writer, one stream call, one writer call per reporter ────────────────────────────────
python3 - "$DIAG" "$WORK" > "$WORK/static.tsv" 2> "$WORK/static.err" <<'PY'
import re, sys
diagPath, work = sys.argv[1], sys.argv[2]
WRITER = "writeNotice"
STREAM = re.compile( r"\bstd::(?:cerr|cout|clog)\b|<<"
                     r"|\b(?:std::)?(?:fputs|fwrite|fprintf|printf|puts|fputc|putc|putchar|vfprintf|dprintf|vdprintf)\s*\("
                     r"|\b(?:rw::)?emit(?:To|Raw)\s*\(|\bstd::print(?:ln)?\s*\("
                     r"|(?<![\w.>])(?:::)?(?:write|send)\s*\(" )
CALL = re.compile( r"\b" + WRITER + r"\s*\(" )

def blank( src ):
    """Comments and string/char literals become spaces (newlines kept), so only code is counted."""
    out, i, n = [], 0, len( src )
    while i < n:
        if src.startswith( "//", i ):
            j = src.find( "\n", i );  j = n if j < 0 else j
            out.append( " " * ( j - i ) );  i = j
        elif src.startswith( "/*", i ):
            j = src.find( "*/", i + 2 );  j = n if j < 0 else j + 2
            out.append( re.sub( r"[^\n]", " ", src[ i:j ] ) );  i = j
        elif src[ i ] in "\"'":
            q, j = src[ i ], i + 1
            while j < n and src[ j ] != q:
                j += 2 if src[ j ] == "\\" else 1
            j = min( j + 1, n )
            out.append( q + re.sub( r"[^\n]", " ", src[ i + 1 : j - 1 ] ) + q );  i = j
        else:
            out.append( src[ i ] );  i += 1
    return "".join( out )

def matching( code, openAt, openCh, closeCh ):
    depth = 0
    for k in range( openAt, len( code ) ):
        if code[ k ] == openCh:
            depth += 1
        elif code[ k ] == closeCh:
            depth -= 1
            if depth == 0:
                return k
    return -1

def definitions( code, nameRegex ):
    """(name, bodyStart, bodyEnd) for every DEFINITION: a name( … ) whose parameter list is followed by a body."""
    found = []
    for m in re.finditer( nameRegex, code ):
        close = matching( code, m.end() - 1, "(", ")" )
        if close < 0:
            continue
        rest = re.match( r"[\s\w:]*", code[ close + 1 : ] )
        after = close + 1 + rest.end()
        if after < len( code ) and code[ after ] == "{":
            end = matching( code, after, "{", "}" )
            if end > 0:
                found.append( ( m.group( 1 ), after, end ) )
    return found

def measure( src ):
    code = blank( src )
    reporters = [ ( name, len( CALL.findall( code[ a:b ] ) ), len( STREAM.findall( code[ a:b ] ) ) )
                  for name, a, b in definitions( code, r"\bConsoleLog::(handle\w+)\s*\(" ) ]
    writers = [ ( name, len( STREAM.findall( code[ a:b ] ) ), a, b ) for name, a, b in definitions( code, r"\b(" + WRITER + r")\s*\(" ) ]
    return code, reporters, writers

src = open( diagPath, encoding = "utf-8" ).read()
code, reporters, writers = measure( src )
for name, calls, streams in reporters:
    print( "reporter\t%s\t%d\t%d" % ( name, calls, streams ) )
print( "writer\t%s\t%d\t%d" % ( WRITER, writers[ 0 ][ 1 ] if len( writers ) == 1 else -1, len( writers ) ) )

# (S') mutation 1: duplicate the LINE holding the writer's stream call.
tookDup, dupStreams = 0, -1
if len( writers ) == 1:
    _n, _s, a, b = writers[ 0 ]
    m = STREAM.search( code, a, b )
    if m:
        lineStart = src.rfind( "\n", 0, m.start() ) + 1
        lineEnd = src.find( "\n", m.start() ) + 1
        mutated = src[ :lineEnd ] + src[ lineStart:lineEnd ] + src[ lineEnd: ]
        if mutated != src:
            tookDup = 1
            open( work + "/diagnostics_mutwriter.cpp", "w", encoding = "utf-8" ).write( mutated )
            _c, _r, w2 = measure( mutated )
            dupStreams = w2[ 0 ][ 1 ] if len( w2 ) == 1 else -1
print( "control\twriter-dup\t%d\t%d" % ( tookDup, dupStreams ) )

# (A') mutation: the writer's one stream call rerouted through rw::emitTo, which formats into a std::string first.
# Not a (S) control: it is written for arm (A), which must see the allocation this rerouting adds.
tookAlloc = 0
if len( writers ) == 1:
    _n, _s, a, b = writers[ 0 ]
    m = re.compile( r"\brw::emitRaw\(\s*stderr\s*,\s*(\w+)\s*\)" ).search( src, a, b )
    if m:
        mutated = src[ :m.start() ] + "rw::emitTo( stderr, \"{}\", rw::cstr( %s ) )" % m.group( 1 ) + src[ m.end(): ]
        if mutated != src:
            tookAlloc = 1
            open( work + "/diagnostics_mutalloc.cpp", "w", encoding = "utf-8" ).write( mutated )
print( "control\twriter-alloc\t%d\t0" % tookAlloc )

# (S') mutation 2: inject a stream call as the first statement of handleDegraded's body.
tookInject, injectStreams = 0, -1
for name, a, b in definitions( code, r"\bConsoleLog::(handle\w+)\s*\(" ):
    if name == "handleDegraded":
        mutated = src[ : a + 1 ] + "\n    rw::emitRaw( stderr, \"\" );" + src[ a + 1 : ]
        if mutated != src:
            tookInject = 1
            _c, r2, _w = measure( mutated )
            injectStreams = next( ( s for n, _k, s in r2 if n == "handleDegraded" ), -1 )
print( "control\treporter-inject\t%d\t%d" % ( tookInject, injectStreams ) )
PY
STATIC_RC=$?
if [ "$STATIC_RC" -ne 0 ]; then
    no "(S) the static extraction did not run (rc=$STATIC_RC)"; sed 's/^/    /' "$WORK/static.err" | head -10
else
    seenReporters=" "
    allocControlTook=0
    while IFS=$'\t' read -r kind name a b <&3; do
        case "$kind" in
            reporter)
                seenReporters="$seenReporters$name "
                if [ "$a" = 1 ] && [ "$b" = 0 ]; then
                    ok "(S) $name calls writeNotice once and makes no stream call of its own"
                else
                    no "(S) $name: $a writeNotice call(s) and $b direct stream call(s) — a notice built from several writes can be torn by any concurrent writer"
                fi ;;
            writer)
                if [ "$b" = 1 ] && [ "$a" = 1 ]; then
                    ok "(S) $name is defined once and makes exactly one stream call"
                else
                    no "(S) $name: $b definition(s), $a stream call(s) in it (want 1 and 1)"
                fi ;;
            control)
                if [ "$name" = writer-alloc ]; then
                    allocControlTook="$a"
                elif [ "$name" = writer-dup ]; then
                    if [ "$a" = 1 ] && [ "$b" = 2 ]; then
                        ok "(S') control: the real file with writeNotice's stream call duplicated reads as 2 stream calls — (S) can go red"
                    else
                        no "(S') control: duplicating writeNotice's stream call took=$a and read $b stream calls (want took=1, 2)"
                    fi
                else
                    if [ "$a" = 1 ] && [ "$b" = 1 ]; then
                        ok "(S') control: a stream call injected into handleDegraded is seen — (S) can go red on a reporter"
                    else
                        no "(S') control: injecting a stream call into handleDegraded took=$a and read $b (want took=1, 1)"
                    fi
                fi ;;
        esac
    done 3< "$WORK/static.tsv"
    for want in handleAssert handlePanic handleThreadViolation handleDegraded; do
        case "$seenReporters" in
            *" $want "*) ;;
            *) no "(S) presence: no definition of ConsoleLog::$want was found — the arm above measured the wrong population" ;;
        esac
    done
fi

# ── building the harness ─────────────────────────────────────────────────────────────────────────────────────────
# -I src for the harness's `infra/` spelling (infraportcheck D); -I src/infra because a MUTATED copy of diagnostics.cpp
# lives in $WORK, away from the siblings its bare `#include "Diagnostics.h"` finds beside the real file.
build_harness()   # $1 = output, $2 = diagnostics.cpp to link, $3 = compile log, rest = extra flags
{
    local out="$1" diag="$2" log="$3"; shift 3
    "$CXX" "$CXXSTD" "$@" -g -Wall -Wextra -pthread -I"$ROOT/src" -I"$ROOT/src/infra" "$HARNESS" "$diag" -o "$out" 2> "$log"
}

check_writes()   # $1 = label, $2 = rows file
{
    local label="$1" rows="$2" spec name rest want writes line
    # name:ending:writes. An ordering case is TWO writes: stdout's buffered text, then the whole notice.
    for spec in degraded:return:1 assert:trap:1 assert-nonotes:trap:1 assert-nullnotes:trap:1 panic:abort:1 thread:trap:1 \
                thread-nonotes:trap:1 stdout-degraded:return:2 stdout-assert:trap:2 stdout-panic:abort:2; do
        name="${spec%%:*}"; rest="${spec#*:}"; want="${rest%%:*}"; writes="${rest#*:}"
        line="$( grep -E "^case $name " "$rows" )"
        if [ -z "$line" ]; then
            no "$label $name: the harness printed no row — nothing was measured"
        elif [[ "$line" == *" writes=$writes "* && "$line" == *" exact=1 "* && "$line" == *" ended=$want" ]]; then
            if [ "$writes" = 1 ]; then
                ok "$label $name: one write, byte-exact, ended=$want"
            else
                ok "$label $name: buffered stdout first, then the notice in one write — byte-exact under 2>&1, ended=$want"
            fi
        else
            no "$label $name: $line (want writes=$writes exact=1 ended=$want)"
            grep -A2 -E "^case $name " "$rows" | grep -E '^  (got|want):' | sed 's/^/  /'
        fi
    done
}

check_long()   # $1 = label, $2 = rows file
{
    local line
    line="$( grep -E '^case degraded-long ' "$2" )"
    if [ -z "$line" ]; then
        no "$1 degraded-long: the harness printed no row — nothing was measured"
    elif [[ "$line" == *" lines=1 "* && "$line" == *" marker=1 "* && "$line" == *" utf8=1 "* && "$line" == *" prefix=1 "* && "$line" == *" ended=return" ]]; then
        ok "$1 an over-long notice is one line, valid UTF-8, its own first K bytes and an honest 'kept K of N bytes' marker ($line)"
    else
        no "$1 over-long notice: $line (want lines=1 marker=1 utf8=1 prefix=1 ended=return)"
        grep -A2 -E '^case degraded-long ' "$2" | grep -E '^  (tail|want)' | sed 's/^/  /'
    fi
}

check_stress()   # $1 = label, $2 = rows file
{
    local line n
    line="$( grep -E '^stress ' "$2" )"
    if [ -z "$line" ]; then
        no "$1 stress: the harness printed no row — nothing was measured"; return
    fi
    n="$( printf '%s\n' "$line" | sed -nE 's#^stress notices=([0-9]+)/([0-9]+) stdio=([0-9]+)/([0-9]+) raw=([0-9]+)/([0-9]+) torn=([0-9]+)$#\1 \2 \3 \4 \5 \6 \7#p' )"
    set -- "$1" $n
    if [ "$#" -ne 8 ]; then
        no "$1 stress: unparseable row: $line"
    elif [ "$3" -gt 0 ] && [ "$2" = "$3" ] && [ "$4" = "$5" ] && [ "$6" = "$7" ] && [ "$8" = 0 ]; then
        ok "$1 stress: $2 notices raced $4 stdio lines and $6 raw write(2) lines; every line whole, torn=0"
    else
        no "$1 stress: $line — a notice was split by a concurrent writer"
        grep -E '^  torn:' "$WORK/stress_rows_last" 2>/dev/null | head -3 | sed 's/^/  /'
    fi
}

H="$WORK/diagnotice"
if ! build_harness "$H" "$DIAG" "$WORK/cc.log" -O2; then
    no "the harness failed to compile against src/infra/diagnostics.cpp"; sed 's/^/    /' "$WORK/cc.log" | head -30
else
    ok "harness compiled against src/infra/diagnostics.cpp"
    gate_bounded 120 "$H" info > "$WORK/info.txt" 2>&1   # not inside $( ): a stop must reach the gate's own wait, not a substitution's
    echo "diagnoticecheck: harness CXX=$CXX ($( "$CXX" --version 2>/dev/null | head -1 )) $( cat "$WORK/info.txt" )"

    # ── (W) one write per notice, byte-exact ──
    mkdir -p "$WORK/dump"
    gate_bounded 120 "$H" writes "$WORK/dump" > "$WORK/writes.txt"; rc=$?
    if [ "$rc" -ne 0 ]; then
        no "(W) the harness could not set up the measurement (rc=$rc)"; sed 's/^/    /' "$WORK/writes.txt" | head -10
    fi
    check_writes "(W)" "$WORK/writes.txt"

    # ── (L) the over-long notice ──
    check_long "(L)" "$WORK/writes.txt"

    # ── (W') the capture can see a second write ──
    if [ -s "$WORK/diagnostics_mutwriter.cpp" ] && build_harness "$WORK/mut" "$WORK/diagnostics_mutwriter.cpp" "$WORK/ccmut.log" -O2; then
        gate_bounded 120 "$WORK/mut" writes > "$WORK/mutwrites.txt"
        mutLine="$( grep -E '^case degraded ' "$WORK/mutwrites.txt" )"
        if [[ "$mutLine" == *" writes=2 "* ]]; then
            ok "(W') control: the harness built against the duplicated-writer mutation reads writes=2 — (W) can go red"
        else
            no "(W') control: the duplicated-writer mutation read '$mutLine' (want writes=2) — (W) cannot see a second write"
        fi
    else
        no "(W') control: no duplicated-writer mutation to build (see (S')), or it failed to compile"; sed 's/^/    /' "$WORK/ccmut.log" 2>/dev/null | head -10
    fi

    # ── (T) stress ──
    gate_bounded 120 "$H" stress "$WORK/stress.err" 4 2 3000 > "$WORK/stress.txt"; rc=$?
    cp "$WORK/stress.txt" "$WORK/stress_rows_last"
    if [ "$rc" -ne 0 ]; then
        no "(T) the harness could not set up the stress run (rc=$rc)"
    fi
    check_stress "(T)" "$WORK/stress.txt"

    # ── (A) no allocation, measured by the house instrument ──
    # src/alloccount.cpp replaces global operator new/delete and reports the process's allocations at exit. Its own
    # rule is that only a DELTA between otherwise identical runs is attributable, so the harness runs twice: one
    # warm-up pair of notices only, then the same plus 110 more (55 of them over-long). The counts must be equal.
    A="$WORK/diagnotice_alloc"
    if ! build_harness "$A" "$DIAG" "$WORK/cca.log" -O2 "$ROOT/src/alloccount.cpp"; then
        no "(A) the harness failed to compile with src/alloccount.cpp"; sed 's/^/    /' "$WORK/cca.log" | head -10
    else
        gate_bounded 120 "$A" alloc 0 > "$WORK/alloc0.out" 2> "$WORK/alloc0.err"; rc0=$?
        gate_bounded 120 "$A" alloc 55 > "$WORK/alloc55.out" 2> "$WORK/alloc55.err"; rc55=$?
        base="$( sed -nE 's/^ALLOC_REPORT allocs=([0-9]+) bytes=([0-9]+) .*/\1 \2/p' "$WORK/alloc0.err" )"
        measured="$( sed -nE 's/^ALLOC_REPORT allocs=([0-9]+) bytes=([0-9]+) .*/\1 \2/p' "$WORK/alloc55.err" )"
        if [ "$rc0" -ne 0 ] || [ "$rc55" -ne 0 ] || [ -z "$base" ] || [ -z "$measured" ] || ! grep -qx 'alloc calls=110' "$WORK/alloc55.out"; then
            no "(A) the allocation measurement did not run (rc=$rc0/$rc55, reports '$base' / '$measured') — nothing was measured"
        elif [ "${base%% *}" -lt 1 ]; then
            no "(A) the baseline run counted 0 allocations — the instrument is not live, so an equal count proves nothing"
        elif [ "$base" = "$measured" ]; then
            ok "(A) 110 reporter calls (55 over-long) add no operator-new allocation: allocs/bytes '$base' with and without them (a libc malloc is not counted)"
        else
            no "(A) operator new is called: allocs/bytes '$base' without the reporter calls, '$measured' with 110 — a reporter can fail exactly when memory is gone"
        fi
    fi

    # ── (A') the delta can move: the same measurement over the writer rerouted through rw::emitTo ──
    if [ "${allocControlTook:-0}" != 1 ] || ! build_harness "$WORK/mutalloc" "$WORK/diagnostics_mutalloc.cpp" "$WORK/ccma.log" -O2 "$ROOT/src/alloccount.cpp"; then
        no "(A') control: no rw::emitRaw( stderr, … ) call in writeNotice to reroute, or the mutation failed to compile — (A) is unproven"
    else
        gate_bounded 120 "$WORK/mutalloc" alloc 0 > /dev/null 2> "$WORK/malloc0.err"
        gate_bounded 120 "$WORK/mutalloc" alloc 55 > /dev/null 2> "$WORK/malloc55.err"
        mBase="$( sed -nE 's/^ALLOC_REPORT allocs=([0-9]+) .*/\1/p' "$WORK/malloc0.err" )"
        mMeasured="$( sed -nE 's/^ALLOC_REPORT allocs=([0-9]+) .*/\1/p' "$WORK/malloc55.err" )"
        if [ -n "$mBase" ] && [ -n "$mMeasured" ] && [ "$mMeasured" -gt "$mBase" ]; then
            ok "(A') control: the writer rerouted through rw::emitTo allocates on the same measurement (allocs $mBase -> $mMeasured) — (A) can go red"
        else
            no "(A') control: the rw::emitTo mutation read allocs '$mBase' -> '$mMeasured' (want an increase) — (A) cannot see an allocation"
        fi
    fi
fi

# ── (Z) the same harness under the G1 sanitizer stack ───────────────────────────────────────────────────────────
Z="$WORK/diagnotice_asan"
z_ready()   # builds the sanitized harness and proves it STARTS; prints the SKIP reason and fails when it cannot
{
    if ! build_harness "$Z" "$DIAG" "$WORK/ccz.log" -O1 -fsanitize=address,undefined -fno-sanitize-recover=all; then
        echo "  SKIP  (Z) the ASan+UBSan harness does not build with $CXX here, so the sanitized arm proved nothing; first compiler line:"
        sed 's/^/    /' "$WORK/ccz.log" | head -5
        return 1
    fi
    # Built, but will it start? On some macOS hosts an ASan binary hangs in the runtime's own init, before main()
    # (scripts/gatebound.sh). That is a host that cannot run this arm, so it SKIPs like a host that cannot link it.
    if ! ASAN_OPTIONS=detect_leaks=0 gate_bounded 30 "$Z" info >/dev/null 2>&1; then
        echo "  SKIP  (Z) the ASan+UBSan harness built but does not start within 30 s on this host (hung or failed in the sanitizer runtime before main), so the sanitized arm proved nothing"
        return 1
    fi
    return 0
}
if z_ready; then
    gate_bounded 120 "$Z" writes > "$WORK/zwrites.txt" 2> "$WORK/zwrites.err"; rc=$?
    if [ "$rc" -ne 0 ]; then
        no "(Z) sanitized writes run exited $rc"; sed 's/^/    /' "$WORK/zwrites.err" | head -10
    fi
    check_writes "(Z)" "$WORK/zwrites.txt"
    check_long "(Z)" "$WORK/zwrites.txt"
    gate_bounded 120 "$Z" stress "$WORK/zstress.err" 4 2 1000 > "$WORK/zstress.txt"; rc=$?
    cp "$WORK/zstress.txt" "$WORK/stress_rows_last"
    if [ "$rc" -ne 0 ]; then
        no "(Z) sanitized stress run exited $rc"
    fi
    check_stress "(Z)" "$WORK/zstress.txt"
fi

if [ "$fail" -eq 0 ]; then
    echo "diagnoticecheck: ALL PASS"
else
    echo "diagnoticecheck: FAIL"
fi
exit "$fail"
