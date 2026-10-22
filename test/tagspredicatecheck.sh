#!/usr/bin/env bash
# tagspredicatecheck.sh — the tags pass evaluates tree-sitter STRING predicates (#eq?, #not-eq?, #any-of?, #not-any-of?),
# so a keyword-headed definition's keyword list is tags.scm data, not a C++ table (#355, slice 5a of #354). Elixir's
# metadata attribute names (@doc, @spec, ...) moved the same way.
#
# WHY. Before #355 the tags pass never ran a pattern's predicates (queries/javascript/tags.scm and queries/cpp/tags.scm
# carried the notes), so Elixir kept `def`/`defp`/… in a C++ table (`elixirFunctionKeyword`, src/ingest_elixir.h) and every
# Lisp-style language after it would have had to do the same. The shared evaluator is src/infra/tspredicates.h: one walk
# over a pattern's predicate steps, used by the tags pass, by --match/--lint's passesPredicates and by its regex
# precompiler. #match? stays OUT of the tags pass (src/ingest_astquery.h's header measured its cost).
#
# RECORDED RED STATE (the pre-#355 binary, main @ 27eddee1):
#   arm A2 — queries/elixir/tags.scm carries no #any-of?, and src/ingest_elixir.h holds the keyword list   → FAIL
#   arm A3 — queries/elixir/tags.scm carries no #not-any-of? on @_attribute; the metadata list is C++       → FAIL
#   arm B4 — --match with (#any-of? @n "keep_one" "keep_two") returns all three functions (hits=3, not 2)    → FAIL
#   arm B5 — --match with (#not-any-of? @n …) returns all three (hits=3, not 1)                               → FAIL
#   arm B7 — `def "not a name" do … end` is indexed as a function named "not a name"/0                        → FAIL
#   arms A1, B1, B2, B3, B6 pass there too: B1/B2/B6 because the C++ tables then made the same decision the predicates
#   make now, B3 because --match always evaluated #eq?. They pin that nothing was lost when the tables moved.
#
# Arms:
#   (A1) every predicate in queries/*/tags.scm is one the tags pass evaluates. A #match? there would filter NOTHING,
#        silently — the exact bug this gate exists to prevent from coming back in another form.
#   (A2) Elixir's definition keywords are data: queries/elixir/tags.scm has #any-of? lists on @_keyword, all identical
#        and including "def", and no C++ statement spells that whole list (the old elixirFunctionKeyword table did).
#   (A3) Elixir's metadata attribute names are data the same way: one #not-any-of? list on @_attribute, including
#        "moduledoc", and no C++ statement spells that whole list (the old elixirMetadataAttribute table did).
#   (B1) #any-of?, through the tags pass: every keyword head in tagspredicatefix/ex defines its function, and an
#        ordinary call of the same shape (`ordinary(not_a_def(x))`) defines nothing.
#   (B2) #not-any-of?, through the tags pass: `def unquote(name)…` heads define no symbol named unquote.
#   (B6) #not-any-of? on an attribute, through the tags pass: tagspredicatefix/ex/lib/attrs.ex keeps the ordinary
#        @limit and the typed @type t, and defines no @moduledoc, @doc, @spec or @enforce_keys.
#   (B7) the one intended output change: tagspredicatefix/ex/lib/titles.ex keeps ExUnit's `test "a literal title"`,
#        and `def "not a name" do` (invalid Elixir) defines nothing. The string-title pattern carries no @_keyword,
#        so a definition keyword no longer reaches it; the C++ table used to accept it as "not a name"/0.
#   (B3..B5) #eq?, #any-of?, #not-any-of? through --match on tagspredicatefix/c: exactly 1, 2 and 1 hits.
#
# BYTE-IDENTITY (the issue's acceptance) is not an arm here — it needs the pre-change binary. Run
#   RIPWIRE_BASE=<pre-change ripwire> bash test/langidentitycheck.sh "$RIPWIRE_BASE" ./build/ripwire --langs=ex,clj,js
# and every row must read SAME.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/tagspredicatefix"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

TMP="$( mktemp -d )"
trap 'rm -rf "$TMP"' EXIT
export XDG_CACHE_HOME="$TMP/cache"

# ── A1. tags.scm uses only predicates the tags pass evaluates ───────────────────────────────────────────────
bad="$( python3 - "$ROOT/queries" <<'PY'
import pathlib, re, sys
allowed = {"eq?", "not-eq?", "any-of?", "not-any-of?"}
for path in sorted(pathlib.Path(sys.argv[1]).glob("*/tags.scm")):
    for no, line in enumerate(path.read_text().splitlines(), 1):
        code = line.split(";", 1)[0]
        for op in re.findall(r"\(#([A-Za-z-]+\?)", code):
            if op not in allowed:
                print(f"{path.parent.name}/tags.scm:{no} #{op}")
PY
)"
if [ -z "$bad" ]; then ok "A1 every tags.scm predicate is one the tags pass evaluates"; else no "A1 tags.scm uses predicates the tags pass does not run: $bad"; fi

# ── A2. Elixir's definition keywords are tags.scm data, with no C++ copy ────────────────────────────────────
a2="$( python3 - "$ROOT" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
scm = "\n".join(l.split(";", 1)[0] for l in (root / "queries/elixir/tags.scm").read_text().splitlines())
lists = [tuple(re.findall(r'"([^"]*)"', m)) for m in re.findall(r'\(#any-of\?\s+@_keyword((?:\s+"[^"]*")+)\s*\)', scm)]
if not lists:
    print("queries/elixir/tags.scm has no (#any-of? @_keyword ...) list")
elif len(set(lists)) != 1:
    print(f"the @_keyword lists differ: {sorted(set(lists))}")
elif "def" not in lists[0]:
    print(f"the @_keyword list has no \"def\": {lists[0]}")
# A COPY of the list is a C++ statement that spells all of it. Statements that test a few of the keywords for another
# reason (src/elixir_resolve.h decides privacy and macro-ness from the keyword a definition used) are a different
# concept and stay: CONTRIBUTING's "two keyword lists can match token for token and mean different things".
if lists:
    for path in sorted((root / "src").rglob("*")):
        if path.suffix in (".h", ".cpp") and path.is_file():
            for stmt in path.read_text(errors="replace").split(";"):
                if all(f'"{kw}"' in stmt for kw in lists[0]):
                    print(f"{path.relative_to(root)} spells the whole keyword list in one statement (a C++ copy of tags.scm's list)")
                    break
PY
)"
if [ -z "$a2" ]; then ok "A2 Elixir's definition keywords live only in queries/elixir/tags.scm"; else no "A2 $a2"; fi

# ── A3. Elixir's metadata attribute names are tags.scm data, with no C++ copy ───────────────────────────────
a3="$( python3 - "$ROOT" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
scm = "\n".join(l.split(";", 1)[0] for l in (root / "queries/elixir/tags.scm").read_text().splitlines())
lists = [tuple(re.findall(r'"([^"]*)"', m)) for m in re.findall(r'\(#not-any-of\?\s+@_attribute((?:\s+"[^"]*")+)\s*\)', scm)]
if len(lists) != 1:
    print(f"queries/elixir/tags.scm has {len(lists)} (#not-any-of? @_attribute ...) lists, want exactly 1")
elif "moduledoc" not in lists[0]:
    print(f"the @_attribute list has no \"moduledoc\": {lists[0]}")
else:
    for path in sorted((root / "src").rglob("*")):
        if path.suffix in (".h", ".cpp") and path.is_file():
            for stmt in path.read_text(errors="replace").split(";"):
                if all(f'"{name}"' in stmt for name in lists[0]):
                    print(f"{path.relative_to(root)} spells the whole metadata list in one statement (a C++ copy of tags.scm's list)")
                    break
PY
)"
if [ -z "$a3" ]; then ok "A3 Elixir's metadata attribute names live only in queries/elixir/tags.scm"; else no "A3 $a3"; fi

# ── B1/B2. the tags pass applies #any-of? and #not-any-of? ─────────────────────────────────────────────────
if ! "$BIN" "$FIX/ex" --no-cache > "$TMP/map.xml" 2> "$TMP/map.err"; then
    no "B1/B2 ripwire exited non-zero on tagspredicatefix/ex: $( head -c 300 "$TMP/map.err" )"
else
    b="$( python3 - "$TMP/map.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
syms = {s.get("n").split("/")[0] for s in ET.parse(sys.argv[1]).getroot().iter("s")}
kept = {"kept_def", "kept_defp", "kept_macro", "kept_guard", "kept_delegate", "caller"}
missing = sorted(kept - syms)
if missing:
    print(f"B1 keyword heads lost their definition: {missing}")
for name in ("not_a_def", "ordinary"):
    if name in syms:
        print(f"B1 an ordinary call became a definition: {name}")
if "unquote" in syms:
    print("B2 a generated `def unquote(...)` head became a symbol named unquote")
for name in ("@limit", "@type t"):
    if name not in syms:
        print(f"B6 an attribute that defines a value or a type lost its definition: {name}")
for name in ("@moduledoc", "@doc", "@spec", "@enforce_keys"):
    if name in syms:
        print(f"B6 a metadata attribute became a definition: {name}")
if "test a literal title" not in syms:
    print("B7 ExUnit's literal test title lost its definition")
quoted = sorted(s for s in syms if s.startswith('"'))
if quoted:
    print(f"B7 a string where a def's name belongs became a definition: {quoted}")
PY
)"
    if [ -z "$b" ]; then ok "B1 #any-of? keeps every keyword head and no ordinary call; B2 #not-any-of? drops unquote heads; B6 drops metadata attributes; B7 keeps test titles, drops def \"string\""; else no "$b"; fi
fi

# ── B3..B5. --match evaluates the same string predicates ─────────────────────────────────────────────────
FN='(function_definition declarator: (function_declarator declarator: (identifier) @n)'
hits(){ "$BIN" "$FIX/c" --no-cache "--match=$FN $1)" --legend=compact 2>/dev/null | grep -o '<match [^>]*hits="[0-9]*"' | grep -o 'hits="[0-9]*"' | grep -o '[0-9]*'; }
check(){ local label="$1" pred="$2" want="$3" got; got="$( hits "$pred" )"; if [ "$got" = "$want" ]; then ok "$label $pred: hits=$got"; else no "$label $pred: hits=${got:-none}, want $want"; fi; }
check B3 '(#eq? @n "keep_one")' 1
check B4 '(#any-of? @n "keep_one" "keep_two")' 2
check B5 '(#not-any-of? @n "keep_one" "keep_two")' 1

if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "FAILURES ABOVE"; fi
exit $fail
