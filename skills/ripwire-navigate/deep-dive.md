# ripwire-navigate — reference: deep-dive (read on demand; the recipe is in SKILL.md)

## Deep-dive ONE symbol — understand it before editing

When you need to understand a specific function/class/concept in full (its body, contract, and rationale):

1. **Full body + callee signatures** — `ripwire <dir> --expand=SYM --legend=compact`
   `<bodies>` with SYM's full source in CDATA and a `<calls>` block of inline one-line signatures for
   everything it calls — read the body with the callee signatures beside it. No ranked map rides along (orient
   ONCE per session with `ripwire <dir>`, then look symbols up lean); a bare name with several definitions
   serves them all, still map-free — `map_next=` on the root is the call that prints the map if you skipped
   orienting, and `unserved_next=` is the call serving the definitions a byte budget cut (the first `unserved_listed=` of
   them when that attribute is present; `unserved_total=` is the true count). (No `<doc>` block
   here; SYM's own doc-comment is in the CDATA body if it sits inside the definition — otherwise read the
   source lines just above `l=`.)
   About to Edit what you just expanded? If your edit tool needs a fresh native Read of the file first
   (true of Claude Code's Edit; other harnesses may differ), the served body doesn't satisfy that — but the
   read doesn't need to start at line 1: Read at `l=`, not the whole file. Same for a `--for` hit before
   you've expanded it — its `<d>` row carries `l=` too. Over MCP, skip the Read requirement altogether —
   see ripwire-mcp's edit verbs.
2. **Who calls it** — `ripwire <dir> --callers=SYM --legend=compact` → `<callers of="SYM" count="N">` with type, name,
   file:line. Callers reveal SYM's contract from the outside — expected preconditions.
3. **What it calls** — `ripwire <dir> --callees=SYM --legend=compact` → cross with the `--expand` body to understand the flow.
4. **Design docs that mention it** — `ripwire <dir> --mentions=SYM --legend=compact` → `<mentions of="SYM" defs="D" docs="N">`
   listing markdown files that backtick-name SYM: the design decisions and rationale around this symbol.
5. **Neighborhood** (optional, when callers+callees don't close the picture) — `ripwire <dir> --around=SYM --legend=compact
   [--around-depth=2]`.
   → **Explanation:** what SYM does (from the body + `<calls>`), who calls it and why, what it coordinates,
   and any design rationale (from `--mentions`). Note `amb="K"` if call edges are ambiguous — verify in source.

## Editing a STRUCT whose bytes cross a boundary — `--layout=STRUCT`

For a plain function, the deep-dive above is the whole story. For a **struct/class whose bytes are a
contract with something outside this compiler** — a GPU uniform block, a wire/IPC/file-format record, a
type mirrored into a stub or a second checkout — the question before you edit is not "who calls it" but
"what is the byte layout, what pins it, and who else declares it":

```bash
ripwire <dir> --layout=AudioUniforms --legend=compact         # file:name disambiguates, like --around/--lego
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

- `ripwire <dir> --query="terms" --legend=compact` — **pure BM25 relatedness**: the map re-ranked by lexical match against
  your terms, nothing else. Use it when you want *what mentions these words*, uncolored by importance —
  chasing a domain term, an error string's neighborhood, a concept's vocabulary.
- `ripwire <dir> --for="task in words"` — the **task lens**: relevance-ranked *signatures* plus doc-comments
  and cx/in metrics, framed for reuse ("compose from these"). Use it when the question is "what should I
  build on / touch for THIS task".
- Rule of thumb: `--for` for a task you're about to do; `--query` for a vocabulary you're hunting. Both shine
  on specific technical wording; for broad common-word asks, plain `rg` + one read can still win.

**Budgeting trap:** a positive, explicit `--top-k` is inert on plain `--for` — the run warns on stderr and
emits the full bundle anyway. (`--for --format=candidates --top-k=N` is different: the export consumes the
flag and caps the rows, no warning. `--for --top-k=0` is refused by the payload-only guard.)
Narrow plain `--for` with its own arguments: `--signatures-only` (no auto-bodies), `--token-budget=N` (shapes
the bundle to fit), `--detail=N` (full bodies for just the top N). `--top-k` does shape `--query`. `--expand`/`--outline` need no
`--top-k=0`: they drop the map by default whenever every definition asked for is served (`topk_default="0"`),
an ambiguous bare name included; pass `--top-k=N` only if you want the map back in the same call.

## When the fixed verbs can't phrase the question

Compose filters over the call graph with `--graph-query=EXPR` — see **ripwire-graph-query** for the
mini-language (sources · kind/cx/fanin/file filters · bounded callers/callees closure · and/or/not joins).
