### Added — `--quality-delta` names a test arm that passes on an empty answer (`defect="zero-evidence"`) and a wrong count word (`defect="count-drift"`)

Two new defect-shape facets, both report-only (`sev="minor"`, never gating).

- `zero-evidence` covers Bash test scripts. It names an arm that passes when every run it reads exits 0 and prints nothing, such as an absence grep or a `cmp` of two answers, when no twin arm can fail on that empty answer. A twin is another arm that reads the same run, the file its output went to, or a variable captured or derived from it. A checked exit status does not help, because a broken verb that exits 0 with an empty page passes it. An arm whose claim is emptiness (`[ -z ]`, `[ ! -s ]`) is not a site. Neither is a statement a vacuous-assert shape already names.
- `count-drift` covers Markdown and C/C++ string literals. It names a count word that introduces a list of names ("the twelve kinds: ...", "six facets (a, b, ...)") when the count is wrong. Either the list holds another number of names, or every name is in one of the tree's string-literal name arrays and that array holds another number. `why=` says which, and names the members the list leaves out. So a kind added to a name table gives a row on every doc and help string that still counts the old set.

Measured on this tree, three dev corpora and 791 CodeRabbit items from PRs #623-#747 (docs/EVALS.md, CR-QD-3). The quality snapshot scheme moves to 39, so an older snapshot cache is rebuilt once. Markdown files now leave a defect-shape presence record.
