#!/usr/bin/env bash
# fornotesjsoncheck.sh — §B1.3 gate (PLAN_outputAudit3): `--for --json` must not SILENTLY drop the
# auto-surfaced field notes its XML sibling emits.
#
# The XML `--for` bundle attaches `<note d="…">…</note>` children to the `<d>` row (and `<f>` wrapper) of any
# symbol/file that has a note in .ripwire_notes. The JSON sibling emitted none, and carried no count either —
# so a consumer could not tell "this symbol has no note" from "the note was dropped on the way out". The
# convention to mirror already exists one verb over: `--pack-task --json` reports notes/notes_kept/notes_total.
#
# Asserted here:
#   (1) the note TEXT reaches the JSON row of the symbol it is attached to;
#   (2) notes_total / notes_kept are present and agree with the XML sibling's note count;
#   (3) the L3 INERTNESS contract holds: a tree with no .ripwire_notes emits no notes keys at all
#       (zero bytes, so every pre-feature byte-identity gate keeps passing);
#   (4) `--pack-task --json`'s own notes convention is unchanged (it owns a dedicated notes section and must
#       NOT grow inline row notes — its XML sigs carry none either);
#   (5) determinism: two runs byte-identical.
#
# Usage: bash test/fornotesjsoncheck.sh [path/to/ripwire]
# Exits non-zero on any failure; DOES NOT touch regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"   # house convention: the suite passes the binary via RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

echo "fornotesjsoncheck: BIN=$BIN"
[ -x "$BIN" ] || { no "binary not executable: $BIN"; echo "FAILURES ABOVE"; exit 1; }
command -v python3 >/dev/null 2>&1 || { no "python3 is REQUIRED (JSON parsing) — not found"; echo "FAILURES ABOVE"; exit 1; }

TASK="manifest cache loader"
NOTE="cache is stale after a rebuild — call reset first"

mk_tree()
{
    local d="$1"
    mkdir -p "$d"
    cat > "$d/loader.py" <<'PY'
def load_manifest_cache(path):
    """Load the manifest cache from disk."""
    return open(path).read()

def probe_manifest(path):
    return load_manifest_cache(path)
PY
}

NOTED="$TMP/noted"; mk_tree "$NOTED"
BARE="$TMP/bare";   mk_tree "$BARE"
"$BIN" "$NOTED" --note-add="load_manifest_cache: $NOTE" >/dev/null 2>&1
[ -s "$NOTED/.ripwire_notes" ] || { no "--note-add did not write .ripwire_notes — the gate has no input"; echo "FAILURES ABOVE"; exit 1; }
[ -e "$BARE/.ripwire_notes" ]  && { no "the bare tree must have NO notes file"; echo "FAILURES ABOVE"; exit 1; }

"$BIN" "$NOTED" --for="$TASK" --json > "$TMP/for.json" 2>/dev/null || { no "--for --json exited non-zero"; echo "FAILURES ABOVE"; exit 1; }
"$BIN" "$NOTED" --for="$TASK"        > "$TMP/for.xml"  2>/dev/null || { no "--for (XML) exited non-zero";  echo "FAILURES ABOVE"; exit 1; }
[ -s "$TMP/for.json" ] && [ -s "$TMP/for.xml" ] || { no "one of the two --for outputs is EMPTY"; echo "FAILURES ABOVE"; exit 1; }

XMLNOTES="$( grep -o '<note ' "$TMP/for.xml" | wc -l | tr -d ' ' )"
[ "$XMLNOTES" -ge 1 ] || { no "the XML sibling surfaced NO note — the fixture is wrong, not the JSON emitter"; echo "FAILURES ABOVE"; exit 1; }
ok "XML sibling surfaces $XMLNOTES note(s) — the fact the JSON must mirror"

python3 - "$TMP/for.json" "$NOTE" > "$TMP/verdict.txt" <<'PY'
import json, sys
d    = json.load( open( sys.argv[1] ) )
want = sys.argv[2]

# every "notes" array reachable in the bundle, wherever it hangs
found_text = 0
on_symbol  = 0
def walk( node, insym ):
    global found_text, on_symbol
    if isinstance( node, dict ):
        if "notes" in node and isinstance( node["notes"], list ):
            for n in node["notes"]:
                if isinstance( n, dict ) and n.get( "text" ) == want:
                    found_text += 1
                    if insym: on_symbol += 1
        for k, v in node.items():
            walk( v, insym or ( k == "symbols" ) )
    elif isinstance( node, list ):
        for v in node: walk( v, insym )
walk( d, False )

print( "TOTAL="      + str( d.get( "notes_total", "ABSENT" ) ) )
print( "KEPT="       + str( d.get( "notes_kept",  "ABSENT" ) ) )
print( "FOUNDTEXT="  + str( found_text ) )
print( "ONSYMBOL="   + str( on_symbol ) )
PY
[ -s "$TMP/verdict.txt" ] || { no "--for --json must be PARSEABLE JSON — the extractor produced nothing"; echo "FAILURES ABOVE"; exit 1; }
. /dev/stdin <<EOF
$( sed 's/^\([A-Z]*\)=\(.*\)$/\1="\2"/' "$TMP/verdict.txt" )
EOF

# (1) the note text reaches the JSON, on the SYMBOL row it is attached to
[ "$FOUNDTEXT" -ge 1 ] && ok "the note text reaches --for --json ($FOUNDTEXT occurrence(s))" \
                       || no "--for --json DROPPED the note text entirely"
[ "$ONSYMBOL" -ge 1 ]  && ok "the note hangs on the symbol row it annotates (mirrors the XML <d> child)" \
                       || no "the note is not attached to the symbol row (the XML attaches it to <d>)"

# (2) the counts exist and agree with the XML
[ "$TOTAL" = ABSENT ] && no "notes_total is ABSENT — a consumer cannot tell 'no notes' from 'notes dropped'" \
                      || ok "notes_total present ($TOTAL)"
[ "$KEPT"  = ABSENT ] && no "notes_kept is ABSENT (the --pack-task --json convention is notes/notes_kept/notes_total)" \
                      || ok "notes_kept present ($KEPT)"
if [ "$TOTAL" != ABSENT ] && [ "$KEPT" != ABSENT ]; then
    [ "$KEPT" = "$XMLNOTES" ] && ok "notes_kept ($KEPT) == the XML sibling's surfaced note count ($XMLNOTES)" \
                              || no "notes_kept ($KEPT) disagrees with the XML sibling's note count ($XMLNOTES)"
    [ "$TOTAL" -ge "$KEPT" ] 2>/dev/null && ok "notes_total >= notes_kept (a truncation report, never inverted)" \
                                         || no "notes_total ($TOTAL) < notes_kept ($KEPT)"
fi

# (3) L3 inertness — a tree with no notes file emits no notes keys AT ALL
"$BIN" "$BARE" --for="$TASK" --json > "$TMP/bare.json" 2>/dev/null || { no "--for --json on the bare tree exited non-zero"; echo "FAILURES ABOVE"; exit 1; }
[ -s "$TMP/bare.json" ] || { no "--for --json on the bare tree produced NO output"; echo "FAILURES ABOVE"; exit 1; }
grep -q '"notes' "$TMP/bare.json" \
    && no "the no-notes tree emits notes keys — the L3 inertness contract (zero bytes when there is no NoteIndex) is broken" \
    || ok "no-notes tree emits zero notes bytes (L3 inertness holds)"

# (4) --pack-task --json keeps its own convention and grows NO inline row notes (its XML sigs carry none)
"$BIN" "$NOTED" --pack-task="$TASK" --json > "$TMP/pt.json" 2>/dev/null || { no "--pack-task --json exited non-zero"; echo "FAILURES ABOVE"; exit 1; }
python3 - "$TMP/pt.json" > "$TMP/pt.txt" <<'PY'
import json, sys
d = json.load( open( sys.argv[1] ) )
print( "PT_TOTAL=" + str( d.get( "notes_total", "ABSENT" ) ) )
inline = 0
for f in d.get( "ranking", [] ):
    for s in f.get( "symbols", [] ):
        if "notes" in s: inline += 1
print( "PT_INLINE=" + str( inline ) )
PY
[ -s "$TMP/pt.txt" ] || { no "--pack-task --json must be PARSEABLE JSON"; echo "FAILURES ABOVE"; exit 1; }
. /dev/stdin <<EOF
$( sed 's/^\([A-Z_]*\)=\(.*\)$/\1="\2"/' "$TMP/pt.txt" )
EOF
[ "$PT_TOTAL" != ABSENT ] && ok "--pack-task --json still reports notes_total ($PT_TOTAL)" \
                          || no "--pack-task --json lost its notes_total"
[ "$PT_INLINE" = 0 ] && ok "--pack-task --json ranking rows carry no inline notes (its XML sigs carry none either)" \
                     || no "--pack-task --json ranking rows grew $PT_INLINE inline note block(s) the XML does not emit"

# (5) determinism
"$BIN" "$NOTED" --for="$TASK" --json > "$TMP/for2.json" 2>/dev/null
cmp -s "$TMP/for.json" "$TMP/for2.json" && ok "det-gate: --for --json byte-identical across 2 runs" \
                                        || no "det-gate: --for --json differs between runs"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
