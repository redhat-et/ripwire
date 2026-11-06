#!/usr/bin/env bash
# forexemplarcheck.sh — EXEMPLAR-STAIRS (src/exemplarfamily.h): an add-a-new-X --for task carries <exemplar_family>, the existing
# siblings a new X joins, just before </ctx>; every other task is unchanged.
#
# ARMS (E1 FAMILY)
#   (f1) one fixture per rule and language: C typed instances (meter), Go registry map (in-tree plugin), C++ registry map (codec),
#        Rust attribute macro (scalar function), TS base interface (dialect), Python subclass (handler): rule=, key=, n=
#   (f2) the cascade: a Python base class and a same-dir name affix tie on the task words: rule="base" (the earlier rule) wins
#   (f3) the task words pick between families: `scalar function` takes the attribute family under scalar/, not a `TableFunction` base
#   (f4) scope: members outside the deepest directory holding half of them are dropped (n= counts the scoped members)
#   (f5) typical first: the first <m> is the member nearest the median size
#   (f6) test code is no member: a subclass under tests/ is not counted
#   (c1) CAP-DISCLOSE: six members print four <m> rows with shown="4" capped="1"; four members print no shown=/capped=
#   (f7) a struct literal is no registry: `return Features{ A: .., }` with more `field: value,` lines than the registry has entries
#        does not take the family from the real registry (kubernetes NewSchedulerFeaturesFromGates beside NewInTreeRegistry)
#   (t1) wordings that fire: add a new / I need a new .. that / write a / implement another / another X like Y / add a X to the ..
#   (t2) wordings that do not: a parameter, a question, a fix, no article; a family-less X prints nothing
#
# ARMS (fix round 1: review rv-exemplar-e1)
#   (m1) a name or stem several members share is ONE unit: (a) four Rust fns in ONE file (one stem) are not credited to a file whose
#        comment holds the stem; their registered names in a dispatcher still are (share 4/4); (b) four Python classes all named
#        `Command` (one name) are not credited to a file that says "Command"; their four file stems in an import list still are (by="stem")
#       (c) seven classes under three names (Codec x3, StreamReader x2, StreamWriter x2; cpython's 330 codecs): a file that says all three
#           names is no listing (the name channel needs at least half as many distinct names as members); the seven stems still are
#   (m2) a function's parameter lines are no registry entries (typed Python): the dict in its body is the family; a signature of
#        `name: Type,` lines alone is no family
#   (d1) a decorator is matched whatever its case (`@Widget()` for the head `widget`), with no other mention of the word in the file
#   (h1) sample, example and benchmark directories hold no member and no touch row
#   (a2) the affix rule names classes only: four `*_command` functions are no family; three `*Worker` classes are
#   (w1) matched= names the task words found in key= or scope=; the legend says registry rows are in listing order
#   (l1) --legend=compact (the CLI default) prints the short legend, --legend=full the long one; both define every attribute
#
# ARMS (E3a TOUCH LIST: files outside the members' own that mention at least half of them)
#   (e1) per language: Rust exhaustive match + mod list (registered names and file stems), Go name list + defaults list, C platform
#        table, TS barrel by kebab path (`./dialects/postgres/postgres-dialect`), Python package __init__; C++ registry with no other
#        lister: <touch_list total="0"/>
#   (e2) the share threshold: a file naming 2 of 4 is listed (share="2/4"), a file naming 1 of 4 is not
#   (e3) not read: a test file, a README, a generated file (banner), a frozen/baseline file, a vendored file — each naming every member
#   (e4) the line to copy: the first naming the typical member (names.go:4), a code line before a comment that names a member
#        (list.go:4, not its doc comment on line 1), an import line only when no code line does (index.ts:2); cut="1" past 120 bytes
#   (e5) CAP-DISCLOSE: seven listing files print five <touch> rows, total="7" shown="5" capped="1"
#   (s1) --json carries no block; (s2) a token budget holds it (held="budget", no rows); (x1) MCP `for`: the same element bytes
#   (a1) the block's own legend defines every attribute it prints; the answer is well-formed XML; the block closes right before </ctx>
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
echo "forexemplarcheck: BIN=$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
cap(){ printf '%s' "$1" | awk '{ print toupper( substr( $0, 1, 1 ) ) substr( $0, 2 ) }'; }

# ── fixtures: one per language and rule (created at runtime) ──────────────────────────────────────────────────────────────────
F="$TMP/fx"
mkdir -p "$F/c/meters" "$F/c/other" "$F/go/names" "$F/rs/src/scalar" "$F/rs/src/table" "$F/rs/proto" "$F/py/app/handlers" "$F/py/tests" \
         "$F/cpp/src/codecs" "$F/ts/src/dialects"
for m in Cpu Mem Disk Net; do
    body=""; [ "$m" = Disk ] && body='   .total = 100,
   .caption = "Disk",
   .uiName = "Disk",'
    cat > "$F/c/meters/${m}Meter.c" <<C
#include "Meter.h"
static void ${m}Meter_update( Meter* this ) { this->value = 1; }
const MeterClass ${m}Meter_class = {
   .super = { .display = 0 },
${body}
   .updateValues = ${m}Meter_update,
};
C
done
cat > "$F/c/other/GpuMeter.c" <<'C'
#include "../meters/Meter.h"
const MeterClass GpuMeter_class = {
   .super = { .display = 0 },
};
C
printf 'typedef struct Meter_ { int value; } Meter;\ntypedef struct MeterClass_ { int super; void ( *updateValues )( Meter* ); } MeterClass;\n' > "$F/c/meters/Meter.h"
cat > "$F/c/Platform.c" <<'C'
#include "meters/Meter.h"
extern const MeterClass CpuMeter_class, MemMeter_class, DiskMeter_class, NetMeter_class;
const MeterClass* const Platform_meterTypes[] = {
   &CpuMeter_class,
   &MemMeter_class,
   &DiskMeter_class,
   &NetMeter_class,
   0
};
C
for p in alpha beta gamma delta; do
    P="$( cap "$p" )"; mkdir -p "$F/go/plugins/$p"
    printf 'package %s\n\nimport "example.com/x/names"\n\nconst Name = names.%s\n\ntype %s struct{}\n\nfunc New() (*%s, error) { return &%s{}, nil }\n' "$p" "$P" "$P" "$P" "$P" > "$F/go/plugins/$p/$p.go"
done
printf 'package names\n\nconst (\n\tAlpha = "Alpha"\n\tBeta  = "Beta"\n\tGamma = "Gamma"\n\tDelta = "Delta"\n)\n' > "$F/go/names/names.go"
cat > "$F/go/plugins/registry.go" <<'GO'
package plugins

type Registry map[string]func() (interface{}, error)

func NewInTreeRegistry() Registry {
	return Registry{
		alpha.Name: alpha.New,
		beta.Name:  beta.New,
		gamma.Name: gamma.New,
		delta.Name: delta.New,
	}
}
GO
mkdir -p "$F/go/plugins/feature"
printf 'package feature\n\ntype Features struct {\n\tEnableA bool\n\tEnableB bool\n\tEnableC bool\n\tEnableD bool\n\tEnableE bool\n}\n\nfunc NewPluginFeatures(g Gate) Features {\n\treturn Features{\n\t\tEnableA: g.On("A"),\n\t\tEnableB: g.On("B"),\n\t\tEnableC: g.On("C"),\n\t\tEnableD: g.On("D"),\n\t\tEnableE: g.On("E"),\n\t}\n}\n' > "$F/go/plugins/feature/feature.go"
for f in upper lower trim concat_ws; do
    printf 'use crate::function;\n\n#[function("%s(varchar) -> varchar")]\npub fn %s_str(s: &str) -> String {\n    s.to_string()\n}\n' "$f" "$f" > "$F/rs/src/scalar/$f.rs"
done
printf 'pub trait TableFunction {\n    fn eval(&self);\n}\n' > "$F/rs/src/table/mod.rs"
for t in Series Unnest Range; do
    printf 'pub struct %sFunction;\nimpl TableFunction for %sFunction {\n    fn eval(&self) {}\n}\n' "$t" "$t" > "$F/rs/src/table/$( echo "$t" | tr 'A-Z' 'a-z' ).rs"
done
printf 'mod upper;\nmod lower;\nmod trim;\nmod concat_ws;\n' > "$F/rs/src/scalar/mod.rs"
printf 'class Handler:\n    def handle(self, req):\n        raise NotImplementedError\n' > "$F/py/app/handlers/base.py"
for h in json xml csv yaml; do
    H="$( cap "$h" )"
    printf 'from .base import Handler\n\n\nclass %sHandler(Handler):\n    def handle(self, req):\n        return "%s"\n' "$H" "$h" > "$F/py/app/handlers/${h}_handler.py"
done
printf 'from app.handlers.base import Handler\n\n\nclass FakeHandler(Handler):\n    def handle(self, req):\n        return None\n' > "$F/py/tests/test_fake.py"
printf 'def route_handler(req):\n    return req\n\n\ndef error_handler(req):\n    return req\n\n\ndef index_handler(req):\n    return req\n' > "$F/py/app/handlers/funcs.py"
for c in Gzip Zstd Lz4 Brotli; do
    printf '#include "Codec.h"\nstd::unique_ptr<Codec> make%sCodec() { return std::make_unique<Codec>(); }\n' "$c" > "$F/cpp/src/codecs/${c}Codec.cpp"
done
printf '#include <memory>\nstruct Codec { virtual ~Codec() = default; };\n' > "$F/cpp/src/codecs/Codec.h"
cat > "$F/cpp/src/codecs/CodecFactory.cpp" <<'CPP'
#include "Codec.h"
#include <map>
#include <string>
using CodecMaker = std::unique_ptr<Codec> (*)();
static const std::map<std::string, CodecMaker> kCodecRegistry = {
    { "gzip", makeGzipCodec },
    { "zstd", makeZstdCodec },
    { "lz4", makeLz4Codec },
    { "brotli", makeBrotliCodec },
};
CPP
printf 'export interface Dialect {\n  createDriver(): unknown\n}\n' > "$F/ts/src/dialect.ts"
for d in postgres mysql sqlite mssql; do
    D="$( cap "$d" )"; mkdir -p "$F/ts/src/dialects/$d"
    printf "import { Dialect } from '../../dialect'\n\nexport class %sDialect implements Dialect {\n  createDriver(): unknown {\n    return '%s'\n  }\n}\n" "$D" "$d" > "$F/ts/src/dialects/$d/$d-dialect.ts"
done

mkdir -p "$F/cap/ui"
printf 'class Widget:\n    pass\n' > "$F/cap/ui/base.py"
for w in a b c d e f; do printf 'from .base import Widget\n\n\nclass %sWidget(Widget):\n    pass\n' "$( cap "$w" )" > "$F/cap/ui/$w.py"; done

# E3a fixtures: listers, skipped classes, the threshold pair, the cap
printf 'from .json_handler import JsonHandler\nfrom .xml_handler import XmlHandler\nfrom .csv_handler import CsvHandler\nfrom .yaml_handler import YamlHandler\n' > "$F/py/app/handlers/__init__.py"
printf "export * from './dialect'\nexport * from './dialects/postgres/postgres-dialect'\nexport * from './dialects/mysql/mysql-dialect'\nexport * from './dialects/sqlite/sqlite-dialect'\nexport * from './dialects/mssql/mssql-dialect'\n" > "$F/ts/src/index.ts"
printf 'pub fn is_pure(t: ExprType) -> bool {\n    match t {\n        ExprType::Upper | ExprType::Lower | ExprType::Trim | ExprType::ConcatWs => true,\n    }\n}\n' > "$F/rs/src/pure.rs"
printf 'package plugins\n\n// two of four\nvar half = []string{names.Alpha, names.Beta}\n' > "$F/go/plugins/half.go"
printf '// Package plugins: Alpha comes first.\npackage plugins\n\nvar list = []string{names.Beta, names.Alpha, names.Gamma}\n' > "$F/go/plugins/list.go"
printf 'package plugins\n\n// one of four\nvar one = []string{names.Gamma}\n' > "$F/go/plugins/one.go"
printf 'package plugins\n\nfunc defaultPlugins() []string {\n\treturn []string{"Alpha", "Beta", "Gamma", "Delta", "AVeryLongPaddingNameThatPushesThisLineFarPastTheOneHundredAndTwentyByteCutOfTheTouchRowText"}\n}\n' > "$F/go/plugins/defaults.go"
all_go='Alpha Beta Gamma Delta'
printf 'package plugins\n\nvar all = "%s"\n' "$all_go" > "$F/go/plugins/registry_test.go"
printf '# Plugins\n\n%s\n' "$all_go" > "$F/go/README.md"
printf '// Code generated by gen. DO NOT EDIT.\npackage plugins\n\nvar gen = "%s"\n' "$all_go" > "$F/go/plugins/zz_listing.go"
mkdir -p "$F/go/baseline" "$F/go/vendor/x"
printf 'package baseline\n\nvar frozen = "%s"\n' "$all_go" > "$F/go/baseline/list.go"
printf 'package x\n\nvar v = "%s"\n' "$all_go" > "$F/go/vendor/x/list.go"
for i in 1 2 3 4 5 6 7; do printf 'from ui.a import AWidget\nREG%s = [AWidget, "BWidget", "CWidget", "DWidget", "EWidget", "FWidget"]\n' "$i" > "$F/cap/list$i.py"; done

# fix-round fixtures
mkdir -p "$F/m1s/src" "$F/m1n/cmds" "$F/m2/app" "$F/s3/src/ui" "$F/s2/src/plugins" "$F/s2/examples" "$F/s2/benchmarks" "$F/s4/src" "$F/s4c/src/jobs"
for c in quit write open close; do printf '#[command]\npub fn %s() {}\n' "$c"; done > "$F/m1s/src/cmds.rs"
printf '// the cmds live in another module\npub fn helper() -> u32 { 0 }\n' > "$F/m1s/src/notes.rs"
printf 'pub fn dispatch( name: &str ) {\n    match name {\n        "quit" => (), "write" => (), "open" => (), "close" => (),\n        _ => (),\n    }\n}\n' > "$F/m1s/src/dispatch.rs"
printf 'class BaseCommand:\n    pass\n' > "$F/m1n/cmds/base.py"
for c in alpha beta gamma delta; do printf 'from .base import BaseCommand\n\n\nclass Command(BaseCommand):\n    def handle(self):\n        return "%s"\n' "$c" > "$F/m1n/cmds/$c.py"; done
printf '# a Command line tool for the shell\nx = 1\n' > "$F/m1n/notes.py"
printf 'from cmds import alpha, beta, gamma, delta\n' > "$F/m1n/registry.py"
mkdir -p "$F/m1c/cmds"
printf 'class BaseCodec:\n    pass\n' > "$F/m1c/cmds/base.py"
i=0; for c in alpha:Codec beta:Codec gamma:Codec delta:StreamReader kappa:StreamReader sigma:StreamWriter omega:StreamWriter; do
    printf 'from .base import BaseCodec\n\n\nclass %s(BaseCodec):\n    pass\n' "${c#*:}" > "$F/m1c/cmds/${c%%:*}.py"; i=$((i+1)); done
printf '# Codec, StreamReader and StreamWriter live elsewhere\nx = 1\n' > "$F/m1c/notes.py"
printf 'from cmds import alpha, beta, gamma, delta, kappa, sigma, omega\n' > "$F/m1c/registry.py"
printf 'def default_handler_options(\n    timeout: int,\n    retries: int,\n    backoff: float,\n    jitter: bool,\n):\n    return 1\n' > "$F/m2/app/opts.py"
printf 'def handler_table(\n    timeout: int,\n    retries: int,\n):\n    return {\n        "json": 1,\n        "xml": 2,\n        "csv": 3,\n        "yaml": 4,\n        "toml": 5,\n        "ini": 6,\n    }\n' > "$F/m2/app/table.py"
for w in foo bar baz; do printf "import { Widget } from '../deco'\n\n@Widget()\nexport class %sPanel {\n  x = 1\n}\n" "$w" > "$F/s3/src/ui/$w.ts"; done
printf 'class Plugin:\n    pass\n' > "$F/s2/src/plugins/base.py"
for p in Aa Bb Cc; do printf 'from .base import Plugin\n\n\nclass %sPlugin(Plugin):\n    pass\n' "$p" > "$F/s2/src/plugins/$p.py"; done
for p in Aa Bb Cc Dd; do printf 'from src.plugins.base import Plugin\n\n\nclass %sDemo(Plugin):\n    pass\n' "$p" > "$F/s2/examples/$p.py"; done
for d in src examples benchmarks; do printf 'ALL = ["AaPlugin", "BbPlugin", "CcPlugin"]\n' > "$F/s2/$d/all.py"; done
for c in quit write open close; do printf 'pub fn %s_command() -> u32 {\n    1\n}\n' "$c"; done > "$F/s4/src/commands.rs"
for j in Send Fetch Purge; do printf 'class %sWorker:\n    def run(self):\n        return 1\n' "$j" > "$F/s4c/src/jobs/$(echo "$j" | tr 'A-Z' 'a-z').py"; done

run(){ local fx="$1"; shift; ( cd "$F/$fx" || exit 1; "$BIN" "$F/$fx" --no-cache "$@" 2>/dev/null </dev/null ); }
block(){ grep -o '<exemplar_family .*</exemplar_family>' "$1" | head -1; }
# fam ARM FIXTURE TASK RULE KEY N — the block fires with rule=, key=, n=
fam(){
    local arm="$1" fx="$2" task="$3" rule="$4" key="$5" n="$6"
    if ! run "$fx" "--for=$task" >"$TMP/o.xml"; then no "($arm) $fx: ripwire failed on: $task"; return; fi
    local b; b="$( block "$TMP/o.xml" )"
    if printf '%s' "$b" | grep -q " rule=\"$rule\" key=\"$key\"[^>]* n=\"$n\"[ >]"; then ok "($arm) $fx: $task -> rule=$rule key=$key n=$n"
    else no "($arm) $fx: $task -> want rule=$rule key=$key n=$n, got: $( printf '%s' "$b" | head -c 300 )"; fi
}
silent(){ # ARM FIXTURE TASK
    if run "$2" "--for=$3" >"$TMP/s.xml" && grep -q '</ctx>$' "$TMP/s.xml" && ! grep -q 'exemplar_family' "$TMP/s.xml"; then ok "($1) $2: silent: $3"
    else no "($1) $2: must be silent: $3"; fi
}

fam f1 c   "add a new meter"                  typed     MeterClass        4
fam f1 go  "add a new in-tree plugin"         registry  NewInTreeRegistry 4
fam f1 cpp "add a new codec"                  registry  kCodecRegistry    4
fam f1 rs  "add a new scalar function"        attribute function          4
fam f1 ts  "add a new dialect"                base      Dialect           4
fam f1 py  "add a new handler"                base      Handler           4
fam f2 py  "write a new handler"              base      Handler           4
fam f7 go  "write a plugin"                   registry  NewInTreeRegistry 4
fam f3 rs  "I want to add a scalar function to the builtin set; where do I begin?" attribute function 4
fam f3 rs  "add a new table function"         base      TableFunction     3
# f4: GpuMeter_class sits outside meters/, which holds 4 of the 5: n="4" and scope="meters"
run c "--for=add a new meter" >"$TMP/f4.xml"
if block "$TMP/f4.xml" | grep -q 'scope="meters" n="4">' && ! block "$TMP/f4.xml" | grep -q 'GpuMeter'; then ok "(f4) scope: the member outside meters/ is dropped"
else no "(f4) scope: $( block "$TMP/f4.xml" | head -c 300 )"; fi
# f5: DiskMeter_class is the longest instance (7 lines), the others 4: the median is 4, so Disk is never first
first="$( block "$TMP/f4.xml" | grep -o '<m n="[^"]*"' | head -1 )"
if [ -n "$first" ] && [ "$first" != '<m n="DiskMeter_class"' ]; then ok "(f5) typical first: $first (not the outlier DiskMeter_class)"; else no "(f5) typical first: $first"; fi
# f6: tests/test_fake.py's FakeHandler is no member
run py "--for=add a new handler" >"$TMP/f6.xml"
if block "$TMP/f6.xml" | grep -q 'n="4"' && ! grep -q 'FakeHandler' <( block "$TMP/f6.xml" ); then ok "(f6) a subclass under tests/ is no member"; else no "(f6) $( block "$TMP/f6.xml" | head -c 300 )"; fi

run cap "--for=add a new widget" >"$TMP/c1.xml"
if block "$TMP/c1.xml" | grep -q ' n="6" shown="4" capped="1">' && [ "$( block "$TMP/c1.xml" | grep -o '<m ' | wc -l | tr -d ' ' )" = 4 ] \
   && ! block "$TMP/f6.xml" | grep -q 'capped='; then ok "(c1) six members: four rows, shown=\"4\" capped=\"1\"; four members: no cap attributes"
else no "(c1) cap: $( block "$TMP/c1.xml" | head -c 200 )"; fi

# E3a arms
touchrows(){ block "$1" | grep -o '<touch_list.*</touch_list>\|<touch_list total="0"/>'; }
has_touch(){ # ARM FILE P SHARE — a <touch> row at p= (file or file:line) with share=
    if touchrows "$2" | grep -q "<touch p=\"$3[:\"][^>]*share=\"$4\""; then ok "($1) touch $3 share=$4"; else no "($1) want touch $3 share=$4 in: $( touchrows "$2" | head -c 400 )"; fi
}
no_touch(){ # ARM FILE P WHY
    if [ -n "$( block "$2" )" ] && ! touchrows "$2" | grep -q "<touch p=\"$3[:\"]"; then ok "($1) no touch row for $3 ($4)"; else no "($1) $3 must not be a touch row ($4): $( touchrows "$2" | head -c 400 )"; fi
}
run rs "--for=add a new scalar function" >"$TMP/e_rs.xml"
has_touch e1 "$TMP/e_rs.xml" src/pure.rs 4/4
has_touch e1 "$TMP/e_rs.xml" src/scalar/mod.rs 4/4
run go "--for=add a new in-tree plugin" >"$TMP/e_go.xml"
has_touch e1 "$TMP/e_go.xml" names/names.go 4/4
has_touch e1 "$TMP/e_go.xml" plugins/defaults.go 4/4
run c "--for=add a new meter" >"$TMP/e_c.xml"
has_touch e1 "$TMP/e_c.xml" Platform.c 4/4
run ts "--for=add a new dialect" >"$TMP/e_ts.xml"
has_touch e1 "$TMP/e_ts.xml" src/index.ts 4/4
run py "--for=add a new handler" >"$TMP/e_py.xml"
has_touch e1 "$TMP/e_py.xml" app/handlers/__init__.py 4/4
run cpp "--for=add a new codec" >"$TMP/e_cpp.xml"
if block "$TMP/e_cpp.xml" | grep -q '<touch_list total="0"/></exemplar_family>'; then ok "(e1) cpp: no lister outside the registry: touch_list total=\"0\""; else no "(e1) cpp: $( touchrows "$TMP/e_cpp.xml" | head -c 300 )"; fi
has_touch e2 "$TMP/e_go.xml" plugins/half.go 2/4
no_touch e2 "$TMP/e_go.xml" plugins/one.go "names 1 of 4"
no_touch e2 "$TMP/e_go.xml" plugins/alpha/alpha.go "a plugin's own package names itself only"
no_touch e3 "$TMP/e_go.xml" plugins/registry_test.go "a test file"
no_touch e3 "$TMP/e_go.xml" README.md "docs"
no_touch e3 "$TMP/e_go.xml" plugins/zz_listing.go "a generated banner"
no_touch e3 "$TMP/e_go.xml" baseline/list.go "a baseline path"
no_touch e3 "$TMP/e_go.xml" vendor/x/list.go "vendored"
has_touch e4 "$TMP/e_go.xml" names/names.go:4 4/4
has_touch e4 "$TMP/e_ts.xml" src/index.ts:2 4/4
has_touch e4 "$TMP/e_go.xml" plugins/list.go:4 3/4
if touchrows "$TMP/e_go.xml" | grep -q '<touch p="plugins/defaults.go:4" share="4/4" cut="1">'; then ok "(e4) a line past 120 bytes is cut: cut=\"1\""; else no "(e4) cut: $( touchrows "$TMP/e_go.xml" | head -c 400 )"; fi
run cap "--for=add a new widget" >"$TMP/e_cap.xml"
if touchrows "$TMP/e_cap.xml" | grep -q '^<touch_list total="7" shown="5" capped="1">' && [ "$( touchrows "$TMP/e_cap.xml" | grep -o '<touch ' | wc -l | tr -d ' ' )" = 5 ]; then ok "(e5) seven listers: five rows, total=7 shown=5 capped=1"
else no "(e5) cap: $( touchrows "$TMP/e_cap.xml" | head -c 300 )"; fi
cp "$TMP/e_go.xml" "$TMP/e_goa.xml"

# t1 / t2: wordings
fam t1 ts "What do I need to change to add a new dialect?"                     base Dialect 4
fam t1 ts "I need a new dialect that speaks to DuckDB; where do I start?"      base Dialect 4
fam t1 ts "I need to write a dialect for DuckDB"                               base Dialect 4
fam t1 ts "how do I implement another dialect"                                 base Dialect 4
fam t1 ts "create another dialect like PostgresDialect"                        base Dialect 4
fam t1 ts "I want to add support for a new database (a new dialect)"           base Dialect 4
fam t1 py "write and register a new handler"                                   base Handler 4
silent t2 ts "add a required parameter to createDriver"
silent t2 ts "how does the postgres dialect create a driver"
silent t2 ts "fix the dialect bug in createDriver"
silent t2 ts "add dialect support"
silent t2 ts "add a new widget"
silent t2 c  "add a new field to Meter"
silent t2 ts "How does running the build make a dialect, end to end"
silent t2 ts "How does createDriver build a dialect for postgres?"

# fix round 1 arms
# m1 (a): four fns in ONE file are one stem; the registered names in a dispatcher are four names
run m1s "--for=add a new command" >"$TMP/m1s.xml"
if block "$TMP/m1s.xml" | grep -q ' rule="attribute" key="command"[^>]* n="4"'; then ok "(m1) m1s: attribute command n=4 (four fns in one file)"; else no "(m1) m1s family: $( block "$TMP/m1s.xml" | head -c 300 )"; fi
no_touch m1 "$TMP/m1s.xml" src/notes.rs "a comment holding the stem of a file that holds all four is one stem, not four members"
has_touch m1 "$TMP/m1s.xml" src/dispatch.rs 4/4
# m1 (b): four classes all named Command are one name; their four file stems are four
run m1n "--for=add a new command" >"$TMP/m1n.xml"
if block "$TMP/m1n.xml" | grep -q ' rule="base" key="BaseCommand"[^>]* n="4"'; then ok "(m1) m1n: base BaseCommand n=4 (four classes named Command)"; else no "(m1) m1n family: $( block "$TMP/m1n.xml" | head -c 300 )"; fi
no_touch m1 "$TMP/m1n.xml" notes.py "the word Command is one shared name, not four members"
if touchrows "$TMP/m1n.xml" | grep -q '<touch p="registry.py:[0-9]*" share="4/4" by="stem"'; then ok "(m1) m1n: registry.py names the four file stems: share=\"4/4\" by=\"stem\""; else no "(m1) m1n stems: $( touchrows "$TMP/m1n.xml" | head -c 300 )"; fi
# m1 (c): seven classes under three names (Codec x3, StreamReader x2, StreamWriter x2): the names say nothing per member, the stems do
run m1c "--for=add a new codec" >"$TMP/m1c.xml"
if block "$TMP/m1c.xml" | grep -q ' rule="base" key="BaseCodec"[^>]* n="7"'; then ok "(m1) m1c: base BaseCodec n=7 (seven classes under three names)"; else no "(m1) m1c family: $( block "$TMP/m1c.xml" | head -c 300 )"; fi
no_touch m1 "$TMP/m1c.xml" notes.py "three shared names across seven members"
if touchrows "$TMP/m1c.xml" | grep -q '<touch p="registry.py:[0-9]*" share="7/7" by="stem"'; then ok "(m1) m1c: registry.py names the seven file stems"; else no "(m1) m1c stems: $( touchrows "$TMP/m1c.xml" | head -c 300 )"; fi
# m2: parameter lines are no entries
silent m2 m2 "add a new handler option"
run m2 "--for=add a new handler table" >"$TMP/m2.xml"
if block "$TMP/m2.xml" | grep -q ' rule="registry" key="handler_table"[^>]* n="6"' && block "$TMP/m2.xml" | grep -q '<m n="json"' && ! block "$TMP/m2.xml" | grep -q '<m n="timeout"'; then ok "(m2) m2: the body dict is the registry (json xml csv yaml toml ini), the parameters timeout/retries are not entries"
else no "(m2) m2: $( block "$TMP/m2.xml" | head -c 300 )"; fi
# d1: a decorator in another case than the head, no other mention of the word in the file
fam d1 s3 "add a new widget" attribute Widget 3
# h1: sample / example / benchmark dirs
run s2 "--for=add a new plugin" >"$TMP/h1.xml"
if block "$TMP/h1.xml" | grep -q ' rule="base" key="Plugin"[^>]* scope="src/plugins" n="3"' && ! block "$TMP/h1.xml" | grep -q 'Demo'; then ok "(h1) s2: four Demo classes under examples/ are no member; the three plugins are"; else no "(h1) s2: $( block "$TMP/h1.xml" | head -c 300 )"; fi
has_touch h1 "$TMP/h1.xml" src/all.py 3/3
no_touch h1 "$TMP/h1.xml" examples/all.py "an example directory"
no_touch h1 "$TMP/h1.xml" benchmarks/all.py "a benchmark directory"
# a2: affix is for classes
silent a2 s4 "add a new command"
fam a2 s4c "add a new worker" affix worker 3
run s4c "--for=add a new worker" >"$TMP/a2.xml"; run s4c "--for=add a new worker" --legend=full >"$TMP/a2f.xml"
if grep -q 'weakest grouping' "$TMP/a2.xml" && grep -q 'weakest grouping' "$TMP/a2f.xml"; then ok "(a2) both legends call the affix rule the weakest grouping"; else no "(a2) legend: affix is not called weakest"; fi
# w1: why this family
if block "$TMP/e_rs.xml" | grep -q ' matched="scalar function" scope='; then ok "(w1) matched= names both task words of the scalar function family"; else no "(w1) matched: $( block "$TMP/e_rs.xml" | head -c 300 )"; fi
if grep -q 'listing order' "$TMP/e_go.xml" && grep -q 'matched=' "$TMP/e_go.xml"; then ok "(w1) the legend says what the first <m> is under rule=registry"; else no "(w1) legend"; fi
# l1: --legend=full prints the long legend, the default (compact) the short one; both define every attribute (a1 below)
run rs "--for=add a new scalar function" --legend=full >"$TMP/l_full.xml"
if python3 - "$TMP/e_rs.xml" "$TMP/l_full.xml" <<'PY'
import sys
def legend( path ):
    s = open( path, encoding="utf8" ).read()
    i = s.index( "<!-- ripwire for exemplar_family:" )
    return s[ i: s.index( "-->", i ) ], s[ :i ] + s[ s.index( "-->", i ): ]
a, ra = legend( sys.argv[1] ); b, rb = legend( sys.argv[2] )
if not len( a ) < len( b ): sys.exit( "compact legend %d B is not shorter than full %d B" % ( len( a ), len( b ) ) )
if ra.split( "<exemplar_family", 1 )[1] != rb.split( "<exemplar_family", 1 )[1]: sys.exit( "the block rows differ between legends" )
PY
then ok "(l1) default legend is shorter than --legend=full; the block rows are the same"; else no "(l1) legend posture"; fi

# s1 / s2 / x1 / a1
run ts "--for=add a new dialect" --json >"$TMP/s1.json"
if [ -s "$TMP/s1.json" ] && ! grep -q 'exemplar_family' "$TMP/s1.json"; then ok "(s1) --json carries no block"; else no "(s1) --json"; fi
run ts "--for=add a new dialect" --token-budget=4000 >"$TMP/s2.xml"
if grep -q '<exemplar_family of="dialect" held="budget"/></ctx>$' "$TMP/s2.xml" && ! grep -q '<m n=' "$TMP/s2.xml"; then ok "(s2) a token budget holds the block"
else no "(s2) budget: $( grep -o '<exemplar_family.*' "$TMP/s2.xml" | head -c 300 )"; fi
run ts "--for=add a new dialect" >"$TMP/a1.xml"
printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"add a new dialect"}}}\n' "$F/ts" \
  | ( cd "$F/ts" || exit 1; "$BIN" --mcp 2>/dev/null ) | python3 -c '
import json, sys
for line in sys.stdin:
    d = json.loads( line )
    if d.get( "id" ) == 1:
        print( d["result"]["content"][0]["text"], end="" )
' >"$TMP/x1.xml"
if [ -n "$( block "$TMP/a1.xml" )" ] && [ "$( block "$TMP/x1.xml" )" = "$( block "$TMP/a1.xml" )" ]; then ok "(x1) MCP for: the same element bytes"
else no "(x1) MCP: $( block "$TMP/x1.xml" | head -c 300 )"; fi
cp "$TMP/c1.xml" "$TMP/c1a.xml"
for f in a1 s2 c1a e_goa l_full; do
    if python3 - "$TMP/$f.xml" <<'PY'
import re, sys, xml.dom.minidom as M
s = open( sys.argv[1], encoding="utf8" ).read()
M.parseString( s )
i = s.index( "<!-- ripwire for exemplar_family:" )
legend = s[ i: s.index( "-->", i ) ]
if "--" in legend[ 4: ]: sys.exit( "double hyphen in the legend" )
m = re.search( r'(<exemplar_family .*?(?:/>|</exemplar_family>))</ctx>$', s, re.S )
if not m: sys.exit( "the block does not close right before </ctx>" )
for tag, attrs in re.findall( r'<(exemplar_family|m|touch_list|touch) ([^>]*?)/?>', m.group( 1 ) ):
    for a in re.findall( r'(\w+)="', attrs ):
        if not re.search( r'(?<![\w])' + a + r'=', legend ): sys.exit( "attribute %s= on <%s> is not in the legend" % ( a, tag ) )
PY
    then ok "(a1) $f: well formed, the block closes before </ctx>, its legend defines every attribute"; else no "(a1) $f: legend / placement"; fi
done
[ "$fail" = 0 ] && echo "forexemplarcheck: PASS" || echo "forexemplarcheck: FAIL"
[ "$fail" = 0 ]
