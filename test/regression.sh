#!/usr/bin/env bash
# regression.sh — the "faster must never change the answer" guard (DV equivalence discipline) + the
# determinism / well-formedness contracts. Run after ANY perf change (cache, parallel, svector, …):
#
#     test/regression.sh                 # uses build/ripwire on test/fixture
#     test/regression.sh path/to/corpus  # the ONE positional argument: an alternate corpus (no flags)
#     RIPWIRE_BIN=asan/ripwire test/regression.sh
#     UPDATE_GOLDEN=1 test/regression.sh # accept a DELIBERATE output change (review the diff first!)
#
# Exits non-zero on any failure. The golden runs on the stable test/fixture corpus; det-gate +
# cache-transparency compare ripwire against itself so they hold on any corpus.

set -u
# A gate that imports a module out of the checkout would otherwise leave __pycache__/ in it: gitignored, but
# still counted by every crawl of the live repo (corpus_pruned_dirs=). test/pargates.py sets the same per gate.
export PYTHONDONTWRITEBYTECODE=1
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative RIPWIRE_BIN
usage(){ printf 'usage: test/regression.sh [CORPUS]   (default: test/fixture — one positional corpus path, no flags)\n' >&2; }
CORPUS="${1:-test/fixture}"
case "$CORPUS" in
    -*) printf "regression.sh: '%s' is not a flag this script accepts (there is no -j; parallelism lives in test/pargates.py)\n" "$CORPUS" >&2; usage; exit 2;;
esac
GOLD="$ROOT/test/golden.xml"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
cd "$ROOT"   # so the corpus path (and thus the XML) is repo-relative → golden is machine-independent
[ -e "$CORPUS" ] || { printf "regression.sh: corpus '%s' does not exist\n" "$CORPUS" >&2; usage; exit 2; }

echo "regression: BIN=$BIN  CORPUS=$CORPUS"

# 0) G1 fresh-asan-binary check — detect if asan/ripwire is stale ( F-OPS).
if RIPWIRE_BIN="$BIN" bash "$ROOT/test/g1freshcheck.sh" >/dev/null 2>&1; then ok "G1 fresh-asan-binary gate (test/g1freshcheck.sh)"; else no "G1 fresh-asan-binary gate (test/g1freshcheck.sh failed)"; RIPWIRE_BIN="$BIN" bash "$ROOT/test/g1freshcheck.sh" 2>&1 | grep -E '(FAIL|stale asan binary)' | head -4; fi

# 1) determinism — same input, byte-identical baseline + three comparisons (§8).
"$BIN" "$CORPUS" --no-cache >"$TMP/a" 2>/dev/null
"$BIN" "$CORPUS" --no-cache >"$TMP/b" 2>/dev/null
"$BIN" "$CORPUS" --no-cache >"$TMP/c" 2>/dev/null
"$BIN" "$CORPUS" --no-cache >"$TMP/d" 2>/dev/null
# NON-VACUITY: an empty baseline compares byte-identical to itself, so 0 B must FAIL, never pass
# (a bad corpus path once produced three empty outputs and a green determinism row).
if [ ! -s "$TMP/a" ]; then
    no "determinism (EMPTY baseline — 0 B output is vacuously identical, not deterministic)"
elif diff -q "$TMP/a" "$TMP/b" >/dev/null && diff -q "$TMP/a" "$TMP/c" >/dev/null && diff -q "$TMP/a" "$TMP/d" >/dev/null; then
    ok "determinism (baseline + 3 byte-identical comparisons, $(wc -c <"$TMP/a" | tr -d ' ') B)"
else
    no "determinism (non-deterministic output)"
fi

# 2) cache transparency — a warm --cache run must produce the SAME output as a cold run
rm -f "$TMP/cache.bin"
"$BIN" "$CORPUS" --cache="$TMP/cache.bin" >"$TMP/cold" 2>/dev/null
"$BIN" "$CORPUS" --cache="$TMP/cache.bin" >"$TMP/warm" 2>/dev/null
if diff -q "$TMP/cold" "$TMP/warm" >/dev/null; then ok "cache transparency (warm == cold)"; else { no "cache transparency (--cache changes output)"; diff "$TMP/cold" "$TMP/warm" | head -4; }; fi

# 2b) warm-BY-DEFAULT transparency — the auto-cache path (no flag) must equal a cold --no-cache run
"$BIN" "$CORPUS" >/dev/null 2>&1                                 # populate the per-root TMPDIR auto-cache
"$BIN" "$CORPUS"            >"$TMP/autowarm" 2>/dev/null         # warm via auto-cache (default behavior)
"$BIN" "$CORPUS" --no-cache >"$TMP/autocold" 2>/dev/null
if diff -q "$TMP/autowarm" "$TMP/autocold" >/dev/null; then ok "warm-by-default == cold (auto-cache)"; else { no "warm-by-default differs from cold"; diff "$TMP/autocold" "$TMP/autowarm" | head -4; }; fi

# 2c) incremental MUTATION transparency (the P1-A gate). #2/#2b prove warm==cold on a STATIC tree; the harder
#     contract is that after an EDIT or a REMOVAL the warm cache (which re-parses only the changed files and
#     re-stamps deterministic node ids) still yields output byte-identical to a fresh cold parse. Operates on
#     a writable COPY so the corpus is never mutated.
MUT="$TMP/mut"
cp -R "$CORPUS" "$MUT" 2>/dev/null
if [ -f "$MUT/geometry.cpp" ]; then
    MCACHE="$TMP/mut.cache"
    "$BIN" "$MUT" --cache="$MCACHE" >/dev/null 2>&1                                   # prime cache on the pristine copy
    # EDIT: append a new function with call edges (perimeter, distance) → new node + edges in the graph
    printf '\ndouble boundingArea( const Point* pts, int n )\n{\n    return perimeter( pts, n ) * distance( pts[0], pts[1] );\n}\n' >> "$MUT/geometry.cpp"
    "$BIN" "$MUT" --cache="$MCACHE" >"$TMP/mut.warm" 2>/dev/null                       # WARM: only geometry.cpp re-parsed
    "$BIN" "$MUT" --no-cache        >"$TMP/mut.cold" 2>/dev/null                       # COLD: full fresh parse (ground truth)
    diff -q "$TMP/mut.warm" "$TMP/mut.cold" >/dev/null \
        && ok "incremental edit transparency (warm-after-edit == fresh cold)" \
        || { no "incremental edit transparency (warm-after-edit diverges from cold)"; diff "$TMP/mut.cold" "$TMP/mut.warm" | head -8; }
    # REMOVAL: delete a file already in the cache; its nodes/edges must vanish exactly as in a cold run
    rm -f "$MUT/related.md"
    "$BIN" "$MUT" --cache="$MCACHE" >"$TMP/mut.warm2" 2>/dev/null
    "$BIN" "$MUT" --no-cache        >"$TMP/mut.cold2" 2>/dev/null
    diff -q "$TMP/mut.warm2" "$TMP/mut.cold2" >/dev/null \
        && ok "incremental removal transparency (warm-after-rm == fresh cold)" \
        || { no "incremental removal transparency (warm-after-rm diverges from cold)"; diff "$TMP/mut.cold2" "$TMP/mut.warm2" | head -8; }
else
    printf '  SKIP  incremental mutation transparency (corpus has no geometry.cpp)\n'
fi

# 2d) document ingest (P1-B): notebooks/html/csv are extracted to text and become recall-able doc nodes,
#     indexed + recalled by the EXTRACTED text (not raw JSON/tags), deterministic and cache-transparent.
DOCFIX="test/docfix"
if [ -d "$DOCFIX" ]; then
    # the notebook's extracted markdown mentions spectral/fiedler/clustering → --recall must surface it AND
    # emit the EXTRACTED body (raw .ipynb JSON would leak "cell_type"; extraction must not), deterministically.
    "$BIN" "$DOCFIX" --recall="spectral fiedler clustering" --no-cache >"$TMP/doc1" 2>/dev/null; rc_doc=$?
    "$BIN" "$DOCFIX" --recall="spectral fiedler clustering" --no-cache >"$TMP/doc2" 2>/dev/null
    { [ $rc_doc -eq 0 ] && diff -q "$TMP/doc1" "$TMP/doc2" >/dev/null \
        && grep -qi 'notebook.ipynb' "$TMP/doc1" && grep -qi 'fiedler' "$TMP/doc1" && ! grep -q 'cell_type' "$TMP/doc1"; } \
        && ok "doc ingest (.ipynb recalled by extracted text, no raw JSON, deterministic)" \
        || { no "doc ingest (.ipynb not recalled / raw JSON leaked / nondeterministic)"; head -6 "$TMP/doc1"; }
    # the .html doc node appears in the default map (extracted prose, not <tags>)
    "$BIN" "$DOCFIX" --no-cache >"$TMP/docmap" 2>/dev/null
    if grep -q 'page.html' "$TMP/docmap"; then ok "doc ingest (.html node in map)"; else no "doc ingest (.html missing from map)"; fi
    # warm == cold on the doc corpus (extraction is cache-transparent)
    rm -f "$TMP/doc.cache"
    "$BIN" "$DOCFIX" --cache="$TMP/doc.cache" >/dev/null 2>&1
    "$BIN" "$DOCFIX" --cache="$TMP/doc.cache" >"$TMP/docwarm" 2>/dev/null
    "$BIN" "$DOCFIX" --no-cache               >"$TMP/doccold" 2>/dev/null
    if diff -q "$TMP/docwarm" "$TMP/doccold" >/dev/null; then ok "doc ingest (warm == cold)"; else { no "doc ingest (warm != cold)"; diff "$TMP/doccold" "$TMP/docwarm" | head -6; }; fi
else
    printf '  SKIP  doc ingest (no test/docfix)\n'
fi

# 3) well-formed XML (G4)
if command -v xmllint >/dev/null 2>&1; then
    if "$BIN" "$CORPUS" 2>/dev/null | xmllint --noout - 2>/dev/null; then ok "xml well-formed"; else no "xml malformed"; fi
else
    printf '  SKIP  xml well-formed (no xmllint)\n'
fi

# 3b) the AST-query paths must not crash. astQuery iterates kLangTable calling grammar(); the markdown
#     entry's grammar is null, which once SIGSEGV'd --match/--lint on every run. Exercise them here so a
#     null-grammar / null-deref regression is caught (the corpus includes a .md file).
"$BIN" "$CORPUS" --lint --no-cache >/dev/null 2>&1
rc_lint=$?
"$BIN" "$CORPUS" --match='(function_definition) @f' --no-cache >/dev/null 2>&1
rc_match=$?
if { [ $rc_lint -eq 0 ] && [ $rc_match -eq 0 ]; }; then ok "--lint / --match run (no crash)"; else no "--lint(rc=$rc_lint) / --match(rc=$rc_match) crashed"; fi

# 3c) --recall (memory-as-graph doc retrieval) — deterministic, non-empty, non-crashing on the corpus docs.
"$BIN" "$CORPUS" --recall="geometry distance" --no-cache >"$TMP/r1" 2>/dev/null; rc_recall=$?
"$BIN" "$CORPUS" --recall="geometry distance" --no-cache >"$TMP/r2" 2>/dev/null
if { [ $rc_recall -eq 0 ] && diff -q "$TMP/r1" "$TMP/r2" >/dev/null && [ -s "$TMP/r1" ]; }; then ok "--recall deterministic + non-empty"; else no "--recall(rc=$rc_recall) nondeterministic/empty/crashed"; fi

# 3d) --seams (untested cross-module integration seams) — deterministic, non-crashing (may be empty on a tiny corpus).
"$BIN" "$CORPUS" --seams --no-cache >"$TMP/sm1" 2>/dev/null; rc_seams=$?
"$BIN" "$CORPUS" --seams --no-cache >"$TMP/sm2" 2>/dev/null
if { [ $rc_seams -eq 0 ] && diff -q "$TMP/sm1" "$TMP/sm2" >/dev/null; }; then ok "--seams deterministic (no crash)"; else no "--seams(rc=$rc_seams) nondeterministic/crashed"; fi

# 3e) --mermaid (module dependency diagram) — deterministic, non-crashing, emits a flowchart.
"$BIN" "$CORPUS" --mermaid --no-cache >"$TMP/mm1" 2>/dev/null; rc_mm=$?
"$BIN" "$CORPUS" --mermaid --no-cache >"$TMP/mm2" 2>/dev/null
if { [ $rc_mm -eq 0 ] && diff -q "$TMP/mm1" "$TMP/mm2" >/dev/null && grep -q '^flowchart' "$TMP/mm1"; }; then ok "--mermaid deterministic (flowchart)"; else no "--mermaid(rc=$rc_mm) nondeterministic/crashed/no-flowchart"; fi

# 3f) --situ (situational awareness for an explicit change set) — deterministic, non-crashing.
"$BIN" "$CORPUS" --situ=geometry.cpp --no-cache >"$TMP/si1" 2>/dev/null; rc_si=$?
"$BIN" "$CORPUS" --situ=geometry.cpp --no-cache >"$TMP/si2" 2>/dev/null
if { [ $rc_si -eq 0 ] && diff -q "$TMP/si1" "$TMP/si2" >/dev/null; }; then ok "--situ deterministic (no crash)"; else no "--situ(rc=$rc_si) nondeterministic/crashed"; fi

# 3g) --mentions (doc<->code links) — deterministic; fixture notes.md names `distance` in a backtick.
"$BIN" "$CORPUS" --mentions=distance --no-cache >"$TMP/mt1" 2>/dev/null; rc_mt=$?
"$BIN" "$CORPUS" --mentions=distance --no-cache >"$TMP/mt2" 2>/dev/null
if { [ $rc_mt -eq 0 ] && diff -q "$TMP/mt1" "$TMP/mt2" >/dev/null && grep -q 'notes.md' "$TMP/mt1"; }; then ok "--mentions deterministic (doc<->code link found)"; else no "--mentions(rc=$rc_mt) nondeterministic/crashed/no-link"; fi

# 3h) wrap (adoption recipes) — deterministic, known agent → exit 0 + MCP wiring; unknown agent → exit 2.
"$BIN" wrap claude >"$TMP/wr1" 2>/dev/null; rc_wr=$?
"$BIN" wrap claude >"$TMP/wr2" 2>/dev/null
"$BIN" wrap no-such-agent >/dev/null 2>&1; rc_wrbad=$?
if { [ $rc_wr -eq 0 ] && diff -q "$TMP/wr1" "$TMP/wr2" >/dev/null && grep -q 'claude mcp add' "$TMP/wr1" && [ $rc_wrbad -eq 2 ]; }; then ok "wrap deterministic (recipe + unknown→exit 2)"; else no "wrap(rc=$rc_wr,bad=$rc_wrbad) nondeterministic/no-recipe"; fi

# 3i) --stable: deterministic, path-ordered (order=stable), and OMITS the globally-volatile k= rank so the
#     emitted prefix is byte-stable across edits (provider KV-cache hits). default keeps k= (golden below).
"$BIN" "$CORPUS" --stable --no-cache >"$TMP/st1" 2>/dev/null; rc_st=$?
"$BIN" "$CORPUS" --stable --no-cache >"$TMP/st2" 2>/dev/null
if { [ $rc_st -eq 0 ] && diff -q "$TMP/st1" "$TMP/st2" >/dev/null && grep -q 'order=stable' "$TMP/st1" && ! grep -q ' k="' "$TMP/st1"; }; then ok "--stable deterministic (path order, no volatile k=)"; else no "--stable(rc=$rc_st) nondeterministic/has-k=/no-order"; fi

# 3k) --stable is the MCP default (P2-C): an --mcp `analyze` response is path-ordered (order=stable) by
#     default — KV-cache-friendly for MCP callers without their having to pass the flag; --no-stable opts out.
mcpreq='{"jsonrpc":"2.0","id":1,"method":"initialize"}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"analyze","arguments":{"path":"'"$CORPUS"'"}}}'
printf '%s\n' "$mcpreq" | "$BIN" --mcp             >"$TMP/mcp_def" 2>/dev/null
printf '%s\n' "$mcpreq" | "$BIN" --mcp --no-stable >"$TMP/mcp_no"  2>/dev/null
{ grep -q 'order=stable' "$TMP/mcp_def" && ! grep -q 'order=stable' "$TMP/mcp_no"; } \
    && ok "--mcp defaults to --stable (order=stable; --no-stable opts out)" \
    || { no "--mcp stable-default / --no-stable opt-out broken"; grep -o 'order=[a-z-]*' "$TMP/mcp_def" "$TMP/mcp_no" | head; }

# 3j) skill security scan (P1-C) — run the dedicated gate (inject/exfil → exit 2; clean/docs → exit 0,
#     incl. the documentation-not-attack precision case). Uses the same binary under test.
if RIPWIRE_BIN="$BIN" bash "$ROOT/test/skillscan.sh" >/dev/null 2>&1; then ok "skill scan gate (test/skillscan.sh)"; else no "skill scan gate (test/skillscan.sh failed)"; RIPWIRE_BIN="$BIN" bash "$ROOT/test/skillscan.sh" 2>&1 | grep -i fail | head -4; fi

# 3m) --html graph export (P2-A) — run the dedicated gate (valid self-contained HTML, ≥3 nodes, deterministic,
#     no external <script src>/<link href>). Uses the same binary under test.
if RIPWIRE_BIN="$BIN" bash "$ROOT/test/htmlexport.sh" >/dev/null 2>&1; then ok "html export gate (test/htmlexport.sh)"; else no "html export gate (test/htmlexport.sh failed)"; RIPWIRE_BIN="$BIN" bash "$ROOT/test/htmlexport.sh" 2>&1 | grep -i fail | head -4; fi

# 3o) --compress body output (P2-B) — run the dedicated gate (comments stripped, string literals intact,
#     blank-line runs collapsed, compressed < uncompressed, deterministic). Uses the same binary under test.
if RIPWIRE_BIN="$BIN" bash "$ROOT/test/compresscheck.sh" >/dev/null 2>&1; then ok "compress gate (test/compresscheck.sh)"; else no "compress gate (test/compresscheck.sh failed)"; RIPWIRE_BIN="$BIN" bash "$ROOT/test/compresscheck.sh" 2>&1 | grep -i fail | head -8; fi

# 3p) --handoff continuation packet — run the dedicated gate (verified+heuristic sections present, verified
#     names the edited file, determinism, xmllint-clean, additive/no side effect on the flagless map, the
#     empty-diff contract, --token-budget composition). Uses the same binary under test.
if RIPWIRE_BIN="$BIN" bash "$ROOT/test/handoffcheck.sh" >/dev/null 2>&1; then ok "handoff gate (test/handoffcheck.sh)"; else no "handoff gate (test/handoffcheck.sh failed)"; RIPWIRE_BIN="$BIN" bash "$ROOT/test/handoffcheck.sh" 2>&1 | grep -i fail | head -8; fi

# 3q) printf-family byte-parity fence — a
#     printf/fprintf/snprintf -> std::format/std::print conversion must not move one byte of any verb's
#     stdout/stderr; per-verb/per-stream SHA-256 against test/printf_parity.manifest. Individually invoked
#     (not folded into the bulk absorb loop below) so this gate's addition does not perturb that loop's
#     length, which docs/EVALS.md §8 quotes verbatim (owned by a different thread this round).
if RIPWIRE_BIN="$BIN" bash "$ROOT/test/printffmtparitycheck.sh" >/dev/null 2>&1; then ok "printf/fmt parity gate (test/printffmtparitycheck.sh)"; else no "printf/fmt parity gate (test/printffmtparitycheck.sh failed)"; RIPWIRE_BIN="$BIN" bash "$ROOT/test/printffmtparitycheck.sh" 2>&1 | grep -i fail | head -8; fi

# Delivery contract is kept separate because it drives the curl installer with a sealed local release
# fixture and inspects the release workflow itself. It USED to need no binary under test; since it gained
# the installer-isolation helper it nests skillinstallcheck, which does. RIPWIRE_BIN is therefore passed
# explicitly: without it the nested gate silently runs ./build/ripwire even under
# `RIPWIRE_BIN=asan/ripwire test/regression.sh`, i.e. it would test a different binary than the one
# named and report a pass for it. Restored on the #51 merge, which predated a5c95aa6 and dropped it
# without a git conflict.
if RIPWIRE_BIN="$BIN" bash "$ROOT/test/releaseinstallcheck.sh" >/dev/null 2>&1; then
    ok "release install gate (test/releaseinstallcheck.sh)"
else
    no "release install gate (test/releaseinstallcheck.sh failed)"
    RIPWIRE_BIN="$BIN" bash "$ROOT/test/releaseinstallcheck.sh" 2>&1 | grep -E 'FAIL|SOME' | head -8
fi

# Source-build delivery is a separate contract from release archives: the binary, skills and hooks
# installed by one component must be the same revision, so an update cannot leave stale agent routing.
if RIPWIRE_BIN="$BIN" bash "$ROOT/test/sourceinstallcheck.sh" >/dev/null 2>&1; then
    ok "source install gate (test/sourceinstallcheck.sh)"
else
    no "source install gate (test/sourceinstallcheck.sh failed)"
    RIPWIRE_BIN="$BIN" bash "$ROOT/test/sourceinstallcheck.sh" 2>&1 | grep -E 'FAIL|SOME' | head -8
fi

# Task router is a standalone contract gate and must run under the binary selected for this suite.
if RIPWIRE_BIN="$BIN" bash "$ROOT/test/taskroutecheck.sh" >/dev/null 2>&1; then
    ok "task router gate (test/taskroutecheck.sh)"
else
    no "task router gate (test/taskroutecheck.sh failed)"
    RIPWIRE_BIN="$BIN" bash "$ROOT/test/taskroutecheck.sh" 2>&1 | grep -E 'FAIL|FAILURES' | head -8
fi

# Prompt routing runs before the first retrieval decision; confidence-gated context and privacy-safe
# telemetry are independent of the binary's held-out taskroute evaluator.
if RIPWIRE_BIN="$BIN" bash "$ROOT/test/codexpromptroutecheck.sh" >/dev/null 2>&1; then
    ok "Codex prompt route gate (test/codexpromptroutecheck.sh)"
else
    no "Codex prompt route gate (test/codexpromptroutecheck.sh failed)"
    RIPWIRE_BIN="$BIN" bash "$ROOT/test/codexpromptroutecheck.sh" 2>&1 | grep -E 'FAIL|SOME' | head -8
fi

# CLI edit delivery is a first-class gate: the preferred surface must share the MCP edit engine's
# refusal/atomicity guarantees rather than leaving safe writes available only through MCP.
if RIPWIRE_BIN="$BIN" bash "$ROOT/test/clieditcheck.sh" >/dev/null 2>&1; then
    ok "CLI edit gate (test/clieditcheck.sh)"
else
    no "CLI edit gate (test/clieditcheck.sh failed)"
    RIPWIRE_BIN="$BIN" bash "$ROOT/test/clieditcheck.sh" 2>&1 | grep -E 'FAIL|SOME' | head -8
fi

if RIPWIRE_BIN="$BIN" bash "$ROOT/test/grephandlecheck.sh" >/dev/null 2>&1; then
    ok "grep handle gate (test/grephandlecheck.sh)"
else
    no "grep handle gate (test/grephandlecheck.sh failed)"
    RIPWIRE_BIN="$BIN" bash "$ROOT/test/grephandlecheck.sh" 2>&1 | grep -E 'FAIL|SOME' | head -8
fi

# 3n) absorb gates (P3-B arch layer(), S6-A lint completion, S6-B swift purity, S5-C owners) — each a
#     dedicated standalone gate; run with the binary under test (skip any not yet present).
if RIPWIRE_BIN="$BIN" bash "$ROOT/test/codexdoctorcheck.sh" >/dev/null 2>&1; then
    ok "Codex active-surface doctor gate (codexdoctorcheck.sh)"
else
    no "Codex active-surface doctor gate (codexdoctorcheck.sh failed)"
    RIPWIRE_BIN="$BIN" bash "$ROOT/test/codexdoctorcheck.sh" 2>&1 | sed 's/^/        | /'
fi
# retired: cacheexclkeycheck — the per-configuration auto-cache key it pinned is a registered NEGATIVE (docs/EVALS.md, "The auto-cache key ignores --exclude", RUN 2026-09-03: a 158K-file root with >= 12 gate configurations thrashed the 2 GiB sweep); the retry design keeps ONE superset blob per root and will bring its own gate
for _g in a9disclosurecheck abicheck accessshapecheck ackonlycheck adaptivecheck adaptivecutshapecheck affectedcheck agentloopclaudecheck agentloopcodexcheck agentloopeditsuitecheck agentloopfollowupcheck agentloopgradercheck agentlooplockcheck agentloopopencodecheck agenttablecheck aiderbytescheck anchorbodycheck anchorcheck archcheck archmetricscheck argvdiffcheck arisefollowupcheck ariseshimcheck aritycheck artifactcheck atcheck atomscheck attrvocabcheck baselinecheck baselinedirtycheck baselineportcheck bashsourcecheck batchcheck binoverridecheck blindspotcheck bm25boundcheck bm25check bodiesshowncheck bodydialectcheck budgetpolicycheck bundleidcheck cachefuzzcheck cachehashcheck cacheidentitycheck cacheisolationcheck cachelintcheck cacheoffsetcheck cachesplitcheck callerscheck callformcheck callsrankordercheck candheadcheck candidatescheck canoncheck capdisclosurecheck capsweepcheck ccheck ccjsoncheck chacheck chaconecheck chainguardcheck chainidcheck churndecaycheck churnjoincheck churnjsonstampcheck claudeconfigdircheck clicheck clonebandcheck clonecachecheck clonededupcheck cloneidiomcheck clonelexcheck clsrecvcheck cochangeboostcheck cochangecliocheck cochangesurprisecheck codexinstallhonestycheck codexplugincheck codexwrapcheck collectioncapcheck columnarattrcheck columnarcheck columnarcommacheck commentcoherencecheck communitydrillcheck communitylabelcheck compactlegendcheck compactroutecheck completecheck composelangcheck connectcheck connectcorecheck connectjoincheck constcheck contextratiocheck coplintcheck cppbenchcheck cppoperatorcheck cppqualcheck crossdirincludecheck crossrefcheck crossrefdegradecheck csharpcheck csharpcondcheck cudacheck cyclecutcheck dartcheck deadcheck deadfiltercheck deadprecisioncheck deckcheck deckclaimcheck deeptailcheck defaultceilingcheck defoverdeclcheck degradedhintcheck dependencypincheck deplangscheck depsprecisecheck detailcheck didyoumeancheck dispatchordercheck dmmcheck docanchorcheck docdemotecheck docdriftcheck docdriftcommentcheck docmdcachecheck docmentioncheck docscommandscheck doctorcheck donelegendcheck droppedpositivecheck duprowcheck dynmapsimdcheck editcheckanswercheck editcheckcheck editchecknotecheck edithandlehintcheck editpayloadbinarycheck editplancheck editplanpayloadconfinecheck editplanrecheckcheck editplanrollbackmsgcheck editpreviewcheck editroundtripcheck edittargetfileabscheck eliximportcheck elixircheck emittertruthcheck emptycorpuscheck emptyvaluerefusecheck ensembleavailcheck ensemblecheck essentialcxcheck estchargecheck evalcheck evictioncheck exemplarcheck exemplarconfcheck exercisescheck expandcallscheck expandmodecheck expandrangecheck expandsibscheck expandtokencheck expandtopk0check externalvetocheck fficheck fieldaffinitycheck fieldnarrowcheck fieldusescheck filerootcheck fileselectorrefusecheck fillordercheck fixedbufsweep flagscheck flagsnoisecheck flagsurfacecheck flagtablecheck flipcheck floormarkcheck fnptrcheck forautobodycheck forbudgetmonotoncheck forcalibfactscheck forcompresscheck fordisclosurecheck forlenscheck formatgatecheck formaxtokenscheck fornotesbudgetcheck fornotesjsoncheck forrankordercheck forrootlegendcheck freshclonecheck freshnesscheck g1configcheck gateabilitycheck gatecountcheck gateexitcheck genrecallcheck githardencheck gitignorecheck gitquotepathcheck gitstampcheck goinstcheck gointerfacecheck graphlegendbudgetcheck graphqueryrefusecheck grepanchorcheck grepandcheck grepbytescheck grepcheck grepcontextcheck grepcorpuscheck grepfastcheck grepfollowupcheck grepignorecheck grepscancheck grepseamcheck greptiercheck guardmsgcheck hasacheck headbinstagecheck headsnapcachecheck helpbudgetcheck hermesinstallcheck historyoraclecheck hookcheck hostilecheck hotspotsincecheck htmlcolorcheck htmlhostcheck htmlrendercheck identitycheck impactimportcheck impactpartitioncheck importnarrowcheck includeanglecheck includeprecisecheck indexoutcheck infraportcheck isolateprovenancecheck javarubycheck jslangcheck jsmetricscheck jsnestedcheck jsoncheck jsonlangcheck jsonparitycheck jsonredactcheck jsonrefusallegendcheck jsonwalkcheck jsshapecheck jsverbscheck knownitemcheck kotlincheck landingcheck langcensuscheck langcheck layerquerycheck layoutcheck lb3namecheck legendcostcheck legendcoveragecheck legenddriftcheck legobundlecheck legocheck liftdisclosurecheck limitstablecheck lintbudgetcheck lintcatalogcheck lintcheck lintdedupcheck lintpayloadcapcheck lintprecisioncheck lintrulescheck lintscopecheck lintselectcheck localitycheck localscountcheck loopconservationcheck lpincheck luacheck luarequirecheck macroedgecheck manifestcheck mapdiffcheck matchcapturecheck matchgrammarcheck maxfilesizecheck mcpattrparitycheck mcpaudit4hardencheck mcpclidiffcheck mcpcodexmetacheck mcpcontractcheck mcpdegradedhintcheck mcpeditcheck mcpeditkindcheck mcpeditmodecheck mcpeditpresencecheck mcpeditracecheck mcpflagshipcheck mcpforparitycheck mcpframehonestycheck mcpgrepdegradedcheck mcphandlecheck mcpincrementalcheck mcpmanifestcheck mcprangeedgecheck mcpreadloopcheck mcpredactcheck mcpreloadcheck mcpremotecheck mcprobustcheck mcpslicecheck mcpstalecheck mcpstrictschemacheck mcptoolprunecheck mcptranchecheck mcpverbscheck mcpw2fixcheck mcpw3fixcheck mcpwatchercheck mdembedcheck mdsectioncheck mentioncapcheck mentioncheck mentionsverbcheck mergechurncheck mergescoutcheck mergescoutlonglinecheck metalcheck meterdisclosurecheck metricscheck modifierguardcheck moduleconstcheck morecontractcheck mrowalkcheck multirootcheck multiswecheck namedfileinputcheck nameinfocheck namingcalibrationcheck namingconsistencycheck naminglenscheck naminglocalscheck narrowcheck narrowlangcheck neighbourcapcheck nestedimportcheck nestedqualcheck nestprofilecheck nextverbcheck nodekindcheck nongitqmetricscheck nonlocalstatecheck notecanoncheck notescheck nsfiltercheck nulbytecheck numericrefusecheck objcfieldcheck objcsniffcheck opencodewrapcheck optremarkscheck optremarkshotcheck ordercheck outlinecheck overbudgetcommentcheck ownerscheck packcallersharecheck packtaskcheck packtaskmonotoncheck packtaskquotacheck padscalecheck paginationcheck pagingsweepcheck panellegendcheck pargatescheck parsehealthcheck partitioncheck patterncheck perfharnesscheck phpcheck pincensuscheck planlanescheck planlintcheck pmccheck portablebuildcheck portablecachecheck postingscheck ppaltcheck pranchorcheck prbudgetcheck prcheck prcontextcheck prconvergecheck precedencecheck preproccondcheck prmaskanchorcheck prnestedcapcheck probecheck propcostcheck prrefsafecheck prrenamecheck pyimportprecisecheck pyshapecheck qackconcurrencycheck qackorigincheck qchurncheck qchurnmemocheck qdrefpaircheck qextractionkeycheck qoriginoraclecheck qrevtokencheck qrowlocatorcheck qschemetripcheck qsnapcachecheck qsnapprefetchcheck qualifiedresolvecheck qualitycheck qualitycrosslangcheck qualityexcludecheck qualitykeycheck qualitykindscheck qualityorigincheck qualitypanelcheck qualityscopecheck qualitysignalcheck qualitystalecheck qualitysymcheck qualnewcheck querycheck queryfilescancheck racymtimecheck radixsimdcheck rangecomposecheck rankbycheck reachcheck readabilitycheck readmedriftcheck readmeexamplecheck recallanchorcheck recallboundarycheck recallbudgetcheck recallbufcheck recallevalcheck recallparitycheck recallpassagecheck recallrankdepthcheck recallrelcheck recalltablecheck recalltotalcheck receiptpostcheck redactcheck redactfixcheck refusaltailcheck regexbombcheck regexcheck regexrefusecheck registermacrocheck relevancefloorcheck relinkcheck reportcheck resolvecheck resolverhonestycheck retrievalqualitycheck reusefirstworkflowcheck ripwirepubliccheck rootrelcheck rootrelemitcheck routecheck routeedgecheck routehookcheck routeoncecheck routingreportcheck rubyconstcheck rubymetricscheck rubyrecvcheck rubyrequirecheck rubyscopecheck rubysettercheck runhintcheck runtracecheck rustanccheck rustimportprecisecheck rustqualcheck safedeletecheck sarifcheck savecachecheck scipcheck scipjoincheck scorecardcheck scoutheadconflictcheck scoutkeycheck seedboundscheck selectorchaincheck selectorhonestycheck selectorrefusecheck selectorscopecheck selfcontainedcheck shadowcheck shapingflagcheck shellgateindexcheck showcasecapturecheck sibliftcheck sigredactcheck sincecheck sincecochangecheck sincewindowcheck singledefcheck situdiffcheck skilldescbudgetcheck skillevalcheck skillevalsplitcheck skillinstallcheck skillroutingjudgedcheck skillscanreadcheck skilltruthcheck skippedcheck skipreasoncheck slicecheck slicediffcheck sliceflowcheck sliceflowsenscheck spectimingcheck staleackcheck statgatecheck stdqualcheck sublistcountcheck substrfiltercheck subtokencheck svectorcheck swiftcheck swiftmemberscheck swiftshapecheck taskechocheck termmargincheck testedreachcheck testgatecheck testgatelegendbudgetcheck testgatepagecheck testgaterefusecheck testmacrocheck testrowruncheck testscopecheck textdocscheck timsortcheck tokenbudgetcheck tomllangcheck toolcallroutecheck tornreadcheck tracecheck tracehandoffcapcheck tracehopcheck traceminecheck treecheck truncvocabcheck tsimportprecisecheck tsshapecheck type3check type3clonecheck typerefcheck unreachablecheck unresolvedcheck usescheck usesselectorcheck usingdeclcheck utf8scrubcheck vendoredassetcheck vendoredbundlecheck vendorpatchcheck verifycheck versioncheck w2verbscheck w3fixbudgetcheck w3fixlegendcheck weaksignalcheck withgraphcheck withprofilecheck worktreeleakcheck wrapverbscheck writetargetcheck xmlwellformed yamllangcheck zonecheck zoneconsistencycheck zoomcheck emitescapecheck strkerncheck astqueryregexcheck fieldidcheck cachereservecheck childwalkscalecheck preprocdeadscalecheck qddialscheck listingpagingcheck declinecheck extentcheck macroreparsecheck sidecarsymlinkcheck crawlescapecheck decltodefcheck ceilingverdictcheck; do
    [ -f "$ROOT/test/$_g.sh" ] || continue
    if RIPWIRE_BIN="$BIN" bash "$ROOT/test/$_g.sh" >/dev/null 2>&1; then
        ok "absorb gate ($_g.sh)"
    else
        # A BARE NAME IS UNDIAGNOSABLE IN CI. The >/dev/null 2>&1 above eats the gate's own FAIL text, so the
        # only thing a log reader gets is "absorb gate (X.sh failed)" — the whole of PR #1's first round
        # (run 30732976779) landed as eight such names across two OSes with zero evidence attached, and every
        # one of them had to be re-derived by hand. Re-run ONLY the gate that failed, with output captured,
        # and echo the part that matters, prefixed with the gate name — the same shape as the NAMED gates
        # above, which already grep a few lines on failure. Cost: one extra run of the few gates that failed.
        #
        # WINDOW, not head. A gate's failing arm is usually NOT in its first 25 lines (lintrulescheck emits
        # ~35 PASS rows before its later arms), so a plain head shows 25 PASSes and hides the failure. Start
        # at the first failure-shaped line and take 25 from there — that captures the FAIL row AND the
        # evidence the gate prints under it (compile logs, diffs, sanitizer reports). A gate that died
        # without ever printing one (missing tool, bad precondition, crash) has no such line, so fall back
        # to the TAIL, where those messages land.
        _rc_absorb=0
        RIPWIRE_BIN="$BIN" bash "$ROOT/test/$_g.sh" >"$TMP/absorb.out" 2>&1 || _rc_absorb=$?
        no "absorb gate ($_g.sh failed, rc=$_rc_absorb)"
        # the repo's OWN marker first (`  FAIL  …` / `FAILURES ABOVE`, case-sensitive and anchored, so a PASS
        # row whose prose contains "fail"/"failure" cannot hijack the window), then the shapes a gate that
        # never reached its own reporting prints instead.
        _first_fail="$( grep -nE -m1 '^[[:space:]]*FAIL|^FAILURES ABOVE' "$TMP/absorb.out" | cut -d: -f1 )"
        [ -n "${_first_fail:-}" ] || _first_fail="$( grep -nE -m1 'error:|fatal|Sanitizer|required$|no ripwire binary|command not found' "$TMP/absorb.out" | cut -d: -f1 )"
        if [ -n "${_first_fail:-}" ]; then
            sed -n "${_first_fail},$(( _first_fail + 24 ))p" "$TMP/absorb.out" | sed "s/^/    [$_g] /"
            printf '    [%s] (window of 25 from line %s of %s; rerun: RIPWIRE_BIN=%s bash test/%s.sh)\n' \
                   "$_g" "$_first_fail" "$( wc -l <"$TMP/absorb.out" | tr -d ' ' )" "$BIN" "$_g"
        else
            tail -n 25 "$TMP/absorb.out" | sed "s/^/    [$_g] /"
            printf '    [%s] (no failure-shaped line — last 25 of %s shown; rerun: RIPWIRE_BIN=%s bash test/%s.sh)\n' \
                   "$_g" "$( wc -l <"$TMP/absorb.out" | tr -d ' ' )" "$BIN" "$_g"
        fi
    fi
done

# 3l) arch-layer auto-tags (P3): a file node under a known layer dir gets a built-in layer= attribute
#     (architecture at a glance). test/fixture lives under test/ → layer="test". Determinism via det-gate above.
"$BIN" test/fixture --no-cache 2>/dev/null | grep -q 'layer="test"' \
    && ok "arch-layer tags (layer= on file nodes)" \
    || no "arch-layer tags (no built-in layer= emitted on a known-layer file)"

# 4) golden snapshot — output matches the committed golden (catches ANY unintended output change).
#    --no-cache so the golden is the canonical cold parse, independent of any TMPDIR cache state.
"$BIN" "$CORPUS" --no-cache >"$TMP/cur" 2>/dev/null
if [ "${UPDATE_GOLDEN:-0}" = "1" ]; then
    cp "$TMP/cur" "$GOLD"; printf '  WROTE golden (%s B)\n' "$(wc -c <"$GOLD" | tr -d ' ')"
elif [ -f "$GOLD" ]; then
    if diff -q "$GOLD" "$TMP/cur" >/dev/null; then ok "golden ($(wc -c <"$GOLD" | tr -d ' ') B)"; else { no "golden drift — review, then UPDATE_GOLDEN=1 if intended"; diff "$GOLD" "$TMP/cur" | head -8; }; fi
else
    printf '  SKIP  golden (none yet; create with UPDATE_GOLDEN=1)\n'
fi

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
