#!/usr/bin/env bash
# gen_truth.sh OUT — the second fixture of test/orientmapcheck.sh: TRUTHFULNESS of the orient sections (O-narrow v3,
# PREREG_orient_narrow_v3; the blind O2 grading's two false-row classes on hono-01, plus the memory-guard partial ingest).
# Every positive sits next to the near miss the code could plausibly mis-handle:
#   (E) ENTRY ROWS name only an exported/public program or package entry:
#       - the package entry module src/index.ts has hono's shape: imports and re-exports only, nothing declared — a
#         source file with no code symbol, named by its module scope <file-scope> at line 1;
#       - a heavier same-stem decoy src/jsx/hooks/index.ts (non-exported alias first) must never be the entry module that
#         dist/index.js / dist/cjs/index.js name (a build path maps to a same-stem source one source root away; a deeper
#         one only when its stem is unique);
#       - a bin module src/options.ts opens with a NON-EXPORTED type alias, a private helper and an exported VERSION
#         constant; its first exported function, class or type is `export interface Options` (the row's n=);
#       - `export { b }` where b is not the first declaration names b; `export default make` names make; CommonJS
#         `exports.create = create` names create;
#       - an export of a CALL RESULT exports the result, not the callee: `module.exports = make({…})`,
#         `export default build({…})` and `exports.api = factory(real)` read <file-scope>; the plain `module.exports = make`
#         names make (webpack lib/index.js `module.exports = mergeExports(fn, {…})`, final review F1);
#       - a bin script that exports nothing (src/cli.ts: a constant, then a private helper) is named by its module scope;
#       - CommonJS: lib/server.js exports `server` by `module.exports = server` after a VERSION constant and a private
#         instanceof helper; lib/application.js exports `module.exports = class Application` after a private helper;
#       - pyproject scripts: one names a function the module only imports (no definition: module scope, never the private
#         helper above it), one names a function the module defines (that function);
#       - `main`: a module-level Python function, a Java `static void main` and a Go `func main` in `package main` are
#         program entries; a Python method named main on a helper class and a Go `func main` in a library package are not.
#   (G) GROUP LABELS are true of every member: src/request.ts and src/request-utils.ts sit BESIDE src/request/ and join
#       its group, so the group is labelled `request` (a name prefix), never `request/`; src/router/router.ts sits INSIDE
#       src/router/ (nested X/X.ts, no sibling) and keeps `router/`; CamelCase src/Stats.ts beside src/stats/ is `stats`;
#       outside g=, tools.py beside tools/ is `/tools`, while
#       scripts/ alone stays `/scripts/`.
#   (M) the memory-guard partial ingest (RIPWIRE_TEST_MEMGUARD=parse:N) is driven by the gate on this tree.
# The output is a pure function of OUT: no dates, no randomness, no environment reads.
set -eu
out="${1:?usage: gen_truth.sh OUT}"
[ -e "$out" ] && { echo "gen_truth.sh: $out exists" >&2; exit 2; }
mkdir -p "$out"
python3 - "$out" <<'PY'
import os, sys
out = sys.argv[1]

def w(rel, text):
    p = os.path.join(out, rel)
    os.makedirs(os.path.dirname(p) or out, exist_ok=True)
    with open(p, "w") as fh:
        fh.write(text)

def ts_fns(prefix, n):
    return "".join("export function %s_%02d(x: number): number {\n  return x + %d;\n}\n\n" % (prefix, i, i) for i in range(n))

def py_fns(prefix, n):
    return "".join("def %s_%02d(value):\n    return value\n\n\n" % (prefix, i) for i in range(n))

# (E) the package entry module in hono's shape: nothing declared, imports and re-exports only
w("src/index.ts", "import { createApp } from './options'\nimport type { Options } from './options'\nexport type { Options }\n"
                  "export { Context } from './context'\nexport { createApp }\n")
w("src/context.ts", "export class Context {\n  value(): number {\n    return 1;\n  }\n}\n" + "".join(
    "export function context_value_store_access_%02d(x: number): number {\n  return x + %d;\n}\n\n" % (i, i) for i in range(5)))
# a bin module: non-exported alias, private helper, exported VERSION constant, then the exported type
w("src/options.ts", 'type Internal = number;\nfunction helperOnly(x: Internal): Internal {\n  return x;\n}\nexport const VERSION = "1.0.0";\n'
                  'export interface Options {\n  depth: number;\n}\nexport function createApp(o: Options): number {\n  return helperOnly(o.depth);\n}\n')
# the heavier same-stem decoy, three directories below the source root
w("src/jsx/hooks/index.ts", "type UpdateStateFunction<T> = (v: T) => T;\n" + ts_fns("hook_state_dispatcher_entry", 14))
w("src/jsx/render.ts", ts_fns("jsx_render_component_tree", 6))
# a bin script that exports nothing
w("src/cli.ts", 'const VERSION_TAG = "2.0.0";\nfunction _parseArgs(argv: string[]): string[] {\n  return argv;\n}\n_parseArgs([VERSION_TAG]);\n')
# (G) a file beside its namesake directory (and a kebab sibling); a nested X/X.ts with no sibling
w("src/request.ts", ts_fns("request_object_accessor", 6))
w("src/request-utils.ts", ts_fns("request_utility_helper", 3))
w("src/request/body.ts", ts_fns("request_body_parser_stage", 5))
w("src/request/headers.ts", ts_fns("request_header_reader_stage", 4))
w("src/router/router.ts", ts_fns("router_dispatch_table_lookup", 6))
w("src/router/trie.ts", ts_fns("router_trie_node_insert", 5))
w("src/Stats.ts", ts_fns("stats_summary_printer", 4))
w("src/stats/collect.ts", ts_fns("stats_collect_sample", 4))
# the three remaining export syntaxes: an export clause naming a later declaration, a default export, CommonJS exports.X
w("src/exportlist.ts", "function firstLocal(x: number): number {\n  return x;\n}\nfunction b(x: number): number {\n"
                       "  return firstLocal(x);\n}\nexport { b }\n")
w("src/defexp.ts", "function _internal(x: number): number {\n  return x;\n}\nfunction make(x: number): number {\n"
                   "  return _internal(x);\n}\nexport default make\n")
w("lib/cjsx.js", "'use strict'\nfunction helperA (x) {\n  return x\n}\nfunction create (x) {\n  return helperA(x)\n}\n"
                 "exports.create = create\n")
# exports of a call result (the callee is not what the module exports) vs the plain identifier
w("lib/callres.js", "'use strict'\nfunction make (o) {\n  return o\n}\nmodule.exports = make({ a: 1 })\n")
w("src/defcall.ts", "function build(o: object): object {\n  return o;\n}\nexport default build({ x: 1 });\n")
w("lib/factory.js", "'use strict'\nfunction factory (f) {\n  return f\n}\nfunction real () {\n  return 1\n}\nexports.api = factory(real)\n")
w("lib/plainmake.js", "'use strict'\nfunction make (x) {\n  return x\n}\nmodule.exports = make\n")
# Go: `func main` is a program entry only in package main
w("src/gox/helper.go", "package gox\n\nfunc main() {\n}\n\nfunc Helper() int {\n\treturn 1\n}\n")
w("cmd/tool/main.go", "package main\n\nfunc main() {\n}\n")
# pyproject scripts and `main` evidence (Python + Java), and the method named main that is not an entry
w("src/tpkg/__init__.py", "")
w("src/tpkg/core.py", "def run(argv):\n    return argv\n\n\n" + py_fns("core_engine_step_runner", 3))
w("src/tpkg/cli.py", "from tpkg.core import run\n\n\ndef _helper(value):\n    return run(value)\n\n\n" + py_fns("cli_option_table_entry", 2))
w("src/tpkg/serve.py", "def _bind_port(value):\n    return value\n\n\ndef serve(argv):\n    return _bind_port(argv)\n")
w("src/tpkg/launch.py", "def _prepare(value):\n    return value\n\n\ndef main():\n    return _prepare(1)\n")
w("src/tpkg/worker.py", "class Worker:\n    def main(self):\n        return 1\n\n    def step(self):\n        return self.main()\n")
w("src/App.java", "public class App {\n    private static int helper() {\n        return 1;\n    }\n\n"
                  "    public static void main(String[] args) {\n        helper();\n    }\n}\n")
# CommonJS entries (bins into lib/, which is indexed source here: an indexed manifest path names itself)
w("lib/server.js", "'use strict'\nconst VERSION = '5.0.0'\nfunction isHttpErrorLike (e) {\n  return e instanceof Error\n}\n"
                   "function server (opts) {\n  return isHttpErrorLike(opts) ? VERSION : opts\n}\nmodule.exports = server\n"
                   "module.exports.default = server\n")
w("lib/application.js", "'use strict'\nfunction isPlainHelper (x) {\n  return x\n}\nmodule.exports = class Application {\n"
                        "  listen () {\n    return isPlainHelper(1)\n  }\n}\n")
# outside g=: a root file beside its namesake top-level directory, and a directory alone
w("tools.py", "def tools_entry_table(value):\n    return value\n")
w("tools/gen.py", "def tools_generate_table(value):\n    return value\n")
w("scripts/build.py", "def scripts_build_step(value):\n    return value\n")
w("package.json", """{
  "name": "orienttruth",
  "version": "1.0.0",
  "bin": { "tcli": "dist/cli.js", "tserve": "lib/server.js", "tapp": "lib/application.js", "topts": "dist/options.js",
           "texl": "dist/exportlist.js", "tdef": "dist/defexp.js", "tcjsx": "lib/cjsx.js",
           "tcall": "lib/callres.js", "tdefcall": "dist/defcall.js", "tfactory": "lib/factory.js", "tplain": "lib/plainmake.js" },
  "main": "dist/cjs/index.js",
  "exports": { ".": { "types": "./dist/types/index.d.ts", "import": "./dist/index.js", "require": "./dist/cjs/index.js" } }
}
""")
w("pyproject.toml", '[project]\nname = "tpkg"\n\n[project.scripts]\ntpy = "tpkg.cli:run"\ntserve = "tpkg.serve:serve"\n')
PY
