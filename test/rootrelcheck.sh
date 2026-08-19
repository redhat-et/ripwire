#!/usr/bin/env bash
# rootrelcheck.sh — R-E (2026-08-17 harvest, report-memgraph §F6 seconded): the root-relative-paths gate
# for verbs BEYOND --grep. G1 (2026-08-15 harvest) already made --grep's <f p=…> root-relative and this
# gate's decisive-arm technique (an independent grep -c oracle over an absolute-root run) is lifted
# straight from that round's own verification method. This gate covers every OTHER high-volume path
# emitter this lane touched: the default map, --for/--pack-task, --expand/--outline/--lego/--deps,
# --callers/--callees/--uses/--impact (XML+JSON+columnar), --lint/--match, --clones, --cochange (both
# forms), --hotspots, --communities/--community=/--seams/--report, --skipped, --map-diff, --pr-context,
# --situ (CLI text + MCP JSON), --mentions, --owners, --handoff, --layout, --edit-check, --exercises,
# --graph-query, --abi, --connect, --path, and the quality-lens family (context-ratio/comment-coherence/
# nonlocal-state/naming-consistency/readability/dead-code/field-affinity) — plus, since 2026-08-19,
# --tree and --quality-panel, and the MCP twins of the two biggest surfaces (`analyze`, `for`).
#
# THE DEFECT (F6): a single-root run invoked with an ABSOLUTE root argument used to repeat that whole
# absolute path once per row in every one of the verbs above — the root spelled N times instead of once.
# THE FIX: root="…" (or the JSON "root":"…" twin, or a CLI text "root: …" leading line for the two
# non-XML/JSON dialects --situ/--report use) on the document's root element, single-root runs only
# (multi-root already carries its own roots=/<root label=…> disclosure and is untouched); every per-row
# p=/file/"p"/"file" attribute is root-relative.
#
# DELIBERATELY OUT OF SCOPE (documented, not silently regressed — see the lane report for the reasoning):
#   - id=/"id" canonical-identifier attributes (resolve.h::canonicalId) — a DIFFERENT relativization
#     scheme (often git-toplevel-relative via relForHash), an identity/lookup key rather than a display
#     path. This gate's oracle EXCLUDES id=/"id" from the count for exactly this reason.
#   - testmap.h's run="…" / "run": shell-command hint — a copy-paste command must stay valid regardless
#     of the reader's cwd, which a relative spelling cannot guarantee; kept absolute on purpose.
#   - editcheck.h's EditCheckGroup::spelling ambiguous-match retry suggestion (a narrower, error-path-only
#     surface not covered by this round).
#
# RED-STATE VERIFICATION (recorded, not re-run every pass — see the lane report's probe table for the
# full inventory): every verb this gate asserts on was probed against the pre-lane integration binary
# (integration/wave2-2026-08-17 @ f58702f) with an ABSOLUTE fixture root before any fix landed, and every
# one FAILED this gate's own oracle — e.g. default-map 37, lint 3207, callees 414, hotspots 40,
# nonlocal-state 303, --graph-query 200, --owners 508 absolute-prefix repetitions. Reproduce the red run
# with `RIPWIRE_BIN=<pre-lane-binary> test/rootrelcheck.sh` against a checkout at that commit.
#
# Usage:
#   test/rootrelcheck.sh                          # uses build/ripwire
#   RIPWIRE_BIN=asan/ripwire test/rootrelcheck.sh
#
# Exits non-zero on any failure. Environment-stable only: this gate asserts COUNTS of absolute-prefix
# occurrences (stable across machines/OSes), never byte-percentage magnitudes (see the informational
# byte-measurement arm below, which is disclosed but not gated).

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required for the attribute-aware oracle"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint required (G4 well-formedness)"; exit 2; }

# CORPUS: the ripwire repo itself, invoked with its ABSOLUTE path — the exact shape the defect needs
# (a relative root, e.g. "ripwire ." or "ripwire test/fixture", already emits "./"-relative paths and
# never repeats an absolute prefix; only an absolute root argument can leak one). Same corpus every
# git-dependent gate in this suite uses (ownerscheck.sh, hotspotsincecheck.sh, …) for the same reason:
# it is the one guaranteed git repo on hand.
CORPUS="$ROOT"
echo "rootrelcheck: BIN=$BIN  CORPUS(absolute)=$CORPUS"

# ── the attribute-aware oracle ──────────────────────────────────────────────────────────────────────────
# A blind `grep -c` of the absolute prefix over the WHOLE document is not the right instrument: it would
# also count the ONE legitimate root="…" disclosure (expected exactly once) and every id=/"id" canonical-
# identifier attribute (a different, deliberately-untouched relativization scheme — see the header). This
# walks every occurrence of the absolute prefix and classifies it by the attribute NAME it is the value
# of (looking backward for `name="` or `"name":"`), then reports two counts: `path_leaks` (occurrences in
# a p=/file/"p"/"file"-shaped attribute — the DEFECT this gate exists to catch, must be 0) and `root_disc`
# (occurrences in root=/"root" — must be EXACTLY 1 on every row of this sweep; see the loop for why the
# bound was tightened from "at most 1" on 2026-08-19).
oracle() {
python3 - "$1" "$CORPUS" <<'PYEOF'
import re, sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
abspath = sys.argv[2]
if not abspath:
    print("0 0"); raise SystemExit
path_attrs = {"p", "file", "cp"}     # value-shaped path attributes this lane targets (XML p=/cp=, JSON "file")
root_attrs = {"root"}                # the ONE allowed disclosure
excluded   = {"id", "target", "run"} # id= (canonicalId, different scheme); target= (note keys, relForHash-based
                                      # already, see D5); run= (shell command, deliberately absolute — see header)
path_leaks = 0
root_disc  = 0
other      = 0
for m in re.finditer(re.escape(abspath), text):
    ctx = text[max(0, m.start() - 40):m.start()]
    # WIDE context for the JSON case: a value can carry TEXT before the path (e.g. `"run":"bash /abs/…"`
    # — a shell command whose value is not JUST the path), so the tight 40-char immediately-after-the-
    # opening-quote lookback misses it. Search a wider window for the last `"key":"` and confirm no
    # UNESCAPED closing quote sits between it and our match (which would mean a different string).
    wide = text[max(0, m.start() - 200):m.start()]
    am = ( re.search(r'(?P<n>[A-Za-z_][A-Za-z0-9_]*)=\"$', ctx)
        or re.search(r'"(?P<n>[A-Za-z_][A-Za-z0-9_]*)":\"$', ctx)
        # the plain-text dialects (--situ, --report) spell the SAME disclosure as a leading
        # "root: <path>" / "Root: `<path>`" line, not an XML/JSON attribute — recognize it too.
        or re.search(r'(?:^|\n)(?P<n>root|Root):\s*`?$', ctx, re.I)
        # --situ's plain-text run hint: "   (run: bash /abs/…)" — no quotes at all, same deliberately-
        # absolute run= command as every other dialect, just spelled without the attribute syntax.
        or re.search(r'\((?P<n>run):\s*(?:bash|python3?|sh)?\s*$', ctx) )
    if am is None:
        # same widening, both dialects: a value can carry TEXT before the path (run="bash /abs/…",
        # "run":"bash /abs/…") — search a wider window for the last key open and confirm no UNESCAPED
        # closing quote sits between it and our match (which would mean we left that string already).
        for km in re.finditer(r'(?:(?P<n1>[A-Za-z_][A-Za-z0-9_]*)="|"(?P<n2>[A-Za-z_][A-Za-z0-9_]*)":")', wide):
            tail = wide[km.end():]
            if '"' not in tail.replace('\\"', ''):
                am = km
    if am is None:
        attr = "?"
    else:
        gd = am.groupdict()
        attr = ( gd.get("n") or gd.get("n1") or gd.get("n2") or "?" ).lower()
    if attr in root_attrs:
        root_disc += 1
    elif attr in excluded:
        other += 1
    elif attr in path_attrs or attr == "?":
        # an unclassified occurrence (attr == "?") is treated as a leak: honesty means the oracle never
        # silently waves through a shape it does not recognize.
        path_leaks += 1
    else:
        other += 1
print(f"{path_leaks} {root_disc}")
PYEOF
}

# label | CLI args (relative to CORPUS). Arguments are TAB-separated and split on TAB ALONE — never on
# spaces. Found 2026-08-19 while widening this gate: three rows carried a multi-WORD query
# (`--for=serialize map`, `--pack-task=serialize the ranked map`, and its --json twin) and the old
# space-splitting `$args` expansion tore each into an option plus stray bare words. A bare word after the
# root is another ROOT, so the binary printed `root path does not exist: map` to stderr, wrote NOTHING to
# stdout, and the oracle dutifully scored an empty file at zero leaks. Those three rows had asserted
# nothing since the gate landed — CONTRIBUTING §2's "a gate that cannot observe what it asserts", in this
# gate's own verb list. TAB separation fixes the splitting; the `-s` presence guard in the loop below is
# the general fix, so a row that emits nothing can never again read as a row that emits nothing WRONG.
declare -a VERBS=(
    "default-map|--top-k=30"
    "json-map|--json"$'\t'"--top-k=10"
    "for|--for=serialize map"
    "pack-task|--pack-task=serialize the ranked map"
    "pack-task-json|--pack-task=serialize the ranked map"$'\t'"--json"
    "expand|--expand=main"
    "outline|--outline=main"
    "callers|--callers=runDefaultMap"
    "callees|--callees=main"
    "callees-json|--callees=main"$'\t'"--json"
    "callees-columnar|--callees=main"$'\t'"--format=columnar"
    "uses|--uses=main"
    "impact|--impact=main"
    "impact-json|--impact=main"$'\t'"--json"
    "lint|--lint"
    "match|--match=(function_definition)"
    "clones|--clones"
    "hotspots|--hotspots"
    "cochange|--cochange"
    "cochange-file|--cochange=src/main.cpp"
    "cochange-groups|--cochange"$'\t'"--cochange-groups"
    "communities|--communities"
    "community|--community=0"
    "seams|--seams"
    "report|--report"
    "skipped|--skipped"
    "map-diff|--map-diff"
    "pr-context|--pr-context"
    "situ|--situ"
    "mentions|--mentions=main"
    "owners|--owners"
    "owners-sym|--owners=main"
    "handoff|--handoff"
    "layout|--layout=Config"
    "edit-check|--edit-check=runDefaultMap"
    "exercises|--exercises=test/regression.sh"
    "graph-query|--graph-query=and(kind(all,fn),fanin(all,5))"
    "connect|--connect=main,rankGraph"
    "path|--path=main,rankGraph"
    "context-ratio|--context-ratio"
    "comment-coherence|--comment-coherence"
    "nonlocal-state|--nonlocal-state"
    "naming-consistency|--naming-consistency"
    "readability|--readability"
    "dead-code|--dead-code"
    "field-affinity|--field-affinity"
    "deps|--deps"
    # ── verifier FINDINGS E1/E2 (2026-08-19): two surfaces this list did not name, and therefore did not
    #    cover. --tree is the single highest-volume path emitter in the tool (1,212 absolute rows on this
    #    corpus before the fix — more than every other verb in this list put together) and is the
    #    session-start orientation map the skills route to first; --quality-panel leaked all 40 of its p=
    #    rows. Neither was a REGRESSION — the pre-lane binary behaves identically — but "all verbs" was the
    #    claim and these two sat outside it. RED at the wave's verified head: tree 1212, quality-panel 40.
    "tree|--tree"
    "quality-panel|--quality-panel"
)

for entry in "${VERBS[@]}"; do
    label="${entry%%|*}"
    args="${entry#*|}"
    out="$TMP/$label.out"
    IFS=$'\t' read -r -a argv <<< "$args"          # TAB only — see the VERBS header for the row this saved
    "$BIN" "$CORPUS" "${argv[@]}" >"$out" 2>"$TMP/$label.err"
    # PRESENCE GUARD (CONTRIBUTING §2): the oracle scores an empty document at zero leaks, so a verb that
    # failed to run at all would read as a verb that ran clean. Assert the row produced something first.
    if [ ! -s "$out" ]; then
        no "$label: produced NO output — this row asserts nothing (stderr: $( head -c 140 "$TMP/$label.err" | tr '\n' ' ' ))"
        continue
    fi
    read -r leaks rootn < <( oracle "$out" )
    if [ "$leaks" = "0" ]; then
        ok "$label: 0 path-attribute leaks of the absolute root (root_disc=$rootn)"
    else
        no "$label: $leaks absolute-root leak(s) in p=/file attributes (root_disc=$rootn)"
        grep -o ".\{15\}$CORPUS.\{15\}" "$out" 2>/dev/null | LC_ALL=C sort -u | head -5
    fi
    # EXACTLY once, not "at most once" (tightened 2026-08-19). Every row of this sweep is a single-root run
    # with an ABSOLUTE root argument, so every row OWES the disclosure: relative p= with nothing naming what
    # they are relative to is the same class of dishonesty as the absolute p= this gate started with, just
    # quieter. The bound was <=1 and the pack-task --json dialect was sitting at 0 — it emitted a whole
    # bundle of root-relative `p` values and no "root" key at all.
    if [ "$rootn" != "1" ]; then
        no "$label: root disclosed $rootn time(s), expected exactly 1 (an absolute-root single-root run owes it)"
    fi
done

# ── CLI/MCP parity arm (at least 2 verbs): grep (G1's own verb — the baseline precedent) and situ ────────
# (this lane's own MCP twin, situationDiffJson) — both dialects must be equally clean and both must
# disclose root= exactly once for a single-root absolute-root run.
mcp_text() {
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' "$1" \
        | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c '
import sys, json
r = json.load(sys.stdin)
print("__ERROR__:" + r["error"].get("message","") if "error" in r else r["result"]["content"][0]["text"])
'
}
call() { printf '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"%s","arguments":%s}}' "$1" "$2"; }

# --grep has no --json CLI dialect ("--json is not yet supported for --grep") — the CLI side of this
# parity check is native XML; the MCP side is grep's own JSON twin (grepHitsJson). Different encodings,
# same fact: root= (XML) / "root" (JSON) disclosed once, zero path-attribute leaks either way.
grep_cli="$TMP/grep_cli.out";  "$BIN" "$CORPUS" --grep=Symbol >"$grep_cli" 2>/dev/null
# Built into a VARIABLE first, never a literal {…,…} on the command line: bash brace expansion runs before
# quote removal and silently SPLIT an inline "{\"path\":\"$CORPUS\",\"pattern\":\"Symbol\"}" argument into
# two separate `call grep` invocations at the comma — a real trap this gate's own first draft hit.
grep_args="{\"path\":\"$CORPUS\",\"pattern\":\"Symbol\"}"
grep_mcp="$TMP/grep_mcp.out";  mcp_text "$( call grep "$grep_args" )" >"$grep_mcp"
read -r gcl gcr < <( oracle "$grep_cli" )
read -r gml gmr < <( oracle "$grep_mcp" )
if [ "$gcl" = "0" ] && [ "$gml" = "0" ] && [ "$gcr" = "1" ] && [ "$gmr" = "1" ]; then
    ok "grep CLI/MCP parity: both clean, both disclose root= exactly once"
else
    no "grep CLI/MCP parity: cli(leaks=$gcl root=$gcr) mcp(leaks=$gml root=$gmr)"
fi

situ_cli="$TMP/situ_cli.out"; "$BIN" "$CORPUS" --situ >"$situ_cli" 2>/dev/null
situ_args="{\"path\":\"$CORPUS\"}"
situ_mcp="$TMP/situ_mcp.out"; mcp_text "$( call situational_awareness "$situ_args" )" >"$situ_mcp"
# --situ's CLI form is plain text (a leading "root: …" line, not an XML/JSON attribute) — the oracle's
# attribute-name lookback finds nothing there by design, so this arm checks the text line directly instead.
situ_cli_root=$( grep -c "^root: $CORPUS\$" "$situ_cli" 2>/dev/null || echo 0 )
read -r sml smr < <( oracle "$situ_mcp" )
if [ "$situ_cli_root" = "1" ] && [ "$sml" = "0" ] && [ "$smr" = "1" ]; then
    ok "situ CLI/MCP parity: CLI text 'root: …' line present once, MCP JSON clean + root= once"
else
    no "situ CLI/MCP parity: cli_root_lines=$situ_cli_root mcp(leaks=$sml root=$smr)"
fi

# ── verifier FINDINGS E3/E4 (2026-08-19): the parity arm covered grep + situ only, so the two MCP verbs
#    that are the direct twins of the two BIGGEST CLI surfaces went unchecked — and both leaked. MCP
#    `analyze` is the default map's own twin (85 absolute rows) and MCP `for` is --for's (3). The defect
#    this closes is not a leak in isolation: it is that the same corpus answered a CLI question with
#    `src/main.cpp` and the MCP twin of that same question with the absolute path. Both dialects must be
#    equally clean AND both must disclose root= exactly once. RED at the wave's verified head.
analyze_cli="$TMP/analyze_cli.out"; "$BIN" "$CORPUS" >"$analyze_cli" 2>/dev/null   # the plain default map
analyze_args="{\"path\":\"$CORPUS\"}"
analyze_mcp="$TMP/analyze_mcp.out"; mcp_text "$( call analyze "$analyze_args" )" >"$analyze_mcp"
read -r acl acr < <( oracle "$analyze_cli" )
read -r aml amr < <( oracle "$analyze_mcp" )
if [ "$acl" = "0" ] && [ "$aml" = "0" ] && [ "$acr" = "1" ] && [ "$amr" = "1" ]; then
    ok "analyze CLI/MCP parity: both clean, both disclose root= exactly once"
else
    no "analyze CLI/MCP parity: cli(leaks=$acl root=$acr) mcp(leaks=$aml root=$amr)"
    grep -o ".\{15\}$CORPUS.\{15\}" "$analyze_mcp" 2>/dev/null | LC_ALL=C sort -u | head -3
fi

for_cli="$TMP/for.out"                      # produced by the verb sweep above (--for=serialize map)
for_args="{\"path\":\"$CORPUS\",\"task\":\"serialize map\"}"
for_mcp="$TMP/for_mcp.out";  mcp_text "$( call for "$for_args" )" >"$for_mcp"
read -r fcl fcr < <( oracle "$for_cli" )
read -r fml fmr < <( oracle "$for_mcp" )
if [ "$fcl" = "0" ] && [ "$fml" = "0" ] && [ "$fcr" = "1" ] && [ "$fmr" = "1" ]; then
    ok "for CLI/MCP parity: both clean, both disclose root= exactly once"
else
    no "for CLI/MCP parity: cli(leaks=$fcl root=$fcr) mcp(leaks=$fml root=$fmr)"
    grep -o ".\{15\}$CORPUS.\{15\}" "$for_mcp" 2>/dev/null | LC_ALL=C sort -u | head -3
fi

# ── well-formedness + determinism, the two structural gates every changed emitter owes (G4) ──────────────
for label in default-map lint clones communities pr-context; do
    xmllint --noout "$TMP/$label.out" >/dev/null 2>&1 \
        && ok "$label: well-formed XML (xmllint)" \
        || no "$label: NOT well-formed XML"
done

"$BIN" "$CORPUS" --top-k=30 >"$TMP/det1" 2>/dev/null
"$BIN" "$CORPUS" --top-k=30 >"$TMP/det2" 2>/dev/null
diff -q "$TMP/det1" "$TMP/det2" >/dev/null \
    && ok "determinism: byte-identical default-map across runs" \
    || no "determinism: non-identical default-map output"

# ── informational byte-measurement arm (disclosed, NOT gated — magnitudes are not environment-stable) ────
# --hotspots on this absolute root, this commit, this corpus, cache state as found. Recorded for the lane
# report; the number is informational, never asserted on (only occurrence COUNTS above are the gate).
hs_bytes=$( wc -c < "$TMP/hotspots.out" 2>/dev/null | tr -d ' ' )
echo "  INFO  byte measurement: ripwire $CORPUS --hotspots = ${hs_bytes:-0} bytes (informational only, not gated)"

# ── Summary ─────────────────────────────────────────────────────────────────────────────────────────────
echo
if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
