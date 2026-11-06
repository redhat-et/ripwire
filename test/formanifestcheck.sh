#!/usr/bin/env bash
# formanifestcheck.sh — MANIFEST-ROW (src/formanifest.h): a --for task that names a package, dependency, script, binary, build target
# or cargo feature a manifest defines carries <manifest_rows>, the manifests' defining lines, just before </ctx>; every other task is
# unchanged.
#
# ARMS (readers, one fixture per manifest format, created at runtime)
#   (n1) package.json: the sub-package the task names ranks first (its name and peer-dependency lines), the root manifest that only
#        lists the same libraries as dev-dependencies after it; matched= holds the task words as spelled
#   (n2) a script fires only when the task says script / npm: `lint` alone is silent, "the lint npm script" prints kind="script"
#   (n3) a generic name (`core`) never fires; (n4) the repo's own name never fires, with or without a kind word ("the acme package"), and adds its row only beside a real anchor
#   (n5) the main row needs a main / entry cue: "brokers" prints no kind="main" row, "the main entry of brokers" does
#   (c1) Cargo.toml: a [features] key fires; <feature_touch> lists the file naming at least half of the features (default and
#        _-private ones out), not one naming a single feature; (c2) a [dependencies.X] header is a dep row on the header line;
#   (c3) a [[bin]] name (`ferris-cli`, a hyphenated task word folded); (c4) a task naming only the crate itself is silent
#   (p1) pyproject.toml [project] name and an optional-dependencies extra; (s1) setup.cfg [metadata] name (an UNINDEXED file, found
#        in an indexed directory); (g1) go.mod module, a require-block dep by its dotted name (`nats.go`), an `// indirect` one silent;
#   (k1) CMakeLists.txt add_executable / add_library (any case), a ${VAR} name not read
# ARMS (1b entry points: pyproject / setup.cfg, through epmanifest.h's readers)
#   (e1) an in-repo example's [project.entry-points.<host>] entry fires on a plugin task even though the group is the repo's own name:
#        kind="entry-point" group="hostlib", the example's manifest first; (e2) the same names without a plugin / entry-point /
#        extension word are silent; (e3) a setup.cfg [options.entry_points] group matches by a dot segment (`hostlib.ext`);
#   (e4) a [project.scripts] key is an installed command: kind="bin", no group=
# ARMS (caps, dialects, placement)
#   (cap1) four manifests naming the word: files="4" shown="3" capped="1"; (cap2) four matching lines: rows="4" shown="3" capped="1"
#   (j1) --json carries no block; (b1) a token budget holds it (held="budget", no rows); (x1) MCP `for`: the same element bytes
#   (l1) --legend=full prints the long legend, the default the short one, the rows the same
#   (a1) the answer is well-formed XML, the block closes right before </ctx>, its legend defines every attribute it prints
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "formanifestcheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
F="$TMP/fx"

# ── fixtures ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# npm: the repo dir is named acme and so is the root package
mkdir -p "$F/acme/packages/brokers" "$F/acme/packages/core" "$F/acme/src"
for p in alpha beta gamma delta; do
    mkdir -p "$F/acme/plugins/$p"
    printf '{\n  "name": "@acme/plugin-%s",\n  "peerDependencies": {\n    "kafkajs": "*"\n  }\n}\n' "$p" >"$F/acme/plugins/$p/package.json"
    printf 'export const %s = 1;\n' "$p" >"$F/acme/plugins/$p/index.js"
done
cat >"$F/acme/package.json" <<'J'
{
  "name": "acme",
  "scripts": {
    "test": "jest",
    "lint": "eslint ."
  },
  "devDependencies": {
    "mqtt": "5.0.0",
    "nats": "2.0.0"
  }
}
J
cat >"$F/acme/packages/brokers/package.json" <<'J'
{
  "name": "@acme/brokers",
  "main": "./index.js",
  "peerDependencies": {
    "@nats-io/transport-node": "*",
    "kafkajs": "*",
    "mqtt": "*"
  },
  "peerDependenciesMeta": {
    "mqtt": {
      "optional": true
    }
  }
}
J
printf '{\n  "name": "@acme/core"\n}\n' >"$F/acme/packages/core/package.json"
printf 'export function connect() { return 1; }\n' >"$F/acme/packages/brokers/index.js"
printf 'export function boot() { return 2; }\n' >"$F/acme/packages/core/index.js"
printf 'export function main() { return 3; }\n' >"$F/acme/src/app.js"

# Cargo: the repo dir and the crate are both ferris
mkdir -p "$F/ferris/ferris/src"
printf '[workspace]\nmembers = ["ferris"]\n' >"$F/ferris/Cargo.toml"
cat >"$F/ferris/ferris/Cargo.toml" <<'T'
[package]
name = "ferris"
version = "0.1.0"

[[bin]]
name = "ferris-cli"
path = "src/main.rs"

[features]
default = [
    "json",
]
json = ["dep:serde_json"]
multipart = ["dep:multer"]
form = []
tokio = []
__private = []

[dependencies]
serde_json = { version = "1", optional = true }
multer = { version = "2", optional = true }

[dependencies.tokio]
version = "1"
T
cat >"$F/ferris/ferris/src/lib.rs" <<'R'
//! Name | Description
//! `json` | JSON bodies
//! `multipart` | multipart forms
//! `form` | url-encoded forms
//! `tokio` | the runtime
pub fn route() -> u32 { 1 }
R
printf '// json helpers\npub fn parse() -> u32 { 2 }\n' >"$F/ferris/ferris/src/other.rs"
printf 'fn main() { }\n' >"$F/ferris/ferris/src/main.rs"

# Python: pyproject at the root, setup.cfg (not an indexed file) in a sub-package
mkdir -p "$F/pyrepo/widgetkit" "$F/pyrepo/sub"
cat >"$F/pyrepo/pyproject.toml" <<'T'
[project]
name = "widgetkit"
description = """
name = "notakey"
"""

[project.optional-dependencies]
msgpack = ["msgpack>=1"]
yaml = ["pyyaml"]
T
printf 'def make():\n    return 1\n' >"$F/pyrepo/widgetkit/__init__.py"
printf '[metadata]\nname = gadgets\n\n[options.extras_require]\nfast =\n    ujson\n' >"$F/pyrepo/sub/setup.cfg"
printf 'def gadget():\n    return 2\n' >"$F/pyrepo/sub/gadgets.py"

# Python entry points: the repo dir and its package are both hostlib; an example plugin package under tests/
mkdir -p "$F/hostlib/hostlib" "$F/hostlib/tests/plugin" "$F/hostlib/contrib"
cat >"$F/hostlib/pyproject.toml" <<'T'
[project]
name = "hostlib"

[project.scripts]
hostctl = "hostlib.cli:main"
T
printf 'def main():\n    return 0\n' >"$F/hostlib/hostlib/cli.py"
cat >"$F/hostlib/tests/plugin/pyproject.toml" <<'T'
[project]
name = "example_plugin"

[project.entry-points.hostlib]
my_plugin = "example_plugin:plugin"
T
printf 'plugin = object()\n' >"$F/hostlib/tests/plugin/example_plugin.py"
printf '[metadata]\nname = fancy\n\n[options.entry_points]\nhostlib.ext =\n    fancy = fancy.mod:Fancy\n' >"$F/hostlib/contrib/setup.cfg"
printf 'class Fancy:\n    pass\n' >"$F/hostlib/contrib/mod.py"

# Go
mkdir -p "$F/gorepo"
cat >"$F/gorepo/go.mod" <<'G'
module example.com/acme/gizmo/v2

go 1.22

require (
	github.com/nats-io/nats.go v1.31.0
	golang.org/x/sync v0.5.0 // indirect
)
G
printf 'package main\n\nfunc main() {}\n' >"$F/gorepo/main.go"

# CMake
mkdir -p "$F/cmrepo/src"
cat >"$F/cmrepo/CMakeLists.txt" <<'C'
cmake_minimum_required(VERSION 3.20)
project(cmdemo C)
add_executable(meterd src/main.c)
ADD_LIBRARY(meterlib STATIC src/lib.c)
add_library(${PROJECT_NAME}_extra src/lib.c)
C
printf 'int main(void) { return 0; }\n' >"$F/cmrepo/src/main.c"
printf 'int lib(void) { return 1; }\n' >"$F/cmrepo/src/lib.c"

# Noise shapes (review R1): a common word of a task matches a third-party dependency, a feature or a bin with a generic name, in a
# manifest that is not about what the task asks. `shop`: a crate feature `handler`, a fuzz bin `path`, an npm dependency `http-server`,
# a benchmarks/ package depending on `koa-router`, and a real package depending on `find-my-way`.
mkdir -p "$F/shop/crates/shop-extra/src" "$F/shop/fuzz" "$F/shop/benchmarks/routers" "$F/shop/packages/web"
printf '[workspace]\nmembers = ["crates/shop-extra"]\n' >"$F/shop/Cargo.toml"
printf '[package]\nname = "shop-extra"\n\n[features]\nhandler = ["dep:shop"]\nmacros = []\n' >"$F/shop/crates/shop-extra/Cargo.toml"
printf 'pub fn extra() -> u32 { 1 }\n' >"$F/shop/crates/shop-extra/src/lib.rs"
printf '[package]\nname = "shop-fuzz"\n\n[[bin]]\nname = "path"\npath = "fuzz_targets/path.rs"\n' >"$F/shop/fuzz/Cargo.toml"
printf '{\n  "name": "shop-test-page",\n  "devDependencies": {\n    "http-server": "14.0.0"\n  }\n}\n' >"$F/shop/packages/web/package.json"
printf 'export const page = 1;\n' >"$F/shop/packages/web/index.js"
printf '{\n  "name": "bench-routers",\n  "dependencies": {\n    "koa-router": "12.0.0"\n  }\n}\n' >"$F/shop/benchmarks/routers/package.json"
mkdir -p "$F/shop/packages/router"
printf '{\n  "name": "shop-router",\n  "dependencies": {\n    "find-my-way": "8.0.0"\n  }\n}\n' >"$F/shop/packages/router/package.json"
printf 'export const route = 1;\n' >"$F/shop/packages/router/index.js"

# Parser shapes (review F3): a Poetry multi-line constraint array, Poetry groups and the interpreter key; a Cargo feature array with a
# trailing comment that holds `=`; CMake bracket comments, IMPORTED / ALIAS targets and a call that spans lines.
mkdir -p "$F/poet/poet" "$F/cg/src" "$F/cmk/src"
cat >"$F/poet/pyproject.toml" <<'T'
[tool.poetry]
name = "poetdemo"

[tool.poetry.dependencies]
python = "^3.9"
numpy = [
    {version = "^1.24", python = ">=3.9"},
    {version = "^1.21", python = "<3.9"},
]
requests = "^2"

[tool.poetry.group.dev.dependencies]
pytest-cov = "^4"
T
printf 'def run():\n    return 1\n' >"$F/poet/poet/__init__.py"
cat >"$F/cg/Cargo.toml" <<'T'
[package]
name = "cgdemo"

[features]
full = [
    "dep:serde",  # level = high
    "dep:rand",   # see docs = none
]
std = []
extra = []
T
printf '//! Name | Description\n//! `full` | everything\n//! `std` | the standard library\n//! `extra` | more\npub fn run() -> u32 { 1 }\n' >"$F/cg/src/lib.rs"
cat >"$F/cmk/CMakeLists.txt" <<'C'
cmake_minimum_required(VERSION 3.20)
project(cmkdemo C)
#[[ old
add_executable(ghostexe old.c)
]]
#[==[ add_executable(ghostlevel old.c) ]==]
add_library(zlibstatic STATIC IMPORTED)
add_library(aliaslib ALIAS meterlib)
add_library(
  turbine STATIC
  src/lib.c)
add_executable(realexe src/main.c)
C
printf 'int main(void) { return 0; }\n' >"$F/cmk/src/main.c"
printf 'int lib(void) { return 1; }\n' >"$F/cmk/src/lib.c"

# Rank: the crate that DEFINES a named thing comes before the crates that only depend on it, even with more anchors of their own
mkdir -p "$F/ws/crates/editor/src" "$F/ws/crates/ui_a/src" "$F/ws/crates/ui_b/src"
printf '[workspace]\nmembers = ["crates/*"]\n' >"$F/ws/Cargo.toml"
printf '[package]\nname = "editor"\n' >"$F/ws/crates/editor/Cargo.toml"
for c in ui_a ui_b; do
    printf '[package]\nname = "%s"\n\n[dependencies]\neditor.workspace = true\n\n[dev-dependencies]\neditor = { workspace = true, features = ["test"] }\n' "$c" >"$F/ws/crates/$c/Cargo.toml"
    printf 'pub fn %s() -> u32 { 1 }\n' "$c" >"$F/ws/crates/$c/src/lib.rs"
done
printf 'pub fn edit() -> u32 { 1 }\n' >"$F/ws/crates/editor/src/lib.rs"

# feature_touch line: the file's first line that defines or documents the anchored feature, not a #[cfg(feature = ..)] use of another
mkdir -p "$F/cfgf/src"
printf '[package]\nname = "cfgf"\n\n[features]\njson = []\nmultipart = []\nform = []\ntokio = []\n' >"$F/cfgf/Cargo.toml"
printf '#[cfg(feature = "form")]\nmod form;\n#[cfg(feature = "json")]\nmod json;\n//! `multipart` | multipart forms\n//! `json` | JSON\n//! `form` | forms\n//! `tokio` | rt\npub fn r() {}\n' >"$F/cfgf/src/lib.rs"

run(){ local fx="$1"; shift; ( cd "$F/$fx" || exit 1; "$BIN" "$F/$fx" --no-cache "$@" 2>/dev/null </dev/null ); }
block(){ grep -o '<manifest_rows .*</manifest_rows>' "$1" | head -1; }
# has ARM FIXTURE TASK PATTERN... — the block fires and holds every (python regex) pattern, in order
has(){
    local arm="$1" fx="$2" task="$3"; shift 3
    if ! run "$fx" "--for=$task" >"$TMP/o.xml"; then no "($arm) $fx: ripwire failed on: $task"; return; fi
    cp "$TMP/o.xml" "$TMP/$arm.xml"
    if python3 - "$TMP/o.xml" "$@" <<'PY'
import re, sys
s = open( sys.argv[1], encoding="utf8" ).read()
m = re.search( r'<manifest_rows .*</manifest_rows>', s )
if not m: sys.exit( "no block" )
b, at = m.group( 0 ), 0
for pat in sys.argv[2:]:
    f = re.compile( pat ).search( b, at )
    if not f: sys.exit( "missing %r after byte %d" % ( pat, at ) )
    at = f.end()
PY
    then ok "($arm) $fx: $task"; else no "($arm) $fx: $task -> $( block "$TMP/o.xml" | head -c 400 )"; fi
}
# lacks ARM FIXTURE TASK PATTERN — the block holds no match of the pattern ('' : no block at all)
lacks(){
    local arm="$1" fx="$2" task="$3" pat="$4"
    if ! run "$fx" "--for=$task" >"$TMP/o.xml" || [ ! -s "$TMP/o.xml" ] || ! grep -q '</ctx>$' "$TMP/o.xml"; then no "($arm) $fx: ripwire failed or printed no answer on: $task"; return; fi
    local b; b="$( block "$TMP/o.xml" )"
    if [ -z "$pat" ]; then
        if [ -z "$b" ] && ! grep -q 'manifest_rows' "$TMP/o.xml"; then ok "($arm) $fx: silent on: $task"; else no "($arm) $fx: fired on: $task -> $( printf '%s' "$b" | head -c 300 )"; fi
    elif [ -n "$b" ] && ! printf '%s' "$b" | grep -qE -- "$pat"; then ok "($arm) $fx: $task: no $pat"
    else no "($arm) $fx: $task: $pat present or no block -> $( printf '%s' "$b" | head -c 300 )"; fi
}

# ── readers ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────
has n1 acme "add a new broker transport like NATS or MQTT to brokers" \
    '<mf p="packages/brokers/package.json" matched="[^"]*nats[^"]*mqtt' '<r l="2" kind="package">&quot;name&quot;: &quot;@acme/brokers&quot;,</r>' \
    'kind="peer-dep">&quot;mqtt&quot;: &quot;\*&quot;</r>' '<mf p="package.json" matched="nats mqtt"' 'kind="dev-dep">&quot;mqtt&quot;'
lacks n2 acme "make lint pass on the app" ''
has n2 acme "run the lint npm script on the app" '<mf p="package.json"' '<r l="5" kind="script">&quot;lint&quot;: &quot;eslint .&quot;</r>'
lacks n3 acme "change core logging" ''
lacks n4 acme "speed up acme startup" ''
lacks n4 acme "rename the acme package" ''
has n4 acme "rename the acme package and its mqtt dependency" '<mf p="package.json" matched="acme mqtt"' 'kind="dev-dep">&quot;mqtt&quot;'
lacks n5 acme "connect the brokers package faster" 'kind="main"'
has n5 acme "the main entry of brokers" '<mf p="packages/brokers/package.json"' 'kind="main">&quot;main&quot;'
has c1 ferris "add a new extractor behind its own cargo feature like multipart" \
    '<mf p="ferris/Cargo.toml" matched="multipart"' '<r l="14" kind="feature">multipart = \[&quot;dep:multer&quot;\]</r>' \
    '<feature_touch n="4"><touch_list total="1"><touch p="ferris/src/lib.rs:2" share="4/4">'
lacks c1 ferris "add a new extractor behind its own cargo feature like multipart" 'other\.rs'
has c2 ferris "upgrade the tokio dependency" '<r l="23" kind="dep">\[dependencies\.tokio\]</r>'
has c3 ferris "ship the ferris-cli binary" '<r l="6" kind="bin">name = &quot;ferris-cli&quot;</r>'
lacks c4 ferris "speed up ferris routing" ''
lacks c4 ferris "rename the ferris crate" ''
has p1 pyrepo "the msgpack extra of the widgetkit package" '<mf p="pyproject.toml" matched="msgpack widgetkit"' \
    '<r l="2" kind="package">name = &quot;widgetkit&quot;</r>' '<r l="8" kind="extra">msgpack = '
lacks p1 pyrepo "rename notakey" ''
has s1 pyrepo "the gadgets package" '<mf p="sub/setup.cfg" matched="gadgets"' '<r l="2" kind="package">name = gadgets</r>'
has g1 gorepo "the gizmo module" '<mf p="go.mod"' '<r l="1" kind="module">module example.com/acme/gizmo/v2</r>'
has g1 gorepo "replace the nats.go dependency" '<r l="6" kind="dep">github.com/nats-io/nats.go v1.31.0</r>'
lacks g1 gorepo "use errgroup from sync" ''
has k1 cmrepo "start the meterd executable" '<mf p="CMakeLists.txt"' '<r l="3" kind="executable">add_executable\(meterd src/main.c\)</r>'
has k1 cmrepo "link the meterlib library statically" '<r l="4" kind="library">ADD_LIBRARY\(meterlib STATIC src/lib.c\)</r>'
lacks k1 cmrepo "the extra library" ''

has e1 hostlib "write and register a hostlib plugin that observes calls" '<mf p="tests/plugin/pyproject.toml" matched="hostlib plugin"' \
    '<r l="5" kind="entry-point" group="hostlib">my_plugin = &quot;example_plugin:plugin&quot;</r>'
lacks e2 hostlib "make hostlib calls faster" ''
has e3 hostlib "ship a hostlib extension" '<mf p="contrib/setup.cfg"' '<r l="6" kind="entry-point" group="hostlib.ext">fancy = fancy.mod:Fancy</r>'
has e4 hostlib "rename the hostctl command" '<mf p="pyproject.toml" matched="hostctl"' '<r l="5" kind="bin">hostctl = &quot;hostlib.cli:main&quot;</r>'

# ── noise: a common task word is not a request for a same-named dependency, feature or bin ───────────────────────────────────
lacks r1a shop "what enables debug_handler" ''
has r1a shop "add the handler feature" '<mf p="crates/shop-extra/Cargo.toml"' 'kind="feature">handler = '
lacks r1b shop "find the path from parse to render" ''
has r1b shop "build the path binary" '<mf p="fuzz/Cargo.toml"' 'kind="bin">name = &quot;path&quot;'
lacks r1c shop "serve it with python -m http.server" ''
has r1c shop "upgrade the http-server dependency" '<mf p="packages/web/package.json"' 'kind="dev-dep">&quot;http-server&quot;'
lacks r1d shop "upgrade the koa-router dependency" ''
has r1d shop "upgrade the find-my-way dependency" '<mf p="packages/router/package.json"' 'kind="dep">&quot;find-my-way&quot;'
lacks r1e shop "which find-my-way routes are slow" ''
has r1e shop "add a new route matcher like find-my-way" '<mf p="packages/router/package.json"'

# ── feature_touch line ───────────────────────────────────────────────────────────────────────────────────────────────────────
has f4a cfgf "add a new cargo feature like multipart" '<touch p="src/lib.rs:5" share="4/4">//! `multipart` \| multipart forms</touch>'
lacks f4a cfgf "add a new cargo feature like multipart" 'cfg\(feature'

# ── rank ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
has f2a ws "add a new action to the editor package" '<manifest_rows files="3"><mf p="crates/editor/Cargo.toml"' '<mf p="crates/ui_a/Cargo.toml"' '<mf p="crates/ui_b/Cargo.toml"'

# ── parser shapes ────────────────────────────────────────────────────────────────────────────────────────────────────────────
lacks f3a poet "the version dependency" ''
has f3a poet "the numpy dependency" '<r l="6" kind="dep">numpy = \['
has f3a poet "the requests dependency" '<r l="10" kind="dep">requests = '
lacks f3g poet "the python dependency" ''
has f3g poet "the pytest-cov dependency" '<r l="13" kind="dep">pytest-cov = '
has f3b cg "add a new cargo feature like std" '<feature_touch n="3"><touch_list total="1"><touch p="src/lib.rs:2" share="[0-9]/3">'
lacks f3b cg "the level feature" ''
has f3c cmk "the realexe executable" '<mf p="CMakeLists.txt"' '<r l="12" kind="executable">add_executable\(realexe src/main.c\)</r>'
lacks f3c cmk "the ghostexe executable" ''
lacks f3c cmk "the ghostlevel executable" ''
lacks f3d cmk "the zlibstatic library" ''
lacks f3d cmk "the aliaslib library" ''
has f3e cmk "the turbine library" '<r l="10" kind="library">turbine STATIC</r>'

# ── caps, dialects, placement ────────────────────────────────────────────────────────────────────────────────────────────────
has cap1 acme "use the kafkajs dependency in a plugin" '<manifest_rows files="5" shown="3" capped="1">'
has cap2 acme "add the kafkajs, nats and mqtt dependencies to brokers" '<mf p="packages/brokers/package.json" matched="[^"]*" rows="4" shown="3" capped="1">'
run acme "--for=add a new broker transport like NATS or MQTT to brokers" --json >"$TMP/j1.json"
if [ -s "$TMP/j1.json" ] && ! grep -q 'manifest_rows' "$TMP/j1.json"; then ok "(j1) --json carries no block"; else no "(j1) --json"; fi
run acme "--for=add a new broker transport like NATS or MQTT to brokers" --token-budget=4000 >"$TMP/b1.xml"
if grep -q '<manifest_rows files="2" held="budget"/></ctx>$' "$TMP/b1.xml" && ! grep -q '<r l=' "$TMP/b1.xml"; then ok "(b1) a token budget holds the block"
else no "(b1) budget: $( grep -o '<manifest_rows.*' "$TMP/b1.xml" | head -c 300 )"; fi
run ferris "--for=add a new extractor behind its own cargo feature like multipart" >"$TMP/a1.xml"
printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"add a new extractor behind its own cargo feature like multipart"}}}\n' "$F/ferris" \
  | ( cd "$F/ferris" || exit 1; "$BIN" --mcp 2>/dev/null ) | python3 -c '
import json, sys
for line in sys.stdin:
    d = json.loads( line )
    if d.get( "id" ) == 1:
        print( d["result"]["content"][0]["text"], end="" )
' >"$TMP/x1.xml"
if [ -n "$( block "$TMP/a1.xml" )" ] && [ "$( block "$TMP/x1.xml" )" = "$( block "$TMP/a1.xml" )" ]; then ok "(x1) MCP for: the same element bytes"
else no "(x1) MCP: $( block "$TMP/x1.xml" | head -c 300 )"; fi
run ferris "--for=add a new extractor behind its own cargo feature like multipart" --legend=full >"$TMP/l1.xml"
if python3 - "$TMP/a1.xml" "$TMP/l1.xml" <<'PY'
import sys
def legend( path ):
    s = open( path, encoding="utf8" ).read()
    i = s.index( "<!-- ripwire for manifest_rows:" )
    return s[ i: s.index( "-->", i ) ], s[ s.index( "-->", i ): ]
a, ra = legend( sys.argv[1] ); b, rb = legend( sys.argv[2] )
if not len( a ) < len( b ): sys.exit( "compact legend %d B is not shorter than full %d B" % ( len( a ), len( b ) ) )
if ra.split( "<manifest_rows", 1 )[1] != rb.split( "<manifest_rows", 1 )[1]: sys.exit( "the block rows differ between legends" )
PY
then ok "(l1) default legend is shorter than --legend=full; the block rows are the same"; else no "(l1) legend posture"; fi
for f in a1 l1 b1 n1 cap1 cap2 g1 k1 s1 e1 e3; do
    if python3 - "$TMP/$f.xml" <<'PY'
import re, sys, xml.dom.minidom as M
s = open( sys.argv[1], encoding="utf8" ).read()
M.parseString( s )
i = s.index( "<!-- ripwire for manifest_rows:" )
legend = s[ i: s.index( "-->", i ) ]
if "--" in legend[ 4: ]: sys.exit( "double hyphen in the legend" )
m = re.search( r'(<manifest_rows .*?(?:/>|</manifest_rows>))</ctx>$', s, re.S )
if not m: sys.exit( "the block does not close right before </ctx>" )
for tag, attrs in re.findall( r'<(manifest_rows|mf|r|feature_touch|touch_list|touch) ([^>]*?)/?>', m.group( 1 ) ):
    for a in re.findall( r'(\w+)="', attrs ):
        if not re.search( r'(?<![\w])' + a + r'=', legend ): sys.exit( "attribute %s= on <%s> is not in the legend" % ( a, tag ) )
PY
    then ok "(a1) $f: well formed, the block closes before </ctx>, its legend defines every attribute"; else no "(a1) $f: legend / placement"; fi
done
[ "$fail" = 0 ] && echo "formanifestcheck: PASS" || echo "formanifestcheck: FAIL"
[ "$fail" = 0 ]
