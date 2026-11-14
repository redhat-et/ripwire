#!/usr/bin/env bash
# budgetmonotonecheck.sh — TOKEN-BUDGET-MONOTONE: a budget may only trim the answer, never switch its regime.
#
# THE DEFECT (found in the 0.7.0 comparison rehearsal, 2026-11-14). `--for`'s body posture (servesBodies, the fold, the
# caller hop, the dispatch hop, <syms>, the graph-verb block, the head round-robin …) was decided with `cfg.tokenBudget == 0`
# in its predicate, so ANY --token-budget — even one far above the answer — switched the answer into a different regime.
# 21 of 21 questions whose unbudgeted answer was under 16,000 est_tokens came back SMALLER and DIFFERENT under
# --token-budget=16000 (koa-02: 24,446 B -> 10,834 B on a 5,494-token answer). The other way round, --detail=3
# --max-tokens=16000 returned 1.14x the unbudgeted size: a ceiling that grew the answer. Three flags, three behaviours.
#
# THE CONTRACT (owner rule "budget serves answers": shed optional attributes first, never cut the answer; an answer already
# under the budget must not change). The posture is decided as if no budget were given; the budget is a ceiling applied
# after it, by ONE fixed shed sequence over that unbudgeted answer U: the blocks outside est_tokens a budget holds (<syms>,
# <doc_body> … when U plus their price does not fit: U is rendered again with them held), the <sigs> rows' optional
# attributes, then the <tail> rows from the last, the <hops> rows, then the <fold> bodies, then the <bodies> section from the
# last, then (--token-budget only) the <sigs> rows from the last, down to a floor of four. answer(B) = U with the SHORTEST prefix of that sequence
# removed that brings est_tokens to B (all of it when none does: the overflow is then visible as est_tokens > the budget
# named on the root, and a --max-tokens ceiling says over_ceiling="1").
#   (a) --token-budget=B >= E (U's est_tokens plus its held blocks' price, <syms> on these fixtures): the answer IS U —
#       stdout, stderr and exit code byte for byte. A budget that cuts nothing says nothing (no budget_tokens=, no clause); the disclosure rides only an answer something was shed from.
#   (b) B < E: est_tokens <= B, or every tier below the <sigs> rows is shed and the rows are at their floor; every <sigs>
#       and <tail> row kept is U's row in U's order — the <tail> rows a prefix of U's, the <sigs> rows U's best-ranked ones
#       (the cut takes the worst r= first: U's document order is not rank order under the head round-robin) — and a <sigs>
#       row is missing only when the tail and fold are already gone. At B = E - 1 every <sigs> row of U is kept.
#   (c) the same two arms for --detail=N --max-tokens=M against the unbudgeted --detail=N answer, except that a ceiling never
#       cuts a ranked <sigs> row (METHODOLOGY §9 #2): past the tail, fold and --detail bodies it says over_ceiling="1".
#   (d) monotone: B1 < B2 => every <sigs>/<tail> row of answer(B1) is in answer(B2), in the same order (the <tail> rows a
#       prefix, the <sigs> rows a subsequence: both are U's best-ranked, the B1 set no larger), answer(B1) carries a <fold>
#       only if answer(B2) does, and price(B1) <= price(B2) (est_tokens plus the held blocks' price: a held answer's
#       est_tokens carries its own disclosure).
#       That is the exact relation the fixed shed sequence guarantees — not a byte prefix: the shown= counts move.
# Each arm counts the questions it judged and FAILS on zero (a vacuous arm is a red arm).
#
# Corpora: two engineered fixtures written at test time (Python, TypeScript — content-stable, so the margins cannot drift with
# ripwire's own source) and this repo's own src/ (real answers with a fold, hops and a deep tail).
#
# Usage:  bash test/budgetmonotonecheck.sh [BIN]      (default build/ripwire; RIPWIRE_BIN= also read)
# Exits non-zero on any failure.

set -u
fail=0   # the failure accumulator (the judge below reports each FAIL; its exit lands here)
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "budgetmonotonecheck: BIN=$BIN"

# ── the two engineered corpora ──────────────────────────────────────────────────────────────────────────────────────────
python3 - "$TMP" <<'PYEOF'
import os, sys
tmp = sys.argv[1]
py = os.path.join( tmp, "pyledger" ); os.makedirs( py )
stages = [ "intake", "validate", "reconcile", "settle", "archive", "audit", "report", "notify", "schedule", "retry", "export", "purge" ]
for i, s in enumerate( stages ):
    fns = []
    for j, verb in enumerate( [ "open", "apply", "check", "close", "merge", "split" ] ):
        fns.append( f'''def {verb}_{s}_ledger_batch(batch, ledger, policy):
    """{verb.capitalize()} one {s} ledger batch: walks every entry, applies the settlement policy and records the balance."""
    total = 0
    for entry in batch:
        if policy.allows(entry):
            total += ledger.post_{s}(entry, {j})
    return total
''' )
    fns.append( f'''class {s.capitalize()}LedgerStage:
    """The {s} stage of the settlement ledger pipeline."""
    def run(self, batch, ledger, policy):
        return open_{s}_ledger_batch(batch, ledger, policy) + close_{s}_ledger_batch(batch, ledger, policy)
''' )
    open( os.path.join( py, f"stage_{s}.py" ), "w" ).write( "\n\n".join( fns ) )
ts = os.path.join( tmp, "tsrouter" ); os.makedirs( ts )
areas = [ "users", "orders", "billing", "catalog", "search", "reviews", "carts", "shipping", "refunds", "coupons" ]
for a in areas:
    body = []
    for k, op in enumerate( [ "list", "get", "create", "update", "remove" ] ):
        body.append( f'''/** {op} handler for the {a} route: parses the request, checks the session token and renders the response. */
export function {op}{a.capitalize()}Handler(req: Request, session: Session): Response {{
  const token = session.verifyToken(req.headers.authorization, {k});
  return renderRouteResponse(token, req.params, "{a}");
}}
''' )
    body.append( f'''export class {a.capitalize()}Router {{
  register(app: App): void {{
    app.route("/{a}", list{a.capitalize()}Handler);
    app.route("/{a}/:id", get{a.capitalize()}Handler);
  }}
}}
''' )
    open( os.path.join( ts, f"{a}.ts" ), "w" ).write( "\n".join( body ) )
open( os.path.join( ts, "render.ts" ), "w" ).write( '''/** Render one route response from a verified session token. */
export function renderRouteResponse(token: Token, params: Params, area: string): Response {
  return new Response(JSON.stringify({ area, params, user: token.user }));
}
''' )
PYEOF

# corpus|question — the src/ rows are this repo's own (real fold / hops / tail); the fixtures are content-stable
cat >"$TMP/questions.tsv" <<EOF
$TMP/pyledger	how does the settlement ledger pipeline reconcile a batch
$TMP/pyledger	where does the audit stage apply the settlement policy
$TMP/tsrouter	how are route handlers registered and how is the session token verified
$TMP/tsrouter	how does the orders route render its response
$ROOT/src	how does pagerank power iteration converge
$ROOT/src	where is repriceRootAfterCut defined and who calls it
EOF
DETAIL_ROWS=3   # (c) runs on the first DETAIL_ROWS questions (the fixtures plus none of src/: --detail bodies there are large and slow)

# ── the runs ────────────────────────────────────────────────────────────────────────────────────────────────────────────
# E = the answer's whole price: the root's est_tokens plus the blocks outside it a budget holds (src/forbudgetfit.h
# kForHeldBlocks, heldBlocksPrice: <doc_body> by its own est_tokens=, the others' bytes at the 2.50 markup rate). A budget at or
# above E cuts nothing; under it the answer is rendered with those blocks held, then shed.
cat >"$TMP/price_of.py" <<'PYEOF'
import re, sys
def price( path ):
  s = open( path, 'rb' ).read().decode( 'latin-1' )   # byte offsets, as the binary counts them
  m = re.search( r'<ctx [^>]*?\best_tokens="(\d+)"', s )
  if not m: return None
  held = ( "syms", "doc_body", "decl_rows", "exemplar_family", "graph_verb", "reexports", "shortkey", "aliases" )
  masked = re.sub( r'<!\[CDATA\[.*?\]\]>|<!--.*?-->', lambda x: ' ' * len( x.group( 0 ) ), s, flags = re.S )
  depth, heldp, open_at, open_tag = 0, 0, None, None
  for t in re.finditer( r'<(/?)([A-Za-z_][\w-]*)([^>]*?)(/?)>', masked ):
      close, name, attrs, selfc = t.groups()
      if close:
          depth -= 1
          if depth == 1 and open_at is not None:
              e = re.search( r'\best_tokens="(\d+)"', open_tag ) if name == "doc_body" else None
              heldp += int( e.group( 1 ) ) if e and int( e.group( 1 ) ) > 0 else int( ( t.end() - open_at ) / 2.5 + 0.5 )
              open_at = None
          continue
      if depth == 1 and name in held:
          if selfc: heldp += int( ( t.end() - t.start() ) / 2.5 + 0.5 )
          else: open_at, open_tag = t.start(), t.group( 0 )
      if not selfc: depth += 1
  return int( m.group( 1 ) ) + heldp
PYEOF
est_of(){ python3 -c 'import sys; sys.path.insert( 0, sys.argv[ 1 ] ); import price_of; p = price_of.price( sys.argv[ 2 ] ); print( "" if p is None else p )' "$TMP" "$1"; }
i=0
while IFS='	' read -r corpus q; do
    [ -z "$corpus" ] && continue
    i=$(( i + 1 ))
    d="$TMP/q$i"; mkdir -p "$d"; printf '%s\n%s\n' "$corpus" "$q" >"$d/what"
    ( cd "$corpus" && "$BIN" . --for="$q" ) >"$d/U" 2>"$d/U.err"; echo "$?" >"$d/U.rc"
    E="$( est_of "$d/U" )"
    [ -n "$E" ] || { echo "  INFO  q$i: the unbudgeted answer carries no est_tokens — skipped (counted as not judged)"; continue; }
    echo "$E" >"$d/E"
    for B in $(( E / 4 )) $(( E / 2 )) $(( E - 1 )) "$E" $(( E + 1 )) $(( E * 2 )); do
        [ "$B" -ge 1 ] || continue
        ( cd "$corpus" && "$BIN" . --for="$q" --token-budget="$B" ) >"$d/tb.$B" 2>"$d/tb.$B.err"; echo "$?" >"$d/tb.$B.rc"
    done
    if [ "$i" -le "$DETAIL_ROWS" ]; then
        ( cd "$corpus" && "$BIN" . --for="$q" --detail=2 ) >"$d/D" 2>"$d/D.err"; echo "$?" >"$d/D.rc"
        ED="$( est_of "$d/D" )"
        if [ -n "$ED" ]; then
            echo "$ED" >"$d/ED"
            for M in $(( ED / 2 )) "$ED" $(( ED * 2 )); do
                ( cd "$corpus" && "$BIN" . --for="$q" --detail=2 --max-tokens="$M" ) >"$d/mt.$M" 2>"$d/mt.$M.err"; echo "$?" >"$d/mt.$M.rc"
            done
        fi
    fi
done <"$TMP/questions.tsv"

# ── the four arms, judged together (one parse per answer) ───────────────────────────────────────────────────────────────
python3 - "$TMP" <<'PYEOF'
import os, re, sys, glob
import xml.etree.ElementTree as ET
tmp = sys.argv[1]
fails = []
counts = { "a": 0, "b": 0, "c": 0, "d": 0 }
def ok( m ): print( "  PASS  " + m )
def no( m ): print( "  FAIL  " + m ); fails.append( m )
def raw( p ): return open( p, encoding = "utf-8", errors = "replace" ).read()

def same_run( p, q ):
    # rule 12 byte identity: stdout, stderr and exit code
    return all( os.path.exists( p + x ) and os.path.exists( q + x ) and raw( p + x ) == raw( q + x ) for x in ( "", ".err", ".rc" ) )

def parse( p ):
    try:
        return ET.fromstring( raw( p ) )
    except ET.ParseError as e:
        no( f"{p}: not well-formed XML ({e})" ); return None
def ident( e ): return ( e.tag, e.get( "p" ) or "", e.get( "n" ) or e.get( "sym" ) or "", e.get( "l" ) or "" )
def rows( root, sec ):
    s = root.find( sec ) if root is not None else None
    if s is None: return []
    return [ ident( c ) for c in s if c.tag in ( "d", "t" ) ]
def est( root ): return int( root.get( "est_tokens", "0" ) ) if root is not None else 0
def has_fold( root ): return root is not None and root.find( "fold" ) is not None
def detail_bodies( root ):
    b = root.find( "bodies" ) if root is not None else None
    return [ ( c.get( "p" ) or "", c.get( "n" ) or "" ) for c in b if c.tag == "b" ] if b is not None else []
def is_prefix( a, b ): return len( a ) <= len( b ) and b[ :len( a ) ] == a
def is_subseq( a, b ):
    it = iter( b ); return all( x in it for x in a )
def best_ranked( U, k ):
    """U's k best-ranked <sigs> rows in U's order: the rows:N unit cuts the worst rank first (no r= = worst; ties: the later row)."""
    s = U.find( "sigs" ) if U is not None else None
    if s is None: return []
    rs = [ c for c in s if c.tag in ( "d", "t" ) ]
    key = lambda i: ( int( rs[ i ].get( "r" ) or 10**9 ), i )
    keep = sorted( sorted( range( len( rs ) ), key = key )[ :k ] )
    return [ ident( rs[ i ] ) for i in keep ]

sys.path.insert( 0, tmp ); import price_of
def judge_fit( label, U, A, budget, hard, pu, pa ):
    """(b)/(c) below the price: est within the budget or every lower tier gone and rows at the floor; kept rows are U's prefix."""
    su, sa = rows( U, "sigs" ), rows( A, "sigs" )
    tu, ta = rows( U, "tail" ), rows( A, "tail" )
    good = True
    if sa != best_ranked( U, len( sa ) ):
        no( f"{label}: the <sigs> rows are not U's {len( sa )} best-ranked rows in U's order ({len( sa )} vs {len( su )})" ); good = False
    if not is_prefix( ta, tu ):
        no( f"{label}: the <tail> rows are not a prefix of the unbudgeted answer's ({len( ta )} vs {len( tu )})" ); good = False
    if len( sa ) < len( su ) and ( ta or has_fold( A ) ):
        no( f"{label}: a <sigs> row was cut while {len( ta )} tail rows / a fold were still served (rows are shed last)" ); good = False
    floor = min( 4, len( su ) )
    if hard and len( sa ) != len( su ):   # a --max-tokens ceiling never cuts a ranked row (METHODOLOGY §9 #2: over_ceiling="1" instead)
        no( f"{label}: the ceiling cut a <sigs> row ({len( sa )} of {len( su )} kept)" ); good = False
    if est( A ) > budget:
        at_floor = ( hard or len( sa ) <= floor ) and not ta and not has_fold( A )
        if not at_floor:
            no( f"{label}: est_tokens={est( A )} > {budget} while optional tiers remain (rows {len( sa )}, tail {len( ta )}, fold {has_fold( A )})" ); good = False
        if hard and A.get( "over_ceiling" ) != "1":
            no( f"{label}: est_tokens={est( A )} > max_tokens={budget} and no over_ceiling=\"1\"" ); good = False
    # a budget never grows the answer — except by the over_ceiling= disclosure a --max-tokens ceiling owes when nothing below the
    # ranked rows was left to shed (rows are never cut against a ceiling): that label and its clause are priced markup too
    # the whole price (est_tokens plus the held blocks, price_of): a held answer's est_tokens grows by its own disclosure
    if price_of.price( pa ) > price_of.price( pu ) and not ( hard and A.get( "over_ceiling" ) == "1" ):
        no( f"{label}: the budgeted answer prices {price_of.price( pa )} > the unbudgeted {price_of.price( pu )} (est_tokens + held blocks)" ); good = False
    return good

for d in sorted( glob.glob( os.path.join( tmp, "q*" ) ) ):
    if not os.path.exists( os.path.join( d, "E" ) ): continue
    corpus, q = raw( os.path.join( d, "what" ) ).split( "\n" )[ :2 ]
    tag = f"{os.path.basename( d )} [{os.path.basename( corpus )}: {q[:40]}]"
    E = int( raw( os.path.join( d, "E" ) ) )
    Uraw = raw( os.path.join( d, "U" ) ); U = parse( os.path.join( d, "U" ) )
    if U is None: continue
    # (a) at and above the price: U, byte for byte
    good = True
    for B in ( E, E + 1, 2 * E ):
        p = os.path.join( d, f"tb.{B}" )
        if not os.path.exists( p ): good = False; no( f"(a) {tag} B={B}: no run" ); continue
        if not same_run( p, os.path.join( d, "U" ) ):
            no( f"(a) {tag} B={B} >= E={E}: the answer is not the unbudgeted one ({os.path.getsize( p )} B vs {len( Uraw.encode() )} B, or stderr/rc differ)" ); good = False
    counts[ "a" ] += 1
    if good: ok( f"(a) {tag}: --token-budget >= E={E} returns the unbudgeted answer byte for byte (stdout, stderr, rc)" )
    # (b) below the price
    good = True
    for B in ( E - 1, E // 2, E // 4 ):
        p = os.path.join( d, f"tb.{B}" )
        if B < 1 or not os.path.exists( p ): continue
        A = parse( p )
        if A is None: good = False; continue
        good = judge_fit( f"(b) {tag} B={B}", U, A, B, False, os.path.join( d, "U" ), p ) and good
        if B == E - 1 and len( rows( A, "sigs" ) ) != len( rows( U, "sigs" ) ):
            no( f"(b) {tag} B=E-1: a <sigs> row was cut one token under the price" ); good = False
    counts[ "b" ] += 1
    if good: ok( f"(b) {tag}: under E={E} the answer sheds tail/fold before rows and keeps U's rows in U's order" )
    # (d) monotone over the whole ladder
    ladder = sorted( { B for B in ( E // 4, E // 2, E - 1, E, E + 1, 2 * E ) if B >= 1 and os.path.exists( os.path.join( d, f"tb.{B}" ) ) } )
    answers = [ ( B, parse( os.path.join( d, f"tb.{B}" ) ) ) for B in ladder ]
    good = len( answers ) >= 3
    for ( b1, a1 ), ( b2, a2 ) in zip( answers, answers[ 1: ] ):
        if a1 is None or a2 is None: good = False; continue
        if not is_subseq( rows( a1, "sigs" ), rows( a2, "sigs" ) ):
            no( f"(d) {tag}: <sigs> rows at B={b1} are not a subsequence of those at B={b2}" ); good = False
        if not is_prefix( rows( a1, "tail" ), rows( a2, "tail" ) ):
            no( f"(d) {tag}: <tail> rows at B={b1} are not a prefix of those at B={b2}" ); good = False
        if has_fold( a1 ) and not has_fold( a2 ):
            no( f"(d) {tag}: B={b1} serves a <fold> that B={b2} does not" ); good = False
        p1, p2 = price_of.price( os.path.join( d, f"tb.{b1}" ) ), price_of.price( os.path.join( d, f"tb.{b2}" ) )
        if p1 > p2:
            no( f"(d) {tag}: the price (est_tokens + held blocks) {p1} at B={b1} > {p2} at B={b2}" ); good = False
    counts[ "d" ] += 1
    if good: ok( f"(d) {tag}: monotone over B={ladder}" )
    # (c) --detail=2 --max-tokens
    if os.path.exists( os.path.join( d, "ED" ) ):
        ED = int( raw( os.path.join( d, "ED" ) ) )
        Draw = raw( os.path.join( d, "D" ) ); D = parse( os.path.join( d, "D" ) )
        good = D is not None
        for M in ( ED, 2 * ED ):
            p = os.path.join( d, f"mt.{M}" )
            if not os.path.exists( p ): good = False; continue
            if not same_run( p, os.path.join( d, "D" ) ):
                no( f"(c) {tag} M={M} >= E={ED}: --detail=2 --max-tokens is not the unbudgeted --detail=2 answer ({os.path.getsize( p )} B vs {len( Draw.encode() )} B)" ); good = False
        p = os.path.join( d, f"mt.{ED // 2}" )
        A = parse( p ) if os.path.exists( p ) else None
        if A is None or D is None: good = False
        else:
            good = judge_fit( f"(c) {tag} M={ED // 2}", D, A, ED // 2, True, os.path.join( d, "D" ), p ) and good
            if not is_prefix( detail_bodies( A ), detail_bodies( D ) ):
                no( f"(c) {tag} M={ED // 2}: the --detail bodies are not a prefix of the unbudgeted ones" ); good = False
        counts[ "c" ] += 1
        if good: ok( f"(c) {tag}: --detail=2 --max-tokens at/above E={ED} is the unbudgeted answer; under it, a shed of it" )

for arm, n in sorted( counts.items() ):
    if n == 0: no( f"arm ({arm}) judged 0 questions — vacuous" )
    else: print( f"  INFO  arm ({arm}) judged {n} question(s)" )
sys.exit( 1 if fails else 0 )
PYEOF
rc=$?
echo
[ "$rc" = 0 ] || { fail=1; echo "budgetmonotonecheck: FAIL (the judge exited $rc)"; }
[ "$fail" = 0 ] && echo "budgetmonotonecheck: PASS"
exit "$fail"
