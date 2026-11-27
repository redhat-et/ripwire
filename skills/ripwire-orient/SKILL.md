---
name: ripwire-orient
description: >
  Landing COLD in an unfamiliar repo or subsystem, or about to open several files for one question:
  map first, read only what it ranks highest — main subsystems, entry points, 'how does X work /
  where is Y'. Also recover context after compaction, retrieve saved docs (--recall), divide code for
  subagents (--partition), save gotchas (--note-add). NAMED symbol → navigate. Stop at the first rung
  that answers.
allowed-tools: Bash, Read
---

# Orient with ripwire

> Routing: a named symbol → **ripwire-navigate** · vetting your own diff → **ripwire-change-check** · risk in
> code you did not write → **ripwire-fresh-eyes** · architecture gates → **ripwire-layers** · unsure →
> **ripwire-router**.

`ripwire` is on your PATH. The first call parses (~1s at 1,500 files); every call after is warm. `<dir>` = the
repo root or the subsystem; a `git-url` or several roots (`ripwire dir1 dir2 --report`) also work.

## The decision: which rung answers your question — stop at the first one that does

| You need | Run |
|---|---|
| what past sessions or design docs already say (do this first; a doc may already answer) | `ripwire <dir> --recall="<the task>"` |
| the one-call orient: ranked map, subsystems, program entries, the files the ranking left out (`<inv>`) | `ripwire <dir>` (once per session) |
| an architecture summary a human can read: modules, god-files by `afferent`, cycles | `ripwire <dir> --report` |
| new to the repo itself: an overview, how it is organized, where to start (about a quarter of `--for`'s bytes) | `ripwire <dir> --brief="<the question>"` |
| "where is the code for X / how does X work" | `ripwire <dir> --for="<the task in your own words>"` |
| everything at once under a budget: ranking + top bodies + callers + notes + tests | `ripwire <dir> --pack-task="<task>" --legend=compact` |
| a file-by-file view, or cohesive modules | `ripwire <dir> --tree --legend=compact` · `ripwire <dir> --communities --legend=compact` |

A `--for` answer comes answer-first in ~12 KB pages; stop once the answer is in hand, else its `next=` (`--page-bytes=N:K`)
is the next page.

**In Claude Code's main conversation**, delegate a code lookup to the `ripwire-locator` subagent (installed beside these
skills) and ask it for edit ranges: it runs the `--for` in its own context and returns only `path:start-end` lines, so the
whole answer does not ride every later request. Run a full `--for` in the main thread only when you need the whole map.

After the orient call, look up lean: `--expand` / `--outline` / `--whereis` / `--callers` answer with no
ride-along map. Then read only the files ripwire ranks highest (god-files and hotspots first) — not a grep sweep.
Read every range it lists (`path:L-E`; a page's `<act read=>` names its top ones) in ONE turn of parallel ranged
Reads, not one per turn and not whole files; don't re-search what ripwire listed, search only for what it marks missing.

**Resuming after a compaction** (you know the task, not your last hour): `ripwire . --recall="<the task>"` →
`ripwire . --situ` (what the working tree already changed + tests to run) → `ripwire . --notes` (gotchas
already paid for). Cheaper and more accurate than re-reading source.

**Learned a gotcha?** Pin it: `ripwire . --note-add="SYM_or_path: the decision, not a description"`. It
surfaces by itself whenever `--for`/`--expand` later emit that symbol.

**A symbol you expected is missing:** a header `skipped_oversize=N` means files were dropped for size —
`ripwire <dir> --skipped --legend=compact` lists them; if the file is not there, `--doctor` checks the setup.

## Stop rule and trust

Stop at the first rung that answers. A thin `--for` answer means widen the query before you read, not read
everything. A zero means "none found", never "none exists"; a count marked as a floor is not a total; `amb="K"`
on a symbol means K of its calls hit an ambiguous name — read the source if the target matters.

## Reference files — read only the one you need

| You need | Read |
|---|---|
| every rung in full: `--recall` dump rules, `--for` routing and selectors, thin-answer widening, budgets | `ladder.md` |
| orienting N agents at once (`--partition=N`, `--plan-lanes`), or a big repo (`--zoom`, `--mermaid`, `--export`) | `partition-zoom.md` |
| one page to paste into a fresh code-editing subagent: `--brief="TASK"` (layout, quoted build/test commands, entries, act ranges, edges, ranked files; 3.5/5/7 KB) | `subagent-brief.md` |
| writing a brief for a subagent: the three-moment block to paste (`--for` before reading source; `--expand`/`--callers`/`--impact` before the first edit; `--quality-delta` then `--test-gate` before done) | `subagent-brief.md` |
| honesty signals in full, field notes, resuming, mid-task reads | `notes-resume.md` |
| the map-before-you-read discipline for any read, mid-task (`--expand`, symbol-range reads, edit verbs) | `map-before-you-read.md` |
| squeezing a body you are already reading (`--compress`, `--outline`, the detail ladder) | `compress-ladder.md` |
