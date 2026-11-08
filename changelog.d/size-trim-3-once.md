### Changed — repeated `<d>` text and tail names print once

A `--for` `<d>` row whose doc and signature text (40 bytes or more) repeats an earlier row's keeps all of its attributes and prints `same_as="<n of that row>"` instead of the text (a run of constants or overloads with one shared comment), with a present-only legend clause. A tail row's `sym=` no longer repeats a name it already lists.
