#!/usr/bin/env bash
# gen.sh OUT — the deterministic fixture generator for test/orientmapcheck.sh (the orient sections of the default map).
#
# One tree, built so every rule of the registered grouping is exercised and every comparison the oracle makes is decided by
# a margin far wider than the map's 4-dp k= rounding (orientmapcheck refuses the fixture otherwise). Masses are set with
# few rows: every function is uncalled and its prior weight is either 1.0 (a short plain name) or 1.7 (a specific name,
# >= 8 characters and >= 2 words: priorwt), so a file of P plain and S specific functions weighs P + 1.7 S units.
#   - core mass sits under src/pkg/, so the grouping root G descends root -> src/ -> src/pkg/;
#   - twelve child directories of G with 1..8 files (distinct member weights inside each group);
#   - files directly in G grouped by prefix: kebab (job-scan), snake (job_pool), a leading underscore (_job_run), a prefix
#     equal to a child directory (job joins job/, labelled `job`: a label is true of every member), CamelCase lowercased (Gateway, gateway_utils), a bare stem (wire);
#   - two EXACT ties, broken by the registered key: members tie-a.py / tie/b.py of group tie (path order puts tie-a.py
#     first; a directory-first crawl lists tie/ first), and groups kappa (Kappa.py) / beta/ (label order puts beta/ first;
#     the crawl lists Kappa.py first);
#   - core files outside G: scripts/ (a top-level directory), setup_tools.py (the root, by prefix), src/legacy_shim.py;
#   - NOT core: tests/, a fixtures/ directory, a numbered migration, a static/ (demo/generated) directory, markdown, a file
#     whose only code is module scope;
#   - O3: vendored/compat directories (compat/, vendor/) and one utility sink (util/blockpool.py: called from twelve files,
#     calling nothing);
#   - entry-point evidence: four package.json bins with a source twin (one flattened: dist/flat.js <- src/pkg/flat.ts; plus
#     one with none and one naming an indexed tests/ file), two
#     `main` definitions in core files (plus `main` in a test, a fixture and a vendored file, and the near-miss
#     `main_loop`), "main" and the "." export (one module), and one subpath export.
# The output is a pure function of OUT: no dates, no randomness, no environment reads.
set -eu
out="${1:?usage: gen.sh OUT}"
[ -e "$out" ] && { echo "gen.sh: $out exists" >&2; exit 2; }
mkdir -p "$out"
python3 - "$out" <<'PY'
import os, sys
out = sys.argv[1]
serial = [0]

def w(rel, text):
    p = os.path.join(out, rel)
    os.makedirs(os.path.dirname(p) or out, exist_ok=True)
    with open(p, "w") as fh:
        fh.write(text)

def names(weight):
    """unique function names whose prior weights sum to `weight`: P plain (1.0) + S specific (1.7), fewest rows"""
    best = None
    for s in range(0, 8):
        p = round(weight - 1.7 * s, 1)
        if p >= 0 and abs(p - round(p)) < 1e-9 and (best is None or p + s < sum(best)):
            best = (int(round(p)), s)
    plain, spec = best
    got = []
    for _ in range(plain):
        serial[0] += 1
        got.append("q%04d" % serial[0])                  # 5 characters: no specific boost
    for _ in range(spec):
        serial[0] += 1
        got.append("spec_unit_%04d" % serial[0])         # >= 8 characters, 3 words: x1.7
    return got

def py(rel, weight, extra=(), calls=()):
    lines = []
    for i, n in enumerate(list(extra) + names(weight - 0)):
        lines.append("def %s(value):" % n)
        for c in calls if i == 0 else ():
            lines.append("    value = %s(value)" % c)
        lines += ["    return value", "", ""]
    w(rel, "\n".join(lines).rstrip() + "\n")

def ts(rel, weight):
    w(rel, "".join("export function %s(x: number): number {\n  return x;\n}\n\n" % n for n in names(weight)))

GROUPS = [("handlers", [7.0, 6.0, 5.0, 4.0, 3.0, 2.0, 1.7, 1.0]), ("routing", [7.4, 6.4, 5.4, 4.4, 3.4, 2.7, 1.0]),
          ("storage", [6.7, 5.7, 4.7, 3.7, 2.7, 1.7]), ("render", [8.0, 6.0, 4.0, 2.0, 1.0]), ("network", [7.7, 5.7, 3.7, 1.7]),
          ("codec", [6.8, 4.7, 2.7, 1.0]), ("scheduler", [5.4, 3.4, 1.7]), ("auth", [5.1, 3.0, 1.0]), ("metrics", [4.7, 2.7]),
          ("plugins", [4.0, 2.0]), ("session", [5.0]), ("config", [3.7])]
for d, (name, weights) in enumerate(GROUPS):
    for i, wt in enumerate(weights):
        rel = "src/pkg/%s/%s_%s_component_implementation_%02d.py" % (name, name, "request_lifecycle" if d % 2 else "service_registry", i)
        py(rel, wt, calls=["pool_take"] if i == 0 else ())

# prefix groups directly in G: job (6.4 + 4.4 + 2.0 + 1.0, joins job/), gateway (3.7 + 1.7), wire (4.7)
py("src/pkg/job/job_dispatch_table.py", 6.4)
py("src/pkg/job-scan.py", 4.4)
py("src/pkg/job_pool.py", 2.0)
py("src/pkg/_job_run.py", 1.0)
py("src/pkg/Gateway.py", 3.7)
py("src/pkg/gateway_utils.py", 1.7)
py("src/pkg/wire.py", 4.7)
# the two exact ties: identical structure, so identical float mass
py("src/pkg/tie-a.py", 3.4)
py("src/pkg/tie/b.py", 3.4)
py("src/pkg/Kappa.py", 3.0)
py("src/pkg/beta/x.py", 3.0)
# launcher (4.4 = main 1.0 + main_loop 1.7 + parse_cli_flags 1.7): `main` is evidence; `main_loop` is the near miss
w("src/pkg/launcher.py", "def main_loop(argv):\n    return argv\n\n\ndef main():\n    return main_loop([])\n\n\n"
                         "def parse_cli_flags(argv):\n    return list(argv)\n")
# TypeScript sources behind package.json's build output (dist/ is never written: only the manifest names it). A build path
# maps to the same-stem source one source root away (dist/pkg/tool.js <- src/pkg/tool.ts, tsc's rootDir=src layout)
ts("src/pkg/sync.ts", 2.7)
ts("src/pkg/tool.ts", 1.7)
ts("src/pkg/admin.ts", 1.0)
ts("src/pkg/index.ts", 2.0)
ts("src/pkg/sub.ts", 3.4)
# a flattened bundler bin (tsup/esbuild: dist/flat.js <- src/pkg/flat.ts, two components deeper): mapped because its stem
# is unique among the core sources (an ambiguous stem maps only one source root away — the hono-01 index.ts defect)
ts("src/pkg/flat.ts", 6.8)
# the utility sink (O3): every directory's first module calls it; it calls nothing
w("src/pkg/util/blockpool.py", "def pool_take(value):\n    return value\n\n\ndef pool_give(value):\n    return value\n")
# vendored / compat (O3 demotes these by the registered generic list); `main` in a vendored file is not evidence
py("src/pkg/compat/list_shim.py", 4.0)
py("src/pkg/vendor/thirdlib.py", 2.0, extra=["main"])
# core files outside G (release_build carries the second `main`: 1.0 + 3.0 = 4.0)
py("scripts/release_build.py", 3.0, extra=["main"])
py("setup_tools.py", 5.7)
py("src/legacy_shim.py", 6.4)
# NOT core (a `main` in a test and in a fixture is not evidence)
py("tests/test_handlers.py", 2.0, extra=["main"])
w("tests/test_runner.ts", "export function runAll(): number {\n  return 0;\n}\n")
w("tests/run_all.js", "function runAllTests () {\n  return 0\n}\nmodule.exports = runAllTests\n")   # an INDEXED bin target: only the tests/ tier drops it
py("src/pkg/fixtures/sample_data.py", 2.0, extra=["main"])
py("src/pkg/migrations/0001_initial.py", 2.0)
py("src/pkg/static/bundle.py", 2.0)
w("src/pkg/bootstrap.py", "import os\n\nos.getcwd()\n")
w("src/pkg/README.md", "# pkg\n\nThe package.\n\n## Layout\n\nDirectories by concern.\n")
w("docs/guide.md", "# Guide\n\n## Usage\n\nRun the tool.\n")
w("package.json", """{
  "name": "orientfix",
  "version": "1.0.0",
  "bin": { "orientfix": "dist/pkg/tool.js", "orientfix-admin": "dist/pkg/admin.js", "orientfix-sync": "dist/pkg/sync.js",
           "orientfix-gone": "dist/pkg/nosuchstem.js", "orientfix-test": "tests/run_all.js", "orientfix-flat": "dist/flat.js" },
  "main": "dist/pkg/index.js",
  "exports": { ".": "./dist/pkg/index.js", "./sub": "./dist/pkg/sub.js" }
}
""")
PY
