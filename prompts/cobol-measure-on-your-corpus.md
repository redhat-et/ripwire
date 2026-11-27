# Measure the COBOL stack, then decide what to build

This is the COBOL round of [issue #70](https://github.com/redhat-et/ripwire/issues/70), written so
that anyone can run it. **Most of it needs nothing but public code**: the two-pass COBOL stack
described below, pointed at public IBM i corpora, producing parse rates, recall split by tier, and
frequency counts for the constructs our roadmap is currently guessing at. That is the part that was
volunteered for, and it is the spine of this prompt.

One section — clearly marked, entirely optional — is for a reader who also has production COBOL they
cannot share. **That section is aggregate-only, and the constraint is absolute: counts, rates and
histogram buckets leave your machine, nothing else.** No file names, no program or paragraph names,
no source lines, no paths, no client identifiers, not once. We cannot see your code, we do not want
to see it, and no step here is worth a single identifier. If a step cannot be answered without
naming something, **skip it and report the skip** — a reported skip is a result, and a leak is not.

Everything measured on the public 716 files is quoted below so you can reproduce it, disagree with
it, or find the case that breaks it. **The measurement comes before any grammar or ingestion code.**
That is the same rule [`add-a-language.md`](add-a-language.md) opens with, and it is not ceremony:
the parse rate and the tier split are what decide whether this work is worth starting and in which
order.

---

## Setup — where to start from

Base the work on **`main`**. The latest release on 2026-11-26 is **v0.7.0** (tagged 2026-11-23, commit
`5a3df049e`). There is no branch to wait for; `main` is the base, and a fork of it is the right shape
for this.

```bash
cmake -S . -B build && cmake --build build -j
python3 test/pargates.py . ./build/ripwire -j 6     # the gate suite, in the foreground
```

Do not add a build type. `-DCMAKE_BUILD_TYPE=Release` defines `NDEBUG`, which compiles the
degrade-path diagnostics out and blinds the gates that assert them.

Record `ripwire --version` and the `<doctor …>` line from `ripwire <dir> --doctor` in your report
header, so every number below has a binary attached to it.

---

## Where #70 stands (2026-11-26)

One external round has already been run. On 2026-10-10 the issue's reporter posted on #70:

- **Part 1 on a small public corpus** — 24 COBOL and 17 DDS files, all 59 reference sites hand-reviewed,
  recall split by tier (tree tier: out-of-line PERFORM 23/24, literal CALL 13/18, COPY 7/17; token
  tier: CALL 1/18, nothing else), plus the same table in aggregate for a private snapshot.
- **The scanner fixes upstream**, as open pull requests on `yutaro-sakamoto/tree-sitter-cobol`: #44
  (the out-of-bounds read) and #42 (the end-of-file hang). Neither was merged on 2026-11-26, so you
  still patch both yourself.
- **Part 2 answered *yes* for their pipeline** — their own parser already knows where a body ends —
  with a proposed standard-SCIP import contract.

The maintainers' reply (2026-10-12) likes the shape and defers the contract decision. It names four
things a SCIP-import pull request must meet, and `CONTRIBUTING.md`, "Languages without a grammar:
imported, not parsed", is the reference it will be reviewed against. Today `--scip=` is a precision
overlay on call edges for languages ripwire already parses; it does not import symbols for a language
it does not parse.

So the most useful run now is Part 1 on **more and different corpora** (41 files is a small
denominator, and a second corpus is the only check on the first), the frequency counts in 1.3, and —
if your resolver differs — your own Part 2 answer.

---

## What was measured first, and on what

The first round of COBOL numbers (2026-09) came from **716 public files**: NIST, CardDemo, an
OMP course set, and IBM, Microsoft and exercism samples. That is a convenience sample, not a census,
and its shape is the reason this round exists — sample code under-represents the constructs real
shops live in.

The recommended configuration is a **two-pass, two-grammar merge**:

- **Pass A — `yutaro-sakamoto/tree-sitter-cobol`, the PR #41 branch, patched.** It carries two
  scanner bugs you will hit immediately: an out-of-bounds read in `start_with_word` that a sanitizer
  build catches, and an infinite loop at end of file when the last line is under six columns — a
  one-byte file hangs. Patch both before you measure anything. **Record the exact commit you forked
  from, and include or link the patch content itself, in your report** — a branch moves, and
  "patched" without a pinned commit and a diff is not reproducible.
- **Pass B — `barrettotte/treesitter-ibmi`** (MIT; COBOL, DDS, RPG and CL in one grammar). Known
  bug: its `picture` token splits words such as `PERFORM`; the workaround is to glue adjacent tokens
  before matching. Record its commit too — the same reproducibility requirement as pass A.
- **Merged BY ROLE, not by best tree.** Structure from one pass, edges from the other.
- **Plus tier-2 edges**: PERFORM, CALL and COPY targets read from pass B's error-free *token*
  stream, used only for paragraphs whose pass A tree failed.
- **Plus an offset-preserving reference-format normaliser** — it blanks the sequence and indicator
  areas without moving a single byte offset, so every span the extraction reports still points at
  the real file.

**The best-tree-per-file merge is a trap, and it is the most important thing on this page.** Picking
whichever pass produced the cleaner tree for each file *looks* better — 95% of files come out clean
— and it destroys the answer: PERFORM recall collapses to **54.5%**, because barrettotte trees carry
no statement nodes at all. A file can be clean and edge-free at the same time. If your own merge
strategy is scored on tree cleanliness, you are measuring the wrong thing.

Measured on the public 716, strict-clean, against a hand-checked lexical reference:

| Quantity | Measured |
| --- | --- |
| PERFORM, CALL and COPY edges | 100% recall and precision (combined, against the lexical reference) |
| Files fully covered | 96.7% |

The definition accuracy, the parse rate split by artifact kind, and the wall-clock cost were not
carried forward from the original round with an instrument attached to them, so this page does not
restate them as numbers here. That is exactly what Part 1 below re-derives, with a denominator on
each one — including the hand-checked sample size, which was not preserved either.

The stack emits a per-file disclosure record, and **the aggregate of that record is the report this
prompt is asking for**: whether pass A was clean, including zero-width hidden errors; which
definitions came from pass B; which paragraphs have unknown edges; a TIER attribute on every edge
(tree or token); bytes neither pass parsed; dynamic CALL sites left unresolved; and what the
normaliser blanked.

---

## Part 1 — the stack against public COBOL

Run the configuration above over as much public IBM i COBOL as you can assemble, and report the
numbers below. **Extending the public corpus is itself a result**: our 716 files are what one person
could find, and a second person's list is the only way to learn what that search missed. Name the
corpora you added and where they came from, so the next run can reproduce yours.

### 1.1 — establish ground truth cheaply

You cannot report recall without a truth set, and you do not need an expensive one.

This project built its truth with a **lexical oracle**: a small script that scans the raw bytes for
PERFORM, CALL and COPY and records every target it can see, independent of any parse tree. The rows
were hand-checked. Do the same thing, and then stop: **a hand-checked sample of a few hundred rows is
enough to place a recall number**, and building more instrument than that is the classic way this
round turns into a project. Sample across artifact kinds rather than taking the first few hundred
rows of one file.

Build a **definitions oracle the same way**, for 1.2(2) below: scan the raw bytes for `PROGRAM-ID`,
paragraph names and `SECTION` headers, hand-check a sample the same way, and use it to decide whether
a definition the stack reports is real. Nothing upstream of this prompt has built that oracle yet, so
it is the one instrument in Part 1 you are establishing from nothing rather than reproducing — state
your rule if you build it differently.

Say how many rows you checked, for both oracles, and how you sampled them. A recall or
false-definition figure without its denominator and its sampling rule is an impression.

### 1.2 — the numbers

Report each of these, split as indicated. Every one is a count or a rate.

1. **Clean-parse rate, split by artifact kind** — programs, copybooks, DDS. One rate per kind, with
   its denominator. A single blended rate hides the kind that is actually broken.
2. **Definitions found**, and the **false-definition rate** — a definition the stack reports that
   your oracle says is not one. The false rate matters more than the found rate: a map that invents
   symbols is worse than one that misses them.
3. **PERFORM, CALL and COPY recall, SPLIT BY TIER.** Tree-tier edges and token-tier edges reported
   separately, never summed into one number. **This split is the point of the whole exercise** — it
   says how much of the answer rests on the token fallback, and a stack whose recall is carried by
   tier-2 is a different product from one whose recall is carried by trees, even at identical totals.
4. **Bytes neither pass parsed.** Absolute and as a fraction of corpus bytes.
5. **Dynamic CALL count** — call sites whose target is an identifier rather than a literal, left
   unresolved. This is a floor, not a total; label it as one.
6. **Normaliser blanks** — how many files had sequence or indicator content blanked, and how many
   bytes. A normaliser that blanks nothing on a corpus is not being exercised.

### 1.3 — the frequency question, which is the highest-value thing here

Our gap list for COBOL is **guesswork about what real IBM i shops use**. It is:

- `EXEC CICS LINK` / `XCTL`
- SQL `INCLUDE`
- `COPY … REPLACING`
- nested programs
- free format

**Report how often each one appears** — a count of occurrences and a count of files containing at
least one, per corpus. That reorders our roadmap directly, and no amount of reading the standard
substitutes for it.

Count on the raw source text, not the parse tree: a case-insensitive literal match for each
construct's keyword or clause, skipping comment lines (column 7 holds `*` or `/` in fixed format) and
skipping matches inside string literals. Every match increments the occurrence count, including
repeats within one paragraph; a file counts once toward "files containing at least one" no matter how
many matches it holds. If your corpus needs a different rule — free format has no column 7 to skip,
for instance — state the rule you used instead; an unstated counting rule is what makes two runs of
this section incomparable.

Run this on the public corpus and expect the answer to be skewed: **public sample code
under-represents CICS and embedded SQL badly**, because teaching material and demo applications are
written to run without a transaction monitor or a database. Saying so with numbers is more useful
than the numbers alone — a near-zero CICS count on public code is evidence about the corpus, not
about COBOL.

---

## Part 1b — optional: a corpus you cannot share

Skip this section entirely unless you have access to production COBOL under an agreement that
forbids sharing it. Nothing in Part 1 depends on it.

If you do have that access, here is the honest framing: **real client code is the only population
that tests this stack, and nobody outside your client base can measure it.** Our 716 public files
are teaching material and demos. Whatever breaks on forty years of accreted production code is
invisible to us and always will be.

**The rule for this section, repeated because it is the only thing that makes it runnable:**

- **Aggregate counts only.** Every figure is a count, a rate, or a histogram bucket.
- **Never** a file name, a program name, a paragraph name, a copybook name, a symbol, a source line,
  a path fragment, a library or schema name, or anything identifying a client.
- Histogram buckets, not distributions with outliers attached — "11 files in the 10–50 KB bucket",
  never "the largest file".
- **If a step cannot be answered without naming something, skip it and report the skip.** Write the
  skip down: "step 1.2(5) skipped, cannot be answered in aggregate on this corpus" is a finding we
  can act on. An identifier is not.
- Run the numbers, read the output yourself, and send only the table. Do not paste tool output.

Report the same list as 1.2, plus the same frequency counts from 1.3 — **the frequency question
belongs in both sections**, and the two answers being different is exactly what we want to see. A
public corpus that says CICS is rare and a production corpus that says it is everywhere is a single
finding worth more than either number alone.

---

## Part 2 — can your resolver produce `typed_enclosing_range`?

This is a design question, not a measurement, and it is the **single blocker** for issue #70's actual
ask. Answer it before writing extraction code, because the answer decides which extraction code is
worth writing.

The situation, precisely. In SCIP, a definition occurrence's `range` is the **identifier**, not the
body — it covers the name and stops. Serving `fetch_body` from a SCIP index therefore needs a second
range, the one that spans the whole symbol. SCIP spells that `typed_enclosing_range`:

    single_line_enclosing_range = 10
    multi_line_enclosing_range  = 11
    enclosing_range = 7            // deprecated, do not emit

So the question for your extraction is narrow and answerable: **does it already know where a
symbol's body ends?**

- **If it does** — if the point at which a program, paragraph or section ends falls out of your parse
  or your resolution logic — then the SCIP-source path is viable. ripwire consumes the index, serves
  bodies honestly from the enclosing range, and **the fork can go away**. That is the outcome
  everyone wants, and it is contingent on this one fact.
- **If it does not** — if end-of-body is something your pipeline never computes — then a first-class
  vendored grammar is the only honest route, and we should stop designing a SCIP-source path on your
  behalf. That is not a worse answer; it is a cheaper one, arrived at before either side builds
  against an assumption.

**We will not ship a heuristic that guesses where a symbol ends.** A body served from a guessed
range is wrong in a way the reader cannot detect, which is the one failure mode this project treats
as disqualifying. So "we could approximate it" is a *no* for the purposes of this question — answer
for what your extraction knows, not what it could be made to infer.

### 2.1 — re-run your verb telemetry

Reported on #70 on 2026-09-11: **17 sessions, 317 MCP calls, eight native verbs** — `fetch_body`,
`grep`, `find_symbol`, `find_referencing_symbols`, `uses`, `explore`, `for`, `analyze` — and **none** of the
parse-tree features. That mix is why `typed_enclosing_range` is the blocker rather than one item
among many: `fetch_body` is in the top of it.

Re-run the same count on the current release and report the same two numbers plus the verb
histogram. If the mix moved, that changes which surface is worth hardening; if it did not, eight
verbs is a much smaller contract than the fork is currently carrying, and that is an argument for
retiring the fork sooner rather than later.

---

## The report

One document, ordered: setup header, Part 1 numbers, Part 1b numbers if you ran it, the Part 2
answer. Then:

- **Every number carries its denominator and its instrument.** "96.7% of 716 files fully covered,
  hand-checked against a lexical reference" is a result; "definitions are good" is not.
- **A zero is a measurement; absent is not zero.** A count that cannot be a total is a floor and
  says so. Dynamic CALL is a floor. Bytes-not-parsed is a total.
- **Report the losses in their own section**, not folded into an average. The corpus where the parse
  rate fell is the interesting one.
- **Name every skip.** Especially in Part 1b, where a skip is the correct answer to several steps.
- Post the Part 1 and Part 2 results on
  [issue #70](https://github.com/redhat-et/ripwire/issues/70). Part 1b's aggregate table goes in the
  same place — it contains no code and never will.

### Honesty rules

- **Never publish a number without an instrument that pins it.** "Works well on real COBOL" is not a
  result; a rate against a hand-checked sample with a stated sampling rule is.
- **A merge strategy is judged on recall, not on tree cleanliness.** The best-tree trap above is the
  worked example; assume your own variant has a version of it and go looking.
- **Tier is never summed away.** Tree edges and token edges are reported apart, in every table where
  either appears.
- **A disclosure surface that under-reports is worse than one that is absent.** If your stack cannot
  tell whether a paragraph's edges are known, say that, rather than emitting a confident zero.

---

**Write the plan, then STOP for my go-ahead.** Say which corpora you will measure, whether you are
running Part 1b at all, and which of the two Part 2 answers you already suspect — that last one is
cheap to state and expensive to discover late.
