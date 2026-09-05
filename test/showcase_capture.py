#!/usr/bin/env python3
"""Regenerate the ripwire command showcase against the CURRENT binary. Successor to runner.py."""
import subprocess, time, os, re, sys, json, tempfile, shutil

# No absolute machine paths here: test/ is a SHIP path and ripwirepubliccheck greps it for home-dir
# prefixes. REPO is derived from this script's own location; SCRATCH is a per-run temp dir (override
# via RIPWIRE_SHOWCASE_SCRATCH to keep the sandbox around for inspection).
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRATCH = os.environ.get("RIPWIRE_SHOWCASE_SCRATCH") or tempfile.mkdtemp(prefix="ripwire_showcase_")
BIN = "./build/ripwire"
ABIN = os.path.join(REPO, "build", "ripwire")
DIRTY = os.path.join(SCRATCH, "dirty")          # throwaway --local clone with ONE deliberate regression
AUX = os.path.join(SCRATCH, "aux")
os.makedirs(AUX, exist_ok=True)

# The capture is a SHIPPED document, so it goes through the SAME public-export scrub docs/COMMANDS.md
# is built with — imported, not re-spelled, so the two can never drift apart and a new leak shape has
# exactly one place to be fixed. A missing scrub must be a hard stop, never a silently unscrubbed
# write: that failure would ship the leak while looking like a successful regeneration.
sys.path.insert(0, os.path.join(REPO, "docs"))
try:
    import docs_commands_build as exportscrub
except ImportError as exc:
    sys.exit(f"showcase_capture: cannot import the export scrub from docs/docs_commands_build.py ({exc}) — "
             f"refusing to write an unscrubbed capture")

# --- helper input files -------------------------------------------------
# A realistic fabricated ASan report. Frame line numbers are the CURRENT ones for those
# symbols, so the locus lane is being asked a fair question.
TRACE = """AddressSanitizer:DEADLYSIGNAL
=================================================================
==41337==ERROR: AddressSanitizer: SEGV on unknown address 0x000000000018 (pc 0x000102f4a1c8 bp 0x00016d2f1a40 sp 0x00016d2f19e0 T0)
    #0 0x102f4a1c8 in rw::rankGraphTeleport(Graph const&, std::vector<float> const&, float) src/graph.h:1148
    #1 0x102f3e884 in rw::rankGraph(Graph const&, float) src/graph.h:1174
    #2 0x102e11f30 in runDefaultMap(MainDispatch const&) src/main.cpp:5155
    #3 0x102e01a44 in main src/main.cpp:5594
    #4 0x1a2b3c0dc in start+0x9dc (dyld:arm64e+0x60dc)
==41337==ABORTING
"""
trace_path = os.path.join(AUX, "asan_trace_now.txt")
open(trace_path, "w").write(TRACE)

# §A10.9: the three words below live on separate lines/variables (not one contiguous source line) so
# this harness does not duplicate the --for="incremental cache invalidation ..." demo phrase elsewhere in
# this file closely enough to rank itself as a hit for that query (instrument self-pollution, the §P17
# class recurring through this NEW harness — same cause as the filter.h banner's "no verbatim eval-query
# vocabulary" rule, applied here since this is DATA the batch demo still needs, not a comment to omit).
# The written aux file's bytes are unaffected: f-string interpolation reproduces the identical text.
_batchWord1 = "incremental"
_batchWord2 = "cache"
_batchWord3 = "invalidation"
BATCH = f"""for:{_batchWord1} {_batchWord2} {_batchWord3}
callers:rankGraphTeleport
grep:DEGRADED_PATH_ALERT
lego:Vehicle
"""
batch_path = os.path.join(AUX, "batch2.txt")
open(batch_path, "w").write(BATCH)

_realRefs = subprocess.run( "git for-each-ref --format='%(refname:short)' refs/heads | grep -v '^main$' | head -3", shell=True, cwd=REPO, capture_output=True ).stdout.decode().split()
while len( _realRefs ) < 3:
    _realRefs.append( f"no-such-ref-{len( _realRefs )}" )   # a label naming a ref that does not exist — the eval must not credit it as merged
STRAY_TSV = "# ref<TAB>verdict labels for --eval-stray (the first three local branches, resolved at capture time; a missing branch is padded with a nonexistent name on purpose)\n" + f"{_realRefs[0]}\tmerged\n{_realRefs[1]}\tunmerged\n{_realRefs[2]}\tmerged\n"
stray_tsv_path = os.path.join(AUX, "stray_labels2.tsv")
open(stray_tsv_path, "w").write(STRAY_TSV)

SKILLS_TSV = ("orient in an unfamiliar codebase fast\tripwire-orient\tjudged\n"
              "who calls this function and what is the blast radius\tripwire-navigate\tjudged\n"
              "plan parallel worktrees so the lanes do not collide\tripwire-change-check\tjudged\n"
              "what is the weather in Paris\tnone\tneg\n")
skills_tsv_path = os.path.join(AUX, "skills_labels2.tsv")
open(skills_tsv_path, "w").write(SKILLS_TSV)

BRIEF = ("add a --since filter to the doc-drift verb\n"
         "add the CLI parse arm and help text for the new filter\n"
         "write regression tests for the new filter\n")
brief_path = os.path.join(AUX, "lanes_brief.txt")
open(brief_path, "w").write(BRIEF)

# A minimal two-file corpus for the --lint --with-profile heat-join demo: one function with a
# pointer-chase loop (trips cache-pointer-chase-loop) and a PROFILE_SCOPE site above it, plus a
# fabricated report whose #PROF_TSV row names that site. Fabricated because a real RIPWIRE_PROFILE
# report needs a profile build of ripwire itself; the row's shape is print_tsv's own
# (src/infra/profileScope.h) so the join is being asked a fair question. Line 9 below IS the
# PROFILE_SCOPE line — the TSV row must point inside walk() and at-or-above the finding line.
HEATDEMO = os.path.join(AUX, "heatdemo")
os.makedirs(os.path.join(HEATDEMO, "src"), exist_ok=True)
open(os.path.join(HEATDEMO, "src", "x.cpp"), "w").write(
"""struct Node
{
    int   value;
    Node* next;
};

int walk( const Node* head )
{
    PROFILE_SCOPE( "walk: chase pass" );
    int total = 0;
    for( const Node* p = head; p != nullptr; p = p->next )
    {
        total += p->value;
    }
    return total;
}
""")
open(os.path.join(HEATDEMO, "report.txt"), "w").write(
    "#PROF_TSV_BEGIN\tone row per scope, aggregated across threads; counters are RAW integers\n"
    "scope\tfile\tline\tcalls\ttotal_ms\tl1d_mpki\n"
    "walk: chase pass\tx.cpp\t9\t12\t48.500\t7.250\n"
    "#PROF_TSV_END\n")

html_out = os.path.join(AUX, "map2.html")
cc_out = os.path.join(AUX, "ripwire2.cc.json")
cache_out = os.path.join(AUX, "warm2.ripwirecache")
idx_out = os.path.join(AUX, "ci_index")
census_out = os.path.join(AUX, "pin_census.tsv")
payload_less_path = os.path.join(AUX, "payload_lessByScoreDescId.h")      # written after OLD_LESS is defined (sandbox section)
payload_note_path = os.path.join(AUX, "payload_note.h")
open(payload_note_path, "w").write("// inserted by the showcase capture: a one-line marker the insert verbs place verbatim\n")
edit_plan_path = os.path.join(AUX, "edit_plan.json")
open(os.path.join(AUX, "plan_note.h"), "w").write("// edit-plan payload: placed before nonNegativeFloatDescKey by ONE transaction\n")
open(edit_plan_path, "w").write(json.dumps({"version": 1, "edits": [
    {"op": "insert_before_symbol", "target": "nonNegativeFloatDescKey", "payload": "plan_note.h"}]}, indent=1) + "\n")
empty_payload_path = os.path.join(AUX, "empty_payload.h")
manifest_py = os.path.join(AUX, "manifest_summary.py")
open(manifest_py, "w").write('''import sys, json
r = json.load(sys.stdin)
ts = r["result"]["tools"]
blob = json.dumps(r, separators=(",", ":"))
print("tools=", len(ts), " manifest_bytes=", len(blob), " (~tokens at 4 bytes/token:", len(blob) // 4, ")")
for t in sorted(ts, key=lambda t: -len(json.dumps(t))):
    d = t.get("description", ""); sch = json.dumps(t.get("inputSchema", {}), separators=(",", ":"))
    print(f"{t[\'name\']:28s} desc_bytes={len(d):5d} schema_bytes={len(sch):5d} required={t.get(\'inputSchema\', {}).get(\'required\', [])}")
''')
open(empty_payload_path, "w").write("")

import shlex
def mcp(*reqs):
    """One-shot stdio JSON-RPC exchange: newline-delimited requests piped into `--mcp`, one response line each."""
    return "printf '%s\\n' " + " ".join(shlex.quote(r) for r in reqs) + f" | {BIN} --mcp"
MCP_INIT = '{"jsonrpc":"2.0","id":1,"method":"initialize"}'
def mcp_call(verb, **args):
    return json.dumps({"jsonrpc": "2.0", "id": 2, "method": "tools/call",
                       "params": {"name": verb, "arguments": dict(path=".", **args)}}, separators=(",", ":"))

# --- the recorded tree condition ----------------------------------------
# The diff-aware verbs (--situ / --test-gate / --quality-delta / --pr-context / --map-diff / --edit-check)
# answer a question ABOUT THE WORKING TREE, so their captions are claims about the tree this run recorded
# against. Hardcoding "clean tree = empty" made those captions lie the moment a regeneration happened on a
# dirty tree: the document then asserted an empty bundle directly above a populated one. Read the condition
# once, up front, and branch every such caption on it — the generator is the only thing that knows.
REPO_DIRTY_LINES = subprocess.run("git status --porcelain", shell=True, cwd=REPO,
                                  capture_output=True).stdout.decode().strip()
REPO_DIRTY = bool(REPO_DIRTY_LINES)
TREE = "a DIRTY tree" if REPO_DIRTY else "a CLEAN tree"
def onTree(clean, dirty):
    """Pick the caption that matches the tree this run is actually recording against."""
    return dirty if REPO_DIRTY else clean

# --- command table ------------------------------------------------------
C = []
def add(section, cmd, what, **opts):
    C.append(dict(section=section, cmd=cmd, what=what, **opts))

S1 = "understand a codebase cold"
add(S1, f"{BIN} .", "The default ranked symbol map — start here when landing cold in a repo.")
add(S1, f"{BIN} . --top-k=5", "Same map, capped to the 5 highest-ranked symbols.")
add(S1, f"{BIN} . --top-k=0 --expand=rankGraphTeleport", "NEW since the last capture: --top-k=0 means PAYLOAD-ONLY — no ranked map rides along with the body you asked for.")
add(S1, f"{BIN} . --top-k=0", "--top-k=0 with NO payload verb asked for — what an empty request emits.")
add(S1, f"{BIN} . --max-tokens=1500", "SHAPE the map to fit ~1500 tokens (binary-search top-K).")
add(S1, f"{BIN} . --token-budget=100", "GATE form: exit 3 if the map's own est_tokens exceeds the budget (over-budget failure shape).")
add(S1, f'{BIN} . --for="{_batchWord1} {_batchWord2} {_batchWord3} when a file content hash changes"', "The task lens: ranked signatures + quality metrics framed for the task.")   # §A10.9/V2-8: same split as BATCH — no contiguous source quote of the demo phrase
add(S1, f'{BIN} . --for="rankGraphTeleport"', "Name-shaped query: the router picks name-exact BM25 (header says which/why).")
add(S1, f'{BIN} . --for="rankGraphTeleport" --no-route', "Same query with routing forced OFF (plain subtoken+body BM25) — contrast with the routed run.")
add(S1, f'{BIN} . --for="rankGraphTeleport" --signatures-only', "T3 opt-out: the signatures-only lens (no auto bodies, no bundle=\"auto\" attribute) — contrast with the terminal default above.")
add(S1, f'{BIN} . --for="tree-sitter parse of a source file" --adaptive', "Cut the result at the relevance cliff (Adaptive-k) — on a flat ranking nothing is cut and the header says so ([adaptive: kept N of N]).")
add(S1, f'{BIN} . --for="why does src/lexical.h chooseForRanker pick name-exact BM25"', "Mention anchoring (default-on): a path and a Symbol literally named in the task get lifted; the header says what anchored.")
add(S1, f'{BIN} . --for="why does src/lexical.h chooseForRanker pick name-exact BM25" --no-mention-boost', "Same task with the anchor disabled — the contrast the flag exists for.")
add(S1, f"{BIN} . --lego=Vehicle", "Interface -> implementors view: every existing impl of the named interface; the method contract is extracted for the C-family/Java/TS/Python tiers — for a Rust trait (this fixture) it discloses caveat=\"not-extracted-for-lang\" rather than an empty list.")
add(S1, f'{BIN} . --exemplar="format byte sizes for humans"', "The repo's best-in-class instance to imitate before writing new code (picked by ROLE).")
add(S1, f'{BIN} . --help-task="calls(runDefaultMap, rankGraphTeleport)"', "Deterministic enhanced help: a closed claim in the task is a structured shape, so the router recommends the ONE command that answers it (--verify) with the evidence behind the pick. Advice only — nothing executes.")
add(S1, f'{BIN} . --help-task="write a cheerful release announcement"', "The honest half of the contract: a task with no ripwire-shaped evidence ABSTAINS with zero commands rather than guessing.")
add(S1, f'{BIN} . --recall="quality delta gating exit codes"', "Most relevant DOCS' full bodies (markdown only) — recall what is already written down.")
add(S1, f"{BIN} . --tree", "File-by-file orientation map (top symbols per file).")
add(S1, f"{BIN} . --html={html_out}", "Self-contained HTML force-directed call graph.", post=f"wc -c {html_out}")
add(S1, f"{BIN} . --order=stable --top-k=5", "Stable (path/id) emit order — provider KV-cache hits across re-runs.")

S2 = "navigate / answer a question"
add(S2, f"{BIN} . --around=rankGraphTeleport", "Ego graph around one symbol.")
add(S2, f"{BIN} . --callers=rankGraphTeleport", "Who calls SYM (1-hop in-edges).")
add(S2, f"{BIN} . --callers=DoesNotExist", "Unknown-symbol failure shape.")
add(S2, f"{BIN} . --callees=rankGraphTeleport", "What SYM calls (1-hop out-edges).")
add(S2, f"{BIN} . --uses=rankGraphTeleport", "The resolvable use-sites (call/read/write/import/extends) with file:line; count= is a floor.")
add(S2, f"""{BIN} . --graph-query='and(callers(name("rankGraphTeleport"),2),kind(all,fn))'""", "Composable node-set query: functions within 2 caller-hops of rankGraphTeleport.")
add(S2, f"{BIN} . --external-surface", "Names referenced but never defined in-corpus (stdlib/third-party surface). NOW carries names/shown/capped (total= joins them only under --limit/--offset).")
add(S2, f"{BIN} . --path=main,rankGraphTeleport", "Shortest directed call-path SRC -> DST. CHANGED: now reports from_p/to_p/from_defs and resolves the right `main` (was reachable=\"0\").")
add(S2, f"{BIN} . --connect=rankGraphTeleport,runEval,getIndex", "Minimal connecting subgraph over 3 symbols (finds shared-caller joins).")
add(S2, f"{BIN} . --impact=rankGraphTeleport", "Transitive blast radius — everything that reaches SYM. NOW carries shown/capped.")
add(S2, f"{BIN} . --mentions=rankGraphTeleport", "Markdown docs that name SYM in a backtick (doc<->code edges).")
add(S2, f"{BIN} . --affected=src/graph.h", "Test files that transitively reach the changed file.")
add(S2, f"{BIN} . --situ", f"Mid-task situational report for the current git diff — recorded against {TREE} (contrast with the sandbox run below).")
add(S2, f"{BIN} . --test-gate", onTree(
    "Pre-PR gate on a CLEAN tree: no obligations, exit 0.",
    "Pre-PR gate recorded against a DIRTY tree, so the obligations below are the working copy's real ones — the recorded exit code says which way it went."))
add(S2, f"{BIN} . --grep=DEGRADED_PATH_ALERT", "Literal trigram-indexed search. CHANGED: each hit now carries the MATCHED line in <m>, plus shown/capped/hits_capped.")
add(S2, f"{BIN} . --grep=DEGRADED_PATH_ALERT --grep-context=1", "Same search with one line of source context either side.")
add(S2, f"{BIN} . --grep=DEGRADED_PATH_ALERT --grep-before=1 --grep-after=2 --limit=3", "The asymmetric spelling of the same context: one line before and two after each hit (ripgrep's -B/-A), on a three-hit window.")
add(S2, f"{BIN} . --regex='fnv1a\\w+'", "Regex search + enclosing symbol.")
add(S2, f"{BIN} . --match='(if_statement)'", "Tree-sitter structural query WITHOUT a capture — a bare node query gets a capture AUTO-ADDED (auto_captured=\"1\") and matches the same nodes the explicit form does.")
add(S2, f"{BIN} . --match='(if_statement) @i'", "The same shape query WITH an explicit capture — identical hits, no auto_captured= attribute.")
add(S2, f'{BIN} . --query="teleport pagerank" --top-k=5', "Raw BM25 ranking (debug lens; --for is the real verb).")

S3 = "zoom the detail ladder"
add(S3, f'{BIN} . --for="pagerank power iteration" --detail=2', "Importance-weighted detail: FULL bodies for top-2, signatures for the rest.")
add(S3, f"{BIN} . --pack-signatures --top-k=10", "Body-elided decl skeletons — recounted on this corpus. Measured as element bytes: the <d> signature+doc elements --pack-signatures emits, against the SAME symbols' full <b> bodies from --expand, with the CORPUS-ROOT PREFIX SUBTRACTED FROM BOTH SIDES. That subtraction is the whole methodology and the figure is meaningless without it: the root repeats inside every element's id= and p=, it is not what this verb elides, and counting it makes the headline a function of how deep the checkout happens to sit on disk — on one corpus, three spellings of the same root read 18.6 points apart before the subtraction and agree exactly after it. Root-neutralised on THIS repo: 84.5% fewer bytes at top-10, 80.2% at top-50, 80.6% at top-100 (V1, 2026-08-15: --expand's <b> bodies now carry sibs=/inc= file-context attributes — see docs/COMMANDS.md's --expand entry — which grows the body side of this ratio and moved the figure up from 70.0/61.0/63.8). top-50 is the number to quote, because the sigs payload is top-50 regardless of --top-k and is therefore what THIS command emits. A single small/trivial body can still invert it (signature+doc bigger than the body), like the --format=columnar sibling below. test/showcasecapturecheck.sh (C) re-derives all three from this repo every run, in the same quantity, and fails if the caption and the recount drift apart.")
add(S3, f"{BIN} . --outline=rankGraphTeleport --top-k=0", "Control-flow skeleton of one symbol, payload-only via the new --top-k=0.")
add(S3, f"{BIN} . --outline=rankGraphTeleport:1-10 --top-k=0", "CHANGED: a line range on --outline is now STRIPPED with a stderr note (it used to refuse).")
add(S3, f"{BIN} . --expand=rankGraphTeleport --top-k=0", "Full body + inline callee signatures.")
add(S3, f"{BIN} . --expand=rankGraphTeleport:1-12 --top-k=0", "Body SLICE: lines 1..12 of the symbol's own body, with lines=\"lo-hi/total\" marking it partial.")
add(S3, f"{BIN} . --expand=compressBody --top-k=0 --compress", "Comments stripped + blank runs collapsed — compressBody is the function that implements --compress itself, chosen because it is comment-heavy enough to show a real reduction (the previously captioned symbol had no comments or blank runs, so before/after were byte-identical under a caption promising a difference).")
add(S3, f"{BIN} . --expand=readAckRecords --top-k=0 --no-redact", "--no-redact: emit bodies verbatim (credential redaction is on by default).")
add(S3, f"{BIN} . --pack-top-n=3 --top-k=0", "Pack the top-3 ranked symbols' full bodies (deprecated verb; see stderr).")

S4 = "assess quality / structure"
add(S4, f"{BIN} . --metrics --top-k=10", "Fan-in/out + complexity annotations on the map.")
add(S4, f"{BIN} . --deps", "File->file dependency graph (god-files, cycles).")
add(S4, f"{BIN} . --hotspots", "Complexity x recent git churn (maintenance pain).")
add(S4, f"{BIN} . --clones", "Token-normalized duplicate bodies.")
add(S4, f"{BIN} . --cochange", "Files that change together in git (hidden coupling).")
add(S4, f'{BIN} . --hotspots --since="2 weeks ago"', "Hotspots scoped to RECENT churn (the regression lens).")
add(S4, f"{BIN} . --arch=test/archfix/rules.txt", "Enforce layering rules (exit 2 on violation) — run against the repo's own test fixture rules.")
add(S4, f"{BIN} . --lint", "Built-in AST checks (c-cast, goto, unsafe-c-fn, ...).")
add(S4, f"{BIN} . --lint-rules=test/lintrulesfix/rules", "User lint rules (YAML, ast-grep style) from a directory.")
add(S4, f"{ABIN} . --lint --with-profile=report.txt", "Join MEASURED heat onto --lint findings — runs in a tiny fabricated demo corpus (one cache-pointer-chase-loop finding under a PROFILE_SCOPE site) because a real report needs a RIPWIRE_PROFILE build; the finding inside the profiled scope gains heat_* columns from the report's #PROF_TSV row.", cwd=HEATDEMO, pre="cat report.txt",
    post=f"{ABIN} . --lint --with-profile=report.txt 2>/dev/null | grep -o '<f rule=[^<]*</f>'",
    post_label="The joined finding — past the display cut above, extracted so the join is visible:")
add(S4, f"{BIN} . --communities", "Cluster the call graph into cohesive modules.")
add(S4, f"{BIN} . --zoom", "Nested module hierarchy (multi-level Louvain) + cross-module bridges.")
add(S4, f"{BIN} . --report", "Architecture summary (modules, god-files, cycles) as markdown.")
add(S4, f"{BIN} . --seams", "Cross-module call seams no test reaches. NOW carries seam_pairs/shown/capped.")
add(S4, f"{BIN} . --mermaid", "Module (directory) dependency graph as a Mermaid diagram.")
add(S4, f"{BIN} . --owners", "Bus-factor: recency-weighted author ownership per file.")
add(S4, f"{BIN} . --dead-code=src", "High-confidence internal functions with no caller. NOTE the filter is a path-COMPONENT match: 'src' matches any .../src/... segment; use ./src to pin the root directory.")
add(S4, f"{BIN} . --exercises=test/regression.sh", "Which symbols a TEST FILE exercises — the reverse direction of --affected.")
add(S4, f"{BIN} . --community=0", "Drill into ONE call-graph community by id — the drill= the --communities output itself advertises.")
add(S4, f"{BIN} . --quality-delta", onTree(
    "On a CLEAN tree: nothing got worse, exit 0. The gating shape is in the sandbox section below.",
    "Recorded against a DIRTY tree, so any row below is a real regression in the working copy. The sandbox section below shows the same gating shape on a known, deliberate edit."))
add(S4, f"{BIN} . --edit-check=rankGraphTeleport", onTree(
    "Fast per-symbol post-edit contract check vs git HEAD (unchanged on a clean tree).",
    "Fast per-symbol post-edit contract check vs git HEAD — recorded against a DIRTY tree, so the verdict describes the working copy, not HEAD alone."))
add(S4, f"{BIN} . --pr-context", onTree(
    "No-LLM review-evidence bundle for the working-tree diff (clean tree = empty).",
    "No-LLM review-evidence bundle for the working-tree diff — recorded against a DIRTY tree, so it is populated rather than empty."))
add(S4, f"{BIN} . --pr-context=HEAD~1", "The BASEREF form: diffed against merge-base(BASEREF, HEAD), never the ref tip — here the previous commit on the current line (a ref with NO merge base falls back to a disclosed two-dot diff: anchor=\"ref-tip-two-dot\").")
add(S4, f"{BIN} . --merge-scout=HEAD~2,HEAD~1", "Pairwise cross-arm conflict sites + suggested landing order (any committish sharing a merge base with HEAD works as an arm; one that does not is reported ok=\"0\", never compared).", timeout=600)
add(S4, f"{BIN} . --stray-content=lane", "Which lane-* refs still hold divergent authored work vs HEAD, with verdicts.", timeout=600)
add(S4, f"{BIN} . --stray-content=worktree-agent-a1", "A second ref family: merged refs are OMITTED from the rows and counted in merged=; refs sharing no merge base with HEAD (a shallow clone, or a pre-rewrite history) land in unknown= with ok=\"0\" — the counters always reconcile against refs=.", timeout=600)
add(S4, f"{BIN} . --stray-content=r27 --plan", "Select the genuinely-unmerged refs and feed them to merge-scout for a landing order.", timeout=900)
add(S4, f"{BIN} . --stray-content=lane --abi", "Cross-branch ABI-break gate: struct byte-contract drift on each ref's AUTHORED paths.", timeout=600)
add(S4, f"{BIN} . --whereis=rankGraphTeleport", "Which ref's tree defines or mentions SYM — HEAD first, then every local branch.", timeout=600)
add(S4, f"{BIN} . --whereis=computeOnePairOverlap --with-history", "Same, plus a git-history <fate> row (never / removed-by-commit) for names no tree carries.", timeout=600)
add(S4, f"{BIN} . --flags", "The dark-content dashboard: gates BUILT but OFF. CHANGED: no longer invents gates from comments/heredocs, so the count only reflects real ifndef/define, CMake option(), and getenv gates.")
add(S4, f"{BIN} . --flags --flip=RIPWIRE_ASAN", "Blast radius of turning ONE gate on: live code, symbols, transitive reach, covering tests.")
add(S4, f"{BIN} . --flags --flip=RIPWIRE_ASA", "Unknown-gate refusal (exit 1) with a did-you-mean from a real edit distance (one character off RIPWIRE_ASAN).")
add(S4, f'{BIN} . --plan-lanes=3 --task="add a --since filter to the doc-drift verb and cover it with tests"', "NEW VERB: pre-hoc lane plan — which of 3 parallel worktrees would COLLIDE, before a line is written. JSON on stdout.")
add(S4, f"{BIN} . --plan-lanes --brief={brief_path}", "NEW VERB, explicit form: one line per lane, lane boundaries are the ones you wrote (the defensible mode).", pre=f"cat {brief_path}")
add(S4, f"{BIN} . --plan-lanes=99 --task=x", "Out-of-range refusal shape for the lane count.")
add(S4, f"{BIN} . --layout=Symbol", "CPU/GPU contract view of one struct: computed offsets/sizes/padding + mirror check.")
add(S4, f"{BIN} . --layout=Lang", "The honest-degrade case: Lang is an `enum class`, not a struct.")
add(S4, f"{BIN} . --doc-drift", "Which of this repo's doc claims are now false. CHANGED: row attribute at= renamed to tgt= (at= is now only the root sha stamp).", timeout=600)
add(S4, f"{BIN} . --doc-drift --gateability", "The finishable to-do list: docs whose LIVE failing anchors a date-stamp would reclassify.", timeout=600,
    post=f"{BIN} . --doc-drift --gateability 2>/dev/null | grep -o '<gateability.*' | sed 's/></>\\n</g' | head -25",
    post_label="Tail of the same output — the `<gateability>` section:")
add(S4, f"{BIN} . --doc-drift --with-history", "Same report, with git history splitting stale mentions into deleted-by-commit vs never-existed.", timeout=600)
add(S4, f"{BIN} . --from-trace=-", "Map a pasted stack trace onto indexed symbols. CHANGED: in_corpus= now reports the real count (was 0).", stdin=trace_path, pre=f"cat {trace_path}")
add(S4, f"{BIN} . --notes", "List all field notes (write-side memory) — the committed .ripwire_notes at the repo root, each with the sha/branch it was recorded at.")
add(S4, f'{BIN} . --pack-task="add a new output format flag to the CLI"', "ONE budget-shared bundle: ranking + top bodies + caller sigs + notes + tests_to_run. CHANGED: <d> rows now carry n=/id=.")
add(S4, f'{BIN} . --pack-task="add a new output format flag to the CLI" --partition=3', "Fan-out form: one shared core + 3 per-agent slices carved along call-graph communities.")
add(S4, f'{BIN} . --for="pagerank power iteration" --with-graph', "Task lens + a compact Mermaid flowchart of the top anchors' 1-hop edges.")
add(S4, f"{BIN} . --export=cc.json:{cc_out}", "Per-file metrics as CodeCharta cc.json.", post=f"wc -c {cc_out} && head -c 400 {cc_out}")
add(S4, f"{BIN} . --batch={batch_path}", "One-turn sweep: 4 newline-delimited verb:arg sub-queries answered in ONE deduped <batch>.", pre=f"cat {batch_path}")

S5 = "self-diagnosis"
add(S5, f"{BIN} . --doctor", "Environment self-check: binary staleness, grammars, cache dir, git, tracked-binary staleness.")

S6 = "security"
add(S6, f"{BIN} --scan-skill=skills/ripwire-orient/SKILL.md", "Scan a single skill file for injection/exfiltration patterns before installing.")
add(S6, f"{BIN} --scan-skills=skills", "Scan a whole skills directory (exit 2 = CRITICAL, 1 = WARN). Explicit-DIR form only.")

S7 = "knobs / modes"
add(S7, f"{BIN} . --rank-by=churn --top-k=5", "Rank by git change-frequency prior instead of PageRank.")
add(S7, f"{BIN} . --rank-by=bogus --top-k=5", "CHANGED: an unknown value is now NAMED, with the supported set listed.")
add(S7, f"{BIN} . --callers=rankGraphTeleport --format=columnar", "Columnar output: paths table + parallel arrays, ~15-60% fewer tokens on MANY-row lists — small results can be LARGER (the columnar legend is a fixed cost).")
add(S7, f'{BIN} . --for="cache invalidation" --format=candidates --top-k=5', "Flat top-K export for an external reranker.")
add(S7, f"{BIN} . --callers=rankGraphTeleport --format=bogus", "CHANGED: unknown --format value named + supported set listed.")
add(S7, f"{BIN} . --callers=rankGraphTeleport --json", "Machine-parseable JSON, same content, keys mirror the XML attrs.")
add(S7, f"{BIN} . --hotspots --json", "JSON refusal shape: an unsupported verb refuses loudly instead of silently falling back to XML.")
add(S7, f"{BIN} . --hotspots --limit=3 --offset=3", "Pagination: 3 items, skipping the first 3 (deterministic seams).")
add(S7, f"{BIN} . --ignore-tests --top-k=5", "Drop test paths from the corpus before ranking.")
add(S7, f"{BIN} . --exclude=present --exclude=bench --top-k=5", "Drop matching paths (repeatable) before ranking.")
add(S7, f"{BIN} . --map-diff --top-k=5", onTree(
    "Full map re-ranked with teleport toward git-changed files — clean tree, so changed=0 and it degrades to the plain map.",
    "Full map re-ranked with teleport toward git-changed files — recorded against a DIRTY tree, so changed= counts the working copy's files and the teleport is live."))
add(S7, f"{BIN} . --no-cache --top-k=3", "Force a cold parse (bypass the warm TMPDIR cache) — shows the cold-vs-warm cost.", timeout=600)
add(S7, f"{BIN} . --cache={cache_out} --top-k=3", "Explicit incremental cache at a path OUTSIDE the repo (first call writes it).", post=f"wc -c {cache_out}")
add(S7, f"{BIN} . --max-file-size=8K --top-k=3", "Skip files above a size bound before parsing (note the corpus shrink in the header).")
add(S7, f"{BIN} . --scip=does_not_exist.scip --callers=rankGraphTeleport", "SCIP overlay with a missing index: degrades to name-based, never fails.")
add(S7, f"{BIN} src test --top-k=5", "Multi-root workspace: ONE merged graph over two roots, paths labeled <root>/<rel>.")
add(S7, f"{BIN} . --eval", "Self-eval: co-change recall vs BM25.", timeout=900)
add(S7, f"{BIN} . --eval-retrieval", "Known-item retrieval eval: MRR + recall@k per ranker per query mode.", timeout=900)
add(S7, f"{BIN} . --eval-stray={stray_tsv_path}", "Labelled verdict-accuracy eval for --stray-content — three labels over REAL local refs (names resolved at capture time). Read got= against v= in the stray-content run: a ref the verb could not analyse (unknown) must never be credited as a merged hit.", timeout=900, pre=f"cat {stray_tsv_path}")
add(S7, f"{BIN} skills --eval-skills={skills_tsv_path}", "Labelled skill-ROUTING eval over the repo's own skills/ directory (4 hand-labelled prompts).", timeout=600, pre=f"cat {skills_tsv_path}")
add(S7, f"{BIN} wrap claude", "Print the recipe to wire ripwire into Claude Code as an MCP server.")
add(S7, f"{BIN} --version", "Version + short build info.")


S2B = "navigate — seeds, claims, slices, shapes"
add(S2B, f"{BIN} . --at=src/graph.h:1148", "Hold a LOCATION, not a name: the enclosing-definition chain at FILE:LINE (a compiler error, a diff hunk, a stack frame), outermost -> innermost.")
add(S2B, f"{BIN} . --callers=@src/graph.h:1148", "The same seed in a SELECTOR position: @FILE:LINE resolves to the innermost enclosing definition, then --callers runs on it.")
add(S2B, f"{BIN} . --at=src/graph.h:999999", "A seed past the end of the file — the refusal shape for a faulted location.")
add(S2B, f'{BIN} . --verify="calls(runDefaultMap, rankGraphTeleport)"', "VERIFY a closed claim in one call: three-valued verdict (confirmed / refuted / not-established) with the evidence rows inline.")
add(S2B, f'{BIN} . --verify="unused(rankGraphTeleport)"', "A claim that is FALSE — the refuted shape, with the references that refute it.")
add(S2B, f'{BIN} . --verify="contains(src/graph.h, \\"no such literal anywhere\\")"', "A literal-scan absence: refuted only with complete= evidence, never on a partial scan.")
add(S2B, f'{BIN} . --verify="frobnicate(x)"', "An unparseable claim — the refusal names the accepted shapes.")
add(S2B, f"{BIN} . --slice=rankGraphTeleport", "Bare --slice=SYM: the INVENTORY of sliceable locals (<v n= l= t=/>), so a caller can pick VAR.")
add(S2B, f"{BIN} . --slice=rankGraphTeleport:teleport", "Intra-procedural def-use slice of ONE variable: one <s> row per line touching it, k=def|use|both, reaching definitions flow-sensitive (reach=cfg).")
add(S2B, f"{BIN} . --slice=rankGraphTeleport:teleport --slice-flow=back --slice-depth=3", "TRANSITIVE backward value-flow from the seed variable, bounded BFS (depth= disclosed; a cut frontier says flow_truncated=1).")
add(S2B, f"{BIN} . --slice=rankGraphTeleport:teleport --slice-flow=fwd", "Forward flow: which statements the seed's value reaches, at the default depth bound.")
add(S2B, f"{BIN} . --slice=rankGraphTeleport:nosuchvar", "A variable the definition does not bind — the refusal shape, naming the inventory.")
add(S2B, f"{BIN} . --slice-depth=3", "--slice-depth without --slice-flow is refused loudly rather than silently ignored.")
add(S2B, f"{BIN} . --slice=rankGraphTeleport:teleport --legend=compact", "The compact legend posture: rows byte-identical, a versioned schema id replaces the repeated explanatory prose — for a many-small-calls loop.")
add(S2B, f"{BIN} . --pattern='rankGraphTeleport($A, $B, $C)'", "Structural search written in CODE: $NAME binds one node; grammars=/shapes= disclose what the pattern became per grammar (a 3-argument call shape — the 2-argument spelling has no call site in this repo and correctly reports hits=0).")
add(S2B, f"{BIN} . --pattern='DEGRADED_PATH_ALERT(...)'", "The ellipsis form over a macro-shaped call site; unsupported= names the families this verb does not serve.")
add(S2B, f"{BIN} . --pattern='x'", "A pattern that collapses to a bare token is REFUSED — never reported as hits=0.")
add(S2B, f"{BIN} . --grep=DEGRADED_PATH_ALERT --and=cache", "Boolean grep: hits where BOTH literals share the matched line (--grep-scope=line is the default).")
add(S2B, f"{BIN} . --grep=DEGRADED_PATH_ALERT --not=test --grep-scope=file", "Drop every hit in a file that ALSO contains the --not literal anywhere (file scope).")
add(S2B, f"{BIN} . --grep=DEGRADED_PATH_ALERT --grep=cache", "A second --grep= REFUSES and names --and= as the AND spelling — no silent overwrite.")
add(S2B, f"{BIN} . --grep=DEGRADED_PATH_ALERT --grep-in=any", "Span tiers off: the exhaustive view — the comment and string hits the default tier held back (suppressed_comment=96 / suppressed_string=29 in the plain --grep block above) now print alongside the code hits; hits= grows accordingly.")
add(S2B, f"{BIN} . --grep=deterministic", "A literal whose classified hits are all prose: the answer serves tier=\"comment+string\" rather than an empty code tier, and tier_unclassified= says how many hits the fixed parse budget never classified.")
add(S2B, f"{BIN} . --grep=DEGRADED_PATH_ALERT --handles", "h= on each editable enclosing-symbol row: a freshness-pinned identity an edit verb can target and must refuse on after any file change.")
add(S2B, f"{BIN} . --grep=DEGRADED_PATH_ALERT --legend=compact", "The grep compact legend (ripwire.grep/v1).")
add(S2B, f'{BIN} . --for="tree-sitter parse of a source file" --legend=compact', "The --for compact legend (ripwire.for/v1) — every data/completeness attribute kept.")
add(S2B, f'{BIN} . --for="tree-sitter parse of a source file" --auto-bodies', "Opt OUT of compact conceptual serving: restore the rank-first auto <bodies> walk (bundle=\"auto\").")
add(S2B, f'{BIN} . --for="quality delta acks ledger rubber stamp"', "Doc-mention surfacing (default ON): a markdown doc naming a top-resolved symbol in a backtick rides in below that symbol — the legend's [doc mentions: …] clause says it fired.")
add(S2B, f'{BIN} . --for="quality delta acks ledger rubber stamp" --no-doc-mention', "The same task with doc-mention surfacing OFF — the contrast the flag exists for (no [doc mentions] clause, one fewer row).")
add(S2B, f"{BIN} . --safe-delete=rankGraphTeleport", "\"Can I delete this?\" — callers + transitive impact + every use site + how much of the radius is tested, composed in ONE call; risk= names what was found, never a verdict.")
add(S2B, f"{BIN} . --safe-delete=DoesNotExist", "Unknown-symbol refusal shape for --safe-delete.")
add(S2B, f"{BIN} . --handoff", "The continuation packet for the NEXT session: <verified> disk truth (branch/sha, changed symbols, blast radius, tests) + <heuristic> labeled suggestions. Recorded against " + TREE + ".")
add(S2B, f"{BIN} . --handoff --token-budget=1200", "The same packet under a hard ceiling: heuristic rows drop tail-first (withheld= disclosed), verified rows never drop.")
add(S2B, f"{BIN} . --skipped", "WHY a file is not in the index (oversize / excluded / unsupported-ext / gitignored) and which indexed files it cannot vouch for (degraded-parse, minified-suspect), plus the per-language census.")
add(S2B, f"{BIN} . --no-ignore --top-k=3", "Crawl paths the repo's own .gitignore covers (default honours it and discloses ignored_files=/ignored_dirs= only when it dropped anything — this repo's crawl drops nothing, so the header is identical to the default map's; --skipped's ignore_mode= says which rule applied).")
add(S2B, f"{BIN} . --no-stable --top-k=3", "--no-stable outside --mcp: what the flag does (or says) when there is no stable-by-default ordering to opt out of.")
add(S2B, f'{BIN} . --run-trace="cat {trace_path}; exit 1"', "EXEC-MODE --from-trace: run a command, and on a non-zero exit map its captured output onto indexed symbols in the same call — the whole fix-loop entry.")
add(S2B, f'{BIN} . --run-trace="true"', "A command that exits 0: a minimal success record (exit, measured duration, disclosed output tail) and NO bundle — nothing failed, nothing to map.")
add(S2B, f'{BIN} . --run-trace="sleep 30" --run-timeout=2', "A command still running at the cap: its process group is killed and the run reports timed_out=1 — an honest timeout, never an empty success.", timeout=120)
add(S2B, f"{BIN} . --run-timeout=5", "--run-timeout alone is refused loudly (it only modifies --run-trace).")

S4B = "assess quality — the wider lens family"
add(S4B, f"{BIN} . --quality-panel", "THE single wide-angle quality read: six families in one pass, an eligible/ranked shortlist rather than a firehose.", timeout=600)
add(S4B, f"{BIN} . --readability --limit=8", "Per-function readability, LEAST readable first (Halstead volume, token entropy, lines, Posnett) — a RANKING lens, not a grade.")
add(S4B, f"{BIN} . --comment-coherence --limit=8", "Functions WITH a doc comment, most name-restating first: c_coeff (high = the comment repeats the name) and cic (Jaccard of comment vs identifier vocabulary), both reported, never collapsed.")
add(S4B, f"{BIN} . --context-ratio --limit=8", "The local-reasoning lens: to understand this symbol, how much must you know that is NOT in front of you (ent_ratio= edge share, read_ratio= token-weighted).")
add(S4B, f"{BIN} . --nonlocal-state --limit=8", "Per function, the non-local MUTABLE state it can reach (transitively), most writes first — unsound by construction, and the legend says where.")
add(S4B, f"{BIN} . --ensemble --limit=8", "The family join: per function, which of four orthogonal evidence families fire, ranked by how many agree.")
add(S4B, f"{BIN} . --field-affinity", "The cache-locality lens over every aggregate: fields READ TOGETHER but declared FAR APART (split-line / straddle findings, Chilimbi separation weight) — advice only, never a rewrite.", timeout=600)
add(S4B, f"{BIN} . --field-affinity=Symbol", "The same lens narrowed to ONE struct — the one --layout=Symbol shows the offsets for.")
add(S4B, f"{BIN} . --naming-consistency --limit=8", "The corpus's OWN case-convention vote per (language, kind) group; off-convention names get a mechanical propose= (a suggestion, never a blind rename).")
add(S4B, f"{BIN} . --naming-calibration", "Score the naming-* rules against this repo's own rename history: proxy=old/(old+new) per rule, 0.50 = chance; read pairs= (sample size) first.", timeout=600)
add(S4B, f"{BIN} . --lint --naming-locals", "The opt-in --lint modifier: naming predicates over LOCAL variable names too, C/C++ only, only inside functions already past a size/complexity gate.")
add(S4B, f"{BIN} . --lint-catalog", "The built-in rule registry — one row per rule with sev=/category=/rationale/lang=/since=; no corpus needed.")
add(S4B, f"{BIN} . --lint --lint-select=cache-", "Run ONLY one rule family; the root carries selected=\"K of N\" so a filtered zero is never confusable with an unfiltered one.")
add(S4B, f"{BIN} . --lint --lint-ignore=naming-,cache-", "DROP two families, applied after selection; the raw select=/ignore= you passed rides on the root.")
add(S4B, f"{BIN} . --lint --lint-select=cach-", "An unresolvable PREFIX refuses (exit 1) with a did-you-mean from a real edit distance (one character off cache-).")
add(S4B, f"{BIN} . --lint --lint-select=nosuchfamily", "A PREFIX with no near miss at all: the refusal points at --lint-catalog instead of guessing.")
add(S4B, f"{BIN} . --lint --sarif", "The SAME findings as SARIF 2.1.0 (what github/codeql-action/upload-sarif consumes) — pure re-serialization, results count == the native run's.",
    post=f"{BIN} . --lint --sarif 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); r=d[\"runs\"][0]; print(\"sarif\", d[\"version\"], \"rules=\", len(r[\"tool\"][\"driver\"][\"rules\"]), \"results=\", len(r[\"results\"]))'",
    post_label="Parsed summary of the same SARIF (past the display cut):")
add(S4B, f"{BIN} . --lint --sarif --limit=5", "SARIF is always the FULL result set: paging alongside it refuses loudly.")
add(S4B, f"{BIN} . --dmm", "The Delta Maintainability Model scalar for the WORKING TREE vs HEAD — recorded against " + TREE + " (the sandbox section shows a real delta). UNAVAILABLE is a stated reason, never 0 or 1.")
add(S4B, f"{BIN} . --dmm=HEAD", "The per-commit scalar: HEAD vs its first parent, with the three separately actionable sub-scores.", timeout=600)
add(S4B, f"{BIN} . --dmm=HEAD~3..HEAD", "The range form: tree HEAD vs tree HEAD~3.", timeout=600)
add(S4B, f"{BIN} . --cochange --cochange-groups", "Modularity-violation GROUPS instead of pairs: \"X co-changes with {A,B,C}, none of which it depends on\" — a greedy cover, disclosed as greedy.", timeout=600)
add(S4B, f"{BIN} . --cochange --cochange-recur=2", "Only pairs whose co-change RECURS in 2+ sub-windows of the mined window (sub_windows= is the denominator) — a one-off sprint stops reading like a structural defect.", timeout=600)
add(S4B, f"{BIN} . --html={html_out} --color-by=community", "The HTML graph with the initial colour mode set to community (the page embeds all five modes and keeps a live selector).", post=f"wc -c {html_out}")
add(S4B, f"{BIN} . --index-out={idx_out}", "CI generate-and-exit: cold-parse and write BOTH committable cache families (lean + rich), no map on stdout.", timeout=600,
    post=f"wc -c {idx_out}.lean.ripwirecache {idx_out}.rich.ripwirecache")   # sizes only — an `ls -l` here leaked the owner column into the public capture (ripwirepubliccheck arm 5)
add(S4B, f"{BIN} . --cache={idx_out}.lean.ripwirecache --top-k=3", "Consume the lean artifact in a PR job: restore-equivalence, never blob-byte-identity.")
add(S4B, f"{BIN} . --pin-census={census_out} --top-k=3", "Eval-only: a per-call-site census of WHICH mechanism resolved each call, and the canonical id of every surviving target.", post=f"head -8 {census_out}; wc -l {census_out}")
add(S4B, f"{BIN} . --plan-lint=test/planlintfix/wave.md", "The house PLAN/DESIGN format's STRUCTURE check — never semantics.")
add(S4B, f"{BIN} . --plan-lint=test/planlintfix/wave_ledger.md", "The ledger-shaped fixture through the same check.")
add(S4B, f"{BIN} . --doctor --agent=claude", "--doctor plus a LIVE integration inspection for one agent: PATH binary, installed-skill manifest parity, hook executability, MCP wiring — read-only, fixed repair commands, never config contents.")
add(S4B, f"{BIN} . --doctor --agent=nosuch", "Other --agent values refuse.")

# --- the sandbox clone: verbs that need a DIRTY tree -------------------
S8 = "the dirty-tree verbs (throwaway clone, NOT the read-only repo)"
D = ABIN
add(S8, f"{D} . --situ", "Situational report for a real diff: blast radius + tests + co-change + forgotten co-change partners.", cwd=DIRTY)
add(S8, f"{D} . --test-gate", "The pre-PR gate with real obligations — exit 4 when tests-to-run or untested blast radius is non-empty.", cwd=DIRTY)
add(S8, f"{D} . --quality-delta", "CHANGED: every row now carries p=\"file:line\", the gating rows are marked gating=\"1\", and exit 2 prints a naming line on stderr.", cwd=DIRTY)
add(S8, f"{D} . --quality-delta --json", "The same findings as JSON (one of the CI/scripting verbs --json supports).", cwd=DIRTY)
add(S8, f"{D} . --quality-delta --quality-ack --ack-only=zzznope", "NEW FLAG: --ack-only matching nothing REFUSES rather than falling back to acking everything.", cwd=DIRTY)
add(S8, f"{D} . --quality-delta --quality-ack --ack-only=api-surface", "NEW FLAG: ack only the api-surface findings — a per-finding ratchet instead of a rubber stamp.", cwd=DIRTY)
add(S8, f"{D} . --quality-delta", "Re-run after the partial ack: acked=3, the rest still gate.", cwd=DIRTY)
add(S8, f"{D} . --ack-only=gating", "--ack-only WITHOUT --quality-ack REFUSES loudly (exit 1, the pairing named) — it used to be silently ignored.", cwd=DIRTY)
add(S8, f"{D} . --edit-check=nonNegativeFloatDescKey", "A real contract-change: was=1 now=2 params, with the call sites that are now provably incompatible.", cwd=DIRTY)
add(S8, f"{D} . --pr-context", "The review-evidence bundle with an actual changed file.", cwd=DIRTY)
add(S8, f"{D} . --map-diff --top-k=5", "The map re-ranked with a teleport toward the changed file (changed=1 here, not 0).", cwd=DIRTY)
add(S8, f"{D} . --clones", "The duplicated helper the sandbox edit introduced shows up as a clone group.", cwd=DIRTY)
add(S8, f"{D} . --stray-content=zz-orphan", "CHANGED: a ref with NO merge base with HEAD now reports v=\"unknown\" ok=\"0\" in its own bucket — the absence of an answer, never a claim it is merged. (The sandbox carries a deliberately parentless branch built with `git commit-tree`; a shallow CI clone puts every ref here.)", cwd=DIRTY, timeout=600)
add(S8, f"{D} . --stray-content=zz-orphan --plan", "CHANGED: --plan surfaces those same refs as an <undetermined> row rather than silently dropping them.", cwd=DIRTY, timeout=600)
add(S8, f"{D} . --dmm", "The DMM scalar on a REAL delta: the sandbox edit grew one unit past the nesting/complexity thresholds and added an 8-parameter one, so dmm is low and the three sub-scores say which property moved.", cwd=DIRTY)
add(S8, f"{D} . --quality-delta --scope=src/graph.h", "OWNERSHIP partition for a shared tree: every regression here lives in src/infra/, so under a scope naming src/graph.h they ALL print under <out-of-scope> with a do-not-ack banner and never gate — scoped-out-gating= says how many would have.", cwd=DIRTY)
add(S8, f"{D} . --quality-delta --quality-ack --scope=src/graph.h --ack-only=api-surface", "The rubber-stamp guard: an --ack-only that names an OUT-OF-SCOPE row refuses (exit 1) and writes nothing.", cwd=DIRTY)
add(S8, f"{D} . --handoff", "The continuation packet with a REAL diff: verified changed symbols + blast radius + tests-to-run, then the heuristic rows.", cwd=DIRTY)
add(S8, f'{D} . --note-add="lessByScoreDescId: keep this branch-free — it sits inside the PageRank sort comparator"', "Pin a field note (write-side memory) to a symbol; committed to .ripwire_notes in the sandbox. The BARE name is resolved through the same resolver the read verbs use and stored as the canonical id — the rewrite is echoed on stderr, because a silent one is not a disclosure.", cwd=DIRTY)
add(S8, f"{D} . --notes", "The note is listed under the canonical id, dangling=\"0\" — i.e. it will actually surface. (Before the H1 fix the bare name was stored verbatim and read dangling=\"1\": recorded, and surfaced nowhere.)", cwd=DIRTY)
add(S8, f'{D} . --note-add="gitOneLine: which one?"', "Two definitions carry this name, so the write REFUSES rather than pick one: a note keys ONE canonical id, and an ambiguous selector is refused, never silently narrowed. Every candidate is named, with a runnable retry.", cwd=DIRTY)
add(S8, f'{D} . --note-add="lessByScoreDescIdd: typo"', "A name that resolves to nothing is refused with the read verbs' own did-you-mean — never written as a dead note.", cwd=DIRTY)
add(S8, f'{D} . --note-add="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId: chose the flat two-branch compare over the nested ladder because the comparator sits inside the PageRank sort"', "The same symbol addressed by its CANONICAL id: already canonical, so nothing is rewritten and both notes land on ONE target.", cwd=DIRTY)
add(S8, f"{D} . --expand=lessByScoreDescId --top-k=0", "Both notes riding along with the symbol's body — the <note> elements follow the body, past the display cut, so they are extracted below.", cwd=DIRTY,
    post=f"{D} . --expand=lessByScoreDescId --top-k=0 2>/dev/null | sed 's/></>\\n</g' | grep -A2 '<note'", post_label="The <note> element on the same output — past the 30-line display cut above:")
add(S8, f"{D} . --replace-symbol-body=lessByScoreDescId --edit-payload={empty_payload_path}", "An EMPTY payload refuses — it never implies deletion.", cwd=DIRTY)
add(S8, f"{D} . --replace-symbol-body=lessByScoreDescId --edit-payload={payload_less_path}", "Whole-symbol replace without a whole-file read: the payload is the ORIGINAL flat body, so this edit undoes the sandbox's deep-nesting regression. The receipt's span is the POST-edit byte range; replaced_bytes counts the old bytes overwritten.", cwd=DIRTY, pre=f"cat {payload_less_path}")
add(S8, f"{D} . --edit-check=lessByScoreDescId", "The closed loop: contract unchanged (same params, same publicness) after the replace — nothing provably incompatible.", cwd=DIRTY)
add(S8, f"{D} . --insert-after-symbol=lessByScoreDescId --edit-payload={payload_note_path}", "Insert immediately AFTER one uniquely-resolved definition; replaced_bytes=0 because the insert verbs never overwrite. The receipt carries the folded post-edit verification (lines=, edit_check, tests_to_run) so the loop closes in one call.", cwd=DIRTY)
add(S8, f"{D} . --insert-after-symbol=lessByScoreDescId --edit-payload={payload_note_path} --no-post-check", "The opt-out: the same insert with the folded verification skipped — lines= still rides (it is free), edit_check/tests_to_run do not, and the two pasteable commands stay on stderr.", cwd=DIRTY)
add(S8, f"{D} . --insert-before-symbol=nonNegativeFloatDescKey --edit-payload={payload_note_path} --edit-target-file=src/infra/sortutil.h", "Insert BEFORE, with --edit-target-file pinning which same-named definition (here unambiguous — the disambiguator is simply honoured).", cwd=DIRTY)
add(S8, f"{D} . --replace-symbol-body=DoesNotExist --edit-payload={payload_note_path}", "An unknown TARGET refuses and leaves every file byte-identical.", cwd=DIRTY)
add(S8, f"{D} . --edit-plan={edit_plan_path} --dry-run", "A versioned multi-edit TRANSACTION preflighted without writing: the receipt shows what each op would read and touch.", cwd=DIRTY, pre=f"cat {edit_plan_path}")
add(S8, f"{D} . --edit-plan={edit_plan_path} --apply", "The same plan committed: per-file locks, re-verify-before-write, atomic rename, rollback on a later failure.", cwd=DIRTY)
add(S8, f"{D} . --edit-plan={edit_plan_path}", "Neither --dry-run nor --apply: the mode is explicit, so this refuses.", cwd=DIRTY)
add(S8, f"{D} . --quality-delta", "After the agent's edits: the complexity/nesting rows on lessByScoreDescId are gone (the replace undid them), the rest still gate.", cwd=DIRTY)
add(S8, f"{D} . --quality-baseline", "REFUSES, exit 1: this sandbox tree is already regressed, and pinning here would swallow that debt into the floor so every later delta read clean. It names how many gating findings it would absorb, the first of them, and the way forward.", cwd=DIRTY)
add(S8, f"{D} . --quality-baseline --allow-dirty", "The consent form: pin anyway. The sidecar is stamped with the dirty pin and the absorbed count, so the fact outlives the process that knew it.", cwd=DIRTY, post="wc -c .ripwire_quality_baseline && head -c 300 .ripwire_quality_baseline")
add(S8, f"{D} . --quality-delta", "Against that sidecar the same tree reads regressions=0 — but baseline_absorbed= is on the root, so this green means clean SINCE THE PIN, never clean. A baseline is a floor YOU chose, and it belongs BEFORE the change.", cwd=DIRTY)

S9 = "the MCP dialect — the same verbs over stdio JSON-RPC (one-shot exchange, not a persistent server)"
add(S9, mcp(MCP_INIT, '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'), "initialize + tools/list: the manifest an agent host loads at session start — every verb's name, description and input schema.",
    post=mcp(MCP_INIT, '{"jsonrpc":"2.0","id":2,"method":"tools/list"}') + f" | tail -1 | python3 {manifest_py}",
    post_label="The manifest, summarised (name / description bytes / required args) — what the host pays in context every session:")
add(S9, mcp(MCP_INIT, mcp_call("for", task="pagerank power iteration")), "MCP `for`: always bundle=sigs (never the CLI's compact route), the same ranked signatures as --for.")
add(S9, mcp(MCP_INIT, mcp_call("explore", task="add a new output format flag to the CLI", budget_tokens=2000)), "MCP `explore` = --pack-task under a token budget, one call.")
add(S9, mcp(MCP_INIT, mcp_call("fetch_body", handle="rankGraphTeleport")), "MCP `fetch_body`: the lazy-body handle posture — bodies only after ranked retrieval, by bare name here.")
add(S9, mcp(MCP_INIT, mcp_call("grep", pattern="DEGRADED_PATH_ALERT", limit=3)), "MCP `grep` with paging args.")
add(S9, mcp(MCP_INIT, mcp_call("slice", symbol="rankGraphTeleport", var="teleport", flow="back", depth=3)), "MCP `slice` — the CLI's --slice/--slice-flow/--slice-depth as one verb.")
add(S9, mcp(MCP_INIT, mcp_call("find_symbol", symbol="DoesNotExist")), "MCP error shape: an unknown symbol comes back as a JSON-RPC error/refusal, not an empty success.")
add(S9, mcp(MCP_INIT, mcp_call("batch", queries=[{"verb": "for", "task": "incremental cache invalidation"}, {"verb": "find_referencing_symbols", "symbol": "rankGraphTeleport"}, {"verb": "grep", "pattern": "DEGRADED_PATH_ALERT", "limit": 2}])), "MCP `batch`: three independent read queries answered in ONE round-trip — NOTE the sub-query grammar is {verb, ...args} objects with MCP verb names, not the CLI --batch file's verb:arg lines.")
add(S9, mcp(MCP_INIT, mcp_call("batch", queries=["for:incremental cache invalidation", "callers:rankGraphTeleport"])), "The CLI --batch spelling handed to MCP `batch`: refused, with the accepted shape named.")
add(S9, mcp(MCP_INIT, mcp_call("edit_check", symbol="rankGraphTeleport")), "MCP `edit_check` on " + TREE + ".")
add(S9, mcp(MCP_INIT, '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"nosuchverb","arguments":{"path":"."}}}'), "An unknown verb name — the JSON-RPC error shape.")

# --- build the sandbox clone (was hand-built in the 07-27 round; folded in so
# --- regeneration stays ONE command). git clone --local + ONE deliberate
# --- regression in src/infra/sortutil.h carrying four shapes: a preexisting fn made
# --- deeply nested, an arity change 1 -> 2, a copy-paste duplicate helper, a
# --- new 8-parameter public fn. Plus a parentless zz-orphan-lane branch
# --- (git commit-tree) feeding --stray-content's no-merge-base bucket.
def mustReplace( text, old, new, what ):
    n = text.count( old )
    if n != 1:
        print( f"FATAL: sandbox edit anchor for '{what}' found {n}x (expected 1) — src/infra/sortutil.h drifted; update the anchors in showcase_capture.py", file=sys.stderr )
        sys.exit( 1 )
    return text.replace( old, new )

if os.path.isdir( DIRTY ):
    shutil.rmtree( DIRTY )
subprocess.run( [ "git", "clone", "--local", "--quiet", REPO, DIRTY ], check=True )
subprocess.run( "git branch zz-orphan-lane $(git commit-tree 'HEAD^{tree}' -m 'zz-orphan-lane: parentless probe branch for the no-merge-base bucket')",
                shell=True, cwd=DIRTY, check=True )

sortutil_path = os.path.join( DIRTY, "src", "infra", "sortutil.h" )
src = open( sortutil_path ).read()

OLD_LESS = """inline bool lessByScoreDescId( const std::vector<float>& scores, std::uint32_t a, std::uint32_t b ) noexcept
{
    if( scores[a] != scores[b] )
    {
        return scores[a] > scores[b];
    }
    return a < b;
}"""
NEW_LESS = """inline bool lessByScoreDescId( const std::vector<float>& scores, std::uint32_t a, std::uint32_t b ) noexcept
{
    if( a < scores.size() )
    {
        if( b < scores.size() )
        {
            if( scores[ a ] != scores[ b ] )
            {
                if( scores[ a ] > scores[ b ] )
                {
                    if( scores[ a ] > 0.0f && scores[ b ] > 0.0f ) return true;
                    else if( scores[ a ] > 0.0f && scores[ b ] == 0.0f ) return true;
                    else if( scores[ a ] == 0.0f || scores[ b ] == 0.0f ) return true;
                    else return true;
                }
                else
                {
                    if( scores[ b ] > 0.0f && scores[ a ] > 0.0f ) return false;
                    else if( scores[ b ] > 0.0f && scores[ a ] == 0.0f ) return false;
                    else if( scores[ b ] == 0.0f || scores[ a ] == 0.0f ) return false;
                    else return false;
                }
            }
            else
            {
                if( a != b )
                {
                    if( a < b )
                    {
                        if( scores[ a ] >= 0.0f || scores[ b ] >= 0.0f ) return true;
                        else return true;
                    }
                    else
                    {
                        if( scores[ b ] >= 0.0f || scores[ a ] >= 0.0f ) return false;
                        else return false;
                    }
                }
                else return false;
            }
        }
        else if( a < b || scores[ a ] >= 0.0f ) return true;
        else return false;
    }
    else if( b < scores.size() && a < b ) return true;
    else return a < b;
}"""
src = mustReplace( src, OLD_LESS, NEW_LESS, "lessByScoreDescId deep-nesting" )
open( payload_less_path, "w" ).write( OLD_LESS + "\n" )   # the edit-verb demo restores the flat original

OLD_DESC = """inline std::uint32_t nonNegativeFloatDescKey( float value ) noexcept
{
    std::uint32_t bits = std::bit_cast<std::uint32_t>( value );
    if( ( bits & 0x7fffffffu ) == 0u )
    {
        bits = 0u;   // bitwise normalization survives the global no-signed-zeros fast-math contract
    }
    return ~bits;
}"""
NEW_DESC = """inline std::uint32_t nonNegativeFloatDescKey( float value, bool flushDenormals ) noexcept
{
    std::uint32_t bits = std::bit_cast<std::uint32_t>( value );
    if( ( bits & 0x7fffffffu ) == 0u )
        bits = 0u;   // bitwise normalization survives the global no-signed-zeros fast-math contract
    if( flushDenormals && ( bits & 0x7f800000u ) == 0u )
        bits = 0u;
    return ~bits;
}

inline std::uint32_t nonNegativeFloatAscKeyCopy( float value, bool flushDenormals ) noexcept
{
    std::uint32_t bits = std::bit_cast<std::uint32_t>( value );
    if( ( bits & 0x7fffffffu ) == 0u )
        bits = 0u;   // bitwise normalization survives the global no-signed-zeros fast-math contract
    if( flushDenormals && ( bits & 0x7f800000u ) == 0u )
        bits = 0u;
    return ~bits;
}

inline void sortScoredIdsWithOptions( std::vector<std::uint32_t>& order, const std::vector<float>& scores, std::vector<std::uint32_t>& scratch,
                                      bool descending, bool stableTies, bool flushDenormals, std::uint32_t idFloor, std::uint32_t idCeiling )
{
    ( void ) descending; ( void ) stableTies; ( void ) flushDenormals; ( void ) idFloor; ( void ) idCeiling;
    radixSortByScoreDescId( order, scores, scratch );
}"""
src = mustReplace( src, OLD_DESC, NEW_DESC, "nonNegativeFloatDescKey arity + duplicate helper + 8-param fn" )
open( sortutil_path, "w" ).write( src )

# --- run ---------------------------------------------------------------
results = []
for i, c in enumerate(C):
    stdin_data = open(c["stdin"], "rb").read() if "stdin" in c else None
    wd = c.get("cwd", REPO)
    t0 = time.time()
    try:
        p = subprocess.run(c["cmd"], shell=True, cwd=wd, capture_output=True,
                           input=stdin_data, timeout=c.get("timeout", 300))
        out, err, rc = p.stdout, p.stderr, p.returncode
    except subprocess.TimeoutExpired as e:
        out = e.stdout or b""; err = (e.stderr or b"") + b"\n[TIMED OUT]"; rc = "timeout"
    dt = time.time() - t0
    post_out = ""
    if "post" in c:
        pp = subprocess.run(c["post"], shell=True, cwd=wd, capture_output=True)
        post_out = pp.stdout.decode("utf-8", "replace")
    pre_out = ""
    if "pre" in c:
        pp = subprocess.run(c["pre"], shell=True, cwd=wd, capture_output=True)
        pre_out = pp.stdout.decode("utf-8", "replace")
    results.append(dict(c=c, out=out, err=err, rc=rc, dt=dt, post=post_out, pre=pre_out))
    print(f"[{i+1}/{len(C)}] rc={rc} {dt:.2f}s  {c['cmd'][:100]}", file=sys.stderr)

# --- formatting --------------------------------------------------------
def explode(text):
    """Re-wrap minified single-line XML/JSON at tag seams for display (real output is one line)."""
    lines = []
    exploded = False
    for ln in text.split("\n"):
        if len(ln) > 300 and ln.lstrip().startswith("<"):
            lines.extend(ln.replace("><", ">\n<").split("\n"))
            exploded = True
        elif len(ln) > 300 and ln.lstrip().startswith("{"):
            lines.extend(ln.replace("},{", "},\n{").replace('],"', '],\n"').split("\n"))
            exploded = True
        else:
            lines.append(ln)
    return lines, exploded

def fmt_block(data):
    text = data.decode("utf-8", "replace").rstrip("\n")
    if not text:
        return "(empty)"
    total_bytes = len(data)
    raw_line_count = len(text.split("\n"))
    lines, exploded = explode(text)
    shown = lines
    marker = None
    if len(lines) > 40:
        shown = lines[:30]
        if exploded:
            marker = f"… [{len(lines)-30} more display lines; full output is {total_bytes} bytes on {raw_line_count} raw line(s)]"
        else:
            marker = f"… [{len(lines)-30} more lines, {total_bytes} bytes total]"
    out = []
    for ln in shown:
        # §B11.2: header COMMENTS are exempt from the 300-byte display cut — the preamble promises they
        # "appear in full", and the cut was truncating exactly the attribute-dictionary legends the capture
        # exists to expose (76 of 131 commands last round: quality-delta lost 1544 bytes, doc-drift 2221).
        # Ordinary long lines (row data) keep the cut; the preamble states both halves honestly.
        # §B12.10: the marker says "bytes" (see the preamble below) so the cut and the count must be BYTES,
        # not Python str CHARACTERS — len(ln)/ln[:300] on a str counts/slices codepoints, which undercounts
        # every multi-byte UTF-8 character (this file's own doc-comments use em-dashes and arrows). Cut the
        # UTF-8 ENCODING at 300 bytes, back off at most 3 bytes so a multi-byte sequence is never split, and
        # report the TRUE remaining byte count via wc-c-equivalent len() on bytes, not on the decoded str.
        ln_bytes = ln.encode("utf-8")
        if len(ln_bytes) > 300 and not ln.lstrip().startswith("<!--"):
            cut = ln_bytes[:300]
            for _ in range(4):
                try:
                    shown_text = cut.decode("utf-8")
                    break
                except UnicodeDecodeError:
                    cut = cut[:-1]
            else:
                shown_text = cut.decode("utf-8", "replace")
            out.append(shown_text + f" … [line truncated: {len(ln_bytes)-len(cut)} more bytes on this line]")
        else:
            out.append(ln)
    if marker:
        out.append(marker)
    return "\n".join(out)

ver = subprocess.run(f"{BIN} --version", shell=True, cwd=REPO, capture_output=True).stdout.decode().strip()
# §B11.5: the --help line count is DERIVED at generation time — the hardcoded "543 lines" went stale
# (live was 669) and a meta-claim about the binary must come from the binary.
help_line_count = len(subprocess.run(f"{BIN} --help", shell=True, cwd=REPO, capture_output=True).stdout.decode().splitlines())
sha = subprocess.run("git rev-parse --short HEAD", shell=True, cwd=REPO, capture_output=True).stdout.decode().strip()
# Same reading the captions branch on (REPO_DIRTY, taken at the top of the run) — one source of truth for
# the tree condition, so the header and the per-command captions cannot disagree about it.
dirty_note = ("CLEAN — `git status --porcelain` is empty" if not REPO_DIRTY else
              f"DIRTY — `git status --porcelain` reports {len(REPO_DIRTY_LINES.splitlines())} entr(ies)")
sandbox_diffstat = subprocess.run("git diff --stat", shell=True, cwd=DIRTY, capture_output=True).stdout.decode().strip()

doc = []
FENCE = "`````"  # 5 backticks: some outputs (--recall, --report) contain 3-backtick fences of their own
date = time.strftime("%Y-%m-%d")
doc.append("# ripwire — every verb, run for real\n")
doc.append(f"- **Date:** {date} (regenerated capture; supersedes any older `docs/captures/COMMANDS_showcase_*.md`)")
doc.append(f"- **Lives in `docs/captures/`** — a directory the crawl/retrieval lenses SKIP (`kCrawlSkipDirs`, src/ingest.h): a generated doc that quotes every verb's output out-scores the source for any query about the tool and was measured at 77% of `--recall` on this repo when it sat at the root. `test/argvdiffcheck.sh` harvests its `## `-heading command lines as differential vectors — keep that format.")
doc.append(f"- **Version:** `{ver}`")
doc.append(f"- **Repo:** the ripwire repo @ `{sha}` — **{dirty_note}**. The diff-aware verbs (`--situ`/`--test-gate`/`--quality-delta`/`--pr-context`/`--map-diff`/`--edit-check`) answer a question about the WORKING TREE, so that condition is part of their answer and every one of their captions below states which tree it recorded against. " + onTree("A clean tree is the honest default for a showcase, so they appear TWICE: once here on the clean tree (their empty/exit-0 shape) and once in the final section against a throwaway `git clone --local` sandbox carrying one deliberate regression, so their real gating shapes are visible without writing a byte into the read-only repo.", "This run recorded against a dirty tree, so their output here reflects uncommitted working-copy edits rather than the empty/exit-0 shape a clean checkout gives. They appear a SECOND time in the final section against a throwaway `git clone --local` sandbox carrying one KNOWN, deliberate regression — that is the reproducible gating demonstration; this one is whatever the tree happened to hold."))
doc.append(f"- **Corpus:** the ripwire repo itself (dogfood), via `./build/ripwire`")
doc.append(f"- **Sandbox diff** (the last section only): `{sandbox_diffstat}` — one preexisting function made deeply nested, one function's arity changed 1 -> 2, one copy-paste duplicate helper, one new 8-parameter public function.")
doc.append("")
doc.append("**How to read the blocks:** ripwire's real XML output is minified — often ONE long line. For scanability, long minified lines are displayed re-wrapped with a line break at every tag seam (`><`). Header COMMENT lines (the legends) always appear in full — they are exempt from the per-line cut; any OTHER display line over 300 bytes is cut with a `… [line truncated: N more bytes]` marker, which can hit a long root element or row. `--plan-lanes` emits JSON and is re-wrapped at object seams the same way. Long outputs are cut to their first ~30 display lines with a `… [N more display lines; full output is M bytes]` marker giving the true size. Exit codes are recorded when non-zero; wall time when >1s.")
doc.append("")
doc.append(f"**Not run (and why):** `ripwire <git-url>` (network clone), `--listen` / `--mcp-token` / `--allow-remote-edits` (the HTTP-server posture; `--mcp` itself IS captured in its own section as a one-shot stdio JSON-RPC exchange, and `wrap claude` shows the wiring), `--arch --baseline[-update]` (state writer against the read-only repo — `--note-add` / `--quality-baseline` / `--quality-ack` / the three edit verbs / `--edit-plan` ARE shown, inside the throwaway sandbox clone; `--index-out` / `--pin-census` write to scratch), `--eval-mined` (needs a `minedpair.jsonl` artifact from `bench/mine_traces.py`; none present in the tree), `--refetch` (git-url only), `--force` (wrap-only modifier), `--scan-skills` bare form (would sweep `~/.claude/skills`; the explicit-DIR form is shown instead), `--help` ({help_line_count} lines — read it from the binary).")
doc.append("")

cur_section = None
for r in results:
    c = r["c"]
    if c["section"] != cur_section:
        cur_section = c["section"]
        doc.append(f"\n---\n\n# {cur_section}\n")
        if cur_section == S8:
            doc.append(f"Everything below runs with `cwd` = the throwaway clone at `{DIRTY}` (`git clone --local` of this repo, then one deliberate regression in `src/infra/sortutil.h`). The read-only repo is never touched. The binary is the same `build/ripwire`, addressed absolutely.\n")
    doc.append(f"## `{c['cmd']}`\n")
    doc.append(f"*{c['what']}*\n")
    meta = []
    if r["rc"] != 0:
        meta.append(f"**exit code: {r['rc']}**")
    if r["dt"] > 1.0:
        meta.append(f"**wall time: {r['dt']:.2f}s**")
    if meta:
        doc.append(" — ".join(meta) + "\n")
    if r["pre"]:
        doc.append("Input file:\n")
        doc.append(FENCE)
        doc.append(r["pre"].rstrip())
        doc.append(FENCE + "\n")
    doc.append(FENCE)
    doc.append(fmt_block(r["out"]))
    doc.append(FENCE + "\n")
    if r["err"].strip():
        doc.append("stderr:\n")
        doc.append(FENCE)
        doc.append(fmt_block(r["err"]))
        doc.append(FENCE + "\n")
    if r["post"]:
        doc.append(c.get("post_label", "Artifact written:") + "\n")
        doc.append(FENCE)
        doc.append(r["post"].rstrip())
        doc.append(FENCE + "\n")

# The capture lands directly where it lives: docs/captures/ (see the header note — the lenses skip it,
# argvdiffcheck harvests it). The run summary is a scratch artifact, not part of the capture.
outpath = os.path.join(REPO, "docs", "captures", f"COMMANDS_showcase_{date}.md")
os.makedirs(os.path.dirname(outpath), exist_ok=True)
# Root-neutralise the published text: the checkout's absolute path is machine detail, not a claim
# (same rationale as the --pack-signatures methodology), and the public scrub gate bans home paths.
# Disclosed here rather than silent, in the order applied:
#   1. every occurrence of the repo root becomes "."
#   2. every occurrence of this run's per-run temp dir becomes "<scratch>" — same mechanism, same
#      reason: `/var/folders/…/ripwire_showcase_o6h2ey7l/aux/batch2.txt` is one mktemp draw on one
#      machine, so publishing it dates the document to a directory nobody can reproduce
#   3. the shared public-export scrub (exportscrub.scrub): home paths, other temp paths, internal
#      branch/document names, OWNERSHIP-row identity attributes and git author addresses. The last two
#      matter most here — --owners and --pr-context read real git history, so a capture of a real run
#      leaks real commit identities unless this runs. It is CONTEXT-GATED (see the long note in
#      docs/docs_commands_build.py): `top=` on --hotspots is a SYMBOL NAME and survives untouched, as
#      do ripwire's own `symbol@file.ext` community labels, which have the address shape but are not
#      addresses. One implementation, shared with docs/COMMANDS.md, so a widened scrub reaches both.
published = "\n".join(doc).replace(REPO, ".").replace(SCRATCH, "<scratch>")
published = exportscrub.scrub(published, "ripwire")

# Refuse rather than write what test/docscommandscheck.sh arm (E) would reject. Note which class is
# checked but NOT substituted: an audit COORDINATE has no honest rewrite in a transcript (the
# generator DROPS such lines from COMMANDS.md samples, which a recorded run cannot do), so a coordinate
# reaching the output is a human decision about the source it came from, not something to paper over.
HOME_RE = re.compile(r"/[Uu]sers/")
CLASSES = (("absolute home path", HOME_RE.search),
           ("temp/scratch path", exportscrub.TMP_PATH.search),
           ("internal coordinate shape", exportscrub.COORD.search),
           ("internal document name", exportscrub.INTERNAL_DOC.search),
           ("email address", exportscrub.find_address))
leaks = [f"{i}: {label}: {line.strip()[:100]}"
         for i, line in enumerate(published.split("\n"), 1)
         for label, hit in CLASSES if hit(line)]
if leaks:
    sys.exit("showcase_capture: refusing to write — %d scrub violation(s) survived:\n  %s"
             % (len(leaks), "\n  ".join(leaks[:20])))
open(outpath, "w").write(published)
summ = [{"cmd": r["c"]["cmd"], "cwd": r["c"].get("cwd", REPO), "rc": r["rc"], "dt": round(r["dt"],2),
         "out_bytes": len(r["out"]), "err_bytes": len(r["err"])} for r in results]
open(os.path.join(SCRATCH, "run_summary_new.json"), "w").write(json.dumps(summ, indent=1))
print("DONE", len(results), "commands ->", outpath, file=sys.stderr)
