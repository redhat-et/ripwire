### Documented — `docs/LINEAGE.md` refreshed against the 2026-11-26 research audits: six rows added, twelve corrected or qualified, three tools surveyed

Six §2 rows were added, and each one points at code that ships today. Chidamber & Kemerer back `cbo=` on `--metrics`. MacCormack, Rusnak & Baldwin back `propagation_cost=` on `--arch`. Both are citation debt: the code cited them before the table did. Xu & Wu on MCP error text back the refusal retry clause and `next=`. CuraLoc backs `--pack-task` and the MCP `batch` verb. Two vendor sources are labelled as not peer-reviewed: the Claude Code output-limit documentation behind `kOutputCeilingChars`, and Anthropic's tool-writing post behind `next=` and the refusal table. Twelve existing rows now carry follow-ons that weaken, correct or strengthen them:

- Louvain can return disconnected communities (Traag et al. 2019). Nothing here checks for that yet.
- The metric-feedback row had read two Pass@1 improvements as two Pass@1 levels. It now says what the abstract says, with two replications and a gaming caveat.
- The agent-maintainability row is narrowed to "in that study". A second study is cited where complexity does track model comprehension failure.
- The AI-smells row's law is scoped to generated code. A 50-project open-source study finds lower smell density in the agentic era.
- Seventy-four percent of hotspot edits come from bots (MSR 2026), and nothing here filters them yet.
- The Cognitive Complexity, Posnett, Gall, Shotgun Surgery, Lanza & Marinescu, keyword-search and Marmoset rows have dated follow-ons. One of them, the keyword-search follow-on, is a pre-registered study that cuts against the no-embeddings choice for small models.

Three §3b tools were added: ColGREP, CodeAssure and the SWE-rebench trajectory-analyzer. The counts are now 49 repositories, 85 papers and 240 surveyed tools. `test/readmedriftcheck.sh` arm (H2) now reads arXiv ids from a row's Work cell only, so a follow-on cited inside a row is not counted as a folded paper. It also refuses a publication date later than the README's as-of date, which it used to count as recent. New controls (H2b) and (H2c) prove both. The README recency sentence re-derives as nineteen 2026 papers, two in the last two months and none in the last thirty days, as of 2026-11-26.
