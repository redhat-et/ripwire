# ripwire documentation

Seven entries, each written for one reader. Start with the row that matches why you are here.

| File | Who it is for | What it answers |
| --- | --- | --- |
| **[`COMMANDS.md`](COMMANDS.md)** | Anyone using the tool | Every flag: the question it answers, a real invocation with real output, the flags that shape it, and the limits the binary itself states. **Generated from `--help`** — it cannot disagree with the shipped binary. |
| **[`ARCHITECTURE.md`](ARCHITECTURE.md)** | A reader deciding whether to trust or extend it | The `ingest → graph → rank → serialize → cli/mcp` pipeline, the data model, the determinism contract, how ranking works, the output-honesty contract ("a zero is a measurement; absent is not zero"), and why CI builds twice. |
| **[`EVALS.md`](EVALS.md)** | Anyone checking whether the tool is oversold | Every published number with its instrument, corpus and pinning file — plus the honest counterexamples, and the claims this project deliberately does *not* publish. |
| **[`METHODOLOGY.md`](METHODOLOGY.md)** | Anyone building something similar | The process, as transferable method: write the gate before the code, capture-audit your own output, and the sibling-completeness rule — the defect class where a fix lands on one member of a family and never on the rest. |
| **[`docs_commands_build.py`](docs_commands_build.py)** | Maintainers | The generator behind `COMMANDS.md`. Reads the binary's `--help` and a recorded showcase capture; `--check` is the drift comparison that `test/docscommandscheck.sh` runs. |
| **[`captures/`](captures/)** | Maintainers, and the curious | One recorded run of every verb against a real repository — the source of `COMMANDS.md`'s sample output, and the harvest source for the differential argv harness. |

Outside this directory:

- **`README.md`** (repository root) — what ripwire is, quickstart, and which flag answers which question.
- **`CONTRIBUTING.md`** — C++ house style, the G1–G5 guardrails, gate discipline, and the submission checklist. Read it before writing code here.
- **`CLAUDE.md`** / **`AGENTS.md`** — the short orientation for a coding agent working on this repository.
- **`CHANGELOG.md`** — user-visible capabilities, behavior changes, and known limits.
- **`test/README.md`** — why the test tree carries synthetic credential-shaped fixtures, and which files are sanctioned to.
- **`bench/`** — the evaluation harnesses themselves, each with its own README.
- **`./build/ripwire --help`** — the authoritative flag list. If a document disagrees with it, the document is the bug.

**Regenerating the generated document:**

```bash
python3 docs/docs_commands_build.py --bin build/ripwire
```

It derives the tool's name from the binary you point it at, so a renamed build produces a correctly
named document in one command.
