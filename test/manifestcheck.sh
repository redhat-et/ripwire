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

# ── a gate name parked PAST the loop's `; do` is silently disabled ─────────────────────────────────
# Both arms above can pass while a gate never runs: "every gate file is listed" greps the whole line and
# still finds the name, and the count arm only notices if the stated count was NOT independently moved to
# match. A merge resolver that whitespace-splits this line produces exactly that state -- the gate is off,
# the manifest agrees with itself, and nothing says so. Assert the loop line's TAIL carries no gate token.
loopTail="$( python3 -c "
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r'for _g in .*?; do(.*)', text)
print('' if not m else m.group(1))
" "$REGRESSION" )"
strayGates="$( printf '%s' "$loopTail" | tr ' \t' '\n\n' | grep -E '^[a-z0-9_]+check$' || true )"
if [ -n "$strayGates" ]; then
    printf 'FAIL: gate name(s) parked AFTER the loop'"'"'s `; do` in test/regression.sh — listed, counted as absent, and never run:\n'
    printf '        %s\n' $strayGates
    fail=1
else
    printf 'PASS: no gate name is stranded past the loop'"'"'s `; do` in test/regression.sh\n'
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
# The line the §8 claim actually sits on, derived the same way the number is. A hard-coded line number
# here was wrong by ~5,800 lines and pointed a reader at a published measurement to edit instead of the
# claim -- the same class of defect the count check itself exists to catch.
evalsLine="$( grep -nE 'loop in `test/regression\.sh` names [0-9]+' "$EVALS" | head -1 | cut -d: -f1 )"
[ -n "$evalsLine" ] || evalsLine="?"
if [ -z "$evalsStated" ]; then
    printf 'FAIL: docs/EVALS.md has no "loop in `test/regression.sh` names N" sentence to check (§8)\n'
    fail=1
elif [ -z "$loopNames" ]; then
    printf 'FAIL: could not derive the gate count from the for-loop in test/regression.sh\n'
    fail=1
elif [ "$evalsStated" = "$loopNames" ]; then
    printf 'PASS: docs/EVALS.md §8 gate count (%s) matches test/regression.sh loop length (%s)\n' "$evalsStated" "$loopNames"
else
    printf 'FAIL: docs/EVALS.md §8 says the loop names %s, but it actually names %s — update docs/EVALS.md:%s\n' "$evalsStated" "$loopNames" "$evalsLine"
    fail=1
fi

# ── the SIBLINGS of that number, which the check above never saw ────────────────────────────────────
# docs/EVALS.md states the gate count in more than one place, and until now exactly ONE of them was
# enforced. Both unenforced siblings drifted twice: once to 371 while the loop was at 373, and again
# to 374 while the loop reached 376 — the second time within one round of being corrected, because a
# passing manifestcheck reported confidence about a number it had not actually checked. That is
# METHODOLOGY §3 (a fix that lands on one family member and not its siblings) applied to a gate, and
# the fix is the §3 fix: enumerate the family, assert over ALL of it. Every "<N> gate scripts" claim
# in the file is now derived-vs-stated, so a new one added later is covered without editing this gate.
gateCountClaims="$( grep -nE '[0-9]+ gate scripts' "$EVALS" || true )"
if [ -z "$gateCountClaims" ]; then
    printf 'FAIL: docs/EVALS.md has no "<N> gate scripts" claim — the presence guard for this arm found nothing to check\n'
    fail=1
else
    while IFS= read -r claim; do
        claimLine="${claim%%:*}"
        claimNum="$( printf '%s' "$claim" | grep -oE '[0-9]+ gate scripts' | grep -oE '^[0-9]+' )"
        if [ "$claimNum" = "$loopNames" ]; then
            printf 'PASS: docs/EVALS.md:%s gate count (%s) matches the loop\n' "$claimLine" "$claimNum"
        else
            printf 'FAIL: docs/EVALS.md:%s says %s gate scripts, but the loop names %s\n' "$claimLine" "$claimNum" "$loopNames"
            fail=1
        fi
    done <<EOF
$gateCountClaims
EOF
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
