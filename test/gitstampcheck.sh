#!/usr/bin/env bash
# gitstampcheck.sh — the gate for r26-stamp Task A: at="<sha>[+dirty]" on every repo-reading verb's root
# element (src/gitstamp.h + its call sites in src/docdrift.h, src/prcontext.h, src/editcheck.h,
# src/landingplan.h, src/situ.h, src/crossref.h, src/serialize.h, src/main.cpp).
#
# Fixture: a throwaway one-commit repo (fixed-ish, RECENT dates so --hotspots' 12-month churn window always
# matches regardless of when this gate runs) with one file carrying enough branching for a non-zero ccx.
#
# Asserts:
#   - clean tree: at="<9-hex>" (no +dirty) on --doctor / --doc-drift / --hotspots / --quality-delta /
#     --cochange / --owners (added 2026-07-28, §P8: the last two unanchored pure-git verbs) /
#     --pr-context / --test-gate / --edit-check=SYM / --whereis=SYM / --stray-content --plan (landing-plan,
#     alongside its pre-existing head=) — the 9-hex prefix matches `git rev-parse --short=9 HEAD` exactly
#   - dirty tree (an uncommitted tracked-file edit): every one of those gains "+dirty", SAME sha prefix,
#     EXCEPT --whereis, which is documented (excluded-file exception, sha-only) to stay bare-sha — this
#     pins that deliberate gap rather than letting it silently drift into "accidentally fixed" or "spread
#     further"
#   - non-git directory: at= is OMITTED entirely on --doctor and --doc-drift (never at="none")
#   - the bare default map (`ripwire <dir>`, no verb) never grows an at= and never shells out to git —
#     `<r>` stays byte-for-byte `<r>` on BOTH a git and a non-git root
#   - --map-diff (which already shells out to git for the diff) DOES stamp `<r at="...">`, single-root only
#   - determinism: two runs over the SAME repo state are byte-identical for every stamped verb
#   - every stamped output stays xmllint-clean
#
# Usage:
#   test/gitstampcheck.sh
#   RIPWIRE_BIN=asan/ripwire test/gitstampcheck.sh
#
# Exits non-zero on any failure; prints PASS/FAIL per check and ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "gitstampcheck: git unavailable — skipping"; exit 0; }

echo "gitstampcheck: BIN=$BIN"

R="$TMP/repo"; mkdir -p "$R/src"
export GIT_AUTHOR_NAME=ripwire GIT_AUTHOR_EMAIL=ripwire@example.invalid
export GIT_COMMITTER_NAME=ripwire GIT_COMMITTER_EMAIL=ripwire@example.invalid
# RECENT dates (1 day ago), not a fixed calendar date: --hotspots scopes churn to "12 months ago" against
# WALL-CLOCK now, so a hardcoded past date would eventually age out of that window and fail this gate for
# a reason that has nothing to do with the stamp being tested.
RECENT="$( date -u -v-1d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '1 day ago' +%Y-%m-%dT%H:%M:%SZ )"
export GIT_AUTHOR_DATE="$RECENT" GIT_COMMITTER_DATE="$RECENT"
g(){ git -C "$R" "$@" >/dev/null 2>&1; }

g init -q -b main
g config commit.gpgsign false

cat > "$R/src/code.h" <<'EOF'
#pragma once
int classify( int a )
{
    if( a > 0 ) return 1;
    else if( a < 0 ) return -1;
    return 0;
}
EOF
g add -A
g commit -q -m "base"

SHA9="$( git -C "$R" rev-parse --short=9 HEAD )"
[ "${#SHA9}" = 9 ] || { echo "gitstampcheck: could not derive a 9-char short sha — aborting"; exit 2; }

# ── clean tree: every stamped verb carries the bare 9-char sha, no +dirty ────────────────────────────────
check_clean()
{
    local desc="$1"; shift
    local out; out="$( "$BIN" "$R" "$@" --no-cache 2>/dev/null )"
    case "$out" in
        *"at=\"$SHA9\""*)      ok "$desc: at=\"$SHA9\" (clean)" ;;
        *"at=\"$SHA9+dirty\""*) no "$desc: at= carries +dirty on a CLEAN tree" ;;
        *)                     no "$desc: no at=\"$SHA9\" found"; echo "$out" | grep -o 'at="[^"]*"' | head -3 ;;
    esac
}

check_clean "doctor"                    --doctor
check_clean "doc-drift"                 --doc-drift
check_clean "hotspots"                  --hotspots
check_clean "quality-delta"             --quality-delta
check_clean "pr-context"                --pr-context
check_clean "test-gate"                 --test-gate
check_clean "edit-check"                --edit-check=classify
check_clean "whereis"                   --whereis=classify
check_clean "landing-plan (--plan)"     --stray-content --plan
# §P8 (2026-07-28) — ADDED: --cochange and --owners are PURE git-history products (a co-change pair mined
# from `git log`, a recency-weighted ownership share), and they were the last two verbs of that kind with no
# anchor at all — a number quoted out of either was unattributable to a HEAD. They belong in this family's
# clean/dirty sweep, not only in attrvocabcheck.sh's presence check.
check_clean "cochange (repo-wide)"      --cochange
check_clean "cochange (per-file)"       --cochange=src/code.h
check_clean "owners"                    --owners

# landing-plan is the "keep both" case: head= (pre-existing) stays a bare 9-char sha alongside the new at=.
out="$( "$BIN" "$R" --stray-content --plan --no-cache 2>/dev/null )"
case "$out" in
    *"head=\"$SHA9\""*) ok "landing-plan: pre-existing head=\"$SHA9\" unchanged" ;;
    *)                  no "landing-plan: head= missing or changed shape" ;;
esac

# ── dirty tree: an uncommitted TRACKED-file edit — every stamp except whereis gains +dirty, same sha ────
printf '\n// a trailing comment, uncommitted\n' >> "$R/src/code.h"

check_dirty()
{
    local desc="$1"; shift
    local out; out="$( "$BIN" "$R" "$@" --no-cache 2>/dev/null )"
    case "$out" in
        *"at=\"$SHA9+dirty\""*) ok "$desc: at=\"$SHA9+dirty\" (dirty)" ;;
        *)                      no "$desc: missing +dirty on a dirty tree"; echo "$out" | grep -o 'at="[^"]*"' | head -3 ;;
    esac
}

check_dirty "doctor"        --doctor
check_dirty "doc-drift"     --doc-drift
check_dirty "hotspots"      --hotspots
check_dirty "quality-delta" --quality-delta
check_dirty "pr-context"    --pr-context
check_dirty "test-gate"     --test-gate
check_dirty "edit-check"    --edit-check=classify

# whereis is the documented EXCEPTION (crossref.h is another agent's file; the exception rule only permits
# adding the bare at= attribute, not a dirty check that needs `root` threaded through too) — pin that it
# STAYS bare-sha even on a dirty tree, so the gap is a recorded decision, not a silent drift either way.
out="$( "$BIN" "$R" --whereis=classify --no-cache 2>/dev/null )"
case "$out" in
    *"at=\"$SHA9\""*)       ok "whereis: at=\"$SHA9\" stays sha-only on a dirty tree (documented gap)" ;;
    *"at=\"$SHA9+dirty\""*) no "whereis: gained +dirty — update this gate's documented-gap comment if intentional" ;;
    *)                      no "whereis: at= missing entirely" ;;
esac

# an untracked file ALSO counts as dirty (mergescout.h's own `git status --porcelain` precedent, no --uno)
g stash -q  # park the tracked edit so this probes untracked-only dirtiness
: > "$R/untracked.txt"
out="$( "$BIN" "$R" --doctor --no-cache 2>/dev/null )"
case "$out" in
    *"at=\"$SHA9+dirty\""*) ok "doctor: an UNTRACKED file alone counts as dirty" ;;
    *)                      no "doctor: an untracked file did not trigger +dirty"; echo "$out" | grep -o 'at="[^"]*"' ;;
esac
rm -f "$R/untracked.txt"
g stash pop -q

# ── the bare default map: NEVER stamped, on a git root or not ────────────────────────────────────────────
# §P8 (2026-07-28) — REPINNED. What this gate protects is unchanged and is NOT "the root has no attributes":
# it is "the default map never pays for a git subprocess", i.e. never grows `at=`. The root legitimately DID
# grow one attribute in the vocabulary pass — `est_tokens=`, computed from bytes already in hand, no git, no
# cost — so the old `*'<r>'*` literal reported "not found at all" for a root that is exactly as unstamped as
# before. Pinned to the ABSENCE of at= (the actual invariant) plus the PRESENCE of the free est_tokens=.
# RE-PINNED 2026-08-19 (R-E CORRECTION): the `<r est_tokens="` literal was POSITIONAL — it assumed
# est_tokens= is the first attribute on <r>, which stopped being true when root= landed in front of it
# (2026-08-17). The INVARIANT this arm protects is unchanged and is asserted directly now: no at= (the
# actual "never pays for a git subprocess" property) and a present, git-free est_tokens=, wherever the two
# sit in the attribute order. Same lesson as the §P8 re-pin above: pin the property, not the byte offset.
out="$( "$BIN" "$R" --no-cache 2>/dev/null )"
rroot="$( printf '%s' "$out" | grep -oE '<r[ >][^>]*' | head -1 )"
case "$rroot" in
    *' at='*)          no "default map: <r> grew an at= — this must never cost a git subprocess on the hot path" ;;
    *'est_tokens="'*)  ok "default map: <r> carries the git-free est_tokens= and no at= ($rroot)" ;;
    '<r>'|'<r '*)      no "default map: <r> lost its est_tokens= — the map's own size is comment-only again" ;;
    *)                 no "default map: <r> not found at all" ;;
esac

# --map-diff DOES stamp <r>: it already shells out to git for the diff itself
out="$( "$BIN" "$R" --map-diff --no-cache 2>/dev/null )"
case "$out" in
    *"<r at=\"$SHA9"*) ok "map-diff: <r at=\"$SHA9...\"> stamped" ;;
    *)                 no "map-diff: <r> was not stamped"; echo "$out" | grep -o '<r[^>]*>' ;;
esac

# ── M10 (capture-audit 2026-09-04, lens7-sibling Family 4 F-STAMP-1/2): six more repo-reading roots with
#    NO anchor at all — --for (churn= per row from a git-log pass), --situ (CLI text + MCP JSON), --naming-
#    calibration (commits=/hunks= from a git-log walk), --merge-scout (head= with no dirty bit despite
#    computing one), --stray-content bare + --abi (same head=-no-dirty gap), --dmm (base=/target= name the
#    COMPARED revisions, not when the tool itself ran). Commit the pending dirty edit so these have a real
#    second commit to diff/compare against, and add a branch off the first commit for merge-scout's REF arg.
g add -A
g commit -q -m "second commit (M10 fixture)"
g branch -q side HEAD~1
SHA9_2="$( git -C "$R" rev-parse --short=9 HEAD )"

check_at_present()
{
    local desc="$1"; shift
    local out; out="$( "$BIN" "$R" "$@" --no-cache 2>/dev/null )"
    case "$out" in
        *"at=\"$SHA9_2\""*|*"at=\"$SHA9_2+dirty\""*) ok "$desc: at= present ($SHA9_2)" ;;
        *)                                            no "$desc: at= missing"; echo "$out" | grep -o 'at="[^"]*"' | head -3 ;;
    esac
}
check_at_text_present()
{
    local desc="$1"; shift
    local out; out="$( "$BIN" "$R" "$@" --no-cache 2>/dev/null )"
    case "$out" in
        *"at: $SHA9_2"*) ok "$desc: at: text line present" ;;
        *)               no "$desc: at: text line missing"; echo "$out" | head -5 ;;
    esac
}
check_at_json_present()
{
    local desc="$1"; shift
    local out; out="$( "$BIN" "$R" "$@" --no-cache 2>/dev/null )"
    case "$out" in
        *"\"at\":\"$SHA9_2\""*|*"\"at\":\"$SHA9_2+dirty\""*) ok "$desc: \"at\" present ($SHA9_2)" ;;
        *)                                                    no "$desc: \"at\" missing"; echo "$out" | grep -o '"at":[^,]*' | head -3 ;;
    esac
}

check_at_present      "for"                 --for="classify" --top-k=3
check_at_json_present  "for --json"         --for="classify" --json
check_at_text_present "situ"                --situ
check_at_present      "naming-calibration"  --naming-calibration
check_at_present       "merge-scout"        --merge-scout=side
check_at_present       "stray-content"      --stray-content
check_at_present       "stray-content --abi" --stray-content --abi
check_at_present       "dmm"                --dmm=HEAD~1..HEAD

# merge-scout / stray-content / abi keep their PRE-EXISTING head= (bare sha, no dirty) alongside the new at=
# — this pins that the rename discipline (M10's "keep head= where a gate pins it") actually held.
out="$( "$BIN" "$R" --merge-scout=side --no-cache 2>/dev/null )"
case "$out" in
    *"head=\"$SHA9_2\""*) ok "merge-scout: pre-existing head=\"$SHA9_2\" unchanged" ;;
    *)                     no "merge-scout: head= missing or changed shape" ;;
esac
out="$( "$BIN" "$R" --stray-content --no-cache 2>/dev/null )"
case "$out" in
    *"head=\"$SHA9_2\""*) ok "stray-content: pre-existing head=\"$SHA9_2\" unchanged" ;;
    *)                     no "stray-content: head= missing or changed shape" ;;
esac

# --handoff: head= was the commit SUBJECT (M0-4's two-meanings-of-head= bug), now subject=; at= is unchanged
out="$( "$BIN" "$R" --handoff --no-cache 2>/dev/null )"
case "$out" in
    *"subject=\"second commit (M10 fixture)\""*) ok "handoff: subject= carries the commit subject" ;;
    *)                                            no "handoff: subject= missing or wrong"; echo "$out" | grep -o '<handoff[^>]*>' ;;
esac
case "$out" in
    *' head="'*) no "handoff: head= should be GONE (renamed to subject=, M0-4)" ;;
    *)           ok "handoff: no stray head= left behind" ;;
esac

# xmllint + determinism on the six new arms
for flags in "--for=classify --top-k=3" "--situ" "--naming-calibration" "--merge-scout=side" "--stray-content" "--dmm=HEAD~1..HEAD" "--handoff"; do
    a="$( "$BIN" "$R" $flags --no-cache 2>/dev/null )"
    b="$( "$BIN" "$R" $flags --no-cache 2>/dev/null )"
    [ "$a" = "$b" ] && ok "determinism ($flags)" || no "determinism ($flags): two runs differed"
    if [ "$flags" != "--situ" ]; then   # --situ is plain text, not XML
        printf '%s' "$a" | xmllint --noout - >/dev/null 2>&1 && ok "xmllint ($flags)" || no "xmllint ($flags) FAILED"
    fi
done

# ── MCP dialect: situational_awareness and for both carry "at" (null on a non-git root, a value here) ────
if command -v python3 >/dev/null 2>&1; then
    MCP_OUT="$( python3 - "$BIN" "$R" "$SHA9_2" <<'PYEOF'
import json, subprocess, sys
binPath, root, sha9 = sys.argv[1], sys.argv[2], sys.argv[3]
p = subprocess.Popen( [ binPath, "--mcp" ], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL )
def call( method, params ):
    req = { "jsonrpc": "2.0", "id": 1, "method": method, "params": params }
    p.stdin.write( json.dumps( req ).encode() + b"\n" ); p.stdin.flush()
    return json.loads( p.stdout.readline().decode() )
call( "initialize", {} )
sa = call( "tools/call", { "name": "situational_awareness", "arguments": { "path": root } } )
fr = call( "tools/call", { "name": "for", "arguments": { "path": root, "task": "classify" } } )
p.stdin.close()
def text_of( r ):
    try:
        return r[ "result" ][ "content" ][ 0 ][ "text" ]
    except Exception:
        return ""
sa_txt = text_of( sa )
fr_txt = text_of( fr )
sa_ok  = ( '"at":"' + sha9 ) in sa_txt or ( '"at":"' + sha9 + "+dirty" ) in sa_txt
fr_ok  = ( 'at="' + sha9 ) in fr_txt
print( "SA_OK=%d FR_OK=%d" % ( int( sa_ok ), int( fr_ok ) ) )
if not sa_ok:
    print( "SA_TEXT_HEAD:" + sa_txt[ :200 ], file=sys.stderr )
# fr_ok has no debug print: MCP `for` lacking at= is a documented, expected scope gap (see the INFO line
# below), not a failure to diagnose.
PYEOF
)"
    case "$MCP_OUT" in
        *"SA_OK=1"*) ok "MCP situational_awareness: \"at\":\"$SHA9_2...\" present" ;;
        *)           no "MCP situational_awareness: \"at\" missing or wrong" ;;
    esac
    # MCP `for`'s header is a SEPARATE hand-rolled emitter (mcpverbs.h), not forLensHeaderText/forLensJsonHeader
    # — CLI --for's at= fix (this round) does not reach it. Reported, not asserted: a scoped-out gap is not a
    # regression, and failing this arm forever would make the gate lie about what it is protecting.
    case "$MCP_OUT" in
        *"FR_OK=1"*) echo "  INFO  MCP for: at= also present (bonus — not required by this gate)" ;;
        *)           echo "  INFO  MCP for: at= absent — documented scope gap, see lane-L9 report (separate emitter, not fixed this round)" ;;
    esac
else
    echo "gitstampcheck: python3 unavailable — skipping the MCP at= arm"
fi

# ── non-git directory: at= is OMITTED entirely, never at="none" ─────────────────────────────────────────
NG="$TMP/nongit"; mkdir -p "$NG"
cat > "$NG/plain.h" <<'EOF'
#pragma once
int justAFunction() { return 1; }
EOF

out="$( "$BIN" "$NG" --doctor --no-cache 2>/dev/null )"
case "$out" in
    *'at="'*) no "doctor on a non-git root: at= should be OMITTED, found one"; echo "$out" | grep -o '<doctor[^>]*>' ;;
    *)        ok "doctor on a non-git root: at= omitted" ;;
esac

out="$( "$BIN" "$NG" --doc-drift --no-cache 2>/dev/null )"
case "$out" in
    *'at="'*) no "doc-drift on a non-git root: at= should be OMITTED, found one"; echo "$out" | grep -o '<doc-drift[^>]*>' ;;
    *)        ok "doc-drift on a non-git root: at= omitted" ;;
esac

out="$( "$BIN" "$NG" --no-cache 2>/dev/null )"
case "$out" in
    *'<r>'*)    ok "default map on a non-git root: <r> stays bare" ;;
    *'<r at='*) no "default map on a non-git root: <r> should never gain at=" ;;
esac

# ── determinism + xmllint on the (still-dirty) repo state left over from above ───────────────────────────
for flags in "--doctor" "--doc-drift" "--hotspots" "--quality-delta" "--pr-context" "--test-gate"; do
    a="$( "$BIN" "$R" $flags --no-cache 2>/dev/null )"
    b="$( "$BIN" "$R" $flags --no-cache 2>/dev/null )"
    cmp_a="$a"; cmp_b="$b"
    if [ "$flags" = "--doctor" ]; then
        # --doctor's cache-dir check reports LIVE counters (blobs=/bytes=) of the shared per-user temp
        # cache dir. That dir is machine-global, so any concurrent ripwire activity (another agent
        # session, another worktree's test run) can grow those counters between these two back-to-back
        # runs even though the binary itself is perfectly deterministic. This arm asserts output-SHAPE
        # determinism of the binary, not that the whole machine held still — so normalize the volatile
        # attributes out of BOTH sides before comparing; everything else still has to match byte-for-byte.
        #
        # many= and truncated= are normalized for exactly the same reason and were the hole this arm
        # flaked through under `pargates.py -j 6`: they are not independent facts, they are DERIVED from
        # the very same live scan as blobs=/bytes=, so scrubbing the counters while still comparing the
        # flags computed from them left the arm as machine-sensitive as before. Measured on a loaded
        # machine (load average ~38, suite running at -j 6): 1 pair in ~3 flipped truncated="0" ->
        # truncated="1" between two back-to-back runs, and the arm reported it as a determinism failure
        # of the BINARY. Anchored on the cache-dir row so a truncated= belonging to any other <c> row is
        # still compared verbatim; if that row's shape ever changes the substitution simply no-ops and
        # the arm goes back to being strict, which is the safe direction for it to fail in.
        scrubCacheDir(){ sed -E 's/(n="cache-dir"[^>]*)blobs="[0-9]+" bytes="[0-9]+" many="[01]" truncated="[01]"/\1blobs="N" bytes="N" many="N" truncated="N"/'; }
        cmp_a="$( printf '%s' "$a" | scrubCacheDir )"
        cmp_b="$( printf '%s' "$b" | scrubCacheDir )"
    fi
    [ "$cmp_a" = "$cmp_b" ] && ok "determinism ($flags)" || no "determinism ($flags): two runs differed"
    printf '%s' "$a" | xmllint --noout - >/dev/null 2>&1 && ok "xmllint ($flags)" || no "xmllint ($flags) FAILED"
done

if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "SOME FAILED"; fi
exit "$fail"
