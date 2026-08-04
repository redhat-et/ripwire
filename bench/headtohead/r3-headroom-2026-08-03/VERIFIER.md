# r3 adversarial verification — findings and dispositions

Independent post-run verifier, briefed to break the comparison. Integrity baseline passed: frozen
artifacts byte-identical to commit `f3f2053` (which predates all results); full re-run of arms A
and C reproduced every recorded token count exactly on all 12 questions; all published totals
recompute from `results.json`. Findings are claims settled by re-measurement; every one below
carries its disposition in the shipped REPORT.md.

| # | severity | finding | disposition |
|---|---|---|---|
| F1 | BREAKS-THE-RESULT | The draft's "+1,013 t headroom overhead / never compressed" attributed the harness's own packaging (+1,423 t: question text + `[tool result …]` wrappers, charged to B only) to headroom. True decomposition: headroom net **−410 t** on content; it compressed four `mixed` grep chunks (q01 −56, q02 −48, q06 −136, q10 −170); all code chunks byte-identical passthrough. The pre-registration's H1 fix was applied to satisfaction scoring but not to the charged-token metric — a metric asymmetry inside the "one implementation" rule. | Headline and readings rewritten around the decomposition. Raw B/D columns kept (they are what the frozen metric measured), decomposition published beside them |
| F2 | BREAKS-ATTRIBUTION | D−C = +829 is 100% harness framing; headroom added **exactly 0 t** to ripwire output on all 12 (byte-identical passthrough). "Composition adds nothing" survives; "returns it with overhead" did not. | Composition bullet rewritten |
| F3 | WEAKENS-FRAMING | 92.5% of C's 50,138 t were spent on the seven failed questions (cheap partly because the ladder gives up while A reads until it succeeds). The 7.3% headline conditions on different satisfaction rates. | Published both companions: both-satisfied subset 1.7% (58×), and the C-then-naive-fallback composite ≈268,019 t = 39% of A at equal 11/12 satisfaction. q03's C "satisfied" verified genuine (18 real caller rows spanning all four gold files) |
| F4 | WEAKENS-A-CLAIM | Two loss-table recovery costs did not reproduce: q06 recovery is 930–2,125 t (not ~375) — naive wins q06 ~2.5× even granting recovery; q12's `--expand=get_host` multi-def-expands to 9,808 t (not ~1,300) — but `--uses=DisallowedHost` alone (1,066 t) completes gold, corrected chain 1,329 t. | Both rows corrected; q06 reclassified from "near-tie" to a naive win |
| F5 | WEAKENS-SCOPE | `HEADROOM_DISABLE_KOMPRESS=1` is read only by proxy mode — a no-op for the library-mode calls this run made. Kompress's absence is real but proven by transform markers (no `kompress` marker in any of 60 results), not by the env pin. | Pins section rewritten; determinism scope restated |
| F6 | SURVIVES (strengthened) | B′ firing only on q02 reproduced exactly; q07/q08 re-run under the override plus `min_tokens_to_compress=50`, `target_ratio=0.3`, and headroom's shipped `agent-90` high-savings profile: ratio 0.000 in every case. Wording: "the only transcript headroom acted on" (classification vs ratio-gating indistinguishable from outputs). | Wording adopted |
| F7 | WORDING | Original headroom determinism check was same-process and on a no-op path. The verifier's fresh-process re-runs reproduced compressing paths to the byte (q02 B′ 32,835 exact). | Determinism paragraph rescoped to that evidence |
| F8 | WORDING | Timing asymmetry: ripwire medians include process spawn; headroom timed in-process post-import (≈0.05 s spawn+import if charged; first-call pipeline init 0.13–0.37 s visible in max_s). | Stated in §(iv) |
| F9 | WORDING | "Code — Passthrough" / 0.0% table is in headroom's GitHub README/wiki @ `3f2ca99`, not the installed METADATA; the "15-20%" headline IS in METADATA (line 172). | Citations pinned accordingly |
| F10 | MINOR | Frozen `harness.py` docstring references a `run_all.sh` that never existed; run environment was otherwise unrecorded. Materially harmless (F5: the env pin was a no-op; full re-run under the stated env reproduced every number). | Environment recorded in REPORT §(i); frozen file left untouched by design |

Headline-claim verdicts: (1) failed as stated → rewritten; (2) survives, strengthened; (3)
arithmetic survives, framing amended; (4) conclusion survives, attribution rewritten; (5) survives
with corrected mechanism; (6) survives with labeling.
