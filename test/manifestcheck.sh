#!/usr/bin/env bash
# manifestcheck.sh — every committed top-level *check.sh gate must be owned by regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
REGRESSION="$ROOT/test/regression.sh"
EVALS="$ROOT/docs/EVALS.md"
fail=0

while IFS= read -r gatePath; do
    gateName="$( basename "$gatePath" .sh )"
    if ! grep -Eq "(^|[^[:alnum:]_])${gateName}(\\.sh)?([^[:alnum:]_]|$)" "$REGRESSION"; then
        printf 'FAIL: test/%s.sh is not listed in test/regression.sh\n' "$gateName"
        fail=1
    fi
done < <( find "$ROOT/test" -maxdepth 1 -type f -name '*check.sh' | LC_ALL=C sort )

if [ "$fail" = 0 ]; then
    printf 'PASS: every top-level *check.sh gate is listed in regression.sh\n'
fi

# ── gate-count drift: docs/EVALS.md §8 quotes the loop's length as a known-honest number; that
# quote must equal the loop's ACTUAL length or it is itself the exact stale-docstring drift §8 is
# complaining about. Both sides are derived here, not hand-copied, so they cannot silently disagree
# again. The loop is the single `for _g in NAME NAME ...; do` line in regression.sh (the bulk-absorbed
# gates); the four gates invoked individually above it (g1freshcheck, skillscan, htmlexport,
# compresscheck) are NOT part of "the loop" and are deliberately excluded from this count, matching
# what §8's prose actually refers to.
loopNames="$( python3 -c "
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r'for _g in (.*?); do', text, re.S)
sys.exit('no loop found') if not m else print(len(m.group(1).split()))
" "$REGRESSION" )"
evalsStated="$( grep -oE 'loop in `test/regression\.sh` names [0-9]+' "$EVALS" | head -1 | grep -oE '[0-9]+$' )"
if [ -z "$evalsStated" ]; then
    printf 'FAIL: docs/EVALS.md has no "loop in `test/regression.sh` names N" sentence to check (§8)\n'
    fail=1
elif [ -z "$loopNames" ]; then
    printf 'FAIL: could not derive the gate count from the for-loop in test/regression.sh\n'
    fail=1
elif [ "$evalsStated" = "$loopNames" ]; then
    printf 'PASS: docs/EVALS.md §8 gate count (%s) matches test/regression.sh loop length (%s)\n' "$evalsStated" "$loopNames"
else
    printf 'FAIL: docs/EVALS.md §8 says the loop names %s, but it actually names %s — update docs/EVALS.md:395\n' "$evalsStated" "$loopNames"
    fail=1
fi

# ── the SIBLINGS of that number, which the check above never saw ────────────────────────────────────
# docs/EVALS.md states the gate count in more than one place, and until now exactly ONE of them was
# enforced. Both unenforced siblings drifted twice: once to 371 while the loop was at 373, and again
# to 374 while the loop reached 376 — the second time within one round of being corrected, because a
# passing manifestcheck reported confidence about a number it had not actually checked. That is
# METHODOLOGY §3 (a fix that lands on one family member and not its siblings) applied to a gate, and
# the fix is the §3 fix: enumerate the family, assert over ALL of it. Every "<N> gate scripts" claim
# in a scanned file is derived-vs-stated, so a new one added later is covered without editing this gate.
#
# WIDENED 2026-09-06 from docs/EVALS.md to the whole FAMILY of files that state this number, for the
# third instance of exactly the drift the paragraph above describes. README.md and the showcase deck
# generator both quote the gate count, and neither was scanned: while the loop stood at 542 the deck's
# own "every claim, and the command that re-derives it" slide said **451**, in a row that NAMES THIS
# GATE as the command that re-derives it — a claim citing its own instrument, that the instrument had
# never read. The deck shipped that way through a public PDF. "Enumerate the family, assert over ALL
# of it" was the right lesson and it was applied to one file's siblings instead of the number's; the
# family is every prose surface that states the count, not every line of one document.
#
# The site list is declared ONCE and drives the scan, exactly as test/deckclaimcheck.sh arm (B) does
# with its own — a duplicated list is the bug both arms keep being widened to fix. A file that does
# not exist is skipped; a file that exists and states NO count fails, because "no wrong count" is
# vacuously true of a document that stopped making the claim, and a claim deleted is a claim drifted.
gateCountSites=( "docs/EVALS.md" "README.md" "present/deck5_ripwire_build.js" )

scanGateCounts() {                   # $1 = file, $2 = its display path → prints "line:number" per claim
    grep -nE '[0-9]+ gate scripts' "$1" || true
}

for site in "${gateCountSites[@]}"; do
    sitePath="$ROOT/$site"
    [ -f "$sitePath" ] || continue
    gateCountClaims="$( scanGateCounts "$sitePath" )"
    if [ -z "$gateCountClaims" ]; then
        printf 'FAIL: %s has no "<N> gate scripts" claim — the presence guard for this arm found nothing to check\n' "$site"
        fail=1
        continue
    fi
    while IFS= read -r claim; do
        [ -z "$claim" ] && continue
        claimLine="${claim%%:*}"
        claimNum="$( printf '%s' "$claim" | grep -oE '[0-9]+ gate scripts' | grep -oE '^[0-9]+' )"
        if [ "$claimNum" = "$loopNames" ]; then
            printf 'PASS: %s:%s gate count (%s) matches the loop\n' "$site" "$claimLine" "$claimNum"
        else
            printf 'FAIL: %s:%s says %s gate scripts, but the loop names %s\n' "$site" "$claimLine" "$claimNum" "$loopNames"
            fail=1
        fi
    done <<EOF
$gateCountClaims
EOF
done

# MUTATION CONTROL for the arm above. Every site passing proves only that some numbers were read and
# compared equal — never that a WRONG one would have been seen. The deck is the mutated site on
# purpose: it is the one this widening was written for, and the one whose scan had never run. A copy
# with the count deliberately shifted must be extracted, must actually differ from the derived loop
# length, and must be seen to differ by the SAME comparison the live arm uses.
mutSrc="$ROOT/present/deck5_ripwire_build.js"
if [ -f "$mutSrc" ]; then
    mutTmp="$( mktemp -t manifestcheck_mut.XXXXXX )"
    trap 'rm -f "$mutTmp"' EXIT
    wrongCount=$(( loopNames + 7 ))
    sed -E "s/${loopNames} gate scripts/${wrongCount} gate scripts/g" "$mutSrc" > "$mutTmp"
    mutClaims="$( scanGateCounts "$mutTmp" )"
    mutNum="$( printf '%s' "$mutClaims" | head -1 | grep -oE '[0-9]+ gate scripts' | grep -oE '^[0-9]+' )"
    if [ -z "$mutNum" ]; then
        printf 'FAIL: mutation control: could not re-extract a gate count from the mutated deck copy at all\n'
        fail=1
    elif [ "$mutNum" = "$loopNames" ]; then
        printf 'FAIL: mutation control: the injected wrong count did not take (%s still equals the derived %s) — the control is vacuous\n' "$mutNum" "$loopNames"
        fail=1
    else
        printf 'PASS: mutation control: a fabricated deck gate count (%s) is correctly seen as disagreeing with the loop (%s)\n' "$mutNum" "$loopNames"
    fi
fi

# ── I1 (capture-audit verify-wave1 2026-09-04): a gate that CALLS a shell function ABOVE its definition is
# inert at that call. Bash resolves functions at run time, so `x="$( fnorm a )"` before `fnorm(){…}` expands
# to the empty string with a "command not found" on stderr the battery never reads — shapingflagcheck.sh's
# (B) byte-identity arm compared "" to "" and passed unconditionally (fnorm called at line 211, defined at
# 395). The scan below: every function `name(){` / `name()\n{` / `function name` defined in a gate, every
# COMMAND-POSITION use of that name on an earlier NON-COMMENT line OUTSIDE any function body (a body only
# runs when its function is called, which may be later — that is legal and excluded). One line per finding.
usedBeforeDef="$( python3 - "$ROOT/test" <<'PY'
import os, re, sys
testDir = sys.argv[ 1 ]
defRe   = re.compile( r'^\s*(?:function\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*\(\)\s*(\{?)\s*(.*)$' )
funcRe  = re.compile( r'^\s*function\s+([A-Za-z_][A-Za-z0-9_]*)\s*(\{?)' )
hereRe  = re.compile( r"<<-?\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?" )
def strip( line ):
    # drop the comment tail and SINGLE-quoted strings; double quotes stay, because `"$( fn x )"` is a real
    # call (the shape the inert arm had) and a name in a message never sits in command position anyway
    line = re.sub( r"'[^']*'", "''", line )
    return re.sub( r'(^|\s)#.*$', '', line )
def heredocLines( lines ):
    # every line INSIDE a heredoc body (fixture content, python blocks): neither a definition nor a use
    inside, tag = [ False ] * len( lines ), None
    for i, raw in enumerate( lines ):
        if tag is not None:
            inside[ i ] = True
            if raw.strip() == tag:
                tag = None
            continue
        m = hereRe.search( re.sub( r'(^|\s)#.*$', '', raw ) )   # on the raw line: strip() would eat the quoted tag
        if m:
            tag = m.group( 1 )
    return inside
# the gates themselves plus the sourced helpers under test/lib/ (helper functions are defined before any gate
# sources them, but a helper can still call a sibling above its definition). NOTE: no apostrophes in this
# heredoc — it sits inside "$( … )" and the bash quote scanner reads a lone one as an open quote.
scripts = [ n for n in sorted( os.listdir( testDir ) ) if n.endswith( ".sh" ) ]
libDir  = os.path.join( testDir, "lib" )
if os.path.isdir( libDir ):
    scripts += [ os.path.join( "lib", n ) for n in sorted( os.listdir( libDir ) ) if n.endswith( ".sh" ) ]
for name in scripts:
    path  = os.path.join( testDir, name )
    lines = open( path, encoding = "utf-8", errors = "replace" ).read().split( "\n" )
    inHere = heredocLines( lines )
    # pass 1: definitions (line index) and function-body spans by brace depth
    defs, inBody = {}, [ False ] * len( lines )
    i = 0
    while i < len( lines ):
        raw = lines[ i ]
        m = defRe.match( raw ) or funcRe.match( raw )
        if m and not raw.lstrip().startswith( "#" ) and not inHere[ i ]:
            fname = m.group( 1 )
            defs.setdefault( fname, i )
            # body: from the first `{` (this line or the next) until depth returns to 0
            depth, j = 0, i
            started = False
            while j < len( lines ):
                body = strip( lines[ j ] )
                for ch in body:
                    if ch == "{":
                        depth += 1; started = True
                    elif ch == "}":
                        depth -= 1
                inBody[ j ] = True
                if started and depth <= 0:
                    break
                if not started and j > i + 1:
                    break            # no brace within two lines: not a body we can span
                j += 1
            i = j + 1
            continue
        i += 1
    # pass 2: command-position uses above the definition, outside every body
    for fname, defAt in defs.items():
        useRe = re.compile( r'(?:^|[;|&(!{]|\$\(|\bthen\b|\bdo\b|\belse\b)\s*' + re.escape( fname ) + r'(?=\s|\)|;|$)' )
        for k in range( defAt ):
            if inBody[ k ] or inHere[ k ]:
                continue
            code = strip( lines[ k ] )
            if not code.strip() or useRe.search( code ) is None:
                continue
            print( "test/%s: %s used at line %d, defined at line %d" % ( name, fname, k + 1, defAt + 1 ) )
PY
)"
if [ -z "$usedBeforeDef" ]; then
    printf 'PASS: no gate calls a shell function above its definition\n'
else
    printf 'FAIL: a gate calls a shell function before it is defined (the call expands EMPTY at run time — an inert arm):\n'
    printf '%s\n' "$usedBeforeDef" | sed 's/^/        /'
    fail=1
fi

exit "$fail"
