### Fixed — the CLI `--batch` pages under the output ceiling by whole sub-answers

Each sub-verb bounds its own answer, but a batch of many did not, so `ripwire . --batch=FILE` could print far past the 30,000 characters Claude Code shows inline. The harness then saved it to a file and showed a 2,000-character preview. The MCP `batch` verb pages the same unit (#774).

- A batch whose answer fits is unchanged, byte for byte.
- Past the 24,000-byte output ceiling, the answer is served in pages of whole `<q>` sub-answers. The root says `offset= shown= has_more=` and, when more follow, `next_offset=` and `next="--batch=FILE --offset=K"`. The `next=` also replays the flags that shaped the sub-answers (`--legend=`, `--top-k=`, `--order=stable`, `--no-redact` and the crawl scope).
- A sub-answer is never split. One larger than a page by itself is served alone and whole: `over_ceiling="1"` on the root, plus one stderr line naming its size.
- `--page-bytes=0` prints the whole batch, with the same over-ceiling stderr line `--for --page-bytes=0` prints. `--page-bytes=N` with N > 0, `--page-bytes=0 --offset=K`, an `--offset` past the last sub-answer and `--limit` all refuse.

Gate: `test/outputceilingcheck.sh` arms B0–B18 and N-B.
