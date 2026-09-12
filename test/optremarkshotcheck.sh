#!/usr/bin/env bash
# optremarkshotcheck.sh — scripts/optremarks.py's HOT_FILES must still describe the tree it triages.
#
# WHY THIS EXISTS, AND WHY optremarkscheck.sh DID NOT CATCH IT.
#
# `--hot` narrows the opt-record to a literal, reviewable list of files (HOT_FILES) so the report's
# notion of "hot" stays auditable instead of being a heuristic nobody can review. The match is EXACT
# (`r.file in HOT_FILES`) — which is what makes it reviewable, and also what makes it silently wrong
# the moment a listed file is split into sections that keep the same translation unit and take new
# names.
#
# That is what happened. The ingest split moved ~18,000 lines of src/ingest.cpp into fifteen
# src/ingest_*.h sections of the SAME translation unit. Every path in HOT_FILES still existed, so
# nothing failed. The compiler still emitted the same remarks; their DebugLoc now names the section
# headers, and `--hot` matched none of them. Measured on a real narrowed record at the tip this gate
# was written against: the ingest family carries 33,957 first-party remarks, and `--hot` saw 69 —
# 0.2%. The two hottest own-code phases in the tool (ingest_sidecap.h at 23.7% + 5.6% of a cold run,
# ingest_parsepool.h at 10.2%) were invisible to the triage for as long as the split has existed.
#
# optremarkscheck.sh asserts the INVERSE — that `--hot` does not DROP a file HOT_FILES names — and it
# stayed green the whole time, because src/ingest.cpp is still listed and still exists. A list can be
# perfectly self-consistent and still describe a tree that moved out from under it. The missing
# assertion is a COVERAGE one, and coverage cannot be asserted against the list alone: it has to be
# asserted against the SOURCE TREE.
#
# THE RULE. Every file the tree groups WITH a hot file must be an explicit DECISION — in HOT_FILES, or
# in COLD_FILES with a stated reason. Two grouping relations, both mechanical, neither a heuristic:
#
#   * TRANSLATION-UNIT SECTIONS. This repo splits a large .cpp into sections that #include into one TU
#     and refuse to compile anywhere else (`#error` unless RIPWIRE_<X>_TU is defined). That guard IS
#     the membership statement, written by the section about itself — so it cannot drift from the
#     truth the way a name convention can. If any member of a TU is hot, every member needs a decision.
#   * NAME FAMILIES. `foo_bar.h` beside an existing `foo.h`/`foo.cpp`, and `x.h` beside `x.inl`. Over
#     the whole tree this relation groups exactly three families, so it is a scalpel, not a dragnet.
#     It exists to cover what the TU guard does not: a plain header split (src/ingest.h) and a
#     header/inline pair (src/infra/radixSort.h + .inl).
#
# Plus: every translation unit under src/ is accounted for at all — so a NEW hot phase cannot appear
# unnoticed — every listed path exists, the lists are disjoint, and every exclusion states a reason.
#
# WHAT THIS GATE DELIBERATELY DOES NOT SAY. It does not say "every large file must be hot". A
# size-threshold rule would drag src/serialize.h (7,536 lines), src/quality.h and src/mcpverbs.h into
# a list whose entire purpose is to be SMALLER than the tree — "hot set" would come to mean "the
# codebase", and `--hot` would stop narrowing anything. So the cap arm below asserts the list stays a
# focus list, and the closure arms assert that every file grouped with a hot one is a decision rather
# than a silence. Those two pull in opposite directions on purpose.
#
# Usage:  bash test/optremarkshotcheck.sh

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
TRIAGE="$ROOT/scripts/optremarks.py"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

command -v python3 >/dev/null || { echo "python3 required"; exit 2; }
[ -f "$TRIAGE" ] || { echo "missing $TRIAGE"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "optremarkshotcheck: ROOT=$ROOT"

# The audit. It loads the REAL scripts/optremarks.py (never a rewritten copy) and walks the REAL tree,
# so the mutation probes below differ from the production run in exactly one value and nothing else.
# The HOTSET_PROBE_* hooks live here in the gate, not in the shipped script: production behaviour has
# no idea they exist.
audit()
{
    python3 - "$TRIAGE" "$ROOT" <<'PY'
import importlib.util, os, re, sys

scriptPath, root = sys.argv[ 1 ], sys.argv[ 2 ]
spec = importlib.util.spec_from_file_location( "optremarks_under_audit", scriptPath )
mod  = importlib.util.module_from_spec( spec )
spec.loader.exec_module( mod )                  # import-safe: optremarks.py runs main() only under __main__

hot  = list( mod.HOT_FILES )
# A missing COLD_FILES is itself a finding, but it must NOT short-circuit: the whole point of the run
# is the list of files nobody decided about, and returning one meta-error instead would hide it.
cold = [ ( p, r ) for p, r in getattr( mod, "COLD_FILES", () ) ]
missingColdList = not hasattr( mod, "COLD_FILES" )

# ── probe hooks (gate-only; see audit() above) ────────────────────────────────────────────────────
drop = os.environ.get( "HOTSET_PROBE_DROP_HOT", "" )
if drop:
    hot = [ p for p in hot if p != drop ]
dropCold = os.environ.get( "HOTSET_PROBE_DROP_COLD", "" )
if dropCold:
    cold = [ e for e in cold if e[ 0 ] != dropCold ]
addHot = os.environ.get( "HOTSET_PROBE_ADD_HOT", "" )
if addHot:
    hot = hot + [ addHot ]
blank = os.environ.get( "HOTSET_PROBE_BLANK_REASON", "" )
if blank:
    cold = [ ( p, "" if p == blank else r ) for p, r in cold ]
bloat = os.environ.get( "HOTSET_PROBE_BLOAT", "" )

kExts = ( ".h", ".hpp", ".inl", ".cpp" )
srcDir = os.path.join( root, "src" )

files = []
for dirpath, dirs, names in os.walk( srcDir ):
    dirs.sort()
    for name in sorted( names ):
        if name.endswith( kExts ):
            files.append( os.path.relpath( os.path.join( dirpath, name ), root ) )
files.sort()
if bloat:
    hot = hot + [ f for f in files if f not in hot ]

coldPaths = [ p for p, _r in cold ]
accounted = set( hot ) | set( coldPaths )
violations = []


def flag( kind, path, why ):
    violations.append( ( kind, path, why ) )


if missingColdList:
    flag( "no-cold-list", "scripts/optremarks.py",
          "no COLD_FILES tuple - every exclusion below is a silence rather than a reviewable decision" )


# ── relation 1: translation-unit sections, as declared by the file's own #error guard ──────────────
kTuGuard = re.compile( r"^[ \t]*#[ \t]*(?:if|ifdef|ifndef|define|elif)\b.*\bRIPWIRE_([A-Z0-9]+)_TU\b", re.M )
tuOf = {}
for rel in files:
    with open( os.path.join( root, rel ), "r", errors = "replace" ) as fh:
        m = kTuGuard.search( fh.read() )
    if m:
        tuOf[ rel ] = m.group( 1 )
tuMembers = {}
for rel, tag in tuOf.items():
    tuMembers.setdefault( tag, [] ).append( rel )


# ── relation 2: name families — foo_bar.h under an existing foo.*, and x.h beside x.inl ────────────
def familyOf( rel ):
    dirName, base = os.path.split( rel )
    stem = os.path.splitext( base )[ 0 ]
    while "_" in stem:
        parent = stem.rsplit( "_", 1 )[ 0 ]
        if any( os.path.exists( os.path.join( root, dirName, parent + ext ) ) for ext in kExts ):
            stem = parent
        else:
            break
    return os.path.join( dirName, stem )


famMembers = {}
for rel in files:
    famMembers.setdefault( familyOf( rel ), [] ).append( rel )

# ── arm A: every translation unit in src/ is an explicit decision ──────────────────────────────────
for rel in files:
    if rel.endswith( ".cpp" ) and rel not in accounted:
        flag( "tu-unaccounted", rel, "a translation unit under src/, neither hot nor explicitly cold" )

# ── arm B: TU-section closure ──────────────────────────────────────────────────────────────────────
for tag, members in sorted( tuMembers.items() ):
    if any( m in hot for m in members ):
        for m in sorted( members ):
            if m not in accounted:
                flag( "section-unaccounted", m, "section of RIPWIRE_%s_TU, whose TU has a hot member" % tag )

# ── arm C: name-family closure ─────────────────────────────────────────────────────────────────────
for fam, members in sorted( famMembers.items() ):
    if len( members ) > 1 and any( m in hot for m in members ):
        for m in sorted( members ):
            if m not in accounted:
                flag( "family-unaccounted", m, "name family %s has a hot member" % fam )

# ── arm D: no dead entries, in either list ─────────────────────────────────────────────────────────
for p in list( hot ) + coldPaths:
    if not os.path.exists( os.path.join( root, p ) ):
        flag( "missing", p, "listed but not on disk" )

# ── arm E: the lists mean what they say ────────────────────────────────────────────────────────────
for p in sorted( set( hot ) & set( coldPaths ) ):
    flag( "both-lists", p, "listed as hot AND as deliberately cold" )
seen = set()
for p in hot:
    if p in seen:
        flag( "duplicate", p, "listed twice in HOT_FILES" )
    seen.add( p )
for p, r in cold:
    if len( r.strip() ) < 20:
        flag( "empty-reason", p, "COLD_FILES entry without a real reason - stating WHY is the point of the list" )

# ── arm F: the hot set stays a FOCUS list, not a copy of the tree ──────────────────────────────────
kMaxHot, kMaxShare = 40, 0.25
if len( hot ) > kMaxHot or len( hot ) > kMaxShare * len( files ):
    flag( "not-a-focus-list", "HOT_FILES",
          "%d entries over %d first-party files (ceiling: %d and %.0f%%) - a hot set that is the whole tree narrows nothing"
          % ( len( hot ), len( files ), kMaxHot, 100 * kMaxShare ) )

for kind, path, why in violations:
    print( "VIOLATION %-20s %s  (%s)" % ( kind, path, why ) )
for tag, members in sorted( tuMembers.items() ):
    print( "TUGROUP %s members=%d hot=%d" % ( tag, len( members ), sum( 1 for m in members if m in hot ) ) )
for fam, members in sorted( famMembers.items() ):
    if len( members ) > 1:
        print( "FAMILY %s members=%d hot=%d" % ( fam, len( members ), sum( 1 for m in members if m in hot ) ) )
print( "AUDIT hot=%d cold=%d files=%d tus=%d violations=%d"
       % ( len( hot ), len( cold ), len( files ), sum( 1 for f in files if f.endswith( ".cpp" ) ), len( violations ) ) )
sys.exit( 1 if violations else 0 )
PY
}

# ── (0) the audit can actually SEE what it asserts ─────────────────────────────────────────────────
# A coverage gate whose relations came back empty would report "no unaccounted files" over a tree it
# never grouped, and that is the green-while-inert shape CONTRIBUTING.md §2 names. Assert the inputs
# before believing the verdict.
REPORT="$TMP/audit.txt"
audit >"$REPORT" 2>"$TMP/audit.err"; auditRc=$?
[ -s "$REPORT" ] || { echo "  FAIL  the audit produced no output:"; cat "$TMP/audit.err"; exit 1; }

srcFiles="$( sed -n 's/^AUDIT .*files=\([0-9]*\) .*/\1/p' "$REPORT" )"
srcTus="$(   sed -n 's/^AUDIT .*tus=\([0-9]*\) .*/\1/p'   "$REPORT" )"
[ "${srcFiles:-0}" -ge 100 ] && [ "${srcTus:-0}" -ge 4 ] \
    && ok "the audit walked the real tree ($srcFiles first-party sources, $srcTus translation units)" \
    || no "the audit saw $srcFiles sources / $srcTus TUs — it is not reading src/, so every arm below is vacuous"

ingestMembers="$( sed -n 's/^TUGROUP INGEST members=\([0-9]*\) .*/\1/p' "$REPORT" )"
[ "${ingestMembers:-0}" -ge 10 ] \
    && ok "the TU-section relation is live: RIPWIRE_INGEST_TU groups $ingestMembers files by their own #error guard" \
    || no "the TU-section relation found ${ingestMembers:-0} INGEST members — the guard convention moved and the closure arm is inert"

famCount="$( grep -c '^FAMILY ' "$REPORT" )"
[ "${famCount:-0}" -ge 2 ] \
    && ok "the name-family relation is live ($famCount multi-member families across the tree)" \
    || no "the name-family relation found ${famCount:-0} families — it is inert"

# ── (1) the verdict ────────────────────────────────────────────────────────────────────────────────
if [ "$auditRc" -eq 0 ]; then
    ok "every file the tree groups with a hot one is an explicit decision (hot, or cold with a reason)"
else
    no "HOT_FILES has drifted from the tree it triages — --hot is silently skipping code it claims to cover:"
    grep '^VIOLATION' "$REPORT" | sed 's/^/        /'
fi

# ── (2) mutation probes: prove each arm can observe its own failure ────────────────────────────────
# Every arm above is an assertion about a list; an assertion about a list passes trivially when the
# code behind it has stopped running. Each probe re-runs the IDENTICAL audit with exactly one value
# changed and requires the matching violation to appear.
probe()
{
    local envVar="$1" envVal="$2" wantKind="$3" label="$4"
    local out="$TMP/probe_$wantKind.txt"
    env "$envVar=$envVal" bash -c "$( declare -f audit ); audit" >"$out" 2>&1
    if grep -q "^VIOLATION $wantKind " "$out"; then
        ok "mutation probe: $label"
    else
        no "mutation probe INERT: $label — the audit stayed clean with the defect injected"
        sed -n '1,4p' "$out" | sed 's/^/        /'
    fi
}

# These probes name src/ingest_sidecap.h and src/main.cpp because those two are the exact shapes that
# went wrong and could go wrong again: the hottest section of a split TU, and a translation unit.
export TRIAGE ROOT
probe HOTSET_PROBE_DROP_HOT       "src/ingest_sidecap.h" section-unaccounted \
      "dropping the hottest ingest section from HOT_FILES is caught by the TU-section closure"
probe HOTSET_PROBE_DROP_COLD      "src/main.cpp"         tu-unaccounted \
      "a translation unit in neither list is caught (a NEW hot phase cannot appear unnoticed)"
probe HOTSET_PROBE_ADD_HOT        "src/no_such_file.h"   missing \
      "a listed path that is not on disk is caught (the other direction of the same drift)"
probe HOTSET_PROBE_BLANK_REASON   "src/main.cpp"         empty-reason \
      "an exclusion with no stated reason is caught"
probe HOTSET_PROBE_BLOAT          "1"                    not-a-focus-list \
      "pasting the whole tree into HOT_FILES is caught — coverage must not be bought by making 'hot' meaningless"

# ── (3) the two lists are still wired to the thing they filter ─────────────────────────────────────
# HOT_FILES only means anything because --hot matches against it. If that lookup is refactored away,
# every arm above keeps passing over a list nothing reads.
grep -q 'r.file in HOT_FILES' "$TRIAGE" \
    && ok "--hot still filters on HOT_FILES membership (the list this gate audits is the list it uses)" \
    || no "scripts/optremarks.py no longer filters --hot on HOT_FILES — this gate is auditing a dead list"

[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "FAILURES ABOVE"; exit 1; }
