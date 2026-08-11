# PLAN — S1 skill-routing calibration (W1-S1, 2026-08-11)

**Status: PLAN ONLY — hard stop for owner approval. Nothing below runs before a go-ahead.**
No `skills/ripwire-*/SKILL.md` was edited, no corpus row written, no floor changed, no line of
`docs/EVALS.md` touched. Everything measured for this plan was read-only against
`origin/main` (worktree `w1-s1-routing-plan`, built plain, never Release).

---

## 0. Current state, verified by running the instrument (not quoted from the brief)

Instrument run (read-only, this worktree's fresh build):

```
./build/ripwire skills --eval-skills=test/skillevalfix/prompts.tsv --no-cache
```

Actual output, headline lines verbatim:

```
ripwire --eval-skills  (skill routing over K=17 candidate skills [ripwire-router excluded];
                        104 positive + 44 negative prompts; split test=128 dev=20)
  split=test  bm25-desc     72.7%   83.0%   0.813     0.957
  judged-only hit@1 per arm: overlap 18/58, name 3/58, bm25-desc 32/58, bm25-full 35/58, for-routed 32/58
  provenance hit@1 (bm25-desc): router 24/26, desc 18/20, judged 32/58
  split=dev   bm25-desc     62.5%   68.8%   0.733     0.969
```

**Every number matches the brief's snapshot exactly** (bm25-desc 72.7 / 83.0 / 0.813 / 0.957;
judged 32/58; bm25-full 35/58 — the three-row gap is live at tip). No discrepancy to report.

Floors as they exist today (read from the gate scripts, not from memory):

| Gate | Floor | Measured today |
| --- | --- | --- |
| `skillevalcheck.sh` | bm25-desc split=test hit@1 ≥ 69.0% | 72.7% |
| `skillevalcheck.sh` | bm25-desc split=test sep-auc ≥ 0.90 | 0.957 |
| `skillevalcheck.sh` | judged split=test rows ≥ 40 | 43 |
| `skillevalcheck.sh` | dev-split hit@1 ≥ 45.0%, sep-auc ≥ 0.80 | 62.5% / 0.969 |
| `skillroutingjudgedcheck.sh` | judged (all 58) bm25-desc hit@1 ≥ 50% | 32/58 = 55.2% |
| `skillroutingjudgedcheck.sh` | judged for-routed hit@1 ≥ 45% | 32/58 = 55.2% |

Corpus composition, counted from `test/skillevalfix/prompts.tsv` (148 rows):

| provenance/split | rows |
| --- | --- |
| judged/test | 43 |
| judged/dev | 15 |
| router/test | 25 |
| router/dev | 1 |
| desc/test | 20 |
| neg/test | 40 |
| neg/dev | 4 |

Judged per-skill label counts (a label can appear in a permitted set): range **2–7** across the
17 routable skills — `ripwire-change-check` 7, `ripwire-orient` 6, `ripwire-fresh-eyes` 5, down to
2 each for `find-bug`, `graph-query`, `layers`, `mcp`, `reuse-first`, `write-tests`. Six skills sit
at n=2, where a single flipped row is a 50-point per-skill swing. This is the imbalance the growth
step fixes.

---

## 1. Corpus growth method — to ≥150 judged rows with a sealed held-out split

### 1.1 Where the new rows come from (real agent phrasing only)

All new positive rows are `provenance=judged` — per the corpus header, the label follows the
router's moment map; only the words are new. Sources, in priority order:

1. **Session transcripts** under `~/.claude/projects/` — especially the canyonraid48-class
   project dirs (the least-ripwire-shaped corpora, per the owner's own S2 reasoning). Protocol:
   sample transcript moments where an agent stood at a routable moment (about to grep, about to
   open files, about to review a diff, resuming cold), transcribe the agent's or user's *actual
   phrasing* at that moment, and label it from the router moment map. Sampling is by *moment
   type*, never by searching transcripts for the word "ripwire" (that would select for
   already-converted phrasing).
2. **`bench/agentloop/results/pilot-6run.json`** — agent turns from the 2026-08-04 Codex pilot;
   the same transcription protocol.
3. **The S2 substitution log** (`~/.ripwire/substitution.jsonl` — verified live on this machine,
   264 rows as of today). Caveat found during read-only inspection: the current rows are
   gate-fixture rows (`repo` points into `$TMPDIR` fixtures, session tag `grepcase`), so it is a
   *future* source — usable once rows tagged with real repos accumulate. Its `detail` field
   (grep needles) plus the surrounding session transcript recovers the phrasing at nudge time;
   these are the highest-value rows because they are, by construction, moments where an agent
   defaulted to native search.
4. **Hand-written paraphrase protocol**, for balance fill only (some skills will not reach their
   quota from transcripts): written from the router moment map in a session where the author has
   NOT opened any description, then mechanically screened (§1.4).

### 1.2 Provenance labeling and balance

- Every new positive row: `provenance=judged`. No new `router` or `desc` rows — those measure
  vocabulary the corpus already over-represents ("a row that quotes the text it scores measures
  nothing").
- Target: **≥153 judged rows total ≈ 9 per routable skill** (17 × 9), i.e. ~95 new judged rows.
  Each skill is filled to ≥9 labels; skills already above stay as they are (no row deletion —
  the frozen rows are frozen).
- Negatives grow proportionally: ~24 new `neg` rows (keeps the positive:negative ratio near the
  current 104:44 so sep-auc keeps its resolution). Negatives are also sourced from real
  transcripts (moments where no ripwire skill should fire), labeled `none`.

### 1.3 The held-out discipline — who holds it, how it is sealed

- **Split assignment is deterministic, not chosen**: each new row is assigned by
  `sha256(prompt_text)` parity — even → `split=test` (held-out; frozen from birth, matching the
  existing test-split freeze), odd → `split=dev` (iteration rows). This removes the collector's
  hand from the split.
- **Sealing**: the collection session writes the full grown TSV and records
  `shasum -a 256 test/skillevalfix/prompts.tsv` **in the recalibration commit message before any
  description-edit session exists**. Collection and editing are separate agent sessions; the
  editing session never opens the new test-split rows and never reads the instrument's
  per-row `misses (...)` blocks for split=test — it iterates on split=dev aggregates + dev miss
  rows only. (The instrument already reports test/dev separately; that separation is the
  enforcement surface.)
- The held-out set is scored **exactly twice**: once at recalibration (aggregates only, to set
  the baseline and re-derived floors — §3.4) and once at the final verdict. Both runs are
  recorded verbatim in the round's EVALS entry.

### 1.4 Contamination screen (mechanical, applied to every candidate row)

Transcript-sourced phrasing can echo description vocabulary (agents that have read the skills do
this). Every candidate row is screened before entry: reject any row sharing a contiguous
≥3-token phrase with any skill's description or with any existing eval prompt; log rejects with
the matching phrase. This is a REJECT filter derived from descriptions — it never *selects*
rows toward anything, so it cannot fit the corpus to the descriptions; it only prevents the
opposite fit.

---

## 2. The pre-registered change and band — as it would enter `docs/EVALS.md`

*(Drafted here verbatim; enters `docs/EVALS.md` only on approval, and only in the execution
round's commit — this plan does not touch that file.)*

> ### §S1 (2026-08-XX) — pre-registered: closing the desc-vs-body judged gap
>
> **Observation being attacked.** bm25-full (raw SKILL.md bodies) scores 35/58 on judged where
> bm25-desc (descriptions) scores 32/58 — the description written to represent a skill loses to
> the body it summarizes. The deficit is vocabulary the body says and the description does not.
>
> **Mechanism (registered before measurement).** For each of the 17 routable skills, compute
> per-skill tf × idf over the SKILL-body corpus (idf across the 17 bodies), subtract every term
> the skill's description already contains (exact match — `bm25Arm` is exact `tf.find`, no
> stemming, so surface forms matter and each added term is the body's literal surface form).
> Candidate terms must additionally pass the validated vocabulary rule: tf ≥ 3 in the skill's own
> body AND document frequency ≤ 4 of 17 across the other bodies. Top-ranked survivors (cap: ≤ 12
> added words per skill, as ADDED prose — never swapping or deleting existing description text)
> are folded into the description as natural trigger phrasing. **Term derivation reads skill
> bodies only — never the eval prompts, never the miss lists.** The full per-skill term table is
> committed alongside the edit so the derivation is auditable.
>
> **Metric.** Paired (same rows, before/after) hit@1 on the grown, sealed held-out judged set
> (split=test judged rows, n ≥ 75), bm25-desc arm. Reported as net flipped rows
> (newly-correct − newly-wrong) and as pp.
>
> **Accept band (≥ 2 points wide; no point prediction):** ACCEPT iff net flips land in
> **[+2, +6] rows** on the held-out judged set (≈ **[+2.7pp, +8.0pp]** at n=75) — the band
> brackets the 3-row (≈5.2%) gap the change targets, scaled to the grown denominator.
>
> **Floors that must hold simultaneously** (all as re-derived on the grown corpus in the
> recalibration commit — see below): `skillevalcheck.sh` test hit@1 + sep-auc + dev floors, and
> both `skillroutingjudgedcheck.sh` judged floors. **sep-auc explicitly may not fall below its
> re-derived floor** — added trigger vocabulary that makes negatives fire is the known failure
> mode of ADD edits, and auc is the tripwire.
>
> **Decision rule.**
> - Inside the band, all floors green → ACCEPT; land; refresh floors only via a deliberate
>   recalibration commit (recall-lane policy).
> - Below +2 rows, or any floor red → REJECT; revert the description edit; write the negative
>   result into this section (as the LB-3 rounds did).
> - **Above +6 rows → NOT auto-accepted.** A result better than the mechanism can explain is
>   audited for leakage first (did any added term coincide with held-out prompt wording?); accept
>   only if the audit is clean, and record the surprise either way.
> - One attempt against the held-out set. If rejected, the next attempt is a new round with a
>   fresh pre-registration and fresh dev iteration — the held-out set is not re-fitted.

**Ordering note baked into the registration:** the baseline for the paired comparison is the
UNCHANGED descriptions scored on the GROWN corpus (recalibration run), never the n=58 numbers —
otherwise the change's effect is confounded with the corpus's (§3.4).

---

## 3. What this round will NOT touch, and why each item is settled

1. **Frontmatter stop-rules stay in frontmatter.** Settled by the 2026-08-04 Codex pilot:
   body-only guards cost a 2–6k-token SKILL.md read, re-billed every turn, to learn the read was
   unnecessary. `agentloopcodexcheck.sh` enumerates the exact marker per skill. Not re-proposed.
2. **No SWAP of existing description prose.** Measured twice: swapping prose out of an
   already-long description fell 72.7→70.5, judged 32→29 — BM25 b=0.75 already length-penalizes
   and the removed prose was already discriminative. This round only ADDS, under a per-skill cap.
3. **No every-skill vocabulary.** "Reach for it instead of…"-class phrasing fell judged 32→28
   (RED). The df ≤ 4/17 filter in §2 is the mechanical form of this prohibition.
4. **No stemming / no `bm25Arm` change.** The ranker change lane (LB-3) was rejected twice by
   the repo's own rules; this round is a *description-content* round on a frozen ranker. Any
   ranker edit would void the registration.
5. **No edits to frozen rows.** Existing test-split rows are never edited, relabeled, or removed;
   growth is append-only.
6. **Floors are re-measured, never inherited — and re-derived BEFORE the change is measured.**
   Corpus growth changes every denominator, so the sequence is fixed:
   **(a)** grow corpus → **(b)** recalibration commit: run the instrument with UNCHANGED skills
   on the grown corpus, record aggregates verbatim, re-derive all six floors with the house
   margins (test: ~8–9pp under measured hit@1, ~0.06–0.07 under sep-auc; dev: 15pp/0.15; judged
   floors likewise under their new measured values), update both gate scripts + the judged-row
   floor (43 → new test-judged count) in that one commit → **(c)** only then measure the
   description change against (b)'s baseline. Floors changed in (b) are corpus-recalibration,
   not change-evaluation; floors are never touched again in (c).
7. **`docs/EVALS.md` and every `SKILL.md`** — untouched until the owner approves this plan;
   §2's block is staged text, not a landed edit.
8. **`ripwire-router` is never a legal label** (corpus header rule) — growth respects it.

---

## 4. Risks and power

- **At n=58, one flipped row = 1.7pp** (the brief's ~1pp is, if anything, generous). The current
  3-row desc-vs-full gap is therefore within two-flips noise — which is exactly why growth
  precedes measurement rather than following it.
- **When is the band meaningful?** The registered band's lower edge is +2 net rows on a held-out
  judged set of **n ≥ 75** (≥153 judged total, hash-halved). At n=75 one row = 1.3pp, so the
  band's edges (+2/+6 rows) are 1.5–4.5× single-row noise, and the paired design means noise is
  confined to discordant rows (the same 75 prompts are scored before and after; rows that never
  flip contribute zero variance). Honest limit, stated up front: with ~5–10 discordant rows a
  sign test on net +3 sits near p≈0.05–0.15 — this round's confidence comes from the conjunction
  of (band) + (all floors green) + (auditable mechanical term provenance), not from n alone. If
  the owner wants sign-test-level power on the band alone, the growth target rises to ~250
  judged; the plan does not assume that.
- **Confounds guarded:** corpus growth vs description change (ordering, §3.4); collector fitting
  rows to descriptions (contamination screen §1.4, deterministic hash split §1.3); editor
  fitting terms to the test set (term derivation from bodies only; test-split miss lists unread);
  machine load (two other suites are running — the instrument is not timing-gated and no timing
  gate is run in this lane).
- **Failure cost is bounded:** an ADD-only description edit reverts cleanly; a REJECT produces an
  EVALS negative-result entry, which this repo treats as a deliverable (LB-3 precedent).

---

## 5. The north-star guard

**This round's result is a routing-proxy improvement and will be reported ONLY as such**: "which
skill wins a prompt" — never as evidence that an agent stops defaulting to Read/Grep/Glob. The
behavior metric is S2's substitution meter, now live on main (verified this session:
`~/.ripwire/substitution.jsonl` is being written, per-call rows with `family`, `nudged`, `arm`
fields). The cross-read, later: a routing ACCEPT here is a *hypothesis* that the substitution
rate (ripwire calls / [Read+Grep+Glob+Bash-parsed-search]) in real sessions should not fall and
ought to rise after the edited skills install; S2's log, split before/after the skills' install
date (and by `nudged` flag, analyzed separately), is where that hypothesis is checked — as an
observational cross-read, not a fresh claim. **The `bench/agentloop` task-success outcome eval
is not proposed and will not be run** — commit `ff928ee`'s power calculation stands (8.5–26pp
MDE floor; a parity pilot cannot resolve it), and S2 has already replaced it as the behavior
instrument by changing the unit of observation from tasks to tool calls.

---

*Lane W1-S1 stops here. Awaiting owner approval before any of §1–§2 executes.*
