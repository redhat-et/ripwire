#!/usr/bin/env bash
# gen.sh OUT — the deterministic fixture generator for test/orientmapcheck.sh (the orient sections of the default map).
#
# One tree, built so every rule of the registered grouping is exercised and every comparison the oracle makes is
# decided by a margin far wider than the map's 4-dp k= rounding (orientmapcheck refuses the fixture otherwise):
#   - core mass sits under src/pkg/ (>= 2/3 at the root, at src/ and not under any child of src/pkg/), so the grouping
#     root G descends root -> src/ -> src/pkg/;
#   - sixteen child directories of G with 1..8 files each, every file a distinct number of functions inside its group;
#   - files directly in G grouped by prefix: kebab (cmd-find), snake (cmd_queue), a leading underscore (_cmd_run), a
#     prefix equal to a child directory (cmd -> cmd/), CamelCase lowercased (Server, server_utils), a bare stem (io);
#   - core files outside G: scripts/ (a top-level directory), setup_tools.py (the root, by prefix), src/legacy_shim.py
#     (inside src/ but outside G);
#   - files that are NOT core: tests/, a fixtures/ directory, a numbered migration, a static/ (demo/generated)
#     directory, a markdown file, a file whose only code is module scope;
#   - vendored/compat directories (compat/, vendor/), which O3 must demote;
#   - entry-point evidence: package.json bin (one whose build output has a source twin, one that has none), "main",
#     the "." export and one subpath export; a Python `main` definition, and a near-miss `main_loop`.
# The output is a pure function of OUT: no dates, no randomness, no environment reads.
set -eu
out="${1:?usage: gen.sh OUT}"
[ -e "$out" ] && { echo "gen.sh: $out exists" >&2; exit 2; }
mkdir -p "$out"
python3 - "$out" <<'PY'
import os, sys
out = sys.argv[1]

def w(rel, text):
    p = os.path.join(out, rel)
    os.makedirs(os.path.dirname(p) or out, exist_ok=True)
    with open(p, "w") as fh:
        fh.write(text)

def pyfile(rel, stem, nfn, calls=()):
    # nfn independent functions of one name shape (equal priors, so a file's mass is ~ nfn x one function's), the first
    # optionally calling other files' functions
    lines = []
    for j in range(nfn):
        lines.append("def %s_fn_%02d(value):" % (stem, j))
        for c in calls if j == 0 else ():
            lines.append("    value = %s(value)" % c)
        lines += ["    return value + %d" % j, "", ""]
    w(rel, "\n".join(lines).rstrip() + "\n")

DIRS = ["handlers", "routing", "storage", "render", "network", "codec", "scheduler", "auth",
        "metrics", "plugins", "session", "config", "events", "cache", "parsers", "widgets"]
SIZES = [8, 7, 7, 6, 6, 5, 5, 4, 4, 3, 3, 3, 2, 2, 1, 1]
BASES = [3, 4, 3, 4, 3, 4, 3, 4, 3, 4, 3, 2, 3, 2, 3, 1]
# file i of a group has BASE + (SIZE-1-i) functions: distinct inside the group, and the group totals
# (52 49 42 39 33 30 25 22 18 15 12 9 7 5 3 1) are distinct from each other and from every other group's below
for d, (name, size, base) in enumerate(zip(DIRS, SIZES, BASES)):
    for i in range(size):
        stem = "%s_%s_component_%02d" % (name, "request_lifecycle" if d % 2 else "service_registry", i)
        pyfile("src/pkg/%s/%s.py" % (name, stem), stem, base + size - 1 - i, ["xmem_alloc"] if i == 0 else ())

# prefix groups directly in G: cmd (2+4+6+8 = 20, joins cmd/), server (7+3 = 10), io (6)
pyfile("src/pkg/cmd-find.py", "cmd_find", 6)
pyfile("src/pkg/cmd_queue.py", "cmd_queue", 4)
pyfile("src/pkg/_cmd_run.py", "cmd_run", 2)
pyfile("src/pkg/cmd/cmd_dispatch_table.py", "cmd_dispatch", 8)
pyfile("src/pkg/Server.py", "server_core", 7)
pyfile("src/pkg/server_utils.py", "server_utils", 3)
pyfile("src/pkg/io.py", "io_layer", 6)
# cli (4 functions): `main` is entry-point evidence; `main_loop` is the near miss that is not
w("src/pkg/cli_main.py",
  "def main_loop(argv):\n    return argv\n\n\ndef main():\n    return main_loop([])\n\n\n"
  "def parse_cli_flags(argv):\n    return list(argv)\n\n\ndef cli_usage_text():\n    return 'usage'\n")
# TypeScript sources behind package.json's build output (dist/ is never written: only the manifest names it)
w("src/pkg/tool.ts", "export function runTool(args: string[]): number {\n  return args.length;\n}\n\nexport function toolHelp(): string {\n  return 'help';\n}\n")
w("src/pkg/index.ts", "".join("export function appPart%d(x: number): number {\n  return x + %d;\n}\n\n" % (j, j) for j in range(8)))
w("src/pkg/sub.ts", "".join("export function subPart%d(x: number): number {\n  return x + %d;\n}\n\n" % (j, j) for j in range(11)))
# the utility sink every directory's first module calls
w("src/pkg/core/xmem.py", "def xmem_alloc(value):\n    return value\n\n\ndef xmem_free(value):\n    return value\n")
# vendored / compat (O3 demotes these by the registered generic list)
pyfile("src/pkg/compat/queue_compat.py", "queue_compat", 17)
pyfile("src/pkg/vendor/thirdlib.py", "thirdlib", 4)
# core files outside G
pyfile("scripts/release_build.py", "release_build", 13)
pyfile("setup_tools.py", "setup_tools", 14)
pyfile("src/legacy_shim.py", "legacy_shim", 27)
# NOT core
pyfile("tests/test_handlers.py", "test_handlers", 2)
pyfile("src/pkg/fixtures/sample_data.py", "sample_data", 2)
pyfile("src/pkg/migrations/0001_initial.py", "initial_migration", 2)
pyfile("src/pkg/static/bundle.py", "static_bundle", 2)
w("src/pkg/bootstrap.py", "import os\n\nos.getcwd()\n")
w("src/pkg/README.md", "# pkg\n\nThe package.\n\n## Layout\n\nDirectories by concern.\n")
w("docs/guide.md", "# Guide\n\n## Usage\n\nRun the tool.\n")
w("package.json", """{
  "name": "orientfix",
  "version": "1.0.0",
  "bin": { "orientfix": "dist/tool.js", "orientfix-gone": "dist/nosuchstem.js" },
  "main": "dist/index.js",
  "exports": { ".": "./dist/index.js", "./sub": "./dist/sub.js" }
}
""")
PY
