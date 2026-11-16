# Ranking and answer size: getting the answer to the top in fewer bytes

**Status: IDEAS, 2026-11-16.** No code, and no new measurement in this note. Every number comes from an earlier
measurement. Each is cited by date and by what was measured, so it can be re-run before a lane relies on it.
Shorter answers are the one axis where ripwire is not yet where we want it: answers are good, memory and speed are
good. This note collects the candidate levers in one place.

---

## A. Getting the right answer to the top

1. **Order by the signals that separate gold, not by score.** A row-feature dump (2026-11-11) covered 512 top-10
   answer rows on the multi-file and large-repo dev slices. Score did not separate the rows the grader marked Wrong
   from the gold rows; two rank signals did:

   | signal | gold rows (median) | Wrong rows (median) |
   |---|---|---|
   | rank in the candidate set | 2 | 6 |
   | rank of the row's file | 1 | 3 |
   | score / head score | 0.95 | 0.76 |

   Proposal: put the print order and the top-10 cut on a key built from these two ranks, with score only as the
   tiebreak.
2. **Make the round-robin head conditional.** The head's one-row-per-file lift puts 43 % of the top-10 Wrong items
   there, against 13 % of gold.
   - An ablation (2026-11-08) switched the lift off. It removed 13 in-sample top-10 decoys and lost 0 credited items.
   - On the held-out set it was net +1, so a plain off switch is not the answer.
   - Proposed rule: lift a file's best row only when that row's own rank is ≤ 8.
3. **Use a resolved edge to the head as a keep guard.** 26 % of gold rows have a resolved or name-resolved edge to
   the head, against 11 % of Wrong rows. Never demote a row that has one. This is a guard, not a ranking signal.
4. **Put a one-line direct answer first:** `name — file:line — the relationship to the question`, ahead of every
   supporting section. Agents read the top and stop, so the answer has to be the first thing they see. The line
   must explain itself without the legend.
5. **Size the answer by confidence.**
   - Anchored head (name-exact, resolved): a short answer with a few supporting rows.
   - Ambiguous head: show the alternatives instead of a long tail.

   The anchor's provenance is already computed, so this needs no new signal.

## B. Fewer bytes without losing answers

1. **The `<tail>` section is the biggest lever.** An answer-size breakdown of 0.6.9 vs 0.6.10 (2026-11-07,
   326 stored answers, three question sets) found:
   - the tail is 58 % of the +31 % growth;
   - 41 % of tail bytes are path-only rows;
   - 78 % of the growth is on rows that gained no item and no tier.

   0.6.9 capped the tail at 50 rows with `next=`. Restoring a cap, or dropping path-only rows by class, was
   estimated at −318 to −537 KB over the three sets.
2. **Prove trims offline before writing code.** No runtime signal in the answer separates rows that gained from rows
   that did not (confidence=, coverage= and the tail totals have equal medians), so a trim has to be a row-class
   rule. The cheap method:
   - edit copies of the stored answers (delete one row class or section);
   - re-grade them;
   - read off the cost in items per cut.

   That gives a ranked cut list with a known item cost for each cut, and no build is needed.
3. **Group rows by file — measure literal-path survival first.** Row markup is about 29 % of an answer, and a byte
   breakdown (2026-10-04) estimated a 19-31 % saving per question class from printing each path once with its rows
   under it. That saving is lossless only for a reader that rejoins the prefix. When the map's inventory tier was
   nested this way (2026-11-16), 87 % of directory rows lost their literal path, so a substring search for the
   path failed and a `p=` meant to be pasted as a command argument stopped running. Ranked rows carry the same
   exposure. Count literal-path survival on before/after answer pairs (one grep each) before building anything.
4. **Legends.** Legends are about 16 % of bytes (median ~2 KB). Present-only legends landed in #668, and agent
   surfaces can already take the legend once per session (`--legend=ref`, CLAUDE.md G4). The open question is
   measurement: how often real agent sessions get the ref form, and what the inline legend costs on the CLI paths
   agents call through a shell.
5. **Detail by distance:** full body for the head, signature for near rows, `name@file:line` for far rows.
6. **Fold duplicate definition rows** in `--for`'s `<ctx>`: constant-group members that each print the same doc
   excerpt fold into one row with a name list. About 23 KB recoverable over the same three sets. (Four elements are
   spelled `<d>`; this is the `--for` context row, not the signature tier's, `--defs`', or the slice verb's.)

## C. Splitting verbs

- **Data:**
  - Answer size and legend share differ a lot by question class. who-calls answers are 1.3 KB, and 43 % of that is
    legend; how-it-works answers are 9.2 KB (2026-10-04 breakdown).
  - Within `--for`, the internal route label explains little. Whether the question names an indexed symbol
    explains most item loss: 71 % complete when it does, 34 % when not (routing census, 2026-11-08, 60 questions
    × 3 wordings). There is no measurement yet of how often agents choose a specialised verb over `--for`.
- **Recommendation: route inside `--for` before splitting it.** Classify the question (where-defined / who-calls /
  how-it-works / change-risk / find-literal) with a simple rule-based classifier. Then give each class its own
  section set and byte budget behind the one entry point. A split adds a routing choice for the agent, and how
  well agents make that choice is unmeasured.
- **When a split does pay:** a short first answer plus a `next=` cursor for depth. That splits by depth rather than
  by verb: `--for` answers short, and `next=` continues.
- **To test:** class-routed budgets on the in-sample rows (bytes and credited items per class). Then, if wanted, a
  small agent A/B of routed-short vs current answers, measuring tokens per solved task.
