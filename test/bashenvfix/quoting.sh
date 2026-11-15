#!/usr/bin/env bash
# quoting.sh — what is CODE in Bash: the NOPE_* names must never become gates, the QUOTE_* names must.
set -euo pipefail

echo '$NOPE_SINGLE_QUOTED' "it's $QUOTE_DOUBLE_WITH_APOSTROPHE"   # $NOPE_COMMENT
echo "\$NOPE_ESCAPED $# ${#} $1 ${1:-x}"
jq -n '
  $NOPE_MULTILINE_SINGLE
'
echo "$(printf '%s' "$QUOTE_IN_SUBSTITUTION")"
cat <<EOF
body $QUOTE_HEREDOC_UNQUOTED
EOF
cat <<'EOF'
body $NOPE_HEREDOC_QUOTED
EOF
cat << "SPACED"
body $NOPE_HEREDOC_SPACED_QUOTED
SPACED
echo $'ansi \' $NOPE_ANSI_C' "$QUOTE_AFTER_ANSI_C"
