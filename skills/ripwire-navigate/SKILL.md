---
name: ripwire-navigate
description: >
  Trace how code connects and understand ONE symbol in depth — who calls a function, what it calls, how one
  symbol reaches another, the flow from A to B or a bounded neighborhood around one definition, a full-body
  deep-dive of a named symbol with its callers/callees/design-docs, or
  find a literal / regex / AST-shape with its enclosing symbol. Use when you know (or can name) the symbol
  and need the call graph, its contract, or to locate code precisely — instead of grepping and guessing.
  Also the answer to "is it safe to change X?" (blast radius, not just 1-hop callers). And the N-way
  relate moment: a ticket names THREE OR MORE symbols or layers and you cannot see how they meet —
  `--connect=A,B,C` returns the minimal subgraph tying them together, including the shared-caller join a
  pairwise A-to-B path never sees. Run the ONE verb
  that matches the question; when its answer is unambiguous, stop — don't stack callers + callees +
  impact as a ritual. Backed by ripwire (deterministic, on PATH).
allowed-tools: Bash, Read
---

# Navigate with ripwire

> Nearest neighbours:
> • You DON'T know the symbol yet — orienting on a whole repo/subsystem → **ripwire-orient**.
> • You have a symptom and need to FIND the buggy code → **ripwire-find-bug**.
> • Your question needs to COMBINE conditions (cx + fanin + file + reachability) → **ripwire-graph-query**.
> • "Is this diff safe to merge" (not "is it safe to touch this symbol") → **ripwire-change-check**.

`<dir>` = the repo or subsystem. Calls are warm after the first parse. Tracing across a split
service+client checkout — pass every root, `ripwire dir1 dir2 --impact=SYM` — the merged graph carries the
cross-root evidence edges (include/import/FFI) a single-root call would never see.

## `--callers` is 1-hop — don't let it answer "is it safe to change X?"

`--callers=SYM` gives direct in-edges only. It under-counts on purpose (it's the *cheap* verb) — a caller
two hops away, a read/write that never calls SYM, or an `#include` that pulls it in all fall outside a
1-hop answer. Match the verb to the question:

- **"Is it safe to change/delete X?"** → `ripwire <dir> --impact=SYM` (transitive blast radius: everything
  that transitively reaches SYM through the call graph, not just direct callers) **+**
  `ripwire <dir> --uses=SYM` (the resolvable use-sites by role — `call|read|write|import|extends` — file:line; catches
  non-call references `--callers` never sees, e.g. a struct read or a header import). Run both — `--impact`
  gives depth (the call chain), `--uses` gives breadth (kinds of reference). `--callers` alone is the wrong
  tool for this question; reach for it only when you already know the change is local.
- **"Who calls this, one hop"** (quick sanity check, not a safety judgment) → `--callers=SYM`.
- **"Where is this VARIABLE defined and used inside one function"** → `--slice=SYM:VAR` — per-line
  def/use rows (declaration/assignment/param vs read) inside the one resolved definition; bare
  `--slice=SYM` lists the sliceable locals first. Name-based and intra-procedural — the legend states
  the limits — so it answers "what touches this variable here" without reading the whole body.
- **"Where did this variable's VALUE come from / what does it flow into"** (still inside one function)
  → add `--slice-flow=back|fwd|both` — the transitive cross-statement data-flow slice over
  reaching-definition def-use edges: `back` = the statements whose values feed the seed variable,
  `fwd` = the statements its value reaches; each flow row carries the variable (`v=`), the BFS depth
  (`d=`) and the line it was reached from (`f=`). `--slice-depth=N` bounds the walk (default 8; a
  bound that cuts is disclosed as `flow_truncated="1"`). Stops at the function boundary by design —
  the inter-procedural half is `--callers`/`--impact`.
- **"I have a FILE:LINE, not a name"** (a compiler error, a diff hunk, a stack frame) →
  `ripwire <dir> --at=FILE:LINE` — the enclosing-definition chain at that location, outermost→innermost;
  `sym=` names the innermost. The SAME seed composes into any SYM selector as `@FILE:LINE`
  (`--callers=@src/f.cpp:120`, `--expand=@…`, `--edit-check=@…`, `--slice=@FILE:LINE:VAR`) and resolves
  to that innermost definition — skip the "what is this function called" grep entirely. A seed on a
  blank top-level line, an ambiguous path, or a line two definitions share is refused with a specific
  diagnosis, never guessed.
- **"I have a FILE:LINE and want the variable story THERE"** → `--slice=@FILE:LINE` (or `--at=FILE:LINE`
  beside any `--slice` spec — the pair composes as the slicer's seed, ARISE's own
  `(file, line[, variable])`). A seed line naming exactly ONE sliceable local pre-picks it (disclosed:
  `seed=`, `var_from="seed"`); zero or several serve the locals inventory with the candidates marked
  `seed="1"` — pick one and re-run with `:VAR`. A plain identifier beside `--at` reads as the seed's
  variable (`--slice=out --at=src/f.cpp:12`), and the seed also narrows an ambiguous SYM to the
  definition enclosing the line.
- **"Trace a FLOW: how does A reach B"** → `--path=A,B` (shortest call-path) or `--around=SYM
  [--around-depth=2]` (bounded neighborhood). Not `--for` — `--for` returns a ranked *set* of relevant
  signatures for a task, it does not trace a path between two named points.
- **"N task symbols — how do A, B and C RELATE, which intermediaries join them?"** →
  `ripwire <dir> --connect=A,B,C [--connect-radius=N]` — the minimal connecting subgraph: your terminals,
  the fewest joining intermediaries (with signatures), and the call edges in true caller→callee direction.
  Reach for `--connect` over `--path` in two cases: **N>2 symbols** (`--path` only ever takes SRC,DST — it
  has no notion of a third point), or **a pair `--path` calls unreachable**. The search is undirected, so it
  finds the *shared caller* joining two symbols — the most common way task symbols relate, which a directed
  `--path` can never see (`--path=A,B` says `reachable="0"` even when `main` calls both). Symbols that can't
  meet within the radius appear honestly in `<unconnected>`.

## Trace the call graph / locate code

- **Who calls / what it calls** — `ripwire <dir> --callers=SYM` · `ripwire <dir> --callees=SYM`
- **The resolvable use-sites of a name** (role=call|read|write|import|extends, file:line; `counts_floor="1"` — the count is a floor) — `ripwire <dir> --uses=SYM`
- **Transitive blast radius** — `ripwire <dir> --impact=SYM`
- **Neighborhood** (bounded k-hop ego graph) — `ripwire <dir> --around=SYM [--around-depth=2] [--around-fanout=32]`
- **How does X reach Y** (shortest call-path) — `ripwire <dir> --path=SRC,DST`
- **How do N symbols relate** (minimal connecting subgraph, shared-caller joins) — `ripwire <dir> --connect=A,B,C [--connect-radius=N]`
- **Verify a CLAIM in one call** — "does X really call Y?", "is Z ever used?", "does this file contain/define A?" →
  `ripwire <dir> --verify='calls(A,B)'` (also `uses(SYM)` / `unused(SYM)` / `contains(FILE, "LIT")` /
  `defines(FILE, SYM)` / `reaches(SYM, "FILE")`): one three-valued verdict with the evidence inline —
  `confirmed` (witness printed) · `refuted` (only with complete evidence; a clean literal-scan no carries
  `complete="1"`) · `not-established` (`limit=` names the floor: dynamic dispatch and string-keyed references
  are invisible to the index, so this verdict is honest "the index cannot prove it", never "false").
  Replaces the grep-then-read chain you would otherwise run to check the claim yourself.
- **Find a literal / regex / structural shape** —
  `ripwire <dir> --grep=STR` (literal + enclosing symbol) ·
  `ripwire <dir> --regex=PAT` ·
  `ripwire <dir> --match='(<tree-sitter query>)'` (e.g. `(call_expression function: (identifier) @c)`) ·
  **`ripwire <dir> --pattern='foo($X, ...)'`** — the same structural search written in CODE instead of in
  node kinds, so you do not have to know whether this grammar calls it `call_expression`, `call`,
  `method_invocation` or `invocation_expression`. `$NAME` binds one node (repeat it and both sites must
  match), `$_` binds nothing, `...` (or `$$$`) is an ellipsis over siblings. ONE pattern searches every
  served language at once — c, cpp, objc, java, csharp, javascript, typescript, python, go, rust, swift —
  and `grammars=`/`shapes=` on the result name which ones it resolved for and what node kind it became in
  each. Reach for `--pattern` when you can WRITE the shape and for `--match` when you need a constraint the
  pattern language cannot express (a field name, a `#match?` predicate). Ruby, bash and the data tiers are
  refused by name, never answered with a zero.
  — add `--grep-context=N` (or `--grep-before=N`/`--grep-after=N`) for ripgrep-style N lines of source
  around each hit, so you see the call site's shape without a follow-up `--expand`.
  When one grep answers a two-term question ("cache staleness check for the MCP index"), narrow it in the
  SAME call instead of grepping again and eyeballing the intersection: `--and=B` (repeatable) keeps only
  hits where B is ALSO present, `--not=C` (repeatable) drops hits where C IS present — literal-only, so
  they pair with `--grep=`, not `--regex=`. `--grep-scope=line` (default) requires the extra term on the
  SAME matched line; `--grep-scope=file` widens that to anywhere in the same file.
  Hits are SPAN-TIERED by default: a hit inside a comment or a string literal is a mention, not a use, so
  the answer serves the CODE tier when any hit is code — and when none is, the ladder COLLAPSES and it
  serves comment **and** string together as `tier="comment+string"` (so pasting an error message reaches
  the string literal that emits it, not just some gate script's comment about it; a pattern that lives only
  in prose is still answered, never emptied) — and says what it held back via
  `suppressed_comment=`/`suppressed_string=`. When those counters appear and the mention IS what you were
  after (an error-message string, a design note), re-ask with `--grep-in=any` for every tier.

`--callers`/`--callees` answer from the call graph directly — no separate index step. Edges are name-based:
a high-rank symbol with no callees may be a dispatch hub (virtual/callback/macro), not a leaf — read it.

**What a high `amb=` should CHANGE about your next action**: `amb="K"` on a symbol means K of its outgoing
calls matched more than one same-named definition and the resolver guessed. Don't treat that edge as fact —
before you rely on it to judge safety or trace a flow, open the source at that call site and confirm which
definition it actually resolves to (or overlay `--scip=index.scip` if you have a compiler index; matched
edges get `prov="scip"` and stop being a guess). A high-rank symbol with a high `amb=` and an `--impact`
result you're about to act on is exactly the case where "read the source" isn't optional.

**Sharper trust with a SCIP index** — `ripwire <dir> --scip=index.scip` overlays compiler-backed precise
edges on top of the name-based graph: a matched edge is tagged `prov="scip"` and its `amb=` risk drops (it's
no longer a guess). Edges `--scip` didn't cover keep their plain name-based status — `amb="K"` on a symbol
still means K of its calls are guessed, `prov=` absent or not. Read `prov="scip"` as "trust this edge more
than an unmarked one," not as "the whole symbol is now precise." A missing/corrupt index degrades silently
to all-name-based (same output as not passing `--scip`) — check header `precise=N` to confirm the overlay
actually matched anything.

## Deep-dive ONE symbol — understand it before editing

When you need to understand a specific function/class/concept in full (its body, contract, and rationale):

1. **Full body + callee signatures** — `ripwire <dir> --expand=SYM`
   The ranked map, then `<bodies>` with SYM's full source in CDATA and a `<calls>` block of inline one-line
   signatures for everything it calls — read the body with the callee signatures beside it. (No `<doc>` block
   here; SYM's own doc-comment is in the CDATA body if it sits inside the definition — otherwise read the
   source lines just above `l=`.)
   About to Edit what you just expanded? If your edit tool needs a fresh native Read of the file first
   (true of Claude Code's Edit; other harnesses may differ), the served body doesn't satisfy that — but the
   read doesn't need to start at line 1: Read at `l=`, not the whole file. Same for a `--for` hit before
   you've expanded it — its `<d>` row carries `l=` too. Over MCP, skip the Read requirement altogether —
   see ripwire-mcp's edit verbs.
2. **Who calls it** — `ripwire <dir> --callers=SYM` → `<callers of="SYM" count="N">` with type, name,
   file:line. Callers reveal SYM's contract from the outside — expected preconditions.
3. **What it calls** — `ripwire <dir> --callees=SYM` → cross with the `--expand` body to understand the flow.
4. **Design docs that mention it** — `ripwire <dir> --mentions=SYM` → `<mentions of="SYM" defs="D" docs="N">`
   listing markdown files that backtick-name SYM: the design decisions and rationale around this symbol.
5. **Neighborhood** (optional, when callers+callees don't close the picture) — `ripwire <dir> --around=SYM
   [--around-depth=2]`.
   → **Explanation:** what SYM does (from the body + `<calls>`), who calls it and why, what it coordinates,
   and any design rationale (from `--mentions`). Note `amb="K"` if call edges are ambiguous — verify in source.

## Editing a STRUCT whose bytes cross a boundary — `--layout=STRUCT`

For a plain function, the deep-dive above is the whole story. For a **struct/class whose bytes are a
contract with something outside this compiler** — a GPU uniform block, a wire/IPC/file-format record, a
type mirrored into a stub or a second checkout — the question before you edit is not "who calls it" but
"what is the byte layout, what pins it, and who else declares it":

```bash
ripwire <dir> --layout=AudioUniforms         # file:name disambiguates, like --around/--lego
```

One call gives three things: the fields in declaration order with **computed** offsets/sizes and every byte
of padding made explicit; every `static_assert` in the index that mentions the type, with `agree="0"` when
a `sizeof(X)==N` tripwire contradicts the computed size; and **every same-name definition**, compared field
by field. It **exits 2** when the contract is broken — `mirror="mismatch"` (`kind="drift"`: two populated
definitions disagree) or a contradicted tripwire — so it works as a pre-commit check, not just a report.
`kind="stub"` (an empty placeholder) and `kind="spelling"` (`simd::float4` vs `float4` — the two arms of
one `#ifdef`) are reported but exit 0.

**Believe the caveats.** The offsets are a MODEL, not the ABI: a lexical walk under standard-layout
assumptions on a 64-bit LP64 target. When it cannot see the truth it says `modeled="0"` with a named
`<caveat>` instead of printing a number — `#pragma pack`, bitfields, virtuals, base classes, nested or
anonymous aggregates, `#if`-conditional members, templates, and any field type it cannot size. One unsized
field un-places every field after it. A `modeled="1"` number that agrees with the type's own
`static_assert` is trustworthy; a `modeled="0"` def is telling you to read the source.

## `--query` (lexical) vs `--for` (task lens)

- `ripwire <dir> --query="terms"` — **pure BM25 relatedness**: the map re-ranked by lexical match against
  your terms, nothing else. Use it when you want *what mentions these words*, uncolored by importance —
  chasing a domain term, an error string's neighborhood, a concept's vocabulary.
- `ripwire <dir> --for="task in words"` — the **task lens**: relevance-ranked *signatures* plus doc-comments
  and cx/in metrics, framed for reuse ("compose from these"). Use it when the question is "what should I
  build on / touch for THIS task".
- Rule of thumb: `--for` for a task you're about to do; `--query` for a vocabulary you're hunting. Both shine
  on specific technical wording; for broad common-word asks, plain `rg` + one read can still win.

## When the fixed verbs can't phrase the question

Compose filters over the call graph with `--graph-query=EXPR` — see **ripwire-graph-query** for the
mini-language (sources · kind/cx/fanin/file filters · bounded callers/callees closure · and/or/not joins).
