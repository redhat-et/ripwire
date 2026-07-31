#!/usr/bin/env bash
# columnarattrcheck.sh — §B1.1 gate (PLAN_outputAudit3): the COLUMNAR-CAPABLE FAMILY is exactly four verbs
# — --callers, --callees, --uses, --impact — and every one of them composes its wrapper attribute string
# from a caller-supplied symbol NAME, which is unbounded (a markdown SECTION heading routinely runs
# 200-600 chars).
#
# The defect this gate pins: three of the four composed that string into a FIXED-SIZE `char attrbuf[]`
# (288 B on callers/callees, 512 B on uses) via snprintf, which TRUNCATES silently. Two distinct wrong
# outputs came out of that, both at exit 0:
#   (a) the attribute is cut mid-value — the closing quote is gone and the output is NOT well-formed XML
#       (measured RED at name length >= ~185 with paging flags on --callers, >= ~480 on --uses);
#   (b) at a boundary length the output stays well-formed but the paging disclosure
#       (`next_offset=`/`offset=`/`limit=`) is AMPUTATED — a paging consumer silently loses its cursor
#       (measured RED at name length 262-263 on --callers).
# --impact was already fixed (std::string composition, `runImpact`); it is checked here too so the gate
# states the FAMILY, not the three broken members — a later fix that reintroduces a fixed buffer on any
# one of the four fails here.
#
# Both output shapes are checked (--format=xml and --format=columnar) and both paging states (unpaged, and
# --limit/--offset), because the disclosure only exists in the paged state and the truncation point moves
# with it.
#
# Usage: bash test/columnarattrcheck.sh [path/to/ripwire]
# Exits non-zero on any failure; DOES NOT touch regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"   # house convention: the suite passes the binary via RIPWIRE_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

echo "columnarattrcheck: BIN=$BIN"
[ -x "$BIN" ] || { no "binary not executable: $BIN"; echo "FAILURES ABOVE"; exit 1; }
command -v xmllint >/dev/null 2>&1 || { no "xmllint is REQUIRED by this gate (well-formedness is the assertion) — not found"; echo "FAILURES ABOVE"; exit 1; }
command -v python3  >/dev/null 2>&1 || { no "python3 is REQUIRED to build the sandbox tree — not found"; echo "FAILURES ABOVE"; exit 1; }

# ── the sandbox: markdown SECTION symbols whose names sit AT and OVER the two measured buffer thresholds,
#    plus a two-function python file so the same tree also exercises a name that really has callers. ──────
SBX="$TMP/sbx"
mkdir -p "$SBX"
LENS="186 262 263 300 480 500 600"
python3 - "$SBX" $LENS <<'PY'
import sys, os
sbx  = sys.argv[1]
lens = [ int( x ) for x in sys.argv[2:] ]
out  = []
for L in lens:
    # a deterministic, unique prefix per length so each heading resolves to exactly one symbol
    out += [ '# ' + ( 'N%03d' % L ) + 'H' * ( L - 4 ), '', 'body text', '' ]
open( os.path.join( sbx, 'doc.md' ), 'w' ).write( '\n'.join( out ) )
open( os.path.join( sbx, 'a.py' ),  'w' ).write( 'def alpha():\n    return beta()\n\ndef beta():\n    return 1\n' )
PY
[ -s "$SBX/doc.md" ] || { no "sandbox doc.md was not written"; echo "FAILURES ABOVE"; exit 1; }

nameOf(){ python3 -c "print('N%03d'%$1 + 'H'*($1-4))"; }

# the sandbox names are section headings, so a call-graph verb legitimately returns zero rows; the
# ATTRIBUTE STRING is what this gate measures, and it is emitted identically at zero rows.
check_one()
{
    local verb="$1" name="$2" L="$3" fmt="$4" paged="$5"
    local args=( "$SBX" "--$verb=$name" )
    [ "$fmt"   = columnar ] && args+=( --format=columnar )
    [ "$paged" = paged ]    && args+=( --limit=1 --offset=0 )

    local out rc lintErr
    out="$( "$BIN" "${args[@]}" 2>/dev/null )"; rc=$?
    local label="--$verb len=$L fmt=$fmt $paged"

    if [ $rc -ne 0 ]; then no "$label: exit $rc (expected 0 — the symbol exists in the sandbox)"; return; fi

    # (a) well-formedness — the G4 contract; a truncated attribute breaks it while the process still exits 0
    lintErr="$( printf '%s\n' "$out" | xmllint --noout - 2>&1 )"
    if [ -n "$lintErr" ]; then
        no "$label: NOT well-formed XML at exit 0 (attribute cut mid-value) — $( printf '%s' "$lintErr" | head -1 )"
    else
        ok "$label: well-formed XML"
    fi

    # (b) the symbol name must survive INTACT inside of="…" — a silently shortened echo is its own defect
    case "$out" in
        *"of=\"$name\""*) ok "$label: of=\"…\" carries the full $L-char name" ;;
        *)                no "$label: of=\"…\" does NOT carry the full $L-char name (truncated echo)" ;;
    esac

    # (c) under paging flags the disclosure must survive — this is the well-formed-but-amputated mode
    if [ "$paged" = paged ]; then
        local missing=""
        for attr in next_offset= offset= limit=; do
            case "$out" in *"$attr"*) ;; *) missing="$missing $attr" ;; esac
        done
        if [ -n "$missing" ]; then
            no "$label: paging disclosure AMPUTATED — missing:$missing"
        else
            ok "$label: paging disclosure intact (next_offset=/offset=/limit=)"
        fi
    fi
}

# ── the family: all four columnar-capable verbs, over every threshold length ─────────────────────────────
for L in $LENS; do
    NAME="$( nameOf "$L" )"
    [ ${#NAME} -eq "$L" ] || { no "sandbox name generator produced ${#NAME} chars, wanted $L"; continue; }
    for verb in callers callees uses impact; do
        for fmt in xml columnar; do
            for paged in unpaged paged; do
                check_one "$verb" "$NAME" "$L" "$fmt" "$paged"
            done
        done
    done
done

# ── a short name still behaves exactly as before (no regression in the ordinary case, rows present) ──────
# RE-PIN (H4 W3-DISC, PLAN_h4QualifiedCalls_2026-07-30.md): the five graph verbs gained the
# `counts_floor="1"` disclosure attribute (emitted between limit= and format= on the columnar
# header). The pinned string moves ONCE, deliberately, to carry it; everything else is unchanged.
short="$( "$BIN" "$SBX" --callers=beta --format=columnar --limit=1 --offset=0 2>/dev/null )"
case "$short" in
    *'<callers of="beta" defs="1" count="1" shown="1" capped="0" total="1" has_more="0" next_offset="1" offset="0" limit="1" counts_floor="1" format="columnar">'*)
        ok "short-name columnar header byte-identical to the pre-fix shape (+ the H4 counts_floor attribute)" ;;
    *)  no "short-name columnar header CHANGED shape: $( printf '%s' "$short" | head -c 200 )" ;;
esac

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
