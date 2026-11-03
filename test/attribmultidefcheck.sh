#!/usr/bin/env bash
# attribmultidefcheck.sh — per-row DEFINITION ATTRIBUTION on answers whose selector names several definitions.
#
#   test/attribmultidefcheck.sh [BIN]        # BIN defaults to $RIPWIRE_BIN, then build/ripwire
#
# The defect class (round 4, O1 false claims ninja-07 / nfpm-06 / ninja-26; kysely-06 / mdbook-06 complete only after a
# follow-on): a selector that matches two or more definitions (defs="2"+) answers with the UNION of their callers,
# callees or dependants, and every row reads as belonging to one definition. fix27-impact-multidef hedged the --impact
# file rollup only; this gate covers every verb that folds per-selector rows.
#
# The contract (docs: the lane design, reports/attrib-multidef.md):
#   * DEFINITION GROUP: a bodied definition plus the bodyless declarations that DECLARE it — for C/C++/ObjC the
#     --edit-check identity rule (src/editcheckdecl.h editCheckTieDeclaration: same full scope chain, qualifiers,
#     parameter-type list, include proof, linkage), for TypeScript the overload signatures beside their implementation;
#     a declaration that declares no listed definition (a foreign one: another scope chain, a static definition in
#     another file) is its own group. An answer is MULTI-GROUP when its selector matched two or more groups.
#   * A multi-group answer lists the groups as <def ix= t= [sc=] p= [bodyless="1"]/> children of its root (CLI JSON
#     "def_table":[{"ix","t","sc","p"}], MCP "def_table":[{"ix","kind","scope","file","line"}]); every row carries
#     of_def="TOKENS" (JSON/MCP "of_def":[TOKENS]): space-separated K (a <def ix=>) with a mark — K alone = a proven edge
#     ties the row to group K, K~n = by name alone, K~s = only as one arm of a call the resolver split between
#     same-named definitions, K~t = bound to a primary template whose specialisation is also a listed group (which of
#     them the call reaches is unproven). callers: row -> group; callees: group -> row; impact: a chain of calls from
#     the row to the group (a by-name hop makes it ~n, else a split hop ~s); safe-delete <c> rows as callers; the
#     impact <rf> rollup row: the union of its symbols' tokens, the strongest mark per K. Above 16 groups the table
#     lists the groups the page's rows name and the root says defs_listed=N; there a row prints its K, K~s and K~t tokens
#     and ONE bare ~n when it also has by-name ties (a row tied by name alone prints no of_def: its via="name" hedges it).
#   * Every other answer (one definition, or one definition with its own declarations) carries no table and no of_def;
#     its rows that are one arm of a split call carry prov="split" (the map's per-edge vocabulary), whatever defs= is.
#   * --path: a to= with several definitions carries no to_p= unless a proven hop bound it (unreached, or the hop into
#     it is a split arm or by name: dropped); a from= with several definitions carries no from_p= when unreached.

# Corpus test/attribmultideffix (in-tree, outside test/fixture); the stand-in dir per known-items row in [brackets]:
#   cpp/  [ninja-07] StringPiece::empty vs EvalString::empty (UsesPiece/UsesEval/UsesBoth, DrivePiece/DriveEval at depth 2
#         in their own files; UsesStd, a std::string::empty confounder), [ninja-26] ManifestParser::ParseDefault (decl +
#         def) calling the CanonicalizePath overload pair (proven by arity since train 29) and the Normalize pair (a split call), near misses in fmt.{h,cc}: Fmt::put overloads in
#         ONE class (split), outer::run vs outer::inner::run (nested namespace), Box<T>::get vs the Box<int>
#         specialisation; ReadPath decl + def; detail.{h,cc}: a::detail::tally declared, b::detail::tally defined (same
#         leaf scope, another chain: a foreign declaration).
#   c/    plain C: a static helper in helper_a.c + a same-named prototype in helper_b.c (foreign declaration); proto.h's
#         lost + its definition in proto.c (the tmux prototype + definition shape: one group).
#   go/   [nfpm-06] three Get (files.Get fn, modtime Get fn, (*Info).Get method), cross_kind fn:2,method:1.
#   py/ts/java/  two same-named methods of different classes IN ONE FILE (entity identity: owner, not file + name);
#         py/ also draw_mixed: a proven Widget.render call and a by-name thing.render call in one row. [kysely-06] ts/;
#         ts/overloads.ts: overload signatures of differing arity + one implementation (one group).
#   js/rb/  two same-named methods of two classes, constructor-typed receivers.
#   rs/   [mdbook-06] Book::walk vs Shelf::walk on param-typed receivers (by name + split today: hedged tokens); Book::iter /
#         Shelf::iter, the original shape, are declined by the standard-member gate's Rust row since #405 (twin f_rs_iter).
#   objc/ two -area methods, typed message receivers (split today: hedged tokens).
#   u2/   [final review R1] scan_tok defined in prog1/util.c, an untied prototype in prog2/main.c (no #include proves the
#         tie), a static namesake in prog3/other.c: a printed table lists all three groups (the prototype bodyless=1).
#   (generated at run time) 20 Python classes with one same-named method each: the definition-table cap (16); a second
#         20-class file with a by-name and a mixed caller (final review R2: a cut table enumerates no by-name tie).
#
# Arm classes in the output: [P] positive — the defect shape, RED on a binary without per-row attribution; [N] near miss —
# a shape the new code could plausibly mis-handle (a one-group answer that must stay plain, an overload or a namesake that
# must not be over-attributed); it is red on such a binary only where it needs a hedge that binary cannot print; [C] control
# — holds on every binary.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/attribmultideffix"
DIR="$( mktemp -d )"; trap 'rm -rf "$DIR"' EXIT
fail=0
# every verdict is an if/else: a failed write of a PASS line must never print FAIL for an arm that passed (gateexitcheck G2)
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
# say RC PASSMSG FAILMSG — the verdict of the test just run ($?), as an if/else (gateexitcheck G2)
say(){ if [ "$1" = 0 ]; then ok "$2"; else no "$3"; fi; }

echo "attribmultidefcheck: BIN=$BIN"
[ -x "$BIN" ] || { echo "  FAIL  no ripwire binary at $BIN"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "  FAIL  python3 is required (the answers are parsed, not grepped)"; exit 1; }
[ -d "$FIX/cpp" ] || { echo "  FAIL  corpus $FIX missing"; exit 1; }

# ── the answer reader: one canonical line per row, so every arm compares strings ─────────────────────────────────────
# amd.py FILE FORM ROOTTAG ROWKEY
#   FORM xml : ROOTTAG = the root element (callers|callees|impact|safe-delete), ROWKEY = the row element (s|c|rf)
#   FORM json: ROOTTAG unused, ROWKEY = the row array key (callers|callees|calledBy|calls|reach…); FILE may be an MCP
#              JSON-RPC line (its content[0].text is read)
# prints: ROOT ok defs=N groups=G         (G = <def> rows; -1 when the root is absent)
#         DEF  k p bodyless sc
#         ROW  name<TAB>canon<TAB>flags   canon = the of_def tokens mapped to their group's p (sorted), "-" when the row has
#                                         no of_def, "!K" for a token whose K names no <def>; flags = via=name / prov=split
cat >"$DIR/amd.py" <<'PY'
import json, re, sys
path, form, roottag, rowkey = sys.argv[1:5]
raw = open(path, encoding='utf-8', errors='replace').read()
def attrs(tag):
    return dict(re.findall(r'\s([A-Za-z_]+)="([^"]*)"', tag))
def canon(tokens, table):
    out = []
    for t in tokens:
        k, _, mark = t.partition('~')
        if k == '' and mark:
            out.append('~' + mark); continue   # a cut table's bare ~n (its by-name ties, not enumerated)
        p = table.get(k)
        out.append(('!' + k) if p is None else (p + ('~' + mark if mark else '')))
    return ' '.join(sorted(out))
if form == 'mcp':
    try:
        msg = json.loads(raw.strip().splitlines()[-1])
        raw = msg['result']['content'][0]['text']
    except Exception as e:
        print('ROOT missing mcp-unreadable %s' % e); sys.exit(0)
    form = 'json' if raw.lstrip().startswith('{') else 'xml'
if form == 'xml':
    m = re.search(r'<%s\s[^>]*>' % re.escape(roottag), raw)
    if not m:
        print('ROOT missing'); sys.exit(0)
    root = attrs(m.group(0))
    body = raw[m.end():]
    end = body.find('</%s>' % roottag)
    body = body if end < 0 else body[:end]
    table = {}
    defs = re.findall(r'<def\s[^>]*?/?>', body)
    for d in defs:
        a = attrs(d)
        table[a.get('ix', '?')] = a.get('p', '?')
        print('DEF\t%s\t%s\t%s\t%s' % (a.get('ix', '?'), a.get('p', '?'), a.get('bodyless', '0'), a.get('sc', '')))
    print('ROOT\tok\tdefs=%s\tgroups=%d\tto_p=%s\tfrom_p=%s\tcount=%s\tdefs_listed=%s\tnext_offset=%s' % (
          root.get('defs', root.get('to_defs', '?')), len(defs), root.get('to_p', '-'), root.get('from_p', '-'),
          root.get('count', root.get('reaches', root.get('callers', '?'))), root.get('defs_listed', '-'), root.get('next_offset', '-')))
    for r in re.findall(r'<%s\s[^>]*?/?>' % re.escape(rowkey), body):
        a = attrs(r)
        name = a.get('n', a.get('p', '?'))
        tok = a.get('of_def')
        flags = ' '.join(x for x in (('via=name' if a.get('via') == 'name' else ''), ('prov=split' if a.get('prov') == 'split' else '')) if x)
        print('ROW\t%s\t%s\t%s' % (name, '-' if tok is None else canon(tok.split(), table), flags))
else:
    try:
        j = json.loads(raw)
    except Exception as e:
        print('ROOT missing json-unreadable %s' % e); sys.exit(0)
    tab = j.get('def_table') or []
    table = {}
    for d in tab:
        p = d.get('p') or ('%s:%s' % (d.get('file', '?'), d.get('line', '?')))
        table[str(d.get('ix'))] = p
        print('DEF\t%s\t%s\t%s\t%s' % (d.get('ix'), p, d.get('bodyless', 0), d.get('sc', d.get('scope', ''))))
    print('ROOT\tok\tdefs=%s\tgroups=%d\tto_p=%s\tfrom_p=%s\tcount=%s\tdefs_listed=%s\tnext_offset=%s' % (
          j.get('defs', j.get('to_defs', '?')), len(tab), j.get('to_p', '-'), j.get('from_p', '-'),
          j.get('count', j.get('reaches', '?')), j.get('defs_listed', '-'), j.get('next_offset', '-')))
    for r in j.get(rowkey) or []:
        name = r.get('n', r.get('name', '?'))
        tok = r.get('of_def')
        flags = ' '.join(x for x in (('via=name' if r.get('via') == 'name' else ''), ('prov=split' if r.get('prov') == 'split' else '')) if x)
        print('ROW\t%s\t%s\t%s' % (name, '-' if tok is None else canon([str(t) for t in tok], table), flags))
PY

# ans TAG LANG ROOTTAG ROWKEY FORM -- ARGS… : run BIN on the corpus, read the answer into $DIR/TAG.rows; FAIL (and return 1)
# when the run failed or printed no root, so no absence arm ever reads a crashed or empty run as "not attributed".
ans(){
    local tag="$1" lang="$2" roottag="$3" rowkey="$4" form="$5"; shift 6
    if ! ( cd "$FIX/$lang" && perl -e 'alarm 120; exec @ARGV' "$BIN" . --no-cache "$@" ) >"$DIR/$tag.out" 2>"$DIR/$tag.err"; then
        no "$tag: '$*' on $lang exited non-zero: $( head -2 "$DIR/$tag.err" )"; : >"$DIR/$tag.rows"; return 1
    fi
    python3 "$DIR/amd.py" "$DIR/$tag.out" "$form" "$roottag" "$rowkey" >"$DIR/$tag.rows"
    if ! grep -q '^ROOT	ok' "$DIR/$tag.rows"; then no "$tag: '$*' on $lang printed no <$roottag> root"; return 1; fi
    return 0
}
# mcp TAG LANG ROWKEY TOOL ARGSJSON : the same, through the MCP server (initialize + one tools/call)
mcp(){
    local tag="$1" lang="$2" rowkey="$3" tool="$4" args="$5"
    printf '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{}}\n{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"%s","arguments":{"path":"%s",%s}}}\n' \
        "$tool" "$FIX/$lang" "$args" | perl -e 'alarm 120; exec @ARGV' "$BIN" --mcp 2>"$DIR/$tag.err" | tail -1 >"$DIR/$tag.out"
    python3 "$DIR/amd.py" "$DIR/$tag.out" mcp "$( [ "$tool" = impact ] && echo impact || echo path )" "$rowkey" >"$DIR/$tag.rows"
    if ! grep -q '^ROOT	ok' "$DIR/$tag.rows"; then no "$tag: MCP $tool on $lang gave no answer: $( head -c 200 "$DIR/$tag.out" )"; return 1; fi
    return 0
}
row(){ awk -F'\t' -v n="$2" '$1=="ROW" && $2==n { print $3; exit }' "$DIR/$1.rows"; }
rowflags(){ awk -F'\t' -v n="$2" '$1=="ROW" && $2==n { print $4; exit }' "$DIR/$1.rows"; }
groups(){ awk -F'\t' '$1=="ROOT" { sub("groups=","",$4); print $4; exit }' "$DIR/$1.rows"; }
rootf(){ awk -F'\t' -v f="$2" '$1=="ROOT" { for(i=3;i<=NF;i++) if(index($i,f"=")==1){ print substr($i,length(f)+2); exit } }' "$DIR/$1.rows"; }
nrows(){ grep -c '^ROW' "$DIR/$1.rows"; }

# expect CLASS TAG NAME WANT : the row's canonical attribution equals WANT exactly
expect(){
    local cls="$1" tag="$2" n="$3" want="$4" got
    got="$( row "$tag" "$n" )"
    if [ -z "$got" ]; then no "[$cls] $tag: no row n=\"$n\" (rows: $( grep '^ROW' "$DIR/$tag.rows" | cut -f2 | tr '\n' ' ' ))"
    elif [ "$got" = "$want" ]; then ok "[$cls] $tag: $n -> $want"
    else no "[$cls] $tag: $n attributed '$got', want '$want'"; fi
}
# hedged CLASS TAG NAME ALLOWED : the row has of_def, every token is marked (~n/~s) and names a group in ALLOWED
hedged(){
    local cls="$1" tag="$2" n="$3" allowed="$4" got t bad=""
    got="$( row "$tag" "$n" )"
    if [ -z "$got" ] || [ "$got" = "-" ]; then no "[$cls] $tag: $n carries no of_def ('$got'); a multi-definition row must name or hedge its definition"; return; fi
    for t in $got; do
        case "$t" in *~n|*~s) ;; *) bad="$bad $t(unmarked)" ;; esac
        case " $allowed " in *" ${t%%~*} "*) ;; *) bad="$bad $t(not in: $allowed)" ;; esac
    done
    [ -z "$bad" ]; say $? "[$cls] $tag: $n hedged ($got)" \
        "[$cls] $tag: $n tokens '$got' —$bad"
}
# plain CLASS TAG [split] : one-group answer — no <def> table and no of_def on any row (a read of a successful run); and,
# unless `split` is given (an answer whose split arms must carry it), no prov="split" on any row either
plain(){
    local cls="$1" tag="$2" allow="${3:-}"
    if [ "$( groups "$tag" )" = 0 ] && ! awk -F'\t' '$1=="ROW" && $3!="-" { f=1 } END { exit !f }' "$DIR/$tag.rows" \
       && { [ -n "$allow" ] || ! awk -F'\t' '$1=="ROW" && $4 ~ /prov=split/ { f=1 } END { exit !f }' "$DIR/$tag.rows"; } \
       && [ "$( nrows "$tag" )" -gt 0 ]; then ok "[$cls] $tag: one definition group — no <def> table, no of_def$( [ -n "$allow" ] || printf ', no prov' ) ($( nrows "$tag" ) rows)"
    else no "[$cls] $tag: a one-group answer grew attribution: groups=$( groups "$tag" ), rows: $( grep '^ROW' "$DIR/$tag.rows" | cut -f2,3,4 | tr '\t\n' '= ' )"; fi
}
# rowset CLASS TAG COUNT NAMES : attribution adds attributes and never removes a row — the root count and the sorted row-name
# multiset equal the base binary's (pinned from base d4325a8c)
rowset(){
    local cls="$1" tag="$2" want_n="$3" want="$4" got got_n
    got="$( awk -F'\t' '$1=="ROW" { print $2 }' "$DIR/$tag.rows" | sort | tr '\n' ' ' | sed 's/ $//' )"
    got_n="$( rootf "$tag" count )"
    { [ "$got" = "$want" ] && [ "$got_n" = "$want_n" ]; }; say $? "[C] $tag: rows preserved (count=$got_n; $got)" \
        "[C] $tag: rows changed: count='$got_n' want '$want_n'; rows '$got' want '$want'"
}
# defbody CLASS TAG P BODYLESS : the <def> row with p=P exists and carries bodyless=BODYLESS (1 = a declaration tied to no
# listed definition, its own group)
defbody(){
    local cls="$1" tag="$2" p="$3" want="$4" got
    got="$( awk -F'\t' -v p="$p" '$1=="DEF" && $3==p { print $4; exit }' "$DIR/$tag.rows" )"
    [ "$got" = "$want" ]; say $? "[$cls] $tag: <def p=\"$p\"> bodyless=$want" \
        "[$cls] $tag: <def p=\"$p\"> bodyless='$got', want '$want' (defs: $( awk -F'\t' '$1=="DEF" { printf "%s/%s ", $3, $4 }' "$DIR/$tag.rows" ))"
}
# invariant CLASS TAG : every row has of_def, every K resolves to a <def>, and a row with no unmarked token is hedged
invariant(){
    local cls="$1" tag="$2" bad
    bad="$( awk -F'\t' '$1=="ROW" { if ($3=="-") print $2": no of_def"; else if ($3 ~ /!/) print $2": token names no <def> ("$3")" }' "$DIR/$tag.rows" )"
    if [ "$( nrows "$tag" )" -gt 0 ] && [ -z "$bad" ]; then ok "[$cls] $tag: invariant — all $( nrows "$tag" ) rows attributed or hedged, every K in the table"
    else no "[$cls] $tag: invariant broken: $( printf '%s' "$bad" | tr '\n' ';' | cut -c1-300 )"; fi
}

SP=string_piece.h:6; EV=eval_env.h:5

# ── (A) ninja-07 shape, C++ callers: the union names its definition per row ───────────────────────────────────────────
echo "(A) C++ --callers=empty (StringPiece::empty vs EvalString::empty)"
if ans a_cpp cpp callers s xml -- --callers=empty; then
    [ "$( groups a_cpp )" = 2 ]; say $? "[P] a_cpp: two <def> groups listed" \
        "[P] a_cpp: <def> rows=$( groups a_cpp ), want 2"
    expect P a_cpp UsesPiece "$SP"
    expect P a_cpp UsesEval  "$EV"
    expect P a_cpp UsesBoth  "$EV $SP"
    expect P a_cpp ManifestParser::ParseDefault "$EV"
    invariant P a_cpp
    rowset C a_cpp 4 "ManifestParser::ParseDefault UsesBoth UsesEval UsesPiece"
    # the std::string::empty confounder: the C++ standard-member gate declines it (no row), or the row names no group proven
    g="$( row a_cpp UsesStd )"
    case "$g" in
        "") ok "[N] a_cpp: UsesStd (std::string::empty) is no row" ;;
        *) bad=""; for t in $g; do case "$t" in *~n|*~s|*~t) ;; *) bad="$bad $t" ;; esac; done
           [ -z "$bad" ]; say $? "[N] a_cpp: UsesStd row hedged ($g)" "[N] a_cpp: UsesStd (a std::string member call) carries proven token(s):$bad" ;;
    esac
    sed 's/-->.*//' "$DIR/a_cpp.out" | grep -q 'of_def='; say $? "[P] a_cpp: the legend defines of_def= (present-only clause)" \
        "[P] a_cpp: of_def= is not defined in the answer's legend"
fi
# QUALNAME-1 observation: --callers --json, --safe-delete (xml) and the MCP find_referencing_symbols still print the caller row BARE
# (ParseDefault); only the XML --callers/--callees rows print Owner::name. Pinned as they are (a_cppj / a_sd / a_mcp); a future widening goes red here.
if ans a_cppj cpp - callers json -- --callers=empty --json; then
    expect P a_cppj UsesPiece "$SP"; expect P a_cppj UsesBoth "$EV $SP"
    rowset C a_cppj 4 "ParseDefault UsesBoth UsesEval UsesPiece"
fi
if ( cd "$FIX/cpp" && "$BIN" . --no-cache --callers=empty --format=columnar ) >"$DIR/a_col.out" 2>/dev/null && grep -q '<callers ' "$DIR/a_col.out"; then
    { grep -q '<def ' "$DIR/a_col.out" && grep -qE 'fields="[^"]*of_def' "$DIR/a_col.out"; }; say $? "[P] a_col: columnar carries the <def> table and an of_def column" \
        "[P] a_col: columnar lacks <def> rows or the of_def column: $( grep -oE 'fields="[^"]*"' "$DIR/a_col.out" )"
else no "a_col: columnar --callers=empty failed"; fi
if ans a_sd cpp safe-delete c xml -- --safe-delete=empty; then
    expect P a_sd UsesPiece "$SP"; expect P a_sd UsesEval "$EV"; expect P a_sd UsesBoth "$EV $SP"; expect P a_sd ParseDefault "$EV"
    invariant P a_sd
    rowset C a_sd 4 "ParseDefault UsesBoth UsesEval UsesPiece"
fi
if mcp a_mcp cpp calledBy find_referencing_symbols '"symbol":"empty"'; then
    expect P a_mcp UsesPiece "$SP"; expect P a_mcp UsesBoth "$EV $SP"; invariant P a_mcp
    rowset C a_mcp 4 "ParseDefault UsesBoth UsesEval UsesPiece"
fi
if mcp a_mcps cpp calledBy find_symbol '"symbol":"empty"'; then
    expect P a_mcps UsesEval "$EV"
    [ "$( groups a_mcps )" = 2 ]; say $? "[P] a_mcps: find_symbol's root symbol object rides beside a def_table of 2" \
        "[P] a_mcps: def_table rows=$( groups a_mcps ), want 2"
fi

# ── (B) ninja-26 shape, C++ callees: a declaration + its definition = ONE group; a split overload's arms are hedged ──
# train 29 (arity-min): the ninja-26 call `CanonicalizePath(&path, &bits)` passes 2 arguments, so the resolver now drops the
# 3-parameter overload (test/aritycheck.sh section 3b) and the call is PROVEN — it no longer serves as this gate's split. The split
# premise moved to `Normalize(&path)`: two 1-parameter overloads arity cannot tell apart, declared in util.h, defined in util.cc.
echo "(B) C++ --callees=ParseDefault (decl + def; CanonicalizePath proven by arity, Normalize overload split)"
if ans b_cpp cpp callees s xml -- --callees=ParseDefault; then
    plain N b_cpp split
    for n in Normalize; do
        n_split="$( awk -F'\t' -v n="$n" '$1=="ROW" && $2==n && $4 ~ /prov=split/' "$DIR/b_cpp.rows" | wc -l | tr -d ' ' )"
        [ "$n_split" = 2 ]; say $? "[P] b_cpp: both $n arms carry prov=\"split\"" \
            "[P] b_cpp: $n_split of 2 $n rows carry prov=\"split\""
    done
    # QUALNAME-1: the member callees print Owner::name; each probe also requires the ROW to exist, so the no-hedge
    # check cannot pass vacuously on a spelling that matches no row
    for n in EvalString::empty Lexer::ReadPath CanonicalizePath; do
        [ -n "$( row b_cpp "$n" )" ] && [ -z "$( rowflags b_cpp "$n" )" ]; say $? "[N] b_cpp: proven callee $n is a row and carries no hedge" \
            "[N] b_cpp: proven callee $n missing or hedged '$( rowflags b_cpp "$n" )'"
    done
    n_canon="$( awk -F'\t' '$1=="ROW" && $2=="CanonicalizePath"' "$DIR/b_cpp.rows" | wc -l | tr -d ' ' )"
    [ "$n_canon" = 1 ]; say $? "[N] b_cpp: CanonicalizePath lists ONE overload (the 3-parameter one cannot take 2 arguments)" \
        "[N] b_cpp: CanonicalizePath lists $n_canon overload rows, want 1"
fi
if ans b_cpp2 cpp callers s xml -- --callers=CanonicalizePath; then
    # two overloads, each declared in util.h and defined in util.cc: the declarations fold into their definitions
    [ "$( groups b_cpp2 )" = 2 ]; say $? "[N] b_cpp2: two groups (each util.h declaration folds into its util.cc definition)" \
        "[N] b_cpp2: <def> rows=$( groups b_cpp2 ), want 2"
    # ParseDefault's 2-argument call binds the 2-parameter overload alone, proven (it was hedged over both before train 29)
    expect N b_cpp2 ManifestParser::ParseDefault util.cc:2
    # the string* overload's own call passes three arguments: the resolver binds it to the 3-parameter overload, proven
    expect N b_cpp2 CanonicalizePath util.cc:6
fi
if ans b_norm cpp callers s xml -- --callers=Normalize; then
    [ "$( groups b_norm )" = 2 ]; say $? "[N] b_norm: two groups (each util.h declaration folds into its util.cc definition)" \
        "[N] b_norm: <def> rows=$( groups b_norm ), want 2"
    hedged P b_norm ManifestParser::ParseDefault "util.cc:9 util.cc:12"
fi
if ans b_rp cpp callers s xml -- --callers=ReadPath; then plain N b_rp; fi
# UsesPiece is declared in piece_user.cc with no #include that ties it to parser.cc's definition: the identity rule answers
# Unproven (may declare it, cannot prove it), and no row ties to that declaration (DrivePiece's call binds the definition), so
# the declaration is silent and the answer stays one group — the tmux/ninja prototype shape (a variadic or template-qualified
# declarator is Unproven the same way). A FOREIGN declaration (c_tal, c_hlp below: provably another function) is always listed.
if ans b_up cpp callers s xml -- --callers=UsesPiece; then plain N b_up; fi
if ans b_q cpp callers s xml -- --callers=string_piece.h:empty; then plain N b_q; fi
# Q1 (orchestrator ruling): the split-arm hedge rides single-definition answers too (by-design byte change on them)
if ans b_one cpp callees s xml -- --callees=PutInt; then
    plain N b_one split
    n_split="$( awk -F'\t' '$1=="ROW" && $2=="Fmt::put" && $4 ~ /prov=split/' "$DIR/b_one.rows" | wc -l | tr -d ' ' )"
    [ "$n_split" = 2 ]; say $? "[P] b_one: a single-definition --callees=PutInt marks both put arms prov=\"split\"" \
        "[P] b_one: $n_split of 2 put rows carry prov=\"split\" on the single-definition answer"
fi

# ── (C) near misses in one C++ file pair, the foreign declarations (C++ and C), the TS overload signatures ──────────────
echo "(C) near misses: overloads in one class, nested namespace, template specialisation, foreign declarations, TS overloads"
if ans c_put cpp callers s xml -- --callers=put; then
    hedged N c_put PutInt "fmt.cc:2 fmt.cc:3"
    hedged N c_put PutStr "fmt.cc:2 fmt.cc:3"
fi
if ans c_run cpp callers s xml -- --callers=run; then
    [ "$( groups c_run )" = 2 ]; say $? "[N] c_run: two groups (each fmt.h declaration folds into its own fmt.cc definition)" \
        "[N] c_run: <def> rows=$( groups c_run ), want 2"
    expect N c_run RunOuter fmt.cc:4
    expect N c_run RunInner fmt.cc:5
    sc4="$( awk -F'\t' '$1=="DEF" && $3=="fmt.cc:4" { print $5 }' "$DIR/c_run.rows" )"
    sc5="$( awk -F'\t' '$1=="DEF" && $3=="fmt.cc:5" { print $5 }' "$DIR/c_run.rows" )"
    { [ -n "$sc4" ] && [ -n "$sc5" ] && [ "$sc4" != "$sc5" ]; }; say $? "[N] c_run: the two run groups carry distinct sc= ($sc4 / $sc5)" \
        "[N] c_run: nested-namespace groups not told apart by sc= ('$sc4' / '$sc5')"
fi
# Box<T>::get (fmt.h:14) vs the Box<int> specialisation's get (fmt.h:18). The resolver binds GetInt(const Box<int>&) to the
# PRIMARY today (premise arm below), so a token naming the primary is a claim no proof backs: it must carry the ~t mark
# (bound to a primary template whose specialisation is listed), never stand unmarked, and never pose as a split (~s: the
# resolver split nothing). The specialisation itself, proven, is accepted (a future resolver fix).
gettok(){
    local tag="$1" n="$2" g t bad=""
    g="$( row "$tag" "$n" )"
    if [ -z "$g" ] || [ "$g" = "-" ]; then no "[N] $tag: $n carries no of_def ('$g')"; return; fi
    for t in $g; do case "$t" in "fmt.h:14~t"|"fmt.h:18") ;; *) bad="$bad $t" ;; esac; done
    [ -z "$bad" ]; say $? "[N] $tag: $n tokens '$g' (the primary only as ~t)" \
        "[N] $tag: $n tokens '$g' — not allowed:$bad (want fmt.h:14~t or fmt.h:18)"
}
if ans c_get cpp callers s xml -- --callers=get; then
    gettok c_get GetInt
    gettok c_get GetDouble
fi
if ( cd "$FIX/cpp" && "$BIN" . --no-cache --callers=get --legend=full ) >"$DIR/c_getl.out" 2>/dev/null; then
    sed 's/-->.*//' "$DIR/c_getl.out" | grep -q 'K~t'; say $? "[P] c_getl: the legend reads the ~t mark (K~t)" \
        "[P] c_getl: no K~t reading in the --legend=full answer"
else no "c_getl: --callers=get --legend=full failed"; fi
# S4 premise: the resolver's binding this lane hedges and does not fix (the resolver card flips this arm when it lands)
if ans c_geti cpp callees s xml -- --callees=GetInt; then
    grep -q 'n="Box::get" p="fmt.h:14"' "$DIR/c_geti.out"; say $? "[C] c_geti: premise — the resolver binds GetInt's b.get() to the primary (fmt.h:14)" \
        "[C] c_geti: premise moved — GetInt's get is no longer fmt.h:14 (resolver card landed? re-anchor c_get): $( grep -o '<s [^>]*>' "$DIR/c_geti.out" | head -2 | tr '\n' ' ' )"
fi
if ans c_tal cpp callers s xml -- --callers=tally; then
    [ "$( groups c_tal )" = 2 ]; say $? "[N] c_tal: a::detail::tally (declared) and b::detail::tally (defined) are two groups" \
        "[N] c_tal: <def> rows=$( groups c_tal ), want 2 (same leaf scope, another chain: never one group)"
    defbody N c_tal detail.h:3 1
    defbody N c_tal detail.cc:2 0
    invariant N c_tal
fi
if ans c_hlp c callers s xml -- --callers=helper; then
    [ "$( groups c_hlp )" = 2 ]; say $? "[N] c_hlp: C static helper (helper_a.c) and the prototype in helper_b.c are two groups" \
        "[N] c_hlp: <def> rows=$( groups c_hlp ), want 2 (internal linkage in another file: never one group)"
    defbody N c_hlp helper_b.c:2 1
    defbody N c_hlp helper_a.c:2 0
    invariant N c_hlp
fi
if ans c_lost c callers s xml -- --callers=lost; then plain N c_lost; fi          # C prototype + definition: one group
if ans c_pick ts callers s xml -- --callers=pick; then plain N c_pick; fi         # TS overload signatures + implementation
# langfacts-fold (train 29) pins, green on the build before the fold and after it: the TS overload-signature rule names TypeScript
# alone (src/defattrib.h). A TS method overload set is one group; a TS abstract / ambient member is a contract, a group of its
# own; and the same bodyless shape in Java, Go and Rust is never folded (a Java or Go interface method is its own group; a Rust
# trait requirement is no definition at all).
if ans lf_stash lf callers s xml -- --callers=stash; then
    plain N lf_stash; [ "$( rootf lf_stash defs )" = 3 ]; say $? "[N] lf_stash: a TS class method's three overload declarations are ONE group (defs=3, no table)" \
        "[N] lf_stash: defs=$( rootf lf_stash defs ), want 3"
fi
for c in measure:box.ts:7:box.ts:8 ring:box.ts:9:box.ts:10 doIt:Doer.java:2:Doer.java:3 Foo:fooer.go:4:fooer.go:7; do
    IFS=: read -r sym p1 l1 p2 l2 <<<"$c"; tg="lf_$sym"
    if ans "$tg" lf callers s xml -- --callers="$sym"; then
        [ "$( groups "$tg" )" = 2 ]; say $? "[N] $tg: the bodyless $sym and its implementation are TWO groups (a contract is never an overload signature)" \
            "[N] $tg: <def> rows=$( groups "$tg" ), want 2"
        defbody N "$tg" "$p1:$l1" 1
        defbody N "$tg" "$p2:$l2" 0
    fi
done
if ans lf_baz lf callers s xml -- --callers=baz; then plain N lf_baz; fi   # a Rust trait requirement is no definition: one def, one group
if ( cd "$FIX/cpp" && "$BIN" . --no-cache --for=empty ) >"$DIR/c_for.out" 2>/dev/null; then
    # QUALNAME-1: a member's scope folds into n= (no sc=): each definition is its own Owner::empty row
    n_d="$( grep -oE '<d [^>]*n="(EvalString|StringPiece)::empty"[^>]*>' "$DIR/c_for.out" | grep -vc 'sc="' )"
    n_bare="$( grep -oE '<d [^>]*n="empty"[^>]*>' "$DIR/c_for.out" | wc -l | tr -d ' ' )"
    { [ "$n_d" = 2 ] && [ "$n_bare" = 0 ]; }; say $? "[C] c_for: --for=empty serves each definition as its own EvalString::empty / StringPiece::empty row, no sc=, no bare row ($n_d)" \
        "[C] c_for: --for=empty qualified rows=$n_d (want 2), bare n=\"empty\" rows=$n_bare (want 0)"
else no "c_for: --for=empty failed"; fi

# ── (D) impact: per-row attribution through the transitive reach, and the file rollup ───────────────────────────────
echo "(D) C++ --impact=empty"
if ans d_imp cpp impact s xml -- --impact=empty; then
    expect P d_imp UsesPiece "$SP"; expect P d_imp UsesEval "$EV"; expect P d_imp UsesBoth "$EV $SP"
    expect P d_imp DrivePiece "$SP";  expect P d_imp DriveEval "$EV"; expect P d_imp ManifestParser::ParseDefault "$EV"
    invariant P d_imp
    rowset C d_imp 6 "DriveEval DrivePiece ManifestParser::ParseDefault UsesBoth UsesEval UsesPiece"
fi
if ans d_rf cpp impact rf xml -- --impact=empty --limit=2; then
    expect P d_rf parser.cc "$EV $SP"
    expect P d_rf eval_user.cc "$EV"
    rowset C d_rf 6 "eval_user.cc parser.cc"
fi
if ans d_impj cpp - reach json -- --impact=empty --json; then
    # the row array key of the JSON dialect is read off the answer, never assumed
    key="$( python3 -c 'import json,sys; j=json.load(open(sys.argv[1])); print(next((k for k,v in j.items() if isinstance(v,list) and v and isinstance(v[0],dict) and "n" in v[0]), "-"))' "$DIR/d_impj.out" 2>/dev/null )"
    python3 "$DIR/amd.py" "$DIR/d_impj.out" json - "$key" >"$DIR/d_impj.rows"
    expect P d_impj DrivePiece "$SP"
fi
if mcp d_mcp cpp s impact '"symbol":"empty"'; then expect P d_mcp DriveEval "$EV"; fi
if ans d_one cpp impact s xml -- --impact=string_piece.h:empty; then plain N d_one; fi

# ── (E) --path endpoints ──────────────────────────────────────────────────────────────────────────────────────────────
echo "(E) C++ --path endpoints"
if ans e_un cpp path s xml -- --path=Clear,empty; then
    [ "$( rootf e_un to_p )" = "-" ]; say $? "[P] e_un: unreached multi-definition to= carries no to_p" \
        "[P] e_un: reachable=0 with to_defs=2 still claims to_p=\"$( rootf e_un to_p )\""
    [ "$( rootf e_un from_p )" = "eval_env.h:4" ]; say $? "[N] e_un: the single-definition from= keeps from_p" \
        "[N] e_un: from_p='$( rootf e_un from_p )'"
fi
if ans e_re cpp path s xml -- --path=DrivePiece,empty; then
    [ "$( rootf e_re to_p )" = "$SP" ]; say $? "[C] e_re: a reached multi-definition to= names the bound one ($SP)" \
        "[C] e_re: to_p='$( rootf e_re to_p )'"
fi
if ans e_sp cpp path s xml -- --path=PutInt,put; then
    # the hop into put is one arm of a split call (Fmt::put(int) vs Fmt::put(const char*)): the row that ends the path says
    # so, and the root does not claim the arm the BFS happened to take as the definition put was bound to
    # path-owners (train 30): a member hop names its owner, so the hop into Fmt::put reads n="Fmt::put" in C++ (the language separator) (pathownercheck)
    case "$( rowflags e_sp Fmt::put )" in *prov=split*) ok "[P] e_sp: the split hop into a multi-definition to= carries prov=\"split\"" ;;
        *) no "[P] e_sp: the hop into Fmt::put is a split arm but carries '$( rowflags e_sp Fmt::put )'" ;; esac
    [ "$( rootf e_sp to_p )" = "-" ]; say $? "[P] e_sp: a to= bound only by a split hop carries no to_p" \
        "[P] e_sp: to_p=\"$( rootf e_sp to_p )\" claimed for a to= the path reached by a split arm"
    [ "$( rootf e_sp from_p )" = "fmt.cc:6" ]; say $? "[N] e_sp: the single-definition from= keeps from_p" \
        "[N] e_sp: from_p='$( rootf e_sp from_p )'"
fi
if mcp e_mcp cpp s path_between '"from":"Clear","to":"empty"'; then
    [ "$( rootf e_mcp to_p )" = "-" ]; say $? "[P] e_mcp: MCP path_between drops the unbound to_p too" \
        "[P] e_mcp: MCP to_p='$( rootf e_mcp to_p )'"
fi
if mcp e_mcps cpp s path_between '"from":"PutInt","to":"put"'; then
    [ "$( rootf e_mcps to_p )" = "-" ]; say $? "[P] e_mcps: MCP path_between drops a to_p bound by a split hop" \
        "[P] e_mcps: MCP to_p='$( rootf e_mcps to_p )'"
fi

# ── (F) the other languages: nfpm-06 (Go), entity identity in one file (Python, TypeScript, Java), JS, Ruby, hedged (Rust, ObjC)
echo "(F) Go / Python / TypeScript / Java / JavaScript / Ruby / Rust / ObjC"
if ans f_go go callers s xml -- --callers=Get; then
    expect P f_go Package  "deb/deb.go:7 files/files.go:4"
    expect P f_go Describe "deb/deb.go:7"
    expect P f_go ListOnly "files/files.go:4"
    expect P f_go Stamp    "modtime.go:4"
    [ "$( groups f_go )" = 3 ]; say $? "[P] f_go: three <def> groups" \
        "[P] f_go: <def> rows=$( groups f_go ), want 3"
    rowset C f_go 4 "Describe ListOnly Package Stamp"
fi
if mcp f_gomcp go calledBy find_referencing_symbols '"symbol":"Get"'; then
    expect P f_gomcp Describe "deb/deb.go:7"
    rowset C f_gomcp 4 "Describe ListOnly Package Stamp"
fi
if ans f_py py callers s xml -- --callers=render; then
    expect P f_py draw_widget widgets.py:2
    expect P f_py draw_canvas widgets.py:6
    expect P f_py draw_both   "widgets.py:2 widgets.py:6"
    # draw_mixed calls Widget.render twice: w.render() (proven) and thing.render() (split between the two by name). The graph keeps
    # ONE provenance per edge (resolve.h edgeProvenance: split outranks plain), so the Widget edge reads ~s — a hedge, never a claim
    expect P f_py draw_mixed  "widgets.py:2~s widgets.py:6~n"
    rowset C f_py 4 "draw_both draw_canvas draw_mixed draw_widget"
fi
if ans f_ts ts callers s xml -- --callers=area; then
    expect P f_ts circleArea shapes.ts:2; expect P f_ts squareArea shapes.ts:5; expect P f_ts bothAreas "shapes.ts:2 shapes.ts:5"
    rowset C f_ts 3 "bothAreas circleArea squareArea"
fi
if ans f_java java callers s xml -- --callers=lookup; then
    expect P f_java fromCache Store.java:2; expect P f_java fromRegistry Store.java:5; expect P f_java fromBoth "Store.java:2 Store.java:5"
    rowset C f_java 3 "fromBoth fromCache fromRegistry"
fi
if ans f_js js callers s xml -- --callers=area; then
    expect P f_js circleArea shapes.js:1; expect P f_js squareArea shapes.js:2
    rowset C f_js 2 "circleArea squareArea"
fi
if ans f_rb rb callers s xml -- --callers=area; then
    expect P f_rb circle_area shapes.rb:2; expect P f_rb square_area shapes.rb:7
    rowset C f_rb 2 "circle_area square_area"
fi
# Re-anchored (lane rust-std-rows, #405): `iter` is in the standard-member gate's Rust row, so the multi-definition hedge this
# arm pins moved to `walk`, the same two-impl shape under a name no table holds. Re-anchored again (lane rust-receivers):
# `b: &Book` / `s: &Shelf` now TYPE their receivers, so walk_items / walk_books are each proven onto ONE definition, and the
# hedge moved to walk_any — `t: &T`, a generic no rule types (the premise: a receiver nothing proves, two impls of the name).
if ans f_rs rs callers s xml -- --callers=walk; then
    hedged P f_rs walk_any "src/lib.rs:12 src/lib.rs:15"
    case "$( rowflags f_rs walk_any )" in *via=name*) ok "[N] f_rs: the via=\"name\" row hedge stays on the untyped walk_any" ;; *) no "[N] f_rs: via=\"name\" lost on walk_any" ;; esac
    expect P f_rs walk_items "src/lib.rs:12"
    expect P f_rs walk_books "src/lib.rs:15"
    rowset C f_rs 3 "walk_any walk_books walk_items"
fi
# train 30 (call-result typing x #405): a Rust member call carries its receiver PATH, so `self.items.iter()` /
# `self.books.iter()` inside each iter is a chained receiver whose field is a Vec, and the standard-member row declines it
# (before, `self` alone proved the caller's own method, a dropped self-loop). Lane rust-receivers: `b.iter()` / `s.iter()` on
# the Book / Shelf parameters are typed now and BIND (one row each), so 2 declined remain (the two Vec fields).
if ans f_rs_iter rs callers s xml -- --callers=iter; then
    if [ "$( nrows f_rs_iter )" = 2 ] && grep -q 'declined_calls="2"' "$DIR/f_rs_iter.out" && ! grep -q 'via="name"' "$DIR/f_rs_iter.out"; then
        ok "[N] f_rs_iter: b.iter() / s.iter() on Book / Shelf parameters bind (2 rows, unhedged); self.items.iter() / self.books.iter() are declined (declined_calls=2)"
    else
        no "[N] f_rs_iter: want 2 unhedged rows and declined_calls=\"2\" (test/stdmembergatecheck.sh arm R); got $( nrows f_rs_iter ) row(s): $( head -c 300 "$DIR/f_rs_iter.out" )"
    fi
fi
if ans f_objc objc callers s xml -- --callers=area; then
    hedged P f_objc circleArea "Shapes.m:6 Shapes.m:12"
    hedged P f_objc squareArea "Shapes.m:6 Shapes.m:12"
    rowset C f_objc 2 "circleArea squareArea"
fi
if ans f_py1 py callers s xml -- --callers=draw_widget; then
    # a single definition with no caller: the root, no rows — read the table count only
    [ "$( groups f_py1 )" = 0 ]; say $? "[N] f_py1: single definition, no <def> table" \
        "[N] f_py1: <def> rows on a single definition"
fi

# ── (H) the definition-table cap: 20 same-named definitions, 12 callers — the table lists what the page names ─────────
echo "(H) the definition-table cap (16): a generated 20-definition selector"
mkdir -p "$DIR/capfix"
python3 - "$DIR/capfix/caps.py" <<'PY'
import sys
out = []
for k in range(20):
    out.append('class C%02d:\n    def go(self):\n        return %d\n' % (k, k))
for k in range(12):
    out.append('def use_%02d():\n    x = C%02d()\n    return x.go()\n' % (k, k))
open(sys.argv[1], 'w').write('\n'.join(out))
PY
FIXSAVE="$FIX"; FIX="$DIR"
if ans h_all capfix callers s xml -- --callers=go; then
    [ "$( groups h_all )" = 12 ] && [ "$( rootf h_all defs_listed )" = 12 ]; say $? "[P] h_all: 20 groups, 12 rows: the table lists the 12 the rows name, defs_listed=\"12\"" \
        "[P] h_all: <def> rows=$( groups h_all ) defs_listed='$( rootf h_all defs_listed )', want 12 / 12"
    invariant P h_all
fi
if ans h_p1 capfix callers s xml -- --callers=go --limit=5; then
    [ "$( groups h_p1 )" = 5 ] && [ "$( rootf h_p1 defs_listed )" = 5 ]; say $? "[P] h_p1: page 1 (--limit=5) lists its 5 groups, defs_listed=\"5\"" \
        "[P] h_p1: <def> rows=$( groups h_p1 ) defs_listed='$( rootf h_p1 defs_listed )', want 5 / 5"
    invariant P h_p1
    nxt="$( rootf h_p1 next_offset )"
    if [ "$nxt" = 5 ] && ans h_p2 capfix callers s xml -- --callers=go --limit=5 --offset="$nxt"; then
        invariant P h_p2
        both="$( { awk -F'\t' '$1=="ROW" { print $2 }' "$DIR/h_p1.rows"; awk -F'\t' '$1=="ROW" { print $2 }' "$DIR/h_p2.rows"; } | sort | uniq -d | tr '\n' ' ' )"
        [ -z "$both" ] && [ "$( nrows h_p2 )" = 5 ]; say $? "[C] h_p2: next_offset=$nxt pages on to 5 new rows, each attributed in its own table" \
            "[C] h_p2: page 2 rows=$( nrows h_p2 ), repeated from page 1: '$both'"
    else no "[C] h_p1: next_offset='$nxt' (want 5) or the page-2 call failed"; fi
fi
# R2 (final review): above the cap, by-name ties are not enumerated. use_any reaches go by name alone: no of_def, via="name"
# is its hedge; use_mix holds a split arm into C05.go plus by-name ties: its split token and ONE bare ~n. The cut table then
# lists only the groups a printed token names (the three proven callers' and C05's).
python3 - "$DIR/capfix2/caps.py" <<'PY'
import os, sys
os.makedirs(os.path.dirname(sys.argv[1]), exist_ok=True)
out = []
for k in range(20):
    out.append('class C%02d:\n    def go(self):\n        return %d\n' % (k, k))
for k in range(3):
    out.append('def use_%02d():\n    x = C%02d()\n    return x.go()\n' % (k, k))
out.append('def use_any(o):\n    return o.go()\n')
out.append('def use_mix(o):\n    y = C05()\n    y.go()\n    return o.go()\n')
open(sys.argv[1], 'w').write('\n'.join(out))
PY
# cutinv TAG : on a cut table every row has of_def or is via="name", and every K resolves to a listed <def>
cutinv(){
    local tag="$1" bad
    bad="$( awk -F'\t' '$1=="ROW" { if ($3=="-" && $4 !~ /via=name/) print $2": no of_def and no via=name"; else if ($3 ~ /!/) print $2": token names no <def> ("$3")" }' "$DIR/$tag.rows" )"
    if [ "$( nrows "$tag" )" -gt 0 ] && [ -z "$bad" ]; then ok "[P] $tag: cut invariant — every row attributed or via=\"name\", every K in the table"
    else no "[P] $tag: cut invariant broken: $( printf '%s' "$bad" | tr '\n' ';' | cut -c1-300 )"; fi
}
for form in xml json; do
    t=h2_$form
    if [ "$form" = json ]; then ans "$t" capfix2 callers callers json -- --callers=go --json; else ans "$t" capfix2 callers s xml -- --callers=go; fi || continue
    expect P "$t" use_any -
    case "$( rowflags "$t" use_any )" in *via=name*) ok "[P] $t: use_any (by name alone) keeps via=\"name\"" ;; *) no "[P] $t: use_any lost via=\"name\" ('$( rowflags "$t" use_any )')" ;; esac
    expect P "$t" use_mix "caps.py:22~s ~n"
    expect C "$t" use_00 caps.py:2
    { [ "$( groups "$t" )" = 4 ] && [ "$( rootf "$t" defs_listed )" = 4 ]; }; say $? "[P] $t: the cut table lists the 4 groups a printed token names, defs_listed=4" \
        "[P] $t: <def> rows=$( groups "$t" ) defs_listed='$( rootf "$t" defs_listed )', want 4 / 4"
    cutinv "$t"
done
if ans h2_imp capfix2 impact s xml -- --impact=go; then
    expect P h2_imp use_any -
    expect P h2_imp use_mix "caps.py:22~s ~n"
    { [ "$( groups h2_imp )" = 4 ] && [ "$( rootf h2_imp defs_listed )" = 4 ]; }; say $? "[P] h2_imp: impact's cut table lists 4 groups, defs_listed=4" \
        "[P] h2_imp: <def> rows=$( groups h2_imp ) defs_listed='$( rootf h2_imp defs_listed )', want 4 / 4"
    cutinv h2_imp
fi
if ( cd "$DIR/capfix2" && "$BIN" . --no-cache --callers=go --legend=full ) >"$DIR/h2_full.out" 2>/dev/null; then
    sed -n '1,/-->/p' "$DIR/h2_full.out" | grep -q 'bare ~n'; say $? "[P] h2_full: the full legend reads the cut table's bare ~n" \
        "[P] h2_full: no legend reading of the bare ~n token"
    if command -v xmllint >/dev/null 2>&1; then
        xmllint --noout "$DIR/h2_full.out" 2>/dev/null; say $? "[C] h2_full: --legend=full well-formed" "[C] h2_full: --legend=full malformed"
    fi
    ( cd "$DIR/capfix2" && "$BIN" . --no-cache --callers=go ) 2>/dev/null | sed -n '1,/-->/p' | grep -q 'bare ~n'; say $? "[P] h2_cmp: the compact legend reads the bare ~n" \
        "[P] h2_cmp: the compact legend does not read the bare ~n"
else no "h2_full: --callers=go --legend=full failed"; fi
FIX="$FIXSAVE"

# ── (J) R1 (final review): an untied declaration is dropped only when that leaves ONE group; a printed table lists it ──────
echo "(J) untied declarations on a printed table"
if ans j_u2 u2 callers s xml -- --callers=scan_tok; then
    [ "$( groups j_u2 )" = 3 ]; say $? "[P] j_u2: three groups listed (definition, untied prototype, static namesake)" \
        "[P] j_u2: <def> rows=$( groups j_u2 ), want 3 (an untied prototype vanished from a printed table)"
    defbody P j_u2 prog2/main.c:2 1
    defbody C j_u2 prog1/util.c:2 0
    defbody C j_u2 prog3/other.c:2 0
    expect C j_u2 use_tok1 prog1/util.c:2
    expect C j_u2 use_tok3 prog3/other.c:2
fi
if ans j_u2i u2 impact s xml -- --impact=scan_tok; then
    [ "$( groups j_u2i )" = 3 ]; say $? "[P] j_u2i: impact lists the three groups" "[P] j_u2i: <def> rows=$( groups j_u2i ), want 3"
fi
# the one-group sibling (u1 = prog1 + prog2): dropping the untied prototype leaves one group, so the answer stays plain
mkdir -p "$DIR/u1/prog1" "$DIR/u1/prog2"; cp "$FIX/u2/prog1/util.c" "$DIR/u1/prog1/"; cp "$FIX/u2/prog2/main.c" "$DIR/u1/prog2/"
FIXSAVE="$FIX"; FIX="$DIR"
if ans j_u1 u1 callers s xml -- --callers=scan_tok; then plain C j_u1; fi
FIX="$FIXSAVE"

# ── (I) Q1 on --for: a body's <calls> row (and a hop's) whose edge is a resolver split arm carries prov="split", defined in the
# bundle's first-screen legend; a proven callee row does not ──────────────────────────────────────────────────────────────────
echo "(I) Q1: --for <calls> rows of a split call"
if ( cd "$FIX/cpp" && "$BIN" . --no-cache --for=PutInt ) >"$DIR/i_for.out" 2>/dev/null && grep -q '<ctx' "$DIR/i_for.out"; then
    n_split="$( grep -oE '<c n="put"[^>]* prov="split"' "$DIR/i_for.out" | wc -l | tr -d ' ' )"
    [ "$n_split" = 2 ]; say $? "[P] i_for: both put arms in PutInt's <calls> carry prov=\"split\"" \
        "[P] i_for: $n_split of 2 put <calls> rows carry prov=\"split\""
    sed 's/-->.*//' "$DIR/i_for.out" | grep -q 'prov=split'; say $? "[P] i_for: the first-screen legend defines prov=split" \
        "[P] i_for: prov=split is not defined in the --for header"
else no "i_for: --for=PutInt failed"; fi
if ( cd "$FIX/cpp" && "$BIN" . --no-cache --for=UsesBoth ) >"$DIR/i_for2.out" 2>/dev/null && grep -q '<ctx' "$DIR/i_for2.out"; then
    ! grep -q 'prov="split"' "$DIR/i_for2.out"; say $? "[N] i_for2: proven callees (both empty) carry no prov=" \
        "[N] i_for2: a proven callee row carries prov=\"split\""
else no "i_for2: --for=UsesBoth failed"; fi
if command -v xmllint >/dev/null 2>&1; then
    ( cd "$FIX/cpp" && "$BIN" . --no-cache --for=PutInt --legend=full ) >"$DIR/i_forf.out" 2>/dev/null && xmllint --noout "$DIR/i_forf.out" 2>/dev/null
    say $? "[C] i_forf: --for=PutInt --legend=full well-formed (the prov=split clause rides)" "[C] i_forf: --for=PutInt --legend=full malformed or failed"
fi

# ── (G) well-formedness and determinism ───────────────────────────────────────────────────────────────────────────────
echo "(G) well-formedness, determinism"
if command -v xmllint >/dev/null 2>&1; then
    for t in a_cpp a_col a_sd b_cpp c_get d_imp d_rf e_un e_sp f_go h_p1; do
        [ -s "$DIR/$t.out" ] || continue
        xmllint --noout "$DIR/$t.out" 2>/dev/null; say $? "[C] $t: well-formed XML" \
            "[C] $t: malformed XML"
    done
    for v in "--callers=empty" "--callees=ParseDefault" "--impact=empty" "--safe-delete=empty" "--path=PutInt,put" "--callers=get" "--callers=empty --format=columnar"; do
        # shellcheck disable=SC2086
        ( cd "$FIX/cpp" && "$BIN" . --no-cache $v --legend=full ) >"$DIR/g_full.out" 2>/dev/null && xmllint --noout "$DIR/g_full.out" 2>/dev/null; say $? "[C] g_full: $v --legend=full well-formed" \
            "[C] g_full: $v --legend=full malformed or failed"
    done
else
    printf '  SKIP  xml well-formedness (no xmllint)\n'
fi
( cd "$FIX/cpp" && "$BIN" . --no-cache --callers=empty ) >"$DIR/g_det.out" 2>/dev/null
cmp -s "$DIR/g_det.out" "$DIR/a_cpp.out"; say $? "[C] determinism: --callers=empty byte-identical run to run" \
    "[C] --callers=empty differs run to run"

# [S] train 28 (for-body-slot x attrib-multidef): the --for body slot's <calls> rows label a split arm prov="split" as every
# other --for body does. "how does ManifestParser ParseDefault work" picks ParseDefault as the slot owner (pick="name"), and
# its Normalize call is the fixture's split call (CanonicalizePath until train 29 made that call proven by arity): the hop row already carried prov="split"; the slot body's two
# <c n="..."> split rows did not before the fix (the same arm read as a plain callee there).
( cd "$FIX/cpp" && "$BIN" . --no-cache --for="how does ManifestParser ParseDefault work" ) >"$DIR/s_slot.out" 2>/dev/null; s_rc=$?
s_counts="$( python3 -c '
import re, sys
d = open( sys.argv[ 1 ], encoding="utf-8", errors="replace" ).read()
m = re.search( r"<bodies [^>]*pick=\"name\"[^>]*>(.*?)</bodies>", d, re.S )
if not m: print( "none" ); sys.exit( 0 )
rows = re.findall( r"<c n=\"Normalize\"[^>]*>", m.group( 1 ) )
legend = d.split( "<sigs", 1 )[ 0 ]
print( len( rows ), sum( "prov=\"split\"" in r for r in rows ), int( "c prov=split" in legend or "prov=\"split\" on a <c> row" in legend ) )
' "$DIR/s_slot.out" )"
if [ "$s_rc" -ne 0 ] || [ "$s_counts" = none ] || [ -z "$s_counts" ]; then
    no "[S] premise: the slot did not ride (rc=$s_rc, no <bodies pick=\"name\">)"
else
    read -r s_all s_split s_leg <<<"$s_counts"
    if [ "$s_all" -ge 1 ] && [ "$s_split" = "$s_all" ]; then ok "[S] the body slot labels its $s_all Normalize split-arm row(s) prov=\"split\""
    else no "[S] the body slot's Normalize rows: $s_split of $s_all carry prov=\"split\""; fi
    if [ "$s_leg" = 1 ]; then ok "[S] the header defines the split reading the slot's rows use"
    else no "[S] no split reading in the header of an answer that labels a split arm"; fi
fi

# [S] MCP twin (CR pre-pass A): the MCP for tool's slot body labels the same two rows, and defines the reading once beside
# them (its header never does: splitLegendInHead is false there) — a duplicate or a missing definition goes red.
printf '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{}}\n{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"for","arguments":{"path":"%s","task":"how does ManifestParser ParseDefault work"}}}\n' \
    "$FIX/cpp" | perl -e 'alarm 120; exec @ARGV' "$BIN" --mcp 2>"$DIR/s_mcp.err" | tail -1 >"$DIR/s_mcp.out"
s_mcp="$( python3 -c '
import json, re, sys
try: t = json.loads( open( sys.argv[ 1 ] ).read() )[ "result" ][ "content" ][ 0 ][ "text" ]
except Exception: print( "none" ); sys.exit( 0 )
m = re.search( r"<bodies [^>]*pick=\"name\"[^>]*>(.*?)</bodies>", t, re.S )
if not m: print( "none" ); sys.exit( 0 )
rows = re.findall( r"<c n=\"Normalize\"[^>]*>", m.group( 1 ) )
print( len( rows ), sum( "prov=\"split\"" in r for r in rows ), t.count( "prov=\"split\" on a <c> row" ) )
' "$DIR/s_mcp.out" )"
if [ "$s_mcp" = none ] || [ -z "$s_mcp" ]; then no "[S] MCP premise: no slot body in the MCP for answer"
else
    read -r m_all m_split m_def <<<"$s_mcp"
    if [ "$m_all" -ge 1 ] && [ "$m_split" = "$m_all" ] && [ "$m_def" = 1 ]; then ok "[S] MCP for: the slot's $m_all Normalize rows carry prov=\"split\", the reading defined once"
    else no "[S] MCP for: $m_split of $m_all rows carry prov=\"split\", the reading defined $m_def time(s) (want all, once)"; fi
fi
# [S2] (CR pre-pass A): a spent soft target serves the hops cut marker and no row carries prov="split", so the present-only
# split reading leaves the header with them (the lane cleared it on the spent-ceiling switch forbudget-soft retired); at 500
# the hop row rides and so does the reading (the control).
for lg in compact full; do
    for n in 100 500; do
        ( cd "$FIX/cpp" && "$BIN" . --no-cache --for="how does ManifestParser ParseDefault work" --token-budget=$n --legend=$lg ) >"$DIR/s2_${n}_$lg.out" 2>/dev/null; s2_rc=$?
        s2="$( python3 -c '
import re, sys
d = open( sys.argv[ 1 ], encoding="utf-8", errors="replace" ).read()
head = d.split( "<sigs", 1 )[ 0 ]
clause = int( "c prov=split" in head or "prov=\"split\" on a <c> row" in head )
rows = len( re.findall( r"<c [^>]*prov=\"split\"", d ) )
marker = int( bool( re.search( r"<hops shown=\"0\"[^>]*capped=\"1\"", d ) ) )
print( rows, clause, marker )' "$DIR/s2_${n}_$lg.out" )"
        read -r r2 c2 k2 <<<"$s2"
        if [ "$s2_rc" -ne 0 ] || [ -z "$s2" ]; then no "[S2] $lg @$n: no answer (rc=$s2_rc)"
        elif [ "$n" = 100 ]; then
            if [ "$k2" = 1 ] && [ "$r2" = 0 ] && [ "$c2" = 0 ]; then ok "[S2] $lg @100: the hops cut marker, no split row, no split reading"
            else no "[S2] $lg @100: marker=$k2 split rows=$r2 split reading=$c2 (want 1 0 0)"; fi
        else
            if [ "$r2" -ge 1 ] && [ "$c2" = 1 ]; then ok "[S2] $lg @500 control: $r2 split row(s) and the reading ride"
            else no "[S2] $lg @500 control: split rows=$r2 reading=$c2 (want >=1 and 1)"; fi
        fi
    done
done

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
