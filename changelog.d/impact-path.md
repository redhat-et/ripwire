### Fixed — `--impact=<path>` lists the file's importers instead of answering `found="0"`

The selector is a symbol, so a path matched nothing and the answer was `found="0"` with no hint, even for a file hundreds of
files include. When no symbol matches and the selector names one indexed file (root-relative, with a leading `./`, absolute
under the root, or a path suffix only one file has), the answer is that file's importers under `selector="file"`, exit 0,
with the importer listing's own `shown_importers=`, `importers_capped=`, `importers_next=` and rollup. It has no call reach:
`FILE:SYM` still picks one symbol. A symbol match always wins, so no selector that answered before answers differently. A
suffix several files share stays a refusal whose `near=` is the first such path.
When files name the path in an include or import the index did not resolve to it (an include root it does not know), the
answer carries `unresolved_naming=N`, so `importers="0"` on such a file reads as a floor, not as unused: Envoy's
`envoy/registry/registry.h` answers `importers="0" unresolved_naming="580"`.
