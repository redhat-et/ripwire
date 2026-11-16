#!/usr/bin/env bash
# forms.sh — one environment variable per Bash read form; test/bashenvcheck.sh asserts each row.
set -euo pipefail

: "${FORM_REQUIRED_COLON:?FORM_REQUIRED_COLON must be set and non-empty}"
: "${FORM_REQUIRED_PLAIN?FORM_REQUIRED_PLAIN must be set}"
target="${FORM_DEFAULT_COLON:-/srv/default path}"
suffix="${FORM_UNSET_DEFAULT-}"
flag="${FORM_ALT_COLON:+--verbose} ${FORM_ALT_PLAIN+--quiet}"
echo "$FORM_PLAIN_BARE ${FORM_PLAIN_BRACED} ${#FORM_PLAIN_LENGTH} ${FORM_PLAIN_ARRAY[@]} ${FORM_PLAIN_TRIM%/}"
if [[ -n "$FORM_TEST_N" ]] && [ -z "${FORM_TEST_Z_DEFAULT:-}" ]; then
    echo "$target $suffix $flag"
fi
test -z "$FORM_TEST_BUILTIN" || echo set
: "${FORM_ASSIGN_COLON:=assigned}"
echo "${FORM_NESTED_OUTER:-${FORM_NESTED_INNER:-deep}}"
