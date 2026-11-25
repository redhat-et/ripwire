### Changed — `--for` confidence= gains a file-gap ground; the edit-file body form is on by default (`RIPWIRE_ROUTING=0` turns both off)

`confidence="high"` used to need a 20 % adjacent score drop in the ranked head. A question with many terms gives a smooth BM25 sum, so 122 of 181 GA1/GA3 DEV answers were `low` with `margin_pct="0"`, including 51 whose top file was right. Now a head is also high when the best row of any other file trails `r=1` by 20 % or more; the header then says why with `file_gap_pct="N"` (present only when it grounds the level, defined in both legends). On GA1/GA3 DEV, high grows from 59 to 71 answers at the same 73 % top-file precision. It is never high over a homonym decline or an unproven anchor. Ranking and pages are unchanged.

The edit-file body form (`RIPWIRE_BODIES_EDIT`, previously off) is now the default for an edit task: the top file's bodies become act ranges. On GA1 DEV: 0 items lost, the same gold ranges shown, page 1 −3 %. `RIPWIRE_BODIES_EDIT=0`/`=1` still decides when set.

`RIPWIRE_ROUTING=0` serves the answer from before this change byte for byte. Gates: `test/routingcheck.sh`, `test/bodyeditcheck.sh`.
