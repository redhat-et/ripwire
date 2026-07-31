# gamma.md — a markdown doc (no grammar) to exercise the prefilter on a non-code file.

The `compute` function and the `Widget` struct are referenced here in backticks,
so a literal regex for `compute` or a char-class regex `[A-Z]\w+` must also keep
this file as a candidate.

Special characters that the regex parser must treat literally when escaped:
a dot\. a star\* a plus\+ and a group paren \( here.

No anchored int line lives in this file (the word integer is spelled out).

Spanning: Foo and then eventually Bar appear far apart on this line for Foo.*Bar.
