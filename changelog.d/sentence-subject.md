### Changed — a `--for` sentence gets the callers, path and connect blocks its bare names get

A task written as a sentence lost the subject blocks that the same symbols get in a short key. "`Route::new` gains an extra required argument" printed `<callers by="subject">`; the full question about the same function printed none. The same happened to "path from A to B" asked as "trace the exact call chain from `A` to `B`", and to "common caller of A and B" asked as "which function calls both `A` and `B`". Agents write sentences, so they met the weaker answer.

- A sentence that puts ONE function in backticks and asks what calls or depends on it now gets `<callers by="subject">`, however long the sentence is and whatever other identifier it mentions in passing. A call's argument list (`` `f(title)` ``) and a Go receiver (`` `(*pkg.T).M` ``) read as the name. The rule for sentences without backticks is unchanged.
- `[call] chain from A to B` and `A reach(es) B` run the path verb, and `calls both A and B` runs the connect verb, as `path from` and `common callers of` already did. Each slot still needs a code-like name, so "a chain from start to finish" reads nothing.
- When a sentence that spells code asks for callers or a path and the answer still carries no such block, the answer ends with one `<reask next="--callers=X"/>` (or `--path=A,B`, `--connect=A,B`). That is the bare call that answers the question. The orient skill says the same.

Everything is additive: the answer before the new block is byte-identical. `test/sentencesubjectcheck.sh` pins each form, its negatives (no cue, two functions, the callee sense, a negated cue, the words with no code) and the re-ask.

Found by the Fable residual-rows and precision pass (2026-11-12), which measured the dropped blocks on 29 in-sample rows (SENTENCE-SUBJECT-BLOCKS and RE-ASK cards).
