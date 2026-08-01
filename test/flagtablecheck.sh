#!/usr/bin/env bash
# flagtablecheck.sh — the ORDER-INDEPENDENCE premise behind kBoolFlags/kViewFlags/kIntFlags, re-derived
# from source.
#
# parseArgs used to be one ordered `else if` chain, so precedence was whatever the author wrote. 105 of its
# arms now live in three constexpr tables scanned AHEAD of the surviving hand-written arms
# (§6.1 Move B; the numeric table is §B8.2). Hoisting a matcher above the arms it used to sit
# below is only safe while NO literal in the surface shadows another — and "safe today" is not a property a
# table keeps on its own. The next flag someone adds is the one that breaks it:
#
#     add `--for-real` as a table bool while `--for=` is a table prefix   → still fine (exact vs prefix)
#     spell a table row `--for` instead of `--for=`                       → `--force` is stolen, silently
#
# That second case compiles, parses, exits 0 and produces a plausible map. Nothing else in the suite would
# see it: argvdiffcheck needs a pre-change binary to compare against, and flagsurfacecheck only asks whether
# a flag is RECOGNISED, not whether the right arm recognised it.
#
# So this gate re-derives the premise from src/cli.h on every run: every table literal, every hand-written
# arm's literal, and the matcher each one actually uses (== vs startsWith), then checks that no prefix
# matcher scanned early can swallow an argv meant for a different arm. It reads the source, not the binary,
# because the property is about the ORDER OF THE MATCHERS, which no output byte exposes.
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
cd "$ROOT"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -f src/cli.h ] || { echo "no src/cli.h"; exit 2; }

python3 - <<'PY'
import io, re, sys

L = io.open( "src/cli.h", encoding = "utf-8" ).read().split( "\n" )
fail = 0
def ok( m ): print( "  PASS  " + m )
def no( m ):
    global fail; fail = 1; print( "  FAIL  " + m )

# ── the tables: literal + which matcher the scan applies to it ────────────────────────────────────────
def rows( name ):
    i = next( ( k for k, l in enumerate( L ) if l.startswith( "inline constexpr %s" % name ) ), None )
    if i is None: return None
    body = []
    for l in L[ i + 2 : ]:
        if l.startswith( "};" ): break
        body.append( re.sub( r'//.*$', '', l ) )          # a naming comment must never be harvested as a row
    else:
        return None
    # §A9 V1-4 gave ViewFlag rows two OPTIONAL columns (needs=/example=) and §B8.2 gave IntFlag rows up to
    # NINE, which no longer fit on one line — so a row is matched by its `{ "--x=", &Config::member` head
    # anywhere in the (comment-stripped) block rather than by anchoring the whole row to a single line.
    # What this gate counts is literals, and that is unchanged.
    return re.findall( r'\{\s*"(--[^"]+)"\s*,\s*&Config::\w+', " ".join( body ) )

bools, views, ints = rows( "BoolFlag kBoolFlags[]" ), rows( "ViewFlag kViewFlags[]" ), rows( "IntFlag kIntFlags[]" )
if bools is None or views is None or ints is None:
    no( "could not read kBoolFlags/kViewFlags/kIntFlags out of src/cli.h — this gate is asserting nothing" ); sys.exit( 1 )
ok( "read the tables from source: %d exact-match rows, %d + %d prefix-match rows" % ( len( bools ), len( views ), len( ints ) ) )

# ── the hand-written arms still in parseArgs, with their real matcher ─────────────────────────────────
start = next( k for k, l in enumerate( L ) if "if( isTableFlag ) continue;" in l )
end   = next( k for k, l in enumerate( L ) if "unknown flag '%.*s'" in l )
hand  = []
for l in L[ start : end + 1 ]:
    m = re.match( r'^\s*(?:else )?if\(\s*(?:a == "(--[^"]*)"|startsWith\( a, "(--[^"]*)" \))', l )
    if m: hand.append( ( m.group( 1 ) or m.group( 2 ), "exact" if m.group( 1 ) else "prefix" ) )
# A SCRAPE tripwire, not a ledger: the exact count is asserted against kHandWrittenFlagArms two blocks
# down, and that assertion is the one that catches a dropped arm. This floor only fires when the regex above
# has stopped matching arms at all. §B5 (capture-audit-4) moved 23 arms into kViewFlags, taking the residue
# from 40 to 17 — so a floor of 20 would have failed on a correct change; it is now 12.
[ ok, no ][ len( hand ) < 12 ]( "read %d hand-written arms from parseArgs" % len( hand ) )

# ── the ledger the static_assert pins must match what is actually in the file ─────────────────────────
def konst( n ):
    m = next( ( re.search( r'=\s*(\d+);', l ) for l in L if l.startswith( "inline constexpr std::size_t %s" % n ) ), None )
    return int( m.group( 1 ) ) if m else -1
kh, kt = konst( "kHandWrittenFlagArms" ), konst( "kTotalFlagArms" )
if kh == len( hand ):  ok( "kHandWrittenFlagArms = %d matches the %d arms actually written out" % ( kh, len( hand ) ) )
else:                  no( "kHandWrittenFlagArms = %d but parseArgs has %d hand-written arms — the static_assert is pinning a stale number, so it cannot catch a dropped arm" % ( kh, len( hand ) ) )
if kt == len( bools ) + len( views ) + len( ints ) + len( hand ):
                       ok( "kTotalFlagArms = %d matches table + hand" % kt )
else:                  no( "kTotalFlagArms = %d but table + hand = %d" % ( kt, len( bools ) + len( views ) + len( ints ) + len( hand ) ) )

# ── the actual property: can an early matcher steal an argv meant for a later arm? ────────────────────
# Scan order: kBoolFlags (exact) → kViewFlags (prefix) → kIntFlags (prefix, §B8.2) → the hand arms.
def shadowing( surface ):
    out = []
    for i, ( lit, kind ) in enumerate( surface ):
        for j, ( other, okind ) in enumerate( surface ):
            if j <= i: continue                              # only an EARLIER matcher can steal
            # `other` is reachable only via argv it matches; the shortest such string is `other` itself.
            probe = other if okind == "exact" else other + "X"
            hit   = ( probe == lit ) if kind == "exact" else probe.startswith( lit )
            if hit: out.append( ( lit, kind, other, okind ) )
    return out

surface = [ ( l, "exact" ) for l in bools ] + [ ( l, "prefix" ) for l in views ] \
        + [ ( l, "prefix" ) for l in ints ] + hand
steals  = shadowing( surface )

if not steals:
    ok( "no matcher shadows a later arm across all %d literals (%d exact, %d prefix)"
        % ( len( surface ), sum( 1 for _, k in surface if k == "exact" ), sum( 1 for _, k in surface if k == "prefix" ) ) )
else:
    for lit, kind, other, okind in steals[ :6 ]:
        no( "%s (%s, scanned earlier) swallows argv meant for %s (%s)" % ( lit, kind, other, okind ) )

# ── a negative control: the SAME function, on a surface that does shadow ──────────────────────────────
# `--for` as a bare PREFIX row would swallow --force, which the real surface avoids only because the row
# is spelled `--for=`. Running the real detector over the counterfactual proves it is looking.
control = shadowing( [ ( "--for", "prefix" ), ( "--force", "exact" ) ] )
if control: ok( "control: the detector DOES flag a shadowing pair (--for before --force)" )
else:       no( "control: a known-shadowing pair came back clean — this gate proves nothing" )

sys.exit( fail )
PY
rc=$?
[ "$rc" = 0 ] || fail=1

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
