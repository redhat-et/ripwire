### Added — a `--for` task that names a literal carries the literal's sites and the code that handles it

A `--for` task that carries a "double-quoted message" (at least six bytes inside the quotes, a letter, an ASCII space inside, no leading or trailing blank: `"a b"` does not qualify) or a CONST_SHAPED word (an environment variable, an
error code or a setting name such as `FZF_DEFAULT_COMMAND`, `FST_ERR_DUPLICATED_ROUTE`, `PYTHONASYNCIODEBUG`) now ends with a
`<lit>` element, just before `</ctx>`: the grep verb's byte-exact scan of the index for that literal. Its `<ls>` rows are the
sites in source files, labelled by the parse (`k="string"` inside a string literal, `k="code"` outside one, `k="?"` a file not
classified) with the definition holding each (`in=`, `ink=`), sites inside a function first; comment sites, Python docstrings (a
triple-quoted string that is the first statement of a module, class or def body; the same string opening a call-argument line is a
site), test paths and doc, shell or config files are counted (`comment=`, `test=`, `doc=`), never listed as a handler. The function
holding a shown site is printed whole when it is ten lines or fewer and its body is at most 3,000 bytes (`<b>`, at most three; a short but large or minified body is an excerpt); a longer one is an excerpt (`<x>`): its
signature line and one window of the site line minus one to plus five per shown site (`l=` lists the ranges, windows that overlap or touch are merged and an ellipsis line sits
between disjoint windows only, `of=` is the body, `next=` the whole body; each window line is cut at 200 bytes, marked `cut="1"`, so a minified one-line body is never printed whole); a body the answer already printed is not repeated (`body="above"`); an owner past the three-body cap prints no body and its rows say `body="held"`.
At most eight `<ls>` rows are shown (`shown=` against `src=`, `capped="1"` when sites were left out; `next=` lists every site); `floor="1"` marks the counts as lower bounds when the scan stopped early or a source site was left unclassified (past 64 hit files, or a file the parse could not read), and the matched lines and excerpts are credential-redacted like any other body.
Several sites are always listed with counts; a literal with no source site (found only in tests, docs or comments, or not at all)
carries no block. The element carries its own legend (a 458-byte form under the default `--legend=compact`, the long text under `--legend=full`) and its size (`bytes=`, not in `est_tokens`);
everything before it is byte-identical to the answer without it (`RIPWIRE_NO_LITERAL_ANCHOR=1`); `--json`, the columnar and
candidate-list dialects, a multi-root run and an explicit `--token-budget` carry none (the default XML dialect with a single root only). A `--flag` spelling is not read as a literal. Gate:
`test/forliteralcheck.sh`.
