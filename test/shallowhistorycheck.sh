#!/usr/bin/env bash
# shallowhistorycheck.sh — the history verbs tell the truth on a shallow clone (0.6.6 command sweep).
#
# A `git clone --depth 1` (actions/checkout's default) holds one commit. The sweep ran every history verb on two
# such clones and found each one saying something false about the REPOSITORY, with at='s "+shallow" suffix the
# only hint:
#   --quality-delta=HEAD, --dmm=HEAD   "a root commit has no earlier tree" — HEAD is the shallow boundary, and its
#                                      parent exists upstream; it was not fetched.
#   --owners                           bf="1" share="1.00" on every file, from one squashed commit, unqualified.
#   --cochange                         "git unavailable / no history (need a git repo)" in a git repo.
#   --rank-by=churn-decay              window="all-history half-life=90d" over one commit.
#   --hotspots                         churn="1" on every row under a twelve-month window label, unqualified.
#   --pr-context / --merge-scout       "unknown ref 'HEAD~1'" with no word about the likeliest cause.
#
#   --pr-context / --situ (0.6.7)    embedded owners/co-change/window rows with no qualification at all.
#   --quality-delta=HEAD~1, --dmm=HEAD~1, --since=HEAD~1 (0.6.7)  "does not resolve" / "neither a git revision" with no word
#                                      about the likeliest cause, while the pr-context/merge-scout refusals already named it.
#   --hotspots/--cochange --since=HEAD (0.6.7)  an empty since-window root returned before the qualified emitter, unqualified.
#
# CONTRACT (one probe, one attribute): on the shallow clone each verb says "shallow" and how to deepen, the
# qualified roots carry shallow="1" with a legend clause defining it (full AND compact), and the MCP owners and
# cochange twins carry the same qualification. On the FULL clone of the same history none of it appears, a true
# root commit is still called one, and "all-history" is still the decay window.
#
# Usage: bash test/shallowhistorycheck.sh [path/to/ripwire]     (default build/ripwire)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }

fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=$(( fail + 1 )); printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=$(( fail + 1 )); }

T="$( mktemp -d )"
trap 'rm -rf "$T"' EXIT
FULL="$T/full"; SH="$T/shallow"

# Three commits by two authors. The last one touches 33 files, over --cochange's 30-file bulk cap, so the depth-1
# clone's only commit is skipped as bulk and --cochange has nothing to mine (the shape the sweep hit).
mkdir -p "$FULL" && (
    cd "$FULL" && git init -q -b main .     && printf 'int helper( int x ) { return x + 1; }\nint twice( int x ) { return helper( helper( x ) ); }\n' > a.c     && printf 'int helper( int x );\nint useit( int y ) { if( y > 2 ) { return helper( y ); } return 0; }\n' > b.c     && git add -A && git -c user.name=A -c user.email=a@example.invalid commit -qm one     && printf 'int extra( void ) { return 3; }\n' >> a.c     && git -c user.name=B -c user.email=b@example.invalid commit -qam two     && printf 'int more( void ) { return extra(); }\n' >> b.c     && for i in $( seq 1 31 ); do printf 'int f%d( int v ) { if( v ) { return %d; } return 0; }\n' "$i" "$i" > "m$i.c"; done     && git add -A && git -c user.name=A -c user.email=a@example.invalid commit -qm three ) >/dev/null 2>&1 || { echo "  FAIL  fixture: could not build the full-history repo"; echo "1 CHECK(S) FAILED"; exit 1; }
git clone -q --depth 1 "file://$FULL" "$SH" >/dev/null 2>&1 || { echo "  FAIL  fixture: git clone --depth 1 failed"; echo "1 CHECK(S) FAILED"; exit 1; }
if [ "$( git -C "$SH" rev-parse --is-shallow-repository )" = true ] && [ "$( git -C "$FULL" rev-parse --is-shallow-repository )" = false ]; then ok "fixture: a depth-1 clone (shallow) of a three-commit repo (full)"; else no "fixture: shallow/full probe mismatch"; echo "$fail CHECK(S) FAILED"; exit 1; fi

run(){ "$BIN" "$1" "${@:2}" --no-cache 2>&1; }
root_of(){ printf '%s' "$1" | python3 -c 'import re,sys
s=re.sub(r"<!--.*?-->","",sys.stdin.read(),flags=re.S); m=re.search(r"<[A-Za-z][^>]*>",s); print(m.group(0) if m else "")'; }
has(){ printf '%s' "$1" | grep -qF -- "$2"; }
# a legend comment (full clause or compact reading) that defines shallow=
legend_defines_shallow(){ printf '%s' "$1" | python3 -c 'import re,sys
s=sys.stdin.read(); c=" ".join(re.findall(r"<!--(.*?)-->",s,flags=re.S))
sys.exit(0 if re.search(r"shallow=(\\?\"1\\?\"|1)",c) else 1)'; }

# ── 1. the rev forms: a shallow boundary is not a root commit ─────────────────────────────────────────────
Q="$( run "$SH" --quality-delta=HEAD )"
if { has "$Q" "shallow" && has "$Q" "git fetch --deepen" && ! has "$Q" "a root commit has no"; }; then ok "quality-delta=HEAD on the shallow boundary says shallow + how to deepen, not 'root commit'"; else no "quality-delta=HEAD on shallow: $( printf '%s' "$Q" | head -c 300 )"; fi
QF="$( run "$FULL" --quality-delta=HEAD~2 )"
if has "$QF" "a root commit has no" && ! has "$QF" "shallow"; then ok "quality-delta=HEAD~2 on the full clone's true root commit still says 'root commit'"; else no "full-clone root commit: $( printf '%s' "$QF" | head -c 300 )"; fi
D="$( run "$SH" --dmm=HEAD )"; DR="$( root_of "$D" )"
if { has "$DR" 'dmm="UNAVAILABLE"' && has "$DR" "shallow" && ! has "$DR" "a root commit has no"; }; then ok "dmm=HEAD on the shallow boundary: reason= says shallow, not 'root commit'"; else no "dmm=HEAD on shallow: $DR"; fi

# ── 2. qualified roots: owners, hotspots, cochange (FILE form) carry shallow="1", defined in both legends ──
for v in --owners --hotspots --cochange=a.c; do
    for leg in full compact; do
        O="$( run "$SH" "$v" --legend=$leg )"; R="$( root_of "$O" )"
        if has "$R" 'shallow="1"'; then ok "$v ($leg): the root carries shallow=\"1\""; else no "$v ($leg): no shallow=\"1\" on the root: $R"; fi
        if legend_defines_shallow "$O"; then ok "$v ($leg): the legend defines shallow="; else no "$v ($leg): shallow= emitted and not defined in the legend"; fi
        if printf '%s' "$O" | xmllint --noout - 2>/dev/null; then ok "$v ($leg): well-formed"; else no "$v ($leg): not well-formed XML"; fi
    done
    # (the at= clause always explains a "+shallow" suffix, so the full-clone probe looks for OUR two artefacts)
    F="$( run "$FULL" "$v" --legend=full )"
    if { has "$F" 'shallow="1"' || has "$F" '<!-- shallow='; }; then no "$v on the full clone carries shallow=\"1\" or its clause"; else ok "$v on the full clone: no shallow attribute or clause"; fi
done

# ── 2m. multi-root: a FULL primary + a SHALLOW secondary still qualifies (0.6.6 review) ──
# hotspots, repo-wide cochange and owners mine EVERY workspace root, but the probe read only the primary root, so the
# merged answer carried no shallow="1" although part of its history was depth-limited. The control is two full roots.
FULL2="$T/full2"; git clone -q "file://$FULL" "$FULL2" >/dev/null 2>&1 || no "fixture: second full clone failed"
for v in --hotspots --owners --cochange; do
    M="$( "$BIN" "$FULL" "$SH" "$v" --legend=full --no-cache 2>/dev/null )"; RC=$?; MR="$( root_of "$M" )"
    if [ "$RC" -le 1 ] && has "$MR" 'shallow="1"' && legend_defines_shallow "$M"; then ok "$v full+shallow workspace: the root carries shallow=\"1\", defined"
    else no "$v full+shallow workspace (rc=$RC): no shallow=\"1\" on the root: $MR"; fi
    MF="$( "$BIN" "$FULL" "$FULL2" "$v" --legend=full --no-cache 2>/dev/null )"
    if { has "$MF" 'shallow="1"' || has "$MF" '<!-- shallow='; }; then no "$v full+full workspace carries shallow=\"1\" or its clause"; else ok "$v full+full workspace: no shallow attribute or clause"; fi
done

# ── 3. cochange (repo form) on the shallow stub: the refusal names the real cause ──
C="$( run "$SH" --cochange )"
if { has "$C" "shallow clone" && has "$C" "git fetch --deepen" && ! has "$C" "git unavailable"; }; then ok "cochange on a shallow stub with nothing mineable: 'shallow clone', not 'git unavailable'"; else no "cochange on shallow: $( printf '%s' "$C" | head -c 300 )"; fi

# ── 3m. multi-root refusal: a FULL primary + a SHALLOW secondary, neither with a mineable commit (CodeRabbit, train 22) ──
# The failure paths probed the primary root alone, so the refusal said "git unavailable" although the secondary is a
# depth-limited clone. Each root's commits touch only notes.txt, which no verb mines. Control: two full roots.
MR="$T/mr"; mkdir -p "$MR"
mk_notes(){ mkdir -p "$1" && ( cd "$1" && git init -q -b main . && echo one > notes.txt && git add -A && git -c user.name=A -c user.email=a@example.invalid commit -qm one && echo two >> notes.txt && git -c user.name=A -c user.email=a@example.invalid commit -qam two ) >/dev/null 2>&1; }
mk_notes "$MR/P"; mk_notes "$MR/Qsrc"
git clone -q --depth 1 "file://$MR/Qsrc" "$MR/Q" >/dev/null 2>&1; git clone -q "file://$MR/P" "$MR/P2" >/dev/null 2>&1
printf 'int p( int x ) { if( x ) { return 1; } return 0; }\n' > "$MR/P/p.c"; cp "$MR/P/p.c" "$MR/P2/p2.c"
printf 'int q( int x ) { if( x ) { return 2; } return 0; }\n' > "$MR/Q/q.c"
for v in --cochange --owners; do
    E="$( "$BIN" "$MR/P" "$MR/Q" "$v" --no-cache 2>&1 >/dev/null )"; RC=$?
    if [ "$RC" = 1 ] && has "$E" "shallow clone" && has "$E" "git fetch --deepen" && ! has "$E" "git unavailable"; then ok "$v full+shallow workspace, nothing mineable: the refusal names the shallow root, not 'git unavailable'"
    else no "$v full+shallow workspace refusal (rc=$RC): $( printf '%s' "$E" | head -c 300 )"; fi
    E="$( "$BIN" "$MR/P" "$MR/P2" "$v" --no-cache 2>&1 >/dev/null )"
    if has "$E" "git unavailable" && ! has "$E" "shallow"; then ok "$v full+full workspace, nothing mineable: still 'git unavailable', no shallow claim"
    else no "$v full+full workspace refusal: $( printf '%s' "$E" | head -c 300 )"; fi
done

# ── 4. churn windows: no all-history over a stub ──
RB="$( root_of "$( run "$SH" --rank-by=churn-decay )" )"
if { ! has "$RB" "all-history" && has "$RB" "shallow clone"; }; then ok "rank-by=churn-decay on shallow: window= is not all-history and says shallow clone"; else no "rank-by=churn-decay on shallow: $RB"; fi
RF="$( root_of "$( run "$FULL" --rank-by=churn-decay )" )"
if { has "$RF" 'window="all-history half-life=' && ! has "$RF" "shallow"; }; then ok "rank-by=churn-decay on the full clone: window= is still all-history"; else no "rank-by=churn-decay on full: $RF"; fi
RC="$( root_of "$( run "$SH" --rank-by=churn )" )"
if has "$RC" "(shallow clone)"; then ok "rank-by=churn on shallow: window= says shallow clone"; else no "rank-by=churn on shallow: $RC"; fi

# ── 5. unknown refs get the shallow hint (and only on a shallow clone) ──
for v in --pr-context=HEAD~1 --merge-scout=HEAD~1; do
    E="$( run "$SH" "$v" )"
    if { has "$E" "unknown" && has "$E" "shallow clone" && has "$E" "git fetch --deepen"; }; then ok "$v on shallow: unknown-ref refusal carries the shallow hint"; else no "$v on shallow: $( printf '%s' "$E" | head -c 300 )"; fi
    E2="$( run "$FULL" "${v%HEAD~1}nosuchref" )"
    if { has "$E2" "unknown" && ! has "$E2" "shallow"; }; then ok "${v%=*}=nosuchref on the full clone: no shallow hint"; else no "${v%=*} on full: $( printf '%s' "$E2" | head -c 300 )"; fi
done

# ── 6. the MCP twins: owners (XML) and cochange (JSON) carry the same qualification ──
mcp_text(){ printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}'                           "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"$1\",\"arguments\":$2}}" | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c '
import sys,json
try:    d=json.loads(sys.stdin.read() or "{}")
except Exception as e: sys.stdout.write("__ERROR__ unparseable: %s"%e);  raise SystemExit
if "error" in d: sys.stdout.write("__ERROR__ %s"%d["error"].get("message",""));  raise SystemExit
sys.stdout.write(d.get("result",{}).get("content",[{}])[0].get("text",""))'; }
MO="$( mcp_text owners "{\"path\":\"$SH\"}" )"
if has "$( root_of "$MO" )" 'shallow="1"'; then ok "MCP owners on shallow: the root carries shallow=\"1\""; else no "MCP owners on shallow: $( root_of "$MO" )"; fi
MOF="$( mcp_text owners "{\"path\":\"$FULL\"}" )"
if { has "$MOF" 'shallow="1"' || has "$MOF" '<!-- shallow='; }; then no "MCP owners on full carries shallow=\"1\" or its clause"; else ok "MCP owners on full: no shallow"; fi
MC="$( mcp_text cochange "{\"path\":\"$SH\",\"file\":\"a.c\"}" )"
if has "$MC" '"shallow":true'; then ok "MCP cochange on shallow: \"shallow\":true"; else no "MCP cochange on shallow: $( printf '%s' "$MC" | head -c 300 )"; fi
MCF="$( mcp_text cochange "{\"path\":\"$FULL\",\"file\":\"a.c\"}" )"
if has "$MCF" '"shallow"'; then no "MCP cochange on full carries a shallow key"; else ok "MCP cochange on full: no shallow key"; fi

# ── 7. the COMPOSED surfaces (0.6.7 tail): --pr-context, --situ and MCP situational_awareness embed owners / co-change /
#      window rows mined from the same history, so they carry the same qualification. One uncommitted edit gives each clone a
#      changed file to review; the sections below run on the dirtied clones, so they sit after every clean-tree arm. ──
for d in "$FULL" "$SH"; do printf 'int edited( int z ) { return helper( z ) + 2; }\n' >> "$d/a.c"; done
for leg in full compact; do
    P="$( run "$SH" --pr-context --legend=$leg )"; PR="$( root_of "$P" )"
    if has "$PR" 'shallow="1"'; then ok "pr-context ($leg) on shallow: the root carries shallow=\"1\""; else no "pr-context ($leg) on shallow: no shallow=\"1\" on the root: $( printf '%s' "$PR" | head -c 300 )"; fi
    if legend_defines_shallow "$P"; then ok "pr-context ($leg): the legend defines shallow="; else no "pr-context ($leg): shallow= emitted and not defined in the legend"; fi
    if printf '%s' "$P" | xmllint --noout - 2>/dev/null; then ok "pr-context ($leg) on shallow: well-formed"; else no "pr-context ($leg) on shallow: not well-formed XML"; fi
    if has "$P" '<owners authors="1" bf="1"'; then ok "pr-context ($leg) on shallow: the embedded owners row still reads from the fetched commit (qualified, not refused)"; else no "pr-context ($leg) on shallow: the embedded owners row changed shape: $( printf '%s' "$P" | grep -o '<owners[^>]*>' | head -1 )"; fi
done
PF="$( run "$FULL" --pr-context --legend=full )"
if { has "$PF" 'shallow="1"' || has "$PF" '<!-- shallow='; }; then no "pr-context on the full clone carries shallow=\"1\" or its clause"; else ok "pr-context on the full clone: no shallow attribute or clause"; fi
# the multi-root form writes one <pr-context root=…> section per root; each section probes ITS root, so the full root's section
# stays byte-identical to the full+full control's while the shallow root's section is qualified.
PM="$( "$BIN" "$FULL" "$SH" --pr-context --legend=full --no-cache 2>/dev/null )"
PM_SH="$( printf '%s' "$PM" | grep -o '<pr-context[^>]*root="[^"]*shallow"[^>]*>' | head -1 )"
PM_FU="$( printf '%s' "$PM" | grep -o '<pr-context[^>]*root="[^"]*full"[^>]*>' | head -1 )"
if { has "$PM_SH" 'shallow="1"' && ! has "$PM_FU" 'shallow="1"'; }; then ok "pr-context full+shallow workspace: only the shallow root's section carries shallow=\"1\""; else no "pr-context full+shallow workspace: shallow-root section [$PM_SH] full-root section [$PM_FU]"; fi
if legend_defines_shallow "$PM"; then ok "pr-context full+shallow workspace: the legend defines shallow="; else no "pr-context full+shallow workspace: shallow= undefined"; fi
SI="$( run "$SH" --situ )"; SI3="$( printf '%s' "$SI" | grep -F '[3] co-change' )"
if { has "$SI3" 'window="' && has "$SI3" 'shallow="1"'; }; then ok "situ on shallow: the [3] co-change window line carries shallow=\"1\""; else no "situ on shallow: [3] line: $SI3"; fi
SIF="$( run "$FULL" --situ )"
if { has "$SIF" '[3] co-change' && ! has "$SIF" 'shallow="1"'; }; then ok "situ on the full clone: no shallow=\"1\""; else no "situ on full: $( printf '%s' "$SIF" | grep -F '[3]' )"; fi
MS="$( mcp_text situational_awareness "{\"path\":\"$SH\"}" )"
if { has "$MS" '"cochange_window":' && has "$MS" '"shallow":true'; }; then ok "MCP situational_awareness on shallow: \"shallow\":true beside cochange_window"; else no "MCP situational_awareness on shallow: $( printf '%s' "$MS" | grep -o '"cochange_window[^}]*' | head -c 300 )"; fi
MSF="$( mcp_text situational_awareness "{\"path\":\"$FULL\"}" )"
if { has "$MSF" '"cochange_window":' && ! has "$MSF" '"shallow"'; }; then ok "MCP situational_awareness on full: no shallow key"; else no "MCP situational_awareness on full: $( printf '%s' "$MSF" | head -c 300 )"; fi

# ── 8. UNFETCHED-REV refusals (0.6.7 tail): a rev spelled past the fetched history refuses with the SAME probe-backed hint the
#      pr-context/merge-scout refusals carry (one helper, gitstamp::shallowRefHint). The full clone's refusal for a rev that does
#      not exist keeps its bytes: a typo there reads exactly as before, and the generic cause list is not the probe's sentence. ──
HINT="this is a shallow clone"
for v in --quality-delta=HEAD~1 --dmm=HEAD~1 "--hotspots --since=HEAD~1" "--cochange --since=HEAD~1" "--rank-by=churn --since=HEAD~1" "--slice=twice:x --since=HEAD~1"; do
    # shellcheck disable=SC2086
    E="$( run "$SH" $v )"
    if { has "$E" "$HINT" && has "$E" "git fetch --deepen"; }; then ok "$v on shallow: the refusal carries the probe-backed shallow hint"; else no "$v on shallow: $( printf '%s' "$E" | head -c 300 )"; fi
done
for v in --quality-delta=nosuchref --dmm=nosuchref "--hotspots --since=nosuchref" "--slice=twice:x --since=nosuchref" --quality-delta=HEAD~9; do
    # shellcheck disable=SC2086
    E="$( run "$FULL" $v )"; RC=$?
    if { [ "$RC" -ne 0 ] && ! has "$E" "$HINT"; }; then ok "$v on the full clone: refuses (rc=$RC) with no probed shallow hint"; else no "$v on full (rc=$RC): $( printf '%s' "$E" | head -c 300 )"; fi
done
# the boundary sentence (section 1) is the NoParent path, not the BadRev one: it must not gain the "may lie beyond" hint
QB="$( run "$SH" --quality-delta=HEAD )"
if { has "$QB" "shallow boundary" && ! has "$QB" "$HINT"; }; then ok "quality-delta=HEAD on shallow: the boundary sentence stays its own (no unfetched-rev hint)"; else no "quality-delta=HEAD on shallow: $( printf '%s' "$QB" | head -c 300 )"; fi
# multi-root: a value no root resolves refuses once; a shallow root among them names the likeliest cause, two full roots do not
E="$( "$BIN" "$FULL" "$SH" --hotspots --since=HEAD~9 --no-cache 2>&1 >/dev/null )"
if { has "$E" "$HINT" && has "$E" "git fetch --deepen"; }; then ok "hotspots --since=HEAD~9 full+shallow workspace: the refusal carries the shallow hint"; else no "since full+shallow workspace: $( printf '%s' "$E" | head -c 300 )"; fi
E="$( "$BIN" "$FULL" "$FULL2" --hotspots --since=HEAD~9 --no-cache 2>&1 >/dev/null )"
if { has "$E" "neither a git revision" && ! has "$E" "shallow"; }; then ok "hotspots --since=HEAD~9 full+full workspace: still the plain refusal, no shallow claim"; else no "since full+full workspace: $( printf '%s' "$E" | head -c 300 )"; fi

# ── 9. EMPTY since-windows (0.6.7 tail): --hotspots / --cochange with an active window that matched no commits return an empty
#      root BEFORE the qualified emitter; that root is a claim about the fetched history too, so it carries shallow= as well. ──
for v in --hotspots --cochange; do
    for leg in full compact; do
        O="$( run "$SH" "$v" --since=HEAD --legend=$leg )"; RC=$?; R="$( root_of "$O" )"
        if { [ "$RC" -eq 0 ] && has "$R" 'commits="0"' && has "$R" 'shallow="1"'; }; then ok "$v --since=HEAD ($leg) on shallow: the empty-window root carries shallow=\"1\" (rc=0, still commits=0)"; else no "$v --since=HEAD ($leg) on shallow (rc=$RC): $R"; fi
        if legend_defines_shallow "$O"; then ok "$v --since=HEAD ($leg): the legend defines shallow="; else no "$v --since=HEAD ($leg): shallow= emitted and not defined in the legend"; fi
        if printf '%s' "$O" | xmllint --noout - 2>/dev/null; then ok "$v --since=HEAD ($leg): well-formed"; else no "$v --since=HEAD ($leg): not well-formed XML"; fi
    done
    F="$( run "$FULL" "$v" --since=HEAD --legend=full )"
    if { has "$F" 'commits="0"' && ! has "$F" 'shallow="1"' && ! has "$F" '<!-- shallow='; }; then ok "$v --since=HEAD on the full clone: empty window, no shallow attribute or clause"; else no "$v --since=HEAD on full: $( root_of "$F" )"; fi
done

[ "$fail" -eq 0 ] && echo "ALL CHECKS PASSED" || echo "$fail CHECK(S) FAILED"
exit $fail
