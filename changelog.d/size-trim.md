### Changed — `--for` legends define only what the answer carries

The `--for` legend clauses for `d layer=`, `iface implementors=`, `field name= type= owner= rel=` and the fold's `slice members= of=` were decided from the ranked set before the rows were rendered, so most answers carried them with no such attribute anywhere in the document. They are now checked against the final rows and dropped when nothing carries them; the `<syms>` legend's `test=1` and `files= head=` readings ride only on a block that prints them. Every attribute an answer emits is still defined in that answer; a section streamed without buffering keeps its clause.

### Changed — a code question's `--for` tail counts non-code path-only rows instead of listing them

On a code question the tail's widened rows (past the first 40 code rows, path only) of doc, test, config, script, test-data and other files are no longer listed: the tail says how many it folded per class (`folded="doc=40,test=30,config=20"`, JSON `"folded"` with `"folded_why"`), `capped="1"`, and `next=` pages from the first folded row, so every folded file is one call away. Code rows are never folded, a task that names tests, config or scripts keeps that class, and a docs question folds nothing. `RIPWIRE_NO_TAIL_FOLD=1` lists every row as before. New gate `test/fortailfoldcheck.sh`.

### Changed — repeated `<d>` text and tail names print once

A `--for` `<d>` row whose doc and signature text (40 bytes or more) repeats an earlier row's keeps all of its attributes and prints `same_as="<n of that row>"` instead of the text (a run of constants or overloads with one shared comment), with a present-only legend clause. A tail row's `sym=` no longer repeats a name it already lists.
