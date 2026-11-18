# ripwire-orient — reference: notes-resume (read on demand; the recipe is in SKILL.md)

## Then read, and trust the honesty signals

**Read the specific files ripwire surfaces** (god-files + hotspots first) — don't grep blindly. A symbol's
`amb="K"` means K of its calls are ambiguous (the resolver guessed) → read the source if which-target
matters. A map header showing `skipped_oversize=N` means N otherwise-indexable files were dropped for
exceeding a size ceiling — they are absent from `files=` and every ranking; `ripwire <dir> --skipped --legend=compact`
names them (path + bytes + the ceiling that dropped each), so you know what the index cannot show you
before you trust a "not found". A git root also drops every `.gitignore`d path by default (header `ignored_files=N`, absent when 0; `--skipped` lists them); `ripwire <dir> --no-ignore --legend=compact` restores the full walk when the symbol you want lives in an ignored tree. Caveat: *broad, common-word* questions can still favor plain `rg` —
ripwire shines on specific technical asks. CI-enforceable module boundaries graduate to
`--arch=rules.txt` (see **ripwire-layers**).

## Leave a note for next time — the gotcha you just learned (field notes)

The most expensive thing you rebuild across sessions is **gotchas, not structure**. When you learn a
non-obvious fact about a symbol or file (a race trap, an off-by-one seam, "don't touch this without
re-running X"), pin it so the *next* orientation surfaces it automatically:

```bash
ripwire . --note-add="Bar::compute: recompute is NOT idempotent — reset the arena first"
ripwire . --note-add="src/pool.h: 128-byte cache line on Apple, never hardcode 64"   # a file also works
```

The TARGET is **a symbol name or a path**. A symbol resolves through the same resolver the read verbs use,
so every spelling they accept works here — a bare name, `file:name`, `Scope::name`, the canonical id
`path::scope::name`, `@FILE:LINE` — and is **canonicalised to the canonical id on write** (that is the id
notes are keyed by; the rewrite is echoed on stderr). A name matching several definitions is refused, naming
each; a name matching none is refused with a did-you-mean. A path is written even when nothing indexed
matches it yet — a note on a file you are about to add is legal — with a loud warning that it is dangling.
Notes live in committed `.ripwire_notes` and **surface on their own** — whenever `--for`/`--expand` emit that
symbol/file, the note rides along as a `<note d="date">…</note>` child. `ripwire . --notes` lists every note
(`dangling="1"` = target no longer in the tree). `--recall=TASK` is the doc-level complement.
`--note-add` nudges (stderr, non-blocking) toward writing the decision, not a description — a note that
keeps firing on the same symbol has outgrown a comment: graduate it into a `--quality-ack` reason or a
standing `--arch` deny rule.

## Resuming — a compaction, or a new session on work already in flight

A different moment from a cold start: you are **not** cold on the repo, you are cold on **your own last
hour**. The task is known; what evaporated is the reasoning, the gotchas already paid for, and what you had
half-changed. Re-reading source rebuilds the *least* valuable of those. Run the three verbs that rebuild the
rest, in this order:

```bash
ripwire . --recall="<the task, in the words you'd use>"   # 1. what past sessions WROTE DOWN
ripwire . --situ                                          # 2. what the working tree already CHANGED
ripwire . --notes                                         # 3. gotchas already paid for
```

1. **`--recall`** returns the *full bodies* of the most relevant markdown only — memory notes,
   planning/design docs, READMEs — so code can't swamp them. This is the decisions-and-rationale layer that a
   compaction destroys and that source code never contained in the first place. Point it at your memory dir
   for past-session memory, or the repo root for the project's plans.
2. **`--situ`** (defaults to `git diff`) tells you what you had already changed, its blast radius, the tests
   to run, and the co-change partners you hadn't touched yet — i.e. where you actually stopped, and what you
   were about to break. This is the step that most often reveals work-in-flight you would otherwise redo.
3. **`--notes`** lists every pinned gotcha (`dangling="1"` = its target is gone). Anything relevant will also
   re-surface on its own once `--for`/`--expand` emit that symbol — see the section above.

Then, and only then, escalate the ladder for whatever is still missing. Two honest cautions: `--recall`
returns what the docs **claim**, not what is still true — a stale plan doc reads exactly as confidently as a
current one, so trust `--situ`'s working-tree facts over a doc when they disagree. And `--situ` carries **no
`at=` commit stamp**, so if you are resuming across a rebase or a moved HEAD, record `git rev-parse --short
HEAD` yourself before you quote anything from it.

**Before the next compaction, spend the note.** The compaction you are recovering from is the argument for
`--note-add`: a gotcha written to `.ripwire_notes` survives a context reset; one held only in context does
not. When you are deep in a task and learn something non-obvious, pin it *then* — not at the end.

## Output

Orientation summary: the 3–5 most important files (from god-files + hotspots), the main architectural
modules (from `--communities` / `--zoom`), any cycles (from `--report`), and one sentence on overall shape.
Use it to decide where a change belongs and which boundary a refactor should respect.

## Mid-task: about to open several files for one question

The same skill, a different rung: run the cheapest verb that answers the question (`--for`, `--grep`, `--expand`,
`--pack-task` under a `--token-budget`), then read only the 2-3 files it ranks highest. Less context is measurably
MORE accurate, not just cheaper. The full discipline — the read ladder, `--pack-task --partition=N` for fan-out,
whole-symbol edits without a whole-file Read, the portable `--cache=FILE` one-liner — is
**[`map-before-you-read.md`](map-before-you-read.md)**; the detail/token squeeze once you are reading a body is
**[`compress-ladder.md`](compress-ladder.md)**. Both load on demand; neither is a separate skill.
