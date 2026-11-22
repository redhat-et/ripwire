#!/usr/bin/env bash
# shellnestcheck.sh — CR712-SHSTATUS-DEPTH: the shell parser's ONE nesting budget (src/shstatus.h kMaxShellNest), shared by the
# lexer's quote / $( ) / ${ } skips and the parser's compound commands and substitutions, cuts a deeply nested script instead
# of exhausting the stack, and --quality-delta says so (shell_cut= on the root, XML and --json).
#
# The scripts are GENERATED here, never committed (PRODUCER_COMMON 12: a committed fixture that trips a cap would put a
# disclosure into every whole-repo run). Each is a new test script under test/ in a one-commit repo, so the defect-shape
# scan (vacuous-assert and unhandled-arm, both through shstatus::parse) reads it.
#   (p1)-(p5) DEEP: 5,000 levels of one shape each — nested subshells, brace groups, if-then, "$( … "$( … )" … )" quotes and
#        bare $( ) substitutions: the run exits 0 or 2 (no signal), within 60 s, and the root carries shell_cut="1".
#        Red before the lane (main 8861b0d4d): subshell, group and if die on SIGSEGV (rc 139); quote and subst exit 0 with no
#        disclosure (the old 40-level substitution cap cut them silently). At 20,000 levels ingest itself takes 60-70 s
#        (tree-sitter on the file, outside this card), so the gate stays at 5,000.
#   (j)  --json on the subshell script: "shell_cut":1.
#   (n1) UNDER THE BUDGET: a function ending in a case with no *) arm (unhandled-arm), 40 subshells deep: the unhandled-arm row is still found
#        and there is no shell_cut= (the budget cut nothing real). Red on a build with a budget under 40.
#   (n2) SHALLOW: the same file at depth 1: no shell_cut= (premise for n1: the row exists without nesting too).
#   (v)  CUT TREE: an absence assertion whose guard lies past the cut is not judged vacuous (premise v0: the facet is live).
#   (f)  FOLD: the subshell script committed with one stale ack: the identity-tree verdict fold keeps shell_cut="1".
# Usage: test/shellnestcheck.sh [BIN]
set -u
ROOT="$( cd "$( dirname "$0" )/.." && pwd )"
. "$ROOT/test/lib/clean-env.sh"
BIN="${1:-${RIPWIRE_BIN:-$ROOT/build/ripwire}}"
[ "${BIN#/}" = "$BIN" ] && BIN="$ROOT/$BIN"
[ -x "$BIN" ] || { echo "no ripwire binary at $BIN — build first"; exit 2; }
TMP="$( mktemp -d )"; trap 'rm -rf "$TMP"' EXIT
export TMPDIR="$TMP/cache"; mkdir -p "$TMPDIR"
export HOME="$TMP/home"; mkdir -p "$HOME"
fail=0
ok(){ printf '  PASS  %s\n' "$*" || { fail=1; printf '  FAIL  could not write the PASS line for: %s\n' "$*"; }; return 0; }
no(){ printf '  FAIL  %s\n' "$*"; fail=1; }
echo "shellnestcheck: BIN=$BIN"
G=( git -c user.name=t -c user.email=t@t -c commit.gpgsign=false )
# cap60 CMD...: the 60 s deadline is ENFORCED, not just measured after the fact (CR721): SIGALRM kills a hung scan (rc 142), which
# every arm below reads as a failure, so regression.sh never stalls on this gate.
cap60(){ perl -e 'alarm 60; exec @ARGV or exit 127' "$@"; }

# gen KIND N OUT — one script nested N levels in one shape (python: no shell recursion of our own)
gen(){ python3 - "$1" "$2" "$3" <<'PY'
import sys
kind, n, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
case = 'kindof() { case "$1" in a) echo x ;; b) echo y ;; esac; }; kindof a'
body = {
    "subshell": "( " * n + "false" + " )" * n,
    "group": "{ " * n + "false; " + "}; " * n,
    "if": "if true; then " * n + "false" + "; fi" * n,
    "quote": 'x="' + '$( echo "' * n + "y" + '" )' * n + '"',
    "subst": "x=" + "$( echo " * n + "y" + " )" * n,
    "case": "( " * n + case + " )" * n,
}[kind]
with open(out, "w") as f:
    f.write("#!/usr/bin/env bash\nset -u\n" + body + "\n")
PY
}
# repo KIND N — a one-commit repo whose working tree adds test/deep_check.sh; prints its path
repo(){ local R="$TMP/r-$1-$2"; mkdir -p "$R/test"; "${G[@]}" -C "$R" init -q; echo 'echo hi' >"$R/test/a.sh"
    "${G[@]}" -C "$R" add -A && "${G[@]}" -C "$R" commit -qm a; gen "$1" "$2" "$R/test/deep_check.sh"; printf '%s' "$R"; }
cutof(){ grep -oE '<quality-delta [^>]*' "$1" | grep -oE ' shell_cut="[0-9]+"' | grep -oE '[0-9]+'; }

for k in subshell group if quote subst; do
    R="$( repo "$k" 5000 )"; s=$( date +%s )
    cap60 "$BIN" "$R" --quality-delta --no-cache >"$TMP/$k.xml" 2>"$TMP/$k.err"; rc=$?; t=$(( $( date +%s ) - s ))
    c="$( cutof "$TMP/$k.xml" )"
    if { [ "$rc" = 0 ] || [ "$rc" = 2 ]; } && [ "$t" -le 60 ] && [ "${c:-0}" = 1 ]; then ok "($k) 5000 deep: rc=$rc in ${t}s, shell_cut=\"$c\""
    else no "($k) 5000 deep: want rc 0/2 within 60 s and shell_cut=\"1\"; got rc=$rc in ${t}s, shell_cut='${c:-none}' ($( tail -c 160 "$TMP/$k.err" | tr '\n' ' ' ))"; fi
done
R="$TMP/r-subshell-5000"
cap60 "$BIN" "$R" --quality-delta --json --no-cache >"$TMP/j.json" 2>/dev/null; jrc=$?
j="$( python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("shell_cut","absent"))' "$TMP/j.json" 2>/dev/null || echo unparseable )"
if { [ "$jrc" = 0 ] || [ "$jrc" = 2 ]; } && [ "$j" = 1 ]; then ok "(j) --json: \"shell_cut\":1"; else no "(j) --json: want rc 0/2 and \"shell_cut\":1, got rc=$jrc '$j'"; fi

for n in 40 1; do
    R="$( repo case "$n" )"
    cap60 "$BIN" "$R" --quality-delta --no-cache >"$TMP/case$n.xml" 2>/dev/null; crc=$?
    case "$crc" in 0|2) ;; *) no "(case $n) --quality-delta exited $crc";; esac
    row="$( grep -oE '<r kind="defect-shape"[^>]*defect="unhandled-arm"[^>]*>' "$TMP/case$n.xml" | grep 'deep_check.sh' | head -1 )"
    c="$( cutof "$TMP/case$n.xml" )"
    label=n1; [ "$n" = 1 ] && label=n2
    if [ -n "$row" ] && [ -z "$c" ]; then ok "($label) case $n deep: the unhandled-arm row is found, no shell_cut=: $row"
    else no "($label) case $n deep: want an unhandled-arm row in deep_check.sh and no shell_cut=; got row='${row:-none}' shell_cut='${c:-none}'"; fi
done

# (f) CR721 FOLD: the deep script COMMITTED (tree = HEAD, head_basis="identity") plus one stale ack: the verdict-only fold
#     (the root line alone) must still carry shell_cut="1" — it is a disclosure, so the fold must not win. --show-stale is the
#     premise (the unfolded root has it). RED before CR721 (train GE3 cbed31d4c): the folded root had no shell_cut=.
R="$TMP/r-fold"; mkdir -p "$R/test"; "${G[@]}" -C "$R" init -q; echo 'echo hi' >"$R/test/a.sh"; gen subshell 5000 "$R/test/deep_check.sh"
printf '# ripwire quality acks v1\nack complexity 0123456789abcdef 5 a target long gone\n' >"$R/.ripwire_quality_acks"
"${G[@]}" -C "$R" add -A && "${G[@]}" -C "$R" commit -qm a
cap60 "$BIN" "$R" --quality-delta --no-cache --show-stale >"$TMP/fold-full.xml" 2>/dev/null
cap60 "$BIN" "$R" --quality-delta --no-cache >"$TMP/fold.xml" 2>/dev/null; frc=$?
full="$( grep -oE '<quality-delta [^>]*' "$TMP/fold-full.xml" )"; root="$( grep -oE '<quality-delta [^>]*' "$TMP/fold.xml" )"
if printf '%s' "$full" | grep -q 'head_basis="identity"' && printf '%s' "$full" | grep -q 'stale="1"' && [ "$( cutof "$TMP/fold-full.xml" )" = 1 ]; then
    ok "(f) premise: identity tree, one stale ack, --show-stale root has shell_cut=\"1\""
else no "(f) premise: want head_basis=identity, stale=1 and shell_cut=1 under --show-stale; got: $full"; fi
if [ "$frc" = 0 ] && [ "$( cutof "$TMP/fold.xml" )" = 1 ]; then ok "(f) the default (folded) answer keeps shell_cut=\"1\""
else no "(f) the default answer dropped shell_cut= (rc=$frc): $root"; fi

# (v) CR721 CUT TREE NOT JUDGED: an absence assertion, a 5,000-deep group, then the presence guard that protects it. The parse
#     stops inside the group, so the guard is invisible; the vacuous-assert facet must not judge the prefix (shell_cut="1" says
#     the file was cut). Premise (v0): the same assertion with NO guard and no nesting rows vacuous-assert (the facet is live).
#     RED before CR721 (train GE3 cbed31d4c): a vacuous-assert row at test/deep_check.sh:4.
vgen(){ python3 - "$1" "$2" "$3" <<'PY'
import sys
n, guard, out = int(sys.argv[1]), sys.argv[2] == "guard", sys.argv[3]
s = '#!/usr/bin/env bash\nset -u\nOUT="$( ./tool --run )"\n'
s += "printf '%s' \"$OUT\" | grep -q 'bad' && echo \"FAIL bad\" || echo \"PASS no bad\"\n"
if n: s += "( " * n + "false" + " )" * n + "\n"
if guard: s += "printf '%s' \"$OUT\" | grep -q 'good' && echo \"PASS good\" || echo \"FAIL no good\"\n"
open(out, "w").write(s)
PY
}
vrepo(){ local R="$TMP/v-$1"; mkdir -p "$R/test"; "${G[@]}" -C "$R" init -q; echo 'echo hi' >"$R/test/a.sh"
    "${G[@]}" -C "$R" add -A && "${G[@]}" -C "$R" commit -qm a; vgen "$2" "$3" "$R/test/deep_check.sh"; printf '%s' "$R"; }
vac(){ grep -oE '<r kind="defect-shape"[^>]*defect="vacuous-assert"[^>]*' "$1" | grep 'deep_check.sh'; }
R="$( vrepo v0 0 noguard )"; cap60 "$BIN" "$R" --quality-delta --no-cache >"$TMP/v0.xml" 2>/dev/null
if [ -n "$( vac "$TMP/v0.xml" )" ]; then ok "(v0) premise: the unguarded absence assertion rows vacuous-assert"; else no "(v0) premise: no vacuous-assert row on the unguarded script"; fi
R="$( vrepo v 5000 guard )"; cap60 "$BIN" "$R" --quality-delta --no-cache >"$TMP/v.xml" 2>/dev/null; vrc=$?
vr="$( vac "$TMP/v.xml" )"; c="$( cutof "$TMP/v.xml" )"
if { [ "$vrc" = 0 ] || [ "$vrc" = 2 ]; } && [ -z "$vr" ] && [ "${c:-0}" = 1 ]; then ok "(v) cut tree: no vacuous-assert row, shell_cut=\"1\""
else no "(v) cut tree: want no vacuous-assert row and shell_cut=\"1\"; got rc=$vrc row='${vr:-none}' shell_cut='${c:-none}'"; fi

[ "$fail" = 0 ] && echo "shellnestcheck: PASS" || echo "shellnestcheck: FAIL"
exit "$fail"
