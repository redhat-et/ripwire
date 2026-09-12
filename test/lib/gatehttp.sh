# gatehttp.sh — the ONE HTTP client shared by the gates that start `ripwire --listen`. SOURCED, not run.
#
# Sourced by mcpframehonestycheck.sh (arms I and K2), mcpcontractcheck.sh (arm E) and mcptoolprunecheck.sh. It lives
# under test/lib/ because pargates.py and every gate-conformance sweep treat a top-level test/*.sh as a GATE.
#
#   gatehttp_install DIR  writes DIR/gatehttp.py and prints its path; returns 1 if it could not. That file is a module
#                         (sys.path.insert( 0, DIR ); import gatehttp -> waitServing, post, NoAnswer) and a command:
#                             python3 DIR/gatehttp.py wait PORT PID                -> exit 0 | exit 1 + the sentence
#                             python3 DIR/gatehttp.py post PORT BODY [TIMEOUT_SEC] -> exit 0 + body | exit 3 + the sentence
#
# ONE CLIENT, because every hand-copied one turned a request that got NO ANSWER into an answer. An uncaught recv
# timeout left the body empty, and the empty string went on to be judged: "transports DIFFER … http=" in
# mcpframehonestycheck (CI 2026-09-12, release macos-14, shard 2/4, first frame only), a traceback that silenced every
# later arm in mcpcontractcheck, "premise BROKEN" in mcptoolprunecheck. `post` reads the body to its Content-Length; a
# timeout, a refused connect, a close without a response, a short body or a garbled one raises NoAnswer, whose sentence
# names which. The sentence is context-free: each caller adds what the silence is NOT (a transport difference, a catalog
# verdict).
#
# ONE DEADLINE PER REQUEST. A timeout set on each recv bounds the silence BETWEEN bytes, not the request: a listener that
# sends one byte more often than the timeout kept a request alive, and its buffer growing, for as long as it went on
# sending (review of PR #188). `post` now gives the whole request, connect through the last body byte, one absolute
# deadline, and every blocking call waits only for what is left of it; waitServing does the same against its serving
# ceiling. Nothing is read past a declared Content-Length, and a read that already carried more is a garbled answer,
# never a body cut to length. mcpframehonestycheck (I0) observes it live: a stand-in that trickles a body it never ends.
#
# READY MEANS ANSWERED. A port that ACCEPTS is not a server that answers: runMcpHttp (src/mcpserver.h) listen()s,
# then warms the pinned index, and only then enters its accept loop, while the kernel completes handshakes into the
# backlog. A fixed sleep (mcpcontractcheck's was 2 s) or an accept poll hands whatever warm-up remains to the first
# request's timeout. waitServing polls until a GET /mcp is ANSWERED (any status line proves the accept loop runs:
# 405 bare, 401 under a token) and gives up the moment the child dies.
#
# The two timeouts, measured 2026-09-12 (M-series, 18 cores, test/fixture, cold $TMPDIR, RIPWIRE_MCP_TIMINGS=1): the
# port accepts 0.02–0.06 s after spawn and the first answer lands 0.09–0.11 s after that (0.11–0.19 s with 36 nice-10
# busy loops starving a nice-19 server); every later request answers in < 1 ms, dispatch 0.005–0.06 ms. The 30 s
# serving ceiling is ~150x the starved warm-up; the 5 s default request timeout bounds dispatch alone, and a caller
# whose verbs do real work passes its own. Both are hang tripwires, not performance bars.

gatehttp_install()
{
    local dest="$1/gatehttp.py"
    cat >"$dest" <<'PY' || return 1
import os, socket, sys, time

SERVING_CEILING_SEC = 30.0
REQUEST_TIMEOUT_SEC = 5.0

class NoAnswer( Exception ):
    """There is no response body to judge; str() is the sentence that says why."""

def secondsLeft( deadline ):
    """What is left of an ABSOLUTE deadline, as the next blocking call's timeout; socket.timeout once nothing is."""
    left = deadline - time.monotonic()
    if left <= 0:
        raise socket.timeout( "timed out" )
    return left

def recvBefore( s, deadline, size ):
    """One recv of at most `size` bytes that cannot outlive `deadline`, however often the peer sends."""
    s.settimeout( secondsLeft( deadline ) )
    return s.recv( size )

def waitServing( port, isAlive, ceilingSec = SERVING_CEILING_SEC ):
    """'' once the listener on `port` ANSWERS an HTTP request, else the sentence naming why it never did."""
    deadline = time.monotonic() + ceilingSec
    status   = b"HTTP/1."                              # any status line: 405 bare, 401 under a token
    while time.monotonic() < deadline:
        if not isAlive():
            return "the HTTP listener exited before it answered a request"
        try:                                           # socket.timeout is an OSError: the ceiling passing lands here too
            s = socket.create_connection( ( "127.0.0.1", port ), min( 0.25, secondsLeft( deadline ) ) )
        except OSError:
            time.sleep( 0.02 )
            continue
        try:                                           # connected is not served: wait on THIS connection, to the ceiling
            s.settimeout( secondsLeft( deadline ) )
            s.sendall( b"GET /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n" )
            got = b""
            while len( got ) < len( status ):          # the status prefix and no further, however it is split
                chunk = recvBefore( s, deadline, len( status ) - len( got ) )
                if not chunk:
                    break
                got += chunk
            if got == status:
                return ""
        except OSError:
            pass
        finally:
            s.close()
        time.sleep( 0.02 )
    return "the HTTP listener never ANSWERED a request on 127.0.0.1:%d within %g s" % ( port, ceilingSec )

def contentLength( head ):
    for line in head.split( b"\r\n" )[ 1: ]:
        key, sep, value = line.partition( b":" )
        if sep and key.strip().lower() == b"content-length" and value.strip().isdigit():
            return int( value.strip() )
    return None

def post( port, body, extraHeaders = b"", timeoutSec = REQUEST_TIMEOUT_SEC ):
    """The body of one POST /mcp, read to its Content-Length. Raises NoAnswer when there is no body to judge.

    `timeoutSec` is ONE deadline for the whole request, connect through the last body byte: every blocking call waits
    only for what is left of it, so a listener that keeps sending cannot keep the request alive."""
    req = ( b"POST /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\n" + extraHeaders
            + b"Accept: application/json, text/event-stream\r\nContent-Length: " + str( len( body ) ).encode()
            + b"\r\n\r\n" + body )
    started  = time.monotonic()
    deadline = started + timeoutSec
    try:
        s = socket.create_connection( ( "127.0.0.1", port ), timeoutSec )
    except OSError as e:
        raise NoAnswer( "could not connect to 127.0.0.1:%d (%s)" % ( port, e ) )
    got, tail, length = b"", b"", None
    try:
        s.settimeout( secondsLeft( deadline ) )
        s.sendall( req )
        while True:
            head, sep, tail = got.partition( b"\r\n\r\n" )
            length = contentLength( head ) if sep else None
            if length is not None and len( tail ) > length:
                raise NoAnswer( "the server sent %d body bytes against a declared Content-Length of %d: a garbled answer, "
                                "not a body to cut to length" % ( len( tail ), length ) )
            if length is not None and len( tail ) == length:
                return tail.decode( "utf-8", "replace" )
            chunk = recvBefore( s, deadline, 65536 if length is None else min( 65536, length - len( tail ) ) )
            if not chunk:
                break
            got += chunk
    except socket.timeout:
        raise NoAnswer( "HTTP request timed out after %g s with %d response bytes (%.2f s elapsed%s)"
                        % ( timeoutSec, len( got ), time.monotonic() - started,
                            "" if length is None else "; %d of the %d body bytes its Content-Length declares" % ( len( tail ), length ) ) )
    except OSError as e:
        raise NoAnswer( "HTTP request failed after %d response bytes (%s)" % ( len( got ), e ) )
    finally:
        s.close()
    head, sep, tail = got.partition( b"\r\n\r\n" )
    if not sep:
        raise NoAnswer( "the server closed the connection without an HTTP response (%d bytes)" % len( got ) )
    if contentLength( head ) is not None:
        raise NoAnswer( "the server closed after %d of %d body bytes" % ( len( tail ), contentLength( head ) ) )
    return tail.decode( "utf-8", "replace" )

if __name__ == "__main__":
    verb, port = sys.argv[1], int( sys.argv[2] )
    if verb == "wait":                                 # wait PORT PID -> exit 0 | exit 1 + the sentence
        pid = int( sys.argv[3] )
        def isAlive():
            try:
                os.kill( pid, 0 )
                return True
            except OSError:
                return False
        why = waitServing( port, isAlive )
        sys.stdout.write( why )
        sys.exit( 1 if why else 0 )
    if verb == "post":                                 # post PORT BODY [TIMEOUT_SEC] -> exit 0 + body | exit 3 + the sentence
        try:
            sys.stdout.write( post( port, sys.argv[3].encode(),
                                    timeoutSec = float( sys.argv[4] ) if len( sys.argv ) > 4 else REQUEST_TIMEOUT_SEC ) )
        except NoAnswer as e:
            sys.stdout.write( str( e ) )
            sys.exit( 3 )
        sys.exit( 0 )
    sys.exit( 2 )
PY
    printf '%s' "$dest"
}
