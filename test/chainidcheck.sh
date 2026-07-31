#!/usr/bin/env bash
# chainidcheck.sh — the id= a bundle EMITS must be an id the nav verbs ACCEPT.
#
# Lane F added n=/id= to --for/--pack-task rows so an agent could chain --for -> --expand/--callers
# without parsing a C++ declarator out of signature text. But the emitted id was not consumable:
# parseExpandToken split on the FIRST ':', turning "./src/serialize.h::XmlWriter::write" into the name
# "./src/serialize.h"; and resolveAllByNameQualified's file:name rule cut it the same way. So the
# chain key was printed and refused by the same binary.
#
# This gate pins the ROUND TRIP in both directions, because either half alone can rot silently:
#   producer -> consumer : an id from --for resolves on --expand/--callers/--impact
#   consumer -> producer : the bare name and file:name forms still resolve (purely additive)
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
cd "$ROOT"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN"; exit 2; }

echo "chainidcheck: BIN=$BIN"

# 1) harvest a REAL scoped id straight out of a --for bundle — never a hand-written literal, so the gate
#    keeps testing the actual emitted shape if the id format ever changes.
ID="$( "$BIN" . --for="serialize xml writer" 2>/dev/null \
      | grep -oE '<d [^>]*id="[^"]+"' | head -1 | grep -oE 'id="[^"]+"' | sed 's/id="//;s/"$//' )"
if [ -n "$ID" ] && [ "${ID#*::}" != "$ID" ]; then ok "harvested a scoped id from --for ($ID)"
else no "no scoped id= in --for output — lane F's chain key is missing"; echo "ALL FAIL"; exit 1; fi

# 2) producer -> consumer: that id resolves on each nav verb (exit 0 AND the verb echoes it back).
for v in expand callers impact uses; do
    if [ "$v" = expand ]; then out="$( "$BIN" . --top-k=0 "--expand=$ID" 2>&1 )"; else out="$( "$BIN" . "--$v=$ID" 2>&1 )"; fi
    rc=$?
    if [ $rc -eq 0 ] && ! printf '%s' "$out" | grep -q 'symbol not found\|matched no symbol'; then
        ok "--$v accepts the emitted id"
    else
        no "--$v REFUSED the id it emits (rc=$rc)"; printf '%s\n' "$out" | head -2 | sed 's/^/        /'
    fi
done

# 3) a range still composes ON an id — the ':' of "::" must never be read as the range seam.
if "$BIN" . --top-k=0 "--expand=$ID:1-3" 2>/dev/null | grep -q 'lines="'; then ok "id + :START-END range composes"
else no "id + range did not slice (the :: was probably eaten as a range separator)"; fi

# 4) consumer -> producer: the pre-existing forms are untouched (this change must be purely additive).
NAME="${ID##*::}"
"$BIN" . "--callers=$NAME"  2>/dev/null | grep -q "<callers of=\"$NAME\"" && ok "bare name still resolves" || no "bare-name resolution regressed"
"$BIN" . --callers="serialize.h:$NAME" 2>/dev/null | grep -q '<callers of=' && ok "file:name still resolves" || no "file:name disambiguation regressed"

# 5) a malformed range on a NON-id token must still degrade loudly to whole-body (the old contract).
#    REPINNED (§P8 seam 1, 2026-07-28): a tail that does NOT start with a digit is now a file:name selector
#    (`blobChecksum:abc` = "a def named abc in a path containing blobChecksum"), so the degrade path is
#    reached with a digit-leading malformed tail instead. The contract under test — degrade + loud note,
#    never a hard error — is unchanged; only the token that triggers it moved. See selectorchaincheck.sh.
err="$( "$BIN" . --top-k=1 --expand=blobChecksum:5x-9 2>&1 >/dev/null )"
printf '%s' "$err" | grep -qi 'malformed range' && ok "malformed range on a bare name still warns" || no "lost the malformed-range degrade note"

# 6) a genuine typo must still be refused — the "::" branch must not swallow unknown names.
"$BIN" . "--callers=./src/nope.h::Nope::nope" >/dev/null 2>&1 && no "a bogus canonical id was accepted" || ok "a bogus canonical id is still refused"

[ "$fail" = 0 ] && echo "ALL PASS" || echo "FAILURES ABOVE"
exit $fail
