### Fixed — a TypeScript/JavaScript module-level constant with a literal value is a definition

A module-level `const`, `let` or `var` whose value is a string, template, number, object or array literal (or a
unary/binary expression), also under `as`, `as const`, `satisfies`, `!` or parentheses, is now a `t="var"` definition
whatever its case, with its whole declaration as its span. An exported destructuring (`export const { a, b } = x`,
`export const [ p, q ] = pair`) defines each name it binds. Before, only SCREAMING_SNAKE names were kept, so on
microsoft/TypeScript `--defs=versionMajorMinor` and `--defs=commandOptionsWithoutBuild` found nothing and `--at` on a
line inside that 1 050-line array refused. Still not definitions: function-local consts, non-exported destructures
(an import-shaped alias such as `const { readFile } = require("fs")`), and call-, `new`- or alias-valued consts.

Index growth, measured cold: microsoft/TypeScript 215 985 -> 271 670 symbols (+25.8 %; most of it in
`tests/baselines/reference` and `tests/cases` test data) and cache 86.3 -> 91.8 MB (+6.4 %); hono +2.2 % symbols,
+0.3 % cache; nest +0.6 % / +0.1 %; angular +1.2 % / +0.2 %. Each new row is bodyless, so bytes grow far less than the
count. `kParserVer` moves, so caches re-index once.
