#!/usr/bin/env bash
# mcpstampcheck.sh — card AT-STAMP-MCP: the STAMP record serves the MCP server's `at=` stamp too, and the stamp
# stays LIVE while it does.
#
# THE GAP. gitstamp::stampAt asks git three questions per answer: `rev-parse --verify HEAD`, `status --porcelain`
# and `rev-parse --is-shallow-repository`. Two of them — HEAD's sha and the shallow bit — are exactly what the
# STAMP record (src/gitstampcache.h) holds, and on the CLI a served warm `--for` asks neither. But the record was
# armed only for a one-shot CLI --for (gitstampcache.h "WHO ARMS IT"), so the MCP server — the surface an agent
# actually calls — paid all three children on EVERY request, inline on the request thread. Measured on main
# 03cbe7115, six `for` calls in one stdio server: 6 `rev-parse --verify HEAD`, 6 `rev-parse
# --is-shallow-repository`, 6 `status --porcelain`. The same calls on the CLI ask one child each.
#
# WHAT MUST NOT CHANGE. at= is provenance that appears in the answer. HEAD can move between two requests of one
# session, and an edit or a new untracked file can make the tree dirty between them; a stamp frozen for the
# process's lifetime would make at= WRONG. So the record is armed PER REQUEST — arm() re-reads every file its
# answers depend on — and the +dirty bit is never stored at all (gitstampstore.h "WHAT IT IS NOT"): it is asked
# live on every request, as before.
#
# THE OBSERVABLE is git's own trace: GIT_TRACE2_EVENT names one file and every `"event":"start"` is one git
# process (test/c1stampcheck.sh uses the same observable; GIT_TRACE* is in kInertGitVarPrefixes, so it does not
# bypass the record). The server is driven over a FIFO (test/mcpstalecheck.sh's technique) so the tree can be
# changed BETWEEN two requests of one session.
#
# ARMS
#   P  premise: the first `for` answer carries at="<git's own 9-hex HEAD>". Without it no arm below means anything.
#   A  the saving: across THREE identical `for` calls in ONE server over an UNCHANGED tree, at most 1
#      `rev-parse --verify HEAD` and at most 1 `rev-parse --is-shallow-repository` (call 1 records, calls 2-3 are
#      served). RED on main 03cbe7115: 3 of each.
#   B  the dirty bit is NOT cached: `status --porcelain` runs once per `for` call, three times over those three.
#      Green on main too — a non-regression arm, not a fix arm.
#   C  HEAD moves mid-session: `git commit --allow-empty` between two requests of one server, and the next
#      answer's at= is the NEW sha. The correctness arm. Proven able to fail by arm M.
#   D  the tree goes dirty mid-session: an untracked file appears and the next at= gains +dirty; it is removed and
#      the one after loses it again.
#   M  mutation control: C and D re-run with RIPWIRE_TEST_GITSTAMP_MUTANT=trust (a record served WITHOUT
#      re-reading its dependencies) — C must FAIL there. An arm that passes under its own mutant could not have
#      caught the defect it names. On a binary that arms no record at all (main) nothing can freeze, so M is red
#      there too, and says so.
#
# Usage: bash test/mcpstampcheck.sh [BIN]      or   RIPWIRE_BIN=./build/ripwire bash test/mcpstampcheck.sh
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
case "$BIN" in /*) ;; *) BIN="$ROOT/$BIN" ;; esac
echo "mcpstampcheck: BIN=$BIN  $( "$BIN" --version 2>/dev/null | head -1 )"
[ -x "$BIN" ] || { echo "  FAIL  no ripwire binary at $BIN — build first (cmake --build build -j)"; echo "FAIL mcpstampcheck"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "  FAIL  git required"; echo "FAIL mcpstampcheck"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "  FAIL  python3 required (JSON-RPC responses)"; echo "FAIL mcpstampcheck"; exit 2; }

TMP="$( cd "$( mktemp -d )" && pwd -P )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; return 0; }

H="$TMP/home"; mkdir -p "$H"                           # an empty HOME: no global git config in the key
export XDG_CACHE_HOME="$TMP/xdg" TMPDIR="$TMP/tmpdir"  # a cache dir of our own, outside the fixture's work tree
mkdir -p "$XDG_CACHE_HOME" "$TMPDIR"

# ─── the fixture: a git repository with a callee and enough callers that `for` has something to rank ───
REPO="$TMP/repo"; mkdir -p "$REPO"
G(){ HOME="$H" GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_DATE="2025-03-01T00:00:00Z" GIT_COMMITTER_DATE="2025-03-01T00:00:00Z" \
     git -C "$REPO" -c user.name=stamp -c user.email=stamp@example.invalid -c commit.gpgsign=false "$@" >/dev/null 2>&1; }
printf 'def parse_config( text ):\n    return helper( text )\n\n\ndef helper( text ):\n    return text.strip()\n' >"$REPO/lib.py"
for i in 1 2 3 4 5 6 7 8; do
    printf 'from lib import parse_config\n\n\ndef use%s( s ):\n    return parse_config( s )\n' "$i" >"$REPO/use$i.py"
done
G init -q -b main || G init -q
G add -A; G commit -q -m one
headsha(){ HOME="$H" git -C "$REPO" rev-parse HEAD 2>/dev/null | cut -c1-9; }
H0="$( headsha )"
[ ${#H0} -eq 9 ] || { echo "  FAIL  the fixture repository has no HEAD"; echo "FAIL mcpstampcheck"; exit 2; }

# ─── response helpers (test/mcpstalecheck.sh's shape) ────────────────────────────────────────────────
inner_for_id(){ grep "\"id\":$2," "$1" 2>/dev/null | tail -1 | python3 -c '
import sys, json
try:    r = json.load(sys.stdin)
except Exception: print("__NONE__"); raise SystemExit
if "error" in r: print("__ERROR__:" + r["error"].get("message",""))
else:            print(r["result"]["content"][0]["text"].replace("\n", " "))
'; }
wait_for_id(){ local i; for i in $( seq 1 400 ); do grep -q "\"id\":$2," "$1" 2>/dev/null && return 0; sleep 0.05; done; return 1; }
# `printf '%s\n'`, not '%s': BSD sed preserves a missing trailing newline, so six values would land on one line.
atof(){ printf '%s\n' "$1" | sed -n 's/.* at="\([^"]*\)".*/\1/p' | head -1; }
nchild(){ python3 - "$1" "$2" <<'PY'
import sys, json
want, n = sys.argv[2], 0
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    line = line.strip()
    if not line: continue
    try:    e = json.loads(line)
    except Exception: continue
    if e.get("event") != "start": continue
    if want in " ".join(e.get("argv") or []): n += 1
print(n)
PY
}

# ─── one server session; $1 = tag, $2 = "steady" | "live", rest = extra environment NAME=VALUE words ──
# Leaves the trace at $TMP/w-<tag>/trace.jsonl and one at= value per request, in order, in $TMP/w-<tag>/at.txt.
run_session()
{
    local tag="$1" shape="$2"; shift 2
    local W="$TMP/w-$tag"; mkdir -p "$W"
    local TRACE="$W/trace.jsonl"; : >"$TRACE"
    local FIFO="$W/in.fifo"; mkfifo "$FIFO"
    local OUT="$W/out.txt"; : >"$OUT"
    # GIT_CONFIG_NOSYSTEM is deliberately NOT exported to the server: it is a GIT_* variable outside
    # kInertGitVarPrefixes, so it bypasses the record and arm A would be red on every binary for a reason that
    # has nothing to do with this card. GIT_TRACE2_EVENT is inert (the "GIT_TRACE" prefix), which is why it can
    # be the observable at all. The system config is a dependency row like any other (collectGitInputs).
    ( export HOME="$H" GIT_TRACE2_EVENT="$TRACE"
      if [ "$#" -gt 0 ]; then export "$@"; fi
      exec "$BIN" --mcp <"$FIFO" >"$OUT" 2>"$W/err.txt" ) &
    local srv=$! i
    exec 9>"$FIFO"
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' >&9
    ask(){ printf '{"jsonrpc":"2.0","id":%s,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"how parse_config calls helper"}}}\n' "$1" "$REPO" >&9
           wait_for_id "$OUT" "$1" || no "$tag: no answer to request id=$1"; }
    if [ "$shape" = steady ]; then
        for i in 2 3 4; do ask "$i"; done                  # three identical calls, the tree untouched between them
    else
        ask 2
        # The message carries the session tag, so the mutant pass's commit lands on a DIFFERENT sha from the live
        # pass's. With fixed author/committer dates an identical empty commit on an identical parent reproduces the
        # identical sha, and arm M's stale record would then hold the right answer by accident — a poison that is a
        # no-op by construction proves nothing.
        G commit -q --allow-empty -m "two-$tag"            # C: HEAD moves between two requests of ONE server
        ask 3
        : >"$REPO/untracked.py"                            # D: the tree goes dirty
        ask 4
        rm -f "$REPO/untracked.py"                         # D: and clean again
        ask 5
    fi
    exec 9>&-
    wait "$srv" 2>/dev/null || true                        # the server exits on EOF; nothing is left running
    : >"$W/at.txt"
    for i in 2 3 4 5; do
        [ "$shape" = steady ] && [ "$i" = 5 ] && continue
        atof "$( inner_for_id "$OUT" "$i" )" >>"$W/at.txt"
    done
}
at_n(){ sed -n "${2}p" "$1" 2>/dev/null; }   # the Nth at= value (1-based); macOS bash 3.2 has no mapfile

# ═══ steady: three identical calls over an unchanged tree ═══════════════════════════════════════════
echo
echo "=== the MCP server's at= stamp: served from the STAMP record ==="
run_session steady steady
S="$TMP/w-steady"
A1="$( at_n "$S/at.txt" 1 )"
if [ "$A1" = "$H0" ]; then ok "P  the first answer's at=\"$H0\" is git's own HEAD"
else no "P  premise: at=\"$A1\" on the first request, want git's own \"$H0\" — no arm below means anything"; fi

nh="$( nchild "$S/trace.jsonl" "rev-parse --verify --quiet HEAD" )"
ns="$( nchild "$S/trace.jsonl" "rev-parse --is-shallow-repository" )"
if [ "$nh" -le 1 ] && [ "$ns" -le 1 ]; then ok "A  $nh HEAD child and $ns shallow child over 3 identical calls (the record serves calls 2-3)"
else no "A  $nh \`rev-parse --verify HEAD\` and $ns \`rev-parse --is-shallow-repository\` children over 3 identical \`for\` calls on an unchanged tree (want at most 1 each: the STAMP record serves the MCP server too)"; fi

nd="$( nchild "$S/trace.jsonl" "status --porcelain" )"
if [ "$nd" -eq 3 ]; then ok "B  $nd \`status --porcelain\` children over 3 calls: the +dirty bit is never stored"
else no "B  $nd \`status --porcelain\` children over 3 \`for\` calls (want one per call, 3: a stored dirty bit would go stale)"; fi

# ═══ live: the tree changes between requests of ONE server ══════════════════════════════════════════
echo
echo "=== and the stamp stays live: a commit and an untracked file between requests ==="
run_session live live
L="$TMP/w-live"; H1="$( headsha )"
LB="$( at_n "$L/at.txt" 1 )"; LC="$( at_n "$L/at.txt" 2 )"; LD="$( at_n "$L/at.txt" 3 )"; LE="$( at_n "$L/at.txt" 4 )"
if [ "$LB" != "$H0" ]; then no "C  premise: the live session's first at=\"$LB\" is not the pre-commit HEAD \"$H0\""
elif [ "$H1" = "$H0" ]; then no "C  premise: \`git commit --allow-empty\` did not move HEAD (still \"$H0\")"
elif [ "$LC" = "$H1" ]; then ok "C  the request after \`git commit\` carries at=\"$H1\", the new HEAD"
else no "C  at=\"$LC\" after a mid-session commit, want the new HEAD \"$H1\" (old was \"$H0\")"; fi
if [ "$LD" = "$H1+dirty" ] && [ "$LE" = "$H1" ]; then ok "D  +dirty appears with an untracked file and goes when it does"
else no "D  at=\"$LD\" with an untracked file (want \"$H1+dirty\") then \"$LE\" without it (want \"$H1\")"; fi

# ═══ M — the mutation control ═══════════════════════════════════════════════════════════════════════
# A record served WITHOUT re-reading its dependencies is exactly the defect arm C exists to catch, so under that
# mutant C must fail. If it passes, arm C is vacuous and proves nothing about liveness.
echo
echo "=== M: mutation control — a record served unchecked must break arm C ==="
G reset -q --hard HEAD~1 2>/dev/null || true               # back to one commit, so the mutant run repeats the move
rm -f "$REPO/untracked.py"
H0M="$( headsha )"
run_session trust live RIPWIRE_TEST_GITSTAMP_MUTANT=trust
T="$TMP/w-trust"; H1M="$( headsha )"
# The mutant serves the record UNCHECKED, so it can already be stale on the mutant run's FIRST request (the record
# left on disk by the live session above holds that session's post-commit sha). So M asserts only what C asserts,
# negated: the post-commit answer is NOT the new HEAD. Its own vacuity guards are that the run answered at all and
# that the commit really moved HEAD.
TB="$( at_n "$T/at.txt" 1 )"; TC="$( at_n "$T/at.txt" 2 )"
if [ -z "$TB" ] || [ -z "$TC" ]; then
    no "M  the mutant run served no at= (first \"$TB\", post-commit \"$TC\") — the control never reached arm C"
elif [ "$H1M" = "$H0M" ]; then
    no "M  premise: \`git commit --allow-empty\` did not move HEAD in the mutant run (still \"$H0M\")"
elif [ "$TC" != "$H1M" ]; then
    ok "M  under the trust mutant the post-commit at=\"$TC\" is stale, not the new HEAD \"$H1M\" (want-fail): arm C is live"
else
    no "M  under the trust mutant arm C still PASSED (at=\"$TC\" = the new HEAD \"$H1M\"): either arm C cannot catch a frozen stamp, or this binary arms no record for the MCP server at all"
fi

echo
if [ "$fail" -ne 0 ]; then echo "FAIL mcpstampcheck"; exit 1; fi
echo "ALL PASS mcpstampcheck"
