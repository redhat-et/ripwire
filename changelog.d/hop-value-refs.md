### Added — a `--for` hop row says when its function is used as a value, and when that cannot be read

A function that is only ever stored or passed (a handler table, a registered callback) has no caller edge, so its `<h>` hop row read exactly like one whose callers are all resolved. `--callers` already prints `value_refs=N` for it; the hop row did not. Call edges are matched by name, so a callback or a call through a slot can be missing, and the reader could not tell "no caller exists" from "the caller is a slot the graph does not follow".

- `<h … value_refs="N">`: the row's function is used as a value N times (what `--callers` prints as `value_refs=`). A call through that slot is not an edge.
- No attribute: none found, for a language whose value uses are read. Never "none exists".
- `<hops … value_refs_unread_for_lang="rb,sh">`: a printed row is in a language that reads no value use at all, so its missing `value_refs=` is unknown, not zero (the precedent is `--lego`'s `implementors_unread_for_lang=`). Only languages of printed function rows are named.
- Two present-only legend comments define the attributes beside the section. `total=` `shown=` `capped=` `noedge=`, row order and every callee row are unchanged.

Measured on a fresh draw of 216 `--for` cells (short wording, not the cells that prompted it): 0 structural differences against the previous binary, 51 answers (23.6 %) carry an attribute, +58.9 B per answer on average (0.20 % of bytes), +249.5 B per answer that fires. 30 of 30 checked counts equal `--callers`. Gate: `test/hopvaluerefscheck.sh`.

What it does not do: it recovers no item and moves no rank. The retrieval-gap partition's 9 resolution items rank 220 to 4,534 and are not hop rows; only 3 of them have a value use at all. Rows whose name has several definitions count one definition, where `--callers` counts all of them.
