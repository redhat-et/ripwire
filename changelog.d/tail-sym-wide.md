### Changed — the `--for` tail's rows past page 0 now name their file's top symbols too

Since the tail walked four pages of the file page, a row past page 0 printed only its path (`p=`), so a file the answer listed at tail rank 41-160 never said which symbol in it matched. Those rows now carry `sym=` as well: the file's top three symbols by lens rank, the same pick and spelling every page 0 row uses (names the ranker already scored for that file, never a text match). The rows, their order, `total=`, `shown=` and `next=` are unchanged; only the names are added. Up to 120 such rows carry names (`kForFileTailSymWideRows`, every widened row a plain walk lists); a code question's walk can list more, and those past 120 still print `p=` only, counted by `p_only=` as before. Both walk legend clauses say so.

Measured on the 60 practice rows (stored, P1 and P2 wordings) and the 321 in-sample calls; the numbers are in the PR. `test/fortailwidecheck.sh` arm 14 pins the default against `RIPWIRE_TAIL_SYM_WIDE_ROWS=0` (the pre-change tail, a measurement and ablation knob) and the 10-row knob, in XML, JSON and the MCP `for` twin.

The walk legend clause change moves the session legend dictionary to `dictv=1106f51037b7009f entries=1053` (docs/COMMANDS.md and the showcase capture are re-recorded).
