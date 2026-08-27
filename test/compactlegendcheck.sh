#!/usr/bin/env bash
# compactlegendcheck.sh — opt-in, versioned compact legends for the two highest-value targeted reads.
# The default/full dialect stays byte-identical; compact changes schema prose only and never drops the
# completeness/truncation/floor/path/ambiguity/degrade facts carried by attributes and payload rows.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${RIPWIRE_BIN:-$ROOT/build/ripwire}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
FIX="$ROOT/test/fixture"
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
run(){ "$BIN" "$FIX" "$@" --no-cache 2>"$TMP/err"; }

[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

# Explicit full is the compatibility spelling: it must not add even a schema attribute.
run --for='geometry distance' >"$TMP/for.default"
run --for='geometry distance' --legend=full >"$TMP/for.full"
run --grep=distance --grep-in=any >"$TMP/grep.default"
run --grep=distance --grep-in=any --legend=full >"$TMP/grep.full"
if diff -q "$TMP/for.default" "$TMP/for.full" >/dev/null && diff -q "$TMP/grep.default" "$TMP/grep.full" >/dev/null; then
    ok 'default == explicit --legend=full for --for and --grep'
else
    no 'explicit --legend=full changed default output'
fi

run --for='geometry distance' --legend=compact >"$TMP/for.compact"; rc_for=$?
run --grep=distance --grep-in=any --legend=compact >"$TMP/grep.compact"; rc_grep=$?
run --regex='dist.*' --legend=compact >"$TMP/regex.compact"; rc_regex=$?

if [ "$rc_for" -eq 0 ] && grep -q '<ctx[^>]* schema="ripwire.for/v1"' "$TMP/for.compact"; then
    ok '--for compact legend carries stable ripwire.for/v1 schema id'
else
    no '--for compact legend missing/refused ripwire.for/v1 schema id'
fi
if [ "$rc_grep" -eq 0 ] && [ "$rc_regex" -eq 0 ] \
    && grep -q '<grep[^>]* schema="ripwire.grep/v1"' "$TMP/grep.compact" \
    && grep -q '<grep[^>]* schema="ripwire.grep/v1"' "$TMP/regex.compact"; then
    ok '--grep/--regex compact legends share stable ripwire.grep/v1 schema id'
else
    no '--grep/--regex compact legends missing/refused ripwire.grep/v1 schema id'
fi

# The compact dialect has to buy real context budget, not just rename the prose.
for_kind_bytes="$( wc -c <"$TMP/for.default" | tr -d ' ' ) $( wc -c <"$TMP/for.compact" | tr -d ' ' )"
grep_kind_bytes="$( wc -c <"$TMP/grep.default" | tr -d ' ' ) $( wc -c <"$TMP/grep.compact" | tr -d ' ' )"
set -- $for_kind_bytes; [ "$2" -lt "$1" ] && ok "--for compact is smaller ($2 < $1 bytes)" || no "--for compact did not shrink ($2 >= $1 bytes)"
set -- $grep_kind_bytes; [ "$2" -lt "$1" ] && ok "--grep compact is smaller ($2 < $1 bytes)" || no "--grep compact did not shrink ($2 >= $1 bytes)"

# Safety/completeness attributes are DATA, not legend prose. Pin the important affirmative and negative
# forms in compact mode: exhaustive literal, paged/truncated literal, regex (never claims complete), and
# the conceptual --for bundle's explicit no-body reason plus capped listing vocabulary.
grep -q '<grep[^>]* complete="1"' "$TMP/grep.compact" \
    && grep -q '<grep[^>]* hits_capped="0"' "$TMP/grep.compact" \
    && grep -q '<grep[^>]* root="' "$TMP/grep.compact" \
    && ok 'compact literal keeps completeness, collection-floor and root/path facts' \
    || no 'compact literal hid completeness, collection-floor or root/path facts'

run --grep=distance --grep-in=any --limit=1 --legend=compact >"$TMP/grep.page"
if grep -q '<grep[^>]* shown="1"[^>]* capped="1"' "$TMP/grep.page" && ! grep -q '<grep[^>]* complete="1"' "$TMP/grep.page"; then
    ok 'compact paged grep keeps truncation and withholds false completeness'
else
    no 'compact paged grep lost truncation or fabricated completeness'
fi
if grep -q '<grep[^>]* hits_capped="0"' "$TMP/regex.compact" && ! grep -q '<grep[^>]* complete="1"' "$TMP/regex.compact"; then
    ok 'compact regex keeps floor disclosure and makes no completeness claim'
else
    no 'compact regex lost floor disclosure or fabricated completeness'
fi
if grep -q '<ctx[^>]* bundle="compact" bodies="0" reason="compact-route"' "$TMP/for.compact" \
    && grep -q '<sigs' "$TMP/for.compact" && grep -q '<hops[^>]* total="' "$TMP/for.compact"; then
    ok 'compact --for keeps bundle reason and listing disclosure attributes'
else
    no 'compact --for hid bundle reason or listing disclosure attributes'
fi

# Both opt-in documents remain deterministic and well-formed.
run --for='geometry distance' --legend=compact >"$TMP/for.compact.2"
run --grep=distance --grep-in=any --legend=compact >"$TMP/grep.compact.2"
if diff -q "$TMP/for.compact" "$TMP/for.compact.2" >/dev/null && diff -q "$TMP/grep.compact" "$TMP/grep.compact.2" >/dev/null; then
    ok 'compact legends are deterministic'
else
    no 'compact legend output is nondeterministic'
fi
if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TMP/for.compact" "$TMP/grep.compact" "$TMP/regex.compact" "$TMP/grep.page" >/dev/null 2>&1; then
        ok 'compact legend documents are well-formed XML'
    else
        no 'compact legend document is malformed XML'
    fi
fi

# Unsupported surfaces refuse instead of silently ignoring a requested output posture.
"$BIN" "$FIX" --callers=distance --legend=compact --no-cache >"$TMP/bad.out" 2>"$TMP/bad.err"; rc_bad=$?
if [ "$rc_bad" -ne 0 ] && grep -q -- '--legend=compact.*--for.*--grep.*--regex' "$TMP/bad.err"; then
    ok '--legend=compact refuses on unsupported surfaces'
else
    no '--legend=compact was silently ignored on an unsupported surface'
fi

[ "$fail" -eq 0 ] && echo 'ALL PASS' || echo 'FAILURES ABOVE'
exit "$fail"
