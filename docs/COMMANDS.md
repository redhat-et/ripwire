# ripwire — every flag, generated from the binary

**This file is generated. Do not hand-edit it.** Regenerate with:

```bash
python3 docs/docs_commands_build.py --bin build/ripwire
```

The flag surface below is read from `ripwire --help`, so it cannot disagree with the shipped
binary. `test/docscommandscheck.sh` fails if it ever does — in either direction.

Sample output is lifted from a real recorded run (`docs/captures/COMMANDS_showcase_2026-10-08.md`), trimmed to the first few lines and
scrubbed of local paths. It is illustrative, not a golden: run the command yourself for the
current shape.

> ripwire — the "ripgrep of AI context": parse a codebase, rank symbols by Personalized PageRank,
> stream a deterministic minified XML map to stdout. Zero runtime deps. Languages: C++, C, ObjC/ObjC++,
> Metal (MSL, .metal — C++ grammar), CUDA (.cu/.cuh — tree-sitter-cuda, <<<>>> launches are call edges),
> Python, TypeScript (.ts/.tsx/.mts/.cts; .astro frontmatter), JavaScript, Java, Ruby, PHP (.php/.phtml), Lua, Elixir (.ex/.exs), Dart (.dart), Kotlin (.kt), Bash, Go, Rust, Swift, C#,
> GDScript (.gd — Godot; .tscn/.tres/.gdshader are NOT indexed);
> JSON, TOML, YAML (config keys); Markdown (.md/.markdown — headings are section symbols with spans).

## How to read a section

- **Answers** — the question this flag exists to answer.
- **Try it** — a real invocation and the real output it produced.
- **Shaped by** — other flags that change what this one emits.
- **Caveats** — the limits the binary itself states for this flag. They are extracted from its
  own help text, so they cannot drift from the code.

Two limits apply to nearly everything here and are not repeated in every section:

1. **Call edges are heuristic and name-based.** Dynamic dispatch, callbacks and macro-generated
   call sites produce no edge, so counts on the graph verbs carry `counts_floor="1"`. **Read a 0
   as "none found", never as "none exists."**
2. **A symbol's `amb="K"`** means K of its calls hit a name with several definitions and the
   resolver split the weight rather than choosing. Read the source when which-target matters.

## Contents

**understand a codebase cold** — [`--top-k`](#--top-kn) · [`--max-tokens`](#--max-tokensn) · [`--token-budget`](#--token-budgetnkmg) · [`--help-task`](#--help-tasktask) · [`--for`](#--fortask) · [`--sections`](#--sectionslegocompose) · [`--signatures-only`](#--signatures-only) · [`--auto-bodies`](#--auto-bodies) · [`--no-route`](#--no-route) · [`--adaptive`](#--adaptive) · [`--no-mention-boost`](#--no-mention-boost) · [`--no-doc-mention`](#--no-doc-mention) · [`--lego`](#--legotype) · [`--exemplar`](#--exemplartaskkind) · [`--recall`](#--recalltask) · [`--tree`](#--tree) · [`--html`](#--htmlfile) · [`--color-by`](#--color-bymode) · [`--order`](#--ordermode) · [`--no-stable`](#--no-stable)

**navigate / answer a question** — [`--around`](#--aroundsym) · [`--callers`](#--callerssym) · [`--callees`](#--calleessym) · [`--uses`](#--usessym) · [`--graph-query`](#--graph-queryexpr) · [`--external-surface`](#--external-surface) · [`--path`](#--pathsrcdst) · [`--connect`](#--connectabc) · [`--impact`](#--impactsym) · [`--verify`](#--verifyclaim) · [`--mentions`](#--mentionssym) · [`--affected`](#--affectedf1f2sym) · [`--exercises`](#--exercisestestfile) · [`--situ`](#--situf1f2) · [`--handoff`](#--handoff) · [`--test-gate`](#--test-gatef1f2) · [`--grep`](#--grepstr----regexpat) · [`--grep-context`](#--grep-contextn----grep-beforen----grep-aftern) · [`--and`](#--andstr) · [`--not`](#--notstr) · [`--grep-scope`](#--grep-scopelinefile) · [`--grep-in`](#--grep-incodeany) · [`--handles`](#--handles) · [`--match`](#--matchquery) · [`--pattern`](#--patternpat) · [`--query`](#--queryterms)

**zoom the detail ladder** — [`--detail`](#--detailn) · [`--pack-signatures`](#--pack-signatures) · [`--outline`](#--outlineab) · [`--expand`](#--expandab) · [`--compress`](#--compress) · [`--pack-top-n`](#--pack-top-nn) · [`--no-redact`](#--no-redact)

**assess quality / structure** — [`--metrics`](#--metrics) · [`--deps`](#--deps) · [`--hotspots`](#--hotspots) · [`--clones`](#--clones) · [`--biggest-first`](#--biggest-first) · [`--nonlocal-state`](#--nonlocal-state) · [`--ensemble`](#--ensemble) · [`--quality-panel`](#--quality-panelpreset) · [`--context-ratio`](#--context-ratio) · [`--naming-calibration`](#--naming-calibration) · [`--naming-consistency`](#--naming-consistency) · [`--naming-locals`](#--naming-locals) · [`--comment-coherence`](#--comment-coherence) · [`--cochange`](#--cochangefile) · [`--cochange-recur`](#--cochange-recurk) · [`--cochange-groups`](#--cochange-groups) · [`--since`](#--sincerevdate) · [`--arch`](#--archfile) · [`--arch`](#--archfile---baseline) · [`--arch`](#--archfile---baseline-update) · [`--lint`](#--lint) · [`--lint-catalog`](#--lint-catalog) · [`--lint-rules`](#--lint-rulesdir) · [`--lint-select`](#--lint-selectprefix) · [`--lint-ignore`](#--lint-ignoreprefix) · [`--lint-max-per-rule`](#--lint-max-per-rulen) · [`--sarif`](#--sarif) · [`--with-profile`](#--with-profilefile) · [`--communities`](#--communities) · [`--community`](#--communityid) · [`--zoom`](#--zoomdepth) · [`--report`](#--report) · [`--seams`](#--seams) · [`--mermaid`](#--mermaid) · [`--owners`](#--ownerssym) · [`--dead-code`](#--dead-codedir) · [`--quality-baseline`](#--quality-baseline) · [`--allow-dirty`](#--allow-dirty) · [`--show-stale`](#--show-stale) · [`--quality-delta`](#--quality-delta) · [`--quality-delta`](#--quality-deltarevab) · [`--dmm`](#--dmmrevab) · [`--quality-ack`](#--quality-ackreason) · [`--ack-only`](#--ack-onlysubstrsubstr) · [`--scope`](#--scopeglobglob) · [`--edit-check`](#--edit-checksym) · [`--replace-symbol-body`](#--replace-symbol-bodytarget) · [`--insert-before-symbol`](#--insert-before-symboltarget) · [`--insert-after-symbol`](#--insert-after-symboltarget) · [`--edit-payload`](#--edit-payloadfile-) · [`--edit-target-file`](#--edit-target-filepath) · [`--no-post-check`](#--no-post-check) · [`--edit-plan`](#--edit-planfile) · [`--dry-run`](#--dry-run----apply) · [`--safe-delete`](#--safe-deletesym) · [`--slice`](#--slicesymvar) · [`--slice-flow`](#--slice-flowbackfwdboth) · [`--slice-depth`](#--slice-depthn) · [`--at`](#--atfileline) · [`--pr-context`](#--pr-contextbaseref) · [`--merge-scout`](#--merge-scoutrefref) · [`--plan-lanes`](#--plan-lanesn---taskgoal) · [`--plan-lanes`](#--plan-lanes---brieffile) · [`--stray-content`](#--stray-contentsubstr) · [`--plan`](#--plan) · [`--abi`](#--abi) · [`--whereis`](#--whereissym) · [`--whereis-listing`](#--whereis-listingwhich) · [`--flags`](#--flagssubstr) · [`--flip`](#--flipname) · [`--layout`](#--layoutstruct) · [`--field-affinity`](#--field-affinitystruct) · [`--doc-drift`](#--doc-driftsubstr) · [`--doc-drift`](#--doc-drift---gateability) · [`--with-history`](#--with-history) · [`--plan-lint`](#--plan-lintfile) · [`--from-trace`](#--from-tracefile) · [`--run-trace`](#--run-tracecmd) · [`--run-timeout`](#--run-timeoutseconds) · [`--note-add`](#--note-addtarget-text) · [`--notes`](#--notes) · [`--pack-task`](#--pack-tasktask) · [`--partition`](#--partitionn) · [`--with-graph`](#--with-graph) · [`--export`](#--exportccjsonfile) · [`--batch`](#--batchfile)

**self-diagnosis** — [`--doctor`](#--doctor) · [`--agent`](#--agentcodexclaude) · [`--skipped`](#--skipped)

**security — scan skill files for injection / exfiltration patterns (exit 2 = CRITICAL, 1 = WARN,** — [`--scan-skill`](#--scan-skillfile) · [`--scan-skills`](#--scan-skillsdir) · [`--force`](#--force)

**knobs / modes** — [`--rank-by`](#--rank-bypagerankauthorityhubrrfchurnchurn-decay) · [`--in`](#--indir) · [`--format`](#--formatxmlcolumnarrows) · [`--format`](#--formatcandidates) · [`--legend`](#--legendfullcompact) · [`--legend-dict`](#--legend-dictroster) · [`--json`](#--json) · [`--limit`](#--limitn---offsetm) · [`--exclude`](#--excludesubstr) · [`--map-diff`](#--map-diff) · [`--cache`](#--cachepath) · [`--index-out`](#--index-outbase) · [`--no-cache`](#--no-cache) · [`--no-ignore`](#--no-ignore) · [`--max-file-size`](#--max-file-sizenkmg) · [`--max-memory`](#--max-memorynkmg) · [`--refetch`](#--refetch) · [`--scip`](#--scipindexscip) · [`--pin-census`](#--pin-censusfile) · [`--mcp`](#--mcp) · [`--mcp-legend`](#--mcp-legendwhen) · [`--mcp-tools`](#--mcp-toolslist) · [`--lsp`](#--lsp) · [`--listen`](#--listenhostport) · [`--mcp-token`](#--mcp-tokent) · [`--allow-remote-edits`](#--allow-remote-edits) · [`--eval-stray`](#--eval-strayfile) · [`--eval`](#--eval) · [`--eval-retrieval`](#--eval-retrieval) · [`--eval-mined`](#--eval-minedfile) · [`--eval-skills`](#--eval-skillsfile) · [`-h`](#-h---help) · [`-v`](#-v---version)

---

## understand a codebase cold

### `--top-k=N`

**Answers:** keep only the N highest-ranked symbols (default 200) keep the N highest-ranked symbols (default 200) — applies to the default map, plain --query, and --format=candidates (incl.

with --for). --for's OWN signature/lego/compose bundle self-limits via --pack-top-n instead — --top-k is INERT there (documented, not fixed — a real fix is a behavior change); to WIDEN a --for answer use --limit=N, the file-grain page (one row per file), not --top-k. --pack-task/--from-trace/--run-trace self-budget via --token-budget, not --top-k. --top-k=0 emits NO ranked map at all — ONLY the payload you asked for (--expand/--outline/--pack-signatures/--pack-top-n). Use it when you want the body and not the ~200-symbol map that otherwise rides along with it; the <ctx> root then carries est_tokens= (the payload's price, the number --token-budget gates on), since no map header is there to carry it.

**Try it**

_Same map, capped to the 5 highest-ranked symbols._

```
$ ./build/ripwire . --top-k=5
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. overloads=N: N same-name defs merged in this row; shown= counts each. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. <c via="name">: that callee matched by name alone (receiver unproven); it does NOT mean the edge is false. <c x=N>: N same-named via=name rows merged; callees=FILE:SYM lists all. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- files=2688 symbols=25558 edges=40392 shown=5 est_tokens=1219 ambiguous=12495 unresolved=12552 locality_pinned=11 external=7267 declined=12204 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:73,tsv:49,jsonl:26,mod:25,scm:23,expected:15" unindexed_exts=20 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="1219" pr_iters="28">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="buf" sc="svector" overloads="2" k="0.0070">
</s>
</f>
<f p="src/resolve.h">
<s t="method" n="empty" sc="RubyConstantIndex" amb="1" k="0.0066">
<c n="empty" prov="split" via="name" x="3"/>
</s>
</f>
<f p="src/infra/os_win32_logic.h" layer="infra">
... [11 more line(s); run it to see the whole thing]
```

**Shaped by:** `--token-budget`, `--for`, `--recall`, `--graph-query`, `--pack-signatures`, `--expand`, `--from-trace`, `--run-trace`

**Caveats (stated by the binary):**

- --for's OWN signature/lego/compose bundle self-limits via --pack-top-n instead — --top-k is INERT there (documented, not fixed — a real fix is a behavior change);
- to WIDEN a --for answer use --limit=N, the file-grain page (one row per file), not --top-k.

### `--max-tokens=N`

**Answers:** budget the map to ~N tokens (binary-search top-K) — SHAPES the map to fit.

THE FIT IS A BYTE CEILING, and it is deliberately CONSERVATIVE: N is converted at 2.36 B/tok (the densest calibrated language, so N holds for any corpus) times a 0.90 headroom factor. The map's own est_tokens uses THIS corpus's language-weighted rate instead, so a conformant fit REPORTS a number below the N you asked for — expect ~10-20% of N unused. The shaped map discloses both: max_tokens=N (asked) and fit_bytes=B (honoured). Consequence for composing it with --token-budget=N below: the two Ns are different units, so the same N on both is NOT a tautology. At a SMALL N the map's fixed floor (envelope + legend) can exceed fit_bytes with even one symbol emitted — that map says over_ceiling=1 rather than overshoot in silence, and its est_tokens can then exceed N. XML only: the --json map carries no max_tokens=/fit_bytes= keys yet, and its fit is measured in XML bytes. On --recall it SHAPES the doc bundle, and the ceiling is SPLIT ACROSS the docs rather than handed to the top hit: the budget serves the longest rank PREFIX it can give each doc a readable slice, then divides the bytes equally — a doc needing LESS than its share takes only what it needs and the surplus flows to the ones needing more. One long top hit no longer erases the rest of the corpus, and a bigger ceiling never returns FEWER docs. Docs past the prefix are dropped from the BOTTOM of the ranking; selection ORDER never changes. Every cut is DISCLOSED (header total=/shown=/capped=/truncated=/share_bytes=, a per-doc [truncated: X of Y bytes] marker, and a closing (capped: …) note); share_bytes= is that per-doc ceiling and is ABSENT when it bound no doc. On --for --detail=N it bounds THE BODIES ALONE: the header, signatures, legend and symbol table are not charged against it, so the bundle can price past N. That is deliberate — a ceiling bounds the tail and never the head, and a complete small answer is not worth cutting to fit — so the root DISCLOSES the overshoot instead, carrying over_ceiling="1" beside max_tokens=N whenever est_tokens exceeds N. Reach for --token-budget=N when the whole DOCUMENT must be bounded; this flag SHAPES.

**Try it**

_SHAPE the map to fit ~1500 tokens (binary-search top-K)._

```
$ ./build/ripwire . --max-tokens=1500
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). over_ceiling=1: budget not met. root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. max_tokens=/fit_bytes=: tokens asked/the byte cap applied. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- files=2688 symbols=25558 edges=40392 shown=1 est_tokens=900 ambiguous=12495 unresolved=12552 locality_pinned=11 external=7267 declined=12204 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:73,tsv:49,jsonl:26,mod:25,scm:23,expected:15" unindexed_exts=20 max_tokens=1500 fit_bytes=3186 over_ceiling=1 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="900" pr_iters="28">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="buf" sc="svector" k="0.0070">
</s>
</f>
</r>
```

**Shaped by:** `--token-budget`, `--recall`, `--detail`, `--pr-context`, `--from-trace`, `--run-trace`, `--limit`

**Caveats (stated by the binary):**

- THE FIT IS A BYTE CEILING, and it is deliberately CONSERVATIVE: N is converted at 2.36 B/tok (the densest calibrated language, so N holds for any corpus) times a 0.90 headroom factor.
- Consequence for composing it with --token-budget=N below: the two Ns are different units, so the same N on both is NOT a tautology.
- At a SMALL N the map's fixed floor (envelope + legend) can exceed fit_bytes with even one symbol emitted — that map says over_ceiling=1 rather than overshoot in silence, and its est_tokens can then exceed N.

### `--token-budget=N[K|M|G]`

**Answers:** cap the whole document at N tokens — a hard gate on the map, a trim-to-fit on the task lenses two personalities depending on the verb: - default map / --query / --recall: a CI GATE — exit 3 if the emitted DOCUMENT's est_tokens exceeds N.

That is the map PLUS every block appended after it (<sigs>/<src>/<bodies>/<outline>), each charged from the bytes it actually emits at the calibrated rate for what those bytes are — so --pack-top-n=3 --token-budget=600 gates on the ~67KB it would stream, not on the map alone. (test/tokenbudgetcheck.sh reports the live MAPE vs tiktoken o200k when tiktoken is installed; the estimate is calibrated, never exact — Claude's tokenizer is not public.) Within budget: exit 0, output unchanged. ASSERTS and fails, vs --max-tokens which shapes to fit — composable: set neither, either, or both (e.g. --max-tokens=16000 --token-budget=16K), but see --max-tokens above: the two Ns are measured in different units. Over budget, nothing of the artifact reaches stdout — only a small record naming withheld_est_tokens= vs budget=, the same vocabulary --recall uses, since est_tokens= is normatively about what a run PRINTED. On --recall the check likewise runs BEFORE a byte of the bundle is emitted: stdout gets the header line naming what was withheld, never the artifact just rejected. --json GATES AT A DIFFERENT NUMBER for the same request, and NOT by a fixed factor: the flag measures the DOCUMENT that was emitted, and whether JSON or XML is smaller flips with RESULT SIZE on this corpus. Small: JSON wins (MEASURED on src --top-k=20: est_tokens 1146 XML vs 899 JSON, ~22% smaller). Large: XML wins instead (MEASURED on src --top-k=200: est_tokens 9405 XML vs 9724 JSON, ~3% LARGER) — the crossover sits near top-k~100-150 here, so the same N can pass or fail differently under --json depending on dialect AND size — never assume one direction, measure the request you actually gate. - --for / --pack-task / --from-trace / --run-trace: SHAPES instead of gating — overrides that lens's own default payload budget and trims to fit, always exit 0. --for's header reports est_tokens="N" so its fit is checkable; --pack-task/--from-trace report their budget ledger in the header report line instead. On --for's auto bundle the ceiling is SPLIT, not handed to the signatures first: the sig side's claim caps at the default sig budget and the rest flows to the inline bodies, so a wider ceiling never serves fewer of them (see --for below). Its VERBATIM task echo is bytes no trim can shrink, so past some task length the header floor alone exceeds the ceiling: the lens drops the comment's DUPLICATE echo first (task_echo: dropped (ceiling); task= keeps the verbatim copy), then labels it over_ceiling (--recall: over_ceiling=1) — never a trim it did not actually do.

**Try it**

_GATE form: exit 3 if the map's own est_tokens exceeds the budget (over-budget failure shape)._

```
$ ./build/ripwire . --token-budget=100
<!-- ripwire map schema=ripwire.map/v1: the ranked map WITHHELD whole, no rows: withheld=1 marks this record, withheld_est_tokens= the map's price, over budget= (the token budget asked); rerun with a larger token budget, or max-tokens to shape a map that fits. -->
<r schema="ripwire.map/v1" withheld_est_tokens="8816" budget="100" withheld="1"/>
```

**Shaped by:** `--top-k`, `--max-tokens`, `--for`, `--recall`, `--handoff`, `--pr-context`, `--from-trace`, `--run-trace`

**Caveats (stated by the binary):**

- That is the map PLUS every block appended after it (<sigs>/<src>/<bodies>/<outline>), each charged from the bytes it actually emits at the calibrated rate for what those bytes are — so --pack-top-n=3 --token-budget=600 gates on the ~67KB it would stream, not on the map alone.
- the estimate is calibrated, never exact — Claude's tokenizer is not public.) Within budget: exit 0, output unchanged.
- On --recall the check likewise runs BEFORE a byte of the bundle is emitted: stdout gets the header line naming what was withheld, never the artifact just rejected.

### `--help-task=TASK`

**Answers:** describe a task, get ONE recommended command back — or an honest abstention deterministic enhanced help: recommend ONE executable Ripwire CLI command for this repository and task, or abstain when evidence/applicability is insufficient.

Reports the intent, integer score/margin and repository facts; never calls a model, executes the recommendation, or accesses the network. Structured claims/traces/symbols outrank lexical cues. Recommendation only; pipe trace text to stdin for --from-trace=-. A symbol NAME resolves as evidence only when it is identifier-shaped (camelCase, PascalCase, snake_case, a ::/. scope) or marked as code in the task text -- a short bare word (a lone letter, a SCREAMING name, or an ordinary word that happens to match an indexed name, e.g. django's F) does not resolve on its own. Wrap it in backticks (task text: `F`) or write it in call form (F()) to route on it by name.

**Try it**

_The honest half of the contract: a task with no ripwire-shaped evidence ABSTAINS with zero commands rather than guessing._

```
$ ./build/ripwire . --help-task="write a cheerful release announcement"
<!-- ripwire help-task schema=ripwire.help-task/v1: which verb answers this task: status=recommend|abstain confidence= score= margin=, <facts> the evidence. git=/dirty=: the root is a git repo / its tree differs from HEAD (the stamp's +dirty). trace=1: the task text has a stack/sanitizer trace shape; it routes to from-trace. resolved_symbols=N: indexed names the task NAMES; a bare short/common word needs backticks or F(). -->
<task-route schema="ripwire.help-task/v1" status="abstain" confidence="none" score="0" margin="0">
<facts git="1" dirty="0" trace="0" resolved_symbols="0"/>
</task-route>
```

**Caveats (stated by the binary):**

- never calls a model, executes the recommendation, or accesses the network.

### `--for=TASK`

**Answers:** the task lens: say what you are doing, get the signatures and bodies to read first the task lens: ranked signatures + metrics framed for reuse.

The bundle enforces a ~7.5KB default payload budget (tail entries trim first; <sigs shown=S total=T capped="1"> marks it: T rows handed to the trim, S printed). The r=1 (top-ranked) <d> row carries next="--expand=FILE:NAME" — the one pasteable follow-up, the body that ends the search (defined here, not in the bundle's own header, which the token ladder does not charge). An explicit --token-budget=N overrides the default at the conservative byte rate (SHAPES, exit 0; see --token-budget above) and the header reports the delivered est_tokens. TERMINAL BY DEFAULT: after the signatures, the top-ranked symbols' FULL bodies ride inline (CDATA + callee signatures, the --expand shape) under a fixed extra body allowance — whole-body-or-not-at-all, rank-first, capped at the --pack-task candidate cap (6). The <ctx> root discloses it: bundle="auto" bodies="N" (bodies="0" reason="budget" when none fit) — on EVERY auto-mode run: a ceiling the signatures alone exhaust still carries the attribute (legend and empty <bodies> shell dropped there; only the attribute has reserved bytes), and --for --json, which serves no bodies by design, says so with "bundle":"sigs". Only the caller-chosen postures (--signatures-only, --detail=N) are attribute-free. ANCHOR-ONLY when the route names one: a query that NAMES a symbol gets THAT symbol's own body or NO body — never a same-named doc section, type stub or re-export shim from another file standing in for it. If the anchor's own body does not fit, the bundle serves nothing and says so, and the per-item over-budget comment names what was dropped. COMPACT ON THE CONCEPTUAL ROUTE: a query that anchors nothing (subtoken+body) gets the ranked map plus a <hops> section — the same candidate head's ONE-HOP callee signatures, the <calls> block a body carries — and NO body CDATA, disclosed as bundle="compact" bodies="0" reason="compact-route". Read the map, then --expand=SYM the one you want. --auto-bodies restores the body walk there. That shape discloses on every run too: a ceiling the signatures alone exhaust carries bundle="compact" bodies="0" reason="budget" — three distinct reasons, never collapsed (compact-route = the route chose edges, no_candidates = nothing scored, budget = the ceiling was spent). An explicit --token-budget=N is a hard ceiling, split so a wider ceiling never buys less: the signature side's claim is capped at the DEFAULT ~7.5KB sig budget and every byte beyond it flows to the enrichment — at any ceiling at or above the default's effective total the <sigs> block is byte-identical to the default run's, so every body (or hop row) the default serves still fits. An explicit --pack-top-n is an explicit SIG posture and keeps the whole-ceiling sig claim. --compress composes: the served bodies (auto/anchor and --detail=N alike) go through the same comment-strip --expand uses, disclosed as compress="1" on the <bodies> element (nothing to strip on the compact route). RANKING CONFIDENCE, disclosed not scored: the <ctx> root always carries confidence="high|low" margin_pct="N" — derived from the SAME relevance-cliff gap statistic --adaptive cuts at (no new scorer, no behavior change; the --json dialect carries the same two keys). low means the ranking is FLAT (no material score cliff and more positive matches than the head shows) — treat the set as a starting point, not an answer; high means a material cliff inside the served head (margin_pct= is that drop as a whole percent) or every positive match already shown. COVERAGE, and the widening page: on a THIN answer only, the root also carries coverage="N" — the IDF-weighted share (whole percent) of the task's subtokens found in the top-ranked symbol's name, doc or body; an unmatched subtoken weighs as the rarest, so a "(#12147)" token honestly lowers it. THIN = coverage under 50, or a ranked head spread over fewer than 3 files: coverage= and its legend clause ride the root (present-only: a confident answer carries neither) and the r=1 row's next= names --for=TASK --limit=40 instead of --expand — the FILE-GRAIN WIDENING PAGE: <files task= route= root= coverage= shown= total= capped= …><f p= score= n= sym=/>…, ONE row per positive-score file (~100 B each), ranked file-first by score= = the IDF-weighted share of the task's subtokens the file's top 8 symbols cover between them (a term counts once however often it recurs, so one huge file cannot monopolise; ties by the best symbol's lens score, then path), n= its positive-score symbols, sym= its top symbols. --limit=N sets the rows, --offset=M pages (the house quintet + next= on a cut page). The page takes NO bundle-shaping flag (--json, --format=candidates, --detail, --signatures-only, --auto-bodies, --adaptive, --token-budget, --top-k …): each is refused beside --limit, never ignored. Measured on the routing-loop ladder (RocksDB, frozen 30): the follow-up that completes answers where a body cannot. <lego>/<compose> COLLAPSE TO A COUNTED STUB BY DEFAULT (L2, a disclosed cut, never a silent one): when the ranked set names an interface with implementors, or a HAS-A field edge into/out of it, the bundle used to spend the full <iface>/<m>/<impl> method contract or <field> row list on it — the STUB instead says only how many rows the section held: <lego total="N" shown="0" capped="1" next="…"/> (same shape for <compose>). No stub for a section that would be EMPTY (an absent section stays absent). total= is that section's own pre-cap row count (packLego's post-dedup interface count; every matched HAS-A edge for compose, which caps nothing). next= carries the one restoring spelling that returns BOTH sections byte-identical to the un-stubbed render, in ONE call: --sections=lego,compose.

**Try it**

_Name-shaped query: the router picks name-exact BM25 (header says which/why)._

```
$ ./build/ripwire . --for="rankGraphTeleport"
<ctx task="rankGraphTeleport" route="name-exact(rankGraphTeleport); anchors: rankGraphTeleport(src/graph.h)" root="." confidence="high" margin_pct="45" at="f1e5c2e76" doc_mentions="2" schema="ripwire.for/v1" bundle="auto" bodies="1" doc_mentions_capped="1" doc_mentions_total="13" est_tokens="1510">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); b t= n= p= l= full bodies, c n= l= callee signatures; t p= file outside sigs (weaker), r= rank (gap = trimmed); d e= its last line (absent=unknown, never 0; l= the name's line); c via=name: that callee matched by name alone, receiver unproven (NOT a claim the edge is false) [doc mentions: 2 docs, 1 symbol; doc_mentions=] [floor: kept 3 of 40] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). [cut: doc_mentions_capped="1" doc_mentions_total="13" — an indexing cap dropped content not shown here] est_tokens= prices this bundle in tokens -->
<sigs>
<d l="7924" e="7952" n="rankGraphTeleport" sc="rw" p="src/graph.h" cx="5" ccx="8" in="7" churn="287" amp="433" r="1" next="--expand=src/graph.h:rankGraphTeleport">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quality-biased through biasPrior() so all rank modes share one weighting seam; the transition matrix (edges</doc>inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&am … [line truncated: 31 more bytes on this line]
<d l="462" n="The convergence disclosure contract" sc="rank — Personalized PageRank" p="docs/ARCHITECTURE.md" churn="53" amp="154" r="2">#### The convergence disclosure contract</d>
<d l="6339" n="Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`" sc="6. Correctness and quality instruments" p="docs/EVALS.md" churn="865" amp="1078" r="3">### Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`</d>
</sigs>
<tail total="0" shown="0" capped="0">
</tail>
<bodies shown="1" total="1" capped="0">
<b t="fn" l="7924" p="src/graph.h" n="rankGraphTeleport">
<![CDATA[inline RankedGraph rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--top-k`, `--max-tokens`, `--token-budget`, `--sections`, `--signatures-only`, `--auto-bodies`, `--no-route`, `--adaptive`

**Caveats (stated by the binary):**

- <sigs shown=S total=T capped="1"> marks it: T rows handed to the trim, S printed).
- TERMINAL BY DEFAULT: after the signatures, the top-ranked symbols' FULL bodies ride inline (CDATA + callee signatures, the --expand shape) under a fixed extra body allowance — whole-body-or-not-at-all, rank-first, capped at the --pack-task candidate cap (6).
- ANCHOR-ONLY when the route names one: a query that NAMES a symbol gets THAT symbol's own body or NO body — never a same-named doc section, type stub or re-export shim from another file standing in for it.

### `--sections=lego,compose`

**Answers:** (with --for) opt back into the full <lego>/<compose> render the stub above replaces (with --for=TASK) restore the <lego>/<compose> sections the ranked bundle collapses to a counted stub by default — this IS the stub's own next= spelling, so pasting it back unchanged is enough.

A comma-separated, order-insensitive, closed set (lego and/or compose, each named at most once); every other section of the bundle is unaffected.

**Try it**

_Restore the <lego>/<compose> sections the --for bundle collapses to a counted stub by default (this is the stub's own next= spelling)._

```
$ ./build/ripwire . --for="tree-sitter parse of a source file" --sections=lego,compose
<ctx task="tree-sitter parse of a source file" route="subtoken+body" root="." confidence="low" margin_pct="0" at="f1e5c2e76" doc_mentions="3" schema="ripwire.for/v1" bundle="compact" bodies="0" reason="compact-route" budget_bytes="7500" est_tokens="3914">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); h l= p= n=, c n= l= (joined for same-named callees, shown= counts them), noedge= no callee resolved; t p= file outside sigs (weaker), r= rank (gap = trimmed); field name= type= owner= rel=: a member of owner=, rel=creates held by value, uses by reference/pointer; iface implementors=N: types implementing it, m= its method contract; d layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; d e= its last line (absent=unknown, never 0; l= the name's line); c via=name: that callee matched by name alone, receiver unproven (NOT a claim the edge is false) [doc mentions: 3 docs, 2 symbols; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="11" [budget_bytes= is the default BYTE ceiling this ranked payload was shaped against; it bounds that payload, not the whole document est_tokens prices] [sigs next=: one call serving all total= rows uncut] [sigs next_offset=: the candidate index the cut starts at; no consumer yet (the for offset pages files; next= re-runs the list)] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] est_tokens= prices this bundle in tokens -->
<sigs shown="29" total="40" capped="1" docs_dropped="22" next_offset="29" next="--for=&apos;tree-sitter parse of a source file&apos; --signatures-only --token-budget=6000">
<d l="28" e="63" n="topLevelEvidence" sc="rw::pythonrunner" p="src/pythonrunner.h" cx="4" ccx="3" in="2" churn="5" amp="15" r="1" next="--expand=src/pythonrunner.h:topLevelEvidence">inline bool topLevelEvidence( std::string_view source, const TSLanguage* language, const Predicate&amp; predicate )</d … [line truncated: 1 more bytes on this line]
<d l="45" e="45" n="kDefaultMaxFileBytes" sc="rw" p="src/ingest.h" churn="57" amp="162" pure="1" r="2">
<doc>The crawl&apos;s per-file byte ceiling. A text file larger than this is skipped: at this size it is o…</doc>constexpr std::size_t kDefaultMaxFileBytes = 4u * 1024u * 1024u</d>
<d l="1153" e="1161" n="parseTree" p="src/ingest_sidecap.h" cx="1" in="2" churn="93" amp="242" tested="1" r="3">TSTree* parseTree( TSParser* parser, std::string_view src )</d>
<d l="588" e="661" n="doctorProbeGrammars" p="src/verbs_doctor.h" cx="7" ccx="17" in="1" churn="43" amp="127" r="4">
<doc>Exercise every registered grammar and its embedded query, reporting loaded and expected totals</doc>inline DoctorGrammarProbe doctorProbeGrammars()</d>
... [21 more line(s); run it to see the whole thing]
```

**Shaped by:** `--for`

### `--signatures-only`

**Answers:** (with --for) signatures only: no automatic bodies in the bundle (with --for) opt out of the terminal-by-default bundle: no auto bodies, no bundle="auto" attribute — the signatures-only lens exactly as before.

Contradicts --detail=N (refused together); --detail=N remains the explicit body knob and supersedes the automatic pick

**Try it**

_T3 opt-out: the signatures-only lens (no auto bodies, no bundle="auto" attribute) — contrast with the terminal default above._

```
$ ./build/ripwire . --for="rankGraphTeleport" --signatures-only
<ctx task="rankGraphTeleport" route="name-exact(rankGraphTeleport); anchors: rankGraphTeleport(src/graph.h)" root="." confidence="high" margin_pct="45" at="f1e5c2e76" doc_mentions="2" schema="ripwire.for/v1" doc_mentions_capped="1" doc_mentions_total="13" est_tokens="878">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); t p= file outside sigs (weaker), r= rank (gap = trimmed); d e= its last line (absent=unknown, never 0; l= the name's line) [doc mentions: 2 docs, 1 symbol; doc_mentions=] [floor: kept 3 of 40] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). [cut: doc_mentions_capped="1" doc_mentions_total="13" — an indexing cap dropped content not shown here] est_tokens= prices this bundle in tokens -->
<sigs>
<d l="7924" e="7952" n="rankGraphTeleport" sc="rw" p="src/graph.h" cx="5" ccx="8" in="7" churn="287" amp="433" r="1" next="--expand=src/graph.h:rankGraphTeleport">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quality-biased through biasPrior() so all rank modes share one weighting seam; the transition matrix (edges</doc>inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&am … [line truncated: 31 more bytes on this line]
<d l="462" n="The convergence disclosure contract" sc="rank — Personalized PageRank" p="docs/ARCHITECTURE.md" churn="53" amp="154" r="2">#### The convergence disclosure contract</d>
<d l="6339" n="Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`" sc="6. Correctness and quality instruments" p="docs/EVALS.md" churn="865" amp="1078" r="3">### Wave-2 adversarial verification (2026-08-19) — six probes against `aa97c9e`</d>
</sigs>
<tail total="0" shown="0" capped="0">
</tail>
</ctx>
```

**Shaped by:** `--for`, `--auto-bodies`

**Caveats (stated by the binary):**

- Contradicts --detail=N (refused together);

### `--auto-bodies`

**Answers:** (with --for) restore the automatic body walk on the conceptual route (with --for) opt out of COMPACT conceptual serving: restore the rank-first auto <bodies> walk on the subtoken+body route (bundle="auto", up to 6 full bodies) instead of the <hops> edge section.

Inert on the name-exact route, where the allowance already runs. Contradicts --signatures-only and --detail=N (refused with either)

**Try it**

_Opt OUT of compact conceptual serving: restore the rank-first auto <bodies> walk (bundle="auto")._

```
$ ./build/ripwire . --for="tree-sitter parse of a source file" --auto-bodies
<ctx task="tree-sitter parse of a source file" route="subtoken+body" root="." confidence="low" margin_pct="0" at="f1e5c2e76" doc_mentions="3" schema="ripwire.for/v1" bundle="auto" bodies="4" budget_bytes="7500" est_tokens="4655">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); b t= n= p= l= full bodies, c n= l= callee signatures; t p= file outside sigs (weaker), r= rank (gap = trimmed); field name= type= owner= rel=: a member of owner=, rel=creates held by value, uses by reference/pointer; iface implementors=N: types implementing it, m= its method contract; d layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; d e= its last line (absent=unknown, never 0; l= the name's line); c via=name: that callee matched by name alone, receiver unproven (NOT a claim the edge is false) [doc mentions: 3 docs, 2 symbols; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="11" [budget_bytes= is the default BYTE ceiling this ranked payload was shaped against; it bounds that payload, not the whole document est_tokens prices] [sigs next=: one call serving all total= rows uncut] [sigs next_offset=: the candidate index the cut starts at; no consumer yet (the for offset pages files; next= re-runs the list)] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)]; lego/compose collapse to a counted stub by default (a disclosed cut): total= that section's own pre-cap row count, shown="0" capped="1" (nothing rendered here), next= names the sections=lego,compose flag that restores both sections byte-identically in one call est_tokens= prices this bundle in tokens -->
<sigs shown="29" total="40" capped="1" docs_dropped="22" next_offset="29" next="--for=&apos;tree-sitter parse of a source file&apos; --signatures-only --token-budget=6000">
<d l="28" e="63" n="topLevelEvidence" sc="rw::pythonrunner" p="src/pythonrunner.h" cx="4" ccx="3" in="2" churn="5" amp="15" r="1" next="--expand=src/pythonrunner.h:topLevelEvidence">inline bool topLevelEvidence( std::string_view source, const TSLanguage* language, const Predicate&amp; predicate )</d … [line truncated: 1 more bytes on this line]
<d l="45" e="45" n="kDefaultMaxFileBytes" sc="rw" p="src/ingest.h" churn="57" amp="162" pure="1" r="2">
<doc>The crawl&apos;s per-file byte ceiling. A text file larger than this is skipped: at this size it is o…</doc>constexpr std::size_t kDefaultMaxFileBytes = 4u * 1024u * 1024u</d>
<d l="1153" e="1161" n="parseTree" p="src/ingest_sidecap.h" cx="1" in="2" churn="93" amp="242" tested="1" r="3">TSTree* parseTree( TSParser* parser, std::string_view src )</d>
<d l="588" e="661" n="doctorProbeGrammars" p="src/verbs_doctor.h" cx="7" ccx="17" in="1" churn="43" amp="127" r="4">
<doc>Exercise every registered grammar and its embedded query, reporting loaded and expected totals</doc>inline DoctorGrammarProbe doctorProbeGrammars()</d>
<d l="1427" e="1438" n="FileHealth" sc="FileHealth" p="src/model.h" churn="160" amp="338" r="5">struct FileHealth</d>
... [20 more line(s); run it to see the whole thing]
```

**Shaped by:** `--for`

**Caveats (stated by the binary):**

- Inert on the name-exact route, where the allowance already runs.
- Contradicts --signatures-only and --detail=N (refused with either)

### `--no-route`

**Answers:** (with --for) skip the query-shape router and always rank by subtoken+body BM25 (with --for/--query) force plain subtoken+body BM25.

Routing is now the DEFAULT: a deterministic, confidence-gated query-shape router picks name-exact BM25 when the query NAMES a symbol (identifier syntax, or every content word is a symbol name) else subtoken+body, and prints which/why in the header. It only routes with a query (the plain map is unaffected). --no-route restores the old behavior. A name-exact header also names its EVIDENCE: anchors: word(defining/file) per anchoring word, +N when N further definitions share that name, or word(syntax) when the word routed on camel/snake SHAPE and names nothing. Paths deeper than two segments print top/.../basename. Discount a one-use test helper yourself. Routing also carries the QUERY-SHAPE document demotion: when the task text parses as a stack trace, sanitizer report or compiler diagnostic, or as a pasted issue-template form, the DOCUMENT tier scores down (repo meta-prose - issue templates, CONTRIBUTING, changelogs - twice as hard) and route= names the shape, its evidence and both factors. Demotion, never exclusion, and the mention anchor still lifts a document the task NAMES. --no-route has no route= to disclose it in, so it does not demote either. Routing also puts CHANGE LOGS (CHANGELOG*, CHANGES*, HISTORY*, NEWS*, RELEASES*, release-notes/) and TRANSLATIONS of a default-language doc (README.zh-CN.md beside README.md, docs/ja/x.md beside docs/en/x.md) LAST in doc-mention surfacing, lifted to x0.35 of the usual height; their own match score is untouched. A task about changes (added, changed, removed, release, version...), about translation, or naming the file or its language tag keeps the usual lift; --no-route turns it off. route= is a CODE: name-exact(X) = the task names symbol X (the anchors: clause after it is the evidence); subtoken+body = the conceptual ranker over names and bodies; subtoken+body:broad = a one- or two-word query where plain rg may also win; subtoken+body:declined(word;N-carriers,M-defs) = a name hit refused because the word is a common name (N names carry it, M definitions); a shape demotion appends "; doc tier demoted (...)". On the rows, sc= is the enclosing scope and the full id is p::sc::n (p= of the row or its <f>) - the spelling --expand/--callers/--impact/--uses accept.

**Try it**

_Same query with routing forced OFF (plain subtoken+body BM25) — contrast with the routed run._

```
$ ./build/ripwire . --for="rankGraphTeleport" --no-route
<ctx task="rankGraphTeleport" root="." confidence="low" margin_pct="0" at="f1e5c2e76" doc_mentions="6" schema="ripwire.for/v1" bundle="auto" bodies="3" budget_bytes="7500" doc_mentions_capped="1" doc_mentions_total="20" est_tokens="5245">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; confidence=/margin_pct= head score drop (low=flat); b t= n= p= l= full bodies, c n= l= callee signatures; t p= file outside sigs (weaker), r= rank (gap = trimmed); field name= type= owner= rel=: a member of owner=, rel=creates held by value, uses by reference/pointer; d layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; d e= its last line (absent=unknown, never 0; l= the name's line); c via=name: that callee matched by name alone, receiver unproven (NOT a claim the edge is false) [doc mentions: 6 docs, 3 symbols; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="18" [budget_bytes= is the default BYTE ceiling this ranked payload was shaped against; it bounds that payload, not the whole document est_tokens prices] [sigs next=: one call serving all total= rows uncut] [sigs next_offset=: the candidate index the cut starts at; no consumer yet (the for offset pages files; next= re-runs the list)] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] [cut: doc_mentions_capped="1" doc_mentions_total="20" — an indexing cap dropped content not shown here]; lego/compose collapse to a counted stub by default (a disclosed cut): total= that section's own pre-cap row count, shown="0" capped="1" (nothing rendered here), next= names the sections=lego,compose flag that restores both sections byte-identically in one call est_tokens= prices this bundle in tokens -->
<sigs shown="22" total="40" capped="1" docs_dropped="15" next_offset="22" next="--for=rankGraphTeleport --signatures-only --no-route --token-budget=7000">
<d l="7965" e="7969" n="rankGraph" sc="rw" p="src/graph.h" cx="2" ccx="1" in="10" churn="287" amp="436" r="1" next="--expand=src/graph.h:rankGraph">
<doc>uniform-teleport PageRank (the default</doc>inline RankedGraph rankGraph( const Graph&amp; g, float alpha = 0.85f )</d>
<d l="7924" e="7952" n="rankGraphTeleport" sc="rw" p="src/graph.h" cx="5" ccx="8" in="7" churn="287" amp="433" r="2">
<doc>PageRank with an explicit teleport / personalization vector p (Σp = 1). The prior is name-quali…</doc>inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )</d>
<d l="1422" e="1461" n="churnRankedGraph" p="src/main.cpp" cx="10" ccx="12" in="1" churn="424" amp="524" r="3">inline ChurnRanking churnRankedGraph( const MainDispatch&amp; d )</d>
<d l="2228" e="2232" n="kChurnRankLegend" sc="rw" p="src/serialize.h" churn="293" amp="414" pure="1" r="4">
<doc>L10 (2026-09-04): the old wording claimed &quot;the same corpus ranked by pagerank orders differently…</doc>inline constexpr const char* kChurnRankLegend = &quot;&lt;!-- rank_by=churn: k= is PageRank re-run with the teleport BIASED by git CHANGE-FREQUENCY over window= &quot; &quot;(a c…</d>
... [20 more line(s); run it to see the whole thing]
```

**Caveats (stated by the binary):**

- (with --for) skip the query-shape router and always rank by subtoken+body BM25 (with --for/--query) force plain subtoken+body BM25.
- Demotion, never exclusion, and the mention anchor still lifts a document the task NAMES.
- subtoken+body:declined(word;N-carriers,M-defs) = a name hit refused because the word is a common name (N names carry it, M definitions);

### `--adaptive`

**Answers:** (with --for/--query) cut the result at the relevance cliff instead of at a fixed K (with --for/--query) cut the result at the relevance CLIFF — the largest relative score gap (Adaptive-k), floor 5, ceiling = the existing top-k;

a sharp query returns few, a flat/broad one hits the ceiling. Prints [adaptive: kept K of N ...] in the header. Without it, output is unchanged.

**Try it**

_Cut the result at the relevance cliff (Adaptive-k) — on a flat ranking nothing is cut and the header says so ([adaptive: kept N of N])._

```
$ ./build/ripwire . --for="tree-sitter parse of a source file" --adaptive
<ctx task="tree-sitter parse of a source file" route="subtoken+body" root="." confidence="low" margin_pct="0" at="f1e5c2e76" doc_mentions="3" schema="ripwire.for/v1" bundle="compact" bodies="0" reason="compact-route" budget_bytes="7500" est_tokens="3826">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); h l= p= n=, c n= l= (joined for same-named callees, shown= counts them), noedge= no callee resolved; t p= file outside sigs (weaker), r= rank (gap = trimmed); field name= type= owner= rel=: a member of owner=, rel=creates held by value, uses by reference/pointer; iface implementors=N: types implementing it, m= its method contract; d layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; d e= its last line (absent=unknown, never 0; l= the name's line); c via=name: that callee matched by name alone, receiver unproven (NOT a claim the edge is false) [adaptive: kept 40 of 40 - no relevance cliff (broad query saturates the score); capped at the ceiling] [doc mentions: 3 docs, 2 symbols; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="11" [budget_bytes= is the default BYTE ceiling this ranked payload was shaped against; it bounds that payload, not the whole document est_tokens prices] [sigs next=: one call serving all total= rows uncut] [sigs next_offset=: the candidate index the cut starts at; no consumer yet (the for offset pages files; next= re-runs the list)] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)]; lego/compose collapse to a counted stub by default (a disclosed cut): total= that section's own pre-cap row count, shown="0" capped="1" (nothing rendered here), next= names the sections=lego,compose flag that restores both sections byte-identically in one call est_tokens= prices this bundle in tokens -->
<sigs shown="29" total="40" capped="1" docs_dropped="22" next_offset="29" next="--for=&apos;tree-sitter parse of a source file&apos; --signatures-only --adaptive --token-budget=6000">
<d l="28" e="63" n="topLevelEvidence" sc="rw::pythonrunner" p="src/pythonrunner.h" cx="4" ccx="3" in="2" churn="5" amp="15" r="1" next="--expand=src/pythonrunner.h:topLevelEvidence">inline bool topLevelEvidence( std::string_view source, const TSLanguage* language, const Predicate&amp; predicate )</d … [line truncated: 1 more bytes on this line]
<d l="45" e="45" n="kDefaultMaxFileBytes" sc="rw" p="src/ingest.h" churn="57" amp="162" pure="1" r="2">
<doc>The crawl&apos;s per-file byte ceiling. A text file larger than this is skipped: at this size it is o…</doc>constexpr std::size_t kDefaultMaxFileBytes = 4u * 1024u * 1024u</d>
<d l="1153" e="1161" n="parseTree" p="src/ingest_sidecap.h" cx="1" in="2" churn="93" amp="242" tested="1" r="3">TSTree* parseTree( TSParser* parser, std::string_view src )</d>
<d l="588" e="661" n="doctorProbeGrammars" p="src/verbs_doctor.h" cx="7" ccx="17" in="1" churn="43" amp="127" r="4">
<doc>Exercise every registered grammar and its embedded query, reporting loaded and expected totals</doc>inline DoctorGrammarProbe doctorProbeGrammars()</d>
... [21 more line(s); run it to see the whole thing]
```

**Shaped by:** `--for`, `--detail`

**Caveats (stated by the binary):**

- (with --for/--query) cut the result at the relevance cliff instead of at a fixed K (with --for/--query) cut the result at the relevance CLIFF — the largest relative score gap (Adaptive-k), floor 5, ceiling = the existing top-k;

### `--no-mention-boost`

**Answers:** (with --for) stop lifting what the task text names: a path, module, Type.method or identifier (with --for) disable the query-mention anchor.

By DEFAULT, a file or dotted module literally NAMED in the task text (a path, `pkg.module` — even inside a URL) has its symbols' SCORE lifted to within 5% of the top score; the header says what anchored. That is a score promise, not a rank one: on a flat/tied head the anchored hit can still land several ranks below #1. A SYMBOL named directly takes the same first slot: `Type.method`, `ns::fn`, `mod.fn`, or a verbatim identifier with identifier shape (snake_case, camelCase), call syntax (`name()`; off for the WHOLE task once it carries pasted code: a ``` fence, an indented line or a stack trace) or backticks, defined in at most 3 files (each file's best definition, a prototype beside its definition counting once; test/fixture files only if the task names them). Up to 8 named symbols are lifted per task: `Type.method` matches first, which may fill all 8, then identifier-resolved symbols (bare, call syntax, `ns::fn`, or a dotted name that matched no `Type.method`), at most 2 of them, in text order. The 2 count definitions, not names: a name defined in two files spends both, and a prototype beside its definition adds none. Named symbols past either cap are disclosed by mention_syms_capped=. Only the first 64 identifiers are read, and the rest are disclosed by mention_idents_capped=. Plain words never qualify ("run the tests" lifts no run()). Inert (byte-identical) when the text names nothing indexed. RIPWIRE_NO_MENTION=1 disables it everywhere (incl. MCP `for`).

**Try it**

_Same task with the anchor disabled — the contrast the flag exists for._

```
$ ./build/ripwire . --for="why does src/lexical.h chooseForRanker pick name-exact BM25" --no-mention-boost
<ctx task="why does src/lexical.h chooseForRanker pick name-exact BM25" route="subtoken+body" root="." confidence="low" margin_pct="0" at="f1e5c2e76" doc_mentions="2" schema="ripwire.for/v1" bundle="compact" bodies="0" reason="compact-route" budget_bytes="7500" doc_mentions_capped="1" doc_mentions_t … [line truncated: 27 more bytes on this line]
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); h l= p= n=, c n= l= (joined for same-named callees, shown= counts them), noedge= no callee resolved; t p= file outside sigs (weaker), r= rank (gap = trimmed); field name= type= owner= rel=: a member of owner=, rel=creates held by value, uses by reference/pointer; iface implementors=N: types implementing it, m= its method contract; d layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; d e= its last line (absent=unknown, never 0; l= the name's line); c via=name: that callee matched by name alone, receiver unproven (NOT a claim the edge is false) [doc mentions: 2 docs, 1 symbol; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="12" [budget_bytes= is the default BYTE ceiling this ranked payload was shaped against; it bounds that payload, not the whole document est_tokens prices] [sigs next=: one call serving all total= rows uncut] [sigs next_offset=: the candidate index the cut starts at; no consumer yet (the for offset pages files; next= re-runs the list)] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] [cut: doc_mentions_capped="1" doc_mentions_total="3" — an indexing cap dropped content not shown here] est_tokens= prices this bundle in tokens -->
<sigs shown="28" total="40" capped="1" docs_dropped="19" next_offset="28" next="--for=&apos;why does src/lexical.h chooseForRanker pick name-exact BM25&apos; --signatures-only --no-mention-boost --token-budget=6200">
<d l="1769" e="1775" n="lexicalScoresNameExactRanked" sc="rw" p="src/lexical.h" cx="1" in="4" churn="62" amp="119" r="1" next="--expand=src/lexical.h:lexicalScoresNameExactRanked">
<doc>The name-exact ranker AS THE RETRIEVAL LENS SERVES IT: whole-name BM25 plus the definition-over-…</doc>inline std::vector&lt;float&gt; lexicalScoresNameExactRanked( const IngestResult&amp; ing, std::string_view query, const std::vector&lt;float&gt;* symbolScoreMul )</d>
<d l="158" e="169" n="printEvalRankerNote" sc="rw" p="src/eval.h" cx="1" in="1" churn="16" amp="29" r="2">
<doc>P11.12: the interpretive footer for --eval&apos;s ranker table, pulled into its own function so the 9…</doc>inline void printEvalRankerNote()</d>
<d l="713" e="792" n="runEvalRetrieval" sc="rw" p="src/eval.h" cx="7" ccx="10" in="1" churn="16" amp="29" r="3">inline int runEvalRetrieval( const IngestResult&amp; ing, const Graph&amp; g )</d>
<d l="140" e="140" n="kWeakLexicalScoreThreshold" sc="rw" p="src/lexical.h" churn="62" amp="115" pure="1" r="4">
... [21 more line(s); run it to see the whole thing]
```

**Caveats (stated by the binary):**

- That is a score promise, not a rank one: on a flat/tied head the anchored hit can still land several ranks below #1.
- Named symbols past either cap are disclosed by mention_syms_capped=.
- Only the first 64 identifiers are read, and the rest are disclosed by mention_idents_capped=.

### `--no-doc-mention`

**Answers:** (with --for) stop surfacing markdown docs that name the task's top symbols (with --for) disable doc-mention surfacing.

By DEFAULT, a markdown doc that names one of the task's top-resolved symbols in a `backtick` (the same doc<->code edges --mentions=SYM reads) is lifted into the bundle, strictly below that symbol's own score — closing the "the doc explains it but shares no words with the query" gap. Inert (byte-identical) when no resolved symbol has a mentioning doc. RIPWIRE_NO_DOC_MENTION=1 disables it everywhere (incl. MCP `for`/`pack_task`).

**Try it**

_The same task with doc-mention surfacing OFF — the contrast the flag exists for (no [doc mentions] clause, one fewer row)._

```
$ ./build/ripwire . --for="quality delta acks ledger rubber stamp" --no-doc-mention
<ctx task="quality delta acks ledger rubber stamp" route="subtoken+body" root="." confidence="low" margin_pct="0" at="f1e5c2e76" schema="ripwire.for/v1" bundle="compact" bodies="0" reason="compact-route" budget_bytes="7500" est_tokens="3890">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); h l= p= n=, c n= l= (joined for same-named callees, shown= counts them), noedge= no callee resolved; t p= file outside sigs (weaker), r= rank (gap = trimmed); field name= type= owner= rel=: a member of owner=, rel=creates held by value, uses by reference/pointer; iface implementors=N: types implementing it, m= its method contract; d layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; d e= its last line (absent=unknown, never 0; l= the name's line); c via=name: that callee matched by name alone, receiver unproven (NOT a claim the edge is false) -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="13" [budget_bytes= is the default BYTE ceiling this ranked payload was shaped against; it bounds that payload, not the whole document est_tokens prices] [sigs next=: one call serving all total= rows uncut] [sigs next_offset=: the candidate index the cut starts at; no consumer yet (the for offset pages files; next= re-runs the list)] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] est_tokens= prices this bundle in tokens -->
<sigs shown="27" total="40" capped="1" docs_dropped="18" next_offset="27" next="--for=&apos;quality delta acks ledger rubber stamp&apos; --signatures-only --no-doc-mention --token-budget=6300">
<d l="4095" e="4167" n="computeQualityDelta" sc="rw" p="src/mcpverbs.h" cx="4" ccx="4" in="1" churn="340" amp="423" r="1" next="--expand=src/mcpverbs.h:computeQualityDelta">inline QualityDeltaOutcome computeQualityDelta( const std::string&amp; root )</d>
<d l="467" e="502" n="refuseForeignAckSelection" p="src/verbs_quality.h" cx="9" ccx="12" in="1" churn="84" amp="194" r="2">std::optional&lt;int&gt; refuseForeignAckSelection( const rw::Config&amp; cfg, const rw::quality::Scope&amp; scope, const std::vector&lt;rw::quality::Regression&gt;&amp; outOfSc … [line truncated: 14 more bytes on this line]
<d l="1142" e="1806" n="runQualityDelta" p="src/verbs_quality.h" cx="117" ccx="296" in="1" churn="84" amp="194" r="3">
<doc>runQualityViews was NOT a dispatch chain — it held two branches, one of which was 298 lines. T…</doc>std::optional&lt;int&gt; runQualityDelta( const MainDispatch&amp; d )</d>
<d l="1002" e="1027" n="ackNothingToAccept" p="src/verbs_quality.h" cx="6" ccx="7" in="1" churn="84" amp="194" r="4">
... [22 more line(s); run it to see the whole thing]
```

**Caveats (stated by the binary):**

- Inert (byte-identical) when no resolved symbol has a mentioning doc.

### `--lego=TYPE`

**Answers:** show one interface and every class implementing it — the contract, then the existing impls the interface->impls view for ONE named interface/base: its signature, method contract, and every implementor (own-language only).

file:name disambiguates a same-named type. No contract for a language this surface cannot read soundly: methods=0 caveat=… says so.

**Try it**

_Interface -> implementors view: every existing impl of the named interface; the method contract is extracted for the C-family/Java/TS/Python tiers — for a Rust trait (this fixture) it discloses caveat="not-extracted-for-lang" rather than an empty list._

```
$ ./build/ripwire . --lego=Vehicle
<ctx schema="ripwire.lego/v1" root=".">
<!-- ripwire lego schema=ripwire.lego/v1: ONE interface/base type: <iface n= p= defs= implementors=>, its <m> method contract, every implementor. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. methods=0 caveat=not-extracted-for-lang: no <m> contract read for this language. -->
<lego graph_ambiguous="12495" graph_unresolved="12552" graph_unindexed="255" counts_floor="1">
<iface n="Vehicle" p="test/legofix/vehicle.rs" methods="0" caveat="not-extracted-for-lang" defs="1" implementors="2">
<impl n="Car" p="test/legofix/vehicle.rs"/>
<impl n="Bike" p="test/legofix/vehicle.rs"/>
</iface>
</lego>
</ctx>
```

**Shaped by:** `--callers`, `--expand`, `--layout`

**Caveats (stated by the binary):**

- file:name disambiguates a same-named type.
- No contract for a language this surface cannot read soundly: methods=0 caveat=… says so.

### `--exemplar=TASK|KIND`

**Answers:** before you write: the repo's best existing example of this kind of code, to imitate before you write: the repo's best-in-class instance to IMITATE.

Just pass a plain task — --exemplar="format byte sizes" — and the KIND is inferred from the top match; or name a KIND directly (fn|method|class|struct|iface|var). Picks by ROLE — lowest cognitive cx under a hard ccx ceiling, then tested + highest fan-in; test-fixture paths de-prioritized — NOT text similarity (similar-snippet retrieval measurably hurts). A weak task match falls back to fn (low_confidence=1); an all-over-ceiling kind flags over_ccx_bar=1

**Try it**

_The repo's best-in-class instance to imitate before writing new code (picked by ROLE)._

```
$ ./build/ripwire . --exemplar="format byte sizes for humans"
<!-- ripwire exemplar schema=ripwire.exemplar/v1: the best-in-class instance of kind= for the task, chosen by role: n= p= in= ccx= tested=, <bodies>
<b> to imitate. window: shown= total= capped= (capped=1 cut). root=: p= relative to it. <c via="name">: that callee matched by name alone (receiver unproven); it does NOT mean the edge is false. candidates=N: instances of kind= under the ccx ceiling the pick was ranked from. low_confidence=1: weak t … [line truncated: 81 more bytes on this line]
<exemplar schema="ripwire.exemplar/v1" kind="fn" candidates="12595" n="emitTo" p="src/infra/emit.h:78" in="282" ccx="2" root="." tested="1" low_confidence="1">
<bodies shown="1" total="1" capped="0">
<b t="fn" l="78" p="src/infra/emit.h" n="emitTo">
<![CDATA[inline void emitTo( std::FILE* stream, std::format_string<A...> f, A&&... a )
{
    // A fixed char[] must arrive as rw::cstr( buf ). printf's %s always meant "bytes to the first NUL";
    // `{}` on a char[N] is a different question that library versions answer differently, and an
    // implementation that formats the ARRAY emits the trailing NUL and the uninitialised bytes after it.
    // A regex sweep missed sites twice, so the compiler enforces it instead of a reviewer.
    // Only a MUTABLE char[N] is rejected. A string literal is const char[N]; every implementation formats
    // that as a string, and the hazard here is the reusable buffer that was written short.
    static_assert( ( ... && !( std::is_array_v<std::remove_reference_t<A>>
... [4 more line(s); run it to see the whole thing]
```

**Shaped by:** `--compress`, `--metrics`, `--doctor`, `--limit`, `--index-out`

### `--recall=TASK`

**Answers:** search the DOCS, not the code — the most relevant plans, designs and notes, in full recall the most relevant DOCS — memory/plans/designs, full bodies (md, .ipynb/.html/.csv, plus Office/PDF via the optional markitdown bridge).

This is the tool's LARGEST output: its header reports est_tokens + total=/shown=/capped=, where total= is the TRUE relevant count (score > 0) and shown= is what this run actually emitted. The header's "of N document files" denominator counts every file the index carries as a DOCUMENT — .md plus the docparse'd .ipynb/.html/.csv — so it is a SUPERSET of --doc-drift's docs=, which is an extension test (markdown only). Two populations, two names, deliberately. --top-k=N shapes HOW MANY docs are emitted (default 8, not the general --top-k default of 200). Recall defaults to an 8000-token body ceiling; --max-tokens=N overrides it and shapes to fit (disclosing each cut), while --token-budget=N gates the finished artifact (exit 3, nothing streamed). A doc WITH HEADINGS is served as whole SECTIONS in relevance order, each section's unit being its OWN PROSE — its heading line up to the next heading of any depth — so units tile instead of nesting and a parent no longer swallows the subsection that answered. Sections are admitted while they fit and the first that does not stops the walk, so WITHIN one document — with the served document SET held fixed — a bigger ceiling returns a SUPERSET rather than a repacked set. ACROSS documents that guarantee does not hold: raising the ceiling can pull in another document, and §C4 water-filling then re-divides the shared budget, which can shrink an already-served document's own slice; share_bytes= is exactly that re-division disclosed. The sections= note reports how many were served of how many matched, dropped_by_budget= what the ceiling cost, and lines= the ranges actually PRESENT in the emitted body rather than the ones merely selected. GENERATED documents rank LAST by default — a doc that declares itself generated in its first lines, or is BOTH >=5x the median doc's size AND mostly ```-fenced quoted output (a capture/API dump quotes every term, so BM25 hands it every query). Never dropped: it still wins when nothing else matches. Each one says [generated_demoted: marker|size+fences] on its own line and the header tallies generated_demoted=N

**Try it**

_Most relevant DOCS' full bodies (markdown only) — recall what is already written down._

```
$ ./build/ripwire . --recall="quality delta gating exit codes"
ripwire recall — "quality delta gating exit codes" — 113 relevant of 216 document files, best-first — total=113 shown=8 capped=1 truncated=7 generated_demoted=3 max_tokens=8000 share_bytes=2161 est_tokens=5489

━━ README.md  (relevance 8.038) ━━  [sections: 2 of 25 selected (60 in doc), section-granular; whole doc 214142 B; lines="2710-2722,2723-2730"; dropped_by_budget=23]
#### 6.2 Exit codes

This is the part to wire into a script.

| Code | Meaning |
| --- | --- |
| 0 | The command completed. |
| 1 | The command refused the request. A refusal names the reason on stderr. When `--callers`, `--callees`, `--uses`, `--impact` or `--path` refuse a selector that matches no indexed definition, they also print an answer on stdout: the verb's element with `found="0"` and the name to retry with. |
| 2 | A policy gate fired: `--arch` found a layering violation, `--scan-skill` found a CRITICAL, `--quality-delta` found new debt. |
| 3 | The output exceeded the token budget that you set. |
| 4 | `--test-gate` found an open obligation. |
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--max-tokens`, `--token-budget`, `--no-redact`, `--from-trace`, `--legend`, `--limit`

**Caveats (stated by the binary):**

- This is the tool's LARGEST output: its header reports est_tokens + total=/shown=/capped=, where total= is the TRUE relevant count (score > 0) and shown= is what this run actually emitted.
- Never dropped: it still wins when nothing else matches.

#### Pattern: a directory of dumped tool output as a knowledge base

**Answers:** can `--recall` serve as a zero-setup knowledge base over dumped tool output — a
`git log`, an API response dump, a fetched doc, `<tool> --help` text — sitting in a scratch
directory, instead of a source repo?

Yes, unmodified. `--recall` never distinguishes "a codebase" from any other directory it can
walk: point it at the scratch dir and query it. No index to build, no daemon, no mutable store
between runs — the whole cost is one cold parse. Two conditions decide whether it works at all,
and both are yours, because the file you write is the only thing that sets them:

1. **Dump to `.md`.** `--recall` ranks DOCUMENT files: `.md`, plus the docparse'd
   `.ipynb`/`.html`/`.csv` (and Office/PDF through the optional markitdown bridge). `.txt`,
   `.log`, `.json` and extensionless files are **not** documents to it. A directory of those
   answers `0 relevant of 0 document files` and exits 0 — which reads like "nothing matched
   your terms" when what happened is "nothing was indexed at all". Redirect to `notes.md`,
   never `notes.txt`. The recorded run below is that rule's own demonstration: its scratch dir
   holds five dumps, and the header says `2 relevant of 2 document files` because only the two
   `.md` ones are documents — the `git log`, the `--help` text and the JSON access log are not
   in the population at all.

2. **Keep `##` headings in the dump.** A headed document is served as whole ranked SECTIONS, so
   an answer buried mid-file arrives at a small `--max-tokens`, and — while the served document
   SET stays fixed — a larger ceiling returns a strict superset of it; the `[sections: S of R
   selected (N in doc) … lines="…"; dropped_by_budget=D]` note names the ranges you actually got
   and what the ceiling cost. A HEADLESS dump has no sections to rank, so it is cut front-first
   and carries no such note.

   That per-document guarantee is not global: dump SEVERAL headed documents into the same
   scratch dir and a larger ceiling can admit another one, which re-divides the shared budget
   and can shrink an already-served document's own slice — `share_bytes=` in the header
   discloses exactly that redivision when it happens.

   Measured on a 73811-byte, 2001-line dump whose answer sat at line 1748: the headed copy
   served exactly that answer at `--max-tokens=1000` (`lines="1748-1752"`, est_tokens=194),
   while the headless copy of the same content withheld it at 1000, 2000, 4000, 8000 and 16000
   and produced it only at 40000 — by which point the front-first cut had emitted the whole
   file.

**Try it**

_The directory-as-knowledge-base pattern: --recall pointed at a 1416688-byte scratch dir of DUMPED TOOL OUTPUT (a git log, this repo's own generated command reference, --help text, an architecture doc, a fabricated JSON access log) instead of a source repo — no index to build, no daemon._

```
$ ./build/ripwire <scratch>/aux/kbcorpus --recall="field affinity cache line data layout which fields are read together" --top-k=3 --max-tokens=1200
ripwire recall — "field affinity cache line data layout which fields are read together" — 2 relevant of 2 document files, best-first — total=2 shown=1 capped=1 truncated=1 max_tokens=1200 share_bytes=2040 est_tokens=957

━━ commands.md  (relevance 10.145) ━━  [sections: 1 of 159 selected (188 in doc), section-granular; whole doc 551924 B; lines="3754-3758"; dropped_by_budget=158]  [truncated: 1865 of 7739 bytes]
### `--field-affinity[=STRUCT]`

**Answers:** find fields that are read together but declared far apart — the cache-locality lens the CACHE-LOCALITY lens: which fields are READ TOGETHER but declared FAR APART.

Builds a static field CO-ACCESS affinity graph (one observation per indexed C-family function body) and diffs it against the DECLARED field order and 64-byte cache-line geometry, reusing --layout's LP64 offset model. Bare = every aggregate in the repo, ranked by separation cost; =STRUCT narrows the  … [line truncated: 1355 more bytes on this line]

(capped: 1 of 2 relevant document files omitted — raise --max-tokens/budget_tokens or narrow the query for 1 more (~2548-byte budget))
```

### `--tree`

**Answers:** orient file by file: each file's top symbols, 80 files by default file-by-file orientation map (top symbols per file).

Default window: the 80 files with the best-ranked symbols (shown=/capped=/total=/next_offset= disclose the cut, next= pastes the next page); --limit=N/--offset=M window it explicitly (--limit=100000 = every file)

**Try it**

_File-by-file orientation map (top symbols per file)._

```
$ ./build/ripwire . --tree
<!-- ripwire tree schema=ripwire.tree/v1: each file with its top 3 symbols by rank, files by best symbol: <file p= symbols=> of <s t= n=>; of files= indexed, files_unlisted= have none. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). symbols_capped=: 1 = cut. root=: p= relative to it. pr_iters=N: PageRank iterations. shown_symbols=: <s> rows printed. next=: the one pasteable follow-up. -->
<tree schema="ripwire.tree/v1" files="2688" files_unlisted="72" shown="80" capped="1" total="2616" has_more="1" next_offset="80" offset="0" limit="0" pr_iters="28" root="." shown_symbols="234" symbols_capped="1" next="--tree --offset=80">
<file p="src/infra/svector.h" symbols="68">
<s t="method" n="buf"/>
<s t="method" n="buf"/>
<s t="method" n="push_back"/>
</file>
<file p="src/resolve.h" symbols="326">
<s t="method" n="empty"/>
<s t="method" n="string"/>
<s t="method" n="unescape"/>
</file>
<file p="src/infra/os_win32_logic.h" symbols="94">
<s t="method" n="ok"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--limit`

**Caveats (stated by the binary):**

- Default window: the 80 files with the best-ranked symbols (shown=/capped=/total=/next_offset= disclose the cut, next= pastes the next page);
- --limit=N/--offset=M window it explicitly (--limit=100000 = every file)

### `--html[=FILE]`

**Answers:** write the map as a self-contained interactive call graph you can open in a browser self-contained HTML force-directed call graph of the DEFAULT map (no CDN — redirect or write FILE).

A navigation or report verb answers instead of the map, so --html beside one refuses rather than writing nothing. The page OPENS on the whole selected map, so the run is the picture; FILE#node/SYM/2 opens one symbol's neighbourhood and FILE#overview the module (community) list

**Try it**

_Self-contained HTML force-directed call graph._

```
$ ./build/ripwire . --html=<scratch>/aux/map2.html
(empty)
```

**Shaped by:** `--color-by`, `--legend`, `--max-memory`

**Caveats (stated by the binary):**

- A navigation or report verb answers instead of the map, so --html beside one refuses rather than writing nothing.

### `--color-by=MODE`

**Answers:** (with --html) colour the nodes by lang, community, complexity, churn or tested (with --html) node colour: lang (default) | community | cx | churn | tested — the page embeds all five and keeps a live selector;

the flag only sets the initial mode

**Try it**

_The HTML graph with the initial colour mode set to community (the page embeds all five modes and keeps a live selector)._

```
$ ./build/ripwire . --html=<scratch>/aux/map2.html --color-by=community
(empty)
```

### `--order=MODE`

**Answers:** choose emit order: stable, important-first (the default), or important-last emit order: stable (path/id order — provider KV-cache hits across re-runs) | important-first (rank order, the default;

no auto-flip) | important-last (highest-rank content emitted last — recency bias for an LLM). Large default maps auto-flip to important-last past ~50% of a nominal 32K window (est_tokens>16000) unless MODE is explicitly given.

**Try it**

_Stable (path/id) emit order — provider KV-cache hits across re-runs._

```
$ ./build/ripwire . --order=stable --top-k=5
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. overloads=N: N same-name defs merged in this row; shown= counts each. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. lens=: attributes another form of this answer serves, withheld here. <c via="name">: that callee matched by name alone (receiver unproven); it does NOT mean the edge is false. <c x=N>: N same-named via=name rows merged; callees=FILE:SYM lists all. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<r schema="ripwire.map/v1" root="." pr_iters="28" lens="k,est_tokens">
<f p="src/infra/os_win32_logic.h" layer="infra">
<s t="method" n="ok" sc="WidePath">
</s>
</f>
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="buf" sc="svector" overloads="2">
</s>
</f>
<f p="src/ingest_model.h">
<s t="method" n="find" sc="DefSweep" amb="2">
<c n="empty" prov="split" via="name" x="4"/>
... [11 more line(s); run it to see the whole thing]
```

**Shaped by:** `--no-stable`

### `--no-stable`

**Answers:** (--mcp/--listen only) turn off the stable ordering those two enable by default opt out of the stable ordering that --mcp/--listen enable by default.

Read ONLY there: on the CLI it changes nothing and says so on stderr (the map is important-first unless you pass --order=stable)

**Try it**

_--no-stable outside --mcp: what the flag does (or says) when there is no stable-by-default ordering to opt out of._

```
$ ./build/ripwire . --no-stable --top-k=3
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. overloads=N: N same-name defs merged in this row; shown= counts each. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. <c via="name">: that callee matched by name alone (receiver unproven); it does NOT mean the edge is false. <c x=N>: N same-named via=name rows merged; callees=FILE:SYM lists all. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- files=2688 symbols=25558 edges=40392 shown=3 est_tokens=1103 ambiguous=12495 unresolved=12552 locality_pinned=11 external=7267 declined=12204 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:73,tsv:49,jsonl:26,mod:25,scm:23,expected:15" unindexed_exts=20 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="1103" pr_iters="28">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="buf" sc="svector" overloads="2" k="0.0070">
</s>
</f>
<f p="src/resolve.h">
<s t="method" n="empty" sc="RubyConstantIndex" amb="1" k="0.0066">
<c n="empty" prov="split" via="name" x="3"/>
</s>
</f>
</r>
```

---

## navigate / answer a question

### `--around=SYM`

**Answers:** ego graph around SYM   [--around-depth=N, default 1] [--around-fanout=K, default 32] (default depth 1 since 2026-09-05: depth 2 was 3x the whole default map on this repo;

the root's depth= says which; --around-depth=2 restores the 2-hop neighbourhood) the root echoes all three (of= depth= fanout=), so the boundary of what could appear is readable and, when a bound actually CUT, which one: depth_truncated="1" (a symbol one hop past depth= is absent) / fanout_cut="N" (N distinct symbols the fanout cap dropped, absent from the whole answer, exact not a floor). Neither is emitted when its bound cut nothing, so absent = the bound did not bind and raising it would return nothing new

**Try it**

_Ego graph around one symbol — depth 1 BY DEFAULT now (the root's depth= says so): ~6 KB where the 2-hop neighbourhood is ~64 KB on this repo._

```
$ ./build/ripwire . --around=rankGraphTeleport
<!-- ripwire around schema=ripwire.around/v1: call neighbourhood of of=: depth= hops, fanout= kept per hop; absent rows lie outside that boundary. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. overloads=N: N same-name defs merged in this row; shown= counts each. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. <c via="name">: that callee matched by name alone (receiver unproven); it does NOT mean the edge is false. <c x=N>: N same-named via=name rows merged; callees=FILE:SYM lists all. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; absent if none. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- a bound BIT this walk, so raising it would return more: depth_truncated=1 means at least one symbol one hop past depth= is absent; fanout_cut=N means N distinct symbols were dropped by the fanout= cap and appear NOWHERE here (exact, not a floor: a neighbour another hub re-admitted is not counted). Neither attribute is emitted when its bound cut nothing, so absent means that bound did not bind and raising it returns nothing new. The knobs are around-depth=N and around-fanout=K. -->
<!-- files=2688 symbols=25558 edges=40392 shown=16 est_tokens=3658 ambiguous=12495 unresolved=12552 locality_pinned=11 external=7267 declined=12204 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:73,tsv:49,jsonl:26,mod:25,scm:23,expected:15" unindexed_exts=20 order=important-first -->
<r schema="ripwire.around/v1" root="." of="rankGraphTeleport" depth="1" fanout="32" depth_truncated="1" est_tokens="3658">
<f p="src/graph.h">
<s t="fn" n="rankGraphTeleport" sc="rw" amb="6" k="1.0000">
<c n="biasPrior"/>
<c n="PROFILE_SCOPE_DESCRIBE" prov="split"/>
<c n="PROFILE_SCOPE_DESCRIBE" prov="split"/>
<c n="begin" prov="split" via="name" x="2"/>
<c n="end" prov="split" via="name" x="2"/>
<c n="pageRankDouble"/>
</s>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--callers`, `--layout`, `--limit`

### `--callers=SYM`

**Answers:** show SYM's direct callers (1-hop in-edges) who calls SYM (1-hop in-edges).

file:name disambiguates a same-named symbol across files (like --around/--lego); Scope::name picks one scope's definition — the sym= spelling edit-check prints resolves everywhere

**Try it**

_Unknown-symbol REFUSAL shape (exit 1) with a did-you-mean from real edit distance._

```
$ ./build/ripwire . --callers=DoesNotExist
<!-- ripwire callers schema=ripwire.callers/v1: 1-hop CALLERS of of= (defs= matched, count= distinct symbols): <s t= n= p=>; hop_tested=/hop_untested=. found=0: no indexed definition matched the selector, nothing listed or counted (zero = none found, not none exists); exit stays 1. -->
<callers schema="ripwire.callers/v1" of="DoesNotExist" found="0"/>
```

**Shaped by:** `--no-route`, `--callees`, `--uses`, `--impact`, `--expand`, `--dead-code`, `--edit-check`, `--slice-flow`

**Caveats (stated by the binary):**

- file:name disambiguates a same-named symbol across files (like --around/--lego);

### `--callees=SYM`

**Answers:** what SYM calls (1-hop out-edges).

file:name disambiguates like --callers

**Try it**

_What SYM calls (1-hop out-edges)._

```
$ ./build/ripwire . --callees=rankGraphTeleport
<!-- ripwire callees schema=ripwire.callees/v1: 1-hop CALLEES of of= (defs= matched, count= distinct symbols): <s t= n= p= role= tested=>. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. declined_calls=K: K call sites left unbound (no evidence chose one def), in no count or row. root=: p= relative to it. <s tested=1>: a non-test row an indexed test transitively reaches (absent otherwise, never 0). via=name: the target was matched by name alone (receiver unproven); every by-name candidate in reach is listed; NOT a claim the edge is false. next=: the one pasteable follow-up. hop_tested=/hop_untested=: count= split by whether an indexed test reaches the row (in-process calls only). -->
<callees schema="ripwire.callees/v1" of="rankGraphTeleport" defs="1" count="8" root="." hop_tested="7" hop_untested="1" declined_calls="1" graph_ambiguous="12495" graph_unresolved="12552" graph_unindexed="255" counts_floor="1" next="--expand=rankGraphTeleport">
<s t="fn" n="biasPrior" p="src/graph.h:7883"/>
<s t="macro" n="PROFILE_SCOPE_DESCRIBE" p="src/infra/profileScope.h:1282" role="macro" tested="1"/>
<s t="macro" n="PROFILE_SCOPE_DESCRIBE" p="src/infra/profileScope.h:1296" role="macro" tested="1"/>
<s t="method" n="begin" p="src/infra/svector.h:269" tested="1" via="name"/>
<s t="method" n="end" p="src/infra/svector.h:270" tested="1" via="name"/>
<s t="method" n="begin" p="src/infra/svector.h:271" tested="1" via="name"/>
<s t="method" n="end" p="src/infra/svector.h:272" tested="1" via="name"/>
<s t="fn" n="pageRankDouble" p="src/pagerank.cpp:99" tested="1"/>
</callees>
```

**Shaped by:** `--exercises`, `--format`, `--legend`, `--json`, `--limit`

**Caveats (stated by the binary):**

- file:name disambiguates like --callers

### `--uses=SYM`

**Answers:** show every place SYM is used, not just called — reads, writes, imports, extends the statically resolvable use-sites of SYM (role=call|macro|read|write|import|extends|type, file:line);

external="1" if SYM has no in-corpus def. file:name or a "::" spelling narrows defs= AND the role="call" sites (kept only where the call RESOLVES to a chosen def — --callers' own narrowing); read/write/import/extends carry no resolution and stay name-matched. narrowed_roles=/defs_of_name=/call_sites_of_name= (qualifier only) disclose what narrowed and the un-narrowed totals; a file: qualifier naming a file with no such def REFUSES, like --callers/--impact Owner.field (also Owner::field, or the id=) — a MEMBER VARIABLE's own use-sites, RESOLVED per site: this->f/self.f/bare f inside the owner pin; v.f pins through v's recorded type, else every owner is a candidate and the row carries amb=K (never a silent pin); write = assignment/compound/++ (address-of and by-reference passing are NOT claimed). A bare field name shared by several owners REFUSES with the Owner.field spellings; C/C++/Python fields only, others refuse

**Try it**

_The resolvable use-sites (call/read/write/import/extends) with file:line; count= is a floor._

```
$ ./build/ripwire . --uses=rankGraphTeleport
<!-- ripwire uses schema=ripwire.uses/v1: resolvable use-sites of of=: <u role=call|macro|read|write|import|extends|type p=file:line in_id=>. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. defs=N: definitions the selector matched; qualify file:name to narrow the call sites. external=1: of= has no definition in the indexed tree under any spelling (stdlib/third-party). count=N: use-site rows in all (a floor). -->
<uses schema="ripwire.uses/v1" of="rankGraphTeleport" defs="1" external="0" count="9" root="." graph_ambiguous="12495" graph_unresolved="12552" graph_unindexed="255" counts_floor="1">
<u role="call" p="src/mcpindex.h:1268" in_id="src/mcpindex.h::rw::getIndex"/>
<u role="call" p="src/graph.h:7968" in_id="src/graph.h::rw::rankGraph"/>
<u role="call" p="src/graph.h:8662" in_id="src/graph.h::rw::anchoredLexicalRank"/>
<u role="call" p="src/eval.h:325" in_id="src/eval.h::rw::runEval"/>
<u role="call" p="src/main.cpp:1397" in_id="churnDecayRanking"/>
<u role="call" p="src/main.cpp:1436" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:1437" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:1451" in_id="churnRankedGraph"/>
<u role="call" p="src/main.cpp:1752" in_id="runDefaultMap"/>
</uses>
```

**Shaped by:** `--no-route`, `--naming-consistency`, `--edit-check`, `--edit-target-file`, `--safe-delete`, `--doctor`, `--format`, `--legend`

**Caveats (stated by the binary):**

- a file: qualifier naming a file with no such def REFUSES, like --callers/--impact Owner.field (also Owner::field, or the id=) — a MEMBER VARIABLE's own use-sites, RESOLVED per site: this->f/self.f/bare f inside the owner pin;
- v.f pins through v's recorded type, else every owner is a candidate and the row carries amb=K (never a silent pin);
- A bare field name shared by several owners REFUSES with the Owner.field spellings;

### `--graph-query=EXPR`

**Answers:** query the call graph directly: pick a node set, filter it, walk it, combine the results composable node-set query over the call graph: sources name("X")/all;

filters kind|cx|fanin|file|layer; bounded closure callers|callees(SET[,depth]); joins and|or|not.  e.g. and(callers(name("foo"),2),kind(all,fn)); file() regex example: file("src/.*\\.cpp") (or in bash, use single quotes: file('src/.*\.cpp')) layer(SET,NAME) keeps the architecture layer NAME (game|infra|render|math|audio|ai|test) — the SAME built-in directory-name taxonomy the map prints as layer= on a file node, so the two cannot disagree. It does NOT read a --arch=FILE rules file: --arch is a verb and outranks --graph-query, so the two never run together. An unknown layer word, or ANY layer() against a tree where no path names a layer, is REFUSED (exit 1) rather than answered count="0" — 0 there would read as "no such code". a name("X") literal matching NO indexed symbol refuses with a did-you-mean (a typo is not a count=0); a query whose names all resolve but that selects nothing still reports count="0" — that IS a measurement (including a VALID layer with no members in a tree that does have layers). file() matches the ROOT-RELATIVE path that p= prints, so ^src/ anchors at the root and the directories the tree was cloned into never match. A file() regex that cannot be screened, compiled or finished (the engine abandons the match) is REFUSED at exit 1, never answered with a count. Ranked result set is capped at --top-k (default 200); --limit overrides that cap (raise or lower it), --offset pages past it — see --limit=N --offset=M above

**Try it**

_Composable node-set query: functions within 2 caller-hops of rankGraphTeleport._

```
$ ./build/ripwire . --graph-query='and(callers(name("rankGraphTeleport"),2),kind(all,fn))'
<!-- ripwire graph-query schema=ripwire.graph-query/v1: graph-query expression over the symbol graph: <s t= n= p=> matching rows. window: shown= capped= (capped=1 cut). counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. pr_iters=N: PageRank iterations. expr=: the expression as given; count=: symbols it matched (rows page by shown=/total=). -->
<query schema="ripwire.graph-query/v1" expr="and(callers(name(&quot;rankGraphTeleport&quot;),2),kind(all,fn))" count="55" shown="55" capped="0" graph_ambiguous="12495" graph_unresolved="12552" graph_unindexed="255" counts_floor="1" root="." pr_iters="28">
<s t="fn" n="getIndex" p="src/mcpindex.h:1165"/>
<s t="fn" n="anchoredLexicalRank" p="src/graph.h:8611"/>
<s t="fn" n="emitCommunitiesReport" p="src/verbs_report.h:2517"/>
<s t="fn" n="emitCommunityDrill" p="src/verbs_report.h:2678"/>
<s t="fn" n="computeLensRanking" p="src/verbs_for.h:78"/>
<s t="fn" n="rankGraph" p="src/graph.h:7965"/>
<s t="fn" n="dispatchMain" p="src/main.cpp:4132"/>
<s t="fn" n="postCheckJson" p="src/mcpedit.h:1116"/>
<s t="fn" n="fetchBody" p="src/mcpverbs.h:4986"/>
<s t="fn" n="dispatchMcpLine" p="src/mcp.h:1118"/>
<s t="fn" n="runEvalRetrieval" p="src/eval.h:713"/>
<s t="fn" n="runEvalMined" p="src/eval.h:1086"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--exercises`, `--limit`

**Caveats (stated by the binary):**

- file() regex example: file("src/.*\\.cpp") (or in bash, use single quotes: file('src/.*\.cpp')) layer(SET,NAME) keeps the architecture layer NAME (game|infra|render|math|audio|ai|test) — the SAME built-in directory-name taxonomy the map prints as layer= on a file node, so the two cannot disagree.
- It does NOT read a --arch=FILE rules file: --arch is a verb and outranks --graph-query, so the two never run together.
- An unknown layer word, or ANY layer() against a tree where no path names a layer, is REFUSED (exit 1) rather than answered count="0" — 0 there would read as "no such code".

### `--external-surface`

**Answers:** list the names this repo uses but never defines — its stdlib and third-party surface names referenced but never defined in-corpus (the stdlib/third-party surface), by ref count;

each row's lang= is the REFERENCING file's language — a name called from several languages (e.g. printf: C stdio call vs Bash builtin) gets one row PER language, not a merged count. Default window: 100 rows (shown=/capped=/next_offset=, next= pastes the next page; --limit=N raises it) and the sh BUILTINS (echo printf cd exit test …) are dropped — builtins_excluded= counts them; --include-builtins keeps them

**Try it**

_Names referenced but never defined in-corpus (stdlib/third-party surface). The root carries names/shown/capped; the default is a 100-row window now, so total= and a pasteable next= join them when it bites (the explicit --limit form carries the same quintet). The sh BUILTINS (cd/echo/set…) are dropped and COUNTED as builtins_excluded= — grep/sed/git stay, they ARE the surface._

```
$ ./build/ripwire . --external-surface
<!-- ripwire external-surface schema=ripwire.external-surface/v1: names used but never defined in the index: <x n= lang= refs= calls=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). next=: the one pasteable follow-up. names=N: distinct external names (the x rows' total). builtins_excluded=N: sh BUILTIN rows (echo printf cd exit test ...) dropped from names=; the include-builtins flag keeps them. -->
<external-surface schema="ripwire.external-surface/v1" names="2642" builtins_excluded="19" shown="100" capped="1" total="2642" has_more="1" next_offset="100" offset="0" limit="0" next="--external-surface --offset=100">
<x n="grep" lang="sh" refs="12671" calls="12671"/>
<x n="cat" lang="sh" refs="2447" calls="2447"/>
<x n="tr" lang="sh" refs="2018" calls="2018"/>
<x n="python3" lang="sh" refs="1573" calls="1573"/>
<x n="sed" lang="sh" refs="1549" calls="1549"/>
<x n="substr" lang="cpp" refs="1125" calls="1125"/>
<x n="print" lang="py" refs="942" calls="942"/>
<x n="wc" lang="sh" refs="855" calls="855"/>
<x n="mktemp" lang="sh" refs="822" calls="822"/>
<x n="dirname" lang="sh" refs="782" calls="782"/>
<x n="to_string" lang="cpp" refs="781" calls="781"/>
<x n="string_view" lang="cpp" refs="722" calls="722"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--limit`

**Caveats (stated by the binary):**

- list the names this repo uses but never defines — its stdlib and third-party surface names referenced but never defined in-corpus (the stdlib/third-party surface), by ref count;
- printf: C stdio call vs Bash builtin) gets one row PER language, not a merged count.
- Default window: 100 rows (shown=/capped=/next_offset=, next= pastes the next page;

### `--path=SRC,DST`

**Answers:** shortest directed call-path SRC -> DST

**Try it**

_Shortest directed call-path SRC -> DST. CHANGED: now reports from_p/to_p/from_defs and resolves the right `main` (was reachable="0")._

```
$ ./build/ripwire . --path=main,rankGraphTeleport
<!-- ripwire path schema=ripwire.path/v1: one DIRECTED call path from= to to=, each <s t= n= p=> a hop; reachable=0 hops=0 when none. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. from_p=/to_p=: the definitions from= and to= were bound to. from_defs=/to_defs=: definitions of each name, all searched; above 1, qualify file:name. -->
<path schema="ripwire.path/v1" from="main" to="rankGraphTeleport" from_p="src/main.cpp:3997" to_p="src/graph.h:7924" from_defs="111" to_defs="1" reachable="1" hops="4" root="." graph_ambiguous="12495" graph_unresolved="12552" graph_unindexed="255" counts_floor="1">
<s t="fn" n="main" p="src/main.cpp:3997"/>
<s t="fn" n="runWithCompactLegend" p="src/main.cpp:3933"/>
<s t="fn" n="dispatchMain" p="src/main.cpp:4132"/>
<s t="fn" n="runDefaultMap" p="src/main.cpp:1632"/>
<s t="fn" n="rankGraphTeleport" p="src/graph.h:7924"/>
</path>
```

**Shaped by:** `--connect`, `--limit`

### `--connect=A,B,C`

**Answers:** show how 2..16 symbols relate: the smallest subgraph that joins them minimal connecting subgraph over 2..16 symbols: terminals + fewest joining intermediaries + call edges in TRUE direction (finds the shared-caller join a directed --path can't)   [--connect-radius=N (1..12, default 6)]

**Try it**

_Minimal connecting subgraph over 3 symbols (finds shared-caller joins)._

```
$ ./build/ripwire . --connect=rankGraphTeleport,runEval,getIndex
<!-- ripwire connect schema=ripwire.connect/v1: minimal joining subgraph: <g> groups, <t> terminals, <s connects=> joins, <e f= t=> edges, <unconnected>. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. hub_floor=D: connects= >= D is hub=1, vacuous. nodes=N: symbols printed, terminals plus joins (a floor). radius=N: undirected hop bound searched (default 6, max 12); raise it with connect-radius=N. terminals=/groups=/edges=: task symbols resolved, connected groups (g), e edges printed. -->
<connect schema="ripwire.connect/v1" terminals="3" nodes="3" edges="2" radius="6" groups="1" est_tokens="512" hub_floor="285" root="." graph_ambiguous="12495" graph_unresolved="12552" graph_unindexed="255" counts_floor="1">
<g terminals="3">
<t n="runEval" t="fn" p="src/eval.h:171"/>
<t n="rankGraphTeleport" t="fn" p="src/graph.h:7924"/>
<t n="getIndex" t="fn" p="src/mcpindex.h:1165"/>
<e f="runEval" t="rankGraphTeleport"/>
<e f="getIndex" t="rankGraphTeleport"/>
</g>
</connect>
```

**Shaped by:** `--no-redact`, `--from-trace`, `--limit`

### `--impact=SYM`

**Answers:** show everything that reaches SYM — the transitive blast radius before a change — the indexed symbols that reach SYM (a floor, see counts_floor).

file:name disambiguates like --callers rows run nearest first: d= is the hop depth (1 = a direct caller; printed where it changes), PageRank order within a depth; by_depth=k:n on the root counts reaches= per depth, so a cut drops the deepest first importers= is a SECOND, weaker reach beside it: the files that directly include/import a file defining SYM, emitted as <f via="import" lazy="0|1"> rows (format=columnar carries the count only; --limit sizes it). NEVER added to reaches= — files and symbols are different units, and an importer may use a different symbol from that file, or none at all. lazy="1": every one of that importer's edges is written inside a closure — a TS/JS require()/import() inside a function body, a Ruby constant receiver or argument inside a method/lambda/block, a Ruby autoload or rescue class — not at load time: still a real dependency, weaker than a top-level one

**Try it**

_Transitive blast radius — everything that reaches SYM. NOW carries shown/capped._

```
$ ./build/ripwire . --impact=rankGraphTeleport
<!-- ripwire impact schema=ripwire.impact/v1: transitive blast radius of of=: <s t= n= p=> reach set, <f via= p=> importers; defs= matched, reaches= their transitive callers, radius_tested= non-tests an indexed test reaches, radius_untested= the rest; importers= files that #include/import a def's file. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). importers_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. pr_iters=N: PageRank iterations. shown_importers=: <f> rows (limit= sizes them). <f lazy=1>: every edge from that importer into a def file is deferred (in a function/block body, or an autoload), firing only if reached; lazy=0: at least one is load-time. <s d=N>: hops to of= (1 = direct caller), set where it changes. by_depth=k:n: n of reaches= at depth k, shallowest rows first. next=: the one pasteable follow-up. -->
<impact schema="ripwire.impact/v1" of="rankGraphTeleport" defs="1" reaches="67" by_depth="1:7,2:48,3:10,4:2" importers="37" shown_importers="37" importers_capped="0" radius_tested="0" radius_untested="67" root="." shown="40" capped="1" total="67" has_more="1" next_offset="40" offset="0" limit="0" gr … [line truncated: 139 more bytes on this line]
<s t="fn" n="getIndex" p="src/mcpindex.h:1165" d="1"/>
<s t="fn" n="anchoredLexicalRank" p="src/graph.h:8611"/>
<s t="fn" n="rankGraph" p="src/graph.h:7965"/>
<s t="fn" n="churnDecayRanking" p="src/main.cpp:1383"/>
<s t="fn" n="churnRankedGraph" p="src/main.cpp:1422"/>
<s t="fn" n="runDefaultMap" p="src/main.cpp:1632"/>
<s t="fn" n="runEval" p="src/eval.h:171"/>
<s t="fn" n="emitCommunitiesReport" p="src/verbs_report.h:2517" d="2"/>
<s t="fn" n="emitCommunityDrill" p="src/verbs_report.h:2678"/>
<s t="fn" n="computeLensRanking" p="src/verbs_for.h:78"/>
<s t="fn" n="dispatchMain" p="src/main.cpp:4132"/>
<s t="fn" n="postCheckJson" p="src/mcpedit.h:1116"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--no-route`, `--uses`, `--metrics`, `--deps`, `--safe-delete`, `--slice-flow`, `--format`, `--legend`

**Caveats (stated by the binary):**

- show everything that reaches SYM — the transitive blast radius before a change — the indexed symbols that reach SYM (a floor, see counts_floor).
- file:name disambiguates like --callers rows run nearest first: d= is the hop depth (1 = a direct caller;
- NEVER added to reaches= — files and symbols are different units, and an importer may use a different symbol from that file, or none at all.

### `--verify="CLAIM"`

**Answers:** check a claim about the code in one call: confirmed, refuted, or not-established VERIFY A CLAIM about the code in ONE call: a CLOSED claim language in, a three-valued verdict out (confirmed / refuted / not-established) with the evidence rows inline — the collapse of the manual verification grep-chain.

Shapes: calls(A,B) does A transitively call B; uses(SYM) / unused(SYM) is SYM referenced anywhere / nowhere; contains(FILE, "LIT") do FILE's indexed bytes contain the literal; defines(FILE, SYM) does FILE define SYM; reaches(SYM, "FILE"|LAYER) does code in that file/layer transitively call SYM (LAYER unquoted: game|infra|render|math|audio|ai|test). refuted appears ONLY with complete evidence: a clean literal-scan absence carries complete=, and an unused claim is refuted by printed witness sites. A graph or reference ZERO can never refute — it yields not-established with limit= naming the floor (call-graph-floor, reference-floor, collection-ceiling, scan-degraded, extraction-floor); see counts_floor above for why. An unknown shape refuses loudly with the whole vocabulary; SYM takes the shared selector grammar (name, file:name, Scope::name, canonical id), FILE is a path substring

**Try it**

_An unparseable claim — the refusal names the accepted shapes._

```
$ ./build/ripwire . --verify="frobnicate(x)"
(empty)
```

**Caveats (stated by the binary):**

- A graph or reference ZERO can never refute — it yields not-established with limit= naming the floor (call-graph-floor, reference-floor, collection-ceiling, scan-degraded, extraction-floor);
- see counts_floor above for why.
- An unknown shape refuses loudly with the whole vocabulary;

### `--mentions=SYM`

**Answers:** find the markdown docs that name SYM in backticks — the doc-to-code link markdown docs (plans/designs) that name SYM in a `backtick` (doc↔code).

An @FILE:LINE seed rebinds to the innermost enclosing definition and answers, disclosing sym= (its name). unbackticked_docs=N (absent at 0): files naming SYM only outside such a span, a ceiling.

**Try it**

_Markdown docs that name SYM in a backtick (doc<->code edges)._

```
$ ./build/ripwire . --mentions=rankGraphTeleport
<!-- ripwire mentions schema=ripwire.mentions/v1: markdown FILES naming of= in backticks (docs=, sections=): <doc p= mentions=>; not a call edge. root=: p= relative to it. defs=N: definitions of= resolved to; rows union their doc mentions. -->
<!-- unbackticked_docs=N: N more markdown files, over readable indexed markdown, name of= as a whole word but not as a clean one-line backtick span (prose, a code block, a span broken across lines) - not in docs=; a text match, so a ceiling -->
<mentions schema="ripwire.mentions/v1" of="rankGraphTeleport" defs="1" docs="6" sections="13" unbackticked_docs="4" root=".">
<doc p="docs/ARCHITECTURE.md" mentions="1"/>
<doc p="docs/EVALS.md" mentions="3"/>
<doc p="prompts/help-wanted/certified-ranking-order.md" mentions="2"/>
<doc p="prompts/help-wanted/correctness-fuzzers.md" mentions="1"/>
<doc p="prompts/help-wanted/graph-unit-tests.md" mentions="5"/>
<doc p="prompts/help-wanted/next-uses-bare-name.md" mentions="1"/>
</mentions>
```

**Shaped by:** `--no-doc-mention`, `--at`, `--limit`

### `--affected=F1,F2|SYM`

**Answers:** name the test files that reach these changed files, or this changed symbol test files that transitively reach the changed files -- or the changed SYMBOL.

Each item may be `path`, `./path`, `path:LINE` / `path:N-M` (paste a --hotspots/--clones/--grep/--lint/ --quality-delta row's locator verbatim; the trailing line locator is stripped, same for --situ/--test-gate), or a symbol: `NAME`, `file:NAME`, `path::scope::name`. FILE-FIRST: an item matching any indexed path is a PATH pattern (unchanged semantics -- `--affected=widget` stays the ./src/widget.cpp pattern); only an item matching NO indexed path is offered to the symbol resolver, and `file:NAME` reaches the symbol reading explicitly. seeded_by="file|symbol|mixed" + seeds=N report which reading fired and how many defs it seeded. An item matching NEITHER refuses (exit 1) naming both readings. seed_test_files=N of the matched files are TEST files: a test cannot reach a change it is part of, so its own symbols are not seeds of the caller walk, and its row carries seed_kind="test" -- it is listed because the argument matched it (it changed, run it), not because it reaches. script_gates_unmodelled= counts the script runners under test/, recursively (a path count; not every one invokes the binary) that this call's graph walk cannot see either way (script-to-binary is not a call edge) — a corpus-wide fact, not scoped to the changed set given

**Try it**

_Test files that transitively reach the changed file._

```
$ ./build/ripwire . --affected=src/graph.h
<!-- ripwire affected schema=ripwire.affected/v1: test files that transitively reach the changed files/symbols: <test p= partner= hops= run=> in evidence order (order= partners=); seeded_by= the reading taken. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. run_unknown=1: no runner derivable (a guess would be worse). <g n= p=a,b,c>: n runner-less rows with equal attrs as ONE row, paths verbatim; a path holding ',' is never grouped, so p= splits into exactly n=; shown=/total= over these rows counts test FILES. root=: p= relative to it. seeds=N: symbols the argument matched; only those outside test files seed the caller walk. seed_test_files=N: matched files that are TESTS; listed to run (seed_kind=test), never walk seeds. tests=N: test files listed to run (the rows). reached=N: symbols the transitive caller walk reached from the seeds (seeds excluded). script_gates_unmodelled=N: test/*.sh runners; their subprocess reach is unmodelled, never in tests=/reached=. run_first=N: the first N test files have the most direct evidence (changed/partner/hops=1, else nearest hops=); not a skip list. changed=: the files/symbols argument as given. -->
<affected schema="ripwire.affected/v1" changed="src/graph.h" seeded_by="file" seeds="425" seed_test_files="0" tests="19" reached="1875" script_gates_unmodelled="743" run_first="3" order="evidence" partners="0" root="." graph_ambiguous="12495" graph_unresolved="12552" graph_unindexed="255" counts_flo … [line truncated: 7 more bytes on this line]
<test p="test/connectcore_harness.cpp" hops="1" run="bash test/connectcorecheck.sh"/>
<test p="test/cppqualtmplfix/member.cpp" hops="1" run="bash test/cppqualcheck.sh"/>
<test p="test/verify_csr.cpp" hops="1" run="bash test/a9disclosurecheck.sh"/>
<test p="test/cloneband_harness.cpp" hops="2" run="bash test/clonebandcheck.sh"/>
<test p="test/clonelex_harness.cpp" hops="2" run="bash test/clonelexcheck.sh"/>
<test p="test/diagnotice_harness.cpp" hops="2" run="bash test/binoverridecheck.sh"/>
<g hops="2" n="4" p="test/fuzz/readers/readers_domain.cpp,test/fuzz/readers/readers_ingest.cpp,test/fuzz/readers/readers_light.cpp,test/fuzz/readers/readers_mcphttp.cpp" run_unknown="1"/>
<test p="test/includeprecise_unit.cpp" hops="2" run="bash test/includeprecisecheck.sh"/>
<test p="test/rustimport_unit.cpp" hops="2" run="bash test/rustimportprecisecheck.sh"/>
<test p="test/type3clone_harness.cpp" hops="2" run="bash test/type3clonecheck.sh"/>
<test p="test/verify_os_win32_logic.cpp" hops="2" run="bash test/binoverridecheck.sh"/>
<test p="test/verify_strkern.cpp" hops="2" run="bash test/binoverridecheck.sh"/>
... [5 more line(s); run it to see the whole thing]
```

**Shaped by:** `--exercises`, `--test-gate`, `--edit-target-file`, `--legend`

**Caveats (stated by the binary):**

- An item matching NEITHER refuses (exit 1) naming both readings.
- seed_test_files=N of the matched files are TEST files: a test cannot reach a change it is part of, so its own symbols are not seeds of the caller walk, and its row carries seed_kind="test" -- it is listed because the argument matched it (it changed, run it), not because it reaches.
- script_gates_unmodelled= counts the script runners under test/, recursively (a path count;

### `--exercises=TESTFILE`

**Answers:** show what a test file actually covers: the non-test symbols it reaches the INVERSE of --affected: the non-test symbols this test file transitively calls into -- what it actually covers.

The first question when a test fails and you have its name and nothing else. Ranked by PageRank, capped at 40 rows (raise with --limit; --offset pages). A NON-TEST path REFUSES rather than answering generically: this verb IS the test/non-test partition (it subtracts test code from the answer), which means nothing for a non-test file -- for "what does this call", use --callees=SYM or --graph-query callees(...) A shell harness carries harness=script: subprocess coverage is unmodelled, so reaches=0 there is a stated limit, not a measurement (the inverse of script_gates_unmodelled).

**Try it**

_Which symbols a TEST FILE exercises — the reverse direction of --affected._

```
$ ./build/ripwire . --exercises=test/regression.sh
<!-- ripwire exercises schema=ripwire.exercises/v1: NON-TEST symbols this test transitively calls (what it covers): <t p= run=>; the inverse of affected. window: shown= capped= (capped=1 cut). seed_files_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. pr_iters=N: PageRank iterations. seed_files=N: test files the pattern matched. shown_seed_files=N: of those, printed as t rows (at most 20). test_symbols=N: symbols in those test files, the walk's seeds. reaches=N: non-test symbols the tests transitively call (the s rows' total). harness=script|mixed: seeds include shell gates, whose subprocess coverage is unseen; note= says so. of=: the test file pattern given. -->
<exercises schema="ripwire.exercises/v1" of="test/regression.sh" seed_files="1" shown_seed_files="1" seed_files_capped="0" test_symbols="4" reaches="0" harness="script" note="a shell gate invokes the compiled binary as a subprocess; script-to-binary edges are not modelled, so reaches= counts call-gr … [line truncated: 190 more bytes on this line]
<t p="test/regression.sh" run="bash test/regression.sh"/>
</exercises>
```

**Shaped by:** `--test-gate`, `--limit`

**Caveats (stated by the binary):**

- Ranked by PageRank, capped at 40 rows (raise with --limit;

### `--situ[=F1,F2]`

**Answers:** situational awareness for a change: blast radius + tests + co-change (default = git diff) Its co-change section is the check for Fowler's SHOTGUN SURGERY: the files this change usually lands in but did not.

Backtested on two histories (EVALS.md): a named partner is edited within the next 3 commits in 56% / 32% of alarms, against a 1-2% chance baseline

**Try it**

_Mid-task situational report for the current git diff — recorded against a CLEAN tree (contrast with the sandbox run below)._

```
$ ./build/ripwire . --situ
ripwire situational-awareness — 0 changed file(s), 0 symbols in them
root: .
at: f1e5c2e76
  (0 changed files — working tree is clean, nothing to analyze)
```

**Shaped by:** `--affected`, `--test-gate`, `--legend`, `--limit`

### `--handoff`

**Answers:** brief the next session — verified disk truth first, labelled guesses second continuation packet for the NEXT session: <verified> disk truth (branch/sha, changed files+symbols, blast radius, tests-to-run) + <heuristic> labeled suggestions (co-change partners, committed notes, plan/design doc pointers via a branch+commit-subject query).

Empty diff is fine — the packet still carries branch/sha + heuristics. Composes with --token-budget=N (drops heuristic rows tail-first, disclosed as withheld= in the header; verified rows are never dropped). Single-root only.

**Try it**

_The continuation packet for the NEXT session: <verified> disk truth (branch/sha, changed symbols, blast radius, tests) + <heuristic> labeled suggestions. Recorded against a CLEAN tree._

```
$ ./build/ripwire . --handoff
<!-- ripwire handoff schema=ripwire.handoff/v1: continuation packet for the NEXT session: <verified changed= blast_files=>, <tests n=>, <heuristic n= candidates=>, <note>, <doc p=>. window: capped= (capped=1 cut). est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. branch=/subject=: the checked out branch and HEAD commit subject; gitok=0: the git diff probe failed, changed counts are floors. cochange_window=/cochange_commits=: the git window the cochange rows were mined in and the commits it held (0: could not look). doc s=: lexical score of that plan/design doc for the branch+subject query. detached=1: HEAD is detached, so branch= reads HEAD; the commit is at=; absent on a branch. note target=/txt=: a committed notes row on this work (symbol id or path) and its text; a suggestion. -->
<handoff schema="ripwire.handoff/v1" at="f1e5c2e76" root="." branch="HEAD" detached="1" subject="fix(path): a call bound by name alone with an unlisted namesake is a path gap, never &quot;no directed call path&quot;" gitok="1" est_tokens="927">
<verified changed="0" blast_files="0">
<tests n="0">
</tests>
</verified>
<heuristic n="6" candidates="201" capped="1" cochange_window="18mo@HEAD" cochange_commits="4174">
<note target="src/infra/Diagnostics.h" txt="ASSUME_NO_ALIAS is an optimizer fact in release (separate_storage) only where the compiler consumes it: clang 18+ by default, LLVM 17/AppleClang 16 via the CMake -mllvm flag (scalars only), GCC never (debug check only); never on two members of one object;  … [line truncated: 57 more bytes on this line]
<note target="test/manifestcheck.sh" txt="README.md&apos;s single &apos;&lt;N&gt; gate scripts&apos; claim (~line 1305) is NOT enforced — the derived-vs-stated sibling loop here covers docs/EVALS.md only. It drifted 407→451 unnoticed (fixed 2026-08-23). To close: grep both files (&apos;file:line … [line truncated: 47 more bytes on this line]
<doc p="CHANGELOG.md" s="20.414"/>
<doc p="docs/COMMANDS.md" s="13.438"/>
<doc p="skills/ripwire-navigate/SKILL.md" s="10.818"/>
<doc p="prompts/help-wanted/uses-qualified-selector.md" s="10.365"/>
</heuristic>
... [1 more line(s); run it to see the whole thing]
```

**Caveats (stated by the binary):**

- Empty diff is fine — the packet still carries branch/sha + heuristics.
- Composes with --token-budget=N (drops heuristic rows tail-first, disclosed as withheld= in the header;
- verified rows are never dropped).

### `--test-gate[=F1,F2]`

**Answers:** before a PR: name the tests to run and the untested blast radius;

exit 4 if either is non-empty agent self-check before a PR (pair with --quality-delta): names the tests to run + the UNTESTED blast radius; exit 4 if either obligation is non-empty (run the tests, then rely on green). (default = git diff) run= on a test row        --affected/--situ/--test-gate/--exercises/--pr-context/--pack-task name harness FILES, not commands. A row carries run="<cmd>" when a runner is DERIVABLE from real evidence: a test-dir .sh/.py whose basename stem matches the harness's, or whose TEXT names the harness file; for TS/JS, the nearest package.json above the test file naming vitest, jest, or node's own test runner (scripts.test, or a vitest/jest dependency -- never guessed from the .ts/.js extension alone). Spelled RELATIVE to the root= the document declares, so it pastes into a shell run from there, and the document does not change with where the tree is checked out (a MULTI-ROOT run declares no single root, so it stays absolute). NO run= means NOT DERIVABLE -- never a guessed suite command

**Try it**

_Pre-PR gate on a CLEAN tree: no obligations, exit 0._

```
$ ./build/ripwire . --test-gate
<!-- ripwire test-gate schema=ripwire.test-gate/v1: tests <t p= changed= partner= hops= run=> + untested blast radius <u sym= p= l= ccx=>; exit 4 while either exists. tests_capped=/untested_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. at=: commit+dirty+shallow. next=: the one pasteable follow-up. impacted=N: symbols that transitively call the change (changed symbols excluded). shown_tests=/shown_untested=: t rows and u rows printed, two independent counts. script_gates_unmodelled=N: test/*.sh runners in the corpus, a path count; not call-graph modelled. script_gates_registered=N: shell gates test/regression.sh registers as suite members. script_gates_mapped=N: registered gates with exact dependency evidence (literal paths or RIPWIRE_TEST_DEPS). script_gates_unresolved_dynamic=N: registered gates with no mappable deps; they may cover the change unlisted. ccx_bar=N: the cognitive-complexity bar a u row's ccx= is read against. untested_modscope=N: <file-scope> owners excluded from untested= (#324, uncallable); still in impacted=. tests=/untested=: tests to run (t total) / impacted symbols no test reaches (u total). -->
<test-gate schema="ripwire.test-gate/v1" changed="0" impacted="0" tests="0" untested="0" untested_modscope="0" shown_tests="0" tests_capped="0" shown_untested="0" untested_capped="0" script_gates_unmodelled="743" script_gates_registered="697" script_gates_mapped="210" script_gates_unresolved_dynamic … [line truncated: 137 more bytes on this line]
</test-gate>
```

**Shaped by:** `--affected`, `--quality-delta`, `--edit-target-file`, `--json`, `--limit`

**Caveats (stated by the binary):**

- for TS/JS, the nearest package.json above the test file naming vitest, jest, or node's own test runner (scripts.test, or a vitest/jest dependency -- never guessed from the .ts/.js extension alone).
- NO run= means NOT DERIVABLE -- never a guessed suite command

### `--grep=STR | --regex=PAT`

**Answers:** search for a literal or a regex;

every hit comes back with its enclosing symbol literal / regex search + enclosing symbol + the matched line. SPAN-TIERED by default (see --grep-in below): the scan itself is exhaustive, the ANSWER serves one tier and discloses what it held back. --grep-in=any is the exhaustive VIEW -- every hit, no tiering. For task-ranked retrieval use --for=TASK (ranks by PageRank + task relevance). --regex is LINE-ORIENTED, like grep/rg: each line is its own search range, so ^ and $ are LINE anchors and no match may span a newline (a trailing CR sits outside the range).

**Try it**

_Literal trigram-indexed search. Each hit carries its MATCHED line as the <hit> element's own CDATA (the <m> wrapper is gone), plus shown/capped/hits_capped and a pasteable next= on the root._

```
$ ./build/ripwire . --grep=DISCLOSE
<!-- ripwire grep schema=ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan; <unindexed> = off-index. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). counts_floor=1: every count is a FLOOR, never a total … [line truncated: 2028 more bytes on this line]
<grep pattern="DISCLOSE" schema="ripwire.grep/v1" root="." files="243" hits="808" shown="100" capped="1" total="808" has_more="1" next_offset="100" offset="0" limit="0" hits_capped="0" suppressed_comment="192" suppressed_string="5" tier_parsed="81" tier_unclassified="559" tier_budget="bytes" tier_fi … [line truncated: 201 more bytes on this line]
<f p=".coderabbit.yaml">
<hit l="30" in="path_instructions" n="2">
<![CDATA[        A degrade path uses DISCLOSE( sink, why ), never ASSUME(false): a one-argument DISCLOSE( msg ) is a debug trace]]>
<at l="30" in="path_instructions"/>
</hit>
</f>
<f p="src/abicheck.h" parse_degraded="1">
<hit l="493" in="abicheck::collectAuthoredSites">
<![CDATA[            DISCLOSE( result, AbiResult::DisclosureWhy::NoMergeBase, "abi: no merge-base for a ref (unrelated history?) — that ref is counted, not compared" );]]>
</hit>
</f>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--affected`, `--and`, `--not`, `--grep-scope`, `--handles`, `--expand`, `--no-redact`, `--insert-after-symbol`

### `--grep-context=N | --grep-before=N / --grep-after=N`

**Answers:** ripgrep-style N lines of source around each hit

**Try it**

_Same search with one line of source context either side._

```
$ ./build/ripwire . --grep=DISCLOSE --grep-context=1
<!-- ripwire grep schema=ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan; <unindexed> = off-index. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). counts_floor=1: every count is a FLOOR, never a total … [line truncated: 2028 more bytes on this line]
<grep pattern="DISCLOSE" schema="ripwire.grep/v1" root="." files="243" hits="808" shown="100" capped="1" total="808" has_more="1" next_offset="100" offset="0" limit="0" hits_capped="0" suppressed_comment="192" suppressed_string="5" tier_parsed="81" tier_unclassified="559" tier_budget="bytes" tier_fi … [line truncated: 201 more bytes on this line]
<f p=".coderabbit.yaml">
<hit l="30" in="path_instructions">
<b>
<![CDATA[        External input (files, git, env, argv, MCP/JSON, data read back from a cache) is checked with VALIDATE.]]>
</b>
<![CDATA[        A degrade path uses DISCLOSE( sink, why ), never ASSUME(false): a one-argument DISCLOSE( msg ) is a debug trace]]>
<a>
<![CDATA[        that ships nothing, and a Diagnostics::answerUnchanged reason must be true. A count that cannot be a total must be]]>
</a>
</hit>
<hit l="30" in="path_instructions">
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--no-redact`

### `--and=STR`

**Answers:** (repeatable)     modifies --grep=STR: keep only hits where STR is ALSO present (literal-only, no --regex)

**Try it**

_Boolean grep: hits where BOTH literals share the matched line (--grep-scope=line is the default)._

```
$ ./build/ripwire . --grep=DISCLOSE --and=cache
<!-- ripwire grep schema=ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan; <unindexed> = off-index. window: shown= capped= (capped=1 cut). hits_capped=1: hits= is a floor. root=: p= relative to it. parse_degraded=1: ERROR nodes in that parse. next=: the one pasteable f … [line truncated: 1338 more bytes on this line]
<grep pattern="DISCLOSE" schema="ripwire.grep/v1" root="." terms="DISCLOSE +cache" scope="line" terms_suppressed="967" files="9" hits="28" shown="28" capped="0" hits_capped="0" suppressed_comment="2" suppressed_string="8" tier_parsed="13" tier_unclassified="0" corpus_oversize="15" corpus_pruned_dirs … [line truncated: 118 more bytes on this line]
<f p="src/ingest_cache.h">
<hit l="1958" in="openCacheFrame" n="5">
<![CDATA[            DISCLOSE( Diagnostics::answerUnchanged, "a rejected cache is rebuilt from source: this run parses and answers byte-identically",]]>
<at l="1966" in="openCacheFrame"/>
<at l="1974" in="openCacheFrame"/>
<at l="2046" in="openCacheFrame"/>
<at l="2141" in="ByteR::fitsBelow"/>
</hit>
<hit l="2006" in="openCacheFrame" n="3">
<![CDATA[        DISCLOSE( Diagnostics::answerUnchanged, "a rejected cache is rebuilt from source: this run parses and answers byte-identically",]]>
<at l="2024" in="openCacheFrame"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--grep-scope`

### `--not=STR`

**Answers:** (repeatable)     modifies --grep=STR: drop hits where STR IS present (literal-only, no --regex)

**Try it**

_Drop every hit in a file that ALSO contains the --not literal anywhere (file scope)._

```
$ ./build/ripwire . --grep=DISCLOSE --not=test --grep-scope=file
<!-- ripwire grep schema=ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan; <unindexed> = off-index. window: shown= capped= (capped=1 cut). hits_capped=1: hits= is a floor. root=: p= relative to it. parse_degraded=1: ERROR nodes in that parse. next=: the one pasteable f … [line truncated: 1241 more bytes on this line]
<grep pattern="DISCLOSE" schema="ripwire.grep/v1" root="." terms="DISCLOSE -test" scope="file" terms_suppressed="967" files="4" hits="11" shown="11" capped="0" hits_capped="0" suppressed_comment="27" tier_parsed="19" tier_unclassified="0" corpus_oversize="15" corpus_pruned_dirs="5" unindexed_hits="8 … [line truncated: 99 more bytes on this line]
<f p="src/commentcoherence.h" parse_degraded="1">
<hit l="216" in="rw::computeCommentCoherence">
<![CDATA[                DISCLOSE( scan, CommentCoherenceScan::DisclosureWhy::UnreadableFile, "comment-coherence: an indexed file could not be read — its functions are absent from the report" );]]>
</hit>
</f>
<f p="src/ingest_docpass.h">
<hit l="34" in="rw::publishDocBridgeBlob" n="3">
<![CDATA[        DISCLOSE( Diagnostics::answerUnchanged, "the doc text is kept for this run: only the bridge cache is not written",]]>
<at l="42" in="rw::publishDocBridgeBlob"/>
<at l="48" in="rw::publishDocBridgeBlob"/>
</hit>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--grep-scope`, `--no-redact`, `--legend`

### `--grep-scope=line|file`

**Answers:** modifies --and=/--not=: must the other term hit the SAME line (default) or anywhere in the file modifies --and=/--not=: line (default) requires the SAME matched line;

file requires anywhere in the same file. Second occurrence of --grep=/--regex= itself REFUSES (naming --and= as the AND spelling) rather than silently overwriting the pattern.

**Try it**

_Drop every hit in a file that ALSO contains the --not literal anywhere (file scope)._

```
$ ./build/ripwire . --grep=DISCLOSE --not=test --grep-scope=file
<!-- ripwire grep schema=ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan; <unindexed> = off-index. window: shown= capped= (capped=1 cut). hits_capped=1: hits= is a floor. root=: p= relative to it. parse_degraded=1: ERROR nodes in that parse. next=: the one pasteable f … [line truncated: 1241 more bytes on this line]
<grep pattern="DISCLOSE" schema="ripwire.grep/v1" root="." terms="DISCLOSE -test" scope="file" terms_suppressed="967" files="4" hits="11" shown="11" capped="0" hits_capped="0" suppressed_comment="27" tier_parsed="19" tier_unclassified="0" corpus_oversize="15" corpus_pruned_dirs="5" unindexed_hits="8 … [line truncated: 99 more bytes on this line]
<f p="src/commentcoherence.h" parse_degraded="1">
<hit l="216" in="rw::computeCommentCoherence">
<![CDATA[                DISCLOSE( scan, CommentCoherenceScan::DisclosureWhy::UnreadableFile, "comment-coherence: an indexed file could not be read — its functions are absent from the report" );]]>
</hit>
</f>
<f p="src/ingest_docpass.h">
<hit l="34" in="rw::publishDocBridgeBlob" n="3">
<![CDATA[        DISCLOSE( Diagnostics::answerUnchanged, "the doc text is kept for this run: only the bridge cache is not written",]]>
<at l="42" in="rw::publishDocBridgeBlob"/>
<at l="48" in="rw::publishDocBridgeBlob"/>
</hit>
... [17 more line(s); run it to see the whole thing]
```

**Caveats (stated by the binary):**

- Second occurrence of --grep=/--regex= itself REFUSES (naming --and= as the AND spelling) rather than silently overwriting the pattern.

### `--grep-in=code|any`

**Answers:** SPAN TIERS: which tree-sitter span a hit must sit in — code (default) or any (exhaustive) SPAN TIERS: which tree-sitter span a hit must sit in to print.

code (default) serves the CODE tier when any hit is code, and otherwise comment AND string TOGETHER (tier= "comment+string"), disclosing what it held back (suppressed_comment=/suppressed_string=); a pattern living only in prose is still answered, never silently emptied. When every code hit is a use of the literal (a test/doc file, or a shell/YAML/TOML/JSON file) and source code (not one of those) holds it as a string, the string tier is served WITH code (tier="code+string"; comments stay held back) — and so it is for a literal no identifier can spell (- / . or a space), a SCREAMING_CASE one, or one with under 8 code hits: rows then rank files named by it, then code, then string-only, 10 by default, string_hits= kept. any turns tiering off entirely -- the exhaustive view. Hit files are parsed on demand under a fixed budget; tier_budget= says so when it stops, and hits it never classified are emitted, never suppressed.

**Try it**

_Span tiers off: the exhaustive view — the comment and string hits the default tier held back (suppressed_comment=96 / suppressed_string=29 in the plain --grep block above) now print alongside the code hits; hits= grows accordingly._

```
$ ./build/ripwire . --grep=DISCLOSE --grep-in=any
<!-- ripwire grep schema=ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan; <unindexed> = off-index. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). hits_capped=1: hits= is a floor. root=: p= relative t … [line truncated: 1386 more bytes on this line]
<grep pattern="DISCLOSE" schema="ripwire.grep/v1" root="." files="268" hits="1005" shown="100" capped="1" total="1005" has_more="1" next_offset="100" offset="0" limit="0" hits_capped="0" corpus_oversize="15" corpus_pruned_dirs="5" unindexed_hits="8" unindexed_files_scanned="254" unindexed_files_skip … [line truncated: 61 more bytes on this line]
<f p=".coderabbit.yaml">
<hit l="30" in="path_instructions" n="2">
<![CDATA[        A degrade path uses DISCLOSE( sink, why ), never ASSUME(false): a one-argument DISCLOSE( msg ) is a debug trace]]>
<at l="30" in="path_instructions"/>
</hit>
</f>
<f p=".github/workflows/ci.yml">
<hit l="243" in="release">
<![CDATA[    #   Release — defines NDEBUG, which compiles the DISCLOSE( msg ) trace out; the optimizer-visible build.]]>
</hit>
<hit l="244" in="release">
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--grep`

**Caveats (stated by the binary):**

- a pattern living only in prose is still answered, never silently emptied.
- tier_budget= says so when it stops, and hits it never classified are emitted, never suppressed.

### `--handles`

**Answers:** (with --grep/--regex) add a stable edit handle h= to each enclosing-symbol row (with --grep/--regex) add h= to each unique editable enclosing-symbol row: a stable identity plus the file-content hash pinned when grep ran.

Ambiguous or document-only rows get no handle; a later edit must refuse after any file change rather than retarget stale coordinates.

**Try it**

_h= on each editable enclosing-symbol row: a freshness-pinned identity an edit verb can target and must refuse on after any file change._

```
$ ./build/ripwire . --grep=DISCLOSE --handles
<!-- ripwire grep schema=ripwire.grep/v1: literal/regex scan grouped by file: <f p=>
<hit l= in=>CDATA text</hit> (<b>/<a> context around it); complete=1 only for an exhaustive literal scan; <unindexed> = off-index. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). counts_floor=1: every count is a FLOOR, never a total … [line truncated: 2028 more bytes on this line]
<grep pattern="DISCLOSE" schema="ripwire.grep/v1" root="." files="243" hits="808" shown="100" capped="1" total="808" has_more="1" next_offset="100" offset="0" limit="0" hits_capped="0" suppressed_comment="192" suppressed_string="5" tier_parsed="81" tier_unclassified="559" tier_budget="bytes" tier_fi … [line truncated: 201 more bytes on this line]
<f p=".coderabbit.yaml">
<hit l="30" in="path_instructions" n="2">
<![CDATA[        A degrade path uses DISCLOSE( sink, why ), never ASSUME(false): a one-argument DISCLOSE( msg ) is a debug trace]]>
<at l="30" in="path_instructions"/>
</hit>
</f>
<f p="src/abicheck.h" parse_degraded="1">
<hit l="493" in="abicheck::collectAuthoredSites">
<![CDATA[            DISCLOSE( result, AbiResult::DisclosureWhy::NoMergeBase, "abi: no merge-base for a ref (unrelated history?) — that ref is counted, not compared" );]]>
</hit>
</f>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--insert-after-symbol`

**Caveats (stated by the binary):**

- Ambiguous or document-only rows get no handle;
- a later edit must refuse after any file change rather than retarget stale coordinates.

### `--match=QUERY`

**Answers:** tree-sitter structural (shape) query

**Try it**

_Tree-sitter structural query WITHOUT a capture — a bare node query gets a capture AUTO-ADDED (auto_captured="1") and matches the same nodes the explicit form does._

```
$ ./build/ripwire . --match='(if_statement)'
<!-- ripwire match schema=ripwire.match/v1: tree-sitter structural query: <m p= in=> captured nodes with their enclosing symbol; grammars=/eligible_files= the scope. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). counts_floor=1: every count is a FLOOR, never a total. hits_capped=1: hits= is a floor. root=: p= relative to it. auto_captured=1: the query bound no @capture, so @m was appended to its single top-level pattern. of_files=: indexed files in all (eligible_files= of them are in the query's languages). -->
<match schema="ripwire.match/v1" hits="5000" shown="100" capped="1" total="5000" has_more="1" next_offset="100" offset="0" limit="0" counts_floor="1" hits_capped="1" auto_captured="1" grammars="cpp,c,python,go,typescript,tsx,swift,objc,javascript,bash,java,csharp,php,dart,lua,gdscript" eligible_file … [line truncated: 34 more bytes on this line]
<m p="bench/agentloop/analyze.py:37" in="load_results">if data.get( "schema" ) != SCHEMA:         raise SystemExit( f"{path}: unexpected schema {data.get('schema')!r} (expecte</m>
<m p="bench/agentloop/analyze.py:48" in="load_results">if not str( data.get( "tasks_lock_content_sha256", "" ) ).startswith( "questions:" ):         train_repos = select_tasks</m>
<m p="bench/agentloop/analyze.py:50" in="load_results">if train_repos:             raise SystemExit(                 f"{path}: records from repo(s) that re-derive to LocBench </m>
<m p="bench/agentloop/analyze.py:72" in="pair_by_task_seed">if base and ctx and base["status"] == "ok" and ctx["status"] == "ok":             paired.append( ( instance_id, base["re</m>
<m p="bench/agentloop/analyze.py:101" in="clustered_bootstrap_lower">if not repos: return 0.0, []</m>
<m p="bench/agentloop/analyze.py:117" in="loc_hit_delta">if base["localization_hit"] is None or ctx["localization_hit"] is None: return 0.0</m>
<m p="bench/agentloop/analyze.py:126" in="paired_ratio">if bv: ratios.append( cv / bv - 1 )</m>
<m p="bench/agentloop/analyze.py:127" in="paired_ratio">if not ratios: return None, None</m>
... [21 more line(s); run it to see the whole thing]
```

**Shaped by:** `--no-redact`, `--sarif`, `--limit`

### `--pattern=PAT`

**Answers:** structural search written in CODE, not in node kinds: --pattern='foo($X, ...)' structural search written in CODE, not in node kinds: --pattern='foo($X, ...)'.

$NAME binds one node (repeat it and both sites must match structurally); $_ binds nothing; ... (or $$$) is an ellipsis over siblings, matched by ONE first-match-wins probe under a hard cap -- both facts on the element. Comments are transparent, everything else is kind- and text-exact ($A + $B does not match a - b). Served: c cpp objc java csharp javascript typescript python go rust swift; ruby, bash and the data tiers are named in unsupported= instead of answered. A pattern no served grammar resolves, or that collapses to a bare token, is REFUSED -- never reported as hits=0. A qualified call (ns::foo) is no hit for a bare foo; unmatched_qualified=N counts them.

**Try it**

_A pattern that collapses to a bare token is REFUSED — never reported as hits=0._

```
$ ./build/ripwire . --pattern='x'
(empty)
```

**Shaped by:** `--limit`

**Caveats (stated by the binary):**

- A pattern no served grammar resolves, or that collapses to a bare token, is REFUSED -- never reported as hits=0.

### `--query=TERMS`

**Answers:** raw BM25 ranking, for debugging the ranker — reach for --for instead raw BM25 ranking (debug);

use --for

**Try it**

_Raw BM25 ranking (debug lens; --for is the real verb)._

```
$ ./build/ripwire . --query="teleport pagerank" --top-k=5
<!-- routed: subtoken+body:broad -->
<!-- ripwire query schema=ripwire.query/v1: lexical-rank map for the query term, the map's row vocabulary. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. <c via="name">: that callee matched by name alone (receiver unproven); it does NOT mean the edge is false. <c x=N>: N same-named via=name rows merged; callees=FILE:SYM lists all. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- files=2688 symbols=25558 edges=40392 shown=5 est_tokens=1389 ambiguous=12495 unresolved=12552 locality_pinned=11 external=7267 declined=12204 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:73,tsv:49,jsonl:26,mod:25,scm:23,expected:15" unindexed_exts=20 order=important-first -->
<r schema="ripwire.query/v1" root="." est_tokens="1389">
<f p="src/serialize.h">
<s t="var" n="kChurnRankLegend" sc="rw" k="18.9156">
</s>
</f>
<f p="src/mcpverbs.h">
<s t="fn" n="rankByText" sc="rw" amb="4" k="15.3995">
<c n="empty" prov="split" via="name" x="4"/>
<c n="takeRank"/>
<c n="rankGraph"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--top-k`, `--token-budget`, `--no-route`, `--adaptive`, `--format`

---

## zoom the detail ladder

### `--detail=N`

**Answers:** (with --for) full bodies for the top N symbols, signatures for the rest (with --for) importance-weighted detail: FULL bodies for the top-N ranked symbols + signatures for the rest, in ONE call — spend body tokens only on the head the rank identifies.

Composes with --max-tokens (bounds the BODIES ONLY, never the bundle — see --max-tokens: past its ceiling the root says over_ceiling="1" rather than cut the rows that answered) and --adaptive. 0 = off.

**Try it**

_Importance-weighted detail: FULL bodies for top-2, signatures for the rest._

```
$ ./build/ripwire . --for="pagerank power iteration" --detail=2
<ctx task="pagerank power iteration" route="subtoken+body" root="." confidence="high" margin_pct="21" at="f1e5c2e76" doc_mentions="5" schema="ripwire.for/v1" budget_bytes="7500" doc_mentions_capped="1" doc_mentions_total="16" est_tokens="5000">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); t p= file outside sigs (weaker), r= rank (gap = trimmed); field name= type= owner= rel=: a member of owner=, rel=creates held by value, uses by reference/pointer; d layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; d e= its last line (absent=unknown, never 0; l= the name's line) [doc mentions: 5 docs, 3 symbols; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="17" [budget_bytes= is the default BYTE ceiling this ranked payload was shaped against; it bounds that payload, not the whole document est_tokens prices] [sigs next=: one call serving all total= rows uncut] [sigs next_offset=: the candidate index the cut starts at; no consumer yet (the for offset pages files; next= re-runs the list)] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] [docs_after_code=N: N doc rows of the shown set moved below its code rows; same rows, reordered, none added or removed; a question naming docs keeps score order] [cut: doc_mentions_capped="1" doc_mentions_total="16" — an indexing cap dropped content not shown here]; lego/compose collapse to a counted stub by default (a disclosed cut): total= that section's own pre-cap row count, shown="0" capped="1" (nothing rendered here), next= names the sections=lego,compose flag that restores both sections byte-identically in one call est_tokens= prices this bundle in tokens -->
<sigs shown="23" total="40" capped="1" docs_dropped="11" docs_after_code="5" next_offset="23" next="--for=&apos;pagerank power iteration&apos; --signatures-only --token-budget=6400">
<d l="419" e="419" n="kScoreTieAbsEps" sc="rw" p="src/eval.h" churn="16" amp="28" pure="1" r="1" next="--expand=src/eval.h:kScoreTieAbsEps">
<doc>NodeId order. Renumbering an otherwise-identical graph (the exact &quot;same probe file, different so…</doc>inline constexpr float kScoreTieAbsEps = 1e-6f</d>
<d l="73" e="144" n="renderDisclosure" sc="rw" p="src/prconverge.h" cx="12" ccx="15" in="14" churn="3" amp="41" r="2">
<doc>Render one form of the disclosure. Empty string whenever there is nothing to say — no power it…</doc>inline std::string renderDisclosure( const RankDisclosure&amp; d, DiscloseAs as )</d>
<d l="99" e="206" n="pageRankDouble" sc="rw" p="src/pagerank.cpp" cx="19" ccx="34" in="2" churn="14" amp="44" tested="1" r="3">
<doc>The PageRank power iteration itself — the numeric kernel every ranked document&apos;s order comes f…</doc>PageRankRun pageRankDouble( const sparseCsr&lt;float&gt;&amp; inEdges, std::span&lt;const double&gt; weightedOutDegree, std::span&lt;const double&gt; teleport, std::span&lt;double&gt; r … [line truncated: 10 more bytes on this line]
... [21 more line(s); run it to see the whole thing]
```

**Shaped by:** `--max-tokens`, `--for`, `--signatures-only`, `--auto-bodies`, `--compress`, `--owners`, `--plan`, `--abi`

**Caveats (stated by the binary):**

- Composes with --max-tokens (bounds the BODIES ONLY, never the bundle — see --max-tokens: past its ceiling the root says over_ceiling="1" rather than cut the rows that answered) and --adaptive.

### `--pack-signatures`

**Answers:** print declaration skeletons with the bodies elided — far cheaper than full bodies body-elided decl skeletons — ~73-91% fewer element bytes than the same symbols' full --expand bodies (about 82% at the top-50 sigs payload cap — the sigs payload is top-50 whatever --top-k is set to, and --top-k's own default is 200), measured at top-10/50/100 on this repo with the corpus-root prefix subtracted from both sides: that prefix repeats inside every element, is charged in both forms, and is not what this elides — count it and the figure becomes a function of how deep your checkout sits.

test/showcasecapturecheck.sh (C) re-derives this range from the SAME repo every run and fails on drift. The share RISES with the result size. Like the --format=columnar sibling, a small result can invert it — a signature plus its doc comment can be bigger than a short body.

**Try it**

_Body-elided decl skeletons — recounted on this corpus. Measured as element bytes: the <d> signature+doc elements --pack-signatures emits, against the SAME symbols' full <b> bodies from --expand, with the CORPUS-ROOT PREFIX SUBTRACTED FROM BOTH SIDES. That subtraction is the whole methodology and the figure is meaningless without it: the root repeats inside every element's id= and p=, it is not what this verb elides, and counting it makes the headline a function of how deep the checkout happens to sit on disk — on one corpus, three spellings of the same root read 18.6 points apart before the subtraction and agree exactly after it. Root-neutralised on THIS repo: 92.7% fewer bytes at top-10, 88.7% at top-50, 87.6% at top-100 (re-derived 2026-09-20 when the native Windows port landed: src/infra/os_win32.cpp and os_win32_logic.h are ~3,900 lines of new, heavily commented infra that the ranked top-10/50/100 now reach, and their bodies are this ratio's DENOMINATOR, so the figure rises without --pack-signatures eliding anything new, from top-50 87.1. Measured by test/showcasecapturecheck.sh's own recount arm on the combined tree, which is the gate that would otherwise report the drift; before that, re-derived 2026-09-17 at the self-check macro vocabulary rename: VERIFY/VERIFY_TEXT/VERIFY_DEBUG_ONLY/VERIFY_NOT_REACHED/VERIFY_SAME_THREAD/VERIFY_NO_ALIAS*/DYNMAP_VERIFY/DEGRADED_PATH_ALERT renamed to ASSUME/EXPECTS/ENSURES/DASSERT/UNREACHABLE/ASSUME_SAME_THREAD*/ASSUME_NO_ALIAS*/DYNMAP_ASSUME/DISCLOSE (plus new VALIDATE sites) across 839 identifier renames in 179 files, and a hand-written Diagnostics.h/diagnostics.cpp replacing the old ones outright: this moves both WHICH symbols the ranked top-10/50/100 hold and how large their bodies are, from top-50 85.2. A real re-derivation of a corpus that changed, not a tolerance edit; previously re-derived 2026-09-12 when the <d> rows dropped the path-repeating id= for the short sc= scope: the signature side shrank, the bodies did not; before that, 89.5% / 81.8% / 84.3% re-derived 2026-09-10 at the sibs= cap raise: kMaxExpandSibs went 8 -> 100, so --expand's <b> bodies now carry the file context the old cap hid — 89.3% of all sibling names — and the body side is this ratio's DENOMINATOR, so the figure rises without --pack-signatures eliding anything new. Measured on a fixed tree with the top-50 membership and the signature side unchanged: top-50 from 71.0. A real re-derivation of a corpus that changed, not a tolerance edit; previously re-derived 2026-09-09 at the printf-family -> std::print conversion: converting ~1,500 emitter call sites to rw::emitTo/emitRaw/formatTo across 93 files changes how large the ranked symbols' BODIES are, and the body side is this ratio's denominator — top-50 from 72.3. A real re-derivation of a corpus that changed, not a tolerance edit; previously re-derived 2026-09-08 at the confident-zero round, issues #62/#63/#66: that change adds symbols to src/graphlegend.h and the new src/preprocdead.h and re-homes two long comment blocks from call sites onto the helpers they explain, which moves both WHICH symbols the ranked top-50 holds and how large their bodies are — top-50 from 74.0. A real re-derivation of a corpus that changed, not a tolerance edit; previously re-derived 2026-09-06 at the stranger-audit fix round: the doctor, cache-sweep and html-provenance bodies grew this corpus's BODY side, moving top-50 from 75.6 — a real re-derivation, not a tolerance edit; before that, re-derived 2026-09-05 at the capture-audit close: lane L7's P16 caps --expand's sibs= at 8 names, which SHRINKS the body side of this ratio and moved the figure down from 84.5/80.2/80.6 — the V1 2026-08-15 re-center, when sibs=/inc= first grew the body side from 70.0/61.0/63.8, in reverse; both were real re-derivations, not tolerance edits). top-50 is the number to quote, because the sigs payload is top-50 regardless of --top-k and is therefore what THIS command emits. A single small/trivial body can still invert it (signature+doc bigger than the body), like the --format=columnar sibling below. test/showcasecapturecheck.sh (C) re-derives all three from this repo every run, in the same quantity, and fails if the caption and the recount drift apart._

```
$ ./build/ripwire . --pack-signatures --top-k=10
<ctx schema="ripwire.pack-signatures/v1">
<!-- ripwire pack-signatures schema=ripwire.pack-signatures/v1: the ranked map plus <sigs>
<d l= n= sc= pure=> signature rows. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls  … [line truncated: 1483 more bytes on this line]
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- files=2688 symbols=25558 edges=40392 shown=10 est_tokens=4613 ambiguous=12495 unresolved=12552 locality_pinned=11 external=7267 declined=12204 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:73,tsv:49,jsonl:26,mod:25,scm:23,expected:15" unindexed_exts=20 order=important-first -->
<r root="." est_tokens="5265" pr_iters="28">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="buf" sc="svector" overloads="2" k="0.0070">
</s>
<s t="method" n="push_back" sc="svector" amb="2" k="0.0049">
<c n="buf" prov="split"/>
<c n="buf" prov="split"/>
<c n="grow"/>
</s>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--top-k`, `--limit`

### `--outline=A,B,...`

**Answers:** control-flow skeletons of A,B,...

(same selector grammar as --expand, minus the range)

**Try it**

_Control-flow skeleton of one symbol, payload-only via the new --top-k=0._

```
$ ./build/ripwire . --outline=rankGraphTeleport --top-k=0
<!-- ripwire pack-signatures schema=ripwire.pack-signatures/v1: the ranked map plus <sigs>
<d l= n= sc= pure=> signature rows. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. -->
<ctx schema="ripwire.pack-signatures/v1" root="." est_tokens="327">
<outline>
<o t="fn" l="7924" p="src/graph.h" n="rankGraphTeleport">
<![CDATA[inline RankedGraph rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )
{
    PROFILE_SCOPE_DESCRIBE( "rankGraph: PageRank (power iteration)" );
    const std::vector<float> pw = biasPrior( g, p );
    const std::size_t N = pw.size();
    std::vector<double> teleport( pw.begin(), pw.end() );
    std::vector<double> rankDouble( N, 0.0 );
    PageRankRun         run{};   // an N == 0 graph never enters the kernel: { 0, converged } — see PageRankRun
    if( N )
... [8 more line(s); run it to see the whole thing]
```

**Shaped by:** `--top-k`, `--expand`, `--compress`, `--no-redact`, `--limit`, `--max-memory`

### `--expand=A,B,...`

**Answers:** print these symbols' full bodies, plus the signatures of what they call full bodies of A,B,...

Selector grammar per item (the tail after the LAST ':' decides; a tail STARTING WITH A DIGIT is a range, anything else is a name): NAME                every def of that name  |  FILE:NAME           that file's def NAME:START-END      body slice              |  FILE:NAME:START-END selector + slice FILE:LINE:NAME      paste a row's p="path:line" straight from --callers/--lint/--grep (NOT --hotspots: its p= is a BARE path — build FILE:LINE:NAME from its own p=/top_l=/top= instead, since top= is just the worst function's name) path::scope::name   the id composed from a row's p= sc= n= (the map, --for, --pack-task) Scope::name         the sym= spelling edit-check and grep's in= rows print — matches the name under any scope whose ::-boundary SUFFIX is Scope (Box::lid, deep::Box::lid); a wrong scope refuses, it never falls back to the bare-name union Scope.name|Scope#name  the same match, dotted (Python/JS/Java) or Ruby-style; tried only when no other spelling matched (START-END is 1-based within the def's OWN body — lines="lo-hi/total" marks the slice partial; out-of-range clamps. FILE matches any path substring, like --callers/--lego.) EXACT-NAME DEFAULT (one token, one unambiguous match, no explicit --top-k): the ranked map defaults to top-k=0 — you already named the exact symbol, so the ~200-row orientation map is pure overhead in front of the one body it exists to summarize. Disclosed on the root as topk_default="0" (self-describing: the change is visible without reading source). A MULTI-match name (an ambiguous bare name) or a multi-token --expand keeps the map — there IS something to disambiguate. An EXPLICIT --top-k=N (0 included) always overrides this default. Each body also carries sibs="a,b,..." sibs_total="N" [sibs_capped="1"] (the file's OTHER symbols, names only, capped at 40) and inc="x.h,..." inc_total="N" [inc_capped="1"] (the file's own #include/import targets, capped at 24) — both absent when the count is 0 (a documented zero, not a degrade), so a body no longer needs a second --outline call just to learn what else lives in its file. CHEAPEST-COMPLETE-ANSWER SERVING (no explicit --top-k, no range slice): the verb ALSO measures the (possibly map-less) bundle against the requested symbols' whole FILE(s) and emits the SMALLER, disclosed on the root as mode="bundle|whole-file" reason="the two byte counts" — on a small file the old bundle was 5.65x the file itself; on a big file the bundle saves ~26x. The whole-file form is <src p= sym="name:line,..."> with the file CDATA-wrapped (redacted as usual) and every requested symbol's line anchor kept. An EXPLICIT --top-k=N (including 0) opts out of BOTH the exact-name default and mode= auto-selection and keeps the classic undecorated shape; a SYM:START-END slice opts out of mode= auto-selection only (serving the whole file would invert an explicit narrowing) but still gets the exact-name top-k=0 default when it applies. When the bundle wins AND no explicit --top-k was given, the requested bodies are served BEFORE the ranked map (not buried after it), and the map's escape hatch also rides the root as note="...--top-k=0 for the payload alone..." (not stderr-only): a caller reading only stdout sees both the answer and how to drop the map on the next call. Absent whenever the bundle carries no map at all (top-k=0, exact-name default) or loses to whole-file, and whenever --top-k was explicit — the classic shape above carries no note= either.

**Try it**

_NEW since the last capture: --top-k=0 means PAYLOAD-ONLY — no ranked map rides along with the body you asked for._

```
$ ./build/ripwire . --top-k=0 --expand=rankGraphTeleport
<ctx schema="ripwire.expand/v1" root="." est_tokens="1298">
<!-- ripwire expand schema=ripwire.expand/v1: full bodies: <bodies shown= total= capped=> of <b t= l= p= n= sibs= sibs_total= sibs_capped= inc=>; <calls>
<c n= l=> resolved callees. window: shown= total= capped= (capped=1 cut). sibs_capped=/inc_capped=: 1 = cut. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. <c via="name">: that callee matched by name alone (receiver unproven); it does NOT mean the edge is fal … [line truncated: 272 more bytes on this line]
<bodies shown="1" total="1" capped="0">
<b t="fn" l="7924" p="src/graph.h" n="rankGraphTeleport" sibs="Graph,edgeNameOnlyInCsr,edgeNameOnly,pathHasNameOnlyHop,edgeExists,rowNameOnly,viaNameAttr,provLabel,langCompatible,namespaceCompatible,kCommonNameMul,kCommonNameDefThreshold,kPrivateNameMul,kSpecificNameMul,kSpecificMinLen,kSpecificMinW … [line truncated: 1794 more bytes on this line]
<![CDATA[inline RankedGraph rankGraphTeleport( const Graph& g, const std::vector<float>& p, float alpha = 0.85f )
{
    PROFILE_SCOPE_DESCRIBE( "rankGraph: PageRank (power iteration)" );
    const std::vector<float> pw = biasPrior( g, p );
    const std::size_t N = pw.size();
    std::vector<double> teleport( pw.begin(), pw.end() );
    std::vector<double> rankDouble( N, 0.0 );
    PageRankRun         run{};   // an N == 0 graph never enters the kernel: { 0, converged } — see PageRankRun
    if( N )
... [20 more line(s); run it to see the whole thing]
```

**Shaped by:** `--top-k`, `--for`, `--no-route`, `--pack-signatures`, `--outline`, `--compress`, `--no-redact`, `--hotspots`

**Caveats (stated by the binary):**

- a wrong scope refuses, it never falls back to the bare-name union Scope.name|Scope#name  the same match, dotted (Python/JS/Java) or Ruby-style;
- FILE matches any path substring, like --callers/--lego.) EXACT-NAME DEFAULT (one token, one unambiguous match, no explicit --top-k): the ranked map defaults to top-k=0 — you already named the exact symbol, so the ~200-row orientation map is pure overhead in front of the one body it exists to summarize.
- A MULTI-match name (an ambiguous bare name) or a multi-token --expand keeps the map — there IS something to disambiguate.

### `--compress`

**Answers:** strip comments and collapse blank runs from every body this run serves strip comments + collapse blank runs from SERVED BODIES (~20-35% token cut): --expand/ --outline, --for's auto/anchor and --detail=N bodies, --pack-task, --from-trace and --exemplar.

Disclosed per bundle as compress="1" on the <bodies> element; without the flag, output is byte-identical. String literals survive; the ranked SET never changes.

**Try it**

_Comments stripped + blank runs collapsed — compressBody is the function that implements --compress itself, chosen because it is comment-heavy enough to show a real reduction (the previously captioned symbol had no comments or blank runs, so before/after were byte-identical under a caption promising a difference)._

```
$ ./build/ripwire . --expand=compressBody --top-k=0 --compress
<ctx schema="ripwire.expand/v1" root="." est_tokens="2215">
<!-- ripwire expand schema=ripwire.expand/v1: full bodies: <bodies shown= total= capped=> of <b t= l= p= n= sibs= sibs_total= sibs_capped= inc=>; <calls>
<c n= l=> resolved callees. window: shown= total= capped= (capped=1 cut). sibs_capped=/inc_capped=: 1 = cut. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. <c via="name">: that callee matched by name alone (receiver unproven); it does NOT mean the edge is fal … [line truncated: 443 more bytes on this line]
<bodies shown="1" total="1" capped="0" compress="1">
<b t="fn" l="4020" p="src/serialize.h" n="compressBody" sibs="&lt;file-scope&gt;,xmlSafeByte,xmlScrubIsLossy,xmlControlCharRef,kXmlEscapeByteset,escapeXml,writeMultiRootTable,kMultiRootTableLegend,multiRootTableLegend,xmlCommentText,ctxRootOpen,ctxRootJsonScrubKeys,appendCdataSafe,XmlWriter,XmlWrite … [line truncated: 1878 more bytes on this line]
<![CDATA[inline std::string compressBody( std::string_view src )
{


    std::string out;
    out.reserve( src.size() );

    const std::size_t N = src.size();
    std::size_t       i = 0;
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--for`

**Caveats (stated by the binary):**

- the ranked SET never changes.

### `--pack-top-n=N`

**Answers:** pack the N top symbols' bodies  [--pack-budget-bytes=B] A budget cut is stated: truncated=1 lines=1-K/T on the cut file, src_cut shown= total= capped=1.

**Try it**

_Pack the top-3 ranked symbols' full bodies (deprecated verb; see stderr)._

```
$ ./build/ripwire . --pack-top-n=3 --top-k=0
<ctx schema="ripwire.pack-top-n/v1" root="." est_tokens="17465">
<!-- ripwire pack-top-n schema=ripwire.pack-top-n/v1: the ranked map plus <src p=> bodies of the top-N symbols. window: shown= total= capped= (capped=1 cut). est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. <src truncated=1 lines=1-K/T>: cut at a line end at the byte budget; K of its T lines. <src_cut shown= total= capped=1 budget_bytes=>: files served of the top-N asked, the rest over the byte ceiling; unreadable=N not readable. -->
<src_cut shown="2" total="3" capped="1" budget_bytes="65536"/>
<src p="./src/infra/svector.h">
<![CDATA[#pragma once

// svector.h — rw::svector: a small-vector with N INLINE slots that spills to the heap only past N.
// 16 bytes at <uint32,2>, with a BRANCH-FREE size(). Both, not one or the other.
//
// ── THE DESIGN, AND WHY IT IS THIS ONE ───────────────────────────────────────────────────────────────
// The shape the host tree leans on hardest is `Map<K, svector<V,N>>` — many tiny id-lists (byName /
// canonByName / shard maps, and ~100 more structures after the conversion wave): WRITE-ONCE during the
// parse/merge, then READ-HOT during resolve.
//
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--top-k`, `--token-budget`, `--for`

**Caveats (stated by the binary):**

- pack the N top symbols' bodies  [--pack-budget-bytes=B] A budget cut is stated: truncated=1 lines=1-K/T on the cut file, src_cut shown= total= capped=1.

### `--no-redact`

**Answers:** emit source and doc text verbatim, redacting nothing emit source/doc text VERBATIM, redacting nothing.

Modifies the BODY-serving verbs (--expand, --for, --pack-task, --recall, --slice, --connect, --from-trace, --batch, --mcp); the default map carries no bodies (identifiers and signatures are never redacted), so bare on the map it is refused, naming one of them REDACTED by default (high-confidence credential SHAPES only, precision over recall): emitted symbol BODIES, doc/markdown bodies and doc-comment excerpts, the --outline skeleton, and SIGNATURES — a default argument carries whatever literal was written. NOT redacted, and a deliberate residual: --grep/--regex/--match hit lines and their --grep-context neighbours, and --note-add/--notes text. --grep is the exception on purpose — auditing a repo FOR secrets needs the hit you searched for shown verbatim.

**Try it**

_--no-redact: emit bodies verbatim (credential redaction is on by default)._

```
$ ./build/ripwire . --expand=readAckRecords --top-k=0 --no-redact
<ctx schema="ripwire.expand/v1" root="." est_tokens="3246">
<!-- ripwire expand schema=ripwire.expand/v1: full bodies: <bodies shown= total= capped=> of <b t= l= p= n= sibs= sibs_total= sibs_capped= inc=>; <calls>
<c n= l=> resolved callees. window: shown= total= capped= (capped=1 cut). sibs_capped=/inc_capped=: 1 = cut. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. <c via="name">: that callee matched by name alone (receiver unproven); it does NOT mean the edge is fal … [line truncated: 443 more bytes on this line]
<bodies shown="3" total="3" capped="0">
<b t="fn" l="7010" p="src/quality.h" n="readAckRecords" sibs="&lt;file-scope&gt;,kBaselineFile,kMinCloneTokens,kCcxBar,kLocBar,kNestBar,kParamBar,kShortHorizonDays,kShortHorizonMinCommits,kReusedHelperMinFanin,kMinorCcxDelta,kMinorLocDelta,kMinorParamDelta,kMaterialGrowthPct,kSubBarGrowthPct,subBarG … [line truncated: 1836 more bytes on this line]
<![CDATA[inline gtl::btree_map<std::string, AckRecord> readAckRecords( const std::string& path, std::size_t& badLines );]]>
</b>
<b t="fn" l="7012" p="src/quality.h" n="readAckRecords" sibs="&lt;file-scope&gt;,kBaselineFile,kMinCloneTokens,kCcxBar,kLocBar,kNestBar,kParamBar,kShortHorizonDays,kShortHorizonMinCommits,kReusedHelperMinFanin,kMinorCcxDelta,kMinorLocDelta,kMinorParamDelta,kMaterialGrowthPct,kSubBarGrowthPct,subBarG … [line truncated: 1836 more bytes on this line]
<![CDATA[inline gtl::btree_map<std::string, AckRecord> readAckRecords( const std::string& path )
{
    std::size_t ignored = 0;
    return readAckRecords( path, ignored );
... [19 more line(s); run it to see the whole thing]
```

**Shaped by:** `--insert-after-symbol`

---

## assess quality / structure

### `--metrics`

**Answers:** annotate every symbol with fan-in, fan-out and complexity annotate fan-in/out + complexity (descriptive;

coupling is the validated signal, complexity is a size-correlated one). also surfaces amp= (--metrics/--for/--exemplar): amp = |direct callers| (symbol-level, the in-edge CSR) + |co-change partners of the symbol's FILE| (file-level, mined from git history) — a deliberate GRANULARITY MIX, not a graph-only count; degrades to callers-only (still valid) when git/history is unavailable. NOT the same quantity as --impact's reaches=: reaches= is the TRANSITIVE blast radius over the call graph alone (everything that reaches SYM, any hop count); amp= is DIRECT callers plus a historical co-edit signal the call graph cannot see at all — the two numbers on the same symbol routinely differ several-fold (one seen case: 4.6x apart) because they measure different things, not because one is wrong. ppalt=N (C-family/C#): the body contains N alternative preprocessor branches (#else/#elif) — code that never coexists at compile time. cx/ccx/nest/loc/locals are summed over ALL branches (deterministic, but an over-count vs any single build; ~2x seen on a real SSE/scalar pair), so discount them accordingly. ripwire never guesses which branch your build compiles — it discloses the count instead. A bare #if with no #else adds no alternative and no ppalt=. Absent when 0. ev=N essential complexity (McCabe: 1=fully structured, 2+=jumps block extract-method cleanly — the jump makes it a rewrite, not a mechanical lift); ev_why=tag:count names which jumps raised it (guard-return, loop-escape, ...). A FLOOR (ev_floor=1): noreturn calls/macro-hidden exits go unseen; absent on a cx row means exactly 1, and Rust ?/ yield/await/defer are not counted, so Bash carries no ev at all. humps=/deep=/locals= are the nesting PROFILE nest= alone cannot give: nest= is a max, so one deep line and a body that is deep throughout report the same number. humps= counts regions reaching the nesting bar, deep= the lines inside them (a floor), and locals= the local-variable-declaration count (a floor, C/C++ only). Read the three together — a tangle (many humps, few deep lines each) and a long blocked-sequential body (one hump, many deep lines) have the same nest= but opposite refactors. Absent exactly when nest is below the bar (not-deep), never a hidden 0.

**Try it**

_Fan-in/out + complexity annotations on the map._

```
$ ./build/ripwire . --metrics --top-k=10
<!-- ripwire metrics schema=ripwire.metrics/v1: the ranked map with per-symbol metrics: in/out, cx/ccx, loc, params, nest, humps/deep, locals, cbo, amp, tested, ev. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. <s tested=1>: a non-test row an indexed test transitively reaches (absent otherwise, never 0). <c via="name">: that callee matched by name alone (receiver unproven); it does NOT mean the edge is false. <c x=N>: N same-named via=name rows merged; callees=FILE:SYM lists all. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. locals_floor=1: locals= is a floor. role=hub: in= is 8 or more. s in= out= cx= ccx= loc= params= nest= cbo= amp=: callers, callees, cyclomatic/cognitive complexity, lines, parameters, nesting depth, coupled types, callers + co-changed files. ev=/ev_why=: essential complexity (2+: jumps block extract-method; absent: 1) / the jumps behind it, tag:count. ev_floor=1: ev= is a FLOOR; noreturn calls, macro-hidden exits and unresolved gotos are unseen. layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; absent if none. l=N: start line; only on a same-name overload's row, one row per body (bodyless decls fold into overloads=). -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- files=2688 symbols=25558 edges=40392 shown=10 est_tokens=2265 ambiguous=12495 unresolved=12552 locality_pinned=11 external=7267 declined=12204 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:73,tsv:49,jsonl:26,mod:25,scm:23,expected:15" unindexed_exts=20 order=important-first -->
<r schema="ripwire.metrics/v1" root="." est_tokens="2265" pr_iters="28">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="buf" sc="svector" l="125" in="29" out="0" cx="2" ccx="1" role="hub" loc="1" params="0" nest="1" locals="0" locals_floor="1" cbo="0" amp="52" tested="1" k="0.0070">
</s>
<s t="method" n="buf" sc="svector" l="126" in="29" out="0" cx="2" ccx="1" role="hub" loc="1" params="0" nest="1" locals="0" locals_floor="1" cbo="0" amp="52" tested="1" k="0.0070">
</s>
<s t="method" n="push_back" sc="svector" in="738" out="3" cx="2" ccx="1" role="hub" loc="5" params="1" nest="1" locals="1" locals_floor="1" cbo="3" amp="761" tested="1" amb="2" k="0.0049" ev="2" ev_floor="1" ev_why="guard-return:1">
<c n="buf" prov="split"/>
<c n="buf" prov="split"/>
<c n="grow"/>
</s>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--doctor`, `--json`, `--limit`, `--index-out`

**Caveats (stated by the binary):**

- also surfaces amp= (--metrics/--for/--exemplar): amp = |direct callers| (symbol-level, the in-edge CSR) + |co-change partners of the symbol's FILE| (file-level, mined from git history) — a deliberate GRANULARITY MIX, not a graph-only count;
- degrades to callers-only (still valid) when git/history is unavailable.
- amp= is DIRECT callers plus a historical co-edit signal the call graph cannot see at all — the two numbers on the same symbol routinely differ several-fold (one seen case: 4.6x apart) because they measure different things, not because one is wrong.

### `--deps`

**Answers:** build the file-to-file dependency graph — god-files and cycles file->file dependency graph (god-files, cycles — validated);

its nccd (Lakos) is a design heuristic, not independently outcome-validated. instab= (Martin's I=Ce/(Ca+Ce)) counts project includes ONLY -- system/third-party headers are excluded from Ce, matching stabledeps' gap= so gap == consumer's instab - provider's instab always. <health>'s ccd/acd/nccd/shape are computed over dep_files= (files whose language has #include/import syntax) not files= (the raw corpus, incl. md/json/toml/yaml, which can't participate in the graph) -- --arch's propagation_cost uses the same N. <health dep_langs=> names that language set, which is what makes a dep_files=/ccd/ acd/nccd number comparable across builds: sh, rb, lua and ex joined it at parser version 81 and every one of those numbers moved on a corpus holding them. STRUCTURE vs USE (parser version 83): a LAZY edge -- every directive of the pair written inside a closure (Ruby method/lambda/block, TS/JS function body), a Ruby autoload or rescue class -- is a use, not a load-time dependency: it is in --impact's importer tier (lazy=1) and in the row's inc t= list, NOT in afferent/instab/transitive/godfiles/ stabledeps/cycles/ccd/acd/nccd/shape. <health lazy_edges=> counts the pairs left out, a row's lazy_edges= its own; both absent when 0. A TS/JS import through a tsconfig paths alias or baseUrl, a workspace package or a package.json imports entry draws its edge by tsc's and Node's rules from the configs inside the crawl root, and one that names this tree yet draws no edge is counted in the root's imports_unresolved=N graph_partial=1. Configs that were not read (above the crawl root up to the git top-level, unparseable, or an extends or references target not in the tree) are counted in tsconfig_unread=N: numbers above are then over resolved edges only. The nearest tsconfig's aliases apply to every TS/JS file below it, whether or not its include lists the file (a references project owns its own)

**Try it**

_File->file dependency graph (god-files, cycles)._

```
$ ./build/ripwire . --deps
<!-- ripwire deps schema=ripwire.deps/v1: file-to-file include/import view, heaviest cone first: <f p= afferent= includes= instab= transitive=>, <health>, <godfiles>, <cycles>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). root=: p= relative to it. files=N: files with at least one include/import directive; this listing's denominator (health files= = corpus). violations=N: edges into a file more unstable by over 0.05 (Martin I); only the worst 12 are listed. from=: the including file of a stable-deps violation; it depends on the more unstable to=. gap=: instab of to= minus instab of from=, project includes only; worst first. health dep_files=N: dependency-capable files (dep_langs=), the ccd/acd/nccd denominator. health dep_langs=: the languages dep_files= counts; compare its numbers across builds only when equal. ccd=/acd=/nccd=: Lakos: sum of per-file transitive cones (self incl) / per file / over a balanced tree's. health shape=: the nccd= verdict: horizontal below 1, vertical 1 to 2, tangled above 2 (a heuristic). health lazy_edges=N: in-closure (lazy) include pairs kept OUT of cones, cycles and ccd; absent at 0. cycle size=/cost=: files in that include cycle / size squared, the cycle's share of ccd=. cycle cut=/cutrefs=: SUGGESTED edge to break it (fewest directives) / that edge's directive count; nothing cut. -->
<deps schema="ripwire.deps/v1" files="990" shown="40" capped="1" total="990" has_more="1" next_offset="40" offset="0" limit="0" root=".">
<health files="2688" dep_files="2335" ccd="9878" acd="4.2" nccd="0.41" shape="horizontal" lazy_edges="61" dep_langs="cpp,py,ts,go,rs,swift,objc,js,sh,java,rb,cs,c,php,lua,ex,kt"/>
<godfiles total="476" shown="12" capped="1">
<f p="test/lib/clean-env.sh" afferent="185"/>
<f p="src/model.h" afferent="88"/>
<f p="src/infra/emit.h" afferent="86"/>
<f p="src/infra/Diagnostics.h" afferent="60"/>
<f p="src/serialize.h" afferent="40"/>
<f p="src/graph.h" afferent="38"/>
<f p="src/infra/os.h" afferent="35"/>
<f p="scripts/cxxstd.sh" afferent="27"/>
<f p="src/infra/jsonesc.h" afferent="25"/>
<f p="src/ingest.h" afferent="24"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--arch`, `--limit`

**Caveats (stated by the binary):**

- its nccd (Lakos) is a design heuristic, not independently outcome-validated.
- A TS/JS import through a tsconfig paths alias or baseUrl, a workspace package or a package.json imports entry draws its edge by tsc's and Node's rules from the configs inside the crawl root, and one that names this tree yet draws no edge is counted in the root's imports_unresolved=N graph_partial=1.

### `--hotspots`

**Answers:** rank files by complexity times recent git churn — where maintenance hurts complexity x recent git churn (maintenance pain);

each row's top= is the worst function's BARE name, top_ccx= its cognitive complexity, top_l= its source line (build an --expand selector from p=/top_l=/top=, not from top= alone — it no longer carries a :line suffix) A function whose extent failed a containment check is LEFT OUT of ccx=/score=/top= and counted: extent_suspect_syms= on its row, unranked_extent_suspect= for a file with none left

**Try it**

_Complexity x recent git churn (maintenance pain)._

```
$ ./build/ripwire . --hotspots
<!-- ripwire hotspots schema=ripwire.hotspots/v1: maintenance pain = churn x ccx over window=: <f p= churn= ccx= score= top= top_ccx= top_l=>; unranked_*= no churn/complexity. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). at=: commit+dirty+shallow. root=: p= relative to it. files=/ranked=: files in the window / those with both churn and complexity; ranked + unranked_no_churn + unranked_no_complexity = files. unranked_no_churn=/unranked_no_complexity=: files left out for no commit in window= / no measured complexity. -->
<!-- extent_suspect_syms=K on a row = K of the file's functions failed an extent/scope containment check (the map, the bundles and the skipped verb mark each one, reasons and all) and are LEFT OUT of that row's ccx=, score= and top=, so its ccx= is a FLOOR of the file's true sum rather than a total. unranked_extent_suspect= counts files with commits whose every scorable function was left out that way (or whose trusted remainder scores 0), so ranked= + unranked_no_churn= + unranked_no_complexity= + unranked_extent_suspect= = files= exactly. Absent = nothing excluded. -->
<hotspots schema="ripwire.hotspots/v1" window="12mo@HEAD" files="2688" ranked="718" unranked_no_churn="0" unranked_no_complexity="1968" unranked_extent_suspect="2" shown="40" capped="1" total="718" has_more="1" next_offset="40" offset="0" limit="0" root="." at="f1e5c2e76">
<f p="src/graph.h" churn="287" ccx="3649" score="1047263" top="buildGraph" top_ccx="1208" top_l="5516"/>
<f p="src/quality.h" churn="389" ccx="1808" score="703312" top="computeDelta" top_ccx="324" top_l="8487"/>
<f p="src/serialize.h" churn="293" ccx="2227" score="652511" top="serialize" top_ccx="265" top_l="2746"/>
<f p="src/main.cpp" churn="424" ccx="1189" score="504136" top="dispatchMain" top_ccx="473" top_l="4132"/>
<f p="src/mcpverbs.h" churn="340" ccx="1183" score="402220" top="runBatchSub" top_ccx="138" top_l="5419"/>
<f p="src/cli.h" churn="450" ccx="643" score="289350" top="parseArgs" top_ccx="213" top_l="5218"/>
<f p="src/resolve.h" churn="133" ccx="1847" score="245651" top="buildPreciseIncludeAdjWithContext" top_ccx="84" top_l="4318"/>
<f p="src/mcp.h" churn="128" ccx="927" score="118656" top="dispatchMcpLine" top_ccx="735" top_l="1118"/>
<f p="src/ingest_binds.h" churn="69" ccx="1661" score="114609" top="bindsVisitNode" top_ccx="85" top_l="5346"/>
<f p="src/verbs_navigate.h" churn="139" ccx="722" score="100358" top="runVerify" top_ccx="142" top_l="1702"/>
<f p="src/verbs_for.h" churn="133" ccx="744" score="98952" top="runForLensPass" top_ccx="360" top_l="2378"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--affected`, `--expand`, `--since`, `--limit`

### `--clones`

**Answers:** token-normalized duplicate bodies

**Try it**

_Token-normalized duplicate bodies._

```
$ ./build/ripwire . --clones
<!-- ripwire clones schema=ripwire.clones/v1: similar normalized-token bodies: <group type=2|3 gid= tokens= n= similarity=> of <f n= p=>; dup_loc=/dup_pct=. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). root=: p= relative to it. groups=/type3=: Type-2 and Type-3 group totals over all groups; total= is their sum. exempt_groups=N: groups whose members all sit on fixture/shell-runner paths quality-delta duplication ignores. idiom_groups=/demoted_groups=: groups of one recognized idiom / those quality-delta demotes to minor; floors. clone_groups=N: clusters after merging pairs (rows sharing gid=); a floor under type3_capped=1. total_loc=N: lines of every function body the detector considered; dup_pct= is dup_loc= over it. group exempt=fixture|shell-runner: every member is on such a path; quality-delta duplication ignores it. group idiom=: the recognized shape every member spells: threshold-ladder, switch-name-table, builder-chain. -->
<clones schema="ripwire.clones/v1" groups="131" type3="565" exempt_groups="397" idiom_groups="17" demoted_groups="12" clone_groups="332" dup_loc="7185" total_loc="211512" dup_pct="3.4" shown="80" capped="1" total="696" has_more="1" next_offset="80" offset="0" limit="0" root=".">
<group type="2" gid="49" tokens="338" n="3">
<f n="rw_is_ripwire_call" p="hooks/ripwire-claude-route.sh:187"/>
<f n="rw_is_ripwire_call" p="hooks/ripwire-codex-route.sh:104"/>
<f n="rw_is_ripwire_call" p="hooks/ripwire-nudge.sh:623"/>
</group>
<group type="2" gid="218" tokens="213" n="2" exempt="shell-runner">
<f n="call_sites" p="test/declinecheck.sh:114"/>
<f n="call_sites" p="test/usesselectorcheck.sh:49"/>
</group>
<group type="2" gid="277" tokens="211" n="4" exempt="shell-runner">
<f n="batch_sub" p="test/mcpclidiffcheck.sh:64"/>
<f n="batch_sub" p="test/mcptranchecheck.sh:55"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--affected`, `--limit`

### `--biggest-first`

**Answers:** order functions by Halstead volume, token entropy and length, largest first per-function lens, LARGEST Halstead volume/token-count/length first (a size proxy, not a readability order — see WITHDRAWN below): vol= Halstead volume V (N*log2(eta)), ent= Shannon token entropy E, lines= L, posnett= sigmoid(8.87 - 0.033V + 0.40L - 1.5E) (Posnett/Hindle/Devanbu, MSR 2011).

APPROXIMATION, disclosed: ONE token-class table serves every language (keywords + punctuation = operators, identifiers + literals = operands), with no per-grammar refinement, so V is cross-language and not a per-grammar Halstead count. The formula was fitted on snippets of 20 lines or fewer, so it is a RANKING lens, not a grade: read the ORDER of the rows, not the number on any one of them. Pages with limit=N (offset=M); default 40 rows. Declarations with no body are not measured. MEASURED: on ripwire's own history at the pinned v0.6.2 tag (412 function pairs mined from 80 refactor/simplify/cleanup commits), the order between two versions of a function tracked the sign of its token-count change in 96.0% of pairs (388/404 whose count changed). Read a move as more or fewer tokens, not as more or less readable; full derivation and history in docs/EVALS.md §8. Do not read a low posnett= as proof a function needs work. WITHDRAWN: the ordering claim (that a lower posnett= predicts a later fix) is withdrawn -- stratified into narrow token-count bands, the later-fix association disappears in 8 of 10 deciles (CIs include 1), so the order is a size proxy, not an independent readability signal; derivation in docs/EVALS.md §8.

**Try it**

_Per-function size ranking, largest Halstead volume/token entropy/lines first — a size proxy, not a readability order (withdrawn, docs/EVALS.md §8) — a RANKING lens, not a grade._

```
$ ./build/ripwire . --biggest-first --limit=8
<!-- ripwire readability schema=ripwire.readability/v1: Posnett/Hindle/Devanbu lens, largest Halstead volume first (a size proxy): <fn p= n= lines= toks= ops= vocab= vol= ent= posnett=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). root=: p= relative to it. functions=N: functions and methods measured (bodyless declarations are not). -->
<readability schema="ripwire.readability/v1" functions="14065" shown="8" capped="1" total="14065" has_more="1" next_offset="8" offset="0" limit="8" root=".">
<fn p="src/graph.h:5516" n="buildGraph" lines="2359" toks="13035" ops="8346" vocab="759" vol="124718.3" ent="6.60" posnett="0.000"/>
<fn p="src/mcp.h:1118" n="dispatchMcpLine" lines="1711" toks="8787" ops="5578" vocab="773" vol="84305.3" ent="6.52" posnett="0.000"/>
<fn p="src/main.cpp:4132" n="dispatchMain" lines="1485" toks="7193" ops="4622" vocab="638" vol="67020.1" ent="6.35" posnett="0.000"/>
<fn p="src/verbs_for.h:2378" n="runForLensPass" lines="1423" toks="6518" ops="3997" vocab="597" vol="60106.3" ent="6.55" posnett="0.000"/>
<fn p="src/main.cpp:1632" n="runDefaultMap" lines="1142" toks="6139" ops="3775" vocab="502" vol="55076.3" ent="6.46" posnett="0.000"/>
<fn p="src/packtask.h:1409" n="packTaskBundleText" lines="829" toks="5756" ops="3520" vocab="525" vol="52012.2" ent="6.55" posnett="0.000"/>
<fn p="src/lexical.h:470" n="lexicalScoresTiered" lines="972" toks="5633" ops="3570" vocab="369" vol="48035.3" ent="6.33" posnett="0.000"/>
<fn p="src/verbs_report.h:3143" n="runStructureText" lines="570" toks="5184" ops="3146" vocab="360" vol="44021.8" ent="6.20" posnett="0.000"/>
</readability>
```

**Shaped by:** `--limit`

**Caveats (stated by the binary):**

- APPROXIMATION, disclosed: ONE token-class table serves every language (keywords + punctuation = operators, identifiers + literals = operands), with no per-grammar refinement, so V is cross-language and not a per-grammar Halstead count.
- The formula was fitted on snippets of 20 lines or fewer, so it is a RANKING lens, not a grade: read the ORDER of the rows, not the number on any one of them.
- Pages with limit=N (offset=M);

### `--nonlocal-state`

**Answers:** per function, the non-local mutable state it can reach, most writes first per function, the NON-LOCAL MUTABLE STATE it can reach, MOST WRITES FIRST: writes= reads= are the distinct cells this function OR its transitive callees write / read;

direct_writes= direct_reads= are the subsets in its own body. A cell is a file/namespace-scope variable, a function-local static, or a Python module global; a const/constexpr/consteval declaration is not a cell. Each cell child names its declaration, its direction (dir=r|w|rw) and either the use site in this body (at=) or the callee it came through (via=). Lineage: Fowler's Global Data / Mutable Data smells (2018) name the hazard and ship no metric; Marinescu's ATFD (ICSM 2004) is the closest number but is one-hop, per-class, Java, and direction-blind; QMOOD DAM and MOOD AHF/MHF count DECLARED VISIBILITY and so score a class with private fields and leaked mutable internals as perfectly encapsulated; the only published measurement of externally reachable state (Potanin/Noble/Biddle 2004) is DYNAMIC, Java-only, and its tool is unmaintained. UNSOUND BY CONSTRUCTION -- it cannot see indirect calls, pointer aliasing, macro-named cells or reflection-like dispatch, and a local SHADOWING a cell name can be charged to the cell -- so every count is a FLOOR (counts_floor="1") and the blind spots are listed in the report's own legend. COVERS C++, ObjC and Python -- the languages whose read/write USE SITES the index carries. Every other indexed language is named on the root as unanalyzed_langs= and contributes no cells and no rows: that absence is NOT a measured zero. Pages with limit=N (offset=M); default 40 rows.

**Try it**

_Per function, the non-local MUTABLE state it can reach (transitively), most writes first — unsound by construction, and the legend says where._

```
$ ./build/ripwire . --nonlocal-state --limit=8
<!-- ripwire nonlocal-state schema=ripwire.nonlocal-state/v1: per function, the non-local MUTABLE state it reaches: <fn p= n= writes= reads=> over <cell n= p= dir= via=> rows. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). cells_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. cells=N: mutable non-local cells found in the corpus (globals, statics, Python module globals; FLOOR). functions=N: functions reaching at least one cell, directly or via callees (all rows, before paging). direct_writes=/direct_reads=: the writes=/reads= cells this function's OWN body writes/reads. cells_total=N: distinct cells reached (read and written counts once); at most 12 cell rows print. at=/at_dir=: one own-body use site (may be more) and what own-body sites do (can be narrower than dir=). cells_shown=/cells_capped=1: only this many of cells_total= cell rows print (cap 12). unanalyzed_langs=/unanalyzed_files=: indexed languages (and their files) this lens skips; NOT zero cells. -->
<nonlocal_state schema="ripwire.nonlocal-state/v1" cells="933" functions="744" shown="8" capped="1" total="744" has_more="1" next_offset="8" offset="0" limit="8" graph_ambiguous="12495" graph_unresolved="12552" graph_unindexed="255" counts_floor="1" unanalyzed_langs="c,go,rust,javascript,typescript, … [line truncated: 98 more bytes on this line]
<fn p="bench/bench_svector_wave.cpp:346" n="main" writes="8" reads="14" direct_writes="0" direct_reads="4" cells_total="14" cells_shown="12" cells_capped="1">
<cell n="kNames" p="bench/bench_svector_wave.cpp:98" dir="rw" at="bench/bench_svector_wave.cpp:358" at_dir="r"/>
<cell n="kPush" p="bench/bench_svector_wave.cpp:99" dir="rw" at="bench/bench_svector_wave.cpp:358" at_dir="r"/>
<cell n="kReads" p="bench/bench_svector_wave.cpp:100" dir="rw" at="bench/bench_svector_wave.cpp:358" at_dir="r"/>
<cell n="kSamples" p="bench/bench_svector_wave.cpp:101" dir="rw" at="bench/bench_svector_wave.cpp:358" at_dir="r"/>
<cell n="g_api" p="src/infra/profilePmc.h:140" dir="rw" via="ensure_thread_counting"/>
<cell n="g_keyOf" p="bench/bench_svector_wave.cpp:145" dir="rw" via="regenerate"/>
<cell n="g_perf" p="src/infra/profilePmc.h:289" dir="rw" via="ensure_thread_counting"/>
<cell n="g_readOf" p="bench/bench_svector_wave.cpp:146" dir="rw" via="regenerate"/>
<cell n="g_arm" p="bench/bench_svector_wave.cpp:65" dir="r" via="runArm"/>
<cell n="g_bytes" p="bench/bench_svector_wave.cpp:67" dir="r" via="runArm"/>
<cell n="g_count" p="bench/bench_svector_wave.cpp:66" dir="r" via="runArm"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--limit`

**Caveats (stated by the binary):**

- a const/constexpr/consteval declaration is not a cell.
- UNSOUND BY CONSTRUCTION -- it cannot see indirect calls, pointer aliasing, macro-named cells or reflection-like dispatch, and a local SHADOWING a cell name can be charged to the cell -- so every count is a FLOOR (counts_floor="1") and the blind spots are listed in the report's own legend.
- Every other indexed language is named on the root as unanalyzed_langs= and contributes no cells and no rows: that absence is NOT a measured zero.

### `--ensemble`

**Answers:** join four independent evidence families per function, ranked by how many agree the FAMILY JOIN: per function, which of FOUR orthogonal evidence families fire, ranked by the COUNT of distinct families

**Try it**

_The family join: per function, which of four orthogonal evidence families fire, ranked by how many agree._

```
$ ./build/ripwire . --ensemble --limit=8
<!-- ripwire ensemble schema=ripwire.ensemble/v1: four orthogonal evidence families joined, ranked by DISTINCT families fired (no composite score): <s p= n= fam= of= fired=>. window: total= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). syms_capped=/files_capped=: 1 = cut. at=: commit+dirty+shallow. root=: p= relative to it. eligible=N: functions and methods with a body, the denominator; ranked + no_family = eligible. no_family=N: eligible symbols where no family fired. bar_ccx=/bar_loc=/bar_nest=/bar_params=: absolute structural bars: cognitive cx, lines, nesting, params. rcut=N: ranks the worst readability decile covers (1 to 40); rrank= inside it fires structural. rmeasured=N: functions the readability lens measured. hcut=N: file ranks the worst churn decile covers (1 to 40); hrank= inside it fires historical. hranked=N: files with any in-window commit; 0 = historical family unavailable. cfiles=N: indexed files the confusion (atom) pack can read: C/C++/ObjC/CUDA. cscope=N: eligible symbols in those files; 0 = confusion family unavailable. lscope=N: eligible symbols in a language the naming pack reads; 0 = lexical family unavailable. shown_syms=N: symbol rows printed; the rest page with offset=next_offset. shown_files=N: file rows printed (fixed cap 20, not paged); files_capped=1 = rows dropped. e f=: the fired family: structural, lexical, confusion or historical. why=: the measurements that crossed, space separated; rule*N = that rule fired N times. top=: the file's most corroborated symbol (most families on one symbol). top_l=: that symbol's line. top_fam=N: families fired on top=, the stronger claim; file rows rank by it. union_fam=N: distinct families firing anywhere in the file (weaker: may be different symbols). union=: the names of those families. syms=N: symbols in the file where at least one family fired. families=N: evidence families joined; ranked=N: symbols at least one fired on; window=: the git span the historical family read. -->
<ensemble schema="ripwire.ensemble/v1" families="4" eligible="14065" ranked="5514" no_family="8551" bar_ccx="15" bar_loc="60" bar_nest="4" bar_params="5" rcut="40" rmeasured="14065" hcut="40" hranked="2688" window="12mo" cfiles="653" cscope="7406" lscope="14065" shown_syms="8" syms_capped="1" shown_ … [line truncated: 115 more bytes on this line]
<s p="src/gitmine.h:1206" n="addRootFilesToGitPathIndex" fam="4" of="4" fired="structural,lexical,confusion,historical">
<e f="structural" why="ccx=25 ev=6"/>
<e f="lexical" why="naming-wordy"/>
<e f="confusion" why="atom-embedded-crement*2"/>
<e f="historical" why="hrank=39 churn=60"/>
</s>
<s p="src/serialize.h:8693" n="packDeps" fam="4" of="4" fired="structural,lexical,confusion,historical">
<e f="structural" why="ccx=120 loc=294 nest=5 params=16 humps=4 deep=14 ev=5 rrank=22"/>
<e f="lexical" why="naming-confusable"/>
<e f="confusion" why="atom-nested-ternary*2"/>
<e f="historical" why="hrank=10 churn=293"/>
</s>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--limit`

### `--quality-panel[=PRESET]`

**Answers:** the whole quality panel in ONE ranked report: which of six evidence families fire THE SINGLE COMMAND: the whole quality panel in ONE ranked report.

Per function, which of SIX evidence families fire -- structural (shape), lexical (identifier text), confusion (syntactic construct), historical (git churn), colocation (what you must read from outside this file), state (this function's OWN BODY touching non-local mutable state) -- ranked by the COUNT of distinct families, NEVER by a weighted composite, each row carrying its own evidence. PRESET selects and cuts, never weights: strict (the four families measured steady enough to gate on, 2 must agree) | default (all six, 2; the bare form) | lenient (all six, 1 -- a reading order, not a verdict). historical and colocation are out of strict: each is a fixed-size worst-40 cut over a ranking whose population moves, so both re-shuffle on code that did not change (docs/EVALS.md section 9.9). A family that could not be measured here is UNAVAILABLE, never 'did not fire', and of= drops with it. A lens: exit 0. Pages limit=N (offset=M). WHY NO COMPOSITE, in full (the emitted legend is deliberately terse and points here): averaging correlated metrics re-weights one signal and calls it six, and a single quotable number is wrong the moment it is quoted -- fam= is ORDINAL, and every row carries its own evidence so a reader can see WHY without a second command. The families are partitioned by KIND of evidence so that corroboration means the lenses failed DIFFERENTLY, not that one weakness echoed six times: the first four are the ensemble join, called through its own entry point and unchanged; colocation and state passed the same orthogonality test on the same corpora before being enabled. Every threshold is REUSED from the lens it came from, none is new: four absolute structural bars (cognitive complexity, lines, nesting, params), and three rankings with no defensible absolute cut, each firing for the worst decile of its OWN ranking (at least one row, at most that lens's default window of 40) -- an ordinal cut is RELATIVE, 'worst in THIS corpus', never 'bad in absolute terms'. The state family fires on the presence of a direct access site and deliberately uses the OWN-BODY half of the lens, not the callee closure: the panel's unit is one function's own comprehensibility, and the closure is a fact about its callees. UNAVAILABLE is never silent: an empty unavailable= means every family was measured, an empty ranking or empty language coverage counts as NOT measured, and the coverage denominators behind each verdict are published so it can be checked instead of trusted. The join=deep+untested annotation puts two facts already in the report side by side (sustained depth, no reaching test) because that pair is where a refactor is most wanted and least safe; counting it would be one family wearing a second hat.

**Try it**

_THE single wide-angle quality read: six families in one pass, an eligible/ranked shortlist rather than a firehose._

```
$ ./build/ripwire . --quality-panel
<!-- ripwire quality-panel schema=ripwire.quality-panel/v1: every quality family in ONE report, ranked by distinct families fired: <s p= n= fam= of= fired= join=>; bar_*= thresholds. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). at=: commit+dirty+shallow. root=: p= relative to it. preset=: strict (5 stable families, cut 2), default (6, cut 2), lenient (6, cut 1); selects, never weights. families=6: evidence families: structural lexical confusion historical colocation state. enabled=/enabled_n=: the families this preset COUNTS, and how many. cut=N: distinct enabled families that must fire for a row to rank. cut_reachable=0: cut= exceeds the evaluable families (of=); a corpus fact, never a clean bill of health. eligible=N: functions/methods with a body; ranked= + below_cut= + no_family= = eligible=, always. ranked=N: rows that met the cut (total=); only shown= print, page with offset=. below_cut=N: fired at least one enabled family, but fewer than cut=. no_family=N: no enabled family fired; unavailable= families were never measured. bar_ccx=/bar_loc=/bar_nest=/bar_params=: absolute bars: cognitive complexity, lines, nesting, params. rcut=/rmeasured=: readability decile width (rrank= under it fires) / functions measured. hcut=/hranked=: file churn decile width / files with an in-window commit (hranked=0 voids historical). window=: the git churn window hrank= and churn= are counted over (RELATIVE to this corpus). ccut=/cranked=: colocation decile width / functions reading any outside definition (0 voids it). cfiles=/cscope=: files the confusion atom rules read / eligible symbols in them. lscope=N: symbols the lexical naming rules read. sfiles=/sscope=: files the state lens reads / symbols in them. cells=N: non-local mutable cells the state lens found. tested_scope=N: symbols an indexed test reaches; at 0 no row can carry join=deep+untested. deep_untested=N: rows carrying join=deep+untested across the WHOLE set, not just this page. e f=: the fired family this evidence row belongs to. counted=1: this preset counts the family toward fam=; 0 = fired, not counted. why=: the measurements that crossed (rule*N fired N times; hrank=/churn= are the file's, inherited). -->
<quality_panel schema="ripwire.quality-panel/v1" preset="default" families="6" enabled="structural,lexical,confusion,historical,colocation,state" enabled_n="6" cut="2" cut_reachable="1" eligible="14065" ranked="823" below_cut="5017" no_family="8225" bar_ccx="15" bar_loc="60" bar_nest="4" bar_params= … [line truncated: 326 more bytes on this line]
<s p="src/gitmine.h:1206" n="addRootFilesToGitPathIndex" fam="4" of="6" fired="structural,lexical,confusion,historical">
<e f="structural" counted="1" why="ccx=25 ev=6"/>
<e f="lexical" counted="1" why="naming-wordy"/>
<e f="confusion" counted="1" why="atom-embedded-crement*2"/>
<e f="historical" counted="1" why="hrank=39 churn=60"/>
</s>
<s p="src/graph.h:5516" n="buildGraph" fam="4" of="6" fired="structural,confusion,historical,colocation">
<e f="structural" counted="1" why="ccx=1208 loc=2359 nest=8 humps=65 deep=466 ev=163 rrank=0"/>
<e f="confusion" counted="1" why="atom-embedded-crement*5 atom-nested-ternary*2"/>
<e f="historical" counted="1" why="hrank=11 churn=287"/>
<e f="colocation" counted="1" why="crank=19"/>
</s>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--limit`

**Caveats (stated by the binary):**

- PRESET selects and cuts, never weights: strict (the four families measured steady enough to gate on, 2 must agree) | default (all six, 2;
- the bare form) | lenient (all six, 1 -- a reading order, not a verdict).
- A family that could not be measured here is UNAVAILABLE, never 'did not fire', and of= drops with it.

### `--context-ratio`

**Answers:** per symbol, how much you must know that is NOT in front of you the LOCAL-REASONING lens: to understand this symbol, how much must you know that is NOT in front of you? Per symbol (and rolled up per file) the distinct in-corpus definitions and files its reference sites resolve to, and the share of them defined OUTSIDE its own file — as an edge count (ent_ratio=) and, weighted by the tokens a reader must actually read, as read_ratio=.

ATTRIBUTION: the fraction itself is published — it is Beck and Diehl's per-class congruence (FSE 2011) flipped, with Martin's instability Ce/(Ca+Ce) as its crude ancestor. What is refined here is the READER WEIGHTING and the use of EVERY reference role (call, read, write, import, base class, member type), not calls alone. Resolution is NAME-BASED and language-gated, the same heuristic level the uses verb works at; a name with several definitions contributes each of them up to defs_per_name_cap= and amb= counts it. Names with no in-corpus definition land in ext=, which locals and parameters DOMINATE, so ext= is not a dependency count and is excluded from both ratios. ents=/files= are FLOORS. Pages with limit=N (offset=M); default 40 symbol rows and 40 file rows. An ORDERING, never a grade and never a threshold.

**Try it**

_The local-reasoning lens: to understand this symbol, how much must you know that is NOT in front of you (ent_ratio= edge share, read_ratio= token-weighted)._

```
$ ./build/ripwire . --context-ratio --limit=8
<!-- ripwire context-ratio schema=ripwire.context-ratio/v1: LOCAL-REASONING lens: the share of a unit's context outside its file: <s p= n= sites= ents_out= ent_ratio= read_ratio=>. window: total= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). syms_capped=/files_capped=/defs_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. root=: p= relative to it. units=N: symbols measured (the s row population). file_units=N: files measured (the f row population). defs_per_name_cap=N: most defs one name adds (lowest ids); defs_capped=1 = cut, ents=/rtok= floors. body_bytes_per_token=: the bytes-per-token rate rtok= is estimated at. shown_syms=N: symbol rows printed; the rest page with offset=next_offset. shown_files=N: file rows printed (fixed cap 40, not paged); files_capped=1 = rows dropped. ents=N: distinct in-corpus defs its reference sites resolve to, by name (a FLOOR). files=N: distinct files holding those defs (a FLOOR). files_out=N: of files=, those other than the unit's own file. rtok=N: est. tokens of every resolved def, what a reader must read. rtok_out=N: the part of rtok= defined outside the unit's own file. ext=N: referenced names with no in-corpus def; mostly locals/params, NOT external deps; in neither ratio. amb_names=N: referenced names with 2+ defs, each counted (per name; not the map's per-call amb=). ents=N: distinct in-corpus defs the file's sites resolve to (a FLOOR; a union, not the sum of s rows). files=N: distinct files holding those defs (a FLOOR). files_out=N: of files=, those other than this file. rtok=N: est. tokens of every resolved def, what a reader must read. rtok_out=N: the part of rtok= defined outside this file. ext=N: referenced names with no in-corpus def; mostly locals/params, NOT external deps; in neither ratio. amb_names=N: referenced names with 2+ defs, each counted (per name; not the map's per-call amb=). -->
<contextratio schema="ripwire.context-ratio/v1" units="20636" file_units="2282" defs_per_name_cap="8" body_bytes_per_token="3.80" shown_syms="8" syms_capped="1" shown_files="40" files_capped="1" total="20636" has_more="1" next_offset="8" offset="0" limit="8" defs_capped="1" counts_floor="1" root="." … [line truncated: 1 more bytes on this line]
<s p="src/main.cpp:4132" n="dispatchMain" t="fn" sites="1152" ents="204" ents_out="181" ent_ratio="0.887" files="61" files_out="60" rtok="241005" rtok_out="205447" read_ratio="0.852" ext="132" amb_names="24"/>
<s p="src/main.cpp:1632" n="runDefaultMap" t="fn" sites="1083" ents="125" ents_out="115" ent_ratio="0.920" files="36" files_out="35" rtok="82993" rtok_out="78686" read_ratio="0.948" ext="145" amb_names="15"/>
<s p="src/mcp.h:1118" n="dispatchMcpLine" t="fn" sites="1355" ents="208" ents_out="182" ent_ratio="0.875" files="40" files_out="39" rtok="81444" rtok_out="76337" read_ratio="0.937" ext="167" amb_names="18"/>
<s p="src/mcpverbs.h:4095" n="computeQualityDelta" t="fn" sites="66" ents="42" ents_out="38" ent_ratio="0.905" files="15" files_out="14" rtok="63812" rtok_out="62941" read_ratio="0.986" ext="7" amb_names="8"/>
<s p="src/mcpverbs.h:4521" n="editCheckText" t="fn" sites="46" ents="37" ents_out="37" ent_ratio="1.000" files="19" files_out="19" rtok="54076" rtok_out="54076" read_ratio="1.000" ext="6" amb_names="7"/>
<s p="src/editpreview.h:338" n="run" t="fn" sites="142" ents="59" ents_out="55" ent_ratio="0.932" files="26" files_out="25" rtok="51908" rtok_out="49705" read_ratio="0.958" ext="36" amb_names="8"/>
... [23 more line(s); run it to see the whole thing]
```

**Shaped by:** `--limit`

**Caveats (stated by the binary):**

- Resolution is NAME-BASED and language-gated, the same heuristic level the uses verb works at;
- Names with no in-corpus definition land in ext=, which locals and parameters DOMINATE, so ext= is not a dependency count and is excluded from both ratios.
- Pages with limit=N (offset=M);

### `--naming-calibration`

**Answers:** score the naming-* lint rules against this repo's OWN rename history score the naming-* lint rules against this repo's OWN rename history: one git log pass mines old->new identifier substitutions, joins each to the symbol it became at HEAD, and scores BOTH spellings with the same predicates --lint runs.

old=fires on the abandoned spelling, new=fires on the chosen one, proxy=old/(old+new), where 0.50 is exactly chance. A NOISY PROXY, stated as one -- rebrands, moves and API changes all look like renames -- so read pairs= (the sample size) first; the group rules report scope=group-rule, not a fake 0/0. Exit 0 always: the per-rule floor lives in test/namingcalibrationcheck.sh

**Try it**

_Score the naming-* rules against this repo's own rename history: proxy=old/(old+new) per rule, 0.50 = chance; read pairs= (sample size) first._

```
$ ./build/ripwire . --naming-calibration
<!-- ripwire naming-calibration schema=ripwire.naming-calibration/v1: naming lint rules scored against this repo's OWN rename history (a noisy proxy): <r n= old= new= fired= proxy=>. at=: commit+dirty+shallow. probed=0: no history to mine, nothing scored (r= says why); 1 = the git walk ran. pairs=N: labelled rename pairs that survived the join, the SAMPLE SIZE; a small one means nothing. candidates=N: raw substitutions mined from the patch stream before the join; FLOOR when truncated=1. commits=N: non-merge commits walked (the walk stops at 40000). hunks=N: diff hunks with content on both sides. wide_hunks=N: hunks DROPPED for exceeding the 24-line per-side pairing cap; never mined. drop_old_alive=N: candidates dropped: the old spelling is still an indexed name. drop_new_absent=N: candidates dropped: the new spelling is no eligible indexed symbol at HEAD. drop_ambiguous=N: candidates dropped: a name on both sides of several (split, rework, revert). drop_old_skipped=N: candidates dropped: the lens skips the old spelling, no rule could fire. scope=group-rule: the rule judges co-visible names, which one pair cannot evidence; unscored, not 0/0. o=/n=: one labelled pair's old (abandoned) and new (chosen) spelling. sup=N: distinct hunks that showed this substitution. p at=: path:line of the symbol the pair joined to, not a commit (the root at= is). old_fires=: rules that fired on the old spelling; absent when none. new_fires=: rules that fired on the new spelling; absent when none. -->
<naming-calibration schema="ripwire.naming-calibration/v1" probed="1" pairs="150" candidates="1796" commits="3792" hunks="79759" wide_hunks="892" drop_old_alive="396" drop_new_absent="1171" drop_ambiguous="79" drop_old_skipped="0" at="f1e5c2e76">
<r n="naming-short" old="2" new="1" fired="3" proxy="0.667"/>
<r n="naming-wordy" old="1" new="2" fired="3" proxy="0.333"/>
<r n="naming-series" scope="group-rule"/>
<r n="naming-underscore" old="0" new="0" fired="0"/>
<r n="naming-case" old="0" new="0" fired="0"/>
<r n="naming-predicate" old="1" new="0" fired="1" proxy="1.000"/>
<r n="naming-setter" old="0" new="0" fired="0"/>
<r n="naming-confusable" scope="group-rule"/>
<!-- 4 rename rows withheld: the project's own rebrand, which names a private pre-release identifier -->
<p o="ATTR" n="ATTR_RE" sup="1" at="./bench/recalleval/run_recalleval.py:84"/>
<p o="DEGRADED_PATH_ALERT" n="DISCLOSE" sup="405" at="./test/showcase_coverage_check.py:154"/>
<p o="ELOOP" n="err" sup="1" at="./test/sliceflowcheck.sh:242"/>
... [14 more line(s); run it to see the whole thing]
```

**Caveats (stated by the binary):**

- A NOISY PROXY, stated as one -- rebrands, moves and API changes all look like renames -- so read pairs= (the sample size) first;
- the group rules report scope=group-rule, not a fake 0/0.
- Exit 0 always: the per-rule floor lives in test/namingcalibrationcheck.sh

### `--naming-consistency`

**Answers:** normalize to the corpus's own case convention, voted per language and kind TIER A convention normalization (section 9.2): the corpus's OWN case-convention vote per (language, kind) group among multi-token eligible names -- a single-token name, or one split only on digit boundaries, carries no case signal and is silently excluded.

A group DECIDES only when its leading style (camel/pascal/snake/screaming) clears a 20-name sample floor AND a 90% agreement floor; short of either it reports style=UNAVAILABLE with why= naming which bar it missed, never a guessed winner. Every off-convention name in a DECIDED group (including mixed -- naming-case's own finding, a separator AND a transition in one name, which never wins a vote) gets propose=: its OWN subtokens mechanically recombined into the dominant style -- no dictionary, no synonym judgment, which is what keeps this derivable from the corpus rather than invented. propose= is a SUGGESTION, never a safe-to-blind-apply rename -- an actual rename needs --uses to prove the complete reference set first. Exit 0 always: a lens, not a gate. Pages limit=N (offset=M); default 40 rows

**Try it**

_The corpus's OWN case-convention vote per (language, kind) group; off-convention names get a mechanical propose= (a suggestion, never a blind rename)._

```
$ ./build/ripwire . --naming-consistency --limit=8
<!-- ripwire naming-consistency schema=ripwire.naming-consistency/v1: the corpus's case-convention vote per (language, kind): <g lang= kind= style= agree= total=>, <f p= n= propose=> outliers. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). root=: p= relative to it. component_exempt=N: PascalCase .tsx/.jsx functions (read as JSX components by extension alone), kept out of voting and flagging. groups=N: (language, kind) groups with at least one styled name. candidates=N: multi-token styled names scanned. decided=N: groups whose leading style cleared both the sample and agreement floors. flagged=N: off-convention names in decided groups (the f rows). g why=insufficient-sample|no-clear-convention: which bar a style=UNAVAILABLE group missed. -->
<naming-consistency schema="ripwire.naming-consistency/v1" groups="32" candidates="10788" decided="11" flagged="468" component_exempt="8" shown="8" capped="1" total="468" has_more="1" next_offset="8" offset="0" limit="8" root=".">
<g lang="cpp" kind="fn" style="camel" agree="5522" total="5859"/>
<g lang="cpp" kind="var" style="camel" agree="1287" total="1299"/>
<g lang="py" kind="fn" style="snake" agree="799" total="822"/>
<g lang="py" kind="var" style="UNAVAILABLE" why="no-clear-convention" total="480"/>
<g lang="ts" kind="fn" style="camel" agree="103" total="105"/>
<g lang="ts" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="5"/>
<g lang="go" kind="fn" style="UNAVAILABLE" why="no-clear-convention" total="36"/>
<g lang="go" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="2"/>
<g lang="rs" kind="fn" style="UNAVAILABLE" why="no-clear-convention" total="57"/>
<g lang="rs" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="4"/>
<g lang="swift" kind="fn" style="UNAVAILABLE" why="no-clear-convention" total="46"/>
<g lang="swift" kind="var" style="UNAVAILABLE" why="insufficient-sample" total="17"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--limit`

**Caveats (stated by the binary):**

- A group DECIDES only when its leading style (camel/pascal/snake/screaming) clears a 20-name sample floor AND a 90% agreement floor;
- short of either it reports style=UNAVAILABLE with why= naming which bar it missed, never a guessed winner.
- propose= is a SUGGESTION, never a safe-to-blind-apply rename -- an actual rename needs --uses to prove the complete reference set first.

### `--naming-locals`

**Answers:** (with --lint) run the naming rules over local variables too;

off by default OPT-IN --lint MODIFIER (requires --lint; refused alone), OFF by default: local-variable-indexing plan Phase 2 (docs/LOCALS_INDEXING.md). Runs the naming-short/naming-wordy/naming-underscore/naming-case predicates (same tags, same rule bodies as the existing Symbol-scoped checks) against LOCAL variable names too, C/C++ only, but ONLY inside a function that already clears an EXISTING size/complexity gate (loc>80 OR nest>4 OR ccx>=15 -- the shipped large-function/deep-nesting thresholds) AND has locals>=8 (measured floor: median locals=9 among this repo's own 377 gated functions) -- never a whole-corpus local-name sweep. naming-short additionally requires the local's own declDepth>=2 (nested, not the function's own outermost block). Deliberately breaks the lens's stated invariant that an un-indexed local can never be flagged -- read the WITHDRAWN note atop src/naminglens.h before relying on this. NOT default-enabled inside a plain --lint run and not a candidate for it yet: the plan's own hard blocker (a hand-curated fixture corpus AND a manual real-corpus audit for idiomatic-short-name skew -- i/j/k/buf/tmp/ err) has not run. Exit 0 always; findings ride the same naming-* tallies/floors as --lint

**Try it**

_The opt-in --lint modifier: naming predicates over LOCAL variable names too, C/C++ only, only inside functions already past a size/complexity gate._

```
$ ./build/ripwire . --lint --naming-locals
<!-- ripwire lint schema=ripwire.lint/v1: AST-only checks, facts not gates: <rule name= count= shown_rows= rows_capped= count_capped=> of <f rule= p= in=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). findings_capped=/rows_capped=/count_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. root=: p= relative to it. findings=N: findings over the printed rules; a floor when findings_capped=1. findings_next=: the call counting the floored rules' rest (count_capped=1 rules only, 10x per-rule budget). -->
<lint schema="ripwire.lint/v1" findings="6592" shown="627" capped="1" total="6592" has_more="1" next_offset="627" offset="0" limit="0" counts_floor="1" findings_capped="1" findings_next="--lint --naming-locals --lint-select=magic-number --lint-max-per-rule=50000" naming_locals="1" root=".">
<rule name="c-style-cast" count="424" shown_rows="54" rows_capped="1"/>
<rule name="goto" count="15" shown_rows="1" rows_capped="1"/>
<rule name="do-while" count="15" shown_rows="0" rows_capped="1"/>
<rule name="unsafe-c-fn" count="0" shown_rows="0" rows_capped="0"/>
<rule name="weak-crypto" count="0" shown_rows="0" rows_capped="0"/>
<rule name="redundant-parens" count="0" shown_rows="0" rows_capped="0"/>
<rule name="suspicious-semicolon" count="0" shown_rows="0" rows_capped="0"/>
<rule name="typedef-over-using" count="21" shown_rows="0" rows_capped="1"/>
<rule name="magic-number" count="470" shown_rows="203" rows_capped="1" count_capped="1"/>
<rule name="empty-catch" count="1" shown_rows="0" rows_capped="1"/>
<rule name="self-assign" count="3" shown_rows="0" rows_capped="1"/>
<rule name="large-function" count="305" shown_rows="28" rows_capped="1"/>
... [17 more line(s); run it to see the whole thing]
```

**Caveats (stated by the binary):**

- refused alone), OFF by default: local-variable-indexing plan Phase 2 (docs/LOCALS_INDEXING.md).
- Deliberately breaks the lens's stated invariant that an un-indexed local can never be flagged -- read the WITHDRAWN note atop src/naminglens.h before relying on this.
- NOT default-enabled inside a plain --lint run and not a candidate for it yet: the plan's own hard blocker (a hand-curated fixture corpus AND a manual real-corpus audit for idiomatic-short-name skew -- i/j/k/buf/tmp/ err) has not run.

### `--comment-coherence`

**Answers:** rank doc comments most-name-restating first, by two published content measures per function/method WITH A DOC COMMENT, two published content measures, MOST NAME-RESTATING FIRST: c_coeff (Steidl/Hummel/Juergens, ICPC 2013) is the fraction of the comment's words within Levenshtein distance <2 of a word in the symbol's own (split) name — HIGH c_coeff IS BAD, it means the comment mostly repeats the name and adds no information (the opposite of the naive 'high coherence sounds good' reading).

cic (Scalabrino, ICPC 2016 / JSEP 2018) is the Jaccard overlap of two preprocessed term sets: the comment's vocabulary vs every identifier the definition's own span uses (operators/keywords stripped, camelCase/snake_case split, English stopwords dropped, deduplicated). The two measure different things and are expected to disagree — both are reported, never collapsed to one number. UNAVAILABLE (not scored, never a zero) where no doc comment exists, counted in no_comment= on the root. Complements --doc-drift (which checks whether a markdown CLAIM is stale) with comment CONTENT, over a disjoint input — neither verb duplicates the other. Pages with limit=N (offset=M); default 40 rows.

**Try it**

_Functions WITH a doc comment, most name-restating first: c_coeff (high = the comment repeats the name) and cic (Jaccard of comment vs identifier vocabulary), both reported, never collapsed._

```
$ ./build/ripwire . --comment-coherence --limit=8
<!-- ripwire comment-coherence schema=ripwire.comment-coherence/v1: two comment/name content measures per documented function, most name-restating first: <fn p= n= c_coeff= cic=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). root=: p= relative to it. documented=N: functions with a doc comment, measured (the rows); a FLOOR when unreadable_files= shows. no_comment=N: eligible symbols with no measurable comment; UNAVAILABLE, never scored as zero. words=/restate=: comment word count (c_coeff= denominator, stopwords kept) / words matching a name word. c_terms=/i_terms=/shared=: comment term set / identifiers the body uses / overlap; cic= shared over union. -->
<comment_coherence schema="ripwire.comment-coherence/v1" documented="4201" no_comment="9864" shown="8" capped="1" total="4201" has_more="1" next_offset="8" offset="0" limit="8" root=".">
<fn p="src/infra/os.h:446" n="socket" c_coeff="1.000" words="1" restate="1" cic="0.000" c_terms="1" i_terms="5" shared="0"/>
<fn p="src/lsp.h:473" n="lspLocationJson" c_coeff="1.000" words="1" restate="1" cic="0.000" c_terms="1" i_terms="26" shared="0"/>
<fn p="src/query.h:267" n="sourceAll" c_coeff="1.000" words="1" restate="1" cic="0.000" c_terms="1" i_terms="12" shared="0"/>
<fn p="src/verbs_quality.h:1816" n="runDmm" c_coeff="1.000" words="1" restate="1" cic="0.029" c_terms="1" i_terms="35" shared="1"/>
<fn p="src/infra/dynamic_map.hpp:1955" n="erase_rec" c_coeff="1.000" words="1" restate="1" cic="0.048" c_terms="1" i_terms="21" shared="1"/>
<fn p="test/verify_os_win32_logic.cpp:249" n="WidePath: separators, the Git Bash drive spelling, and nothing else rewritten" c_coeff="1.000" words="2" restate="2" cic="0.133" c_terms="2" i_terms="15" shared="2"/>
<fn p="test/verify_os_win32_logic.cpp:191" n="utf: every scalar value round-trips UTF-8 -&gt; UTF-16 -&gt; UTF-8 byte-exactly" c_coeff="1.000" words="5" restate="5" cic="0.150" c_terms="4" i_terms="19" shared="3"/>
<fn p="test/lintfix/bad.cpp:23" n="emptyCatchFunc" c_coeff="1.000" words="2" restate="2" cic="0.400" c_terms="2" i_terms="5" shared="2"/>
</comment_coherence>
```

**Shaped by:** `--limit`

**Caveats (stated by the binary):**

- The two measure different things and are expected to disagree — both are reported, never collapsed to one number.
- UNAVAILABLE (not scored, never a zero) where no doc comment exists, counted in no_comment= on the root.
- Pages with limit=N (offset=M);

### `--cochange[=FILE]`

**Answers:** files that change together in git (hidden coupling;

the rows' own legend defines surprising=) = Fowler's SHOTGUN SURGERY in its measurable, historical form: change coupling (Gall 1998, Zimmermann 2005). The static form — callers spread over many files (Lanza & Marinescu 2006) — was measured on two corpora and does NOT predict it, so it is not a flag (EVALS.md)

**Try it**

_Files that change together in git (hidden coupling)._

```
$ ./build/ripwire . --cochange
<!-- ripwire cochange schema=ripwire.cochange/v1: files that change together in git: <pair a= b= together= deg= conf_ab= conf_ba= surprising=>, or for of= <f p= together= conf_rev=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). at=: commit+dirty+shallow. root=: p= relative to it. pairs=N: file pairs with 3+ shared commits in window= (after min_recur), surprising or not. sub_windows=N: equal-commit-count slices of window=; the denominator of recur=. driver=a|b: the side whose changes best imply the other's, look there first; absent on a tie. recur=K: slices of sub_windows= the pair co-changed in; 1 = one burst, not a standing coupling. -->
<cochange schema="ripwire.cochange/v1" pairs="3722" window="18mo@HEAD" sub_windows="3" shown="30" capped="1" total="3722" has_more="1" next_offset="30" offset="0" limit="0" root="." at="f1e5c2e76">
<pair a="test/qsnapcachecheck.sh" b="test/qsnapprefetchcheck.sh" together="4" deg="1.00" conf_ab="1.00" conf_ba="0.67" driver="a" recur="2" surprising="1"/>
<pair a="src/layout.h" b="test/layoutfix/attrfields.h" together="4" deg="1.00" conf_ab="0.18" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
<pair a="test/headsnapcachecheck.sh" b="test/qsnapcachecheck.sh" together="4" deg="1.00" conf_ab="1.00" conf_ba="1.00" recur="2" surprising="1"/>
<pair a="test/headsnapcachecheck.sh" b="test/qsnapprefetchcheck.sh" together="4" deg="1.00" conf_ab="1.00" conf_ba="0.67" driver="a" recur="2" surprising="1"/>
<pair a="test/grepcheck.sh" b="test/grepscancheck.sh" together="3" deg="1.00" conf_ab="0.50" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="test/javamethodreffix/A.java" b="test/javamethodreffix/Widget.java" together="3" deg="1.00" conf_ab="0.75" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="test/cachesplitcheck.sh" b="test/evictioncheck.sh" together="3" deg="1.00" conf_ab="1.00" conf_ba="0.23" driver="a" recur="2" surprising="1"/>
<pair a="src/accessshape.h" b="test/accessshapefix/walks.cpp" together="3" deg="1.00" conf_ab="0.75" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
<pair a="src/fieldaffinity.h" b="test/accessshapefix/walks.cpp" together="3" deg="1.00" conf_ab="0.38" conf_ba="1.00" driver="b" recur="1" surprising="1"/>
... [22 more line(s); run it to see the whole thing]
```

**Shaped by:** `--cochange-recur`, `--cochange-groups`, `--since`, `--limit`

**Caveats (stated by the binary):**

- The static form — callers spread over many files (Lanza & Marinescu 2006) — was measured on two corpora and does NOT predict it, so it is not a flag (EVALS.md)

### `--cochange-recur=K`

**Answers:** (with --cochange) keep only pairs whose co-change recurs in K or more sub-windows (with --cochange) report only pairs whose co-change RECURS in K or more of the mined window's sub-windows, so a one-off refactor sprint stops reading like an eighteen-month structural defect (Clio, ICSE 2011).

Every row carries recur= with or without this flag; the header publishes sub_windows= (the denominator) and min_recur= when the filter is on

**Try it**

_Only pairs whose co-change RECURS in 2+ sub-windows of the mined window (sub_windows= is the denominator) — a one-off sprint stops reading like a structural defect._

```
$ ./build/ripwire . --cochange --cochange-recur=2
<!-- ripwire cochange schema=ripwire.cochange/v1: files that change together in git: <pair a= b= together= deg= conf_ab= conf_ba= surprising=>, or for of= <f p= together= conf_rev=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). at=: commit+dirty+shallow. root=: p= relative to it. pairs=N: file pairs with 3+ shared commits in window= (after min_recur), surprising or not. sub_windows=N: equal-commit-count slices of window=; the denominator of recur=. driver=a|b: the side whose changes best imply the other's, look there first; absent on a tie. recur=K: slices of sub_windows= the pair co-changed in; 1 = one burst, not a standing coupling. -->
<cochange schema="ripwire.cochange/v1" pairs="2832" window="18mo@HEAD" sub_windows="3" min_recur="2" shown="30" capped="1" total="2832" has_more="1" next_offset="30" offset="0" limit="0" root="." at="f1e5c2e76">
<pair a="test/headsnapcachecheck.sh" b="test/qsnapcachecheck.sh" together="4" deg="1.00" conf_ab="1.00" conf_ba="1.00" recur="2" surprising="1"/>
<pair a="test/headsnapcachecheck.sh" b="test/qsnapprefetchcheck.sh" together="4" deg="1.00" conf_ab="1.00" conf_ba="0.67" driver="a" recur="2" surprising="1"/>
<pair a="test/qsnapcachecheck.sh" b="test/qsnapprefetchcheck.sh" together="4" deg="1.00" conf_ab="1.00" conf_ba="0.67" driver="a" recur="2" surprising="1"/>
<pair a="test/javamethodreffix/A.java" b="test/javamethodreffix/Widget.java" together="3" deg="1.00" conf_ab="0.75" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="test/pincensuscheck.sh" b="test/scipjoincheck.sh" together="3" deg="1.00" conf_ab="0.38" conf_ba="1.00" driver="b" recur="3" surprising="1"/>
<pair a="test/grepcontextcheck.sh" b="test/grepscancheck.sh" together="3" deg="1.00" conf_ab="1.00" conf_ba="1.00" recur="2" surprising="1"/>
<pair a="test/grepcheck.sh" b="test/grepscancheck.sh" together="3" deg="1.00" conf_ab="0.50" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="test/grepcheck.sh" b="test/grepcontextcheck.sh" together="3" deg="1.00" conf_ab="0.50" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
<pair a="test/luacheck.sh" b="test/phpcheck.sh" together="3" deg="1.00" conf_ab="0.75" conf_ba="1.00" driver="b" recur="2" surprising="1"/>
... [22 more line(s); run it to see the whole thing]
```

### `--cochange-groups`

**Answers:** (with --cochange) report co-change GROUPS instead of pairs, naming the file to fix (with --cochange, repo-wide only) emit Modularity Violation GROUPS instead of pairs: "X co-changes with {A,B,C}, none of which it depends on" is ONE row that names the file to fix (Mo/Cai/Kazman, IEEE TSE 2019).

A greedy cover, disclosed as greedy — set cover is NP-hard, so the group count is an upper bound on the minimum, not the minimum

**Try it**

_Modularity-violation GROUPS instead of pairs: "X co-changes with {A,B,C}, none of which it depends on" — a greedy cover, disclosed as greedy._

```
$ ./build/ripwire . --cochange --cochange-groups
<!-- ripwire cochange schema=ripwire.cochange/v1: files that change together in git: <pair a= b= together= deg= conf_ab= conf_ba= surprising=>, or for of= <f p= together= conf_rev=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). at=: commit+dirty+shallow. root=: p= relative to it. sub_windows=N: equal-commit-count slices of window=; the denominator of recur=. recur=K: slices of sub_windows= the pair co-changed in; 1 = one burst, not a standing coupling. -->
<cochange schema="ripwire.cochange/v1" groups="115" pairs_covered="938" cover="greedy" window="18mo@HEAD" sub_windows="3" shown="30" capped="1" total="115" has_more="1" next_offset="30" offset="0" limit="0" root="." at="f1e5c2e76">
<group core="src/cli.h" partners="79">
<f p="src/abicheck.h" together="3" recur="3" conf_core="0.01"/>
<f p="src/arch.h" together="5" recur="3" conf_core="0.01"/>
<f p="src/callhierarchy.h" together="3" recur="1" conf_core="0.01"/>
<f p="src/clones.h" together="6" recur="2" conf_core="0.01"/>
<f p="src/codexdoctor.h" together="3" recur="2" conf_core="0.01"/>
<f p="src/commentcoherence.h" together="3" recur="2" conf_core="0.01"/>
<f p="src/compactlegend.h" together="72" recur="2" conf_core="0.16"/>
<f p="src/contextratio.h" together="4" recur="2" conf_core="0.01"/>
<f p="src/crossref.h" together="16" recur="3" conf_core="0.04"/>
<f p="src/darkflags.h" together="4" recur="3" conf_core="0.01"/>
<f p="src/didyoumean.h" together="3" recur="1" conf_core="0.01"/>
... [17 more line(s); run it to see the whole thing]
```

### `--since=REV|DATE`

**Answers:** limit the churn-based verbs to commits after this revision or date scope --hotspots/--cochange/--rank-by=churn|churn-decay to commits after this point: a revision (HEAD~20, a tag/sha — deterministic) or a git approxidate ("2 weeks ago" — wall-clock-relative).

e.g. --hotspots --since="1 week ago" ranks by RECENT churn (the regression lens). Absent ⇒ each verb's OWN bounded default window, NOT all history: --hotspots 12 months, --rank-by=churn 18 months, --cochange 18 months (--rank-by=churn-decay is the ONE exception: its default IS all history, because the 90-day half-life makes a cut-off unnecessary — it stamps that too). All of them STAMP the window they used AND the anchor that produced it: a DEFAULT window is measured back from HEAD's OWN committer date, never the wall clock, and says so (window="12mo@HEAD"/"18mo@HEAD"), so a pinned corpus, an archived release or a bisect checkout has its history INSIDE its own window — unanchored, a 2024 checkout read in 2026 reported no repository at all. A value you pass HERE is never re-anchored: it is stamped verbatim, so --since="18 months ago" is the wall-clock window on request. An UNRESOLVABLE value is refused by --hotspots (exit 1 — its window is part of the measurement) and degrades to the verb's own default window elsewhere BESIDE --slice=SYM:VAR it is not a window at all: it names the revision whose def-use slice of that variable this run is diffed against — see --slice

**Try it**

_Hotspots scoped to RECENT churn (the regression lens)._

```
$ ./build/ripwire . --hotspots --since="2 weeks ago"
<!-- ripwire hotspots schema=ripwire.hotspots/v1: maintenance pain = churn x ccx over window=: <f p= churn= ccx= score= top= top_ccx= top_l=>; unranked_*= no churn/complexity. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). at=: commit+dirty+shallow. root=: p= relative to it. files=/ranked=: files in the window / those with both churn and complexity; ranked + unranked_no_churn + unranked_no_complexity = files. unranked_no_churn=/unranked_no_complexity=: files left out for no commit in window= / no measured complexity. -->
<hotspots schema="ripwire.hotspots/v1" window="2 weeks ago" files="2688" ranked="263" unranked_no_churn="1965" unranked_no_complexity="460" shown="40" capped="1" total="263" has_more="1" next_offset="40" offset="0" limit="0" root="." at="f1e5c2e76">
<f p="src/graph.h" churn="92" ccx="3649" score="335708" top="buildGraph" top_ccx="1208" top_l="5516"/>
<f p="src/serialize.h" churn="74" ccx="2227" score="164798" top="serialize" top_ccx="265" top_l="2746"/>
<f p="src/quality.h" churn="84" ccx="1808" score="151872" top="computeDelta" top_ccx="324" top_l="8487"/>
<f p="src/mcpverbs.h" churn="82" ccx="1183" score="97006" top="runBatchSub" top_ccx="138" top_l="5419"/>
<f p="src/resolve.h" churn="35" ccx="1847" score="64645" top="buildPreciseIncludeAdjWithContext" top_ccx="84" top_l="4318"/>
<f p="src/cli.h" churn="81" ccx="643" score="52083" top="parseArgs" top_ccx="213" top_l="5218"/>
<f p="src/ingest_binds.h" churn="29" ccx="1661" score="48169" top="bindsVisitNode" top_ccx="85" top_l="5346"/>
<f p="src/main.cpp" churn="38" ccx="1189" score="45182" top="dispatchMain" top_ccx="473" top_l="4132"/>
<f p="src/verbs_navigate.h" churn="50" ccx="722" score="36100" top="runVerify" top_ccx="142" top_l="1702"/>
<f p="src/compactlegend.h" churn="102" ccx="313" score="31926" top="applyCompactDialectOnce" top_ccx="47" top_l="2091"/>
<f p="src/mcp.h" churn="33" ccx="927" score="30591" top="dispatchMcpLine" top_ccx="735" top_l="1118"/>
<f p="src/verbs_for.h" churn="38" ccx="744" score="28272" top="runForLensPass" top_ccx="360" top_l="2378"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--slice`

**Caveats (stated by the binary):**

- limit the churn-based verbs to commits after this revision or date scope --hotspots/--cochange/--rank-by=churn|churn-decay to commits after this point: a revision (HEAD~20, a tag/sha — deterministic) or a git approxidate ("2 weeks ago" — wall-clock-relative).
- Absent ⇒ each verb's OWN bounded default window, NOT all history: --hotspots 12 months, --rank-by=churn 18 months, --cochange 18 months (--rank-by=churn-decay is the ONE exception: its default IS all history, because the 90-day half-life makes a cut-off unnecessary — it stamps that too).
- A value you pass HERE is never re-anchored: it is stamped verbatim, so --since="18 months ago" is the wall-clock window on request.

### `--arch=FILE`

**Answers:** enforce layering rules from a rules file;

exit 2 on a violation enforce layering rules (exit 2 on violation); the Martin Ca/Ce/I/A/D block it emits is a design heuristic, not independently outcome-validated (never gates). propagation_cost's N is dependency-capable files only, same denominator as --deps <health>. Layer substrings and regex path-rules match the ROOT-RELATIVE path (src/core/x.cpp), not the spelling you passed, so a rules file means the same thing in every checkout

**Try it**

_Enforce layering rules (exit 2 on violation) — run against the repo's own test fixture rules._

```
$ ./build/ripwire . --arch=test/archfix/rules.txt
<!-- ripwire arch schema=ripwire.arch/v1: layering rules fit: allowed/denied file-to-file edges, each violation a row. -->
<arch schema="ripwire.arch/v1" layers="2" rules="1" pathRules="0" violations="0" baselined="0" new_violations="0">
<metrics modules="665" typed_modules="261" zone_pain="224" zone_useless="1" zone_ok="36" zone_na="404" propagation_cost="0.002" note="Martin Ca/Ce/I/A/D + zone (main-sequence heuristic, no independent outcome-based validation — folklore, not proof) + reachability — directory-level estimate from  … [line truncated: 410 more bytes on this line]
<m path="." ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./.codex-plugin" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./.github" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./.github/workflows" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench" ca="0" ce="1" types="20" abstract="2" I="1.00" A="0.10" D="0.10" zone="ok" reachable="1"/>
<m path="./bench/agentloop" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/agentloop/editsuite" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/agentloop/editsuite/fixture" ca="0" ce="0" types="1" abstract="0" I="0.00" A="0.00" D="1.00" zone="pain" reachable="1" isolated="1"/>
... [20 more line(s); run it to see the whole thing]
```

**Shaped by:** `--graph-query`, `--deps`

**Caveats (stated by the binary):**

- the Martin Ca/Ce/I/A/D block it emits is a design heuristic, not independently outcome-validated (never gates).

### `--arch=FILE --baseline`

**Answers:** write .ripwire_arch_baseline (accept current debt as baseline), exit 0

**Try it**

_Enforce layering rules (exit 2 on violation) — run against the repo's own test fixture rules._

```
$ ./build/ripwire . --arch=test/archfix/rules.txt
<!-- ripwire arch schema=ripwire.arch/v1: layering rules fit: allowed/denied file-to-file edges, each violation a row. -->
<arch schema="ripwire.arch/v1" layers="2" rules="1" pathRules="0" violations="0" baselined="0" new_violations="0">
<metrics modules="665" typed_modules="261" zone_pain="224" zone_useless="1" zone_ok="36" zone_na="404" propagation_cost="0.002" note="Martin Ca/Ce/I/A/D + zone (main-sequence heuristic, no independent outcome-based validation — folklore, not proof) + reachability — directory-level estimate from  … [line truncated: 410 more bytes on this line]
<m path="." ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./.codex-plugin" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./.github" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./.github/workflows" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench" ca="0" ce="1" types="20" abstract="2" I="1.00" A="0.10" D="0.10" zone="ok" reachable="1"/>
<m path="./bench/agentloop" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/agentloop/editsuite" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/agentloop/editsuite/fixture" ca="0" ce="0" types="1" abstract="0" I="0.00" A="0.00" D="1.00" zone="pain" reachable="1" isolated="1"/>
... [20 more line(s); run it to see the whole thing]
```

**Shaped by:** `--graph-query`, `--deps`

### `--arch=FILE --baseline-update`

**Answers:** merge current violations into baseline (accept new debt), exit 0

**Try it**

_Enforce layering rules (exit 2 on violation) — run against the repo's own test fixture rules._

```
$ ./build/ripwire . --arch=test/archfix/rules.txt
<!-- ripwire arch schema=ripwire.arch/v1: layering rules fit: allowed/denied file-to-file edges, each violation a row. -->
<arch schema="ripwire.arch/v1" layers="2" rules="1" pathRules="0" violations="0" baselined="0" new_violations="0">
<metrics modules="665" typed_modules="261" zone_pain="224" zone_useless="1" zone_ok="36" zone_na="404" propagation_cost="0.002" note="Martin Ca/Ce/I/A/D + zone (main-sequence heuristic, no independent outcome-based validation — folklore, not proof) + reachability — directory-level estimate from  … [line truncated: 410 more bytes on this line]
<m path="." ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./.codex-plugin" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./.github" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./.github/workflows" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench" ca="0" ce="1" types="20" abstract="2" I="1.00" A="0.10" D="0.10" zone="ok" reachable="1"/>
<m path="./bench/agentloop" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/agentloop/editsuite" ca="0" ce="0" types="0" abstract="0" I="0.00" A="0.00" D="1.00" zone="n/a" reachable="1" isolated="1"/>
<m path="./bench/agentloop/editsuite/fixture" ca="0" ce="0" types="1" abstract="0" I="0.00" A="0.00" D="1.00" zone="pain" reachable="1" isolated="1"/>
... [20 more line(s); run it to see the whole thing]
```

**Shaped by:** `--graph-query`, `--deps`

### `--lint`

**Answers:** run the built-in AST checks: c-cast, goto, unsafe-c-fn, naming-*, cache-* data-layout built-in AST checks (c-cast, goto, unsafe-c-fn, naming-*, cache-* data-layout, ...).

naming-uninformative is ONE-SIDED by design: it fires only when a name's subtokens are ALL corpus-common (BM25 idf over the identifier-name corpus) AND its body clears a size floor — a high-idf (distinctive) name is never penalised, unlike the withdrawn name<->body rule. Each <rule> row's applicability is per-LANGUAGE, not per-file-content: a rule whose registered languages (see --lint-catalog) intersect NONE of the corpus' languages carries applicable="0" (its count="0" is then structural inertness, not a measurement), and the root tallies inert_rules="N"; see --lint-catalog for the full registry

**Try it**

_Built-in AST checks (c-cast, goto, unsafe-c-fn, ...)._

```
$ ./build/ripwire . --lint
<!-- ripwire lint schema=ripwire.lint/v1: AST-only checks, facts not gates: <rule name= count= shown_rows= rows_capped= count_capped=> of <f rule= p= in=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). findings_capped=/rows_capped=/count_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. root=: p= relative to it. findings=N: findings over the printed rules; a floor when findings_capped=1. findings_next=: the call counting the floored rules' rest (count_capped=1 rules only, 10x per-rule budget). -->
<lint schema="ripwire.lint/v1" findings="5223" shown="685" capped="1" total="5223" has_more="1" next_offset="685" offset="0" limit="0" counts_floor="1" findings_capped="1" findings_next="--lint --lint-select=magic-number --lint-max-per-rule=50000" root=".">
<rule name="c-style-cast" count="424" shown_rows="103" rows_capped="1"/>
<rule name="goto" count="15" shown_rows="1" rows_capped="1"/>
<rule name="do-while" count="15" shown_rows="0" rows_capped="1"/>
<rule name="unsafe-c-fn" count="0" shown_rows="0" rows_capped="0"/>
<rule name="weak-crypto" count="0" shown_rows="0" rows_capped="0"/>
<rule name="redundant-parens" count="0" shown_rows="0" rows_capped="0"/>
<rule name="suspicious-semicolon" count="0" shown_rows="0" rows_capped="0"/>
<rule name="typedef-over-using" count="21" shown_rows="0" rows_capped="1"/>
<rule name="magic-number" count="470" shown_rows="293" rows_capped="1" count_capped="1"/>
<rule name="empty-catch" count="1" shown_rows="0" rows_capped="1"/>
<rule name="self-assign" count="3" shown_rows="0" rows_capped="1"/>
<rule name="large-function" count="305" shown_rows="42" rows_capped="1"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--affected`, `--expand`, `--naming-calibration`, `--naming-locals`, `--lint-catalog`, `--lint-rules`, `--lint-select`, `--lint-ignore`

**Caveats (stated by the binary):**

- naming-uninformative is ONE-SIDED by design: it fires only when a name's subtokens are ALL corpus-common (BM25 idf over the identifier-name corpus) AND its body clears a size floor — a high-idf (distinctive) name is never penalised, unlike the withdrawn name<->body rule.
- Each <rule> row's applicability is per-LANGUAGE, not per-file-content: a rule whose registered languages (see --lint-catalog) intersect NONE of the corpus' languages carries applicable="0" (its count="0" is then structural inertness, not a measurement), and the root tallies inert_rules="N";

### `--lint-catalog`

**Answers:** list the built-in rule registry, one row per rule — no corpus needed the built-in rule registry: one row per rule with sev=/category=/rationale/lang=/since= — no corpus needed.

Every built-in rule from every pack (base checks, atoms-*, cache-*, naming-*, the symbol-level checks) has exactly one row; lang= is the SAME token spelling --lint-rules' language: field accepts, so it round-trips into a user rule

**Try it**

_The built-in rule registry — one row per rule with sev=/category=/rationale/lang=/since=; no corpus needed._

```
$ ./build/ripwire . --lint-catalog
<!-- ripwire lint-catalog schema=ripwire.lint-catalog/v1: the built-in lint rule registry: <rule name= sev= cat= lang= since=>. rules=N: rules in the built-in registry, one rule row each, never cut. -->
<lintcatalog schema="ripwire.lint-catalog/v1" rules="39">
<rule name="c-style-cast" sev="warn" cat="style" lang="cpp,c,objc,java,cs" since="v0.1.0">a C-style cast — cppcoreguidelines-pro-type-cstyle-cast prefers the explicit static_cast/const_cast/reinterpret_cast</rule>
<rule name="goto" sev="warn" cat="control-flow" lang="cpp,c,objc,go,cs" since="v0.1.0">a goto statement — cppcoreguidelines-avoid-goto</rule>
<rule name="do-while" sev="info" cat="style" lang="cpp,c,objc,ts,js,swift,java,cs" since="v0.1.0">a do/while loop shape (on Swift, its do/catch block shares the same grammar node and also matches)</rule>
<rule name="unsafe-c-fn" sev="error" cat="security" lang="cpp,c,objc,ts,js,go,rs" since="v0.1.0">a call to an unbounded C string function (strcpy/strcat/sprintf/gets)</rule>
<rule name="weak-crypto" sev="error" cat="security" lang="cpp,c,objc,ts,js,go,rs" since="v0.1.0">a call to a broken hash or cipher (MD5/SHA1/MD4/RC4)</rule>
<rule name="redundant-parens" sev="info" cat="style" lang="cpp,c,objc,py,ts,js,go,rs,java,cs" since="v0.1.0">a doubly-parenthesized expression — readability-redundant-parentheses</rule>
<rule name="suspicious-semicolon" sev="warn" cat="correctness" lang="cpp,c,objc" since="v0.1.0">an if-body that is just `;` — bugprone-suspicious-semicolon</rule>
<rule name="typedef-over-using" sev="info" cat="style" lang="cpp,c,objc" since="v0.1.0">a C-style typedef struct/union where `using` is preferred</rule>
... [21 more line(s); run it to see the whole thing]
```

**Shaped by:** `--lint`

### `--lint-rules=DIR`

**Answers:** load user lint rules (YAML, ast-grep style) from DIR — runs with, or instead of, --lint

**Try it**

_User lint rules (YAML, ast-grep style) from a directory._

```
$ ./build/ripwire . --lint-rules=test/lintrulesfix/rules
<!-- ripwire lint schema=ripwire.lint/v1: AST-only checks, facts not gates: <rule name= count= shown_rows= rows_capped= count_capped=> of <f rule= p= in=>. window: shown= capped= (capped=1 cut). rows_capped=: 1 = cut. root=: p= relative to it. findings=N: findings over the printed rules; a floor when findings_capped=1. -->
<lint schema="ripwire.lint/v1" findings="5" shown="5" capped="0" root=".">
<rule name="broken-query" sev="error" count="0" shown_rows="0" rows_capped="0" compiled="0"/>
<rule name="no-printf" sev="warn" count="5" shown_rows="5" rows_capped="0"/>
<f rule="no-printf" sev="warn" p="test/coplintfix/position.cpp:41" in="demo">use LOG() instead of printf</f>
<f rule="no-printf" sev="warn" p="test/coplintfix/safe.cpp:15" in="safe_demo">use LOG() instead of printf</f>
<f rule="no-printf" sev="warn" p="test/coplintfix/safe.cpp:27" in="safe_demo">use LOG() instead of printf</f>
<f rule="no-printf" sev="warn" p="test/lintrulesfix/sample.cpp:8" in="greet">use LOG() instead of printf</f>
<f rule="no-printf" sev="warn" p="test/usesfix/store.cpp:24" in="run">use LOG() instead of printf</f>
</lint>
```

**Shaped by:** `--lint-catalog`, `--lint-select`, `--lint-ignore`, `--lint-max-per-rule`, `--sarif`

### `--lint-select=PREFIX[,...]`

**Answers:** (with --lint) run only the rules whose name starts with one of these prefixes (with --lint / --lint-rules) run ONLY rules whose name starts with one of these PREFIXes (or '*' for all) — comma-separated, e.g.

cache- selects the whole cache-* family. The root then carries selected="K of N" plus the raw select=/ignore= you passed, so a filtered zero is never confusable with an unfiltered one. An unresolvable PREFIX (matches no rule) refuses (exit 1), naming the nearest rule/family by edit distance

**Try it**

_An unresolvable PREFIX refuses (exit 1) with a did-you-mean from a real edit distance (one character off cache-)._

```
$ ./build/ripwire . --lint --lint-select=cach-
(empty)
```

**Shaped by:** `--lint-ignore`

**Caveats (stated by the binary):**

- The root then carries selected="K of N" plus the raw select=/ignore= you passed, so a filtered zero is never confusable with an unfiltered one.
- An unresolvable PREFIX (matches no rule) refuses (exit 1), naming the nearest rule/family by edit distance

### `--lint-ignore=PREFIX[,...]`

**Answers:** (with --lint) drop the rules whose name starts with one of these prefixes (with --lint / --lint-rules) DROP rules whose name starts with one of these PREFIXes (or '*' to drop everything, e.g.

paired with --lint-select elsewhere to isolate one family) — applied AFTER --lint-select narrows the set; same unresolvable-PREFIX refusal and root disclosure as --lint-select

**Try it**

_DROP two families, applied after selection; the raw select=/ignore= you passed rides on the root._

```
$ ./build/ripwire . --lint --lint-ignore=naming-,cache-
<!-- ripwire lint schema=ripwire.lint/v1: AST-only checks, facts not gates: <rule name= count= shown_rows= rows_capped= count_capped=> of <f rule= p= in=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). findings_capped=/rows_capped=/count_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. root=: p= relative to it. findings=N: findings over the printed rules; a floor when findings_capped=1. findings_next=: the call counting the floored rules' rest (count_capped=1 rules only, 10x per-rule budget). -->
<lint schema="ripwire.lint/v1" findings="2004" shown="732" capped="1" total="2004" has_more="1" next_offset="732" offset="0" limit="0" counts_floor="1" findings_capped="1" findings_next="--lint --lint-select=magic-number --lint-max-per-rule=50000" selected="22 of 39" ignore="naming-,cache-" root="." … [line truncated: 1 more bytes on this line]
<rule name="c-style-cast" count="424" shown_rows="115" rows_capped="1"/>
<rule name="goto" count="15" shown_rows="1" rows_capped="1"/>
<rule name="do-while" count="15" shown_rows="0" rows_capped="1"/>
<rule name="unsafe-c-fn" count="0" shown_rows="0" rows_capped="0"/>
<rule name="weak-crypto" count="0" shown_rows="0" rows_capped="0"/>
<rule name="redundant-parens" count="0" shown_rows="0" rows_capped="0"/>
<rule name="suspicious-semicolon" count="0" shown_rows="0" rows_capped="0"/>
<rule name="typedef-over-using" count="21" shown_rows="0" rows_capped="1"/>
<rule name="magic-number" count="470" shown_rows="436" rows_capped="1" count_capped="1"/>
<rule name="empty-catch" count="1" shown_rows="0" rows_capped="1"/>
<rule name="self-assign" count="3" shown_rows="0" rows_capped="1"/>
<rule name="large-function" count="305" shown_rows="59" rows_capped="1"/>
... [17 more line(s); run it to see the whole thing]
```

### `--lint-max-per-rule=N`

**Answers:** (with --lint / --lint-rules) set each rule's match budget, below or above the default 5000.

The default is a runaway guard, not a target. A rule that spends its budget carries count_capped="1" (its count= is a FLOOR) and the root names the call that counts the rest: findings_next= (SARIF: run properties findingsNext, --sarif kept) re-runs only the floored rules under a 10x budget; a re-run still floored names its own. Raising it costs time and memory in proportion to the matches kept

**Try it**

_A rule that spends its own match budget (here 4, set BELOW the default 5000 so the floor shows on this repo): goto carries count_capped="1", its count= is a FLOOR, and the root names the call that counts the rest — findings_next= re-runs only the floored rules under a 10x budget._

```
$ ./build/ripwire . --lint --lint-select=goto --lint-max-per-rule=4
<!-- ripwire lint schema=ripwire.lint/v1: AST-only checks, facts not gates: <rule name= count= shown_rows= rows_capped= count_capped=> of <f rule= p= in=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). findings_capped=/rows_capped=/count_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. root=: p= relative to it. findings=N: findings over the printed rules; a floor when findings_capped=1. findings_next=: the call counting the floored rules' rest (count_capped=1 rules only, 10x per-rule budget). -->
<lint schema="ripwire.lint/v1" findings="4" shown="4" capped="1" total="4" has_more="0" next_offset="4" offset="0" limit="0" counts_floor="1" findings_capped="1" findings_next="--lint --lint-select=goto --lint-max-per-rule=40" selected="1 of 39" select="goto" root=".">
<rule name="goto" count="4" shown_rows="4" rows_capped="0" count_capped="1"/>
<f rule="goto" p="src/clones.h:909" in="findClonesType3">goto done;</f>
<f rule="goto" p="src/infra/timsort.hpp:508" in="mergeLo">goto epilogue;</f>
<f rule="goto" p="src/infra/timsort.hpp:517" in="mergeLo">goto epilogue;</f>
<f rule="goto" p="src/infra/timsort.hpp:534" in="mergeLo">goto epilogue;</f>
</lint>
```

**Caveats (stated by the binary):**

- The default is a runaway guard, not a target.
- A rule that spends its budget carries count_capped="1" (its count= is a FLOOR) and the root names the call that counts the rest: findings_next= (SARIF: run properties findingsNext, --sarif kept) re-runs only the floored rules under a 10x budget;
- a re-run still floored names its own.

### `--sarif`

**Answers:** (with --lint / --lint-rules) the SAME findings as SARIF 2.1.0 instead of the native XML <lint> block — the shape github/codeql-action/upload-sarif consumes for code scanning.

Pure re-serialization (zero new analysis); results count == the native run's findings count. Levels: user severity error/warn/info -> SARIF error/warning/note; a built-in finding (a fact, never a gate) has no severity of its own and also maps to note. Fields with no SARIF home (per-rule capped= floor, enclosing symbol, raw sev=) ride in properties rather than being dropped; URIs are relative to the scanned root. Always the FULL result set — refuses loudly alongside limit=/offset= paging, --match and --with-profile

**Try it**

_The SAME findings as SARIF 2.1.0 (what github/codeql-action/upload-sarif consumes) — pure re-serialization, results count == the native run's._

```
$ ./build/ripwire . --lint --sarif
{"version":"2.1.0","$schema":"https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json","runs":[{"tool":{"driver":{"name":"ripwire","rules":[{"id":"c-style-cast","shortDescription":{"text":"c-style-cast"},"properties":{"builtin":true,"capped":false,"applicable": … [line truncated: 7 more bytes on this line]
{"id":"goto","shortDescription":{"text":"goto"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"do-while","shortDescription":{"text":"do-while"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"unsafe-c-fn","shortDescription":{"text":"unsafe-c-fn"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"weak-crypto","shortDescription":{"text":"weak-crypto"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"redundant-parens","shortDescription":{"text":"redundant-parens"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"suspicious-semicolon","shortDescription":{"text":"suspicious-semicolon"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"typedef-over-using","shortDescription":{"text":"typedef-over-using"},"properties":{"builtin":true,"capped":false,"applicable":true}},
{"id":"magic-number","shortDescription":{"text":"magic-number"},"properties":{"builtin":true,"capped":true,"applicable":true}},
{"id":"empty-catch","shortDescription":{"text":"empty-catch"},"properties":{"builtin":true,"capped":false,"applicable":true}},
... [21 more line(s); run it to see the whole thing]
```

**Shaped by:** `--lint-max-per-rule`, `--legend`

**Caveats (stated by the binary):**

- a built-in finding (a fact, never a gate) has no severity of its own and also maps to note.
- Fields with no SARIF home (per-rule capped= floor, enclosing symbol, raw sev=) ride in properties rather than being dropped;
- Always the FULL result set — refuses loudly alongside limit=/offset= paging, --match and --with-profile

### `--with-profile=FILE`

**Answers:** (with --lint) join measured runtime heat from a profile report onto the findings (with --lint) join MEASURED heat onto findings: FILE is a RIPWIRE_PROFILE build's report (its #PROF_TSV block);

a finding whose enclosing symbol contains a PROFILE_SCOPE site gains heat_* attributes (scope, calls, total_ms, and whichever counter columns the profiled run armed — l1d_mpki etc.). Static shape x measured weight; joins nothing silently — a missing file or a FILE with no #PROF_TSV block refuses loudly

**Try it**

_Join MEASURED heat onto --lint findings — runs in a tiny fabricated demo corpus (one cache-pointer-chase-loop finding under a PROFILE_SCOPE site) because a real report needs a RIPWIRE_PROFILE build; the finding inside the profiled scope gains heat_* columns from the report's #PROF_TSV row._

```
$ ./build/ripwire . --lint --with-profile=report.txt
#PROF_TSV_BEGIN	one row per scope, aggregated across threads; counters are RAW integers
scope	file	line	calls	total_ms	l1d_mpki
walk: chase pass	x.cpp	9	12	48.500	7.250
#PROF_TSV_END
```

**Shaped by:** `--sarif`

**Caveats (stated by the binary):**

- joins nothing silently — a missing file or a FILE with no #PROF_TSV block refuses loudly

### `--communities`

**Answers:** cluster the call graph into cohesive modules;

each row's id= drills down cluster the call graph into cohesive modules (each row's id= drills down below; drill= names the verb)

**Try it**

_Cluster the call graph into cohesive modules._

```
$ ./build/ripwire . --communities
<!-- ripwire communities schema=ripwire.communities/v1: call-graph modules (Louvain): <community id= size= dir= label=> of <member t= n= p=>; drill= the verb taking a row's id=; shown_modules=/shown_bridges= <community>/<bridge> rows listed; bridges= community pairs joined by a call edge; isolated= symbols with no call edge: isolated_doc= doc sections, isolated_decl= other bodyless, isolated_header= other header defs, isolated_source= the rest; modules= modules of 2+ symbols; connected_singletons= 1-symbol modules with a call edge; symbols= indexed symbols. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). modules_capped=/bridges_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. pr_iters=N: PageRank iterations. <bridge a= b=>: two module ids joined by call edges. from_label=/to_label=: the label= of a=/b=. <bridge edges=>: call edges between the two, either direction. -->
<communities schema="ripwire.communities/v1" drill="--community=ID" modules="2494" shown_modules="30" modules_capped="1" bridges="2689" shown_bridges="12" bridges_capped="1" isolated="11469" isolated_decl="3087" isolated_header="1678" isolated_source="2119" isolated_doc="4585" connected_singletons=" … [line truncated: 194 more bytes on this line]
<community id="4928" size="1685" dir="src" label="src::emitTo@infra/emit.h:53:2760 [write,run,emit]" shown="5" capped="1">
<member t="method" n="empty" p="src/resolve.h:1566"/>
<member t="method" n="empty" p="src/defectshape.h:566"/>
<member t="method" n="empty" p="src/notes.h:540"/>
<member t="method" n="empty" p="src/scipoverlay.h:106"/>
<member t="method" n="c_str" p="src/infra/os_win32_logic.h:484"/>
</community>
<community id="4941" size="1021" dir="src" label="src::append@elixir_resolve.h:111:4875 [add,resolve,compute]" shown="5" capped="1">
<member t="method" n="push_back" p="src/infra/svector.h:326"/>
<member t="method" n="reserve" p="src/mergescout.h:390"/>
<member t="method" n="clear" p="src/renamemine.h:250"/>
<member t="method" n="end" p="src/infra/svector.h:270"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--community`, `--limit`

### `--community=ID`

**Answers:** open one module from the partition: its members, and its bridges to other modules ONE module from that partition: its FULL ranked member list (40 rows by default, raise with --limit, page with --offset) plus its bridge edges to every other module it touches.

ID is an id= from --communities/--zoom; ids live in 0..partition-1 (the child's partition= — the full label space, isolated singletons included), so a single-member module is a legal drill-down and reports size="1". modules= counts the non-isolated communities (same number as the parent's modules=). An id outside 0..partition-1 REFUSES, naming the valid range and the nearest legal id -- a bad id is a typo, not an empty module

**Try it**

_Drill into ONE call-graph community by id — the drill= the --communities output itself advertises._

```
$ ./build/ripwire . --community=0
<!-- ripwire community schema=ripwire.community/v1: ONE module id=: <member t= n= p=> ranked members, its <bridge> edges; size= the TRUE count; dir= its members' most common directory (a top-level file's own path); label= dir::name@file:line:byte of its top fan-in member (non-accessors first) [up to 3 top name verbs]; bridges= modules a call edge joins to it; partition= module count incl. singletons (ids 0..partition-1); modules= those of 2+ symbols; shown_bridges= <bridge> rows listed. window: shown= capped= (capped=1 cut). bridges_capped=: 1 = cut. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. pr_iters=N: PageRank iterations. -->
<community schema="ripwire.community/v1" id="0" size="1" dir=".coderabbit.yaml" label=".coderabbit.yaml::reviews@.coderabbit.yaml:10:751" bridges="0" shown_bridges="0" bridges_capped="0" partition="13963" modules="2494" shown="1" capped="0" pr_iters="28" root="." graph_ambiguous="12495" graph_unreso … [line truncated: 52 more bytes on this line]
<member t="sec" n="reviews" p=".coderabbit.yaml:10"/>
</community>
```

**Shaped by:** `--limit`

**Caveats (stated by the binary):**

- open one module from the partition: its members, and its bridges to other modules ONE module from that partition: its FULL ranked member list (40 rows by default, raise with --limit, page with --offset) plus its bridge edges to every other module it touches.
- An id outside 0..partition-1 REFUSES, naming the valid range and the nearest legal id -- a bad id is a typo, not an empty module

### `--zoom[=depth]`

**Answers:** show the nested module hierarchy plus the bridges between modules NESTED module hierarchy (multi-level Louvain) + cross-module bridges;

--zoom --mermaid = nested diagram. Default window: the top 2 levels (levels_shown=; a module at the cut carries children= for its unprinted child modules; --zoom-levels=N prints N, 0 = all) over the 40 largest top modules (shown=/capped=/next_offset=, next= pastes the next page; --limit=N/--offset=M window them)

**Try it**

_Nested module hierarchy (multi-level Louvain) + cross-module bridges — levels_shown="2" of levels= BY DEFAULT over the 40 largest top modules (~8 KB, where the whole tree is ~220 KB); a module AT the cut carries children=._

```
$ ./build/ripwire . --zoom
<!-- ripwire zoom schema=ripwire.zoom/v1: nested module hierarchy: <module level= id= size= dir= shown= capped=> of <member t= n= p=>; levels_shown= of levels= printed; symbols= = isolated= + size= of all top_modules=. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. pr_iters=N: PageRank iterations. children=K: K child modules below the levels_shown= cut, unprinted. next=: the one pasteable follow-up. -->
<zoom schema="ripwire.zoom/v1" levels="4" levels_shown="2" top_modules="1062" symbols="25558" isolated="11469" shown="40" capped="1" total="1062" has_more="1" next_offset="40" offset="0" limit="0" pr_iters="28" graph_ambiguous="12495" graph_unresolved="12552" graph_unindexed="255" counts_floor="1" n … [line truncated: 25 more bytes on this line]
<module level="3" id="1557" size="6264" dir="./src">
<module level="2" id="1559" size="5875" dir="./src" children="68">
</module>
<module level="2" id="4642" size="197" dir="./test" children="10">
</module>
<module level="2" id="5494" size="74" dir="./src/infra" children="6">
</module>
<module level="2" id="5509" size="39" dir="./src/infra" children="3">
</module>
<module level="2" id="5617" size="22" dir="./src/infra" children="2">
</module>
<module level="2" id="5325" size="19" dir="./test/cppqualtmplfix" children="2">
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--community`, `--limit`

**Caveats (stated by the binary):**

- --zoom-levels=N prints N, 0 = all) over the 40 largest top modules (shown=/capped=/next_offset=, next= pastes the next page;
- --limit=N/--offset=M window them)

### `--report`

**Answers:** architecture summary (modules, god-files, cycles) as markdown

**Try it**

_Architecture summary (modules, god-files, cycles) as markdown._

```
$ ./build/ripwire . --report
<!-- ripwire markdown: no run of 4-or-more backticks in this output — safe to embed inside a wider fence -->

# ripwire architecture report

2688 files · 25558 symbols · 40392 edges · 2494 modules (11469 call-graph isolated)

Root: `.`

Call-graph isolate provenance: 3087 declaration, 1678 header, 2119 source, 4585 document; 0 connected Louvain singletons

## Modules (call-graph clusters; showing 12 of 2494)
- **src::emitTo@infra/emit.h:53:2760 [write,run,emit]** — 1685 symbols
- **src::append@elixir_resolve.h:111:4875 [add,resolve,compute]** — 1021 symbols
- **src::emplace@infra/svector.h:408:22477 [resolve,scan,find]** — 605 symbols
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--legend`, `--limit`

### `--seams`

**Answers:** cross-module call seams no test reaches (untested integration seams)

**Try it**

_Cross-module call seams no test reaches. NOW carries seam_pairs/shown/capped._

```
$ ./build/ripwire . --seams
<!-- ripwire seams schema=ripwire.seams/v1: cross-directory call edges NO test reaches: <seam from= to= untested= shown= capped=> of <edge caller= p= callee= cp=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. root=: p= relative to it. pr_iters=N: PageRank iterations. modules=N: directories holding indexed symbols (a module = parent dir). bridges=N: cross-directory call edges, tested or not; untested= is those no test reaches. test_files=N: test files whose calls seed the reach; 0 means every seam reads untested. seam_pairs=N: directed dir pairs with an untested edge (the seam rows' total). <file-scope> (t=modscope): a file's MODULE SCOPE — where a top-level call and an anonymous callback body's calls live; a CALLER, never a callee, with no body to expand. -->
<seams schema="ripwire.seams/v1" modules="663" bridges="9596" untested="6140" test_files="2048" seam_pairs="34" shown="20" capped="1" total="34" has_more="1" next_offset="20" offset="0" limit="0" pr_iters="28" root="." graph_ambiguous="12495" graph_unresolved="12552" graph_unindexed="255" counts_flo … [line truncated: 7 more bytes on this line]
<seam from="src" to="src/infra" untested="5950" shown="5" capped="1">
<edge caller="write" p="src/serialize.h:412" callee="data" cp="src/infra/svector.h:265"/>
<edge caller="write" p="src/serialize.h:412" callee="data" cp="src/infra/svector.h:266"/>
<edge caller="jsonEscape" p="src/mcpjson.h:877" callee="escapeMcp" cp="src/infra/jsonesc.h:230"/>
<edge caller="lowerExtOf" p="src/docparse.h:83" callee="size" cp="src/infra/os_win32_logic.h:485"/>
<edge caller="baseNameOf" p="src/mention.h:274" callee="afterLast" cp="src/infra/namesplit.h:157"/>
</seam>
<seam from="bench" to="src/infra" untested="73" shown="5" capped="1">
<edge caller="applyOne" p="bench/bench_svector_diff.cpp:166" callee="pop_back" cp="src/infra/svector.h:340"/>
<edge caller="applyOne" p="bench/bench_svector_diff.cpp:166" callee="emplace_back" cp="src/infra/svector.h:333"/>
<edge caller="applyOne" p="bench/bench_svector_diff.cpp:166" callee="shrink_to_fit" cp="src/infra/svector.h:305"/>
<edge caller="infraSortSmall" p="bench/bench_radix_ab.cpp:73" callee="sortKeySmall" cp="src/infra/radixSort.h:91"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--limit`

### `--mermaid`

**Answers:** module (directory) dependency graph as a Mermaid diagram (paste/render)

**Try it**

_Module (directory) dependency graph as a Mermaid diagram._

```
$ ./build/ripwire . --mermaid
%% ripwire --mermaid: module (directory) dependency graph — node = dir (symbol count), edge = inter-module calls (>= 3). Render at mermaid.live.
flowchart LR
  subgraph sg0 ["src"]
    n101["src<br/>7731"]
    n102["src/infra<br/>1280"]
  end
  subgraph sg1 ["test"]
    n103["test<br/>5057"]
    n333["test/fixtures/recallpassage<br/>314"]
    n280["test/expandmodefix<br/>151"]
    n282["test/expandsibsfix<br/>149"]
    n535["test/rubyattrsfix<br/>85"]
    n411["test/massfix<br/>77"]
    n492["test/receiverevidencefix/js/lib<br/>74"]
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--zoom`, `--with-graph`, `--legend`, `--limit`, `--max-memory`

### `--owners[=SYM]`

**Answers:** bus factor: recency-weighted author ownership per file bus-factor: recency-weighted author ownership per file;

bf=1 = one person holds >80% of weighted commits. Files with authors=1 (deterministically bf=1 share=1.00) fold into ONE <uniform files="N"/> summary row instead of N identical rows; --detail=N restores the full listing. An @FILE:LINE seed rebinds to the innermost enclosing definition (sym= names it) and analyses exactly that definition's file

**Try it**

_Bus-factor: recency-weighted author ownership per file._

```
$ ./build/ripwire . --owners
<!-- ripwire owners schema=ripwire.owners/v1: recency-weighted author ownership (half-life 6mo): <f p= authors= bf= top= share=>; bf=1 = one person holds it. at=: commit+dirty+shallow. root=: p= relative to it. files=N: files analysed. files=N: single-author files folded into this one row; detail=1 lists each. -->
<owners schema="ripwire.owners/v1" files="2688" root="." at="f1e5c2e76">
<uniform authors="1" bf="1" share="1.00" files="1749"/>
<f p=".coderabbit.yaml" authors="2" bf="0" top="<author>" share="0.75"/>
<f p=".github/pargates-shard-weights.json" authors="3" bf="0" top="<author>" share="0.75"/>
<f p=".github/workflows/ci.yml" authors="6" bf="0" top="<author>" share="0.46"/>
<f p=".github/workflows/nightly.yml" authors="2" bf="1" top="<author>" share="0.86"/>
<f p=".github/workflows/release.yml" authors="3" bf="0" top="<author>" share="0.49"/>
<f p="AGENTS.md" authors="2" bf="0" top="<author>" share="0.71"/>
<f p="CHANGELOG.md" authors="12" bf="0" top="<author>" share="0.72"/>
<f p="CLAUDE.md" authors="5" bf="0" top="<author>" share="0.41"/>
<f p="CONTRIBUTING.md" authors="5" bf="0" top="<author>" share="0.60"/>
<f p="INSTALL.md" authors="2" bf="1" top="<author>" share="0.87"/>
<f p="README.md" authors="19" bf="0" top="<author>" share="0.44"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--at`, `--limit`

### `--dead-code[=DIR]`

**Answers:** list internal functions with no caller anywhere in the indexed tree internal source functions with no caller found in the indexed tree — a name-based graph reading, not a confidence score (dynamic dispatch, reflection and macro-generated callers are invisible to it);

=DIR scopes to whole path components (dir or filename) and REFUSES a filter that names nothing indexed. A symbol whose definition is produced by a SELF-REGISTERING test/benchmark macro is never reported: doctest TEST_CASE/ TEST_CASE_FIXTURE/SCENARIO, gtest TEST/TEST_F/TEST_P, Catch2, Google Benchmark — a static initializer registers them, so a name-based call graph cannot see the caller and every one of them would be a false positive. Extend the list for your own framework with `.ripwire_config`'s one key, `register_macros = NAME[, NAME...]` (one directive per line, # comments). The exemption is DISCLOSED, never silent: register-macro-excluded="N" rides the report and prints even at 0. Exempt from dead-code only — such a symbol still participates in clone detection. A function a table, field or argument holds as a VALUE (--callers' <vr> rows) is not reported either: value-ref-excluded="N" counts them, absent at 0 (matched by name, not a proven call); a function that only stores ITSELF still is. A value walk cut by deep nesting is disclosed on the root, with value_refs_depth_at= naming the first cut (the list may over-report there). A LEADING ./ anchors DIR at the repo ROOT (=./src matches only the top-level src/ subtree); a bare name (=src) matches that component ANYWHERE in the tree, including nested (test/fixture/src/…)

**Try it**

_Internal functions with no caller found in the index — a name-based graph reading, not a confidence score. NOTE the filter is a path-COMPONENT match: 'src' matches any .../src/... segment; use ./src to pin the root directory._

```
$ ./build/ripwire . --dead-code=src
<!-- ripwire dead-code schema=ripwire.dead-code/v1: internal-linkage functions with no caller found in the index (not a confidence score): <d n= t= p= l=>; filter= path component. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. value-ref-excluded=N: internal functions kept off because a table, field or argument in another function or at file scope holds them (matched by name, not a proven call); a floor. root=: p= relative to it. evidence=: the rule every row met, internal linkage and no caller in the index; verify before deleting. register-macro-excluded=N: symbols skipped as self-registering test/bench macros (TEST, BENCHMARK...); a floor. count=N: candidates meeting evidence= (a floor). -->
<dead-code schema="ripwire.dead-code/v1" count="1" evidence="internal-linkage+zero-callers" register-macro-excluded="0" value-ref-excluded="6" filter="src" root="." graph_ambiguous="12495" graph_unresolved="12552" graph_unindexed="255" counts_floor="1">
<d n="unused_helper" t="fn" p="test/archmetricsfix/src/orphan/util.cpp" l="1"/>
</dead-code>
```

**Shaped by:** `--safe-delete`, `--limit`

**Caveats (stated by the binary):**

- list internal functions with no caller anywhere in the indexed tree internal source functions with no caller found in the indexed tree — a name-based graph reading, not a confidence score (dynamic dispatch, reflection and macro-generated callers are invisible to it);
- =DIR scopes to whole path components (dir or filename) and REFUSES a filter that names nothing indexed.
- The exemption is DISCLOSED, never silent: register-macro-excluded="N" rides the report and prints even at 0.

### `--quality-baseline`

**Answers:** snapshot today's complexity, clones and dead code as the floor to measure against snapshot ccx/clones/dead-code to .ripwire_quality_baseline (run BEFORE a change, on a CLEAN tree).

On a tree that DIFFERS from HEAD it computes the HEAD delta FIRST and REFUSES (exit 1) rather than pin the debt already in the tree as the floor — it names how many gating findings it would absorb and the first of them. Commit, or pass --allow-dirty. The pin is stamped with HEAD and with THIS build's identity, and only this build honors it.

**Try it**

_REFUSES, exit 1: this sandbox tree is already regressed, and pinning here would swallow that debt into the floor so every later delta read clean. It names how many gating findings it would absorb, the first of them, and the way forward._

```
$ ./build/ripwire . --quality-baseline
(empty)
```

**Shaped by:** `--allow-dirty`, `--quality-delta`, `--legend`

**Caveats (stated by the binary):**

- snapshot today's complexity, clones and dead code as the floor to measure against snapshot ccx/clones/dead-code to .ripwire_quality_baseline (run BEFORE a change, on a CLEAN tree).
- On a tree that DIFFERS from HEAD it computes the HEAD delta FIRST and REFUSES (exit 1) rather than pin the debt already in the tree as the floor — it names how many gating findings it would absorb and the first of them.

### `--allow-dirty`

**Answers:** (with --quality-baseline) pin the baseline even though the tree differs from HEAD (with --quality-baseline) pin anyway: the sidecar is stamped with the dirty pin and the absorbed count, and every later --quality-delta against it carries baseline_absorbed="N" — so a green exit beside that attribute reads as "clean SINCE THE PIN", never "clean".

Refused alone.

**Try it**

_The consent form: pin anyway. The sidecar is stamped with the dirty pin and the absorbed count, so the fact outlives the process that knew it._

```
$ ./build/ripwire . --quality-baseline --allow-dirty
(empty)
```

**Shaped by:** `--quality-baseline`

### `--show-stale`

**Answers:** (with --quality-delta) print the stale-ack rows and the full header a clean answer collapses — a regression-free answer keeps only stale= and stale_by_kind= (its <sa> rows collapsed), and on a tree that IS its HEAD only the verdict.

Refused alone.

### `--quality-delta`

**Answers:** before a PR: report ONLY what your change made worse, across 12 kinds — pair with --test-gate.

Each kind is measured against the baseline (complexity/verbosity/nesting/params/dup/dead/api-surface + error-masking/short-horizon-churn/new-clone-of-reused-helper + placeholder + defect-shape); every finding is classified by ORIGIN: a symbol that EXISTED at the baseline and got worse (preexisting-worse="N", no attribute on the row) vs one that exists only because the code is NEW (new-symbol="N", origin="new-symbol" on the row). A small numeric delta is additionally sev="minor". EXIT 2 ONLY on a major AND unacked row that is preexisting-worse or defect-shape format-arity (any origin) — the gating="N" header count. New-symbol rows are still PRINTED (they are the debt you are adding — read them); new-symbol rows never gate, except defect-shape format-arity; exit 0 means "nothing that already existed got worse", not "clean". Clone kinds classify by member set (new-symbol only if EVERY member is new); short-horizon-churn is preexisting by construction. LIMIT: origin is canonId (path::scope::name) identity, so a RENAMED/MOVED symbol reads as new and a regression carried in with the move will not gate. error-masking = a NEW empty/pass/comment-only handler, or log-only (a broad handler whose body only logs and never names the error) or rethrow-only (the sole handler re-throws it unchanged); those two gate only where their precision was measured (Python) and are sev="minor" in every other language. placeholder = a stub the change ADDED (todo!()/unimplemented!(), Kotlin TODO(), NotImplementedException, a bare raise NotImplementedError as a free function's body, a throw/raise/panic/assert saying "not implemented") or a comment line opening with TODO/FIXME that names no issue (#12, ABC-12, a URL); new-symbol by construction, so it never gates. Counted per enclosing symbol, like error-masking: a file-level TODO outside every definition is not counted. defect-shape = a known defect shape the change ADDED, named by defect=: format-arity (a literal std::format/print/format_to, fmt::, rw::emitTo/formatTo or Python "literal".format whose fields do not match its arguments — GATES on any origin, a defect not debt), utf8-cut and dedup-first (C++) and vacuous-assert (Bash test scripts) — report-only, always sev="minor". A site is new only when its text occurs more often than in the baseline: a moved one is not. Test-fixture dirs + doc sections are exempt from dead-code/churn; churn needs COMMITTED thrash evidence (rewritten across recent commits AND again by this diff), never the current edit alone WHICH FLOOR IT COMPARES AGAINST, and a side effect: the sidecar is honored only when the sha it was pinned at EQUALS the current git HEAD (strict equality — an ancestor commit describes a DIFFERENT tree, so everything committed since would read as your regression). A sidecar pinned anywhere else is STALE: this verb then DELETES it from your working tree (self-heal, so the next run does not rediscover the dead pin) and auto-compares the working tree vs git HEAD instead. Re-pin with --quality-baseline. The read-only MCP quality_delta verb applies the SAME staleness test but never deletes. A sidecar at the current HEAD that ANOTHER ripwire build pinned (its producer stamp names other sources — a dead set depends on how calls were resolved) is FOREIGN: both arms ignore it, never delete it, and auto-compare vs git HEAD. Which floor was actually used is on every report as baseline=: sidecar | git-HEAD | git-HEAD (stale sidecar removed) | git-HEAD (stale sidecar ignored) | git-HEAD (foreign sidecar ignored) — the stale two say a stale sidecar existed, and 'removed' means the file is gone. A non-git root has no HEAD to fall back to, so its sidecar is honored whenever this build pinned it; without one there, or with another build's, the verb exits 1.

**Try it**

_On a CLEAN tree: nothing got worse, exit 0. The gating shape is in the sandbox section below._

```
$ ./build/ripwire . --quality-delta
<!-- ripwire quality-delta schema=ripwire.quality-delta/v1: only what the change made WORSE vs baseline=: regressions= minor= gating=; <r kind= sym= p= was= now= gating= bar=>, <sa> acked. value-ref-excluded=N: internal functions kept off because a table, field or argument in another function or at file scope holds them (matched by name, not a proven call); a floor. at=: commit+dirty+shallow. stale=N: ack ledger rows whose target no longer applies (sa rows); never gating. preexisting-worse=N: regressions on symbols that existed at baseline; they gate when major. new-symbol=N: findings on NEW code; new-symbol rows never gate, except defect-shape format-arity. register-macro-excluded=N: symbols kept out of dead-code as self-registering test/bench macros; a floor. api-new-surface=N: new PUBLIC symbols; a count, never gates, not in regressions=. renames=/rename_window_commits=: git rename pairs read over that many commits, to re-file baseline and acks. acked_by_rename=/acked_by_content=: acked= suppressions matched via git renames / an equal body hash. renames_window_truncated=1: history is deeper than the rename window, older renames unread. acked=N: findings suppressed by the ack ledger, listed as sa rows; never gating. sa key=/why=: the stale ack's ledger hash / target-gone (names nothing now) or finding-gone (no longer fires). head_basis=identity: the floor is this tree's own snapshot; archived-index-hidden: refused, a tracked path is skip-worktree/assume-unchanged; absent: the archived HEAD tree. -->
<quality-delta schema="ripwire.quality-delta/v1" baseline="git-HEAD" regressions="0" minor="0" acked="0" stale="145" preexisting-worse="0" new-symbol="0" gating="0" register-macro-excluded="62" api-new-surface="0" at="f1e5c2e76" renames="58" rename_window_commits="400" acked_by_rename="0" acked_by_c … [line truncated: 86 more bytes on this line]
<sa kind="api-surface" key="085e3d408c2c4a35" why="target-gone"/>
<sa kind="api-surface" key="155d74d341a49f3c" why="target-gone"/>
<sa kind="api-surface" key="1a15386c2d1e47af" why="target-gone"/>
<sa kind="api-surface" key="298e798c7f075715" why="target-gone"/>
<sa kind="api-surface" key="56acdf9b5c314a14" why="target-gone"/>
<sa kind="api-surface" key="5a07390012b46e06" why="target-gone"/>
<sa kind="api-surface" key="6eef859578c8c376" why="target-gone"/>
<sa kind="api-surface" key="6f2394762f82a855" why="target-gone"/>
<sa kind="api-surface" key="7f2c3eefdf6e512e" why="target-gone"/>
<sa kind="api-surface" key="802e513731103806" why="target-gone"/>
<sa kind="api-surface" key="b6a24afef32a68a8" why="target-gone"/>
<sa kind="api-surface" key="c923e661c197b265" why="target-gone"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--affected`, `--test-gate`, `--allow-dirty`, `--show-stale`, `--dmm`, `--quality-ack`, `--scope`, `--json`

**Caveats (stated by the binary):**

- new-symbol rows never gate, except defect-shape format-arity;
- LIMIT: origin is canonId (path::scope::name) identity, so a RENAMED/MOVED symbol reads as new and a regression carried in with the move will not gate.
- error-masking = a NEW empty/pass/comment-only handler, or log-only (a broad handler whose body only logs and never names the error) or rethrow-only (the sole handler re-throws it unchanged);

### `--quality-delta=REV|A..B`

**Answers:** the same 12-kind report between two committed trees — a whole branch at once the same 12-kind report between two COMMITTED TREES instead of the working tree vs a baseline — the WAVE-level measurement (=A..B = tree B against tree A;

=REV = that commit against its FIRST PARENT; an EMPTY side of the range means HEAD). Same grammar --dmm= takes, and A...B is REFUSED rather than read as A..B. Use it to measure a whole integration branch at once (--quality-delta=<merge-base>..<head>): per-lane checks each compare against their own baseline and cannot see a regression the WAVE introduced. Identical output contract to the bare form — same kinds, gating="N", exit 2, and the same .ripwire_quality_acks ratchet (acks are keyed root-relative, so a ledger recorded from working-tree runs applies unchanged). base_ref= and target_ref= disclose the two RESOLVED shas. No sidecar is read, written or deleted by this form, and at= is omitted: the two refs ARE the anchor. A==B is a legal, empty, exit-0 comparison. ONE KIND CANNOT BE MEASURED HERE and says so as churn="unavailable": short-horizon-churn needs git history at the tree being judged, and both trees are materialized OUT of the repo into temp dirs. The other 10 kinds are computed exactly as the bare form computes them.

**Try it**

_On a CLEAN tree: nothing got worse, exit 0. The gating shape is in the sandbox section below._

```
$ ./build/ripwire . --quality-delta
<!-- ripwire quality-delta schema=ripwire.quality-delta/v1: only what the change made WORSE vs baseline=: regressions= minor= gating=; <r kind= sym= p= was= now= gating= bar=>, <sa> acked. value-ref-excluded=N: internal functions kept off because a table, field or argument in another function or at file scope holds them (matched by name, not a proven call); a floor. at=: commit+dirty+shallow. stale=N: ack ledger rows whose target no longer applies (sa rows); never gating. preexisting-worse=N: regressions on symbols that existed at baseline; they gate when major. new-symbol=N: findings on NEW code; new-symbol rows never gate, except defect-shape format-arity. register-macro-excluded=N: symbols kept out of dead-code as self-registering test/bench macros; a floor. api-new-surface=N: new PUBLIC symbols; a count, never gates, not in regressions=. renames=/rename_window_commits=: git rename pairs read over that many commits, to re-file baseline and acks. acked_by_rename=/acked_by_content=: acked= suppressions matched via git renames / an equal body hash. renames_window_truncated=1: history is deeper than the rename window, older renames unread. acked=N: findings suppressed by the ack ledger, listed as sa rows; never gating. sa key=/why=: the stale ack's ledger hash / target-gone (names nothing now) or finding-gone (no longer fires). head_basis=identity: the floor is this tree's own snapshot; archived-index-hidden: refused, a tracked path is skip-worktree/assume-unchanged; absent: the archived HEAD tree. -->
<quality-delta schema="ripwire.quality-delta/v1" baseline="git-HEAD" regressions="0" minor="0" acked="0" stale="145" preexisting-worse="0" new-symbol="0" gating="0" register-macro-excluded="62" api-new-surface="0" at="f1e5c2e76" renames="58" rename_window_commits="400" acked_by_rename="0" acked_by_c … [line truncated: 86 more bytes on this line]
<sa kind="api-surface" key="085e3d408c2c4a35" why="target-gone"/>
<sa kind="api-surface" key="155d74d341a49f3c" why="target-gone"/>
<sa kind="api-surface" key="1a15386c2d1e47af" why="target-gone"/>
<sa kind="api-surface" key="298e798c7f075715" why="target-gone"/>
<sa kind="api-surface" key="56acdf9b5c314a14" why="target-gone"/>
<sa kind="api-surface" key="5a07390012b46e06" why="target-gone"/>
<sa kind="api-surface" key="6eef859578c8c376" why="target-gone"/>
<sa kind="api-surface" key="6f2394762f82a855" why="target-gone"/>
<sa kind="api-surface" key="7f2c3eefdf6e512e" why="target-gone"/>
<sa kind="api-surface" key="802e513731103806" why="target-gone"/>
<sa kind="api-surface" key="b6a24afef32a68a8" why="target-gone"/>
<sa kind="api-surface" key="c923e661c197b265" why="target-gone"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--affected`, `--test-gate`, `--allow-dirty`, `--show-stale`, `--dmm`, `--quality-ack`, `--scope`, `--json`

**Caveats (stated by the binary):**

- Same grammar --dmm= takes, and A...B is REFUSED rather than read as A..B.
- Use it to measure a whole integration branch at once (--quality-delta=<merge-base>..<head>): per-lane checks each compare against their own baseline and cannot see a regression the WAVE introduced.
- ONE KIND CANNOT BE MEASURED HERE and says so as churn="unavailable": short-horizon-churn needs git history at the tree being judged, and both trees are materialized OUT of the repo into temp dirs.

### `--dmm[=REV|A..B]`

**Answers:** score a change as ONE number in [0,1], so quality trends across commits the DELTA MAINTAINABILITY MODEL scalar: ONE comparable number in [0,1] for a change, so quality becomes TRENDABLE across commits instead of a per-kind list (di Biase, Rastogi, Bruntink and van Deursen, TechDebt 2019;

thresholds and arithmetic from PyDriller's deltamaintainability reference implementation). Bare = the WORKING TREE vs git HEAD (what --quality-delta compares); =REV = that commit vs its FIRST PARENT (the per-commit scalar); =A..B = tree B vs tree A. A UNIT is a function/method definition with a body; its VOLUME is its line span. Per property a unit is LOW risk iff size: loc<=15, complexity: cyclomatic<=5, interfacing: params<=2. good = low-risk volume ADDED plus high-risk volume REMOVED; bad = low-risk REMOVED plus high-risk ADDED; dmm = good/(good+bad). So DELETING a god function scores 1.000 and GROWING one scores 0.000. The three sub-scores (size/complexity/interfacing) are emitted alongside the combined one because they are separately actionable; the combined one POOLS them (summed good over summed good+bad) and is labelled combine="pooled", since the paper publishes the three separately and no aggregate. IT IS A DELTA, NEVER A LEVEL: a unit you edit without changing its size, complexity or parameter count sits in the same bin with the same volume on both sides and contributes NOTHING. Touching bad code is not punished, deliberately, because a gate that punishes it is a gate people route around. dmm="UNAVAILABLE" means good+bad was 0 (a rename, a literal edit, a comment reflow): the change is outside what the model measures. That is NEVER to be read as 1.000 or 0.000, and reason= says which case it was. Same token per property. VOLUME IS PHYSICAL LINE SPAN (size_metric="physical-loc"), where the reference implementation uses non-comment non-blank lines, so a heavily commented unit crosses the size threshold here earlier. NO THRESHOLD, NO VERDICT, ALWAYS EXIT 0.

**Try it**

_The Delta Maintainability Model scalar for the WORKING TREE vs HEAD — recorded against a CLEAN tree (the sandbox section shows a real delta). UNAVAILABLE is a stated reason, never 0 or 1._

```
$ ./build/ripwire . --dmm
<!-- ripwire dmm schema=ripwire.dmm/v1: Delta Maintainability Model base=→target=: dmm= good/(good+bad) units by size_metric=; <p k= dmm= good= bad= d_low= d_high=>. at=: commit+dirty+shallow. available=0: no score at all (dmm=UNAVAILABLE, reason= says why); never read as 1.000 or 0.000. combine=pooled: root dmm= is summed good over summed good+bad of the 3 properties (ripwire's own). low_loc=/low_cx=/low_params=: a unit is LOW risk at or under these lines / cyclomatic / params. base_units=/base_volume=/target_units=/target_volume=: units with a body and their line span per side. reason=: why no score (no unit's size, complexity or params moved; a tree failed to parse ...). -->
<dmm schema="ripwire.dmm/v1" base="f1e5c2e76f0a8c29149cc56d865c6627d76b4c24" target="working-tree" at="f1e5c2e76" available="0" combine="pooled" size_metric="physical-loc" low_loc="15" low_cx="5" low_params="2" dmm="UNAVAILABLE" good="0" bad="0" base_units="14065" base_volume="211512" target_units=" … [line truncated: 147 more bytes on this line]
<p k="size" dmm="UNAVAILABLE" good="0" bad="0" d_low="0" d_high="0"/>
<p k="complexity" dmm="UNAVAILABLE" good="0" bad="0" d_low="0" d_high="0"/>
<p k="interfacing" dmm="UNAVAILABLE" good="0" bad="0" d_low="0" d_high="0"/>
</dmm>
```

**Shaped by:** `--quality-delta`

**Caveats (stated by the binary):**

- IT IS A DELTA, NEVER A LEVEL: a unit you edit without changing its size, complexity or parameter count sits in the same bin with the same volume on both sides and contributes NOTHING.
- That is NEVER to be read as 1.000 or 0.000, and reason= says which case it was.

### `--quality-ack[=REASON]`

**Answers:** accept the current findings as known, until one of them gets worse accept the current findings into .ripwire_quality_acks (per-finding ratchet): re-runs suppress them honestly (acked="N") until one WORSENS past its acked size.

=REASON implies the --quality-delta report it acks; the reason-less spelling needs --quality-delta beside it (refused alone). An ack with 0 findings to accept writes nothing and says so.

**Try it**

_NEW FLAG: --ack-only matching nothing REFUSES rather than falling back to acking everything._

```
$ ./build/ripwire . --quality-delta --quality-ack --ack-only=zzznope
(empty)
```

**Shaped by:** `--ack-only`, `--scope`, `--legend`

**Caveats (stated by the binary):**

- the reason-less spelling needs --quality-delta beside it (refused alone).

### `--ack-only=SUBSTR[,SUBSTR]`

**Answers:** (with --quality-ack) ack only SOME findings — those whose KIND, canonical id or FACET matches (with --quality-ack) ack only SOME findings — those whose KIND, canonical id, or FACET contains one of these;

the pseudo-token 'gating' selects exactly what would exit 2. Bare --quality-ack accepts the WHOLE report, so accepting one deliberate change silently accepts the rest — how a ratchet turns into a rubber stamp. Prefer the facet: --ack-only=contract-change acks the deliberate arity changes WITHOUT the never-gating api-surface new-symbol rows; a defect-shape facet (format-arity, utf8-cut, dedup-first, vacuous-assert) selects that shape alone. Matching nothing refuses (exit 1) rather than falling back to acking everything. Whatever you leave unacked stays visible.

**Try it**

_--ack-only WITHOUT --quality-ack REFUSES loudly (exit 1, the pairing named) — it used to be silently ignored._

```
$ ./build/ripwire . --ack-only=gating
(empty)
```

**Shaped by:** `--scope`

**Caveats (stated by the binary):**

- Prefer the facet: --ack-only=contract-change acks the deliberate arity changes WITHOUT the never-gating api-surface new-symbol rows;
- Matching nothing refuses (exit 1) rather than falling back to acking everything.

### `--scope=GLOB[,GLOB...]`

**Answers:** (with --quality-delta/--quality-ack) file findings by OWNERSHIP when one tree has several writers (with --quality-delta/--quality-ack) OWNERSHIP partition for a working tree that has MORE THAN ONE WRITER in it — N agent sessions sharing one checkout.

The delta compares the working tree against HEAD, so every concurrent writer's uncommitted rows land in YOUR report; this files each finding by its p= path. Rows in scope gate as usual; rows outside it are STILL PRINTED, under an out-of-scope element with a do-not-ack banner, and never gate. The header carries scope=, scoped-out= and scoped-out-gating= (how many disclosed rows WOULD have gated — do not read a green exit as a clean tree). THE POINT IS THE ACK: bare --quality-ack in a dirty shared tree accepts the WHOLE report, which silently absorbs a sibling session's debt into a committed ledger under your reason string — that is how a ratchet becomes a rubber stamp. Under --scope, an out-of-scope row is never written, and an --ack-only that NAMES one refuses (exit 1, naming the rows, writing nothing). Each row written under a scope records by=<scope>, and a later run flags an ack whose by= does not cover what it suppresses (foreign-acks= plus an sa row with why="foreign-scope"). THE GLOB, EXACTLY (a pattern that silently fails to match is worse than a documented prefix): each comma-separated pattern is matched against the ROOT-RELATIVE path p= prints, and the list is an OR. NO wildcard = a ROOT-ANCHORED path prefix ending on a / boundary (scope=alpha matches alpha/lib.h, never alphabet/lib.h and never a nested src/alpha/ — stricter than the dead-code directory filter, on purpose). With * or ? = matched against the WHOLE path, * spanning / and ? exactly one character. NOT SUPPORTED: ** (it is two stars, and one already spans /), character classes, brace expansion, negation; whitespace and XML metacharacters in a pattern are REFUSED, not mangled. FLOORS: a clone group is in scope iff ANY member matches; a finding with no locator at all is filed OUT of scope (not provably yours); a scope naming nothing indexed REFUSES (exit 1) rather than reporting a clean zero. ONE RESERVED WORD: --scope=diff is the files the WORKING TREE changes vs the baseline, expanded to one path per changed INDEXED file (the count travels with the report as scope-diff-files=). It composes by UNION: --scope=diff,src/quality.h is that set plus that file. A directory really called diff must be spelled ./diff or diff/. IT IS SUGAR FOR THE SINGLE-WRITER CASE and wrong on its own in the shared tree this flag exists for — a sibling's edits are "changed" too, so name your own paths when the tree has more than one writer. Refused, never silently widened, when there is no git, when the range form is in play (it compares two COMMITTED trees), or when it expands to nothing. An ack written under it records by=diff, which a later run does NOT sweep: an auto-scope meant one file set then and another now, so re-checking it would invent findings.

**Try it**

_OWNERSHIP partition for a shared tree: every regression here lives in src/infra/, so under a scope naming src/graph.h they ALL print under <out-of-scope> with a do-not-ack banner and never gate — scoped-out-gating= says how many would have._

```
$ ./build/ripwire . --quality-delta --scope=src/graph.h
<!-- ripwire quality-delta schema=ripwire.quality-delta/v1: only what the change made WORSE vs baseline=: regressions= minor= gating=; <r kind= sym= p= was= now= gating= bar=>, <sa> acked. value-ref-excluded=N: internal functions kept off because a table, field or argument in another function or at file scope holds them (matched by name, not a proven call); a floor. at=: commit+dirty+shallow. stale=N: ack ledger rows whose target no longer applies (sa rows); never gating. preexisting-worse=N: regressions on symbols that existed at baseline; they gate when major. new-symbol=N: findings on NEW code; new-symbol rows never gate, except defect-shape format-arity. register-macro-excluded=N: symbols kept out of dead-code as self-registering test/bench macros; a floor. api-new-surface=N: new PUBLIC symbols; a count, never gates, not in regressions=. renames=/rename_window_commits=: git rename pairs read over that many commits, to re-file baseline and acks. acked_by_rename=/acked_by_content=: acked= suppressions matched via git renames / an equal body hash. renames_window_truncated=1: history is deeper than the rename window, older renames unread. r surface=: the api-surface tier, new-symbol or contract-change. acked=N: findings suppressed by the ack ledger, listed as sa rows; never gating. r sev=minor: a small numeric delta, counted in minor=, never gating (absent: major). r origin=new-symbol: a finding on NEW code (absent: preexisting-worse). sa key=/why=: the stale ack's ledger hash / target-gone (names nothing now) or finding-gone (no longer fires). r members=/tokens=: a duplication row's clone group (member ids) / their shared normalized-token count. -->
<quality-delta schema="ripwire.quality-delta/v1" baseline="git-HEAD" regressions="0" minor="0" acked="0" stale="145" preexisting-worse="0" new-symbol="0" gating="0" register-macro-excluded="62" api-new-surface="2" at="f1e5c2e76+dirty" renames="58" rename_window_commits="400" acked_by_rename="0" acke … [line truncated: 127 more bytes on this line]
<out-of-scope n="9" would-gate="4" note="not yours - do not ack: these rows lie outside the scope this run named. They are disclosed rather than hidden, they never gate this exit code, and the ack refuses to write them.">
<r kind="api-surface" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="1" now="2" surface="contract-change" p="src/infra/sortutil.h:109"/>
<r kind="complexity" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="67" bar="15" p="src/infra/sortutil.h:49"/>
<r kind="dead-code" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy" origin="new-symbol" p="src/infra/sortutil.h:119"/>
<r kind="dead-code" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" origin="new-symbol" p="src/infra/sortutil.h:129"/>
<r kind="duplication" members="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" tokens="59" p="src/infra/sortutil.h:119"/>
<r kind="nesting" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="6" bar="4" p="src/infra/sortutil.h:49"/>
... [22 more line(s); run it to see the whole thing]
```

**Caveats (stated by the binary):**

- rows outside it are STILL PRINTED, under an out-of-scope element with a do-not-ack banner, and never gate.
- Under --scope, an out-of-scope row is never written, and an --ack-only that NAMES one refuses (exit 1, naming the rows, writing nothing).
- NO wildcard = a ROOT-ANCHORED path prefix ending on a / boundary (scope=alpha matches alpha/lib.h, never alphabet/lib.h and never a nested src/alpha/ — stricter than the dead-code directory filter, on purpose).

### `--edit-check=SYM`

**Answers:** after an edit: did SYM's contract change, and which callers no longer fit? fast per-symbol post-edit contract check: SYM's param count + publicness NOW vs git HEAD (unchanged/new-symbol/contract-change with was/now), plus its 1-hop callers with any call-site provably incompatible with the NEW arity flagged.

A contract is PER DEFINITION, so a SYM matching several definition sites REFUSES (exit 1) and lists the file:name spellings that pick one — unlike --callers/--uses, this verb may not union overloads and disclose defs=. A .ripwire_notes entry targeting SYM (or its file) rides along as a <note> child, the same row shape --for/--expand surface. PRE-APPLY PREVIEW — add --edit-payload=FILE|- --dry-run to ask the SAME question about bytes that have NOT been written yet. The payload is spliced over SYM's definition span in memory, exactly as --replace-symbol-body would write it; that one file is re-parsed, the call graph rebuilt over the re-derived tree, and the same document emitted with preview="1" plus an <overwrite l= end= bytes=> child holding the CURRENT span the apply would replace, as on disk (over 4 KB: the head, with shown=/capped="1"/elided_lines=) — preview then apply, no Read. Nothing is written, and every other file plus the git HEAD baseline stay the real tree's. Refuses, exit 1, on a payload that is unreadable, empty, oversize or NUL-bearing, on one whose splice raises the file's parse errors, on one that does not define SYM, and on a span the file's current bytes no longer fit. Single-root, and it previews a body REPLACEMENT only.

**Try it**

_Fast per-symbol post-edit contract check vs git HEAD (unchanged on a clean tree)._

```
$ ./build/ripwire . --edit-check=rankGraphTeleport
<!-- ripwire edit-check schema=ripwire.edit-check/v1: sym='s contract NOW vs HEAD: status=unchanged|new-symbol|contract-change; <c n= p= incompatible=1 sites_l=> callers. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. next=: the one pasteable follow-up. defs=N: overloads at this site (same file, scope, name) folded into one contract; params compared by MAX. callers=N: callers of sym= (the c rows' total; a floor). -->
<edit-check schema="ripwire.edit-check/v1" sym="rankGraphTeleport" t="fn" p="src/graph.h:7924" status="unchanged" defs="1" callers="7" incompatible="0" at="f1e5c2e76" graph_ambiguous="12495" graph_unresolved="12552" graph_unindexed="255" counts_floor="1" root="." next="--test-gate=src/graph.h" est_t … [line truncated: 12 more bytes on this line]
<c n="runEval" p="src/eval.h:171"/>
<c n="rankGraph" p="src/graph.h:7965"/>
<c n="anchoredLexicalRank" p="src/graph.h:8611"/>
<c n="churnDecayRanking" p="src/main.cpp:1383"/>
<c n="churnRankedGraph" p="src/main.cpp:1422"/>
<c n="runDefaultMap" p="src/main.cpp:1632"/>
<c n="getIndex" p="src/mcpindex.h:1165"/>
</edit-check>
```

**Shaped by:** `--edit-target-file`, `--slice`, `--at`, `--legend`, `--limit`

**Caveats (stated by the binary):**

- A contract is PER DEFINITION, so a SYM matching several definition sites REFUSES (exit 1) and lists the file:name spellings that pick one — unlike --callers/--uses, this verb may not union overloads and disclose defs=.
- that one file is re-parsed, the call graph rebuilt over the re-derived tree, and the same document emitted with preview="1" plus an <overwrite l= end= bytes=> child holding the CURRENT span the apply would replace, as on disk (over 4 KB: the head, with shown=/capped="1"/elided_lines=) — preview then apply, no Read.
- Refuses, exit 1, on a payload that is unreadable, empty, oversize or NUL-bearing, on one whose splice raises the file's parse errors, on one that does not define SYM, and on a span the file's current bytes no longer fit.

### `--replace-symbol-body=TARGET`

**Answers:** replace one whole definition atomically with the bytes from --edit-payload atomically replace one uniquely-resolved definition with the bytes from --edit-payload=FILE|- (ONE trailing newline on the payload folds into the newline already after the span — a heredoc or echo always appends one the span never had;

disclosed as trailing_newline_folded=true; a second one, a deliberate blank line, stays)

**Try it**

_An unknown TARGET refuses and leaves every file byte-identical._

```
$ ./build/ripwire . --replace-symbol-body=DoesNotExist --edit-payload=<scratch>/aux/payload_note.h
(empty)
```

**Shaped by:** `--edit-check`, `--edit-target-file`, `--at`

**Caveats (stated by the binary):**

- replace one whole definition atomically with the bytes from --edit-payload atomically replace one uniquely-resolved definition with the bytes from --edit-payload=FILE|- (ONE trailing newline on the payload folds into the newline already after the span — a heredoc or echo always appends one the span never had;

### `--insert-before-symbol=TARGET`

**Answers:** atomically insert the payload immediately before one uniquely-resolved definition

**Try it**

_Insert BEFORE, with --edit-target-file pinning which same-named definition (here unambiguous — the disambiguator is simply honoured)._

```
$ ./build/ripwire . --insert-before-symbol=nonNegativeFloatDescKey --edit-payload=<scratch>/aux/payload_note.h --edit-target-file=src/infra/sortutil.h
{"applied":"insert_before_symbol","symbol":"nonNegativeFloatDescKey","file":"src/infra/sortutil.h","span":{"start":2895,"end":2983},"lines":{"start":74,"end":75},"replaced_bytes":0,"old_file_bytes":11000,"new_file_bytes":11088,"file_eol":"lf","eol_normalized":false,"trailing_newline_folded":false,"s … [line truncated: 755 more bytes on this line]
{"n":"benchAdaptive","p":"bench/bench_radix_ab.cpp:157","l":[162]},
{"n":"radixSortNonNegativeFloatsDesc","p":"src/infra/sortutil.h:105","l":[114]},
{"n":"radixSortByScoreDescId","p":"src/infra/sortutil.h:120","l":[180]}],
"graph_ambiguous":12495,"graph_unresolved":12552,"graph_unindexed":255,"counts_floor":true},"tests_to_run":[{"p":"test/verify_radix.cpp","hops":1,"run":"bash test/greptiercheck.sh"},
{"p":"test/adaptivecutshapefix/adaptive_cut_shape_test.cpp","hops":2,"run":"bash test/adaptivecutshapecheck.sh"},
{"p":"test/includeprecise_unit.cpp","hops":2,"run":"bash test/includeprecisecheck.sh"},
{"p":"test/verify_csr.cpp","hops":2,"run":"bash test/a9disclosurecheck.sh"},
{"p":"test/rustimport_unit.cpp","hops":4,"run":"bash test/rustimportprecisecheck.sh"}],
"order":"evidence","partners":0,"run_first":1,"tests":5,"script_gates_unmodelled":743,"graph_ambiguous":12495,"graph_unresolved":12552,"graph_unindexed":255,"counts_floor":true,"next":"--uses=src/infra/sortutil.h:nonNegativeFloatDescKey"}
```

### `--insert-after-symbol=TARGET`

**Answers:** atomically insert the payload immediately after one uniquely-resolved definition.

Both inserts PAD the block (newlines only, never removed) so it is separated from the anchor by the same blank-line run the file already uses at that seam; separator_padded=N on the receipt is the count added (0 when the payload carried its own). A payload carrying MORE …[REDACTED:kind] markers than the bytes it would replace already do (a body copied from a redacted serve) refuses: re-fetch that body with --no-redact. TARGET is a symbol name, an @FILE:LINE line-seed (edits the innermost definition enclosing that line — paste the location from a diff hunk or error; the receipt discloses resolved_from_seed, a faulted seed refuses with a specific diagnosis, and --edit-target-file may not accompany a seed), or a freshness-pinned sym# handle emitted by --grep --handles.

**Try it**

_Insert immediately AFTER one uniquely-resolved definition; replaced_bytes=0 because the insert verbs never overwrite. The receipt carries the folded post-edit verification (lines=, edit_check, tests_to_run) so the loop closes in one call._

```
$ ./build/ripwire . --insert-after-symbol=lessByScoreDescId --edit-payload=<scratch>/aux/payload_note.h
{"applied":"insert_after_symbol","symbol":"lessByScoreDescId","file":"src/infra/sortutil.h","span":{"start":2375,"end":2463},"lines":{"start":56,"end":58},"replaced_bytes":0,"old_file_bytes":10824,"new_file_bytes":10912,"file_eol":"lf","eol_normalized":false,"trailing_newline_folded":true,"separator … [line truncated: 652 more bytes on this line]
"graph_ambiguous":12495,"graph_unresolved":12552,"graph_unindexed":255,"counts_floor":true},"tests_to_run":[{"p":"test/verify_radix.cpp","hops":1,"run":"bash test/greptiercheck.sh"},
{"p":"test/adaptivecutshapefix/adaptive_cut_shape_test.cpp","hops":2,"run":"bash test/adaptivecutshapecheck.sh"},
{"p":"test/includeprecise_unit.cpp","hops":2,"run":"bash test/includeprecisecheck.sh"},
{"p":"test/verify_csr.cpp","hops":2,"run":"bash test/a9disclosurecheck.sh"},
{"p":"test/rustimport_unit.cpp","hops":4,"run":"bash test/rustimportprecisecheck.sh"}],
"order":"evidence","partners":0,"run_first":1,"tests":5,"script_gates_unmodelled":743,"graph_ambiguous":12495,"graph_unresolved":12552,"graph_unindexed":255,"counts_floor":true,"next":"bash test/greptiercheck.sh"}
```

**Caveats (stated by the binary):**

- Both inserts PAD the block (newlines only, never removed) so it is separated from the anchor by the same blank-line run the file already uses at that seam;
- A payload carrying MORE …[REDACTED:kind] markers than the bytes it would replace already do (a body copied from a redacted serve) refuses: re-fetch that body with --no-redact.
- the receipt discloses resolved_from_seed, a faulted seed refuses with a specific diagnosis, and --edit-target-file may not accompany a seed), or a freshness-pinned sym# handle emitted by --grep --handles.

### `--edit-payload=FILE|-`

**Answers:** required exact byte payload ('-' reads stdin);

empty payloads refuse, never imply deletion

**Try it**

_An unknown TARGET refuses and leaves every file byte-identical._

```
$ ./build/ripwire . --replace-symbol-body=DoesNotExist --edit-payload=<scratch>/aux/payload_note.h
(empty)
```

**Shaped by:** `--edit-check`, `--replace-symbol-body`

**Caveats (stated by the binary):**

- empty payloads refuse, never imply deletion

### `--edit-target-file=PATH`

**Answers:** optional file-path substring disambiguating a same-named definition (relative or absolute) optional file-path substring disambiguating a same-named definition.

RELATIVE (matched against the indexed spelling) or ABSOLUTE (matched against the file's resolved on-disk path), so the path a receipt or a trace hands you works verbatim. These three CLI verbs reuse the MCP edit engine: freshness hash, lock, pre-rename recheck, fsync, mode preservation and atomic rename. Every refusal leaves the target byte-identical. Success prints a JSON receipt whose span is the POST-EDIT byte range (where the payload now sits in the new file), NOT the region overwritten in the old one — for --replace-symbol-body those two lengths usually differ; replaced_bytes is the count of old bytes actually overwritten (0 for the two insert verbs, which never overwrite), lines={start,end} is that same region as FILE:LINE, and trailing_newline_folded / separator_padded say what the seam rules did to the payload. region={start,end,context,text} is the post-edit region as it is ON DISK (the applied lines plus context=3 each side; over 2 KB it carries head, tail, elided_lines and capped=true) and blob_sha is the git blob id of the written bytes (== git hash-object FILE) — the Read an agent would make to see what landed is already in hand. The receipt also carries the POST-EDIT VERIFICATION the tool would otherwise tell you to run: edit_check={status,callers,incompatible,sites} — the same answer --edit-check=FILE:SYM gives, sites naming each broken caller's call LINES — and tests_to_run, the same rows --affected=FILE gives, run recipe included; and exactly ONE next= (a contract-change with broken callers: --uses=FILE:SYM; else the first run= recipe in EVIDENCE order (a changed or partner test outranks a deeper graph hop); else --test-gate=FILE; under --no-post-check: --edit-check=FILE:SYM). Edit, see what landed, verify and find the tests to run is ONE call.

**Try it**

_Insert BEFORE, with --edit-target-file pinning which same-named definition (here unambiguous — the disambiguator is simply honoured)._

```
$ ./build/ripwire . --insert-before-symbol=nonNegativeFloatDescKey --edit-payload=<scratch>/aux/payload_note.h --edit-target-file=src/infra/sortutil.h
{"applied":"insert_before_symbol","symbol":"nonNegativeFloatDescKey","file":"src/infra/sortutil.h","span":{"start":2895,"end":2983},"lines":{"start":74,"end":75},"replaced_bytes":0,"old_file_bytes":11000,"new_file_bytes":11088,"file_eol":"lf","eol_normalized":false,"trailing_newline_folded":false,"s … [line truncated: 755 more bytes on this line]
{"n":"benchAdaptive","p":"bench/bench_radix_ab.cpp:157","l":[162]},
{"n":"radixSortNonNegativeFloatsDesc","p":"src/infra/sortutil.h:105","l":[114]},
{"n":"radixSortByScoreDescId","p":"src/infra/sortutil.h:120","l":[180]}],
"graph_ambiguous":12495,"graph_unresolved":12552,"graph_unindexed":255,"counts_floor":true},"tests_to_run":[{"p":"test/verify_radix.cpp","hops":1,"run":"bash test/greptiercheck.sh"},
{"p":"test/adaptivecutshapefix/adaptive_cut_shape_test.cpp","hops":2,"run":"bash test/adaptivecutshapecheck.sh"},
{"p":"test/includeprecise_unit.cpp","hops":2,"run":"bash test/includeprecisecheck.sh"},
{"p":"test/verify_csr.cpp","hops":2,"run":"bash test/a9disclosurecheck.sh"},
{"p":"test/rustimport_unit.cpp","hops":4,"run":"bash test/rustimportprecisecheck.sh"}],
"order":"evidence","partners":0,"run_first":1,"tests":5,"script_gates_unmodelled":743,"graph_ambiguous":12495,"graph_unresolved":12552,"graph_unindexed":255,"counts_floor":true,"next":"--uses=src/infra/sortutil.h:nonNegativeFloatDescKey"}
```

**Shaped by:** `--insert-after-symbol`

**Caveats (stated by the binary):**

- optional file-path substring disambiguating a same-named definition (relative or absolute) optional file-path substring disambiguating a same-named definition.
- replaced_bytes is the count of old bytes actually overwritten (0 for the two insert verbs, which never overwrite), lines={start,end} is that same region as FILE:LINE, and trailing_newline_folded / separator_padded say what the seam rules did to the payload.
- over 2 KB it carries head, tail, elided_lines and capped=true) and blob_sha is the git blob id of the written bytes (== git hash-object FILE) — the Read an agent would make to see what landed is already in hand.

### `--no-post-check`

**Answers:** skip that folded verification — pass it when you are about to edit again immediately skip that folded verification (the index refresh it needs is the one the next verb call would pay for anyway;

pass this when you are about to edit again immediately). The MCP spelling is post_check:false. Single-root only.

**Try it**

_The opt-out: the same insert with the folded verification skipped — lines= still rides (it is free), edit_check/tests_to_run do not, and the two pasteable commands stay on stderr._

```
$ ./build/ripwire . --insert-after-symbol=lessByScoreDescId --edit-payload=<scratch>/aux/payload_note.h --no-post-check
{"applied":"insert_after_symbol","symbol":"lessByScoreDescId","file":"src/infra/sortutil.h","span":{"start":2375,"end":2463},"lines":{"start":56,"end":58},"replaced_bytes":0,"old_file_bytes":10912,"new_file_bytes":11000,"file_eol":"lf","eol_normalized":false,"trailing_newline_folded":true,"separator … [line truncated: 572 more bytes on this line]
```

**Shaped by:** `--edit-target-file`

**Caveats (stated by the binary):**

- skip that folded verification — pass it when you are about to edit again immediately skip that folded verification (the index refresh it needs is the one the next verb call would pay for anyway;

### `--edit-plan=FILE`

**Answers:** apply several edits as one transaction, described in a versioned JSON file versioned JSON multi-edit transaction: {version:1, edits:[{op,target,file?,payload}]};

op is one of replace_symbol_body, insert_before_symbol, insert_after_symbol each target takes the same forms as TARGET above (a name, an @FILE:LINE seed, a handle)

**Try it**

_Neither --dry-run nor --apply: the mode is explicit, so this refuses._

```
$ ./build/ripwire . --edit-plan=<scratch>/aux/edit_plan.json
(empty)
```

### `--dry-run | --apply`

**Answers:** the plan's mode: --dry-run preflights, --apply commits;

exactly one of the two is required the plan's explicit mode: --dry-run preflights and prints the receipt without writing, --apply commits; exactly one of the two is required. Payload paths are relative to the plan file and CONFINED to its directory: a path resolving outside it (an absolute path, a '..' escape, or a symlink pointing out) refuses, naming the path it resolved to, and the receipt's payload_path shows what each op will READ. Every target/payload/span is preflighted before any write; overlaps refuse. Apply holds sorted per-file locks and atomically renames each file, re-verifying EACH file's bytes immediately before ITS OWN write (recheck_before_each_write in the receipt) so a non-cooperating external writer is detected rather than clobbered. Prior files roll back on a later write failure or such a detection; the message says which happened and how many files it restored, and ends with the ONE call that shows the state — next: a git diff (exit-code mode) over the plan's files from <root>; exit 0 IS the claim, checked against git. A crash between file renames remains a disclosed limit.

**Try it**

_The same plan committed: per-file locks, re-verify-before-write, atomic rename, rollback on a later failure._

```
$ ./build/ripwire . --edit-plan=<scratch>/aux/edit_plan.json --apply
{"schema":"ripwire.edit-plan/v1","mode":"apply","edits":1,"files":1,"callers_union":4,"graph_ambiguous":12495,"graph_unresolved":12552,"graph_unindexed":255,"counts_floor":true,"applied":1,"atomic_files":1,"atomic_scope":"per-file","rollback_on_write_error":true,"recheck_before_each_write":true,"mul … [line truncated: 529 more bytes on this line]
{"n":"benchAdaptive","p":"bench/bench_radix_ab.cpp:157","l":[162]},
{"n":"radixSortNonNegativeFloatsDesc","p":"src/infra/sortutil.h:107","l":[116]},
{"n":"radixSortByScoreDescId","p":"src/infra/sortutil.h:122","l":[182]}],
"graph_ambiguous":12495,"graph_unresolved":12552,"graph_unindexed":255,"counts_floor":true}}]}
```

**Shaped by:** `--edit-check`

**Caveats (stated by the binary):**

- Payload paths are relative to the plan file and CONFINED to its directory: a path resolving outside it (an absolute path, a '..' escape, or a symlink pointing out) refuses, naming the path it resolved to, and the receipt's payload_path shows what each op will READ.
- A crash between file renames remains a disclosed limit.

### `--safe-delete=SYM`

**Answers:** "can I delete this?" — one call joining callers, blast radius, tests and history "can I delete this?" — ONE call composing signals the tool already computes for one already-resolved SYM: 1-hop callers=, the transitive --impact blast radius (impact_reaches=), every --uses read/write/import/call/extends site (uses=), how much of the blast radius the tested= lens covers (tested_self=/radius_tested=/radius_untested=), and --dead-code's own zero-caller/internal-linkage shape at defs=1 (dead_code_candidate=).

ambiguous_callers= names callers whose own calls include an ambiguously-resolved one (g.ambOut) — a caveat, not a count of proven-wrong edges. FACTS only: risk= names what was found — none-found (zero callers AND zero uses), untested-radius (a radius exists and none of it is test-covered), or uses-exist (a radius exists and some of it is tested) — never a go/no-go verdict; unmodelled when nothing was found for a kind used by reading or naming it (a variable, class, struct) whose uses those counts cannot see. callers_floor=/uses_floor= mark a count the index holds evidence of a miss for, and next= is the call that lists the rest. A caller row's sites_l= is its call-site LINES (p= stays the line where the caller is defined).

**Try it**

_Unknown-symbol refusal shape for --safe-delete._

```
$ ./build/ripwire . --safe-delete=DoesNotExist
(empty)
```

**Shaped by:** `--limit`

**Caveats (stated by the binary):**

- ambiguous_callers= names callers whose own calls include an ambiguously-resolved one (g.ambOut) — a caveat, not a count of proven-wrong edges.
- FACTS only: risk= names what was found — none-found (zero callers AND zero uses), untested-radius (a radius exists and none of it is test-covered), or uses-exist (a radius exists and some of it is tested) — never a go/no-go verdict;
- unmodelled when nothing was found for a kind used by reading or naming it (a variable, class, struct) whose uses those counts cannot see.

### `--slice=SYM[:VAR]`

**Answers:** trace one variable's definitions and uses inside one function NAME-BASED intra-procedural def-use slice of variable VAR inside the ONE uniquely-resolved definition SYM (statement-level def-use edges as a queryable primitive — the ARISE result, arXiv:2605.03117).

One <s l= k= t=> row per line touching VAR, ranked as the root's order="defuse" states: def-use coverage (distinct local names on the line) descending, then line — measured (docs/EVALS.md): puts a gold line first more often than a random shuffle, among these rows only — a pre-registered attempt to rank lines over the WHOLE function span did not beat chance (docs/EVALS.md); order="defuse" is not a whole-function relevance ranking. k=def|use|both| scope = a Python global/nonlocal statement, neither read nor write; t=param|decl| assign|call-arg|read|global|nonlocal = the strongest role on the line; CDATA = the trimmed source line; defs=/uses= count occurrences. JS/TS destructuring binders (`const {a, b} = o`, `[x] = arr`, destructured parameters) are locals whose def is the pattern line. A write hidden behind a call — receiver mutation, a by-reference/out-parameter, a function-like macro — is a use, never a def (stated in the legend). Bare --slice=SYM lists the sliceable locals (<v n= l= t=/> rows) so a caller can pick VAR. LIMITS in the legend, not implied: no alias analysis. REACHING DEFINITIONS are FLOW-SENSITIVE inside the definition for C-family and Python (root reach="cfg": a def is killed by the next unconditional def on every path, defs join at if/elif/else, switch, loop back-edge, try/finally, for/while-else, match, #ifdef merges) and source-order for JS/TS/Go/Java/Rust (reach="linear", nothing joins); every use row carries rd= (the lines of the defs that reach it, "-" = none). The unit is the STATEMENT (uses read the entering state, defs apply after); a nested lambda/def body, ?:, short-circuit fold into their statement, goto is untracked, global/nonlocal is tracked like a local — each disclosed in the legend. Block scopes ARE separated: a name declared twice in the definition is two variables, each row of a shadowed name carries b= (the declaration line it binds to), the root bindings=, the inventory one <v> per binding. SYM matching several definition sites REFUSES (exit 1) listing the file:name spellings that pick one, like --edit-check. Served: C/C++/ObjC (+CUDA/Metal), Python, JS/TS, Go, Java, Rust — other indexed languages refuse loudly (never an empty success). Single-root only. PREPROCESSOR (C-family): a `#if 0` body and the `#else` of `#if 1` are DEAD — dropped, the line count disclosed as preproc_rows=; every other conditional region (`#ifdef X`, `#ifndef X`, `#if defined(X)`, `#if EXPR`) is build-dependent and cannot be decided without the build's macro set, so its rows are KEPT and flagged pp="1", and a pp def never hides the unconditional def before it in a flow (both are reaching). LINE-SEEDED: --at=FILE:LINE beside --slice (or --slice=@FILE:LINE) is the ARISE (file, line[, variable]) seed — the definition sliced is the innermost one enclosing the line (a seed narrows an otherwise-ambiguous SYM; a seed enclosed by none of SYM's definitions refuses naming both). A seed line naming exactly ONE sliceable local pre-picks it (disclosed: seed= var_from="seed"); zero or several serve the inventory with seed_vars= and the candidate rows marked seed="1", never a guess. A plain identifier spec beside --at reads as the seed's VARIABLE (--slice=VAR --at=src/f.cpp:12). SINCE: --since=REV|DATE beside --slice=SYM:VAR adds a <since> child carrying the DEPENDENCE diff of that variable against the committed tree at REV — one <sd> row per added or removed STATEMENT of the variable, one <se> row per added or removed def-use edge. The unit is the STATEMENT and the key is the ROLE, never the line and never the text, so a re-wrap, a comment edit, an insertion above the definition, and a rename of an unrelated local all come back EMPTY. Empty means no def-use edge of that variable moved, never that the commit changed nothing — git diff answers the second question. status= names each way the symbol can be absent at REV, and comparable="0" says outright that no comparison was made and the emptiness is not evidence. Refused on the bare inventory: a dependence diff needs a seed variable.

**Try it**

_Bare --slice=SYM: the INVENTORY of sliceable locals (<v n= l= t=/>), so a caller can pick VAR._

```
$ ./build/ripwire . --slice=rankGraphTeleport
<!-- ripwire slice schema=ripwire.slice/v1: name-based def-use rows of one variable in one definition: <s l= k=def|use|both|scope t= [b= pp= rd=]> (rd= reaching-def lines per reach=cfg|linear), <v n= l= t=> inventory; steps=/depth= flow. at=: commit+dirty+shallow. root=: p= relative to it. sym=/lang=: the sliced definition's name and language; p= is its file:line. vars=N: sliceable local bindings in the definition, one v row each; name one to slice it. counts=as-classified: defs=/uses=/vars=/steps= count what the name classifier rowed; neither floors nor totals. -->
<slice sym="rankGraphTeleport" p="src/graph.h:7924" t="fn" lang="cpp" schema="ripwire.slice/v1" vars="14" at="f1e5c2e76" root="." counts="as-classified">
<v n="alpha" l="7924" t="param"/>
<v n="g" l="7924" t="param"/>
<v n="p" l="7924" t="param"/>
<v n="pw" l="7927" t="decl"/>
<v n="N" l="7928" t="decl"/>
<v n="teleport" l="7929" t="decl"/>
<v n="rankDouble" l="7930" t="decl"/>
<v n="run" l="7931" t="decl"/>
<v n="teleportMass" l="7934" t="decl"/>
<v n="value" l="7935" t="decl"/>
<v n="inverseMass" l="7941" t="decl"/>
<v n="value" l="7942" t="decl"/>
... [3 more line(s); run it to see the whole thing]
```

**Shaped by:** `--no-redact`, `--since`, `--slice-flow`, `--slice-depth`, `--at`

**Caveats (stated by the binary):**

- order="defuse" is not a whole-function relevance ranking.
- A write hidden behind a call — receiver mutation, a by-reference/out-parameter, a function-like macro — is a use, never a def (stated in the legend).
- LIMITS in the legend, not implied: no alias analysis.

### `--slice-flow=back|fwd|both`

**Answers:** (with --slice) follow the value flow transitively — back, forward, or in both directions TRANSITIVE cross-statement data-flow slice (modifies --slice=SYM:VAR;

refused alone or on the bare inventory — a flow needs a seed variable). Follows VALUE FLOW over reaching-definition def-use edges — a use of v reaches the last def of v in source order before it — by bounded BFS from the seed variable, the ARISE paper's own slicer semantics (arXiv:2605.03117: seed + direction, bounded BFS, stops at the function boundary; the inter-procedural half stays with --callers/--impact by the paper's own design). back = statements whose values feed the seed; fwd = statements the seed's value reaches; both = the union. Flow rows are <s l= k= t= v= d= f=>: v= the variable at that step, d= BFS depth (seed rows are depth 0), f= the line the step was reached from. steps= counts flow rows; depth= states the bound in force. LIMITS (in the legend too): name-based, no alias analysis, line-granular ROWS (a multi-statement line merges) over statement-anchored CHAINING (a multi-LINE statement chains as ONE unit), a shadowed name's bindings walk separately (never into each other's block), data dependence only — no control dependence (the guard deciding whether a def executes is never a row). both= is UNSEEDED-REDUNDANT: unioned over a function's whole variable inventory, an unseeded both reaches no line the flat rows (bare --slice=SYM lists them) do not — disclosed as flow_redundant="1", never gated. Seed it (--at=FILE:LINE) for flow to add real reach beyond the flat inventory (measured, docs/research).

**Try it**

_Forward flow: which statements the seed's value reaches, at the default depth bound._

```
$ ./build/ripwire . --slice=rankGraphTeleport:teleport --slice-flow=fwd
<!-- ripwire slice schema=ripwire.slice/v1: name-based def-use rows of one variable in one definition: <s l= k=def|use|both|scope t= [b= pp= rd=]> (rd= reaching-def lines per reach=cfg|linear), <v n= l= t=> inventory; steps=/depth= flow. at=: commit+dirty+shallow. root=: p= relative to it. sym=/lang=: the sliced definition's name and language; p= is its file:line. order=defuse: seed s rows (no v=) ranked among these rows by def-use coverage (distinct local names on the line) desc, then line; not source order, not a whole-function ranking (measured at chance — docs/EVALS.md) — flow s rows (v=) keep their (d=,l=,v=) order. counts=as-classified: defs=/uses=/vars=/steps= count what the name classifier rowed; neither floors nor totals. -->
<slice sym="rankGraphTeleport" p="src/graph.h:7924" t="fn" lang="cpp" schema="ripwire.slice/v1" var="teleport" defs="1" uses="3" reach="cfg" flow="fwd" depth="8" steps="7" order="defuse" at="f1e5c2e76" root="." counts="as-classified">
<s l="7947" k="use" t="call-arg" rd="7929">
<![CDATA[run = pageRankDouble( g.inEdges, g.wOutDeg, teleport, rankDouble, PageRankConfig{ .alpha = double( alpha ) } );]]>
</s>
<s l="7929" k="def" t="decl">
<![CDATA[std::vector<double> teleport( pw.begin(), pw.end() );]]>
</s>
<s l="7935" k="use" t="read" rd="7929">
<![CDATA[for( const double value : teleport )]]>
</s>
<s l="7942" k="use" t="read" rd="7929">
<![CDATA[for( double& value : teleport )]]>
</s>
... [22 more line(s); run it to see the whole thing]
```

**Shaped by:** `--slice-depth`

**Caveats (stated by the binary):**

- refused alone or on the bare inventory — a flow needs a seed variable).
- both= is UNSEEDED-REDUNDANT: unioned over a function's whole variable inventory, an unseeded both reaches no line the flat rows (bare --slice=SYM lists them) do not — disclosed as flow_redundant="1", never gated.

### `--slice-depth=N`

**Answers:** (with --slice-flow) bound the walk at N hops;

1..32, default 8 the --slice-flow BFS depth bound, 1..32 (default 8, always disclosed as depth= on the root). A bound that cuts a live frontier is disclosed as flow_truncated="1" — a short slice means "bounded here", never "nothing further exists". Refused without --slice-flow.

**Try it**

_--slice-depth without --slice-flow is refused loudly rather than silently ignored._

```
$ ./build/ripwire . --slice-depth=3
(empty)
```

**Caveats (stated by the binary):**

- A bound that cuts a live frontier is disclosed as flow_truncated="1" — a short slice means "bounded here", never "nothing further exists".
- Refused without --slice-flow.

### `--at=FILE:LINE`

**Answers:** name the definitions enclosing one line, outermost first — when you hold a location, not a name the ENCLOSING-DEFINITION CHAIN at one location (1-based line), outermost->innermost — for when you hold a compiler error / diff hunk / stack frame, not a name.

<s n= t= l= el=/> rows, indexed definitions only; sym= names the innermost. The SAME seed composes into any SYM selector as @FILE:LINE (--callers=@src/f.cpp:120, --expand=@..., --edit-check=@..., --slice=@FILE:LINE:VAR, --replace-symbol-body=@... and the other edit TARGETs, ...) and resolves to that innermost definition — the no-name half of the file:line:name grammar. The NAME-scan verbs --mentions/--owners rebind a seed to that definition's name and answer, disclosing sym=. Beside --slice, the at flag is that verb's LINE SEED instead of a competing verb (see --slice). A malformed seed, an ambiguous or unmatched path, a line past EOF, a line inside no indexed definition, or two disjoint definitions sharing the line each REFUSE with a specific diagnosis (exit 1) — never a guess, never an empty chain.

**Try it**

_Hold a LOCATION, not a name: the enclosing-definition chain at FILE:LINE (a compiler error, a diff hunk, a stack frame), outermost -> innermost._

```
$ ./build/ripwire . --at=src/graph.h:7926
<!-- ripwire at schema=ripwire.at/v1: enclosing-definition chain at p=:l=: sym= innermost, chain= outermost-first, <s n= t= l= el=> spans. root=: p= relative to it. -->
<at schema="ripwire.at/v1" p="src/graph.h" l="7926" sym="rankGraphTeleport" chain="1" root=".">
<s n="rankGraphTeleport" t="fn" l="7924" el="7952"/>
</at>
```

**Shaped by:** `--slice`, `--slice-flow`

**Caveats (stated by the binary):**

- name the definitions enclosing one line, outermost first — when you hold a location, not a name the ENCLOSING-DEFINITION CHAIN at one location (1-based line), outermost->innermost — for when you hold a compiler error / diff hunk / stack frame, not a name.
- A malformed seed, an ambiguous or unmatched path, a line past EOF, a line inside no indexed definition, or two disjoint definitions sharing the line each REFUSE with a specific diagnosis (exit 1) — never a guess, never an empty chain.

### `--pr-context[=BASEREF]`

**Answers:** build the review evidence for a diff: per file, its callers, blast radius, tests and owners no-LLM review-evidence bundle for the diff (working-tree, or vs BASEREF): per changed file, its symbols + callers + blast radius + affected tests + co-change partners + owners.

The bundle is BUDGETED by default (8000 tokens, budget_default="1" on the root; --token-budget=N or --max-tokens=N set it explicitly): per-file structural counts survive first, the deep detail (caller/co-change lists, per-symbol rows) trims deepest-first, truncated= names what was dropped and est_tokens= reports the fit. When even the structural floor of every changed file exceeds the budget, the FILES (blast-radius order) are windowed: shown=/capped=/total=/ next_offset= disclose the cut and next= pastes the next page (--offset=N / --limit=N window them explicitly). ANCHORING: the BASEREF form diffs against merge-base(BASEREF,HEAD), never BASEREF's tip — "what did THIS work change since it forked", not "how do the two trees differ today". base_moved= counts the paths BASEREF moved since the fork that this work never touched (excluded, not silently); anchor="ref-tip-two-dot" = no merge-base (unrelated history). direction= always names the SIDE you are reading, and a no-ref-work row fires when BASEREF's tip IS the merge base -- it carries no divergent work, so every row is HEAD's.

**Try it**

_No-LLM review-evidence bundle for the working-tree diff (clean tree = empty)._

```
$ ./build/ripwire . --pr-context
<!-- ripwire pr-context schema=ripwire.pr-context/v1: review bundle per changed file vs base=: symbols, callers, blast radius, tests, owners. counts_floor=1: every count is a FLOOR, never a total. graph_ambiguous=/graph_unresolved=: resolver gauge. graph_unindexed=N: N files no grammar could read (the map header's unindexed=); their calls raise neither gauge. est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. truncated=: what the trim ladder dropped to fit budget_tokens= (budget-floor-exceeded: still over). direction=: side reviewed: worktree-since-head, head-since-fork or head-since-ref-tip. skipped_mode_only=N: mode-only (chmod) diffs left out of the changed files; renames stay in. trim_level=0-4: trim ladder step taken to fit budget_tokens= (0 none, 4 counts only); raise token-budget. budget_default=1: the default 8000-token budget applied (no token-budget or max-tokens given). files=N: changed files in the diff (shown= of them listed). -->
<pr-context schema="ripwire.pr-context/v1" base="working-tree" root="." direction="worktree-since-head" files="0" skipped_mode_only="0" budget_tokens="8000" est_tokens="584" trim_level="0" truncated="none" budget_default="1" at="f1e5c2e76" graph_ambiguous="12495" graph_unresolved="12552" graph_unind … [line truncated: 28 more bytes on this line]
<!-- no changed files in the index (clean tree, or the diff touched only non-indexed files) -->
</pr-context>
```

**Shaped by:** `--test-gate`, `--from-trace`, `--limit`, `--map-diff`, `--index-out`

**Caveats (stated by the binary):**

- --token-budget=N or --max-tokens=N set it explicitly): per-file structural counts survive first, the deep detail (caller/co-change lists, per-symbol rows) trims deepest-first, truncated= names what was dropped and est_tokens= reports the fit.
- When even the structural floor of every changed file exceeds the budget, the FILES (blast-radius order) are windowed: shown=/capped=/total=/ next_offset= disclose the cut and next= pastes the next page (--offset=N / --limit=N window them explicitly).
- ANCHORING: the BASEREF form diffs against merge-base(BASEREF,HEAD), never BASEREF's tip — "what did THIS work change since it forked", not "how do the two trees differ today".

### `--merge-scout=REF[,REF...]`

**Answers:** compare branches before landing: which symbols two refs both touched, and the merge order read-only cross-branch overlap: for each REF, the symbols it changed vs its merge-base with HEAD (git-archive TEMP copies — never checked out, never mutates a ref);

the dirty working tree joins as an implicit extra arm. Pairwise: a changed symbol on TWO arms is a same-symbol conflict, two arms touching different symbols in the same file is a textual risk; <landing order=...> is the fewest-conflicts-first greedy land order (ties: ref name asc). An unresolvable REF refuses loudly (exit 1, names the ref) before any archive work. ANCHORING: every arm is diffed against its OWN merge-base with HEAD, never against live HEAD — a file an arm never opened can never show up because the live line moved. head_conflicts= is what that anchor hides, kept as its own row class: symbols this arm changed that the LIVE LINE also changed since the arm forked (HEAD is not an arm, so no pairwise comparison can see it). Single-root only.

**Try it**

_Pairwise cross-arm conflict sites + suggested landing order (any committish sharing a merge base with HEAD works as an arm; one that does not is reported ok="0", never compared)._

```
$ ./build/ripwire . --merge-scout=HEAD~2,HEAD~1
<!-- ripwire merge-scout schema=ripwire.merge-scout/v1: cross-branch overlap of arms= refs: <arm ref= base= changed= head_conflicts=>, <pair a= b= conflicts= risks=>, <landing order=>. at=: commit+dirty+shallow. head=: the HEAD commit, bare 9-hex sha (at= adds +dirty). ok=1 on an arm row means the comparison RAN, so changed=/head_conflicts= are real and may legitimately be 0 (an empty but materialized tree is a real index); ok=0 means it did not run at all. no-work note=: arm compared and has no divergent work vs its merge base, so no landing slot. -->
<merge-scout schema="ripwire.merge-scout/v1" arms="2" head="f1e5c2e76" at="f1e5c2e76">
<arm ref="HEAD~2" base="f51c2d7ea" ok="1" changed="0" head_conflicts="0">
<no-work note="no divergent work vs merge-base — see --stray-content"/>
</arm>
<arm ref="HEAD~1" base="7dd380a9d" ok="1" changed="0" head_conflicts="0">
<no-work note="no divergent work vs merge-base — see --stray-content"/>
</arm>
<pair a="HEAD~2" b="HEAD~1" conflicts="0" risks="0"/>
<landing order=""/>
</merge-scout>
```

**Shaped by:** `--plan-lanes`, `--plan`

**Caveats (stated by the binary):**

- compare branches before landing: which symbols two refs both touched, and the merge order read-only cross-branch overlap: for each REF, the symbols it changed vs its merge-base with HEAD (git-archive TEMP copies — never checked out, never mutates a ref);
- An unresolvable REF refuses loudly (exit 1, names the ref) before any archive work.
- ANCHORING: every arm is diffed against its OWN merge-base with HEAD, never against live HEAD — a file an arm never opened can never show up because the live line moved.

### `--plan-lanes=N --task=GOAL`

**Answers:** plan lanes BEFORE any code: which of N parallel worktrees would collide, and how to land them PRE-HOC lane plan: BEFORE a line is written, if this task is split across N isolated worktrees (N=2..16), which lanes would COLLIDE and in what order should they land.

Where --merge-scout says "these branches already conflict", this says "these lanes WOULD conflict if assigned this way" — no ref to resolve, no archive, no re-ingest. JSON on stdout, always (redirect it: > .ripwire_lanes.json); ripwire writes no file. Exit 0 whenever a plan was produced, INCLUDING when conflicts are predicted (conflicts are data, and the landing order exists to handle them); exit 1 only for refusals. A claim keys on path+scope+name, never on id= (id degrades to a bare NAME when no scope was captured, so free functions in different files would collide); id= is carried per row for addressability, null when it would be bare, with id_addressable saying so. Three separate pair classes: conflicts[] (same claim key on both lanes — git will fight), same_file_risk[] (different keys, same file, aggregated per file), contract_touch[] (one lane's claim sits in another's blast radius — an adaptation, NOT a merge conflict). The conflict test runs on CLAIMS, never on blast radii. warnings[] carries every honest limit in band with a stable code. Each lane also carries an advisory execution object: the current Codex model + reasoning effort, selecting rule, exact structural signals and caveats under policy=codex-lane/v1. basis=structural-only: it does NOT understand task semantics, runtime behavior or security sensitivity; the orchestrator must override those cases. Single-root only. AUTO-CARVE SPLITS THE RANKED SURFACE, NOT YOUR SENTENCE: if your task has enumerable parts, use --brief and write one line per part.

**Try it**

_Out-of-range refusal shape for the lane count._

```
$ ./build/ripwire . --plan-lanes=99 --task=x
(empty)
```

**Shaped by:** `--legend`, `--json`

**Caveats (stated by the binary):**

- Exit 0 whenever a plan was produced, INCLUDING when conflicts are predicted (conflicts are data, and the landing order exists to handle them);
- A claim keys on path+scope+name, never on id= (id degrades to a bare NAME when no scope was captured, so free functions in different files would collide);
- Three separate pair classes: conflicts[] (same claim key on both lanes — git will fight), same_file_risk[] (different keys, same file, aggregated per file), contract_touch[] (one lane's claim sits in another's blast radius — an adaptation, NOT a merge conflict).

### `--plan-lanes --brief=FILE`

**Answers:** the explicit form of the above: one line per lane in FILE, N = the line count the explicit form of the above: one non-blank line per lane, N = the line count.

Each line is ranked on its own — no community carve, no bin packing — so the lane boundaries are the ones you wrote. This is the mode whose precision is defensible; prefer it when you can. Lane isolation is a QUALITY argument, not a speed one (CAID, arXiv 2603.21489: 63.3% vs 55.5% shared, largest gains on weaker lane models — and wall clock got WORSE).

**Try it**

_NEW VERB, explicit form: one line per lane, lane boundaries are the ones you wrote (the defensible mode)._

```
$ ./build/ripwire . --plan-lanes --brief=<scratch>/aux/lanes_brief.txt
add a --since filter to the doc-drift verb
add the CLI parse arm and help text for the new filter
write regression tests for the new filter
```

**Shaped by:** `--legend`, `--json`

**Caveats (stated by the binary):**

- Lane isolation is a QUALITY argument, not a speed one (CAID, arXiv 2603.21489: 63.3% vs 55.5% shared, largest gains on weaker lane models — and wall clock got WORSE).

### `--stray-content[=SUBSTR]`

**Answers:** "where does this content live?" across every branch — what `git cherry` cannot answer "where does this content live?" across ALL branches — the question `git cherry` cannot answer.

Per local ref (SUBSTR filters ref names): the lines its own divergent work AUTHORED vs its merge-base with HEAD that the live line does NOT have, and a verdict. v="unmerged" = genuinely absent; v="superseded" = the live line removed the SAME base code this ref removed, i.e. it re-implemented the work (git cherry still calls that commit unmerged, forever); v="merged" refs are omitted. Every row shows its raw del=/redone=/sim= evidence, so a verdict is auditable, not a black box. v="unknown" (ok="0") = the ref has NO merge-base with HEAD, so it could not be analysed at all — a shallow clone (the actions/checkout DEFAULT) puts every ref here. It is NOT a claim the work is merged: it is the absence of an answer, counted in its own unknown= bucket so unmerged+superseded+merged+unknown always reconciles with refs=, and surfaced by --plan as an <undetermined> row rather than silently dropped. LIMITS: line-granular, not semantic — a rewrite that shares no deleted base line reads as unmerged; binary/oversized blobs are reported diffable="0" with no counts. Read-only (cat-file/diff/ls-tree); single-root only.

**Try it**

_Which refs of the `lane/` ref family still hold divergent authored work vs HEAD, with verdicts._

```
$ ./build/ripwire . --stray-content=lane/
<!-- ripwire stray-content schema=ripwire.stray-content/v1: per local ref, lines/symbols NOT in HEAD: <ref ok= v= base= stray=>; v=unknown = no merge base. at=: commit+dirty+shallow. head=: the HEAD commit, bare 9-hex sha (at= adds +dirty). head_ref=: HEAD's branch (HEAD when detached); that branch itself is not scanned. refs=N: local branches scanned (refs/heads only); unmerged + superseded + merged + unknown = refs. blobs=N: distinct git blobs read for the sweep. unmerged=N: refs whose authored work the live line genuinely lacks. superseded=N: refs whose work the live line re-implemented (removed the same base code). merged=N: refs whose work HEAD already has; omitted from the rows. name=: the local branch. tip=: the branch tip commit (9 hex). date=: the tip's committer date, YYYY-MM-DD. files=N: files with stray lines; rows capped at 12, a more element counts the rest (detail=1 lists all). ref superseded=N>: of this ref's stray= lines, those in files the live line re-implemented. authored=N: lines this ref authored in the file vs its merge base. del=N: base lines this ref removed (0 = pure addition). redone=N: of del=, the base lines HEAD removed too (the supersession evidence). sim=: minhash containment, 0 to 1, of the ref's blob in HEAD's (pure-addition evidence). head-touched=1: the live line changed this path since the merge base. more files=N: N more file rows of this ref withheld; shown + N = the ref's files=; detail=1 lists all. unknown=N: refs that could not be analysed (v=unknown, e.g. no merge base); never counted merged. -->
<stray-content schema="ripwire.stray-content/v1" head="f1e5c2e76" head_ref="HEAD" refs="107" blobs="452" unmerged="21" superseded="0" merged="86" unknown="0" filter="lane/" at="f1e5c2e76">
<ref name="lane/arise-result" tip="13292db7a" date="2026-09-23" base="60b65f026" ok="1" v="unmerged" stray="16331" files="18" superseded="55">
<file p="bench/slice/results/arise_line_rank_prereg/narrowpool-results.json" v="unmerged" stray="8629" authored="8629" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p="bench/slice/results/arise_line_rank_prereg/results.json" v="unmerged" stray="3810" authored="3810" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p="bench/slice/results/arise_line_rank_prereg/scorer-results.json" v="unmerged" stray="1213" authored="1213" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p="docs/research/arise-line-ranking-prereg.md" v="unmerged" stray="625" authored="625" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p="bench/slice/score_arise_linerank.py" v="unmerged" stray="537" authored="537" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p="bench/slice/run_slice_linerecall_r3.py" v="unmerged" stray="326" authored="326" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p="test/slicerank_unit.cpp" v="unmerged" stray="258" authored="258" del="0" redone="0" sim="0.00" head-touched="0"/>
<file p="bench/slice/score_arise_narrowpool.py" v="unmerged" stray="199" authored="199" del="0" redone="0" sim="0.00" head-touched="0"/>
... [20 more line(s); run it to see the whole thing]
```

**Shaped by:** `--plan`, `--abi`, `--whereis`, `--limit`, `--eval-stray`

**Caveats (stated by the binary):**

- "where does this content live?" across every branch — what `git cherry` cannot answer "where does this content live?" across ALL branches — the question `git cherry` cannot answer.
- Every row shows its raw del=/redone=/sim= evidence, so a verdict is auditable, not a black box.
- It is NOT a claim the work is merged: it is the absence of an answer, counted in its own unknown= bucket so unmerged+superseded+merged+unknown always reconciles with refs=, and surfaced by --plan as an <undetermined> row rather than silently dropped.

### `--plan`

**Answers:** (with --stray-content) which branches still hold real work, and in what order to land them (with --stray-content) "of all my branches, which still hold REAL work, and in what order should I land them?" Selects the refs --stray-content calls v="unmerged", DROPS the v="superseded" ones (landing them would re-do work the live line already did — the exact waste --stray-content exists to catch), and feeds the survivors to --merge-scout's existing pairwise-conflict + fewest-conflicts-first landing-order machinery — composition only, neither verb's logic is reimplemented.

<ref scouted="0"> is unmerged work NOT fed to merge-scout THIS run (a cost bound, not a verdict); <excluded> names the superseded drops and why. COST: --stray-content is a cheap per- blob sweep, but --merge-scout is per-ARM (git-archive + full ingest of each ref's tree) — measured 27s for 9 unmerged refs on a 35-branch real C++ repo (~3s/ref). kMaxPlanScout (12) bounds it to the top-N unmerged refs BY STRAY SIZE; --detail lifts the bound to scout everything. This is an EXPLICIT opt-in "before you land" call, not a per- question one — the default map's ~0.10s path is untouched. Read-only; single-root only.

**Try it**

_Select the genuinely-unmerged refs of the `lane/` ref family and feed them to merge-scout for a landing order (a fully merged selection yields an empty landing set — still a measurement, disclosed on the root)._

```
$ ./build/ripwire . --stray-content=lane/ --plan
<!-- ripwire landing-plan schema=ripwire.landing-plan/v1: stranded-work landing order across refs, fewest conflicts first. at=: commit+dirty+shallow. -->
<landing-plan schema="ripwire.landing-plan/v1" head="f1e5c2e76" refs="107" unmerged="21" superseded="0" merged="86" undetermined="0" scouted="12" bounded="9" scout-ok="1" at="f1e5c2e76">
<ref name="lane/arise-result" v="unmerged" stray="16331" files="18" scouted="1"/>
<ref name="lane/margin-rescore" v="unmerged" stray="13920" files="12" scouted="1"/>
<ref name="lane/served-syms-result" v="unmerged" stray="6345" files="8" scouted="1"/>
<ref name="lane/orient-narrow-v3" v="unmerged" stray="3270" files="46" scouted="1"/>
<ref name="lane/for-howitworks-067" v="unmerged" stray="3247" files="38" scouted="1"/>
<ref name="lane/m1-lookback-harness" v="unmerged" stray="3164" files="14" scouted="1"/>
<ref name="lane/orient-map-067" v="unmerged" stray="2469" files="40" scouted="1"/>
<ref name="lane/served-syms-prereg" v="unmerged" stray="2134" files="4" scouted="1"/>
<ref name="lane/crossctx-external-prereg" v="unmerged" stray="2054" files="6" scouted="1"/>
<ref name="lane/arise-line-ranking" v="unmerged" stray="1538" files="7" scouted="1"/>
<ref name="lane/owner-hop-068" v="unmerged" stray="1517" files="27" scouted="1"/>
<ref name="lane/research-abstention" v="unmerged" stray="898" files="2" scouted="1"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--stray-content`, `--legend`, `--json`

**Caveats (stated by the binary):**

- <ref scouted="0"> is unmerged work NOT fed to merge-scout THIS run (a cost bound, not a verdict);
- This is an EXPLICIT opt-in "before you land" call, not a per- question one — the default map's ~0.10s path is untouched.

### `--abi`

**Answers:** (with --stray-content) the cross-branch ABI-break gate for a struct that changed shape (with --stray-content) the CROSS-BRANCH ABI-BREAK gate `--layout` and `--stray-content` each miss alone: a branch that adds one field to a dual-compile uniform struct merges textually clean and reads as a harmless "+1 field" to a line-granular diff.

SCOPE is what each ref AUTHORED — the paths `git diff base..tip` reports against its own MERGE BASE, never `diff HEAD..tip`. A file the branch never opened cannot be a break the branch introduced, and on a long-lived shared tree that one distinction is nearly all the noise: measured on a 35-branch C++ repo, 487 drift rows fell to 4 (the rest were the live line's own evolution reflected back at the reader). For each authored path this runs --layout's OWN field-offset arithmetic lexically on that ref's git blob (never indexed) and compares it against HEAD's computed fields. LISTED by default: kind="drift" (the byte contract differs — the only kind that exits 2), kind="unknown" (a ref-side copy this module could not model; its caveats ride along in ref_caveat and it is NEVER reported as unchanged), kind="absent" (the ref does not define the struct at that path at all). EXCLUDED by default, each on its own header counter — add --detail=N to print them: kind="rename" (identical slots and field TYPES under different field NAMES: every byte stayed where it was, so it is a source change, not a byte-contract one — note a same-type field REORDER is lexically indistinguishable from a rename and lands here too), kind="spelling"/"stub" (--layout's own harmless cases), and kind="head-moved" (the ref's copy equals its own merge-base copy, so the LIVE LINE changed, not the branch). head_only= counts candidate sites on paths only the live line touched; unmodelable= counts sites skipped because HEAD's own copy carries no baseline; rows=/ shown=/dropped=/excluded= reconcile the body against the sweep (capped="0|1" is the tool-wide truncation BIT; dropped= is the count). Nothing is dropped without a number. Structs that match are omitted (report only differences); a ref with no rows at all counts into quiet=, a ref whose every row is an excluded kind counts into excluded_refs= (and prints under --detail=N), and broken_refs= counts REFS (not rows). Rows are ranked by SIZE DELTA so the biggest contract break leads, capped at 12 per ref with an explicit <more structs="N"/>; --detail=N lifts the cap. LIMITS: HEAD's own side is the WORKING TREE's --layout answer, not a re-fetched git blob at HEAD's commit (the same scope --layout itself claims); a nested field's OWN type resolves through HEAD's copy even when the ref also changed it; the ref-side locator is index-free and file-scope (one namespace deep) only, so a struct nested in a class or an extern "C" block reads absent rather than compared; a HEAD-side struct --layout itself cannot model at all (pragma pack, bitfields, ...) has no baseline and is counted in unmodelable=, not compared; the authorship anchor is per PATH, so a branch changing struct S in one file while the live line changes S's mirror in another is a merge hazard only `--layout=S` on the merged result can see. Read-only; single-root only.

**Try it**

_Cross-branch ABI-break gate over the `lane/` ref family: struct byte-contract drift on each ref's AUTHORED paths — exit 2 when any drift row is found (the only kind that gates), 0 when the compared refs are clean, and exit 1 if the --stray-content filter matches no ref at all._

```
$ ./build/ripwire . --stray-content=lane/ --abi
<!-- ripwire abi schema=ripwire.abi/v1: contract diff of the indexed symbols between two refs: added/removed/changed signatures. window: shown= capped= (capped=1 cut). at=: commit+dirty+shallow. root=: p= relative to it. -->
<abi schema="ripwire.abi/v1" head="f1e5c2e76" head_ref="HEAD" refs="107" candidates="1508" compared="223" blobs="110" rows="56" shown="3" capped="0" dropped="0" excluded="53" head_only="92863" unmodelable="691" unrelated="0" broken_refs="0" quiet="98" excluded_refs="6" at="f1e5c2e76" unknown="1" abs … [line truncated: 33 more bytes on this line]
<ref name="lane/orient-map-067" tip="6a7046111" date="2026-10-03" rows="8" shown="1" capped="0" excluded="7" head_only="668" absent="1" head-moved="7">
<struct n="ObjSpan" p="src/jsrunner.h" l="170" kind="absent" head_size="16">
</struct>
</ref>
<ref name="lane/orient-narrow-v3" tip="eb88882f1" date="2026-10-03" rows="10" shown="1" capped="0" excluded="9" head_only="621" absent="1" head-moved="9">
<struct n="ObjSpan" p="src/jsrunner.h" l="170" kind="absent" head_size="16">
</struct>
</ref>
<ref name="lane/owner-hop-068" tip="f01bdd78d" date="2026-10-08" rows="2" shown="1" capped="0" excluded="1" head_only="180" unknown="1" head-moved="1">
<struct n="CalleeCallsSink" p="src/serialize.h" l="6280" kind="unknown" head_size="48">
<ref_caveat k="unknown-type" d="cappedNext: std::string_view"/>
</struct>
... [2 more line(s); run it to see the whole thing]
```

**Caveats (stated by the binary):**

- SCOPE is what each ref AUTHORED — the paths `git diff base..tip` reports against its own MERGE BASE, never `diff HEAD..tip`.
- A file the branch never opened cannot be a break the branch introduced, and on a long-lived shared tree that one distinction is nearly all the noise: measured on a 35-branch C++ repo, 487 drift rows fell to 4 (the rest were the live line's own evolution reflected back at the reader).
- For each authored path this runs --layout's OWN field-offset arithmetic lexically on that ref's git blob (never indexed) and compares it against HEAD's computed fields.

### `--whereis=SYM`

**Answers:** find which branch's tree defines or mentions SYM, HEAD first which REF's tree defines or mentions SYM — HEAD first, then every local branch, with on-head="0" naming the case the verb exists for: content that lives only on a branch.

Each distinct blob is read ONCE (content-addressed), so N branches cost ~one tree. kind="def" on a HEAD row is the PARSED index's answer (head_labels="index"); on a REF row it is a LEXICAL heuristic — ref blobs are raw text, never ingested, so a doc quoting a signature still reads as a definition. head_labels="lexical" ⇒ HEAD fell back to that heuristic too (no indexed def of the name, or a working tree that drifted from HEAD). refs_scanned= is the SCAN denominator (refs read besides HEAD), not a matched count. Read-only; single-root only. A checkout that differs from HEAD is read from disk: each changed path's rows say ref="worktree" and replace HEAD's, at= gains +dirty, and worktree= says whether every one was read. LIMITS: a TREE scan finds only what some ref STILL carries, so hits="0" alone cannot tell a name this repo never had from one it deleted, and content dropped by every tree is invisible. Add --with-history: a <fate> row then says v="never" or v="removed" with the commit, date and file that removed it. Remote-tracking refs are excluded (they mirror local ones); refs are capped, narrow with --stray-content=SUBSTR. LISTING: by default only the kind="def" rows are listed and the kind="ref" rows counted in one <refs count=N next=...> element, when that page lists MORE definitions than the --whereis-listing=all page under the row cap, or the same ones in strictly fewer bytes; otherwise every hit is listed.

**Try it**

_Which ref's tree defines or mentions SYM — HEAD first, then every local branch. The default lists the kind="def" rows (here the first 60, most on branches, each carrying tip= and date=) and counts the references in <refs count= next=>: on this symbol HEAD's references would fill the 60-row cap before the branch definitions arrive, so the whole list (below) shows fewer definitions, and the default serves the page that shows more of them, whatever its bytes._

```
$ ./build/ripwire . --whereis=rankGraphTeleport
<!-- ripwire whereis schema=ripwire.whereis/v1: every LOCAL ref whose tree holds sym= (refs_scanned=, blobs=), HEAD first: <hit ref= tip= date= p= l= kind= t=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). at=: commit+dirty+shallow. next=: the one pasteable follow-up. hits=N: occurrences in HEAD plus every scanned local ref's full tree (the total rows). on-head=1|0: whether HEAD's tree holds it; 0 beside hits = it lives only on a branch. head_labels=index: HEAD kind= from the parsed index; lexical: text heuristic (non-HEAD rows always are). hit test_local=1: a definition in a test scope or under a test/bench/fixture path, ordered after the production definitions (only when both exist; nothing dropped). more hits=N: rows after this page; page on with offset=next_offset. listing=defs|refs: only those kind= rows listed; under defs <refs count=N next=> counts the kind=ref rows and next= lists them; the window counts listed rows; default: defs if it lists more defs than all, else if shorter; a def the parser does not model (define_method, setattr, assignment) is a counted ref. head_date=: a hit without tip= date= has tip= at=, date= this. -->
<whereis schema="ripwire.whereis/v1" sym="rankGraphTeleport" on-head="1" refs_scanned="141" blobs="6169" hits="345402" head_labels="index" shown="60" capped="1" total="10247" has_more="1" next_offset="60" offset="0" limit="0" listing="defs" head_date="2026-10-08" at="f1e5c2e76">
<hit ref="HEAD" p="src/graph.h" l="7924" kind="def" t="inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="arm/for-howitworks-067-f2add" tip="abcbd8b7f" date="2026-10-02" p="src/graph.h" l="4645" kind="def" t="inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="arm/for-howitworks-067-f2add" tip="abcbd8b7f" date="2026-10-02" p="src/main.cpp" l="1434" kind="def" t="rw::RankedGraph    ranked = isDecay ? rankGraphTeleport( d.g, churnDecayTeleportWorkspace( rootDirs, d.ing, &amp;hasChurnEvidence ) )"/>
<hit ref="arm/for-howitworks-067-f2add" tip="abcbd8b7f" date="2026-10-02" p="bench/recalleval/snapshot.mdpack" l="14490" kind="def" test_local="1" t="&lt;hit ref=&quot;HEAD&quot; tip=&quot;bc09d0260&quot; date=&quot;2026-08-01&quot; p=&quot;test/crossrefcheck.sh&quot; l=&quot;234&quot; kind=&quot;re … [line truncated: 191 more bytes on this line]
<hit ref="arm/for-howitworks-067-f2add" tip="abcbd8b7f" date="2026-10-02" p="bench/recalleval/snapshot.mdpack" l="14935" kind="def" test_local="1" t="&lt;![CDATA[inline std::vector&lt;float&gt; rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
... [24 more line(s); run it to see the whole thing]
```

**Shaped by:** `--whereis-listing`, `--with-history`, `--limit`

**Caveats (stated by the binary):**

- on a REF row it is a LEXICAL heuristic — ref blobs are raw text, never ingested, so a doc quoting a signature still reads as a definition.
- head_labels="lexical" ⇒ HEAD fell back to that heuristic too (no indexed def of the name, or a working tree that drifted from HEAD).
- refs_scanned= is the SCAN denominator (refs read besides HEAD), not a matched count.

### `--whereis-listing=WHICH`

**Answers:** with --whereis: which rows to list, defs, refs or all (default: more defs, else shorter).

The default lists defs when that page lists MORE definitions than all under the same row cap (references can fill a capped all page before the branch definitions arrive), whatever its bytes; when both list the same definitions, defs only when strictly shorter in bytes, else all (a tie lists all). defs lists every kind="def" row and COUNTS the kind="ref" rows in one <refs count=N next=...> element whose next= lists exactly them (refs). kind="def" is the parser's label: a definition it does not model (define_method, setattr, a name bound by assignment) is a counted ref. With no ref row, or no def row (the mentions are then the answer), every hit is listed and the root carries no listing=. all lists every row, the whole hit list. shown=/capped= and --limit/--offset window the LISTED rows; hits= counts every row. Refused without --whereis, and on an unknown value.

**Try it**

_The whole hit list asked for by name: under the same 60-row cap HEAD's references fill the list, so it shows far fewer definitions (here HEAD's one) than the default above (here 60). The default serves the all page only when it shows the same definitions as the defs page in strictly fewer bytes (a tie serves it too)._

```
$ ./build/ripwire . --whereis=rankGraphTeleport --whereis-listing=all
<!-- ripwire whereis schema=ripwire.whereis/v1: every LOCAL ref whose tree holds sym= (refs_scanned=, blobs=), HEAD first: <hit ref= tip= date= p= l= kind= t=>. window: shown= total= capped= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). at=: commit+dirty+shallow. hits=N: occurrences in HEAD plus every scanned local ref's full tree (the total rows). on-head=1|0: whether HEAD's tree holds it; 0 beside hits = it lives only on a branch. head_labels=index: HEAD kind= from the parsed index; lexical: text heuristic (non-HEAD rows always are). more hits=N: rows after this page; page on with offset=next_offset. head_date=: a hit without tip= date= has tip= at=, date= this. -->
<whereis schema="ripwire.whereis/v1" sym="rankGraphTeleport" on-head="1" refs_scanned="141" blobs="6169" hits="345402" head_labels="index" shown="60" capped="1" total="345402" has_more="1" next_offset="60" offset="0" limit="0" head_date="2026-10-08" at="f1e5c2e76">
<hit ref="HEAD" p="src/graph.h" l="7924" kind="def" t="inline RankedGraph rankGraphTeleport( const Graph&amp; g, const std::vector&lt;float&gt;&amp; p, float alpha = 0.85f )"/>
<hit ref="HEAD" p=".ripwire_quality_acks" l="1276" kind="ref" t="ack short-horizon-churn 89b3fd14c192c899 116 cid=b6e271ab92996f75 by=src/* macro-vocabulary rename (VERIFY/DEGRADED_PATH_ALERT family -&gt; ASSUME/EXPECTS/ENSURES/DASSERT/UNREACHABLE/VALIDATE/DISCLOSE): identifier-only churn across 179 … [line truncated: 586 more bytes on this line]
<hit ref="HEAD" p="present/deck5_ripwire_build.js" l="1157" kind="ref" t="s.addText(&quot;$ ripwire . --callers=rankGraphTeleport&quot;, { x: 8.68, y: 2.1, w: 3.8, h: 0.3, fontFace: MONO, fontSize: 10, color: MUTED, margin: 0 });"/>
<hit ref="HEAD" p="present/deck5_ripwire_build.js" l="1159" kind="ref" t="{ text: &quot;&lt;callers of=\&quot;rankGraphTeleport\&quot;\n  defs=\&quot;1\&quot; count=\&quot;7\&quot; &quot;, options: { color: TEXT } },"/>
<hit ref="HEAD" p="present/deck5_ripwire_build.js" l="1173" kind="ref" t="&quot;- The --callers example: `ripwire . --callers=rankGraphTeleport` answered defs=\&quot;1\&quot; count=\&quot;6\&quot; counts_floor=\&quot;1\&quot;, with runEval and rankGraph as its first two rows, on main 40a1895b. On ma … [line truncated: 260 more bytes on this line]
... [24 more line(s); run it to see the whole thing]
```

**Shaped by:** `--whereis`

**Caveats (stated by the binary):**

- The default lists defs when that page lists MORE definitions than all under the same row cap (references can fill a capped all page before the branch definitions arrive), whatever its bytes;
- shown=/capped= and --limit/--offset window the LISTED rows;
- Refused without --whereis, and on an unknown value.

### `--flags[=SUBSTR]`

**Answers:** the dark-content dashboard: what is built but switched OFF in this repo the dark-content dashboard: what is BUILT but OFF in this repo.

Harvests all three gate patterns — #ifndef/#define header gates, CMake option(), and getenv() reads — and reports gate, kind (compile/cmake/env), default, the size of the code it guards (#if regions and their LOC), and its read sites. When a name is BOTH a header gate and a CMake option the CMake default WINS (that is what the build actually passes) and both sites are listed. A gate whose default IS another gate's name (#define F_WALLS F_ALL) is resolved: it inherits the master's default and rolls its guarded size up, so a master switch shows <aliases n=..> rather than a misleading loc="0". LIMITS: lexical, not preprocessed — a gate computed at configure time or set only in a CI script shows its in-repo default, never the value your build used. A gate needs a VALUE (#ifndef F / #define F 0) to be a gate: valueless pairs are include guards and are excluded, and a gate read as a VALUE (constexpr bool k = F != 0, then if constexpr) reports regions="0" honestly — its code is a C++ branch, not an #if region. Pair it with --flip=NAME below to size ONE gate instead of listing them all.

**Try it**

_The dark-content dashboard: gates BUILT but OFF. CHANGED: no longer invents gates from comments/heredocs, so the count only reflects real ifndef/define, CMake option(), and getenv gates._

```
$ ./build/ripwire . --flags
<!-- ripwire flags schema=ripwire.flags/v1: BUILT but DARK: <gate name= kind=compile|cmake|env default= dark= regions=/loc=(#if only) reads= p= l=> with <read p= l=> sites. reads_capped=: 1 = cut. next=: the one pasteable follow-up. gates=/dark_gates=: gate rows (never cut) / those whose default keeps the guarded code out of the build. compile=/cmake=/env=: gates by kind: ifndef/define header gate, CMake option(), getenv read. files=N: files this verb scanned for gates (source + CMakeLists), wider than the map's corpus. -->
<!-- ROWS AND WHAT IS NEVER CUT: the gate rows ARE the answer this verb was asked for and are never windowed, capped or paged, and gates/dark_gates/compile/cmake/env/files on the root plus regions/loc/reads/dark on every gate are counted over the FULL set before any cap exists. What pages is the read SITES under one gate, at 8 a gate by default: a gate whose sites were cut says shown_reads= (the rows this run printed) with reads_capped="1", against the reads= total already on the same element, and the more reads= child keeps naming the remainder. The pair is emitted ONLY on a gate that was cut, never as a capped="0" on the gates that fit. limit=N raises the per gate cap (offset=M skips that many sites in every gate), detail lifts it entirely, and next= on the root is the exact pasteable invocation that shows every site this run dropped. -->
<flags schema="ripwire.flags/v1" gates="96" dark_gates="88" compile="13" cmake="12" env="71" files="2695" next="--flags --limit=19">
<gate name="FIXTURE_DARK_FEATURE" kind="compile" default="0" dark="1" regions="2" loc="13" reads="2" p="test/flagsfix/wiringFlags.h" l="10">
<read p="test/flagsfix/feature.cpp" l="10"/>
<read p="test/flagsfix/sub/nested.cpp" l="5"/>
</gate>
<gate name="PROFILE_PMC_VERBOSE" kind="compile" default="0" dark="1" regions="2" loc="11" reads="2" p="src/infra/profilePmc.h" l="78">
<read p="src/infra/profilePmc.h" l="81"/>
<read p="src/infra/profilePmc.h" l="480"/>
</gate>
<gate name="ALIASFIX_ALL" kind="compile" default="0" dark="1" regions="0" loc="0" reads="2" p="test/flagsaliasfix/aliases.h" l="7">
<aliases n="2" regions="2" loc="8"/>
<read p="test/flagsaliasfix/aliases.h" l="11"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--flip`, `--limit`

**Caveats (stated by the binary):**

- LIMITS: lexical, not preprocessed — a gate computed at configure time or set only in a CI script shows its in-repo default, never the value your build used.
- A gate needs a VALUE (#ifndef F / #define F 0) to be a gate: valueless pairs are include guards and are excluded, and a gate read as a VALUE (constexpr bool k = F != 0, then if constexpr) reports regions="0" honestly — its code is a C++ branch, not an #if region.

### `--flip=NAME`

**Answers:** (with --flags) the blast radius of turning ONE gate on (with --flags) the BLAST RADIUS of turning ONE gate ON: which code becomes live, how much, which SYMBOLS hold it, what those transitively reach, and which TESTS cover it — the actionable sequel to --flags' list.

Reports #if regions AND the C++ branch sites a value-style gate governs (constexpr bool k = F != 0, then if constexpr( k )): the binding is followed, so the family --flags honestly sizes at regions="0" gets a real radius here. Alias chains run BOTH ways — flipping a MASTER rolls up every child that #defines to it (<member> rows), flipping a CHILD lights only that child and names the <parent> plus the siblings its flip would add. kind=cmake means the switch becomes a -DNAME=1 compile definition, so the C++ radius is identical, but it ALSO steers the build graph (an if(NAME) target_sources can add whole files) — those CMake sites are listed as <c> rows and deliberately NOT followed. kind=env is RUNTIME (runtime="1"): there is no delimited region, so the hosts are the symbols that consult the variable and every row is conditional at its read. --detail lifts the per-list row caps. LIMITS: lexical and single-line, never preprocessed. A binding split across two lines is missed, and block comments are only skipped line-by-line. The value lane reads C-family source only and treats a file that declares its OWN constant of the same name as shadowing the gate's (C++ scoping) — but a third header's same-named constant, included rather than redeclared, would still be counted. A lit site inside no indexed def (a guarded member field, a file-scope constexpr, a test-macro body) counts into filescope= instead of a host. Single-root only (the harvest reads on-disk paths, which a merged workspace relabels) — run it per root. Exit 0 always otherwise: a report, not a gate; an unknown gate name refuses (exit 1) and names the near-misses.

**Try it**

_Unknown-gate refusal (exit 1) with a did-you-mean from a real edit distance (one character off RIPWIRE_ASAN)._

```
$ ./build/ripwire . --flags --flip=RIPWIRE_ASA
(empty)
```

**Shaped by:** `--flags`, `--limit`

**Caveats (stated by the binary):**

- kind=env is RUNTIME (runtime="1"): there is no delimited region, so the hosts are the symbols that consult the variable and every row is conditional at its read.
- LIMITS: lexical and single-line, never preprocessed.
- A binding split across two lines is missed, and block comments are only skipped line-by-line.

### `--layout=STRUCT`

**Answers:** show one struct's memory layout — fields in order, with computed offsets, sizes and padding the CPU/GPU contract view for ONE struct/class: its fields in declaration order with COMPUTED offsets/sizes/padding, every static_assert in the index that mentions it, and EVERY same-name definition compared field-by-field (the mirror/stub drift check that a dual-compile uniform block needs on every edit).

file:name disambiguates a same-named struct (like --around/--lego). Exit 2 when the contract is BROKEN: mirror="mismatch" (two definitions of the name disagree) or agree="0" (a sizeof tripwire contradicts the computed size). Exit 3 when it could not be VERIFIED: a same-name definition's file was unreadable when this ran (unreadable="N" on the root; 2 still wins when a readable pair already disagrees). Multi-root aware: the mirror check spans every merged root. LIMITS, read them: the offsets are a MODEL, not the ABI — a lexical walk under standard- layout assumptions on a 64-bit Apple/LP64 target (natural alignment, interior padding, trailing pad to the aggregate's own alignment). It is NOT a compiler: #pragma pack, bitfields, virtuals, base classes, nested/anonymous aggregates, #if-conditional members, templates, pointer-to-member fields and any field type it cannot size all set modeled="0" with a named caveat instead of printing a number, and one unsized field un-places every field after it. alignas(N) and attribute packed ARE modelled. Array extents and macro type names resolve against the DEFINING FILE's own #define/constexpr constants only, and a macro with two definitions is accepted only when both agree on the size (the dual-compile half/__fp16 case). Definitions and asserts come from the INDEXED C-FAMILY files only (a TypeScript/Swift class has no byte layout) — .metal IS one of them (indexed under the C++ grammar, see kLangTable), so a Metal struct's layout is modelled like any other C-family aggregate.

**Try it**

_The honest refusal (exit 1): Lang is an `enum class`, not a struct — no offsets are fabricated._

```
$ ./build/ripwire . --layout=Lang
(empty)
```

**Shaped by:** `--abi`, `--field-affinity`

**Caveats (stated by the binary):**

- file:name disambiguates a same-named struct (like --around/--lego).
- LIMITS, read them: the offsets are a MODEL, not the ABI — a lexical walk under standard- layout assumptions on a 64-bit Apple/LP64 target (natural alignment, interior padding, trailing pad to the aggregate's own alignment).
- It is NOT a compiler: #pragma pack, bitfields, virtuals, base classes, nested/anonymous aggregates, #if-conditional members, templates, pointer-to-member fields and any field type it cannot size all set modeled="0" with a named caveat instead of printing a number, and one unsized field un-places every field after it.

### `--field-affinity[=STRUCT]`

**Answers:** find fields that are read together but declared far apart — the cache-locality lens the CACHE-LOCALITY lens: which fields are READ TOGETHER but declared FAR APART.

Builds a static field CO-ACCESS affinity graph (one observation per indexed C-family function body) and diffs it against the DECLARED field order and 64-byte cache-line geometry, reusing --layout's LP64 offset model. Bare = every aggregate in the repo, ranked by separation cost; =STRUCT narrows the report to one. Pairs carry Chilimbi's separation weight wt = (64 - dist)/64 (Cache-Conscious Structure Definition, PLDI 1999) — CITED, not invented here, along with the affinity graph and the points-to-free access enumeration; the advice-not-transform posture is Hundt et al., CGO 2006. Exactly TWO findings fire, both with a direction you can defend in one sentence: split-line (two fields co-accessed by 2+ functions at wt 0.00, so NO field order puts them on one line) and straddle (one co-accessed field crossing a line boundary). ADVICE ONLY: it never proposes a reordering and it has no rewrite mode, because pack-tighter/sort-by-size advice is NON-MONOTONIC (tight packing can induce false sharing — the reason the Go team keeps its own fieldalignment analyzer out of vet and gopls). LIMITS, both in the header: static access counts are NOT dynamic frequency, so fns= is a FLOOR of distinct indexed functions and w= is a call-graph reachability PROXY (1 + fan-in), never a measured count; only dot/arrow member syntax is counted (a bare field name inside its own method is indistinguishable from a local); a field name declared by TWO aggregates is REFUSED and tallied in amb_skipped= rather than guessed; and all geometry is the LP64 MODEL, so a definition --layout marks modeled="0" contributes its affinity graph and NO geometry finding. validate= names the instrumented PROFILE_SCOPE whose hardware counters would confirm the hypothesis (see docs/FIELDAFFINITY.md for the worked example). C/C++/ObjC only. Exit 0 always: a report, not a gate.

**Try it**

_The cache-locality lens over every aggregate: fields READ TOGETHER but declared FAR APART (split-line / straddle findings, Chilimbi separation weight) — advice only, never a rewrite._

```
$ ./build/ripwire . --field-affinity
<!-- ripwire field-affinity schema=ripwire.field-affinity/v1: fields read together but declared far apart vs 64-byte lines: <s n= p=> structs, <pair a= b= fns= dist=>, <finding k= f= g=>. window: shown= capped= (capped=1 cut). counts_floor=1: every count is a FLOOR, never a total. root=: p= relative to it. block=64: ASSUMED cache-line bytes; all geometry (dist= wt= ln= lines= findings) is against it. model=lp64-approx: sizes/offsets are the layout verb's LP64 standard-layout MODEL, not the real ABI. weighting=fanin-floor: w= sums 1 + fan-in per co-accessing fn; a reachability proxy, not a frequency. aggregates=N: C-family structs/classes the layout model located a body for (the scanned universe). files=N: C-family files declaring at least one struct/class the modelling pass visited. fns_scanned=N: C-family functions/methods with a readable body scanned for dot/arrow member accesses. accesses=N: member-access sites tied to one aggregate field (FLOOR: bare in-method names uncounted). amb_skipped=N: access sites REFUSED, not guessed: 2+ aggregates declare that field name; in no count here. structs=N: aggregates with 1+ attributed access; the top 20 by sepcost= print (shown=/capped=). findings=N: split-line + straddle findings over ALL structs=, not just the printed rows. min_fns=2: a pair fires split-line only when co-accessed by this many distinct functions. as_loops=N: for-loops the static advance-shape pass classified corpus-wide; report-only, never ranks. as_index=/as_chase=/as_mixed=/as_unknown=: as_loops= by advance shape (chase = pointer chase). agg=: the aggregate keyword (struct, class ...). modeled=1: layout model placed the fields; 0 = affinity only, no geometry, no finding (why= says why). fields=N: fields declared (before the touched-only filter). touched=N: fields with 1+ attributed access; at most 32 f rows print. pairs=N: co-accessed field pairs in all; at most 12 pair rows print (most fns= first). sepcost=: sum over measured pairs of fns x (1 - wt); the struct ranking key. findings=N: this struct's findings, every one printed. size=/align=/lines=: modeled sizeof, alignment, cache lines spanned (modeled=1 only). acc=N: member-access sites attributed to this field (FLOOR). sz=B: the field's modeled size in bytes (absent when the model could not size it). off=/ln=: modeled byte offset and its cache line (off/64); placed=0 instead when the model refused. w=: sum of 1 + fan-in over the co-accessing functions; a static reachability proxy, never a frequency. wt=: separation weight (64 - dist)/64, 0.00 = the two can never share a line; measured=0 instead when unplaced. wt=0.00: split-line fires only when the pair can never share a 64-byte line. w=: the split-line pair's 1 + fan-in weight sum (proxy); straddle rows carry none. off=/sz=/crosses=: straddle field offset, size, and the line its last byte lands on (lines start at off/64). fanin=N: this function's caller count (the w= proxy input). touched=N: distinct fields of this struct the function touches (named in f=); at most 8 fn rows of fns= print. scope=: the function's PROFILE_SCOPE description (first 120 chars), a counter to confirm with. scopes=N: distinct PROFILE_SCOPEs among the co-accessing functions (the scope children). status=: instrumented (a scope exists to measure) or uninstrumented (no witness yet). counter=: the hardware counter to compare across the two layouts. hint=: how to add the missing instrumentation (uninstrumented only). as_stem_ambiguous=/as_stem_unowned=/as_stem_nonptr=: chase names REFUSED - 2+ owners / no owner / owner type has no pointer marker. -->
<fieldaffinity schema="ripwire.field-affinity/v1" block="64" model="lp64-approx" counts_floor="1" weighting="fanin-floor" aggregates="1508" files="324" fns_scanned="7969" accesses="10730" amb_skipped="25974" structs="731" shown="20" capped="1" findings="16" min_fns="2" as_loops="2551" as_index="8" a … [line truncated: 113 more bytes on this line]
<s n="MainDispatch" p="src/main.cpp" l="499" agg="struct" modeled="1" fields="21" touched="14" fns="23" pairs="57" sepcost="77.12" findings="6" size="168" align="8" lines="3">
<f n="multiRoot" acc="12" fns="10" sz="1" off="32" ln="0"/>
<f n="ws" acc="7" fns="7" sz="8" off="40" ln="0"/>
<f n="fanInPtr" acc="6" fns="6" sz="8" off="56" ln="0"/>
<f n="qmetrics" acc="1" fns="1" sz="8" off="64" ln="1"/>
<f n="ampPtr" acc="7" fns="7" sz="8" off="72" ln="1"/>
<f n="cboPtr" acc="2" fns="2" sz="8" off="80" ln="1"/>
<f n="testedPtr" acc="8" fns="8" sz="8" off="88" ln="1"/>
<f n="lcom4Ptr" acc="2" fns="2" sz="8" off="96" ln="1"/>
<f n="impurePtr" acc="5" fns="5" sz="8" off="104" ln="1"/>
<f n="forChurn" acc="2" fns="2" sz="8" off="112" ln="1"/>
<f n="redactCounts" acc="13" fns="7" sz="8" off="120" ln="1"/>
... [17 more line(s); run it to see the whole thing]
```

**Caveats (stated by the binary):**

- ADVICE ONLY: it never proposes a reordering and it has no rewrite mode, because pack-tighter/sort-by-size advice is NON-MONOTONIC (tight packing can induce false sharing — the reason the Go team keeps its own fieldalignment analyzer out of vet and gopls).
- LIMITS, both in the header: static access counts are NOT dynamic frequency, so fns= is a FLOOR of distinct indexed functions and w= is a call-graph reachability PROXY (1 + fan-in), never a measured count;
- a field name declared by TWO aggregates is REFUSED and tallied in amb_skipped= rather than guessed;

### `--doc-drift[=SUBSTR]`

**Answers:** check which of this repo's documented claims are now false which of this repo's DOC claims are now false.

Verifies the CHECKABLE anchors in every markdown file (SUBSTR filters doc paths) against the live index and prints ONLY the ones that no longer hold, four kinds: file:line refs (why="missing-file" the path is gone, "past-eof" the file is shorter than that, "line-moved" the line is no longer inside the symbol the doc names beside it — got= names the squatter); backticked symbol mentions ("undefined"); `= N` constants ("const-value"); and `[N]` array extents ("array-extent"). LIMITS, stated because a doc-drift verb that cries wolf is worse than none — every lane deliberately UNDER-reports. A backticked name is called stale only when it occurs nowhere in any non-markdown file as an identifier token, so every library name is silent, and so is any repo constant the grammar does not tag as a definition (namespace-scope constexpr in C++, for one) — those are counted as unchecked r="not-a-definition", never as drift. A number is compared only against a DECLARATION-shaped integer literal (a decl keyword on the line, or the name opening it) that the corpus binds UNIQUELY; two values in the tree means unchecked, not drift. A `NAME = N` whose NAME appears nowhere in the code is prose, counted in prose= and never claimed as an anchor. Symbol mentions inside ``` fences are skipped (illustrative code, not claims). checked + unchecked = anchors, always: whatever was not proved says so in an <unchecked> row. Read why="undefined" precisely — it says the name is defined NOWHERE in this repo, which is not the same as DELETED: in a plan or design doc naming work not yet built, that is expected rather than rot. The file:line, const and array lanes are the high-precision ones; the mention lane is the weakest — --with-history is the fix, splitting it into why="deleted" (history removed the name; got= names the commit and date, at= the file) versus unchecked r="never-in-history" (this repo never had it, so it is not rot at all). DATED RECORDS vs ROT. An audit's finding row and a live map gone stale look identical — both are "the code moved and the doc did not" — so a failed anchor the AUTHOR DATED is split out as kind="dated-record" and counted in dated=, leaving drift= for the LIVE rot. drift + dated is every anchor that failed: a record still prints, it is never dropped. rec= names the evidence, most specific first: "line" (the line itself hedges — an at-the-time / as-of-DATE note, or a row opening with an ISO date), "block" (the nearest heading carries an ISO date), "title" (the filename or H1 does), "stamp" (a LABELLED front-matter self-date: 'Date: …', 'Written …', 'Generated: …'). WHAT THIS LANE CANNOT DO, because both were measured and rejected: it cannot use git history — 90 of this repo's 98 stale file:line anchors were CORRECT at their own doc's last commit, audit findings and live design docs alike, because "was it true when written" is the definition of BOTH a record and rot; and it will not read a bare date in the opening prose, which on this repo alone dated three LIVE documents on a day they merely mentioned. It reads dating MARKS, so a doc that is obviously an artifact-of-a-date to a human but never writes that date machine-readably reports LIVE (this repo has two). The bias is one-directional on purpose: a wrong "record" hides real rot, a wrong "live" only over-reports. An inception or freshness date ('opened …', 'Last updated …') is a claim the doc is CURRENT and never marks a record. NOT CHECKED AT ALL: prose, Status lines, dates, 'N of M done' tallies, and whether a code block's body is still correct. Always exits 0 — a report, not a gate. Root element carries at="<sha>[+dirty][+shallow]" (omitted on a non-git root) — the commit these counts were computed against, so a number quoted from this report stays comparable across a HEAD that moves mid-session.

**Try it**

_Which of this repo's doc claims are now false. CHANGED: row attribute at= renamed to tgt= (at= is now only the root sha stamp)._

```
$ ./build/ripwire . --doc-drift
<!-- ripwire doc-drift schema=ripwire.doc-drift/v1: markdown anchors that no longer hold: <doc p=> of <a k= l= c= why= ref= want= got= tgt=>; unchecked/dated rows disclose the rest. failed_capped=/weak_capped=: 1 = cut. at=: commit+dirty+shallow. next=: the one pasteable follow-up. docs=N: markdown docs scanned for anchors; docs minus clean = the doc rows. clean=N: docs with no failed anchor (drift and dated 0); not proof every anchor was checked. checked=N: anchors verified against the index; checked + unchecked = anchors. prose=N: value anchors dropped as prose (name not in code); subtracted from anchors=, never checked. corpus=N: files the anchors were checked against (index + config/build exts); 0 = no anchor shape, no scan. drift=/dated=: anchors that no longer hold / anchors skipped as dated (unverifiable by date). unchecked=N: anchors not proved (the unchecked rows give each reason); checked + unchecked = anchors. doc shown_failed=/failed_total=: a rows printed / all failed anchors (drift+dated); cut at 12, detail=1 lifts. a kind=/rec=: dated-record, an author-dated failed anchor in dated= / its evidence: line|block|title|stamp. a sym=: the symbol the doc names on that file:line; line-moved = that symbol no longer spans the line. more weak=N: w rows of this group withheld; shown_weak + N = its n=; detail=1 lists all. shown_weak=N: w rows printed of n= (cut at 12 a doc, weak_capped=1); detail=1 lists all. w resolves-to=: the indexed symbol spanning that line; not proof it is the one the doc meant. unchecked r=/note=: why n= anchors were not proved, and what was still checked for them. dated r=/note=: the dating mark that moved n= failed anchors into dated= instead of drift=. -->
<doc-drift schema="ripwire.doc-drift/v1" docs="213" clean="184" anchors="6590" checked="3067" unchecked="3523" drift="107" dated="107" prose="26" corpus="2726" at="f1e5c2e76" next="--doc-drift --detail=1">
<doc p="docs/COMMANDS.md" anchors="223" checked="58" drift="29" dated="0" shown_failed="12" failed_capped="1" failed_total="29">
<a k="const" l="506" c="153" why="const-value" ref="dropped_by_budget=23" want="23" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="575" c="146" why="const-value" ref="dropped_by_budget=158" want="158" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3804" c="53" why="const-value" ref="dropped_by_budget=23" want="23" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3805" c="53" why="const-value" ref="dropped_by_budget=156" want="156" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3806" c="53" why="const-value" ref="dropped_by_budget=23" want="23" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3807" c="53" why="const-value" ref="dropped_by_budget=157" want="157" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3808" c="53" why="const-value" ref="dropped_by_budget=19" want="19" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3809" c="53" why="const-value" ref="dropped_by_budget=150" want="150" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3810" c="53" why="const-value" ref="dropped_by_budget=9" want="9" got="298" tgt="test/recallpassagecheck.sh:96"/>
... [19 more line(s); run it to see the whole thing]
```

**Shaped by:** `--recall`, `--comment-coherence`, `--with-history`, `--plan-lint`, `--limit`

**Caveats (stated by the binary):**

- LIMITS, stated because a doc-drift verb that cries wolf is worse than none — every lane deliberately UNDER-reports.
- A `NAME = N` whose NAME appears nowhere in the code is prose, counted in prose= and never claimed as an anchor.
- Symbol mentions inside ``` fences are skipped (illustrative code, not claims).

### `--doc-drift --gateability`

**Answers:** turn "CI stays non-gating" into a finishable list: which docs still have live failing anchors turn "CI stays non-gating" into a finishable to-do list: for every doc that STILL has a LIVE (undated) failing anchor, prints its path and live=N (how many of its rows a date would fix), plus projected_drift= — repo-wide drift= if EVERY listed doc got the fix.

The fix is always the same one this lane already reads for rec="title"/"stamp": an ISO date in the doc's H1/filename, or a front-matter self-date line (Date:/Written:/ Generated:/Recorded:/Reviewed:/Audited:/Authored:). projected_drift= is an UPPER BOUND, not a mandate — dating a doc that is genuinely a live/current reference (not a snapshot-in-time record) would hide real rot rather than honestly classify it. Requires --doc-drift (refused loudly alone).

**Try it**

_Which of this repo's doc claims are now false. CHANGED: row attribute at= renamed to tgt= (at= is now only the root sha stamp)._

```
$ ./build/ripwire . --doc-drift
<!-- ripwire doc-drift schema=ripwire.doc-drift/v1: markdown anchors that no longer hold: <doc p=> of <a k= l= c= why= ref= want= got= tgt=>; unchecked/dated rows disclose the rest. failed_capped=/weak_capped=: 1 = cut. at=: commit+dirty+shallow. next=: the one pasteable follow-up. docs=N: markdown docs scanned for anchors; docs minus clean = the doc rows. clean=N: docs with no failed anchor (drift and dated 0); not proof every anchor was checked. checked=N: anchors verified against the index; checked + unchecked = anchors. prose=N: value anchors dropped as prose (name not in code); subtracted from anchors=, never checked. corpus=N: files the anchors were checked against (index + config/build exts); 0 = no anchor shape, no scan. drift=/dated=: anchors that no longer hold / anchors skipped as dated (unverifiable by date). unchecked=N: anchors not proved (the unchecked rows give each reason); checked + unchecked = anchors. doc shown_failed=/failed_total=: a rows printed / all failed anchors (drift+dated); cut at 12, detail=1 lifts. a kind=/rec=: dated-record, an author-dated failed anchor in dated= / its evidence: line|block|title|stamp. a sym=: the symbol the doc names on that file:line; line-moved = that symbol no longer spans the line. more weak=N: w rows of this group withheld; shown_weak + N = its n=; detail=1 lists all. shown_weak=N: w rows printed of n= (cut at 12 a doc, weak_capped=1); detail=1 lists all. w resolves-to=: the indexed symbol spanning that line; not proof it is the one the doc meant. unchecked r=/note=: why n= anchors were not proved, and what was still checked for them. dated r=/note=: the dating mark that moved n= failed anchors into dated= instead of drift=. -->
<doc-drift schema="ripwire.doc-drift/v1" docs="213" clean="184" anchors="6590" checked="3067" unchecked="3523" drift="107" dated="107" prose="26" corpus="2726" at="f1e5c2e76" next="--doc-drift --detail=1">
<doc p="docs/COMMANDS.md" anchors="223" checked="58" drift="29" dated="0" shown_failed="12" failed_capped="1" failed_total="29">
<a k="const" l="506" c="153" why="const-value" ref="dropped_by_budget=23" want="23" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="575" c="146" why="const-value" ref="dropped_by_budget=158" want="158" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3804" c="53" why="const-value" ref="dropped_by_budget=23" want="23" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3805" c="53" why="const-value" ref="dropped_by_budget=156" want="156" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3806" c="53" why="const-value" ref="dropped_by_budget=23" want="23" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3807" c="53" why="const-value" ref="dropped_by_budget=157" want="157" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3808" c="53" why="const-value" ref="dropped_by_budget=19" want="19" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3809" c="53" why="const-value" ref="dropped_by_budget=150" want="150" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3810" c="53" why="const-value" ref="dropped_by_budget=9" want="9" got="298" tgt="test/recallpassagecheck.sh:96"/>
... [19 more line(s); run it to see the whole thing]
```

**Shaped by:** `--recall`, `--comment-coherence`, `--with-history`, `--plan-lint`, `--limit`

**Caveats (stated by the binary):**

- projected_drift= is an UPPER BOUND, not a mandate — dating a doc that is genuinely a live/current reference (not a snapshot-in-time record) would hide real rot rather than honestly classify it.
- Requires --doc-drift (refused loudly alone).

### `--with-history`

**Answers:** opt in: let --doc-drift and --whereis ask git history whether a name ever existed here OPT-IN: let --doc-drift and --whereis ask git HISTORY whether a name was ever in this repo, and which commit removed it.

ONE `git log -p` walk over everything reachable from HEAD, tokenizing removed lines — the pickaxe's semantics without the pickaxe's cost (`git log -S` per name is ~126 s at 247 names on a 2900-file repo; this is ~3 s, and ~0.8 s on ripwire itself). Off by default because those default paths run in 0.64 s and 0.15 s. Memoized per (repo, HEAD sha) — a commit is immutable, so the cache cannot go stale — and the blob covers the WHOLE repo, so a second question on the same commit costs a cache load, and --whereis reuses whatever --doc-drift already built. LIMITS: it walks HEAD's own history, so a name that only ever lived on an unmerged branch reads as never here (use --whereis's tree scan for that); a deletion performed ONLY as a merge resolution is not seen (merge diffs are not walked); and evidence is a removed LINE carrying the name, so a name whose last removal was from a doc rather than code is reported with that doc as its site. A repo deeper than the walk bound reports truncated="1" and answers unknown — never "never" — for anything it did not reach.

**Try it**

_Same report, with git history splitting stale mentions into deleted-by-commit vs never-existed._

```
$ ./build/ripwire . --doc-drift --with-history
<!-- ripwire doc-drift schema=ripwire.doc-drift/v1: markdown anchors that no longer hold: <doc p=> of <a k= l= c= why= ref= want= got= tgt=>; unchecked/dated rows disclose the rest. failed_capped=/weak_capped=: 1 = cut. at=: commit+dirty+shallow. next=: the one pasteable follow-up. docs=N: markdown docs scanned for anchors; docs minus clean = the doc rows. clean=N: docs with no failed anchor (drift and dated 0); not proof every anchor was checked. checked=N: anchors verified against the index; checked + unchecked = anchors. prose=N: value anchors dropped as prose (name not in code); subtracted from anchors=, never checked. corpus=N: files the anchors were checked against (index + config/build exts); 0 = no anchor shape, no scan. drift=/dated=: anchors that no longer hold / anchors skipped as dated (unverifiable by date). unchecked=N: anchors not proved (the unchecked rows give each reason); checked + unchecked = anchors. doc shown_failed=/failed_total=: a rows printed / all failed anchors (drift+dated); cut at 12, detail=1 lifts. a kind=/rec=: dated-record, an author-dated failed anchor in dated= / its evidence: line|block|title|stamp. a sym=: the symbol the doc names on that file:line; line-moved = that symbol no longer spans the line. more weak=N: w rows of this group withheld; shown_weak + N = its n=; detail=1 lists all. shown_weak=N: w rows printed of n= (cut at 12 a doc, weak_capped=1); detail=1 lists all. w resolves-to=: the indexed symbol spanning that line; not proof it is the one the doc meant. unchecked r=/note=: why n= anchors were not proved, and what was still checked for them. dated r=/note=: the dating mark that moved n= failed anchors into dated= instead of drift=. -->
<doc-drift schema="ripwire.doc-drift/v1" docs="213" clean="189" anchors="6590" checked="3049" unchecked="3541" drift="97" dated="99" prose="26" corpus="2726" at="f1e5c2e76" next="--doc-drift --detail=1">
<history probed="1" head="f1e5c2e76" commits="3792" removed-names="43742"/>
<doc p="docs/COMMANDS.md" anchors="223" checked="58" drift="29" dated="0" shown_failed="12" failed_capped="1" failed_total="29">
<a k="const" l="506" c="153" why="const-value" ref="dropped_by_budget=23" want="23" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="575" c="146" why="const-value" ref="dropped_by_budget=158" want="158" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3804" c="53" why="const-value" ref="dropped_by_budget=23" want="23" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3805" c="53" why="const-value" ref="dropped_by_budget=156" want="156" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3806" c="53" why="const-value" ref="dropped_by_budget=23" want="23" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3807" c="53" why="const-value" ref="dropped_by_budget=157" want="157" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3808" c="53" why="const-value" ref="dropped_by_budget=19" want="19" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3809" c="53" why="const-value" ref="dropped_by_budget=150" want="150" got="298" tgt="test/recallpassagecheck.sh:96"/>
<a k="const" l="3810" c="53" why="const-value" ref="dropped_by_budget=9" want="9" got="298" tgt="test/recallpassagecheck.sh:96"/>
... [18 more line(s); run it to see the whole thing]
```

**Shaped by:** `--whereis`, `--doc-drift`

**Caveats (stated by the binary):**

- Memoized per (repo, HEAD sha) — a commit is immutable, so the cache cannot go stale — and the blob covers the WHOLE repo, so a second question on the same commit costs a cache load, and --whereis reuses whatever --doc-drift already built.
- LIMITS: it walks HEAD's own history, so a name that only ever lived on an unmerged branch reads as never here (use --whereis's tree scan for that);
- A repo deeper than the walk bound reports truncated="1" and answers unknown — never "never" — for anything it did not reach.

### `--plan-lint=FILE`

**Answers:** check a PLAN/DESIGN file's structure — never its semantics the house PLAN/DESIGN format's STRUCTURE check — never semantics, that stays --doc-drift's job.

FILE is read directly (like --from-trace's FILE, not through the crawled index), so it need not live inside any indexed root. GRAMMAR, narrow and opt-in on purpose (real house plans do not converge on one dialect): a card is exactly an H3 heading opening with a task id ("T" + 1-4 digits + up to 3 letters, e.g. T5 / T10 / T7b); a status ledger is exactly one heading (any level) whose text, stripped of a leading section mark, reads "Status" case-insensitively. A card's status is satisfied EITHER by a glyph on the LAST non-blank line of its own body OR by a ledger line naming its id (folded by digits — a bare card "T7" is also answered by a lettered ledger mention "T7a"/"T7b") that itself carries a glyph; the card's own body wins when it has one. A file showing NEITHER an H3 card NOR a ledger heading is reported dialect="0" with nothing further checked — not a failing lint, since most real plans are exactly that file. Once dialect="1": a card whose status did not resolve is status="missing" with why="unlaunched" (a ledger exists and never names this id or a lettered sub-task of it — the mid-wave "this task was never launched" catch), why="unresolved" (the ledger names it with no glyph nearby), or why="no-glyph" (no ledger exists in this document at all); an hourglass line whose git-blamed commit sits more than stale_commits= commits behind HEAD is stale="1" (never claimed outside a git repo — see git=; blames whichever line the status resolved to, named by src="ledger" when that is the ledger); a task id named in the ledger's own body with no matching card (same digit fold) is a ledger-orphan; a literal owed/OWED mention with no check-mark or cross anywhere LATER in the SAME document is undischarged (no cross-document tracking — a successor plan's discharge is invisible here, a stated limit, and this is substring matching with no semantic disambiguation: a doc that merely QUOTES the words reads the same as a real marker). Every gating row carries gating="1"; NOT CHECKED AT ALL: whether a card's claims are true, any heading level other than three for a card, a ledger heading spelled any other way, and a document that uses card headings as plain labels with NO status mechanism anywhere (no ledger, no glyph) — every card there reads "missing" too, a known, disclosed gap. Exit 2 when dialect="1" and gating is non-zero (unlike --doc-drift's always-0 report — nothing here has a legitimate "dated on purpose" reading); exit 0 clean or dialect="0"; exit 1 only when FILE could not be read.

**Try it**

_The house PLAN/DESIGN format's STRUCTURE check — never semantics; exit 2 when a card or ledger row gates._

```
$ ./build/ripwire . --plan-lint=test/planlintfix/wave.md
<!-- ripwire plan-lint schema=ripwire.plan-lint/v1: structural lint of a plan document: each finding names the section and the rule. at=: commit+dirty+shallow. file=/dialect=: the plan read and whether the PLAN dialect was detected (dialect=0: nothing to lint). cards=/ledger=: card rows found / whether the doc carries a ledger (ledger_line= names its line). git=1: git was available, so the staleness read ran; stale_commits=N: a waiting card N commits behind HEAD is stale. gating=N: findings that fail the plan (exit 2); the rest are advisory. -->
<plan-lint schema="ripwire.plan-lint/v1" file="test/planlintfix/wave.md" dialect="1" cards="3" ledger="1" ledger_line="21" at="f1e5c2e76" git="1" stale_commits="20" gating="3">
<card id="T1" line="10" status="check" tline="12"/>
<card id="T2" line="14" status="cross" tline="16"/>
<card id="T5" line="18" status="missing" tline="19" why="unlaunched" gating="1"/>
<ledger-orphan id="T9" line="24" gating="1"/>
<owed line="22">
<![CDATA[- 2026-08-01 — T2 owed a re-check]]>
</owed>
<owed line="24" gating="1">
<![CDATA[- 2026-08-03 — T9 owed a kickoff review, still pending]]>
</owed>
</plan-lint>
```

**Caveats (stated by the binary):**

- check a PLAN/DESIGN file's structure — never its semantics the house PLAN/DESIGN format's STRUCTURE check — never semantics, that stays --doc-drift's job.
- A file showing NEITHER an H3 card NOR a ledger heading is reported dialect="0" with nothing further checked — not a failing lint, since most real plans are exactly that file.
- an hourglass line whose git-blamed commit sits more than stale_commits= commits behind HEAD is stale="1" (never claimed outside a git repo — see git=;

### `--from-trace=FILE`

**Answers:** map a stack trace, sanitizer report or compiler error onto the indexed symbols map a stack trace / sanitizer report / compiler-error text ('-'=stdin) onto the indexed symbols: table-driven frame extraction (python / asan / node / compiler / generic), ranked INNERMOST-first over in-corpus frames only (out-of-corpus frames are listed and counted, never ranked).

Each frame binds by its own NAME first (resolved_by="name") and falls back to the def enclosing its line (resolved_by="line") only when the name is absent/unknown/ambiguous — a trace older than the checkout therefore lands on the symbol it names, and a name-vs-line disagreement is disclosed as line_encloses=, never silently rebound. The counters close: in_corpus = suspects + merged + unresolved, with one <unresolved> row per file-matched frame no resolver could place. p= on a frame is the TRACE's own path:line; definition sites are the <sigs> l= values. Emits the same bundle shape as --for — top suspects' signatures + the innermost in-corpus symbol's FULL body; composes with --token-budget, and HONORS --max-tokens=N (it bounds the bodies) — one of the six shapes that do, alongside the default map, --recall, --connect, --pr-context and --for --detail=N. --top-k is NOT read here (the frame order is the trace's, not a rank). TEST-TO-SOURCE HOP: when the innermost in-corpus frame is a TEST symbol — a failing-test trace names the assertion, not the subject — a <test_hop> block also serves the source symbols reached from it: via="callee" is a real 1-hop call edge into non-test code, via="basename" the naming-convention source pair (foo_test.go/foo.go) used only where no call edge landed there. Labelled heuristic="1"; the frame map is unchanged and the innermost frame keeps rank 1, but the hop rows rank in <sigs> ahead of the remaining frames and the top one's body is served beside it. A non-test trace is unaffected. Unparseable input refuses loudly (never an empty map).

**Try it**

_Map a pasted stack trace onto indexed symbols. CHANGED: in_corpus= now reports the real count (was 0)._

```
$ ./build/ripwire . --from-trace=-
AddressSanitizer:DEADLYSIGNAL
=================================================================
==41337==ERROR: AddressSanitizer: SEGV on unknown address 0x000000000018 (pc 0x000102f4a1c8 bp 0x00016d2f1a40 sp 0x00016d2f19e0 T0)
    #0 0x102f4a1c8 in rw::rankGraphTeleport(Graph const&, std::vector<float> const&, float) src/graph.h:7926
    #1 0x102f3e884 in rw::rankGraph(Graph const&, float) src/graph.h:7967
    #2 0x102e11f30 in runDefaultMap(MainDispatch const&) src/main.cpp:1634
    #3 0x102e01a44 in main src/main.cpp:3999
    #4 0x1a2b3c0dc in start+0x9dc (dyld:arm64e+0x60dc)
==41337==ABORTING
```

**Shaped by:** `--top-k`, `--token-budget`, `--help-task`, `--compress`, `--no-redact`, `--plan-lint`, `--run-trace`, `--limit`

**Caveats (stated by the binary):**

- The counters close: in_corpus = suspects + merged + unresolved, with one <unresolved> row per file-matched frame no resolver could place.
- --top-k is NOT read here (the frame order is the trace's, not a rank).
- Unparseable input refuses loudly (never an empty map).

### `--run-trace="CMD"`

**Answers:** run CMD, then map its failure output onto the code — the whole fix loop in one call EXEC-MODE --from-trace — the whole fix-loop entry in ONE call.

Runs CMD under `sh -c` (the make trust model: your user, your environment, stdin=/dev/null, NO sandbox), captures stdout+stderr interleaved, and on a NON-ZERO exit serves the --from-trace bundle for the captured text (frames mapped innermost-first, the innermost in-corpus symbol's FULL body) plus a token-frugal <lines view="relevant"> cut of the error / frame-shaped output lines — shown=/relevant=/total= all disclosed, the cut never silent. The command's own exit code is ALWAYS disclosed on <run exit=>; a command that exits 0 gets a minimal success record (exit, measured duration_ms, a disclosed tail of output) and NO bundle — nothing failed, so there is nothing to map. The <run> record and captured lines are MEASURED (not deterministic, not claimed to be); the MAPPING of the captured text is byte-deterministic, and the document says which part is which. Composes with --token-budget (it bounds the bundle half, like --from-trace); --top-k / --max-tokens are not read here. ripwire's exit: 0 = the command succeeded; 4 = it failed or timed out (the report is on stdout either way); 1 = ripwire itself could not spawn it.

**Try it**

_A command that exits 0: a minimal success record (exit, measured duration, disclosed output tail) and NO bundle — nothing failed, nothing to map._

```
$ ./build/ripwire . --run-trace="true"
<ctx schema="ripwire.from-trace/v1" task="run-trace: true">
<!-- ripwire from-trace schema=ripwire.from-trace/v1: trace frames mapped to indexed symbols, innermost first; the innermost in-corpus body included. task=: the trace source this bundle maps, verbatim (a file path, stdin, or an MCP label). run exit=: the command's OWN exit code; signal=: the signal that killed it; timed_out=1: the timeout_s= cap did. run duration_ms=: wall clock, MEASURED, not deterministic; timeout_s=: the cap it ran under. run lines=: non-empty captured lines; bytes=: the whole capture; dropped_bytes=: middle bytes the cap dropped. -->
<run exit="0" duration_ms="36" timeout_s="600" lines="0" bytes="0"/>
</ctx>
```

**Shaped by:** `--top-k`, `--token-budget`, `--run-timeout`

### `--run-timeout=SECONDS`

**Answers:** cap --run-trace's command;

default 600 s cap for --run-trace's command (default 600 s; always disclosed as timeout_s=). A command still running at the cap has its whole process group killed and is reported timed_out="1" — an honest TIMEOUT, never an empty success. Modifies --run-trace only; refused loudly alone.

**Try it**

_--run-timeout alone is refused loudly (it only modifies --run-trace)._

```
$ ./build/ripwire . --run-timeout=5
(empty)
```

**Caveats (stated by the binary):**

- A command still running at the cap has its whole process group killed and is reported timed_out="1" — an honest TIMEOUT, never an empty success.

### `--note-add="TARGET: text"`

**Answers:** pin a note to a symbol or file, committed to .ripwire_notes and resurfaced later pin a field note (write-side memory) to TARGET — a SYMBOL in any spelling the read verbs resolve (bare name, file:name, Scope::name, the canonical id path::scope::name, or @FILE:LINE) or a FILE PATH — in the committed, sorted .ripwire_notes at the repo root.

A symbol is CANONICALISED to its canonical id on write (the id --for/--expand key notes by) and the rewrite is echoed on stderr; a name matching SEVERAL definitions is refused naming each, and a name matching NONE is refused with a did-you-mean. A path target is written even when nothing indexed matches it (a note on a file you are about to add is legal), with a loud stderr warning that it is stored dangling. The date is git's committer clock (HEAD), not wall time, so the line is deterministic; prints the exact written line. Also STAMPS the writing repo's HEAD sha + branch onto the note (a "done"/"fixed" claim is then anchored to the commit it was true at) — a non-git root or an unresolvable HEAD writes the plain unstamped line rather than a wrong sha. MUTATES one file; single-root only. text with no causal/decision marker ("because"/"chose"/"over"/"instead"/etc.) gets a gentle stderr tip toward the decision shape — never a refusal, the add always proceeds.

**Try it**

_Two definitions carry this name, so the write REFUSES rather than pick one: a note keys ONE canonical id, and an ambiguous selector is refused, never silently narrowed. Every candidate is named, with a runnable retry._

```
$ ./build/ripwire . --note-add="gitOneLine: which one?"
(empty)
```

**Shaped by:** `--no-redact`, `--legend`

**Caveats (stated by the binary):**

- a name matching SEVERAL definitions is refused naming each, and a name matching NONE is refused with a did-you-mean.
- text with no causal/decision marker ("because"/"chose"/"over"/"instead"/etc.) gets a gentle stderr tip toward the decision shape — never a refusal, the add always proceeds.

### `--notes`

**Answers:** list every field note, grouped by target list all field notes grouped by target;

a target with no matching indexed symbol/file is flagged dangling="1" (legal — surfaced nowhere, listed here). Read-only. Notes surface automatically as <note d="date" [sha="…" branch="…"]> children on the symbols/files that --for and --expand emit (and the MCP for / fetch_body verbs); the sha/branch attrs appear only on notes stamped by this version, abbreviated (7 hex) for terseness — the full sha lives in .ripwire_notes on disk. An OLDER .ripwire_notes (3 fields, pre-provenance) reads and surfaces exactly as before, with no sha/branch shown. Absent/empty file = zero effect.

**Try it**

_List all field notes (write-side memory) — the committed .ripwire_notes at the repo root, each with the sha/branch it was recorded at._

```
$ ./build/ripwire . --notes
<ctx schema="ripwire.notes/v1">
<!-- ripwire notes schema=ripwire.notes/v1: field notes by target: <target id= dangling=> holds <note d= sha= branch=>; the kept count comment: notes= rows, targets= <target> rows, dangling= targets matching nothing indexed (listed, surfaced nowhere). dangling=1: matches nothing indexed. -->
<!-- notes=2 targets=2 dangling=0 -->
<notes>
<target id="src/infra/Diagnostics.h" dangling="0">
<note d="2026-09-12" sha="42b7c8d" branch="lane/noalias-docs">
<![CDATA[ASSUME_NO_ALIAS is an optimizer fact in release (separate_storage) only where the compiler consumes it: clang 18+ by default, LLVM 17/AppleClang 16 via the CMake -mllvm flag (scalars only), GCC never (debug check only); never on two members of one object; ASSUME_NO_ALIAS_BUF for OWNING cont … [line truncated: 22 more bytes on this line]
</note>
</target>
<target id="test/manifestcheck.sh" dangling="0">
<note d="2026-08-23" sha="42634f5" branch="claude/fervent-volhard-ddfd9f">
<![CDATA[README.md's single '<N> gate scripts' claim (~line 1305) is NOT enforced — the derived-vs-stated sibling loop here covers docs/EVALS.md only. It drifted 407→451 unnoticed (fixed 2026-08-23). To close: grep both files ('file:line:' parsing) in the gateCountClaims arm.]]>
</note>
</target>
... [2 more line(s); run it to see the whole thing]
```

**Shaped by:** `--no-redact`

### `--pack-task="TASK"`

**Answers:** the whole orientation dance in ONE call, under ONE shared budget the budget-shared task bundle: ONE call assembling, under ONE deterministic budget (default 6K tokens;

--token-budget overrides), the whole orientation dance in FIXED order — (1) routed+anchored ranking, (2) top-K full bodies, (3) their 1-hop caller signatures, (4) their field notes, (5) tests_to_run for the top files, emitted in FIXED order ranking>bodies>callers>notes>tests. Each section holds a FIXED, up-front proportional quota of the budget (rank40/body30/caller15/note5/test10, percent); an under-spent section's leftover quota ROLLS FORWARD to the next section, so a small budget still zeroes a section eventually but never past its own fair share. Each section truncates rank-adaptively and the header reports EVERY truncation (no silent caps). A tiny budget degrades to ranking-only WITH the truncation note. Refuses loudly without a task string.

**Try it**

_ONE budget-shared bundle: ranking + top bodies + caller sigs + notes + tests_to_run. CHANGED: <d> rows now carry n=/id=._

```
$ ./build/ripwire . --pack-task="add a new output format flag to the CLI"
<ctx schema="ripwire.pack-task/v1" task="add a new output format flag to the CLI" route="subtoken+body:declined(add;125-carriers,47-defs)" root="." est_tokens="3619" budget_tokens="6000">
<!-- ripwire pack-task schema=ripwire.pack-task/v1: one-call task bundle for task= under budget_tokens=: <sigs>
<d n= sc= l= p=> ranking, <far>
<s t= n= p=> ranked but over 1 hop out (of_top= ranked rows) > <bodies>
<b t= n= p= l=> with <calls>
<c n= l=> callees > <callers>
<s rel=caller|callee shared=> 1-hop from the bodies (of_top= bodies; shared= bodies reached, absent at 1) > notes > <tests>
<test p= run=> (run= when derivable). window: shown= total= capped= (capped=1 cut). run_unknown=1: no runner derivable (a guess would be worse). est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. <c via="name">: that callee matched by name alone (receiver unprove … [line truncated: 552 more bytes on this line]
<!-- ledger: budget=12744 bytes (6000-token target, ceiling 14160) | ranking: full | bodies: kept 5 of 6 (capped) | callers: 21 of 21 | notes: none | tests: 1 of 1 | far: 6 of 6 -->
<sigs>
<d l="2989" n="printUsage" sc="rw" p="src/cli.h" cx="1" ccx="0" in="1" r="1" next="--expand=src/cli.h:printUsage">
<doc>Print the authoritative CLI usage and flag catalog to the caller-provided output stream</doc>inline void printUsage( std::FILE* out ) noexcept</d>
<d l="459" n="wrapCliAddPost" sc="rw" p="src/wrap.h" cx="4" ccx="2" in="1" r="2">
<doc>claude&apos;s `mcp add … -- ripwire --mcp`: the flag goes on the end of that command line, ahead of its newline</doc>inline std::string wrapCliAddPost( const AgentTarget&amp; row, std::string_view toolsArg )</d>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--top-k`, `--token-budget`, `--for`, `--test-gate`, `--expand`, `--compress`, `--no-redact`, `--partition`

**Caveats (stated by the binary):**

- an under-spent section's leftover quota ROLLS FORWARD to the next section, so a small budget still zeroes a section eventually but never past its own fair share.
- Each section truncates rank-adaptively and the header reports EVERY truncation (no silent caps).
- A tiny budget degrades to ranking-only WITH the truncation note.

### `--partition=N`

**Answers:** (with --pack-task, N=2..16) FAN OUT: one shared core plus N per-agent slices, not one bundle (with --pack-task, N=2..16) FAN-OUT form: instead of one bundle, emit ONE shared common core plus N per-agent slices, so N parallel agents stop re-deriving the same orientation.

The task's ranked surface is carved along the call graph's own Louvain communities — a partition is a union of WHOLE modules (largest-first packing) so it reads coherently; when there are fewer modules than agents the widest is cut at its rank median and split="K" says so. The core is exactly the anchors a plain --pack-task would have bodied. --token-budget then means ONE AGENT's budget (core + its partition), not the document's — total_bytes reports the rest. Each inner <ctx> is byte-identical to a standalone call with that slice, so an orchestrator hands one bundle to one agent verbatim. LIMITS: overlap_mean/overlap_max are pairwise Jaccard over the ids each partition NAMES (window + bodies + their 1-hop neighbors) measured BEFORE budget trimming — a ceiling, not the trimmed truth; and on a task whose surface sits inside one module the split is a rank cut, not a semantic one (read split= and overlap_max before trusting the slices). Refuses loudly without --pack-task, or outside 2..16; --with-graph does not compose with it (N+1 bundles, no single graph — says so on stderr).

**Try it**

_Fan-out form: one shared core + 3 per-agent slices carved along call-graph communities._

```
$ ./build/ripwire . --pack-task="add a new output format flag to the CLI" --partition=3
<ctx-partitions schema="ripwire.pack-task/v1" partitions="3" requested="3" core_symbols="6" surface="42" modules="13" split="0" budget_per_agent_tokens="6000" core_budget_tokens="2040" partition_budget_tokens="3960" total_bytes="20844" overlap_mean="0.044" overlap_max="0.097" shared_symbols="8" unio … [line truncated: 36 more bytes on this line]
<!-- ripwire pack-task schema=ripwire.pack-task/v1: N minimally overlapping agent bundles carved along call-graph communities plus one shared core; each <bundle> wraps a <ctx>; bundle role=core|partition i= symbols= modules= bytes= tokens=: one agent's ctx, symbols= ids assigned, bytes= its size; tokens= = est_tokens= = bytes/2.36 (flat, the densest rate; the inner ctx est_tokens= is language-weighted). Inner ctx task= root= budget_tokens= dropped_positive=: the task, p= base, the slice's token target, ranked candidates its budget cut. of_top=: rows ranked (far) / bodies (callers); s rel=caller|callee shared=: 1-hop edge, bodies reached (absent at 1). window: shown= total= capped= (capped=1 cut). run_unknown=1: no runner derivable (a guess would be worse). est_tokens=: price as emitted (an upper bound under compact). <c via="name">: that callee matched by name alone (receiver unproven); it does NOT mean the edge is false. <d r=N>: rank N in this ranking, rows in r= order. <d cx= ccx=>: cyclomatic/cognitive complexity. <d in=N>: N callers in the index (absent: not measured). route=: the ranker: name-exact(X) = the task names symbol X (anchors: its evidence), subtoken+body = conceptual BM25 (:broad = 1-2 plain words, plain rg may also win; :declined(...) = a name hit refused as a common name). sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. next=: the one pasteable follow-up. pure=1: const/constexpr signature (Swift: non-mutating) and no transitive side effect found; a hint. partitions=/requested=: partitions carved / asked for. modules=/split=: call-graph groups found / cuts forced to split one. core_symbols=/surface=: ids in the shared core / core plus the assignable remainder. budget_per_agent_tokens=: one agent's budget, core_budget_tokens= plus partition_budget_tokens=. total_bytes=N: bytes of all bundles together. overlap_mean=/overlap_max=: pairwise Jaccard over the ids partitions name, before trimming. shared_symbols=/union_symbols=: ids two or more partitions name / ids any partition names. core_overlap=: share of the core surface a partition reaches anyway. -->
<bundle role="core" symbols="6" bytes="3025" tokens="1282" est_tokens="1282">
<ctx task="add a new output format flag to the CLI" route="subtoken+body:declined(add;125-carriers,47-defs)" root="." dropped_positive="2" est_tokens="1058" budget_tokens="2040">
<!-- slice budget=4332 bytes (2040-token target, ceiling 4814) | ranking: capped | bodies: kept 2 of 6 (capped) | callers: kept 2 of 21 | notes: none | tests: 1 of 1 | far: none -->
<sigs shown="4" total="6" capped="1">
<d l="2989" n="printUsage" sc="rw" p="src/cli.h" cx="1" ccx="0" in="1" r="1" next="--expand=src/cli.h:printUsage">
<doc>Print the authoritative CLI usage and flag catalog to the caller-provided output stream</doc>inline void printUsage( std::FILE* out ) noexcept</d>
<d l="459" n="wrapCliAddPost" sc="rw" p="src/wrap.h" cx="4" ccx="2" in="1" r="2">
<doc>claude&apos;s `mcp add … -- ripwire --mcp`: the flag goes on the end of that command line, ahead of…</doc>inline std::string wrapCliAddPost( const AgentTarget&amp; row, std::string_view toolsArg )</d>
<d l="699" n="wrapEmitCliFirst" sc="rw" p="src/wrap.h" cx="10" ccx="5" in="1" r="3">
<doc>ONE recipe path for every agent that can shell out, and the point is that the RECOMMENDATION doe…</doc>inline void wrapEmitCliFirst( const AgentTarget&amp; row, const std::string&amp; token, const std::string_view executablePath, const WrapListing&amp; listing ) noexcept</d>
... [19 more line(s); run it to see the whole thing]
```

**Caveats (stated by the binary):**

- LIMITS: overlap_mean/overlap_max are pairwise Jaccard over the ids each partition NAMES (window + bodies + their 1-hop neighbors) measured BEFORE budget trimming — a ceiling, not the trimmed truth;
- and on a task whose surface sits inside one module the split is a rank cut, not a semantic one (read split= and overlap_max before trusting the slices).
- Refuses loudly without --pack-task, or outside 2..16;

### `--with-graph`

**Answers:** (with --for/--pack-task) append a small Mermaid flowchart of the bundle's top anchors (with --for/--pack-task) append a compact MERMAID flowchart of the bundle's top-N (<=8) ranked anchors + their 1-hop call edges among themselves — <graph fmt="mermaid"><![CDATA[ flowchart LR ...]]></graph>, right before </ctx>.

Reuses the --mermaid emitter's syntax. Costs tokens beyond the sigs it sits next to — worth it only when the reading agent renders mermaid natively. Off by default and purely additive: omitted, output is byte-identical.

**Try it**

_Task lens + a compact Mermaid flowchart of the top anchors' 1-hop edges._

```
$ ./build/ripwire . --for="pagerank power iteration" --with-graph
<ctx task="pagerank power iteration" route="subtoken+body" root="." confidence="high" margin_pct="21" at="f1e5c2e76" doc_mentions="5" schema="ripwire.for/v1" bundle="compact" bodies="0" reason="compact-route" budget_bytes="7500" doc_mentions_capped="1" doc_mentions_total="16" est_tokens="3909">
<!-- ripwire for schema=ripwire.for/v1: bundle=/bodies=/reason= the body posture; d: cx= ccx= complexity, in= callers (absent cx/ccx/in = 0), churn= amp= change, clone= tested= 1, sc= scope, id=p::sc::n; total= shown= capped=1 if cut; task= the query; d pure=1 const/constexpr sig, next= the follow-up to paste; route= name-exact(X)|subtoken+body[:broad|:declined]; confidence=/margin_pct= head score drop (low=flat); h l= p= n=, c n= l= (joined for same-named callees, shown= counts them), noedge= no callee resolved; t p= file outside sigs (weaker), r= rank (gap = trimmed); field name= type= owner= rel=: a member of owner=, rel=creates held by value, uses by reference/pointer; d layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; d e= its last line (absent=unknown, never 0; l= the name's line); c via=name: that callee matched by name alone, receiver unproven (NOT a claim the edge is false) [doc mentions: 5 docs, 3 symbols; doc_mentions=] -->
<!-- root= is the crawl root; p= below is RELATIVE to it (single-root only; absent => p= is ingest's own path, unchanged); at=this commit(+dirty). dropped_positive="18" [budget_bytes= is the default BYTE ceiling this ranked payload was shaped against; it bounds that payload, not the whole document est_tokens prices] [sigs next=: one call serving all total= rows uncut] [sigs next_offset=: the candidate index the cut starts at; no consumer yet (the for offset pages files; next= re-runs the list)] [docs_dropped=N: N shown rows have a doc comment not printed (r>24 always, r5..24 if capped)] [docs_after_code=N: N doc rows of the shown set moved below its code rows; same rows, reordered, none added or removed; a question naming docs keeps score order] [cut: doc_mentions_capped="1" doc_mentions_total="16" — an indexing cap dropped content not shown here]; lego/compose collapse to a counted stub by default (a disclosed cut): total= that section's own pre-cap row count, shown="0" capped="1" (nothing rendered here), next= names the sections=lego,compose flag that restores both sections byte-identically in one call est_tokens= prices this bundle in tokens -->
<sigs shown="22" total="40" capped="1" docs_dropped="11" docs_after_code="5" next_offset="22" next="--for=&apos;pagerank power iteration&apos; --signatures-only --token-budget=6500">
<d l="419" e="419" n="kScoreTieAbsEps" sc="rw" p="src/eval.h" churn="16" amp="28" pure="1" r="1" next="--expand=src/eval.h:kScoreTieAbsEps">
<doc>NodeId order. Renumbering an otherwise-identical graph (the exact &quot;same probe file, different so…</doc>inline constexpr float kScoreTieAbsEps = 1e-6f</d>
<d l="73" e="144" n="renderDisclosure" sc="rw" p="src/prconverge.h" cx="12" ccx="15" in="14" churn="3" amp="41" r="2">
<doc>Render one form of the disclosure. Empty string whenever there is nothing to say — no power it…</doc>inline std::string renderDisclosure( const RankDisclosure&amp; d, DiscloseAs as )</d>
<d l="99" e="206" n="pageRankDouble" sc="rw" p="src/pagerank.cpp" cx="19" ccx="34" in="2" churn="14" amp="44" tested="1" r="3">
<doc>The PageRank power iteration itself — the numeric kernel every ranked document&apos;s order comes f…</doc>PageRankRun pageRankDouble( const sparseCsr&lt;float&gt;&amp; inEdges, std::span&lt;const double&gt; weightedOutDegree, std::span&lt;const double&gt; teleport, std::span&lt;double&gt; r … [line truncated: 10 more bytes on this line]
... [21 more line(s); run it to see the whole thing]
```

**Shaped by:** `--partition`

### `--export=cc.json[:FILE]`

**Answers:** export per-file metrics as CodeCharta cc.json for its 3D city view export per-file metrics (loc/symbols/cx/cognitive_cx/fan-in/fan-out/churn) as CodeCharta cc.json (apiVersion 1.3) — write FILE or redirect stdout;

feeds a CodeCharta 3D city

**Try it**

_Per-file metrics as CodeCharta cc.json._

```
$ ./build/ripwire . --export=cc.json:<scratch>/aux/ripwire2.cc.json
(empty)
```

**Shaped by:** `--legend`

### `--batch=FILE`

**Answers:** run several lookups in one turn: FILE is newline-delimited `verb:arg` sub-queries one-turn context sweep: FILE ('-'=stdin) is newline-delimited `verb:arg` sub-queries (for/grep/callers/callees/impact/uses/mentions/analyze/lego/owners/cochange/exemplar, path_between:FROM,TO), answered in ONE deduped <batch>;

caps at 16 (over-cap = capped=1). THE SAME `verb:arg` line is accepted by the MCP `batch` verb's queries array (queries=["for:parse the config","callers:escapeXml"]), which also takes the {verb, ...args} object form — one grammar to learn, both front doors.

**Try it**

_One-turn sweep: 4 newline-delimited verb:arg sub-queries answered in ONE deduped <batch>._

```
$ ./build/ripwire . --batch=<scratch>/aux/batch2.txt
for:incremental cache invalidation
callers:rankGraphTeleport
grep:DISCLOSE
lego:Vehicle
```

**Shaped by:** `--no-redact`

**Caveats (stated by the binary):**

- run several lookups in one turn: FILE is newline-delimited `verb:arg` sub-queries one-turn context sweep: FILE ('-'=stdin) is newline-delimited `verb:arg` sub-queries (for/grep/callers/callees/impact/uses/mentions/analyze/lego/owners/cochange/exemplar, path_between:FROM,TO), answered in ONE deduped <batch>;
- caps at 16 (over-cap = capped=1).

---

## self-diagnosis

### `--doctor`

**Answers:** check the environment: stale binary, grammars, cache health, git, index identity environment self-check: binary-vs-PATH staleness, grammar tags.scm compile, cache-dir health, git reachability, tree-sitter version, INDEX IDENTITY, and TRACKED-BINARY staleness (a committed binary whose last commit is a git-history ANCESTOR of a same-directory/same-stem source's last commit — never mtime, which a fresh clone stamps at checkout time).

"Dependent source" is a NAMING heuristic (same dir, same filename stem, e.g. tool <-> tool.cpp) — ripwire parses no build system, so a binary built from a differently-named or differently-located source is silently out of scope, neither flagged nor cleared. Single-root only. DIAGNOSTIC, not deterministic (env-dependent by design); exit 0 iff all ok, else 1. Root reports <doctor checks=N passed=M ...>; each <c/> child row carries the BOOLEAN ok="0|1". passed= is the root's count (it was spelled ok= until the vocabulary pass, which collided with the child bool). A FAILING row (ok="0") also carries hint=, the derived verdict (which of self=/which= is stale and the fix, which grammar(s) failed to compile, why the cache dir isn't writable, ...) — a passing row never carries hint=. The index-cache row states the INDEX-VERSION CONTRACT — cache_version=, parser_ver_lean=, parser_ver_rich=, artifact_arch= — the four numbers that decide whether a committed --index-out artifact is reusable at all, and which appear in no other output. lean=/rich= then say whether THIS binary can open the artifact this root would consume (source="auto" its per-root blob, "cache-flag" the file you named, "disabled" under --no-cache), naming WHICH guard refused it: ok | absent | not-regular | unreadable | truncated | not-a-cache | format-version | parser-version | artifact-arch | checksum | corrupt-frame. BOTH families are reported because a team that commits only the lean artifact gets no warm hit on --for/--exemplar/--metrics/--uses. This is a FORMAT verdict about an artifact, never a freshness verdict about an index: every invocation re-validates each file, so a non-ok lean= costs speed, never correctness — the run cold-parses instead. Only an artifact you NAMED with --cache= and this binary cannot read is ok="0" (a missing auto blob is the ordinary cold-start miss, not sickness). The root carries TWO shas, and they answer different questions: at= is the TREE's HEAD (+dirty) right now, built_from= is the commit THIS BINARY was compiled from (byte-identical to --version's own built_from=). They differ from the moment you commit until the next build — normal, so a mismatch is reported, never gated; a stale PATH copy shadowing a fresh build is the binary-path row's job and is decided on inode/mtime/size, not on this sha. The git-config-trust row reads the checkout's OWN core.fsmonitor as this process saw it at startup (fsmonitor="hook|builtin|off|unset"): a HOOK-form value is a command git would run on every read-only call ripwire makes, so the process appends core.fsmonitor=false to git's GIT_CONFIG_COUNT override for its own git children (neutralised="1", and a stderr line carrying git_harden=fsmonitor-hook); the boolean forms need no override (neutralised="0"). Independently of this row, every git command ripwire runs carries git's no-optional-locks and core.fsmonitor=false so no monitor of either form runs for its read-only calls. Not a verdict on your setup — ok="1" always; the neutralisation is the verdict.

**Try it**

_Environment self-check: binary staleness, grammars, cache dir, git, tracked-binary staleness — exit 1 when any check fails (here: the PATH install is older than ./build)._

```
$ ./build/ripwire . --doctor
<!-- ripwire doctor schema=ripwire.doctor/v1: setup health: <c n= ok=> checks; exit 1 when one fails. at=: commit+dirty+shallow. n=: the check's name (binary-path, grammars, cache-dir, git, tree-sitter, index-cache, layout ...). loaded=/expected=: grammars whose tags query compiled / grammars compiled in; a shortfall fails the row. dir=: the per-user cache directory scanned (TMPDIR/XDG_CACHE_HOME ladder); unwritable fails the row. blobs=N: ripwire cache blobs in dir=; the scan stops at 4096 (blobs_floor=1 then). bytes=N: total size in bytes of the blobs counted (short when truncated=1). many=1: more than 50 blobs; an eviction-sanity flag, informational, never fails the row. truncated=1: cache-dir, blob scan cut (cap or I/O error); tracked-binaries, scan SKIPPED, stale=0 unmeasured. locks=N: advisory edit-lock files under locks/; unheld ones over a day old are swept on a cache write. volatile=: this row's attributes that read LIVE machine state; a determinism diff strips them, never the row. git=0|1: git runs from PATH; 0 fails the row (churn verbs need it). repo=0|1: the root is inside a git work tree; 0 is a diagnosis, not a failure. history=0|1: the repo has at least one commit; head= prints only when it does. head=: HEAD's short sha (9 hex, the at= width). core_abi=/cpp_grammar_abi=: tree-sitter core language ABI / the C++ grammar's ABI; informational. languages=N: distinct compiled-in grammars (the grammars row's expected=). tracked=N: git ls-files count, printed even when truncated=1 (over 20000 files skips the scan). binaries=N: tracked paths that sniff as binary content. non_git=1: no git history to compare; the row passes unscanned. stale=N: tracked binaries committed before a same-dir same-stem source changed; any fails the row. cache_version=/parser_ver_lean=/parser_ver_rich=/artifact_arch=: index identity; reuse needs all four. rich_verbs=: the verbs that consume the rich artifact (rich=); every other verb reads the lean one. source=: auto (per-root blob), cache-flag (named by the cache flag) or disabled (no-cache: nothing read). lean_path=/rich_path=: the artifact files checked; one path when the cache flag named it. lean=/rich=: can THIS binary open that artifact (ok, absent, parser-version ...); format, never freshness. fsmonitor=: the checkout's core.fsmonitor at startup: unset, builtin, off, or hook (a command git runs). neutralised=1: a hook fsmonitor was overridden to false for this run; 0 when none was needed. state=: layout records agree, disagree (mixed binary: rebuild clean-first), not-checked or no-records. checked=1: the cross-unit layout comparison ran; 0 = under two comparable records. units=N: translation units that registered a layout record. types=N: layout types recorded (only those registered in src/model.h); omitted on state=disagree. checks=/passed=: checks run / how many passed; exit 1 when passed= is below checks=. built_from=: the commit this binary was built from; at= is the tree HEAD now, a mismatch is normal. self=/which=: this binary's path and the one which ripwire finds on PATH; which_version= is the version line that one prints when they differ. on_path=0|1: whether a ripwire is on PATH; 0 fails the row and hint= carries the export line. same_file=1: the PATH copy is this very file (same device and inode). same_bytes=1: a different file with identical content, a copied install (ok); 0 fails the row; unknown: a file was unreadable; the row fails unverified (hint= names it). self_mtime=/self_size=/which_mtime=/which_size=: epoch mtime and byte size of each binary. hint=: the row's verdict and fix in plain text (which binary is stale, what to run). -->
<doctor schema="ripwire.doctor/v1" checks="9" passed="8" at="f1e5c2e76" built_from="f1e5c2e76">
<c n="binary-path" ok="0" self="./build/ripwire" which="/opt/homebrew/bin/ripwire" on_path="1" same_file="0" same_bytes="0" self_mtime="1791487369" self_size="56512680" which_mtime="1790819582" which_size="53425560" which_version="ripwi … [line truncated: 402 more bytes on this line]
<c n="grammars" ok="1" loaded="25" expected="25"/>
<c n="cache-dir" ok="1" dir="<tmp>" blobs="617" bytes="1859755522" many="1" truncated="0" locks="1221" volatile="blobs,blobs_floor,bytes,many,truncated,locks"/>
<c n="git" ok="1" git="1" repo="1" history="1" head="f1e5c2e76"/>
<c n="tree-sitter" ok="1" core_abi="15" cpp_grammar_abi="14" languages="25"/>
<c n="tracked-binaries" ok="1" tracked="3318" binaries="33" non_git="0" truncated="0" stale="0"/>
<c n="index-cache" ok="1" cache_version="29" parser_ver_lean="156" parser_ver_rich="157" artifact_arch="16" rich_verbs="for,uses,metrics,exemplar,context-ratio,nonlocal-state,quality-panel,verify,eval-retrieval,eval-mined,eval-skills" source="auto" lean_path="<tmp> … [line truncated: 219 more bytes on this line]
<c n="git-config-trust" ok="1" fsmonitor="unset" neutralised="0"/>
<c n="layout" ok="1" state="agree" checked="1" units="2" types="12"/>
</doctor>
```

**Shaped by:** `--agent`

**Caveats (stated by the binary):**

- "Dependent source" is a NAMING heuristic (same dir, same filename stem, e.g.
- A FAILING row (ok="0") also carries hint=, the derived verdict (which of self=/which= is stale and the fix, which grammar(s) failed to compile, why the cache dir isn't writable, ...) — a passing row never carries hint=.
- This is a FORMAT verdict about an artifact, never a freshness verdict about an index: every invocation re-validates each file, so a non-ok lean= costs speed, never correctness — the run cold-parses instead.

### `--agent=codex|claude`

**Answers:** (with --doctor) also inspect that agent's live integration with ripwire (with --doctor) also inspect that agent's LIVE CLI-first integration: PATH binary, exact installed-skill manifest parity, advisory hook executability, and the secondary mcp_servers.ripwire command/--mcp args.

Read-only; emits fixed repair commands and never prints config contents or shell command lines. Other values refuse.

**Try it**

_--doctor plus a LIVE integration inspection for one agent: PATH binary, installed-skill manifest parity, hook executability, MCP wiring — read-only, fixed repair commands, never config contents; exit 1 when any check fails._

```
$ ./build/ripwire . --doctor --agent=claude
<!-- ripwire doctor schema=ripwire.doctor/v1: setup health: <c n= ok=> checks; exit 1 when one fails. at=: commit+dirty+shallow. n=: the check's name (binary-path, grammars, cache-dir, git, tree-sitter, index-cache, layout ...). agent=: the agent named by the agent flag; its live-integration c rows follow the built-in checks. loaded=/expected=: grammars whose tags query compiled / grammars compiled in; a shortfall fails the row. dir=: the per-user cache directory scanned (TMPDIR/XDG_CACHE_HOME ladder); unwritable fails the row. blobs=N: ripwire cache blobs in dir=; the scan stops at 4096 (blobs_floor=1 then). bytes=N: total size in bytes of the blobs counted (short when truncated=1). many=1: more than 50 blobs; an eviction-sanity flag, informational, never fails the row. truncated=1: cache-dir, blob scan cut (cap or I/O error); tracked-binaries, scan SKIPPED, stale=0 unmeasured. locks=N: advisory edit-lock files under locks/; unheld ones over a day old are swept on a cache write. volatile=: this row's attributes that read LIVE machine state; a determinism diff strips them, never the row. git=0|1: git runs from PATH; 0 fails the row (churn verbs need it). repo=0|1: the root is inside a git work tree; 0 is a diagnosis, not a failure. history=0|1: the repo has at least one commit; head= prints only when it does. head=: HEAD's short sha (9 hex, the at= width). core_abi=/cpp_grammar_abi=: tree-sitter core language ABI / the C++ grammar's ABI; informational. languages=N: distinct compiled-in grammars (the grammars row's expected=). tracked=N: git ls-files count, printed even when truncated=1 (over 20000 files skips the scan). binaries=N: tracked paths that sniff as binary content. non_git=1: no git history to compare; the row passes unscanned. stale=N: tracked binaries committed before a same-dir same-stem source changed; any fails the row. cache_version=/parser_ver_lean=/parser_ver_rich=/artifact_arch=: index identity; reuse needs all four. rich_verbs=: the verbs that consume the rich artifact (rich=); every other verb reads the lean one. source=: auto (per-root blob), cache-flag (named by the cache flag) or disabled (no-cache: nothing read). lean_path=/rich_path=: the artifact files checked; one path when the cache flag named it. lean=/rich=: can THIS binary open that artifact (ok, absent, parser-version ...); format, never freshness. fsmonitor=: the checkout's core.fsmonitor at startup: unset, builtin, off, or hook (a command git runs). neutralised=1: a hook fsmonitor was overridden to false for this run; 0 when none was needed. state=: layout records agree, disagree (mixed binary: rebuild clean-first), not-checked or no-records. checked=1: the cross-unit layout comparison ran; 0 = under two comparable records. units=N: translation units that registered a layout record. types=N: layout types recorded (only those registered in src/model.h); omitted on state=disagree. checks=/passed=: checks run / how many passed; exit 1 when passed= is below checks=. built_from=: the commit this binary was built from; at= is the tree HEAD now, a mismatch is normal. self=/which=: this binary's path and the one which ripwire finds on PATH; which_version= is the version line that one prints when they differ. on_path=0|1: whether a ripwire is on PATH; 0 fails the row and hint= carries the export line. same_file=1: the PATH copy is this very file (same device and inode). same_bytes=1: a different file with identical content, a copied install (ok); 0 fails the row; unknown: a file was unreadable; the row fails unverified (hint= names it). self_mtime=/self_size=/which_mtime=/which_size=: epoch mtime and byte size of each binary. hint=: the row's verdict and fix in plain text (which binary is stale, what to run). -->
<doctor schema="ripwire.doctor/v1" checks="12" passed="10" agent="claude" at="f1e5c2e76" built_from="f1e5c2e76">
<c n="binary-path" ok="0" self="./build/ripwire" which="/opt/homebrew/bin/ripwire" on_path="1" same_file="0" same_bytes="0" self_mtime="1791487369" self_size="56512680" which_mtime="1790819582" which_size="53425560" which_version="ripwi … [line truncated: 402 more bytes on this line]
<c n="grammars" ok="1" loaded="25" expected="25"/>
<c n="cache-dir" ok="1" dir="<tmp>" blobs="636" bytes="1879729155" many="1" truncated="0" locks="1221" volatile="blobs,blobs_floor,bytes,many,truncated,locks"/>
<c n="git" ok="1" git="1" repo="1" history="1" head="f1e5c2e76"/>
<c n="tree-sitter" ok="1" core_abi="15" cpp_grammar_abi="14" languages="25"/>
<c n="tracked-binaries" ok="1" tracked="3318" binaries="33" non_git="0" truncated="0" stale="0"/>
<c n="index-cache" ok="1" cache_version="29" parser_ver_lean="156" parser_ver_rich="157" artifact_arch="16" rich_verbs="for,uses,metrics,exemplar,context-ratio,nonlocal-state,quality-panel,verify,eval-retrieval,eval-mined,eval-skills" source="auto" lean_path="<tmp> … [line truncated: 219 more bytes on this line]
<c n="git-config-trust" ok="1" fsmonitor="unset" neutralised="0"/>
<c n="layout" ok="1" state="agree" checked="1" units="2" types="12"/>
<c n="claude-binary" ok="0" on_path="1" same_file="0" copied_heuristic="0" hint="reinstall the current build so Claude Code shell calls and this doctor resolve the same ripwire binary"/>
<c n="claude-skills" ok="1" manifest="1" declared="16" live="16"/>
... [2 more line(s); run it to see the whole thing]
```

**Caveats (stated by the binary):**

- emits fixed repair commands and never prints config contents or shell command lines.

### `--skipped`

**Answers:** say WHY a file is missing from the index, and which indexed files it cannot vouch for WHY the index does not contain a file, and which files it DOES contain but cannot vouch for.

<f p= why= bytes=/> per DROPPED file: why=oversize (limit= names the ceiling — --max-file-size, or the fixed .json/.yaml config ceilings it does not raise), why=excluded (--exclude hit), why=unsupported-ext (ext= has no grammar in this build — the class that hides a whole LANGUAGE). <h p= why= err= err_ratio= ws_freq=/> per INDEXED-but-suspect file, nothing dropped: why=degraded-parse (the parse holds ERROR/MISSING nodes — a parser-state fact, never a syntax verdict) and/or why=minified-suspect (ws_freq under 0.070 over the leading 4KB). <e x= files=/> per unindexed extension — what the map header rolls up as unindexed=. <lang n= files= symbols=/> per LANGUAGE this build DID extract from — the mirror of unindexed= (which names what it could NOT read at all); sorted files DESC then name ASC, absent means the language contributed nothing, never a printed zero; files= is a floor (a file with zero extracted symbols is not attributed to any language), symbols= is exact. The root states the ACCOUNTING INVARIANT indexed= + oversize= + excluded= = the enumerated candidate population, plus unsupported_ext=, excluded_dirs= (SUBTREES --exclude pruned: contents UNKNOWN, not zero), pruned_dirs= (SUBTREES this build always prunes by policy — the committed noise/vendor/build denylist and any dir holding a CMakeCache.txt — contents likewise UNKNOWN), degraded_parse=, minified_suspect=, extent_suspect_files= (files holding a definition whose extent/scope failed a containment check; the <h> row says why=extent-suspect with extent_suspect_syms=), macro_blanked_files= (files whose symbols come from a re-parse with semicolon-less member macro invocations blanked; the <h> row says why=macro-blanked with macro_blanked=), unmeasured= (indexed files this run never parsed) and the effective ceilings, so a zero-row report still states its bounds. rows_capped="1" ⇒ rows are a sample of an exact count. Rows sort by path; composes with --max-file-size/--exclude and multi-root (rows carry the <label>/<rel> spelling). Read-only; exit 0 always: a report, not a gate.

**Try it**

_WHY a file is not in the index (oversize / excluded / unsupported-ext / gitignored) and which indexed files it cannot vouch for (degraded-parse, minified-suspect), plus the per-language census._

```
$ ./build/ripwire . --skipped
<ctx schema="ripwire.skipped/v1">
<!-- ripwire skipped schema=ripwire.skipped/v1: why the index lacks a file <f p= why= bytes= limit= ext=>; indexed but unvouched <h p= why= err= err_ratio=>; <lang> census. root=: p= relative to it. indexed=N: the map's files=; indexed= + oversize= + excluded= + ignored= = every file the crawl enumerated. oversize=N: files dropped for exceeding a size ceiling (row limit= names which). excluded=N: files dropped by an exclude substring you passed. unsupported_ext=N: source/text files no grammar reads; binary assets and excluded/ignored files not counted. excluded_dirs=N: subtrees an exclude pruned; their files are UNKNOWN, not zero, and in no count here. pruned_dirs=N: subtrees pruned by built-in policy (vendor/build, CMakeCache.txt dirs); contents UNKNOWN. ignored=/ignored_dirs=: files / subtrees git ignore rules hid (else indexed); subtree contents UNKNOWN. ignore_mode=: git (rules applied), off (no-ignore flag), unavailable/root-ignored (not consulted, full walk). degraded_parse=/minified_suspect=: counts of the h rows of each why=; those files stay indexed. unmeasured=N: indexed files never parsed (doc pass, binary sniff, nest guard, read error); not health-counted. max_file_size=B: the effective per-file size ceiling in bytes (the max-file-size flag raises it). json_ceiling=/yaml_ceiling=: fixed .json/.yaml byte ceilings the max-file-size flag does NOT raise. ws_freq=R: whitespace share of the leading 4096 bytes; under 0.070 = minified-suspect (never under 256 B). x=/files=: an unindexed extension and its file count (full list; the map's unindexed= is the top 6). files=/symbols=: per language, files with its symbols (FLOOR: symbol-less files uncounted) / symbols (exact). -->
<!-- why=extent-suspect on an <h> row = the file holds extent_suspect_syms= definitions whose extent, scope or kind FAILED a containment check (the map and bundle rows carry the reasons as extent_suspect=: name, head, scope, error); joined to the parse-health reasons comma-separated, and rowed even when the parse itself is clean. extent_suspect_files= on the root counts such rows. Nothing is dropped. -->
<!-- why=macro-blanked on an <h> row = this file's symbols come from a SECOND parse. Its first parse held error bytes, so macro_blanked= semicolon-less ALL-CAPS function-like macro invocations, each alone on its line directly inside a class/struct/union body (a shape the C-family grammars misread as a field missing its semicolon, letting one body swallow what follows it), were replaced by spaces with every offset and line unchanged, and that re-parse was adopted because it held STRICTLY FEWER error bytes; names, spans and bodies still read the original bytes. err=, err_ratio= and degraded-parse on such a row describe the ADOPTED parse: a row without degraded-parse parsed clean once blanked. A blanked invocation stays a use of the macro name for the uses verb (role=type, as the unrepaired parse recorded it) but is no call edge, and identifiers inside its parentheses are not recorded. macro_blanked_files= on the root counts such rows. Nothing is dropped. -->
<skipped indexed="2688" oversize="15" excluded="0" unsupported_ext="255" excluded_dirs="0" pruned_dirs="5" ignored="0" ignored_dirs="0" ignore_mode="git" degraded_parse="115" minified_suspect="2" extent_suspect_files="4" macro_blanked_files="7" unmeasured="26" max_file_size="4194304" json_ceiling="2 … [line truncated: 38 more bytes on this line]
<f p="bench/locbench/full560.json" why="oversize" bytes="679702" limit="262144"/>
<f p="bench/locbench/results/r1_anchorhop/heldout_baseline_release.json" why="oversize" bytes="365776" limit="262144"/>
<f p="bench/locbench/results/r1_anchorhop/heldout_candidate_release.json" why="oversize" bytes="365761" limit="262144"/>
<f p="bench/locbench/results/r3_pathtok/heldout_baseline.json" why="oversize" bytes="440937" limit="262144"/>
<f p="bench/locbench/results/r3_pathtok/heldout_candidate_w3.json" why="oversize" bytes="440925" limit="262144"/>
<f p="bench/locbench/results/r3_pathtok/train_w0.json" why="oversize" bytes="342194" limit="262144"/>
<f p="bench/locbench/results/r3_pathtok/train_w1.json" why="oversize" bytes="342123" limit="262144"/>
<f p="bench/locbench/results/r3_pathtok/train_w2.json" why="oversize" bytes="342117" limit="262144"/>
<f p="bench/locbench/results/r3_pathtok/train_w3.json" why="oversize" bytes="342138" limit="262144"/>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--no-ignore`

**Caveats (stated by the binary):**

- say WHY a file is missing from the index, and which indexed files it cannot vouch for WHY the index does not contain a file, and which files it DOES contain but cannot vouch for.
- <f p= why= bytes=/> per DROPPED file: why=oversize (limit= names the ceiling — --max-file-size, or the fixed .json/.yaml config ceilings it does not raise), why=excluded (--exclude hit), why=unsupported-ext (ext= has no grammar in this build — the class that hides a whole LANGUAGE).
- <h p= why= err= err_ratio= ws_freq=/> per INDEXED-but-suspect file, nothing dropped: why=degraded-parse (the parse holds ERROR/MISSING nodes — a parser-state fact, never a syntax verdict) and/or why=minified-suspect (ws_freq under 0.070 over the leading 4KB).

---

## security — scan skill files for injection / exfiltration patterns (exit 2 = CRITICAL, 1 = WARN,

### `--scan-skill=FILE`

**Answers:** scan a single skill file before installing (any file, not just .md) EXFILTRATE:net-exfil (a network verb plus a $VAR or base64 on one fenced line) needs a destination: a verb named but not run, as in command -v curl, does not fire.

It is CRITICAL only when a credential-shaped source is on that line: a credential-named var, an Authorization: header with a var, an env dump or a key file. Otherwise it is WARN and the row says why="no-cred-source". A sensitive file read fed into an upload (cat /etc/passwd | curl ... @-, curl -d @.env ...) is CRITICAL with or without a var: why="sensitive-read-upload".

**Try it**

_Scan a single skill file for injection/exfiltration patterns before installing._

```
$ ./build/ripwire --scan-skill=skills/ripwire-orient/SKILL.md
<!-- ripwire scan-skills schema=ripwire.scan-skills/v1: injection/exfiltration/path-traversal scan of skill files: files= findings= skipped= verdict=. files=N: files scanned (unscannable ones are skipped=). findings=N: pattern hits; rows print up to 200 (shown= capped=1 past that). verdict=clean|warn|critical: the worst finding's severity, the same as exit 0/1/2. -->
<skillscan schema="ripwire.scan-skills/v1" files="1" findings="0" verdict="clean">
</skillscan>
```

**Shaped by:** `--scan-skills`

### `--scan-skills[=DIR]`

**Answers:** scan a skills directory before installing — every text file, .md and .sh alike scan DIR (or .agents/skills/ + ${CLAUDE_CONFIG_DIR:-~/.claude}/skills/ + ${CODEX_HOME:-~/.codex}/skills/).

EVERY text file, .md and .sh alike — a skill dir's executables are the files most worth scanning. skipped= counts what it could not scan (binary content, or unreadable); denylisted subtrees (.git, node_modules, build, ...) are not descended and the stderr tally says how many. The bare form never reads a positional root: one that is not the current directory is refused (exit 3, use --scan-skills=DIR), and its answer names the directories it walked in dirs=

**Try it**

_Scan a whole skills directory (exit 2 = CRITICAL, 1 = WARN). Explicit-DIR form only._

```
$ ./build/ripwire --scan-skills=skills
<!-- ripwire scan-skills schema=ripwire.scan-skills/v1: injection/exfiltration/path-traversal scan of skill files: files= findings= skipped= verdict=. files=N: files scanned (unscannable ones are skipped=). findings=N: pattern hits; rows print up to 200 (shown= capped=1 past that). verdict=clean|warn|critical: the worst finding's severity, the same as exit 0/1/2. -->
<skillscan schema="ripwire.scan-skills/v1" files="26" findings="0" verdict="clean">
</skillscan>
```

**Caveats (stated by the binary):**

- skipped= counts what it could not scan (binary content, or unreadable);
- The bare form never reads a positional root: one that is not the current directory is refused (exit 3, use --scan-skills=DIR), and its answer names the directories it walked in dirs=

### `--force`

**Answers:** (wrap) proceed even if CRITICAL findings are found

---

## knobs / modes

### `--rank-by=pagerank|authority|hub|rrf|churn|churn-decay`

**Answers:** choose the ranking signal: structure, authority, hub, fusion or churn ranking signal (churn = git change-frequency prior, and stamps its own map with rank_by/window/at so it cannot pass for the structural one;

churn-decay = the same prior with each commit weighted 0.5^(age_days/90) instead of counted equally, so recent edits outweigh old ones. Its age clock is HEAD's OWN commit timestamp, never the wall clock, so the default (whole-history) run is byte-stable for a fixed tree; the half-life is disclosed in window=. default pagerank)

**Try it**

_Rank by git change-frequency prior instead of PageRank._

```
$ ./build/ripwire . --rank-by=churn --top-k=5
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. pr_iters=N: PageRank iterations. rank_by=: the ranker behind k=. window=: the git span mined. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. overloads=N: N same-name defs merged in this row; shown= counts each. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. <c via="name">: that callee matched by name alone (receiver unproven); it does NOT mean the edge is false. <c x=N>: N same-named via=name rows merged; callees=FILE:SYM lists all. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- files=2688 symbols=25558 edges=40392 shown=5 est_tokens=1240 ambiguous=12495 unresolved=12552 locality_pinned=11 external=7267 declined=12204 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:73,tsv:49,jsonl:26,mod:25,scm:23,expected:15" unindexed_exts=20 order=important-first -->
<r schema="ripwire.map/v1" at="f1e5c2e76" root="." rank_by="churn" window="18mo@HEAD" est_tokens="1240" pr_iters="27">
<f p="src/resolve.h">
<s t="method" n="empty" sc="RubyConstantIndex" amb="1" k="0.0111">
<c n="empty" prov="split" via="name" x="3"/>
</s>
</f>
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="buf" sc="svector" overloads="2" k="0.0089">
</s>
</f>
<f p="src/notes.h">
... [9 more line(s); run it to see the whole thing]
```

**Shaped by:** `--since`, `--in`

**Caveats (stated by the binary):**

- choose the ranking signal: structure, authority, hub, fusion or churn ranking signal (churn = git change-frequency prior, and stamps its own map with rank_by/window/at so it cannot pass for the structural one;
- Its age clock is HEAD's OWN commit timestamp, never the wall clock, so the default (whole-history) run is byte-stable for a fixed tree;

### `--in=DIR`

**Answers:** (with --rank-by=churn-decay) scope the recent-changes block to one directory DIR is root-relative and must be an existing directory under the root (db, src/util;

a trailing slash is ignored; absolute paths and '..' are refused). The global <recent> block stays exactly as without the flag — a change outside DIR is still answered — and a SECOND block <recent scope="DIR" n= of=> follows it with DIR's files only, p= spelled root-relative exactly as the global block spells them, same order (newest commit first). It pages: 40 rows by default, then capped="1" has_more="1" next_offset=N offset=M limit=L and a pasteable next= (--offset=N continues, --limit=N sets the page size). The block's of= IS its total, so the paging half carries no total=. next= replays THIS run's own corpus and window flags (the crawl shapers and the history window), so the page it names is a page of the same answer; a presentation flag is not replayed, since it cannot move of=. next= is absent when that invocation would exceed 120 bytes, and has_more= still says the page exists. The scoped block rides exactly when the global one does: absent means no history was mined, n="0" means none of DIR's files was touched. merge_bombs_skipped= stays on the GLOBAL block only — it counts the window's skipped commits, not DIR's. The symbol map collapses to a disclosed stub <symbols stubbed="1" would_show=N next=/> — the map was not asked for and was not ranked at all (so the header carries no pr_iters=); would_show= is that same run's own shown= — symbol DEFINITIONS, counted individually exactly as shown= counts them, so the rows that run prints follow from rows+sum(overloads-1)=shown — and next= fetches them. DIR is validated against the CRAWL, not only the filesystem: a case-folded name, a symlink alias and a subtree --exclude dropped are refused rather than answered with an empty block. REFUSED, exactly: beside any flag that answers instead of the scoped map (a report verb, a map-diff run, a body rider, a doctor/batch/server run), under multi-root, beside a --top-k of any value (the map it sizes is the stub), and beside --json. COMPOSES with --limit/--offset, which page the scoped block, and with the byte budgets, which shape the document that is emitted.

**Try it**

_Scope the recent-changes answer to ONE directory. The global <recent> block stays byte-identical, a second <recent scope="src"> page follows it — n=/of= are its counts (of= IS the total, so the paging half carries no total=), capped="1" has_more="1" next_offset= offset= limit= page it, and next= replays THIS run's own corpus flags (--since/--exclude) so the page it names is a page of the same answer. The symbol map collapses to a disclosed <symbols stubbed="1" would_show= next=/> stub — the map was not asked for and was not ranked at all, which is why the header carries no pr_iters=. merge_bombs_skipped= stays on the global block: it counts the window's skipped commits, not the directory's._

```
$ ./build/ripwire . --rank-by=churn-decay --since=HEAD~4 --exclude=test --exclude=docs --exclude=skills --in=src --limit=3
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. window: capped= has_more= next_offset= (capped=1 cut; next_offset= pastes as offset=). est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. rank_by=: the ranker behind k=. window=: the git span mined. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). <recent n= of=>: the n= newest-touched of of= touched files; <rc age_d=> days since its last commit, w= decayed weight. merge_bombs_skipped=N: N commits touching more than 100 INDEXED files skipped, uncounted; a file only they touched is absent; the window's count, so the global block only. <recent scope=DIR>: a second block riding when the global one does, DIR's files only (p= root-relative); of= is its total; capped=/has_more=/next_offset=/offset=/limit= page it, next= is that page. <symbols stubbed=1 would_show=N next=>: the symbol map in= did not ask for was not rendered; N is that run's own shown= — definitions counted individually as shown= counts them, so its rows follow from rows+sum(overloads-1)=shown (not the header's symbols= corpus count); next= fetches it. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. next=: the one pasteable follow-up. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- files=531 symbols=13777 edges=31324 shown=0 est_tokens=1537 ambiguous=11393 unresolved=3652 locality_pinned=8 external=4864 declined=8687 skipped_oversize=15 unindexed="tsv:42,txt:24,jsonl:23,scm:23,expected:15,lock:7" unindexed_exts=12 order=important-first -->
<r schema="ripwire.map/v1" at="f1e5c2e76" root="." rank_by="churn-decay" window="HEAD~4 half-life=90d" est_tokens="1537">
<recent n="12" of="12" merge_bombs_skipped="0">
<rc p="src/defectshape.h" age_d="0" w="8.96"/>
<rc p="src/quality.h" age_d="0" w="7.97"/>
<rc p="CHANGELOG.md" age_d="0" w="4.99"/>
<rc p="src/compactlegend.h" age_d="0" w="4.98"/>
<rc p="src/verbs_quality.h" age_d="0" w="3.99"/>
<rc p="src/cli.h" age_d="0" w="2.99"/>
<rc p="src/mcp.h" age_d="0" w="2.99"/>
<rc p="README.md" age_d="0" w="2.99"/>
<rc p="src/mcpverbs.h" age_d="0" w="1.99"/>
... [11 more line(s); run it to see the whole thing]
```

**Shaped by:** `--external-surface`, `--doctor`, `--legend`, `--max-memory`

**Caveats (stated by the binary):**

- absolute paths and '..' are refused).
- It pages: 40 rows by default, then capped="1" has_more="1" next_offset=N offset=M limit=L and a pasteable next= (--offset=N continues, --limit=N sets the page size).
- a presentation flag is not replayed, since it cannot move of=.

### `--format=xml|columnar|rows`

**Answers:** choose the output shape for the flat list verbs output shape for the FLAT list verbs (--callers/--callees/--uses/--impact): xml (default, byte-identical) or columnar (a <paths> table + parallel arrays: fields= path,name,line,kind on --callers/--callees/--impact, path,line,role,in_id on --uses — the emitted block's own legend states the zip/n=/&#44;-escape contract;

~15-60% fewer tokens on multi-row results, by de-duplicating the repeated per-row markup + paths; results of a few rows can be LARGER — the paths/cols scaffold has a fixed cost). rows is an alias for columnar. Any OTHER verb refuses (exit 1) — it has no row list to re-encode. Map is unaffected.

**Try it**

_An unknown --format value REFUSES (exit 1), named, with the supported set listed._

```
$ ./build/ripwire . --callers=rankGraphTeleport --format=bogus
(empty)
```

**Shaped by:** `--top-k`, `--for`, `--pack-signatures`, `--json`, `--limit`

**Caveats (stated by the binary):**

- Any OTHER verb refuses (exit 1) — it has no row list to re-encode.

### `--format=candidates`

**Answers:** (with --for/--query) a flat top-K export for an external reranker (with --for/--query) a FLAT top-K export for an EXTERNAL reranker: one <cand r= s= n= id= k= p= l=><sig>..</sig></cand> row per result — identity + score + signature only, no lens/quality extras, no doc bodies.

Composes with --top-k.

**Try it**

_An unknown --format value REFUSES (exit 1), named, with the supported set listed._

```
$ ./build/ripwire . --callers=rankGraphTeleport --format=bogus
(empty)
```

**Shaped by:** `--top-k`, `--for`, `--pack-signatures`, `--json`, `--limit`

### `--legend=full|compact`

**Answers:** legend posture for every XML verb — compact is the default;

full restores the prose output legend posture for EVERY XML verb. The DEFAULT is compact: the legend is a FIXED ~3 KB of prose per call in its full form, so its share is a function of ANSWER SIZE, not of the verb: at least 40% of a small --callers/--uses/--impact/--affected answer (and more on --callees and --edit-check), a little of a large --for bundle — and the callers who pay it are agents, scripts and harnesses making repeated calls. READING ONE MAP AS A HUMAN, or need a definition's reasoning (a term you do not recognise, a floor or cap explained)? pass --legend=full: it restores the full prose legend, byte-identical to the default of 0.6.1 and earlier. compact keeps every row byte and every data/completeness attribute (counts_floor= capped= shown= total= has_more= next_offset= est_tokens= at= root= graph_ambiguous= …), adds a versioned schema id on the root (schema="ripwire.<verb>/v1") and replaces the explanatory prose with ONE legend defining exactly the attributes the answer carries — the meanings live here and in the full legend. DATA comments stay (the map header, pack-task's body-omitted rows, +more). Per call this drops 2.8-5.8 KB on the navigation verbs (--edit-check's legend 7.4 KB -> 0.9 KB). --for compacts too (ripwire.for/v1 header); under --token-budget it never costs a row --legend=full would keep, unless its own header is the larger one and the row pays for <sigs next=> to fit. The MCP twin is the argument legend, compact by default there as well, legend:"full" restores the prose. Runs with nothing to compact ignore the default; an ASKED --legend=compact refuses there, naming the verb: prose/markdown/JSON answers (--situ --recall --report --mermaid --html --plan-lanes --sarif --eval* --json), where --legend=full is a no-op, and the writers and servers (edit verbs, --note-add, --quality-baseline/--quality-ack, --index-out, --export, the server transports), which refuse either posture. ref is the MCP server's SESSION posture, not a CLI one: once a session reads the resource ripwire://legend-dict, answers list rows first, carry each definition once per session and end with <about legend="ref" dict= dictv=/>. A CLI run has no session to hold a definition, so --legend=ref refuses; --legend-dict prints them all.

**Try it**

_The same gating report under --legend=full — same rows, same exit 2; the default compact comment (schema="ripwire.quality-delta/v1", the shape an agent's edit loop should run) becomes ~4 KB of prose legend._

```
$ ./build/ripwire . --quality-delta --legend=full
<!-- ripwire quality-delta: only what a change made WORSE against the floor baseline= names below. Descriptive: weigh and fix the real ones, do not game the number (a wrong abstraction beats a low score). TWELVE KINDS, and kind= on every row names which one: complexity over the ccx bar, verbosity (LOC), nesting, params, duplication, dead-code, api-surface (new public contract drift), error-masking, short-horizon-churn, new-clone-of-reused-helper, placeholder (added stub/TODO), defect-shape (defect= names it). THREE independent axes, in this order: (1) acked findings are suppressed entirely (acked= counts them); (2) ORIGIN — a finding on a symbol that EXISTED at the baseline is preexisting-worse (no origin attribute), one that exists only because the code is NEW carries origin="new-symbol"; (3) MATERIALITY — a small numeric delta is sev="minor", and minor= counts them. EXIT 2 fires only on preexisting-worse AND major, or on format-arity, the gating= count; new-symbol rows never gate, except defect-shape format-arity, so exit 0 is NOT a verdict on them — nothing that existed got worse, but the new debt is yours: read them. Clone kinds are new-symbol only when EVERY member is new; short-horizon-churn is preexisting by construction. preexisting-worse= and new-symbol= partition regressions=. stale= is a FOURTH axis, never gating and never counted in regressions=: rows in the .ripwire_quality_acks ledger whose target no longer applies. api-new-surface= COUNTS the new PUBLIC symbols (never gates, not in regressions=, printed even at zero). register-macro-excluded= is a FLOOR, not a finding: symbols this run excluded from the dead-code kind because their own definition is a registered self-registering test/benchmark macro call. Never gates, never counted in regressions=, printed even at zero (zero means none excluded, not that the check did not run). A gating row's next= is the one pasteable follow-up: expand on FILE:NAME, the body to fix (a duplication row names a SET and carries none). bar= on a complexity/verbosity/nesting/params row is the threshold now= is judged against (ccx 15, loc 60, nest 4, params 5). baseline="git-HEAD" means no sidecar existed, so the working tree was auto-compared against the HEAD tree — anything already committed cannot appear. at= is the git commit (plus a dirty marker when the working tree differs) this list was computed at. The registered families are doctest/Catch2 TEST_CASE, GoogleTest TEST/TEST_F/TEST_P, Google Benchmark BENCHMARK, plus any name a .ripwire_config register_macros= line adds; each registers itself through a static initializer the call graph cannot see, so zero in-edges on one is not evidence of anything. value-ref-excluded= is a FLOOR, not a finding: symbols this run kept out of the dead-code kind only because a table, field, argument or registering decorator holds them as a VALUE (matched by name; it is not a proven call; the callers verb lists the sites; @classmethod-style wrappers do not count), the --dead-code verb's own rule. Never gates; absent at zero. IDENTITY across a rename or a move: a finding is keyed path::scope::name, which a rename would destroy, so the baseline and the .ripwire_quality_acks ledger are both re-filed into the CURRENT tree's identity before either is read, by two EXACT mechanisms — git's own rename record, and equality of a whitespace-and-name-scrubbed body hash — never a similarity heuristic. renames= is how many rename pairs were read, rename_window_commits= how deep the commit window went, acked_by_rename= and acked_by_content= how many of the acked= suppressions each mechanism is responsible for. Three appear ONLY when true, so an absent one is not a silent no: renames_window_truncated= (history is deeper than the window), renames_truncated= (the pair cap was hit), renames_ambiguous= (an ancestor two current symbols both claim — refused rather than guessed). ORIGIN reads the re-filed baseline too, so a regression carried in with a rename is judged preexisting-worse and GATES instead of slipping through as new-symbol. FLOORS, stated because silence here would read as a guarantee: the two clone kinds key on a member-SET hash and are NOT re-filed, so a clone ack still dies on a rename; ORIGIN follows the rename record but never content, because the baseline stores no content id at all; and a move git recorded no rename for still reads as new-symbol. Each sa row carries key= (the ack identity as stored) and why=, which is target-gone (the key names no symbol or group any more) or finding-gone (the target survived, this kind just does not fire on it). sym= and p=path:line name WHICH ack it is, and are present exactly when the key still names a live symbol: on every finding-gone row, on none of the target-gone rows (there is nothing left to name), and on neither clone kind — a clone key hashes a member SET that no single symbol carries, so those rows are unnameable by construction rather than guessed at. Hygiene disclosure only — the ledger file is never auto-edited. ROWS: sym= is the canonical id the finding regressed on; was= and now= carry the before/after value for the numeric kinds; p="path:line" is the locator (root-relative; the first-sorting member for the clone kinds; omitted, never faked, when none resolves). churn= and surface= are per-kind classification facets (short-horizon-churn's self/ambient split; api-surface's new-symbol/contract-change tier). churn= facets never gate alone: the kind gates only on 2+ COMMITTED in-window rewrites of the edited lines. Every row the header's gating= counter counts also carries a gating attribute set to 1 — marked positively, never by the ABSENCE of sev or origin. CLONE ROWS name the whole group rather than one symbol: members= is the member list and tokens= its shared normalized-token count (the same per-group pair the clones verb reports). idiom= names a RECOGNIZED BODY SHAPE every member spells, out of a closed set of three (threshold-ladder, switch-name-table, builder-chain). idiom= alone changes nothing; a group that ALSO shares no non-keyword identifier between any two members, sits in pairwise-distinct enclosing contexts, and stays under 80 normalized tokens is an idiom COLLISION rather than a copy, and is reported minor instead of gating. Break any one of those and it gates as before, idiom= and all: two bucketing ladders over the SAME enum are a copy. The shape is read off the body's token stream and not a parse tree, so a macro-assembled body classifies as whatever its raw tokens spell — the name is printed so the call can be overruled by reading. -->
<quality-delta baseline="git-HEAD" regressions="9" minor="1" acked="0" stale="145" preexisting-worse="6" new-symbol="3" gating="5" register-macro-excluded="62" api-new-surface="2" at="f1e5c2e76+dirty" renames="58" rename_window_commits="400" acked_by_rename="0" acked_by_content="0" renames_window_tr … [line truncated: 36 more bytes on this line]
<r kind="api-surface" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" was="1" now="2" surface="contract-change" p="src/infra/sortutil.h:109" gating="1" next="--expand=src/infra/sortutil.h:nonNegativeFloatDescKey"/>
<r kind="complexity" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="67" bar="15" p="src/infra/sortutil.h:49" gating="1" next="--expand=src/infra/sortutil.h:lessByScoreDescId"/>
<r kind="dead-code" sym="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy" origin="new-symbol" p="src/infra/sortutil.h:119"/>
<r kind="dead-code" sym="src/infra/sortutil.h::rw::sortutil::sortScoredIdsWithOptions" origin="new-symbol" p="src/infra/sortutil.h:129"/>
<r kind="duplication" members="src/infra/sortutil.h::rw::sortutil::nonNegativeFloatAscKeyCopy | src/infra/sortutil.h::rw::sortutil::nonNegativeFloatDescKey" tokens="59" p="src/infra/sortutil.h:119" gating="1"/>
<r kind="nesting" sym="src/infra/sortutil.h::rw::sortutil::lessByScoreDescId" was="1" now="6" bar="4" p="src/infra/sortutil.h:49" gating="1" next="--expand=src/infra/sortutil.h:lessByScoreDescId"/>
... [23 more line(s); run it to see the whole thing]
```

**Caveats (stated by the binary):**

- READING ONE MAP AS A HUMAN, or need a definition's reasoning (a term you do not recognise, a floor or cap explained)? pass --legend=full: it restores the full prose legend, byte-identical to the default of 0.6.1 and earlier.
- under --token-budget it never costs a row --legend=full would keep, unless its own header is the larger one and the row pays for <sigs next=> to fit.
- ref is the MCP server's SESSION posture, not a CLI one: once a session reads the resource ripwire://legend-dict, answers list rows first, carry each definition once per session and end with <about legend="ref" dict= dictv=/>.

### `--legend-dict[=roster]`

**Answers:** print the session legend dictionary, or with =roster the attributes it defines.

Prints the dictionary the MCP server serves as ripwire://legend-dict/full: one definition per line, headed by its dictv= (FNV-1a 64 of the lines, the version a ref answer's <about dictv=> names). =roster lists the completeness attributes it defines (attr, element, source), the roster test/legendrefcheck.sh reads. Answered wherever it stands on the command line; nothing else runs.

**Try it**

_The session legend dictionary the MCP server serves as ripwire://legend-dict/full — one definition per line, headed by its dictv= version; no corpus needed. =roster lists the completeness attributes it defines._

```
$ ./build/ripwire . --legend-dict
ripwire legend dictionary ripwire.dict/v1 dictv=593769ab691623d8 entries=806
<about legend="ref" dict= dictv=>: the answer's rows come first; its root keeps only task= changed= from= to=, and this LAST child carries every other root attribute unchanged (schema= included); legend="ref": a definition is sent once per session (this dictionary's core, or the first answer that ne … [line truncated: 83 more bytes on this line]
schema=ripwire.KEY/v1: the line ripwire.KEY/v1 below reads the answer's rows
window: shown= total= capped= has_more= next_offset= offset= limit= page a list (capped=1 cut; next_offset= pastes as offset=)
X_capped= (any attribute ending _capped): 1 = cut
under ref, est_tokens= and over_ceiling= price the answer with its inline legend: an upper bound
under ref, a <g n= p=> group of n <= 8 runner-less rows prints as its n single rows, each run_unknown=1
ripwire.map/v1 <r>: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data
ripwire.map-diff/v1 <r>: the ranked map anchored at at=: what the diff touched, the map's row vocabulary
ripwire.metrics/v1 <r>: the ranked map with per-symbol metrics: in/out, cx/ccx, loc, params, nest, humps/deep, locals, cbo, amp, tested, ev
ripwire.around/v1 <r>: call neighbourhood of of=: depth= hops, fanout= kept per hop; absent rows lie outside that boundary
ripwire.query/v1 <r>: lexical-rank map for the query term, the map's row vocabulary
ripwire.pack-signatures/v1 <ctx>: the ranked map plus <sigs><d l= n= sc= pure=> signature rows
... [18 more line(s); run it to see the whole thing]
```

**Shaped by:** `--legend`

### `--json`

**Answers:** emit JSON instead of XML;

keys mirror the XML attribute names one to one machine-parseable JSON instead of XML, keys mirror the XML attr names 1:1. Every ROOT attribute survives; a verb that serves fewer SECTIONS than its XML form NAMES them in lens= on the root (--for --json: lens="compose,lego,routes,docs" — their *_total counts are there, their rows are not) — supported for the default map, --for, --pack-task, --callers/--callees/ --impact, --quality-delta, --test-gate, --metrics (the CI/scripting verbs), plus --plan-lanes which is JSON-native. That set is an ALLOW-list: every other verb (and --format=columnar/candidates, --detail, --map-diff, --scip composed with it) refuses loudly on stderr + exit 1 rather than silently falling back to XML — a verb added tomorrow refuses by default. Deterministic: same 2-run byte-diff + stable key order contract as the XML.

**Try it**

_JSON refusal shape: an unsupported verb refuses loudly instead of silently falling back to XML._

```
$ ./build/ripwire . --hotspots --json
(empty)
```

**Shaped by:** `--max-tokens`, `--token-budget`, `--for`, `--in`, `--legend`

**Caveats (stated by the binary):**

- That set is an ALLOW-list: every other verb (and --format=columnar/candidates, --detail, --map-diff, --scip composed with it) refuses loudly on stderr + exit 1 rather than silently falling back to XML — a verb added tomorrow refuses by default.

### `--limit=N --offset=M`

**Answers:** paginate a high-cardinality verb paginate a high-cardinality verb.

HONORED by: --deps --callers --callees --tree --lint --hotspots --clones --cochange --owners --communities --community --doc-drift --whereis --grep/--regex --match --pattern --impact --uses --exercises --seams --zoom --external-surface --dead-code --mentions --graph-query --stray-content --test-gate --biggest-first --ensemble --quality-panel --context-ratio --nonlocal-state --comment-coherence --naming-consistency --safe-delete --pr-context --edit-check --flags --situ --for. Emit at most N rows, skipping the first M; N overrides the verb's own display cap (40 hotspot files, 30 co-change pairs, 60 whereis hits, 100 grep/match hits, 40 impact rows, 20 seam pairs, 40 readability rows, 40 ensemble symbol rows, 40 context-ratio symbol rows, 40 nonlocal-state rows, 200 graph-query rows / --top-k, 40 unflagged --edit-check caller rows, 8 --flags read sites per gate, 25 --flip context rows per listing, 8 --situ blast-radius files and 8 co-change partners). A verb NEVER pages the rows that ARE its answer: --edit-check's flagged callers, --flip's and --situ's tests-to-run rows and --flags' gate rows ride every page in full, and every verdict/count attribute is computed over the full set first. With --offset alone (no --limit) the verb's own default page size applies and the root discloses limit="0" — on OUTPUT that 0 means 'no explicit --limit', never a zero-row page (the flag itself refuses --limit=0). A BARE run whose default cap cut rows (capped="1") carries the same limit="0" and the whole paging block below, so you can page from the first answer without guessing. Deterministic seams (rows are already sorted) so --offset=N is the exact continuation of the previous --limit=N page. On --for, --limit=N/--offset=M do not window the bundle: they select its FILE-GRAIN WIDENING PAGE instead (one <f p= score= n= sym=> row per positive-score file, ranked file-first; see --for), the answer to "the head missed it, show me more files". The root element then carries shown= capped= total= has_more= next_offset= offset= limit= — loop until has_more="0". capped= compares the PAGE to the total (1 ⇔ shown < total), so a page past the end reads shown="0" capped="1" has_more="0": nothing was cut, the offset skipped everything — EXCEPT the verbs with TWO INDEPENDENT listings, which carry the noun-prefixed form instead (one shown= could only describe one): --test-gate shown_tests=/tests_capped= + shown_untested=/untested_capped=, --communities shown_modules=/modules_capped= + shown_bridges=/bridges_capped=, --ensemble and --context-ratio shown_syms=/syms_capped= + shown_files=/files_capped=; the window takes the PRIMARY listing (--test-gate's <u> rows; its <t> rows repeat on every page, complete). --edit-check is the same shape for a different reason: its <c> rows split into the ANSWER (callers flagged incompatible="1", with their complete sites_l=) and the CONTEXT (unflagged callers). Only the context pages — shown_unflagged=/unflagged_capped=, with total= the unflagged count — while the flagged rows and the <def> overload census ride every page in full and status=/defs=/callers=/incompatible= are computed over the FULL caller set before any window, so a page can never make the verdict say less than it knows. Any verb NOT in that list REFUSES both flags (exit 1) rather than accepting and ignoring them: budget/top-k verbs (--recall/--pack-task/--from-trace/ --expand/--outline/--pack-signatures/--format=candidates) are shaped by --top-k/--max-tokens/--token-budget, not a page (--for's bare bundle is shaped by --token-budget the same way, and takes --limit/--offset only as its file page, where the budget flags are refused in turn); the rest (--path/--connect/ --around/--exemplar/--report/--mermaid/--map-diff/--metrics and the default map) answer with a single fixed-shape result that has no row list to window at all.

**Try it**

_The family join: per function, which of four orthogonal evidence families fire, ranked by how many agree._

```
$ ./build/ripwire . --ensemble --limit=8
<!-- ripwire ensemble schema=ripwire.ensemble/v1: four orthogonal evidence families joined, ranked by DISTINCT families fired (no composite score): <s p= n= fam= of= fired=>. window: total= has_more= next_offset= offset= limit= (capped=1 cut; next_offset= pastes as offset=). syms_capped=/files_capped=: 1 = cut. at=: commit+dirty+shallow. root=: p= relative to it. eligible=N: functions and methods with a body, the denominator; ranked + no_family = eligible. no_family=N: eligible symbols where no family fired. bar_ccx=/bar_loc=/bar_nest=/bar_params=: absolute structural bars: cognitive cx, lines, nesting, params. rcut=N: ranks the worst readability decile covers (1 to 40); rrank= inside it fires structural. rmeasured=N: functions the readability lens measured. hcut=N: file ranks the worst churn decile covers (1 to 40); hrank= inside it fires historical. hranked=N: files with any in-window commit; 0 = historical family unavailable. cfiles=N: indexed files the confusion (atom) pack can read: C/C++/ObjC/CUDA. cscope=N: eligible symbols in those files; 0 = confusion family unavailable. lscope=N: eligible symbols in a language the naming pack reads; 0 = lexical family unavailable. shown_syms=N: symbol rows printed; the rest page with offset=next_offset. shown_files=N: file rows printed (fixed cap 20, not paged); files_capped=1 = rows dropped. e f=: the fired family: structural, lexical, confusion or historical. why=: the measurements that crossed, space separated; rule*N = that rule fired N times. top=: the file's most corroborated symbol (most families on one symbol). top_l=: that symbol's line. top_fam=N: families fired on top=, the stronger claim; file rows rank by it. union_fam=N: distinct families firing anywhere in the file (weaker: may be different symbols). union=: the names of those families. syms=N: symbols in the file where at least one family fired. families=N: evidence families joined; ranked=N: symbols at least one fired on; window=: the git span the historical family read. -->
<ensemble schema="ripwire.ensemble/v1" families="4" eligible="14065" ranked="5514" no_family="8551" bar_ccx="15" bar_loc="60" bar_nest="4" bar_params="5" rcut="40" rmeasured="14065" hcut="40" hranked="2688" window="12mo" cfiles="653" cscope="7406" lscope="14065" shown_syms="8" syms_capped="1" shown_ … [line truncated: 115 more bytes on this line]
<s p="src/gitmine.h:1206" n="addRootFilesToGitPathIndex" fam="4" of="4" fired="structural,lexical,confusion,historical">
<e f="structural" why="ccx=25 ev=6"/>
<e f="lexical" why="naming-wordy"/>
<e f="confusion" why="atom-embedded-crement*2"/>
<e f="historical" why="hrank=39 churn=60"/>
</s>
<s p="src/serialize.h:8693" n="packDeps" fam="4" of="4" fired="structural,lexical,confusion,historical">
<e f="structural" why="ccx=120 loc=294 nest=5 params=16 humps=4 deep=14 ev=5 rrank=22"/>
<e f="lexical" why="naming-confusable"/>
<e f="confusion" why="atom-nested-ternary*2"/>
<e f="historical" why="hrank=10 churn=293"/>
</s>
... [17 more line(s); run it to see the whole thing]
```

**Shaped by:** `--top-k`, `--for`, `--tree`, `--graph-query`, `--external-surface`, `--impact`, `--exercises`, `--community`

**Caveats (stated by the binary):**

- Emit at most N rows, skipping the first M;
- A verb NEVER pages the rows that ARE its answer: --edit-check's flagged callers, --flip's and --situ's tests-to-run rows and --flags' gate rows ride every page in full, and every verdict/count attribute is computed over the full set first.
- With --offset alone (no --limit) the verb's own default page size applies and the root discloses limit="0" — on OUTPUT that 0 means 'no explicit --limit', never a zero-row page (the flag itself refuses --limit=0).

### `--exclude=SUBSTR`

**Answers:** drop matching paths (repeatable)   --ignore-tests

**Try it**

_Drop matching paths (repeatable) before ranking._

```
$ ./build/ripwire . --exclude=present --exclude=bench --top-k=5
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. overloads=N: N same-name defs merged in this row; shown= counts each. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. <c via="name">: that callee matched by name alone (receiver unproven); it does NOT mean the edge is false. <c x=N>: N same-named via=name rows merged; callees=FILE:SYM lists all. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- files=2425 symbols=22315 edges=38987 shown=5 est_tokens=1182 ambiguous=12458 unresolved=9707 locality_pinned=11 external=5100 declined=9933 extent_suspect_syms=12 macro_blanked_files=7 unindexed="txt:52,mod:25,scm:23,xml:13,tsv:7,cmake:5" unindexed_exts=15 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="1182" pr_iters="28">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="buf" sc="svector" overloads="2" k="0.0077">
</s>
</f>
<f p="src/resolve.h">
<s t="method" n="empty" sc="RubyConstantIndex" amb="1" k="0.0072">
<c n="empty" prov="split" via="name" x="3"/>
</s>
</f>
<f p="src/infra/os_win32_logic.h" layer="infra">
... [11 more line(s); run it to see the whole thing]
```

**Shaped by:** `--skipped`, `--in`, `--index-out`

### `--map-diff`

**Answers:** re-rank the whole map toward git-changed files, so recent work floats up the FULL map, re-ranked with a PageRank teleport toward git-changed files (working tree vs HEAD) — changed files and their neighbours float up, but every file can still appear;

this is NOT a filter to only-changed symbols. changed="N" in the header names the seed file count (0 on a clean tree or no-git — teleport degrades to uniform; ranked CONTENT is then identical to the plain default map, but not byte-identical: the map-diff header keeps its changed= and at= stamp). Want only-changed instead? --pr-context.

**Try it**

_Full map re-ranked with teleport toward git-changed files — clean tree, so changed=0 and it degrades to the plain map._

```
$ ./build/ripwire . --map-diff --top-k=5
<!-- ripwire map-diff schema=ripwire.map-diff/v1: the ranked map anchored at at=: what the diff touched, the map's row vocabulary. est_tokens=: price as emitted (an upper bound under compact). at=: commit+dirty+shallow. root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. overloads=N: N same-name defs merged in this row; shown= counts each. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). changed=K: K indexed git-changed files seed the PageRank teleport (0: uniform, incl. no git). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. <c via="name">: that callee matched by name alone (receiver unproven); it does NOT mean the edge is false. <c x=N>: N same-named via=name rows merged; callees=FILE:SYM lists all. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. layer=: built-in arch layer (game|infra|render|math|audio|ai|test) from a dir name in p=; absent if none. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- files=2688 symbols=25558 edges=40392 shown=5 est_tokens=1306 ambiguous=12495 unresolved=12552 locality_pinned=11 external=7267 declined=12204 extent_suspect_syms=12 macro_blanked_files=7 changed=0 skipped_oversize=15 unindexed="txt:73,tsv:49,jsonl:26,mod:25,scm:23,expected:15" unindexed_exts=20 order=important-first -->
<r schema="ripwire.map-diff/v1" at="f1e5c2e76" root="." est_tokens="1306" pr_iters="28">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="buf" sc="svector" overloads="2" k="0.0070">
</s>
</f>
<f p="src/resolve.h">
<s t="method" n="empty" sc="RubyConstantIndex" amb="1" k="0.0066">
<c n="empty" prov="split" via="name" x="3"/>
</s>
</f>
<f p="src/infra/os_win32_logic.h" layer="infra">
... [11 more line(s); run it to see the whole thing]
```

**Shaped by:** `--json`, `--limit`

**Caveats (stated by the binary):**

- this is NOT a filter to only-changed symbols.
- changed="N" in the header names the seed file count (0 on a clean tree or no-git — teleport degrades to uniform;

### `--cache=PATH`

**Answers:** incremental cache at PATH (re-parse only changed files)

**Try it**

_Explicit incremental cache at a path OUTSIDE the repo (first call writes it)._

```
$ ./build/ripwire . --cache=<scratch>/aux/warm2.ripwirecache --top-k=3
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. overloads=N: N same-name defs merged in this row; shown= counts each. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. <c via="name">: that callee matched by name alone (receiver unproven); it does NOT mean the edge is false. <c x=N>: N same-named via=name rows merged; callees=FILE:SYM lists all. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- files=2688 symbols=25558 edges=40392 shown=3 est_tokens=1103 ambiguous=12495 unresolved=12552 locality_pinned=11 external=7267 declined=12204 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:73,tsv:49,jsonl:26,mod:25,scm:23,expected:15" unindexed_exts=20 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="1103" pr_iters="28">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="buf" sc="svector" overloads="2" k="0.0070">
</s>
</f>
<f p="src/resolve.h">
<s t="method" n="empty" sc="RubyConstantIndex" amb="1" k="0.0066">
<c n="empty" prov="split" via="name" x="3"/>
</s>
</f>
</r>
```

**Shaped by:** `--doctor`, `--index-out`

### `--index-out=BASE`

**Answers:** cold-parse the tree, write the committable index artifact, and exit without a map CI generate-and-exit: cold-parse the tree and write the committable index artifact, then exit 0 with NO map on stdout.

Writes BOTH families — BASE.lean.ripwirecache (map/ nav/--pr-context) and BASE.rich.ripwirecache (--for/--exemplar/--metrics/--uses are RICH, a lean-only artifact leaves them cold). Consume in a PR job with --cache=BASE.lean.ripwirecache (or .rich.). --exclude shapes the crawl and therefore the blob content. Same-architecture speed cache: consumed on a different arch it self-heals to a full cold parse (correct, slower). NOT byte-identical run-to-run (the header stamps the blob write time); the contract is RESTORE-EQUIVALENCE (a --cache restore == a cold parse), never blob-byte-identity.

**Try it**

_CI generate-and-exit: cold-parse and write BOTH committable cache families (lean + rich), no map on stdout._

```
$ ./build/ripwire . --index-out=<scratch>/aux/ci_index
(empty)
```

**Shaped by:** `--doctor`, `--legend`

**Caveats (stated by the binary):**

- the contract is RESTORE-EQUIVALENCE (a --cache restore == a cold parse), never blob-byte-identity.

### `--no-cache`

**Answers:** disable the warm-by-default per-root TMPDIR cache (forces a cold parse)

**Try it**

_Force a cold parse (bypass the warm TMPDIR cache) — shows the cold-vs-warm cost._

```
$ ./build/ripwire . --no-cache --top-k=3
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. overloads=N: N same-name defs merged in this row; shown= counts each. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. <c via="name">: that callee matched by name alone (receiver unproven); it does NOT mean the edge is false. <c x=N>: N same-named via=name rows merged; callees=FILE:SYM lists all. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- files=2688 symbols=25558 edges=40392 shown=3 est_tokens=1103 ambiguous=12495 unresolved=12552 locality_pinned=11 external=7267 declined=12204 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:73,tsv:49,jsonl:26,mod:25,scm:23,expected:15" unindexed_exts=20 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="1103" pr_iters="28">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="buf" sc="svector" overloads="2" k="0.0070">
</s>
</f>
<f p="src/resolve.h">
<s t="method" n="empty" sc="RubyConstantIndex" amb="1" k="0.0066">
<c n="empty" prov="split" via="name" x="3"/>
</s>
</f>
</r>
```

**Shaped by:** `--doctor`

### `--no-ignore`

**Answers:** crawl the paths the repository's .gitignore covers;

by default they are skipped crawl paths the repository's own .gitignore covers. DEFAULT: in a git work tree the crawl honours git's ignore rules (node_modules/, .venv/, target/, build/, dist/ — whatever the repo declared), and the header discloses ignored_files= / ignored_dirs= when it dropped anything. A non-git root, a missing git binary, or a root that is ITSELF inside an ignored subtree all keep the full walk; --skipped's ignore_mode= says which of the four applied, and rows the ignored set.

**Try it**

_Crawl paths the repo's own .gitignore covers (default honours it and discloses ignored_files=/ignored_dirs= only when it dropped anything — this repo's crawl drops nothing, so the header is identical to the default map's; --skipped's ignore_mode= says which rule applied)._

```
$ ./build/ripwire . --no-ignore --top-k=3
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. overloads=N: N same-name defs merged in this row; shown= counts each. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. <c via="name">: that callee matched by name alone (receiver unproven); it does NOT mean the edge is false. <c x=N>: N same-named via=name rows merged; callees=FILE:SYM lists all. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- files=2688 symbols=25558 edges=40392 shown=3 est_tokens=1103 ambiguous=12495 unresolved=12552 locality_pinned=11 external=7267 declined=12204 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:73,tsv:49,jsonl:26,mod:25,scm:23,expected:15" unindexed_exts=20 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="1103" pr_iters="28">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="buf" sc="svector" overloads="2" k="0.0070">
</s>
</f>
<f p="src/resolve.h">
<s t="method" n="empty" sc="RubyConstantIndex" amb="1" k="0.0066">
<c n="empty" prov="split" via="name" x="3"/>
</s>
</f>
</r>
```

**Caveats (stated by the binary):**

- by default they are skipped crawl paths the repository's own .gitignore covers.
- --skipped's ignore_mode= says which of the four applied, and rows the ignored set.

### `--max-file-size=N[K|M|G]`

**Answers:** skip files larger than N bytes;

default 4MB skip files larger than N bytes (default 4MB; raise for repos with big hand-authored source, e.g. --max-file-size=100M; suffix = 1024^n). .json carries a SECOND, fixed 256KB ceiling this flag does not raise (that size of .json is data, not config, and explodes the symbol table); files it drops are counted in the header's skipped_oversize=

**Try it**

_Skip files above a size bound before parsing (note the corpus shrink in the header)._

```
$ ./build/ripwire . --max-file-size=8K --top-k=3
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- files=1721 symbols=6888 edges=2333 shown=3 est_tokens=899 ambiguous=173 unresolved=770 locality_pinned=3 external=808 declined=740 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=982 unindexed="txt:73,tsv:49,jsonl:26,mod:25,scm:23,expected:15" unindexed_exts=20 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="899" pr_iters="38">
<f p="test/fnliteralfix/arrows.ts" layer="test">
<s t="fn" n="sink" k="0.0019">
</s>
</f>
<f p="src/scipoverlay.h">
<s t="method" n="empty" sc="ScipOverlay" k="0.0019">
</s>
</f>
<f p="src/alloccount.cpp">
<s t="fn" n="countedFree" k="0.0014">
... [3 more line(s); run it to see the whole thing]
```

**Shaped by:** `--skipped`

**Caveats (stated by the binary):**

- skip files larger than N bytes;
- default 4MB skip files larger than N bytes (default 4MB;
- files it drops are counted in the header's skipped_oversize=

### `--max-memory=N[K|M|G]`

**Answers:** the memory guard's limit (default 65% of this machine's memory, env RIPWIRE_MAX_MEMORY) the memory guard is on for every run and silent on normal ones: it measures this process's footprint at most once per 5 s, from 5 s into an ingest.

Past its lines the crawl (growth of limit/8) or the parse (half the limit) stops, and the default map answers from what was built, disclosed in its header (memory_stop=, memory_parsed=, memory_limit=; a parse stop keeps the first K slots it claimed of its work order — uncached files first, largest first within a tier, or path order when every grammar-bearing file was an ingest-cache hit — so a partial map repeats for a given memory_parsed=K); critical OS pressure stops them too. Every other verb (--html, --mermaid, --expand, --outline and, after a crawl stop, --in included) refuses a partial index, and so does any verb whose own internal ingest was cut; at the limit itself ripwire exits 5 with one line naming it. Nothing derived from a partial ingest is cached. The default is 65% of physical RAM (or of the cgroup's memory.max when lower); this flag, or RIPWIRE_MAX_MEMORY when the flag is absent, replaces it; below 64M is refused.

**Shaped by:** `--mcp`

**Caveats (stated by the binary):**

- the memory guard's limit (default 65% of this machine's memory, env RIPWIRE_MAX_MEMORY) the memory guard is on for every run and silent on normal ones: it measures this process's footprint at most once per 5 s, from 5 s into an ingest.
- Past its lines the crawl (growth of limit/8) or the parse (half the limit) stops, and the default map answers from what was built, disclosed in its header (memory_stop=, memory_parsed=, memory_limit=;
- Every other verb (--html, --mermaid, --expand, --outline and, after a crawl stop, --in included) refuses a partial index, and so does any verb whose own internal ingest was cut;

### `--refetch`

**Answers:** when the root is a git URL, clone it fresh instead of reusing the cached copy when the root is a git URL, force a fresh clone instead of reusing the cached one (default: reuse forever;

stderr notes the cached clone's age)

### `--scip=index.scip`

**Answers:** consume a SCIP index as a precision overlay: exact call edges replace name guesses consume a SCIP index as a PRECISION overlay: precise call edges replace name-based guesses (tagged prov="scip"), ambiguous= drops.

A path that is missing, empty or not a regular file refuses (exit 1). A corrupt index warns on stderr and degrades to name-based. Zero deps (hand-rolled reader).

**Try it**

_SCIP overlay with a missing index REFUSES (exit 1) naming the file — never silently serves the name-based map you named a precision index to improve on (it used to degrade in silence)._

```
$ ./build/ripwire . --scip=does_not_exist.scip --callers=rankGraphTeleport
(empty)
```

**Shaped by:** `--json`, `--pin-census`

**Caveats (stated by the binary):**

- consume a SCIP index as a precision overlay: exact call edges replace name guesses consume a SCIP index as a PRECISION overlay: precise call edges replace name-based guesses (tagged prov="scip"), ambiguous= drops.
- A path that is missing, empty or not a regular file refuses (exit 1).
- A corrupt index warns on stderr and degrades to name-based.

### `--pin-census=FILE`

**Answers:** eval only: record which mechanism resolved each call site eval-only: write a per-call-site census of WHICH mechanism resolved each call (unique/qualified/receiver-rule/cone/arity/locality/split/scip/binding) and the canonical id of every surviving target — the identity <c n="NAME"/> omits.

Under --scip it also writes the index's covered sites, so a precision join needs no protobuf reader. stdout is byte-identical with or without it.

**Try it**

_Eval-only: a per-call-site census of WHICH mechanism resolved each call, and the canonical id of every surviving target._

```
$ ./build/ripwire . --pin-census=<scratch>/aux/pin_census.tsv --top-k=3
<!-- ripwire map schema=ripwire.map/v1: ranked symbol map: <f p= layer=> groups <s t= n= sc= k= amb=> rows (k= rank), <c n=> resolved callees; the header comment is data. est_tokens=: price as emitted (an upper bound under compact). root=: p= relative to it. pr_iters=N: PageRank iterations. declined=K: K calls left unbound (no evidence chose one def). external=K: K calls proven outside the tree, no edge. locality_pinned=K: K calls pinned by locality alone (a guess). extent_suspect_syms=K: K defs failed containment, corpus-wide. macro_blanked_files=K: K files indexed from a macro-blanked re-parse. overloads=N: N same-name defs merged in this row; shown= counts each. prov=scip|binding|import|split|final-segment: how that <c> edge bound (absent: one unique name); split = one arm of an amb= pick; final-segment = a qualified type matched by last name only. files=/symbols=: files and symbols indexed; edges= distinct call edges; shown= symbols printed, a merged row counting each def; ambiguous= calls split over several defs, corpus-wide; unresolved= calls with in-tree evidence and no edge (every def language-filtered or unreachable, or binding refused); order= rows by rank (important-first, important-last; (auto:fill) = flipped past a size threshold) or by path (stable). skipped_oversize=K: K files over a size ceiling, not indexed. unindexed=ext:N: N text files of that extension no grammar reads (6 extensions at most). unindexed_exts=E: E such extensions in all, the list cut. <c via="name">: that callee matched by name alone (receiver unproven); it does NOT mean the edge is false. <c x=N>: N same-named via=name rows merged; callees=FILE:SYM lists all. sc=: enclosing scope; the full id is p::sc::n (p= of the row or its <f>) and selectors take it. amb=K: K calls split over several defs. -->
<!-- t=modscope=a-file's-MODULE-SCOPE(n=<file-scope>):the-statements-outside-every-named-definition,where-a-top-level-call-and-an-anonymous-callback-body's-calls-live;a-CALLER-never-a-callee(nothing-in-the-source-can-name-it)-with-no-body-to-expand;a-file-with-no-such-call-has-no-such-row -->
<!-- files=2688 symbols=25558 edges=40392 shown=3 est_tokens=1103 ambiguous=12495 unresolved=12552 locality_pinned=11 external=7267 declined=12204 extent_suspect_syms=12 macro_blanked_files=7 skipped_oversize=15 unindexed="txt:73,tsv:49,jsonl:26,mod:25,scm:23,expected:15" unindexed_exts=20 order=important-first -->
<r schema="ripwire.map/v1" root="." est_tokens="1103" pr_iters="28">
<f p="src/infra/svector.h" layer="infra">
<s t="method" n="buf" sc="svector" overloads="2" k="0.0070">
</s>
</f>
<f p="src/resolve.h">
<s t="method" n="empty" sc="RubyConstantIndex" amb="1" k="0.0066">
<c n="empty" prov="split" via="name" x="3"/>
</s>
</f>
</r>
```

### `--mcp`

**Answers:** persistent index server (parse once, many warm queries) over stdio persistent index server over stdio.

Roots: a request's path= (or `paths`), else the startup root of `ripwire <root> --mcp`, else the directory the server was launched in. A root that is $HOME itself (a git repository or not), a filesystem or drive root, or a system tree (/usr, /etc, /System, %WINDIR% ...) is refused with "no project root: <dir> is a home/system directory; pass a project path" and the server stays up — an agent fills path= from its session's cwd, so it is judged like the launch directory. The one exception is the startup root itself: `ripwire ~ --mcp` was typed by a human and is answered. On the CLI a typed root (`ripwire ~`) is always answered, and a run without <dir> prints usage, or that same line from such a directory. Each tool call over the --max-memory limit is refused by name; an answer from an index the memory guard cut carries _memory_stop in its envelope.

**Try it**

_initialize + tools/list: the manifest an agent host loads at session start — every verb's name, description and input schema._

```
$ ./build/ripwire '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | ./build/ripwire --mcp
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a sym … [line truncated: 738 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"analyze","description":"Architecture map for a directory: signatures and the call graph for the top symbols. Use when landing cold in a repo or subdir, before reading files; for a task-scoped inventory use 'for', for one symbol's neighborhood find_ … [line truncated: 742 more bytes on this line]
{"name":"rank_by","description":"The SAME architecture map 'analyze' serves, ranked by a different signal instead of plain PageRank. rank_by = pagerank (default, omit it — the CLI's own unbiased --rank-by=pagerank; 'analyze' can rank differently on a tree with uncommitted changes, where it biases  … [line truncated: 1077 more bytes on this line]
{"name":"find_symbol","description":"A symbol's 1-hop neighborhood: the symbol (with a fetch_body handle) plus direct callers (calledBy) and callees (calls). Full transitive reach: 'impact'. Read/write/import sites, not just calls: 'uses'. JSON {symbol, calledBy, calls, defs, count, hop_tested, hop_ … [line truncated: 1181 more bytes on this line]
... [30 more line(s); run it to see the whole thing]
```

**Shaped by:** `--no-stable`, `--no-redact`, `--agent`, `--mcp-tools`, `--lsp`, `--listen`

**Caveats (stated by the binary):**

- A root that is $HOME itself (a git repository or not), a filesystem or drive root, or a system tree (/usr, /etc, /System, %WINDIR% ...) is refused with "no project root: <dir> is a home/system directory;
- Each tool call over the --max-memory limit is refused by name;

### `--mcp-legend=WHEN`

**Answers:** the stdio MCP server's legend posture: session (the default) or inline session: the first answer of a session carries its legend inline;

later answers list rows first, carry each definition only the first time the session meets it, and end with <about legend="ref" dict= dictv=/> (the first of them also carries the core). inline: every answer keeps its legend until the client reads ripwire://legend-dict. legend:"compact"/"full" on a call keeps that answer inline either way. Stdio only.

**Try it**

_--mcp-legend=inline: every answer of the stdio session carries its own legend (the default, session, sends each definition once per session after the first answer)._

```
$ ./build/ripwire '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"whereis","arguments":{"path":".","symbol":"rankGraphTeleport"}}}' '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"whereis","arguments":{"path":".","symbol":"computeOnePairOverlap"}}}' | ./build/ripwire --mcp --mcp-legend=inline
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a sym … [line truncated: 735 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"<!-- ripwire whereis schema=ripwire.whereis/v1: every LOCAL ref whose tree holds sym= (refs_scanned=, blobs=), HEAD first: <hit ref= tip= date= p= l= kind= t=>. window: shown= total= capped= has_more= next_offset= offset= limit= (ca … [line truncated: 19102 more bytes on this line]
"_index":"[index: files=2688 symbols=25558 hash=3e4b5e31]","_fresh":"ok"}}
{"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"<!-- ripwire whereis schema=ripwire.whereis/v1: every LOCAL ref whose tree holds sym= (refs_scanned=, blobs=), HEAD first: <hit ref= tip= date= p= l= kind= t=>. window: shown= total= capped= has_more= next_offset= offset= limit= (ca … [line truncated: 15756 more bytes on this line]
"_index":"[index: files=2688 symbols=25558 hash=3e4b5e31]","_fresh":"ok"}}
```

### `--mcp-tools=LIST`

**Answers:** list only these MCP tools (names and/or the core/full profiles, default full).

A comma list of tool names and/or profiles, unioned. core = explore, batch, from_trace, impact, uses, fetch_body, edit_check, quality_delta (the loop the server's own instructions teach); full = all tools, the default. A client that loads every schema at session start pays only for the listed ones. initialize announces the subset; calling an unlisted tool is refused with the flag that enables it. The list is not access control: batch sub-queries still reach hidden verbs. An unknown, repeated or empty name exits 1. `ripwire wrap AGENT --mcp-tools=LIST` writes it into the server command (claude, cursor, windsurf, gemini, opencode).

**Try it**

_--mcp-tools=core: the server lists only the core profile's tools (explore, batch, from_trace, impact, uses, fetch_body, edit_check, quality_delta), so a host that loads every schema at session start pays only for those._

```
$ ./build/ripwire '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize"}' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | ./build/ripwire --mcp --mcp-tools=core
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","serverInfo":{"name":"ripwire","version":"1.0"},"capabilities":{"tools":{},"resources":{}},"instructions":"Map before reading files. Start a new task with explore; use from_trace for an error; use impact plus uses before changing a sym … [line truncated: 955 more bytes on this line]
{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"fetch_body","description":"Full (or partial-range) source of a symbol's definition, addressed by the stable `handle` a read verb attached to it (bodies on request, not by default). start_line/end_line are optional, 1-based, INCLUSIVE and BODY-RELAT … [line truncated: 1092 more bytes on this line]
{"name":"quality_delta","description":"Your PR self-check, run every time you think a change is DONE — pairs with the CLI-only --test-gate (names the tests to run + the untested blast radius; not MCP-exposed) to form the two-step pre-PR gate. Reports ONLY what your working tree made WORSE vs basel … [line truncated: 867 more bytes on this line]
{"name":"impact","description":"IS IT SAFE TO CHANGE X? — the TRANSITIVE blast radius of a symbol via calls, nearest first (d= hop depth), then PageRank. Use before modifying or deleting a symbol; it beats find_referencing_symbols (direct callers only), and 'uses' catches the read/write/import sit … [line truncated: 1325 more bytes on this line]
... [5 more line(s); run it to see the whole thing]
```

**Caveats (stated by the binary):**

- calling an unlisted tool is refused with the flag that enables it.
- The list is not access control: batch sub-queries still reach hidden verbs.

### `--lsp`

**Answers:** read-only navigation LSP server over stdio (definition/references/symbols/hover) off the warm index;

saved-state answers, UTF-8 positions, counts are floors. Refuses --mcp/--listen (one protocol per stdin).

**Caveats (stated by the binary):**

- saved-state answers, UTF-8 positions, counts are floors.
- Refuses --mcp/--listen (one protocol per stdin).

### `--listen=HOST:PORT`

**Answers:** serve the MCP server over Streamable HTTP instead of stdio (implies --mcp).

Binds 127.0.0.1 by default (bare PORT = loopback); one listener serves ONE workspace fixed at startup. A non-loopback host (e.g. 0.0.0.0:8080) REQUIRES --mcp-token and refuses to start without it. No TLS — reverse-proxy it.

**Shaped by:** `--no-stable`, `--lsp`, `--allow-remote-edits`

**Caveats (stated by the binary):**

- 0.0.0.0:8080) REQUIRES --mcp-token and refuses to start without it.

### `--mcp-token=T`

**Answers:** require this bearer token on every HTTP request;

mandatory for a non-loopback bind shared bearer token gating every HTTP request (or set RIPWIRE_MCP_TOKEN); a missing/wrong token gets a 401. Required for a non-loopback bind.

**Shaped by:** `--listen`

### `--allow-remote-edits`

**Answers:** permit the edit verbs over --listen;

refused by default permit the edit verbs over --listen (refused by default: a remote file-writer is a different trust contract); forces the token requirement even on loopback

**Caveats (stated by the binary):**

- refused by default permit the edit verbs over --listen (refused by default: a remote file-writer is a different trust contract);

### `--eval-stray=FILE`

**Answers:** labelled verdict-accuracy eval for --stray-content: FILE is TSV `ref<TAB>verdict` (merged|superseded|unmerged, '#' comments ok).

Emits per-case want=/got= plus an accuracy, and exits 3 if any labelled case regressed — MEASURE a supersession- threshold change against real labels instead of eyeballing it. A ref absent from the report scores as merged (merged refs are omitted by design).

**Try it**

_Labelled verdict-accuracy eval for --stray-content — three labels over REAL local refs (names resolved at capture time); exit 3 when accuracy is under the floor. Read got= against v= in the stray-content run: a ref the verb could not analyse (unknown) must never be credited as a merged hit._

```
$ ./build/ripwire . --eval-stray=<scratch>/aux/stray_labels2.tsv
# ref<TAB>verdict labels for --eval-stray (the first three local branches, resolved at capture time; a missing branch is padded with a nonexistent name on purpose)
arm/for-howitworks-067-f2add	merged
arm/for-howitworks-067-placebo	unmerged
arm/orient-map-067-narrow	merged
```

### `--eval`

**Answers:** self-eval (co-change recall vs BM25)

**Try it**

_Self-eval: co-change recall vs BM25._

```
$ ./build/ripwire . --eval
ripwire --eval  (co-change recovery, averaged over 80 historical commits)
  ranker     recall@5  recall@10  recall@20
  ripwire        1.2%       8.5%      12.7%
  BM25          14.0%      14.9%      20.9%
  BM25sub       15.8%      23.8%      31.8%
  BM25body      11.3%      24.2%      39.4%
  fused         11.3%      23.0%      29.6%
  anchored      11.3%      24.2%      39.4%
  same-dir       0.2%       1.8%       6.1%
  random         0.2%       0.4%       0.7%   <- floor (random ranking over F=2688 files)
  note: `ripwire` here is the DEFAULT MAP's structural-only PageRank (importance, not
        relatedness) — it is NOT what a --for/--query retrieval call ranks with. BM25 /
        BM25sub / BM25body are QUERY-TIME lexical rankers (whole-name / subtoken /
        subtoken+body); fused = RRF(ripwire, BM25sub); anchored = BM25body + anchored PPR
... [5 more line(s); run it to see the whole thing]
```

**Shaped by:** `--legend`

### `--eval-retrieval`

**Answers:** measure the rankers on known-item retrieval — MRR and recall@1/5/10 per query mode known-item retrieval eval: for symbols WITH a doc-comment, query by NAME and by a doc-comment PHRASE;

reports MRR + recall@1/5/10 per ranker (subtoken+body, name-exact, anchored, routed) per query-mode. Validates query-TIME ranker choice.

**Try it**

_Known-item retrieval eval: MRR + recall@k per ranker per query mode._

```
$ ./build/ripwire . --eval-retrieval
ripwire --eval-retrieval  (known-item, 4000 doc-commented symbols; gold is in-corpus by construction)
  sample: population=6431 scored=4000 rule=smallest-key CAPPED — a SUBSET, not the population
          (smallest fnv1a64(scope::name) over the population, cut on the key so an identity is never split;
           path- and order-independent, but a corpus this size is NOT graded exhaustively — say so when citing it)
  ingest: lex=rich (persisted subtoken stats; no per-query corpus re-tokenize)
  ranker    query-mode     MRR  recall@1  recall@5 recall@10
  subtoken  name         0.680     54.7%     84.4%     90.0%
  subtoken  doc-phrase   0.913     89.0%     93.5%     94.7%
  name-exact name         0.892     81.3%     95.7%     97.0%
  name-exact doc-phrase   0.013      0.5%      1.8%      2.6%
  anchored  name         0.688     56.6%     83.7%     88.3%
  anchored  doc-phrase   0.910     88.5%     93.5%     94.3%
  routed    name         0.895     81.5%     95.9%     97.2%
  routed    doc-phrase   0.911     89.0%     93.3%     94.4%
... [6 more line(s); run it to see the whole thing]
```

### `--eval-mined=FILE`

**Answers:** retrieval eval over real (query, gold-files) pairs mined from session traces session-trace-mined retrieval eval: consumes a minedpair.jsonl artifact from bench/mine_traces.py (real (query, gold-files) pairs mined from local Claude Code session transcripts) and reports recall@5/10/20 + Acc@k + MRR per arm (for/query/anchor/random), assisted vs unassisted.

### `--eval-skills=FILE`

**Answers:** measure skill routing against a labelled prompt corpus labelled skill-ROUTING eval: ROOT is a skills directory (one SKILL.md per subdir);

FILE is TSV `prompt<TAB>skill[,skill]|none<TAB>provenance`. Scores deterministic selectors (keyword overlap = the trivial baseline, BM25 over descriptions/full text, name match, the routed --for ranker) on top-1-in- permitted-set plus positive/negative separation (AUC) — does the right skill fire, does every skill stay quiet on off-topic prompts. Ambiguous moments carry a permitted SET; `none` rows are first-class.

**Try it**

_Labelled skill-ROUTING eval over the repo's own skills/ directory (4 hand-labelled prompts)._

```
$ ./build/ripwire skills --eval-skills=<scratch>/aux/skills_labels2.tsv
orient in an unfamiliar codebase fast	ripwire-orient	judged
who calls this function and what is the blast radius	ripwire-navigate	judged
plan parallel worktrees so the lanes do not collide	ripwire-change-check	judged
what is the weather in Paris	none	neg
```

**Caveats (stated by the binary):**

- Ambiguous moments carry a permitted SET;

### `-h, --help`

**Answers:** this catalog, one line per flag  (--help=--FLAG, --help=SECTION, or --help=all)

**Shaped by:** `--html`, `--color-by`, `--around`, `--callers`, `--callees`, `--affected`, `--expand`, `--metrics`

### `-v, --version`

**Answers:** print the version + short build info, exit 0

**Try it**

_Version + short build info._

```
$ ./build/ripwire --version
ripwire 0.6.5 (dev, AppleClang 21.0.0.21000101, emit=std::print, built_from=f1e5c2e76)
```

**Shaped by:** `--verify`, `--metrics`, `--deps`, `--naming-locals`, `--arch`, `--dry-run`, `--doc-drift`, `--from-trace`

---

_Generated by `docs/docs_commands_build.py`. See `docs/README.md` for the documentation index._
