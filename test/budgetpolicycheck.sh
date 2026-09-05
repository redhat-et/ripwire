#!/usr/bin/env bash
# budgetpolicycheck.sh — capture-audit 2026-09-04 H9: the BUDGET FAMILY's disclosure contract.
#
# THE FINDING. `--recall --token-budget=500` printed `shown="0" … max_tokens="8000"` on stdout and put the
# only statement of WHY (`withheld_est_tokens=6442 > budget=500`) on stderr; `--recall --max-tokens=1500`
# APPLIED a 1500-token ceiling and then emitted NO `max_tokens=` attribute at all — the attribute appeared
# only when the effective ceiling happened to equal the 8000 default. MCP `memory_recall budget_tokens=1500`
# maps to that same `--max-tokens` flag, so it dropped the attribute in exactly the same place, and the
# tools/list description promising "the header discloses max_tokens=" was false for every non-default call.
# `--connect` and `--from-trace` shape to `--max-tokens` too (cli.h's kShapingVerbs rows say so, and the
# payload really does shrink) and disclosed no ceiling either; `--for --token-budget=N` re-shapes its whole
# bundle (`bundle="compact" reason="budget"`) without ever naming N.
#
# WHY A FAMILY GATE AND NOT A RECALL ASSERT. Every instance above is the same defect — a verb that APPLIED a
# ceiling and did not NAME it — and each one shipped because the verb that had the bug was not the verb the
# previous round measured. So this gate never names a verb: it reads the binary's OWN two honoring lists
# (the kMaxTokensGuard / kTokenBudgetGuard refusal sentences, which cli.h composes from the same table
# test/shapingflagcheck.sh re-derives from the read sites) and holds every member of them to the contract.
# A verb that starts honoring a budget flag joins this gate the moment its refusal prose names it.
#
# THE CONTRACT, in the three parts H9 states:
#   (A) the honoring PROSE names exactly the verbs whose kShapingVerbs row claims to honor the flag —
#       a verb that reads the budget but is missing from the sentence is a ceiling an agent cannot find.
#   (B) the header attribute naming the ceiling EQUALS the ceiling applied: run each honoring verb with an
#       explicit budget and the number must appear in-band, as `max_tokens=` / `budget_tokens=` / `budget=`.
#   (C) every `withheld`/budget fact is in the PAYLOAD, never only on stderr (an MCP client has no stderr),
#       and the CLI and MCP forms of one verb apply the SAME policy for the same argument — asserted where
#       the two surfaces exist, by comparing the two header lines directly.
#
# Usage:
#   bash test/budgetpolicycheck.sh                                 # uses build/ripwire
#   RIPWIRE_BIN=build_base/ripwire bash test/budgetpolicycheck.sh   # the RED run (pre-fix binary)
# Exits non-zero on any failure.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
cd "$ROOT"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "budgetpolicycheck: BIN=$BIN  CORPUS=$ROOT"

# ── the two honoring lists, READ OFF THE BINARY ────────────────────────────────────────────────────────
# Both guards fire on any honorsPaging verb, and each prints the set the flag IS honored by. `--hotspots` is
# only the trigger: nothing about it appears in the sentence we parse.
"$BIN" . --hotspots --max-tokens=10   >/dev/null 2>"$TMP/mt.msg"
"$BIN" . --hotspots --token-budget=10 >/dev/null 2>"$TMP/tb.msg"

# honoring_list FILE — the flag names between "is honored by" and " — none of them", one per line.
honoring_list() {
    python3 - "$1" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
m = re.search(r"is honored by (.*?) — none of them", t, re.S)
if not m:
    print("__NOSENTENCE__"); raise SystemExit
seg = m.group(1)
# the sentence is prose: "the default map (the CI gate), --for, --pack-task, … and --run-trace"
for f in sorted(set(re.findall(r"--[a-z-]+", seg))):
    print(f)
if "default map" in seg:
    print("__MAP__")
PY
}
MT_LIST="$( honoring_list "$TMP/mt.msg" )"
TB_LIST="$( honoring_list "$TMP/tb.msg" )"
case "$MT_LIST$TB_LIST" in
    *__NOSENTENCE__*) no "could not read a honoring sentence off the binary — the guard prose moved; fix this gate's parser"; echo; exit 1 ;;
esac

# ── (A) the prose agrees with the TABLE it is supposed to describe ─────────────────────────────────────
# cli.h's kShapingVerbs is the read-site-derived truth (shapingflagcheck.sh re-derives it from source every
# run). A row whose honorsTokenBudget/honorsMaxTokens column is true and whose name the sentence omits is a
# budget a caller is told does not exist. `--for` is carved out of the --max-tokens column by hand in cli.h
# (it honors it only under --detail=N) and the sentence says so, so it is compared as a member.
echo
echo "=== (A) the honoring prose names exactly the table's honoring rows ==="
table_rows() {   # table_rows COLUMN_INDEX  (0=name 1=flagPtr 2=valuePtr 3=honorsTopK 4=honorsMaxTokens 5=honorsTokenBudget)
    python3 - "$ROOT/src/cli.h" "$1" <<'PY'
import re, sys
src, col = open(sys.argv[1]).read(), int(sys.argv[2])
m = re.search(r"inline constexpr ShapingVerb kShapingVerbs\[\]\s*=\s*\{(.*?)\n\};", src, re.S)
if not m:
    print("__NOTABLE__"); raise SystemExit
for line in m.group(1).splitlines():
    row = line.split("//")[0].strip()
    if not row.startswith("{"):
        continue
    fields = [f.strip() for f in row.strip("{},").split(",")]
    name = fields[0].strip('"')
    if len(fields) > col and fields[col] == "true":
        print(name)
PY
}
# The two lists ride FILES, not a packed string: honoring_list emits one flag per line and a `read`
# splitting on | would silently keep only the first line — a comparison against a one-element set that
# passes for the wrong reason.
printf '%s\n' "$MT_LIST" >"$TMP/mt.list"
printf '%s\n' "$TB_LIST" >"$TMP/tb.list"
while IFS='|' read -r col flag listfile; do
    [ -z "$col" ] && continue
    want="$( table_rows "$col" | sort -u )"
    case "$want" in *__NOTABLE__*) no "(A) $flag: kShapingVerbs is unreadable — fix this gate's parser"; continue ;; esac
    have="$( grep -v '^__MAP__$' "$TMP/$listfile" | grep . | sort -u )"
    missing="$( comm -23 <( printf '%s\n' "$want" ) <( printf '%s\n' "$have" ) | tr '\n' ' ' )"
    extra="$(   comm -13 <( printf '%s\n' "$want" ) <( printf '%s\n' "$have" ) | tr '\n' ' ' )"
    # An EXTRA is not a defect by itself: the sentence legitimately names shapes the table cannot express
    # (`--for --detail=N`) and riders of the default map's serialize path. A MISSING one always is.
    if [ -n "$missing" ]; then
        no "(A) $flag: honored by [$missing] per kShapingVerbs, but the refusal sentence never names them"
    else
        ok "(A) $flag: every honoring row is named in the refusal sentence (sentence also names: ${extra:-none})"
    fi
done <<EOF
4|--max-tokens|mt.list
5|--token-budget|tb.list
EOF

# ── (B) the ceiling attribute equals the ceiling applied ───────────────────────────────────────────────
# One probe per honoring verb, at a budget small enough to BIND on this corpus. The assertion is on the
# NUMBER, in-band: a verb may spell its ceiling max_tokens= (the shaping vocabulary), budget_tokens= (the
# bundle vocabulary) or budget= (the gate vocabulary) — what it may not do is apply one and name none.
echo
echo "=== (B) every honored budget is NAMED in the payload, with the value that was applied ==="
N=1500
probe_args() {   # the argv that selects VERB, budget flag appended by the caller
    case "$1" in
        __MAP__)        printf '%s' "" ;;
        --recall)       printf '%s' '--recall=quality delta gating exit codes' ;;
        --connect)      printf '%s' '--connect=main,parseArgs,escapeXml' ;;
        --from-trace)   printf '%s' "--from-trace=$TMP/trace.txt" ;;
        # HEAD~10, not HEAD~1: --pr-context's EMPTY-diff form carries neither budget nor est_tokens
        # (there is nothing to shape), so a probe against a base with no changed files measures nothing.
        --pr-context)   printf '%s' '--pr-context=HEAD~10' ;;
        --for)          printf '%s' '--for=pagerank power iteration' ;;
        # --html renders the map into a FILE and --run-trace execs a command: neither emits an
        # attribute-bearing document on stdout, so neither can carry an in-band ceiling attribute. Named
        # here rather than silently absent — a skip a reader cannot see is a hole in a family gate.
        --html)         printf '%s' '__SKIP__' ;;
        --pack-task)    printf '%s' '--pack-task=pagerank power iteration' ;;
        --handoff)      printf '%s' '--handoff' ;;
        --run-trace)    printf '%s' '__SKIP__' ;;   # execs a command; not a payload-shape probe
        *)              printf '%s' '__SKIP__' ;;
    esac
}
printf 'src/graph.h:120:5: error: no member named zz\nsrc/serialize.h:200: in escapeXml\n' >"$TMP/trace.txt"

check_named() {   # check_named FLAG VERB VALUE
    local flag="$1" verb="$2" want="$3" args
    args="$( probe_args "$verb" )"
    [ "$args" = "__SKIP__" ] && return 0
    if [ -z "$args" ]; then
        "$BIN" . "$flag=$want" >"$TMP/out" 2>"$TMP/err"
    else
        "$BIN" . "$args" "$flag=$want" >"$TMP/out" 2>"$TMP/err"
    fi
    # a probe that refused or emitted nothing measured nothing — say so rather than passing vacuously
    if [ ! -s "$TMP/out" ]; then
        # --token-budget's GATE personality legitimately streams only the refusal header (exit 3); that
        # case is covered by (C), which asserts the withheld disclosure is on stdout.
        no "(B) $flag $verb: the probe produced no stdout (exit $?) — cannot judge the disclosure"
        return 0
    fi
    if grep -qE "(max_tokens|budget_tokens|budget)=\"?$want\"?( |>|$)" "$TMP/out"; then
        ok "(B) $flag $verb: names the ceiling it applied ($want)"
    else
        no "(B) $flag $verb: applied a $want-token ceiling and named no ceiling in the payload — $( grep -oE '<[a-z-]+ [^>]{0,200}' "$TMP/out" | head -1 )"
    fi
}
for v in $MT_LIST; do
    # --for honors --max-tokens ONLY under --detail=N (cli.h carves it out by hand and the sentence says
    # "--for --detail=N"): probe the shape the sentence actually names, not the bare one it excludes.
    if [ "$v" = "--for" ]; then
        "$BIN" . '--for=pagerank power iteration' --detail=1 --max-tokens=$N >"$TMP/out" 2>/dev/null
        grep -qE "(max_tokens|budget_tokens|budget)=\"?$N\"?( |>|$)" "$TMP/out" \
            && ok "(B) --max-tokens --for --detail=1: names the ceiling it applied ($N)" \
            || no "(B) --max-tokens --for --detail=1: applied a $N-token ceiling and named no ceiling in the payload"
        continue
    fi
    check_named --max-tokens "$v" "$N"
done
for v in $TB_LIST; do
    # the GATE personality (map, recall) streams no artifact at a binding budget — probe it high enough to
    # SHAPE rather than gate where the verb gates, and let (C) own the gate case.
    case "$v" in --recall|__MAP__) continue ;; esac
    check_named --token-budget "$v" "$N"
done

# ── (C) the withheld disclosure is in the PAYLOAD, and CLI ≡ MCP for the same argument ─────────────────
echo
echo "=== (C) withheld facts in-band; CLI and MCP apply one policy ==="
"$BIN" . --recall="quality delta gating exit codes" --token-budget=100 >"$TMP/gate.out" 2>"$TMP/gate.err"
if grep -q 'withheld' "$TMP/gate.err" && ! grep -q 'withheld' "$TMP/gate.out"; then
    no "(C) --recall --token-budget: the withheld disclosure is on stderr only — an MCP client never sees it"
else
    ok "(C) --recall --token-budget: the withheld disclosure rides in the payload"
fi
# the gate personality must still not stream the artifact it rejected (recallbudgetcheck's §2, restated
# here only as the guard against "fix (C) by printing everything").
if [ "$( wc -c <"$TMP/gate.out" )" -gt 4000 ]; then
    no "(C) --recall --token-budget=100 streamed $( wc -c <"$TMP/gate.out" ) bytes — the gate must reject, not emit"
else
    ok "(C) --recall --token-budget=100 streams only the refusal header"
fi

mcp_text() {   # mcp_text NAME ARGSJSON
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"$1\",\"arguments\":$2}}" \
        | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
print("__ERROR__:" + r["error"].get("message","") if "error" in r else r["result"]["content"][0]["text"])'
}
# memory_recall.budget_tokens maps to --max-tokens (the tools/list description says so). Same argument, same
# policy ⇒ the two header lines must be identical, at the default AND at an explicit budget. This is the arm
# that catches "one surface discloses the ceiling and the other does not".
for b in default 1500; do
    if [ "$b" = default ]; then
        "$BIN" . --recall="quality delta" >"$TMP/c.out" 2>/dev/null
        mcp_text memory_recall "{\"path\":\"$ROOT\",\"task\":\"quality delta\"}" >"$TMP/m.out"
    else
        "$BIN" . --recall="quality delta" --max-tokens=$b >"$TMP/c.out" 2>/dev/null
        mcp_text memory_recall "{\"path\":\"$ROOT\",\"task\":\"quality delta\",\"budget_tokens\":$b}" >"$TMP/m.out"
    fi
    ch="$( head -1 "$TMP/c.out" )"; mh="$( head -1 "$TMP/m.out" )"
    if [ "$ch" = "$mh" ]; then
        ok "(C) memory_recall budget_tokens=$b: the MCP header is byte-identical to --recall --max-tokens=$b"
    else
        no "(C) memory_recall budget_tokens=$b: CLI [$ch] vs MCP [$mh]"
    fi
    case "$b" in
        1500) grep -q "max_tokens=$b" "$TMP/m.out" \
                  && ok "(C) memory_recall budget_tokens=$b discloses the ceiling it applied" \
                  || no "(C) memory_recall budget_tokens=$b applied a $b-token ceiling and disclosed none" ;;
    esac
done
# the description must keep naming the CLI flag the argument maps to (lens 4's ask) — otherwise "the same
# policy" is a claim the caller cannot check.
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
    | "$BIN" --mcp 2>/dev/null | tail -1 >"$TMP/list.json"
python3 - "$TMP/list.json" <<'PY' >"$TMP/desc.res" 2>&1
import json, sys
tools = json.load(open(sys.argv[1]))["result"]["tools"]
d = next( ( t["description"] for t in tools if t["name"] == "memory_recall" ), "" )
print("OK" if "--max-tokens" in d else "MISSING")
PY
[ "$( cat "$TMP/desc.res" )" = OK ] \
    && ok "(C) the memory_recall description names --max-tokens, the CLI flag budget_tokens maps to" \
    || no "(C) the memory_recall description does not name the CLI flag budget_tokens maps to"

# ── (D) a ceiling NAMED is a ceiling MEASURED AGAINST — the labelling half of (B) ──────────────────────
# verify-wave2 F2/F4/F5. Arm (B) proves the ceiling attribute EXISTS and carries the value that was applied.
# It says nothing about whether the document then honoured it, and `grep -n over_ceiling budgetpolicycheck.sh`
# was empty — so H9's fix made a pre-existing labelling bug LEGIBLE without catching it:
#   --from-trace --max-tokens=200  → est_tokens="1090" max_tokens="200"                (5.4x over, SILENT)
#   --from-trace --max-tokens=8000 → est_tokens="4471" max_tokens="8000" over_ceiling="1"  (UNDER, labelled)
#   --for --token-budget=1600      → budget_tokens="1600" est_tokens="1665"            (65 over, SILENT)
#
# THE CONTRACT, one sentence for the whole family: over_ceiling="1" exactly when the delivered document's
# est_tokens exceeds a ceiling NAMED ON THE SAME ROOT; absent means no ceiling was named, or the document is
# inside every ceiling that was. Both directions — a label with no overshoot behind it is as dishonest as an
# overshoot with no label, and the pre-fix binary produced one of each. The ceilings are read off the root
# itself (max_tokens=/budget_tokens=/budget=), never assumed from the argv, so the arm cannot drift from what
# the document actually claims.
echo
echo "=== (D) over_ceiling= is 1 exactly when est_tokens exceeds a ceiling named on the same root ==="
# root_nums FILE — prints "EST CEIL OVER" for the first root element: the priced tokens, the SMALLEST ceiling
# named on that root, and whether it says over_ceiling. Comments are stripped: a legend DEFINES these names
# and a definition is not a measurement. Prints nothing when the document names no ceiling at all.
root_nums() {
    python3 - "$1" <<'PY_EOF'
import re, sys
t = re.sub( r"<!--.*?-->", "", open( sys.argv[1], encoding = "utf-8", errors = "replace" ).read(), flags = re.S )
# XML dialects put every root attribute in the first start-tag; --recall's is a PROSE header line, and its
# markdown bodies are full of angle brackets, so the dialect is decided by the first byte of the document
# rather than by whichever "<" happens to appear first.
if t.lstrip().startswith( "<" ):
    m    = re.search( r"<[a-z-]+(?: [^>]*)?>", t )
    root = m.group( 0 ) if m else ""
else:
    root = t.split( "\n" )[ 0 ] if t else ""
def num( name ):
    g = re.search( r'\b%s="?(\d+)"?' % name, root )
    return int( g.group( 1 ) ) if g else None
est   = num( "est_tokens" )
ceils = [ c for c in ( num( "max_tokens" ), num( "budget_tokens" ), num( "budget" ) ) if c ]
over  = 1 if re.search( r'\bover_ceiling="?1"?', root ) else 0
if est is None or not ceils:
    raise SystemExit
print( "%d %d %d" % ( est, min( ceils ), over ) )
PY_EOF
}
label_probe() {   # label_probe LABEL ARGS...
    local label="$1"; shift
    "$BIN" . "$@" >"$TMP/lab.out" 2>/dev/null
    local nums; nums="$( root_nums "$TMP/lab.out" )"
    if [ -z "$nums" ]; then
        no "(D) $label: the root names no ceiling and no price — arm (B)'s subject vanished, fix this probe"
        return
    fi
    # shellcheck disable=SC2086
    set -- $nums
    local est="$1" ceil="$2" over="$3"
    if [ "$est" -gt "$ceil" ] && [ "$over" = 0 ]; then
        no "(D) $label: root prices $est tokens against a ceiling of $ceil and says NOTHING (over_ceiling absent)"
    elif [ "$est" -le "$ceil" ] && [ "$over" = 1 ]; then
        no "(D) $label: root says over_ceiling=\"1\" but $est tokens is inside the $ceil it names"
    else
        ok "(D) $label: est=$est ceiling=$ceil over_ceiling=$over — the label and the numbers agree"
    fi
}
# Every budgeted verb, through BOTH front doors where it has two, at a ceiling that BINDS and one that does
# not — the pair is the point: a verb that labels everything passes the first half and fails the second.
label_probe "--for --token-budget=600"                  '--for=pagerank power iteration' --token-budget=600
label_probe "--for --token-budget=1600"                 '--for=pagerank power iteration' --token-budget=1600
label_probe "--for --token-budget=8000"                 '--for=pagerank power iteration' --token-budget=8000
label_probe "--pack-task --token-budget=600"            '--pack-task=pagerank power iteration' --token-budget=600
label_probe "--pack-task --token-budget=8000"           '--pack-task=pagerank power iteration' --token-budget=8000
label_probe "--from-trace --token-budget=200"           "--from-trace=$TMP/trace.txt" --token-budget=200
label_probe "--from-trace --token-budget=8000"          "--from-trace=$TMP/trace.txt" --token-budget=8000
label_probe "--from-trace --max-tokens=200"             "--from-trace=$TMP/trace.txt" --max-tokens=200
label_probe "--from-trace --max-tokens=8000"            "--from-trace=$TMP/trace.txt" --max-tokens=8000
label_probe "--handoff --token-budget=100"              --handoff --token-budget=100
label_probe "--handoff --token-budget=100000"           --handoff --token-budget=100000
label_probe "--recall --max-tokens=300"                 '--recall=quality delta gating exit codes' --max-tokens=300
label_probe "--recall --max-tokens=8000"                '--recall=quality delta gating exit codes' --max-tokens=8000
label_probe "--connect --max-tokens=200"                '--connect=main,parseArgs,escapeXml' --max-tokens=200
label_probe "--connect --max-tokens=8000"               '--connect=main,parseArgs,escapeXml' --max-tokens=8000
# F4: --recall's SECOND front door. --token-budget GATES this verb (D10) rather than shaping it, and the
# header named only the 8000-token SHAPING default — the ceiling that decided the run appeared nowhere an
# attribute reader can find it, on either side of the decision:
#   --recall --token-budget=1500 → over_ceiling=1 max_tokens=8000 est_tokens=182   (+ stderr: budget=1500)
#   --recall --token-budget=6000 → max_tokens=8000                                 (still the default)
for tb in 1500 6000 60000; do
    "$BIN" . '--recall=quality delta gating exit codes' --token-budget=$tb >"$TMP/rtb.out" 2>/dev/null
    head -1 "$TMP/rtb.out" | grep -qE "budget_tokens=$tb( |\$)" \
        && ok "(D) --recall --token-budget=$tb: the header names the ceiling that decided the run" \
        || no "(D) --recall --token-budget=$tb: applied a $tb-token gate and named only [$( head -1 "$TMP/rtb.out" | grep -oE '(max_tokens|budget_tokens)=[0-9]+' | tr '\n' ' ' )]"
done
# and the GATE path obeys (D)'s own property: est_tokens there prices the refusal header, so a label carried
# over from the shaping stage would claim a 200-token document busted an 8000-token ceiling.
label_probe "--recall --token-budget=1500 (refused)"  '--recall=quality delta gating exit codes' --token-budget=1500
label_probe "--recall --token-budget=60000 (honoured)" '--recall=quality delta gating exit codes' --token-budget=60000
# and the withheld number the label refers to is an ATTRIBUTE, not only prose (arm (C) asserts it is in the
# payload at all; this asserts a parser can read it beside the budget it lost to)
"$BIN" . '--recall=quality delta gating exit codes' --token-budget=1500 >"$TMP/rtb.out" 2>/dev/null
head -1 "$TMP/rtb.out" | grep -qE 'withheld_est_tokens=[0-9]+' \
    && ok "(D) --recall --token-budget=1500: withheld_est_tokens= rides the header beside the budget it lost to" \
    || no "(D) --recall --token-budget=1500: the withheld estimate is prose only — the header states a budget nothing on it exceeds"

echo
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILURES — see above"; exit 1
