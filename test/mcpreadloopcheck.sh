#!/usr/bin/env bash
# mcpreadloopcheck.sh — the R4 gate: the stdin READ LOOP itself, not the verbs it feeds.
#
# WHAT WENT WRONG (the red this gate is the green side of). Every stdin-consuming surface read its
# lines with `std::getline( std::cin, line )`. libc++'s getline refills through a one-character
# fallback (`istream:1283`, `_CharT __1buf = __next;`) whenever the streambuf exposes NO get area —
# which is exactly std::cin's stdio-synced case, where `gptr() == egptr()` on every read. That
# assignment narrows int_type(int) → char, so ANY 0x80..0xFF input byte trips `-fsanitize=integer`
# (implicit-integer-sign-change) and, under `-fno-sanitize-recover=all`, ABORTS the process. Pre-fix,
# an --mcp request containing "café" answered `initialize` and then died with exit 134, so the entire
# MCP surface was sanitizer-DARK for non-ASCII input: no gate could observe behaviour past that byte.
# Fix (R4): src/stdinline.h's readByteSafeLine, swapped in at all three std::cin sites — src/mcp.h
# (runMcp's loop), src/main.cpp readTraceText (--from-trace=-), src/main.cpp --batch=-.
#
# WHY THE GATE LOOKS LIKE THIS. The bug lived BELOW the JSON layer, so every arm here is about bytes
# and framing, and every arm runs against a LIVE server (spawn --mcp, pipe frames) — the shape that
# was dark. The `batch` verb and the two `-`-from-stdin CLI verbs get their own arms because they are
# the same clone seam (all three reproduced the abort independently).
#
# ARMS
#   (a) non-ASCII UTF-8 inside a VALID request — 2/3/4-byte sequences, live + batch + both CLI
#       siblings: answered, survived, no sanitizer diagnostic on stderr
#   (b) CRLF-terminated frames — stdout byte-identical to the LF run (getline left the '\r' in the
#       string and so must readByteSafeLine; a stripped '\r' would be a silent behaviour change)
#   (c) EOF mid-UTF-8-sequence (truncated multi-byte, NO trailing newline) — the unterminated tail is
#       delivered exactly once, no abort, no hang, exit 0
#   (d) a 64 KB single-line request, and a 1.5 MB one — read as ONE line and processed intact (the
#       load-bearing `id` sits at the END of the line, so a split or a truncation cannot pass)
#   (e) torn frames — a request arriving in pieces with no newline until later yields NOTHING until
#       the newline lands, then EXACTLY one response
#   (f) empty / whitespace-only lines — skipped, exactly as before
#   (g) the 61-frame HOSTILE SWEEP, now a repeatable arm: >=61 adversarial frames (malformed JSON,
#       huge/absent/wrong-typed ids, 2/3/4-byte UTF-8, lone continuation + overlong + truncated
#       sequences, raw control bytes and NUL, null-ish content, oversized args, duplicate keys, CRLF,
#       deep nesting) streamed into ONE server session, which must survive them all and then answer a
#       normal trailing request. The corpus is generated IN this file and is fully deterministic — no
#       clock, no random seed, no network.
#
# Usage:
#   test/mcpreadloopcheck.sh                                 # uses build/ctxpack
#   test/mcpreadloopcheck.sh asan/ctxpack                    # positional binary  (the arm that matters)
#   CTXPACK_BIN=asan/ctxpack test/mcpreadloopcheck.sh         # env binary
#   CTXPACK_BIN_ALT=asan/ctxpack test/mcpreadloopcheck.sh     # + plain-vs-alt byte-identity arm
#
# For asan runs, export LSAN_OPTIONS=suppressions=lsan_suppressions.txt as usual.
# Exits non-zero on any failure. Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${CTXPACK_BIN:-$ROOT/build/ctxpack}}"       # BOTH seams — positional and env
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
ALT="${CTXPACK_BIN_ALT:-}"
[ -n "$ALT" ] && [ "${ALT#/}" = "$ALT" ] && ALT="$ROOT/$ALT"
FIX="$ROOT/test/fixture"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ctxpack binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for the byte-level driver"; exit 2; }

echo "mcpreadloopcheck: BIN=$BIN  FIX=$FIX${ALT:+  ALT=$ALT}"

# ── the byte-level driver ────────────────────────────────────────────────────────────────────────────
# Bash cannot hold a NUL byte in a variable and cannot do a timed partial write, so the raw-byte work
# lives in ONE python helper. It never inspects semantics — it moves bytes and reports survival.
cat >"$TMP/drive.py" <<'PYDRIVE'
import json, os, subprocess, sys, time

SANITIZER_MARKS = ( "runtime error:", "UndefinedBehaviorSanitizer", "AddressSanitizer",
                    "LeakSanitizer", "SUMMARY:" )

def feed( binPath, args, stdinBytes, outPath, errPath, timeoutSec = 300 ):
    """write stdinBytes, close stdin, wait. Returns (exitCode, sanitizerHit, timedOut)."""
    with open( outPath, "wb" ) as fo, open( errPath, "wb" ) as fe:
        p = subprocess.Popen( [ binPath ] + args, stdin = subprocess.PIPE, stdout = fo, stderr = fe )
        try:
            p.communicate( input = stdinBytes, timeout = timeoutSec )
        except subprocess.TimeoutExpired:
            p.kill(); p.wait()
            return ( None, False, True )
    err = open( errPath, "rb" ).read().decode( "utf-8", "replace" )
    return ( p.returncode, any( m in err for m in SANITIZER_MARKS ), False )

def torn( binPath, root, outPath, errPath ):
    """(e): send a request in pieces with the newline held back. Reports what arrived when."""
    import selectors
    head = ( '{"jsonrpc":"2.0","id":1,"method":"initialize"}\n' ).encode()
    piece1 = ( '{"method":"tools/call","params":{"name":"grep","arguments":'
               '{"path":"' + root + '","pattern":"perimeter"' ).encode()
    piece2 = ( '}},"jsonrpc":"2.0","id":' ).encode()
    piece3 = ( '777}\n' ).encode()

    with open( errPath, "wb" ) as fe:
        p = subprocess.Popen( [ binPath, "--mcp" ], stdin = subprocess.PIPE,
                              stdout = subprocess.PIPE, stderr = fe )
        sel = selectors.DefaultSelector(); sel.register( p.stdout, selectors.EVENT_READ )
        got = b""

        def drain( budgetSec, wantLines = None ):
            """collect stdout for up to budgetSec. Returns EARLY once wantLines complete lines have
            arrived — the 'expect output' calls must not burn their whole ceiling, or this arm alone
            would dominate the gate's runtime; wantLines=None is the 'expect NOTHING' case, which
            deliberately waits out its (short) budget."""
            nonlocal got
            deadline = time.monotonic() + budgetSec
            while time.monotonic() < deadline:
                if wantLines is not None and got.count( b"\n" ) >= wantLines: return
                for _ in sel.select( timeout = min( 0.1, max( 0.0, deadline - time.monotonic() ) ) ):
                    chunk = os.read( p.stdout.fileno(), 65536 )
                    if not chunk: return
                    got += chunk

        p.stdin.write( head ); p.stdin.flush(); drain( 120.0, 1 )   # initialize answers -> 1 line
        linesAfterInit = got.count( b"\n" )
        for piece in ( piece1, piece2 ):
            p.stdin.write( piece ); p.stdin.flush(); drain( 1.5 )   # expect NOTHING: wait it out
        linesWhileTorn = got.count( b"\n" )                         # must still be linesAfterInit
        p.stdin.write( piece3 ); p.stdin.flush(); drain( 120.0, linesAfterInit + 1 )
        linesAfterNewline = got.count( b"\n" )
        p.stdin.close()
        rest = p.stdout.read(); got += rest
        code = p.wait()
    open( outPath, "wb" ).write( got )
    err = open( errPath, "rb" ).read().decode( "utf-8", "replace" )
    return ( code, any( m in err for m in SANITIZER_MARKS ),
             linesAfterInit, linesWhileTorn, linesAfterNewline )

# ── the deterministic hostile corpus (arm g) ─────────────────────────────────────────────────────────
def hostileCorpus( root ):
    """>=61 adversarial frames. Deterministic: no clock, no random, no network."""
    frames = []
    def add( raw ):
        frames.append( raw if isinstance( raw, bytes ) else raw.encode() )

    # 1. malformed JSON (9)
    for bad in ( "not-json", "{", "}", '{"jsonrpc":', "[]", "null", '"a string"',
                 '{"jsonrpc":"2.0",}', "{'jsonrpc':'2.0','id':1}" ):
        add( bad )

    # 2. hostile ids (7)
    add( '{"jsonrpc":"2.0","id":' + "9" * 400 + ',"method":"initialize"}' )
    add( '{"jsonrpc":"2.0","method":"initialize"}' )                       # absent id (a notification)
    add( '{"jsonrpc":"2.0","id":"a-string-id","method":"initialize"}' )
    add( '{"jsonrpc":"2.0","id":null,"method":"initialize"}' )
    add( '{"jsonrpc":"2.0","id":{"nested":1},"method":"initialize"}' )
    add( '{"jsonrpc":"2.0","id":[1,2,3],"method":"initialize"}' )
    add( '{"jsonrpc":"2.0","id":-0.0000001,"method":"initialize"}' )

    # 3. non-ASCII and malformed UTF-8 (12) — the class that used to abort the process
    pat = lambda p: ( '{"jsonrpc":"2.0","id":31,"method":"tools/call","params":{"name":"grep",'
                      '"arguments":{"path":"' + root + '","pattern":"' ).encode() + p + b'"}}}'
    add( pat( "é".encode() ) )                       # 2-byte
    add( pat( "€".encode() ) )                       # 3-byte
    add( pat( "𝄞".encode() ) )                       # 4-byte (astral)
    add( pat( "日本語テキスト".encode() ) )
    add( pat( b"\x80" ) )                            # lone continuation byte
    add( pat( b"\xbf\xbf\xbf" ) )                    # continuation run
    add( pat( b"\xc3" ) )                            # truncated 2-byte lead
    add( pat( b"\xe2\x82" ) )                        # truncated 3-byte
    add( pat( b"\xf0\x9d\x84" ) )                    # truncated 4-byte
    add( pat( b"\xc0\xaf" ) )                        # overlong '/'
    add( pat( b"\xff\xfe" ) )                        # never-valid UTF-8 bytes
    add( pat( "﻿".encode() + b"mid" ) )         # BOM mid-string

    # 4. null-ish / wrong-typed content (7)
    add( '{"jsonrpc":"2.0","id":41,"method":null}' )
    add( '{"jsonrpc":"2.0","id":42,"method":""}' )
    add( '{"jsonrpc":"2.0","id":43,"method":"tools/call","params":null}' )
    add( '{"jsonrpc":"2.0","id":44,"method":"tools/call","params":{"name":"grep","arguments":null}}' )
    add( '{"jsonrpc":"2.0","id":45,"method":"tools/call","params":{"name":null,"arguments":{}}}' )
    add( '{"jsonrpc":"2.0","id":46,"method":"tools/call","params":{"name":"grep","arguments":{"path":null,"pattern":"x"}}}' )
    add( '{"jsonrpc":"2.0","id":47,"method":"tools/call","params":{"name":"grep","arguments":{"path":"' + root + '","pattern":null}}}' )

    # 5. oversized arguments (4)
    big = "A" * 200000
    add( '{"jsonrpc":"2.0","id":51,"method":"tools/call","params":{"name":"grep","arguments":{"path":"' + root + '","pattern":"' + big + '"}}}' )
    add( '{"jsonrpc":"2.0","id":52,"method":"tools/call","params":{"name":"grep","arguments":{"path":"' + root + '","' + big + '":1}}}' )
    add( '{"jsonrpc":"2.0","id":53,"method":"tools/call","params":{"name":"' + big + '","arguments":{}}}' )
    add( '{"jsonrpc":"2.0","id":54,"method":"' + big + '"}' )

    # 6. duplicate keys (4)
    add( '{"jsonrpc":"2.0","id":61,"id":62,"method":"initialize"}' )
    add( '{"jsonrpc":"2.0","id":63,"method":"initialize","method":"tools/list"}' )
    add( '{"jsonrpc":"2.0","id":64,"method":"tools/call","params":{"name":"grep","arguments":{"path":"' + root + '","pattern":"a"},"arguments":{"pattern":"b"}}}' )
    add( '{"jsonrpc":"2.0","jsonrpc":"1.0","id":65,"method":"initialize"}' )

    # 7. raw control bytes inside a frame, incl. an embedded NUL (5)
    add( b'{"jsonrpc":"2.0","id":71,"method":"tools/call","params":{"name":"grep","arguments":{"path":"' + root.encode() + b'","pattern":"a\tb"}}}' )
    add( b'{"jsonrpc":"2.0","id":72,"method":"tools/call","params":{"name":"grep","arguments":{"path":"' + root.encode() + b'","pattern":"a\x01b"}}}' )
    add( b'{"jsonrpc":"2.0","id":73,"method":"tools/call","params":{"name":"grep","arguments":{"path":"' + root.encode() + b'","pattern":"a\x7fb"}}}' )
    add( b'{"jsonrpc":"2.0","id":74,"method":"tools/call","params":{"name":"grep","arguments":{"path":"' + root.encode() + b'","pattern":"a\x00b"}}}' )
    add( b'\x00{"jsonrpc":"2.0","id":75,"method":"initialize"}' )

    # 8. deep nesting + structural abuse (4)
    add( '{"jsonrpc":"2.0","id":81,"method":"tools/call","params":{"name":"grep","arguments":' + '{"a":' * 200 + '1' + '}' * 200 + '}}' )
    add( '{"jsonrpc":"2.0","id":82,"method":"tools/call","params":' + '[' * 200 + ']' * 200 + '}' )
    add( '{"jsonrpc":"2.0","id":83,"method":"tools/call","params":{"name":"grep","arguments":{"path":"' + root + '","pattern":"\\\\u0000\\\\ud800"}}}' )
    add( '{"jsonrpc":"2.0","id":84,"method":"tools/call","params":{"name":"grep","arguments":{"path":"' + root + '","pattern":"' + '\\"' * 500 + '"}}}' )

    # 9. blank / whitespace-only frames, which must be skipped not answered (5)
    for blank in ( "", "   ", "\t", "\r", " \t\r " ):
        add( blank )

    # 10. a valid frame carrying CRLF line endings (4) — the '\r' rides INTO the JSON parser
    add( '{"jsonrpc":"2.0","id":101,"method":"initialize"}\r' )
    add( '{"jsonrpc":"2.0","id":102,"method":"tools/list"}\r' )
    add( '{"jsonrpc":"2.0","id":103,"method":"tools/call","params":{"name":"grep","arguments":{"path":"' + root + '","pattern":"perimeter"}}}\r' )
    add( '{"jsonrpc":"2.0","id":104,"method":"notifications/initialized"}\r' )
    return frames

# ── entry points ─────────────────────────────────────────────────────────────────────────────────────
mode = sys.argv[ 1 ]

if mode == "feed":                     # feed BIN OUT ERR IN [args...]
    binPath, outPath, errPath, inPath = sys.argv[ 2 : 6 ]
    code, san, timedOut = feed( binPath, sys.argv[ 6 : ], open( inPath, "rb" ).read(), outPath, errPath )
    print( "exit=%s sanitizer=%d timeout=%d" % ( "KILLED" if code is None else code, san, timedOut ) )

elif mode == "torn":                   # torn BIN ROOT OUT ERR
    code, san, a, b, c = torn( sys.argv[ 2 ], sys.argv[ 3 ], sys.argv[ 4 ], sys.argv[ 5 ] )
    print( "exit=%s sanitizer=%d afterInit=%d whileTorn=%d afterNewline=%d" % ( code, san, a, b, c ) )

elif mode == "mkframes":               # mkframes OUT ROOT eol frame...   (eol: lf|crlf)
    outPath, root, eol = sys.argv[ 2 : 5 ]
    sep = b"\r\n" if eol == "crlf" else b"\n"
    with open( outPath, "wb" ) as f:
        for frame in sys.argv[ 5 : ]:
            f.write( frame.replace( "@ROOT@", root ).encode() + sep )

elif mode == "mkhostile":              # mkhostile OUT ROOT  -> writes the corpus + a trailing probe
    outPath, root = sys.argv[ 2 : 4 ]
    frames = hostileCorpus( root )
    with open( outPath, "wb" ) as f:
        f.write( b'{"jsonrpc":"2.0","id":1,"method":"initialize"}\n' )
        for frame in frames:
            f.write( frame + b"\n" )
        f.write( b'{"jsonrpc":"2.0","id":999999,"method":"tools/list"}\n' )
    print( len( frames ) )

elif mode == "mkbigline":              # mkbigline OUT ROOT BYTES ID — the load-bearing id goes LAST
    outPath, root, nBytes, wantId = sys.argv[ 2 ], sys.argv[ 3 ], int( sys.argv[ 4 ] ), sys.argv[ 5 ]
    pad = "x" * nBytes
    with open( outPath, "wb" ) as f:
        f.write( b'{"jsonrpc":"2.0","id":1,"method":"initialize"}\n' )
        f.write( ( '{"method":"tools/call","params":{"name":"grep","arguments":{"path":"' + root
                   + '","pattern":"' + pad + '"}},"jsonrpc":"2.0","id":' + wantId + '}\n' ).encode() )

elif mode == "mkeofmidutf8":           # mkeofmidutf8 OUT ROOT — truncated multibyte, NO trailing \n
    outPath, root = sys.argv[ 2 : 4 ]
    with open( outPath, "wb" ) as f:
        f.write( b'{"jsonrpc":"2.0","id":1,"method":"initialize"}\n' )
        f.write( ( '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"grep",'
                   '"arguments":{"path":"' + root + '","pattern":"' ).encode() + b"\xe2\x82" )

elif mode == "lastid":                 # lastid OUT — the id of the LAST response line
    lines = [ l for l in open( sys.argv[ 2 ], "rb" ).read().split( b"\n" ) if l.strip() ]
    if not lines: print( "__NOLINES__" ); raise SystemExit
    try:    print( json.dumps( json.loads( lines[ -1 ].decode( "utf-8", "replace" ) ).get( "id" ) ) )
    except Exception as e: print( "__BADJSON__:" + str( e ) )

elif mode == "countlines":
    print( sum( 1 for l in open( sys.argv[ 2 ], "rb" ).read().split( b"\n" ) if l.strip() ) )

elif mode == "alljson":                # alljson OUT — how many response lines fail to parse
    bad = 0
    for l in open( sys.argv[ 2 ], "rb" ).read().split( b"\n" ):
        if not l.strip(): continue
        try: json.loads( l.decode( "utf-8", "replace" ) )
        except Exception: bad += 1
    print( bad )

else:
    print( "unknown mode " + mode ); raise SystemExit( 2 )
PYDRIVE

DRIVE(){ python3 "$TMP/drive.py" "$@"; }

# ═════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (a) non-ASCII UTF-8 inside a valid request — the byte class that ABORTED the sanitizer ==="
# ═════════════════════════════════════════════════════════════════════════════════════════════════════
DRIVE mkframes "$TMP/a.in" "$FIX" lf \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"grep","arguments":{"path":"@ROOT@","pattern":"café"}}}' \
    '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"grep","arguments":{"path":"@ROOT@","pattern":"€uro"}}}' \
    '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"grep","arguments":{"path":"@ROOT@","pattern":"𝄞clef"}}}' \
    '{"jsonrpc":"2.0","id":5,"method":"tools/list"}'
res="$( DRIVE feed "$BIN" "$TMP/a.out" "$TMP/a.err" "$TMP/a.in" --mcp )"
case "$res" in
    "exit=0 sanitizer=0 timeout=0" ) ok "(a) live: 2/3/4-byte UTF-8 requests answered, exit 0, sanitizer-clean" ;;
    * ) no "(a) live: $res  [stderr: $( head -c 200 "$TMP/a.err" | tr '\n' ' ' )]" ;;
esac
[ "$( DRIVE countlines "$TMP/a.out" )" = 5 ] \
    && ok "(a) live: all 5 frames answered — nothing was swallowed after the first high byte" \
    || no "(a) live: $( DRIVE countlines "$TMP/a.out" ) response lines, want 5"
[ "$( DRIVE lastid "$TMP/a.out" )" = 5 ] \
    && ok "(a) live: the LAST frame (after three non-ASCII ones) still gets its own id" \
    || no "(a) live: last id = $( DRIVE lastid "$TMP/a.out" )"

# the batch arm — the SAME dispatch reached through the `batch` verb's sub-query chain.
DRIVE mkframes "$TMP/ab.in" "$FIX" lf \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"batch","arguments":{"path":"@ROOT@","queries":[{"verb":"grep","pattern":"café"},{"verb":"grep","pattern":"𝄞"}]}}}'
res="$( DRIVE feed "$BIN" "$TMP/ab.out" "$TMP/ab.err" "$TMP/ab.in" --mcp )"
case "$res" in
    "exit=0 sanitizer=0 timeout=0" ) ok "(a) batch verb: non-ASCII sub-queries answered, sanitizer-clean" ;;
    * ) no "(a) batch verb: $res" ;;
esac

# the two CLI siblings — same clone seam, both reproduced the abort independently.
printf 'at café::méthode( %s/geometry.cpp:3 )\n' "$FIX" >"$TMP/trace.in"
res="$( DRIVE feed "$BIN" "$TMP/trace.out" "$TMP/trace.err" "$TMP/trace.in" "$FIX" --from-trace=- )"
case "$res" in
    "exit=0 sanitizer=0 timeout=0" ) ok "(a) sibling --from-trace=-: non-ASCII frame text survived, sanitizer-clean" ;;
    * ) no "(a) sibling --from-trace=-: $res  [stderr: $( head -c 200 "$TMP/trace.err" | tr '\n' ' ' )]" ;;
esac
printf 'grep:café\ngrep:€uro\n' >"$TMP/batch.in"
res="$( DRIVE feed "$BIN" "$TMP/batch.out" "$TMP/batch.err" "$TMP/batch.in" "$FIX" --batch=- )"
case "$res" in
    "exit=0 sanitizer=0 timeout=0" ) ok "(a) sibling --batch=-: non-ASCII verb args survived, sanitizer-clean" ;;
    * ) no "(a) sibling --batch=-: $res  [stderr: $( head -c 200 "$TMP/batch.err" | tr '\n' ' ' )]" ;;
esac
# and both siblings are still deterministic (the reader must not depend on buffer boundaries).
DRIVE feed "$BIN" "$TMP/batch2.out" "$TMP/batch2.err" "$TMP/batch.in" "$FIX" --batch=- >/dev/null
cmp -s "$TMP/batch.out" "$TMP/batch2.out" \
    && ok "(a) sibling --batch=-: two runs byte-identical" \
    || no "(a) sibling --batch=-: two runs DIFFER"

# ═════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (b) CRLF frames behave EXACTLY as LF frames (the '\\r' stays in the line, as getline left it) ==="
# ═════════════════════════════════════════════════════════════════════════════════════════════════════
CRLF_FRAMES=( '{"jsonrpc":"2.0","id":1,"method":"initialize"}'
              '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
              '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"grep","arguments":{"path":"@ROOT@","pattern":"perimeter"}}}'
              '{"jsonrpc":"2.0","id":4,"method":"notifications/initialized"}'
              '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"grep","arguments":{"path":"@ROOT@","pattern":"café"}}}' )
DRIVE mkframes "$TMP/b_lf.in"   "$FIX" lf   "${CRLF_FRAMES[@]}"
DRIVE mkframes "$TMP/b_crlf.in" "$FIX" crlf "${CRLF_FRAMES[@]}"
res_lf="$(   DRIVE feed "$BIN" "$TMP/b_lf.out"   "$TMP/b_lf.err"   "$TMP/b_lf.in"   --mcp )"
res_crlf="$( DRIVE feed "$BIN" "$TMP/b_crlf.out" "$TMP/b_crlf.err" "$TMP/b_crlf.in" --mcp )"
[ "$res_crlf" = "exit=0 sanitizer=0 timeout=0" ] \
    && ok "(b) CRLF session: exit 0, sanitizer-clean" \
    || no "(b) CRLF session: $res_crlf"
if cmp -s "$TMP/b_lf.out" "$TMP/b_crlf.out"; then
    ok "(b) CRLF stdout is byte-identical to LF stdout"
else
    no "(b) CRLF stdout DIFFERS from LF: $( cmp "$TMP/b_lf.out" "$TMP/b_crlf.out" 2>&1 | head -c 160 )"
fi

# ═════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (c) EOF in the middle of a UTF-8 sequence, no trailing newline — deliver once, exit clean ==="
# ═════════════════════════════════════════════════════════════════════════════════════════════════════
DRIVE mkeofmidutf8 "$TMP/c.in" "$FIX"
res="$( DRIVE feed "$BIN" "$TMP/c.out" "$TMP/c.err" "$TMP/c.in" --mcp )"
case "$res" in
    "exit=0 sanitizer=0 timeout=0" ) ok "(c) truncated multibyte at EOF: no abort, no hang, exit 0" ;;
    * ) no "(c) truncated multibyte at EOF: $res  [stderr: $( head -c 200 "$TMP/c.err" | tr '\n' ' ' )]" ;;
esac
# the unterminated tail is delivered EXACTLY once: initialize + one parse-error frame = 2 lines.
[ "$( DRIVE countlines "$TMP/c.out" )" = 2 ] \
    && ok "(c) the unterminated tail line is delivered exactly once (2 response lines)" \
    || no "(c) $( DRIVE countlines "$TMP/c.out" ) response lines, want 2 (init + the tail's refusal)"

# ═════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (d) one 64 KB line, and one 1.5 MB line — read whole, never split (the id is LAST on the line) ==="
# ═════════════════════════════════════════════════════════════════════════════════════════════════════
for spec in "65536|424242|64 KB" "1572864|515151|1.5 MB"; do
    nBytes="${spec%%|*}"; rest="${spec#*|}"; wantId="${rest%%|*}"; label="${rest#*|}"
    DRIVE mkbigline "$TMP/d.in" "$FIX" "$nBytes" "$wantId"
    res="$( DRIVE feed "$BIN" "$TMP/d.out" "$TMP/d.err" "$TMP/d.in" --mcp )"
    lines="$( DRIVE countlines "$TMP/d.out" )"; gotId="$( DRIVE lastid "$TMP/d.out" )"
    if [ "$res" = "exit=0 sanitizer=0 timeout=0" ] && [ "$lines" = 2 ] && [ "$gotId" = "$wantId" ]; then
        ok "(d) a single $label request line: read intact as ONE frame, id=$wantId echoed"
    else
        no "(d) a single $label request line: $res lines=$lines id=$gotId (want 2 / $wantId)"
    fi
done

# ═════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (e) torn frames — nothing until the newline arrives, then EXACTLY one response ==="
# ═════════════════════════════════════════════════════════════════════════════════════════════════════
res="$( DRIVE torn "$BIN" "$FIX" "$TMP/e.out" "$TMP/e.err" )"
set -- $res
tornExit="${1#exit=}"; tornSan="${2#sanitizer=}"
afterInit="${3#afterInit=}"; whileTorn="${4#whileTorn=}"; afterNewline="${5#afterNewline=}"
[ "$tornExit" = 0 ] && [ "$tornSan" = 0 ] \
    && ok "(e) torn session: exit 0, sanitizer-clean" \
    || no "(e) torn session: $res  [stderr: $( head -c 200 "$TMP/e.err" | tr '\n' ' ' )]"
[ "$afterInit" = 1 ] \
    && ok "(e) the initialize frame answered before the torn request began" \
    || no "(e) afterInit=$afterInit, want 1"
[ "$whileTorn" = "$afterInit" ] \
    && ok "(e) NO response while the request is newline-less — the reader blocks, it does not guess" \
    || no "(e) a partial request produced output: whileTorn=$whileTorn afterInit=$afterInit"
[ "$afterNewline" = 2 ] \
    && ok "(e) exactly ONE response once the newline lands (2 lines total)" \
    || no "(e) afterNewline=$afterNewline, want 2"
[ "$( DRIVE lastid "$TMP/e.out" )" = 777 ] \
    && ok "(e) the reassembled frame's trailing id=777 survived — all three pieces joined" \
    || no "(e) reassembled id = $( DRIVE lastid "$TMP/e.out" ), want 777"

# ═════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (f) empty and whitespace-only lines are SKIPPED, exactly as before ==="
# ═════════════════════════════════════════════════════════════════════════════════════════════════════
DRIVE mkframes "$TMP/f.in" "$FIX" lf \
    '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '' '   ' '	' '' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
res="$( DRIVE feed "$BIN" "$TMP/f.out" "$TMP/f.err" "$TMP/f.in" --mcp )"
if [ "$res" = "exit=0 sanitizer=0 timeout=0" ] && [ "$( DRIVE countlines "$TMP/f.out" )" = 2 ]; then
    ok "(f) 4 blank/whitespace lines skipped — exactly 2 responses for 2 real frames"
else
    no "(f) $res lines=$( DRIVE countlines "$TMP/f.out" ) (want 2)"
fi
# a lone '\r' (a CRLF stream's empty line) is whitespace too, and must not be answered.
DRIVE mkframes "$TMP/f2.in" "$FIX" crlf '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
DRIVE feed "$BIN" "$TMP/f2.out" "$TMP/f2.err" "$TMP/f2.in" --mcp >/dev/null
[ "$( DRIVE countlines "$TMP/f2.out" )" = 2 ] \
    && ok "(f) a CRLF stream's empty line (a bare '\\r') is skipped, not answered" \
    || no "(f) bare-'\\r' line produced $( DRIVE countlines "$TMP/f2.out" ) responses, want 2"

# ═════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (g) the HOSTILE SWEEP, repeatable: >=61 adversarial frames in ONE session ==="
# ═════════════════════════════════════════════════════════════════════════════════════════════════════
nFrames="$( DRIVE mkhostile "$TMP/g.in" "$FIX" )"
[ "$nFrames" -ge 61 ] \
    && ok "(g) corpus is $nFrames frames (>=61), generated in-gate and deterministic" \
    || no "(g) corpus is only $nFrames frames — the sweep must be >=61"
res="$( DRIVE feed "$BIN" "$TMP/g.out" "$TMP/g.err" "$TMP/g.in" --mcp )"
case "$res" in
    "exit=0 sanitizer=0 timeout=0" ) ok "(g) the session SURVIVED all $nFrames hostile frames: exit 0, sanitizer-clean" ;;
    * ) no "(g) $res  [stderr: $( head -c 300 "$TMP/g.err" | tr '\n' ' ' )]" ;;
esac
[ "$( DRIVE lastid "$TMP/g.out" )" = 999999 ] \
    && ok "(g) the normal trailing request is still answered (id 999999) — the server is alive at the end" \
    || no "(g) trailing request answer: $( DRIVE lastid "$TMP/g.out" ), want 999999"
[ "$( DRIVE alljson "$TMP/g.out" )" = 0 ] \
    && ok "(g) every response line is well-formed JSON — no hostile frame minted a broken one" \
    || no "(g) $( DRIVE alljson "$TMP/g.out" ) response lines are not valid JSON"
# repeatability is the whole point of turning a one-off sweep into an arm.
DRIVE feed "$BIN" "$TMP/g2.out" "$TMP/g2.err" "$TMP/g.in" --mcp >/dev/null
cmp -s "$TMP/g.out" "$TMP/g2.out" \
    && ok "(g) two sweeps of the same corpus are byte-identical" \
    || no "(g) the sweep is not deterministic: $( cmp "$TMP/g.out" "$TMP/g2.out" 2>&1 | head -c 160 )"

# ═════════════════════════════════════════════════════════════════════════════════════════════════════
if [ -n "$ALT" ]; then
echo
echo "=== (h) BIN vs CTXPACK_BIN_ALT byte-identity on the deterministic arms ==="
# ═════════════════════════════════════════════════════════════════════════════════════════════════════
    if [ ! -x "$ALT" ]; then
        no "(h) CTXPACK_BIN_ALT=$ALT is not executable"
    else
        for pair in "a:--mcp" "b_lf:--mcp" "b_crlf:--mcp" "c:--mcp" "f:--mcp" "g:--mcp"; do
            tag="${pair%%:*}"
            DRIVE feed "$ALT" "$TMP/$tag.alt" "$TMP/$tag.alterr" "$TMP/$tag.in" --mcp >/dev/null
            cmp -s "$TMP/$tag.out" "$TMP/$tag.alt" \
                && ok "(h) arm $tag: BIN and ALT stdout byte-identical" \
                || no "(h) arm $tag: BIN and ALT stdout DIFFER"
        done
    fi
fi

echo
if [ "$fail" -eq 0 ]; then echo "mcpreadloopcheck: ALL PASS"; else echo "mcpreadloopcheck: FAILURES"; fi
exit "$fail"
