#!/usr/bin/env bash
# builtinbindcheck.sh — a call on a receiver of unproven type never binds to an in-repo method by a BUILTIN name alone.
#
#   test/builtinbindcheck.sh                          # uses build/ripwire on test/builtinbindfix
#   RIPWIRE_BIN=asan/ripwire test/builtinbindcheck.sh
#   test/builtinbindcheck.sh build_base/ripwire       # the RED run (a pre-change binary)
#
# THE DEFECT. A member call whose receiver's type no rule proved reaches buildGraph's name ladder with its spelling as the
# only evidence, and a name with ONE in-repo definition binds to it. `d.get( k )` on a dict is such a call, and so is
# `m.get( k )` on a JS Map or `h.fetch( k )` on a Ruby Hash. On a real Python corpus one `ConnectionPool.get` collected
# 611 callers that way — 5 of them real — became the default map's first symbol, and inflated every --callers, --impact
# and --test-gate answer that reached it. Rule 3's include narrow did the same one step earlier: a caller file that
# transitively imports the class's module says nothing about whether this receiver is an instance of the class.
#
# THE FIX (graph.h BuiltinMethodGate; the tables and their generator commands are in src/externalnames.h). A call whose
# name is a method of its language's builtin map, list, set or string type, and that no qualifier, import binding or
# receiver rule resolved, is decided by the UNCHANGED ladder and then POST-FILTERED: when the gate admits none of the
# ladder's targets the call loses its edge — DECLINED and counted (header declined=, declined_calls= on every verb that
# reads callers) when a target lacked evidence, EXTERNAL when every target is one the call provably cannot reach. The
# gate only ever removes: a call the ladder declined stays declined, and a kept call keeps exactly its targets. The list
# decides only WHEN evidence is required, and languages with no table keep the ladder whole (reasons in graph.h).
# Fix round (review of the first cut): that cut filtered the candidates BEFORE the ladder, so a declined two-way set
# narrowed to one admitted member and BOUND — 17,466 new edges and 10,319 retargeted over 88 repositories, most false.
#
# THE FIXTURE (test/builtinbindfix/). Per language, one in-repo method named like a builtin method, called from a file
# that names its class (the edge must SURVIVE) and from plain.* files that never do (the calls must NOT bind).
#   (A) Python true edges survive: a typed local (Rule 2), `self.pool = ConnectionPool()` then `self.pool.get()`
#       (file evidence), and an untyped parameter in a file that names a SUBCLASS (cone evidence) — exactly those three
#   (B) Python builtin calls do not bind: dict.get, a parameter's .get, os.environ.get, self.store.get — none is a
#       caller row, and all four are counted as declined_calls="4" (the RED arm on a pre-change binary)
#   (C) a nested helper `def decode( raw )` inside a method is no method: `raw.decode( "utf-8" )` elsewhere loses its
#       edge as EXTERNAL (no member call reaches a closure) and adds nothing to its declined_calls=, while the bare call
#       inside its enclosing method still binds
#   (D) control: a name OUTSIDE the table (`checkout`) still binds by name from the same plain file — the gate is not
#       a general receiver-type requirement
#   (M) control: Rule 3 still chooses between two admitted FREE functions — a bare `add( … )` in a file that imports
#       helpers/sums.py binds there and not to other/sums.py's namesake, as it did before the gate
#   (N) a member call can never reach a free function: `table.get`, `config.get`, `self.store.get` and
#       `os.environ.get` (rooted at an import from outside the tree) all skip the module-level `def get` in lookup.py,
#       which the pre-change binary split every one of them onto by directory locality — and count none of them as
#       declined against it (it is not what they could have meant)
#   (O) MONOTONE (fixture mono/): a call the ladder DECLINED stays declined — Python `cfg.update()` in a file that
#       constructs Timer (Timer.update vs Config.update), Ruby `rows.each` beside `LinkedList.new`, JS `app.has()` and
#       `m.has()` beside a free `has` — each definition keeps count="0" and its declined_calls=; the census diff against
#       the ladder's own decision has no added and no retargeted call (the first cut bound all three)
#   (P) Python `from ..d.instance import registry; registry.pop( k )`: an imported INSTANCE is no module, so the free
#       `pop` in another package gains nothing (the first cut bound it silently); Registry.pop is declined, disclosed
#   (Q) JS: `list.shift()` in a file that requires no module defining `shift` is declined; `q.shift()` on
#       `const q = require( "../b/queue" )` keeps its edge (a direct require is evidence)
#   (R) the caller-reading verbs disclose a declined caller: --edit-check, --safe-delete (beside risk=none-found, with
#       the legend sentence), --uses FILE:SYM and --test-gate each carry declined_calls="1" for dependency-injected
#       `self.pool.popitem()`; --quality-delta counts the dead-code exemption as declined-call-excluded=
#   (S) 0 bytes on a tree the gate never declined in: test/declinefix's map and --callers legends carry no gate clause
#   (E) JavaScript: Map.get and Array.push are declined; `new ConnectionPool()` in the file keeps its edge
#   (F) TypeScript: the named import carries a parameter annotated with the class (the extractor records no
#       per-parameter type there), while Map.get in a file that never names it is declined
#   (G) Ruby: Hash#fetch is declined; `RbPool.new` in the file keeps the edge
#   (H) stated scope: Java has no table (graph.h floor 5), so its Map.get keeps binding by name — the pin that makes a
#       change there deliberate rather than accidental
#   (I) the header: declined=9 in the stats comment, a full legend that defines hdr:declined= and names the builtin
#       clause, and a census whose dispositions sum to calls= with declined equal to the header's
#   (J) --impact counts the declines that could have reached the method and lists only the true callers
#   (K) the predicates can fail: a callers document carrying a plain.py row, and one without declined_calls=
#   (L) determinism x2 (map and census), xmllint, no degrade alert on stderr
#   (T) SAME-FILE decoy (a tree built in $TMP, so the fixture's counts above stay put): a Python file that DEFINES the
#       class is no evidence for a receiver other than self/cls. `data.get( "repos" )` on a json dict and
#       `entry.get( "alias" )` on a parameter in registry.py bound to ConnectionPool.get (4 of its 9 callers on the
#       corpus the gate was measured on); they are declined now, while `self.get()` and `cls.get()` inside the class
#       and the importing file's typed local keep their edges (a construction in the same file is still file-grain
#       evidence for every call there — floor 2 — so the decoy file constructs nothing). Review round: a class named
#       ANYWHERE in its own file beyond its `class` line is still evidence, because Python records no annotation as a
#       binding — a parameter, an annotated local, a string/Optional/List annotation, an annotated __init__ parameter
#       stored on self, an isinstance() narrowing and a return annotation, each in a file that defines the class,
#       must keep their edge (the first cut of this arm dropped all eight)
#
# Exits non-zero on any failure.

set -u
export PYTHONDONTWRITEBYTECODE=1
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"   # a gate that builds a repo must not inherit GIT_DIR/GIT_WORK_TREE (gitenvhermeticcheck D)
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"          # allow a repo-relative binary
CORPUS="$ROOT/test/builtinbindfix"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
[ -d "$CORPUS" ] || { echo "fixture missing: $CORPUS"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "builtinbindcheck: BIN=$BIN  CORPUS=$CORPUS"

cd "$CORPUS" || exit 2                               # every file:name selector below is relative to the root `.`
rw(){ "$BIN" . --no-cache "$@" 2>/dev/null; }

# ── helpers ───────────────────────────────────────────────────────────────────────────────────────────────────
root_tag(){ grep -oE "<$2( [^>]*)?>" "$1" | head -1; }                               # first <TAG …> start tag
attr(){ printf '%s' "$1" | grep -oE " $2=\"[^\"]*\"" | head -1 | sed -E 's/^[^"]*"([^"]*)"$/\1/'; }
# the caller rows of a callers/impact document as sorted "file:name" lines (p= without its line number)
rows(){ grep -oE '<s [^>]*/>' "$1" | python3 -c '
import re, sys
out = set()
for line in sys.stdin:
    n = re.search( r" n=\"([^\"]*)\"", line ); p = re.search( r" p=\"([^\"]*)\"", line )
    if n and p:
        out.add( p.group( 1 ).rsplit( ":", 1 )[ 0 ] + ":" + n.group( 1 ) )
print( " ".join( sorted( out ) ) )'; }
# callers(sel, want_rows, want_declined): the exact caller set and the exact declined_calls= ("" = absent)
callers_are(){
    local sel="$1" want="$2" wantd="$3" doc="${4:-}"
    if [ -z "$doc" ]; then doc="$TMP/callers.xml"; rw --callers="$sel" >"$doc"; fi
    local R got gotd; R="$( root_tag "$doc" callers )"; got="$( rows "$doc" )"; gotd="$( attr "$R" declined_calls )"
    [ -n "$R" ] && [ "$got" = "$want" ] && [ "$gotd" = "$wantd" ]
}
stats(){ grep -oE '<!-- files=[^>]*-->' "$1" | head -1; }
gauge(){ printf '%s' "$1" | grep -oE " $2=[0-9]+" | head -1 | grep -oE '[0-9]+$'; }
disp_in(){ grep -m1 '^# dispositions ' "$1" | grep -oE " $2=[0-9]+" | head -1 | grep -oE '[0-9]+$'; }
legend_of(){ python3 - "$1" <<'PY'
import re, sys
t = open( sys.argv[1] ).read()
m = re.match( r"(\s*<!--.*?-->)+", t, re.S )
print( m.group( 0 ) if m else "" )
PY
}
conserves(){ python3 - "$1" <<'PY'
import re, sys
kv = dict( ( k, int( v ) ) for k, v in re.findall( r"(\w+)=(\d+)", sys.argv[1] ) )
calls = kv.pop( "calls", None )
sys.exit( 0 if calls is not None and "unaccounted" in kv and kv[ "unaccounted" ] == 0 and sum( kv.values() ) == calls else 1 )
PY
}
check(){   # label | selector | want rows | want declined_calls
    if callers_are "$2" "$3" "$4"; then ok "$1"
    else no "$1 — got rows [$( rows "$TMP/callers.xml" )] declined_calls=\"$( attr "$( root_tag "$TMP/callers.xml" callers )" declined_calls )\""; fi
}

# the census and the full-legend map every later arm reads (O's census rows, I's header) — written FIRST, so no arm reads
# a file that does not exist yet (an awk over a missing file prints nothing, which would pass a "no row" check blind)
"$BIN" . --no-cache --pin-census="$TMP/c.tsv" --legend=full >"$TMP/map.xml" 2>"$TMP/err" || no "(I) the map run exited non-zero"
[ -s "$TMP/c.tsv" ] || no "the census run wrote no census — every census arm below would be vacuous"

# ── (A) + (B) Python ──────────────────────────────────────────────────────────────────────────────────────────
echo "=== (A)(B) Python: the evidenced callers stay, the builtin calls are declined and counted ==="
PYGET='py/uses_pool.py:true_field py/uses_pool.py:true_local py/uses_smart.py:via_subclass'
check "(A)+(B) --callers=py/pool.py:get is exactly the typed local, the self.pool field and the subclass-evidenced parameter; declined_calls=\"4\"" \
      py/pool.py:get "$PYGET" 4
rows "$TMP/callers.xml" | grep -q 'py/plain.py' \
    && no "(B) a plain.py call (dict/param/environ/self.store .get) is still a caller of ConnectionPool.get" \
    || ok "(B) no plain.py function is a caller of ConnectionPool.get"

# ── (C) the nested helper ─────────────────────────────────────────────────────────────────────────────────────
echo "=== (C) a nested helper is no method ==="
check "(C) --callers=py/pool.py:decode is only its enclosing render; raw.decode(\"utf-8\") is external, not declined against it" \
      py/pool.py:decode 'py/pool.py:render' ''

# ── (D) control: a name outside the table keeps the ladder ────────────────────────────────────────────────────
echo "=== (D) control: a non-builtin name still binds by name ==="
check "(D) --callers=py/pool.py:checkout keeps untyped_checkout (not a builtin name: the ladder is unchanged)" \
      py/pool.py:checkout 'py/plain.py:untyped_checkout' ''

# ── (M) (N) free functions ────────────────────────────────────────────────────────────────────────────────────
echo "=== (M)(N) free functions: Rule 3 still chooses among admitted ones; a member call reaches none ==="
check "(M) --callers=py/helpers/sums.py:add is the importing bare call (Rule 3 over the admitted free functions)" \
      py/helpers/sums.py:add 'py/uses_add.py:total' ''
check "(M) --callers=py/other/sums.py:add has no caller and no decline (the import chose its namesake)" py/other/sums.py:add '' ''
check "(N) --callers=py/lookup.py:get has no caller and no declined_calls=: no member .get call can mean a free function" \
      py/lookup.py:get '' ''

# ── (O) (P) (Q) monotone: the gate never binds what the ladder declined ────────────────────────────────────────
echo "=== (O)(P)(Q) the gate only removes: declined stays declined; an imported instance is no module; JS require evidence ==="
check "(O) py: --callers=mono/py/a/timer.py:update stays count=\"0\" declined_calls=\"1\" (the ladder declined cfg.update between two classes)" \
      mono/py/a/timer.py:update '' 1
check "(O) py: --callers=mono/py/b/config.py:update stays count=\"0\" declined_calls=\"1\"" mono/py/b/config.py:update '' 1
check "(O) rb: --callers=mono/rb/a/list.rb:each stays count=\"0\" declined_calls=\"1\" beside LinkedList.new" mono/rb/a/list.rb:each '' 1
check "(O) rb: --callers=mono/rb/b/tree.rb:each stays count=\"0\" declined_calls=\"1\"" mono/rb/b/tree.rb:each '' 1
check "(O) js: --callers=mono/js/b/helpers.js:has stays count=\"0\" declined_calls=\"2\" (app.has and m.has)" mono/js/b/helpers.js:has '' 2
check "(O) js: --callers=mono/js/a/pool.js:has stays count=\"0\" declined_calls=\"2\"" mono/js/a/pool.js:has '' 2
if awk -F'\t' '$1=="C" && $6 ~ /^mono\// && ( $7=="update" || $7=="each" || $7=="has" )' "$TMP/c.tsv" | grep -q .; then
    no "(O) a census decision row binds update/each/has in mono/ — the gate bound a call the ladder declined"
else
    ok "(O) no census decision row for update/each/has in mono/: nothing bound that the ladder declined"
fi
check "(P) --callers=mono/py/e/util.py:pop has no caller and no declined_calls=: registry (an imported instance) is not the util module" \
      mono/py/e/util.py:pop '' ''
check "(P) --callers=mono/py/d/registry.py:pop: the Rule-3 edge the file gives no class evidence for is declined, disclosed" \
      mono/py/d/registry.py:pop '' 1
check "(Q) js: --callers=mono/js/b/queue.js:shift keeps q.shift() on a direct require; list.shift() is declined_calls=\"1\"" \
      mono/js/b/queue.js:shift 'mono/js/c/uses_queue.js:head' 1

# ── (R) the caller-reading verbs disclose a declined caller ───────────────────────────────────────────────────
echo "=== (R) edit-check, safe-delete, uses FILE:SYM, test-gate and quality-delta disclose the declined caller ==="
for spec in "edit-check|--edit-check=mono/py/e/pool.py:popitem" "safe-delete|--safe-delete=mono/py/e/pool.py:popitem" \
            "uses|--uses=mono/py/e/pool.py:popitem" "test-gate|--test-gate=mono/py/e/pool.py" "callers|--callers=mono/py/e/pool.py:popitem"; do
    tag="${spec%%|*}"; flag="${spec#*|}"
    rw "$flag" --legend=full >"$TMP/r.xml"
    R="$( root_tag "$TMP/r.xml" "$tag" )"
    if [ "$( attr "$R" declined_calls )" = 1 ] && legend_of "$TMP/r.xml" | grep -q 'declined_calls=K (absent when 0)'; then
        ok "(R) $flag carries declined_calls=\"1\" and its legend defines it"
    else
        no "(R) $flag: no declined_calls=\"1\" or no definition: ${R:-no <$tag> root}"
    fi
done
rw --safe-delete=mono/py/e/pool.py:popitem --legend=full >"$TMP/sd.xml"
if [ "$( attr "$( root_tag "$TMP/sd.xml" safe-delete )" risk )" = none-found ] && legend_of "$TMP/sd.xml" | grep -q 'none-found beside declined_calls= is not a safety reading'; then
    ok "(R) --safe-delete: risk=none-found is qualified by the declined_calls= sentence"
else
    no "(R) --safe-delete: risk=none-found stands unqualified beside declined_calls="
fi
QD="$TMP/qd"; rm -rf "$QD"; mkdir -p "$QD"; cp -R mono "$QD/" 2>/dev/null
( cd "$QD" && git init -q && git -c user.name=t -c user.email=t@t add -A && git -c user.name=t -c user.email=t@t commit -qm base ) >/dev/null 2>&1
printf '\n' >>"$QD/mono/py/c/service.py"
( cd "$QD" && "$BIN" . --no-cache --quality-delta >"$TMP/qd.xml" 2>/dev/null )
QR="$( root_tag "$TMP/qd.xml" quality-delta )"
if [ -n "$( attr "$QR" declined-call-excluded )" ] && [ "$( attr "$QR" declined-call-excluded )" -ge 1 ] 2>/dev/null; then
    ok "(R) --quality-delta counts the dead-code exemption: declined-call-excluded=\"$( attr "$QR" declined-call-excluded )\""
else
    no "(R) --quality-delta carries no declined-call-excluded= count: ${QR:-no <quality-delta> root}"
fi

# ── (S) no bytes where the gate declined nothing ──────────────────────────────────────────────────────────────
echo "=== (S) a tree the gate never declined in carries no gate clause ==="
DF="$ROOT/test/declinefix"
"$BIN" "$DF" --no-cache --legend=full >"$TMP/df.xml" 2>/dev/null
"$BIN" "$DF" --no-cache --legend=full --callers=jbody >"$TMP/dfc.xml" 2>/dev/null
if grep -q 'declined=' "$TMP/df.xml" && ! grep -q 'also-counts-builtin' "$TMP/df.xml" && grep -q 'declined_calls=' "$TMP/dfc.xml" \
   && ! grep -q 'builtin-type method' "$TMP/dfc.xml"; then
    ok "(S) declinefix: map and --callers carry declined= / declined_calls= with no gate clause"
else
    no "(S) declinefix: the gate clause leaked onto a tree the gate declined nothing in (or the premise declined= is gone)"
fi

# ── (E) (F) (G) the other gated languages ─────────────────────────────────────────────────────────────────────
echo "=== (E)(F)(G) JavaScript, TypeScript, Ruby ==="
check "(E) --callers=js/pool.js:get is jsTrueLocal only; Map.get is declined_calls=\"1\"" js/pool.js:get 'js/uses.js:jsTrueLocal' 1
check "(E) --callers=js/pool.js:push has no caller; Array.push is declined_calls=\"1\"" js/pool.js:push '' 1
check "(F) --callers=ts/pool.ts:get keeps the import-evidenced annotated parameter; Map.get is declined_calls=\"1\"" \
      ts/pool.ts:get 'ts/uses.ts:tsAnnotated' 1
check "(G) --callers=rb/pool.rb:fetch keeps rb_true_local; Hash#fetch is declined_calls=\"1\"" rb/pool.rb:fetch 'rb/uses.rb:rb_true_local' 1

# ── (H) stated scope ──────────────────────────────────────────────────────────────────────────────────────────
echo "=== (H) stated scope: Java keeps the name ladder ==="
check "(H) --callers=java/JPool.java:get still lists javaMapGet with no declined_calls= (no Java table, graph.h floor 5)" \
      java/JPool.java:get 'java/JPlain.java:javaMapGet' ''

# ── (I) header, legend, census conservation ───────────────────────────────────────────────────────────────────
echo "=== (I) the header, its legend and the census agree ==="
HDR="$( stats "$TMP/map.xml" )"
[ "$( gauge "$HDR" declined )" = 15 ] && ok "(I) header declined=15 (8 gate declines outside mono/: four Python .get, JS Map.get and Array.push, TS Map.get, Ruby Hash#fetch; mono/: 4 ladder declines kept + pop, popitem, shift)" \
    || no "(I) header declined= should be 15: ${HDR:-no stats comment}"
# external=3 since parser version 137 (test/rubyclassrecvcheck.sh): RbPool.new and LinkedList.new are Class#new on a class
# the tree defines no initialize for, which runs BasicObject's — outside the tree
[ "$( gauge "$HDR" external )" = 3 ] && ok "(I) header external=3: raw.decode(\"utf-8\") can reach no in-repo definition (the only one is a closure); RbPool.new and LinkedList.new reach no in-tree initialize" \
    || no "(I) header external= should be 3: ${HDR:-no stats comment}"
legend_of "$TMP/map.xml" | grep -q 'hdr:declined=also-counts-builtin-type-method-calls' \
    && ok "(I) the full map legend defines hdr:declined= including the builtin-name clause" \
    || no "(I) the full map legend does not name the builtin-name decline under hdr:declined="
DISP="$( grep -m1 '^# dispositions ' "$TMP/c.tsv" )"
if conserves "$DISP"; then ok "(I) census dispositions sum to calls= with unaccounted=0: $DISP"
else no "(I) census does not conserve: ${DISP:-no dispositions line}"; fi
[ "$( disp_in "$TMP/c.tsv" declined )" = "$( gauge "$HDR" declined )" ] \
    && ok "(I) census declined= equals the header's" || no "(I) census declined=$( disp_in "$TMP/c.tsv" declined ) vs header $( gauge "$HDR" declined )"

# ── (J) impact ────────────────────────────────────────────────────────────────────────────────────────────────
echo "=== (J) --impact ==="
rw --impact=py/pool.py:get >"$TMP/impact.xml"
R="$( root_tag "$TMP/impact.xml" impact )"
[ "$( rows "$TMP/impact.xml" )" = "$PYGET" ] && [ "$( attr "$R" declined_calls )" = 4 ] && [ "$( attr "$R" reaches )" = 3 ] \
    && ok "(J) --impact=py/pool.py:get reaches=\"3\" (the three true callers) with declined_calls=\"4\"" \
    || no "(J) --impact=py/pool.py:get: ${R:-no <impact> root} rows [$( rows "$TMP/impact.xml" )]"

# ── (K) the predicates can fail ───────────────────────────────────────────────────────────────────────────────
echo "=== (K) mutation controls ==="
printf '<callers of="py/pool.py:get" count="4" declined_calls="4"><s t="fn" n="dict_get" p="py/plain.py:4"/><s t="fn" n="true_field" p="py/uses_pool.py:13"/><s t="fn" n="true_local" p="py/uses_pool.py:4"/><s t="fn" n="via_subclass" p="py/uses_smart.py:8"/></callers>' >"$TMP/mut1.xml"
callers_are py/pool.py:get "$PYGET" 4 "$TMP/mut1.xml" && no "(K) a callers document with a plain.py row passed the (A) predicate" \
    || ok "(K) a plain.py caller row turns the (A) predicate red"
printf '<callers of="py/pool.py:get" count="3"><s t="fn" n="true_field" p="py/uses_pool.py:13"/><s t="fn" n="true_local" p="py/uses_pool.py:4"/><s t="fn" n="via_subclass" p="py/uses_smart.py:8"/></callers>' >"$TMP/mut2.xml"
callers_are py/pool.py:get "$PYGET" 4 "$TMP/mut2.xml" && no "(K) a callers document without declined_calls= passed the (A) predicate" \
    || ok "(K) a silent drop (no declined_calls=) turns the (A) predicate red"

# ── (L) determinism, well-formedness, no alert ────────────────────────────────────────────────────────────────
echo "=== (L) determinism x2, xmllint, stderr ==="
"$BIN" . --no-cache --pin-census="$TMP/c2.tsv" --legend=full >"$TMP/map2.xml" 2>>"$TMP/err"
cmp -s "$TMP/map.xml" "$TMP/map2.xml" && cmp -s "$TMP/c.tsv" "$TMP/c2.tsv" && ok "(L) map and census byte-identical across two runs" \
    || no "(L) two runs differ"
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/map.xml" "$TMP/impact.xml" 2>/dev/null; then ok "(L) xmllint: map and impact well-formed"
    else no "(L) xmllint rejected an answer"; fi
fi
if [ ! -s "$TMP/err" ]; then ok "(L) nothing on stderr"
else no "(L) stderr is not empty"; sed 's/^/          /' "$TMP/err"; fi

# ── (T) same-file decoy ───────────────────────────────────────────────────────────────────────────────────────
echo "=== (T) a same-file class definition is no evidence for a non-self receiver ==="
T="$TMP/samefile"; mkdir -p "$T/pkg"
: >"$T/pkg/__init__.py"
cat >"$T/pkg/registry.py" <<'PY'
import json


def load_repos(text):
    data = json.loads(text)
    return data.get("repos", [])


def find_alias(entry):
    return entry.get("alias")


class ConnectionPool:
    def __init__(self):
        self._pool = {}

    def get(self, key):
        return self._pool.get(key)

    def warm(self, key):
        return self.get(key)

    @classmethod
    def probe(cls, key):
        return cls.get(cls, key)
PY
cat >"$T/pkg/user.py" <<'PY'
from .registry import ConnectionPool


def true_local(key):
    pool = ConnectionPool()
    return pool.get(key)
PY
# same-file annotations: one class per file, each file's own caller must keep its edge
cat >"$T/pkg/ann_param.py" <<'PY'
class PTyped:
    def get(self, key):
        return key


def caller_PTyped(p: PTyped):
    return p.get("a")
PY
cat >"$T/pkg/ann_local.py" <<'PY'
class PLocal:
    def get(self, key):
        return key


def caller_PLocal(make):
    x: PLocal = make()
    return x.get("a")
PY
cat >"$T/pkg/ann_str.py" <<'PY'
class PStr:
    def get(self, key):
        return key


def caller_PStr(p: "PStr"):
    return p.get("a")
PY
cat >"$T/pkg/ann_opt.py" <<'PY'
from typing import Optional


class POpt:
    def get(self, key):
        return key


def caller_POpt(p: Optional[POpt]):
    return p.get("a")
PY
cat >"$T/pkg/ann_list.py" <<'PY'
from typing import List


class PList:
    def get(self, key):
        return key


def caller_PList(ps: List[PList]):
    for q in ps:
        q.get("a")
PY
cat >"$T/pkg/ann_selfattr.py" <<'PY'
class PSelfAttr:
    def get(self, key):
        return key


class Holder:
    def __init__(self, pool: PSelfAttr):
        self.pool = pool

    def caller_PSelfAttr(self):
        return self.pool.get("a")
PY
cat >"$T/pkg/ann_inst.py" <<'PY'
class PInst:
    def get(self, key):
        return key


def caller_PInst(o):
    if isinstance(o, PInst):
        return o.get("a")
    return None
PY
cat >"$T/pkg/ann_ret.py" <<'PY'
class PRet:
    def get(self, key):
        return key


def make_PRet(factory) -> PRet:
    return factory()


def caller_PRet(factory):
    return make_PRet(factory).get("a")
PY
for probe in param:PTyped local:PLocal str:PStr opt:POpt list:PList selfattr:PSelfAttr inst:PInst ret:PRet; do
    pf="${probe%%:*}"; pc="${probe#*:}"
    PROWS="$( cd "$T" && "$BIN" . --no-cache --callers=pkg/ann_$pf.py:get 2>/dev/null | grep -oE '<s [^>]*/>' | grep -oE ' n="[^"]*"' )"
    case "$PROWS" in *"n=\"caller_$pc\""*) ok "(T) same-file annotation ($pf): caller_$pc keeps its edge to $pc.get";;
        *) no "(T) same-file annotation ($pf): caller_$pc lost its edge to $pc.get: [$PROWS]";; esac
done
TCALL="$( cd "$T" && "$BIN" . --no-cache --callers=pkg/registry.py:get 2>/dev/null )"
TROWS="$( printf '%s' "$TCALL" | grep -oE '<s [^>]*/>' | grep -oE ' n="[^"]*"' | sed -E 's/ n="([^"]*)"/\1/' | sort | tr '\n' ' ' )"
case " $TROWS" in *" load_repos "*|*" find_alias "*) no "(T) a same-file dict .get binds to ConnectionPool.get: rows [$TROWS]";;
    *) ok "(T) data.get / entry.get in the defining file do not bind to ConnectionPool.get";; esac
[ "$TROWS" = "probe true_local warm " ] \
    && ok "(T) self.get, cls.get and the importing file's typed local keep their edges" \
    || no "(T) callers should be exactly probe true_local warm: [$TROWS]"
[ "$( attr "$( printf '%s' "$TCALL" | grep -oE '<callers [^>]*>' | head -1 )" declined_calls )" = 2 ] \
    && ok "(T) the two decoys are counted: declined_calls=\"2\"" \
    || no "(T) declined_calls should be 2: $( printf '%s' "$TCALL" | grep -oE '<callers [^>]*>' | head -1 )"

[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$fail"
