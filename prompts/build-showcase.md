# Build a showcase from this repo's measured artifacts

Make something that shows the tool off — and that survives someone checking it. Every number comes
from this repository's own instruments. Nothing is invented, estimated, rounded up, or remembered.

## Step 0 — the sources, and only these

```bash
cmake -S . -B build && cmake --build build -j
```

- **`docs/EVALS.md`** — every published number with its instrument, its corpus, its N and the
  in-tree file that pins it. This is your only source of figures. §7 is the honest counterexamples,
  §8 is the list of claims this project deliberately does *not* publish. Read both before you write
  a single slide.
- **`docs/captures/`** — a fresh recorded run of every verb against a real repository. Regenerate it
  first with `python3 test/showcase_capture.py` if it predates the binary you are showing; a capture
  from an earlier round documents behavior that no longer exists.
- **`docs/COMMANDS.md`** — the per-verb reference, generated from `--help`, so its examples cannot
  disagree with the shipped binary. Real output for your screenshots lives here and in the capture.
- **`docs/METHODOLOGY.md`** and **`docs/ARCHITECTURE.md`** — for the "why trust this" material.
- **`./build/ripwire --help`** — the authoritative flag list. If a document disagrees with it, the
  document is the bug, and quoting the document propagates the bug into your deck.

## Step 1 — pick the form, per audience

Decide once, in one line, and say why:

- **Deck** — a room, a demo slot, a decision to make. Ten to twenty slides, one claim each.
- **One-pager** — someone scanning before a meeting. One page, three claims, a quickstart.
- **HTML page** — self-contained, sharable, scrollable, with real output blocks. Best when the
  audience will read alone and wants to poke at the commands.

Audience decides depth: an engineer wants the honesty contract and a counterexample; a manager wants
the token and time deltas with their caveats; a user wants the quickstart on slide two.

## Step 2 — the rules for every claim

**Never invent a number.** If a claim has no gate, gate it first or drop the slide. There is no
third option, and "it's approximately right" is how a fabricated figure ships.

- **Every slide that carries a figure cites its instrument** — the harness, the corpus, the N, and
  the file that pins it. Put it on the slide, in small type if you must, not in a footnote nobody
  opens.
- **Cache state and corpus travel with the number.** A speed multiple that compares a warm run
  against a cold one is a lie of omission even when both numbers are true. Say which is which in the
  same sentence.
- **Quote the figure the source actually pins**, at the same N and the same base. Re-deriving a
  headline from a different top-K is a new claim and needs a new instrument.
- **A floor is not a total.** If a slide shows a call count, it says `counts_floor="1"` means "none
  found", not "none exists". The honesty vocabulary is a selling point here, not fine print.
- If a claim you want is in `docs/EVALS.md` §8 — the claims this project does *not* publish —
  it stays unpublished. That list exists because those claims could not be pinned.

## Step 3 — the required slides

Whatever form you pick, three things are not optional:

1. **What it is, in one screen** — the pipeline (`ingest → graph → rank → serialize`), what it
   costs, what it refuses to guess at.
2. **One honest counterexample.** Pick a real one from `docs/EVALS.md` §7: the verb that makes output
   *larger* on short symbols, the anchor worth nothing on the wrong corpus, the search verb that
   costs more tokens than it saves, the ranker that is excellent at importance and terrible at
   relatedness. Give it a full slide, not a caveat line. A tool that only publishes its wins has not
   told anyone how to use it, and an audience that catches you hiding a loss stops believing the
   wins.
3. **The quickstart, last.** Build, run, the three verbs that pay for themselves on day one, and
   where `--help` and `docs/COMMANDS.md` live.

## Step 4 — verify before you ship

- **Every flag named in the deck must exist.** Check each against `./build/ripwire --help`, or run
  `bash test/deckcheck.sh` over the prose sources it scans. A plausible-looking flag that the binary
  does not parse has shipped into a deck here before; it was caught by hand, once.
- **Every output block must be a real run**, pasted from the capture or reproduced live — never
  hand-written to look like output.
- **Re-derive one number per section from its instrument** and check it matches the slide.
- `bash test/ripwirepubliccheck.sh` — no absolute home paths, no personal identifiers, no dangling
  references, in anything you are about to hand to someone.

## Process

- Build the artifact in a **git worktree**; keep generated assets out of the source tree unless I ask
  for them committed.
- Run every check in the **foreground**.
- **Adversarial verifier before delivery**, briefed to find a fabricated or unpinned number and to
  check each citation resolves to a real file and a real figure. Its findings are claims, not
  verdicts — a re-derivation that refutes it wins.
- Commit the artifact and its source separately, with the instrument list in the message.

**Write the plan — form, audience, slide list with the instrument each slide cites — then STOP for my
go-ahead.**
