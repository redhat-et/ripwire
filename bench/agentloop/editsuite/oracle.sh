#!/usr/bin/env bash
# oracle.sh TASK_ID REPO_DIR — the deterministic gate for one editsuite task.
# exit 0 = every touched file is byte-identical to expected/TASK_ID/<file>
# exit 2 = equal after collapsing runs of blank lines and trailing whitespace ("ws-only": the edit landed,
#          the blank-line layout did not) — reported separately, never counted as a pass
# exit 1 = the edit did not land
set -u
HERE="$( cd "$( dirname "$0" )" && pwd )"
TASK="${1:?task id}"; REPO="${2:?repo dir}"
EXP="$HERE/expected/$TASK"
[ -d "$EXP" ] || { echo "oracle: no expected tree for task $TASK"; exit 1; }
rc=0
while IFS= read -r f; do
    rel="${f#"$EXP"/}"
    if cmp -s "$f" "$REPO/$rel"; then
        continue
    fi
    if [ -f "$REPO/$rel" ] && python3 - "$f" "$REPO/$rel" <<'PY'
import re, sys
def norm( p ):
    t = open( p ).read()
    t = re.sub( r"[ \t]+\n", "\n", t )
    return re.sub( r"\n{2,}", "\n\n", t ).strip( "\n" )
sys.exit( 0 if norm( sys.argv[1] ) == norm( sys.argv[2] ) else 1 )
PY
    then
        echo "oracle: $rel differs only in blank lines / trailing whitespace"
        [ "$rc" = 0 ] && rc=2
    else
        echo "oracle: $rel does not match expected bytes"
        rc=1
    fi
done < <( find "$EXP" -type f | LC_ALL=C sort )
exit "$rc"
