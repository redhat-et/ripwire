#!/usr/bin/env bash
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
fail=0
ok(){ printf '  PASS  %s\n' "$*"; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }

TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
R="$TMP/repo"; mkdir -p "$R/src" "$R/plans"
cat > "$R/src/math.cpp" <<'EOF'
int alpha()
{
    return 1;
}

int beta()
{
    return 2;
}
EOF
printf 'int alpha()\n{\n    return 10;\n}' > "$R/plans/alpha.txt"
printf 'int helper() { return 3; }' > "$R/plans/helper.txt"
cat > "$R/plans/good.json" <<'EOF'
{"version":1,"edits":[
  {"op":"replace_symbol_body","target":"alpha","file":"src/math.cpp","payload":"alpha.txt"},
  {"op":"insert_after_symbol","target":"beta","file":"src/math.cpp","payload":"helper.txt"}
]}
EOF

BEFORE="$( shasum "$R/src/math.cpp" | awk '{print $1}' )"
DRY="$( "$BIN" "$R" --edit-plan="$R/plans/good.json" --dry-run 2>/dev/null )"; DRC=$?
AFTER="$( shasum "$R/src/math.cpp" | awk '{print $1}' )"
[ "$DRC" = 0 ] && [ "$BEFORE" = "$AFTER" ] && ok 'dry-run validates two edits without mutating the file' || no 'dry-run mutated or failed'
case "$DRY" in
  *'"schema":"ripwire.edit-plan/v1"'*'"mode":"dry-run"'*'"edits":2'*'"files":1'*) ok 'dry-run receipt is versioned and tallies edits/files' ;;
  *) no "dry-run receipt missing facts: $DRY" ;;
esac
[ "$( "$BIN" "$R" --edit-plan="$R/plans/good.json" --dry-run 2>/dev/null )" = "$DRY" ] \
  && ok 'dry-run receipt is deterministic' || no 'dry-run receipt is nondeterministic'

APPLY="$( "$BIN" "$R" --edit-plan="$R/plans/good.json" --apply 2>/dev/null )"; ARC=$?
[ "$ARC" = 0 ] && grep -q 'return 10' "$R/src/math.cpp" && grep -q 'int helper' "$R/src/math.cpp" \
  && ok 'apply commits both same-file edits' || no 'apply did not commit both edits'
case "$APPLY" in *'"mode":"apply"'*'"applied":2'*'"atomic_files":1'*) ok 'apply receipt discloses applied and per-file atomic counts' ;; *) no "apply receipt wrong: $APPLY" ;; esac

# One bad target makes the whole plan refuse before the valid first edit writes.
cp "$R/src/math.cpp" "$R/src/snapshot.cpp"
cat > "$R/plans/bad.json" <<'EOF'
{"version":1,"edits":[
  {"op":"replace_symbol_body","target":"beta","file":"src/math.cpp","payload":"alpha.txt"},
  {"op":"replace_symbol_body","target":"missing_symbol","file":"src/math.cpp","payload":"alpha.txt"}
]}
EOF
BAD_BEFORE="$( shasum "$R/src/math.cpp" | awk '{print $1}' )"
"$BIN" "$R" --edit-plan="$R/plans/bad.json" --apply >/dev/null 2>"$TMP/bad.err"; BRC=$?
BAD_AFTER="$( shasum "$R/src/math.cpp" | awk '{print $1}' )"
[ "$BRC" = 1 ] && [ "$BAD_BEFORE" = "$BAD_AFTER" ] && grep -q 'missing_symbol' "$TMP/bad.err" \
  && ok 'a bad later target refuses the whole plan before any write' || no 'bad plan partially wrote or hid its cause'

cat > "$R/plans/overlap.json" <<'EOF'
{"version":1,"edits":[
  {"op":"replace_symbol_body","target":"beta","file":"src/math.cpp","payload":"alpha.txt"},
  {"op":"replace_symbol_body","target":"beta","file":"src/math.cpp","payload":"alpha.txt"}
]}
EOF
OV_BEFORE="$( shasum "$R/src/math.cpp" | awk '{print $1}' )"
"$BIN" "$R" --edit-plan="$R/plans/overlap.json" --apply >/dev/null 2>"$TMP/overlap.err"; ORC=$?
[ "$ORC" = 1 ] && [ "$OV_BEFORE" = "$( shasum "$R/src/math.cpp" | awk '{print $1}' )" ] && grep -qi 'overlap' "$TMP/overlap.err" \
  && ok 'overlapping edits refuse byte-identically' || no 'overlap was accepted or mutated bytes'

MALFORMED_BEFORE="$( shasum "$R/src/math.cpp" | awk '{print $1}' )"
for PLAN in trailing-comma missing-comma; do
  case "$PLAN" in
    trailing-comma) SEP=',' ;;
    missing-comma) SEP=' ' ;;
  esac
  printf '{"version":1,"edits":[{"op":"replace_symbol_body","target":"beta","payload":"alpha.txt"}%s]}\n' "$SEP" > "$R/plans/$PLAN.json"
  "$BIN" "$R" --edit-plan="$R/plans/$PLAN.json" --dry-run >/dev/null 2>"$TMP/$PLAN.err"; PRC=$?
  [ "$PRC" = 1 ] && [ "$MALFORMED_BEFORE" = "$( shasum "$R/src/math.cpp" | awk '{print $1}' )" ] \
    && ok "$PLAN JSON refuses without mutation" || no "$PLAN JSON was accepted or mutated bytes"
done

"$BIN" "$R" --edit-plan="$R/plans/good.json" >/dev/null 2>"$TMP/mode.err"; MRC=$?
[ "$MRC" = 1 ] && grep -q 'dry-run.*apply' "$TMP/mode.err" && ok 'a plan requires an explicit mode' || no 'missing mode did not refuse clearly'
"$BIN" "$R" --edit-plan="$R/plans/good.json" --dry-run --apply >/dev/null 2>&1; XRC=$?
[ "$XRC" = 1 ] && ok 'dry-run and apply together refuse' || no 'conflicting modes were accepted'

M="$TMP/multi"; mkdir -p "$M/src" "$M/plans"
printf 'int left() { return 1; }\n' > "$M/src/left.cpp"
printf 'int right() { return 2; }\n' > "$M/src/right.cpp"
printf 'int left() { return 11; }' > "$M/plans/left.txt"
printf 'int right() { return 22; }' > "$M/plans/right.txt"
cat > "$M/plans/multi.json" <<'EOF'
{"version":1,"edits":[
  {"op":"replace_symbol_body","target":"left","payload":"left.txt"},
  {"op":"replace_symbol_body","target":"right","payload":"right.txt"}
]}
EOF
MULTI="$( "$BIN" "$M" --edit-plan="$M/plans/multi.json" --apply 2>/dev/null )"; MURC=$?
[ "$MURC" = 0 ] && grep -q 'return 11' "$M/src/left.cpp" && grep -q 'return 22' "$M/src/right.cpp" \
  && ok 'multi-file apply commits every preflighted file' || no 'multi-file apply was partial'
case "$MULTI" in
  *'"files":2'*'"atomic_files":2'*'"atomic_scope":"per-file"'*'"multifile_crash_atomic":false'*)
    ok 'multi-file receipt states the per-file atomicity boundary' ;;
  *) no "multi-file honesty fields missing: $MULTI" ;;
esac

[ "$fail" = 0 ] && echo 'ALL PASS' || echo 'FAILURES ABOVE'
exit "$fail"
