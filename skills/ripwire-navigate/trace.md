# ripwire-navigate — reference: trace (read on demand; the recipe is in SKILL.md)

## Trace the call graph / locate code

- **Who calls / what it calls** — `ripwire <dir> --callers=SYM --legend=compact` · `ripwire <dir> --callees=SYM --legend=compact`
- **The resolvable use-sites of a name** (role=call|read|write|import|extends, file:line; `counts_floor="1"` — the count is a floor) — `ripwire <dir> --uses=SYM --legend=compact`
- **Who reads/writes a MEMBER VARIABLE** (`t="field"` symbols; per-site owner resolution, `owner_candidates=K` where several owners could match, never a silent pin) — `ripwire <dir> --uses=Owner.field --legend=compact`
- **Transitive blast radius** — `ripwire <dir> --impact=SYM --legend=compact`
- **Neighborhood** (bounded k-hop ego graph) — `ripwire <dir> --around=SYM --legend=compact [--around-depth=2] [--around-fanout=32]`
- **How does X reach Y** (shortest call-path) — `ripwire <dir> --path=SRC,DST --legend=compact`
- **Which definitions does a name bind** (each with `sel=`, the spelling that picks it alone in any verb above) — `ripwire <dir> --defs=NAME[,NAME…] --legend=compact`
- **How do N symbols relate** (minimal connecting subgraph, shared-caller joins) — `ripwire <dir> --connect=A,B,C --legend=compact [--connect-radius=N]`
- **Verify a CLAIM in one call** — "does X really call Y?", "is Z ever used?", "does this file contain/define A?" →
  `ripwire <dir> --verify='calls(A,B)' --legend=compact` (also `uses(SYM)` / `unused(SYM)` / `contains(FILE, "LIT")` /
  `defines(FILE, SYM)` / `reaches(SYM, "FILE")`): one three-valued verdict with the evidence inline —
  `confirmed` (witness printed) · `refuted` (only with complete evidence; a clean literal-scan no carries
  `complete="1"`) · `not-established` (`limit=` names the floor: dynamic dispatch and string-keyed references
  are invisible to the index, so this verdict is honest "the index cannot prove it", never "false").
  Replaces the grep-then-read chain you would otherwise run to check the claim yourself.
- **Find a literal / regex / structural shape** —
  `ripwire <dir> --grep=STR --legend=compact` (literal + enclosing symbol) ·
  `ripwire <dir> --regex=PAT --legend=compact` ·
  `ripwire <dir> --match='(<tree-sitter query>)' --legend=compact` (e.g. `(call_expression function: (identifier) @c)`) ·
  **`ripwire <dir> --pattern='foo($X, ...)' --legend=compact`** — the same structural search written in CODE instead of in
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
than an unmarked one," not as "the whole symbol is now precise." A path that is missing, empty or not a
regular file refuses (exit 1); a corrupt index warns on stderr and proceeds all-name-based (same stdout as not
passing `--scip`) — check header `precise=N` to confirm the overlay actually matched anything.
