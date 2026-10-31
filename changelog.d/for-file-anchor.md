### Fixed — `--for` on a file name answers with that file (reported in #466 by @pguerrerolinares)

A `--for` subject that is a file used to miss it in every language: a bare basename (`--for=DynamicScreen.c`,
`--for=sync_ledger.py`) was split on its dot and anchored nothing, a snake_case stem (`--for=sync_ledger`) ended in an empty
`reason="no_candidates"`, and a hyphenated stem (`--for=document-remind`) returned a `confidence="high"` answer whose head was a
test sibling or a decoy that merely shared its words. Now a bare basename with a code extension, a hyphenated or snake_case stem
(when no symbol has that exact name) and a directory anchor the file(s) they name, and a subject that is nothing but the file
(stopwords and words like "file", "package", "script" aside) gets a `<named-file>` page first in the answer: every def in line
order with its last line, its indexed callers (`in=`; `in="0"` is "no caller in the index", never "unused") and their files
(`by=`), a pasteable `next=` graph query listing the defs neither `main` nor the file's own top-level code reaches within 16 calls, and for a script whose work is its top-level code
(Bash, Python `__main__`, JS/TS, Ruby, Lua) that top-level text, capped at 40 lines / 2 KB with the rest disclosed
(`<top_cut rest=>`). The named file's top defs rank first. A name that matches several files lists them in `<named-files>` and
picks none; a file named as context in a longer question is anchored but gets no page; a dotted `Class.method` with no such
file keeps its old reading. `RIPWIRE_NO_FILE_PAGE=1` turns the page off. Gate: `test/forfileanchorcheck.sh`. A path that names a directory (`--for=pkg/foo`) is read as that
directory before any shorter suffix, so it is never answered by an unrelated same-stem file elsewhere; a shorter-suffix match is
listed as `near="1"` and never paged. The whole page stops at 16 KB at a file boundary (`bytes_capped="1"`). The note the lift leaves in the answer's header comment now says what it did to the auto-served bodies: they follow the named file's rank, a def ranked lower gets none, and the expand flag reads one by name.
