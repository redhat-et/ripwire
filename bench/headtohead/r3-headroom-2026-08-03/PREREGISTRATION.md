# r3 head-to-head pre-registration: ripwire vs headroom vs naive grep+read

**Frozen 2026-08-03, BEFORE any arm ran.** Questions, gold, arm protocols, metrics and exclusions
below are fixed; the run may not alter them. Committed separately from results on purpose.

## Why this comparison is shaped differently from r2

headroom is not a retrieval tool; it is a **reactive compression layer** (it shrinks bytes an agent
already fetched; it never chooses what to fetch). LocBench file@k therefore does not apply. The
comparable axis is **end-to-end tokens-to-correct-answer on real mid-task questions**, where
upstream selection (ripwire) competes with downstream compression of a naive workflow (headroom).
The arms compose rather than strictly compete; arm D measures the composition instead of hiding it.

## Pins

| thing | pin |
| --- | --- |
| ripwire | commit `bf8e90e4d0ac9e55940c44d792ee7dc154c318ce`, dev build (no build type), AppleClang 21 |
| headroom | PyPI `headroom-ai==0.33.0` (repo HEAD `3f2ca99` same day), Python 3.12.13 venv + `onnxruntime` |
| headroom env | `HEADROOM_TELEMETRY=off HEADROOM_UPDATE_CHECK=off HEADROOM_DISABLE_KOMPRESS=1` (ML prose model disabled — scope noted in report) |
| corpus | `django/django` @ `70f39e46f86b946c273340d52109824c776ffb4c` (LocBench django__django-16421 base), depth-1, 896 files |
| tokenizer | tiktoken `cl100k_base`, one implementation (`harness.py::tokens`) called from every arm |
| machine | Apple Silicon macOS 25.5.0, same host for all arms |

## Arms

- **A — naive floor**: for each pre-registered grep term in order: `grep -rnF --include=*.py` from
  the corpus root, then whole-file reads in order of first appearance in the grep output (cap 15
  files/term), stopping when the answer criterion is satisfied. Rule fixed in `harness.py::arm_naive`.
- **B — naive + headroom (default config)**: arm A's transcript packaged as
  `[{user: question}, {tool: output}...]` (tool role, per headroom's own docstring), compressed once
  by `headroom.compress(messages, model="claude-sonnet-4-5-20250929")`. Single-shot compression at
  answer time — deliberately generous to headroom (no multi-turn cache-bust dynamics).
- **B′ — labeled non-default override**: same, with
  `CompressConfig(protect_analysis_context=False, protect_recent=0)` — the only way headroom's code
  path fires at all on a coding conversation; labeled as such everywhere.
- **C — ripwire**: warm prebuilt index; per-question verb ladder pre-registered in `arms_spec.json`
  from the documented use-when protocol (C1→`--for`+expand-top-hit, C2→`--callers/--uses/--impact`,
  C3→`--affected`, C4→`--for`+path/connect-over-top-hits, C5→`--pack-task`, C6→`--grep`). Dynamic
  rungs (EXPAND_TOP1, PATH_TOP2, CONNECT_TOP3, USES_RAISED_EXC) resolve mechanically against the
  first rung's output — rules in `harness.py::arm_ripwire`. Run from the corpus root with dir `.`
  so paths are relative, byte-comparable with arm A's grep output (EVALS §5 root discipline).
- **D — composition check**: arm C's transcript through headroom `compress()` default config.

## Metrics (chosen before the run; all reported whether or not they flatter)

1. **Tokens to correct answer** — tiktoken count of everything the arm emitted until the criterion
   was satisfied. Criterion per question: every `gold_files` path present (substring) AND every
   `gold_symbols` name present (word boundary) AND ≥1 member of each `gold_any` OR-group.
   For B/B′/D: compressed tokens, **plus the CCR round-trip charged honestly** — a gold item present
   in an input chunk but absent from the compressed text costs the full original chunk again
   (headroom's `headroom_retrieve` returns the full original; its own miss message says re-read the
   file), classified retained / recoverable (marker present) / lost (no marker).
2. **Gold survival** for B/B′/D: retained / recoverable / lost per chunk.
3. **Wall time** — median of 5 (`timing_determinism.py`), cache state named beside every figure.
4. **Determinism** — byte-identity of two identical runs, both tools.

## Question set

12 questions, 2 per category (C1 conceptual localization, C2 blast radius, C3 test coverage,
C4 flow trace, C5 task orientation, C6 literal needle — C6 is deliberately grep's best case and we
expect the baseline to win or tie it). Gold authored by corpus reading only (no ripwire), with
file:line evidence, then **adversarially verified by an independent agent** (call-site exhaustiveness
for C2 confirmed by sweep; q12's "only catcher" claim confirmed). Verifier findings applied before
freezing: q07/q08 vacuous OR-group members replaced (`resolve`→`URLPattern`, `clean`→`to_python`),
q08 grep-term order swapped to the question-derived term first, B-arm scoring excludes the user
question text (it can carry gold tokens), survival check uses the same word-boundary rule as the
criterion. Full set: `questions.json`; ladders: `arms_spec.json`.

## Exclusions

**None planned; target zero.** Scope statements (not exclusions):

- Library-mode `compress()` stands in for the proxy (same pipeline per headroom's docs; no LLM in
  the loop, so no API cost or nondeterminism from the model side).
- Kompress (their ML prose compressor) is disabled; it targets prose, not code, and requires an HF
  model download. Report states this next to every headroom figure.
- We do NOT measure headroom's home turf: JSON/log tool-output compression, provider-cache
  alignment, conversation-history economics, output-token steering. On those axes ripwire does not
  compete and this run makes no claim either way.
- History-dependent ripwire verbs (churn/hotspots) are unmeasured here (depth-1 checkout).
- One corpus, one language, N=12 — directional for category-level conclusions, not a universal
  ranking. Same limits style as EVALS §7/§8.

## What would count as ripwire losing

Arm A or B beating arm C on tokens-to-correct-answer in a category (C6 expected), any C ladder
failing to satisfy a criterion the naive arm satisfies, or wall time where warm ripwire is slower
than the naive path. Losses get buckets and re-runs per `prompts/head-to-head.md` before anything
is published.
