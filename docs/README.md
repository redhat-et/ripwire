# ripwire documentation

Sixteen entries, each written for one reader. Start with the row that matches why you are here.

| File | Who it is for | What it answers |
| --- | --- | --- |
| **[`COMMANDS.md`](COMMANDS.md)** | Anyone using the tool | Every flag: the question it answers, a real invocation with real output, the flags that shape it, and the limits the binary itself states. **Generated from `--help`** — it cannot disagree with the shipped binary. |
| **[`ARCHITECTURE.md`](ARCHITECTURE.md)** | A reader deciding whether to trust or extend it | The `ingest → graph → rank → serialize → cli/mcp` pipeline, the data model, the determinism contract, how ranking works, the output-honesty contract ("a zero is a measurement; absent is not zero"), and why CI builds twice. |
| **[`EVALS.md`](EVALS.md)** | Anyone checking whether the tool is oversold | Every published number with its instrument, corpus and pinning file — plus the honest counterexamples, and the claims this project deliberately does *not* publish. |
| **[`LIMITS.md`](LIMITS.md)** | Anyone tuning what an agent can find, or adding a cap | Every compile-time cap in `src/` — value, site, and whether its file discloses a truncation when it fires. A cap is a routing decision, so this exists to stop one being set where nobody can see it. **Generated** by `limits_build.py`, gated by `test/limitstablecheck.sh`. |
| **[`TUNING.md`](TUNING.md)** | Anyone about to retune a cap | What each cap actually COSTS, measured: 23 of 107 tunable caps move any real invocation at all and 84 move nothing, so most of them should be left alone. Measured by patching a scratch copy of the tree so caps read an env var — production keeps its `constexpr`. **Generated** by `bench/capsweep/capsweep.py emit`, gated by `test/capsweepcheck.sh`. |
| **[`METHODOLOGY.md`](METHODOLOGY.md)** | Anyone building something similar | The process, as transferable method: write the gate before the code, capture-audit your own output, the sibling-completeness rule — the defect class where a fix lands on one member of a family and never on the rest — and the six principles (§9) that reconcile a complete one-shot answer with a bounded one. |
| **[`OPTREMARKS.md`](OPTREMARKS.md)** | Anyone tempted to act on a compiler remark | The clang optimization-remarks build (`-DRIPWIRE_OPT_REMARKS=ON`), the triage that turns ~1.1 M remarks into a short list, and the findings — including the two that measured a win (`-DRIPWIRE_LTO=ON`, `-DRIPWIRE_PGO=use`) and every remark that was real, correctly fixed, and moved nothing. |
| **[`FIELDAFFINITY.md`](FIELDAFFINITY.md)** | Anyone weighing `--field-affinity` | What the cache-locality lens is, what is 1999 prior art (nearly all of it — Chilimbi PLDI 1999, Hundt CGO 2006), why it advises and never transforms, and the one end-to-end measurement that took the static hypothesis to hardware — including the access regime in which the hypothesis was **refuted**. |
| **[`CACHELINT.md`](CACHELINT.md)** | Anyone weighing the `cache-*` lint rules or `--with-profile` | The cache-friendliness check catalog: what shipped as the 8-rule `--lint` pack, what `--field-affinity` already covered, the wave-2 specs (loop interchange, reserve-absence, false sharing, AoS touch-ratio), the compiler-handled myths deliberately NOT checked, and the measured tier — `--lint --with-profile=FILE` joining `#PROF_TSV` scope heat onto findings (SYZYGY's advice mode reconstructed). |
| **[`LOCALS_INDEXING.md`](LOCALS_INDEXING.md)** | Anyone weighing `--naming-locals`, or extending the naming lens | The design record for indexing a function's locals and gating naming predicates on them: why `locals=` is a disclosed floor and absent rather than zero for uncovered languages, why Phase 2 deliberately breaks `naminglens.h`'s own stated invariant, and the calibration blocker — cited against this lens's own withdrawn rule — that keeps it opt-in. |
| **[`SUBSTITUTION_METER.md`](SUBSTITUTION_METER.md)** | Anyone asking whether agents actually reach for this tool | The per-tool-call meter inside `hooks/ripwire-nudge.sh`: why the unit is a call and not a task (the task-success eval is dead on power grounds), the JSONL row schema, the command-line classifier's rule table including the rtk unwrap, the A/B arm that ships built-but-dormant, and an explicit list of what the meter cannot see — starting with the MCP calls no hook is shown. |
| **[`CODEX_ORCHESTRATION.md`](CODEX_ORCHESTRATION.md)** | Anyone orchestrating parallel Codex lanes | The deterministic model/effort policy emitted by `--plan-lanes`, the structural signals and caveats behind it, the task-matched agent roles used to implement it, and the verification record. |
| **[`LINEAGE.md`](LINEAGE.md)** | Anyone asking what is actually new here | Every idea folded into the tool, row by row: the paper, specification or repository it came from, the one-line lesson taken, and the flag or source file where that lesson lives — plus the labelled survey of the wider field, kept explicitly separate from what was borrowed. |
| **[`docs_commands_build.py`](docs_commands_build.py)** | Maintainers | The generator behind `COMMANDS.md`. Reads the binary's `--help` and a recorded showcase capture; `--check` is the drift comparison that `test/docscommandscheck.sh` runs. |
| **[`gatecount_build.py`](gatecount_build.py)** | Maintainers, and anyone adding a gate | The generator behind the **published gate count**. Derives it from the single `for _g in …; do` loop in `test/regression.sh` and rewrites all eight marked sites across `README.md`, `EVALS.md` and the deck; `--check` is the drift comparison that `test/gatecountcheck.sh` runs. Never edit that number by hand — two lanes hand-writing the same N+1 auto-merge clean against a loop of N+2. |
| **[`limits_classes.tsv`](limits_classes.tsv)** | Maintainers | Cap name -> INDEXING or OUTPUT, the taxonomy `LIMITS.md` renders in its `class` column: does this cap bound what can EVER be found, or only what is shown from what was found. A sidecar with a known expiry — the tag belongs on the declaration in `src/` — kept honest by `limitstablecheck.sh`, which fails if a row names a cap that no longer exists. |
| **[`lineage-paper-dates.tsv`](lineage-paper-dates.tsv)** | Maintainers | arXiv id -> publication date for every 2026 paper in `LINEAGE.md`. The ID stem does not track the date (`2607.09691` was published 2026-06-19), so the README's recency claim is re-derived from this file by `readmedriftcheck.sh` arm (H2) rather than from the ids. Adding a 2026 paper without a date row fails that arm. |
| **[`assets/`](assets/)** | The front page | The README banner and tagline artwork (SVG, self-contained). |
| **[`captures/`](captures/)** | Maintainers, and the curious | One recorded run of every verb against a real repository — the source of `COMMANDS.md`'s sample output, and the harvest source for the differential argv harness. |

Outside this directory:

- **`README.md`** (repository root) — what ripwire is, quickstart, and which flag answers which question.
- **`CONTRIBUTING.md`** — C++ house style, the G1–G5 guardrails, gate discipline, and the submission checklist. Read it before writing code here.
- **`CLAUDE.md`** / **`AGENTS.md`** — the short orientation for a coding agent working on this repository.
- **`CHANGELOG.md`** — user-visible capabilities, behavior changes, and known limits.
- **`test/README.md`** — why the test tree carries synthetic credential-shaped fixtures, and which files are sanctioned to.
- **`bench/`** — the evaluation harnesses themselves, each with its own README.
- **`paper/`** — the working draft of a preprint on the localization results and the method behind them. In preparation, not submitted; every table names the `bench/` artifact that pins it.
- **`prompts/`** — copy-paste orchestrator prompts for improving this tool with your own coding agent; see `prompts/README.md` for the index.
- **`./build/ripwire --help`** — the authoritative flag list. If a document disagrees with it, the document is the bug.

**Regenerating the generated document:**

```bash
python3 docs/docs_commands_build.py --bin build/ripwire
python3 docs/limits_build.py                       # docs/LIMITS.md, from the caps in src/
python3 docs/gatecount_build.py                    # the gate count, from test/regression.sh's loop
```

It derives the tool's name from the binary you point it at, so a renamed build produces a correctly
named document in one command.
