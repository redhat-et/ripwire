# prompts/ — run the loops this tool was built with

Each file here is a **self-contained orchestrator prompt**. Paste one into your coding agent at the
root of a ripwire checkout; it needs nothing else from this directory to work. They encode the
workflow rather than describing it, so an agent can pick one up and work the way the project works.

Every prompt ends the same way: **it writes a plan and stops for your go-ahead.** Nothing runs
before you approve it. Read the plan, cut what you disagree with, then say go.

| Prompt | Who it is for | What it produces |
| --- | --- | --- |
| [`improve-for-my-language.md`](improve-for-my-language.md) | Anyone using ripwire on a language it serves unevenly | Transcript-grounded gaps for one language — grammar coverage, symbol kinds, ranking, legends — as an ordered plan with measurable gates. |
| [`full-audit.md`](full-audit.md) | A maintainer, or anyone deciding whether to trust the tool | A severity-ranked audit across bugs, measured performance, verb-to-moment matching, token efficiency, and an ecosystem scan of papers and repos with real momentum. |
| [`dogfood-gaps.md`](dogfood-gaps.md) | Anyone who wants findings instead of opinions | A real task done using only ripwire for navigation, with every fallback to grep or a whole-file read logged as a product gap at the moment it happened. |
| [`capture-audit.md`](capture-audit.md) | Anyone checking whether the output is honest | A fresh showcase capture read by parallel adversarial lenses, and the findings turned into family-wide gates. |
| [`ranking-eval-loop.md`](ranking-eval-loop.md) | Anyone who thinks the ranker missed | Real retrieval misses mined from your own sessions, turned into held-out labels, and a ranking change measured against them — or dropped. |
| [`fresh-agent-onboarding.md`](fresh-agent-onboarding.md) | Anyone shipping ripwire to other agents | A zero-context agent's transcript as evidence: which verbs it found, misused, or never discovered — and the help/skill/description fixes that follow. |
| [`sibling-sweep.md`](sibling-sweep.md) | Anyone who just landed a fix | Every unfixed sibling of a mechanism the output discloses, found by enumerating the emitter family in source instead of trusting the docs. |
| [`head-to-head.md`](head-to-head.md) | Anyone who needs a number they can defend | A paired comparison against a competitor or a bare-grep baseline, with tokens-to-correct-answer and wall time, and the losses examined instead of buried. |
| [`build-showcase.md`](build-showcase.md) | Anyone presenting the tool to someone else | A deck, one-pager or HTML page built only from numbers this repo's gates pin, each slide citing its instrument, with one honest counterexample. |
| [`command-tour.md`](command-tour.md) | A new user, and the docs | Every verb run live on this repo with its output explained, plus a filed drift finding for any verb whose help, reference entry and live behavior disagree. |

**Before you start any of them:** build the tool, because most prompts need a binary to measure
against.

```bash
cmake -S . -B build && cmake --build build -j
python3 test/pargates.py . ./build/ripwire -j 6     # the gate suite, in the foreground
```

Do not add a build type. `-DCMAKE_BUILD_TYPE=Release` defines `NDEBUG`, which compiles the
degrade-path diagnostics out and blinds the gates that assert them.
