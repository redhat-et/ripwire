#!/usr/bin/env bash
# writes.sh — a name the script assigns BEFORE it reads it is the script's own state, not an env read.
set -euo pipefail

WRITE_PLAIN=1
echo "$WRITE_PLAIN"
export WRITE_EXPORTED=on
echo "$WRITE_EXPORTED"
readonly WRITE_READONLY=yes
declare -r WRITE_DECLARED=x
echo "$WRITE_READONLY $WRITE_DECLARED"
read -r -p "name? " WRITE_READ_NAME
echo "$WRITE_READ_NAME"
for WRITE_LOOP in a b; do echo "$WRITE_LOOP"; done
mapfile -t WRITE_MAPFILE < /dev/null
echo "${WRITE_MAPFILE[@]}"
printf -v WRITE_PRINTF '%s' x
echo "$WRITE_PRINTF"
WRITE_SAMELINE=2; echo "$WRITE_SAMELINE"
greet() {
    local WRITE_LOCAL="$1"
    echo "$WRITE_LOCAL"
}

# Still env reads: the read happens BEFORE the write.
KEEP_SELF_DEFAULT="${KEEP_SELF_DEFAULT:-fallback}"
echo "$KEEP_READ_FIRST"
KEEP_READ_FIRST=late
# `export NAME` with no `=` publishes the inherited value: it writes nothing.
export KEEP_BARE_EXPORT
echo "$KEEP_BARE_EXPORT"
# Set by lib/shared.lib.sh, which this file sources: the read stays (one file, lexical order), and the gate lists
# the library's write so a consumer that follows `source` can join them.
source "$(dirname "$0")/lib/shared.lib.sh"
echo "$LIB_SET_ME"
greet "$KEEP_SELF_DEFAULT"
# A write that reads its own name passes the caller's value through (the set -u normaliser): it shadows nothing.
PASS_NORMALISED="${PASS_NORMALISED:-}"
echo "${PASS_NORMALISED:-later-default}"
: "${PASS_ASSIGNED:=first}"
echo "${PASS_ASSIGNED:-second}"
