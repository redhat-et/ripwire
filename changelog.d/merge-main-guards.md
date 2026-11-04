### Fixed — `scripts/merge_main.sh` no longer stops on an RST underline, and refuses a kParserVer both sides bumped

The staged-marker check read the RST `=======` underline at `test/restdocscheck.sh:77` as a leftover conflict marker, so every lane's merge of main stopped on a file that was identical to main's. The check now skips a path whose staged text is `MERGE_HEAD`'s own; a real `<<<<<<<` / `=======` / `>>>>>>>` hunk in any other path is still refused and named.

When both sides bumped `kParserVer` (`src/ingest_cache.h`) above the merge base, the merge is refused unless the merged value is above both. The message names the lane's and main's numbers and suggests max+2 (the rich file tag is `kParserVer` + 1), and reminds you to update `kIngestParserVerMirror` in `src/quality.h`. One side bumped, or neither: nothing is checked. `test/mergemaincheck.sh` has arms for both.
