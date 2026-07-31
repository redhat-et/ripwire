#!/usr/bin/env bash
# churnjsonstampcheck.sh — §B1.2 gate (PLAN_outputAudit3): a churn-ranked map must be DISTINGUISHABLE from
# the structural one on the JSON surface, not just the XML one.
#
# --help promises of --rank-by=churn: "stamps its own map with rank_by/window/at so it cannot pass for the
# structural one" (cli.h). The XML `<r>` element honours that (`at=` `rank_by="churn"` `window="18mo"`).
# The JSON sibling took no MapAnnotations at all, so `--rank-by=churn --json` and `--rank-by=pagerank --json`
# emitted KEYSET-IDENTICAL headers while every `k` underneath means something different — a machine consumer
# had no way to tell a git-change-frequency prior from call-graph importance.
#
# The assertion is a KEYSET DIFFERENCE, not a byte comparison: the two headers must differ by EXACTLY the
# three stamp keys {at, rank_by, window} — no more (a churn-only key that is not part of the stamp) and no
# fewer (the defect). Values are checked for MEANING (rank_by == "churn", window non-empty, at looks like a
# git sha), never pinned to a sha/window that moves with the tree.
#
# Runs against the repo itself: churn is mined from git history, so the corpus must be a git checkout.
#
# Usage: bash test/churnjsonstampcheck.sh [path/to/ctxpack]
# Exits non-zero on any failure; DOES NOT touch regression.sh.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${CTXPACK_BIN:-$ROOT/build/ctxpack}}"   # house convention: the suite passes the binary via CTXPACK_BIN
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

echo "churnjsonstampcheck: BIN=$BIN"
[ -x "$BIN" ]       || { no "binary not executable: $BIN"; echo "FAILURES ABOVE"; exit 1; }
[ -e "$ROOT/.git" ] || { no "$ROOT is not a git checkout — churn has no history to mine, the gate cannot run"; echo "FAILURES ABOVE"; exit 1; }   # -e, not -d: a git WORKTREE's .git is a file
command -v python3 >/dev/null 2>&1 || { no "python3 is REQUIRED (JSON keyset extraction) — not found"; echo "FAILURES ABOVE"; exit 1; }

"$BIN" "$ROOT/src" --rank-by=churn    --top-k=3 --json > "$TMP/churn.json"    2>"$TMP/churn.err"    || { no "--rank-by=churn --json exited non-zero"; cat "$TMP/churn.err"; echo "FAILURES ABOVE"; exit 1; }
"$BIN" "$ROOT/src" --rank-by=pagerank --top-k=3 --json > "$TMP/pagerank.json" 2>"$TMP/pagerank.err" || { no "--rank-by=pagerank --json exited non-zero"; cat "$TMP/pagerank.err"; echo "FAILURES ABOVE"; exit 1; }
[ -s "$TMP/churn.json" ] && [ -s "$TMP/pagerank.json" ] || { no "one of the two JSON maps is EMPTY"; echo "FAILURES ABOVE"; exit 1; }

# ── the keyset difference, computed on parsed JSON (never on a grep of the bytes) ────────────────────────
python3 - "$TMP/churn.json" "$TMP/pagerank.json" > "$TMP/verdict.txt" <<'PY'
import json, sys
churn = json.load( open( sys.argv[1] ) )
plain = json.load( open( sys.argv[2] ) )
extra   = sorted( set( churn ) - set( plain ) )
missing = sorted( set( plain ) - set( churn ) )
print( "EXTRA=" + ",".join( extra ) )
print( "MISSING=" + ",".join( missing ) )
print( "RANK_BY=" + str( churn.get( "rank_by", "" ) ) )
print( "WINDOW="  + str( churn.get( "window",  "" ) ) )
print( "AT="      + str( churn.get( "at",      "" ) ) )
print( "PLAIN_STAMPED=" + ",".join( sorted( k for k in ( "at", "rank_by", "window" ) if k in plain ) ) )
PY
[ -s "$TMP/verdict.txt" ] || { no "both maps must be PARSEABLE JSON — the extractor produced nothing"; echo "FAILURES ABOVE"; exit 1; }
. /dev/stdin <<EOF
$( sed 's/^\([A-Z_]*\)=\(.*\)$/\1="\2"/' "$TMP/verdict.txt" )
EOF

# (1) the defect itself: the churn header must NOT be keyset-identical to the pagerank one
if [ "$EXTRA" = "at,rank_by,window" ]; then
    ok "churn JSON header adds EXACTLY the stamp keys {at, rank_by, window}"
else
    no "churn JSON header keyset difference is '$EXTRA', want exactly 'at,rank_by,window' (empty ⇒ the two headers are indistinguishable)"
fi
[ -z "$MISSING" ] && ok "churn JSON header drops no key the pagerank header carries" \
                  || no "churn JSON header is MISSING keys the pagerank header has: $MISSING"

# (2) the values carry MEANING (not pinned to a sha/window that moves with the tree)
[ "$RANK_BY" = "churn" ] && ok "rank_by == \"churn\"" || no "rank_by is '$RANK_BY', want \"churn\""
[ -n "$WINDOW" ]         && ok "window is non-empty (\"$WINDOW\")" || no "window is empty — the mined window is the fact that makes k= interpretable"
case "$AT" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*) ok "at is a git sha stamp (\"$AT\")" ;;
    *) no "at is '$AT', want an abbreviated git sha (optionally +dirty)" ;;
esac

# (3) the structural map stays UNSTAMPED — the stamp is churn-only, so it can never be mistaken for a default
[ -z "$PLAIN_STAMPED" ] && ok "the pagerank JSON map carries no stamp keys (the default map is unchanged)" \
                        || no "the pagerank JSON map carries stamp keys it must not: $PLAIN_STAMPED"

# (4) XML/JSON parity — the two serializations must agree on the SAME three facts
XMLR="$( "$BIN" "$ROOT/src" --rank-by=churn --top-k=3 2>/dev/null | grep -o '<r [^>]*>' | head -1 )"
[ -n "$XMLR" ] || { no "could not extract the XML <r> element for the parity check"; echo "FAILURES ABOVE"; exit 1; }
case "$XMLR" in *"rank_by=\"$RANK_BY\""*) ok "XML rank_by= agrees with JSON rank_by" ;; *) no "XML/JSON disagree on rank_by ($XMLR)" ;; esac
case "$XMLR" in *"window=\"$WINDOW\""*)   ok "XML window= agrees with JSON window"   ;; *) no "XML/JSON disagree on window ($XMLR)"   ;; esac
case "$XMLR" in *"at=\"$AT\""*)           ok "XML at= agrees with JSON at"           ;; *) no "XML/JSON disagree on at ($XMLR)"       ;; esac

# (5) the "documented gap" enumeration in serialize.h must not name a gap that is now closed (trap-ledger #12:
#     a stale enumeration is itself a defect). Asserted on MEANING: the comment block above serializeJson may
#     not describe churn/rank_by as uncovered.
GAPDOC="$( sed -n '/NOT covered/,/^inline void serializeJson/p' "$ROOT/src/serialize.h" )"
[ -n "$GAPDOC" ] || { no "could not locate serializeJson's documented-gap comment block"; echo "FAILURES ABOVE"; exit 1; }
printf '%s' "$GAPDOC" | grep -qiE 'churn|rank_by' \
    && ok "the documented-gap comment names the churn stamp at all" \
    || no "the documented-gap comment never mentions the churn stamp — it reads as a complete coverage statement while omitting a fact this emitter serializes (a stale enumeration is itself a defect, trap-ledger #12)"
# the NOT-covered enumeration proper (its own sentence, which ends at extraBodyTokens) must not list churn
#     (flattened to one line first: the sentence STARTS mid-line, so a line-range extraction would drag in
#      the covered-scope text that legitimately names rank_by)
NOTCOVERED="$( printf '%s\n' "$GAPDOC" | tr '\n' ' ' | sed -e 's/.*NOT covered//' -e 's/extraBodyTokens.*//' )"
[ -n "$NOTCOVERED" ] || { no "could not locate the NOT-covered enumeration sentence"; echo "FAILURES ABOVE"; exit 1; }
printf '%s' "$NOTCOVERED" | grep -qiE 'churn|rank_by' \
    && no "the NOT-covered enumeration still lists churn/rank_by as uncovered" \
    || ok "the NOT-covered enumeration does not list churn/rank_by"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
