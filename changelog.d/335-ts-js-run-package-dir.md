### Fixed — TS/JS `run=` runs from the package directory (#335, #442, thanks @llvm-x86)

A TS/JS test in a subdirectory package got a `run=` that could not run. The command was root-relative. Run from the root,
the runner found no package config. Run from the package, the path was root-relative. Now the command is a subshell,
`(cd <package> && <runner> <path>)`, and the path after the `cd` is package-relative. The subshell keeps the `cd` from outliving the command, so a shell that keeps its directory between calls (an agent's) starts the next row at the root again. A multi-root run has no `root=` and keeps the plain command. Paste it from the shell at the root.

A bracketed path, such as a Next.js route (`app/[slug]/page.test.ts`), had `--` before it. vitest reads `--` as the end
of its options and drops the file filter, so the row ran the whole suite. vitest and jest now get one quoted path.

Two paths get no `run=` now. A path that starts with `-` gets no `run=`, because the runner could read it as an option. To run such a file by hand, use `node ./-suite.test.mjs`: on Node 26.9 `node --test` drops the `./` and exits 1 with `bad option`. Node's test runner globs its
file arguments, so a bracketed path under `node --test` matches no file and the runner exits 1. Both rows print `run_unknown="1"`.

jest reads its argument as a regular expression, so a path under a package below `root=` has every regex byte escaped with a backslash, a dot included (`a.test.js` would also match `aXtest.js`).

A package at `root=` keeps its command. A path there that is not shell-safe loses the `--` and has its regex bytes escaped. For `node --test`, a glob byte in the path gives `run_unknown="1"`.

Limit: a jest package at `root=` keeps a plain dot as a regex dot when the path is shell-safe, so its filter may also match a sibling such as `route/test.ts`. vitest and jest match the path as a substring, so `src/lib.test.ts` also runs `deep/src/lib.test.ts`: a run can include extra files, never fewer.

A vitest or jest command now needs a file the runner's default include collects: a name ending in `.test.<ext>` or `.spec.<ext>`, or, for jest only, a file under a `__tests__/` directory (jest matches that glob against the whole path, so one above the package counts too; thanks CodeRabbit). `x.test.helper.ts` (both runners) and a vitest `__tests__/x.ts` got a command that exits 1 with "No test files found". They are now `run_unknown="1"`. The rule follows `defaultVitestFileName` from #330 (thanks @rainhuang0220, #330). Limits: a `vitest.config.*` or `jest.config.*` `include`/`testMatch` is not read, so a config that narrows the default still gets a command; and jest 29's default lacks the `.mjs`/`.cjs`/`.mts`/`.cts` extensions that jest 30 collects, so a jest 29 package gets a command for such a file that exits 1.
