#!/usr/bin/env bash
# mcptoolprunecheck.sh — the MCP catalog must advertise only verbs that CAN succeed on a PINNED workspace.
#
# THE FINDING (octocode recon F4, 2026-08-15): the pinned-root MCP listener advertised all 31 verbs in
# tools/list regardless of what the pinned workspace actually is. On a workspace that is not a git
# repository the git-backed verbs can only ever REFUSE, so every connected agent paid their schema bytes
# every turn to be told "not a git repository" if it ever tried one. octocode's server removes the routes
# for capabilities it does not have; this gate encodes the same rule for the one root we can prove.
#
# THE SCOPE, and why it is exactly this narrow. Omission is only honest when the verb provably cannot
# answer. It is provable for a PINNED root (`--listen`) and nowhere else: that listener serves ONE
# workspace fixed at startup and REFUSES a `path` naming a different tree, so a git verb there has no
# reachable git repo at all. A stdio server — bare, or with a `ripwire <root> --mcp` startup root — still
# answers read verbs about ANY path the caller names, so its git verbs can succeed and stay advertised.
# Arm (F) pins that half: the same non-git directory over stdio still advertises all 31.
#
# WHICH verbs, measured rather than assumed. The recon named five candidates; probing every git-touching
# verb against a non-git pinned root found only THREE that refuse unconditionally:
#     owners / whereis / stray_content    — refuse, always, with their own git cause
# Four others ANSWER without git and are NOT omitted (two of them from the recon's own five) — arm (E) is
# that measurement turned into a gate, so a later widening of the rule has to argue with a passing test
# rather than with a comment:
#     cochange              answers (commits:0 / at:null — the disclosure IS the git-less answer)
#     situational_awareness answers when `files` names the changed files instead of a git diff
#     quality_delta         answers against a quality_baseline SIDECAR (head_sha "(none — not a git repo)")
#     edit_check            answers (every symbol reads as new-symbol vs an absent HEAD)
#
# Omission is a DISCOVERABILITY change, never a capability removal: arm (D) proves an omitted verb still
# dispatches when called by name, refusing with its own honest git cause rather than "unknown tool".
#
# Arms:
#   (A) [red] non-git pinned root: owners / whereis / stray_content are ABSENT from tools/list; the other
#             28 are present, and the count is 28 — not 31.
#   (B) [red] the omission is SELF-DESCRIBING: initialize's `instructions` say the root is not a git
#             repository and NAME the omitted verbs. A silent omission is the dishonest version of this fix.
#   (C) [red] batch's own exclusion arithmetic MOVES with the omission: the "The other N advertised verbs"
#             count equals (advertised - the batch-served verbs still advertised), and the cross-branch
#             prose no longer names verbs this server does not advertise.
#   (D) [red] an omitted verb still DISPATCHES (tools/call owners → its git refusal, not "unknown tool").
#   (E) [red] the four measured non-git-refusing verbs stay advertised — the anti-over-prune arm.
#   (F)       stdio on the SAME non-git directory advertises all 31 and discloses nothing (per-call roots).
#   (G)       a GIT pinned root advertises all 31 and discloses nothing.
#
# Usage:  test/mcptoolprunecheck.sh   |   RIPWIRE_BIN=build_base/ripwire test/mcptoolprunecheck.sh
# Exits non-zero on any failure. Everything happens under a scratch mktemp dir; test/ is never modified.
# Does NOT edit regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'cleanup' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

SRV_PID=""
cleanup(){ [ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null; rm -rf "$TMP"; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for JSON assertions"; exit 2; }
command -v curl    >/dev/null 2>&1 || { echo "curl required (present on macOS/Linux)"; exit 2; }
command -v git     >/dev/null 2>&1 || { echo "git required (arm G pins a GIT workspace)"; exit 2; }

echo "mcptoolprunecheck: BIN=$BIN"

# The three verbs the probe proved cannot answer without git, and the four it proved can.
GIT_ONLY="owners whereis stray_content"
GIT_LESS="cochange situational_awareness quality_delta edit_check"

# finding #12: the exact retained-verb IDENTITY, not just a count — a drop-one/add-one mutation that kept
# the total at 28 (or 31) would slip past a bare wc -w. Spelled once here; every arm below that checks a
# tools/list listing diffs against ALL_VERBS or ALL_VERBS-minus-GIT_ONLY (EXPECTED_NONGIT) rather than
# re-deriving it. names_identical prints OK or the missing/extra sets, so a failure names exactly what moved.
ALL_VERBS="analyze batch cochange connect doc_drift edit_check exemplar explore fetch_body find_referencing_symbols find_symbol flags for from_trace grep impact insert_after_symbol insert_before_symbol lego memory_recall mentions owners path_between quality_baseline quality_delta replace_symbol_body situational_awareness slice stray_content uses whereis"
# NOT built via `$( … case … esac … )` — bash 3.2 (macOS's stock /bin/bash) misparses a case pattern's
# bare `)` inside a `$( )` command substitution as closing the substitution early ("syntax error near
# unexpected token `;;'"), so the filter has to run as a plain loop instead.
EXPECTED_NONGIT=""
for v in $ALL_VERBS; do
    case " $GIT_ONLY " in
        *" $v "*) ;;
        *) EXPECTED_NONGIT="$EXPECTED_NONGIT $v";;
    esac
done
names_identical() { # $1 = got (space-separated), $2 = want (space-separated)
    python3 -c '
import sys
got, want = sorted(sys.argv[1].split()), sorted(sys.argv[2].split())
if got == want:
    print("OK")
else:
    missing = [x for x in want if x not in got]
    extra = [x for x in got if x not in want]
    print("missing:%s extra:%s" % (",".join(missing) or "-", ",".join(extra) or "-"))
' "$1" "$2"
}

# ── three workspaces off ONE corpus: identical trees — full git history, `.git init` with NO commit (finding
# #7's repro), and no git at all ─────────────────────────────────────────────────────────────────────────
NOGIT="$TMP/nogit";  cp -R "$ROOT/test/zoomfix" "$NOGIT"
GITWS="$TMP/gitws";  cp -R "$ROOT/test/zoomfix" "$GITWS"
EMPTYGIT="$TMP/emptygit"; cp -R "$ROOT/test/zoomfix" "$EMPTYGIT"
( cd "$GITWS" && git init -q . && git add -A \
  && git -c user.email=gate@example.invalid -c user.name=gate commit -qm "fixture" ) >/dev/null 2>&1
git -C "$GITWS" rev-parse --verify --quiet HEAD >/dev/null 2>&1 \
    || { echo "could not create the git workspace — arm G cannot run"; exit 2; }
git -C "$NOGIT" rev-parse --show-toplevel >/dev/null 2>&1 \
    && { echo "the non-git workspace resolved INTO a repo ($TMP is inside a checkout?) — arms A-E are void"; exit 2; }
( cd "$EMPTYGIT" && git init -q . ) >/dev/null 2>&1
git -C "$EMPTYGIT" rev-parse --verify --quiet HEAD >/dev/null 2>&1 \
    && { echo "the empty git workspace already has a HEAD commit — arm H is void"; exit 2; }
git -C "$EMPTYGIT" rev-parse --show-toplevel >/dev/null 2>&1 \
    || { echo "the empty git workspace is not even inside a repo (git init failed?) — arm H is void"; exit 2; }

PORT=$(( 21000 + ( $$ % 4000 ) ))
ACCEPT='application/json, text/event-stream'

start_pinned() { # $1 = workspace root
    "$BIN" "$1" --listen=127.0.0.1:"$PORT" >"$TMP/srv.out" 2>"$TMP/srv.err" &
    SRV_PID=$!
    for _ in $( seq 1 60 ); do
        curl -s -o /dev/null -m 1 -H "Accept: $ACCEPT" -H 'Content-Type: application/json' \
             -X POST "http://127.0.0.1:$PORT/mcp" -d '{"jsonrpc":"2.0","id":0,"method":"initialize"}' 2>/dev/null && return 0
        kill -0 "$SRV_PID" 2>/dev/null || return 1
        sleep 0.1
    done
    return 1
}
stop_pinned() { [ -n "$SRV_PID" ] && kill "$SRV_PID" 2>/dev/null; wait "$SRV_PID" 2>/dev/null; SRV_PID=""; }
http_call() {
    curl -s -H "Accept: $ACCEPT" -H 'Content-Type: application/json' \
         -X POST "http://127.0.0.1:$PORT/mcp" -d "$1"
}
stdio_call() { # $1 = workspace root (positional startup root), $2 = the JSON-RPC line
    printf '%s\n%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$2" \
        | "$BIN" "$1" --mcp 2>/dev/null | tail -1
}

# names + count out of a tools/list response; "__ERR__" if it is not one.
names_py='
import sys, json
r = json.load(open(sys.argv[1]))
if "result" not in r: print("__ERR__"); sys.exit(0)
print(" ".join(t["name"] for t in r["result"]["tools"]))
'

# ════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (A) [red] NON-GIT pinned root: the three git-only verbs are omitted from tools/list ==="
# ════════════════════════════════════════════════════════════════════════════════════════════════════
start_pinned "$NOGIT" || { echo "listener on the non-git workspace failed to start: $( head -3 "$TMP/srv.err" )"; exit 1; }
http_call '{"jsonrpc":"2.0","id":1,"method":"initialize"}' > "$TMP/nogit.init"
http_call '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' > "$TMP/nogit.list"
NOGIT_NAMES="$( python3 -c "$names_py" "$TMP/nogit.list" )"
[ "$NOGIT_NAMES" = "__ERR__" ] && { no "(A) tools/list on the non-git pinned root returned an error"; NOGIT_NAMES=""; }

present=""; absent=""
for v in $GIT_ONLY; do
    case " $NOGIT_NAMES " in *" $v "*) present="$present $v";; *) absent="$absent $v";; esac
done
[ -z "$present" ] && ok "(A) omitted:$absent" || no "(A) still advertised on a non-git pinned root:$present"

NOGIT_COUNT="$( printf '%s' "$NOGIT_NAMES" | wc -w | tr -d ' ' )"
[ "$NOGIT_COUNT" = "28" ] && ok "(A) tools/list advertises 28 verbs (31 minus the 3 git-only)" \
                          || no "(A) tools/list advertises $NOGIT_COUNT verbs, expected 28"

# finding #12: count + absence alone would not catch a drop-one/add-one mutation (omit a 28th verb instead
# of / in addition to one of the three, while some OTHER verb slips in) — pin the exact retained SET.
NOGIT_IDENTITY="$( names_identical "$NOGIT_NAMES" "$EXPECTED_NONGIT" )"
[ "$NOGIT_IDENTITY" = "OK" ] && ok "(A) the retained 28 are EXACTLY ALL_VERBS minus the 3 git-only (identity, not just count)" \
                             || no "(A) retained-set identity mismatch: $NOGIT_IDENTITY"

# ════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (B) [red] the omission is self-describing in initialize's instructions ==="
# ════════════════════════════════════════════════════════════════════════════════════════════════════
python3 - "$TMP/nogit.init" "$GIT_ONLY" <<'PY' > "$TMP/disc.res" 2>&1
import sys, json
r = json.load(open(sys.argv[1]))
ins = r.get("result", {}).get("instructions", "")
problems = []
if "git" not in ins.lower():
    problems.append("instructions never mention git")
if "omit" not in ins.lower():
    problems.append("instructions never say anything was omitted")
for v in sys.argv[2].split():
    if v not in ins:
        problems.append("omitted verb '%s' is not named in the instructions" % v)
print("OK" if not problems else "; ".join(problems))
PY
[ "$( cat "$TMP/disc.res" )" = "OK" ] \
    && ok "(B) instructions disclose the omission and name every omitted verb" \
    || no "(B) $( cat "$TMP/disc.res" )"

# ════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (C) [red] batch's exclusion arithmetic moves with the omission ==="
# ════════════════════════════════════════════════════════════════════════════════════════════════════
# The same derivation mcptranchecheck.sh's M14 arm runs, against the PRUNED listing: the count batch
# states must equal (advertised - the batch-served verbs that are still advertised), and the prose must
# not name a verb this server does not serve. A hand-written 17 next to a 28-verb listing is M14's own
# finding, one policy over.
python3 - "$TMP/nogit.list" <<'PY' > "$TMP/m14p.res" 2>&1
import sys, json, re
d = { t["name"]: t for t in json.load(open(sys.argv[1]))["result"]["tools"] }
# P17 (capture-audit 2026-09-04): slice and edit_check joined the served set. Re-pinned to the NEW set.
served = { "for","grep","find_symbol","find_referencing_symbols","impact","uses","mentions",
           "analyze","lego","owners","cochange","path_between","exemplar","fetch_body",
           "slice","edit_check" }
truth = len(d) - len(served & set(d))          # advertised, minus what batch serves AND advertises
b = d.get("batch", {}).get("description", "")
problems = []
m = re.search(r"The other (\d+) advertised verbs", b)
if not m:
    problems.append("batch states no exclusion count")
elif int(m.group(1)) != truth:
    problems.append("batch says %s excluded, the pruned listing's arithmetic says %d" % (m.group(1), truth))
# finding #8: ALL THREE git-only verbs, not just the two that sit in the EXCLUDED half of the sentence.
# `owners` is batch-SERVED (kBatchServedVerbs), so on a pruned catalog it must vanish from the SERVED half
# ("each verb is one of for/grep/.../owners/...") instead — a check that only ever looked at the excluded
# half's two names would miss exactly that bug (mcp.h:687 conditioned one half and not the other).
for gone in ("owners", "whereis", "stray_content"):
    if gone not in d and gone in b:
        problems.append("batch's prose still names '%s', which this server does not advertise" % gone)
print("OK" if not problems else "; ".join(problems))
PY
[ "$( cat "$TMP/m14p.res" )" = "OK" ] \
    && ok "(C) batch's exclusion count and named set match the pruned listing" \
    || no "(C) $( cat "$TMP/m14p.res" )"

# ════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (D) [red] an omitted verb still DISPATCHES — omission is discoverability, not removal ==="
# ════════════════════════════════════════════════════════════════════════════════════════════════════
http_call '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"owners","arguments":{}}}' > "$TMP/owners.res"
python3 - "$TMP/owners.res" <<'PY' > "$TMP/own.res" 2>&1
import sys, json
r = json.load(open(sys.argv[1]))
m = r.get("error", {}).get("message", "")
low = m.lower()
if "result" in r:            print("ANSWERED")                  # a non-git root cannot answer owners
elif "unknown tool" in low:  print("UNKNOWN_TOOL:" + m[:120])   # omission must not disable dispatch
elif "git" in low:           print("OK")
else:                        print("OTHER:" + m[:120])
PY
[ "$( cat "$TMP/own.res" )" = "OK" ] \
    && ok "(D) an omitted verb still dispatches and refuses with its own git cause" \
    || no "(D) $( cat "$TMP/own.res" )"

# ════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (E) [red] anti-over-prune: the verbs that DO answer without git stay advertised ==="
# ════════════════════════════════════════════════════════════════════════════════════════════════════
missing=""
for v in $GIT_LESS; do
    case " $NOGIT_NAMES " in *" $v "*) ;; *) missing="$missing $v";; esac
done
[ -z "$missing" ] && ok "(E) still advertised (they answer without git): $GIT_LESS" \
                  || no "(E) over-pruned — these answer without git but were omitted:$missing"

# and PROVE the premise, so (E) is a measurement rather than a claim: each of the four answers here.
http_call '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"cochange","arguments":{"file":"core/engine.cpp"}}}' > "$TMP/e.cochange"
http_call '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"situational_awareness","arguments":{"files":"core/engine.cpp"}}}' > "$TMP/e.situ"
http_call '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"edit_check","arguments":{"symbol":"engineStepA2"}}}' > "$TMP/e.editcheck"
http_call '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"quality_baseline","arguments":{}}}' > /dev/null
http_call '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"quality_delta","arguments":{}}}' > "$TMP/e.qdelta"
refused=""
for f in cochange situ editcheck qdelta; do
    python3 -c '
import sys, json
r = json.load(open(sys.argv[1]))
print("Y" if "result" in r else "N")
' "$TMP/e.$f" | grep -q Y || refused="$refused $f"
done
[ -z "$refused" ] && ok "(E) premise holds: all four answer on the non-git pinned root" \
                  || no "(E) premise BROKEN — these no longer answer without git:$refused (re-measure before widening the rule)"
stop_pinned

# ════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (F) stdio on the SAME non-git directory advertises all 31 (per-call roots — you cannot know) ==="
# ════════════════════════════════════════════════════════════════════════════════════════════════════
stdio_call "$NOGIT" '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' > "$TMP/stdio.list"
STDIO_NAMES="$( python3 -c "$names_py" "$TMP/stdio.list" )"
STDIO_COUNT="$( printf '%s' "$STDIO_NAMES" | wc -w | tr -d ' ' )"
[ "$STDIO_COUNT" = "31" ] && ok "(F) stdio startup-root server still advertises all 31" \
                          || no "(F) stdio advertises $STDIO_COUNT verbs — a stdio read verb may name ANY path, so nothing is provably unreachable"
STDIO_IDENTITY="$( names_identical "$STDIO_NAMES" "$ALL_VERBS" )"
[ "$STDIO_IDENTITY" = "OK" ] && ok "(F) stdio's 31 are EXACTLY ALL_VERBS (identity, not just count)" \
                             || no "(F) stdio retained-set identity mismatch: $STDIO_IDENTITY"
stdio_call "$NOGIT" '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' >/dev/null
INIT_STDIO="$( printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' | "$BIN" "$NOGIT" --mcp 2>/dev/null | tail -1 )"
printf '%s' "$INIT_STDIO" | python3 -c '
import sys, json
ins = json.load(sys.stdin).get("result", {}).get("instructions", "")
print("QUIET" if "omit" not in ins.lower() else "DISCLOSED_WRONGLY")
' > "$TMP/fdisc"
grep -q QUIET "$TMP/fdisc" && ok "(F) stdio discloses no omission (nothing was omitted)" \
                           || no "(F) stdio claims an omission it did not make"

# ════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (G) a GIT pinned root advertises all 31 and discloses nothing ==="
# ════════════════════════════════════════════════════════════════════════════════════════════════════
start_pinned "$GITWS" || { echo "listener on the git workspace failed to start: $( head -3 "$TMP/srv.err" )"; exit 1; }
http_call '{"jsonrpc":"2.0","id":1,"method":"initialize"}' > "$TMP/git.init"
http_call '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' > "$TMP/git.list"
GIT_NAMES="$( python3 -c "$names_py" "$TMP/git.list" )"
GIT_COUNT="$( printf '%s' "$GIT_NAMES" | wc -w | tr -d ' ' )"
[ "$GIT_COUNT" = "31" ] && ok "(G) git pinned root advertises all 31 verbs" \
                        || no "(G) git pinned root advertises $GIT_COUNT verbs, expected 31"
gone=""
for v in $GIT_ONLY; do
    case " $GIT_NAMES " in *" $v "*) ;; *) gone="$gone $v";; esac
done
[ -z "$gone" ] && ok "(G) every git verb present on a real repo" || no "(G) pruned on a REAL git repo:$gone"
GIT_IDENTITY="$( names_identical "$GIT_NAMES" "$ALL_VERBS" )"
[ "$GIT_IDENTITY" = "OK" ] && ok "(G) the git root's 31 are EXACTLY ALL_VERBS (identity, not just count)" \
                           || no "(G) git-root retained-set identity mismatch: $GIT_IDENTITY"
python3 -c '
import sys, json
ins = json.load(open(sys.argv[1])).get("result", {}).get("instructions", "")
print("QUIET" if "omit" not in ins.lower() else "FALSE_DISCLOSURE")
' "$TMP/git.init" > "$TMP/gdisc"
grep -q QUIET "$TMP/gdisc" && ok "(G) no omission sentence on a git root" || no "(G) instructions claim an omission on a real git repo"
stop_pinned

# ════════════════════════════════════════════════════════════════════════════════════════════════════
echo
echo "=== (H) [red] finding #7: an EMPTY git repo (git init, no commit) gets the QUALIFIED wording ==="
# ════════════════════════════════════════════════════════════════════════════════════════════════════
# THE BUG: gitOnlyOmissionNote used to say, unconditionally, "this server's workspace is not a git
# repository" — FALSE for this workspace, which IS a git repository, it just has no HEAD commit yet. Every
# git-only verb's OWN per-request refusal already carries the honest qualifier ("not a git repository (or
# no HEAD commit)"); the disclosure sentence must say the same thing, not a narrower false one.
start_pinned "$EMPTYGIT" || { echo "listener on the empty-git workspace failed to start: $( head -3 "$TMP/srv.err" )"; exit 1; }
http_call '{"jsonrpc":"2.0","id":1,"method":"initialize"}' > "$TMP/empty.init"
http_call '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' > "$TMP/empty.list"
stop_pinned

EMPTY_NAMES="$( python3 -c "$names_py" "$TMP/empty.list" )"
EMPTY_IDENTITY="$( names_identical "$EMPTY_NAMES" "$EXPECTED_NONGIT" )"
[ "$EMPTY_IDENTITY" = "OK" ] && ok "(H) the empty-git root also prunes to EXACTLY ALL_VERBS minus the 3 git-only" \
                             || no "(H) empty-git retained-set identity mismatch: $EMPTY_IDENTITY"

python3 - "$TMP/empty.init" <<'PY' > "$TMP/empty.res" 2>&1
import sys, json
r = json.load(open(sys.argv[1]))
ins = r.get("result", {}).get("instructions", "")
low = ins.lower()
problems = []
# the FALSE claim the bug made: "is not a git repository" with no qualifier reaching the SAME sentence.
# A workspace that has .git but no HEAD IS a git repository, so that exact unqualified claim must be gone.
if "is not a git repository" in low and "or has no head commit" not in low and "or no head commit" not in low:
    problems.append("still asserts the unqualified false cause 'is not a git repository'")
# the honest content the fix must add: SOME wording naming "no HEAD" / "no commit" as the actual cause.
if "no head commit" not in low and "no head" not in low:
    problems.append("does not name the real cause (no HEAD commit) anywhere in the disclosure")
if "omit" not in low:
    problems.append("instructions never say anything was omitted")
print("OK" if not problems else "; ".join(problems))
PY
[ "$( cat "$TMP/empty.res" )" = "OK" ] \
    && ok "(H) the disclosure names the real cause (no HEAD commit), not the false 'not a git repository' claim" \
    || no "(H) $( cat "$TMP/empty.res" )"

# the byte measurement the recon asked for, reported (not asserted — a byte budget is a ledger, not a gate).
NB="$( wc -c < "$TMP/nogit.list" | tr -d ' ' )"; GB="$( wc -c < "$TMP/git.list" | tr -d ' ' )"
echo
echo "  INFO  tools/list bytes: git root=$GB  non-git pinned root=$NB  (saved $(( GB - NB )))"

echo
if [ "$fail" -eq 0 ]; then echo "ALL PASS"; exit 0; fi
echo "SOME CHECKS FAILED"; exit 1
