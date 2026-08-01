# Capture-audit — read this tool's own output as a stranger would

The honesty audit. Record what every verb *actually prints*, then read it as an unfamiliar user and
write down every place the output is misleading, over-confident, ambiguous, or silently incomplete.
This finds a defect class no unit test looks for, because each individual output is *valid*.

Background: `docs/METHODOLOGY.md` §2 and §3, and `docs/ARCHITECTURE.md` §4 (the honesty contract).

## Step 1 — regenerate the capture against the CURRENT binary

```bash
cmake -S . -B build && cmake --build build -j        # no build type
python3 test/showcase_capture.py                     # writes docs/captures/COMMANDS_showcase_<date>.md
```

Regenerate against the binary you are auditing, never one from an earlier round — a stale capture
documents behavior that no longer exists. The capture is scrubbed and root-neutralised on write; if
it refuses, fix the offending output rather than bypassing the refusal.

## Step 2 — read it with these lenses, IN PARALLEL

One agent per lens, each with only its lens and the capture. Lenses find different defects and
contaminate each other when combined. Every finding quotes the exact capture line.

1. **Numeric re-derivation.** Take each number in the output and derive it independently from the
   source or from another verb. A header that names a denominator it does not actually count, a
   percentage over the wrong base, a `total=` that disagrees with the rows below it.
2. **Cross-verb agreement.** Ask the same question two ways and diff the answers. `--callers`
   against `--uses` against `--impact`; a CLI verb against its MCP sibling; `--situ` against
   `--affected`. Two verbs using the same word for different quantities is the classic hit here —
   call **sites** versus caller/callee **pairs**.
3. **Prose-as-claim.** Read every caption, legend and help line as a *promise*, then check the
   binary keeps it. A caption saying "~70% fewer tokens" is a claim and needs an instrument.
4. **Paging seams.** Every verb that pages or caps: `--limit`, `--offset`, `--top-k`,
   `--token-budget`, `--max-tokens`, `--pack-top-n`. Does the last page say it is the last? Does a
   cut disclose what was cut (`total=`, `shown=`, `capped=`, `truncated=`)? Does an over-budget
   bundle say `over_ceiling=1` rather than quietly overshooting?
5. **Dialect parity.** The same run in each output dialect — default XML, `--json`,
   `--format=columnar`, `--format=rows`, `--format=candidates`. Every attribute, legend and
   disclosure present in one must be present in the others or deliberately and visibly absent.
6. **Refusal population.** Feed every selector a name that does not exist, an empty value, and a
   near-miss typo. Each must **refuse**, naming the flag, the problem, and an example of the
   accepted form — with a did-you-mean from a real edit distance. A selector that answers `0`
   instead of refusing is a finding.
7. **Sibling-completeness.** For every disclosure the capture *does* show, enumerate the family it
   belongs to in `src/` and check every member. This lens finds more than the other six combined;
   `prompts/sibling-sweep.md` is the standalone version of it.

## Standing rules (they decide what counts as a finding)

- **A zero is a measurement. Absent is not zero.** A count that cannot be a total is a **floor** and
  must carry `counts_floor="1"`. An unlabelled zero that a reader will take as "does not exist" is a
  HIGH finding, not a wording nit.
- **A refusal is not an answer of zero.** A selector naming nothing indexed refuses, with
  flag + problem + example. A query whose names all resolve but selects nothing reports `count="0"`,
  because *that* is a measurement.
- **Never publish a number without an instrument that pins it.** Any claim in a caption or legend
  either has a gate or is deleted.
- **Every truncation is disclosed**, and an estimate says it is calibrated rather than exact.

## Step 3 — land the findings

Each finding becomes a **gate over the whole family**, not over the instance you found. "Every verb
that emits a count states its unit" is worth more than a dozen single-verb checks, because it fails
for the next sibling too — including one that does not exist yet.

- Add each new `test/*check.sh` to `test/regression.sh` in the same commit, or `test/manifestcheck.sh`
  fails.
- **Red first**: run the new gate against the pre-fix binary and watch it go red. A gate that cannot
  observe what it asserts is worse than no gate, because it reports confidence.
- Regenerate the capture one last time **against the final binary** once the round lands, and
  re-run `test/showcasecapturecheck.sh` and `test/docscommandscheck.sh`.

## Process

- Lens agents and producer agents in **git worktrees**, one lane each.
- Producers run **their own gates in the foreground**; the full suite is the orchestrator's job.
- **Adversarial verifier after every merge wave**, briefed to find the wave broken. In this repo's
  history that pass has found something broken every time it ran; "the merge looked clean" has never
  been evidence. Its findings are claims, not verdicts — a measurement that refutes it wins.
- Zero unacknowledged `--quality-delta` regressions; `python3 test/pargates.py . ./build/ripwire -j 6`
  green in the foreground; commit per verified finding, gate name in the message.

**Write the plan — lenses, findings, gates, ordering — then STOP for my go-ahead.**
