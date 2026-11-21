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
| "where is the code for X / how does X work" | `ripwire <dir> --for="<the task in your own words>"` |
| everything at once under a budget: ranking + top bodies + callers + notes + tests | `ripwire <dir> --pack-task="<task>" --legend=compact` |
| a file-by-file view, or cohesive modules | `ripwire <dir> --tree --legend=compact` · `ripwire <dir> --communities --legend=compact` |

A `--for` answer comes answer-first in ~12 KB pages; stop once the answer is in hand, else its `next=` (`--page-bytes=N:K`)
is the next page.

After the orient call, look up lean: `--expand` / `--outline` / `--whereis` / `--callers` answer with no
ride-along map. Then read only the files ripwire ranks highest (god-files and hotspots first) — not a grep sweep.

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
| writing a brief for a subagent: the three-moment block to paste (`--for` before reading source; `--expand`/`--callers`/`--impact` before the first edit; `--quality-delta` then `--test-gate` before done) | `subagent-brief.md` |
| honesty signals in full, field notes, resuming, mid-task reads | `notes-resume.md` |
| the map-before-you-read discipline for any read, mid-task (`--expand`, symbol-range reads, edit verbs) | `map-before-you-read.md` |
| squeezing a body you are already reading (`--compress`, `--outline`, the detail ladder) | `compress-ladder.md` |
