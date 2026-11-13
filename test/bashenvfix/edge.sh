#!/usr/bin/env bash
# edge.sh — inputs from the #641 review. Each one used to hide a required read or mislabel a plain one.
set -euo pipefail

# 1. -n / -z are a set test only as an operand of [ / [[ / test.
echo -n "$EDGE_ECHO_FLAG"
kubectl -n "$EDGE_NAMESPACE" get pods
[[ -n "$EDGE_DBL_A" && -z "${EDGE_DBL_B:-}" ]]
[ -n "$EDGE_SGL" ] && echo -z "$EDGE_AFTER_TEST"
# 2. heredoc delimiters Bash accepts that are not one identifier, two heredocs on one line, and shifts.
cat <<'END-OF-HELP'
$EDGE_NOPE_HYPHEN_BODY
END-OF-HELP
echo "${EDGE_AFTER_HYPHEN:?}"
cat <<'!'
$EDGE_NOPE_BANG_BODY
!
echo "${EDGE_AFTER_BANG:?}"
cat <<"E"OF
$EDGE_NOPE_SPLIT_BODY
EOF
echo "${EDGE_AFTER_SPLIT:?}"
cat <<A <<'B'
$EDGE_HEREDOC_FIRST
A
$EDGE_NOPE_HEREDOC_SECOND
B
echo "${EDGE_AFTER_TWO:?}"
echo $(( 1 << EDGE_SHIFT ))
(( mask = 1 << 3 ))
echo "${EDGE_AFTER_SHIFT:?}"
# 3. a brace or quote inside a nested substitution or quote does not close the expansion.
x=${EDGE_OUTER:-$(awk '{print $1}' f)}
echo "${EDGE_AFTER_AWK:?}"
echo '$EDGE_NOPE_AFTER_AWK'
y="${EDGE_DQ_OUTER:-"a}b"}"
# 4. writes that leave the caller's value in place: a prefix assignment, an arithmetic test, declare -p / -x,
#    a read redirect target, an array element.
EDGE_PREFIX=1 ./child.sh
echo "${EDGE_PREFIX:?}"
((EDGE_ARITH==1)) || true
echo "${EDGE_ARITH:?}"
declare -p EDGE_DECLARE_P >/dev/null
echo "${EDGE_DECLARE_P:?}"
declare -x EDGE_DECLARE_X
echo "${EDGE_DECLARE_X:?}"
read -r edge_line < EDGE_VERSION
echo "${EDGE_VERSION:?} $edge_line"
EDGE_ELEMENT[1]=x
echo "${EDGE_ELEMENT:?}"
declare EDGE_TOP_BARE
echo "${EDGE_TOP_BARE:?}"
EDGE_TWO_A=1 EDGE_TWO_B=2
echo "$EDGE_TWO_A $EDGE_TWO_B"
# 5. a function's local / declare reaches the end of that function only.
helper() {
    local EDGE_LOCAL="$1"
    echo "$EDGE_LOCAL"
}
echo "${EDGE_LOCAL:?}"
function other {
    declare EDGE_FN_DECLARE=1
    declare -g EDGE_FN_GLOBAL=1
    echo "$EDGE_FN_DECLARE"
}
echo "${EDGE_FN_DECLARE:?}"
echo "${EDGE_FN_GLOBAL:-x}"
one() { local EDGE_ONE_LINE=1; echo "$EDGE_ONE_LINE"; }
echo "${EDGE_ONE_LINE:?}"
echo "${EDGE_ELEMENT[1]}"
EDGE_CONTINUED="$( date )" \
    && echo "$EDGE_CONTINUED"
