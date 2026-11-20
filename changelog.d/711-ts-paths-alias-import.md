### Fixed — a TypeScript call through a tsconfig `paths` alias binds through its import (#711, reported by SStonkSS1)

A named import through a `compilerOptions.paths` alias that points inside the root (`import { f } from "@/lib/mod"` with
Next.js's default `@/*` → `./src/*`) now pins its call to the imported definition, as a relative `../lib/mod` import
already did. Before, the call binder asked only the path resolver, which leaves such a specifier unresolved, so the call
bound by its name alone and was declined (`<dc … cands="2" via="declined">`) as soon as any class had a same-named method,
dropping it from `--callers`, `--impact` and `--test-gate`, while the file edge for the same import resolved. The binder
now reads the same tsconfig resolution as the file edge (`baseUrl`, `extends` chains and directory `index.ts` targets
included). Unchanged: an alias whose target is outside the root, missing, or in another workspace root; a bare package
import; a relative import. Gate: `test/lib/tspathsalias.sh`, run by `test/tsimportprecisecheck.sh`.
