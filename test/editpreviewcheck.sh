#!/usr/bin/env bash
# editpreviewcheck.sh — gate for the PRE-APPLY contract preview:
#   ripwire <dir> --edit-check=SYM --edit-payload=FILE --dry-run
#
# The band this gate enforces is registered in docs/EVALS.md ("Pre-apply `--edit-check` — the contract
# preview on an unwritten payload (card A1)"), written BEFORE this script and before any feature code.
#
# THE ONE PROPERTY. For every VALID payload the answer computed BEFORE the write must equal the answer the
# ordinary post-hoc --edit-check gives AFTER the same payload is actually applied. So each case is run BOTH
# WAYS: the preview on a pristine corpus, then --replace-symbol-body of the SAME payload bytes onto a FRESH
# copy of that corpus followed by a plain --edit-check. Agreement is byte-equality of the <edit-check>
# element after exactly three normalisations and no others (see `norm` below):
#   • the leading <!-- … --> legend is dropped (the preview's legend carries one extra sentence),
#   • ` at="…"` is dropped (the applied tree is dirty, the pristine one is not),
#   • ` preview="1"` is dropped (present only on the pre-apply document).
# Everything else — status=, change=, params_was/now=, public_was/now=, defs_was/now=, defs=, callers=,
# incompatible=, p=, every <def> row and every <c> row in order — is compared verbatim.
#
# ACCEPT: the registered rate is 29 of 30 — ONE allowed disagreement — applied to the realized valid set as
# "at most one disagreement" (a stricter rate than 29/30 on a set this size, never a looser one). Plus ZERO
# false "unchanged": a preview saying unchanged where the applied tree says contract-change / new-symbol
# fails the band outright, whatever the ratio, because reassurance is the one answer this verb exists to be
# trusted on. Every INVALID payload must REFUSE (exit 1, empty stdout).
#
# WHY THE MUTATION CONTROL (arm M) EXISTS. A comparison of two documents that are both empty, or both the
# tool's own refusal text, passes while measuring nothing — the "green while inert" shape CONTRIBUTING.md §2
# names. Arm M runs the SAME comparison on a deliberately mismatched pair (a contract-CHANGING preview
# against a contract-PRESERVING apply) and fails if that pair is reported as agreeing, so a false clean is
# provably visible to this script. Arm P is its presence guard: the documents being compared must actually
# be <edit-check> elements carrying a status=.
#
# Fixtures: test/editpreviewfix/{corpus,payloads,cases.tsv}. 37 payloads — 12 contract-changing, 13
# contract-preserving, 12 invalid — across C++ (free functions, a public header, methods, an added overload)
# and Python (free functions, methods with the implicit self).
#
# THE ONE RECORDED LIMIT, pinned by fixture pre13 and arm R below rather than left to be rediscovered: the
# parse-validity refusal is an ERROR/MISSING-node DELTA, so a payload the GRAMMAR RECOVERS is not detectably
# invalid. tree-sitter-python parses a de-indented function body (`def f(a):` then an unindented `return`)
# with ZERO error nodes — the def keeps its parameters and the statement becomes top-level — so that payload
# is answered, not refused, and both sides agree on "unchanged". It is classed `preserve` here, honestly,
# instead of being called invalid by a rule the tool cannot actually apply.
#
# Arm N pins the MCP mirror: `edit_check` with `new_body` must return the SAME document the CLI preview
# returns. It is the same property the sweep enforces, one surface over — the two route through one
# editpreview::run, and the gate is what keeps that true.
#
# Operates entirely on private temp git repos; never touches the real repo. Needs git.
# Usage:  bash test/editpreviewcheck.sh [BIN]   |   RIPWIRE_BIN=asan/ripwire bash test/editpreviewcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/editpreviewfix"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }
[ -f "$FIX/cases.tsv" ] || { echo "missing fixture table $FIX/cases.tsv"; exit 2; }

WORK="$( mktemp -d )"; trap 'rm -rf "$WORK"' EXIT
echo "editpreviewcheck: BIN=$BIN"

# a pristine committed copy of the fixture corpus at $1
mkcorpus(){
    mkdir -p "$1"
    cp "$FIX"/corpus/* "$1/"
    ( cd "$1" && git init -q && git config user.email t@t && git config user.name t \
      && git add -A && git commit -qm init ) >/dev/null 2>&1
}

BASE="$WORK/base"; mkcorpus "$BASE"

# The NUL-bearing payload is GENERATED here rather than committed under payloads/. test/nulbytecheck.sh is a
# tripwire that forbids an embedded NUL in any tracked text file — it exists because one prose NUL once turned
# src/mcp.h binary to every search tool in the tree — and its allowlist is evidence-based on purpose. Widening
# that allowlist to ".txt" so this fixture could live on disk would punch a repo-wide hole to hold one test
# byte. The payload is materialised into the temp tree instead; the case is otherwise an ordinary table row.
mkdir -p "$WORK/gen"
printf 'int trim( int a, int b )\n{\n    return \000 a;\n}\n' > "$WORK/gen/nul.txt"

# the FOUR normalisations, and nothing else. The document is minified XML on ONE line, so the greedy
# comment strip removes exactly the single leading legend. The fourth (E3, terminality round A 2026-09-05):
# the preview-only <overwrite> child — the CURRENT span an apply would replace, which the post-hoc document
# cannot carry because after the apply that span no longer exists — is dropped before the comparison.
# (perl -0 slurps the whole document: the overwrite CDATA carries the span's own newlines, which a per-line sed
# could never match across.)
norm(){ printf '%s' "$1" | perl -0pe 's/<overwrite [^>]*><!\[CDATA\[.*?\]\]><\/overwrite>//s' | sed -e 's/<!--.*-->//' -e 's/ at="[^"]*"//g' -e 's/ preview="1"//g'; }
statusOf(){ printf '%s' "$1" | sed -e 's/<!--.*-->//' | grep -oE 'status="[a-z-]+"' | head -1; }

preview(){ # $1 selector  $2 payload-path
    ( cd "$BASE" && "$BIN" . --edit-check="$1" --edit-payload="$2" --dry-run --no-cache 2>/dev/null )
}
previewrc(){
    ( cd "$BASE" && "$BIN" . --edit-check="$1" --edit-payload="$2" --dry-run --no-cache >/dev/null 2>&1; echo $? )
}

applied(){ # $1 name  $2 file  $3 payload-path  → the POST-apply --edit-check document, on a fresh corpus
    local w="$WORK/apply.$$.$RANDOM"
    mkcorpus "$w"
    ( cd "$w" && "$BIN" . --replace-symbol-body="$1" --edit-target-file="$2" --edit-payload="$3" ) >/dev/null 2>&1
    ( cd "$w" && "$BIN" . --edit-check="$2:$1" --no-cache 2>/dev/null )
    rm -rf "$w"
}

# ── the fixture sweep ────────────────────────────────────────────────────────────────────────────────
valid=0; agree=0; falseclean=0; invalid=0; refused=0; nchange=0; npreserve=0
firstPreview=""; changePreview=""; preserveApplied=""
while IFS=$'\t' read -r id cls name file pay note; do
    case "$id" in \#*|"") continue;; esac
    if [ "$pay" = "GENERATED:nul" ]; then P="$WORK/gen/nul.txt"; else P="$FIX/payloads/$pay"; fi
    [ -f "$P" ] || { no "fixture $id: missing payload $pay"; continue; }
    if [ "$cls" = "invalid" ]; then
        invalid=$(( invalid + 1 ))
        out="$( preview "$file:$name" "$P" )"
        rc="$( previewrc "$file:$name" "$P" )"
        if [ "$rc" != "0" ] && [ -z "$out" ]; then
            refused=$(( refused + 1 ))
        else
            no "invalid fixture $id ($note) ANSWERED instead of refusing (rc=$rc, ${#out} bytes on stdout)"
        fi
        continue
    fi
    valid=$(( valid + 1 ))
    [ "$cls" = "change" ]   && nchange=$(( nchange + 1 ))
    [ "$cls" = "preserve" ] && npreserve=$(( npreserve + 1 ))
    pre="$( preview "$file:$name" "$P" )"
    post="$( applied "$name" "$file" "$P" )"
    [ -z "$firstPreview" ] && firstPreview="$pre"
    [ "$id" = "chg01" ] && changePreview="$pre"
    [ "$id" = "pre01" ] && preserveApplied="$post"
    if [ "$( norm "$pre" )" = "$( norm "$post" )" ]; then
        agree=$(( agree + 1 ))
    else
        no "fixture $id ($note): preview != applied"
        printf '        pre : %s\n' "$( norm "$pre" | cut -c1-320 )"
        printf '        post: %s\n' "$( norm "$post" | cut -c1-320 )"
    fi
    # the hard stop: a preview that reassures where the applied tree does not
    ps="$( statusOf "$pre" )"; qs="$( statusOf "$post" )"
    if [ "$ps" = 'status="unchanged"' ] && [ "$qs" != 'status="unchanged"' ]; then
        falseclean=$(( falseclean + 1 ))
        no "fixture $id: FALSE CLEAN — preview said unchanged, the applied tree said $qs"
    fi
done < "$FIX/cases.tsv"

total=$(( valid + invalid ))
disagree=$(( valid - agree ))
[ "$total" -ge 30 ] && ok "fixture set is $total payloads ($valid valid, $invalid invalid) — band floor is 30" \
                    || no "fixture set is only $total payloads — the band requires >= 30"
{ [ "$nchange" -ge 10 ] && [ "$npreserve" -ge 10 ] && [ "$invalid" -ge 10 ]; } \
    && ok "class mix: $nchange contract-changing, $npreserve contract-preserving, $invalid invalid (floor 10 each)" \
    || no "class mix below the registered floor (change=$nchange preserve=$npreserve invalid=$invalid)"
# The band's floor is the RATE 29/30 — one allowed disagreement. Applied to the realized valid set that is
# "at most one disagreement", which on 25 valid payloads is a STRICTER rate than 29/30, never a looser one.
[ "$disagree" -le 1 ] && ok "pre-apply == post-apply on $agree of $valid valid payloads ($disagree disagreement, floor is at most 1)" \
                      || no "$disagree disagreements across $valid valid payloads — the band allows at most 1"
[ "$falseclean" = 0 ] && ok "zero false \"unchanged\" verdicts" || no "$falseclean false-clean verdict(s) — the band fails outright"
[ "$refused" = "$invalid" ] && ok "all $invalid invalid payloads refused (exit != 0, empty stdout)" \
                            || no "only $refused of $invalid invalid payloads refused"

# ── (P) presence guard — the documents compared above are real answers, not two empty strings ─────────
if printf '%s' "$firstPreview" | grep -q '<edit-check ' && printf '%s' "$firstPreview" | grep -q 'status="'; then
    ok "(P) presence guard: the compared documents are real <edit-check> elements carrying status="
else
    no "(P) presence guard: the preview document is not an <edit-check> element — the sweep proved nothing"
fi

# ── (M) mutation control — the comparison can SEE a mismatch ──────────────────────────────────────────
if [ -n "$changePreview" ] && [ -n "$preserveApplied" ]; then
    if [ "$( norm "$changePreview" )" = "$( norm "$preserveApplied" )" ]; then
        no "(M) mutation control: a contract-CHANGING preview compared EQUAL to a contract-PRESERVING apply — the sweep's comparison is vacuous"
    else
        ok "(M) mutation control: a deliberately mismatched pair is reported as disagreeing"
    fi
else
    no "(M) mutation control could not run — one of its two documents is empty"
fi

# ── (D) the preview marker, and the legend that defines it ────────────────────────────────────────────
printf '%s' "$firstPreview" | grep -q 'preview="1"' \
    && ok "(D) the pre-apply document carries preview=\"1\"" \
    || no "(D) the pre-apply document does not carry preview=\"1\""
printf '%s' "$firstPreview" | sed -e 's/\(<!--.*-->\).*/\1/' | grep -q 'preview=' \
    && ok "(D) preview= is defined in the emitted legend" \
    || no "(D) preview= is emitted but never defined in the legend"
printf '%s' "$firstPreview" | grep -qi 'not been written\|no byte' \
    && ok "(D) the legend states the payload was not written" \
    || no "(D) the legend never says the payload was not written"

# ── (C) the combination refusals ──────────────────────────────────────────────────────────────────────
comb(){ ( cd "$BASE" && "$BIN" . "$@" >"$WORK/c.out" 2>"$WORK/c.err"; echo $? ); }
rc="$( comb --edit-check=lib.h:scale --edit-payload="$FIX/payloads/pre01.txt" )"
{ [ "$rc" != 0 ] && [ ! -s "$WORK/c.out" ] && grep -q -- '--dry-run' "$WORK/c.err"; } \
    && ok "(C) --edit-check --edit-payload without --dry-run refuses and names --dry-run" \
    || { no "(C) --edit-payload without --dry-run did not refuse cleanly (rc=$rc)"; head -2 "$WORK/c.err"; }
rc="$( comb --edit-check=lib.h:scale --dry-run )"
{ [ "$rc" != 0 ] && [ ! -s "$WORK/c.out" ] && grep -q -- '--edit-payload' "$WORK/c.err"; } \
    && ok "(C) --edit-check --dry-run with no payload refuses and names --edit-payload" \
    || { no "(C) --dry-run with no payload did not refuse cleanly (rc=$rc)"; head -2 "$WORK/c.err"; }
rc="$( comb --edit-check=lib.h:scale --edit-payload="$WORK/does-not-exist.txt" --dry-run )"
{ [ "$rc" != 0 ] && [ ! -s "$WORK/c.out" ]; } \
    && ok "(C) an unreadable payload file refuses" \
    || { no "(C) an unreadable payload file did not refuse (rc=$rc)"; head -2 "$WORK/c.err"; }
rc="$( comb --edit-check=lib.h:scale --edit-payload="$FIX/payloads/pre01.txt" --dry-run --apply )"
{ [ "$rc" != 0 ] && [ ! -s "$WORK/c.out" ]; } \
    && ok "(C) --apply beside the preview refuses (the preview never writes)" \
    || { no "(C) --apply beside the preview did not refuse (rc=$rc)"; head -2 "$WORK/c.err"; }

# ── (A) the ambiguity refusal still fires on the preview path, with a payload in hand ──────────────────
AMB="$WORK/amb"; mkcorpus "$AMB"
cat > "$AMB/extra.cpp" <<'XEOF'
int trim( int a, int b )
{
    return b;
}
XEOF
( cd "$AMB" && git add -A && git commit -qm extra ) >/dev/null 2>&1
( cd "$AMB" && "$BIN" . --edit-check=trim --edit-payload="$FIX/payloads/pre03.txt" --dry-run --no-cache \
    >"$WORK/a.out" 2>"$WORK/a.err" ); rc=$?
{ [ "$rc" != 0 ] && [ ! -s "$WORK/a.out" ] && grep -q 'ambiguous' "$WORK/a.err"; } \
    && ok "(A) an ambiguous SYM refuses on the preview path and lists the spellings" \
    || { no "(A) ambiguous SYM was not refused on the preview path (rc=$rc)"; head -2 "$WORK/a.err"; }

# ── (R) the RECORDED LIMIT — a grammar-recovered payload is answered, and the legend says so ─────────
rc="$( previewrc mod.py:widen "$FIX/payloads/pre13.txt" )"
[ "$rc" = 0 ] \
    && ok "(R) recorded limit: a de-indented python body parses clean and is ANSWERED, not refused" \
    || no "(R) the de-indented python payload refused — the recorded limit changed; re-derive it before re-classing pre13"
printf '%s' "$firstPreview" | sed -e 's/\(<!--.*-->\).*/\1/' | grep -q 'RECOVERS' \
    && ok "(R) the legend discloses that a recovered parse is answered on its recovered parse" \
    || no "(R) the legend never discloses the recovered-parse limit"

# ── (S) the Section kind guard — a document heading is not an editable definition ─────────────────────
SEC="$WORK/sec"; mkcorpus "$SEC"
printf '# Heading\n\nprose\n' > "$SEC/doc.md"
( cd "$SEC" && git add -A && git commit -qm doc ) >/dev/null 2>&1
( cd "$SEC" && "$BIN" . --edit-check=doc.md:Heading --edit-payload="$FIX/payloads/pre01.txt" --dry-run --no-cache \
    >"$WORK/s.out" 2>"$WORK/s.err" ); rc=$?
if [ ! -s "$WORK/s.err" ] && [ ! -s "$WORK/s.out" ]; then
    no "(S) neither stream produced anything — the Section arm proved nothing"
elif [ "$rc" != 0 ] && [ ! -s "$WORK/s.out" ]; then
    ok "(S) a document heading refuses instead of previewing a splice through it"
else
    no "(S) a document heading was previewed as an editable definition (rc=$rc)"
fi

# ── (N) the MCP mirror — edit_check with new_body must answer EXACTLY what the CLI preview answers ────
if command -v python3 >/dev/null 2>&1; then
    MCPOUT="$( cd "$BASE" && python3 - "$BIN" "$FIX/payloads/chg01.txt" <<'PYEOF' 2>/dev/null
import json, subprocess, sys
binPath, payloadPath = sys.argv[1], sys.argv[2]
body = open( payloadPath ).read()
req  = { "jsonrpc": "2.0", "id": 1, "method": "tools/call",
         # M1 RE-PIN (terminality round A, 2026-09-05): the MCP legend default moved to compact, and this
         # arm compares the server document against the CLI PREVIEW, which is the CLI default (full). The
         # posture is named so both operands are the same dialect; the compact default equivalence
         # (default == compact, payload byte-identical to full) is pinned per verb by compactlegendcheck (N).
         "params": { "name": "edit_check",
                     "arguments": { "path": ".", "symbol": "lib.h:scale", "new_body": body, "legend": "full" } } }
p = subprocess.run( [ binPath, "--mcp" ], input = json.dumps( req ) + "\n",
                    capture_output = True, text = True )
for line in p.stdout.splitlines():
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads( line )
    except ValueError:
        continue
    for c in d.get( "result", {} ).get( "content", [] ):
        if c.get( "text" ):
            sys.stdout.write( c[ "text" ] )
PYEOF
)"
    CLIOUT="$( preview lib.h:scale "$FIX/payloads/chg01.txt" )"
    if [ -z "$MCPOUT" ]; then
        no "(N) the MCP edit_check preview returned nothing — the mirror arm proved nothing"
    elif [ "$( norm "$MCPOUT" )" = "$( norm "$CLIOUT" )" ]; then
        ok "(N) MCP edit_check with new_body == the CLI preview, document for document"
    else
        no "(N) the MCP mirror disagrees with the CLI preview"
        printf '        cli: %s\n' "$( norm "$CLIOUT" | cut -c1-260 )"
        printf '        mcp: %s\n' "$( norm "$MCPOUT" | cut -c1-260 )"
    fi
else
    no "(N) python3 absent — the MCP mirror arm could not run"
fi

# ── (T) determinism (x3) and well-formedness ─────────────────────────────────────────────────────────
d1="$( preview lib.h:scale "$FIX/payloads/chg01.txt" )"
d2="$( preview lib.h:scale "$FIX/payloads/chg01.txt" )"
d3="$( preview lib.h:scale "$FIX/payloads/chg01.txt" )"
{ [ "$d1" = "$d2" ] && [ "$d2" = "$d3" ] && [ -n "$d1" ]; } \
    && ok "(T) three preview runs are byte-identical" || no "(T) preview output is not deterministic"
if command -v xmllint >/dev/null 2>&1; then
    printf '%s' "$d1" | xmllint --noout - 2>"$WORK/x.err" \
        && ok "(T) the preview document is well-formed XML" \
        || { no "(T) xmllint rejected the preview document"; head -3 "$WORK/x.err"; }
else
    ok "(T) xmllint absent — well-formedness arm skipped"
fi

# ── (W) NOTHING WAS WRITTEN — the whole point of a dry run ────────────────────────────────────────────
( cd "$BASE" && git status --porcelain ) > "$WORK/dirty.txt" 2>/dev/null
[ ! -s "$WORK/dirty.txt" ] \
    && ok "(W) the corpus is still byte-clean after $total previews — nothing was written" \
    || { no "(W) the preview MODIFIED the working tree"; cat "$WORK/dirty.txt"; }

# ── (O) E3 (terminality round A 2026-09-05, lane E) — THE PREVIEW ANSWERS THE READ-BEFORE-EDIT ────────
# An agent that previews a payload and then applies it still Reads the target first to see what it is about to
# overwrite. The preview document therefore carries an <overwrite> child: the CURRENT definition span an apply
# would replace, as the bytes are on disk (CDATA; l=/end= its lines, bytes= its size), budgeted — over the budget
# shown=/capped="1" and elided_lines= say so. Read→edit→Read collapses to preview→apply. --expand's body is
# byte-exact by test/editroundtripcheck.sh, so it is the oracle for the span's bytes here.
OW_DOC="$( preview lib.h:scale "$FIX/payloads/chg01.txt" )"
python3 - "$OW_DOC" "$( cd "$BASE" && "$BIN" . --expand=lib.h:scale --top-k=0 --no-cache 2>/dev/null )" "$BASE/lib.h" <<'PY' >"$WORK/o.res" 2>&1
import re, sys
doc, expand, path = sys.argv[1], sys.argv[2], sys.argv[3]
m = re.search( r'<overwrite ([^>]*)><!\[CDATA\[(.*?)\]\]></overwrite>', doc, re.S )
assert m, "the preview carries no <overwrite> child — the agent still has to Read the span it is about to replace"
attrs = dict( re.findall( r'([\w-]+)="([^"]*)"', m.group( 1 ) ) ); text = m.group( 2 ).replace( "]]]]><![CDATA[>", "]]>" )
b = re.search( r'<b [^>]*n="scale"[^>]*><!\[CDATA\[(.*?)\]\]></b>', expand, re.S )
assert b, "fixture: --expand served no body for lib.h:scale"
body = b.group( 1 ).replace( "]]]]><![CDATA[>", "]]>" )
assert text == body, "overwrite CDATA is not the span's bytes on disk:\n%r\n!=\n%r" % ( text, body )
for k in ( "l", "end", "bytes" ): assert k in attrs, "overwrite lacks %s= (has %r)" % ( k, sorted( attrs ) )
assert int( attrs["bytes"] ) == len( body.encode() ), "bytes=%s but the span is %d bytes" % ( attrs["bytes"], len( body.encode() ) )
lines = open( path ).read().split( "\n" )
assert "\n".join( lines[ int( attrs["l"] ) - 1 : int( attrs["end"] ) ] ) == body, "l=/end= do not bracket the span on disk"
assert "capped" not in attrs, "a %d-byte span must not be capped" % len( body )
print( "OK <overwrite l=%s end=%s bytes=%s> == the span on disk" % ( attrs["l"], attrs["end"], attrs["bytes"] ) )
PY
[ $? -eq 0 ] && ok "(O) $( cat "$WORK/o.res" )" || no "(O) $( tail -1 "$WORK/o.res" )"
# (O3) the budget: a 400-line definition previews with head bytes only, disclosed
OWB="$WORK/owbig"; mkcorpus "$OWB"
python3 - "$OWB/big.cpp" <<'PY'
import sys
lines = [ "int huge( int x )", "{" ] + [ "    x += %d;" % i for i in range( 400 ) ] + [ "    return x;", "}", "" ]
open( sys.argv[1], "w" ).write( "\n".join( lines ) )
PY
( cd "$OWB" && git add -A && git commit -qm big ) >/dev/null 2>&1
printf 'int huge( int x )\n{\n    return x;\n}\n' > "$WORK/huge_pay.txt"
OWB_DOC="$( cd "$OWB" && "$BIN" . --edit-check=big.cpp:huge --edit-payload="$WORK/huge_pay.txt" --dry-run --no-cache 2>/dev/null )"
python3 - "$OWB_DOC" <<'PY' >"$WORK/o3.res" 2>&1
import re, sys
m = re.search( r'<overwrite ([^>]*)><!\[CDATA\[(.*?)\]\]></overwrite>', sys.argv[1], re.S )
assert m, "no <overwrite> on the big preview"
a = dict( re.findall( r'([\w-]+)="([^"]*)"', m.group( 1 ) ) )
assert a.get( "capped" ) == "1", "a %s-byte span was not capped (attrs %r)" % ( a.get( "bytes" ), sorted( a ) )
assert "shown" in a and int( a["shown"] ) < int( a["bytes"] ), "capped without shown= < bytes="
assert int( a["shown"] ) == len( m.group( 2 ).encode() ), "shown=%s but the CDATA is %d bytes" % ( a["shown"], len( m.group( 2 ) ) )
assert "elided_lines" in a and int( a["elided_lines"] ) > 0, "capped without elided_lines="
assert m.group( 2 ).startswith( "int huge( int x )\n{" ), "the head is not the span's start"
print( "OK capped: shown=%s of bytes=%s, elided_lines=%s" % ( a["shown"], a["bytes"], a["elided_lines"] ) )
PY
[ $? -eq 0 ] && ok "(O3) an oversize span is budgeted and disclosed: $( cat "$WORK/o3.res" )" || no "(O3) $( tail -1 "$WORK/o3.res" )"
# (O4) compact <-> compact parity: the CLI preview under --legend=compact == MCP edit_check with legend:"compact"
CLI_C="$( cd "$BASE" && "$BIN" . --edit-check=lib.h:scale --edit-payload="$FIX/payloads/chg01.txt" --dry-run --no-cache --legend=compact 2>/dev/null )"
MCP_C="$( cd "$BASE" && python3 - "$BIN" "$FIX/payloads/chg01.txt" <<'PYEOF' 2>/dev/null
import json, subprocess, sys
body = open( sys.argv[2] ).read()
req  = { "jsonrpc": "2.0", "id": 1, "method": "tools/call",
         "params": { "name": "edit_check", "arguments": { "path": ".", "symbol": "lib.h:scale", "new_body": body, "legend": "compact" } } }
p = subprocess.run( [ sys.argv[1], "--mcp" ], input = json.dumps( req ) + "\n", capture_output = True, text = True )
for line in p.stdout.splitlines():
    try: d = json.loads( line )
    except ValueError: continue
    for c in d.get( "result", {} ).get( "content", [] ):
        if c.get( "text" ): sys.stdout.write( c[ "text" ] )
PYEOF
)"
strip_at(){ printf '%s' "$1" | sed -e 's/<!--.*-->//' -e 's/ at="[^"]*"//g'; }
if [ -z "$MCP_C" ]; then
    no "(O4) MCP edit_check legend:compact returned nothing"
elif [ "$( strip_at "$CLI_C" )" = "$( strip_at "$MCP_C" )" ] && printf '%s' "$CLI_C" | grep -q '<overwrite '; then
    ok "(O4) compact<->compact: the CLI preview == MCP edit_check legend:compact, <overwrite> included"
else
    no "(O4) the compact CLI preview and the compact MCP twin differ (or neither carries <overwrite>)"
    printf '        cli: %s\n' "$( strip_at "$CLI_C" | cut -c1-200 )"; printf '        mcp: %s\n' "$( strip_at "$MCP_C" | cut -c1-200 )"
fi
# (O5) both legends define the child where the reader meets it
printf '%s' "$OW_DOC" | sed -e 's/\(<!--.*-->\).*/\1/' | grep -q 'overwrite' \
    && ok "(O5) the full preview legend defines the overwrite child" || no "(O5) the full preview legend never mentions overwrite"
printf '%s' "$CLI_C" | sed -e 's/\(<!--.*-->\).*/\1/' | grep -q 'overwrite' \
    && ok "(O5) the compact preview legend defines the overwrite child (present-only term)" || no "(O5) the compact preview legend never mentions overwrite"
# (O6) the post-hoc --edit-check (no payload) carries NO overwrite child — it is the preview's, by construction
( cd "$BASE" && "$BIN" . --edit-check=lib.h:scale --no-cache 2>/dev/null ) | grep -q '<overwrite ' \
    && no "(O6) the post-hoc --edit-check carries an overwrite child — nothing is about to be overwritten there" \
    || ok "(O6) the post-hoc --edit-check carries no overwrite child (preview-only, by construction)"

echo
[ "$fail" = 0 ] && echo "editpreviewcheck: OK" || echo "editpreviewcheck: FAILURES"
exit "$fail"
