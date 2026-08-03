# paper/

The working draft of a preprint about this tool, kept in the repository it measures so its numbers
and its evidence cannot drift apart.

**The thesis, in two sentences.** A deterministic, model-free, sub-second symbol ranker establishes a
measured *floor* for code localization — 60.9% strict file@10 on held-out Python LocBench, 55.4% on a
public C++ benchmark built for this work, and a pre-registered graph-expansion candidate rejected
twice for failing to beat it. The second half of the claim is the method that makes those numbers
checkable: gate before code, audit your own output adversarially, and machine-check every published
claim against the shipped binary — including this paper's own flag names.

**Status: working draft, in preparation.** Not submitted anywhere, not peer-reviewed, not a release
artifact. Numbers are current as of the date in the draft's status header.

**Checking any number.** [`../docs/EVALS.md`](../docs/EVALS.md) is the register: it names every
published figure's instrument, corpus and pinning file, and §8 lists the claims this project refuses
to publish. Each table in [`PREPRINT.md`](PREPRINT.md) names its own pinning artifact under
`bench/`; open that file rather than trusting the table.

| File | What it is |
| --- | --- |
| [`PREPRINT.md`](PREPRINT.md) | The draft. |
