#!/usr/bin/env bash
# tierankservedcheck.sh — TIERANK-SERVED: the TAIL-SYM-TERMS tie-break rank is SERVED, not recomputed, on a run whose
# graph came from the warm snapshot — and the answer is the same bytes either way.
#
# WHY. src/forpage.h tailTermTieRank orders the extra names a --for tail row prints (tsym=) by the graph's plain
# uniform-teleport PageRank. That value is a function of the GRAPH ALONE — the teleport is uniform, so nothing about the
# task enters it — and it was computed from scratch on every --for answer, warm runs included: 399.7 ms per answer on
# llvm-project, 15.4% of the verb (CLI, warm, 3 reps, 2026-11-27). The warm snapshot already persists exactly that rank
# beside the graph it ranks (src/warmsnap_graph.h storedDefaultRank, written by readGraph on a served run and by
# buildGraphRecorded on the run that records), so a served run can read it.
#
# That is only correct if the persisted rank IS the rank this site would compute. Measured before the change, with an
# in-process probe that compared the two float arrays element by element on a served run (graph=loaded): BIT-IDENTICAL
# on six corpora — this repo (n=47,742), jq (2,461), django (60,574), envoy (171,803), kubernetes (293,542) and
# llvm-project (1,399,402) — 0 differing elements, equal iteration counts, equal convergence flags. The rank rides the
# snapshot as its raw IEEE bit pattern (warmsnap.h's RawRow concept: "a float row is its computed bit pattern") and is
# read back by one memcpy, so the file is lossless; the power iteration is deterministic by the §2 contract. This gate
# is the standing guard on the ANSWER, which is what a reader of the tool actually holds.
#
# ARMS
#   R   every run this gate reads exited 0 and wrote an answer, stated on SUCCESS with its byte count. A precondition
#       that only speaks up on failure is indistinguishable from one that stopped running.
#   P1  coverage: the cold answer carries tsym="restorer_scheduling,restorer_cache" — a tail row whose extra names are
#       in PAGERANK order (c050..c059 call restorer_cache, which is what lifts it over config_restorer; the same
#       fixture and the same reason as test/tailsymtermscheck.sh arm a). Matched as the VALUE, never the key.
#   P1n coverage, the other way: the same run with RIPWIRE_NO_TAIL_SYM_TERMS=1 carries 0 occurrences of tsym=" where
#       the default answer carries more than 0 — so P1's match can go negative, and a zero means "none printed" rather
#       than "the pattern cannot match". Both counts are printed either way, pass or fail.
#   P2  warm premise, stated POSITIVELY: the two warm runs report graph=loaded. Never "nothing reparsed" — a recording
#       run reparses nothing either.
#   S1  the fix: the warm runs disclose tie_rank=served n=<count>. RED on a binary without the change, which emits no
#       tie_rank= at all.
#   S2  the RECORDING run serves too, and that was not the expectation this gate was written with — the run that
#       records already ran the power iteration once, in warmsnap_graph.h buildGraphRecorded, to put the rank in the
#       snapshot, and it stores it in the slot before any verb runs. So a cold --for answer used to run the iteration
#       TWICE over one graph. Measured, not reasoned: the first draft of this gate asserted tie_rank=computed here and
#       went red on the fix.
#   S3  the fallback is live, not dead: --no-cache arms no snapshot session at all, so the slot is empty and the site
#       computes. Without this arm "served" could be the only reachable answer and the fallback never exercised.
#   D1  warm == cold: the served answer is the recording run's bytes, and the same exit status.
#   D2  warm == warm: two served answers are the same bytes.
#   D3  served == computed: the --no-cache answer, whose tie-break rank came from a fresh power iteration in this same
#       binary, is byte-identical to the served one. This is the arm that compares the two ranks through the answer.
#   D4  the tsym= value is the same in the warm answer as in the cold one, stated as a value (D1 covers it; this names
#       the outcome under test, so a reader sees WHAT is pinned and not only that two files matched).
#
#   test/tierankservedcheck.sh [BIN]     (RIPWIRE_BIN also honoured)
#
# Exits non-zero on any failure. Prints ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
echo "tierankservedcheck: BIN=$BIN  $( "$BIN" --version 2>&1 | head -1 )"

TMP="$( mktemp -d )" && [ -n "$TMP" ] && [ -d "$TMP" ] || { echo "tierankservedcheck: mktemp -d failed"; exit 2; }
trap 'rm -rf "$TMP"' EXIT
fail=0
# A PASS line that could not be WRITTEN must not read as a pass: with no accumulator here, a failed printf loses the
# line and the gate still exits 0 (test/gateexitcheck.sh arm G1). Same shape as every other rule in this file — a
# success path that is silent passes in states nobody considered — and the spelling is snapdeterminismcheck.sh's.
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

# FMT2 (src/forrowlines.h): the default answer serves its tail rows as text lines in one CDATA. This gate reads tsym= as
# an attribute, the same reason test/tailsymtermscheck.sh does, so the line form is off here.
export RIPWIRE_NO_ROWLINES=1
Q="widget frobnicate restoration scheduler"

# ── the fixture: test/tailsymtermscheck.sh's fx tree, the part that makes a PageRank-ordered tsym= ────────────────────
F="$TMP/fx"; mkdir -p "$F/docs" "$F/scheduler"
i=0
while [ $i -lt 60 ]; do
    n=$( printf '%03d' $i )
    if [ $i -ge 50 ]; then   # the tie-break: ten callers lift restorer_cache's PageRank over the other one-word names
        printf 'from scheduler.zz_store import restorer_cache\n\n\ndef widget_frobnicate_%s():\n    """widget frobnicate helper"""\n    return restorer_cache()\n' "$n" > "$F/c$n.py"
    else
        printf 'def widget_frobnicate_%s():\n    """widget frobnicate helper"""\n    return 1\n' "$n" > "$F/c$n.py"
    fi
    i=$(( i + 1 ))
done
cat > "$F/scheduler/zz_store.py" <<'PYEOF'
def alpha_one():
    """widget"""
    return 1


def alpha_two():
    """widget"""
    return 2


def alpha_three():
    """widget"""
    return 3


def config_restorer():
    return 0


def restorer_cache():
    return 0


def restorer_scheduling():
    return 0
PYEOF
printf 'def probe_schedulers():\n    return 0\n' >> "$F/c000.py"
printf 'def alpha_probe():\n    """widget"""\n    return 1\n\n\ndef probe_schedulers():\n    return 0\n' > "$F/zz_restorer_probe.py"
printf '# Restorer scheduling, widget frobnicate notes\n\nThe widget restoration scheduler notes.\n' > "$F/docs/restoration.md"

# The racy rule (src/warmsnap.h kRacySlackNs): nothing is recorded while any file or directory is younger than two
# seconds before the crawl began, by mtime OR ctime. The fixture was written moments ago, so wait it out — without this
# the cold run records nothing, every later run is cold too, and S and P2 fail for the wrong reason.
sleep 3

# run TAG HOMEDIR [VAR=value...] — one run of `"$BIN" . [FLAGS] --for=$Q`, its stdout at $TMP/TAG.out and stderr at
# TAG.err. The exit status is TESTED IN THIS SCOPE, immediately, and arm R is said on SUCCESS as well as on failure: a
# precondition that only speaks up when it fails is indistinguishable from one that stopped running. (It is also why the
# status is not parked in a file and read back three screens later — nothing downstream can then tell a 0 from a
# never-written file.) rc is kept in rc_TAG for D1, which compares two runs' statuses.
# RIPWIRE_SNAPSHOT_STATS is one of src/warmsnap.h's declared observers, so setting it does NOT move the snapshot key.
# FLAGS come from $RUNFLAGS, so only S3's --no-cache arm sets it.
H="$TMP/home"; mkdir -p "$H/tmp" "$H/xdg"
RUNFLAGS=""
run()
{
    local tag="$1" home="$2"; shift 2
    mkdir -p "$home/tmp" "$home/xdg"
    ( cd "$F" && env "$@" HOME="$home" TMPDIR="$home/tmp/" XDG_CACHE_HOME="$home/xdg" \
        "$BIN" . ${RUNFLAGS:+$RUNFLAGS} "--for=$Q" >"$TMP/$tag.out" 2>"$TMP/$tag.err" </dev/null )
    local rc=$?
    local bytes; bytes="$( wc -c <"$TMP/$tag.out" | tr -d ' ' )"
    eval "rc_$tag=\$rc"
    if [ "$rc" = 0 ] && [ "${bytes:-0}" -gt 0 ]; then ok "R   the $tag run exited 0 and wrote ${bytes} B"
    else no "R   the $tag run exited $rc and wrote ${bytes:-0} B ($( tail -1 "$TMP/$tag.err" ))"; fi
}
run cold  "$H" RIPWIRE_SNAPSHOT_STATS=1    # opens with no blob: records the tree, the model and the graph
run warm1 "$H" RIPWIRE_SNAPSHOT_STATS=1    # serves them
run warm2 "$H" RIPWIRE_SNAPSHOT_STATS=1
# P1n's ablation and S3's no-snapshot run: their own cache path, so neither disturbs the served pair above
run abl "$TMP/homeab" RIPWIRE_NO_TAIL_SYM_TERMS=1
RUNFLAGS="--no-cache"
run nosnap "$TMP/homenc" RIPWIRE_SNAPSHOT_STATS=1
RUNFLAGS=""

tsym(){ grep -o 'tsym="[^"]*"' "$TMP/$1.out" | head -1; }
tsymn(){ grep -o 'tsym="' "$TMP/$1.out" | wc -l | tr -d ' '; }   # occurrences, not lines: the answer is one minified line
graphstate(){ grep -o 'graph=[a-z]*' "$TMP/$1.err" | head -1; }
tierank(){ grep -oE 'tie_rank=[a-z]+ n="?[0-9]+' "$TMP/$1.err" | head -1; }

# ── P1 / P1n: the coverage, both ways ────────────────────────────────────────────────────────────────────────────────
want='tsym="restorer_scheduling,restorer_cache"'
if [ "$( tsym cold )" = "$want" ]; then ok "P1  the cold answer carries $want (the PageRank-ordered pair)"
else no "P1  VACUOUS: the cold answer does not carry $want (got '$( tsym cold )') — the fixture no longer prints a PageRank-ordered tsym="; fi
# Both branches carry the two counts, so a PASS here states what it compared rather than only that a grep found nothing.
if [ "$( tsymn abl )" -eq 0 ] && [ "$( tsymn cold )" -gt 0 ]; then
    ok "P1n the ablated answer carries 0 tsym= where the default answer carries $( tsymn cold ), so P1 matches a value and not a key"
else no "P1n tsym= occurrences: ablated $( tsymn abl ) (want 0), default $( tsymn cold ) (want > 0) — P1's match cannot go negative"; fi

# ── P2: the warm premise, asserted as the PRESENCE of the thing that must have loaded ────────────────────────────────
[ "$( graphstate cold )" = "graph=built" ] && ok "P2  the cold run built the graph ($( graphstate cold ))" \
    || no "P2  the cold run did not build the graph (got '$( graphstate cold )'): it was not the recording run"
for t in warm1 warm2; do
    [ "$( graphstate $t )" = "graph=loaded" ] && ok "P2  the $t run LOADED the graph from the snapshot ($( graphstate $t ))" \
        || no "P2  the $t run did not load the graph (got '$( graphstate $t )'): nothing served, so S proves nothing"
done

# ── S: the fix — served wherever a snapshot session held the rank, computed where none did ───────────────────────────
served_arm()
{
    local arm="$1" t="$2" why="$3"
    case "$( tierank $t )" in
        tie_rank=served*) ok "$arm the $t run SERVED the tie-break rank ($( tierank $t )) — $why";;
        '')               no "$arm the $t run disclosed no tie_rank= at all — this binary does not have the change";;
        *)                no "$arm the $t run disclosed '$( tierank $t )', expected tie_rank=served";;
    esac
}
served_arm "S1 " warm1 "the snapshot served the graph, so it served the rank beside it"
served_arm "S1 " warm2 "the snapshot served the graph, so it served the rank beside it"
served_arm "S2 " cold  "buildGraphRecorded ran the iteration once FOR the snapshot and left it in the slot: a cold --for answer used to run it twice"
case "$( tierank nosnap )" in
    tie_rank=computed*) ok "S3  --no-cache arms no snapshot, so the site computed ($( tierank nosnap )) — the fallback is reachable";;
    '')                 no "S3  the --no-cache run disclosed no tie_rank= at all — this binary does not have the change";;
    *)                  no "S3  the --no-cache run disclosed '$( tierank nosnap )', expected tie_rank=computed: nothing exercises the fallback";;
esac

# ── D: the answer does not move ──────────────────────────────────────────────────────────────────────────────────────
if cmp -s "$TMP/cold.out" "$TMP/warm1.out"; then ok "D1  warm == cold — the served answer is the recording run's bytes ($( wc -c <"$TMP/cold.out" | tr -d ' ' ) B)"
else no "D1  warm != cold ($( cmp "$TMP/cold.out" "$TMP/warm1.out" 2>&1 | head -1 | sed 's/.* differ: //' ))"; fi
[ "${rc_cold}" = "${rc_warm1}" ] && ok "D1  warm and cold exited alike (rc=${rc_cold})" \
    || no "D1  warm exited ${rc_warm1}, cold ${rc_cold}"
if cmp -s "$TMP/warm1.out" "$TMP/warm2.out"; then ok "D2  warm == warm — two served answers are the same bytes"
else no "D2  two served answers differ ($( cmp "$TMP/warm1.out" "$TMP/warm2.out" 2>&1 | head -1 | sed 's/.* differ: //' ))"; fi
if cmp -s "$TMP/nosnap.out" "$TMP/warm1.out"; then ok "D3  served == computed — the --no-cache answer, whose rank came from a fresh power iteration, is the served answer's bytes"
else no "D3  served != computed ($( cmp "$TMP/nosnap.out" "$TMP/warm1.out" 2>&1 | head -1 | sed 's/.* differ: //' )): the persisted rank and a fresh one order the tie-break differently"; fi
if [ -n "$( tsym warm1 )" ] && [ "$( tsym warm1 )" = "$( tsym cold )" ] && [ "$( tsym warm1 )" = "$( tsym nosnap )" ]; then ok "D4  the served answer's $( tsym warm1 ) is the recording run's and the computed run's"
else no "D4  tsym= differs: served '$( tsym warm1 )', recording '$( tsym cold )', computed '$( tsym nosnap )'"; fi

if [ "$fail" = 0 ]; then echo "ALL PASS"; exit 0; fi
echo "FAILURES above"; exit 1
