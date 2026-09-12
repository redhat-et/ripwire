#!/usr/bin/env bash
# elixirnamearitycheck.sh — Elixir callables are keyed `name/N` (parser version 95). This gate pins what that
# key must NOT cost the verbs around it, and what the resolver must disclose when it refuses a call.
#
# Fixture test/elixirnamearityfix (copied to a tmp dir; the edit-check arms turn the copy into a git repo):
#   lib/web.ex      Web.__using__ injects `import Web.Helpers`; Web.Helpers.text/2 is the use-delivered target
#   lib/page.ex     `use Web` then a bare text/2 call (no alias/import/receiver names it) and a call nothing defines
#   lib/channel.ex  socket/0 decoy + `%Channel{} = socket` bindings in a def head, a case clause and a with
#                   generator, read in the body; rhs/0 and bare_rhs/0 are the body-match CONTROLS whose right
#                   side is a real call
#   lib/work.ex     run/1 (the edit-check arm widens it to run/2) and generate_app/1 (the exact-name --for target)
#   lib/client.ex   an imported bare caller and a module-qualified caller of run/1
#   lib/outer.ex    a nested module named through alias, and two modules reading a same-named @limit
#   lib/user.ex     `alias Outer.Inner` — the nested-module import use-site
#
# Arms (each answers one review item on the PR that introduced name/N — items 2..5 and two CodeRabbit findings):
#   (A) a call delivered by `use` has no lexical candidate. NO edge is minted from a same-spelled function
#       elsewhere, and the drop is COUNTED: the map header's unresolved= and every answer's graph_unresolved=
#       carry it when some definition spells the name (unresolved), and stay silent when nothing does
#       (undefined has no header surface by design). Two mutations: delete the definition (the count must
#       drop to 0 — the call became undefined), and add the lexical import (the edge appears, the count drops).
#   (B) a variable bound on the RIGHT of `=` inside a pattern (def head, case clause, with generator) is a
#       binding, never a zero-arity call: the decoy socket/0 gains no caller from it. Controls: a body match
#       whose right side is `socket()` or bare `socket` IS a call, and that edge stays.
#   (C) --edit-check across an arity change: run(x) -> run(x, y) is a CONTRACT CHANGE on the logical symbol
#       `run` (params 1 -> 2), never a new-symbol, and every caller of the OLD arity is listed and flagged
#       incompatible with its call-site lines. Sound side: widening with a DEFAULT (`run(x, y \\ 1)`) still
#       reports the contract change but flags nobody — a default has no fixed arity.
#   (D) --for by exact name: the query `generate_app` (snake shape) and the plain word `text` both route
#       name-exact and rank their `name/N` symbol first; the explicit `text/2` spelling keeps working.
#   (E) --uses on a nested module named through `alias`, and on an attribute read where a same-named
#       attribute lives in another module: the import row is present and the qualifier keeps the reads apart
#       (the CodeRabbit reachesAny finding on PR #81, declined — this is the evidence).
#   (F) determinism and well-formedness of the fixture map.
#
# Fixture test/elixirresolvefix (its own crawl: every row below adds a COUNTED unresolved call, which would move
# arm (A)'s header count on the fixture above; copied to a tmp dir, the arm-(H) mutation deletes a file):
#   lib/toolbox.ex  `import Toolbox, only: [...]` then `import Toolbox, except: [...]` in Narrowed; Widened has the
#                   `except:` alone — the CONTROL where except applies to every function
#   lib/ring.ex     a TOP-LEVEL Ring.Core — the decoy a dotted nested declaration's later caller must not reach
#   lib/shell.ex    `defmodule Ring.Core` nested in Shell, called before and after its declaration, by full name,
#                   and an undotted nested Plain as the control
#   lib/shape.ex    `defimpl Shape, for: [Disc, Box]` with `alias __MODULE__, as: Current`; `__MODULE__.measure`
#                   and a literal `Shape.Disc.measure` are the controls
#   lib/seeds.ex    `&_seed/0`, the bare capture of an underscore-named function; the remote capture, the plain
#                   call and an `_seed` PARAMETER read are the controls
#   lib/dflt.ex     a bodyless `def f(x \\ default())` head over two clauses; `f()` omits the argument,
#                   `f(1)` supplies it, `g(x \\ default()), do: x` is the head-with-body control
#
# Arms (each a resolution rule of Kernel.SpecialForms / Kernel, reproduced against Elixir 1.20.3 / OTP 29):
#   (G) `import M, except: [...]` after `import M, only: [...]` SUBTRACTS from the only-list in force (import/2:
#       ":except is always exclusive on a previously declared import"); it does not replace it. A function absent
#       from the only-list stays un-imported — no edge, and the refusal is COUNTED in the header. With no earlier
#       import, except applies to all of M's functions.
#   (H) `defmodule Inner.Deep` nested in Outer defines Outer.Inner.Deep AND aliases its FIRST segment, Inner ->
#       Outer.Inner, in the enclosing scope from that point on (defmodule/2, nesting). A later `Inner.Deep.f()`
#       names the nested module even when a top-level Inner.Deep exists; an earlier one still names the top-level
#       module; with no top-level module the later call resolves instead of being dropped.
#   (I) inside a multi-target defimpl, `alias __MODULE__, as: Current` is `__MODULE__` under another name: each
#       implementation's `Current.f()` reaches its OWN f, exactly as `__MODULE__.f()` already does; a literal
#       `Proto.A.f()` stays literal in every implementation.
#   (J) `&_seed/0` names a function: the leading underscore marks an unused VARIABLE, and a named capture is never
#       one. The remote capture and the plain call already resolved; an `_seed` parameter read still does not.
#   (K) a call that OMITS a defaulted argument reaches the bodyless head that declares the default (the only symbol
#       that calls the default expression), so `--path` and `--impact` see the caller through it; a call that
#       supplies the argument never evaluates the default and keeps reaching the clauses alone.
#
# Usage:  test/elixirnamearitycheck.sh   |   RIPWIRE_BIN=asan/ripwire test/elixirnamearitycheck.sh
# Exit:   0 = clean · 1 = an arm failed · 2 = usage / missing prerequisite

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/elixirnamearityfix"
FIX2="$ROOT/test/elixirresolvefix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$FIX" ] || { echo "no test/elixirnamearityfix — fixture missing"; exit 2; }
[ -d "$FIX2" ] || { echo "no test/elixirresolvefix — fixture missing"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "elixirnamearitycheck: BIN=$BIN  FIX=$FIX  FIX2=$FIX2"

mkdir -p "$TMP/cache"
export XDG_CACHE_HOME="$TMP/cache"     # every quality/ingest blob this gate writes stays inside its own tmp dir
cp -R "$FIX" "$TMP/fix"
F="$TMP/fix"
cp -R "$FIX2" "$TMP/resolve"
R="$TMP/resolve"

# callees of the symbol whose canonical id ends with $2, from the map in $1 — one sorted line, empty when none
callees(){
    python3 - "$1" "$2" <<'PY'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
for s in root.iter('s'):
    if (s.get('id') or '').endswith(sys.argv[2]):
        print(' '.join(sorted(c.get('n') for c in s.iter('c'))))
PY
}
header_unresolved(){ grep -oE 'unresolved=[0-9]+' "$1" | head -1; }

"$BIN" "$F" --no-cache >"$TMP/map.xml" 2>/dev/null

# ── (A) a use-delivered call: no lexical candidate → no edge, and the drop is COUNTED ───────────────────
[ "$( callees "$TMP/map.xml" '::Page::index/1' )" = "" ] \
    && ok "(A) index/1's use-delivered text/2 call minted NO edge (no lexical candidate, no name-ladder fallback)" \
    || no "(A) index/1 gained an edge without a lexical candidate: $( callees "$TMP/map.xml" '::Page::index/1' )"
[ "$( header_unresolved "$TMP/map.xml" )" = "unresolved=1" ] \
    && ok "(A) the map header counts the one use-delivered drop: unresolved=1 (missing/1's undefined call is not in it)" \
    || no "(A) the use-delivered drop is not disclosed in the header: $( header_unresolved "$TMP/map.xml" ) (expected unresolved=1)"
"$BIN" "$F" --callers=text/2 --no-cache >"$TMP/callers_text.xml" 2>/dev/null
grep -q '<callers of="text/2" defs="1" count="0"' "$TMP/callers_text.xml" && grep -q 'graph_unresolved="1"' "$TMP/callers_text.xml" \
    && ok "(A) --callers=text/2: count=0 beside graph_unresolved=1 — the answer says a call was refused, not that none exists" \
    || no "(A) --callers=text/2 root wrong: $( grep -oE '<callers [^>]*>' "$TMP/callers_text.xml" )"
# mutation 1: no definition spells text/2 any more → the call is UNDEFINED, which has no header surface → 0
cp -R "$F" "$TMP/undefined"
python3 - "$TMP/undefined/lib/web.ex" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert 'def text(conn, body), do: {conn, body}' in s
p.write_text(s.replace('def text(conn, body), do: {conn, body}', 'def renamed(conn, body), do: {conn, body}'))
PY
grep -q 'def renamed' "$TMP/undefined/lib/web.ex" || no "(A) mutation 1 did not take"
"$BIN" "$TMP/undefined" --no-cache >"$TMP/undefined.xml" 2>/dev/null
[ "$( header_unresolved "$TMP/undefined.xml" )" = "unresolved=0" ] \
    && ok "(A) mutation: with no definition spelling text/2 the drop is undefined — unresolved=0" \
    || no "(A) mutation: an undefined name was counted as unresolved: $( header_unresolved "$TMP/undefined.xml" )"
# mutation 2: the lexical import appears → the same call resolves, the edge exists, the count is gone
cp -R "$F" "$TMP/imported"
python3 - "$TMP/imported/lib/page.ex" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert '  use Web\n' in s
p.write_text(s.replace('  use Web\n', '  use Web\n  import Web.Helpers\n'))
PY
grep -q 'import Web.Helpers' "$TMP/imported/lib/page.ex" || no "(A) mutation 2 did not take"
"$BIN" "$TMP/imported" --no-cache >"$TMP/imported.xml" 2>/dev/null
[ "$( callees "$TMP/imported.xml" '::Page::index/1' )" = "text/2" ] && [ "$( header_unresolved "$TMP/imported.xml" )" = "unresolved=0" ] \
    && ok "(A) mutation: the lexical import makes the same call resolve — edge index/1 -> text/2, unresolved=0" \
    || no "(A) mutation: the imported call did not resolve: callees='$( callees "$TMP/imported.xml" '::Page::index/1' )' $( header_unresolved "$TMP/imported.xml" )"

# ── (B) a pattern binding on the right of `=` is not a call ─────────────────────────────────────────────
for fn in join/2 pick/1 unwrap/1; do
    [ "$( callees "$TMP/map.xml" "::Channel::$fn" )" = "" ] \
        && ok "(B) $fn: \`%Channel{} = socket\` binds socket; the body read is not a socket/0 call" \
        || no "(B) $fn: the pattern-bound socket became a call: $( callees "$TMP/map.xml" "::Channel::$fn" )"
done
for fn in rhs/0 bare_rhs/0; do
    [ "$( callees "$TMP/map.xml" "::Channel::$fn" )" = "socket/0" ] \
        && ok "(B) control $fn: the right side of a body match is a call — the socket/0 edge stays" \
        || no "(B) control $fn lost its socket/0 edge: '$( callees "$TMP/map.xml" "::Channel::$fn" )'"
done
"$BIN" "$F" --callers=socket/0 --no-cache >"$TMP/callers_socket.xml" 2>/dev/null
grep -q '<callers of="socket/0" defs="1" count="2"' "$TMP/callers_socket.xml" \
    && ! grep -qE 'n="(join/2|pick/1|unwrap/1)"' "$TMP/callers_socket.xml" \
    && ok "(B) --callers=socket/0: count=2 (rhs/0, bare_rhs/0) — no pattern binding among the callers" \
    || no "(B) --callers=socket/0 wrong: $( grep -oE '<callers [^>]*>|<s [^>]*/>' "$TMP/callers_socket.xml" | tr '\n' ' ' )"

# ── (C) --edit-check across an arity change ─────────────────────────────────────────────────────────────
W="$TMP/repo"; mkdir -p "$W"; cp -R "$F/lib" "$W/lib"
( cd "$W" && git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -qm init >/dev/null 2>&1 )
ec(){ ( cd "$W" && "$BIN" . --edit-check=run --no-cache 2>/dev/null ); }
rows(){ printf '%s' "$1" | grep -oE '<c [^>]*/>'; }
OUT0="$( ec )"
printf '%s' "$OUT0" | grep -q 'status="unchanged"' && printf '%s' "$OUT0" | grep -q 'callers="3" incompatible="0"' \
    && ok "(C) clean tree: --edit-check=run -> unchanged, 3 callers (bare, imported, qualified), none flagged" \
    || no "(C) clean tree wrong: $( printf '%s' "$OUT0" | grep -oE '<edit-check [^>]*>' )"
python3 - "$W/lib/work.ex" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert 'def run(x), do: x\n' in s
p.write_text(s.replace('def run(x), do: x\n', 'def run(x, y), do: {x, y}\n'))
PY
grep -q 'def run(x, y)' "$W/lib/work.ex" || no "(C) the arity edit did not take"
OUT1="$( ec )"
printf '%s' "$OUT1" | grep -q 'status="contract-change"' && printf '%s' "$OUT1" | grep -q 'params_was="1" params_now="2"' \
    && printf '%s' "$OUT1" | grep -q 'defs_was="1" defs_now="1" change="params,broken-callers"' \
    && ok "(C) run(x) -> run(x, y): contract-change on the logical symbol, params 1 -> 2, change=params,broken-callers" \
    || no "(C) the arity change is not a contract change: $( printf '%s' "$OUT1" | grep -oE '<edit-check [^>]*>' )"
printf '%s' "$OUT1" | grep -q 'callers="3" incompatible="3"' \
    && ok "(C) every caller of the OLD arity is listed and flagged: callers=3 incompatible=3" \
    || no "(C) callers of the old arity were lost: $( printf '%s' "$OUT1" | grep -oE 'callers="[0-9]+" incompatible="[0-9]+"' )"
rows "$OUT1" | grep -q 'n="go/1" p="lib/client.ex:4" incompatible="1" sites_l="4"' \
    && rows "$OUT1" | grep -q 'n="remote/1" p="lib/client.ex:6" incompatible="1" sites_l="6"' \
    && rows "$OUT1" | grep -q 'n="generate_app/1" p="lib/work.ex:5" incompatible="1" sites_l="5"' \
    && ok "(C) the imported, the module-qualified and the same-module bare caller each carry incompatible=1 and its call-site line" \
    || { no "(C) flagged caller rows wrong:"; rows "$OUT1" | sed 's/^/        | /'; }
printf '%s' "$OUT1" | grep -q '<edit-check sym="run/2"' \
    && ok "(C) the document names the definition as it stands (sym=run/2) while the contract is compared as run" \
    || no "(C) sym= wrong: $( printf '%s' "$OUT1" | grep -oE '<edit-check sym="[^"]*"' )"
# the same question through --quality-delta: the widened function is ONE identity that got WORSE — every
# caller still spells run/1, so `run` went from called to uncalled and the dead-code kind gates on it as
# preexisting-worse — never a dead old symbol beside a brand-new one, which is what the arity-carrying key
# reported (new-symbol="1", nothing gating). The document names the definition as it stands (run/2).
QD="$( cd "$W" && "$BIN" . --quality-delta --legend=compact --no-cache 2>/dev/null )"
printf '%s' "$QD" | grep -q 'preexisting-worse="1" new-symbol="0" gating="1"' \
    && printf '%s' "$QD" | grep -q '<r kind="dead-code" sym="lib/work.ex::Work::run/2" p="lib/work.ex:3" gating="1"' \
    && ! printf '%s' "$QD" | grep -q 'origin="new-symbol"' \
    && ok "(C) --quality-delta: the widened run is its own preexisting identity, gating as newly dead (every caller still spells run/1), not a new-symbol" \
    || no "(C) --quality-delta still splits the identity: $( printf '%s' "$QD" | grep -oE '<quality-delta [^>]*>|<r [^>]*/?>' | tr '\n' ' ' )"
# sound side: a DEFAULT has no fixed arity, so the old-arity callers still bind and none may be flagged
python3 - "$W/lib/work.ex" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert 'def run(x, y), do: {x, y}\n' in s
p.write_text(s.replace('def run(x, y), do: {x, y}\n', 'def run(x, y \\\\ 1), do: {x, y}\n'))
PY
grep -q 'def run(x, y \\\\ 1)' "$W/lib/work.ex" || no "(C) the default-argument edit did not take"
OUT2="$( ec )"
printf '%s' "$OUT2" | grep -q 'status="contract-change"' && printf '%s' "$OUT2" | grep -q 'params_was="1" params_now="2"' \
    && printf '%s' "$OUT2" | grep -q 'callers="3" incompatible="0"' \
    && ok "(C) run(x, y \\\\ 1): still a contract change (params 1 -> 2) but NO caller flagged — a default is not a fixed arity" \
    || no "(C) default-argument widening wrong: $( printf '%s' "$OUT2" | grep -oE '<edit-check [^>]*>' )"

# ── (D) --for by exact name ─────────────────────────────────────────────────────────────────────────────
"$BIN" "$F" --for=generate_app --no-cache >"$TMP/for_snake.xml" 2>/dev/null
firstd(){ grep -oE '<d [^>]*>' "$1" | head -1 | grep -oE ' n="[^"]*"'; }
[ "$( firstd "$TMP/for_snake.xml" )" = ' n="generate_app/1"' ] && ! grep -q 'reason="no_candidates"' "$TMP/for_snake.xml" \
    && ok "(D) --for=generate_app ranks generate_app/1 first (no no_candidates)" \
    || no "(D) --for=generate_app: first row $( firstd "$TMP/for_snake.xml" ); ctx $( grep -oE 'reason="[^"]*"' "$TMP/for_snake.xml" | head -1 )"
# the fixture copy is scanned by an absolute path, so the evidence is the elided form `<top>/.../work.ex`
# (lexical.h routeAnchorPath); what matters is that it is a FILE, not the literal `syntax` of a name-less hit
grep -qE 'route="routed: name-exact BM25[^"]*anchors: generate_app\([^)]*work\.ex\)' "$TMP/for_snake.xml" \
    && ok "(D) the name-exact route's anchor evidence names the defining file (not \`syntax\`)" \
    || no "(D) anchor evidence wrong: $( grep -oE 'route="[^"]*"' "$TMP/for_snake.xml" | head -1 )"
"$BIN" "$F" --for=text --no-cache >"$TMP/for_word.xml" 2>/dev/null
grep -q 'route="routed: name-exact BM25' "$TMP/for_word.xml" && [ "$( firstd "$TMP/for_word.xml" )" = ' n="text/2"' ] \
    && ok "(D) --for=text: the plain word is a whole-name hit through the arity-less spelling — name-exact route, text/2 first" \
    || no "(D) --for=text: route $( grep -oE 'route="[^ ]* [^ ]*' "$TMP/for_word.xml" | head -1 ) first $( firstd "$TMP/for_word.xml" )"
"$BIN" "$F" --for=text/2 --no-cache >"$TMP/for_arity.xml" 2>/dev/null
[ "$( firstd "$TMP/for_arity.xml" )" = ' n="text/2"' ] \
    && ok "(D) --for=text/2: the explicit name/N spelling still ranks its symbol first" \
    || no "(D) --for=text/2 first row: $( firstd "$TMP/for_arity.xml" )"

# ── (E) use-sites: nested-module import and same-named attribute reads (reachesAny) ─────────────────────
"$BIN" "$F" --uses=Outer.Inner --no-cache >"$TMP/uses_inner.xml" 2>/dev/null
grep -q '<u role="import" p="lib/user.ex:2" in_id="User"/>' "$TMP/uses_inner.xml" \
    && ok "(E) --uses=Outer.Inner lists the \`alias Outer.Inner\` import row of the nested module" \
    || no "(E) nested-module import row missing: $( grep -oE '<u [^>]*/>' "$TMP/uses_inner.xml" | tr '\n' ' ' )"
"$BIN" "$F" '--uses=Attrs.A::@limit' --no-cache >"$TMP/uses_limit.xml" 2>/dev/null
grep -q 'count="1"' "$TMP/uses_limit.xml" && grep -q '<u role="read" p="lib/outer.ex:11" in_id="lib/outer.ex::Attrs.A::limit/0"/>' "$TMP/uses_limit.xml" \
    && ! grep -q 'Attrs.B' "$TMP/uses_limit.xml" \
    && ok "(E) --uses=Attrs.A::@limit: one read row, Attrs.B's same-named @limit kept apart by the qualifier" \
    || no "(E) attribute read rows wrong: $( grep -oE '<uses [^>]*>|<u [^>]*/>' "$TMP/uses_limit.xml" | tr '\n' ' ' )"

# ── (F) determinism, well-formed XML ────────────────────────────────────────────────────────────────────
"$BIN" "$F" --no-cache >"$TMP/map2.xml" 2>/dev/null
if cmp -s "$TMP/map.xml" "$TMP/map2.xml"; then ok "(F) deterministic (two --no-cache runs identical)"; else no "(F) non-deterministic"; fi
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/map.xml" 2>/dev/null; then ok "(F) xml well-formed"; else no "(F) xml malformed"; fi
else
    ok "(F) xml well-formed (xmllint absent — skipped)"
fi

# ═══ the resolution-rule fixture (test/elixirresolvefix) — its own crawl, see the header ═════════════════
"$BIN" "$R" --no-cache >"$TMP/resolve.xml" 2>/dev/null
# the rows the arms below assert on, or the assertions cannot fail (a vanishing probe target)
for probe in 'import Toolbox, except: [flatten: 1]' 'defmodule Ring.Core do' 'alias __MODULE__, as: Current' '&_seed/0' 'def f(x \\ default())'; do
    grep -rqF -- "$probe" "$R/lib" || no "(G-K) the fixture no longer spells the probe target: $probe"
done
# --uses in_id rows of one symbol, sorted, one per line
use_ids(){ grep -oE 'in_id="[^"]*"' "$1" | sort; }
# the p= of every callee row of $2, sorted onto one line
callee_ps(){ "$BIN" "$R" "--callees=$1" --no-cache 2>/dev/null | grep -oE '<s [^>]*/>' | grep -oE 'p="[^"]*"' | sort | tr '\n' ' ' | sed 's/ $//'; }

# ── (G) import M, except: [...] after import M, only: [...] subtracts; it does not replace ──────────────
[ "$( callees "$TMP/resolve.xml" '::Narrowed::c_never/1' )" = "" ] \
    && ok "(G) Narrowed.c_never/1: never/1 was outside the only-list and the later except: kept it out — no edge" \
    || no "(G) Narrowed.c_never/1 gained an edge the only-list never admitted: $( callees "$TMP/resolve.xml" '::Narrowed::c_never/1' )"
[ "$( header_unresolved "$TMP/resolve.xml" )" = "unresolved=3" ] \
    && ok "(G) the refused never/1 call is COUNTED beside the two excluded flatten/1 calls: unresolved=3" \
    || no "(G) the refused call is not disclosed in the header: $( header_unresolved "$TMP/resolve.xml" ) (expected unresolved=3)"
[ "$( callees "$TMP/resolve.xml" '::Narrowed::c_keyfind/1' )" = "keyfind/1" ] && [ "$( callees "$TMP/resolve.xml" '::Narrowed::c_flatten/1' )" = "" ] \
    && ok "(G) control: keyfind/1 (only-listed, not excepted) resolves; flatten/1 (only-listed, then excepted) does not" \
    || no "(G) control wrong: keyfind='$( callees "$TMP/resolve.xml" '::Narrowed::c_keyfind/1' )' flatten='$( callees "$TMP/resolve.xml" '::Narrowed::c_flatten/1' )'"
[ "$( callees "$TMP/resolve.xml" '::Widened::c_never/1' )" = "never/1" ] && [ "$( callees "$TMP/resolve.xml" '::Widened::c_flatten/1' )" = "" ] \
    && ok "(G) control: except: with no earlier import admits every other function — Widened.c_never/1 -> never/1, flatten/1 out" \
    || no "(G) control wrong: Widened never='$( callees "$TMP/resolve.xml" '::Widened::c_never/1' )' flatten='$( callees "$TMP/resolve.xml" '::Widened::c_flatten/1' )'"

# ── (H) a dotted nested defmodule aliases its first segment in the enclosing scope ──────────────────────
[ "$( callee_ps 'Shell::late/0' )" = 'p="lib/shell.ex:6"' ] \
    && ok "(H) Shell.late/0 (after the declaration): Ring.Core.spin() names the nested Shell.Ring.Core, not the top-level decoy" \
    || no "(H) Shell.late/0 reached the wrong spin/0: $( callee_ps 'Shell::late/0' ) (expected lib/shell.ex:6)"
"$BIN" "$R" '--callers=lib/ring.ex:spin/0' --no-cache >"$TMP/callers_top_spin.xml" 2>/dev/null
grep -q '<callers of="lib/ring.ex:spin/0" defs="1" count="1"' "$TMP/callers_top_spin.xml" && grep -q 'n="early/0"' "$TMP/callers_top_spin.xml" \
    && ok "(H) the top-level Ring.Core.spin/0 keeps exactly one caller, early/0 — the call written before the declaration" \
    || no "(H) top-level spin/0 callers wrong: $( grep -oE '<callers [^>]*>|<s [^>]*/>' "$TMP/callers_top_spin.xml" | tr '\n' ' ' )"
[ "$( callee_ps 'Shell::early/0' )" = 'p="lib/ring.ex:3"' ] \
    && ok "(H) control: Shell.early/0 (before the declaration) still names the top-level Ring.Core — source order" \
    || no "(H) control: early/0 wrong: $( callee_ps 'Shell::early/0' )"
[ "$( callee_ps 'Shell::full/0' )" = 'p="lib/shell.ex:6"' ] && [ "$( callee_ps 'Shell::plain/0' )" = 'p="lib/shell.ex:14"' ] \
    && ok "(H) control: the full name Shell.Ring.Core and the undotted nested Plain resolve as before" \
    || no "(H) control wrong: full=$( callee_ps 'Shell::full/0' ) plain=$( callee_ps 'Shell::plain/0' )"
# mutation: no top-level Ring.Core at all — the later call must resolve to the nested module, never drop
cp -R "$R" "$TMP/nodecoy" && rm "$TMP/nodecoy/lib/ring.ex"
[ ! -e "$TMP/nodecoy/lib/ring.ex" ] || no "(H) mutation did not take"
"$BIN" "$TMP/nodecoy" --no-cache >"$TMP/nodecoy.xml" 2>/dev/null
[ "$( callees "$TMP/nodecoy.xml" '::Shell::late/0' )" = "spin/0" ] && [ "$( callees "$TMP/nodecoy.xml" '::Shell::early/0' )" = "" ] \
    && ok "(H) mutation: without the decoy, late/0 -> spin/0 through the nested module; early/0 (before it) has nothing to name" \
    || no "(H) mutation: late='$( callees "$TMP/nodecoy.xml" '::Shell::late/0' )' early='$( callees "$TMP/nodecoy.xml" '::Shell::early/0' )'"

# ── (I) alias __MODULE__, as: Current inside a multi-target defimpl ─────────────────────────────────────
"$BIN" "$R" --uses=Shape.Disc::measure/1 --no-cache >"$TMP/uses_disc.xml" 2>/dev/null
"$BIN" "$R" --uses=Shape.Box::measure/1 --no-cache >"$TMP/uses_box.xml" 2>/dev/null
use_ids "$TMP/uses_disc.xml" | grep -q '::Shape.Disc::area/1"' && ! use_ids "$TMP/uses_disc.xml" | grep -q '::Shape.Box::area/1"' \
    && use_ids "$TMP/uses_box.xml" | grep -q '::Shape.Box::area/1"' && ! use_ids "$TMP/uses_box.xml" | grep -q '::Shape.Disc::area/1"' \
    && ok "(I) Current.measure(x): Shape.Disc.area/1 -> Shape.Disc.measure/1 and Shape.Box.area/1 -> Shape.Box.measure/1 — each its own" \
    || no "(I) Current.measure(x) crossed implementations: disc=[$( use_ids "$TMP/uses_disc.xml" | tr '\n' ' ' )] box=[$( use_ids "$TMP/uses_box.xml" | tr '\n' ' ' )]"
use_ids "$TMP/uses_disc.xml" | grep -q '::Shape.Disc::own/1"' && ! use_ids "$TMP/uses_disc.xml" | grep -q '::Shape.Box::own/1"' \
    && use_ids "$TMP/uses_box.xml" | grep -q '::Shape.Box::own/1"' && ! use_ids "$TMP/uses_box.xml" | grep -q '::Shape.Disc::own/1"' \
    && ok "(I) control: the literal __MODULE__.measure(x) resolves per implementation" \
    || no "(I) control: __MODULE__ crossed implementations: disc=[$( use_ids "$TMP/uses_disc.xml" | tr '\n' ' ' )] box=[$( use_ids "$TMP/uses_box.xml" | tr '\n' ' ' )]"
use_ids "$TMP/uses_disc.xml" | grep -q '::Shape.Disc::literal/1"' && use_ids "$TMP/uses_disc.xml" | grep -q '::Shape.Box::literal/1"' \
    && ! use_ids "$TMP/uses_box.xml" | grep -q 'literal/1"' \
    && ok "(I) control: a literal Shape.Disc.measure(x) stays literal — both implementations' literal/1 reach Shape.Disc.measure/1 only" \
    || no "(I) control: the literal receiver moved: disc=[$( use_ids "$TMP/uses_disc.xml" | tr '\n' ' ' )] box=[$( use_ids "$TMP/uses_box.xml" | tr '\n' ' ' )]"

# ── (J) &_seed/0 names a function ───────────────────────────────────────────────────────────────────────
[ "$( callees "$TMP/resolve.xml" '::Seeds::by_capture/0' )" = "_seed/0" ] \
    && ok "(J) by_capture/0: the bare capture &_seed/0 -> _seed/0" \
    || no "(J) by_capture/0 has no _seed/0 edge: '$( callees "$TMP/resolve.xml" '::Seeds::by_capture/0' )'"
"$BIN" "$R" --callers=Seeds::_seed/0 --no-cache >"$TMP/callers_seed.xml" 2>/dev/null
grep -q '<callers of="Seeds::_seed/0" defs="1" count="3"' "$TMP/callers_seed.xml" && grep -q 'n="by_capture/0"' "$TMP/callers_seed.xml" \
    && ok "(J) --callers=Seeds::_seed/0: count=3 — the bare capture, the remote capture and the plain call" \
    || no "(J) --callers=Seeds::_seed/0 wrong: $( grep -oE '<callers [^>]*>|<s [^>]*/>' "$TMP/callers_seed.xml" | tr '\n' ' ' )"
[ "$( callees "$TMP/resolve.xml" '::Seeds::by_remote_capture/0' )" = "_seed/0" ] && [ "$( callees "$TMP/resolve.xml" '::Seeds::by_call/0' )" = "_seed/0" ] \
    && ok "(J) control: &Seeds._seed/0 and the plain _seed() call resolve" \
    || no "(J) control lost an edge: remote='$( callees "$TMP/resolve.xml" '::Seeds::by_remote_capture/0' )' call='$( callees "$TMP/resolve.xml" '::Seeds::by_call/0' )'"
[ "$( callees "$TMP/resolve.xml" '::Seeds::by_parameter/1' )" = "" ] \
    && ok "(J) control: the _seed PARAMETER read in by_parameter/1 is a variable — no _seed/0 edge" \
    || no "(J) control: an underscore parameter read became a call: $( callees "$TMP/resolve.xml" '::Seeds::by_parameter/1' )"

# ── (K) a call that omits a defaulted argument reaches the bodyless head ────────────────────────────────
"$BIN" "$R" --path=caller/0,default/0 --no-cache >"$TMP/path_caller.xml" 2>/dev/null
grep -q '<path from="caller/0" to="default/0" [^>]*reachable="1"' "$TMP/path_caller.xml" \
    && ok "(K) --path=caller/0,default/0: f() omits the argument, so default/0 is reachable through the head" \
    || no "(K) --path=caller/0,default/0 unreachable: $( grep -oE '<path [^>]*>' "$TMP/path_caller.xml" | grep -oE 'reachable="[0-9]"' )"
"$BIN" "$R" --impact=default/0 --no-cache >"$TMP/impact_default.xml" 2>/dev/null
grep -q 'n="caller/0"' "$TMP/impact_default.xml" && ! grep -q 'n="caller_explicit/0"' "$TMP/impact_default.xml" \
    && ok "(K) --impact=default/0 lists caller/0 and not caller_explicit/0" \
    || no "(K) --impact=default/0 wrong: $( grep -oE '<s [^>]*/>' "$TMP/impact_default.xml" | tr '\n' ' ' )"
[ "$( callee_ps 'Dflt::caller/0' )" = 'p="lib/dflt.ex:5" p="lib/dflt.ex:6" p="lib/dflt.ex:7"' ] \
    && ok "(K) caller/0's f() reaches the head (line 5) and both clauses" \
    || no "(K) caller/0 callees wrong: $( callee_ps 'Dflt::caller/0' )"
[ "$( callee_ps 'Dflt::caller_explicit/0' )" = 'p="lib/dflt.ex:6" p="lib/dflt.ex:7"' ] \
    && ok "(K) control: caller_explicit/0's f(1) supplies the argument — the two clauses only, never the head" \
    || no "(K) control: caller_explicit/0 callees wrong: $( callee_ps 'Dflt::caller_explicit/0' )"
"$BIN" "$R" --path=caller_explicit/0,default/0 --no-cache >"$TMP/path_explicit.xml" 2>/dev/null
"$BIN" "$R" --path=caller_g/0,default/0 --no-cache >"$TMP/path_g.xml" 2>/dev/null
grep -q '<path from="caller_explicit/0" to="default/0" [^>]*reachable="0"' "$TMP/path_explicit.xml" \
    && grep -q '<path from="caller_g/0" to="default/0" [^>]*reachable="1"' "$TMP/path_g.xml" \
    && ok "(K) control: no path from caller_explicit/0; caller_g/0 reaches default/0 through the head that has a body" \
    || no "(K) control paths wrong: explicit $( grep -oE 'reachable="[0-9]"' "$TMP/path_explicit.xml" ) g $( grep -oE 'reachable="[0-9]"' "$TMP/path_g.xml" )"

# ── (F, again) determinism and well-formedness of the resolution fixture ────────────────────────────────
"$BIN" "$R" --no-cache >"$TMP/resolve2.xml" 2>/dev/null
if cmp -s "$TMP/resolve.xml" "$TMP/resolve2.xml"; then ok "(F) resolution fixture deterministic"; else no "(F) resolution fixture non-deterministic"; fi
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/resolve.xml" 2>/dev/null; then ok "(F) resolution fixture xml well-formed"; else no "(F) resolution fixture xml malformed"; fi
else
    ok "(F) resolution fixture xml well-formed (xmllint absent — skipped)"
fi

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "SOME CHECKS FAILED"; exit 1; }
