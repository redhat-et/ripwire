#!/usr/bin/env bash
# rereview.sh — inputs from the #641 re-review (CodeRabbit on 902f363df). Each one used to hide a caller requirement.
# 1. REPLY / OPTARG / MAPFILE: set only by the command that sets them, so a read before it is the caller's.
: "${REPLY:?}"
read -r -p "name? "
echo "$REPLY"
while getopts "a:" opt; do echo "$OPTARG $opt"; done
mapfile < /dev/null
echo "${MAPFILE[@]}"
# 2. an expansion inside an array subscript.
: "${RR_VALUES[${RR_INDEX:?}]}"
# 3. a write inside $( … ) or ( … ) is the subshell's own: it ends at the `)`.
unused=$(RR_SUB=internal; echo "$RR_SUB")
: "${RR_SUB:?} $unused"
( RR_PAREN=internal )
: "${RR_PAREN:?}"
# 4. a value that spans lines: the assignment takes effect where its command ends.
RR_MULTI='prefix
'${RR_MULTI:?}
RR_SPAN='a
b'
echo "$RR_SPAN"
# 5. heredoc terminators: exact, `<<-` strips tabs only, and `<<''` closes at an empty line.
cat <<'EOF'
 EOF
RR_HD_SPACE=internal
EOF
: "${RR_HD_SPACE:?}"
cat <<-EOF
	$RR_HD_TAB_BODY
	EOF
: "${RR_AFTER_TAB:?}"
cat <<''
RR_HD_EMPTY=internal

: "${RR_HD_EMPTY:?}"
# 6. a compound assignment's list is part of its command.
RR_LIST=( "$RR_LIST_ITEM" "(" )
echo "${RR_LIST[0]}"
# 7. a case pattern's `)` closes no paren, and `for (( … ))` assigns its counter.
( for rr_n in 1 2; do
    case "$rr_n" in
        1|2) echo "$rr_n" ;;
        *)   echo "$rr_n" ;;
    esac
  done; echo "$rr_n" )
for (( rr_i = 0; rr_i < 2; rr_i++ )); do echo "${RR_ARR[$rr_i]} $rr_i"; done
