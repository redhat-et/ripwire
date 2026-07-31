#!/usr/bin/env bash
# dependencypincheck.sh — reproducible dependencies use immutable tags or commit ids.

set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
CMAKE="$ROOT/CMakeLists.txt"
SWIFT_COMMIT="31d17fe7e818a2048c808b5c6fdc2dc792f4f5b5"
fail=0

ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }

if grep -q "$SWIFT_COMMIT" "$CMAKE"; then
    ok "Swift grammar is pinned to the audited immutable commit"
else
    no "Swift grammar is not pinned to the audited immutable commit"
fi

swiftBlock="$( sed -n '/tree-sitter-swift.git/,+4p' "$CMAKE" )"
if printf '%s\n' "$swiftBlock" | grep -q 'GIT_SHALLOW FALSE'; then
    ok "arbitrary Swift commit uses a full fetch"
else
    no "Swift commit fetch is not configured with GIT_SHALLOW FALSE"
fi

if printf '%s\n' "$swiftBlock" | grep -Eq 'with-generated-files|GIT_TAG[[:space:]]+(main|master|HEAD)([[:space:]]|$)'; then
    no "Swift declaration still contains a moving ref"
else
    ok "Swift declaration contains no moving ref"
fi

if rg -n 'ctxpack_use_shared_source_commit\(swift|rev-parse HEAD' "$CMAKE" >/dev/null; then
    ok "shared Swift cache adoption validates the checked-out revision"
else
    no "shared Swift cache can bypass the declared immutable revision"
fi

[ "$fail" = 0 ] && printf 'ALL PASS\n' || printf 'FAILURES ABOVE\n'
exit "$fail"
