### Fixed — `--impact=<path>` lists the file's importers instead of answering `found="0"`

The selector is a symbol, so a path matched nothing and the answer was `found="0"` with no hint, even for a file hundreds of
files include. When no symbol matches and the selector names one indexed file (root-relative, with a leading `./`, absolute
under the root however the root was typed, or a path suffix only one file has), the answer is that file's importers under
`selector="file"`, exit 0, with the importer listing's own `shown_importers=`, `importers_capped=`, `importers_next=` and
rollup. The answer names the file it used, `file=`, and a suffix match says so, `matched="suffix"`: a path to a deleted or
unindexed file that another file's path ends with answers for that other file, visibly. It has no call reach: `FILE:SYM`
still picks one symbol. A symbol match always wins, so no selector that answered before answers differently. A suffix several
files share stays a refusal whose `near=` is the first such path, with `matches=N` counting them.
When files name the path in an include or import that resolved to no indexed file (an include root the index does not know),
the answer carries `unresolved_naming=N`, so `importers="0"` on such a file reads as a possible floor, not as unused: Envoy's
`envoy/registry/registry.h` answers `importers="0" unresolved_naming="580"`. A directive that resolved to another file of the
same name (`a/util.h` beside `b/util.h`) is not counted.
