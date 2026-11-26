#!/usr/bin/env bash
# packpartnerscheck.sh — --pack-task's <partners> block: the files that historically change WITH the task's top-ranked files.
#
# WHY. Across 752 real bug-fix commits the median fix edits two files, and developers miss a related change 45.7% of the time.
# --pack-task named the files a task touches and never the ones that usually change WITH them; --situ's [3] knew them, but only
# for a diff that already exists. The block reuses --situ's merge (situ.h mergeSeedPartners) over the ranking's first files.
#
# RED-FIRST: arms 1, 2, 3, 5, 6, 7, 8, 9, 11 fail on a binary without the block (no <partners>, no partners_none=, no sentence);
# arm 2's prohibitions are made non-vacuous by requiring the block they are about.
# Arm 4 (determinism) and arm 10's well-formedness hold on any binary — they guard the change, they do not prove it.
#
# Arms:
#   1. a.c and b.c co-change in 4 commits: a --pack-task about a.c lists b.c in <partners> with together="4"
#   2. d.c shares only 2 commits with a.c (under the 3-commit support floor): never listed; no seed is listed as its own partner
#   3. the JSON twin carries the same row ("p":"b.c","together":4)
#   4. deterministic: two runs, identical bytes (compact and full)
#   5. no git: no <partners> element, and the root says why: partners_none="no_git"; a repository with no commit says no_history
#   6. a shallow clone discloses shallow="1" on <partners> (a cut history, as --situ discloses it)
#   7. budget squeeze: 40 partners at --token-budget=1500 — the cut is disclosed (capped="1", partners_cut= = total - shown);
#      a larger budget serves every row with no partners_cut=, and shown= never falls as the budget grows (600..60000)
#   8. the legend defines what the block carries: full posture spells together= and partners_cut=, compact spells together=
#   9. #777's history policy, for THIS walk, rides <partners> inside the budget: the fixture's one agent commit is agent_commits="1"
#      (the JSON twin too), and the legend reads it
#  10. every answer above is well-formed XML
#  11. the bulk cut is disclosed: the fixture's two commits over 30 indexed files read bulk_skipped="2" on <partners>, and the
#      31-file commit adds nothing to b.c's support (arm 1 reads 4, not 5)
#
# Usage: test/packpartnerscheck.sh [BIN]   (default build/ripwire)
set -u
export RIPWIRE_NO_ROWLINES=1
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first (cmake --build build -j)"; exit 2; }
command -v git >/dev/null 2>&1 || { echo "git required"; exit 2; }
command -v xmllint >/dev/null 2>&1 || { echo "xmllint required"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 required"; exit 2; }
echo "packpartnerscheck: BIN=$BIN"

TMP="$( mktemp -d )"
trap '[ -n "${KEEP:-}" ] || rm -rf "$TMP"' EXIT
R="$TMP/repo"; NOGIT="$TMP/nogit"; EMPTY="$TMP/empty"; SH="$TMP/shallow"; WIDE="$TMP/wide"
mkdir -p "$R"

mkfn(){ printf 'int %s( int x )\n{\n    if( x > 1 ) return x + 1;\n    return x - 1;\n}\n' "$1"; }
T=1780000000
tick(){ T=$(( T + 3600 )); export GIT_AUTHOR_DATE="@$T +0000" GIT_COMMITTER_DATE="@$T +0000"; }
export GIT_AUTHOR_NAME=Hana GIT_AUTHOR_EMAIL=hana@x.com GIT_COMMITTER_NAME=Hana GIT_COMMITTER_EMAIL=hana@x.com
C(){ tick; d="$1"; shift; git -C "$d" add -A >/dev/null; git -C "$d" commit -qm "$@"; }

# ── the fixture: a.c is the task's file; b.c co-changes with it 4 times, d.c twice; c.c changes alone ────────────────────
git -C "$R" init -q -b main
mkfn alpha_widget_resize > "$R/a.c"; mkfn zq_bravo > "$R/b.c"; mkfn zq_charlie > "$R/c.c"; mkfn zq_delta > "$R/d.c"
for k in $( seq 1 29 ); do mkfn "zq_filler_$k" > "$R/filler_$k.c"; done
C "$R" "init"                                        # 33 indexed files: a bulk commit (over 30)
for i in 1 2 3 4; do printf '// ab %s\n' "$i" >> "$R/a.c"; printf '// ab %s\n' "$i" >> "$R/b.c"; C "$R" "a and b $i"; done
for i in 1 2;     do printf '// ad %s\n' "$i" >> "$R/a.c"; printf '// ad %s\n' "$i" >> "$R/d.c"; C "$R" "a and d $i"; done
for i in 1 2 3;   do printf '// c %s\n'  "$i" >> "$R/c.c"; C "$R" "c alone $i"; done
printf '// agent\n' >> "$R/c.c"; C "$R" "c with an agent" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
printf '// bulk\n' >> "$R/a.c"; printf '// bulk\n' >> "$R/b.c"; for k in $( seq 1 29 ); do printf '// bulk\n' >> "$R/filler_$k.c"; done
C "$R" "one 31-file commit: a, b and 29 fillers"     # the second bulk commit; it must NOT make a/b's support 5
TASK='fix `alpha_widget_resize` in a.c'

# oracle: the fixture is what the arms claim
AB="$( for h in $( git -C "$R" log --format=%H ); do git -C "$R" show --diff-filter=M --name-only --format= "$h" | grep -cxE 'a\.c|b\.c'; done | grep -cx 2 )"
[ "$AB" = 5 ] && ok "(oracle) a.c and b.c share 5 commits, 1 of them the 31-file bulk commit" || no "(oracle) a.c and b.c share $AB commits, not 5 — the arms prove nothing"

run(){ ( cd "$1" && "$BIN" . --pack-task="$2" "${@:3}" ) 2>/dev/null; }
partners_of(){ python3 - "$1" <<'PY_EOF'
import re, sys
doc = re.sub( r'<!--.*?-->', '', open( sys.argv[1], encoding = 'utf-8', errors = 'replace' ).read(), flags = re.S )
m = re.search( r'<partners\b[^>]*>(.*?)</partners>', doc, re.S )
print( ' '.join( '%s:%s' % ( p, n ) for p, n in re.findall( r'<f p="([^"]*)" together="(\d+)"/>', m.group( 1 ) ) ) if m else 'NONE' )
PY_EOF
}
# the PAYLOAD's elements only: a legend comment spells `<partners seeds= …>` in prose, and that is not the element
payload(){ python3 -c 'import re,sys; print( re.sub( r"<!--.*?-->", "", open( sys.argv[1], encoding = "utf-8", errors = "replace" ).read(), flags = re.S ) )' "$1"; }
attr_of(){ payload "$1" | grep -oE "<$2 [^>]*" | head -1 | grep -oE " $3=\"[^\"]*\"" | head -1 | sed -E "s/^ $3=\"//; s/\"\$//"; }
has_el(){ payload "$1" | grep -q "<$2[ >]"; }

run "$R" "$TASK" > "$TMP/a.xml"
run "$R" "$TASK" --legend=full > "$TMP/af.xml"
P="$( partners_of "$TMP/a.xml" )"

# 1
case " $P " in *" b.c:4 "*) ok "1. <partners> lists b.c with together=\"4\" ($P)";; *) no "1. b.c:4 not in <partners>: '$P'";; esac
# 2 — a prohibition passes on any binary that prints no block at all, so it holds only beside a block that exists
[ "$P" = NONE ] && no "2. no <partners> block, so 'not listed' would be vacuous"
case " $P " in *" d.c:"*) no "2. d.c (2 shared commits, under the floor) is listed: '$P'";; *) ok "2. d.c, under the 3-commit floor, is not listed";; esac
case " $P " in *" a.c:"*) no "2. the seed a.c is listed as its own partner: '$P'";; *) ok "2. the seed a.c is not listed as a partner";; esac
# 3
run "$R" "$TASK" --json > "$TMP/a.json"
if python3 - "$TMP/a.json" <<'PY_EOF'
import json, sys
d = json.load( open( sys.argv[1], encoding = 'utf-8' ) )
rows = d.get( 'partners' )
sys.exit( 0 if isinstance( rows, list ) and { 'p': 'b.c', 'together': 4 } in rows and d.get( 'partners_total' ) == len( rows ) else 1 )
PY_EOF
then ok "3. the JSON twin carries {\"p\":\"b.c\",\"together\":4}"; else no "3. the JSON twin lacks b.c's row: $( grep -o '"partners[^]]*' "$TMP/a.json" | head -c 300 )"; fi
# 4
run "$R" "$TASK" > "$TMP/a2.xml"; run "$R" "$TASK" --legend=full > "$TMP/af2.xml"
if cmp -s "$TMP/a.xml" "$TMP/a2.xml" && cmp -s "$TMP/af.xml" "$TMP/af2.xml"; then ok "4. deterministic: compact and full answers are byte-identical across two runs"
else no "4. two runs differ"; fi

# 5
mkdir -p "$NOGIT"; cp "$R"/*.c "$NOGIT/"
run "$NOGIT" "$TASK" > "$TMP/n.xml"
if ! has_el "$TMP/n.xml" partners && [ "$( attr_of "$TMP/n.xml" ctx partners_none )" = no_git ]; then ok "5. no git: no <partners>, partners_none=\"no_git\" on the root"
else no "5. no git: '$( grep -oE '<partners[^>]*|partners_none="[^"]*"' "$TMP/n.xml" | head -2 | tr '\n' ' ' )'"; fi
mkdir -p "$EMPTY"; cp "$R"/*.c "$EMPTY/"; git -C "$EMPTY" init -q -b main
run "$EMPTY" "$TASK" > "$TMP/e.xml"
if ! has_el "$TMP/e.xml" partners && [ "$( attr_of "$TMP/e.xml" ctx partners_none )" = no_history ]; then ok "5. a repository with no commit: partners_none=\"no_history\""
else no "5. no commit: '$( grep -oE '<partners[^>]*|partners_none="[^"]*"' "$TMP/e.xml" | head -2 | tr '\n' ' ' )'"; fi

# 6
git clone -q --depth=2 "file://$R" "$SH" 2>/dev/null
if [ "$( git -C "$SH" rev-parse --is-shallow-repository 2>/dev/null )" = true ]; then
    run "$SH" "$TASK" > "$TMP/s.xml"
    if [ "$( attr_of "$TMP/s.xml" partners shallow )" = 1 ]; then ok "6. a shallow clone: shallow=\"1\" on <partners>"
    else no "6. shallow clone: '$( grep -oE '<partners[^>]*|partners_none="[^"]*"' "$TMP/s.xml" | head -2 | tr '\n' ' ' )'"; fi
else no "6. (fixture) the --depth=2 clone is not shallow"; fi

# 7 — 40 partners, each sharing 3 commits with a.c (commits of 11 files: under the 30-file bulk cut)
mkdir -p "$WIDE"; git -C "$WIDE" init -q -b main
mkfn alpha_widget_resize > "$WIDE/a.c"
for k in $( seq 10 49 ); do mkfn "zq_partner_with_a_long_descriptive_name_$k" > "$WIDE/partner_with_a_long_descriptive_name_$k.c"; done
C "$WIDE" "init"
for g in 1 2 3 4; do for rep in 1 2 3; do
    printf '// g%s r%s\n' "$g" "$rep" >> "$WIDE/a.c"
    for k in $( seq $(( 10 * g )) $(( 10 * g + 9 )) ); do printf '// r%s\n' "$rep" >> "$WIDE/partner_with_a_long_descriptive_name_$k.c"; done
    C "$WIDE" "group $g rep $rep"
done; done
run "$WIDE" "$TASK" --token-budget=1500 > "$TMP/w.xml"     # MEASURED: 13 of the 40 rows fit here (0 at 1000, 40 at 2500)
run "$WIDE" "$TASK" --token-budget=60000 > "$TMP/wbig.xml"
WT="$( attr_of "$TMP/w.xml" partners total )"; WS="$( attr_of "$TMP/w.xml" partners shown )"; WC="$( attr_of "$TMP/w.xml" partners partners_cut )"
WCAP="$( attr_of "$TMP/w.xml" partners capped )"
if [ "$WT" = 40 ] && [ -n "$WS" ] && [ "$WS" -lt 40 ] && [ "$WCAP" = 1 ] && [ "$WC" = "$(( WT - WS ))" ] \
   && [ "$( partners_of "$TMP/w.xml" | wc -w | tr -d ' ' )" = "$WS" ]; then
    ok "7. budget squeeze: shown=$WS of total=$WT, capped=\"1\", partners_cut=\"$WC\" — the cut is disclosed"
else no "7. squeeze: total=$WT shown=$WS capped=$WCAP partners_cut=$WC rows=$( partners_of "$TMP/w.xml" | wc -w | tr -d ' ' )"; fi
BS="$( attr_of "$TMP/wbig.xml" partners shown )"
if [ "$BS" = 40 ] && [ -z "$( attr_of "$TMP/wbig.xml" partners partners_cut )" ]; then ok "7. a larger budget serves all 40 rows, no partners_cut="
else no "7. at --token-budget=60000: shown=$BS partners_cut=$( attr_of "$TMP/wbig.xml" partners partners_cut )"; fi
prev=0; mono=1; seq7=""
for b in 600 1000 1500 2000 2500 6000 60000; do
    run "$WIDE" "$TASK" --token-budget=$b > "$TMP/wm.xml"; n="$( attr_of "$TMP/wm.xml" partners shown )"; seq7="$seq7 $b:$n"
    { [ -n "$n" ] && [ "$n" -ge "$prev" ]; } || mono=0; prev="${n:-0}"
done
[ "$mono" = 1 ] && ok "7. shown= is monotone in the budget:$seq7" || no "7. shown= falls as the budget grows:$seq7"

# 8
if grep -q 'together= commits' "$TMP/af.xml" && grep -q 'partners_cut=N' "$TMP/af.xml"; then ok "8. the full legend defines together= and partners_cut="
else no "8. the full legend lacks together=/partners_cut="; fi
if grep -q 'together=N' "$TMP/a.xml"; then ok "8. the compact legend defines together="; else no "8. the compact legend lacks together="; fi
if grep -q 'partners_none=:' "$TMP/n.xml"; then ok "8. the compact legend defines partners_none= where it rides"; else no "8. no partners_none= reading on the no-git answer"; fi

# 9
if [ "$( attr_of "$TMP/a.xml" partners agent_commits )" = 1 ] && grep -q '"partners_agent_commits":1' "$TMP/a.json" \
   && grep -q 'agent_commits=N' "$TMP/a.xml" && grep -q 'agent_commits=N' "$TMP/af.xml"; then ok "9. <partners agent_commits=\"1\">: this walk's own policy count, JSON twin and both legends"
else no "9. agent_commits on <partners>='$( attr_of "$TMP/a.xml" partners agent_commits )' json=$( grep -o '"partners_agent_commits":[0-9]*' "$TMP/a.json" )"; fi

# 11
BK="$( attr_of "$TMP/a.xml" partners bulk_skipped )"
if [ "$BK" = 2 ] && grep -q '"partners_bulk_skipped":2' "$TMP/a.json"; then ok "11. the bulk cut is disclosed: bulk_skipped=\"2\" (XML and JSON)"
else no "11. bulk_skipped='$BK' on <partners>, JSON: $( grep -o '"partners_bulk_skipped":[0-9]*' "$TMP/a.json" )"; fi

# 10
bad=0
for f in a af a2 n e s w wbig; do [ -s "$TMP/$f.xml" ] || continue; xmllint --noout "$TMP/$f.xml" 2>/dev/null || { bad=1; echo "    malformed: $f.xml"; }; done
[ "$bad" = 0 ] && ok "10. every answer is well-formed XML" || no "10. a malformed answer"

[ "$fail" = 0 ] && { echo "packpartnerscheck: PASS"; exit 0; }
echo "packpartnerscheck: FAIL"; exit 1
