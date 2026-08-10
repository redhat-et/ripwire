---
name: ripwire-handoff
description: >
  Summarize a subsystem for another agent or teammate — "hand this area off". Use when you're about to
  brief someone else (not understand it yourself — that's orient) on a subsystem's purpose, key symbols,
  design rationale, and current maintenance risk — what the recipient needs and nothing stale, written as a
  summary of a repo area for the next agent (or
  teammate) to pick up. Produces a compact, pasteable brief instead of a wall of source code — signatures +
  full bodies of the 2-3 entry points, the design docs that explain WHY, and hotspot/bus-factor risk scoped
  to just that subsystem. Backed by ripwire (deterministic, on PATH).
allowed-tools: Bash, Read
---

# Handoff with ripwire

> Nearest neighbours:
> • You need to UNDERSTAND the subsystem yourself first (not brief someone else) → **ripwire-orient**.
> • You need ONE symbol's full contract, not a whole-subsystem brief → **ripwire-navigate** (`--expand`).
> • The recipient needs an architecture/layering read specifically → **ripwire-layers**.

Trigger: you're handing a subsystem to another agent or developer and want to give them a
fast, accurate brief — not a wall of source code.

`<dir>` = repo root. `SUBSYSTEM` = the area in plain words (e.g. "ingest pipeline",
"graph ranking", "MCP server loop").

1. **Task-relevant symbols** — `ripwire <dir> --for="SUBSYSTEM" --top-k=20`
   Output: `<sigs>` ranked by relevance. The top 10 are the symbols the recipient most needs
   to know. Note their file paths, complexity (`cx=`), and reuse count (`in=`).

2. **Expand the key symbols** — `ripwire <dir> --expand=SYM1,SYM2,SYM3`
   (Pick the top 3 by rank from step 1.)
   Output: full bodies + callee signatures. This is the actual contract — paste it into the
   handoff verbatim rather than paraphrasing. **Bodies are redacted by default** — high-confidence
   credentials (API keys, tokens, connection strings) are masked before you see them, so pasting this
   straight into a handoff doc is safe as-is; pass `--no-redact` only if you deliberately need the
   verbatim secret (e.g. auditing the credential-handling code itself).

3. **Design rationale** — `ripwire <dir> --recall="SUBSYSTEM"`
   Output: most relevant markdown docs (planning/design notes, READMEs) in full. Read and
   summarize the key decisions — why this design, not another. That's what the recipient most
   needs and least gets from reading code.
   Also check `ripwire <dir> --notes` for this subsystem's symbols/files — any gotcha a prior agent already
   pinned (`<note d="date">…</note>`) surfaces automatically on the symbols step 1/2 emit; fold it into the
   brief instead of letting the recipient rediscover it. Before you hand off, `--note-add="SYM_or_path:
   text"` any trap you found yourself that isn't already written down — the cheapest thing you can leave
   the successor. If the same symbol has collected several notes across handoffs, that's a signal to
   graduate it out of prose entirely, into a `--quality-ack` reason or a standing `--arch` deny rule.

4. **Maintenance risk, scoped to the subsystem** — point `--hotspots` straight at the subsystem instead of
   filtering the whole-repo list: `ripwire <subdir> --hotspots` (verified: subdir scoping works, same as
   `--dead-code=DIR`). If the subsystem isn't a clean subdirectory, keep the repo root and `--exclude` the
   rest (repeatable flag) to fence the scan to just the area you're briefing on.
   Also worth a look: `ripwire <dir> --hotspots` (whole-repo, no scoping) to see whether any subsystem file
   also lands in the *global* top-10 — a file can be locally worst-in-subsystem and still unremarkable
   repo-wide, or vice versa; that distinction matters to the recipient. Tell them: "this file is gnarly —
   high churn, high complexity — be careful and run tests after any change here."

## Calibration — what's fact vs framing here

- Steps 1–3 are direct reads (ranked signatures, full bodies, doc text) — trustworthy as far as the
  underlying call graph goes (name-based edges; a symbol with high `amb=` in `--expand`'s `<calls>` block
  means some of ITS calls were ambiguous — don't present those as certain in the brief, flag them).
  `--recall` returns doc *text*, not a verified fact — summarize what the docs claim, not what's provably
  still true; a stale design doc will still get picked up.
- Step 4 (hotspots) is `churn × cognitive complexity` — a maintenance-pain *signal*, not a defect count.
  Frame it to the recipient as "developers keep touching this, tread carefully," not "this file has bugs."

## Stamp the commit you measured at — `at="<sha>[+dirty]"`

A brief is read hours or days later, against a HEAD that has moved. **Every number you quote must carry
the commit it was measured at**, or the recipient cannot tell a stale finding from a live one.

Several repo-reading verbs now do this for you: the header carries `at="<sha>"`, and `at="<sha>+dirty"`
when the working tree had uncommitted changes at measure time. Real output from this repo:

```
<quality-delta baseline="git-HEAD" regressions="0" … gating="0" at="f0a45e43d">
```

**`+dirty` is the important half.** A stamp ending in `+dirty` means the numbers describe a working tree
that exists on exactly one machine and is not recoverable from the sha — it is *not* reproducible by the
recipient. Either commit first and re-measure, or say so explicitly in the brief.

**What actually carries a stamp today (verified by running each verb — do not assume it is universal):**

| verb | stamp |
|---|---|
| `--quality-delta` · `--pr-context` · `--test-gate` · `--map-diff` · `--doc-drift` | `at="<sha>[+dirty]"` |
| `--stray-content` | `head="<sha>"` — different attribute name, and **no `+dirty` suffix** |
| `--situ` · `--cochange` · `--owners` | **none** — record the sha yourself (`git rev-parse --short HEAD`) |

Two traps: the attribute is `head=` rather than `at=` on `--stray-content`, so a script grepping only for
`at=` silently gets nothing; and in `--doc-drift` the name `at=` is *overloaded* — the header `at=` is a
git sha, but each drift ROW's `at=` is a **file path** (`at="src/mcp.h"`). Anchor on the header, not the
first match.

## Output

Handoff brief: (1) what the subsystem does in 2 sentences, (2) the 3 key entry-point symbols
with file:line and their signatures (from `--expand`), (3) the design decisions the recipient
must know (from `--recall`), (4) any hotspot files to be careful with, flagged if churn/complexity data
looks stale (no git history, non-git root). Aim for under 600 tokens.

## Mid-task session handoff — `--handoff`

Handing off an INTERRUPTED WORKING SESSION (not a subsystem summary)? `ripwire <dir> --handoff` emits
the whole continuation packet in one deterministic call: a `<verified>` section (branch, HEAD sha with
`+dirty` marker, changed files + their symbols, transitive blast-radius size, tests-to-run) that is pure
disk truth, and a `<heuristic>` section (co-change partners not in the diff, committed `--note-add`
notes on the touched files, plan/design doc pointers ranked by a branch+commit-subject query) that is
labeled suggestion, never presented as fact. Composes with `--token-budget=N` — heuristic rows drop
tail-first and the header discloses `withheld=`; verified rows never drop. Single-root only; paste the
packet to the next agent as-is.
