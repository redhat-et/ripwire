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
for f in a1 s2 c1a; do
    if python3 - "$TMP/$f.xml" <<'PY'
import re, sys, xml.dom.minidom as M
s = open( sys.argv[1], encoding="utf8" ).read()
M.parseString( s )
i = s.index( "<!-- ripwire for exemplar_family:" )
legend = s[ i: s.index( "-->", i ) ]
if "--" in legend[ 4: ]: sys.exit( "double hyphen in the legend" )
m = re.search( r'(<exemplar_family .*?(?:/>|</exemplar_family>))</ctx>$', s, re.S )
if not m: sys.exit( "the block does not close right before </ctx>" )
for tag, attrs in re.findall( r'<(exemplar_family|m) ([^>]*?)/?>', m.group( 1 ) ):
    for a in re.findall( r'(\w+)="', attrs ):
        if not re.search( r'(?<![\w])' + a + r'=', legend ): sys.exit( "attribute %s= on <%s> is not in the legend" % ( a, tag ) )
PY
    then ok "(a1) $f: well formed, the block closes before </ctx>, its legend defines every attribute"; else no "(a1) $f: legend / placement"; fi
done
[ "$fail" = 0 ] && echo "forexemplarcheck: PASS" || echo "forexemplarcheck: FAIL"
[ "$fail" = 0 ]
