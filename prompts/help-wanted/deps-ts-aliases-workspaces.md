# TypeScript aliases and workspace packages: draw the file-graph edge, or say the graph is partial

> **Solved (2026-11-26).** All four slices are on `main`. Part 1, an in-tree alias or workspace import that draws
> no edge is counted on the root (`imports_unresolved="N" graph_partial="1"`), landed in [#336](https://github.com/redhat-et/ripwire/pull/336)
> (train 20). Part 2, tsconfig `paths` and `baseUrl`, workspace package names and `package.json` `imports` resolved
> into real `--deps`, `--arch`, `--report` and `--impact` edges, landed in [#340](https://github.com/redhat-et/ripwire/pull/340) (0.6.5,
> train 21), closing [#220](https://github.com/redhat-et/ripwire/issues/220), reported by @srinchow. Both were maintainer lanes;
> [#717](https://github.com/redhat-et/ripwire/pull/717) later made a `paths` alias pin the named-import call binding as well, fixing
> [#711](https://github.com/redhat-et/ripwire/issues/711). `test/depsprecisecheck.sh` carries the #220 arms. Run on this kit's own script, the alias
> tree now prints the relative tree's answer: two cycles, `ccd="11"`, `--arch` exit 2; a `./f.js` specifier reaches
> `f.ts`. This kit stays as a worked example; nothing in it remains open.

**Large overall · four slices, the first two good-first-issue sized · issue #220 · no prerequisite**

You are fixing ripwire's **file graph** for TypeScript and JavaScript monorepos. `--deps` resolves only
relative specifiers. An import spelled through a tsconfig `paths` alias (`@app/b`) or a workspace
package name (`@acme/lib`) draws no edge. Everything built on that graph then answers a smaller graph
than the compiler sees, and says so nowhere: a cycle through an alias is missing, `--arch` passes a
layering rule it never checked, and `--report` prints `Dependency cycles (showing 1 of 1)` over a
graph that holds two.

The work splits into four slices that land as separate pull requests. **Slice 1** makes the partial
graph say it is partial. **Slice 2** maps a `./x.js` specifier to its `x.ts` source, which the call
graph already does; a maintainer pull request split out of #44 may take it, so check before you start
it (see slice 2). **Slice 3** reads tsconfig `paths`. **Slice 4** reads workspace package names.
Slice 1 is the recommended first pull request: it is useful on its own, and slices 2 to 4 then shrink
the number it adds.

This is not a tour. Every output below was recorded with a plain dev build of `30f14a27`; `main` at
`f8e6087c` differs from it only in `src/quality.h`, which nothing below reads. Every TypeScript
behaviour marked "tsc" was checked with `tsc --traceResolution` or `tsc --showConfig` (TypeScript
7.0.2). Line numbers move, so every pointer is a function name: `git grep -n <name> -- src` finds it.

Work in a git worktree, not the main checkout. Run every gate in the foreground.

---

## Why this matters

- **The zero reads as an answer.** No `<cycles>` element, `violations="0"` and `propagation_cost="0.280"`
  look exactly like a clean architecture. `CLAUDE.md` non-negotiable 3 says a zero means "none found",
  never "none exists". `docs/METHODOLOGY.md` §9 principle 6 says a count that cannot be a total is a
  floor. Today nothing on `<deps>`, `<health>`, `<arch>` or the `--report` line says how many
  directives went unresolved.
- **Aliases are the mandated style in many monorepos.** The issue's own census, on a 2,700-file pnpm
  repository: 3,123 `from '@/…'` lines and 3,459 `from '@package/…'` lines, against 1,427 relative
  ones. `ripwire --deps` reported 0 cycles; the repository's own `require.resolve` checker reported 2
  (11 files and 10 files).
- **Seven surfaces read this graph, and so does the call graph.** `--deps`, `--arch`, `--report`,
  `--impact`'s importer tier (CLI and MCP), `--cochange`'s `surprising=` flag, `--for`'s structural
  expansion and `--export=cc.json` read the file adjacency. The call graph resolves named imports
  through the same resolver, so an aliased import also loses its `prov="import"` evidence (see
  "Reproduce the gap").
- **It also limits #60's fix.** The maintainers are fixing #60 by resolving calls made outside any
  named function (a test's arrow callback, for example) through the normal resolver, so they count as
  test evidence. A call imported through `@/foo` cannot be narrowed to its definition until this lands.

---

## STEP 0: check the ground has not moved

```bash
git fetch origin
git grep -c 'if( !ws || ws->configAliases.empty()' origin/main -- src/resolve.h   # 2 at f8e6087c: resolveTsImport and resolveGoImport
gh pr view 44 --repo redhat-et/ripwire --json state,mergedAt                          # see "Related": it carries a slice 2 hunk
gh pr list --repo redhat-et/ripwire --state all --search '220 in:body'                 # pull requests that reference #220 (slice 2 may be taken)
gh issue view 163 --repo redhat-et/ripwire --comments | tail -20                      # the sibling TS call-graph lane; know who holds it
```

A different count on the first line means someone has changed bare-specifier handling. Run the
reproduction before anything else, and if an alias edge already draws, **stop and say so on #220.**

---

## Background: read these before you plan

### Where a directive becomes an edge

- **`buildPreciseIncludeAdjWithContext`** (`src/resolve.h`) loops over `ing.includes` and calls
  **`resolvePreciseInclude`**, which picks a per-language Step-A by the includer's extension
  (`includeLangOf`). TS and JS files go to **`resolveTsImport`**.
- **`resolveTsImport`**: a specifier not starting with `.` returns `kNoFile` on a single root. A relative
  one probes the exact spelling, then `kFileExt` (`.ts`, `.tsx`, `.d.ts`, `.js`, `.jsx`, `.mjs`, `.cjs`),
  then `kIndexRel`, and resolves **only when exactly one file answers** (unique-or-degrade). Back in
  the loop, a `kNoFile` result is skipped with `continue`. Nothing counts it.
- The comment block that opens the per-language Step-A section (above `includeLangOf`) states the
  soundness bar every Step-A obeys: exactly one repo file, or nothing. Never a basename match, never a
  guess.

### The config-alias machinery that already exists, and its limits

A merged multi-root run (`ripwire dirA dirB …`) already reads tsconfig aliases:
`buildPreciseIncludeAdjWithContext` calls **`readConfigBytes`** on `<root>/tsconfig.json` and
**`parseTsconfigPaths`**, which appends **`ConfigAlias`** records to **`WsIncludeCtx::configAliases`**;
`resolveTsImport`'s bare-specifier branch probes them against `absIndex`. Read it before you design,
because it shows the evidence-only posture and because its limits are the gap:

- **Cross-root only, on purpose.** `parseTsconfigPaths` drops any alias whose destination
  `pathIsUnder` its own root. The comment says intra-root aliases "stay external exactly as a bare
  specifier is single-root". Slice 3 retires that sentence; say so in the plan.
- **One file, one target.** Only `<root>/tsconfig.json`, no `extends`, only the first array element,
  only a trailing `*`.
- **A text scan, not JSON.** It finds the first `"baseUrl"` and `"paths"` byte strings anywhere in the
  file, comments included. Measured on a two-root fixture: `@lib/*` → `../lib/src/*` resolves
  cross-root, and adding one line `// "baseUrl": "nowhere",` above the live key makes the edge vanish
  with no disclosure. Reuse the posture, not the scanner.
- `test/multirootcheck.sh`, section "Decision B", pins the cross-root alias and its bogus-target
  mutation. It must stay green.

### Every consumer of the resolver

A change in `resolveTsImport` reaches all of these. Your plan says, per consumer, whether its output is
expected to move and how you will show it:

| consumer | surface |
| --- | --- |
| `resolveStructuralIncludeAdj` → `runArchViews` (`sccCycles`, `dependencyHealth`, `restrictDependencyHealth`, `packDeps`) | `--deps` |
| `resolveIncludeAdj` → `runArchViews` (`dsmPropagationCostCapable`) | `--arch`, its `<metrics propagation_cost=>` and violations |
| `resolveIncludeAdj` → `runStructureText` | `--report`'s `## Dependency cycles (showing N of M)` |
| `importersOfFiles` → `impactImportTier` | `--impact` `importers=`, and the MCP `impact` twin (`src/mcpverbs.h`) |
| `StaticIncludeCoupling` | `--cochange` `surprising=` |
| `applyStructuralExpansion` · `ccComputeMetrics` | `--for` structural expansion · `--export=cc.json` |
| `buildGraph` (the SameInclude tier, `forCallNarrow=true`) | call-edge narrowing |
| `buildJsImportTables` → `resolveJsImportModule` → `resolveJsNamedImportFile` → `resolvePreciseInclude` | named-import call binding, `prov="import"` |
| `markCandidateFilesIncludingDecl` | the decl-to-def proof |
| `test/includeprecise_unit.cpp`, `test/rustimport_unit.cpp` | call `resolvePreciseInclude` directly; a signature change reaches them |

### The call graph already knows about this gap

- **`jsModuleVocabulary` and `jsModuleIsForeign`** (`src/graph.h`). The comment names "a workspace
  package, a tsconfig path alias, neither of which this resolver follows". The vocabulary is every
  directory segment and file stem in the tree. A bare specifier is External only when no segment of it
  names anything in the tree. **That is exactly the split slice 1 needs:** "did not resolve, and names
  something here" versus "did not resolve, and is a package from outside".
- **`resolveJsNamedImportFile`** maps `./x.js` to `x.ts` or `x.tsx` (and `.mjs`→`.mts`, `.cjs`→`.cts`)
  for call binding, unique-or-degrade. `resolveTsImport` does not, so the call graph and the file graph
  disagree on the same directive. That is slice 2.

### Where disclosure lives today

- **`packDeps`** (`src/serialize.h`) writes the `--deps` legend. It says a target row with no edge
  behind it "is a directive that did not resolve". That is per row, and a reader cannot tell from the
  row which of its `inc t=` targets drew an edge. `includes=` counts directives and `instab=` counts
  resolved edges. No total exists anywhere.
- **The precedent to copy is `lazy_edges=`.** It is written on `<health>` only when greater than zero,
  so every corpus without a lazy directive stays byte-identical, and the legend defines it.
  `resolveStructuralIncludeAdj` computes it and `runArchViews` passes it through.
- #66 established the shape for a verb answer that hides a gap (`graph_unindexed=`).

### Config files as the crawl sees them

- JSON and YAML grammars are vendored and linked (`tree_sitter_json`, `tree_sitter_yaml` in the
  extension table in `src/ingest_crawl.h`). The map already lists the keys of a `tsconfig.base.json`
  written with a comment and trailing commas, and of `pnpm-workspace.yaml`.
- Their pathological-nesting prescans are **`jsonNestsTooDeep`** and **`yamlNestsTooDeep`**. The YAML
  one is memory safety, not performance (`prompts/help-wanted/nesting-refusals-visible.md`). Any new
  tree-sitter parse of a config file goes through them first.
- The crawl never enters `node_modules` or `dist` (`kCrawlSkipDirs`), and skips JSON over 256 KB.

---

## Reproduce the gap

Build first: `cmake -S . -B build && cmake --build build -j`, the plain dev build. **Never configure
with `-DCMAKE_BUILD_TYPE=Release`**: it compiles `DISCLOSE` out, and a gate over a degrade
path then passes blind.

This script writes one tree in two spellings that differ **only** in three specifiers. Write it outside
the checkout, and never commit it (see "Known traps").

```bash
cat > mkfix.sh <<'EOF'
#!/usr/bin/env bash
# mkfix.sh DIR [alias|relative]: an npm-workspaces tree whose app package imports through a tsconfig alias
# and a workspace package name; "relative" writes the same tree with relative specifiers instead
set -eu
D="$1"; SPELL="${2:-alias}"
rm -rf "$D"; mkdir -p "$D/packages/lib/src" "$D/packages/app/src"; cd "$D"
if [ "$SPELL" = relative ]; then AB="./b"; AA="./a"; LIB="../../lib/src/index"; else AB="@app/b"; AA="@app/a"; LIB="@acme/lib"; fi
printf '{ "name": "fixture-root", "private": true, "workspaces": ["packages/*"] }\n' > package.json
printf '{\n  // tsc accepts comments and trailing commas here\n  "compilerOptions": { "strict": true, },\n}\n' > tsconfig.base.json
printf '{ "name": "@acme/lib", "main": "src/index.ts" }\n' > packages/lib/package.json
printf 'export function helper(): number { return 1; }\n' > packages/lib/src/index.ts
printf '{ "name": "@acme/app", "dependencies": { "@acme/lib": "*" } }\n' > packages/app/package.json
printf '{\n  "extends": "../../tsconfig.base.json",\n  "compilerOptions": { "baseUrl": ".", "paths": { "@app/*": ["src/*"] } }\n}\n' > packages/app/tsconfig.json
printf "import { b } from '%s';\nimport { helper } from '%s';\nexport function a(): number { return b() + helper(); }\n" "$AB" "$LIB" > packages/app/src/a.ts
printf "import { a } from '%s';\nexport function b(): number { return typeof a === 'function' ? 1 : 0; }\n" "$AA" > packages/app/src/b.ts
printf "import { d } from './d';\nexport function c(): number { return d(); }\n" > packages/app/src/c.ts
printf "import { c } from './c';\nexport function d(): number { return typeof c === 'function' ? 1 : 0; }\n" > packages/app/src/d.ts
EOF
bash mkfix.sh "$PWD/fx-alias" alias && bash mkfix.sh "$PWD/fx-rel" relative
printf 'layer app = packages/app\nlayer lib = packages/lib\ndeny app -> lib\n' > rules.txt
( cd fx-alias && ../ripwire/build/ripwire . --no-cache --deps )      # adjust the binary path to your worktree
```

`a.ts` and `b.ts` form a genuine cycle through the alias. `c.ts` and `d.ts` form the same cycle through
relative specifiers: that is the in-tree control.

**`--deps` on the alias tree**, legend comment removed, one element per line:

```
<deps files="4" shown="4" capped="0" root=".">
<health files="10" dep_files="5" ccd="7" acd="1.4" nccd="0.67" shape="horizontal" dep_langs="cpp,py,ts,go,rs,swift,objc,js,sh,java,rb,cs,c,php,lua,ex,kt"/>
<godfiles total="2" shown="2" capped="0"><f p="packages/app/src/c.ts" afferent="1"/><f p="packages/app/src/d.ts" afferent="1"/></godfiles>
<cycles><cycle size="2" cost="4" cut="packages/app/src/c.ts -&gt; packages/app/src/d.ts" cutrefs="1"><f p="packages/app/src/d.ts"/><f p="packages/app/src/c.ts"/></cycle></cycles>
<f p="packages/app/src/c.ts" includes="1" afferent="1" instab="0.50" transitive="2"><inc t="./d"/></f>
<f p="packages/app/src/d.ts" includes="1" afferent="1" instab="0.50" transitive="2"><inc t="./c"/></f>
<f p="packages/app/src/a.ts" includes="2" afferent="0" instab="0.00" transitive="1"><inc t="@app/b"/><inc t="@acme/lib"/></f>
<f p="packages/app/src/b.ts" includes="1" afferent="0" instab="0.00" transitive="1"><inc t="@app/a"/></f>
</deps>
```

**The matched pair.** Same tree, same configs, three specifiers spelled differently:

| read | alias spelling | relative spelling |
| --- | --- | --- |
| `--deps` `<cycles>` | 1 cycle, `c`↔`d` | 2 cycles, `a`↔`b` and `c`↔`d` |
| `--deps` `<health>` | `ccd="7" acd="1.4" nccd="0.67" shape="horizontal"` | `ccd="11" acd="2.2" nccd="1.05" shape="vertical"` |
| `--deps` row for `a.ts` | `afferent="0" instab="0.00" transitive="1"` | `afferent="1" instab="0.67" transitive="3"` |
| `--impact=packages/app/src/b.ts:b` | `reaches="1" importers="0"` | `reaches="1" importers="1"`, `<f via="import" p="packages/app/src/a.ts" lazy="0"/>` |
| `--arch=rules.txt` (`deny app -> lib`) | `violations="0"`, **exit 0** | `violations="1"`, exit 2 |
| `--arch` `propagation_cost=` | `0.280` | `0.440` |
| `--report` | `## Dependency cycles (showing 1 of 1)` | `## Dependency cycles (showing 2 of 2)` |
| default map, `a`'s calls | `<c n="b"/><c n="helper"/>` (the name ladder) | `<c n="b" prov="import"/><c n="helper" prov="import"/>` |

Both trees are deterministic, and warm equals cold. The issue's own pnpm fixture (`pnpm-workspace.yaml`,
`exports` pointing into `dist/`, `"@/*": ["./src/*"]`) prints the same `--deps` answer the issue shows,
on this build.

**The runtime-extension spelling (slice 2).** Two files, `src/e.ts` importing `./f.js` and `src/f.ts`
importing `./e.js`: `--deps` lists both rows with no edge and no cycle, while the default map already
shows `<c n="f" prov="import"/>` on `e`, bound through `resolveJsNamedImportFile`.

**The multi-root reader (background).** Two roots, `app` with `paths` `{ "@lib/*": ["../lib/src/*"],
"@app/*": ["src/*"] }`: `ripwire app lib --deps` resolves `@lib/index` to `lib/src/index.ts` and leaves
`@app/b` and `@app/a` unresolved, so the aliased cycle is missed there too.

---

## What TypeScript does (checked with tsc 7.0.2 unless marked)

Model the compiler, and write down which version's behaviour you model. Verify anything you rely on
with `tsc --traceResolution` or `tsc --showConfig` before writing it into a gate.

- **Pattern match:** the `paths` key with the **longest prefix** wins (`@/sub/*` beats `@/*`).
- **Targets:** tried in order, and the **first that exists wins**, even when a later one also exists.
  When the first is missing, the second is tried.
- **`extends` replaces `paths`, it does not merge it.** A child that declares `paths` loses the base's
  entries entirely. With an `extends` array, the last config that declares `paths` wins. The issue's
  sketch says "merging"; tsc does not.
- **Inherited `paths` without `baseUrl` resolve relative to the config that declared them**, not the
  one that extends it.
- **`baseUrl` is version-dependent.** tsc 7.0.2 rejects it (`TS5102: Option 'baseUrl' has been
  removed`) and wants `./`-relative targets (`TS5090`), yet older trees depend on it. Real corpora pin
  both kinds of version.
- **Runtime extensions:** under `nodenext` and `bundler`, `./x.js` and `@/x.js` resolve to `x.ts`.
  `./g.js` does **not** resolve to `g/index.ts`.
- **Workspace packages are not a tsc rule.** tsc reaches `@acme/lib` through `node_modules` links the
  package manager creates, and an unbuilt package's `main` or `exports` often points into `dist/`. What
  slice 4 models is the package manager's linking plus a source mapping, so state that rule plainly.
- **Not checked here, check before relying on them:** `extends` naming a package, `rootDirs`, project
  `references`, `exports` condition order for `types`/`import`/`default`, and pnpm glob negation.

---

## The four slices

Each slice is its own pull request. Write its gate arms first, show them RED on a build of `origin/main`
(`../rw-base`), then write the code. Prefer new arms in an existing gate over a new gate file
(CONTRIBUTING.md §6). `test/depsprecisecheck.sh` owns the file graph's precision, and
`test/tsimportprecisecheck.sh` owns TS import resolution. Generate every fixture under the gate's own
`mktemp -d` directory with the script above.

### Slice 1: the partial graph says it is partial (good first issue)

**What.** Count, per run, the TS/JS directives that did not resolve **and** name something in this tree
(`jsModuleIsForeign` returns false). Write the count where the graph is summarized, absent at zero. Mark
every number computed over that graph as a floor while the count is non-zero: `--deps`' cycles and
`ccd`/`acd`/`nccd`, `--arch`'s `propagation_cost=` and its violations verdict, and the `--report` cycle
line.

**Where.** The counter is collected where `buildPreciseIncludeAdjWithContext` skips a `kNoFile`, through
an optional out-parameter shaped like `lazyPairsOut`, so every other caller stays byte-identical.
`resolve.h` cannot call into `graph.h`, so classify in `resolveStructuralIncludeAdj`, which already
post-processes that adjacency. Then pass it through `runArchViews`, `runStructureText`, `packDeps` and
the `--arch` metrics emit.

**Decisions for the plan.**
- The attribute names and where each sits.
- Whether other languages are counted. A count that covers only TS/JS must say so the way `dep_langs=`
  names its set, so a C++ tree never reads "0 unresolved".
- Whether each unresolved `inc t=` row gets a marker, and what that costs in bytes.
- Whether `--impact`'s `importers=` and `--cochange`'s `surprising=` carry the disclosure here or are
  named follow-ups.

**Red-first arms** (alias tree unless stated):
1. `<health>` carries a count of **3**: `@app/b`, `@app/a` and `@acme/lib`. Today it is absent: RED.
2. The cycle total is marked a floor on `--deps`, and `propagation_cost=` and the verdict are marked on
   `--arch`. The `--report` line says the total is a floor. Today all three are silent: RED.
3. **Mutation:** respell `@acme/lib` as `left-pad` in `a.ts` and re-run. The count drops to 2, because
   `left-pad` names nothing in the tree. Assert the mutation took (`grep` the file) before you trust
   the drop.
4. **Controls that must not move:** the relative tree carries no count, and its `--deps` output with the
   legend comment removed is byte-identical to `../rw-base`'s (`cmp`). A tree whose only bare import is `react` carries no count.
   Determinism, warm equals cold, and `xmllint --noout`.

### Slice 2: `./x.js` reaches `x.ts` in the file graph too (good first issue; check the linked PR first)

**What.** In `resolveTsImport`'s relative branch, probe the source spelling for a runtime extension
(`.js`→`.ts`/`.tsx`, `.mjs`→`.mts`, `.cjs`→`.cts`; say whether `.d.ts` counts), inside the existing
unique-or-degrade accumulator.
**Share the rule with `resolveJsNamedImportFile`; do not write a second copy.**

**Check the linked pull request before starting this slice.** Open PR #44 carries a hunk in
`resolveTsImport` for this mapping, and the maintainers may land it on its own as a pull request split
out of #44 that references #220 (branch `lane/win32-split-ts-runtime-ext`). Look at the pull requests
linked from #220 and at #44 first. If one of them covers the mapping, this slice shrinks to the arms
below that it does not already pin, plus any correction they force, or it is already done. Ask on #220
if you cannot tell.

**Red-first arms:**
1. `e.ts` ↔ `f.ts` through `./f.js`/`./e.js` forms a cycle, with `afferent="1"` on both. Today there is
   no edge: RED.
2. **Controls:**
   - `./f.js` when both `f.ts` and `f.js` exist gives no edge (degrade).
   - `./f.js` when only `f.js` exists gives the exact hit, unchanged.
   - `./g.js` when only `g/index.ts` exists gives **no edge**, because tsc rejects it under `nodenext`
     and `bundler`.
   - `--callers=f` is unchanged.

### Slice 3: tsconfig `paths` (medium)

**What.** For an importing TS/JS file, find the config that governs it, follow a **relative** `extends`
chain, and resolve a bare specifier through `paths` with the compiler's rules above. The result is one
file or no edge, counted by slice 1.

**Decisions for the plan.**
- **Posture.** tsc takes the first existing target, while `resolveTsImport` degrades when two extension
  probes both hit. Pick one rule for alias targets, argue it against the Step-A soundness bar in
  `src/resolve.h`, and pin it with an arm either way.
- **Which config governs a file.** The nearest `tsconfig.json` walking up is the editor's rule. tsc's
  rule is the project whose `include`/`files` admit the file. Say which you implement and what you
  disclose when they differ. Say whether `jsconfig.json` counts.
- **Which bytes you read.** The recommended answer is only config files the crawl admitted
  (`ing.files`). They are then sorted, they follow `--exclude` and gitignore, the crawl's symlink rule
  already applied to them, and nothing walks the disk or `node_modules`. An `extends` target outside
  the crawl is not followed and is disclosed.
- **How the context reaches `resolveTsImport`.** Not by building a `WsIncludeCtx` on a single root:
  `ws != nullptr` means multi-root throughout `joinNormalizeLookup`, and its rules 1 to 3 would switch
  on.
- **The call graph.** Threading aliases through `resolvePreciseInclude` also changes
  `buildJsImportTables` outcomes and `prov="import"`. Say whether that is in this PR, and measure it
  either way.
- **Multi-root.** Whether `parseTsconfigPaths` and `ConfigAlias` are extended or replaced, and the
  `pathIsUnder` "intra-root stays external" comment retired.

**Red-first arms:**
1. On the alias tree, the `a`↔`b` cycle appears, and its `<cycle>` element is byte-identical to the
   relative tree's. `a.ts` shows `afferent="1"`, `--impact=packages/app/src/b.ts:b` shows
   `importers="1"`, and the `<cycles>` total is 2. Today it is 1: RED.
2. **Compiler rules, each with a tsc-checked expectation:**
   - longest prefix;
   - first existing target wins (or your plan's rule);
   - fall-through to the second target;
   - `extends` inheritance, and replacement by a child's `paths`;
   - inherited `paths` resolve from the declaring config.
3. **jsonc:** a commented-out `// "paths": {…}` or `// "baseUrl": …` above the live key is never read.
   Today's multi-root reader fails this; your reader must not.
4. **Honest misses:**
   - an alias whose targets do not exist gives no edge and is counted;
   - an `extends` cycle (`a.json` → `b.json` → `a.json`) terminates with a disclosure and no edge;
   - a package-form `extends` is not followed and is disclosed.
5. **Stays green:** `test/multirootcheck.sh` Decision B and its bogus-target mutation;
   `test/tsimportprecisecheck.sh`, including its monotonicity arm (`ambiguous` never rises); determinism;
   warm equals cold.

### Slice 4: workspace packages (medium, after slice 3)

**What.** Enumerate workspace members from root `package.json` `workspaces` (an array, or
`{ "packages": [...] }`) and from `pnpm-workspace.yaml` `packages:`. Map each member's `name` to its
directory. Resolve a bare specifier equal to a member name to that package's source entry.

**Decisions for the plan.**
- The glob subset you support, with `*`, `**` and `!` negation stated, and how an unsupported glob is
  disclosed.
- The entry order: `exports["."]` in a documented condition order, then `types`/`main`.
- How a `dist/` entry maps back to source: through that package's tsconfig `outDir`→`rootDir`, which
  reuses slice 3's reader, or a named `src/` probe. Say which, and that it is a rule, not a guess.

**Red-first arms:**
1. On the alias tree, `a.ts` → `packages/lib/src/index.ts`, and `--arch=rules.txt` reports
   `violations="1"` and exits 2. Today it is `violations="0"`, exit 0: a vacuous pass, RED.
2. The issue's pnpm fixture: `@acme/shared` reaches `packages/shared/src/index.ts` through
   `exports` → `dist/index.js` → `outDir`/`rootDir`.
3. **Honest misses:**
   - two members declaring one `name` resolve to neither, and the miss is counted;
   - a member whose entry has no source file gives no edge, counted;
   - `@acme/shared/sub` (an `exports` subpath) is deferred and counted, not guessed;
   - a bare name that is not a member (`react`) is unchanged.
4. A negated glob excludes a member; determinism holds when members are listed out of order.

---

## Constraints (CLAUDE.md and CONTRIBUTING.md; none of these is optional)

- **Gate before code**, arms observed RED on `../rw-base`, controls that mutate real input and assert
  the mutation took (CONTRIBUTING.md §2).
- **Unique-or-degrade, never a guess.** A specifier that cannot be resolved by a stated rule stays
  unresolved, and after slice 1 it is counted. No basename matching, no "probably `src/`".
- **Honesty in attributes.** Every new attribute is absent at zero, defined in the leading legend and in
  the compact legend (`src/compactlegend.h`), and carried on the MCP twin where one exists
  (`test/legendcoveragecheck.sh`, `test/mcpattrparitycheck.sh`).
- **Determinism.** Config files are read in sorted `ing.files` order. Glob expansion and member lists
  are sorted. `HashMap` iteration order never reaches output. Two runs are byte-identical, and warm
  equals cold.
- **Containers.** No `std::map` or `std::unordered_map`: `HashMap<>` with `reserve()`, or
  `gtl::btree_map` for ordered iteration.
- **Degrade paths** use `DISCLOSE`, never `ASSUME( false )`.
- **Style** (CONTRIBUTING.md §3): Allman braces on every body, spaces inside parens, declarative tables,
  output through `rw::emitTo` or the existing writer.
- **Build discipline.** Plain dev build. Never edit while a build runs. After a branch switch or rebase,
  `cmake --build build --clean-first -j`.

---

## Acceptance criteria (per slice PR)

1. The slice's arms are RED on `../rw-base` and GREEN on your build, with every control green on both.
2. The matched pair still differs only where your slice says it should. For slices 3 and 4, the alias
   tree's `--deps`, `--arch` and `--impact` answers equal the relative tree's, modulo the `inc t=`
   spelling.
3. **Population measurement on real corpora, never a sample.**
   - At least one public pnpm or yarn monorepo that uses both shapes: run the issue's import-style
     census on it first and pin the commit.
   - For slices 3 and 4, also the issue reporter's repository if they are willing: they offered on #220.
   - Report directives moved from unresolved to resolved, new cycles, `propagation_cost=` before and
     after, and the call graph's `edges=`, `ambiguous=` and `external=` before and after.
   - List every edge that **disappeared**, read at its call site.
   - Time one large TS tree before and after. A per-file config walk belongs in a per-directory memo.
4. **This repository's own map moves, and you account for it.** Run `ripwire . --deps` on the checkout
   before and after. `test/multirootfix/cli/tsconfig.json` declares `@svc/*` → `../svc/src/*`, so on a
   single-root run `test/multirootfix/cli/src/cli_app.ts`'s `@svc/api` is expected to start
   resolving. Regenerate recorded outputs with their generators (`python3 docs/docs_commands_build.py`,
   the showcase capture), never by hand.
5. **Gates.**
   - Green: `test/depsprecisecheck.sh`, `test/tsimportprecisecheck.sh`, `test/multirootcheck.sh`,
     `test/impactimportcheck.sh`, `test/cyclecutcheck.sh`, `test/deplangscheck.sh`,
     `test/propcostcheck.sh`, `test/archmetricscheck.sh`, `test/jsverbscheck.sh`,
     `test/legendcoveragecheck.sh`, `test/mcpattrparitycheck.sh` and `test/printffmtparitycheck.sh`.
   - Then `python3 test/pargates.py . ./build/ripwire -j 6`, in the foreground.
   - ASan clean on the fixtures.
   - `./build/ripwire . --quality-delta --legend=compact` with zero unacknowledged regressions, then
     `./build/ripwire . --test-gate`.

---

## Known traps

**Never commit a TS or JSON fixture at repository scope.** The tool indexes this repository in its own
gates. A committed `tsconfig.json` or a `package.json` with `workspaces` becomes live evidence on every
repo-wide run once your reader exists. Generate fixtures under the gate's temp dir.

**`ws != nullptr` is the multi-root switch.** `joinNormalizeLookup` changes its lookup rules when it is
non-null. Carry alias and workspace context some other way.

**The existing config reader is a text scan.** It reads a commented-out key as live (measured above).
The JSON grammar is already linked. If you parse with tree-sitter, run `jsonNestsTooDeep` or
`yamlNestsTooDeep` first.

**`extends` can loop, and can leave the tree.** Bound the chain, detect a revisit, and disclose. A
package-form `extends` (`@tsconfig/node20/tsconfig.json`) lives in `node_modules`, which the crawl never
enters. Do not open it from disk.

**Never walk `node_modules`, and never follow a pnpm link back into the tree.** pnpm links
`node_modules/@acme/shared` to `packages/shared`. Resolve workspace names from the member list, not by
reading links. Two routes to one file are how a graph double-counts.

**`dist/` is not in the index.** An entry pointing there has no file to land on until your source mapping
runs. "Unbuilt package, no source found" is an honest miss, not a reason to probe further directories.

**The `--deps` listing is capped.** It shows 40 rows by default (`--pack-top-n`). A gate over a real
corpus passes `--pack-top-n=1000` as `test/depsprecisecheck.sh` does, or pages with `--limit`/`--offset`.

**Re-export barrels are a different gap.** `export * from './g'` and `export { h } from './h'` produce
no `--deps` row at all today, so the directive is never captured. That is an extraction change with a
`kParserVer` bump. Name it as a follow-up; do not fold it in.

**A sample is not a population.** List every removed or added edge on the measured corpus. If the list is
too long to read, the rule is wider than the slice.

**`__pycache__` moves the crawl.** Export `PYTHONDONTWRITEBYTECODE=1` for anything you run by hand next
to Python gates.

**A clean rebase can still be wrong.** Everything generated or pinned (`docs/COMMANDS.md`, captures, the
gate count) is re-derived after the rebase by its generator, never by picking a side of a conflict.

---

## Related issues and pull requests

- **#59 and #163 (`prompts/help-wanted/ts-literal-receivers.md`), TS/JS literal receivers.** #163 is
  claimed by @csy20, with a plan agreed on the issue. Not a duplicate: that is a call-edge false positive
  decided in `buildGraph`'s name ladder and the external veto; this is a file-graph false negative. **Shared code:** both lanes read `jsModuleIsForeign`'s
  vocabulary and change what TS/JS calls bind, and both measure `edges=`/`external=` on real corpora.
  #163 bumps `kParserVer` (extraction). Slices 1 to 4 read config at graph time and need no bump unless
  your plan changes capture. **Conflict risk:** textual, if either lane edits
  `resolveJsNamedImportFile` or `jsModuleIsForeign`. Keep this work inside `resolve.h`'s Step-A so
  `graph.h` inherits it. Whichever lands second re-measures on the other's baseline.
- **#60, `--affected` misses `node:test` arrow callbacks.** Not a duplicate. The maintainers are fixing
  it themselves: calls outside any named function go through the resolver and count as test evidence.
  **This work extends that fix to calls imported through an alias or a workspace name.** Different
  files, low conflict risk.
- **#61 (closed by #77), `--for --detail` over `--max-tokens` without disclosure.** A disclosure sibling:
  the same METHODOLOGY §9 principle 6 ("a ceiling attribute names the ceiling actually applied") that
  slice 1 applies to cycle totals. No shared code.
- **#66 (closed), a zero from an unindexed language.** The disclosure precedent the issue cites
  (`graph_unindexed=`). Borrow its shape; no shared code.
- **#67, Astro.** Not a duplicate. An Astro frontmatter import would go through the same TS resolver,
  and Astro projects commonly import through `paths` aliases, so this work raises that port's value
  later. No conflict.
- **#44 (open), native Windows support.** As its diff stands on 2026-09-16, its `resolveTsImport` hunk
  maps runtime extensions, which is slice 2's ground. It also probes `stem/index.*` for a `.js`
  specifier, a shape tsc 7.0.2 does not resolve (slice 2's third control). The maintainers are splitting
  cross-platform pieces out of #44 into their own pull requests, and this mapping may be one of them.
  Check the pull requests linked from #220 and #44 before touching that function.
- **#45 (merged), named import aliases (`import { f as g }`).** Introduced `buildJsImportTables`, the
  call-graph consumer listed above. Different meaning of "alias"; read it so the two do not get confused in the PR.

---

## What the PR description should contain

- **The slice**, and the rule it implements, stated precisely: for slice 3, the governing-config rule,
  the `extends` handling, match and target precedence, and the TypeScript version modelled.
- **Red first:** the new arms' FAIL lines on `../rw-base`, the mutation that proved each control live,
  and the PASS count after.
- **The matched pair**, before and after, as in the table above.
- **The measurement:** the corpora and commits, directives resolved, cycles, `propagation_cost=`, the
  call graph's `edges=`/`ambiguous=`/`external=`, and the full list of edges that moved.
- **This repository's own map:** what moved, and the regenerated recordings.
- **Scope, honestly:** what stays out (`exports` subpath patterns and exotic conditions, `imports` `#`
  specifiers, `rootDirs`, project `references`, package-form `extends`, Yarn PnP, bundler-only aliases
  such as Vite or webpack `resolve.alias`, re-export barrels), each as a named follow-up.
- **Links** to #220, this prompt, and whichever related lane you rebased over.

---

**Write the plan: which slice you take first, the attribute names and where they sit (slice 1), the
governing-config and precedence rules with the tsc runs that back them (slice 3), how the context reaches
`resolveTsImport` without a single-root `WsIncludeCtx`, the gate file and arms with their red runs, and the
measurement protocol. Post it as a comment on #220, then STOP for a maintainer's go-ahead.**
