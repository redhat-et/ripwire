#!/usr/bin/env bash
# xmlwellformed.sh — G4 gate: every XML-emitting verb must pass `xmllint --noout`.
#
# Verbs exercised:
#   default map          plain `ripwire <dir>`
#   --for=task           task lens (sigs + lego + compose)
#   --expand=SYM         full def bodies
#   --pack-signatures    signatures-only bundle
#   --pack-top-n=5       top-N raw source bundle
#   --outline=SYM        control-flow skeleton
#   --owners             file git-author ownership
#   --dead-code          in-degree-0 symbol candidates
#   --tree               file-by-file orientation map
#   --arch --baseline    arch layering with baseline mode
#   --around=SYM         ego-graph pack, walked over a SYMBOL SAMPLE (see §B4b below)
#   --edit-check=SYM     contract-vs-HEAD bundle (CA4 §B15: this gate did not exercise it at all)
#   --impact=SYM --legend=full   with a via="name" row: the present-only FE-B clause inside the legend comment
#                        (CLI, columnar and the MCP twin — CodeRabbit 5468003465)
#   + the additive-flag shapes (--for --detail/--with-graph, --pack-task, --lego, --exemplar, --query
#     --adaptive, --expand+--outline+--pack-signatures together, --max-tokens): a verb's WIDEST form is
#     where a second top-level element appears, and a bare invocation cannot see it (trap #7).
#   + ONE case at CORPUS WIDTH (--edit-check at a ~600-byte absolute path). Every other case here runs at a
#     ~44-byte path, which is why 29 of them could not see §B14: an snprintf into char[512] does not start
#     cutting inside the markup until the escaped path approaches the buffer. See test/det-gate.sh's header
#     for the principle and for the other four verbs' width coverage.
#
# §B4b — WHY THIS GATE WALKS A SYMBOL SAMPLE. `--around` emitted its <compose>/<routes> siblings AFTER
# serialize() had already closed the root <r>, so the document had TWO top-level elements: xmllint rejected
# it and ripwire exited 0. Only 5 of 135 sampled symbols reproduce it — the breach needs a focus symbol whose
# ego-graph actually carries compose or route edges, not a hostile byte, which is precisely why the audit's
# 19-verb control-byte G4 sweep structurally could not find it. A fixed hand-picked symbol would rot the
# moment ranking moved, so the sample is DERIVED: the repo's own top-K map, walked. Keep it derived.
#
# Usage:
#   bash test/xmlwellformed.sh                    # uses build/ripwire on . and test/fixture
#   bash test/xmlwellformed.sh asan/ripwire       # positional BIN
#   RIPWIRE_BIN=asan/ripwire bash test/xmlwellformed.sh
#   XMLWF_AROUND_SAMPLE=40 bash test/xmlwellformed.sh   # narrow the --around walk (default 150)
#
# Exits non-zero on any failure; prints PASS/FAIL per check; prints ALL PASS on success.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow repo-relative BIN / RIPWIRE_BIN
AROUND_SAMPLE="${XMLWF_AROUND_SAMPLE:-150}"

CORPUS_SMALL="$ROOT/test/fixture"     # tiny fixture for fast deterministic checks
CORPUS_FULL="$ROOT"                   # the ripwire repo itself (has owners, tree, arch data)

fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint not found — install libxml2-utils"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT

echo "xmlwellformed: BIN=$BIN"

# Helper: run ripwire with given args, pipe stdout through xmllint, report PASS/FAIL.
check_xml() {
    local label="$1"; shift
    local out
    out=$( "$BIN" "$@" --no-cache 2>/dev/null )
    local rc_ripwire=$?
    if [ -z "$out" ]; then
        no "$label — ripwire produced no output (rc=$rc_ripwire)"
        return
    fi
    if [ "$rc_ripwire" -ge 128 ]; then   # a signal after a complete document still reads as well-formed (gateexitcheck H2)
        no "$label — ripwire died on signal $(( rc_ripwire - 128 )) after printing"
        return
    fi
    if printf '%s' "$out" | xmllint --noout - 2>/dev/null; then
        ok "$label"
    else
        no "$label — xmllint rejected the output"
        printf '%s' "$out" | xmllint --noout - 2>&1 | head -4
    fi
}

# ── default map ─────────────────────────────────────────────────────────────────────────
check_xml "default map (fixture)" "$CORPUS_SMALL"
check_xml "default map (repo)"    "$CORPUS_FULL"

# ── --for: task lens (sigs + lego + compose) ────────────────────────────────────────────
check_xml "--for (fixture)" "$CORPUS_SMALL" --for="parse files"
check_xml "--for (repo)"    "$CORPUS_FULL"  --for="serialize xml output"

# ── --expand: full def bodies ────────────────────────────────────────────────────────────
# Use a symbol that definitely exists in fixture; fall back gracefully if resolveAllByName misses
check_xml "--expand (fixture)" "$CORPUS_SMALL" --expand=distance
check_xml "--expand (repo)"    "$CORPUS_FULL"  --expand=escapeXml

# ── --pack-signatures ────────────────────────────────────────────────────────────────────
check_xml "--pack-signatures (fixture)" "$CORPUS_SMALL" --pack-signatures
check_xml "--pack-signatures (repo)"    "$CORPUS_FULL"  --pack-signatures

# ── --pack-top-n=5 ───────────────────────────────────────────────────────────────────────
check_xml "--pack-top-n (fixture)" "$CORPUS_SMALL" --pack-top-n=5
check_xml "--pack-top-n (repo)"    "$CORPUS_FULL"  --pack-top-n=5

# ── --outline ────────────────────────────────────────────────────────────────────────────
check_xml "--outline (fixture)" "$CORPUS_SMALL" --outline=distance
check_xml "--outline (repo)"    "$CORPUS_FULL"  --outline=escapeXml

# ── --owners (paths + git emails must be escaped) ────────────────────────────────────────
# ripwire repo is a git repo with commits; --owners on it exercises the email escape path.
# Skip gracefully if git is unavailable (CI without git history).
owners_out=$( "$BIN" "$CORPUS_FULL" --owners --no-cache 2>&1 )
if echo "$owners_out" | grep -q 'git unavailable\|no history'; then
    printf '  SKIP  --owners (git unavailable in this environment)\n'
elif printf '%s' "$owners_out" | xmllint --noout - 2>/dev/null; then
    ok "--owners (repo, emails escaped)"
else
    no "--owners (repo) — xmllint rejected the output"
    printf '%s' "$owners_out" | xmllint --noout - 2>&1 | head -4
fi

# ── --dead-code (paths must be escaped) ─────────────────────────────────────────────────
check_xml "--dead-code (fixture)" "$CORPUS_SMALL" --dead-code
check_xml "--dead-code (repo)"    "$CORPUS_FULL"  --dead-code

# ── --tree (section heading names with <...> must be escaped) ────────────────────────────
check_xml "--tree (fixture)" "$CORPUS_SMALL" --tree
check_xml "--tree (repo)"    "$CORPUS_FULL"  --tree

# ── --arch --baseline (comment must not contain --) ─────────────────────────────────────
# Use a TEMP COPY of baselinefix so the sidecar never lands in the repo.
# cd into the work dir so ripwire finds rules.txt relative to the indexed directory
# (matching how baselinecheck.sh works — archRules is resolved relative to the cwd).
BLFIX="$ROOT/test/baselinefix"
if [ -d "$BLFIX" ]; then
    BLWORK="$TMP/blfix"
    cp -R "$BLFIX" "$BLWORK"
    bl_out=$( cd "$BLWORK" && "$BIN" . --arch=rules.txt --baseline --no-cache 2>/dev/null )
    if [ -z "$bl_out" ]; then
        no "--arch --baseline — ripwire produced no output"
    elif printf '%s' "$bl_out" | xmllint --noout - 2>/dev/null; then
        ok "--arch --baseline (no double-hyphen in comment)"
    else
        no "--arch --baseline — xmllint rejected the output"
        printf '%s' "$bl_out" | xmllint --noout - 2>&1 | head -4
    fi

    # Also exercise --baseline-update (has a distinct comment string)
    bl_upd=$( cd "$BLWORK" && "$BIN" . --arch=rules.txt --baseline-update --no-cache 2>/dev/null )
    if [ -z "$bl_upd" ]; then
        no "--arch --baseline-update — ripwire produced no output"
    elif printf '%s' "$bl_upd" | xmllint --noout - 2>/dev/null; then
        ok "--arch --baseline-update (no double-hyphen in comment)"
    else
        no "--arch --baseline-update — xmllint rejected the output"
        printf '%s' "$bl_upd" | xmllint --noout - 2>&1 | head -4
    fi
else
    printf '  SKIP  --arch --baseline (no test/baselinefix fixture)\n'
fi

# ── §B4b: the ADDITIVE-FLAG shapes ──────────────────────────────────────────────────────
# Trap #7: a verb measured in its BARE form cannot show the sections only its flags add. Every shape below
# appends at least one more block to a document some other code already rooted.
check_xml "--for --detail (repo)"         "$CORPUS_FULL" --for="serialize xml output" --detail=3
check_xml "--for --with-graph (repo)"     "$CORPUS_FULL" --for="serialize xml output" --with-graph
check_xml "--for --detail --with-graph"   "$CORPUS_FULL" --for="serialize xml output" --detail=3 --with-graph
check_xml "--for --format=candidates"     "$CORPUS_FULL" --for="serialize xml" --format=candidates
check_xml "--pack-task (repo)"            "$CORPUS_FULL" --pack-task="serialize xml output"
check_xml "--pack-task --with-graph"      "$CORPUS_FULL" --pack-task="serialize xml output" --with-graph
check_xml "--pack-task --json off (fx)"   "$CORPUS_SMALL" --pack-task="parse files"
check_xml "--lego (repo)"                 "$CORPUS_FULL" --lego=XmlWriter
check_xml "--exemplar (repo)"             "$CORPUS_FULL" --exemplar="write xml"
check_xml "--query --adaptive (repo)"     "$CORPUS_FULL" --query="serialize" --adaptive
check_xml "map --max-tokens (repo)"       "$CORPUS_FULL" --max-tokens=400
check_xml "map sigs+expand+outline"       "$CORPUS_FULL" --pack-signatures --expand=escapeXml --outline=escapeXml
check_xml "--edit-check (repo)"           "$CORPUS_FULL" --edit-check=escapeXml
check_xml "--edit-check (fixture)"        "$CORPUS_SMALL" --edit-check=test/fixture/geometry.cpp:distance

# ── CA4 §B15: the WIDTH case ────────────────────────────────────────────────────────────
# Everything above runs at a path ~44 B long. §B14's six emitters snprintf'd ALREADY-ESCAPED path text into
# char[512], so the truncation that broke the document could not begin until the corpus path passed ~456 B
# raw (or ~228 B once `&`/`'` expand 5:1/6:1 BEFORE the buffer) — this gate had 29 cases and could not see
# any of it, and it did not exercise --edit-check at all. --edit-check is the widest of the six (two
# unbounded interpolands per <c> row, one per head) and is the case added here; test/det-gate.sh's width arm
# carries the other four verbs plus the byte-determinism half. The principle is stated in that gate's header:
# a well-formedness gate proves nothing about a fixed buffer unless its corpus can FILL that buffer.
WIDEDIR="$TMP/wide"
WD="$WIDEDIR"
WSEG="$( printf 'd%.0s' $( seq 1 60 ) )"
mkdir -p "$WIDEDIR"
while [ "${#WD}" -lt 580 ]; do
    if mkdir -p "$WD/$WSEG" 2>/dev/null; then WD="$WD/$WSEG"; else break; fi
done
if [ "${#WD}" -lt 520 ]; then
    printf '  SKIP  --edit-check at width (filesystem capped the path at %s B, need >=520)\n' "${#WD}"
else
    cat > "$WD/w.cpp" <<'WEOF'
int tgt( int a, int b ) { return a + b; }
int callerA( int x ) { return tgt( x, 1 ); }
int callerB( int x ) { return tgt( x, 2 ) + callerA( x ); }
WEOF
    # The PREMISE is the corpus path length checked above, NEVER the emitted width: a broken binary
    # truncates p= to just under its buffer, so an emitted-width premise reads "corpus too narrow" and skips
    # the very run it exists to catch (base_w3 emits a widest value of 506 B here — the truncation itself).
    "$BIN" "$WIDEDIR" --edit-check=tgt --no-cache >"$TMP/wide.xml" 2>/dev/null
    wide_widest=$( tr '"' '\n' <"$TMP/wide.xml" | awk '{ if ( length($0) > m ) m = length($0) } END { print m+0 }' )
    if [ ! -s "$TMP/wide.xml" ]; then
        no "--edit-check at width — no output"
    elif xmllint --noout "$TMP/wide.xml" 2>/dev/null; then
        ok "--edit-check at a ${#WD} B corpus path (widest emitted value ${wide_widest} B)"
    else
        no "--edit-check at width — xmllint rejected the output at exit 0 (§B14: the buffer cut inside the markup)"
        xmllint --noout "$TMP/wide.xml" 2>&1 | head -3
    fi
fi

# ── §B4b: --around over a derived SYMBOL SAMPLE ─────────────────────────────────────────
# The one shape the control-byte sweep could not reach. Cache stays WARM here on purpose: this asserts
# document SHAPE, not parse behaviour, and 150 cold runs would cost ~150 s for the same answer. One warm-up
# run first so the walk itself is not paying the parse.
"$BIN" "$CORPUS_FULL" --top-k=1 >/dev/null 2>&1
around_syms=$( "$BIN" "$CORPUS_FULL" --top-k="$AROUND_SAMPLE" 2>/dev/null \
               | grep -o '<s t="[^"]*" n="[^"]*"' | sed 's/.* n="//;s/"$//' | sort -u )
around_n=0; around_bad=0; around_first=""
# read LINES, not words: markdown section symbols (t="sec") carry spaces in their names, and the old
# unquoted `for sym in $around_syms` split "Where to look" into three bogus selectors whose empty
# error documents then failed xmllint (2026-08-12, markdown section tier).
while IFS= read -r sym; do
    [ -n "$sym" ] || continue
    around_n=$(( around_n + 1 ))
    "$BIN" "$CORPUS_FULL" --around="$sym" >"$TMP/around.xml" 2>/dev/null
    xmllint --noout "$TMP/around.xml" 2>/dev/null && continue
    around_bad=$(( around_bad + 1 ))
    [ -z "$around_first" ] && around_first="$sym"
done <<EOF_AROUND
$around_syms
EOF_AROUND
if [ "$around_n" -eq 0 ]; then
    no "--around symbol sample — derived ZERO symbols from the top-$AROUND_SAMPLE map (the sample's own premise failed)"
elif [ "$around_bad" -eq 0 ]; then
    ok "--around over $around_n derived symbols (0 ill-formed)"
else
    no "--around — $around_bad of $around_n sampled symbols emit an ill-formed document (first: --around=$around_first)"
    "$BIN" "$CORPUS_FULL" --around="$around_first" 2>/dev/null | xmllint --noout - 2>&1 | head -2
fi

# Every --around run must ALSO be single-rooted at exit 0 — the §B4b defect exited 0 while emitting two
# top-level elements, so a rc-only assertion would have passed it. Asserted on a symbol KNOWN to carry a
# sibling section when one exists in this corpus; silent (not skipped-as-pass) when none does.
compose_sym=""
for sym in $around_syms; do
    if "$BIN" "$CORPUS_FULL" --around="$sym" 2>/dev/null | grep -q '<compose>\|<routes>'; then compose_sym="$sym"; break; fi
done
if [ -n "$compose_sym" ]; then
    "$BIN" "$CORPUS_FULL" --around="$compose_sym" >"$TMP/around2.xml" 2>/dev/null
    rc_a=$?
    if [ "$rc_a" -eq 0 ] && xmllint --noout "$TMP/around2.xml" 2>/dev/null; then
        ok "--around=$compose_sym carries a <compose>/<routes> sibling AND is single-rooted at rc=0"
    else
        no "--around=$compose_sym (has a sibling section) rc=$rc_a, xmllint rejected it"
    fi
else
    printf '  SKIP  --around sibling-section arm (no sampled symbol has compose/route edges in this corpus)\n'
fi

# ── summary ─────────────────────────────────────────────────────────────────────────────
echo
# ── #60 — WITH A MODULE-SCOPE OWNER IN THE BODY SET ─────────────────────────────────────
# WHY THIS SECTION EXISTS, in this gate's own §B4b terms: a document's shape can break on the KIND of row it
# carries, not on the flags it was asked for, and a bare invocation cannot see it. `packBodies` writes a
# legend comment ahead of its `<bodies …>` tag when a requested symbol has no body by construction (a
# t="modscope" module-scope owner, issue #60), and that comment contains `n=<file-scope>` — an angle bracket
# in legend PROSE. `packtask.h`'s restating wrapper found the tag with `find( '>' )`, so it spliced inside the
# comment and emitted TWO `<bodies` opens and one close. Every case above passed: none of them puts an owner
# in a body set. So the corpus is BUILT here rather than sampled, and the callers of packBodies are walked
# over it — the same "derive it, do not hand-pick it" rule §B4b states, applied to a row KIND.
MS="$TMP/modscope"; mkdir -p "$MS/src"
printf 'export function setPhase(phase: string): void {\n  console.log(phase)\n}\n' > "$MS/src/lifecycle.ts"
printf "import { setPhase } from './lifecycle'\n\nexport function boot(): void {\n  setPhase('booting')\n}\n\nsetPhase('starting')\n" > "$MS/src/index.ts"
# premise: this corpus really does mint an owner, so the cases below are not vacuous
if "$BIN" "$MS" --no-cache --callers=setPhase 2>/dev/null | grep -q 't="modscope"'; then
    ok "#60 premise: the built corpus mints a module-scope owner"
else
    no "#60 premise: no t=\"modscope\" row in the built corpus — every case below would prove nothing"
fi
check_xml "#60 --pack-task, owner named"        "$MS" --pack-task='<file-scope> setPhase'
check_xml "#60 --pack-task, owner ranked in"    "$MS" --pack-task='module scope of a file'
check_xml "#60 --pack-task --with-graph"        "$MS" --pack-task='<file-scope> setPhase' --with-graph
check_xml "#60 --partition + --pack-task"       "$MS" --partition=2 --pack-task='<file-scope> setPhase'
check_xml "#60 --expand on the owner"           "$MS" --expand='<file-scope>'
check_xml "#60 --expand owner + real symbol"    "$MS" --expand='<file-scope>,setPhase'
check_xml "#60 --for names the owner"           "$MS" --for='module scope of a file'
check_xml "#60 --callers of the owner's callee" "$MS" --callers=setPhase
check_xml "#60 --impact"                        "$MS" --impact=setPhase
check_xml "#60 --safe-delete"                   "$MS" --safe-delete=setPhase
check_xml "#60 --edit-check"                    "$MS" --edit-check=setPhase
check_xml "#60 --graph-query kind(all,modscope)" "$MS" --graph-query='kind(all,modscope)'
check_xml "#60 --tree"                          "$MS" --tree
check_xml "#60 --pack-task at CORPUS width"     "$ROOT" --pack-task='scope of a file'
# …and the structural fact the malformed shape broke: exactly ONE <bodies element, and it is not restamped
# as capped over a body that never existed.
#
# CodeRabbit 4057546154: the two blocks below are the first in this gate to need python3 — one to count
# <bodies opens outside comments, one to unwrap the MCP envelope. Without it, `$( … | python3 … )` is the
# EMPTY STRING and both report a failure that is about the environment, not about the binary: BOPEN="" is
# "not 1", and an empty MCP payload is "did not answer". A gate that cannot tell a missing interpreter
# from a real defect is worse than one that says so, so the prerequisite is checked ONCE, by name, and the
# section skips with the reason. Every arm above this point uses only the shell and xmllint and still runs.
if ! command -v python3 >/dev/null 2>&1; then
    printf '  SKIP  #60 <bodies> structure and the MCP explore twin — python3 is not on PATH (prerequisite, not a failure)\n'
else
PT="$( "$BIN" "$MS" --no-cache --pack-task='<file-scope> setPhase' 2>/dev/null )"
BOPEN="$( printf '%s' "$PT" | python3 -c 'import sys,re; d=sys.stdin.read(); print(len(re.findall(r"<bodies[ >]", re.sub(r"<!--.*?-->","",d,flags=re.S))))' )"
BCLOSE="$( printf '%s' "$PT" | grep -o "</bodies>" | wc -l | tr -d " " )"
[ "$BOPEN" = 1 ] && [ "$BCLOSE" = 1 ] \
    && ok "#60 --pack-task emits exactly one <bodies> element (open=$BOPEN close=$BCLOSE)" \
    || no "#60 --pack-task emits open=$BOPEN close=$BCLOSE <bodies> — the wrapper spliced inside a legend comment"
printf '%s' "$PT" | grep -qE '<bodies shown="[0-9]+" total="[0-9]+" capped="0" bodyless="1">' \
    && ok "#60 --pack-task restates capped=\"0\" bodyless=\"1\": a bodyless owner is not an over-budget cut" \
    || no "#60 --pack-task restated the bodies tag wrongly: $( printf '%s' "$PT" | grep -oE '<bodies shown[^>]*>' )"
printf '%s' "$PT" | grep -q 'body omitted (over budget): &lt;file-scope&gt;' \
    && no "#60 --pack-task marks the owner as an over-budget omission — it has no body to omit" \
    || ok "#60 --pack-task does not call the owner an over-budget omission"
# the MCP twin of the same document (explore = --pack-task), through one tools/call round trip
mcp_text(){ printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' \
                          "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"$1\",\"arguments\":$2}}" \
    | "$BIN" --mcp 2>/dev/null | tail -1 | python3 -c '
import sys,json
try:    d=json.loads(sys.stdin.read() or "{}")
except Exception as e: sys.stdout.write("__ERROR__ unparseable: %s"%e);  raise SystemExit
if "error" in d: sys.stdout.write("__ERROR__ %s"%d["error"].get("message",""));  raise SystemExit
sys.stdout.write(d.get("result",{}).get("content",[{}])[0].get("text",""))'; }
MCPTXT="$( mcp_text explore "{\"path\":\"$MS\",\"task\":\"<file-scope> setPhase\"}" )"
case "$MCPTXT" in
    __ERROR__*|"") no "#60 MCP explore did not answer: ${MCPTXT:-empty}" ;;
    *) printf '%s' "$MCPTXT" | xmllint --noout - 2>/dev/null \
           && ok "#60 MCP explore (the --pack-task twin) is well-formed with an owner in the body set" \
           || { no "#60 MCP explore rejected by xmllint"; printf '%s' "$MCPTXT" | xmllint --noout - 2>&1 | head -3; } ;;
esac
fi   # end of the python3-dependent #60 section

# ── FE-B via="name" under --legend=full: --impact's present-only clause (CodeRabbit 5468003465) ──────────
# viaNameLegend( present, impact = true ) is spliced INSIDE the --impact legend comment, on the CLI and on MCP, and
# rides only when a shown row is via="name" and the posture is full — the compact default never carries it, which
# is why no arm above could see "An --impact row" put a double hyphen inside a comment. Premise first: this root's
# answer really carries a via="name" row AND the clause, so the well-formedness arms below are not vacuous.
RE="$ROOT/test/receiverevidencefix/js"
IMPF="$( "$BIN" "$RE" --no-cache --impact=lib/reply.js:send --legend=full 2>/dev/null )"
if printf '%s' "$IMPF" | grep -q ' via="name"' && printf '%s' "$IMPF" | grep -q 'impact row reached only through such an edge'; then
    ok "FE-B premise: --impact=lib/reply.js:send --legend=full carries a via=\"name\" row and the impact clause"
else
    no "FE-B premise: no via=\"name\" row or no impact clause in --impact=lib/reply.js:send --legend=full — the arms below prove nothing"
fi
check_xml "FE-B --impact with a via=\"name\" row, --legend=full"                  "$RE" --impact=lib/reply.js:send --legend=full
check_xml "FE-B --impact with a via=\"name\" row, --legend=full --format=columnar" "$RE" --impact=lib/reply.js:send --legend=full --format=columnar
if ! command -v python3 >/dev/null 2>&1; then
    printf '  SKIP  FE-B MCP impact twin — python3 is not on PATH (prerequisite, not a failure)\n'
else
    MIMP="$( mcp_text impact "{\"path\":\"$RE\",\"symbol\":\"lib/reply.js:send\",\"legend\":\"full\"}" )"
    case "$MIMP" in
        __ERROR__*|"") no "FE-B MCP impact did not answer: ${MIMP:-empty}" ;;
        *'impact row reached only through such an edge'*)
            printf '%s' "$MIMP" | xmllint --noout - 2>/dev/null \
                && ok "FE-B MCP impact (legend=full, a via=\"name\" row) is well-formed" \
                || { no "FE-B MCP impact (legend=full, a via=\"name\" row) rejected by xmllint"; printf '%s' "$MIMP" | xmllint --noout - 2>&1 | head -3; } ;;
        *) no "FE-B MCP impact premise: legend=full answer carries no impact clause — the arm proves nothing" ;;
    esac
fi

if [ "$fail" -eq 0 ]; then
    echo "ALL PASS"
    exit 0
else
    echo "SOME CHECKS FAILED"
    exit 1
fi
