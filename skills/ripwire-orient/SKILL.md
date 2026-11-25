---
name: ripwire-orient
description: >
  Landing COLD in an unfamiliar repo or subsystem, or about to open several files for one question: map
  first, read only what it ranks highest — main subsystems, entry points, 'how does X work / where is
  Y'. Also recover context after compaction, retrieve saved docs (--recall), divide code for subagents
  (--partition), save gotchas (--note-add). NAMED symbol → navigate. Stop at the first rung that
  answers.
allowed-tools: Bash, Read
---

# Orient with ripwire

> Routing: a named symbol → **ripwire-navigate** · your own diff → **ripwire-change-check** · risk in code you did not
> write → **ripwire-fresh-eyes** · architecture gates → **ripwire-layers**.

`<dir>` = the repo root or the subsystem (a `git-url`, or several roots, also work). The first call parses (~1s at
1,500 files); later calls are warm.

## Stop at the first rung that answers

| You need | Run |
|---|---|
| what past sessions or design docs already say (first: a doc may already answer) | `ripwire <dir> --recall="<the task>"` |
| the one-call orient: ranked map, subsystems, entries, files the ranking left out (`<inv>`) | `ripwire <dir>` (once per session) |
| an architecture summary a human reads: modules, god-files by `afferent`, cycles | `ripwire <dir> --report` |
| "where is the code for X / how does X work" | `ripwire <dir> --for="<the task in your own words>"` |
| everything under one budget: ranking + top bodies + callers + notes + tests | `ripwire <dir> --pack-task="<task>" --legend=compact` |
| a file-by-file view, or cohesive modules | `ripwire <dir> --tree --legend=compact` · `ripwire <dir> --communities --legend=compact` |

A `--for` answer comes answer-first in ~12 KB pages; stop once the answer is in hand, else its `next=` (`--page-bytes=N:K`) is the next page.

**In Claude Code's main conversation**, delegate a code lookup to the `ripwire-locator` subagent
and ask it for edit ranges: it runs the `--for` in its own context and returns only `path:start-end` lines. Run a full `--for` in the main
thread only when you need the whole map.

Then read lean: `--expand` / `--outline` / `--whereis` / `--callers` answer with no ride-along map. Read every range
the answer lists (`path:L-E`; a page's `<act read=>` names the top ones) in ONE turn of parallel ranged Reads — not
whole files, not a grep sweep; search only for what it marks missing.

**Resuming after a compaction:** `ripwire . --recall="<the task>"` → `ripwire . --situ` (what the tree already changed,
tests to run) → `ripwire . --notes` (gotchas already paid for). **Learned a gotcha?**
`ripwire . --note-add="SYM_or_path: the decision"` — it resurfaces whenever `--for`/`--expand` emit that symbol.
**An expected symbol is missing:** a header `skipped_oversize=N` → `ripwire <dir> --skipped --legend=compact`; else `--doctor`.

## Trust

A thin `--for` answer means widen the query, not read everything. A zero means "none found", never "none exists"; a
count marked as a floor is not a total; `amb="K"` = K calls hit an ambiguous name — read the source if the target matters.

## Reference files — read only the one you need

| You need | Read |
|---|---|
| every rung in full: `--recall` rules, `--for` routing and selectors, widening a thin answer, budgets | `ladder.md` |
| orienting N agents (`--partition=N`, `--plan-lanes`), or a big repo (`--zoom`, `--mermaid`, `--export`) | `partition-zoom.md` |
| one page to paste into a fresh code-editing subagent: `--brief="TASK"` (layout, quoted build/test commands, entries, act ranges, edges; 2.5/4/6 KB) | `subagent-brief.md` |
| the three-moment block to paste into a subagent brief | `subagent-brief.md` |
| honesty signals, field notes, resuming, mid-task reads | `notes-resume.md` |
| the map-before-you-read discipline for any read (`--expand`, symbol-range reads, edit verbs) | `map-before-you-read.md` |
| squeezing a body you are already reading (`--compress`, `--outline`, the detail ladder) | `compress-ladder.md` |
