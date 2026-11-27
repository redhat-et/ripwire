#!/usr/bin/env bash
# auditregresscheck.sh — the INTEGRATION gate for spec security-regression-integration (v1.1.0): the five
# 2026-09-14 audit reproductions replayed end-to-end against the REAL binary, both transports, plus the
# suite invariants that must survive the composition.
#
# WHY (the closed loop this file closes). Each of the five fixes has its own unit gate, and each passed. What
# no unit gate can say is whether the five compose in one binary: whether the regex screen still refuses on
# the CLI, whether the edit pin still refuses on the tiers it pins, whether the atomic publish still ignores a
# planted temp name, whether hostile git paths still attribute to their real author, and whether each
# transport still refuses past ITS OWN bound and then keeps serving. This gate asserts exactly that, and
# nothing else. Integration specs produce verification, not features: this lane touches zero src/ files.
#
# FOUR THINGS THIS GATE DELIBERATELY DOES NOT DO, each for a measured reason (Phase 0, 2026-11-06):
#
#  1. It does NOT assert a regex REFUSAL over MCP. No MCP verb takes a regex at all: `grep` is literal-only
#     (src/mcpverbs.h:1324 `/*regex=*/false`), and no wire field in the MCP surface matches "regex". So the
#     HTTP leg asserts the TRANSPORT-SAFETY fact instead — a bomb-shaped pattern answers a structured empty
#     (files=0 total=0 complete=true), the server stays responsive, and a POSITIVE CONTROL proves the tree
#     really was scanned. Without that control an empty answer is indistinguishable from a dead scan.
#
#  2. It does NOT arm the bare-stdio edit escape. `ripwire --mcp` with no startup root runs the assumedRoot
#     tier, which the edit pin's own gate (src/mcp.h:1944, `!policy.defaultRoot.empty()`) never enters; an
#     off-workspace edit SUCCEEDS there. That is SRI-F1 (findings/stdio-bare-edit-escape.md), red at base and
#     reproduced by both seats — a proposed unit spec, NOT this lane's arm. A permanently red row is an issue
#     tracker, not a gate. The PINNED tiers (startup-root stdio, HTTP with and without --allow-remote-edits)
#     are asserted here, because those are the tiers the shipped contract pins.
#
#  3. It does NOT conflate the two caps. They are different constants on different transports:
#     HTTP  kMaxBodyBytes         = 8 MiB  (src/mcpserver.h:60)  -> 413 "request body exceeds the 8 MB limit"
#     stdio kMcpStdioLineMaxBytes = 32 MiB (src/mcp.h:3009)      -> -32600 "request line exceeds the
#                                                                        33554432-byte limit"
#     A 9 MiB STDIO LINE IS INSIDE THE SHIPPED BOUND: it is served, correctly, and is therefore NOT an attack
#     row. Arms A5h (HTTP at cap+1) and A5s (stdio past 32 MiB) each assert one error + one healthy follow-up
#     at ITS OWN bound.
#
#  4. It does NOT assert "pargates green" from inside itself. test/pargates.py runs EVERY top-level test/*.sh,
#     this file included, so a gate that ran pargates would re-enter itself without bound. The suite-level
#     oracle for that property is the suite run itself; arm B asserts what a gate CAN own — determinism and
#     XML well-formedness over the adversarial fixture — and SKIPS the two legs it cannot own (pargates,
#     ASan) with a disclosure naming why, rather than pretending.
#
# A3 IS A REGRESSION GUARD, NOT A LIVE ATTACK. The shipped temp name is 24 hex chars drawn from /dev/urandom
# and created O_EXCL|O_NOFOLLOW with 8 EEXIST retries (src/pathguard.h:361-410,507-523), so no name can be
# pre-planted from outside; test/tempfilesymlinkcheck.sh owns the live half and says so in its own header.
# What this arm pins is that the HISTORICAL predictable shapes stay dead, that the edit still publishes, and
# that no temp residue is left behind.
#
# EVERY PATH THIS GATE SENDS IS ABSOLUTE, and every stdio child runs with cwd set to the tree it is being
# asked about. A relative `path` resolves against the CHILD's cwd, so an arm that says "." from the repo root
# is asking about the repo, not about its fixture — a distinction that made an earlier draft of arm A2a pass
# for the wrong reason (refused as "outside", but never aimed at the victim at all).
#
# A1's discriminator is the LEAD-IN, not the verdict word: `refused, nothing was scanned:` is the structural
# screen (verbs_grep.h:998), while `refused, no hit is reported:` is an abandonment (verbs_grep.h:906). Exit
# status, the bare word `refused`, and `catastrophic backtracking` are all unusable as discriminators.
#
# Usage:  test/auditregresscheck.sh [BIN]
#         RIPWIRE_BIN=asan/ripwire test/auditregresscheck.sh
#         RIPWIRE_AUDIT_REPORT=DIR test/auditregresscheck.sh    # also write DIR/report.txt
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
# Arm A4 builds a throwaway git repo, and two more repos are built from Python below. `git -C DIR` changes the
# working DIRECTORY but not the ENVIRONMENT, and GIT_DIR/GIT_WORK_TREE/GIT_INDEX_FILE outrank it — so on a host
# where one is exported (a git hook running the suite, `git rebase --exec`, a CI job) every question this gate
# asks its own repo is answered by somebody else's. Source the repo-wide clearing FIRST; see
# test/lib/clean-env.sh and the sweep that enforces it, test/gitenvhermeticcheck.sh arm (D).
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }

FIXTURE="$ROOT/test/fixtures/audit-reef"
[ -d "$FIXTURE" ] || { echo "auditregresscheck: no fixture tree at $FIXTURE"; exit 2; }
[ -f "$FIXTURE/minified-oneline.js" ] || { echo "auditregresscheck: fixture is missing minified-oneline.js"; exit 2; }

echo "auditregresscheck: BIN=$BIN  ROOT=$ROOT  fixture=$FIXTURE"

# The one HTTP client the --listen gates share (test/lib/gatehttp.sh): it waits until the listener ANSWERS,
# and a request that gets no answer is a FAIL of its own rather than a body to compare. It already sends
# `Accept: application/json, text/event-stream`; a caller must NOT add a second one (a duplicated header is
# rejected as a malformed request, which reads as a refusal and would pass a careless arm).
. "$ROOT/test/lib/gatehttp.sh"
GATEHTTP="$( gatehttp_install "$TMP" )" || { echo "could not write the shared HTTP client into $TMP"; exit 2; }

fails=0
# ok() must survive a failed write of its own PASS line: it records the failure where THIS gate reads it
# (`fails`, tested at the bottom) and still returns 0, so a `… && ok … || no …` chain cannot report the ARM
# as failed when only the terminal was broken. Canonical suite shape; pinned by test/gateexitcheck.sh (G1).
ok(){ printf '  PASS  %s\n' "$1" || { fails=$(( fails + 1 )); printf '  FAIL  could not write the PASS line for: %s\n' "$1"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$1"; fails=$(( fails + 1 )); }
skip(){ printf '  SKIP  %s\n' "$1"; }

# ─── the report rows ──────────────────────────────────────────────────────────────────────────────────────
# One row per (attack, transport) pair — the audited column contract, unchanged:
#     attack_id, transports, expected_shape, observed, wall, verdict
# A row may be `repelled` ONLY when its expected shape string appears IN the captured output, and row()
# enforces that relation rather than trusting the caller's verdict: the report cannot claim a shape the logs
# do not contain. Rows accumulate as TAB-separated fields and are rendered to CSV only at the end.
ROWS="$TMP/rows.tsv"
: >"$ROWS"
row()   # $1 attack, $2 transport, $3 expected, $4 observed, $5 wall, $6 verdict
{
    local attack="$1" transport="$2" expect="$3" observed="$4" wall="$5" verdict="$6"
    case "$observed" in
        *"$expect"*) : ;;                                   # the contracted shape IS in the captured output
        *)
            if [ "$verdict" = "repelled" ]; then
                no "($attack/$transport) verdict 'repelled' but the expected shape is NOT in the output: '$expect'"
                verdict="unproven"
            fi
            ;;
    esac
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$attack" "$transport" "$expect" \
        "$( printf '%s' "$observed" | tr '\n\t' '  ' | sed 's/  */ /g' )" "$wall" "$verdict" >>"$ROWS"
}

# ═══ A1a — the three audit bombs on the CLI, refused structurally ════════════════════════════════════════
# The patterns are the audit reproduction's own. The lead-in is the discriminator (see the header); `rc=1` is
# the CLI's refusal status and the second, independent tell.
echo "arm A1a: the three audit bombs are refused on the CLI (lead-in = the discriminator)"
A1_LEADIN='refused, nothing was scanned:'
a1_all=1; a1_worst=0; a1_saw=""; a1_rcs=""
for pat in '^(a|aa)+b$' '(x|xy)+c$' '(\w|\d)+$'; do
    a1_t0=$( date +%s )
    "$BIN" "$FIXTURE" --regex="$pat" >"$TMP/a1.out" 2>"$TMP/a1.err"
    a1_rc=$?
    a1_wall=$(( $( date +%s ) - a1_t0 ))
    a1_rcs="$a1_rcs$a1_rc"
    cat "$TMP/a1.out" "$TMP/a1.err" >"$TMP/a1.cat" 2>/dev/null
    a1_hit=0; grep -qF -- "$A1_LEADIN" "$TMP/a1.cat" && a1_hit=1
    grep -qF -- 'no hit is reported' "$TMP/a1.cat" && a1_hit=0      # the abandonment lead-in is NOT this one
    if [ "$a1_rc" = 1 ] && [ "$a1_hit" = 1 ] && [ "$a1_wall" -lt 60 ]; then
        ok "A1a --regex='$pat' refused with the structural lead-in (rc=1, ${a1_wall}s)"
    else
        no "A1a --regex='$pat': rc=$a1_rc structural-lead-in=$a1_hit wall=${a1_wall}s — want rc=1 (+lead-in, <60s)"
        a1_all=0
    fi
    [ "$a1_wall" -gt "$a1_worst" ] && a1_worst="$a1_wall"
    # MEASURED, not appended: the lead-in is taken from the output. The reason text after it is a long sentence
    # in the binary's own words, so only the lead-in is quoted — appending a guess at the reason would be the
    # same constructed-observed defect this gate exists to avoid.
    if [ -z "$a1_saw" ]; then
        a1_saw="$( grep -oF -- "$A1_LEADIN" "$TMP/a1.cat" | head -1 )"
        [ -z "$a1_saw" ] && a1_saw="(no structural lead-in in the output)"
    fi
done
a1v="unproven"; [ "$a1_all" = 1 ] && a1v="repelled"
row "A1" "cli" "$A1_LEADIN" "$a1_saw rc per pattern = $a1_rcs" "${a1_worst}s" "$a1v"

# ═══ A4 — hostile git filenames attribute correctly ══════════════════════════════════════════════════════
# The names are git-porcelain-framing's own fixture shapes (test/gitframingcheck.sh:153-158) and the assertions
# follow its idiom (:284-290). They are built at RUN TIME into a fresh mktemp repo rather than committed: a
# committed name containing `|`, a space or a newline does not survive every checkout path, and gitframingcheck
# already establishes runtime construction as the house pattern. Expectations are consumed read-only from that
# gate's literals, not re-typed from a report.
echo "arm A4: hostile git filenames are attributed to their true author"
H="$TMP/hostile"; mkdir -p "$H"
git -C "$H" init -q -b main
printf 'int alphaFn( int x )\n{\n    return x + 1;\n}\n'       > "$H/Alpha.cpp"
printf 'int cFn( int x )\n{\n    return x + 2;\n}\n'           > "$H/__C__"
printf 'int dotFn( int x )\n{\n    return x + 3;\n}\n'         > "$H/__C__.cpp"
printf 'int spoofFn( int x )\n{\n    return x + 4;\n}\n'       > "$H/__C__x|1694000000.cpp"
printf 'int piFn( int x )\n{\n    return x + 5;\n}\n'          > "$H/pi|pe.cpp"
printf 'int nlFn( int x )\n{\n    return x + 6;\n}\n'          > "$H/a"$'\n'"b.cpp"
printf 'int spFn( int x )\n{\n    return x + 7;\n}\n'          > "$H/sp ace.cpp"
git -C "$H" add -A >/dev/null 2>&1
# The author and the COMMITTER are DIFFERENT people on purpose. With both emails equal, an attribution that
# reads `%ce` instead of `%ae` answers identically and this arm cannot tell the two apart — it would pass a
# binary whose ownership field had been swapped. `real@x.com` is the AUTHOR (what every row must name);
# `committer@x.com` is what a swap would produce, and it must appear NOWHERE.
GIT_AUTHOR_NAME=Real GIT_AUTHOR_EMAIL=real@x.com GIT_COMMITTER_NAME=Committer GIT_COMMITTER_EMAIL=committer@x.com \
GIT_AUTHOR_DATE=2026-06-01T12:00:00Z GIT_COMMITTER_DATE=2026-06-01T12:00:00Z \
    git -C "$H" commit -qm c1 >/dev/null 2>&1

attr_of(){ tr '>' '\n' < "$1" | psel "$2" | grep -oE "$3=\"[^\"]*\"" | head -1 | sed 's/^[^"]*"//; s/"$//'; }
psel(){ grep -m1 "$1" || true; }

"$BIN" "$H" --owners --detail=1 --limit=60 >"$TMP/owners.xml" 2>"$TMP/owners.err"
a4_rc=$?
a4_rows=$( tr '>' '\n' <"$TMP/owners.xml" | grep -c '<f p="' )
case "$a4_rc" in 0) ok "A4 --owners exits 0 on the hostile fixture" ;; *) no "A4 --owners exits $a4_rc: $( head -1 "$TMP/owners.err" )" ;; esac
# 6, not 7: the extensionless `__C__` is unindexed BY DESIGN (no grammar), the same reason gitframingcheck's
# own row count excludes it. A count that silently accepted 7 would mean the extensionless file got indexed.
[ "$a4_rows" = 6 ] && ok "A4 all 6 indexed files get ownership rows (__C__ is unindexed by design)" \
                  || no "A4 expected 6 ownership rows, got $a4_rows"
a4_forged=$( grep -o '="x"' "$TMP/owners.xml" | wc -l | tr -d ' ' )
[ "$a4_forged" = 0 ] && ok 'A4 the forged author "x" appears nowhere' \
                     || no "A4 the forged author survived in $a4_forged places"
# The author/committer discriminator. `committer@x.com` is a real email in this repo's history — the committer's
# — so a row naming it is a row that read the wrong field, not a row that found a stranger.
a4_committer=$( grep -c 'committer@x\.com' "$TMP/owners.xml" )
[ "$a4_committer" = 0 ] && ok "A4 no row reads the COMMITTER email — ownership is the author's (%ae, not %ce)" \
                        || no "A4 $a4_committer row(s) name the committer (committer@x.com) — the attribution field is swapped"
a4_true=$( tr '>' '\n' <"$TMP/owners.xml" | grep '<f p="' | grep -c 'top="real@x.com"' )
[ "$a4_true" = "$a4_rows" ] && ok "A4 every row names its true author real@x.com" \
                            || no "A4 only $a4_true of $a4_rows rows name real@x.com"
a4_spoof=$( attr_of "$TMP/owners.xml" '__C__x|1694000000.cpp' top )
[ "$a4_spoof" = "real@x.com" ] && ok "A4 __C__x|1694000000.cpp is owned by its true author" \
                              || no "A4 __C__x|1694000000.cpp is owned by '$a4_spoof'"
a4_nl=$( attr_of "$TMP/owners.xml" 'a&#10;b.cpp' top )
[ "$a4_nl" = "real@x.com" ] && ok "A4 a<LF>b.cpp round-trips as ONE path and is owned by its author" \
                           || no "A4 a<LF>b.cpp is owned by '$a4_nl'"
"$BIN" "$H" --for=nlFn --page-bytes=12000 >"$TMP/for-nl.xml" 2>/dev/null
a4_churn=$( tr '>' '\n' <"$TMP/for-nl.xml" | grep -o 'churn="[0-9]*"' | head -1 | sed 's/[^0-9]//g' )
[ "$a4_churn" = 1 ] && ok "A4 a<LF>b.cpp has churn=1 — one path, one commit" \
                    || no "A4 a<LF>b.cpp churn='$a4_churn', want 1"

a4v="unproven"
[ "$a4_spoof" = "real@x.com" ] && [ "$a4_forged" = 0 ] && [ "$a4_committer" = 0 ] && [ "$a4_churn" = 1 ] \
    && [ "$a4_true" = "$a4_rows" ] && a4v="repelled"
row "A4" "cli" "top=real@x.com" \
    "top=real@x.com on $a4_true/$a4_rows rows; forged-author x seen $a4_forged time(s); committer-email rows $a4_committer; spoof top=$a4_spoof; a<LF>b.cpp churn=$a4_churn (one path)" \
    "${SECONDS}s" "$a4v"

# ═══ the MCP / HTTP arms (A1b, A2a, A2h, A3, A5h, A5s) ═══════════════════════════════════════════════════
# One embedded program, because every one of these arms needs a JSON-RPC client, a port probe and a sha256
# pair, and hand-copying that six times is how the repo's earlier hand-rolled HTTP clients drifted apart. It
# appends its rows to $ROWS in the same TAB schema and emits per-check PASS/FAIL lines the shell folds in.
echo "arms A1b/A2a/A2h/A3/A5h/A5s: MCP stdio and loopback HTTP"
python3 - "$BIN" "$ROOT" "$FIXTURE" "$TMP" "$GATEHTTP" "$ROWS" >"$TMP/mcp.log" 2>&1 <<'PY'
import hashlib, json, os, socket, subprocess, sys, time

BIN, ROOT, FIXTURE, TMP, GATEHTTP, ROWFILE = sys.argv[1:7]
sys.path.insert(0, os.path.dirname(GATEHTTP))
import gatehttp                                   # waitServing / post / NoAnswer — see test/lib/gatehttp.sh

fails = 0
def ok( m ):
    print( "  PASS  " + m )
def no( m ):
    global fails
    print( "  FAIL  " + m ); fails += 1

def sha( p ):
    return hashlib.sha256( open( p, "rb" ).read() ).hexdigest()

def row( attack, transport, expect, observed, wall, verdict ):
    """Same relation the shell's row() enforces: a 'repelled' verdict needs the expected shape IN the output."""
    global fails
    if expect not in observed:
        if verdict == "repelled":
            no( "(%s/%s) verdict 'repelled' but the expected shape is NOT in the output: %r" % ( attack, transport, expect ) )
            verdict = "unproven"
    with open( ROWFILE, "a" ) as f:
        f.write( "\t".join( [ attack, transport, expect, " ".join( observed.split() ), wall, verdict ] ) + "\n" )

def freePort():
    """Bind-and-release: the CLI refuses port 0 (mcpserver.h:453 wants 1..65535), so probe-and-retry is the
    only option; this narrows the race to the microseconds between release and the child's bind."""
    s = socket.socket(); s.bind( ( "127.0.0.1", 0 ) ); p = s.getsockname()[ 1 ]; s.close(); return p

def serve( root, token, extra = (), tries = 20 ):
    """Spawn a listener on a free port; return (proc, port) once it ANSWERS, else (None, None)."""
    for _ in range( tries ):
        port = freePort()
        argv = [ BIN, root, "--listen=127.0.0.1:%d" % port, "--mcp-token=" + token ] + list( extra )
        p    = subprocess.Popen( argv, stdout = subprocess.PIPE, stderr = subprocess.STDOUT )
        why  = gatehttp.waitServing( port, lambda: p.poll() is None, 12.0 )
        if not why:
            return p, port
        p.terminate()
        try: p.wait( 5 )
        except Exception: p.kill()
    return None, None

def httpCall( port, token, body ):
    """gatehttp already sends Accept; adding a second one gets a 400 'malformed HTTP request', which a careless
    arm would read as a refusal. Only the Authorization header is added here."""
    return gatehttp.post( port, body.encode(), b"Authorization: Bearer " + token.encode() + b"\r\n", 90.0 )

def toolCall( name, args ):
    return json.dumps( { "jsonrpc": "2.0", "id": 1, "method": "tools/call",
                         "params": { "name": name, "arguments": args } } )

def stdioSession( root, frames, cwd = None ):
    """One `ripwire <root> --mcp` process. cwd matters: a RELATIVE `path` resolves against the CHILD's cwd,
    so an arm asking about a fixture must either pass an absolute path or run with cwd inside it."""
    p = subprocess.Popen( [ BIN, root, "--mcp" ], stdin = subprocess.PIPE, stdout = subprocess.PIPE,
                          stderr = subprocess.PIPE, text = True, cwd = cwd )
    out, err = p.communicate( "".join( f + "\n" for f in frames ), timeout = 240 )
    parsed = []
    for line in out.splitlines():
        line = line.strip()
        if not line.startswith( "{" ): continue
        try: parsed.append( json.loads( line ) )
        except Exception: pass
    return parsed, err

# ═══ A1b — the bombs are TRANSPORT-SAFE over HTTP ════════════════════════════════════════════════════════
# No refusal is asserted, because there is none to assert: the verb is literal-only, so a regex-shaped pattern
# is an ordinary literal that matches nothing. What IS asserted: the answer is a structured empty (not a hang,
# not a torn frame), the tree was really scanned (the POSITIVE CONTROL), and the server still answers.
print( "arm A1b: bombs are transport-safe over HTTP (structured empty + positive control + responsive)" )
BOMBS = [ "^(a|aa)+b$", "(x|xy)+c$", r"(\w|\d)+$" ]
tok   = "a1b-%d" % os.getpid()
proc, port = serve( FIXTURE, tok )
a1b_ok, a1b_worst, a1b_obs, a1b_ctl, a1b_live = True, 0.0, "", None, False
if proc is None:
    no( "A1b could not start a listener on any probed port (20 tries) — a disclosed failure, never a false pass" )
    a1b_ok = False
else:
    try:
        for pat in BOMBS:
            t0 = time.monotonic()
            try:
                raw = httpCall( port, tok, toolCall( "grep", { "pattern": pat } ) )
            except gatehttp.NoAnswer as e:
                no( "A1b bomb %s got NO ANSWER: %s" % ( pat, e ) ); a1b_ok = False; continue
            dt = time.monotonic() - t0; a1b_worst = max( a1b_worst, dt )
            try:
                env   = json.loads( raw )
                inner = json.loads( env[ "result" ][ "content" ][ 0 ][ "text" ] )
            except Exception as e:
                no( "A1b bomb %s answered an unusable frame (%s): %r" % ( pat, e, raw[ :160 ] ) ); a1b_ok = False; continue
            if inner.get( "files" ) == 0 and inner.get( "total" ) == 0 and inner.get( "complete" ) is True:
                ok( "A1b bomb %-14s -> structured empty (files=0 total=0 complete=true) in %.2fs" % ( pat, dt ) )
            else:
                no( "A1b bomb %-14s -> files=%s total=%s complete=%s (want 0/0/true)"
                    % ( pat, inner.get( "files" ), inner.get( "total" ), json.dumps( inner.get( "complete" ) ) ) )
                a1b_ok = False
            a1b_obs = "structured empty files=%s total=%s complete=%s" % (
                inner.get( "files" ), inner.get( "total" ), json.dumps( inner.get( "complete" ) ) )
        # THE POSITIVE CONTROL: without it an empty answer cannot be told from a scan that never ran.
        try:
            inner = json.loads( json.loads( httpCall( port, tok, toolCall( "grep", { "pattern": "aaaaaaaaaa" } ) ) )[ "result" ][ "content" ][ 0 ][ "text" ] )
            ctl = inner.get( "total", 0 )
            a1b_ctl = ctl
            if ctl and ctl > 0:
                ok( "A1b POSITIVE CONTROL: a literal that IS in the fixture answers total=%s — the tree was scanned" % ctl )
            else:
                no( "A1b POSITIVE CONTROL answered total=%s — the empty bomb answers prove nothing" % ctl ); a1b_ok = False
        except Exception as e:
            no( "A1b positive control failed (%s) — the empty bomb answers prove nothing" % e ); a1b_ok = False
        try:
            if '"result"' in httpCall( port, tok, '{"jsonrpc":"2.0","id":9,"method":"tools/list"}' ):
                a1b_live = True
                ok( "A1b the server still answers tools/list after every bomb" )
            else:
                no( "A1b tools/list after the bombs did not answer a result" ); a1b_ok = False
        except gatehttp.NoAnswer as e:
            no( "A1b tools/list after the bombs got no answer: %s" % e ); a1b_ok = False
    finally:
        proc.terminate()
        try: proc.wait( 10 )
        except Exception: proc.kill()
row( "A1", "http", "structured empty files=0 total=0 complete=true",
     "%s; control=%s; tools/list %s" % ( a1b_obs, a1b_ctl if a1b_ctl is not None else "NOT MEASURED",
                                         "answered" if a1b_live else "MISSING" ),
     "%.2fs" % a1b_worst, "repelled" if a1b_ok else "unproven" )

# ═══ A2a / A2h — off-workspace edits are refused on the PINNED tiers ═════════════════════════════════════
# dir A is the workspace; dir B holds the victim. The attack is the real one: name B's file from a server bound
# to A. On the pinned tiers it must refuse -32602 and leave B byte-identical. ABSOLUTE paths throughout.
print( "arm A2a/A2h: off-workspace edits are refused on the pinned tiers, victim bytes unchanged" )
A = os.path.join( TMP, "A2A" ); B = os.path.join( TMP, "A2B" )
for d in ( A, B ): os.makedirs( d, exist_ok = True )
open( os.path.join( A, "local.c" ), "w" ).write( "int localFn( int x ) { return x + 1; }\n" )
victim = os.path.join( B, "victim.c" )
open( victim, "w" ).write( "int targetFn( int x )\n{\n    return x - 1;\n}\n" )
for d in ( A, B ):
    for cmd in ( [ "git", "init", "-q" ], [ "git", "add", "-A" ],
                 [ "git", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "init" ] ):
        subprocess.run( cmd, cwd = d, stdout = subprocess.DEVNULL, stderr = subprocess.DEVNULL )
before     = sha( victim )
ESCAPE_ARGS = { "path": B, "file": "victim.c", "symbol": "targetFn",
                "new_body": "int targetFn( int x ) { return 1337; }" }

# A2a — the STARTUP-ROOT stdio tier: the pin the shipped contract actually arms.
frames = [ '{"jsonrpc":"2.0","id":1,"method":"initialize"}',
           '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"analyze","arguments":{"path":"."}}}',
           toolCall( "replace_symbol_body", ESCAPE_ARGS ) ]
t0 = time.monotonic()
answers, err = stdioSession( A, frames, cwd = A )
a2a_wall = time.monotonic() - t0
errored = [ a for a in answers if a.get( "id" ) == 1 and "error" in a ]
code = errored[ 0 ][ "error" ].get( "code" ) if errored else None
msg  = errored[ 0 ][ "error" ].get( "message", "" ) if errored else ""
a2a_ok = ( code == -32602 and "path outside workspace" in msg and sha( victim ) == before )
if a2a_ok:
    ok( "A2a startup-root stdio: -32602 naming the workspace; victim unchanged" )
else:
    no( "A2a startup-root stdio: code=%s msg=%r victim_changed=%s"
        % ( code, msg[ :120 ], sha( victim ) != before ) )
row( "A2", "stdio", "path outside workspace",
     "code=%s; %s; victim %s" % ( code if code is not None else "none (no refusal answered)",
                                  "path outside workspace" if ( code == -32602 and "path outside workspace" in msg )
                                  else "no 'path outside workspace' in the answer",
                                  "byte-identical" if sha( victim ) == before else "CHANGED" ),
     "%.2fs" % a2a_wall, "repelled" if a2a_ok else "unproven" )

# A2h — the HTTP tier, asserted BOTH with and without --allow-remote-edits: the workspace pin is not the
# optional edit gate, and an operator who enables remote edits must still not reach outside the pinned tree.
a2h_ok, a2h_worst, a2h_obs = True, 0.0, ""
for extra in ( (), ( "--allow-remote-edits", ) ):
    label = "with --allow-remote-edits" if extra else "default"
    tok   = "a2h-%d-%d" % ( os.getpid(), 1 if extra else 0 )
    proc, port = serve( A, tok, extra )
    if proc is None:
        no( "A2h (%s) could not start a listener on any probed port" % label ); a2h_ok = False
        a2h_obs = "listener never started"
        continue
    try:
        t0 = time.monotonic()
        try:
            raw = httpCall( port, tok, toolCall( "replace_symbol_body", ESCAPE_ARGS ) )
        except gatehttp.NoAnswer as e:
            no( "A2h (%s) got NO ANSWER: %s — not a refusal" % ( label, e ) ); a2h_ok = False
            a2h_obs = "no answer (%s)" % label
            continue
        dt = time.monotonic() - t0; a2h_worst = max( a2h_worst, dt )
        e2 = json.loads( raw ).get( "error", {} )
        live = ( e2.get( "code" ) == -32602 and "outside this server's workspace" in e2.get( "message", "" ) )
        if live and sha( victim ) == before:
            ok( "A2h (%s): -32602 naming the pinned workspace; victim unchanged" % label )
        else:
            no( "A2h (%s): code=%s msg=%r victim_changed=%s"
                % ( label, e2.get( "code" ), e2.get( "message", "" )[ :120 ], sha( victim ) != before ) )
            a2h_ok = False
        # OBSERVED IS MEASURED, never asserted. This line reports the code the server actually answered and the
        # sha256 comparison actually made, so an `unproven` row never displays the shape it failed to produce.
        a2h_obs = "code=%s; %s; victim %s in both states" % (
            e2.get( "code" ),
            "path is outside this server's workspace" if live else "no in-workspace refusal in the answer",
            "byte-identical" if sha( victim ) == before else "CHANGED" )
    finally:
        proc.terminate()
        try: proc.wait( 10 )
        except Exception: proc.kill()
row( "A2", "http", "path is outside this server's workspace", a2h_obs, "%.2fs" % a2h_worst,
     "repelled" if a2h_ok else "unproven" )
if sha( victim ) != before:
    no( "A2 the victim was MODIFIED by a refused path — a refusal that writes is not a refusal" )

# ═══ A3 — the historical temp-name shapes stay dead (regression guard) ═══════════════════════════════════
print( "arm A3: planted temp-name symlinks are never followed (regression guard at the historical shapes)" )
T3 = os.path.join( TMP, "A3TREE" ); os.makedirs( T3 )
subject = os.path.join( T3, "subject.c" )
open( subject, "w" ).write( "int targetFn( int x )\n{\n    return x + 100;\n}\n" )
outside = os.path.join( TMP, "A3-outside.txt" )
open( outside, "w" ).write( "ORIGINAL-EXTERNAL\n" )
for cmd in ( [ "git", "init", "-q" ], [ "git", "add", "-A" ],
             [ "git", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "t" ] ):
    subprocess.run( cmd, cwd = T3, stdout = subprocess.DEVNULL, stderr = subprocess.DEVNULL )
planted = []
for shp in ( str( os.getpid() ), "0", "1", "2", "XXXXXX" ):
    try:
        name = os.path.join( T3, "subject.c." + shp + ".tmp" ); os.symlink( outside, name ); planted.append( name )
    except OSError: pass
try:                                            # the bare no-suffix shape as well
    name = os.path.join( T3, "subject.c.tmp" ); os.symlink( outside, name ); planted.append( name )
except OSError: pass
sub_before, out_before = sha( subject ), sha( outside )
t0 = time.monotonic()
answers, err = stdioSession( T3, [ toolCall( "replace_symbol_body",
    { "path": T3, "file": "subject.c", "symbol": "targetFn",
      "new_body": "int targetFn( int x )\n{\n    return x + 200;\n}" } ) ], cwd = T3 )
a3_wall = time.monotonic() - t0
applied = False
for a in answers:
    if "result" in a:
        try: applied = json.loads( a[ "result" ][ "content" ][ 0 ][ "text" ] ).get( "applied" ) == "replace_symbol_body"
        except Exception: pass
residue = [ f for f in os.listdir( T3 ) if f.endswith( ".tmp" ) and not os.path.islink( os.path.join( T3, f ) ) ]
a3_ok, out_same, sub_changed = True, sha( outside ) == out_before, sha( subject ) != sub_before
if out_same: ok( "A3 all %d planted symlinks ignored — the victim outside is byte-identical" % len( planted ) )
else: no( "A3 A PLANTED SYMLINK WAS FOLLOWED — the victim outside changed" ); a3_ok = False
if applied: ok( "A3 the edit still published to its real target (applied=replace_symbol_body)" )
else: no( "A3 the edit did not report applied — a guard that cannot tell safe from broken is not a guard" ); a3_ok = False
if sub_changed: ok( "A3 subject.c changed as expected — the edit landed" )
else: no( "A3 subject.c did not change — the edit silently did nothing" ); a3_ok = False
if not residue: ok( "A3 no non-symlink *.tmp residue left behind" )
else: no( "A3 temp residue left behind: %r" % residue ); a3_ok = False
# the escaped-root line is an HONEST DISCLOSURE from the crawl, not a defect: tolerated, and asserted present
# so that a future silence there is visible rather than silent.
if "escaped-root" in err or "leaves the crawl root" in err:
    ok( "A3 the crawl disclosed the escaped-root symlinks on stderr (honest, tolerated by design)" )
row( "A3", "stdio", "victim byte-identical", 
     "victim %s; %d planted symlinks ignored; applied=%s; residue=%d"
     % ( "byte-identical" if out_same else "CHANGED", len( planted ), json.dumps( applied ), len( residue ) ),
     "%.2fs" % a3_wall, "repelled" if a3_ok else "unproven" )

# ═══ A5h — the HTTP body cap refuses at ITS bound, once, and keeps serving ═══════════════════════════════
# HEADERS FIRST, then read: the refusal fires on Content-Length (src/mcpserver.h:311) BEFORE the body is read,
# so a client that sendall()s 8 MiB races the server's close and reports a broken pipe instead of the 413 it
# actually got. gatehttp.post is the right client for every normal-size request; this one arm needs the raw
# shape, and says so.
print( "arm A5h: HTTP body cap refuses at cap+1 with 413, then the server serves again" )
CAP = 8 * 1024 * 1024
ACCEPT = b"Accept: application/json, text/event-stream\r\n"
def httpExchange( port, token, nbytes ):
    pre  = b'{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"grep","arguments":{"pattern":"'
    post = b'"}}}'
    body = pre + b"x" * ( nbytes - len( pre ) - len( post ) ) + post
    assert len( body ) == nbytes
    s = socket.create_connection( ( "127.0.0.1", port ), 30 ); s.settimeout( 180 )
    s.sendall( b"POST /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\n"
               + b"Authorization: Bearer " + token.encode() + b"\r\n" + ACCEPT
               + b"Content-Length: " + str( nbytes ).encode() + b"\r\n\r\n" )
    head = b""
    while b"\r\n\r\n" not in head:
        c = s.recv( 4096 )
        if not c: break
        head += c
    h, _, tail = head.partition( b"\r\n\r\n" )
    n = 0
    for line in h.split( b"\r\n" )[ 1: ]:
        k, _, v = line.partition( b":" )
        if k.strip().lower() == b"content-length" and v.strip().isdigit(): n = int( v.strip() )
    got = tail
    if n:
        try: s.sendall( body )                    # only reached when the server did NOT refuse on the headers
        except OSError: pass
        while len( got ) < n:
            c = s.recv( 65536 )
            if not c: break
            got += c
    s.close()
    return h.split( b"\r\n" )[ 0 ].decode( "utf-8", "replace" ), got.decode( "utf-8", "replace" )

tok  = "a5h-%d" % os.getpid()
proc, port = serve( FIXTURE, tok )
a5h_ok, a5h_wall, a5h_obs = True, 0.0, ""
if proc is None:
    no( "A5h could not start a listener on any probed port" ); a5h_ok = False
else:
    try:
        t0 = time.monotonic()
        status, body = httpExchange( port, tok, CAP + 1 )
        a5h_wall = time.monotonic() - t0
        A5HW = "request body exceeds the 8 MB limit"
        if "413" in status and A5HW in body:
            ok( "A5h cap+1 (%d bytes) -> %s + the contracted sentence" % ( CAP + 1, status ) )
        else:
            no( "A5h cap+1 -> %s %r (want 413 + %r)" % ( status, body[ :160 ], A5HW ) ); a5h_ok = False
        # OBSERVED IS MEASURED. The status and the sentence are the ones this exchange actually got; appending
        # the contracted text unconditionally would print `413 … 8 MB limit` beside a row whose check failed.
        a5h_obs = "%s%s" % ( status.replace( "HTTP/1.1 ", "" ),
                             " + the 8 MB sentence" if A5HW in body else " (no 8 MB sentence)" )
        try:
            if '"result"' in httpCall( port, tok, '{"jsonrpc":"2.0","id":9,"method":"tools/list"}' ):
                ok( "A5h the server still serves tools/list after the 413" )
            else:
                no( "A5h tools/list after the 413 did not answer a result" ); a5h_ok = False
        except gatehttp.NoAnswer as e:
            no( "A5h tools/list after the 413 got no answer: %s" % e ); a5h_ok = False
    finally:
        proc.terminate()
        try: proc.wait( 10 )
        except Exception: proc.kill()
row( "A5", "http", "413 Payload Too Large", a5h_obs + "; tools/list answered after it",
     "%.2fs" % a5h_wall, "repelled" if a5h_ok else "unproven" )

# ═══ A5s — the stdio LINE cap refuses at ITS bound, once, and the stream resyncs ═════════════════════════
# 33 MiB, not 9: 9 MiB is INSIDE the shipped 32 MiB stdio bound and is served, correctly. Asserting a refusal
# at 9 MiB would be asserting a bug.
print( "arm A5s: stdio line cap refuses a 33 MiB line once, then the stream answers again" )
A5SW = "request line exceeds the 33554432-byte limit"
big  = "x" * ( 33 * 1024 * 1024 )
t0   = time.monotonic()
answers, err = stdioSession( FIXTURE, [ toolCall( "grep", { "pattern": big } ),
                                        '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' ] )
a5s_wall = time.monotonic() - t0
refusals = [ a for a in answers if a.get( "error", {} ).get( "code" ) == -32600 and A5SW in a.get( "error", {} ).get( "message", "" ) ]
healthy  = [ a for a in answers if a.get( "id" ) == 2 and "result" in a ]
a5s_ok = True
if len( refusals ) == 1: ok( "A5s a 33 MiB line yields exactly one -32600 line-limit refusal" )
else: no( "A5s expected exactly 1 line-limit refusal, got %d" % len( refusals ) ); a5s_ok = False
if healthy: ok( "A5s the stream resynchronised — tools/list answers after the oversize line" )
else: no( "A5s the stream did NOT recover: no tools/list result after the oversize line" ); a5s_ok = False
row( "A5", "stdio", "-32600 %s" % A5SW,
     "-32600 %s; refusals measured: %d; tools/list %s"
     % ( "request line exceeds the 33554432-byte limit" if refusals else "(NOT answered)",
         len( refusals ), "answered" if healthy else "MISSING" ),
     "%.2fs" % a5s_wall, "repelled" if a5s_ok else "unproven" )

sys.exit( 1 if fails else 0 )
PY
mcp_rc=$?
grep -E '^  (PASS|FAIL)' "$TMP/mcp.log" || true
mcp_fails=$( grep -c '^  FAIL' "$TMP/mcp.log" 2>/dev/null || true )
mcp_fails=${mcp_fails:-0}
fails=$(( fails + mcp_fails ))
# A program that died without printing a FAIL still owes an explanation: a silent non-zero here used to mean a
# traceback swallowed the rest of the arms.
if [ "$mcp_rc" != 0 ] && [ "$mcp_fails" = 0 ]; then
    no "the MCP arm program exited $mcp_rc without naming a failure: $( tail -3 "$TMP/mcp.log" | tr '\n' ' ' )"
fi

# ═══ arm B — the invariants a gate can own ═══════════════════════════════════════════════════════════════
# Determinism and XML well-formedness over the ADVERSARIAL fixture: both are cheap, both are the gate's to own.
# pargates and ASan are NOT: pargates runs this file (unbounded recursion), and ASan is a 1.4 GiB rebuild.
# Both are SKIPPED with the reason named — a gate that cannot run must say so, never pretend (the sanctioned
# shape test/argvdiffcheck.sh uses for its RIPWIRE_BASE leg).
echo "arm B: suite-wide invariants a gate can own"
"$BIN" "$FIXTURE" >"$TMP/det-a" 2>/dev/null
"$BIN" "$FIXTURE" >"$TMP/det-b" 2>/dev/null
if [ -s "$TMP/det-a" ] && cmp -s "$TMP/det-a" "$TMP/det-b"; then
    ok "B determinism: two runs over the adversarial fixture are byte-identical"
    b_det="clean"
else
    no "B determinism: the two runs differ (or the first produced nothing)"
    b_det="DIFFERS"
fi
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/det-a" 2>"$TMP/xmllint.err"; then
        ok "B the map over the adversarial fixture is well-formed XML"
        b_xml="clean"
    else
        no "B xmllint rejected the map: $( head -1 "$TMP/xmllint.err" )"
        b_xml="REJECTED"
    fi
else
    skip "B xmllint is not on PATH — XML well-formedness NOT asserted here (the suite's own XML gate owns it)"
    b_xml="not asserted (no xmllint)"
fi
skip "B pargates: NOT run from inside a gate — test/pargates.py runs this file, so asserting it here would recurse without bound; the suite run IS the oracle for that property"
if [ -n "${RIPWIRE_ASAN_BIN:-}" ] && [ -x "${RIPWIRE_ASAN_BIN}" ]; then
    # BOTH channels, because neither alone is enough: LSan exits non-zero on a leak, but an ASan report can be
    # EMITTED and the program still exit 0 (and a suppressions file can hide a class of report). So the exit
    # status is checked AND the stderr is scanned for a sanitizer banner. A clean run must satisfy both.
    if LSAN_OPTIONS=suppressions="$ROOT/lsan_suppressions.txt" "$RIPWIRE_ASAN_BIN" "$FIXTURE" >/dev/null 2>"$TMP/asan.err"; then
        if grep -qE 'ERROR: (Address|Leak)Sanitizer|SUMMARY: (Address|Leak)Sanitizer|runtime error:' "$TMP/asan.err"; then
            no "B ASan/LSan exited 0 but EMITTED a report on the adversarial fixture: $( grep -m2 -E 'ERROR: (Address|Leak)Sanitizer|runtime error:' "$TMP/asan.err" | tr '\n' ' ' )"
            b_asan="REPORTED (exit 0)"
        else
            ok "B ASan/LSan clean over the adversarial fixture — no report on stderr and exit 0 ($RIPWIRE_ASAN_BIN)"
            b_asan="clean"
        fi
    else
        no "B ASan/LSan reported on the adversarial fixture: $( head -3 "$TMP/asan.err" )"
        b_asan="REPORTED"
    fi
else
    skip "B ASan/LSan: no RIPWIRE_ASAN_BIN given (nothing executable at '${RIPWIRE_ASAN_BIN:-<unset>}') — the 1.4 GiB rebuild is a Phase-3 line item, not a per-PR gate; set RIPWIRE_ASAN_BIN to assert it"
    b_asan="not run (no RIPWIRE_ASAN_BIN)"
fi

# ═══ arm C — the report's own shape ══════════════════════════════════════════════════════════════════════
# The column contract is audit-validation-standalone's: `^A[1-5],` rows + trailer lines. Asserted here so a
# drift in this gate's own output fails at the producer, not in the consumer.
#
# EMITTED AND PARSED AS REAL CSV, never by splitting on ", ". A field of this report legitimately CONTAINS
# ", " — AC-1 requires the literal `refused, nothing was scanned:` as the expected shape — so an
# `awk -F', '` column counter reports that row as malformed when it is in fact exactly right. That is the
# suspect-instrument class this seat has been bitten by twice already: the bug was in the ruler, not the
# thing measured. csv.writer quotes only the fields that need it, so the line still begins `A1, ` and the
# consumer's `^A[1-5],` schema grep is untouched.
echo "arm C: the report matches the contracted shape"
REPORT="$TMP/report.txt"
python3 - "$ROWS" "$REPORT" "$b_det" "$b_xml" "$b_asan" <<'PY'
import csv, sys
rows_path, report_path, b_det, b_xml, b_asan = sys.argv[ 1 : 6 ]
ORDER = [ ( "A1", "cli" ), ( "A1", "http" ), ( "A2", "stdio" ), ( "A2", "http" ),
          ( "A3", "stdio" ), ( "A4", "cli" ), ( "A5", "http" ), ( "A5", "stdio" ) ]
store = {}
with open( rows_path, newline = "" ) as f:
    for r in csv.reader( f, delimiter = "\t" ):
        if len( r ) == 6: store.setdefault( ( r[ 0 ], r[ 1 ] ), r )   # first write wins
with open( report_path, "w", newline = "" ) as f:
    w = csv.writer( f, lineterminator = "\n" )                        # QUOTE_MINIMAL: only where needed
    f.write( "# ripwire auditregresscheck — spec security-regression-integration v1.1.0\n" )
    f.write( "# columns: attack_id, transport, expected_shape, observed, wall, verdict\n" )
    for k in ORDER:                                                  # fixed order => stable run to run
        if k in store: w.writerow( store[ k ] )
    f.write( "# trailer\n" )
    f.write( "suite: determinism=%s, xmllint=%s, asan=%s, pargates=the suite run itself "
             "(a gate cannot assert its own suite)\n" % ( b_det, b_xml, b_asan ) )
PY
{ echo "binary: $( "$BIN" --version 2>/dev/null | head -1 )"; } >>"$REPORT"

python3 - "$REPORT" >"$TMP/ccheck" <<'PY'
import csv, sys
rows, bad, notrepelled = 0, 0, []
with open( sys.argv[ 1 ], newline = "" ) as f:
    for r in csv.reader( f ):
        if not r or r[ 0 ] not in ( "A1", "A2", "A3", "A4", "A5" ): continue
        rows += 1
        if len( r ) != 6:
            bad += 1; print( "# row %s/%s has %d columns: %r" % ( r[ 0 ], r[ 1 :2 ], len( r ), r ), file = sys.stderr )
            continue
        if r[ 5 ] != "repelled": notrepelled.append( r[ 0 ] + "/" + r[ 1 ] )
print( "%d\t%d\t%s" % ( rows, bad, " ".join( notrepelled ) ) )
PY
IFS="$( printf '\t' )" read -r c_rows c_bad c_notrepelled <"$TMP/ccheck"

[ "$c_rows" = 8 ] && ok "C the report carries 8 rows, one per (attack, transport) pair" \
                  || no "C expected 8 rows matching ^A[1-5], got $c_rows"
[ "$c_bad" = 0 ] && ok "C every row has exactly 6 columns (parsed as CSV, not split on ', ')" \
                 || no "C $c_bad row(s) do not have 6 columns"
c_ccons=$( grep -cE '^A[1-5],' "$REPORT" )
[ "$c_ccons" = 8 ] && ok "C the consumer's ^A[1-5], schema grep still sees every row" \
                   || no "C the consumer's ^A[1-5], schema grep sees $c_ccons rows, want 8"
[ -z "$c_notrepelled" ] && ok "C every row's verdict is 'repelled'" \
                        || no "C rows not repelled: $c_notrepelled"
grep -q '^binary: ' "$REPORT" && ok "C the trailer carries the binary provenance line" \
                              || no "C the trailer is missing the binary line"

echo
cat "$REPORT"
echo
# The report is emitted on stdout unconditionally (CI log retention); a caller that names a directory also
# gets the file, which is how the local spec's report/ path is satisfied at execution time.
if [ -n "${RIPWIRE_AUDIT_REPORT:-}" ]; then
    if mkdir -p "$RIPWIRE_AUDIT_REPORT" 2>/dev/null && cp "$REPORT" "$RIPWIRE_AUDIT_REPORT/report.txt" 2>/dev/null; then
        echo "auditregresscheck: report written to $RIPWIRE_AUDIT_REPORT/report.txt"
    else
        echo "auditregresscheck: could NOT write the report to $RIPWIRE_AUDIT_REPORT (the stdout copy above is the record)"
        fails=$(( fails + 1 ))
    fi
fi

if [ "$fails" = 0 ]; then
    echo "auditregresscheck: PASS"
    exit 0
fi
echo "auditregresscheck: $fails FAILURE(S)"
exit 1
