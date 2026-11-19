# ripwire-mcp — reference: session-legend (read on demand; the recipe is in SKILL.md)

## The per-session legend: each definition once per session

On the stdio server the legend session opens with the first answer that carries a legend (served inline) or
with a read of the MCP resource `ripwire://legend-dict` (`initialize` names it). After that, the verbs that take
`legend` (and `for`) answer rows first and end with `<about legend="ref" dict= dictv=/>`, which is only the
pointer to the legend: the root keeps every attribute it carries inline — `capped=`, `has_more=`,
`next_offset=`, `counts_floor=`, `root=` — so read cuts and floors off the root, as always; a definition arrives once per session, in a comment after the rows of the first answer that
needs it (an answer whose ref form would be longer stays inline). Lost the definitions (a compacted context)?
Read `ripwire://legend-dict/full` for all of them, or print them with `ripwire --legend-dict`.
`legend:"compact"` on one call keeps that answer's legend inline; a server started with
`--mcp --mcp-legend=inline` keeps every answer's legend inline. The HTTP transport (`--listen`) keeps every
legend inline.

### On the CLI, say which definitions you hold: `--legend-have=`

The CLI has no session, so it cannot know what you were already sent. You tell it — and you may only
tell it what is actually in your context. `--legend-have` is a statement that you READ those lines,
not a switch that makes answers shorter.

Read the core once (13 definitions, about 1.5 KB — read all of it, not its first line):

```
ripwire --legend-dict=core
```

Its first line carries `have=<16 hex>`. Pass that value on later calls:

```
ripwire ROOT --callers=SYM --legend-have=<that value>
```

The answer then comes back rows first, its root unchanged, ending `<about legend="ref" have="core" …/>`. The
definitions you hold are left out. Every definition you do NOT hold is still in the answer, in a
comment after the rows — read it there. You are never expected to open the full dictionary.

About to call the same verb three or more times? Read its pack too (the core plus 0.4–2.3 KB for the
everyday verbs, core included in the text):

```
ripwire --legend-dict=callers        # first line: have=<16 hex> pack=callers
```

and pass that value instead: `--legend-have=<pack value>`. Holding several packs: join the values
with commas. `ripwire --legend-dict=tiers` lists every pack and its size.

**When it is worth it.** Measured over 453 answers across twelve verbs on five corpora: the core is 1,512 B and
removes 149 B per call, so it pays for itself after **11 calls** (9 over the 388 answers that are not
`--for`; by corpus, 9 to 17). A pack pays for itself within 3 calls of its verb (1.3–2.0 measured) and
removes most of that verb's legend, 0.3–1.7 KB per call. Core plus the verb's own pack keeps 86 % of
what holding the whole dictionary saves. For a session of fewer than about 10 ripwire calls, pass
nothing: the default answer already defines only what it carries.

**What it does not do.** `--for` answers are unchanged by it (0 of 65 reduced), and stderr says so on
each one. A percentage quoted for this flag is over a named set of answers; ask for the n.

Never pass a value whose lines you have not read in this context, and after your context was
compacted, read them again or stop passing it. The first line alone gives you a value and none of
the definitions it stands for.

Refusals, all deliberate: an empty value; a value this binary does not recognise, even beside a valid
one (the tier changed — run the `--legend-dict=core` command the message names); `--mcp`/`--listen`/`--lsp`
(the server already sends each definition once); `--legend=full`. The whole dictionary still works as a
holding (`ripwire --legend-dict`, its `dictv=`; about 160 KB; about 130 calls to repay, measured when it was 131 KB) and is not the
handshake to reach for.

### Or name the definitions you RECEIVED: `--legend-seen=FILE`

Per definition, no tiers to read first. Pipe each answer you received into `ripwire --legend-dict=seen`
and append what it prints to a file; pass that file on later calls:

```
ripwire ROOT --for="TASK" | tee answer.xml          # read it as usual
ripwire --legend-dict=seen <answer.xml >>seen.txt   # the entry hashes it carried
ripwire ROOT --for="OTHER TASK" --legend-seen=seen.txt
```

The answer leaves out exactly the definitions `seen.txt` names — `--for`'s trailing legend and block legends
included — and says so where it left them (`[legend-seen: N held]`) and once with the `dictv=` of the
dictionary that holds them all. Rows are byte-identical. A missing or corrupt file serves the whole answer
(stderr says so); it never refuses. In Claude Code, `skills/install.sh --hook` keeps this file for you per
session (the legend-seen hook under hooks/) and forgets it on compaction. Pass only what you received whole: an
answer you cut with `| head` should be scanned as cut.
