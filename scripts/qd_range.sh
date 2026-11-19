#!/usr/bin/env bash
# qd_range.sh — the pull-request range quality gate: `--quality-delta=<merge-base>..HEAD` over a repo (this one by
# default), failing on any GATING row the ack ledger does not cover. CI's qd-range job runs exactly this script, so a
# developer or a lane runs the identical check before pushing:
#
#   scripts/qd_range.sh origin/main                 # this checkout's HEAD against its merge-base with origin/main
#   scripts/qd_range.sh --bin build/ripwire -C DIR BASE [HEAD]
#
# WHY A RANGE. --quality-delta compares a change with its parent, so once a regression merges the next comparison's
# base already holds it and it never shows again (#697, quality-drift prompt). A per-commit check also misses a
# regression made in two steps, and a check run before the last edit passes for a tree it never saw. The range
# <merge-base>..HEAD is the whole branch, measured on its committed trees, every time CI runs.
#
# ACKS. The range form reads the ack ledger (.ripwire_quality_acks) from DIR's WORKING TREE, keyed root-relative, so
# a gating row is accepted the same way as everywhere else: `--quality-ack="why" --ack-only=<id>` writes a row with
# its reason, and the commit that carries the ledger change carries the decision. The FAIL line prints that command
# for every gating row. In CI the working tree IS the commit under test, so the ledger read is the committed one.
#
# OUTPUT. Every row of the answer as a table (gating, minor, new-symbol and the rest), the counts read off the
# answer's root element, then ONE verdict line: `qd-range: PASS ...` or `qd-range: FAIL ...` naming each gating row
# and how to ack it. Exit 0 = no gating row; 2 = gating rows; 1 = the check could not be made (no binary, a base that
# is not reachable — CI needs fetch-depth: 0 — no answer, or a partial answer under memory pressure, which cannot
# certify the kinds it skipped).
set -u
BIN="${RIPWIRE_BIN:-}"
DIR=""
while [ $# -gt 0 ]; do
    case "$1" in
        --bin) BIN="${2:?--bin needs a path}"; shift 2 ;;
        -C)    DIR="${2:?-C needs a directory}"; shift 2 ;;
        -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        --*)   echo "qd-range: unknown option '$1' (usage: qd_range.sh [--bin BIN] [-C DIR] BASE [HEAD])" >&2; exit 1 ;;
        *)     break ;;
    esac
done
BASE="${1:-}"
HEADREV="${2:-HEAD}"
[ -n "$BASE" ] || { echo "qd-range: FAIL — no BASE given (usage: qd_range.sh [--bin BIN] [-C DIR] BASE [HEAD]; e.g. origin/main)"; exit 1; }
if [ -z "$DIR" ]; then
    DIR="$( git rev-parse --show-toplevel 2>/dev/null )" || { echo "qd-range: FAIL — not inside a git checkout (pass -C DIR)"; exit 1; }
fi
DIR="$( cd "$DIR" && pwd )" || { echo "qd-range: FAIL — no directory $DIR"; exit 1; }
[ -n "$BIN" ] || BIN="$DIR/build/ripwire"
case "$BIN" in /*) ;; *) BIN="$PWD/$BIN" ;; esac
[ -x "$BIN" ] || { echo "qd-range: FAIL — no ripwire binary at $BIN (build it, or pass --bin / RIPWIRE_BIN)"; exit 1; }

resolve() { git -C "$DIR" rev-parse -q --verify "$1^{commit}" 2>/dev/null; }
headSha="$( resolve "$HEADREV" )" || { echo "qd-range: FAIL — HEAD '$HEADREV' names no commit in $DIR"; exit 1; }
baseSha="$( resolve "$BASE" )" || { echo "qd-range: FAIL — BASE '$BASE' is not reachable in $DIR (fetch it; in CI use actions/checkout fetch-depth: 0)"; exit 1; }
mb="$( git -C "$DIR" merge-base "$baseSha" "$headSha" 2>/dev/null )" \
    || { echo "qd-range: FAIL — '$BASE' and '$HEADREV' share no merge-base in $DIR (a shallow clone? CI needs fetch-depth: 0)"; exit 1; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
echo "qd-range: $BIN $DIR --quality-delta=$mb..$headSha (merge-base of $BASE and $HEADREV)"
ledgerNote="committed"
if ! git -C "$DIR" diff --quiet HEAD -- .ripwire_quality_acks 2>/dev/null; then ledgerNote="UNCOMMITTED changes in the working tree are read"; fi
echo "qd-range: ack ledger $DIR/.ripwire_quality_acks ($ledgerNote)"

"$BIN" "$DIR" "--quality-delta=$mb..$headSha" --legend=compact >"$TMP/qd.xml" 2>"$TMP/qd.err"
rc=$?
sed 's/^/  stderr: /' "$TMP/qd.err"

# The answer must be the one asked for: a <quality-delta> root naming the two resolved shas. Anything else (a refusal,
# a crash, a different comparison) is "no answer", never a pass.
# The legend comment in front of the answer spells row shapes (`<r kind= sym= ...>`) as text, so everything is read from
# the root element on: the answer is one line, and the comment's own "quality-delta schema=" has no '<' before it.
sed -n 's/.*\(<quality-delta schema=.*\)/\1/p' "$TMP/qd.xml" >"$TMP/body"
root="$( grep -o '<quality-delta [^>]*>' "$TMP/body" | head -1 )"
attr() { printf '%s' "$1" | grep -o " $2=\"[^\"]*\"" | head -1 | sed -E 's/^[^"]*"(.*)"$/\1/'; }
if [ -z "$root" ] || [ "$( attr "$root" base_ref )" != "$mb" ] || [ "$( attr "$root" target_ref )" != "$headSha" ]; then
    echo "qd-range: first bytes of stdout:"; head -c 600 "$TMP/qd.xml"; echo
    echo "qd-range: FAIL — no --quality-delta answer for $mb..$headSha (ripwire exit $rc)"
    exit 1
fi

# One row per line. Rows carry kind=, then sym= (or members= for a clone group), was=/now=/bar=, p=, and the markers
# gating="1" | sev="minor" | origin="new-symbol". Acked findings are not <r> rows (the root's acked= counts them); <sa>
# rows are stale ledger entries and never gate.
grep -o '<r [^>]*>' "$TMP/body" >"$TMP/rows" || true
unesc() { sed -e 's/&quot;/"/g' -e "s/&apos;/'/g" -e 's/&lt;/</g' -e 's/&gt;/>/g' -e 's/&amp;/\&/g'; }
seen=0; gating=0; : >"$TMP/gating"
printf '  %-5s %-26s %-11s %s  (%s)\n' "tier" "kind" "was->now" "symbol" "p"
while IFS= read -r row; do
    seen=$(( seen + 1 ))
    kind="$( attr "$row" kind )"; sym="$( attr "$row" sym | unesc )"
    [ -n "$sym" ] || sym="$( attr "$row" members | unesc )"
    was="$( attr "$row" was )"; now="$( attr "$row" now )"; [ -n "$now" ] || now="$( attr "$row" tokens )"
    p="$( attr "$row" p )"
    tier=row
    if [ "$( attr "$row" gating )" = 1 ]; then tier=GATE; gating=$(( gating + 1 )); printf '%s\t%s\t%s\t%s\t%s\n' "$kind" "$sym" "$p" "${was:-0}" "$now" >>"$TMP/gating"
    elif [ "$( attr "$row" sev )" = minor ]; then tier=minor
    elif [ "$( attr "$row" origin )" = new-symbol ]; then tier=new
    fi
    printf '  %-5s %-26s %-11s %s  (%s)\n' "$tier" "$kind" "${was:-0}->${now:-?}" "$sym" "$p"
done <"$TMP/rows"

counts="regressions=$( attr "$root" regressions ) gating=$( attr "$root" gating ) minor=$( attr "$root" minor ) new-symbol=$( attr "$root" new-symbol ) acked=$( attr "$root" acked ) stale=$( attr "$root" stale )"
echo "qd-range: rows seen=$seen; answer $counts"
skipped="$( attr "$root" kinds_skipped )"
if [ "$rc" = 6 ] || [ -n "$skipped" ]; then
    echo "qd-range: FAIL — a PARTIAL answer (ripwire exit $rc, kinds_skipped=$skipped): the skipped kinds are unmeasured, so this range cannot be certified clean; rerun where memory allows"
    exit 1
fi
if [ "$gating" != "$( attr "$root" gating )" ]; then
    echo "qd-range: FAIL — counted $gating gating row(s) but the answer says gating=$( attr "$root" gating ) (ripwire exit $rc): the rows were not all read"
    exit 1
fi
case "$rc" in
    0) if [ "$gating" = 0 ]; then
           echo "qd-range: PASS — 0 gating rows over ${mb:0:12}..${headSha:0:12} ($seen row(s) seen, $( attr "$root" acked ) acked)"
           exit 0
       fi ;;
    2) ;;
    *) echo "qd-range: FAIL — ripwire exit $rc on the range (see stderr above)"; exit 1 ;;
esac
[ "$gating" -gt 0 ] || { echo "qd-range: FAIL — ripwire exit $rc but no gating row was read"; exit 1; }

# The FAIL line: each gating row, then the one command that acks them all with a reason (run it where the branch is
# checked out, review the ledger diff, commit it). --ack-only matches a row's kind, canonical id or facet by substring.
ids=""; named=""
while IFS="$( printf '\t' )" read -r kind sym p was now; do
    named="${named:+$named; }$kind $sym ($p, $was->$now)"
    id="$sym"; case "$id" in *" | "*) id="${id%% | *}" ;; esac
    ids="${ids:+$ids,}$id"
done <"$TMP/gating"
echo "qd-range: FAIL — $gating gating row(s) over ${mb:0:12}..${headSha:0:12}: $named. Fix each, or ack it with a reason and commit the ledger: ripwire . --quality-delta=\$(git merge-base $BASE HEAD)..HEAD --quality-ack='<why this is deliberate>' --ack-only='$ids' && git add .ripwire_quality_acks"
exit 2
