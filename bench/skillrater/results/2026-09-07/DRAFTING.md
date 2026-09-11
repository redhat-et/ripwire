# Drafting log — C1 descriptions (dev split only; the held-out set was never read as text)

| draft | set total (chars) | over 320 | dev bm25-desc hit@1 | note |
| --- | --- | --- | --- | --- |
| today (arm A) | 18,455 | 18 | 69.1% | baseline |
| today head-cut (arm B) | 6,300 | 0 (cut) | 57.4% | what Codex renders |
| 1 | 6,970 | 18 | — | first compression, not scored |
| 2 | 6,158 | 13 | — | not scored |
| 3 | 5,547 | 5 | — | not scored |
| 4 | 5,140 | 2 | **48.5%** | terse; dev misses were surface-form losses (godfile/godfiles, deserializer/deserialization, compacted/compaction) and cut moments |
| 5 | 5,674 | 11 | 83.8% | natural trigger phrases restored from the dev misses |
| 6 | 5,551 | 5 | 80.9% | trims |
| 7 (committed 9e1e9f90) | 5,400 | 0 | 77.9% | total ceiling amended 4,800 → 5,400 before measurement |
| 8 (committed 2ee10e36 = C1) | 5,386 | 0 | 77.9% | orient regains "main subsystems and entry points" for the cold-start gate row; held-out bm25-desc 43 → 42 / 85 |

`draft1_descs.py` and `draft2_descs.py` are the first two drafts verbatim; drafts 3–6 were overwritten in
place (their sizes and dev scores are the record); `desc_C1.md` / `desc_C2.md` are the rated texts.
Lexical reports for every arm are under `lexical/`; the blind packets (what each rater saw), the sealed
keys (never shown to a rater) and the raw answer files are under `packets/`, `keys/`, `answers/`; the
single dev dry run under `devdryrun/`.
